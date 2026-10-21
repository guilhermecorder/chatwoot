# Gasto da conta de anúncios da Meta MÊS A MÊS (item 318): a mesma leitura
# do Crm::MetaInsightsService com time_increment=monthly — uma chamada só para
# o gráfico de evolução do Financeiro & CAC.
#   call → { configured:, months: { '2026-09' => 1234.5, … } } | { configured:, error: }
class Crm::MetaMonthlySpendService < Crm::MetaInsightsService
  def call # rubocop:disable Metrics/AbcSize
    return { configured: false } unless configured?

    response = HTTParty.get(
      "#{BASE_URI}/#{api_version}/act_#{ad_account_id}/insights",
      query: {
        fields: 'spend',
        time_increment: 'monthly',
        time_range: { since: @since_date.iso8601, until: @until_date.iso8601 }.to_json,
        access_token: access_token
      },
      timeout: 15
    )
    return { configured: true, error: extract_error(response) } unless response.success?

    months = Array(response.parsed_response['data']).each_with_object(Hash.new(0.0)) do |row, acc|
      acc[row['date_start'].to_s[0, 7]] += row['spend'].to_f
    end
    { configured: true, months: months.transform_values { |v| v.round(2) } }
  rescue StandardError => e
    Rails.logger.error "[Crm::MetaMonthlySpendService] #{e.message}"
    { configured: true, error: e.message }
  end
end
