# Busca o NOME do anúncio (nomenclatura interna do Gerenciador de Anúncios)
# pelo ad_id, via Marketing API. O referral do webhook só traz o título do
# criativo — o nome interno é o que a equipe usa para ajustar nomenclatura.
# Cacheado por 7 dias para não bater na API a cada lead.
class Crm::AdNameLookupService
  BASE_URI = 'https://graph.facebook.com'.freeze

  def initialize(account:)
    @account = account
  end

  def name_for(ad_id)
    return nil if ad_id.blank? || access_token.blank?

    Rails.cache.fetch("crm:meta_ad_name:#{ad_id}", expires_in: 7.days, skip_nil: true) do
      fetch_name(ad_id)
    end
  end

  private

  def fetch_name(ad_id)
    response = HTTParty.get(
      "#{BASE_URI}/#{api_version}/#{ad_id}",
      query: { fields: 'name', access_token: access_token },
      timeout: 10
    )
    response.success? ? response.parsed_response['name'] : nil
  rescue StandardError => e
    Rails.logger.error "[Crm::AdNameLookup] #{e.message}"
    nil
  end

  def access_token
    @access_token ||= (CrmSetting.find_by(account: @account)&.meta_ads_config || {})['access_token']
  end

  def api_version
    GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
  end
end
