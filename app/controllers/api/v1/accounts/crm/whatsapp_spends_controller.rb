# 💸 GASTO DO WHATSAPP (item 303, só admin): quanto a Meta cobra pelas
# mensagens — fatura real (pricing_analytics) + quem gastou (atribuição por
# mensagem) + tarifas editáveis + botão de sincronizar com a Meta.
class Api::V1::Accounts::Crm::WhatsappSpendsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  include Crm::ResolvesPeriod
  before_action :require_administrator!

  def show
    since, until_at = standard_period_range || default_range
    render json: Crm::WhatsappSpendService.new(account: Current.account, since: since, until_at: until_at).call
  end

  # POST /crm/whatsapp_spend/rates — tarifas por categoria (R$) + moeda
  def rates
    permitted = params.permit(:currency, *Crm::WhatsappPricing::CATEGORIES)
    render json: { rates: Crm::WhatsappPricing.save(Current.account, permitted) }
  end

  # POST /crm/whatsapp_spend/sync — puxa a fatura da Meta (até 95 dias na
  # hora; mais que isso vai para a fila e a tela avisa)
  def sync
    days = params[:days].to_i.clamp(1, Crm::WhatsappPricingSyncService::MAX_DAYS)
    if days > 95
      Crm::WhatsappPricingSyncJob.perform_later(Current.account.id, days)
      render json: { ok: true, queued: true, days: days }
    else
      render json: Crm::WhatsappPricingSyncService.new(account: Current.account, days: days).call
    end
  end

  private

  def default_range
    now = PERIOD_TZ.now
    [(now - 6.days).beginning_of_day, now.end_of_day]
  end
end
