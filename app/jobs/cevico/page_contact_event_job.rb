# Clique no botão do WhatsApp de uma página → "Contact" na Meta pelo SERVIDOR.
#
# O Pixel do navegador dispara o mesmo Contact, mas o clique leva o paciente
# para o WhatsApp na hora e o aviso do Pixel se perde no caminho (19/10: zero
# Contact em 28 dias com 21 mil visitas). Daqui ele sai sempre. O Protocolo é
# o event_id dos dois lados, então a Meta conta UM só quando os dois chegam.
class Cevico::PageContactEventJob < ApplicationJob
  # chamada curta; quanto antes a Meta recebe, melhor ela aprende com o clique
  queue_as :default

  def perform(ref_id, web = {})
    ref = CevicoPageRef.find_by(id: ref_id)
    return if ref.nil?

    data = ref.source_data || {}
    web = web.to_h.symbolize_keys.merge(fbp: data['fbp'], fbc: data['fbc']).compact_blank
    page = ref.cevico_page
    # o mesmo nome/categoria que o Pixel da página usa (_analytics_snippet)
    custom = { content_name: page&.slug || 'hub', content_category: page&.category.presence || 'hub' }

    result = MetaAdsConversionsService.new(account: ref.account, event_name: 'Contact', custom_data: custom,
                                           event_id: ref.token, web: web).call
    Rails.logger.warn "[PageContactEvent] Protocolo #{ref.token}: #{result[:error]}" unless result[:success]
  end
end
