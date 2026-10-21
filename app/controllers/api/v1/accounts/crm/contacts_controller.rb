class Api::V1::Accounts::Crm::ContactsController < Api::V1::Accounts::BaseController
  before_action :pipeline
  before_action :crm_contact, only: [:update, :destroy, :history, :trigger_label_change, :detect_value, :start_conversation]
  # 🔒 Rodada 2 da auditoria (#0, #300): remover card e varrer valores em lote
  # é "tratamento de dados" (admin ou quem tem esse nó); detectar o valor de um
  # card grava R$ no card, então pede o Financeiro (admin ou concessão).
  before_action -> { require_capability(:data_tools) }, only: [:destroy, :detect_values_bulk]
  before_action -> { require_capability(:finance) }, only: [:detect_value]

  # scope=preview: os N cards mais recentes de CADA coluna (carga inicial
  #   instantânea — o board completa em background com a janela de trabalho).
  # scope=period&date_from&date_to&date_mode: período por CALENDÁRIO no
  #   servidor — contagem VERDADEIRA por coluna + entrega limitada por coluna
  #   (o board pagina dentro de cada coluna com scope=stage_page).
  #   date_mode=activity (padrão): leads com atividade no período.
  #   date_mode=created: leads que CHEGARAM no período (data real do contato).
  #   date_mode=moved: leads que ENTRARAM na coluna atual no período
  #     (stage_moved_at — "Consulta Confirmada em julho" = confirmou em julho).
  # scope=stage_page&stage_id&offset&limit: próxima página de UMA coluna,
  #   mesmo período/ordenação do scope=period.
  # scope=days&days=N: leads com atividade nos últimos N dias (legado).
  # scope=all(&q=texto): tudo desde o início (sob demanda: busca ou "Carregar
  #   todos"). 🫁 Rodada 7 (#323): NÃO entrega mais o funil inteiro de uma vez
  #   (com 30 mil cards isso derrubava o servidor). Funciona igual ao
  #   scope=period, só que sem datas: contagem VERDADEIRA por coluna + até 200
  #   cards por coluna; o resto vem pelo "Carregar mais" de cada coluna
  #   (scope=stage_page&range=all). O q= filtra no servidor (nome, telefone,
  #   anotação, etiqueta) para a busca achar o paciente na base toda.
  # scope=recent (legado): ativos nos últimos 30 dias.
  # (days e recent também param em 200 cards por coluna — ver index)
  PREVIEW_PER_STAGE = 15
  PERIOD_PER_STAGE = 50
  ALL_PER_STAGE = 200
  BOARD_TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  def index
    return render_period if %w[period all].include?(params[:scope])
    return render_stage_page if params[:scope] == 'stage_page'

    base = @pipeline.crm_contacts
    total = base.count

    scoped = case params[:scope]
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

    # 🫁 Rodada 7 (#323, revisão): os caminhos antigos (days=365 e recent)
    # também têm teto por coluna — ninguém traz o funil inteiro de uma vez
    # por eles (depois de uma carga em massa o "recent" pegava quase tudo)
    scoped = base.where(id: ranked_ids(scoped, ALL_PER_STAGE)) unless params[:scope] == 'preview'

    crm_contacts = scoped.includes(:stage, :assignee, contact: { avatar_attachment: :blob }).to_a
    preload_card_data(crm_contacts)

    render json: {
      payload: crm_contacts.map { |c| contact_json(c) },
      meta: {
        total: total,
        shown: crm_contacts.size,
        # leads do funil que têm pelo menos uma conversa (o total inclui
        # contatos migrados/cadastrados que nunca conversaram)
        with_conversations: with_conversations_count,
        scope: %w[preview days].include?(params[:scope]) ? params[:scope] : 'recent'
      }
    }
  end

  def create
    contact = Current.account.contacts.find(params[:contact_id])
    stage = @pipeline.stages.find(params[:stage_id])
    @crm_contact = with_environment_choice do
      @pipeline.crm_contacts.create!(
        contact: contact,
        stage: stage,
        assignee_id: params[:assignee_id],
        value: finance_edit? ? params[:value] : nil, # 💰 R2 (#287): valor só com Financeiro
        origin: params[:origin],
        procedure_of_interest: params[:procedure_of_interest],
        notes: params[:notes]
      )
    end
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

  # DELETE — "Remover do funil". 🔒 R2 (#300): só tratamento de dados/admin
  # (before_action); fica registrado quem removeu e o histórico de colunas
  # (stage_logs) é preservado para os indicadores — ver Crm::Contact#remove_from_pipeline!
  def destroy
    @crm_contact.remove_from_pipeline!(by: Current.user)
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
  # 🏷️ Rodada 5 (#17): NÃO dispara mais nada. O disparo de verdade sai do
  # servidor quando a etiqueta do contato muda no banco
  # (Contact#cevico_fire_label_triggers) — e as telas do CRM gravam a etiqueta
  # por /contacts/:id/labels, que já passa por lá. Antes este endpoint confiava
  # no "antes×depois" que o navegador mandava, e o navegador pode ter uma foto
  # velha das etiquetas: marcar de novo uma etiqueta que a IA já tinha posto
  # disparava a automação (e a conversão Meta/Google) uma segunda vez.
  # Fica respondendo 200 só para telas abertas com a versão antiga.
  def trigger_label_change
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
  # 🔒 R2 (#0): sobrescrever valor já preenchido (only_empty=false) só o admin;
  # para os demais a varredura só preenche cards sem valor.
  def detect_values_bulk
    only_empty = params[:only_empty].to_s != 'false' || !Current.account_user&.administrator?
    Crm::BulkDetectValuesJob.perform_later(@pipeline.id, only_empty)
    render json: { enqueued: true, only_empty: only_empty }
  end

  private

  def pipeline
    @pipeline ||= Current.account.crm_pipelines.find(params[:pipeline_id])
  end

  # ── Período por calendário (a régua Hoje/Ontem/7 dias/Mês/Ano/Personalizado) ──

  def period_range
    from = begin
      BOARD_TZ.parse(params[:date_from].to_s)&.beginning_of_day
    rescue ArgumentError
      nil
    end
    to = begin
      BOARD_TZ.parse(params[:date_to].to_s)&.end_of_day
    rescue ArgumentError
      nil
    end
    from ||= 30.days.ago
    to ||= Time.current
    to = from if to < from
    [from, to]
  end

  def period_scope(base)
    from, to = period_range
    case params[:date_mode]
    when 'created'
      # data REAL de chegada do lead (contacts.created_at — corrigida pela
      # rake de importação para a data da primeira conversa)
      base.joins(:contact).where(contacts: { created_at: from..to })
    when 'moved'
      # MOVIMENTAÇÃO: quando o card ENTROU na coluna em que está hoje —
      # "Consulta Confirmada em julho" = confirmou EM julho, não importa
      # quando o lead chegou. Card antigo sem carimbo cai na criação.
      base.joins(:contact).where(
        'COALESCE(crm_contacts.stage_moved_at, crm_contacts.created_at) BETWEEN :from AND :to',
        from: from, to: to
      )
    else
      # atividade: mensagem, card criado ou card movido dentro do período
      base.joins(:contact).where(
        '(contacts.last_activity_at BETWEEN :from AND :to) ' \
        'OR (crm_contacts.created_at BETWEEN :from AND :to) ' \
        'OR (crm_contacts.stage_moved_at BETWEEN :from AND :to)',
        from: from, to: to
      )
    end
  end

  def per_stage_limit
    (params[:per_stage].presence || default_per_stage).to_i.clamp(10, ALL_PER_STAGE)
  end

  # 🫁 #323: "Carregar todos" (scope=all, ou range=all na próxima página de
  # uma coluna) = a base toda, sem datas, mas sempre em páginas por coluna
  def all_range?
    params[:scope] == 'all' || params[:range] == 'all'
  end

  def default_per_stage
    all_range? ? ALL_PER_STAGE : PERIOD_PER_STAGE
  end

  # recorte do board: período da régua OU a base toda; mais a busca (q)
  def board_scope(base)
    scoped = all_range? ? base.joins(:contact) : period_scope(base)
    search_scope(scoped)
  end

  # Busca no SERVIDOR — os mesmos campos da busca da tela (nome, telefone,
  # anotação do card, etiqueta), para achar o paciente sem baixar o funil todo
  def search_term
    params[:q].to_s.strip.first(80)
  end

  def search_scope(scoped)
    return scoped if search_term.blank?

    like = "%#{ActiveRecord::Base.sanitize_sql_like(search_term)}%"
    scoped.where(
      'contacts.name ILIKE :q OR contacts.phone_number ILIKE :q OR crm_contacts.notes ILIKE :q ' \
      'OR EXISTS (SELECT 1 FROM taggings tg JOIN tags t ON t.id = tg.tag_id ' \
      "WHERE tg.taggable_type = 'Contact' AND tg.context = 'labels' " \
      'AND tg.taggable_id = crm_contacts.contact_id AND t.name ILIKE :q)',
      q: like
    )
  end

  # 🫁 #323: "N com conversa" no topo do board. Antes era um COUNT DISTINCT de
  # cards × conversas do funil inteiro a cada abertura; agora é um EXISTS
  # (sem multiplicar linhas) guardado por 5 minutos por funil.
  def with_conversations_count
    Rails.cache.fetch("cevico:crm:with_conversations:#{@pipeline.id}", expires_in: 5.minutes) do
      # 🧭 item 341: conversa de caixa de outro ambiente não conta
      foreign = Crm::Environments.foreign_inbox_ids(Current.account, @pipeline)
      extra = foreign.any? ? " AND cv.inbox_id NOT IN (#{foreign.map(&:to_i).join(',')})" : ''
      @pipeline.crm_contacts
               .where("EXISTS (SELECT 1 FROM conversations cv WHERE cv.contact_id = crm_contacts.contact_id#{extra})")
               .count
    end
  end

  def render_period
    base = @pipeline.crm_contacts
    scoped = board_scope(base)
    stage_counts = scoped.group(:stage_id).count
    stage_values = scoped.group(:stage_id).sum(:value)

    cards = base.where(id: ranked_ids(scoped, per_stage_limit))
                .includes(:stage, :assignee, contact: { avatar_attachment: :blob }).to_a
    preload_card_data(cards)

    render json: {
      payload: cards.map { |c| contact_json(c) },
      meta: {
        total: base.count,
        matching: stage_counts.values.sum,
        stage_counts: stage_counts,
        # 💰 R2 (#287): soma por coluna é visão do Financeiro
        stage_values: finance_view? ? stage_values.transform_values(&:to_f) : {},
        shown: cards.size,
        per_stage: per_stage_limit,
        with_conversations: with_conversations_count
      }.merge(board_scope_meta)
    }
  end

  def board_scope_meta
    return { scope: 'all', q: search_term } if all_range?

    from, to = period_range
    {
      scope: 'period',
      date_mode: %w[created moved].include?(params[:date_mode]) ? params[:date_mode] : 'activity',
      date_from: from.to_date.iso8601,
      date_to: to.to_date.iso8601
    }
  end

  # Próxima página de UMA coluna — mesma ordenação do ranking do scope=period
  # (última atividade DESC), então offset = quantos cards a coluna já tem.
  # (com range=all, a base toda sem datas — "Carregar mais" do "Carregar todos")
  def render_stage_page
    stage = @pipeline.stages.find(params[:stage_id])
    scoped = board_scope(@pipeline.crm_contacts).where(stage_id: stage.id)
    limit = (params[:limit].presence || default_per_stage).to_i.clamp(10, ALL_PER_STAGE)
    offset = params[:offset].to_i.clamp(0, 1_000_000)

    cards = scoped.order(Arel.sql('contacts.last_activity_at DESC NULLS LAST, crm_contacts.id DESC'))
                  .offset(offset).limit(limit)
                  .includes(:stage, :assignee, contact: { avatar_attachment: :blob }).to_a
    preload_card_data(cards)

    render json: {
      payload: cards.map { |c| contact_json(c) },
      meta: {
        scope: 'stage_page',
        stage_id: stage.id,
        offset: offset,
        limit: limit,
        stage_total: scoped.count
      }
    }
  end

  # IDs dos N cards mais recentes (por última atividade do contato) de cada
  # coluna — window function, uma consulta só.
  def preview_ids(base)
    ranked_ids(base, PREVIEW_PER_STAGE)
  end

  def ranked_ids(base, per_stage)
    ranked = base.joins(:contact).select(
      'crm_contacts.id AS cid, ' \
      'ROW_NUMBER() OVER (PARTITION BY crm_contacts.stage_id ' \
      'ORDER BY contacts.last_activity_at DESC NULLS LAST, crm_contacts.id DESC) AS rn'
    )
    Crm::Contact.from(ranked, :ranked).where('ranked.rn <= ?', per_stage).pluck('ranked.cid')
  end

  def crm_contact
    @crm_contact ||= @pipeline.crm_contacts.find(params[:id])
  end

  # 🏷️ #17: do diff que a tela mandou, só o que confere com o contato agora
  def crm_contact_params
    permitted = %i[stage_id assignee_id origin procedure_of_interest notes]
    permitted << :value if finance_edit? # 💰 R2 (#287): só o Financeiro grava valor
    params.permit(*permitted)
  end

  # 💰 R2 (#287): valor em R$ do card é visão do Financeiro — admin ou quem
  # tem o nó "financeiro" (ver = enxerga; editar = grava). O admin passa
  # direto no Cevico::Access.
  def finance_view?
    return @finance_view if defined?(@finance_view)

    @finance_view = cevico_can?('financeiro', :view)
  end

  def finance_edit?
    return @finance_edit if defined?(@finance_edit)

    @finance_edit = crm_can?(:finance)
  end

  # Carrega em ~6 consultas tudo que a listagem precisa, evitando o N+1 que
  # travava o board com muitos cards (antes eram ~4 queries por card).
  def preload_card_data(cards)
    contact_ids = cards.map(&:contact_id).uniq
    return if contact_ids.empty?

    # 🧭 item 341 (Ambientes do CRM): conversas das caixas de OUTRO ambiente
    # (ex.: caixa 12 Oftalmofácil no funil da CEVICO) não aparecem no balão
    # nem na contagem do card
    @foreign_inbox_ids = @pipeline ? Crm::Environments.foreign_inbox_ids(Current.account, @pipeline) : []

    # caixas de entrada PRINCIPAIS por coluna (settings.main_inbox_ids)
    @main_inboxes_by_stage = Crm::Stage.where(id: cards.map(&:stage_id).uniq)
                                       .pluck(:id, :settings).to_h
                                       .transform_values { |s| Array((s || {})['main_inbox_ids']).map(&:to_i) }

    # 🫁 #323: antes carregava TODAS as conversas de TODOS os contatos como
    # objetos (no "Carregar todos" do funil principal, dezenas de milhares).
    # Agora: só a CONTAGEM por contato e o id da conversa mais recente de cada
    # um (DISTINCT ON); os objetos carregados são só os do balão (1 por card).
    # 🏷️ item 344: o TIPO do atendimento (Consulta, Exame, Cirurgia, Lente,
    # Retorno, Pós-op, Intravítrea) vira etiqueta + filtro no card
    @kind_by_contact = Crm::AppointmentKind.for_contacts(Current.account, contact_ids)

    @conv_count_by_contact = without_foreign_inboxes(Conversation.where(contact_id: contact_ids)).group(:contact_id).count
    @conv_count_by_contact.default = 0
    @last_conv_by_card = balloon_conversations(cards, contact_ids)

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

  # { card.id => conversa do balão }: se a coluna tem caixas principais, a
  # mais recente NESSAS caixas ganha; senão (ou sem conversa nelas), a mais
  # recente de qualquer caixa. Só as conversas escolhidas viram objeto.
  def balloon_conversations(cards, contact_ids)
    latest_any = latest_conversation_ids(contact_ids)
    latest_main = latest_in_main_inboxes(cards)
    chosen_ids = cards.to_h do |card|
      main_ids = @main_inboxes_by_stage[card.stage_id] || []
      [card.id, latest_main.dig(main_ids, card.contact_id) || latest_any[card.contact_id]]
    end
    convs_by_id = Conversation.where(id: chosen_ids.values.compact.uniq).includes(:inbox).index_by(&:id)
    chosen_ids.transform_values { |conv_id| convs_by_id[conv_id] }
  end

  # { [caixas principais] => { contact_id => conversa mais recente nelas } }
  # — uma consulta por grupo de colunas que têm caixas principais
  def latest_in_main_inboxes(cards)
    cards.group_by { |card| @main_inboxes_by_stage[card.stage_id] || [] }
         .reject { |main_ids, _group| main_ids.empty? }
         .to_h { |main_ids, group| [main_ids, latest_conversation_ids(group.map(&:contact_id).uniq, inbox_ids: main_ids)] }
  end

  # { contact_id => id da conversa mais recente } — uma linha por contato,
  # direto do banco (DISTINCT ON), sem montar objetos de conversa
  def latest_conversation_ids(contact_ids, inbox_ids: nil)
    rel = without_foreign_inboxes(Conversation.where(contact_id: contact_ids))
    rel = rel.where(inbox_id: inbox_ids) if inbox_ids
    rel.reorder(Arel.sql('conversations.contact_id, conversations.last_activity_at DESC, conversations.id DESC'))
       .pluck(Arel.sql('DISTINCT ON (conversations.contact_id) conversations.contact_id'), 'conversations.id')
       .to_h
  end

  # 🧭 item 341: tira as conversas das caixas de outro ambiente
  def without_foreign_inboxes(rel)
    @foreign_inbox_ids.present? ? rel.where.not(inbox_id: @foreign_inbox_ids) : rel
  end

  # 🧭 item 341: o card nasce no funil do ambiente do paciente (Crm::CardRouter);
  # o administrador pode forçar o funil escolhido com ignore_environment=true
  def with_environment_choice(&)
    force = Current.account_user&.administrator? && ActiveModel::Type::Boolean.new.cast(params[:ignore_environment])
    force ? Crm::CardRouter.bypass('admin', &) : yield
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
      # 💰 R2 (#287): valor só para quem vê o Financeiro (a tela já escondia;
      # agora o servidor também não manda)
      value: finance_view? ? c.value : nil,
      origin: c.origin,
      procedure_of_interest: c.procedure_of_interest,
      notes: c.notes,
      labels: @labels_by_contact ? @labels_by_contact[contact.id] : contact.label_list,
      # atribuição de anúncio é visão de gestor — agente tem painel simples
      meta_ads: Current.account_user&.administrator? ? contact.additional_attributes&.[]('meta_ads') : nil,
      last_activity_at: contact.last_activity_at,
      conversations_count: @conv_count_by_contact ? (@conv_count_by_contact[contact.id] || 0) : contact.conversations.count,
      last_conversation_id: last_conversation&.id,
      last_conversation: last_conv_data,
      appointment_kind: @kind_by_contact&.[](contact.id)
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
