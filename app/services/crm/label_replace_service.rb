# Substitui uma etiqueta por outra em massa (contatos e conversas).
# Ex.: "refrativa" → "orçamento-refrativa": adiciona a nova e remove a antiga
# em todo mundo que tinha a antiga. Reversível só rodando o inverso.
class Crm::LabelReplaceService
  pattr_initialize [:account!, :from_label!, :to_label!]

  def preview
    {
      from: from,
      to: to,
      contacts: tagged_contacts.count,
      conversations: tagged_conversations.count
    }
  end

  def apply!
    return { contacts: 0, conversations: 0 } if from.blank? || to.blank? || from == to

    contacts = 0
    tagged_contacts.find_each do |contact|
      swap_labels(contact)
      contacts += 1
    end

    conversations = 0
    tagged_conversations.find_each do |conversation|
      swap_labels(conversation)
      conversations += 1
    end

    { contacts: contacts, conversations: conversations }
  end

  private

  def from
    @from ||= from_label.to_s.strip
  end

  def to
    @to ||= to_label.to_s.strip
  end

  def tagged_contacts
    account.contacts.tagged_with(from)
  end

  def tagged_conversations
    account.conversations.tagged_with(from)
  end

  def swap_labels(record)
    labels = record.label_list.map(&:to_s)
    return unless labels.include?(from)

    new_labels = (labels - [from] + [to]).uniq
    record.update_labels(new_labels)
  end
end
