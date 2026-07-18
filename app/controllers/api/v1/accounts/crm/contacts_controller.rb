class Api::V1::Accounts::Crm::ContactsController < Api::V1::Accounts::BaseController
  before_action :pipeline
  before_action :crm_contact, only: [:update, :destroy, :history, :trigger_label_change, :detect_value, :start_conversation]

  # scope=preview: os N cards mais recentes de CADA coluna (carga inicial
  #   instantânea — o board completa em background com a janela de trabalho).
  # scope=days&days=N: leads com atividade nos últimos N dias (janela de
  #   trabalho — leve para máquinas fracas; padrão do board).
  # scope=all: tudo desde o início (sob demanda: busca ou "Carregar todos").
  # scope=recent (legado): ativos nos últimos 30 dias.
  PREVIEW_PER_STAGE = 15

  def index
    base = @pipeline.crm_contacts
    total = base.count

    scoped = case params[:scope]
             when 'all'
               base
             when 'preview'
               base.where(id: preview_ids(base))
             when 'days'
               cutoff = params[:days].to_i.clamp(1, 365).days.ago
               # última mensagem (contacts.last_activity_at), card mexido ou
               # card criado dentro da janela
               base.joins(:contact).where(
                 'contacts.last_activity_at >= :cutoff OR crm_contacts.updated_at >= :cutoff OR crm_contacts.created_at >= :cutoff',
                 cutoff: cutoff
               )
             else
               cutoff = 30.days.ago
               base.joins(:contact).where(
                 'contacts.created_at >= :cutoff OR crm_contacts.updated_at >= :cutoff',
                 cutoff: cutoff
               )
             end

    crm_contacts = scoped.includes(:stage, :assignee, contact: { avatar_attachment: :blob }).to_a
    preload_card_data(crm_contacts)

    render json: {
      payload: crm_contacts.map { |c| contact_json(c) },
      meta: {
        total: total,
        shown: crm_contacts.size,
        # leads do funil que têm pelo menos uma conversa (o total inclui
        # contatos migrados/cadastrados que nunca conversaram)
        with_conversations: base.joins(contact: :conversations).distinct.count,
        scope: %w[all preview days].include?(params[:scope]) ? params[:scope] : 'recent'
      }
    }
  end

  def create
    contact = Current.account.contacts.find(params[:contact_id])
    stage = @pipeline.stages.find(params[:stage_id])
    @crm_contact = @pipeline.crm_contacts.create!(
      contact: contact,
      stage: stage,
      assignee_id: params[:assignee_id],
      value: params[:value],
      origin: params[:origin],
      procedure_of_interest: params[:procedure_of_interest],
      notes: params[:notes]
    )
    preload_card_data([@crm_contact]) # resposta completa (conversa, etiquetas)
    render json: contact_json(@crm_contact), status: :created
  end

  def update
    # stage_id tem que ser uma coluna DESTE funil (evita mover o card para uma
    # coluna de outro funil/conta passando um id qualquer)
    if params[:stage_id].present? && !@pipeline.stages.exists?(id: params[:stage_id])
      return render json: { error: 'Coluna inválida para este funil.' }, status: :unprocessable_entity
    end

    previous_stage = @crm_contact.stage
    @crm_contact.update!(crm_contact_params)

    # Dispara automações se o card mudou de coluna
    if @crm_contact.saved_change_to_stage_id?
      new_stage = @crm_contact.stage
      CrmAutomationTriggerService.new(
        crm_contact: @crm_contact,
        new_stage: new_stage,
        previous_stage: previous_stage,
        event_type: 'card_entered'
      ).call

      CrmAutomationTriggerService.new(
        crm_contact: @crm_contact,
        new_stage: previous_stage,
        previous_stage: previous_stage,
        event_type: 'card_left'
      ).call
    end

    preload_card_data([@crm_contact]) # resposta completa (conversa, etiquetas)
    render json: contact_json(@crm_contact)
  end

  def destroy
    @crm_contact.destroy!
    head :no_content
  end

  def history
    logs = @crm_contact.stage_logs.order(entered_at: :asc)
    render json: logs.map { |log|
      {
        id: log.id,
        stage_id: log.stage_id,
        stage_name: log.stage_name,
        stage_color: log.stage_color,
        event_type: log.event_type,
        entered_at: log.entered_at,
        left_at: log.left_at,
        duration_minutes: log.duration_minutes
      }
    }
  end

  # POST /crm/pipelines/:pipeline_id/contacts/:id/trigger_label_change
  # Chamado pelo frontend após salvar etiquetas — recebe diff e dispara automações
  def trigger_label_change
    added   = Array(params[:added])
    removed = Array(params[:removed])

    added.each do |label|
      CrmAutomationTriggerService.new(
        crm_contact: @crm_contact,
        new_stage: @crm_contact.stage,
        previous_stage: @crm_contact.stage,
        event_type: 'label_added',
        label: label
      ).call
    end

    removed.each do |label|
      CrmAutomationTriggerService.new(
        crm_contact: @crm_contact,
        new_stage: @crm_contact.stage,
        previous_stage: @crm_contact.stage,
        event_type: 'label_removed',
        label: label
      ).call
    end

    head :ok
  end

  # POST start_conversation — cria a primeira conversa do contato numa caixa
  # escolhida (cards adicionados à mão não têm conversa; o balão precisa dela).
  def start_conversation
    contact = @crm_contact.contact
    inbox = Current.account.inboxes.find(params[:inbox_id])

    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
    if contact_inbox.blank?
      return render json: { error: 'Não foi possível vincular o contato a esta caixa (confira o telefone).' },
                    status: :unprocessable_entity
    end

    Current.account.conversations.create!(
      inbox_id: inbox.id,
      contact_id: contact.id,
      contact_inbox_id: contact_inbox.id
    )

    preload_card_data([@crm_contact])
    render json: contact_json(@crm_contact)
  end

  # POST detect_value — extrai o maior orçamento (R$) das conversas e grava no card
  def detect_value
    value = Crm::BudgetValueExtractor.new(account: Current.account, contact: @crm_contact.contact).max_value
    @crm_contact.update!(value: value) if value
    render json: { value: value, updated: value.present? }
  end

  # POST detect_values_bulk — roda a detecção para todos os cards do pipeline (background)
  def detect_values_bulk
    only_empty = params[:only_empty].to_s != 'false'
    Crm::BulkDetectValuesJob.perform_later(@pipeline.id, only_empty)
    render json: { enqueued: true }
  end

  private

  def pipeline
    @pipeline ||= Current.account.crm_pipelines.find(params[:pipeline_id])
  end

  # IDs dos N cards mais recentes (por última atividade do contato) de cada
  # coluna — window function, uma consulta só.
  def preview_ids(base)
    ranked = base.joins(:contact).select(
      'crm_contacts.id AS cid, ' \
      'ROW_NUMBER() OVER (PARTITION BY crm_contacts.stage_id ' \
      'ORDER BY contacts.last_activity_at DESC NULLS LAST, crm_contacts.id DESC) AS rn'
    )
    Crm::Contact.from(ranked, :ranked).where('ranked.rn <= ?', PREVIEW_PER_STAGE).pluck('ranked.cid')
  end

  def crm_contact
    @crm_contact ||= @pipeline.crm_contacts.find(params[:id])
  end

  def crm_contact_params
    params.permit(:stage_id, :assignee_id, :value, :origin, :procedure_of_interest, :notes)
  end

  # Carrega em ~6 consultas tudo que a listagem precisa, evitando o N+1 que
  # travava o board com muitos cards (antes eram ~4 queries por card).
  def preload_card_data(cards)
    contact_ids = cards.map(&:contact_id).uniq
    return if contact_ids.empty?

    # caixas de entrada PRINCIPAIS por coluna (settings.main_inbox_ids)
    @main_inboxes_by_stage = Crm::Stage.where(id: cards.map(&:stage_id).uniq)
                                       .pluck(:id, :settings).to_h
                                       .transform_values { |s| Array((s || {})['main_inbox_ids']).map(&:to_i) }

    # conversas por contato, mais recente primeiro (+ inbox)
    convs_by_contact = Hash.new { |h, k| h[k] = [] }
    Conversation.where(contact_id: contact_ids)
                .includes(:inbox)
                .order(last_activity_at: :desc)
                .each { |cv| convs_by_contact[cv.contact_id] << cv }

    # total de conversas por contato (da lista já carregada — sem query extra)
    @conv_count_by_contact = convs_by_contact.transform_values(&:size)
    @conv_count_by_contact.default = 0

    # conversa do balão POR CARD: se a coluna tem caixas principais, a mais
    # recente NESSAS caixas ganha; senão (ou sem conversa nelas), a mais recente
    @last_conv_by_card = {}
    cards.each do |card|
      convs = convs_by_contact[card.contact_id]
      main_ids = @main_inboxes_by_stage[card.stage_id] || []
      chosen = main_ids.any? ? convs.find { |cv| main_ids.include?(cv.inbox_id) } : nil
      @last_conv_by_card[card.id] = chosen || convs.first
    end

    # última mensagem (não-atividade) da conversa escolhida de cada card
    conv_ids = @last_conv_by_card.values.compact.map(&:id).uniq
    @last_msg_by_conv = {}
    @unread_by_conv = {}
    if conv_ids.any?
      max_ids = Message.reorder(nil).where(conversation_id: conv_ids).where.not(message_type: 2)
                       .group(:conversation_id).maximum(:id)
      Message.where(id: max_ids.values).each { |m| @last_msg_by_conv[m.conversation_id] = m }

      # mensagens recebidas ainda não vistas pela atendente (uma consulta só)
      @unread_by_conv = Message.reorder(nil)
                               .where(conversation_id: conv_ids, message_type: :incoming)
                               .joins(:conversation)
                               .where("messages.created_at > COALESCE(conversations.agent_last_seen_at, 'epoch')")
                               .group(:conversation_id).count
    end

    # etiquetas por contato (uma consulta só na tabela de taggings)
    @labels_by_contact = Hash.new { |h, k| h[k] = [] }
    ActsAsTaggableOn::Tagging
      .where(taggable_type: 'Contact', taggable_id: contact_ids, context: 'labels')
      .includes(:tag)
      .each { |t| @labels_by_contact[t.taggable_id] << t.tag.name }
  end

  def contact_json(c)
    contact = c.contact
    last_conversation = @last_conv_by_card&.[](c.id)
    last_conv_data = build_conversation_data(last_conversation)

    {
      id: c.id,
      contact_id: contact.id,
      name: contact.name,
      phone_number: contact.phone_number,
      email: contact.email,
      avatar_url: contact.avatar_url,
      contact_created_at: contact.created_at,
      crm_created_at: c.created_at,
      stage_id: c.stage_id,
      pipeline_id: c.pipeline_id,
      assignee: c.assignee ? { id: c.assignee.id, name: c.assignee.name } : nil,
      value: c.value,
      origin: c.origin,
      procedure_of_interest: c.procedure_of_interest,
      notes: c.notes,
      labels: @labels_by_contact ? @labels_by_contact[contact.id] : contact.label_list,
      # atribuição de anúncio é visão de gestor — agente tem painel simples
      meta_ads: Current.account_user&.administrator? ? contact.additional_attributes&.[]('meta_ads') : nil,
      last_activity_at: contact.last_activity_at,
      conversations_count: @conv_count_by_contact ? (@conv_count_by_contact[contact.id] || 0) : contact.conversations.count,
      last_conversation_id: last_conversation&.id,
      last_conversation: last_conv_data
    }
  end

  def build_conversation_data(conversation)
    return nil unless conversation

    last_msg = @last_msg_by_conv ? @last_msg_by_conv[conversation.id] : nil
    # Conversa RESOLVIDA conta como respondida — só fica "aguardando resposta"
    # se a última mensagem é do paciente E a conversa ainda está aberta.
    awaiting_reply = (last_msg&.incoming? && conversation.open?) || false

    {
      id: conversation.id,
      status: conversation.status,
      inbox_id: conversation.inbox_id,
      inbox_name: conversation.inbox&.name,
      channel_type: conversation.inbox&.channel_type,
      last_message: last_msg&.content&.slice(0, 120),
      last_message_at: last_msg&.created_at,
      last_message_type: last_msg&.message_type,
      unread_count: @unread_by_conv ? (@unread_by_conv[conversation.id] || 0) : 0,
      awaiting_reply: awaiting_reply,
      waiting_since: awaiting_reply ? last_msg.created_at : nil
    }
  end
end
