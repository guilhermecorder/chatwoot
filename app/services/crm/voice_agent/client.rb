# Cliente da API da ElevenLabs (Agents + WhatsApp nativo) — só o que o
# Agente de Ligação precisa: testar a chave, listar vozes e contas WhatsApp,
# criar/atualizar ferramentas, agente e webhook, disparar ligação de saída
# e ler conversa/áudio. Mesmo estilo do Crm::Calls::MetaClient (HTTParty).
#
# Simulação: CEVICO_VOICE_SIMULATE=1 devolve ids falsos sem chamar a rede —
# para exercitar Sincronizar/discador/pós-chamada no ambiente local.
class Crm::VoiceAgent::Client
  BASE_URL = 'https://api.elevenlabs.io'.freeze
  TIMEOUT = 20

  attr_reader :api_key

  def initialize(api_key)
    @api_key = api_key.to_s
  end

  def simulated?
    Crm::VoiceAgent::Settings.simulate_env?
  end

  # GET /v1/user → { subscription: { tier }, first_name … } (testa a chave)
  def user
    return { 'first_name' => 'Simulação', 'subscription' => { 'tier' => 'simulado' } } if simulated?

    get('/v1/user')
  end

  # vozes em português (ou busca por nome) → [{ voice_id, name, labels }]
  def voices(search: nil)
    return [{ 'voice_id' => 'sim_voice', 'name' => 'Voz simulada', 'labels' => { 'language' => 'pt' } }] if simulated?

    query = { page_size: 30, language: 'pt', search: search.to_s.strip.presence }.compact
    Array(get('/v2/voices', query)['voices']).map { |v| v.slice('voice_id', 'name', 'labels', 'preview_url') }
  end

  # contas WhatsApp importadas na ElevenLabs → items[]
  def whatsapp_accounts
    return simulated_whatsapp_accounts if simulated?

    Array(get('/v1/convai/whatsapp-accounts')['items'])
  end

  # amarra o agente ao número e desliga mensagens de texto (só ligações)
  def update_whatsapp_account(phone_number_id, assigned_agent_id:, enable_messaging: false)
    return { 'ok' => true } if simulated?

    patch("/v1/convai/whatsapp-accounts/#{phone_number_id}", { assigned_agent_id: assigned_agent_id, enable_messaging: enable_messaging })
  end

  # webhook pós-chamada (HMAC) → { webhook_id, webhook_secret } (segredo só vem aqui)
  def create_webhook(name:, url:)
    return { 'webhook_id' => "sim_webhook_#{SecureRandom.hex(4)}", 'webhook_secret' => "sim_secret_#{SecureRandom.hex(16)}" } if simulated?

    post('/v1/workspace/webhooks', { settings: { auth_type: 'hmac', name: name, webhook_url: url } })
  end

  def create_tool(tool_config)
    return { 'id' => "sim_tool_#{SecureRandom.hex(4)}" } if simulated?

    post('/v1/convai/tools', { tool_config: tool_config })
  end

  def update_tool(tool_id, tool_config)
    return { 'id' => tool_id } if simulated?

    patch("/v1/convai/tools/#{tool_id}", { tool_config: tool_config })
  end

  def tool(tool_id)
    return { 'id' => tool_id } if simulated?

    get("/v1/convai/tools/#{tool_id}")
  end

  def create_agent(body)
    return { 'agent_id' => "sim_agent_#{SecureRandom.hex(4)}" } if simulated?

    post('/v1/convai/agents/create', body)
  end

  def update_agent(agent_id, body)
    return { 'agent_id' => agent_id } if simulated?

    patch("/v1/convai/agents/#{agent_id}", body)
  end

  def agent(agent_id)
    return { 'agent_id' => agent_id, 'whatsapp_accounts' => [] } if simulated?

    get("/v1/convai/agents/#{agent_id}")
  end

  # ligação de saída pelo WhatsApp nativo → { success, message, conversation_id }
  def whatsapp_outbound_call(body)
    return { 'success' => true, 'message' => 'simulada', 'conversation_id' => "sim_conv_#{SecureRandom.hex(4)}" } if simulated?

    post('/v1/convai/whatsapp/outbound-call', body)
  end

  def conversation(conversation_id)
    return { 'conversation_id' => conversation_id, 'status' => 'done', 'transcript' => [], 'metadata' => {} } if simulated?

    get("/v1/convai/conversations/#{conversation_id}")
  end

  # mp3 cru da conversa (nil quando ainda não existe)
  def conversation_audio(conversation_id)
    return nil if simulated?

    response = HTTParty.get("#{BASE_URL}/v1/convai/conversations/#{conversation_id}/audio", headers: headers, timeout: TIMEOUT)
    response.success? ? response.body : nil
  rescue StandardError => e
    Rails.logger.warn("[CEVICO voice] áudio #{conversation_id}: #{e.message}")
    nil
  end

  private

  def get(path, query = {})
    request { HTTParty.get(BASE_URL + path, headers: headers, query: query, timeout: TIMEOUT) }
  end

  def post(path, body)
    request { HTTParty.post(BASE_URL + path, headers: headers, body: body.to_json, timeout: TIMEOUT) }
  end

  def patch(path, body)
    request { HTTParty.patch(BASE_URL + path, headers: headers, body: body.to_json, timeout: TIMEOUT) }
  end

  def request
    raise Crm::VoiceAgent::Error.new('Configure a chave da API da ElevenLabs.', 401) if api_key.blank?

    handle(yield)
  rescue Crm::VoiceAgent::Error
    raise
  rescue StandardError => e
    raise Crm::VoiceAgent::Error.new("Sem resposta da ElevenLabs (#{e.class.name.demodulize}).", nil)
  end

  def handle(response)
    parsed = response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
    return parsed if response.success?

    message = error_message(parsed).presence || "A ElevenLabs respondeu com erro #{response.code}."
    raise Crm::VoiceAgent::Error.new(message, response.code, parsed)
  end

  # erro da ElevenLabs vem em detail: string, { message }, ou lista de validação [{ msg }] — devolve cru
  def error_message(parsed)
    detail = parsed['detail']
    return (detail['message'] || detail['status']).to_s if detail.is_a?(Hash)
    return detail.map { |d| d.is_a?(Hash) ? (d['msg'] || d.to_s) : d.to_s }.join('; ') if detail.is_a?(Array)

    detail.to_s
  end

  def headers
    { 'xi-api-key' => api_key, 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
  end

  def simulated_whatsapp_accounts
    [{ 'business_account_id' => 'sim_waba', 'phone_number_id' => 'sim_phone', 'business_account_name' => 'CEVICO (simulação)',
       'phone_number_name' => 'Assistente', 'phone_number' => '+5511999990000', 'assigned_agent_id' => nil,
       'assigned_agent_name' => nil, 'enable_messaging' => false, 'is_token_expired' => false }]
  end
end
