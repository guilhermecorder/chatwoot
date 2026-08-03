# Envia eventos de conversão para o Google via GA4 Measurement Protocol
# O GA4 deve estar vinculado ao Google Ads para importar conversões.
#
# Documentação: https://developers.google.com/analytics/devguides/collection/protocol/ga4
# Pré-requisito: GA4 property vinculada ao Google Ads + import de conversões ativo.
#
# Uso:
#   GoogleAdsConversionsService.new(account: account, event_name: 'generate_lead', contact: contact).call
class GoogleAdsConversionsService
  ENDPOINT = 'https://www.google-analytics.com/mp/collect'.freeze

  def initialize(account:, event_name:, contact: nil, params: {})
    @account    = account
    @event_name = event_name
    @contact    = contact
    @params     = params
  end

  def call # rubocop:disable Metrics/MethodLength
    config = crm_settings&.google_ads_config
    return { success: false, error: 'Google Ads não configurado' } unless configured?(config)

    measurement_id = config['measurement_id']
    api_secret     = config['api_secret']

    url = "#{ENDPOINT}?measurement_id=#{measurement_id}&api_secret=#{api_secret}"

    body = {
      client_id: client_identity[:client_id],
      events: [build_event]
    }

    response = HTTParty.post(
      url,
      body: body.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: 15
    )

    # GA4 Measurement Protocol retorna 204 em sucesso (sem corpo)
    if response.code == 204 || response.success?
      log_sent! # alimenta o Dashboard Google (conversões enviadas por dia)
      { success: true }
    else
      { success: false, error: "HTTP #{response.code}: #{response.body&.slice(0, 200)}" }
    end
  rescue StandardError => e
    { success: false, error: e.message }
  end

  private

  def crm_settings
    @crm_settings ||= CrmSetting.find_by(account: @account)
  end

  # registro leve por dia/evento (Dashboard Google mostra o que foi enviado)
  def log_sent!
    settings = crm_settings
    return if settings.blank?

    cfg = settings.google_ads_config || {}
    log = (cfg['sent_log'] ||= {})
    day = (log[Date.current.iso8601] ||= {})
    day[@event_name.to_s] = day[@event_name.to_s].to_i + 1
    # mantém só ~90 dias
    cfg['sent_log'] = log.sort.last(90).to_h
    settings.update_columns(google_ads_config: cfg) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.warn "[GoogleAdsConversions] log falhou: #{e.message}"
  end

  def configured?(config)
    config.is_a?(Hash) && config['measurement_id'].present? && config['api_secret'].present?
  end

  def build_event
    {
      name: @event_name,
      params: base_params.merge(@params)
    }
  end

  # Identidade da sessão que veio da PÁGINA (rastreio do Protocolo): se o
  # contato tem o client_id real do GA4 gravado (page_ads.ga_client_id,
  # capturado dos cookies _ga no clique do WhatsApp), a conversão volta
  # AMARRADA à sessão que clicou no anúncio — é assim que o Google Ads
  # passa a contabilizar. Sem ele, cai no id sintético antigo (o evento
  # aparece no GA4, mas sem atribuição de anúncio).
  def client_identity
    @client_identity ||= real_client_identity ||
                         { client_id: "crm.#{@contact&.id || SecureRandom.hex(8)}", session_id: nil, real: false }
  end

  def real_client_identity
    page_ads = @contact&.additional_attributes&.dig('page_ads') || {}
    return if page_ads['ga_client_id'].blank?

    { client_id: page_ads['ga_client_id'], session_id: page_ads['ga_session_id'].presence, real: true }
  end

  def base_params
    p = {
      engagement_time_msec: '1'
    }
    # session_id da visita original: reforça a junção da conversão com a
    # sessão certa dentro do GA4
    p[:session_id] = client_identity[:session_id] if client_identity[:session_id].present?
    if @contact
      p[:contact_id]    = @contact.id.to_s
      p[:contact_name]  = @contact.name if @contact.name.present?
      p[:contact_phone] = @contact.phone_number if @contact.phone_number.present?
    end
    p
  end
end
