# 🔐 Segurança CEVICO (rodada 171, Fase C do plano de 30/08)
#
# 1. HSTS forte quando FORCE_SSL=true (o redirecionamento HTTPS já é do
#    Rails; aqui só o cabeçalho: 1 ano + subdomínios). Ligar FORCE_SSL só
#    depois de conferir que o proxy manda X-Forwarded-Proto — senão loop.
# 2. Cabeçalhos padrão em TODA resposta: Referrer-Policy (não vaza URL com
#    token pra terceiros) e Permissions-Policy (câmera/geolocalização
#    desligadas; microfone só na própria origem — ligações do item 167).
# 3. Gerador de nonce do CSP: as páginas públicas (CevicoPagesController /
#    CevicoFormsController) declaram a política por controller, em modo
#    "só relatar" — nada quebra; o que violaria vai para o log em
#    /webhooks/cevico/csp_report. Enforce vira uma linha depois.
Rails.application.configure do
  config.ssl_options = { hsts: { expires: 1.year, subdomains: true, preload: false } }

  config.action_dispatch.default_headers.merge!(
    'Referrer-Policy' => 'strict-origin-when-cross-origin',
    'Permissions-Policy' => 'camera=(), geolocation=(), microphone=(self), payment=()'
  )

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
