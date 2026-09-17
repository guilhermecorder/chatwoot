# Cliente da WhatsApp Business Calling API (Graph). Só o que as ligações
# precisam: aceitar/recusar/encerrar, ligar (connect), ligar o recurso no
# número (settings) e consultar/pedir permissão para ligar.
#
# Simulação: com simulated: true (chamada criada pela rake) ou
# CEVICO_CALLS_SIMULATE=1 nada sai para a Meta — devolve sucesso, para
# testar popup/card/dashboard localmente com o mesmo código do fluxo real.
class Crm::Calls::MetaClient
  API_VERSION = 'v23.0'.freeze
  TIMEOUT = 10

  attr_reader :channel

  def initialize(channel, simulated: false)
    @channel = channel
    @simulated = simulated
  end

  def simulated?
    @simulated || Crm::Calls::Settings.simulate_env?
  end

  def pre_accept(call_id, sdp)
    call_action(call_id, 'pre_accept', session: { sdp_type: 'answer', sdp: sdp })
  end

  def accept(call_id, sdp)
    call_action(call_id, 'accept', session: { sdp_type: 'answer', sdp: sdp })
  end

  def reject(call_id)
    call_action(call_id, 'reject')
  end

  def terminate(call_id)
    call_action(call_id, 'terminate')
  end

  # ligação iniciada pela clínica → devolve o call_id da Meta
  def connect(to:, sdp:, callback_data: nil)
    return "sim-#{SecureRandom.hex(6)}" if simulated?

    body = { messaging_product: 'whatsapp', to: to, action: 'connect', session: { sdp_type: 'offer', sdp: sdp } }
    body[:biz_opaque_callback_data] = callback_data if callback_data.present?
    response = post("#{phone_path}/calls", body)
    call_id = response.dig('calls', 0, 'id')
    raise Crm::Calls::MetaError.new('A Meta não devolveu o identificador da chamada.', 'no_call_id') if call_id.blank?

    call_id
  end

  # GET /settings → { calling: { status, call_icon_visibility, callback_permission_status, ... } }
  def settings
    return { 'calling' => { 'status' => 'ENABLED', 'callback_permission_status' => 'ENABLED', 'simulated' => true } } if simulated?

    get("#{phone_path}/settings")
  end

  def update_settings(calling)
    return { 'success' => true } if simulated?

    post("#{phone_path}/settings", { calling: calling })
  end

  def call_permissions(wa_id)
    return simulated_permissions if simulated?

    get("#{phone_path}/call_permissions", { user_wa_id: wa_id })
  end

  def send_permission_request(to:, text:)
    return { 'messages' => [{ 'id' => "sim-#{SecureRandom.hex(6)}" }] } if simulated?

    post("#{phone_path}/messages", {
           messaging_product: 'whatsapp', recipient_type: 'individual', to: to, type: 'interactive',
           interactive: { type: 'call_permission_request', action: { name: 'call_permission_request' }, body: { text: text } }
         })
  end

  private

  # corpo exato da doc: { messaging_product, call_id, action, session: { sdp_type: 'answer', sdp } }
  def call_action(call_id, action, extra = {})
    return { 'success' => true } if simulated?

    post("#{phone_path}/calls", { messaging_product: 'whatsapp', call_id: call_id, action: action }.merge(extra))
  end

  def get(url, query = {})
    handle(HTTParty.get(url, headers: headers, query: query, timeout: TIMEOUT))
  rescue Crm::Calls::MetaError
    raise
  rescue StandardError => e
    raise Crm::Calls::MetaError.new("Sem resposta da Meta (#{e.class.name.demodulize}).", 'network')
  end

  def post(url, body)
    handle(HTTParty.post(url, headers: headers, body: body.to_json, timeout: TIMEOUT))
  rescue Crm::Calls::MetaError
    raise
  rescue StandardError => e
    raise Crm::Calls::MetaError.new("Sem resposta da Meta (#{e.class.name.demodulize}).", 'network')
  end

  def handle(response)
    parsed = response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
    return parsed if response.success?

    error = parsed['error'] || {}
    raise Crm::Calls::MetaError.new(error['message'].presence || "A Meta respondeu com erro #{response.code}.",
                                    error['code'] || response.code)
  end

  def simulated_permissions
    {
      'permission' => { 'status' => 'temporary', 'expiration_time' => 7.days.from_now.to_i },
      'actions' => [
        { 'action_name' => 'send_call_permission_request', 'can_perform_action' => true },
        { 'action_name' => 'start_call', 'can_perform_action' => true }
      ]
    }
  end

  def phone_path
    "#{ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')}/#{API_VERSION}/#{provider_config['phone_number_id']}"
  end

  def provider_config
    (channel.provider_config || {}).to_h
  end

  # cabeçalho do provider oficial quando existir; senão Bearer da chave da caixa
  def headers
    service = channel.respond_to?(:provider_service) ? channel.provider_service : nil
    return service.api_headers if service.respond_to?(:api_headers)

    fallback_headers
  rescue StandardError
    fallback_headers
  end

  def fallback_headers
    { 'Authorization' => "Bearer #{provider_config['api_key']}", 'Content-Type' => 'application/json' }
  end
end
