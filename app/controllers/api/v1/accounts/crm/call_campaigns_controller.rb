# 🤖📞 Campanhas de ligação (item 169): a assistente virtual liga para um
# público. Leitura livre para o time acompanhar; criar/editar/começar/pausar
# é área concedível (campaigns), como a Campanha WhatsApp.
class Api::V1::Accounts::Crm::CallCampaignsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  PER_PAGE = 50

  before_action -> { require_capability(:campaigns) }, only: %i[create update destroy start pause resume preview_audience]
  before_action :campaign, only: %i[show update destroy start pause resume]

  def index
    campaigns = Crm::CallCampaign.where(account_id: Current.account.id).order(created_at: :desc)
    render json: { call_campaigns: campaigns.map { |c| campaign_json(c) } }
  end

  def show
    scope = @campaign.campaign_contacts.includes(:contact, call: :conversation).order(:id)
    rows = scope.offset((page - 1) * PER_PAGE).limit(PER_PAGE)
    render json: campaign_json(@campaign).merge(contacts: rows.map(&:to_payload), meta: { total: scope.count, page: page, per_page: PER_PAGE })
  end

  def create
    @campaign = Crm::CallCampaign.create!(campaign_params.merge(account: Current.account, created_by: Current.user, status: :draft))
    render json: campaign_json(@campaign), status: :created
  end

  def update
    return render_could_not_create_error('Campanha concluída não pode ser editada') if @campaign.completed?

    @campaign.update!(campaign_params)
    render json: campaign_json(@campaign)
  end

  def destroy
    return render_could_not_create_error('Pause a campanha antes de excluí-la') if @campaign.processing?

    @campaign.destroy!
    head :no_content
  end

  # Começar: agenda (scheduled_at futuro) ou dispara agora — o discador
  # (cron 5 min) faz as ligações dentro do horário
  def start
    return render_could_not_create_error('Campanha já foi concluída') if @campaign.completed?

    if params[:scheduled_at].present? && Time.zone.parse(params[:scheduled_at].to_s).to_i > Time.current.to_i
      @campaign.update!(status: :scheduled, scheduled_at: params[:scheduled_at])
    else
      @campaign.start!
    end
    render json: campaign_json(@campaign)
  end

  def pause
    return render_could_not_create_error('Só campanhas em andamento podem ser pausadas') unless @campaign.processing? || @campaign.scheduled?

    @campaign.update!(status: :paused)
    render json: campaign_json(@campaign)
  end

  def resume
    return render_could_not_create_error('Só campanhas pausadas podem ser retomadas') unless @campaign.paused?

    @campaign.start!
    render json: campaign_json(@campaign)
  end

  # POST preview_audience — contagem + amostra do público (mesmo da Campanha WhatsApp)
  def preview_audience
    contacts = Crm::CallCampaign.new(account: Current.account, audience: audience_params).resolve_audience
    render json: { count: contacts.size, sample: contacts.limit(10).map { |c| { id: c.id, name: c.name, phone_number: c.phone_number } } }
  end

  private

  def campaign
    @campaign ||= Crm::CallCampaign.where(account_id: Current.account.id).find(params[:id])
  end

  def page
    [params[:page].to_i, 1].max
  end

  def campaign_params
    permitted = params.require(:call_campaign).permit(:name, :objective, :first_message, :apply_label, :daily_cap, :concurrency,
                                                      :scheduled_at, audience: {}, hours: [:start, :end])
    permitted[:hours] = sanitize_hours(permitted[:hours]) if permitted.key?(:hours)
    permitted
  end

  def audience_params
    params.require(:audience).permit(:period_field, :period_from, :period_to, include_label_ids: [], include_stage_ids: [],
                                                                              exclude_label_ids: [], exclude_stage_ids: []).to_h
  end

  # "HH:MM" válidos e início < fim; senão nil (vale o horário da configuração)
  def sanitize_hours(raw)
    h = (raw || {}).to_h.stringify_keys
    start_at = h['start'].to_s.strip
    end_at = h['end'].to_s.strip
    valid = [start_at, end_at].all? { |v| v.match?(/\A([01]\d|2[0-3]):[0-5]\d\z/) } && start_at < end_at
    valid ? { 'start' => start_at, 'end' => end_at } : nil
  end

  def campaign_json(record)
    {
      id: record.id, name: record.name, status: record.status, audience: record.audience, objective: record.objective,
      first_message: record.first_message, apply_label: record.apply_label, hours: record.hours, daily_cap: record.daily_cap,
      concurrency: record.concurrency, scheduled_at: record.scheduled_at, started_at: record.started_at,
      finished_at: record.finished_at, stats: record.stats, progress: record.progress, outcomes: record.outcomes,
      created_by_name: record.created_by&.available_name, created_at: record.created_at
    }
  end
end
