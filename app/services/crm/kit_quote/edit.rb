# ✏️ Editar um orçamento já gerado (LIFE · Guilherme, 13/11/2026: "poder editar o nome ou qualquer coisa assim que a
# proposta automática já gerou"). Troca os dados de apresentação — nome do cliente, cidade/UF, tipo de telhado e
# quantos dias o orçamento vale — no payload guardado e gera os PDFs de novo (proposta, justificativa e resumo).
# Os números (preço, DRE, kit) não mudam aqui: para mudar o preço, gere de novo no Gerador de proposta.
class Crm::KitQuote::Edit
  Result = Struct.new(:ok, :aviso, keyword_init: true)

  def initialize(quote, changes, renderer)
    @quote = quote
    @changes = changes.to_h.transform_keys(&:to_s)
    @renderer = renderer
  end

  def call
    payload = @quote.payload.deep_dup
    apply_client(payload)
    apply_roof(payload)
    apply_validity(payload)
    files, aviso = render(payload)
    Crm::Quote.transaction do
      @quote.update!(payload: payload)
      if files.present?
        @quote.files.purge
        @quote.attach_rendered(files)
      end
    end
    Result.new(ok: true, aviso: aviso)
  end

  # Valores atuais que a tela mostra no formulário.
  def self.current(quote)
    p = quote.payload['proposta'] || {}
    {
      'nome' => p.dig('cliente', 'nome').presence || quote.payload.dig('cliente', 'nome'),
      'cidade' => p.dig('cliente', 'cidade').presence || quote.payload.dig('cliente', 'cidade'),
      'uf' => p.dig('cliente', 'uf').presence || quote.payload.dig('cliente', 'uf'),
      'telhado' => p.dig('telhado', 'tipo'),
      'validade_dias' => (p.dig('proposta', 'validade_dias') || 7).to_i
    }
  end

  private

  def text(key, max)
    @changes[key].to_s.squish.first(max).presence
  end

  def apply_client(payload)
    given = { 'nome' => text('nome', 80), 'cidade' => text('cidade', 60), 'uf' => text('uf', 2)&.upcase }.compact
    return if given.empty?

    cliente = ((payload['proposta'] ||= {})['cliente'] ||= {})
    cliente.merge!(given)
    (payload['cliente'] ||= {}).merge!(given)
    apply_justification(payload['justificativa'], cliente, given)
  end

  def apply_justification(justificativa, cliente, given)
    return unless justificativa.is_a?(Hash)

    justificativa['cliente'] = cliente['nome'] if given['nome']
    justificativa['cidade'] = [cliente['cidade'], cliente['uf']].compact_blank.join('/') if given['cidade'] || given['uf']
  end

  def apply_roof(payload)
    roof = text('telhado', 40)
    ((payload['proposta'] ||= {})['telhado'] ||= {})['tipo'] = roof if roof
  end

  def apply_validity(payload)
    return if @changes['validade_dias'].blank?

    days = @changes['validade_dias'].to_i.clamp(1, 30)
    ((payload['proposta'] ||= {})['proposta'] ||= {})['validade_dias'] = days
  end

  # [arquivos, aviso]: sem gerador de PDF (ou se ele falhar), os dados ficam salvos e os PDFs antigos continuam.
  def render(payload)
    return [nil, 'Os dados foram salvos, mas o gerador de PDF não está ligado: os PDFs continuam os de antes.'] unless @renderer.available?

    result = @renderer.render(payload.slice('proposta', 'justificativa'))
    [result['arquivos'], nil]
  rescue Crm::KitQuote::NoAccess => e
    [nil, "Os dados foram salvos, mas os PDFs não saíram de novo: #{e.message}"]
  end
end
