# ⚠️ ITEM 346 (15/10): todo paciente que NASCE (WhatsApp, Agenda, CRM, Nova
# conversa, OftalmoFácil, robô) passa por aqui. Se já existe alguém com o
# MESMO CELULAR (com ou sem o 9) ou o MESMO NOME COMPLETO, os dois ganham o
# alerta "possível duplicado" para a equipe conferir — nada é juntado sozinho.
class Crm::DuplicateWatchJob < ApplicationJob
  queue_as :low

  # sem acento no SQL (o nome "Simões" tem que achar "simoes")
  ACCENTS = "'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn'".freeze

  def perform(contact_id)
    contact = Contact.find_by(id: contact_id)
    return if contact.blank?

    line = same_line(contact)
    line.each { |other| flag_pair(contact, other, 'Mesmo celular (com ou sem o 9)') }
    (same_name(contact) - line).each { |other| flag_pair(contact, other, 'Mesmo nome completo, telefone diferente') }
    Crm::PatientReview.flag!(contact, 'duas_pessoas', contact.name) if Crm::PatientReview.two_people?(contact.name)
  end

  private

  def same_line(contact)
    digits = contact.phone_number.to_s.gsub(/\D/, '')
    return [] if digits.length < 8

    contact.account.contacts.where.not(id: contact.id)
           .where("regexp_replace(COALESCE(phone_number, ''), '\\D', '', 'g') LIKE ?", "%#{digits.last(8)}")
           .select { |other| Crm::AppointmentRecorder.same_phone_line?(digits, other.phone_number) }
           .first(5)
  end

  # nome completo igual, palavra por palavra (2+ palavras; acento e caixa não importam)
  def same_name(contact) # rubocop:disable Metrics/AbcSize
    words = Crm::AppointmentRecorder.name_words(contact.name)
    return [] if words.size < 2 || Crm::AppointmentRecorder.placeholder_name?(contact.name)

    contact.account.contacts.where.not(id: contact.id)
           .where("translate(LOWER(name), #{ACCENTS}) LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(words.max_by(&:length))}%")
           .limit(200)
           .select { |other| Crm::AppointmentRecorder.name_words(other.name).sort == words.sort }
           .select { |other| Crm::PatientReview.strong_name?(contact.name, [contact.id, other.id]) }
           .first(5)
  end

  def flag_pair(contact, other, why)
    Crm::PatientReview.flag!(contact, 'possivel_duplicado', "#{why}: #{other.name}#{phone(other)}", other_id: other.id)
    Crm::PatientReview.flag!(other, 'possivel_duplicado', "#{why}: #{contact.name}#{phone(contact)}", other_id: contact.id)
  end

  def phone(contact)
    contact.phone_number.present? ? " (#{contact.phone_number})" : ''
  end
end
