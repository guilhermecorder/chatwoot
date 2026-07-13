# Envia eventos de conversão para a Meta via Conversions API (server-side)
# Documentação: https://developers.facebook.com/docs/marketing-api/conversions-api
#
# Uso:
#   MetaAdsConversionsService.new(account: account, event_name: 'Lead', contact: contact).call
class MetaAdsConversionsService
  GRAPH_API_URL = 'https://graph.facebook.com/v19.0'.freeze

  def initialize(account:, event_name:, contact: nil, custom_data: {}, event_id: nil)
    @account     = account
    @event_name  = event_name
    @contact     = contact
    @custom_data = custom_data
    @event_id    = event_id || SecureRandom.hex(16)
  end

  def call
    config = crm_settings&.meta_ads_config
    return { success: false, error: 'Meta Ads não configurado' } unless configured?(config)

    pixel_id     = config['pixel_id']
    access_token = config['access_token']
    test_code    = config['test_event_code']

    body = build_payload(test_code)
    url  = "#{GRAPH_API_URL}/#{pixel_id}/events?access_token=#{access_token}"

    response = HTTParty.post(
      url,
      body:    body.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: 15
    )

    parsed = response.parsed_response
    if response.success?
      { success: true, events_received: parsed['events_received'], fbtrace_id: parsed['fbtrace_id'] }
    else
      { success: false, error: parsed.dig('error', 'message') || "HTTP #{response.code}" }
    end
  rescue => e
    { success: false, error: e.message }
  end

  private

  def crm_settings
    @crm_settings ||= CrmSetting.find_by(account: @account)
  end

  def configured?(config)
    config.is_a?(Hash) && config['pixel_id'].present? && config['access_token'].present?
  end

  def build_payload(test_code)
    payload = {
      data: [event_data],
    }
    payload[:test_event_code] = test_code if test_code.present?
    payload
  end

  def event_data
    data = {
      event_name:       @event_name,
      event_time:       Time.current.to_i,
      event_id:         @event_id,
      action_source:    ctwa_clid.present? ? 'business_messaging' : 'system_generated',
      user_data:        build_user_data,
    }
    # ctwa_clid = clique no anúncio click-to-WhatsApp: com ele a Meta
    # atribui a conversão DIRETO ao anúncio que trouxe o contato
    data[:messaging_channel] = 'whatsapp' if ctwa_clid.present?
    data[:custom_data] = @custom_data if @custom_data.present?
    data
  end

  def build_user_data
    return {} unless @contact

    ud = {}
    ud[:em] = [hash_value(@contact.email)]    if @contact.email.present?
    ud[:ph] = [hash_value(normalize_phone(@contact.phone_number))] if @contact.phone_number.present?

    name_parts = @contact.name&.split(' ', 2)
    ud[:fn] = [hash_value(name_parts&.first&.downcase)] if name_parts&.first.present?
    ud[:ln] = [hash_value(name_parts&.last&.downcase)]  if name_parts&.last.present?

    ud[:ctwa_clid] = ctwa_clid if ctwa_clid.present?

    ud
  end

  # gravado pelo Crm::AdAttributionService quando o lead chega por anúncio
  def ctwa_clid
    @ctwa_clid ||= @contact&.additional_attributes&.dig('meta_ads', 'ctwa_clid').to_s
  end

  def normalize_phone(phone)
    return nil unless phone
    phone.gsub(/\D/, '')
  end

  def hash_value(value)
    return nil unless value.present?
    Digest::SHA256.hexdigest(value.strip.downcase)
  end
end
