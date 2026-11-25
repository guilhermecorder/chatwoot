# 🆚 COMPARATIVO DE CAIXAS (item 413, 24/11): cada caixa de entrada lado a lado,
# pela TURMA que chegou por ela no período (Crm::InboxComparison). Mesmo acesso
# do Dashboard CRM (nó relatorios.crm); dinheiro (gasto de anúncio, custo por
# lead, custo da IA) só para administrador, como lá.
#   GET crm/inbox_comparison?preset=…&compare=previous|month|pick&compare_month=AAAA-MM
#   GET crm/inbox_comparison/lines?…  📈 item 418: as linhas por caixa, campanha e criativo
#     (Crm::InboxLines; pedido à parte para não pesar o comparativo; sem dinheiro)
class Api::V1::Accounts::Crm::InboxComparisonsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  include Crm::ResolvesPeriod

  CACHE_TTL = 5.minutes

  def show
    since, until_at = standard_period_range || custom_period_range
    compare = period_comparison(since, until_at)
    admin = Current.account_user&.administrator? == true
    key = ['cevico_inbox_comparison', Current.account.id, since.to_i, until_at.to_i, compare.cache_key, admin]
    payload = Rails.cache.fetch(key, expires_in: CACHE_TTL) do
      Crm::InboxComparison.new(account: Current.account, since: since, until_at: until_at, compare: compare,
                               invest: admin ? invest_for(since, until_at) : nil).call
    end
    render json: payload
  end

  def lines
    since, until_at = standard_period_range || custom_period_range
    compare = period_comparison(since, until_at)
    key = ['cevico_inbox_lines', Current.account.id, since.to_i, until_at.to_i, compare.cache_key]
    payload = Rails.cache.fetch(key, expires_in: CACHE_TTL) do
      Crm::InboxLines.new(account: Current.account, since: since, until_at: until_at, compare: compare).call
    end
    render json: payload
  end

  private

  # o gasto dos anúncios do período, com o MESMO cache do Dashboard CRM
  def invest_for(since, until_at) # rubocop:disable Metrics/AbcSize
    meta = Rails.cache.fetch(['cevico_meta_spend', Current.account.id, since.to_date.iso8601, until_at.to_date.iso8601],
                             expires_in: 10.minutes) do
      Crm::MetaInsightsService.new(account: Current.account, since_date: since.to_date, until_date: until_at.to_date).call
    end
    config = investments_config
    {
      meta_total: meta[:spend].to_f.positive? ? meta[:spend].to_f : nil,
      meta_note: meta[:error].presence || (meta[:configured] ? nil : 'Meta Ads não configurado em Integrações'),
      google: config.values.any? { |cfg| cfg['mode'] == 'google_auto' } ? google_cost(since, until_at) : nil,
      config: config
    }
  end

  def google_cost(since, until_at)
    Rails.cache.fetch(['cevico_google_cost', Current.account.id, since.to_date.iso8601, until_at.to_date.iso8601],
                      expires_in: 10.minutes) do
      Crm::GoogleAdCostService.new(account: Current.account, since_date: since.to_date, until_date: until_at.to_date).call
    end
  end

  # config por caixa no formato novo {mode, monthly}; número puro = legado manual
  def investments_config
    raw = CrmSetting.find_by(account: Current.account)&.agenda_config&.dig('inbox_investments') || {}
    raw.transform_values { |value| value.is_a?(Hash) ? value : { 'mode' => 'manual', 'monthly' => value.to_f } }
  end
end
