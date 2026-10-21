# 🌪️ item 271 (28/09): funil de AQUISIÇÃO por turma + DA PORTA PRA DENTRO
# (blocos do painel Gestor no Meu Painel). Só leitura.
class Api::V1::Accounts::Crm::FunnelsController < Api::V1::Accounts::BaseController
  include Crm::ResolvesPeriod

  # GET /crm/funnels/acquisition?preset=month&horizon=90
  def acquisition
    since, until_at = standard_period_range || custom_period_range
    horizon = params[:horizon].presence&.to_i || 90
    data = Rails.cache.fetch(cache_key('acq', since, until_at, horizon), expires_in: 10.minutes) do
      Crm::FunnelService.new(Current.account).acquisition(since, until_at, horizon_days: horizon)
    end
    render json: data.merge(since: since, until: until_at)
  end

  # GET /crm/funnels/clinic?preset=month
  def clinic
    since, until_at = standard_period_range || custom_period_range
    data = Rails.cache.fetch(cache_key('clinic', since, until_at, 0), expires_in: 10.minutes) do
      Crm::FunnelService.new(Current.account).clinic(since, until_at)
    end
    render json: data.merge(since: since, until: until_at)
  end

  private

  def cache_key(kind, since, until_at, extra)
    "cevico:funnel:#{Current.account.id}:#{kind}:#{since.to_i}:#{until_at.to_i}:#{extra}:#{params[:fresh].present? ? Time.current.to_i : 0}"
  end
end
