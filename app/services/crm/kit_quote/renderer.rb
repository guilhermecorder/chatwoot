# Pede os PDFs ao gerador da LIFE (o mesmo gerador aprovado: Python + Chrome, que roda
# como um serviço à parte porque o servidor do sistema não tem Chrome).
#
#   POST <url>/gerar   { proposta: {...}, justificativa: {...} }
#     → { arquivos: [{ nome:, tipo:, base64: }], avisos: [...] }
#
# Sem endereço configurado (config['gerador_pdf']['url']), devolve nil: a tela mostra os
# números e avisa que o PDF não pôde ser gerado neste servidor. Com config['gerador_pdf']['token'],
# manda a senha de serviço (o serviço só atende quem a apresenta).
# O serviço em si: docker/life-proposta (imagem ghcr.io/guilhermecorder/life-proposta-pdf).
class Crm::KitQuote::Renderer
  def initialize(config)
    @url = config.dig('gerador_pdf', 'url').to_s.chomp('/')
    @token = config.dig('gerador_pdf', 'token').to_s
  end

  def available?
    @url.present?
  end

  # Devolve { 'arquivos' => [...], 'avisos' => [...] } ou levanta NoAccess com o motivo.
  def render(documents)
    return nil unless available?

    status, data = Crm::KitQuote::Http.post("#{@url}/gerar", body: documents, headers: headers, timeout: 120)
    return data.slice('arquivos', 'avisos') if status == 200 && data.is_a?(Hash) && data['arquivos'].present?

    raise Crm::KitQuote::NoAccess, "O gerador de PDF não conseguiu montar os documentos: #{reason(status, data)}"
  end

  private

  def headers
    @token.present? ? { 'Authorization' => "Bearer #{@token}" } : {}
  end

  def reason(status, data)
    text = data.is_a?(Hash) ? data['erro'] : data.to_s.first(120)
    text.presence || "resposta #{status}"
  end
end
