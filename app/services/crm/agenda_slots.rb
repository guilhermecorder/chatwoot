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

  UNIT_LABELS = { 'tatuape' => 'Tatuapé', 'paulista' => 'Av. Paulista' }.freeze
  WEEKDAYS = %w[domingo segunda terça quarta quinta sexta sábado].freeze

  module_function

  def windows(account)
    cfg = agenda_config(account)
    saved = Array(cfg['windows'])
    (saved.presence || DEFAULT_WINDOWS).map do |w|
      w.merge('dow' => w['dow'].to_i, 'block' => w['block'].to_i.positive? ? w['block'].to_i : 15)
    end
  end

  # vagas livres dos próximos N dias, no máximo `per_window` por janela/dia.
  # Devolve [{date:, time:, unit:, doctor:}]
  def free_slots(account, days: 10, per_window: 3)
    cfg = agenda_config(account)
    blocked = Array(cfg['blocked']).to_set { |b| "#{b['date']}|#{b['time']}|#{b['unit']}" }
    blocked_days = Array(cfg['blocked_days']).to_set
    wins = windows(account)
    now = TZ.now

    occupied = account.tasks
                      .where(task_type: 'consulta', canceled_at: nil)
                      .where(due_at: now.beginning_of_day..(now + days.days).end_of_day)
                      .pluck(:due_at, :unit)
                      .to_set { |due, unit| "#{due.in_time_zone(TZ).strftime('%Y-%m-%d|%H:%M')}|#{unit}" }

    slots = []
    (0..days).each do |offset|
      day = now.to_date + offset
      next if day.saturday? || day.sunday?
      next if blocked_days.include?(day.to_s)

      wins.select { |w| w['dow'] == day.wday }.each do |win|
        taken = 0
        each_slot(win) do |hm|
          break if taken >= per_window

          slot_time = TZ.parse("#{day} #{hm}")
          next if slot_time <= now
          next if blocked.include?("#{day}|#{hm}|#{win['unit']}")
          next if occupied.include?("#{day}|#{hm}|#{win['unit']}") || occupied.include?("#{day}|#{hm}|")

          slots << { date: day, time: hm, unit: win['unit'], doctor: win['doctor'] }
          taken += 1
        end
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

  # o horário existe numa janela e está livre?
  def slot_available?(account, date:, time:, unit:)
    free_slots(account, days: 30, per_window: 100).any? do |s|
      s[:date] == date && s[:time] == time && (unit.blank? || s[:unit] == unit)
    end
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
