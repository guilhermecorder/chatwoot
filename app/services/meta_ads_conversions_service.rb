# Envia eventos de conversão para a Meta via Conversions API (server-side)
# Documentação: https://developers.facebook.com/docs/marketing-api/conversions-api
#
# Uso:
#   MetaAdsConversionsService.new(account: account, event_name: 'Lead', contact: contact).call
#
# 📣 item 345 (14/10): evento comum vai para o conjunto do site (pixel_id);
# evento de anúncio de WhatsApp vai para o conjunto da conta do WhatsApp da
# caixa (Crm::MetaWabaDatasets) — e, se esse não der, cai no do site.
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

    @config = config
    messaging? ? send_messaging : send_to_site
  rescue StandardError => e
    { success: false, error: scrub(e.message) }
  end

  private

  # evento comum (lead da página, telefone…) → conjunto do site (pixel_id)
  def send_to_site(fallback: false)
    result = Crm::MetaWabaDatasets.post_events(@config['pixel_id'], @config['access_token'], build_payload)
    finish(result.merge(token: 'sistema'), dataset_id: @config['pixel_id'], fallback: fallback)
  end

  # 📣 item 345 (14/10): evento de MENSAGEM (lead de anúncio click-to-WhatsApp)
  # vai para o conjunto de dados LIGADO à conta do WhatsApp da caixa — o do
  # site recusa (subcode 2804132). Se o conjunto não sai (sem permissão, conta
  # de parceiro…) ou os dois tokens forem recusados, o evento vai pelo site do
  # jeito comum para a conversão não se perder (fallback: true na resposta).
  def send_messaging
    datasets = Crm::MetaWabaDatasets.new(@account, @config)
    dataset = datasets.dataset_id(waba_id)
    return fall_back_to_site(datasets.last_error) if dataset.blank?

    result = datasets.post_events(waba_id, dataset, build_payload)
    return fall_back_to_site(result[:error]) if !result[:ok] && result[:auth_error]

    finish(result, dataset_id: dataset, fallback: false)
  end

  def fall_back_to_site(reason)
    Rails.logger.warn "[MetaAdsConversions] item 345: #{@event_name} da conta do WhatsApp #{waba_id} foi pelo site — #{reason}"
    @messaging = false
    send_to_site(fallback: true).merge(fallback_reason: reason.to_s.presence || 'conjunto do WhatsApp indisponível')
  end

  def finish(result, dataset_id:, fallback:)
    base = { event_name: sent_event_name, messaging: messaging?, fallback: fallback, dataset_id: dataset_id, token: result[:token] }
    return base.merge(success: false, error: result[:error]) unless result[:ok]

    parsed = result[:parsed] || {}
    base.merge(success: true, events_received: parsed['events_received'], fbtrace_id: parsed['fbtrace_id'])
  end

  # nunca devolver/registrar token (erro de rede pode trazer a URL)
  def scrub(message)
    text = message.to_s
    [@config&.dig('access_token')].compact_blank.each { |token| text = text.gsub(token, '[token]') }
    text.gsub(/access_token=[^&\s]+/, 'access_token=[token]')
  end

  def crm_settings
    @crm_settings ||= CrmSetting.find_by(account: @account)
  end

  def configured?(config)
    config.is_a?(Hash) && config['pixel_id'].present? && config['access_token'].present?
  end

  def build_payload
    test_code = @config['test_event_code']
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
    return @messaging if defined?(@messaging)

    @messaging = ctwa_clid.present? && waba_id.present?
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

  # 📣 item 345: conversa em caixa dos parceiros (Oftalmofácil) não conta —
  # a conta do WhatsApp deles nunca recebe evento da CEVICO
  def ad_whatsapp_conversation
    convs = @contact.conversations.joins(:inbox).where(inboxes: { channel_type: 'Channel::Whatsapp' })
    partner_inboxes = Crm::PartnerGuard.partner_inbox_ids(@account)
    convs = convs.where.not(inbox_id: partner_inboxes) if partner_inboxes.any?
    convs.where("jsonb_exists(conversations.additional_attributes, 'meta_ads')").reorder(:created_at).first ||
      convs.reorder(:created_at).first
  end

  # gravado pelo Crm::AdAttributionService quando o lead chega por anúncio
  # 🔗 item 345b: clique e conta do WhatsApp saem da MESMA conversa (a do
  # anúncio) — clique de uma caixa com a conta de outra = recusa da Meta
  # (subcode 2804117, "ctwa_clid gerado para uma Página diferente"). Sem
  # clique na conversa, vale o do contato (primeiro toque), como antes.
  def ctwa_clid
    @ctwa_clid ||= (ad_conversation_clid.presence || @contact&.additional_attributes&.dig('meta_ads', 'ctwa_clid')).to_s
  end

  def ad_conversation_clid
    return nil if @contact.nil?

    ad_whatsapp_conversation&.additional_attributes&.dig('meta_ads', 'ctwa_clid')
  rescue StandardError
    nil
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
