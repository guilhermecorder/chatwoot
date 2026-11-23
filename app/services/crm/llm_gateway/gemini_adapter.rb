# 🧠 Tradutor Anthropic → Google Gemini, pela camada compatível OFICIAL do
# Google (generativelanguage.googleapis.com/v1beta/openai/chat/completions).
# - Mesma chave que já lê áudio/imagem (ai_config['gemini_api_key']).
# - Pedido de ferramenta: a mensagem do assistente volta IGUALZINHA na volta
#   seguinte (o Gemini 3/4 guarda nela a "assinatura do pensamento"; sem ela,
#   a chamada com ferramenta falha).
# - Formato JSON: tenta o json_schema; se o Gemini recusar o schema, repete em
#   modo JSON simples com o schema escrito no prompt.
# Conferido na documentação oficial em 22/11/2026 (aistudio.google.com/docs/openai).
class Crm::LlmGateway::GeminiAdapter
  include Crm::LlmGateway::Shared

  URL = 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions'.freeze
  PROVIDER_LABEL = 'Gemini (Google)'.freeze
  # o Gemini aceita minimal/low/medium/high; xhigh só em alguns do Gemini 4
  XHIGH_MODELS = %w[gemini-4-neon gemini-4-hydrogen].freeze

  def create(**params) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
    ensure_key!
    params = params.deep_symbolize_keys
    model = Crm::LlmCatalog.api_id(params[:model])
    body = { model: model, messages: chat_messages(params), max_tokens: output_budget(params) }
    schema = json_schema(params)
    body[:response_format] = { type: 'json_schema', json_schema: { name: 'resposta', schema: schema, strict: strict_schema?(schema) } } if schema
    level = reasoning_level(model, effort(params))
    body[:reasoning_effort] = level if level
    if params[:tools].present?
      body[:tools] = params[:tools].filter_map { |tool| tool_definition(h(tool)) }
      body[:tool_choice] = tool_choice(h(params[:tool_choice])) if params[:tool_choice]
      body.delete(:tools) if body[:tools].empty?
    end

    response = post_json(URL, body, auth)
    if response.code.to_i == 400 && schema && error_detail(response).match?(/schema|response_format|json/i)
      body[:response_format] = { type: 'json_object' }
      body[:messages] = with_schema_hint(body[:messages], schema)
      response = post_json(URL, body, auth)
    end
    if response.code.to_i == 400 && body[:reasoning_effort] && error_detail(response).match?(/reasoning|thinking/i)
      body.delete(:reasoning_effort)
      response = post_json(URL, body, auth)
    end
    raise_http_error!(response, model) unless response.code.to_i == 200

    to_response(response.parsed_response, model)
  end

  private

  def auth
    { 'Authorization' => "Bearer #{@api_key}" }
  end

  def reasoning_level(model, effort)
    case effort
    when 'low', 'medium', 'high', 'minimal' then effort
    when 'xhigh', 'max' then XHIGH_MODELS.include?(model) ? 'xhigh' : 'high'
    end
  end

  def chat_messages(params)
    out = []
    system = system_text(params)
    out << { role: 'system', content: system } if system.present?
    Array(params[:messages]).each { |message| out.concat(convert(h(message))) }
    out
  end

  def convert(message) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    role = message[:role].to_s
    parts = blocks(message[:content])
    if role == 'assistant'
      uses = parts.select { |b| b[:type].to_s == 'tool_use' }
      raw = uses.filter_map { |use| @raw_by_call[use[:id].to_s] }.uniq
      return raw if raw.any?

      text = parts.select { |b| b[:type].to_s == 'text' }.pluck(:text).join("\n")
      msg = { role: 'assistant', content: text.presence }
      if uses.any?
        msg[:tool_calls] = uses.map do |use|
          { id: use[:id].to_s, type: 'function', function: { name: use[:name].to_s, arguments: (use[:input] || {}).to_json } }
        end
      end
      return [msg]
    end

    out = parts.select { |b| b[:type].to_s == 'tool_result' }.map do |block|
      { role: 'tool', tool_call_id: block[:tool_use_id].to_s, content: tool_result_text(block) }
    end
    content = parts.filter_map do |block|
      case block[:type].to_s
      when 'text' then { type: 'text', text: block[:text].to_s }
      when 'image'
        src = h(block[:source])
        url = src[:type].to_s == 'url' ? src[:url] : "data:#{src[:media_type]};base64,#{src[:data]}"
        { type: 'image_url', image_url: { url: url } }
      when 'document'
        src = h(block[:source])
        if src[:type].to_s == 'text'
          { type: 'text',
            text: src[:data].to_s }
        else
          { type: 'text', text: '(documento em PDF anexado: não suportado neste modelo)' }
        end
      end
    end
    out << { role: 'user', content: content } if content.any?
    out
  end

  def with_schema_hint(messages, schema)
    hint = "\n\nResponda SOMENTE com um JSON válido que siga exatamente este JSON Schema:\n#{schema.to_json}"
    if messages.first&.dig(:role) == 'system'
      [messages.first.merge(content: "#{messages.first[:content]}#{hint}"), *messages.drop(1)]
    else
      [{ role: 'system', content: hint.strip }, *messages]
    end
  end

  def tool_definition(tool)
    return nil if tool[:name].blank? || tool[:type].to_s.start_with?('web_search', 'computer', 'bash', 'text_editor')

    { type: 'function', function: { name: tool[:name], description: tool[:description].to_s,
                                    parameters: tool[:input_schema] || { type: 'object', properties: {} } } }
  end

  def tool_choice(choice)
    case choice[:type].to_s
    when 'none' then 'none'
    when 'any' then 'required'
    when 'tool' then { type: 'function', function: { name: choice[:name] } }
    else 'auto'
    end
  end

  def to_response(data, model) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
    data = data.first if data.is_a?(Array)
    raise Crm::LlmGateway::Error.new('Gemini devolveu uma resposta que não é JSON.', provider: PROVIDER_LABEL) unless data.is_a?(Hash)
    raise Crm::LlmGateway::Error.new("Gemini: #{data.dig('error', 'message').to_s.truncate(160)}", provider: PROVIDER_LABEL) if data['error'].present?

    choice = Array(data['choices']).first || {}
    message = choice['message'] || {}
    calls = Array(message['tool_calls'])
    raw = message.slice('role', 'content', 'tool_calls', 'extra_content').compact
    raw['role'] ||= 'assistant'
    calls.each { |call| @raw_by_call[call['id'].to_s] = raw.deep_symbolize_keys }

    content = []
    text = message['content'].is_a?(Array) ? message['content'].map { |p| p['text'].to_s }.join : message['content'].to_s
    content << Crm::LlmGateway::TextBlock.new(text: strip_fences(text)) if text.present?
    calls.each do |call|
      fn = call['function'] || {}
      content << Crm::LlmGateway::ToolUseBlock.new(id: call['id'].to_s, name: fn['name'].to_s, input: parse_arguments(fn['arguments']))
    end

    stop = if calls.any? then :tool_use
           elsif choice['finish_reason'] == 'length' then :max_tokens
           else
             :end_turn
           end
    usage = data['usage'] || {}
    prompt = usage['prompt_tokens'].to_i
    cached = [usage.dig('prompt_tokens_details', 'cached_tokens').to_i, prompt].min
    Crm::LlmGateway::Response.new(
      id: data['id'], model: model, content: content, stop_reason: stop, provider: 'google',
      usage: Crm::LlmGateway::Usage.new(input_tokens: prompt - cached, cache_read_input_tokens: cached,
                                        cache_creation_input_tokens: 0, output_tokens: usage['completion_tokens'].to_i)
    )
  end

  # no modo JSON simples o Gemini às vezes embrulha em ```json … ```
  def strip_fences(text)
    text.strip.sub(/\A```(?:json)?\s*/i, '').sub(/\s*```\z/, '')
  end
end
