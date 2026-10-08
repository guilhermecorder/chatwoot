# 🤖📞 Campanhas de ligação (item 169): a assistente virtual liga para um
# público. Leitura livre para o time acompanhar; criar/editar/começar/pausar
# é área concedível (campaigns), como a Campanha WhatsApp.
class Api::V1::Accounts::Crm::CallCampaignsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  PER_PAGE = 50
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  SCHEDULE_ERROR = 'Data de agendamento inválida ou no passado. Escolha um dia e horário à frente.'.freeze

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

  # item 333: "Agendar para…" agora nasce AGENDADA (antes ficava rascunho e o
  # discador nunca a achava); a data digitada é hora de São Paulo
  def create
    attrs = campaign_params
    return render_could_not_create_error(SCHEDULE_ERROR) if attrs.key?(:scheduled_at) && attrs[:scheduled_at] == :invalid

    status = attrs[:scheduled_at].present? ? :scheduled : :draft
    @campaign = Crm::CallCampaign.create!(attrs.merge(account: Current.account, created_by: Current.user, status: status))
    render json: campaign_json(@campaign), status: :created
  end

  def update
    return render_could_not_create_error('Campanha concluída não pode ser editada') if @campaign.completed?

    attrs = campaign_params
    return render_could_not_create_error(SCHEDULE_ERROR) if attrs.key?(:scheduled_at) && attrs[:scheduled_at] == :invalid

    @campaign.update!(attrs)
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

    if params[:scheduled_at].present?
      when_at = parse_schedule(params[:scheduled_at])
      return render_could_not_create_error(SCHEDULE_ERROR) if when_at == :invalid

      @campaign.update!(status: :scheduled, scheduled_at: when_at)
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
    permitted[:scheduled_at] = permitted[:scheduled_at].present? ? parse_schedule(permitted[:scheduled_at]) : nil if permitted.key?(:scheduled_at)
    permitted
  end

  # "2026-10-10T09:00" (sem fuso) = hora de São Paulo; com fuso/Z respeita o
  # fuso. Inválida ou no passado → :invalid
  def parse_schedule(raw)
    value = TZ.parse(raw.to_s)
    value.present? && value.future? ? value : :invalid
  rescue ArgumentError
    :invalid
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
