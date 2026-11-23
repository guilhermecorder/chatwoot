# 🧠 Tradutor Anthropic → OpenAI (Responses API oficial, HTTPS direto).
# - `store: false`: a conversa não fica guardada na OpenAI; por isso o laço de
#   ferramentas reenvia a saída crua (com o raciocínio cifrado) a cada volta.
# - O prompt do agente vai como mensagem `developer` no começo: a OpenAI guarda
#   esse trecho em cache sozinha (lido do cache custa ~5%).
# Formato conferido na documentação oficial em 22/11/2026.
class Crm::LlmGateway::OpenaiAdapter
  include Crm::LlmGateway::Shared

  URL = 'https://api.openai.com/v1/responses'.freeze
  PROVIDER_LABEL = 'ChatGPT (OpenAI)'.freeze
  EFFORTS = %w[none minimal low medium high xhigh max].freeze

  def create(**params) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    ensure_key!
    params = params.deep_symbolize_keys
    model = Crm::LlmCatalog.api_id(params[:model])
    body = { model: model, input: input_items(params), store: false, max_output_tokens: output_budget(params),
             include: ['reasoning.encrypted_content'] }
    schema = json_schema(params)
    body[:text] = { format: { type: 'json_schema', name: 'resposta', schema: schema, strict: strict_schema?(schema) } } if schema
    body[:reasoning] = { effort: effort(params) } if EFFORTS.include?(effort(params))
    if params[:tools].present?
      body[:tools] = params[:tools].filter_map { |tool| tool_definition(h(tool)) }
      body[:tool_choice] = tool_choice(h(params[:tool_choice])) if params[:tool_choice]
      body[:parallel_tool_calls] = false if h(params[:tool_choice] || {})[:disable_parallel_tool_use]
    end

    response = post_json(URL, body, 'Authorization' => "Bearer #{@api_key}")
    # modelo que não aceita o nível de raciocínio pedido: tenta de novo sem ele
    if response.code.to_i == 400 && body[:reasoning] && error_detail(response).match?(/reasoning|effort/i)
      body.delete(:reasoning)
      response = post_json(URL, body, 'Authorization' => "Bearer #{@api_key}")
    end
    raise_http_error!(response, model) unless response.code.to_i == 200

    to_response(response.parsed_response, model)
  end

  private

  def input_items(params)
    items = []
    system = system_text(params)
    items << { role: 'developer', content: system } if system.present?
    Array(params[:messages]).each { |message| items.concat(message_items(h(message))) }
    items
  end

  def message_items(message) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    role = message[:role].to_s
    parts = blocks(message[:content])
    out = []
    inline = []
    sent_raw = []
    parts.each do |block|
      case block[:type].to_s
      when 'text'
        inline << { type: role == 'assistant' ? 'output_text' : 'input_text', text: block[:text].to_s }
      when 'image'
        src = h(block[:source])
        url = src[:type].to_s == 'url' ? src[:url] : "data:#{src[:media_type]};base64,#{src[:data]}"
        inline << { type: 'input_image', image_url: url }
      when 'document'
        src = h(block[:source])
        inline << if src[:type].to_s == 'text'
                    { type: 'input_text', text: src[:data].to_s }
                  else
                    { type: 'input_file', filename: 'documento.pdf', file_data: "data:#{src[:media_type] || 'application/pdf'};base64,#{src[:data]}" }
                  end
      when 'tool_use'
        raw = @raw_by_call[block[:id].to_s]
        if raw
          out.concat(raw) unless sent_raw.include?(raw.object_id)
          sent_raw << raw.object_id
        else
          out << { type: 'function_call', call_id: block[:id].to_s, name: block[:name].to_s, arguments: (block[:input] || {}).to_json }
        end
      when 'tool_result'
        out << { type: 'function_call_output', call_id: block[:tool_use_id].to_s, output: tool_result_text(block) }
      end
      # thinking/redacted_thinking da Anthropic não têm equivalente: ficam de fora
    end
    # com a saída crua reenviada, o texto do assistente já vai dentro dela
    inline = [] if role == 'assistant' && sent_raw.any?
    message_item =
      if inline.empty? then []
      elsif role == 'assistant' then [{ role: 'assistant', content: inline.pluck(:text).join("\n") }]
      else
        [{ role: 'user', content: inline }]
      end
    role == 'assistant' ? message_item + out : out + message_item
  end

  def tool_definition(tool)
    return nil if tool[:name].blank? || tool[:type].to_s.start_with?('web_search', 'computer', 'bash', 'text_editor')

    { type: 'function', name: tool[:name], description: tool[:description].to_s,
      parameters: tool[:input_schema] || { type: 'object', properties: {} }, strict: false }
  end

  def tool_choice(choice)
    case choice[:type].to_s
    when 'none' then 'none'
    when 'any' then 'required'
    when 'tool' then { type: 'function', name: choice[:name] }
    else 'auto'
    end
  end

  def to_response(data, model) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
    raise Crm::LlmGateway::Error.new('ChatGPT devolveu uma resposta que não é JSON.', provider: PROVIDER_LABEL) unless data.is_a?(Hash)

    if data['error'].present?
      raise Crm::LlmGateway::Error.new("ChatGPT: #{data.dig('error', 'message').to_s.truncate(160)}",
                                       provider: PROVIDER_LABEL)
    end

    items = Array(data['output'])
    calls = items.select { |item| item['type'] == 'function_call' }
    parts = items.select { |item| item['type'] == 'message' }.flat_map { |item| Array(item['content']) }
    refusal = parts.find { |part| part['type'] == 'refusal' }
    if refusal
      raise Crm::LlmGateway::Error.new("O ChatGPT se recusou a responder: #{refusal['refusal'].to_s.truncate(120)}",
                                       provider: PROVIDER_LABEL)
    end

    calls.each { |call| @raw_by_call[call['call_id'].to_s] = items }
    content = []
    text = parts.select { |part| part['type'] == 'output_text' }.pluck('text').join
    content << Crm::LlmGateway::TextBlock.new(text: text) if text.present?
    calls.each do |call|
      content << Crm::LlmGateway::ToolUseBlock.new(id: call['call_id'].to_s, name: call['name'].to_s, input: parse_arguments(call['arguments']))
    end

    stop = if calls.any? then :tool_use
           elsif data['status'] == 'incomplete' then :max_tokens
           else
             :end_turn
           end
    usage = data['usage'] || {}
    total = usage['input_tokens'].to_i
    cached = [usage.dig('input_tokens_details', 'cached_tokens').to_i, total].min
    Crm::LlmGateway::Response.new(
      id: data['id'], model: model, content: content, stop_reason: stop, provider: 'openai',
      usage: Crm::LlmGateway::Usage.new(input_tokens: total - cached, cache_read_input_tokens: cached,
                                        cache_creation_input_tokens: 0, output_tokens: usage['output_tokens'].to_i)
    )
  end
end
