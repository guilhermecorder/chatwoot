class Api::V1::Accounts::Crm::CampaignsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  # disparar/criar campanha em massa = área concedível (padrão: só admin).
  # Leitura (index/show/results) e prévias ficam livres p/ acompanhar.
  before_action -> { require_capability(:campaigns) },
                only: %i[create destroy send_now schedule preview_audience]
  before_action :campaign, only: [:show, :destroy, :send_now, :schedule, :results]

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

  def send_now
    # bloqueia só a campanha CONCLUÍDA (evita reblast acidental). Uma campanha
    # travada em "processando" (job perdido num deploy) ou "falhou" pode ser
    # reenviada: o job agora retoma sem reenviar quem já recebeu.
    return render_could_not_create_error('Campanha já foi concluída') if @campaign.completed?

    @campaign.update!(status: :processing)
    Crm::CampaignRunJob.perform_later(@campaign.id)
    render json: campaign_json(@campaign)
  end

  # POST schedule — agenda o disparo (scheduled_at obrigatório)
  def schedule
    return render_could_not_create_error('Campanha já foi enviada') unless @campaign.draft? || @campaign.scheduled?
    return render_could_not_create_error('Informe a data de envio') if params[:scheduled_at].blank?

    @campaign.update!(status: :scheduled, scheduled_at: params[:scheduled_at])
    render json: campaign_json(@campaign)
  end

  # GET results — painel de resultados: destinatários x conversões no CRM
  def results
    recipients_count = @campaign.campaign_contacts.count
    converted = @campaign.converted_crm_contacts.to_a
    replies = build_replies
    label_conversions = build_label_conversions

    total_value = converted.sum { |c| c.value.to_f }
    by_procedure = converted.group_by { |c| c.procedure_of_interest.presence || 'Não informado' }
                            .map do |procedure, cards|
      {
        procedure: procedure,
        count: cards.size,
        total_value: cards.sum { |c| c.value.to_f }
      }
    end.sort_by { |p| -p[:total_value] }

    render json: {
      recipients: recipients_count,
      replies: replies,
      label_conversions: label_conversions,
      conversions: {
        count: converted.size,
        rate: recipients_count.positive? ? (converted.size.to_f / recipients_count * 100).round(1) : 0,
        total_value: total_value
      },
      by_procedure: by_procedure,
      converted_contacts: converted.map do |c|
        {
          contact_id: c.contact_id,
          name: c.contact.name,
          phone_number: c.contact.phone_number,
          procedure: c.procedure_of_interest,
          value: c.value,
          stage_name: c.stage&.name,
          stage_color: c.stage&.color
        }
      end
    }
  end

  # POST preview_audience — recebe o audience e devolve contagem + amostra
  def preview_audience
    preview = Crm::Campaign.new(account: Current.account, audience: audience_params)
    contacts = preview.resolve_audience
    render json: {
      count: contacts.size,
      sample: contacts.limit(10).map { |c| { id: c.id, name: c.name, phone_number: c.phone_number } }
    }
  end

  # GET templates?inbox_id= — templates aprovados do canal WhatsApp
  def templates
    inbox = Current.account.inboxes.find(params[:inbox_id])
    return render json: [] unless inbox.channel_type == 'Channel::Whatsapp'

    approved = (inbox.channel.message_templates || []).select do |t|
      t['status']&.downcase == 'approved'
    end
    render json: approved
  end

  private

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
      scheduled_at: c.scheduled_at,
      status: c.status,
      stats: c.stats,
      sender_name: c.sender&.name,
      started_at: c.started_at,
      finished_at: c.finished_at,
      created_at: c.created_at
    }
  end
end
