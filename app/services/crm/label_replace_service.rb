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

  # 🏷️ Rodada 5 (#17): troca em massa NÃO dispara as automações "Etiqueta
  # adicionada/removida" (senão cada paciente atingido viraria uma mensagem
  # paga, webhook ou conversão). A etiqueta da conversa que sobe ao contato
  # também fica muda, porque roda dentro do mesmo bloco.
  def apply!
    return { contacts: 0, conversations: 0 } if from.blank? || to.blank? || from == to

    Contact.without_label_triggers do
      { contacts: swap_all(tagged_contacts), conversations: swap_all(tagged_conversations) }
    end
  end

  private

  def swap_all(scope)
    count = 0
    scope.find_each do |record|
      swap_labels(record)
      count += 1
    end
    count
  end

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
