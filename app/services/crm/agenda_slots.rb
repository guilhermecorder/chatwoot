# Vagas LIVRES da agenda de consultas, calculadas no servidor — mesma conta
# da Agenda/Meu Painel (janelas dos médicos × consultas marcadas × cadeados).
# Usado pelo Atendente Instagram para oferecer só horários que existem.
module Crm::AgendaSlots # rubocop:disable Metrics/ModuleLength
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  # espelho do DEFAULT_WINDOWS do frontend (cevicoAgenda.js) — vale enquanto
  # as janelas não forem editadas na tela (agenda_config['windows'] vazio)
  DEFAULT_WINDOWS = [
    { 'dow' => 1, 'unit' => 'paulista', 'doctor' => 'Dr. Gustavo Bittar',   'start' => '08:30', 'end' => '10:00', 'block' => 15 },
    { 'dow' => 2, 'unit' => 'paulista', 'doctor' => 'Dr. Henrique Gemelli', 'start' => '08:00', 'end' => '11:30', 'block' => 15 },
    { 'dow' => 2, 'unit' => 'paulista', 'doctor' => 'Dra. Roberta Negri',   'start' => '14:30', 'end' => '16:30', 'block' => 15 },
    # item 307 (01/10): quarta 13h–14h do Dr. Henrique = só retorno de pós-operatório; consulta a partir das 14h
    { 'dow' => 3, 'unit' => 'paulista', 'doctor' => 'Dr. Henrique Gemelli', 'start' => '13:00', 'end' => '14:00', 'block' => 15,
      'only' => ['pos_op'] },
    { 'dow' => 3, 'unit' => 'paulista', 'doctor' => 'Dr. Henrique Gemelli', 'start' => '14:00', 'end' => '17:00', 'block' => 15 },
    { 'dow' => 3, 'unit' => 'tatuape',  'doctor' => 'Dr. Gustavo Bittar',   'start' => '08:30', 'end' => '11:00', 'block' => 10 },
    { 'dow' => 4, 'unit' => 'paulista', 'doctor' => 'Dr. Gustavo Bittar',   'start' => '08:30', 'end' => '11:00', 'block' => 15 },
    { 'dow' => 5, 'unit' => 'tatuape',  'doctor' => 'Dra. Roberta Negri',   'start' => '10:30', 'end' => '13:00', 'block' => 10 }
  ].freeze

  # 'online' = teleconsulta (item 210): não é unidade física, não ocupa bloco
  UNIT_LABELS = { 'tatuape' => 'Tatuapé', 'paulista' => 'Av. Paulista', 'online' => 'Online' }.freeze
  WEEKDAYS = %w[domingo segunda terça quarta quinta sexta sábado].freeze

  # 🗂️ item 307 (01/10): FAIXA RESERVADA. Cada janela pode aceitar só alguns
  # tipos de atendimento (`only`); sem `only` aceita tudo. A IA marca CONSULTA
  # NOVA (avaliação) — então ela só enxerga as faixas que aceitam avaliação.
  RESERVABLE = %w[avaliacao retorno pos_op].freeze
  AI_MODALITY = 'avaliacao'.freeze
  MODALITY_LABELS = { 'avaliacao' => 'avaliação (consulta nova)', 'retorno' => 'retorno',
                      'pos_op' => 'retorno de pós-operatório' }.freeze

  module_function

  # janelas em vigor: as salvas na tela (ou o padrão), SEM os médicos com a
  # agenda fechada — antes do item 307 o "Fechar agenda" só valia na tela e a
  # IA continuava oferecendo os horários do médico fechado
  def windows(account)
    cfg = agenda_config(account)
    saved = Array(cfg['windows'])
    closed = Array(cfg['closed_doctors']).map(&:to_s)
    (saved.presence || DEFAULT_WINDOWS).reject { |w| closed.include?(w['doctor'].to_s) }.map do |w|
      w.merge('dow' => w['dow'].to_i, 'block' => w['block'].to_i.positive? ? w['block'].to_i : 15)
    end
  end

  def reserved_for(win)
    Array(win['only']).map(&:to_s) & RESERVABLE
  end

  def accepts?(win, modality)
    only = reserved_for(win)
    only.empty? || only.include?(modality.to_s)
  end

  # tipo do atendimento que a IA está REMARCANDO: retorno e pós-operatório
  # seguem as faixas deles; todo o resto é tratado como consulta nova
  def slot_modality(task)
    modality = task&.modality.to_s
    RESERVABLE.include?(modality) ? modality : AI_MODALITY
  end

  # faixas onde a IA pode pôr um atendimento deste tipo. Consulta nova: toda
  # faixa que aceita avaliação. Retorno / pós-operatório: havendo faixa
  # DEDICADA ao tipo (ex.: quarta 13h–14h = só pós-operatório), a IA usa só as
  # dedicadas — é o que mantém o pós-operatório fora do período das consultas.
  # Sem faixa dedicada, vale qualquer faixa que aceite o tipo.
  def windows_for(account, modality)
    wins = windows(account)
    if modality.to_s != AI_MODALITY
      dedicated = wins.select { |w| reserved_for(w).include?(modality.to_s) }
      return dedicated if dedicated.any?
    end
    wins.select { |w| accepts?(w, modality) }
  end

  # horizonte máximo de "agendamento futuro" (item 200: qualquer data futura
  # dentro das janelas vale; a lista do prompt mostra os primeiros dias e a
  # ferramenta horarios_do_dia busca um dia específico até este limite)
  MAX_FUTURE_DAYS = 120

  # vagas livres dos próximos N dias, no máximo `per_window` por janela/dia.
  # Devolve [{date:, time:, unit:, doctor:}]
  def free_slots(account, days: 10, per_window: 3, modality: AI_MODALITY)
    now = TZ.now
    ctx = slot_context(account, now.to_date, now.to_date + days, modality: modality)
    (0..days).flat_map { |offset| day_slots(ctx, now.to_date + offset, per_window: per_window) }
  end

  # vagas livres de UM dia (qualquer data futura até MAX_FUTURE_DAYS), opcionalmente
  # só de uma unidade. Devolve [] para dia sem janela, fechado ou no passado.
  def free_slots_on(account, date, unit: nil, per_window: 100, modality: AI_MODALITY)
    date = date.to_date
    today = TZ.now.to_date
    return [] if date < today || date > today + MAX_FUTURE_DAYS

    ctx = slot_context(account, date, date, modality: modality)
    day_slots(ctx, date, per_window: per_window).select { |s| unit.blank? || s[:unit] == unit }
  end

  # item 255 (26/09): agendamento do Oftalmofácil OCUPA o horário da unidade
  # dele por sobreposição de tempo (mesma duração padrão da tela da Agenda) —
  # a IA nunca oferece nem grava em cima de um paciente do hub
  HUB_DURATION = { 'cirurgia' => 60, 'exames' => 30 }.freeze

  def hub_busy(account, from_date, to_date)
    account.tasks.where(source: 'oftalmofacil', canceled_at: nil, archived_at: nil)
           .where.not(unit: [nil, ''])
           .where(due_at: TZ.parse(from_date.to_s).beginning_of_day..TZ.parse(to_date.to_s).end_of_day)
           .pluck(:due_at, :unit, :task_type, :modality)
           .map do |due, unit, type, modality|
             at = due.in_time_zone(TZ)
             start = (at.hour * 60) + at.min
             mins = HUB_DURATION[type] || HUB_DURATION[modality] || 15
             { date: at.to_date, unit: unit, from: start, to: start + mins, kind: hub_kind(type, modality) }
           end
  end

  # 🪑 item 330b (06/10, regra dele: "deixar a IA agendar consulta de avaliação
  # encaixada no mesmo horário de retorno, pós-op ou exame — 1 a mais por horário"):
  # retorno e pós-op são consultas "flexíveis": não travam o horário para a IA.
  # O horário só fecha quando já tem uma avaliação (ou consulta sem tipo) nele.
  SOFT_MODALITIES = %w[retorno pos_op].freeze

  # cirurgia × exame × flexível × consulta (de qual agenda o item do hub é e se trava o horário)
  def hub_kind(type, modality)
    return 'cirurgia' if type == 'cirurgia'
    return 'exames' if modality == 'exames'

    SOFT_MODALITIES.include?(modality) ? 'flexivel' : 'consulta'
  end

  # item 297 (30/09): na janela do MÉDICO o agendamento ocupa SÓ o bloco em que
  # começa — a mesma regra da tela. Antes a duração presumida (cirurgia 60,
  # exame 30, consulta 15) tomava 2 ou 3 blocos de 10 min e a IA deixava de
  # oferecer horário que estava livre.
  # 🔪 item 330 (06/10): cirurgia e exame do hub NÃO ocupam a janela do médico —
  # cirurgia é agenda independente (sala cirúrgica) e exame tem a agenda própria;
  # a janela do médico é só de consultas (a tela da Agenda segue a mesma regra).
  def hub_overlap?(ctx, day, hhmm, win) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    start = hm_to_min(hhmm)
    finish = start + win['block'].to_i
    ctx[:hub_busy].any? do |b|
      next false unless b[:date] == day && b[:unit] == win['unit']
      next false if win['doctor'].present? && b[:kind] != 'consulta'
      next b[:from] >= start && b[:from] < finish if win['doctor'].present?

      b[:from] < finish && b[:to] > start
    end
  end

  def hm_to_min(hhmm)
    hours, mins = hhmm.split(':').map(&:to_i)
    (hours * 60) + mins
  end

  # tudo o que a conta de vagas precisa, calculado UMA vez para o intervalo
  def slot_context(account, from_date, to_date, modality: AI_MODALITY) # rubocop:disable Metrics/AbcSize
    cfg = agenda_config(account)
    {
      hub_busy: hub_busy(account, from_date, to_date),
      now: TZ.now,
      # item 307: só as faixas deste tipo de atendimento
      wins: windows_for(account, modality),
      blocked: Array(cfg['blocked']).to_set { |b| "#{b['date']}|#{b['time']}|#{b['unit']}" },
      blocked_days: Array(cfg['blocked_days']).select { |b| b.is_a?(String) }.to_set,
      # item 267: fechamentos de PARTE do dia (uma unidade ou um médico)
      blocked_parts: Array(cfg['blocked_days']).select { |b| b.is_a?(Hash) },
      # item 330: exame não ocupa horário de consulta (tem agenda própria);
      # item 330b: retorno e pós-op também não travam — a IA pode encaixar UMA
      # avaliação no mesmo horário (e só uma: a avaliação, sim, trava)
      occupied: account.tasks
                       .where(task_type: 'consulta', canceled_at: nil)
                       .where('tasks.modality IS NULL OR tasks.modality NOT IN (?)', ['exames'] + SOFT_MODALITIES)
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
      next if window_blocked?(ctx, day, win)

      taken = 0
      each_slot(win) do |hm|
        break if taken >= per_window

        slot_time = TZ.parse("#{day} #{hm}")
        next if slot_time <= ctx[:now]
        next if ctx[:blocked].include?("#{day}|#{hm}|#{win['unit']}")
        next if ctx[:occupied].include?("#{day}|#{hm}|#{win['unit']}") || ctx[:occupied].include?("#{day}|#{hm}|")
        next if hub_overlap?(ctx, day, hm, win)

        slots << { date: day, time: hm, unit: win['unit'], doctor: win['doctor'] }
        taken += 1
      end
    end
    slots
  end

  # item 267: a janela deste médico/unidade está fechada neste dia?
  def window_blocked?(ctx, day, win)
    Array(ctx[:blocked_parts]).any? do |b|
      b['date'] == day.to_s &&
        (b['unit'].blank? || b['unit'] == win['unit']) &&
        (b['doctor'].blank? || b['doctor'] == win['doctor'])
    end
  end

  # texto compacto p/ entrar no prompt do agente:
  # "quarta 22/07 · Tatuapé · Dr. Gustavo Bittar: 08:30, 08:40, 08:50"
  def free_slots_text(account, days: 10, per_window: 3, modality: AI_MODALITY)
    grouped = free_slots(account, days: days, per_window: per_window, modality: modality)
              .group_by { |s| [s[:date], s[:unit], s[:doctor]] }
    return 'NENHUM horário livre nos próximos dias — diga que vai verificar com a equipe.' if grouped.empty?

    grouped.map do |(date, unit, doctor), list|
      "#{WEEKDAYS[date.wday]} #{date.strftime('%d/%m')} · #{UNIT_LABELS[unit] || unit} · #{doctor}: " +
        list.map { |s| s[:time] }.join(', ')
    end.join("\n")
  end

  # o horário existe numa janela e está livre? (qualquer data futura até MAX_FUTURE_DAYS)
  def slot_available?(account, date:, time:, unit:, modality: AI_MODALITY)
    free_slots_on(account, date, unit: unit.presence, modality: modality).any? { |s| s[:time] == time }
  end

  # 🩺 item 311 (02/10, "a IA está agendando terça o dia todo com o Dr. Henrique;
  # à tarde a agenda é da Dra. Roberta"): o médico da consulta é o da FAIXA que
  # cobre o horário. Antes cada agente pegava a 1ª faixa do dia naquela unidade —
  # na terça (Av. Paulista: manhã Henrique, tarde Roberta) dava sempre Henrique.
  # Horário fora de qualquer faixa: a 1ª do dia, como era.
  def doctor_at(account, date, time, unit, modality: AI_MODALITY)
    minutes = hm_to_min(time.to_s)
    wins = windows_for(account, modality).select { |w| w['dow'] == date.wday && w['unit'] == unit }
    covering = wins.find { |w| minutes >= hm_to_min(w['start']) && minutes < hm_to_min(w['end']) }
    (covering || wins.first)&.[]('doctor')
  end

  # 🗂️ item 307: REGRAS DA AGENDA para o prompt dos agentes — as faixas
  # reservadas (geradas das janelas) + o texto livre que a clínica escreve em
  # Agenda → Configurações → Regras para a IA. Vazio = nada entra no prompt.
  def rules_text(account)
    lines = windows(account).reject { |w| accepts?(w, AI_MODALITY) }.map do |w|
      kinds = reserved_for(w).map { |k| MODALITY_LABELS[k] }.join(' e ')
      "- #{WEEKDAYS[w['dow']]} #{w['start']}–#{w['end']} · #{UNIT_LABELS[w['unit']] || w['unit']} · #{w['doctor']}: " \
        "faixa reservada para #{kinds}. NÃO ofereça nem marque consulta nova nesta faixa " \
        "(ela só serve para remarcar #{kinds})."
    end
    custom = agenda_config(account)['ai_rules'].to_s.strip
    lines << custom if custom.present?
    lines.join("\n")
  end

  # bloco pronto para colar no contexto do agente ('' quando não há regra)
  def rules_block(account)
    text = rules_text(account)
    return '' if text.blank?

    "REGRAS DA AGENDA (definidas pela clínica — valem acima de qualquer horário que o paciente peça):\n#{text}\n"
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
