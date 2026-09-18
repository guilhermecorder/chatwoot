# 🔐 Política de segurança de conteúdo (CSP) das páginas PÚBLICAS do CEVICO
# (landing pages + formulários; rodada 171). Terceiros que elas realmente
# usam: Google Tag Manager/Analytics, Pixel da Meta, Google Fonts. Tudo o
# mais é da própria origem. Aplicada em modo "só relatar" pelo concern
# Cevico::PublicSecurity — nada quebra; violações vão pro log.
module Cevico::PublicCsp
  THIRD_PARTY_SCRIPTS = %w[https://www.googletagmanager.com https://www.google-analytics.com https://connect.facebook.net].freeze
  ANALYTICS_CONNECT = %w[https://www.google-analytics.com https://*.google-analytics.com https://*.analytics.google.com
                         https://www.googletagmanager.com https://www.facebook.com https://connect.facebook.net].freeze

  def self.apply(policy)
    policy.default_src :self
    policy.base_uri :self
    policy.frame_ancestors :none
    policy.object_src :none
    policy.script_src :self, *THIRD_PARTY_SCRIPTS
    policy.style_src :self, :unsafe_inline, 'https://fonts.googleapis.com'
    policy.font_src :self, :data, 'https://fonts.gstatic.com'
    policy.img_src :self, :data, :https
    policy.media_src :self, :https
    policy.connect_src :self, *ANALYTICS_CONNECT
    policy.frame_src :self, 'https://www.googletagmanager.com', 'https://www.facebook.com', 'https://www.youtube.com'
    policy.form_action :self
    policy.report_uri '/webhooks/cevico/csp_report'
  end
end
