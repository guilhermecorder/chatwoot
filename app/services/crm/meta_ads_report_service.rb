# Busca métricas POR ANÚNCIO (level=ad) na Marketing API da Meta:
# investimento, impressões, cliques — por ad_id, com nome do anúncio,
# conjunto e campanha. É a metade "Meta" do relatório de anúncios;
# a outra metade (leads/conversões) vem do nosso banco via atribuição CTWA.
class Crm::MetaAdsReportService
  BASE_URI = 'https://graph.facebook.com'.freeze
  MAX_PAGES = 5

  def initialize(account:, since_date:, until_date: Date.current)
    @account = account
    @since_date = since_date
    @until_date = until_date
  end

  def call
    return { configured: false, rows: [] } unless configured?

    rows = []
    url = insights_url
    query = insights_query

    MAX_PAGES.times do
      response = HTTParty.get(url, query: query, timeout: 20)
      return { configured: true, error: extract_error(response), rows: rows } unless response.success?

      parsed = response.parsed_response
      rows.concat(Array(parsed['data']).map { |row| map_row(row) })

      next_url = parsed.dig('paging', 'next')
      break if next_url.blank?

      url = next_url
      query = nil # a URL "next" já vem com todos os parâmetros
    end

    { configured: true, rows: rows }
  rescue StandardError => e
    Rails.logger.error "[Crm::MetaAdsReportService] #{e.message}"
    { configured: true, error: e.message, rows: [] }
  end

  private

  def insights_url
    "#{BASE_URI}/#{api_version}/act_#{ad_account_id}/insights"
  end

  def insights_query
    {
      level: 'ad',
      fields: 'ad_id,ad_name,adset_name,campaign_name,spend,impressions,reach,inline_link_clicks',
      time_range: { since: @since_date.iso8601, until: @until_date.iso8601 }.to_json,
      limit: 100,
      access_token: access_token
    }
  end

  def map_row(row)
    {
      ad_id: row['ad_id'],
      ad_name: row['ad_name'],
      adset_name: row['adset_name'],
      campaign_name: row['campaign_name'],
      spend: row['spend'].to_f,
      impressions: row['impressions'].to_i,
      reach: row['reach'].to_i,
      link_clicks: row['inline_link_clicks'].to_i
    }
  end

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
