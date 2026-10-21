# Recebe os relatórios de violação do CSP das páginas públicas (modo "só
# relatar") e escreve no log — é como descobrimos o que quebraria antes
# de ligar a política pra valer. Nunca grava no banco; nunca responde erro.
class Webhooks::CevicoCspReportsController < ActionController::API
  MAX_BODY = 8_192

  def create
    body = request.raw_post.to_s.byteslice(0, MAX_BODY)
    Rails.logger.warn("[CEVICO csp] #{request.ip} #{body.gsub(/\s+/, ' ')}")
    head :no_content
  end
end
