# 📞 item 281 (29/09): QUEM está ligando — "pra gente entender melhor quem liga".
# Para cada contato devolve o que a atendente precisa ver ANTES de atender:
#   cards            = em que coluna do CRM o paciente está (nome + cor da etapa),
#                      um por funil, o que se mexeu por último primeiro
#   origin_inbox     = caixa de origem (a da 1ª conversa — Crm::PatientKind)
#   last_appointment = última consulta que já passou
#   next_appointment = próxima consulta marcada
# Sempre em lote (4 consultas no banco para a lista inteira, nunca 1 por chamada).
module Crm::Calls::PatientContext
  module_function

  MAX_CARDS = 3

  # { contact_id => { cards:, origin_inbox:, last_appointment:, next_appointment: } }
  def for_contacts(account, contact_ids)
    ids = Array(contact_ids).compact.uniq
    return {} if ids.empty?

    cards = cards_by_contact(account, ids)
    origins = Crm::PatientKind.origin_inbox_by_contact(account, ids)
    appointments = appointments_by_contact(account, ids)
    ids.index_with do |id|
      { cards: cards[id] || [], origin_inbox: origins[id] }.merge(appointments[id] || {})
    end
  end

  def for_contact(account, contact_id)
    for_contacts(account, [contact_id])[contact_id]
  end

  def cards_by_contact(account, ids)
    Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: account.id }, contact_id: ids)
                .includes(:stage, :pipeline).order(Arel.sql('crm_contacts.stage_moved_at DESC NULLS LAST'))
                .group_by(&:contact_id)
                .transform_values { |list| list.first(MAX_CARDS).map { |card| card_json(card) } }
  end

  def card_json(card)
    { pipeline_id: card.pipeline_id, pipeline_name: card.pipeline.name, stage_id: card.stage_id,
      stage_name: card.stage.name, stage_color: card.stage.color, stage_moved_at: card.stage_moved_at&.iso8601 }
  end

  # consultas de verdade: com data, não canceladas, sem os avisos "⚠️"
  def appointments_by_contact(account, ids)
    now = Time.current
    account.tasks.where(task_type: 'consulta', contact_id: ids, canceled_at: nil).where.not(due_at: nil)
           .where("title NOT LIKE '⚠️%'").order(:due_at).group_by(&:contact_id)
           .transform_values do |tasks|
      { last_appointment: appointment_json(tasks.reverse.find { |t| t.due_at <= now }),
        next_appointment: appointment_json(tasks.find { |t| t.due_at > now }) }
    end
  end

  def appointment_json(task)
    return nil unless task

    { id: task.id, at: task.due_at.iso8601, doctor: task.doctor, unit: task.unit, modality: task.modality,
      attendance: task.attendance }
  end
end
