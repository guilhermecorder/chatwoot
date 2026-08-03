# Custo dos anúncios do Google SEM developer token: lê o gasto pela API de
# dados do GA4 (métrica advertiserAdCost), que enxerga o investimento da
# conta do Google Ads VINCULADA à propriedade. Autentica com uma conta de
# serviço do Google Cloud (JSON colado em Integrações → Google) via JWT —
# a mesma conta de serviço precisa estar adicionada como "Leitor" na
# propriedade do GA4. Alimenta o investimento automático do Dashboard CRM.
class Crm::GoogleAdCostService
  TOKEN_URI = 'https://oauth2.googleapis.com/token'.freeze
  SCOPE = 'https://www.googleapis.com/auth/analytics.readonly'.freeze
  DATA_API = 'https://analyticsdata.googleapis.com/v1beta'.freeze

  def initialize(account:, since_date:, until_date: Date.current)
    @account = account
    @since_date = since_date
    @until_date = until_date
  end

  def call
    return { configured: false } unless configured?

    token = access_token
    return { configured: true, error: @auth_error || 'Falha na autenticação com o Google' } if token.blank?

    fetch_cost(token)
  rescue StandardError => e
    Rails.logger.error "[Crm::GoogleAdCostService] #{e.class}: #{e.message}"
    { configured: true, error: e.message }
  end

  def configured?
    property_id.present? && config['service_account_json'].present?
  end

  private

  def config
    @config ||= CrmSetting.find_by(account: @account)&.google_ads_config || {}
  end

  def property_id
    config['ga4_property_id'].to_s.gsub(/\D/, '')
  end

  def credentials
    @credentials ||= JSON.parse(config['service_account_json'].to_s)
  rescue JSON::ParserError
    nil
  end

  # troca o JWT assinado pela conta de serviço por um access token do Google
  def access_token
    creds = credentials
    if creds.nil? || creds['client_email'].blank? || creds['private_key'].blank?
      @auth_error = 'JSON da conta de serviço inválido (precisa de client_email e private_key)'
      return nil
    end

    response = HTTParty.post(
      TOKEN_URI,
      body: { grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: signed_jwt(creds) },
      timeout: 15
    )
    return response.parsed_response['access_token'] if response.success?

    @auth_error = "Google recusou a conta de serviço (HTTP #{response.code})"
    nil
  end

  def signed_jwt(creds)
    now = Time.now.to_i
    payload = { iss: creds['client_email'], scope: SCOPE, aud: TOKEN_URI, iat: now, exp: now + 3600 }
    JWT.encode(payload, OpenSSL::PKey::RSA.new(creds['private_key']), 'RS256')
  end

  def fetch_cost(token)
    response = HTTParty.post(
      "#{DATA_API}/properties/#{property_id}:runReport",
      headers: { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' },
      body: {
        dateRanges: [{ startDate: @since_date.iso8601, endDate: @until_date.iso8601 }],
        metrics: [{ name: 'advertiserAdCost' }]
      }.to_json,
      timeout: 15
    )
    return { configured: true, error: extract_error(response) } unless response.success?

    cost = response.parsed_response.dig('rows', 0, 'metricValues', 0, 'value').to_f
    { configured: true, cost: cost.round(2) }
  end

  def extract_error(response)
    message = response.parsed_response&.dig('error', 'message').presence || "HTTP #{response.code}"
    # o erro mais comum: faltou dar acesso de Leitor à conta de serviço no GA4
    message += ' — confira se o e-mail da conta de serviço foi adicionado como Leitor na propriedade do GA4' if response.code == 403
    message
  end
end
