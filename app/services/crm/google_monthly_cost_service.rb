# Gasto do Google Ads MÊS A MÊS (item 318): a mesma leitura do GA4 do custo
# automático (advertiserAdCost), quebrada pela dimensão yearMonth — uma
# chamada só para o gráfico de evolução do Financeiro & CAC.
#   call → { configured:, months: { '2026-09' => 1234.5, … } } | { configured:, error: }
class Crm::GoogleMonthlyCostService < Crm::GoogleAdCostService
  def call
    return { configured: false } unless configured?

    token = access_token
    return { configured: true, error: @auth_error || 'Falha na autenticação com o Google' } if token.blank?

    fetch_months(token)
  rescue StandardError => e
    Rails.logger.error "[Crm::GoogleMonthlyCostService] #{e.class}: #{e.message}"
    { configured: true, error: e.message }
  end

  private

  def fetch_months(token)
    response = HTTParty.post(
      "#{DATA_API}/properties/#{property_id}:runReport",
      headers: { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' },
      body: {
        dateRanges: [{ startDate: @since_date.iso8601, endDate: @until_date.iso8601 }],
        dimensions: [{ name: 'yearMonth' }],
        metrics: [{ name: 'advertiserAdCost' }]
      }.to_json,
      timeout: 15
    )
    return { configured: true, error: extract_error(response) } unless response.success?

    months = Array(response.parsed_response['rows']).to_h do |row|
      ym = row.dig('dimensionValues', 0, 'value').to_s # "202609"
      ["#{ym[0, 4]}-#{ym[4, 2]}", row.dig('metricValues', 0, 'value').to_f.round(2)]
    end
    { configured: true, months: months }
  end
end
