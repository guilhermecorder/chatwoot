# Remove uma etiqueta em massa: de todos os contatos que a têm (e das
# conversas deles), opcionalmente só de quem está numa coluna do CRM.
# Ex.: remover "ABC" de todo mundo que está na coluna "123".
class Crm::LabelRemoveService
  pattr_initialize [:account!, :label!, :stage_id]

  def preview
    contacts = target_contacts
    {
      label: clean_label,
      contacts: contacts.count,
      sample: contacts.limit(5).map { |c| { id: c.id, name: c.name } }
    }
  end

  def apply!
    removed = 0
    target_contacts.find_each do |contact|
      strip_label(contact)
      contact.conversations.tagged_with(clean_label).find_each { |conv| strip_label(conv) }
      removed += 1
    end
    { contacts: removed }
  end

  private

  def clean_label
    @clean_label ||= label.to_s.strip
  end

  def target_contacts
    contacts = account.contacts.tagged_with(clean_label)
    if stage_id.present?
      stage_contact_ids = Crm::Contact.where(stage_id: stage_id).select(:contact_id)
      contacts = contacts.where(id: stage_contact_ids)
    end
    contacts
  end

  def strip_label(record)
    labels = record.label_list.map(&:to_s)
    return unless labels.include?(clean_label)

    record.update_labels(labels - [clean_label])
  end
end
