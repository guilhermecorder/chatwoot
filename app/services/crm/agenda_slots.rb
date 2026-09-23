# Vagas LIVRES da agenda de consultas, calculadas no servidor — mesma conta
# da Agenda/Meu Painel (janelas dos médicos × consultas marcadas × cadeados).
# Usado pelo Atendente Instagram para oferecer só horários que existem.
module Crm::AgendaSlots
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  # espelho do DEFAULT_WINDOWS do frontend (cevicoAgenda.js) — vale enquanto
  # as janelas não forem editadas na tela (agenda_config['windows'] vazio)
  DEFAULT_WINDOWS = [
    { 'dow' => 1, 'unit' => 'paulista', 'doctor' => 'Dr. Gustavo Bittar',   'start' => '08:30', 'end' => '10:00', 'block' => 15 },
    { 'dow' => 2, 'unit' => 'paulista', 'doctor' => 'Dr. Henrique Gemelli', 'start' => '08:00', 'end' => '11:30', 'block' => 15 },
    { 'dow' => 2, 'unit' => 'paulista', 'doctor' => 'Dra. Roberta Negri',   'start' => '14:30', 'end' => '16:30', 'block' => 15 },
    { 'dow' => 3, 'unit' => 'paulista', 'doctor' => 'Dr. Henrique Gemelli', 'start' => '13:00', 'end' => '17:00', 'block' => 15 },
    { 'dow' => 3, 'unit' => 'tatuape',  'doctor' => 'Dr. Gustavo Bittar',   'start' => '08:30', 'end' => '11:00', 'block' => 10 },
    { 'dow' => 4, 'unit' => 'paulista', 'doctor' => 'Dr. Gustavo Bittar',   'start' => '08:30', 'end' => '11:00', 'block' => 15 },
    { 'dow' => 5, 'unit' => 'tatuape',  'doctor' => 'Dra. Roberta Negri',   'start' => '10:30', 'end' => '13:00', 'block' => 10 }
  ].freeze

  # 'online' = teleconsulta (item 210): não é unidade física, não ocupa bloco
  UNIT_LABELS = { 'tatuape' => 'Tatuapé', 'paulista' => 'Av. Paulista', 'online' => 'Online' }.freeze
  WEEKDAYS = %w[domingo segunda terça quarta quinta sexta sábado].freeze

  module_function

  def windows(account)
    cfg = agenda_config(account)
    saved = Array(cfg['windows'])
    (saved.presence || DEFAULT_WINDOWS).map do |w|
      w.merge('dow' => w['dow'].to_i, 'block' => w['block'].to_i.positive? ? w['block'].to_i : 15)
    end
  end

  # horizonte máximo de "agendamento futuro" (item 200: qualquer data futura
  # dentro das janelas vale; a lista do prompt mostra os primeiros dias e a
  # ferramenta horarios_do_dia busca um dia específico até este limite)
  MAX_FUTURE_DAYS = 120

  # vagas livres dos próximos N dias, no máximo `per_window` por janela/dia.
  # Devolve [{date:, time:, unit:, doctor:}]
  def free_slots(account, days: 10, per_window: 3)
    now = TZ.now
    ctx = slot_context(account, now.to_date, now.to_date + days)
    (0..days).flat_map { |offset| day_slots(ctx, now.to_date + offset, per_window: per_window) }
  end

  # vagas livres de UM dia (qualquer data futura até MAX_FUTURE_DAYS), opcionalmente
  # só de uma unidade. Devolve [] para dia sem janela, fechado ou no passado.
  def free_slots_on(account, date, unit: nil, per_window: 100)
    date = date.to_date
    today = TZ.now.to_date
    return [] if date < today || date > today + MAX_FUTURE_DAYS

    ctx = slot_context(account, date, date)
    day_slots(ctx, date, per_window: per_window).select { |s| unit.blank? || s[:unit] == unit }
  end

  # tudo o que a conta de vagas precisa, calculado UMA vez para o intervalo
  def slot_context(account, from_date, to_date)
    cfg = agenda_config(account)
    {
      now: TZ.now,
      wins: windows(account),
      blocked: Array(cfg['blocked']).to_set { |b| "#{b['date']}|#{b['time']}|#{b['unit']}" },
      blocked_days: Array(cfg['blocked_days']).to_set,
      occupied: account.tasks
                       .where(task_type: 'consulta', canceled_at: nil)
                       .where(due_at: TZ.parse(from_date.to_s).beginning_of_day..TZ.parse(to_date.to_s).end_of_day)
                       .pluck(:due_at, :unit)
                       .to_set { |due, unit| "#{due.in_time_zone(TZ).strftime('%Y-%m-%d|%H:%M')}|#{unit}" }
    }
  end

  def day_slots(ctx, day, per_window:) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return [] if day.saturday? || day.sunday?
    return [] if ctx[:blocked_days].include?(day.to_s)

    slots = []
    ctx[:wins].select { |w| w['dow'] == day.wday }.each do |win|
      taken = 0
      each_slot(win) do |hm|
        break if taken >= per_window

        slot_time = TZ.parse("#{day} #{hm}")
        next if slot_time <= ctx[:now]
        next if ctx[:blocked].include?("#{day}|#{hm}|#{win['unit']}")
        next if ctx[:occupied].include?("#{day}|#{hm}|#{win['unit']}") || ctx[:occupied].include?("#{day}|#{hm}|")

        slots << { date: day, time: hm, unit: win['unit'], doctor: win['doctor'] }
        taken += 1
      end
    end
    slots
  end

  # texto compacto p/ entrar no prompt do agente:
  # "quarta 22/07 · Tatuapé · Dr. Gustavo Bittar: 08:30, 08:40, 08:50"
  def free_slots_text(account, days: 10, per_window: 3)
    grouped = free_slots(account, days: days, per_window: per_window)
              .group_by { |s| [s[:date], s[:unit], s[:doctor]] }
    return 'NENHUM horário livre nos próximos dias — diga que vai verificar com a equipe.' if grouped.empty?

    grouped.map do |(date, unit, doctor), list|
      "#{WEEKDAYS[date.wday]} #{date.strftime('%d/%m')} · #{UNIT_LABELS[unit] || unit} · #{doctor}: " +
        list.map { |s| s[:time] }.join(', ')
    end.join("\n")
  end

  # o horário existe numa janela e está livre? (qualquer data futura até MAX_FUTURE_DAYS)
  def slot_available?(account, date:, time:, unit:)
    free_slots_on(account, date, unit: unit.presence).any? { |s| s[:time] == time }
  end

  def each_slot(win)
    sh, sm = win['start'].split(':').map(&:to_i)
    eh, em = win['end'].split(':').map(&:to_i)
    t = (sh * 60) + sm
    limit = (eh * 60) + em
    while t < limit
      yield format('%02d:%02d', t / 60, t % 60)
      t += win['block']
    end
  end

  def agenda_config(account)
    CrmSetting.find_by(account: account)&.agenda_config || {}
  end
end
