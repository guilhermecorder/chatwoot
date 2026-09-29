# 📊 item 277 (28/09): "agendamento de consulta pra mim é quando o card CHEGA
# na coluna Agendamento de Consulta — é exatamente esse dado que eu preciso;
# e preciso saber de quais caixas o lead veio, como foi, encontrá-lo".
# Quem ENTROU na coluna de agendamento no período (regra oficial do item 233),
# um por paciente, com: caixa de origem (1ª conversa), quando entrou, a consulta
# ligada (robô × equipe, data, presença) e onde o card está hoje.
class Crm::StageEntriesReport
  LIMIT = 600

  def initialize(account)
    @account = account
  end

  def call(since, until_at) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    stage = Crm::BookingRate.stage(@account)
    return { stage: nil, total: 0, rows: [], by_origin: [], by_outcome: [] } unless stage

    logs = Crm::BookingRate.entries(@account, since, until_at).order(:entered_at).includes(crm_contact: %i[contact stage])
    firsts = {}
    logs.each { |l| firsts[l.crm_contact_id] ||= l }
    cards = firsts.values.first(LIMIT).map(&:crm_contact).select(&:contact)
    contact_ids = cards.map(&:contact_id)
    origins = Crm::PatientKind.origin_inbox_by_contact(@account, contact_ids)
    consults = consults_by_contact(contact_ids)
    convs = last_conversation_ids(contact_ids)
    rows = cards.map do |card|
      log = firsts[card.id]
      t = consults[card.contact_id]
      {
        contact_id: card.contact_id, name: card.contact.name, phone: card.contact.phone_number,
        entered_at: log.entered_at, origin: origins[card.contact_id]&.dig(:name) || 'sem conversa',
        origin_id: origins[card.contact_id]&.dig(:id), stage_now: card.stage&.name, stage_now_color: card.stage&.color,
        conversation_id: convs[card.contact_id],
        consult: t && { task_id: t.id, due_at: t.due_at, unit: Crm::AgendaSlots::UNIT_LABELS[t.unit] || t.unit,
                        source: Crm::BookingSource.of(t), attendance: t.attendance, canceled: t.canceled_at.present?,
                        confirmed: t.confirmed_at.present? },
        outcome: outcome_of(t)
      }
    end
    {
      stage: { id: stage.id, name: stage.name, color: stage.color },
      total: rows.size,
      passages: logs.size,
      rows: rows,
      by_origin: group(rows) { |r| [r[:origin_id], r[:origin]] },
      by_outcome: OUTCOMES.map { |key, label| { key: key, label: label, count: rows.count { |r| r[:outcome] == key } } }
                          .reject { |o| o[:count].zero? },
      by_source: { ia: rows.count { |r| r.dig(:consult, :source) == 'ia' },
                   equipe: rows.count { |r| r.dig(:consult, :source) == 'equipe' },
                   sem_consulta: rows.count { |r| r[:consult].nil? } }
    }
  end

  OUTCOMES = {
    'attended' => 'compareceu',
    'missed' => 'faltou',
    'canceled' => 'cancelou',
    'confirmed' => 'confirmou (SIM)',
    'scheduled' => 'consulta marcada, ainda vai acontecer',
    'past_unknown' => 'consulta passou, sem registro de presença',
    'no_consult' => 'entrou na coluna, mas SEM consulta na Agenda'
  }.freeze

  private

  # a consulta da Agenda mais próxima da entrada na coluna (a última criada)
  def consults_by_contact(ids)
    return {} if ids.empty?

    @account.tasks.where(task_type: 'consulta', contact_id: ids, archived_at: nil)
            .where("title NOT LIKE '⚠️%'")
            .where("modality IS NULL OR modality NOT IN ('teleconsulta', 'exames')")
            .order(:created_at).index_by(&:contact_id)
  end

  def last_conversation_ids(ids)
    return {} if ids.empty?

    Conversation.where(account_id: @account.id, contact_id: ids)
                .select('DISTINCT ON (contact_id) contact_id, display_id').order('contact_id, last_activity_at DESC NULLS LAST')
                .to_h { |c| [c.contact_id, c.display_id] }
  end

  def outcome_of(task) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return 'no_consult' unless task
    return 'canceled' if task.canceled_at
    return 'attended' if task.attendance == 'attended'
    return 'missed' if task.attendance == 'missed'
    return 'confirmed' if task.confirmed_at && task.due_at && task.due_at > Time.current
    return 'scheduled' if task.due_at && task.due_at > Time.current

    'past_unknown'
  end

  def group(rows, &)
    groups = rows.group_by(&).map do |(id, name), list|
      { inbox_id: id, name: name, count: list.size, contact_ids: list.map { |r| r[:contact_id] } }
    end
    groups.sort_by { |h| -h[:count] }
  end
end
