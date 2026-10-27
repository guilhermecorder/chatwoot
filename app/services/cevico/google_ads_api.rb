# 🎯 item 371 (27/10): cliente MÍNIMO da API do Google Ads (REST) — o que o
# sistema precisa para devolver as conversões DIRETO ao Google Ads pelo
# código do clique (gclid/gbraid/wbraid), sem passar pelo GA4.
#
# Autenticação (uma das duas, em Integrações → Google):
#   • OAuth do Google Ads: client_id + client_secret + refresh_token (o jeito
#     oficial; o refresh token é gerado uma vez com a conta que acessa o Ads);
#   • conta de serviço REPRESENTANDO um e-mail do Workspace que acessa o Ads
#     (delegação em todo o domínio) — reaproveita o JSON que o GA4/Search
#     Console já usam.
# Mais o developer token (Central de API do Google Ads) e o ID da conta.
#
# Uso:
#   api = Cevico::GoogleAdsApi.new(config)
#   api.upload_click_conversions([{ gclid: ..., conversionAction: ... }])
class Cevico::GoogleAdsApi
  # versão da API — o Google aposenta cada uma ~1 ano depois de lançar
  # (v26 = outubro/2026). Dá para forçar outra em google_ads_config['api_version'].
  DEFAULT_VERSION = 'v26'.freeze
  HOST = 'https://googleads.googleapis.com'.freeze
  TOKEN_URI = 'https://oauth2.googleapis.com/token'.freeze
  SCOPE = 'https://www.googleapis.com/auth/adwords'.freeze
  TOKEN_CACHE_TTL = 50.minutes

  attr_reader :last_error

  def initialize(config)
    @config = config.is_a?(Hash) ? config : {}
  end

  # tudo que precisa para falar com o Google Ads está salvo?
  def configured?
    developer_token.present? && customer_id.present? && (oauth? || impersonation?)
  end

  def customer_id
    @config['customer_id'].to_s.gsub(/\D/, '')
  end

  def version
    @config['api_version'].to_s[/\Av\d{1,3}\z/] || DEFAULT_VERSION
  end

  def auth_mode
    return 'oauth' if oauth?
    return 'conta_de_servico' if impersonation?

    nil
  end

  # ── chamadas ─────────────────────────────────────────────────────────────

  # GAQL: devolve as linhas (results) ou nil (last_error preenchido)
  def search(query)
    response = post("customers/#{customer_id}/googleAds:search", { query: query })
    return nil if response.nil?

    Array(response['results'])
  end

  def mutate_conversion_actions(operations)
    post("customers/#{customer_id}/conversionActions:mutate", { operations: operations })
  end

  def mutate_conversion_custom_variables(operations)
    post("customers/#{customer_id}/conversionCustomVariables:mutate", { operations: operations })
  end

  # conversions: lista de ClickConversion (chaves no formato da API, camelCase)
  # devolve { ok:, results:, errors: [texto…] } — com partialFailure o Google
  # aceita as boas e explica cada ruim (CLICK_NOT_FOUND, EXPIRED_CLICK…)
  def upload_click_conversions(conversions, validate_only: false)
    body = { conversions: conversions, partialFailure: true, validateOnly: validate_only }
    response = post("customers/#{customer_id}:uploadClickConversions", body)
    return { ok: false, errors: [last_error] } if response.nil?

    errors = partial_failure_errors(response)
    { ok: errors.empty?, results: Array(response['results']), errors: errors, job_id: response['jobId'] }
  end

  # ── autenticação ─────────────────────────────────────────────────────────

  def access_token
    @access_token ||= Rails.cache.fetch(token_cache_key, expires_in: TOKEN_CACHE_TTL) { fetch_access_token }
  rescue StandardError => e
    @last_error = scrub(e.message)
    nil
  end

  private

  def developer_token
    @config['developer_token'].to_s.strip
  end

  def oauth?
    %w[oauth_client_id oauth_client_secret oauth_refresh_token].all? { |k| @config[k].present? }
  end

  def impersonation?
    @config['ads_impersonate_email'].present? && Cevico::GoogleServiceAccount.parse(@config['service_account_json']).present?
  end

  def token_cache_key
    seed = oauth? ? @config['oauth_refresh_token'] : "#{@config['ads_impersonate_email']}#{@config['service_account_json'].to_s[0, 200]}"
    "cevico/google_ads_token/#{Digest::SHA256.hexdigest(seed.to_s)[0, 24]}"
  end

  def fetch_access_token
    token, error = oauth? ? oauth_token : impersonated_token
    raise error if token.blank?

    token
  end

  def oauth_token
    response = HTTParty.post(TOKEN_URI, body: {
                               grant_type: 'refresh_token', client_id: @config['oauth_client_id'],
                               client_secret: @config['oauth_client_secret'], refresh_token: @config['oauth_refresh_token']
                             }, timeout: 15)
    return [response.parsed_response['access_token'], nil] if response.success? && response.parsed_response['access_token'].present?

    detail = response.parsed_response.is_a?(Hash) ? response.parsed_response['error_description'] || response.parsed_response['error'] : nil
    [nil, "Google recusou o acesso OAuth do Ads (HTTP #{response.code}#{detail.present? ? ": #{detail}" : ''}) — gere um refresh token novo"]
  end

  # conta de serviço com delegação: o JWT leva `sub` = o e-mail representado
  def impersonated_token
    creds = Cevico::GoogleServiceAccount.parse(@config['service_account_json'])
    now = Time.now.to_i
    payload = { iss: creds['client_email'], sub: @config['ads_impersonate_email'].to_s.strip, scope: SCOPE,
                aud: TOKEN_URI, iat: now, exp: now + 3600 }
    assertion = JWT.encode(payload, OpenSSL::PKey::RSA.new(creds['private_key']), 'RS256')
    response = HTTParty.post(TOKEN_URI, body: { grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: assertion }, timeout: 15)
    return [response.parsed_response['access_token'], nil] if response.success? && response.parsed_response['access_token'].present?

    [nil, "Google recusou a conta de serviço para o Ads (HTTP #{response.code}) — confira a delegação em todo o domínio " \
          "para o escopo #{SCOPE} e se #{@config['ads_impersonate_email']} acessa a conta do Ads"]
  end

  # ── transporte ───────────────────────────────────────────────────────────

  def post(path, body)
    token = access_token
    return nil if token.blank?

    response = HTTParty.post("#{HOST}/#{version}/#{path}", headers: headers(token), body: body.to_json, timeout: 20)
    return response.parsed_response.is_a?(Hash) ? response.parsed_response : {} if response.success?

    @last_error = error_message(response)
    nil
  rescue StandardError => e
    @last_error = scrub(e.message)
    nil
  end

  def headers(token)
    h = { 'Authorization' => "Bearer #{token}", 'developer-token' => developer_token, 'Content-Type' => 'application/json' }
    login = @config['login_customer_id'].to_s.gsub(/\D/, '')
    h['login-customer-id'] = login if login.present?
    h
  end

  # a resposta de erro do Google Ads vem com a lista de erros dentro de
  # error.details[].errors[] — o errorCode é um hash { tipo => CODIGO }
  def error_message(response)
    parsed = response.parsed_response
    unless parsed.is_a?(Hash)
      parsed = begin
        JSON.parse(parsed.to_s)
      rescue JSON::ParserError
        {}
      end
    end
    errors = Array(parsed.dig('error', 'details')).flat_map { |d| Array(d['errors']) }
    text = errors.map { |e| describe_error(e) }.compact_blank.uniq.join('; ')
    text = parsed.dig('error', 'message').to_s if text.blank?
    scrub("Google Ads recusou (HTTP #{response.code}#{text.present? ? ": #{text}" : ''})")
  end

  def partial_failure_errors(response)
    details = Array(response.dig('partialFailureError', 'details'))
    errors = details.flat_map { |d| Array(d['errors']) }.map { |e| describe_error(e) }.compact_blank
    errors = [response.dig('partialFailureError', 'message').to_s] if errors.empty? && response['partialFailureError'].present?
    errors.uniq
  end

  def describe_error(err)
    code = err['errorCode'].is_a?(Hash) ? err['errorCode'].values.first : nil
    field = Array(err.dig('location', 'fieldPathElements')).filter_map { |f| f['fieldName'] }.join('.')
    [code, err['message'].to_s.presence, (field.present? ? "(#{field})" : nil)].compact.join(' ')
  end

  # nunca devolver token/segredo (erro de rede pode trazer a URL ou o corpo)
  def scrub(message)
    text = message.to_s
    %w[developer_token oauth_client_secret oauth_refresh_token].each do |k|
      text = text.gsub(@config[k].to_s, '[segredo]') if @config[k].to_s.length > 6
    end
    text
  end
end
