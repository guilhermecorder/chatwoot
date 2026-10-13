# Unifica contatos duplicados da conta (mesmo telefone ou mesmo e-mail),
# preservando conversas, mensagens, notas e etiquetas (união) — usa o
# ContactMergeAction do core. Sempre rode preview antes de apply!.
#
# 🔒 Rodada 6 (#200):
#   - e-mail igual é critério FRACO: só junta se também bater o MESMO nome
#     (2+ palavras, sem "parecido") ou a mesma linha de telefone (mãe e filho,
#     pai e "Filho/Júnior" com o mesmo e-mail deixam de virar uma pessoa só).
#   - o merge leva card, consultas, anotações etc. (Cevico::ContactMergeRecords).
#   - as falhas voltam para a tela: o resultado da última unificação (com quem
#     falhou e por quê) fica guardado e aparece no `preview` como `last_run`.
class Crm::ContactUnificationService
  pattr_initialize [:account!]

  LAST_RUN_TTL = 30.days
  MAX_FAILURES_SHOWN = 50

  def self.last_run_key(account_id)
    "cevico:contact_unification:last_run:#{account_id}"
  end

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
      end,
      last_run: last_run
    }
  end

  # resultado da última unificação aplicada (nil se nunca rodou / expirou)
  def last_run
    raw = Redis::Alfred.get(self.class.last_run_key(account.id))
    raw.present? ? JSON.parse(raw) : nil
  rescue JSON::ParserError
    nil
  end

  # 🏷️ Rodada 5 (#17): juntar as etiquetas do duplicado na base NÃO dispara
  # as automações "Etiqueta adicionada" (é limpeza de cadastro em massa).
  def apply!
    result = Contact.without_label_triggers { merge_all }
    save_last_run(result)
    result
  end

  private

  def merge_all
    merged = 0
    failures = []
    duplicate_groups.each do |group|
      # recarrega com todos os atributos (a listagem usa select parcial)
      base_partial = pick_base(group)
      base = account.contacts.find(base_partial.id)
      (group - [base_partial]).each do |partial|
        merge_pair!(base, account.contacts.find(partial.id))
        merged += 1
      rescue StandardError => e
        # a transação voltou, mas o objeto em memória pode ter ficado com os
        # dados do duplicado: relê para o próximo merge não gravar lixo
        base.reload
        failures << failure_entry(partial, base_partial, e)
        Rails.logger.error("[CEVICO unify] falha ao mesclar contato #{partial.id} em #{base_partial.id}: #{e.message}")
      end
    end
    { merged: merged, failed: failures.size, failures: failures }
  end

  # etiquetas só depois do merge dar certo (antes, a base ganhava as
  # etiquetas do duplicado mesmo quando a mesclagem falhava)
  def merge_pair!(base, mergee)
    labels = mergee.label_list
    ContactMergeAction.new(account: account, base_contact: base, mergee_contact: mergee).perform
    base.add_labels(labels)
  end

  def failure_entry(partial, base_partial, error)
    {
      contact_id: partial.id, name: partial.name,
      base_contact_id: base_partial.id, base_name: base_partial.name,
      reason: "#{error.class.name.demodulize}: #{error.message.to_s.truncate(200)}"
    }
  end

  def save_last_run(result)
    payload = result.merge(at: Time.current.iso8601, failures: result[:failures].first(MAX_FAILURES_SHOWN))
    Redis::Alfred.setex(self.class.last_run_key(account.id), payload.to_json, LAST_RUN_TTL.to_i)
  rescue StandardError => e
    Rails.logger.error("[CEVICO unify] não consegui guardar o resultado: #{e.message}")
  end

  # grupos de contatos com o mesmo telefone (só dígitos) ou mesmo e-mail
  # + mesmo nome/telefone (e-mail sozinho não basta — ver email_groups)
  def duplicate_groups
    phone_groups.values + email_groups
  end

  # memoizado: duplicate_groups e email_groups chamavam isto, varrendo os ~20k
  # contatos DUAS vezes por preview/apply
  def phone_groups
    @phone_groups ||= begin
      contacts = account.contacts.where.not(phone_number: [nil, '']).select(:id, :name, :phone_number, :email, :created_at)
      contacts.group_by { |c| c.phone_number.gsub(/\D/, '') }
              .select { |digits, group| digits.present? && group.size > 1 }
    end
  end

  # duplicados por e-mail que ainda não foram pegos pelo telefone.
  # 🔒 Rodada 6 (#200): e-mail igual é critério FRACO — dentro do mesmo e-mail
  # só vira grupo quem também tem o MESMO nome ou a MESMA linha de telefone
  # (família que usa um e-mail só = pessoas diferentes, dado clínico separado).
  def email_groups
    phone_ids = phone_groups.values.flatten.to_set(&:id)
    contacts = account.contacts.where.not(email: [nil, '']).select(:id, :name, :phone_number, :email, :created_at)
    contacts.reject { |c| phone_ids.include?(c.id) }
            .group_by { |c| c.email.downcase.strip }
            .select { |email, group| email.present? && group.size > 1 }
            .values.flat_map { |group| split_by_person(group) }
  end

  # separa um grupo de mesmo e-mail em "mesma pessoa" (nome ou telefone batem).
  # Junta por "corrente": se A bate com B e B bate com C, os três são um grupo
  # só, não importa a ordem em que vieram da lista.
  def split_by_person(group)
    leader = group.to_h { |contact| [contact.id, contact.id] }
    find = ->(id) { leader[id] == id ? id : (leader[id] = find.call(leader[id])) }
    group.combination(2) do |one, other|
      leader[find.call(one.id)] = find.call(other.id) if same_person?(one, other)
    end
    group.group_by { |contact| find.call(contact.id) }.values.select { |members| members.size > 1 }
  end

  def same_person?(one, other)
    same_phone?(one, other) || same_name?(one.name, other.name)
  end

  def same_phone?(one, other)
    digits = one.phone_number.to_s.gsub(/\D/, '')
    digits.length >= 8 && Crm::AppointmentRecorder.same_phone_line?(digits, other.phone_number)
  end

  # Nome só prova "mesma pessoa" quando é o MESMO nome, palavra por palavra
  # (ordem e acento não importam), com pelo menos 2 palavras. Nome parecido NÃO
  # basta: pai "Jose Carlos Santos" e filho "Jose Carlos Santos Filho", ou a mãe
  # "Maria" (nome do WhatsApp) e a filha "Maria Eduarda Souza", usando o mesmo
  # e-mail, continuam sendo pessoas diferentes (anotações e consultas separadas).
  def same_name?(one, other)
    # nome vazio / "Paciente" não prova nada
    return false if Crm::AppointmentRecorder.placeholder_name?(one) || Crm::AppointmentRecorder.placeholder_name?(other)

    one_words = Crm::AppointmentRecorder.name_words(one).sort
    one_words.size >= 2 && one_words == Crm::AppointmentRecorder.name_words(other).sort
  end

  # base = contato com mais conversas; empate → o mais antigo
  def pick_base(group)
    counts = Conversation.where(contact_id: group.map(&:id)).group(:contact_id).count
    group.min_by { |c| [-(counts[c.id] || 0), c.created_at] }
  end
end
