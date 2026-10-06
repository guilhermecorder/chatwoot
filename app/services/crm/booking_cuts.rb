# 🧭 TUDO O QUE FOI MARCADO NO PERÍODO, aberto em três cortes (item 328, Fase 2
# das Fontes — 05/10). Pedido do Guilherme: no indicador de agendamentos ele
# quer o VOLUME TOTAL e entender de onde veio — "quantos foram apenas mudança
# de coluna, ou pós-op, ou o que quer que seja, e também as origens
# (oftalmofácil, cevico, google, instagram, consulta particular etc.)".
#
# O que entra na conta (sempre dentro da lente da fonte escolhida):
#   · agendamento NOVO criado na Agenda no período (consulta ou cirurgia),
#     marcado para a frente e não cancelado;
#   · card que ENTROU na coluna de agendamento do CRM no período SEM consulta
#     na Agenda criada naqueles dias = "só mudança de coluna".
# Ficam de fora, mas aparecem contados ao lado: consulta LANÇADA (já estava
# marcada fora do sistema, item 217) e lançamento de HISTÓRICO (a data já
# tinha passado quando foi criado).
#
# Os três cortes:
#   o que foi    avaliação · retorno · pós-operatório · exame · teleconsulta ·
#                cirurgia · só mudança de coluna
#   de onde veio a fonte (carimbo: CEVICO × Oftalmofácil…), a caixa por onde o
#                paciente chegou (1ª conversa: Google, Instagram…) e particular
#   quem fez     paciente · robô · equipe · sincronização · carga · integração
#                (`cevico_born_via`). O carimbo existe desde 05/10/2026: no
#                agendamento anterior o "quem fez" é deduzido pela marca do
#                Atendente de IA na consulta; na mudança de coluna anterior não
#                há como saber ("antes do carimbo").
#
# Cada linha traz o paciente — nenhum número sem nome atrás.
class Crm::BookingCuts
  ROW_LIMIT = 500
  MATCH_WINDOW = 1.day # consulta criada até 1 dia antes/depois da mudança de coluna = é a mesma marcação
  KINDS = {
    'avaliacao' => 'Avaliação (1ª consulta)', 'retorno' => 'Retorno', 'pos_op' => 'Pós-operatório',
    'exames' => 'Exame', 'teleconsulta' => 'Teleconsulta', 'cirurgia' => 'Cirurgia',
    'consulta' => 'Consulta sem tipo informado',
    'coluna' => 'Só mudança de coluna no CRM'
  }.freeze
  VIAS = {
    'paciente' => 'Paciente (formulário ou link)', 'robo' => 'Robô (IA e automações)',
    'equipe' => 'Equipe', 'sync' => 'Sincronização do Oftalmofácil', 'carga' => 'Carga em lote',
    'integracao' => 'Integração de fora (N8N)', 'antes' => 'Antes do carimbo'
  }.freeze
  TASK_COLUMNS = %w[
    tasks.id tasks.contact_id tasks.task_type tasks.modality tasks.booking_kind tasks.created_at tasks.due_at
    tasks.particular tasks.cevico_source_id tasks.cevico_born_via tasks.source tasks.source_detail tasks.origin
    tasks.title tasks.phone
  ].freeze

  def initialize(account, lens:)
    @account = account
    @lens = lens
  end

  def call(since, until_at)
    outside = { registered: 0, history: 0 }
    rows = agenda_rows(since, until_at, outside)
    agenda = rows.size
    rows.concat(column_rows(since, until_at))
    inboxes = Crm::PatientKind.origin_inbox_by_contact(@account, rows.filter_map { |r| r[:contact_id] })
    rows.each { |r| r[:inbox] = inbox_of(r, inboxes) }
    summary(rows, agenda, outside).merge(cuts(rows, inboxes)).merge(people(rows, inboxes))
  end

  private

  def summary(rows, agenda, outside)
    { total: rows.size, agenda: agenda, column_only: rows.size - agenda, outside: outside,
      deduced: rows.count { |r| r[:deduced] }, source: @lens.key, source_label: @lens.label }
  end

  def cuts(rows, inboxes)
    { what: slices(rows, :what) { |key| KINDS[key] },
      sources: source_slices(rows),
      inboxes: slices(rows, :inbox) { |key| inbox_label(key, inboxes) },
      particular: { yes: rows.count { |r| r[:particular] }, no: rows.count { |r| r[:task_id] && !r[:particular] } },
      who: slices(rows, :via) { |key| VIAS[key] } }
  end

  # ── agendamentos novos da Agenda ───────────────────────────────────────
  def agenda_rows(since, until_at, outside)
    registered, rest = created_tasks(since, until_at).partition { |t| t[:booking_kind] == 'registro' }
    history, fresh = rest.partition { |t| t[:due_at] && t[:due_at] < t[:created_at] }
    outside[:registered] = registered.size
    outside[:history] = history.size
    fresh.map { |task| agenda_row(task) }
  end

  # consultas e cirurgias criadas no período, só as colunas que os cortes usam
  def created_tasks(since, until_at)
    keys = TASK_COLUMNS.map { |c| c.delete_prefix('tasks.').to_sym }
    @lens.tasks(@account.tasks).where(task_type: Task::APPOINTMENT_TYPES, created_at: since..until_at, canceled_at: nil)
         .where("tasks.title NOT LIKE '⚠️%'")
         .pluck(*TASK_COLUMNS.map { |c| Arel.sql(c) }, Arel.sql("(#{Crm::BookingSource::SQL_IA})"))
         .map { |values| keys.zip(values).to_h.merge(ia: values.last) }
  end

  def agenda_row(task)
    via, deduced = task_via(task)
    { key: "t#{task[:id]}", task_id: task[:id], contact_id: task[:contact_id], at: task[:created_at], due_at: task[:due_at],
      what: task_kind(task), source: source_key(task[:cevico_source_id] || legacy_task_source_id(task)),
      via: via, deduced: deduced, particular: task[:particular] == true,
      fallback_name: patient_name(task[:title]), fallback_phone: task[:phone] }
  end

  def task_kind(task)
    return 'cirurgia' if task[:task_type] == 'cirurgia'

    KINDS.key?(task[:modality]) ? task[:modality] : 'consulta'
  end

  # quem fez: o carimbo; sem carimbo (antes de 05/10), a marca do Atendente de IA
  def task_via(task)
    return [task[:cevico_born_via], false] if VIAS.key?(task[:cevico_born_via])
    return ['sync', false] if task[:source] == 'oftalmofacil'

    [task[:ia] ? 'robo' : 'equipe', true]
  end

  # mesma regra de quem carimba o passado (Crm::SourceBackfill)
  def legacy_task_source_id(task)
    partner = task[:origin] == 'oftalmofacil' || (task[:source] == 'oftalmofacil' && task[:source_detail].present?)
    partner ? Crm::Sources.id_for_key(@account, Crm::Source::PARTNER_KEY) : Crm::Sources.own_id(@account)
  end

  def patient_name(title)
    title.to_s.sub(/\A(Consulta|Teleconsulta|Exame|Cirurgia|Retorno|P[oó]s-operat[oó]rio):\s*/i, '').delete('✅').strip
  end

  # ── só mudança de coluna ───────────────────────────────────────────────
  def column_rows(since, until_at)
    firsts = {}
    Crm::BookingRate.entries(@account, since, until_at, lens: @lens).joins(:crm_contact).order(:entered_at)
                    .pluck('crm_contact_stage_logs.crm_contact_id', 'crm_contacts.contact_id', 'crm_contacts.pipeline_id',
                           'crm_contact_stage_logs.entered_at', 'crm_contact_stage_logs.cevico_source_id',
                           'crm_contact_stage_logs.cevico_born_via')
                    .each { |row| firsts[row[0]] ||= row }
    booked = contacts_with_consult(firsts.values.pluck(1), since, until_at)
    firsts.values.reject { |row| booked.include?(row[1]) }.map { |row| column_row(row) }
  end

  def contacts_with_consult(contact_ids, since, until_at)
    ids = contact_ids.compact.uniq
    return Set.new if ids.empty?

    @account.tasks.where(task_type: 'consulta', contact_id: ids, created_at: (since - MATCH_WINDOW)..(until_at + MATCH_WINDOW))
            .distinct.pluck(:contact_id).to_set
  end

  def column_row(row)
    card_id, contact_id, pipeline_id, entered_at, source_id, via = row
    { key: "c#{card_id}", contact_id: contact_id, at: entered_at, what: 'coluna',
      source: source_key(source_id || Crm::Sources.id_for_pipeline(@account, pipeline_id)),
      via: VIAS.key?(via) ? via : 'antes', deduced: false, particular: false }
  end

  # ── cortes ─────────────────────────────────────────────────────────────
  def sources_by_id
    @sources_by_id ||= Crm::Sources.list(@account).index_by(&:id)
  end

  def source_key(id)
    sources_by_id[id]&.key || Crm::Source::OWN_KEY
  end

  def source_slices(rows)
    counts = rows.group_by { |r| r[:source] }.transform_values(&:size)
    sources_by_id.values.filter_map do |source|
      n = counts[source.key].to_i
      { key: source.key, label: source.name, color: source.color, count: n } if n.positive?
    end
  end

  def slices(rows, field)
    rows.group_by { |r| r[field] }.map { |key, list| { key: key, label: yield(key), count: list.size } }
        .sort_by { |slice| -slice[:count] }
  end

  def inbox_of(row, inboxes)
    return 'sem_cadastro' if row[:contact_id].blank?

    inboxes[row[:contact_id]]&.dig(:id) || 'sem_conversa'
  end

  def inbox_label(key, inboxes)
    return 'Sem cadastro de paciente' if key == 'sem_cadastro'
    return 'Sem conversa no sistema' if key == 'sem_conversa'

    inboxes.values.find { |i| i[:id] == key }&.dig(:name) || 'Caixa removida'
  end

  # ── a lista de pacientes por trás dos números (as mais recentes) ──────
  def people(rows, inboxes)
    shown = rows.sort_by { |r| r[:at] }.last(ROW_LIMIT).reverse
    ids = shown.filter_map { |r| r[:contact_id] }.uniq
    contacts = @account.contacts.where(id: ids).pluck(:id, :name, :phone_number).to_h { |id, name, phone| [id, [name, phone]] }
    conversations = last_conversation_ids(ids)
    { rows: shown.map { |r| person(r, contacts, conversations, inboxes) }, rows_total: rows.size, truncated: rows.size > shown.size }
  end

  def person(row, contacts, conversations, inboxes)
    name, phone = contacts[row[:contact_id]]
    { id: row[:key], task_id: row[:task_id], contact_id: row[:contact_id],
      name: name.presence || row[:fallback_name].presence || 'Paciente', phone: phone.presence || row[:fallback_phone],
      when: row[:at], due_at: row[:due_at], what: row[:what], what_label: KINDS[row[:what]], source: row[:source],
      inbox: row[:inbox], origin: inbox_label(row[:inbox], inboxes), via: row[:via], via_label: VIAS[row[:via]],
      particular: row[:particular], conversation_id: conversations[row[:contact_id]] }
  end

  def last_conversation_ids(ids)
    return {} if ids.empty?

    Conversation.where(account_id: @account.id, contact_id: ids)
                .select('DISTINCT ON (contact_id) contact_id, display_id').order('contact_id, last_activity_at DESC NULLS LAST')
                .to_h { |c| [c.contact_id, c.display_id] }
  end
end
