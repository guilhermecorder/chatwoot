class Contacts::BulkRemoveLabelsService
  def initialize(account:, contact_ids:, labels:)
    @account = account
    @contact_ids = Array(contact_ids)
    @labels = Array(labels).compact_blank
  end

  def perform
    return { success: true, updated_contact_ids: [] } if @contact_ids.blank? || @labels.blank?

    contacts = @account.contacts.where(id: @contact_ids)

    # CEVICO Rodada 5 (#17): etiqueta em lote não dispara automações de etiqueta
    Contact.without_label_triggers do
      contacts.find_each do |contact|
        contact.update!(label_list: contact.label_list - @labels)
      end
    end

    { success: true, updated_contact_ids: contacts.pluck(:id) }
  end
end
