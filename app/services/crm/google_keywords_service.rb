# Palavras-chave, termos de pesquisa e campanhas do Google SEM developer
# token: lê pela API de dados do GA4 (dimensões sessionGoogleAdsKeyword /
# sessionGoogleAdsQuery / sessionGoogleAdsCampaignName) com a MESMA conta de
# serviço do custo automático (Crm::GoogleAdCostService). Cada linha traz
# cliques, custo e sessões — o cruzamento com leads/consultas/cirurgias vem
# do banco (page_ads.utm_term) no dashboard Google.
class Crm::GoogleKeywordsService < Crm::GoogleAdCostService
  ROW_LIMIT = 50
  METRICS = %w[advertiserAdClicks advertiserAdCost sessions keyEvents].freeze

  def call
    return { configured: false } unless configured?

    token = access_token
    return { configured: true, error: @auth_error || 'Falha na autenticação com o Google' } if token.blank?

    {
      configured: true,
      keywords: report(token, 'sessionGoogleAdsKeyword'),
      queries: report(token, 'sessionGoogleAdsQuery'),
      campaigns: report(token, 'sessionGoogleAdsCampaignName')
    }
  rescue StandardError => e
    Rails.logger.error "[Crm::GoogleKeywordsService] #{e.class}: #{e.message}"
    { configured: true, error: e.message }
  end

  private

  def report(token, dimension)
    response = HTTParty.post(
      "#{DATA_API}/properties/#{property_id}:runReport",
      headers: { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' },
      body: {
        dateRanges: [{ startDate: @since_date.iso8601, endDate: @until_date.iso8601 }],
        dimensions: [{ name: dimension }],
        metrics: METRICS.map { |m| { name: m } },
        orderBys: [{ metric: { metricName: 'advertiserAdClicks' }, desc: true }],
        limit: ROW_LIMIT
      }.to_json,
      timeout: 20
    )
    return { error: extract_error(response) } unless response.success?

    rows = Array(response.parsed_response['rows']).map do |row|
      mets = row['metricValues'] || []
      {
        term: row.dig('dimensionValues', 0, 'value').to_s,
        clicks: mets.dig(0, 'value').to_i,
        cost: mets.dig(1, 'value').to_f.round(2),
        sessions: mets.dig(2, 'value').to_i,
        key_events: mets.dig(3, 'value').to_f.round(0).to_i
      }
    end
    # tira o ruído: linha sem nome e "(not set)" sem clique nenhum
    { rows: rows.reject { |r| r[:term].blank? || (r[:term] == '(not set)' && r[:clicks].zero?) } }
  end
end
