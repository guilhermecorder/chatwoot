# 🪞🎨 A IMAGEM DA PROVA VIRTUAL (08/11/2026): foto da cliente + foto da
# armação → foto da cliente USANDO a armação. Roda no Gemini (família
# "Nano Banana", geração/edição de imagem), com a MESMA chave que já lê os
# áudios e fotos (Integrações → IA → chave do Gemini). Nada de serviço novo.
#
# Como funciona: as duas imagens vão no pedido (a selfie primeiro, a armação
# depois) com uma instrução firme: não mude a pessoa (rosto, pele, cabelo,
# fundo), só coloque a armação no rosto dela, do tamanho certo, encaixada no
# nariz e nas orelhas. A resposta volta com a imagem em base64.
#
# Dois caminhos (o Google mudou a porta de entrada em 2026): o novo
# `/v1beta/interactions` primeiro; se o modelo/endpoint responder 404/400 de
# "não existe", cai no `generateContent` clássico com responseModalities IMAGE.
# O modelo é configurável (ai_config['gemini_image_model']) e, se o Google
# aposentar um, a lista abaixo tenta o próximo (como em Crm::GeminiModels).
#
# Custo (lista oficial, nov/2026, por imagem ~1K): Nano Banana 2.1 ≈ US$ 0,067 ·
# 3.1 Flash ≈ US$ 0,067 · Pro ≈ US$ 0,134 · 2.5 Flash ≈ US$ 0,039. Gravado em
# Crm::AiUsage (agent_key 'visagismo') para aparecer no "Gasto da IA".
class Otica::TryOnImage
  AGENT_KEY = 'visagismo'.freeze
  CONFIG_KEY = 'gemini_image_model'.freeze
  DEFAULT_MODEL = 'gemini-nano-banana-2.1'.freeze
  FALLBACKS = %w[gemini-nano-banana-2.1 gemini-3.1-flash-image gemini-3-pro-image gemini-2.5-flash-image].freeze
  PRICE_PER_IMAGE = {
    'gemini-nano-banana-2.1' => 0.067, 'gemini-3.1-flash-image' => 0.067, 'gemini-3.1-flash-lite-image' => 0.034,
    'gemini-3-pro-image' => 0.134, 'gemini-2.5-flash-image' => 0.039
  }.freeze
  INTERACTIONS_URL = 'https://generativelanguage.googleapis.com/v1beta/interactions'.freeze
  GENERATE_URL = 'https://generativelanguage.googleapis.com/v1beta/models/%<model>s:generateContent'.freeze
  TIMEOUT = 120
  MAX_INPUT_BYTES = 8.megabytes

  # instrução em inglês (os modelos de imagem seguem melhor); o que NÃO pode
  # mudar vem repetido de propósito
  PROMPT = <<~TXT.freeze
    Virtual try-on for an eyewear store. The FIRST image is a customer's photo. The SECOND image is a pair of
    eyeglasses frames from the store (%<frame>s).
    Put these exact frames on the customer's face, as a real photo taken in the same moment:
    - keep the person EXACTLY as she/he is: same face, skin, eyes, expression, hair, makeup, clothes, pose, lighting and background;
    - if the person is already wearing glasses, replace them with the new frames;
    - the frames must be the SAME model, shape, color and material as the second image, at a realistic size for this face,
      resting on the nose bridge and reaching the ears, with natural shadows and reflections, lenses clear and transparent;
    - photorealistic, no text, no logo, no watermark, no extra objects, no change of framing or crop.
    Output only the edited photo.
  TXT

  class Error < StandardError
    attr_reader :code

    def initialize(message, code = nil)
      super(message)
      @code = code.to_i
    end

    def transient?
      code == 408 || code == 429 || code >= 500
    end
  end

  def self.configured?(account)
    Crm::MediaReadingService.configured?(account)
  end

  def self.chain(account)
    configured = CrmSetting.find_by(account: account)&.ai_config&.dig(CONFIG_KEY).to_s.strip.presence
    [configured, *FALLBACKS].compact.uniq
  end

  def initialize(account)
    @account = account
    @api_key = Crm::MediaReadingService.api_key_for(account)
  end

  # selfie/frame: bytes; devolve { bytes:, mime:, model: } ou levanta Otica::TryOnImage::Error
  def generate(selfie:, selfie_mime:, frame:, frame_mime:, product:) # rubocop:disable Metrics/AbcSize
    raise Error, 'Configure a chave do Gemini em Integrações → IA.' if @api_key.blank?
    raise Error, 'Foto grande demais (até 8 MB).' if selfie.bytesize > MAX_INPUT_BYTES || frame.bytesize > MAX_INPUT_BYTES

    prompt = format(PROMPT, frame: describe(product))
    last_error = nil
    self.class.chain(@account).each do |model|
      result = try_model(model, prompt, selfie, selfie_mime, frame, frame_mime)
      record_usage(model, result[:usage])
      return { bytes: result[:bytes], mime: result[:mime], model: model }
    rescue Error => e
      last_error = e
      # modelo fora do ar / não existe: tenta o próximo; erro de verdade: para
      raise e unless model_gone?(e)

      Rails.logger.warn("[Otica::TryOnImage] modelo #{model} indisponível (#{e.code}): #{e.message.truncate(100)} — tentando o próximo")
    end
    raise(last_error || Error.new('Nenhum modelo de imagem respondeu.'))
  end

  private

  # "Ray-Ban Wayfarer, preta, acetato, formato quadrada"
  def describe(product)
    parts = [product.brand, product.line, product.model].map(&:to_s).map(&:strip).compact_blank.join(' ')
    extras = [product.color.presence, product.lens_material.presence, (product.frame_shape.present? ? "#{Otica::Visagismo.frame_label(product.frame_shape)} shape" : nil)].compact
    [parts.presence || product.name, *extras].join(', ')
  end

  def try_model(model, prompt, selfie, selfie_mime, frame, frame_mime)
    via_interactions(model, prompt, selfie, selfie_mime, frame, frame_mime)
  rescue Error => e
    raise e unless endpoint_unsupported?(e)

    Rails.logger.info("[Otica::TryOnImage] interactions indisponível para #{model} (#{e.code}); usando generateContent")
    via_generate_content(model, prompt, selfie, selfie_mime, frame, frame_mime)
  end

  # ── caminho 1: Interactions API ─────────────────────────────────────────
  def via_interactions(model, prompt, selfie, selfie_mime, frame, frame_mime)
    body = {
      model: model,
      input: [
        { type: 'image', mime_type: selfie_mime, data: Base64.strict_encode64(selfie) },
        { type: 'image', mime_type: frame_mime, data: Base64.strict_encode64(frame) },
        { type: 'text', text: prompt }
      ],
      response_format: { type: 'image', aspect_ratio: '1:1' }
    }
    response = HTTParty.post(INTERACTIONS_URL, headers: { 'Content-Type' => 'application/json', 'x-goog-api-key' => @api_key },
                                               body: body.to_json, timeout: TIMEOUT)
    raise Error.new("Gemini (interactions) respondeu #{response.code}: #{error_message(response)}", response.code) unless response.success?

    parsed = response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
    image = find_image(parsed)
    raise Error, 'O Gemini não devolveu imagem (interactions).' if image.nil?

    usage = parsed['usage'].is_a?(Hash) ? parsed['usage'] : {}
    { bytes: Base64.decode64(image['data'].to_s), mime: image['mime_type'].presence || 'image/png',
      usage: { input: usage['total_input_tokens'].to_i, output: usage['total_output_tokens'].to_i } }
  end

  # ── caminho 2: generateContent clássico ─────────────────────────────────
  def via_generate_content(model, prompt, selfie, selfie_mime, frame, frame_mime)
    body = {
      contents: [{ parts: [
        { text: prompt },
        { inline_data: { mime_type: selfie_mime, data: Base64.strict_encode64(selfie) } },
        { inline_data: { mime_type: frame_mime, data: Base64.strict_encode64(frame) } }
      ] }],
      generationConfig: { responseModalities: %w[IMAGE], temperature: 0.2 }
    }
    response = HTTParty.post(format(GENERATE_URL, model: model), query: { key: @api_key },
                                                                  headers: { 'Content-Type' => 'application/json' }, body: body.to_json, timeout: TIMEOUT)
    raise Error.new("Gemini (generateContent) respondeu #{response.code}: #{error_message(response)}", response.code) unless response.success?

    parsed = response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
    parts = Array(parsed.dig('candidates', 0, 'content', 'parts'))
    inline = parts.filter_map { |p| p['inlineData'] || p['inline_data'] }.find { |d| d['data'].present? }
    raise Error, 'O Gemini não devolveu imagem (generateContent).' if inline.nil?

    usage = parsed['usageMetadata'] || {}
    { bytes: Base64.decode64(inline['data'].to_s), mime: (inline['mimeType'] || inline['mime_type']).presence || 'image/png',
      usage: { input: usage['promptTokenCount'].to_i, output: usage['candidatesTokenCount'].to_i } }
  end

  # procura o primeiro bloco {type: image, data: …} em qualquer lugar da resposta
  # (steps[].content[], output[], output_image…) — o formato mudou mais de uma vez em 2026
  def find_image(node)
    case node
    when Hash
      return node if node['type'].to_s == 'image' && node['data'].present?
      return node['output_image'] if node['output_image'].is_a?(Hash) && node['output_image']['data'].present?

      node.each_value do |v|
        found = find_image(v)
        return found if found
      end
    when Array
      node.each do |v|
        found = find_image(v)
        return found if found
      end
    end
    nil
  end

  def error_message(response)
    parsed = response.parsed_response
    (parsed.is_a?(Hash) ? parsed.dig('error', 'message') : parsed).to_s.truncate(160)
  end

  GONE_MESSAGE = Crm::GeminiModels::GONE_MESSAGE

  # 404, ou 400 falando do modelo: vale tentar o próximo modelo
  def model_gone?(error)
    return true if error.code == 404
    return false unless error.code == 400

    error.message.match?(/model/i) && error.message.match?(GONE_MESSAGE)
  end

  # endpoint novo não existe / não aceita este modelo → caminho clássico
  def endpoint_unsupported?(error)
    [404, 400, 405, 501].include?(error.code)
  end

  def record_usage(model, usage)
    price = PRICE_PER_IMAGE[model] || PRICE_PER_IMAGE[DEFAULT_MODEL]
    Crm::AiUsage.create!(account: @account, agent_key: AGENT_KEY, model: model,
                         input_tokens: usage[:input].to_i, output_tokens: usage[:output].to_i, cost_usd: price.round(6))
  rescue StandardError => e
    Rails.logger.warn("[Crm::AiUsage] falhou ao registrar a prova virtual: #{e.message}")
  end
end
