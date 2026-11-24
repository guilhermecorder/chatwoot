# 🧠 TOMADA UNIVERSAL DE IA (22/11/2026): todos os agentes falam com a IA do
# mesmo jeito de sempre — `client.messages.create(model:, system_:, messages:,
# tools:, output_config:…)`, no formato da Anthropic. Esta peça olha o modelo:
#   claude-…  → devolve o Anthropic::Client oficial (nada muda)
#   gpt-…     → traduz para a Responses API da OpenAI
#   gemini-…  → traduz para a API do Gemini (camada compatível oficial do Google)
# e devolve a resposta no MESMO formato da Anthropic (blocos :text/:tool_use,
# stop_reason, usage com cache). Assim os ~26 agentes ganham os 3 fornecedores
# sem cada um precisar de um motor próprio.
#
# Erros dos outros fornecedores sobem como Crm::LlmGateway::Error, que é filho
# de Anthropic::Errors::APIError: os `rescue` que já existem continuam pegando.
module Crm::LlmGateway
  module_function

  class Error < Anthropic::Errors::APIError
    def initialize(message, status: nil, provider: nil)
      @provider = provider
      super(url: URI('https://localhost/llm'), status: status, message: message)
    end

    attr_reader :provider
  end

  # blocos e resposta com a mesma "cara" dos objetos do gem anthropic
  TextBlock = Struct.new(:text, keyword_init: true) do
    def type = :text
    def to_h = { type: 'text', text: text }
  end

  ToolUseBlock = Struct.new(:id, :name, :input, keyword_init: true) do
    def type = :tool_use
    def to_h = { type: 'tool_use', id: id, name: name, input: input }
  end

  Usage = Struct.new(:input_tokens, :output_tokens, :cache_read_input_tokens, :cache_creation_input_tokens, keyword_init: true)

  Response = Struct.new(:id, :model, :content, :stop_reason, :usage, :provider, keyword_init: true)

  # o cliente certo para o modelo. keys = ai_config (as 3 chaves ficam lá).
  def client(model:, ai_config:, timeout: 300, max_retries: 2)
    provider = Crm::LlmCatalog.provider(model) || 'anthropic'
    key = ai_config.to_h[Crm::LlmCatalog.key_name(provider)].presence
    return Anthropic::Client.new(api_key: key, timeout: timeout, max_retries: max_retries) if provider == 'anthropic'

    Client.new(provider: provider, api_key: key, timeout: timeout, max_retries: max_retries)
  end

  # imita `Anthropic::Client`: client.messages.create(**params)
  class Client # rubocop:disable Style/OneClassPerFile
    attr_reader :provider

    def initialize(provider:, api_key:, timeout:, max_retries:)
      @provider = provider
      @api_key = api_key
      @timeout = timeout
      @max_retries = max_retries
    end

    def messages
      @messages ||= adapter_class.new(api_key: @api_key, timeout: @timeout, max_retries: @max_retries)
    end

    private

    def adapter_class
      case @provider
      when 'openai' then Crm::LlmGateway::OpenaiAdapter
      when 'google' then Crm::LlmGateway::GeminiAdapter
      else raise Error.new("Fornecedor de IA desconhecido: #{@provider}", provider: @provider)
      end
    end
  end

  # ── peças comuns aos tradutores ────────────────────────────────────────────
  module Shared # rubocop:disable Metrics/ModuleLength
    RETRIABLE = [408, 429, 500, 502, 503, 504].freeze

    def initialize(api_key:, timeout:, max_retries:)
      @api_key = api_key
      @timeout = timeout
      @max_retries = max_retries
      # resposta crua de cada pedido de ferramenta, para reenviar igualzinho na
      # volta seguinte (raciocínio cifrado da OpenAI / assinatura do Gemini)
      @raw_by_call = {}
    end

    private

    def provider_name
      self.class::PROVIDER_LABEL
    end

    def ensure_key!
      return if @api_key.present?

      raise Crm::LlmGateway::Error.new("Configure a chave do #{provider_name} em CRM → Integrações.", status: 401, provider: provider_name)
    end

    def h(value)
      return value.to_h.deep_symbolize_keys if value.respond_to?(:to_h) && !value.is_a?(Array)

      value
    end

    # system_ chega como texto ou como blocos (com cache_control da Anthropic)
    def system_text(params)
      raw = params[:system_] || params[:system]
      return raw.to_s if raw.is_a?(String) || raw.nil?

      Array(raw).map { |block| h(block)[:text].to_s }.join("\n\n")
    end

    def blocks(content)
      return [{ type: 'text', text: content.to_s }] if content.is_a?(String) || content.nil?

      Array(content).map { |block| h(block) }
    end

    def tool_result_text(block)
      content = block[:content]
      text = content.is_a?(String) ? content : Array(content).map { |part| h(part)[:text].to_s }.join("\n")
      block[:is_error] ? "ERRO: #{text}" : text
    end

    def json_schema(params)
      format = h(params.dig(:output_config, :format) || params[:output_format] || {})
      format[:type].to_s == 'json_schema' ? format[:schema] : nil
    end

    def effort(params)
      params.dig(:output_config, :effort).presence&.to_s
    end

    # Anthropic conta o "pensar" dentro do max_tokens; os outros também — dá
    # folga para o raciocínio não cortar a resposta no meio
    def output_budget(params)
      base = params[:max_tokens].to_i.nonzero? || 4096
      [base + 8_000, 128_000].min
    end

    # OpenAI/Gemini só aceitam o modo ESTRITO se todo objeto listar todos os
    # campos em required e travar additionalProperties
    def strict_schema?(schema) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      node = h(schema)
      return true unless node.is_a?(Hash)

      if node[:type].to_s == 'object' || node.key?(:properties)
        props = h(node[:properties] || {})
        return false unless node[:additionalProperties] == false
        return false unless Array(node[:required]).map(&:to_s).sort == props.keys.map(&:to_s).sort

        return props.values.all? { |child| strict_schema?(child) }
      end
      return strict_schema?(node[:items]) if node.key?(:items)

      %i[anyOf oneOf allOf].all? { |k| Array(node[k]).all? { |child| strict_schema?(child) } }
    end

    def parse_arguments(raw)
      return raw.deep_stringify_keys if raw.is_a?(Hash)

      parsed = JSON.parse(raw.presence || '{}')
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    def post_json(url, body, headers)
      attempts = 0
      begin
        attempts += 1
        response = HTTParty.post(url, headers: headers.merge('Content-Type' => 'application/json'), body: body.to_json, timeout: @timeout)
        if RETRIABLE.include?(response.code.to_i) && attempts <= @max_retries && !quota_error?(response)
          sleep(response.code.to_i == 429 ? 2 * attempts : 0.5 * attempts)
          raise Net::ReadTimeout, "HTTP #{response.code}"
        end

        response
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, SocketError => e
        retry if attempts <= @max_retries
        raise Crm::LlmGateway::Error.new("#{provider_name} não respondeu a tempo (#{e.class.name.demodulize}).", provider: provider_name)
      end
    end

    def quota_error?(response)
      parsed = response.parsed_response
      text = parsed.is_a?(Hash) ? parsed.to_json : parsed.to_s
      # 24/11: "billing" solto pegava o aviso de limite de velocidade da OpenAI (o texto
      # dele traz o endereço da página de billing) e a tela dizia "sem créditos" com saldo na conta
      text.match?(/insufficient_quota|RESOURCE_EXHAUSTED.*(billing|quota)|credit balance is too low|billing (hard )?limit/i)
    end

    def error_detail(response)
      parsed = response.parsed_response
      parsed = parsed.first if parsed.is_a?(Array)
      return parsed.to_s.truncate(200) unless parsed.is_a?(Hash)

      (parsed.dig('error', 'message') || parsed['message'] || parsed.to_json).to_s.truncate(200)
    end

    def raise_http_error!(response, model)
      code = response.code.to_i
      detail = error_detail(response)
      message =
        case code
        when 401 then "Chave do #{provider_name} inválida."
        when 403 then "A chave do #{provider_name} não tem permissão para o modelo #{model}."
        when 404 then "Modelo #{model} não existe (ou não está liberado) para esta chave do #{provider_name}."
        when 429
          if quota_error?(response) then "#{provider_name} sem créditos: recarregue na conta do fornecedor."
          else "#{provider_name}: limite de uso atingido (429). #{detail}".strip
          end
        else "#{provider_name} respondeu com erro #{code}: #{detail}"
        end
      raise Crm::LlmGateway::Error.new(message, status: code, provider: provider_name)
    end
  end
end
