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
      { success: true, events_received: parsed['events_received'], fbtrace_id: parsed['fbtrace_id'],
        event_name: sent_event_name, messaging: messaging? }
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
    # test_event_code manda os eventos para o balde de TESTE da Meta (não
    # otimizam nem atribuem): só vale fora de produção ou com CEVICO_META_TEST_EVENTS=1
    payload[:test_event_code] = test_code if test_code.present? && test_events_allowed?
    payload
  end

  def event_data
    data = {
      event_name:       sent_event_name,
      event_time:       Time.current.to_i,
      event_id:         @event_id,
      action_source:    messaging? ? 'business_messaging' : 'system_generated',
      user_data:        build_user_data,
    }
    # ctwa_clid = clique no anúncio click-to-WhatsApp: com ele a Meta
    # atribui a conversão DIRETO ao anúncio que trouxe o contato
    data[:messaging_channel] = 'whatsapp' if messaging?
    data[:custom_data] = @custom_data if @custom_data.present?
    data
  end

  # Item 313: evento de MENSAGEM (lead de anúncio de WhatsApp) só vale com o
  # código do clique E o número da conta do WhatsApp (WABA) — a Meta exige
  # os dois. Sem a conta, o evento segue pelo caminho comum (telefone).
  def messaging?
    ctwa_clid.present? && waba_id.present?
  end

  # no caminho de mensagem a Meta só aceita a lista dela (Lead → LeadSubmitted…)
  def sent_event_name
    messaging? ? Cevico::ConversionEvents.meta_messaging_name(@event_name) : @event_name
  end

  def build_user_data
    return {} unless @contact

    ud = {}
    ud[:em] = [hash_value(@contact.email)]    if @contact.email.present?
    ud[:ph] = [hash_value(normalize_phone(@contact.phone_number))] if @contact.phone_number.present?

    name_parts = @contact.name&.split(' ', 2)
    ud[:fn] = [hash_value(name_parts&.first&.downcase)] if name_parts&.first.present?
    ud[:ln] = [hash_value(name_parts&.last&.downcase)]  if name_parts&.last.present?

    ud.merge(ad_identity)
  end

  # o que amarra o evento ao ANÚNCIO: no anúncio de WhatsApp, o código do
  # clique + a conta do WhatsApp; no anúncio que leva à página, o clique (fbc)
  # e o navegador (fbp) guardados no Protocolo
  def ad_identity
    ids = messaging? ? { ctwa_clid: ctwa_clid, whatsapp_business_account_id: waba_id } : {}
    ids[:fbc] = page_fbc if page_fbc.present?
    ids[:fbp] = page_ads['fbp'] if page_ads['fbp'].present?
    ids
  end

  def page_ads
    @page_ads ||= @contact&.additional_attributes&.dig('page_ads') || {}
  end

  # fbc = cookie _fbc da página; sem ele, montado do fbclid no formato da
  # Meta (fb.1.<momento do clique em ms>.<fbclid>)
  def page_fbc
    return page_ads['fbc'] if page_ads['fbc'].present?
    return if page_ads['fbclid'].blank?

    clicked_at = Time.zone.parse(page_ads['clicked_at'].to_s) || Time.current
    "fb.1.#{(clicked_at.to_f * 1000).to_i}.#{page_ads['fbclid']}"
  rescue ArgumentError
    nil
  end

  # número da conta do WhatsApp (WABA) da caixa em que o lead do anúncio
  # chegou — a conversa carimbada com o anúncio vence; senão, a primeira
  def waba_id
    return @waba_id if defined?(@waba_id)

    @waba_id = ad_whatsapp_conversation&.inbox&.channel&.provider_config&.dig('business_account_id').to_s.presence
  rescue StandardError => e
    Rails.logger.warn "[MetaAdsConversions] conta do WhatsApp não encontrada: #{e.message}"
    @waba_id = nil
  end

  def ad_whatsapp_conversation
    convs = @contact.conversations.joins(:inbox).where(inboxes: { channel_type: 'Channel::Whatsapp' })
    convs.where("jsonb_exists(conversations.additional_attributes, 'meta_ads')").reorder(:created_at).first ||
      convs.reorder(:created_at).first
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

  def test_events_allowed?
    !Rails.env.production? || ActiveModel::Type::Boolean.new.cast(ENV.fetch('CEVICO_META_TEST_EVENTS', nil))
  end
end
