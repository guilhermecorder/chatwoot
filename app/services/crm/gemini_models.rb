# 🤖 item 340 (13/10): a IA parou de responder quem manda ÁUDIO. Uma das
# causas possíveis: o Google aposenta modelos do Gemini de tempos em tempos e
# o "gemini-2.5-flash" estava fixo no código — quando ele sai do ar, toda
# transcrição falha. Agora o modelo é configurável (ai_config
# ['gemini_media_model'], Integrações → IA) e, se o Google responder que o
# modelo não existe mais (404, ou 400 "not found/deprecated"), a chamada tenta
# o próximo da lista sozinha. O modelo fora do ar fica anotado por 6 h para não
# gastar uma chamada a cada áudio. Usado pela leitura de áudio/imagem dos
# pacientes, pela transcrição dos vídeos dos criativos e das ligações.
module Crm::GeminiModels
  module_function

  DEFAULT = 'gemini-2.5-flash'.freeze
  FALLBACKS = %w[gemini-2.5-flash gemini-flash-latest gemini-2.0-flash].freeze
  URL = 'https://generativelanguage.googleapis.com/v1beta/models/%<model>s:generateContent'.freeze
  CONFIG_KEY = 'gemini_media_model'.freeze
  GONE_KEY = 'cevico:gemini:modelo_fora:%<model>s'.freeze
  GONE_TTL = 6.hours
  # 400 que quer dizer "esse modelo não existe/não serve mais" (não é áudio ruim)
  GONE_MESSAGE = /not found|deprecat|retired|no longer (available|supported)|is not supported|unsupported model|unknown model/i

  def url(model)
    format(URL, model: model)
  end

  # o configurado primeiro, depois a lista fixa; os anotados como fora do ar
  # ficam de fora (se todos estiverem, tenta a lista inteira de novo)
  def chain(account)
    configured = CrmSetting.find_by(account: account)&.ai_config&.dig(CONFIG_KEY).to_s.strip.presence
    list = [configured, *FALLBACKS].compact.uniq
    alive = list.reject { |model| gone?(model) }
    alive.presence || list
  end

  # POST no generateContent com a troca automática de modelo.
  # Devolve [response, modelo_usado].
  def post(account:, api_key:, body:, timeout:)
    models = chain(account)
    models.each_with_index do |model, index|
      response = HTTParty.post(url(model), query: { key: api_key }, headers: { 'Content-Type' => 'application/json' },
                                           body: body, timeout: timeout)
      return [response, model] unless model_gone?(response) && index < models.size - 1

      mark_gone!(model)
      Rails.logger.warn("[CEVICO Gemini] modelo #{model} fora do ar (#{response.code}) — tentando #{models[index + 1]}")
    end
  end

  def model_gone?(response)
    return true if response.code.to_i == 404
    return false unless response.code.to_i == 400

    parsed = response.parsed_response
    message = parsed.is_a?(Hash) ? parsed.dig('error', 'message').to_s : parsed.to_s
    message.match?(/model/i) && message.match?(GONE_MESSAGE)
  end

  def gone?(model)
    Rails.cache.read(format(GONE_KEY, model: model)).present?
  rescue StandardError
    false
  end

  def mark_gone!(model)
    Rails.cache.write(format(GONE_KEY, model: model), Time.current.iso8601, expires_in: GONE_TTL)
  rescue StandardError
    nil
  end
end
