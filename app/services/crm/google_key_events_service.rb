# Item 313: quais eventos estão marcados como EVENTO-CHAVE na propriedade do
# GA4 — evento que a CEVICO envia e que não é evento-chave morre no Analytics
# (o Google Ads só importa evento-chave). Lê pela API de administração do GA4
# com a MESMA conta de serviço do custo automático (Leitor já basta); a API
# "Google Analytics Admin API" precisa estar ativada no projeto do Google Cloud.
class Crm::GoogleKeyEventsService < Crm::GoogleAdCostService
  ADMIN_API = 'https://analyticsadmin.googleapis.com/v1beta'.freeze

  def initialize(account:)
    super(account: account, since_date: Date.current)
  end

  def call
    return { configured: false } unless configured?

    token = access_token
    return { configured: true, error: @auth_error || 'Falha na autenticação com o Google' } if token.blank?

    response = HTTParty.get(
      "#{ADMIN_API}/properties/#{property_id}/keyEvents?pageSize=200",
      headers: { 'Authorization' => "Bearer #{token}" },
      timeout: 15
    )
    return { configured: true, error: admin_error(response) } unless response.success?

    { configured: true, key_events: Array(response.parsed_response['keyEvents']).filter_map { |k| k['eventName'].presence } }
  rescue StandardError => e
    Rails.logger.error "[Crm::GoogleKeyEventsService] #{e.class}: #{e.message}"
    { configured: true, error: e.message }
  end

  private

  def admin_error(response)
    message = response.parsed_response&.dig('error', 'message').presence || "HTTP #{response.code}"
    return message unless response.code == 403

    "#{message} — ative a \"Google Analytics Admin API\" no Google Cloud (mesmo projeto da conta de serviço)"
  end
end
