# 🔗 Link SÓ DE LEITURA da análise de um criativo (item 287).
# O que o link mostra mora num token FECHADO pelo sistema (cifrado e assinado
# com a chave do servidor): a conta, o anúncio, o período e a validade (30
# dias). Quem tem o link lê a análise daquele anúncio naquele período — e nada
# além disso. Token adulterado ou vencido não abre.
# 🔗 item 302 (30/09): o endereço ficou CURTO — /c/<código de 10 letras>. O
# token fica guardado (Crm::ShortLink) e o código é só o apelido dele. Os links
# compridos antigos (/criativos/analise/<token>) continuam abrindo.
module Crm::CreativeShareLink
  module_function

  TTL = 30.days
  PURPOSE = :creative_share
  PATH = '/criativos/analise'.freeze
  SHORT_PATH = '/c'.freeze
  KIND = 'creative_share'.freeze

  # finance: true = "com dados financeiros"; false (padrão) = sem nenhum valor em R$.
  # A escolha mora DENTRO do token: mexer no endereço não troca a versão.
  def generate(account:, ad_id:, since_date:, until_date:, finance: false)
    expires_at = TTL.from_now
    payload = [account.id, ad_id.to_s, since_date.iso8601, until_date.iso8601, expires_at.to_i, finance ? 1 : 0]
    token = verifier.encrypt_and_sign(payload, purpose: PURPOSE, expires_at: expires_at)
    short = Crm::ShortLink.shorten!(account: account, kind: KIND, token: token, expires_at: expires_at)
    { token: token, code: short.code, url: "#{base_url}#{SHORT_PATH}/#{short.code}", expires_at: expires_at.iso8601, finance: finance ? true : false,
      finance_label: finance_label(finance),
      expires_label: expires_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m/%Y') }
  end

  # período do link (rodada 4): "Este ano" é o padrão — a análise é do ano
  PERIODS = { 'year' => 'Este ano', 'last90' => 'Últimos 90 dias', 'screen' => 'O período da tela' }.freeze

  # → [since, until, chave] — `screen` usa as datas que a tela mandou
  def period_for(key, screen_since:, screen_until:, today: Date.current)
    case key.to_s
    when 'screen' then [screen_since, screen_until, 'screen']
    when 'last90' then [today - 89, today, 'last90']
    else [today.beginning_of_year, today, 'year']
    end
  end

  def finance_label(finance)
    finance ? 'Com dados financeiros' : 'Sem dados financeiros'
  end

  # código curto do endereço → o token guardado (nil = não existe ou venceu)
  def token_for(code)
    Crm::ShortLink.token_for(code, kind: KIND)
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
