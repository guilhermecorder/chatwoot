# 🧠 Conector do ChatGPT (item 399): fala com a Responses API da OpenAI por
# HTTPS direto (sem biblioteca), no mesmo espírito do Crm::GeminiModels.
#
# - SEM GUARDAR NA OPENAI (`store: false`): a conversa do paciente não fica
#   armazenada lá. Por isso o laço de ferramentas reenvia os itens da resposta
#   anterior (inclusive o "raciocínio" cifrado) a cada volta.
# - O prompt do agente vai como mensagem `developer` no COMEÇO da entrada: é o
#   que a OpenAI guarda em cache sozinha (trecho repetido custa ~5%).
# - A resposta final é JSON no formato pedido (json_schema estrito); as
#   ferramentas vão em modo não estrito porque têm campos opcionais.
#
# Formato conferido na documentação oficial em 22/11/2026
# (developers.openai.com/api/reference/resources/responses).
class Crm::LlmEngines::OpenaiResponses
  URL = 'https://api.openai.com/v1/responses'.freeze
  MODELS_URL = 'https://api.openai.com/v1/models'.freeze
  # o teto inclui o que o modelo "pensa" antes de escrever: folga para o
  # esforço médio/alto não cortar a resposta no meio
  MAX_OUTPUT_TOKENS = 16_000
  RETRIABLE = [408, 500, 502, 503, 504].freeze

  class Error < StandardError; end

  # text = JSON final (quando houver) · tool_calls = pedidos de ferramenta ·
  # items = saída crua, para reenviar na próxima volta · usage = tokens
  Reply = Struct.new(:text, :tool_calls, :items, :usage, keyword_init: true)

  def initialize(api_key:, model:, effort: nil, timeout: 90, max_retries: 1)
    @api_key = api_key
    @model = model
    @effort = Crm::LlmEngines::OPENAI_EFFORTS.include?(effort.to_s) ? effort.to_s : nil
    @timeout = timeout
    @max_retries = max_retries
  end

  # ferramentas no formato da Anthropic ({name, description, input_schema}) →
  # formato da OpenAI
  def self.tool_definitions(definitions)
    Array(definitions).map do |tool|
      { type: 'function', name: tool[:name], description: tool[:description], parameters: tool[:input_schema], strict: false }
    end
  end

  # chave válida? devolve os ids de modelo que ela enxerga
  def self.model_ids(api_key, timeout: 20)
    response = HTTParty.get(MODELS_URL, headers: { 'Authorization' => "Bearer #{api_key}" }, timeout: timeout)
    raise Error, error_message(response, nil) unless response.code.to_i == 200

    Array(response.parsed_response['data']).pluck('id')
  end

  # UMA chamada. allow_tools: false = última volta (tem que responder em texto).
  def create(input:, schema:, schema_name:, tools: nil, allow_tools: true)
    body = {
      model: @model, input: input, store: false, max_output_tokens: MAX_OUTPUT_TOKENS,
      include: ['reasoning.encrypted_content'],
      text: { format: { type: 'json_schema', name: schema_name, schema: schema, strict: true } }
    }
    body[:reasoning] = { effort: @effort } if @effort
    if tools.present?
      body[:tools] = tools
      body[:tool_choice] = allow_tools ? 'auto' : 'none'
    end
    parse(post(body))
  end

  def self.error_message(response, model) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    parsed = response.parsed_response
    detail = parsed.is_a?(Hash) ? parsed.dig('error', 'message').to_s : ''
    code = parsed.is_a?(Hash) ? parsed.dig('error', 'code').to_s : ''
    case response.code.to_i
    when 401 then 'Chave da OpenAI inválida.'
    when 403 then 'A chave da OpenAI não tem permissão para este modelo.'
    when 404 then "Modelo #{model} indisponível para esta chave da OpenAI."
    when 429
      return 'OpenAI sem créditos: recarregue em platform.openai.com → Billing.' if code == 'insufficient_quota'

      # 24/11: limite de VELOCIDADE da conta (tokens ou pedidos por minuto/dia), não falta de crédito.
      # O texto da OpenAI diz qual limite estourou (platform.openai.com → Settings → Limits).
      "OpenAI: limite de uso atingido (429).#{" #{detail.truncate(240)}" if detail.present?}"
    else
      return "Modelo #{model} indisponível para esta chave da OpenAI." if code == 'model_not_found'

      "OpenAI respondeu com erro #{response.code}#{": #{detail.truncate(160)}" if detail.present?}"
    end
  end

  private

  def post(body)
    attempts = 0
    begin
      attempts += 1
      response = HTTParty.post(URL, headers: { 'Authorization' => "Bearer #{@api_key}", 'Content-Type' => 'application/json' },
                                    body: body.to_json, timeout: @timeout)
      raise Net::ReadTimeout, "HTTP #{response.code}" if RETRIABLE.include?(response.code.to_i) && attempts <= @max_retries

      response
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, SocketError => e
      retry if attempts <= @max_retries
      raise Error, "OpenAI não respondeu a tempo (#{e.class.name.demodulize})."
    end
  end

  def parse(response) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    raise Error, self.class.error_message(response, @model) unless response.code.to_i == 200

    data = response.parsed_response
    raise Error, 'OpenAI devolveu uma resposta que não é JSON.' unless data.is_a?(Hash)
    raise Error, "OpenAI: #{data.dig('error', 'message').to_s.truncate(160)}" if data['error'].present?

    items = Array(data['output'])
    tool_calls = items.select { |item| item['type'] == 'function_call' }
    parts = items.select { |item| item['type'] == 'message' }.flat_map { |item| Array(item['content']) }
    refusal = parts.find { |part| part['type'] == 'refusal' }
    raise Error, "O ChatGPT se recusou a responder: #{refusal['refusal'].to_s.truncate(120)}" if refusal

    if data['status'] == 'incomplete' && tool_calls.empty?
      raise Error, "Resposta do ChatGPT cortada (#{data.dig('incomplete_details', 'reason') || 'incompleta'})."
    end

    text = parts.select { |part| part['type'] == 'output_text' }.pluck('text').join
    Reply.new(text: text.presence, tool_calls: tool_calls, items: items, usage: data['usage'] || {})
  end
end
