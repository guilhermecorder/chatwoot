class Api::V1::Accounts::Crm::CampaignsController < Api::V1::Accounts::BaseController # rubocop:disable Metrics/ClassLength
  include Crm::AccessControl
  include Crm::ClinicalAccessGate # 💰 R2 da auditoria (#287): money_visible?

  # disparar/criar campanha em massa = área concedível (padrão: só admin).
  # Leitura (index/show/results) e prévias ficam livres p/ acompanhar.
  before_action :campaign, only: [:show, :destroy, :send_now, :schedule, :pause, :results]

  def index
    campaigns = Current.account.crm_campaigns.order(created_at: :desc)
    render json: campaigns.map { |c| campaign_json(c) }
  end

  def show
    render json: campaign_json(@campaign)
  end

  def create
    @campaign = Current.account.crm_campaigns.create!(
      campaign_params.merge(sender: Current.user, status: :draft)
    )
    render json: campaign_json(@campaign), status: :created
  end

  def destroy
    return render_could_not_create_error('Campanha em processamento não pode ser excluída') if @campaign.processing?

    @campaign.destroy!
    head :no_content
  end

  # 🕐 mesmo texto da campanha de ligação: a hora digitada é de São Paulo
  SCHEDULE_ERROR = 'Data de envio inválida ou no passado (use uma data futura, no horário de São Paulo)'.freeze

  def send_now
    # bloqueia a campanha CONCLUÍDA (evita reblast acidental). "Pausada" ou
    # "falhou" pode ser reenviada: o job retoma sem reenviar quem já recebeu.
    return render_could_not_create_error('Campanha já foi concluída') if @campaign.completed?
    # 🚦 R3 da auditoria (#415): o 2º clique numa campanha em envio não
    # re-enfileira o job; quem quiser recomeçar pausa primeiro e envia de novo.
    return render_could_not_create_error('Campanha já está sendo enviada. Para reenviar, pause primeiro.') if @campaign.processing?
    # 🚦 R3 da auditoria (#415): campanha AGENDADA só sai agora se a pessoa
    # disser de propósito que quer ignorar o horário marcado.
    if @campaign.scheduled? && !ignore_schedule?
      return render_could_not_create_error("Campanha agendada para #{scheduled_label(@campaign)}. Confirme que quer ignorar o agendamento.")
    end

    # 🔒 revisão R3: a troca para "em envio" é atômica no banco — dois pedidos
    # ao mesmo tempo (duplo clique, duas pessoas) só passam uma vez.
    return render_could_not_create_error('Campanha já está sendo enviada. Para reenviar, pause primeiro.') unless claim_for_sending

    Crm::CampaignRunJob.perform_later(@campaign.id)
    render json: campaign_json(@campaign.reload)
  end

  # POST schedule — agenda o disparo (scheduled_at obrigatório).
  # 🕐 R3 da auditoria (CONTRATO-0/#411): "2026-10-08T08:00" (sem fuso) é
  # 08:00 de SÃO PAULO — antes era gravado como UTC e a campanha saía 3 h antes.
  def schedule
    return render_could_not_create_error('Campanha já foi enviada') unless @campaign.draft? || @campaign.scheduled? || @campaign.paused?
    return render_could_not_create_error('Informe a data de envio') if params[:scheduled_at].blank?

    when_at = parse_schedule(params[:scheduled_at])
    return render_could_not_create_error(SCHEDULE_ERROR) if when_at == :invalid

    @campaign.update!(status: :scheduled, scheduled_at: when_at)
    render json: campaign_json(@campaign)
  end

  # POST pause — ⏸ R3 da auditoria (#415): para uma campanha em envio (o job
  # vê a mudança e interrompe no próximo contato) ou cancela o agendamento.
  def pause
    return render_could_not_create_error('Só campanhas em envio ou agendadas podem ser pausadas') unless @campaign.processing? || @campaign.scheduled?

    @campaign.update!(status: :paused)
    render json: campaign_json(@campaign)
  end

  # GET results — painel de resultados: destinatários x conversões no CRM
  # 💰 R2 da auditoria (#287): dinheiro (soma e valor de cada convertido) só
  # para quem vê o Financeiro — "resultados" é leitura do time todo, então os
  # campos de R$ vão como nil para os demais.
  def results
    recipients_count = @campaign.campaign_contacts.count
    converted = @campaign.converted_crm_contacts.to_a

    render json: {
      recipients: recipients_count,
      replies: build_replies,
      label_conversions: build_label_conversions,
      conversions: {
        count: converted.size,
        rate: recipients_count.positive? ? (converted.size.to_f / recipients_count * 100).round(1) : 0,
        total_value: money_sum(converted)
      },
      by_procedure: build_by_procedure(converted),
      converted_contacts: converted.map { |card| converted_json(card) }
    }
  end

  # POST preview_audience — recebe o audience e devolve contagem + amostra
  # 💸 R3 da auditoria (#415): devolve também o custo estimado (tarifa da
  # Meta na tabela de Crm::WhatsappPricing × contatos) para a confirmação
  # "Enviar para N contatos (≈ R$ X)?". category = marketing (padrão) ou
  # utility/authentication, conforme o modelo escolhido.
  def preview_audience
    preview = Crm::Campaign.new(account: Current.account, audience: audience_params)
    contacts = preview.resolve_audience
    count = contacts.size
    render json: {
      count: count,
      sample: contacts.limit(10).map { |c| { id: c.id, name: c.name, phone_number: c.phone_number } }
    }.merge(cost_estimate(count))
  end

  # GET templates?inbox_id= — templates aprovados do canal WhatsApp
  def templates
    inbox = Current.account.inboxes.find(params[:inbox_id])
    return render json: [] unless inbox.channel_type == 'Channel::Whatsapp'

    templates = inbox.channel.message_templates || []
    # item 314: all=1 → também os pendentes/recusados (o card de Confirmação
    # diz "existe mas não está aprovado" em vez de "não achei")
    templates = templates.select { |t| t['status']&.downcase == 'approved' } unless params[:all].to_s == '1'
    render json: templates
  end

  private

  # soma dos valores dos cards — nil para quem não vê o Financeiro
  def money_sum(cards)
    return nil unless finance_view?

    cards.sum { |card| card.value.to_f }
  end

  def finance_view?
    return @finance_view if defined?(@finance_view)

    @finance_view = money_visible?
  end

  def build_by_procedure(converted)
    converted.group_by { |card| card.procedure_of_interest.presence || 'Não informado' }
             .map { |procedure, cards| { procedure: procedure, count: cards.size, total_value: money_sum(cards) } }
             .sort_by { |row| [-row[:total_value].to_f, -row[:count]] }
  end

  def converted_json(card)
    {
      contact_id: card.contact_id,
      name: card.contact.name,
      phone_number: card.contact.phone_number,
      procedure: card.procedure_of_interest,
      value: finance_view? ? card.value : nil,
      stage_name: card.stage&.name,
      stage_color: card.stage&.color
    }
  end

  # Quem respondeu: mensagem recebida na conversa após o envio da campanha,
  # com a primeira resposta de cada um
  def build_replies
    responded = @campaign.campaign_contacts
                         .where.not(conversation_id: nil)
                         .joins('INNER JOIN messages ON messages.conversation_id = crm_campaign_contacts.conversation_id ' \
                                'AND messages.message_type = 0 AND messages.created_at > crm_campaign_contacts.sent_at')
                         .includes(:contact)
                         .distinct

    items = responded.limit(50).map do |cc|
      first_reply = ::Message.where(conversation_id: cc.conversation_id, message_type: :incoming)
                             .where('created_at > ?', cc.sent_at)
                             .order(:created_at).first
      {
        contact_id: cc.contact_id,
        name: cc.contact.name,
        phone_number: cc.contact.phone_number,
        reply: first_reply&.content.to_s.slice(0, 200),
        replied_at: first_reply&.created_at,
        conversation_id: cc.conversation_id
      }
    end

    { count: responded.count(:id), items: items }
  end

  # Conversões por etiqueta (ex: consulta-agendada aplicada ao destinatário)
  def build_label_conversions
    label_ids = Array(@campaign.conversion_label_ids)
    return { count: 0, labels: [], items: [] } if label_ids.empty?

    titles = Current.account.labels.where(id: label_ids).pluck(:title)
    return { count: 0, labels: [], items: [] } if titles.empty?

    recipient_ids = @campaign.campaign_contacts.select(:contact_id)
    converted = Current.account.contacts.where(id: recipient_ids).tagged_with(titles, any: true)

    {
      count: converted.count,
      labels: titles,
      items: converted.limit(50).map { |c| { contact_id: c.id, name: c.name, phone_number: c.phone_number, labels: c.label_list & titles } }
    }
  end

  def campaign
    @campaign ||= Current.account.crm_campaigns.find(params[:id])
  end

  # tarifa da Meta (tabela do item 303) × contatos = custo estimado do disparo
  def cost_estimate(count)
    rates = Crm::WhatsappPricing.rates(Current.account)
    category = Crm::WhatsappPricing::CATEGORIES.include?(params[:category].to_s) ? params[:category].to_s : 'marketing'
    rate = rates[category].to_f
    { estimated_cost: (rate * count).round(2), rate: rate, rate_category: category, currency: rates['currency'] }
  end

  # "2026-10-10T09:00" (sem fuso) = hora de São Paulo; com fuso/Z respeita o
  # fuso. Inválida ou no passado → :invalid (mesmo padrão da campanha de ligação)
  def parse_schedule(raw)
    value = Crm::Campaign::TZ.parse(raw.to_s)
    value.present? && value.future? ? value : :invalid
  rescue ArgumentError
    :invalid
  end

  # marca "em envio" só se a campanha AINDA estiver num estado que pode sair
  # (rascunho, agendada, pausada, falhou); devolve false se outro pedido chegou antes
  def claim_for_sending
    sendable = Crm::Campaign.statuses.slice('draft', 'scheduled', 'paused', 'failed').values
    Current.account.crm_campaigns.where(id: @campaign.id, status: sendable)
           .update_all(status: Crm::Campaign.statuses[:processing], updated_at: Time.current).positive? # rubocop:disable Rails/SkipsModelValidations
  end

  # a tela manda ignore_schedule=1 só depois que a pessoa confirmou no modal
  def ignore_schedule?
    ActiveModel::Type::Boolean.new.cast(params[:ignore_schedule]) == true
  end

  # horário do agendamento como a equipe lê (fuso da clínica)
  def scheduled_label(record)
    return nil if record.scheduled_at.blank?

    record.scheduled_at.in_time_zone(Crm::Campaign::TZ).strftime('%d/%m/%Y %H:%M')
  end

  def campaign_params
    params.require(:campaign).permit(
      :name, :inbox_id, :apply_label, :message_preview, :scheduled_at,
      template_params: {}, audience: {}, conversion_stage_ids: [], conversion_label_ids: []
    )
  end

  def audience_params
    params.require(:audience).permit(
      :period_field, :period_from, :period_to,
      include_label_ids: [], include_stage_ids: [],
      exclude_label_ids: [], exclude_stage_ids: []
    ).to_h
  end

  def campaign_json(c)
    {
      id: c.id,
      name: c.name,
      inbox_id: c.inbox_id,
      inbox_name: c.inbox&.name,
      template_params: c.template_params,
      message_preview: c.message_preview,
      audience: c.audience,
      apply_label: c.apply_label,
      conversion_stage_ids: c.conversion_stage_ids,
      conversion_label_ids: c.conversion_label_ids,
      # 🕐 R3 (#411): scheduled_at_label = hora pronta no fuso da clínica (a lista não depende do fuso do navegador)
      scheduled_at: c.scheduled_at, scheduled_at_label: scheduled_label(c),
      status: c.status,
      stats: c.stats,
      sender_name: c.sender&.name,
      started_at: c.started_at,
      finished_at: c.finished_at,
      created_at: c.created_at
    }
  end
end
