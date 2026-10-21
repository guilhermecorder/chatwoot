# 🌪️ item 271 (28/09): os DOIS FUNIS que ele pediu ("o funil de aquisição é de
# importância extrema, assim quanto 'da porta pra dentro'").
#
# AQUISIÇÃO POR TURMA: quem CHEGOU no período (LeadsUniverse) e onde cada um
# está hoje, olhando até `horizon` dias depois da chegada (decisão dele: 90).
#   chegou → conversou → orçamento → marcou consulta → compareceu → indicação
#   → cirurgia marcada → cirurgia realizada
# DA PORTA PRA DENTRO: quem SENTOU NA CADEIRA (consulta com data no período).
#   consultas → compareceram → indicação → cirurgia marcada → realizada → NPS
#   + faltas, cancelamentos, remarcações; por médico e por unidade.
#
# Cada etapa devolve a LISTA de pacientes (nome, telefone, origem, dias) e
# "parou aqui" = chegou nesta etapa e não passou para a seguinte. Nenhum
# número sem nome atrás.
class Crm::FunnelService # rubocop:disable Metrics/ClassLength
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  LIST_LIMIT = 400
  SURGERY_DONE_KINDS = %w[realizada aguardando_pagamento].freeze
  SURGERY_BOOKED_KINDS = %w[agendada realizada aguardando_pagamento].freeze

  ACQ_STEPS = [
    ['arrived', 'Chegaram', 'leads novos pelas caixas de captação'],
    ['replied', 'Conversaram', 'responderam depois da nossa 1ª mensagem'],
    ['budget', 'Orçamento', 'entrou em Envio de Orçamento (ou já marcou)'],
    ['booked', 'Marcaram consulta', 'consulta marcada (robô ou equipe)'],
    ['attended', 'Compareceram', 'presença registrada na consulta'],
    ['indicated', 'Indicação', 'saiu da consulta com indicação de cirurgia'],
    ['surgery_booked', 'Cirurgia marcada', 'na Agenda ou no Oftalmofácil'],
    ['surgery_done', 'Cirurgia realizada', 'realizada (ou aguardando pagamento no Oftalmofácil)']
  ].freeze

  CLINIC_STEPS = [
    ['due', 'Consultas', 'consultas com data no período (sem exame/tele)'],
    ['attended', 'Compareceram', 'presença registrada'],
    ['indicated', 'Indicação', 'saíram com indicação de cirurgia'],
    ['surgery_booked', 'Cirurgia marcada', 'na Agenda ou no Oftalmofácil, depois da consulta'],
    ['surgery_done', 'Cirurgia realizada', 'realizada (ou aguardando pagamento)'],
    ['nps', 'Respondeu NPS', 'pesquisa de satisfação respondida']
  ].freeze

  def initialize(account)
    @account = account
  end

  # ── FUNIL DE AQUISIÇÃO POR TURMA ──────────────────────────────────────────
  def acquisition(since, until_at, horizon_days: 90) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    contacts = Crm::LeadsUniverse.scope(@account, since, until_at).select(:id, :name, :phone_number, :created_at).to_a
    ids = contacts.map(&:id)
    horizon = horizon_days.to_i.clamp(7, 365)
    origins = Crm::PatientKind.origin_inbox_by_contact(@account, ids)
    stamps = acquisition_stamps(ids) # contact_id → { step => Time }
    people = contacts.map do |c|
      limit = c.created_at + horizon.days
      st = stamps[c.id] || {}
      reached = { 'arrived' => c.created_at }
      ACQ_STEPS.drop(1).each { |(key, _)| reached[key] = st[key] if st[key] && st[key] <= limit }
      cascade!(reached, ACQ_STEPS)
      { id: c.id, name: c.name.presence || 'Sem nome', phone: c.phone_number, arrived_at: c.created_at,
        origin: origins[c.id]&.dig(:name) || 'sem conversa', origin_id: origins[c.id]&.dig(:id),
        booked_by: st[:booked_by], reached: reached }
    end
    {
      horizon_days: horizon, total: people.size,
      steps: steps_json(ACQ_STEPS, people),
      by_origin: breakdown(ACQ_STEPS, people) { |p| p[:origin] },
      by_source: booked_by_source(people),
      lists: lists_json(ACQ_STEPS, people)
    }
  end

  # ── DA PORTA PRA DENTRO ────────────────────────────────────────────────────
  def clinic(since, until_at) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    tasks = @account.tasks.where(task_type: 'consulta', due_at: since..until_at, archived_at: nil)
                    .where("title NOT LIKE '⚠️%'")
                    .where("modality IS NULL OR modality NOT IN ('teleconsulta', 'exames')")
                    .includes(:contact).order(:due_at).to_a
    ids = tasks.filter_map(&:contact_id).uniq
    surg = surgery_stamps(ids)
    nps = nps_answered(ids)
    origins = Crm::PatientKind.origin_inbox_by_contact(@account, ids)
    people = tasks.map do |t|
      reached = { 'due' => t.due_at }
      unless t.canceled_at
        reached['attended'] = t.due_at if t.attendance == 'attended'
        reached['indicated'] = t.due_at if t.surgery_indication == 'indicated' && reached['attended']
        sb = surg.dig(t.contact_id, :booked)
        reached['surgery_booked'] = sb if reached['indicated'] && sb && sb >= t.due_at - 1.day
        sd = surg.dig(t.contact_id, :done)
        reached['surgery_done'] = sd if reached['surgery_booked'] && sd && sd >= t.due_at
        reached['nps'] = nps[t.contact_id] if reached['surgery_done'] && nps[t.contact_id]
      end
      name = t.title.to_s.sub(/\A(Consulta|Teleconsulta):\s*/i, '').strip.presence || t.contact&.name || 'Paciente'
      { id: t.contact_id || -t.id, task_id: t.id, name: name,
        phone: t.phone.presence || t.contact&.phone_number, due_at: t.due_at, doctor: Crm::DoctorNames.canonical(t.doctor) || 'sem médico',
        unit: Crm::AgendaSlots::UNIT_LABELS[t.unit] || t.unit.presence || 'sem unidade', origin: origins[t.contact_id]&.dig(:name) || 'sem conversa',
        modality: t.modality, status: consult_status(t), rescheduled: t.rescheduled_count.to_i, reached: reached }
    end
    {
      total: people.size,
      steps: steps_json(CLINIC_STEPS, people),
      side: {
        missed: people.count { |p| p[:status] == 'missed' },
        canceled: people.count { |p| p[:status] == 'canceled' },
        rescheduled: people.count { |p| p[:rescheduled].positive? },
        pending: people.count { |p| p[:status] == 'pending' },
        future: people.count { |p| p[:status] == 'future' }
      },
      by_doctor: breakdown(CLINIC_STEPS, people) { |p| p[:doctor] },
      by_unit: breakdown(CLINIC_STEPS, people) { |p| p[:unit] },
      lists: lists_json(CLINIC_STEPS, people).merge(
        'missed' => people.select { |p| p[:status] == 'missed' }.first(LIST_LIMIT).map { |p| person_json(p) },
        'canceled' => people.select { |p| p[:status] == 'canceled' }.first(LIST_LIMIT).map { |p| person_json(p) },
        'rescheduled' => people.select { |p| p[:rescheduled].positive? }.first(LIST_LIMIT).map { |p| person_json(p) }
      )
    }
  end

  private

  # funil de verdade: quem chegou numa etapa passou pelas anteriores (marcou
  # consulta ⇒ conversou e recebeu orçamento, mesmo que o rastro não exista)
  def cascade!(reached, defs)
    keys = defs.map(&:first)
    (keys.size - 2).downto(0) do |i|
      nxt = reached[keys[i + 1]]
      reached[keys[i]] ||= nxt if nxt
    end
    reached
  end

  def consult_status(task)
    return 'canceled' if task.canceled_at
    return 'attended' if task.attendance == 'attended'
    return 'missed' if task.attendance == 'missed'
    return 'future' if task.due_at > Time.current

    'pending'
  end

  # ── carimbos de cada etapa, em poucas consultas (nunca 1 por pessoa) ──
  def acquisition_stamps(ids) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return {} if ids.empty?

    out = Hash.new { |h, k| h[k] = {} }
    replied_at(ids).each { |cid, at| out[cid]['replied'] = at }
    budget_at(ids).each { |cid, at| out[cid]['budget'] = at }
    booked = @account.tasks.bookings.where(task_type: 'consulta', contact_id: ids)
                     .where("title NOT LIKE '⚠️%'")
                     .where("modality IS NULL OR modality NOT IN ('teleconsulta', 'exames')")
                     .order(:created_at).pluck(:contact_id, :created_at, :description)
    booked.each do |cid, at, desc|
      next if out[cid]['booked']

      out[cid]['booked'] = at
      out[cid][:booked_by] = desc.to_s.match?(Crm::BookingSource::IA_MARKS) ? 'ia' : 'equipe'
    end
    # orçamento: quem marcou sem passar pela coluna também "recebeu" (o processo
    # de vendas apresenta o valor antes de marcar)
    out.each_value { |st| st['budget'] = [st['budget'], st['booked']].compact.min if st['booked'] }
    @account.tasks.where(task_type: 'consulta', contact_id: ids, attendance: 'attended', canceled_at: nil)
            .group(:contact_id).minimum(:due_at).each { |cid, at| out[cid]['attended'] = at }
    @account.tasks.where(task_type: 'consulta', contact_id: ids, surgery_indication: 'indicated', canceled_at: nil)
            .group(:contact_id).minimum(:due_at).each { |cid, at| out[cid]['indicated'] = at }
    surgery_stamps(ids).each do |cid, s|
      out[cid]['surgery_booked'] = s[:booked] if s[:booked]
      out[cid]['surgery_done'] = s[:done] if s[:done]
    end
    out
  end

  # respondeu = mensagem RECEBIDA depois da nossa primeira mensagem enviada
  def replied_at(ids)
    first_out = Message.reorder(nil).joins(:conversation)
                       .where(conversations: { account_id: @account.id, contact_id: ids })
                       .where(message_type: :outgoing, private: false)
                       .group('conversations.contact_id').minimum(:created_at)
    return {} if first_out.empty?

    incoming = Message.reorder(nil).joins(:conversation)
                      .where(conversations: { account_id: @account.id, contact_id: first_out.keys })
                      .where(message_type: :incoming)
                      .pluck('conversations.contact_id', :created_at)
    incoming.group_by(&:first).filter_map do |cid, list|
      at = list.map(&:last).select { |t| t > first_out[cid] }.min
      [cid, at] if at
    end.to_h
  end

  # entrou na coluna de orçamento (ou em qualquer coluna depois dela)
  def budget_at(ids)
    stage = Crm::BudgetSideEffects.stage(@account)
    return {} unless stage

    later = Crm::Stage.where(pipeline_id: stage.pipeline_id).where('position >= ?', stage.position).pluck(:id)
    Crm::StageLog.joins(:crm_contact)
                 .where(crm_contacts: { contact_id: ids }, stage_id: later, event_type: 'entered')
                 .group('crm_contacts.contact_id').minimum(:entered_at)
  end

  # cirurgia marcada / realizada: Agenda (tasks cirurgia) + Oftalmofácil
  def surgery_stamps(ids) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return {} if ids.empty?

    out = Hash.new { |h, k| h[k] = {} }
    @account.tasks.where(task_type: 'cirurgia', contact_id: ids, canceled_at: nil)
            .group(:contact_id).minimum(:created_at).each { |cid, at| out[cid][:booked] = at }
    @account.tasks.where(task_type: 'cirurgia', contact_id: ids, canceled_at: nil)
            .where("attendance = 'attended' OR status = 2").group(:contact_id).minimum(:due_at)
            .each { |cid, at| out[cid][:done] = at }
    of = Crm::OftalmofacilSurgery.where(account_id: @account.id, contact_id: ids, status_kind: SURGERY_BOOKED_KINDS)
                                 .pluck(:contact_id, :status_kind, :of_created_at, :surgery_date)
    of.each do |cid, kind, created, date|
      booked = created || date&.in_time_zone(TZ)
      out[cid][:booked] = [out[cid][:booked], booked].compact.min if booked
      next unless SURGERY_DONE_KINDS.include?(kind) && date

      done = date.in_time_zone(TZ).end_of_day
      out[cid][:done] = [out[cid][:done], done].compact.min
    end
    out
  end

  def nps_answered(ids)
    return {} if ids.empty?

    @account.contacts.where(id: ids).pluck(:id, :additional_attributes).to_h do |cid, attrs|
      at = attrs&.dig('cevico_nps_survey', 'answered_at') || attrs&.dig('nps', 'at')
      [cid, at ? (Time.zone.parse(at.to_s) rescue nil) : nil] # rubocop:disable Style/RescueModifier
    end.compact
  end

  # ── saída ──
  def steps_json(defs, people)
    first = people.size
    prev = nil
    defs.map do |(key, label, hint)|
      hit = people.select { |p| p[:reached][key] }
      count = hit.size
      days = median_days(hit, defs, key)
      row = { key: key, label: label, hint: hint, count: count,
              pct_first: first.positive? ? (count * 100.0 / first).round(1) : 0,
              pct_prev: prev&.positive? ? (count * 100.0 / prev).round(1) : nil,
              median_days: days }
      prev = count
      row
    end
  end

  # dias (mediana) entre a etapa anterior e esta, entre quem chegou nesta
  def median_days(hit, defs, key) # rubocop:disable Metrics/CyclomaticComplexity
    idx = defs.index { |d| d.first == key }
    return nil if idx.nil? || idx.zero?

    prev_key = defs[idx - 1].first
    vals = hit.filter_map do |p|
      a = p[:reached][prev_key]
      b = p[:reached][key]
      ((b - a) / 86_400.0).round(1) if a && b && b >= a
    end.sort
    return nil if vals.empty?

    vals[vals.size / 2]
  end

  def breakdown(defs, people, &)
    groups = people.group_by(&)
    rows = groups.map do |name, list|
      { name: name.to_s, total: list.size, steps: defs.to_h { |(key, _)| [key, list.count { |p| p[:reached][key] }] } }
    end
    rows.sort_by { |h| -h[:total] }
  end

  def booked_by_source(people)
    booked = people.select { |p| p[:reached]['booked'] }
    { ia: booked.count { |p| p[:booked_by] == 'ia' }, equipe: booked.count { |p| p[:booked_by] == 'equipe' } }
  end

  # por etapa: quem chegou nela e quem PAROU nela (não passou para a seguinte)
  def lists_json(defs, people) # rubocop:disable Metrics/CyclomaticComplexity
    keys = defs.map(&:first)
    keys.each_with_index.to_h do |key, i|
      nxt = keys[i + 1]
      reached = people.select { |p| p[:reached][key] }
      stopped = nxt ? reached.reject { |p| p[:reached][nxt] } : []
      [key, { reached: reached.first(LIST_LIMIT).map { |p| person_json(p) },
              stopped: stopped.first(LIST_LIMIT).map { |p| person_json(p) } }]
    end
  end

  def person_json(person)
    person.except(:reached).merge(steps: person[:reached].transform_values { |t| t&.iso8601 })
  end
end
