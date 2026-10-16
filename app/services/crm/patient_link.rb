# 👪 ITEM 346 (15/10): "quando uma pessoa agenda para outra" (mãe → filho,
# Henrique → Ricardo). Pedido do Guilherme: o paciente ganha CADASTRO e CARD
# PRÓPRIOS (nome + telefone dele) e os dois ficam AMARRADOS — no painel de quem
# agendou aparece "agendou para Ricardo (nº)", no do paciente "quem agendou foi
# Henrique (nº)".
#
# Antes, a consulta da outra pessoa caía no contato de quem conversava (caso
# Francislene × Alice: a consulta da Alice morava na ficha da Francislene e o
# nome do contato virou "Francislene … E Alice …").
#
# Regras:
#   - telefone do paciente (com DDD) diferente do de quem agenda → acha o
#     cadastro dessa linha ou cria um novo com nome + telefone;
#   - sem telefone próprio (criança, idoso) ou o mesmo número de quem agenda →
#     cadastro só com o nome (o telefone é único por contato), reaproveitando o
#     que a MESMA pessoa já agendou antes com o mesmo nome. A consulta leva o
#     telefone de quem agendou: lembrete e confirmação vão para ele;
#   - o vínculo fica gravado nos dois contatos (additional_attributes):
#       paciente     'agendado_por' => { contact_id, name, phone, at }
#       quem agendou 'agendou_para' => [{ contact_id, name, phone, at }, …]
#     e numa linha da observação do card de cada um.
module Crm::PatientLink
  module_function

  MAX_LINKS = 20

  # devolve o contato do PACIENTE (nunca o de quem agenda)
  def patient_for!(account:, requester:, name:, phone:) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    phone = Crm::AppointmentOrigin.normalize_phone(phone)
    own_line = phone.present? && requester&.phone_number.present? &&
               Crm::AppointmentRecorder.same_phone_line?(phone.gsub(/\D/, ''), requester.phone_number)
    phone = nil if own_line

    patient = (phone && by_phone(account, phone, requester)) || (phone.nil? && earlier_dependent(account, requester, name))
    patient || create!(account, requester, name, phone)
  end

  # amarra os dois lados (idempotente: o mesmo par não repete)
  def link!(requester:, patient:) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return if requester.blank? || patient.blank? || requester.id == patient.id

    at = Time.current.iso8601
    Cevico::AttributeMerge.merge!(patient) do |attrs|
      attrs.merge('agendado_por' => entry(requester, at))
    end
    Cevico::AttributeMerge.merge!(requester) do |attrs|
      list = Array(attrs['agendou_para']).reject { |e| e['contact_id'].to_i == patient.id }
      attrs.merge('agendou_para' => ([entry(patient, at)] + list).first(MAX_LINKS))
    end
    note_on_cards(patient, "Agendado por #{requester.name}#{phone_suffix(requester)}")
    note_on_cards(requester, "Agendou para #{patient.name}#{phone_suffix(patient)}")
  rescue StandardError => e
    Rails.logger.warn "[Crm::PatientLink] vínculo #{requester&.id} → #{patient&.id}: #{e.message}"
  end

  # texto para a nota interna da conversa
  def summary(requester, patient)
    "agendado por #{requester&.name}#{phone_suffix(requester)} para #{patient.name}#{phone_suffix(patient)}"
  end

  def by_phone(account, phone, requester)
    found = Task.match_contact(account, phone)
    found unless found&.id == requester&.id
  end

  # mesma pessoa já agendou antes alguém com esse nome, sem telefone próprio
  def earlier_dependent(account, requester, name)
    return nil if requester.blank? || Crm::AppointmentRecorder.placeholder_name?(name)

    ids = Array(requester.additional_attributes&.dig('agendou_para')).filter_map { |e| e['contact_id'] }
    account.contacts.where(id: ids, phone_number: [nil, ''])
           .find { |c| Crm::AppointmentRecorder.same_patient_name?(name, c.name) }
  end

  def create!(account, requester, name, phone)
    attrs = { name: name.to_s.strip.presence || 'Paciente', additional_attributes: { 'origem' => 'agendado_por_outro' } }
    attrs[:phone_number] = phone if phone
    source = requester.try(:cevico_source_id)
    Crm::Stamp.with(via: 'robo', source: source) { account.contacts.create!(attrs) }
  rescue ActiveRecord::RecordInvalid
    # o telefone já existe com outra máscara: acha de novo antes de desistir
    (phone && by_phone(account, phone, requester)) || account.contacts.create!(attrs.except(:phone_number))
  end

  def entry(contact, at)
    { 'contact_id' => contact.id, 'name' => contact.name, 'phone' => contact.phone_number, 'at' => at }
  end

  def phone_suffix(contact)
    contact&.phone_number.present? ? " (#{contact.phone_number})" : ''
  end

  # uma linha na observação de cada card do contato (sem repetir)
  def note_on_cards(contact, line)
    Crm::Contact.where(contact_id: contact.id).find_each do |card|
      next if card.notes.to_s.include?(line)

      card.update_columns(notes: [card.notes.presence, "👪 #{line}"].compact.join("\n")) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
