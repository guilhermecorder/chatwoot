# Inherits from ActionController::Base to skip all middleware,
# authentication, and callbacks. Used for health checks
class HealthController < ActionController::Base # rubocop:disable Rails/ApplicationController
  def show
    # 🚨 CEVICO (achado #217): /health?sidekiq=1 também confere a fila dos robôs
    # (sinal de 1 min do Crm::SidekiqHeartbeatJob) — 503 quando ela parou. O
    # /health sem parâmetro continua igual (não derruba o web por causa da fila).
    return render json: { status: 'sidekiq_parado' }, status: :service_unavailable if params[:sidekiq].present? && !Crm::CronHealth.sidekiq_alive?

    render json: { status: 'woot' }
  end
end
