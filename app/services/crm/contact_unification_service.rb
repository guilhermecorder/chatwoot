# Unifica contatos duplicados da conta (mesmo telefone ou mesmo e-mail),
# preservando conversas, mensagens, notas e etiquetas (união) — usa o
# ContactMergeAction do core. Sempre rode preview antes de apply!.
class Crm::ContactUnificationService
  pattr_initialize [:account!]

  def preview
    groups = duplicate_groups
    {
      groups: groups.size,
      contacts_to_merge: groups.sum { |g| g.size - 1 },
      examples: groups.first(15).map do |g|
        base = pick_base(g)
        {
          name: base.name,
          phone_number: base.phone_number,
          email: base.email,
          duplicates: g.size,
          names: g.map(&:name).uniq
        }
      end
    }
  end

  def apply!
    merged = 0
    failed = 0
    duplicate_groups.each do |group|
      # recarrega com todos os atributos (a listagem usa select parcial)
      base_partial = pick_base(group)
      base = account.contacts.find(base_partial.id)
      (group - [base_partial]).each do |partial|
        mergee = account.contacts.find(partial.id)
        base.add_labels(mergee.label_list)
        ContactMergeAction.new(account: account, base_contact: base, mergee_contact: mergee).perform
        merged += 1
      rescue StandardError => e
        failed += 1
        Rails.logger.error("[CEVICO unify] falha ao mesclar contato #{partial.id} em #{base.id}: #{e.message}")
      end
    end
    { merged: merged, failed: failed }
  end

  private

  # grupos de contatos com o mesmo telefone (só dígitos) ou mesmo e-mail
  def duplicate_groups
    phone_groups.values + email_groups.values
  end

  def phone_groups
    contacts = account.contacts.where.not(phone_number: [nil, '']).select(:id, :name, :phone_number, :email, :created_at)
    contacts.group_by { |c| c.phone_number.gsub(/\D/, '') }
            .select { |digits, group| digits.present? && group.size > 1 }
  end

  # duplicados por e-mail que ainda não foram pegos pelo telefone
  def email_groups
    phone_ids = phone_groups.values.flatten.map(&:id).to_set
    contacts = account.contacts.where.not(email: [nil, '']).select(:id, :name, :phone_number, :email, :created_at)
    contacts.reject { |c| phone_ids.include?(c.id) }
            .group_by { |c| c.email.downcase.strip }
            .select { |email, group| email.present? && group.size > 1 }
  end

  # base = contato com mais conversas; empate → o mais antigo
  def pick_base(group)
    counts = Conversation.where(contact_id: group.map(&:id)).group(:contact_id).count
    group.min_by { |c| [-(counts[c.id] || 0), c.created_at] }
  end
end
