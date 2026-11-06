# 💰 FINANCEIRO & CAC (item 318): quanto custa cada paciente que operou —
# CAC de anúncios (por canal e campanha) + CAC total (tecnologia e anúncios)
# + retorno (ROAS). Mesmo acesso do Financeiro. ?usd=5.5 = dólar manual
# (projeção) no lugar da cotação do dia.
class Api::V1::Accounts::Crm::AcquisitionCostsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  include Crm::ResolvesPeriod

  def show
    since, until_at = standard_period_range || default_range
    render json: Crm::AcquisitionCostService.new(
      account: Current.account, since: since, until_at: until_at, manual_usd: params[:usd]
    ).call
  end

  # 📈 custo por fonte ao longo do tempo + faturamento × etapas (19/10/2026)
  def timeline
    since, until_at = standard_period_range || default_range
    render json: Crm::AcquisitionTimelineService.new(account: Current.account, since: since, until_at: until_at).call
  end

  private

  def default_range
    now = PERIOD_TZ.now
    [now.beginning_of_month, now.end_of_day]
  end
end
