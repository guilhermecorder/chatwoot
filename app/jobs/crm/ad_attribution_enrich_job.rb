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

  # Rodada 4 da auditoria (#66/#174/#229): o nome é buscado na Meta ANTES de
  # entrar na trava (a chamada HTTP pode levar segundos) e a gravação é pelo
  # Cevico::AttributeMerge — o update! cru gravava a coluna inteira a partir de
  # uma foto velha e apagava pausa da IA, marca de follow-up e lembrete gravados
  # nesse intervalo (mesmo buraco do incidente de julho).
  def enrich(record, lookup)
    meta = record.additional_attributes&.[]('meta_ads')
    return unless needs_name?(meta)

    name = lookup.name_for(meta['source_id'])
    return if name.blank?

    Cevico::AttributeMerge.merge!(record) do |attrs|
      fresh = attrs['meta_ads']
      # alguém já completou (ou tirou) o carimbo enquanto a Meta respondia: não mexe
      next attrs unless needs_name?(fresh)

      attrs.merge('meta_ads' => fresh.merge('ad_name' => name))
    end
  rescue StandardError => e
    Rails.logger.error "[Crm::AdAttributionEnrich] #{record.class}##{record.id}: #{e.message}"
  end

  # carimbo presente, ainda sem nome e com o id do anúncio para perguntar
  def needs_name?(meta)
    meta.present? && meta['ad_name'].blank? && meta['source_id'].present?
  end
end
