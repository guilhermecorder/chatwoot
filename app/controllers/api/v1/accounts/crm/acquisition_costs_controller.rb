# 💰 FINANCEIRO & CAC (item 318): quanto custa cada paciente que operou —
# CAC de anúncios (por canal e campanha) + CAC total (tecnologia e anúncios)
# + retorno (ROAS). Mesmo acesso do Financeiro. ?usd=5.5 = dólar manual
# (projeção) no lugar da cotação do dia.
class Api::V1::Accounts::Crm::AcquisitionCostsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  include Crm::ResolvesPeriod
  before_action -> { require_capability(:finance) }

  def show
    since, until_at = standard_period_range || default_range
    render json: Crm::AcquisitionCostService.new(
      account: Current.account, since: since, until_at: until_at, manual_usd: params[:usd]
    ).call
  end

  private

  def default_range
    now = PERIOD_TZ.now
    [now.beginning_of_month, now.end_of_day]
  end
end
