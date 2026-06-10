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

  def call
    config = crm_settings&.google_ads_config
    return { success: false, error: 'Google Ads não configurado' } unless configured?(config)

    measurement_id = config['measurement_id']
    api_secret     = config['api_secret']
    client_id      = config.fetch('client_id', "crm.#{@contact&.id || SecureRandom.hex(8)}")

    url = "#{ENDPOINT}?measurement_id=#{measurement_id}&api_secret=#{api_secret}"

    body = {
      client_id: client_id,
      events:    [build_event],
    }

    response = HTTParty.post(
      url,
      body:    body.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: 15
    )

    # GA4 Measurement Protocol retorna 204 em sucesso (sem corpo)
    if response.code == 204 || response.success?
      { success: true }
    else
      { success: false, error: "HTTP #{response.code}: #{response.body&.slice(0, 200)}" }
    end
  rescue => e
    { success: false, error: e.message }
  end

  private

  def crm_settings
    @crm_settings ||= CrmSetting.find_by(account: @account)
  end

  def configured?(config)
    config.is_a?(Hash) && config['measurement_id'].present? && config['api_secret'].present?
  end

  def build_event
    event = {
      name:   @event_name,
      params: base_params.merge(@params),
    }
    event
  end

  def base_params
    p = {
      engagement_time_msec: '1',
    }
    if @contact
      p[:contact_id]    = @contact.id.to_s
      p[:contact_name]  = @contact.name if @contact.name.present?
      p[:contact_phone] = @contact.phone_number if @contact.phone_number.present?
    end
    p
  end
end
