# 🔑 Conta de serviço do Google Cloud → chave de acesso (access token).
#
# O JSON da conta de serviço fica em Integrações → Google (google_ads_config
# ['service_account_json'], write-only — nunca volta para a tela). O mesmo
# JSON serve para o custo do GA4 (Crm::GoogleAdCostService) e para o Search
# Console (Cevico::SearchConsole): o que muda é o escopo pedido e onde o
# e-mail da conta foi adicionado (Leitor no GA4 / usuário no Search Console).
#
# Uso:
#   token, erro = Cevico::GoogleServiceAccount.access_token(json, SCOPE)
module Cevico::GoogleServiceAccount
  module_function

  TOKEN_URI = 'https://oauth2.googleapis.com/token'.freeze

  # devolve [token, nil] ou [nil, mensagem em português]
  def access_token(json, scope)
    creds = parse(json)
    return [nil, 'JSON da conta de serviço inválido (precisa de client_email e private_key)'] if creds.nil?

    response = HTTParty.post(
      TOKEN_URI,
      body: { grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: signed_jwt(creds, scope) },
      timeout: 15
    )
    return [response.parsed_response['access_token'], nil] if response.success?

    [nil, "Google recusou a conta de serviço (HTTP #{response.code})"]
  rescue OpenSSL::PKey::PKeyError
    [nil, 'A chave (private_key) do JSON da conta de serviço não abriu — cole o arquivo .json inteiro de novo']
  end

  # o e-mail da conta de serviço — é ele que a pessoa adiciona no Search
  # Console / GA4 (não é segredo; a chave privada é)
  def email(json)
    parse(json)&.dig('client_email')
  end

  def parse(json)
    creds = JSON.parse(json.to_s)
    creds.is_a?(Hash) && creds['client_email'].present? && creds['private_key'].present? ? creds : nil
  rescue JSON::ParserError
    nil
  end

  def signed_jwt(creds, scope)
    now = Time.now.to_i
    payload = { iss: creds['client_email'], scope: scope, aud: TOKEN_URI, iat: now, exp: now + 3600 }
    JWT.encode(payload, OpenSSL::PKey::RSA.new(creds['private_key']), 'RS256')
  end
end
