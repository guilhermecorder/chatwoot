# 🗺️ Envios da jornada (item 168): a "Fila de hoje" (aprovar/pular/aprovar
# todos), o histórico por mensagem e o reenvio. Leitura livre para o time;
# aprovar/pular/reenviar = área `campaigns`.
class Api::V1::Accounts::Crm::JourneySendsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  PER_PAGE = 50
  TZ = Crm::Journey::Settings::TZ

  before_action -> { require_capability(:campaigns) }, only: %i[approve skip retry approve_all]
  before_action :send_record, only: %i[approve skip retry]

  def index
    scope = filtered_scope
    rows = scope.order(scheduled_for: :desc, id: :desc).offset((page - 1) * PER_PAGE).limit(PER_PAGE)
    render json: { sends: rows.map(&:to_payload), meta: { total: scope.count, page: page, per_page: PER_PAGE } }
  end

  # fila do dia (padrão hoje): tudo o que está planejado, agrupado por mensagem
  def queue
    day = safe_date(params[:date]) || TZ.now.to_date
    rows = base_scope.for_day(day, TZ).order(:scheduled_for, :id)
    render json: { date: day.iso8601, sends: rows.map(&:to_payload), counts: rows.reorder(nil).group(:status).count }
  end

  def approve
    return render json: { error: 'Este envio já foi tratado.' }, status: :conflict unless @send.status == 'pending_review'

    outcome = Crm::Journey::Dispatcher.new(account: Current.account).dispatch(@send)
    render json: { outcome: outcome, send: @send.reload.to_payload }
  end

  def skip
    return render json: { error: 'Este envio já saiu.' }, status: :conflict if @send.status == 'sent'

    @send.update!(status: 'skipped', error: "Pulado por #{Current.user.available_name}")
    render json: { send: @send.to_payload }
  end

  RETRYABLE = %w[failed skipped expired].freeze

  def retry
    unless RETRYABLE.include?(@send.status)
      return render json: { error: 'Só envios que falharam ou foram pulados podem ser reenviados.' }, status: :conflict
    end

    @send.update!(status: 'queued', error: nil, scheduled_for: Time.current)
    outcome = Crm::Journey::Dispatcher.new(account: Current.account).dispatch(@send)
    render json: { outcome: outcome, send: @send.reload.to_payload }
  end

  # aprova todos os pendentes do dia (opcionalmente só de uma mensagem)
  def approve_all
    day = safe_date(params[:date]) || TZ.now.to_date
    scope = base_scope.for_day(day, TZ).where(status: 'pending_review')
    scope = scope.where(journey_message_id: params[:message_id]) if params[:message_id].present?
    dispatcher = Crm::Journey::Dispatcher.new(account: Current.account)
    results = Hash.new(0)
    scope.includes(:journey_message, :contact).find_each { |s| results[dispatcher.dispatch(s)] += 1 }
    render json: { results: results }
  end

  private

  def filtered_scope
    scope = base_scope
    { journey_message_id: :message_id, status: :status, contact_id: :contact_id }.each do |column, key|
      scope = scope.where(column => params[key]) if params[key].present?
    end
    scope
  end

  def base_scope
    Crm::JourneySend.where(account: Current.account).includes(:journey_message, :contact, :conversation)
  end

  def send_record
    @send = base_scope.find(params[:id])
  end

  def page
    [params[:page].to_i, 1].max
  end

  def safe_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
