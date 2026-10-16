# ⚠️ ITEM 346 (15/10): CONFERÊNCIA MANUAL de cadastro. Decisão do Guilherme:
# quando o sistema não tem CERTEZA de que dois cadastros são a mesma pessoa,
# ele não junta nem troca nada sozinho — cria/mantém e deixa um alerta para os
# admins e o responsável conferirem ("possível duplicado", "nome diferente no
# mesmo telefone" — mãe que agenda para o filho —, "CPF diferente"...).
#
# O alerta mora no próprio contato (additional_attributes['cevico_conferir'],
# sem migration) e aparece no Espaço do Paciente; o ambiente "Notificações
# sobre agendamentos" (etapa 3) lê a mesma lista.
module Crm::PatientReview
  module_function

  KEY = 'cevico_conferir'.freeze
  MAX = 10
  TYPES = {
    'possivel_duplicado' => 'Possível duplicado',
    'nome_diferente' => 'Nome diferente no mesmo telefone',
    'cpf_diferente' => 'CPF diferente',
    'duas_pessoas' => 'Duas pessoas no mesmo cadastro'
  }.freeze

  # grava (ou atualiza) um alerta; o mesmo tipo + mesmo outro contato não repete
  def flag!(contact, type, detail, other_id: nil) # rubocop:disable Metrics/CyclomaticComplexity
    return if contact.blank? || TYPES.exclude?(type)

    entry = { 'tipo' => type, 'titulo' => TYPES[type], 'detalhe' => detail.to_s.truncate(240),
              'outro_contact_id' => other_id, 'at' => Time.current.iso8601 }
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      list = Array(attrs[KEY]).reject { |e| e['tipo'] == type && e['outro_contact_id'] == other_id }
      attrs.merge(KEY => ([entry] + list).first(MAX))
    end
  rescue StandardError => e
    Rails.logger.warn "[Crm::PatientReview] #{contact&.id} #{type}: #{e.message}"
  end

  def list(contact)
    Array(contact&.additional_attributes&.dig(KEY))
  end

  # o primeiro nome bate? ("Fran" × "Francislene" bate; nome vazio/"Paciente" também)
  def compatible_names?(one, other)
    return true if Crm::AppointmentRecorder.placeholder_name?(one) || Crm::AppointmentRecorder.placeholder_name?(other)

    a = Crm::AppointmentRecorder.name_words(one).first.to_s
    b = Crm::AppointmentRecorder.name_words(other).first.to_s
    short, long = [a, b].sort_by(&:length)
    short.length >= 3 && long.start_with?(short)
  end

  # 📋 levantamento de 15/10 (307 grupos de "mesmo nome"): nome de 2 palavras
  # repete muito entre pessoas diferentes ("Ana Lucia" ×6, "Felipe Silva").
  # Nome igual só vira alerta com 3+ palavras, ou com 2 palavras quando TODOS
  # já têm agendamento na Agenda (caso Samuel de Andrade: os dois em cirurgia).
  def strong_name?(name, contact_ids)
    words = Crm::AppointmentRecorder.name_words(name).size
    return true if words >= 3
    return false if words < 2

    Task.where(contact_id: contact_ids).distinct.count(:contact_id) == contact_ids.uniq.size
  end

  # "Francislene Pereira Borges E Alice Quadros Schimit": dois nomes completos
  def two_people?(name)
    parts = name.to_s.split(/\s+e\s+/i)
    parts.size >= 2 && parts.all? { |part| Crm::AppointmentRecorder.name_words(part).size >= 2 }
  end
end
