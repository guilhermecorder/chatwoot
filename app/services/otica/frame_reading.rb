# 🪞 LEITURA DA ARMAÇÃO PELA FOTO (08/11/2026, noite — pedido do Guilherme:
# "essa semana a gente cataloga o estoque com foto"). O mesmo Gemini que lê o
# rosto da cliente (Crm::MediaReadingService) olha a foto da armação e diz o
# FORMATO (retangular, gatinho, aviador…), o PÚBLICO (feminina, masculina,
# unissex), cor/material e 1 frase de visagismo. Catalogar vira: importar o
# CSV do SavWin → subir as fotos por lote → "Ler todas sem formato".
# É sugestão: fica gravada no produto e a equipe corrige no cadastro quando
# quiser. Sem formato o visagismo trata a armação como "aproximada" sempre.
module Otica::FrameReading
  module_function

  class Error < StandardError; end

  PROMPT = <<~TXT.freeze
    Você recebe a foto de UMA armação de óculos (ou óculos de sol) de uma ótica brasileira, de frente ou quase.
    Responda SOMENTE com um JSON válido:
    {"armacao": true/false (é mesmo um óculos/armação?),
     "formato": UMA palavra: retangular | quadrada | redonda | oval | gatinho | aviador | browline | geometrica | sem_aro | borboleta,
     "publico": feminina | masculina | unissex,
     "cor": a cor principal em 1 ou 2 palavras (ex.: "preto", "tartaruga", "dourado"),
     "material": acetato | metal | misto | outro,
     "frase": 1 frase simples (até 90 letras) sobre o estilo, útil pra oferecer a armação, sem termo técnico}
    Guia dos formatos: retangular = mais larga que alta, cantos retos; quadrada = quase tão alta quanto larga, cantos retos;
    redonda = círculo; oval = elipse suave; gatinho = cantos de cima puxados pra fora e pra cima; aviador = gota com ponte dupla;
    browline = aro grosso só em cima; geometrica = hexágono/octógono/ângulos; sem_aro = lente sem aro (três peças);
    borboleta = grande, mais larga embaixo. Sem comentários fora do JSON.
  TXT

  # lê a foto e GRAVA no produto o que estava vazio (force: true sobrescreve formato/público/frase)
  def read!(product, force: false)
    raise Error, 'Esse produto não é armação nem óculos de sol.' unless product.frame?
    raise Error, 'O produto ainda não tem foto.' unless product.photo.attached?

    api_key = Crm::MediaReadingService.api_key_for(product.account)
    raise Error, 'Configure a chave do Gemini em Integrações → IA.' if api_key.blank?

    reading = ask(product, api_key)
    raise Error, 'A foto não parece ser de uma armação.' if reading['armacao'] == false

    attrs = {}
    attrs[:frame_shape] = reading['formato'] if reading['formato'].present? && (force || product.frame_shape.blank?)
    attrs[:frame_fit] = reading['publico'] if reading['publico'].present? && (force || product.frame_fit.blank?)
    attrs[:visagismo_notes] = reading['frase'] if reading['frase'].present? && (force || product.visagismo_notes.blank?)
    attrs[:color] = reading['cor'] if reading['cor'].present? && product.color.blank?
    product.update!(attrs) if attrs.any?
    reading.merge('gravado' => attrs.keys.map(&:to_s))
  end

  # todas as armações ativas com foto e SEM formato (até `limit`): devolve [lidas, erros]
  def read_missing!(account, limit: 200)
    products = account.otica_products.active.where(kind: Otica::Product::FRAME_KINDS, frame_shape: '').with_attached_photo
                      .select { |p| p.photo.attached? }.first(limit)
    done = 0
    errors = []
    products.each do |p|
      read!(p)
      done += 1
    rescue Error, StandardError => e
      errors << "#{p.name}: #{e.message.truncate(80)}"
    end
    [done, errors]
  end

  def missing_count(account)
    account.otica_products.active.where(kind: Otica::Product::FRAME_KINDS, frame_shape: '').with_attached_photo.count { |p| p.photo.attached? }
  end

  def ask(product, api_key)
    bytes = product.photo.blob.open(&:read)
    mime = product.photo.content_type.presence || 'image/jpeg'
    body = {
      contents: [{ parts: [{ text: PROMPT }, { inline_data: { mime_type: mime, data: Base64.strict_encode64(bytes) } }] }],
      generationConfig: { temperature: 0.1, response_mime_type: 'application/json' }
    }
    response, = Crm::GeminiModels.post(account: product.account, api_key: api_key, body: body.to_json, timeout: 60)
    raise Error, "O Gemini respondeu com erro #{response.code}." unless response.success?

    text = response.parsed_response.is_a?(Hash) ? response.parsed_response.dig('candidates', 0, 'content', 'parts', 0, 'text') : nil
    normalize(parse(text))
  end

  def parse(text)
    raise Error, 'O Gemini não devolveu texto.' if text.blank?

    clean = text.to_s.gsub(/```(?:json)?/i, '').strip
    JSON.parse(clean[(clean.index('{') || 0)..(clean.rindex('}') || -1)])
  rescue JSON::ParserError
    raise Error, 'O Gemini respondeu fora do formato esperado.'
  end

  FITS = { 'feminina' => 'feminina', 'feminino' => 'feminina', 'masculina' => 'masculina', 'masculino' => 'masculina', 'unissex' => 'unissex' }.freeze
  def normalize(raw)
    raw = {} unless raw.is_a?(Hash)
    formato = raw['formato'].to_s.strip.downcase.tr('éê', 'ee').tr(' ', '_')
    formato = 'geometrica' if formato == 'geométrica'
    {
      'armacao' => raw['armacao'] != false,
      'formato' => (Otica::Visagismo::FRAME_SHAPES.key?(formato) ? formato : ''),
      'publico' => FITS[raw['publico'].to_s.strip.downcase] || '',
      'cor' => raw['cor'].to_s.strip.first(40),
      'material' => raw['material'].to_s.strip.downcase.first(20),
      'frase' => raw['frase'].to_s.strip.first(120)
    }
  end
end
