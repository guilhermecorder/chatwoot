# Busca métricas de anúncios (investimento, alcance, cliques) na conta de
# anúncios do Meta via Marketing API. Usa o access_token e o ad_account_id
# configurados em CRM → Integrações → Meta Ads.
class Crm::MetaInsightsService
  BASE_URI = 'https://graph.facebook.com'.freeze

  def initialize(account:, since_date:, until_date: Date.current)
    @account = account
    @since_date = since_date
    @until_date = until_date
  end

  def call
    return { configured: false } unless configured?

    response = HTTParty.get(
      "#{BASE_URI}/#{api_version}/act_#{ad_account_id}/insights",
      query: {
        fields: 'spend,reach,impressions,inline_link_clicks',
        time_range: { since: @since_date.iso8601, until: @until_date.iso8601 }.to_json,
        access_token: access_token
      },
      timeout: 15
    )

    return { configured: true, error: extract_error(response) } unless response.success?

    row = (response.parsed_response['data'] || []).first || {}
    {
      configured: true,
      spend: row['spend'].to_f,
      reach: row['reach'].to_i,
      impressions: row['impressions'].to_i,
      link_clicks: row['inline_link_clicks'].to_i
    }
  rescue StandardError => e
    Rails.logger.error "[Crm::MetaInsightsService] #{e.message}"
    { configured: true, error: e.message }
  end

  private

  def config
    @config ||= CrmSetting.find_by(account: @account)&.meta_ads_config || {}
  end

  def access_token
    config['access_token']
  end

  def ad_account_id
    config['ad_account_id'].to_s.sub(/\Aact_/, '')
  end

  def configured?
    access_token.present? && config['ad_account_id'].present?
  end

  def api_version
    GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
  end

  def extract_error(response)
    response.parsed_response.dig('error', 'message') || "HTTP #{response.code}"
  rescue StandardError
    "HTTP #{response.code}"
  end
end
