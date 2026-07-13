# Completa a atribuição de anúncio com o NOME interno do anúncio (Gerenciador),
# buscado na Marketing API em background — o webhook não espera a API da Meta.
# Sem conversation_id, enriquece também todas as conversas carimbadas do contato
# (caminho do retroativo).
class Crm::AdAttributionEnrichJob < ApplicationJob
  queue_as :low

  def perform(contact_id, conversation_id = nil)
    contact = Contact.find_by(id: contact_id)
    return unless contact

    lookup = Crm::AdNameLookupService.new(account: contact.account)

    records = [contact]
    records += if conversation_id
                 [Conversation.find_by(id: conversation_id)].compact
               else
                 contact.conversations.where("additional_attributes -> 'meta_ads' IS NOT NULL").to_a
               end

    records.each { |record| enrich(record, lookup) }
  end

  private

  def enrich(record, lookup)
    meta = record.additional_attributes&.[]('meta_ads')
    return if meta.blank? || meta['ad_name'].present? || meta['source_id'].blank?

    name = lookup.name_for(meta['source_id'])
    return if name.blank?

    record.update!(
      additional_attributes: record.additional_attributes.merge('meta_ads' => meta.merge('ad_name' => name))
    )
  rescue StandardError => e
    Rails.logger.error "[Crm::AdAttributionEnrich] #{record.class}##{record.id}: #{e.message}"
  end
end
