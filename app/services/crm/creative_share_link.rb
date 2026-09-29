# 🔗 Link SÓ DE LEITURA da análise de um criativo (item 287).
# Sem tabela nova: o link carrega um token FECHADO pelo sistema (cifrado e
# assinado com a chave do servidor) com a conta, o anúncio, o período e a
# validade (30 dias). Quem tem o link lê a análise daquele anúncio naquele
# período — e nada além disso; nem os números internos (conta, anúncio) dá
# para ler no endereço. Token adulterado ou vencido não abre.
module Crm::CreativeShareLink
  module_function

  TTL = 30.days
  PURPOSE = :creative_share
  PATH = '/criativos/analise'.freeze

  # finance: true = "com dados financeiros"; false (padrão) = sem nenhum valor em R$.
  # A escolha mora DENTRO do token: mexer no endereço não troca a versão.
  def generate(account:, ad_id:, since_date:, until_date:, finance: false)
    expires_at = TTL.from_now
    payload = [account.id, ad_id.to_s, since_date.iso8601, until_date.iso8601, expires_at.to_i, finance ? 1 : 0]
    token = verifier.encrypt_and_sign(payload, purpose: PURPOSE, expires_at: expires_at)
    { token: token, url: "#{base_url}#{PATH}/#{token}", expires_at: expires_at.iso8601, finance: finance ? true : false,
      finance_label: finance_label(finance),
      expires_label: expires_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m/%Y') }
  end

  def finance_label(finance)
    finance ? 'Com dados financeiros' : 'Sem dados financeiros'
  end

  # → { account_id:, ad_id:, since_date:, until_date:, expires_at:, finance: } ou nil
  # (link sem a marca de versão = SEM financeiro: na dúvida, mostra menos)
  def verify(token)
    data = verifier.decrypt_and_verify(token.to_s, purpose: PURPOSE)
    return nil unless data.is_a?(Array) && data.size.between?(5, 6)

    { account_id: data[0].to_i, ad_id: data[1].to_s, since_date: Date.iso8601(data[2].to_s),
      until_date: Date.iso8601(data[3].to_s), expires_at: Time.zone.at(data[4].to_i), finance: data[5].to_i == 1 }
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ArgumentError, TypeError
    nil
  end

  # cifra + assinatura (AES-256-GCM) com a chave do sistema; só letras e números
  # que cabem num endereço (sem + / =)
  def verifier
    key = Rails.application.key_generator.generate_key('cevico-creative-share', ActiveSupport::MessageEncryptor.key_len('aes-256-gcm'))
    ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm', url_safe: true, serializer: JSON)
  end

  # o link é para gente de fora abrir: sai pelo endereço do SISTEMA (FRONTEND_URL)
  def base_url
    ENV.fetch('FRONTEND_URL', '').chomp('/')
  end
end
