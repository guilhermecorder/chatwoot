# 🚪 PORTAL DE TERCEIROS · agenda particular de um médico (item 420, 26/11).
#
# Tudo o que a secretária do médico vê e faz passa por aqui — e SÓ por aqui:
#   · VÊ: as consultas EXTERNAS (marcadas pelo portal) do médico dela, com
#     nome e telefone; as particulares que a CLÍNICA marcou para o mesmo
#     médico, só com o nome (sem telefone, sem mexer); e os demais pacientes
#     da clínica apenas como "horário ocupado", sem nome nenhum;
#   · MARCA: só para o médico dela, só como particular, só dentro das faixas
#     que o administrador liberou, em dia que a clínica não fechou e em
#     horário que ainda está livre para aquele médico;
#   · o que ela marca nasce como Task::EXTERNAL_TYPE: aparece na Agenda da
#     clínica e trava o horário para os robôs, mas fica fora de TODAS as
#     contagens da clínica (novos contatos, consultas agendadas, funis,
#     lembretes automáticos) — e não cria paciente nem card no CRM.
#
# Cada ação deixa rastro na própria consulta (lista `comments`, kind 'portal'):
# quem, quando e o quê.
class Crm::ThirdPartyAgenda # rubocop:disable Metrics/ClassLength
  TZ = Crm::AgendaSlots::TZ
  MAX_SPAN_DAYS = 100
  FUTURE_LIMIT_DAYS = 365
  CANCEL_REASON = 'cancelada_terceiro'.freeze
  PORTAL_KIND = 'portal'.freeze
  ATTENDANCES = %w[attended missed].freeze
  ATTENDANCE_NOTES = { 'attended' => 'Compareceu', 'missed' => 'Faltou' }.freeze
  # roxo: na Agenda da clínica a consulta do portal se reconhece de longe
  COLOR = '#7C3AED'.freeze

  class Refused < StandardError; end

  attr_reader :account, :third, :user

  def initialize(account, third, user)
    @account = account
    @third = third
    @user = user
  end

  def doctor = third.doctor
  def company = @company ||= Cevico::Company.for(account)
  def config = @config ||= (CrmSetting.find_by(account: account)&.agenda_config || {})

  # ── o que a tela recebe ────────────────────────────────────────────────
  def payload(from:, to:) # rubocop:disable Metrics/AbcSize
    from, to = clamp_period(from, to)
    range = TZ.parse(from.to_s).beginning_of_day..TZ.parse(to.to_s).end_of_day
    {
      doctor: doctor, label: third.label, today: TZ.now.to_date.to_s, now: TZ.now.iso8601,
      from: from.to_s, to: to.to_s,
      units: units_json, windows: third.windows,
      closed: closed_json(from, to),
      appointments: mine_scope.where(due_at: range).order(:due_at).includes(:creator).map { |t| appointment_json(t) },
      clinic: clinic_json(range),
      indicators: indicators
    }
  end

  # ── marcar ─────────────────────────────────────────────────────────────
  def create!(attrs)
    name, phone = person!(attrs)
    due_at, unit = slot!(attrs[:due_at], attrs[:unit])
    task = account.tasks.new(
      task_type: Task::EXTERNAL_TYPE, title: name, phone: phone, due_at: due_at, unit: unit,
      doctor: doctor, particular: true, procedure: 'Consulta particular',
      description: attrs[:description].to_s.strip[0, 1000].presence,
      creator: user, cevico_born_via: 'terceiro', color: COLOR,
      comments: [trail("🚪 Marcada pelo portal · #{who}")]
    )
    task.save!
    task
  end

  # ── mexer numa consulta dela ───────────────────────────────────────────
  def update!(task, attrs) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
    notes = []
    if attrs.key?(:name) || attrs.key?(:phone)
      name, phone = person!(name: attrs.fetch(:name, task.title), phone: attrs.fetch(:phone, task.phone))
      task.title = name
      task.phone = phone
    end
    task.description = attrs[:description].to_s.strip[0, 1000].presence if attrs.key?(:description)

    if attrs.key?(:canceled)
      cancel = ActiveModel::Type::Boolean.new.cast(attrs[:canceled]) == true
      apply_cancel(task, cancel)
      notes << (cancel ? "🚪 Cancelada pelo portal · #{who}" : "🚪 Reativada pelo portal · #{who}")
    end

    moving = attrs[:due_at].present? && parse_time(attrs[:due_at]) != task.due_at
    if moving
      due_at, unit = slot!(attrs[:due_at], attrs[:unit].presence, except: task)
      task.rescheduled_count += 1 # o modelo carimba a remarcação (de, para, quem)
      task.due_at = due_at
      task.unit = unit
      # o "confirmou" era para a data antiga
      task.confirmed_at = nil
      task.declined_at = nil
    elsif attrs.key?(:canceled) && task.canceled_at.nil? && task.due_at > TZ.now && taken?(task.due_at, task)
      # reativar: o horário antigo precisa continuar livre
      raise Refused, 'Esse horário já foi ocupado. Reative escolhendo outro horário.'
    end

    if attrs.key?(:confirmed)
      confirmed = ActiveModel::Type::Boolean.new.cast(attrs[:confirmed]) == true
      task.confirmed_at = confirmed ? (task.confirmed_at || Time.current) : nil
      task.declined_at = nil if confirmed
      notes << (confirmed ? "🚪 Confirmada pelo portal · #{who}" : "🚪 Confirmação desfeita pelo portal · #{who}")
    end

    if attrs.key?(:attendance)
      value = attrs[:attendance].to_s.presence
      raise Refused, 'Presença inválida.' if value && ATTENDANCES.exclude?(value)

      task.attendance = value
      notes << "🚪 #{ATTENDANCE_NOTES.fetch(value, 'Presença desfeita')} (portal) · #{who}"
    end

    task.comments = Array(task.comments) + notes.map { |text| trail(text) } if notes.any?
    as_actor { task.save! }
    task
  end

  # a consulta que ESTE terceiro pode abrir: externa, do médico dele
  def find(id)
    mine_scope.find_by(id: id)
  end

  def appointment_json(task) # rubocop:disable Metrics/AbcSize
    {
      id: task.id, name: task.title, phone: task.phone, due_at: task.due_at,
      unit: task.unit, unit_label: unit_label(task.unit),
      description: task.description,
      confirmed_at: task.confirmed_at, declined_at: task.declined_at,
      canceled_at: task.canceled_at, attendance: task.attendance,
      rescheduled_count: task.rescheduled_count, created_at: task.created_at,
      creator: task.creator&.name, mine: task.creator_id == user.id,
      history: Array(task.comments).select { |c| c.is_a?(Hash) && c['text'].present? }.last(12)
                                   .map { |c| { at: c['at'], text: c['text'].to_s } }
    }
  end

  private

  # o carimbo da remarcação (no modelo) leva o nome de quem remarcou: fora de
  # uma requisição (rotina, console, teste) empresta o usuário e DEVOLVE
  def as_actor
    previous = Current.user
    Current.user = user if previous.nil?
    yield
  ensure
    Current.user = previous
  end

  def mine_scope
    account.tasks.external.where(doctor: doctor, archived_at: nil)
  end

  def who
    [user.name, third.label.presence].compact.join(' · ')
  end

  def trail(text)
    { 'kind' => PORTAL_KIND, 'user_id' => user.id, 'name' => user.name, 'text' => text, 'at' => Time.current.iso8601 }
  end

  def apply_cancel(task, cancel)
    if cancel
      task.canceled_at ||= Time.current
      task.canceled_by ||= user
      task.cancel_reason ||= CANCEL_REASON
    else
      task.canceled_at = nil
      task.canceled_by = nil
      task.cancel_reason = nil
    end
  end

  # nome e telefone do paciente (telefone é opcional, mas se vier tem que ser telefone)
  def person!(attrs)
    name = attrs[:name].to_s.strip.squeeze(' ')[0, 120]
    raise Refused, 'Escreva o nome do paciente.' if name.length < 2

    phone = attrs[:phone].to_s.strip[0, 30]
    digits = phone.gsub(/\D/, '')
    raise Refused, 'Confira o telefone (com DDD).' if phone.present? && !digits.length.between?(10, 13)

    [name, phone.presence]
  end

  # o horário pedido vale? Devolve [quando, unidade] ou recusa com o motivo.
  def slot!(due_at_param, unit_param, except: nil) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    at = parse_time(due_at_param)
    raise Refused, 'Escolha o dia e o horário.' if at.nil?
    raise Refused, 'Esse horário já passou.' if at <= TZ.now
    raise Refused, 'Data longe demais (até 1 ano).' if at.to_date > TZ.now.to_date + FUTURE_LIMIT_DAYS

    day = at.to_date
    hhmm = at.strftime('%H:%M')
    wins = third.windows.select { |w| w['dow'].to_i == day.wday && inside?(w, hhmm) }
    wins = wins.select { |w| w['unit'].to_s == unit_param.to_s } if unit_param.present?
    raise Refused, 'Esse horário está fora das faixas liberadas para o seu acesso.' if wins.empty?

    unit = wins.first['unit'].to_s
    raise Refused, closed_reason(day, unit) if closed_reason(day, unit)
    raise Refused, 'A clínica travou esse horário.' if padlocked?(day, hhmm, unit)
    raise Refused, 'Esse horário já está ocupado.' if taken?(at, except)

    [at, unit]
  end

  def parse_time(value)
    return nil if value.blank?

    TZ.parse(value.to_s)&.change(sec: 0)
  rescue ArgumentError
    nil
  end

  # dentro da faixa E em cima de um horário da grade dela
  def inside?(win, hhmm)
    start = minutes(win['start'])
    finish = minutes(win['end'])
    at = minutes(hhmm)
    block = win['block'].to_i.positive? ? win['block'].to_i : 15
    at >= start && at < finish && ((at - start) % block).zero?
  end

  def minutes(hhmm)
    h, m = hhmm.to_s.split(':').map(&:to_i)
    (h.to_i * 60) + m.to_i
  end

  # a clínica fechou o dia (inteiro, a unidade ou o médico) ou a agenda do médico?
  def closed_reason(day, unit) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return 'A clínica fechou a agenda deste médico.' if Array(config['closed_doctors']).map(&:to_s).include?(doctor)

    Array(config['blocked_days']).each do |b|
      return 'A clínica fechou esse dia.' if b.is_a?(String) && b == day.to_s
      next unless b.is_a?(Hash) && b['date'].to_s == day.to_s
      next unless (b['unit'].blank? || b['unit'].to_s == unit) && (b['doctor'].blank? || b['doctor'].to_s == doctor)

      return 'A clínica fechou esse dia para este médico.'
    end
    nil
  end

  def padlocked?(day, hhmm, unit)
    Array(config['blocked']).any? do |b|
      b.is_a?(Hash) && b['date'].to_s == day.to_s && b['time'].to_s == hhmm && (b['unit'].blank? || b['unit'].to_s == unit)
    end
  end

  # o MÉDICO já tem alguém neste horário? (consulta da clínica ou externa)
  def taken?(at, except)
    scope = account.tasks.where(task_type: Task::AGENDA_CONSULT_TYPES, canceled_at: nil, archived_at: nil,
                                doctor: doctor, due_at: at..(at + 59.seconds))
    scope = scope.where.not(id: except.id) if except
    scope.exists?
  end

  def clamp_period(from, to)
    today = TZ.now.to_date
    from = parse_date(from) || today.beginning_of_month
    to = parse_date(to) || from.end_of_month
    to = from if to < from
    to = from + MAX_SPAN_DAYS if to > from + MAX_SPAN_DAYS
    [from, to]
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def units_json
    keys = third.windows.map { |w| w['unit'].to_s }.uniq
    keys.map { |key| { key: key, label: unit_label(key) } }
  end

  def unit_label(key)
    Crm::AgendaSlots::UNIT_LABELS[key.to_s] || company.unit_label(key)
  end

  # dias fechados pela clínica dentro do período (a tela risca o dia)
  def closed_json(from, to) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return [{ all: true, reason: 'A clínica fechou a agenda deste médico.' }] if Array(config['closed_doctors']).map(&:to_s).include?(doctor)

    days = Array(config['blocked_days']).filter_map do |b|
      if b.is_a?(String)
        { date: b, unit: nil }
      elsif b.is_a?(Hash) && (b['doctor'].blank? || b['doctor'].to_s == doctor)
        { date: b['date'].to_s, unit: b['unit'].to_s.presence }
      end
    end
    locks = Array(config['blocked']).filter_map do |b|
      { date: b['date'].to_s, time: b['time'].to_s, unit: b['unit'].to_s.presence } if b.is_a?(Hash)
    end
    (days + locks).select { |row| row[:date].between?(from.to_s, to.to_s) }
  end

  # o que a CLÍNICA marcou para o mesmo médico: particular = só o nome;
  # o resto = "ocupado", sem nome (privacidade dos pacientes da clínica)
  def clinic_json(range)
    account.tasks.where(task_type: 'consulta', canceled_at: nil, archived_at: nil, doctor: doctor, due_at: range)
           .order(:due_at).pluck(:due_at, :unit, :particular, :title).map do |due, unit, particular, title|
      { due_at: due, unit: unit, particular: particular, name: particular ? title : nil }
    end
  end

  # ── indicadores dela (só as consultas do portal) ───────────────────────
  def indicators # rubocop:disable Metrics/AbcSize
    now = TZ.now
    live = mine_scope.where(canceled_at: nil)
    week = live.where(due_at: now..(now + 7.days).end_of_day)
    past = live.where(due_at: (now - 30.days).beginning_of_day..now)
    attended = past.where(attendance: 'attended').count
    missed = past.where(attendance: 'missed').count
    {
      today: live.where(due_at: now.all_day).count,
      next7: week.count,
      to_confirm: week.where(confirmed_at: nil).count,
      attended30: attended, missed30: missed,
      unmarked30: past.where(attendance: nil).count,
      show_rate30: (attended + missed).positive? ? ((attended * 100.0) / (attended + missed)).round : nil,
      canceled30: mine_scope.where(canceled_at: (now - 30.days)..now).count,
      missed_no_return: missed_without_return(live, now)
    }
  end

  # faltou nos últimos 60 dias e não tem consulta futura (para ela ligar e remarcar)
  def missed_without_return(live, now) # rubocop:disable Metrics/AbcSize
    future = live.where('due_at > ?', now).pluck(:phone, :title)
    back = future.flat_map { |phone, title| person_keys(phone, title) }.to_set
    rows = live.where(attendance: 'missed', due_at: (now - 60.days)..now).order(due_at: :desc).limit(40)
    rows = rows.reject { |t| person_keys(t.phone, t.title).any? { |key| back.include?(key) } }
    rows.uniq { |t| person_keys(t.phone, t.title) }.first(15)
        .map { |t| { id: t.id, name: t.title, phone: t.phone, due_at: t.due_at } }
  end

  # como reconhecer a mesma pessoa em duas consultas: o final do telefone e o nome
  def person_keys(phone, title)
    tail = phone.to_s.gsub(/\D/, '').last(8).to_s
    [tail.presence && "tel:#{tail}", "nome:#{title.to_s.downcase.strip}"].compact
  end
end
