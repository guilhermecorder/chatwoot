# Custo de CADA campanha do Google Ads no período (18/10 — ROI por campanha):
# lê pela API de dados do GA4 (dimensões sessionGoogleAdsCampaignId e
# sessionGoogleAdsCampaignName, métricas advertiserAdCost/advertiserAdClicks)
# com a MESMA conta de serviço do custo automático (Crm::GoogleAdCostService).
# O ID da campanha é a chave que junta com o lead: a página guarda o utm_id
# ({campaignid} no sufixo do URL final) no Protocolo do clique.
#
# A resposta fica guardada por 30 minutos (a tela de Resultados recarrega a
# cada troca de período e não precisa bater no Google toda vez).
class Crm::GoogleCampaignCostService < Crm::GoogleAdCostService
  ROW_LIMIT = 200
  CACHE_TTL = 30.minutes

  def call
    return { configured: false } unless configured?

    cached = Rails.cache.read(cache_key)
    return cached if cached

    result = fetch
    # erro (autenticação, acesso, rede) não fica guardado: tenta de novo na próxima abertura
    Rails.cache.write(cache_key, result, expires_in: CACHE_TTL) unless result[:error]
    result
  rescue StandardError => e
    Rails.logger.error "[Crm::GoogleCampaignCostService] #{e.class}: #{e.message}"
    { configured: true, error: e.message }
  end

  private

  def cache_key
    "crm/google_campaign_cost/#{@account.id}/#{property_id}/#{@since_date.iso8601}/#{@until_date.iso8601}"
  end

  def fetch
    token = access_token
    return { configured: true, error: @auth_error || 'Falha na autenticação com o Google' } if token.blank?

    response = HTTParty.post(
      "#{DATA_API}/properties/#{property_id}:runReport",
      headers: { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' },
      body: request_body.to_json,
      timeout: 20
    )
    return { configured: true, error: extract_error(response) } unless response.success?

    { configured: true, campaigns: parse(response.parsed_response) }
  end

  def request_body
    {
      dateRanges: [{ startDate: @since_date.iso8601, endDate: @until_date.iso8601 }],
      dimensions: [{ name: 'sessionGoogleAdsCampaignId' }, { name: 'sessionGoogleAdsCampaignName' }],
      metrics: [{ name: 'advertiserAdCost' }, { name: 'advertiserAdClicks' }],
      orderBys: [{ metric: { metricName: 'advertiserAdCost' }, desc: true }],
      limit: ROW_LIMIT
    }
  end

  # [{ id:, name:, cost:, clicks: }] — sem as linhas "(not set)" e sem custo nem clique
  def parse(payload)
    Array(payload['rows']).filter_map { |row| parse_row(row) }
  end

  def parse_row(row)
    dims = Array(row['dimensionValues']).map { |d| d['value'].to_s.sub('(not set)', '') }
    mets = Array(row['metricValues']).pluck('value')
    item = { id: dims[0].to_s, name: dims[1].to_s, cost: mets[0].to_f.round(2), clicks: mets[1].to_i }
    return nil if item[:id].blank? || (item[:cost].zero? && item[:clicks].zero?)

    item
  end
end
