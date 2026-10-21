# 📥 FOTO DIÁRIA do Google por campanha (item 352): lê do GA4, por DIA e por
# campanha do Google Ads, o custo, os cliques e as impressões (mesma conta de
# serviço do custo automático — sem developer token). Grava em
# cevico_campaign_days. A primeira carga pega 365 dias (a "nossa média" de 360
# dias precisa disso); as seguintes refazem só os últimos dias (o Google
# reprocessa o custo recente).
#
# Simulação local: google_ads_config['service_account_json'] == 'simulate' ou
# CEVICO_GOOGLE_SIMULATE=1 → três campanhas fictícias, determinísticas.
class Cevico::CampaignAgent::GoogleSync < Crm::GoogleAdCostService
  FIRST_DAYS = 365
  DEFAULT_DAYS = 3
  ROW_LIMIT = 100_000
  STATE_KEY = 'campaign_days_sync'.freeze

  SIMULATED = [
    { id: '9001', name: '[Search] Cirurgia de miopia SP', base_cost: 420.0, cpc: 6.5 },
    { id: '9002', name: '[GD] Refrativa · cenas do dia a dia', base_cost: 260.0, cpc: 1.4 },
    { id: '9003', name: '[Search] Catarata trifocal', base_cost: 180.0, cpc: 7.2 }
  ].freeze

  def initialize(account:, days: nil, until_date: Date.current)
    @days = days
    super(account: account, since_date: until_date - (window_days - 1), until_date: until_date)
  end

  def self.state(account)
    (CrmSetting.find_by(account: account)&.google_ads_config || {})[STATE_KEY] || {}
  end

  def simulate?
    ENV['CEVICO_GOOGLE_SIMULATE'] == '1' || config['service_account_json'].to_s == 'simulate'
  end

  def configured?
    simulate? || super
  end

  def call
    return { configured: false } unless configured?

    rows = simulate? ? simulated_rows : fetch_rows
    return rows if rows.is_a?(Hash) # erro

    store(rows)
    write_state('synced_at' => Time.current.iso8601, 'rows' => rows.size, 'since' => @since_date.iso8601,
                'until' => @until_date.iso8601, 'last_error' => nil)
    { configured: true, rows: rows.size, since: @since_date, until: @until_date }
  rescue StandardError => e
    Rails.logger.error "[CEVICO campanhas] Google: #{e.class}: #{e.message}"
    write_state('last_error' => e.message)
    { configured: true, error: e.message }
  end

  private

  def window_days
    @window_days ||= (@days || (self.class.state(@account)['synced_at'].present? ? DEFAULT_DAYS : FIRST_DAYS)).to_i.clamp(1, 400)
  end

  def fetch_rows
    token = access_token
    return { configured: true, error: @auth_error || 'Falha na autenticação com o Google' } if token.blank?

    response = HTTParty.post(
      "#{DATA_API}/properties/#{property_id}:runReport",
      headers: { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' },
      body: request_body.to_json, timeout: 60
    )
    return { configured: true, error: extract_error(response) } unless response.success?

    parse(response.parsed_response)
  end

  def request_body
    {
      dateRanges: [{ startDate: @since_date.iso8601, endDate: @until_date.iso8601 }],
      dimensions: [{ name: 'date' }, { name: 'sessionGoogleAdsCampaignId' }, { name: 'sessionGoogleAdsCampaignName' }],
      metrics: [{ name: 'advertiserAdCost' }, { name: 'advertiserAdClicks' }, { name: 'advertiserAdImpressions' }],
      limit: ROW_LIMIT
    }
  end

  # [{ date:, id:, name:, spend:, clicks:, impressions: }] — sem "(not set)" e sem linha vazia
  def parse(payload) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    Array(payload['rows']).filter_map do |row|
      dims = Array(row['dimensionValues']).map { |d| d['value'].to_s.sub('(not set)', '') }
      mets = Array(row['metricValues']).pluck('value')
      next if dims[1].blank?

      item = { date: Date.strptime(dims[0], '%Y%m%d'), id: dims[1], name: dims[2].to_s,
               spend: mets[0].to_f.round(2), clicks: mets[1].to_i, impressions: mets[2].to_i }
      item if item[:spend].positive? || item[:clicks].positive? || item[:impressions].positive?
    rescue ArgumentError
      nil
    end
  end

  def simulated_rows
    (@since_date..@until_date).flat_map do |day|
      SIMULATED.map do |c|
        seed = ((c[:id].to_i * 7) + day.yday) % 13
        wave = 1.0 + ((seed - 6) / 30.0)
        wave *= 0.55 if day.saturday? || day.sunday?
        spend = (c[:base_cost] * wave).round(2)
        clicks = (spend / c[:cpc]).round
        { date: day, id: c[:id], name: c[:name], spend: spend, clicks: clicks, impressions: clicks * (c[:cpc] > 3 ? 18 : 60) }
      end
    end
  end

  def store(rows)
    now = Time.current
    records = rows.map do |r|
      { account_id: @account.id, channel: 'google', campaign_id: r[:id], campaign_name: r[:name], date: r[:date],
        spend: r[:spend], clicks: r[:clicks], impressions: r[:impressions], created_at: now, updated_at: now }
    end
    records.each_slice(500) do |slice|
      Crm::CampaignDay.upsert_all(slice, unique_by: [:account_id, :channel, :campaign_id, :date]) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def write_state(patch)
    settings = CrmSetting.find_by(account: @account)
    return unless settings

    Cevico::SettingMerge.merge_key!(settings, :google_ads_config, STATE_KEY) { |h| (h || {}).merge(patch) }
  end
end
