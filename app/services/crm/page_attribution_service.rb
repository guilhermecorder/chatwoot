# Fecha o ciclo do rastreamento das Páginas: a primeira mensagem do
# paciente chega com "Protocolo: 3F9K2" (gerado no clique do WhatsApp na
# página) → carimba no contato e na conversa a página + anúncio de origem
# (page_ads: Google Ads/gclid, Google orgânico, Meta, campanha...).
#
# Mesma regra do CTWA (Crm::AdAttributionService): PRIMEIRO TOQUE — se o
# contato já tem page_ads, não sobrescreve; a conversa ganha o carimbo
# quando ainda não tem. page_ads e meta_ads convivem (chaves separadas).
class Crm::PageAttributionService
  def initialize(contact:, text:, conversation: nil)
    @contact = contact
    @conversation = conversation
    @text = text.to_s
  end

  def call
    return if @contact.blank? || @text.blank?

    ref = CevicoPageRef.find_in_text(@contact.account, @text)
    return if ref.blank?

    stamp(@conversation, ref) if @conversation
    stamp(@contact, ref)
    # liga o protocolo ao contato (primeiro que usar o código leva)
    ref.update(contact_id: @contact.id) if ref.contact_id.nil?
  rescue StandardError => e
    Rails.logger.error "[Crm::PageAttribution] #{e.class}: #{e.message}"
  end

  private

  def attribution_data(ref)
    ref.source_data.merge(
      'token' => ref.token,
      'clicked_at' => ref.created_at.iso8601,
      'captured_at' => Time.current.iso8601
    )
  end

  def stamp(record, ref)
    return if (record.additional_attributes || {})['page_ads'].present? # primeiro toque vence

    # merge atômico: não pode apagar chaves concorrentes (follow-up, pausa,
    # perfil do paciente, meta_ads do CTWA)
    Cevico::AttributeMerge.merge!(record) do |attrs|
      attrs['page_ads'].present? ? attrs : attrs.merge('page_ads' => attribution_data(ref))
    end
  rescue StandardError => e
    Rails.logger.error "[Crm::PageAttribution] #{record.class}##{record.id}: #{e.message}"
  end
end
