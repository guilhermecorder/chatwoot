# 🗺️ Envios da jornada (item 168): a "Fila de hoje" (aprovar/pular/aprovar
# todos), o histórico por mensagem e o reenvio. Leitura livre para o time;
# aprovar/pular/reenviar = área `campaigns`.
class Api::V1::Accounts::Crm::JourneySendsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  PER_PAGE = 50
  TZ = Crm::Journey::Settings::TZ

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

  # 🔒 auditoria R3 (#21/#412): o Dispatcher PEGA o envio no banco de forma
  # atômica antes de mandar; se outra aba/pessoa/cron pegou primeiro, devolve
  # :busy e aqui vira 409 — o paciente nunca recebe o mesmo balão duas vezes.
  BUSY = 'Este envio já está sendo tratado (outra pessoa, outra aba ou o robô pegou primeiro).'.freeze

  def approve
    return render json: { error: 'Este envio já foi tratado.' }, status: :conflict unless @send.status == 'pending_review'

    outcome = Crm::Journey::Dispatcher.new(account: Current.account).dispatch(@send)
    return render_conflict if outcome == :busy

    render json: { outcome: outcome, send: @send.reload.to_payload }
  end

  # 🔒 R3: pular também é atômico — só sai de "na fila"/"aguardando aprovação".
  # Envio que já está saindo ('sending') não vira "Pulada" por cima (a tela
  # diria "pulada" e a mensagem sairia mesmo assim; e um "Reenviar" em seguida
  # mandaria o balão de novo).
  def skip
    got = Crm::JourneySend.where(id: @send.id, status: Crm::JourneySend::CLAIMABLE)
                          .update_all(status: 'skipped', error: "Pulado por #{Current.user.available_name}", updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    return render_conflict unless got == 1

    render json: { send: @send.reload.to_payload }
  end

  RETRYABLE = Crm::JourneySend::RETRYABLE

  def retry
    unless RETRYABLE.include?(@send.status)
      return render json: { error: 'Só envios que falharam ou foram pulados podem ser reenviados.' }, status: :conflict
    end

    # 🛡️ auditoria 10/10 (#426): não reenvia mensagem de consulta/cirurgia
    # cancelada, remarcada ou cujo dia já passou (ia sair com a data velha)
    dispatcher = Crm::Journey::Dispatcher.new(account: Current.account)
    why = dispatcher.retry_blocker(@send)
    return render json: { error: "Não dá para reenviar. #{why}." }, status: :conflict if why

    # 🔒 R3: pega direto de falhou/pulado/expirou → 'sending' (não passa por
    # 'queued', senão o cron podia pegar o mesmo envio naquele instante)
    outcome = dispatcher.retry(@send)
    return render_conflict if outcome == :busy

    render json: { outcome: outcome, send: @send.reload.to_payload }
  end

  # aprova todos os pendentes do dia (opcionalmente só de uma mensagem)
  def approve_all
    day = safe_date(params[:date]) || TZ.now.to_date
    scope = base_scope.for_day(day, TZ).where(status: 'pending_review')
    scope = scope.where(journey_message_id: params[:message_id]) if params[:message_id].present?
    dispatcher = Crm::Journey::Dispatcher.new(account: Current.account)
    results = Hash.new(0)
    # cada envio é pego de forma atômica; o que outra pessoa pegou no meio conta como :busy
    scope.includes(:journey_message, :contact, :source).find_each { |s| results[dispatcher.dispatch(s)] += 1 }
    render json: { results: results }
  end

  private

  # 409 quando não deu para pegar o envio: se ele já terminou (saiu, foi pulado,
  # falhou ou expirou um instante antes do clique) diz isso; senão, alguém
  # (outra pessoa, outra aba ou o cron) está mandando agora
  def render_conflict
    @send.reload
    error = @send.final? ? "Este envio já foi tratado (#{Crm::JourneySend::STATUS_LABELS[@send.status]})." : BUSY
    render json: { error: error, send: @send.to_payload }, status: :conflict
  end

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
