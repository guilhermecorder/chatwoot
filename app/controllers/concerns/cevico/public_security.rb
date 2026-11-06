# 🔐 Cabeçalhos de segurança das páginas PÚBLICAS do CEVICO (rodada 171):
# CSP em modo "só relatar" (scripts inline levam nonce; violações vão pro
# log via /webhooks/cevico/csp_report) + a página não pode ser embutida em
# iframe de outro site. Incluído em CevicoPagesController e CevicoFormsController.
module Cevico::PublicSecurity
  extend ActiveSupport::Concern

  included do
    content_security_policy { |policy| Cevico::PublicCsp.apply(policy) }
    content_security_policy_report_only
    # 24/10 (Ver na página): a biblioteca, no MESMO domínio, abre a página num
    # iframe para desenhar o mapa de calor por cima — só nesse caso, só da própria origem
    after_action { response.headers['X-Frame-Options'] = same_origin_frame? ? 'SAMEORIGIN' : 'DENY' }
  end

  private

  def same_origin_frame?
    false
  end
end
