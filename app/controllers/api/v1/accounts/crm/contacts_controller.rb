class Api::V1::Accounts::Crm::ContactsController < Api::V1::Accounts::BaseController
  before_action :pipeline
  before_action :crm_contact, only: [:update, :destroy, :history]

  # scope=recent (padrão): só cards "ativos no último mês" — lead novo OU
  # card criado/movido nos últimos 30 dias. Deixa o board leve (mobile!).
  # scope=all: tudo desde o início, sob demanda.
  def index
    base = @pipeline.crm_contacts
    total = base.count

    scoped = if params[:scope] == 'all'
               base
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
        scope: params[:scope] == 'all' ? 'all' : 'recent'
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
    render json: contact_json(@crm_contact), status: :created
  end

  def update
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

  private

  def pipeline
    @pipeline ||= Current.account.crm_pipelines.find(params[:pipeline_id])
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

    # última conversa por contato (+ inbox)
    @last_conv_by_contact = {}
    Conversation.where(contact_id: contact_ids)
                .includes(:inbox)
                .order(last_activity_at: :desc)
                .each { |cv| @last_conv_by_contact[cv.contact_id] ||= cv }

    # total de conversas por contato
    @conv_count_by_contact = Conversation.where(contact_id: contact_ids).group(:contact_id).count

    # última mensagem (não-atividade) da última conversa de cada contato
    conv_ids = @last_conv_by_contact.values.map(&:id)
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
    last_conversation = @last_conv_by_contact&.[](contact.id)
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
      last_activity_at: contact.last_activity_at,
      conversations_count: @conv_count_by_contact ? (@conv_count_by_contact[contact.id] || 0) : contact.conversations.count,
      last_conversation_id: last_conversation&.id,
      last_conversation: last_conv_data
    }
  end

  def build_conversation_data(conversation)
    return nil unless conversation

    last_msg = @last_msg_by_conv ? @last_msg_by_conv[conversation.id] : nil
    awaiting_reply = last_msg&.incoming? || false

    {
      id: conversation.id,
      status: conversation.status,
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
