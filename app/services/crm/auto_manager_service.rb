# 📊 GESTOR AUTÔNOMO (item 128): rotina diária que LÊ os números do funil e
# AGE — compara a semana atual (em ritmo) e a última semana fechada contra a
# MÉDIA das 12 semanas, encontra os desvios que importam e:
#   1. registra os achados em ai_config['manager_state'] (card no Meu Painel);
#   2. abre TAREFA para o responsável certo (attendance_owners → admin);
#   3. escreve um BRIEFING diário curto com a IA (haiku — barato) explicando
#      o que aconteceu e o que fazer, em português de gente.
# Sem migration: estado no jsonb, idempotente por dia.
class Crm::AutoManagerService
  include Crm::AiAgentConfig

  AGENT_KEY = 'manager'.freeze
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  # queda relevante = abaixo de (média × limiar). Padrão 25% abaixo da média.
  DEFAULT_DROP_PCT = 25
  # volume mínimo na média para o indicador ser julgado (semana de base ~zero
  # não pode gritar "queda de 100%")
  MIN_BASELINE = { 'new_leads' => 10, 'appointments_booked' => 5,
                   'consultations_attended' => 4, 'surgeries_booked' => 2,
                   'revenue_closed' => 1 }.freeze

  INDICATOR_LABELS = {
    'new_leads' => 'Leads novos',
    'appointments_booked' => 'Consultas agendadas',
    'consultations_attended' => 'Comparecimentos',
    'surgeries_booked' => 'Cirurgias agendadas',
    'revenue_closed' => 'Faturamento fechado',
    'rate_scheduling' => 'Taxa de agendamento',
    'rate_attendance' => 'Taxa de comparecimento',
    'rate_surgery' => 'Taxa de conversão em cirurgia'
  }.freeze

  RATE_KEYS = %w[rate_scheduling rate_attendance rate_surgery].freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o Gestor Autônomo de uma clínica: um gerente comercial experiente,
    direto e caloroso. Recebe os números da semana comparados à média das
    últimas 12 semanas e escreve um BRIEFING DIÁRIO de no máximo 4 frases em
    português simples: o que está indo bem (1 frase), o desvio mais importante
    e a causa provável (1-2 frases), e a ação prática de HOJE (1 frase,
    começando com um verbo). Sem jargão, sem enrolação, números arredondados.
  PROMPT

  def initialize(account:)
    @account = account
  end

  attr_reader :account

  def call(force: false)
    return { skipped: 'desligado' } if agent_paused?
    return { skipped: 'já rodou hoje' } if !force && state['last_run_date'] == TZ.today.iso8601

    weeks = Crm::GoalPeriodHistoryService.new(account, 'week')
                                         .history(account.cevico_goal_plans.where(period_type: 'week'))
    return { skipped: 'sem histórico' } if weeks.blank? || weeks.size < 4

    findings = detect_findings(weeks)
    tasks_opened = open_tasks(findings)
    brief = write_brief(weeks, findings)

    write_state(
      'last_run_date' => TZ.today.iso8601,
      'last_run_at' => Time.current.iso8601,
      'findings' => findings,
      'brief' => brief,
      'tasks_opened' => tasks_opened,
      'baseline_weeks' => weeks.size - 1
    )
    { ok: true, findings: findings.size, tasks: tasks_opened }
  end

  def state
    (ai_config || {})['manager_state'] || {}
  end

  private

  # ── DETECÇÃO ──────────────────────────────────────────────────────────
  # semana ATUAL em ritmo (projeção) + última semana FECHADA, ambas vs média
  # das semanas anteriores. Um achado por indicador (o pior dos dois).
  def detect_findings(weeks)
    current = weeks.last
    closed = weeks[-2]
    baseline_rows = weeks[0..-2] # a média não inclui a semana corrente
    drop_pct = config_drop_pct

    findings = []
    INDICATOR_LABELS.each_key do |key|
      base_values = baseline_rows.map { |w| w[:values][key].to_f }
      baseline = average(base_values)
      next if baseline.zero?

      # guarda de volume: indicador (ou o volume que alimenta a taxa) com
      # média baixa demais não é julgado — evita "queda de 100%" em base ~zero
      vk = volume_key(key)
      min_volume = MIN_BASELINE[vk]
      next if min_volume && average(baseline_rows.map { |w| w[:values][vk].to_f }) < min_volume

      paced = paced_value(current[:values][key].to_f, key)
      closed_v = closed[:values][key].to_f

      worst = [
        { 'window' => 'semana atual (ritmo)', 'value' => paced },
        { 'window' => 'semana passada', 'value' => closed_v }
      ].min_by { |c| c['value'] }

      deviation = ((worst['value'] - baseline) / baseline * 100).round
      next if deviation > -drop_pct

      findings << {
        'indicator' => key,
        'label' => INDICATOR_LABELS[key],
        'window' => worst['window'],
        'value' => round_for(key, worst['value']),
        'baseline' => round_for(key, baseline),
        'deviation_pct' => deviation,
        'detected_at' => Time.current.iso8601
      }
    end

    # os 3 piores bastam — mais que isso vira ruído
    findings.sort_by { |f| f['deviation_pct'] }.first(3)
  end

  # taxa é julgada pelo VOLUME que a alimenta (taxa de comparecimento sem
  # consultas agendadas na base não significa nada)
  def volume_key(key)
    { 'rate_scheduling' => 'new_leads',
      'rate_attendance' => 'appointments_booked',
      'rate_surgery' => 'consultations_attended' }[key] || key
  end

  # projeção da semana corrente: valor até agora ÷ fração da semana decorrida.
  # Taxas não são projetadas (já são proporção).
  def paced_value(value, key)
    return value if RATE_KEYS.include?(key)

    now = TZ.now
    elapsed_days = now.wday.zero? ? 7 : now.wday # semana começa segunda (ISO)
    fraction = (elapsed_days - 1 + now.hour / 24.0) / 7.0
    fraction < 0.15 ? value / 0.15 : value / fraction # começo de semana não dispara alarme falso
  end

  def average(values)
    return 0.0 if values.empty?

    values.sum / values.size
  end

  def round_for(key, value)
    RATE_KEYS.include?(key) || key == 'revenue_closed' ? value.round(1) : value.round
  end

  # ── AÇÃO 1: tarefas para os responsáveis ──────────────────────────────
  def open_tasks(findings)
    opened = 0
    findings.each do |f|
      title = "📊 Gestor: #{f['label']} #{f['deviation_pct']}% vs média — #{TZ.today.strftime('%d/%m')}"
      next if account.tasks.where(title: title).exists?

      account.tasks.create!(
        title: title,
        description: "#{f['label']} está em #{f['value']} na #{f['window']} — a média das últimas " \
                     "#{state['baseline_weeks'] || 11} semanas é #{f['baseline']}. " \
                     'Vale olhar hoje: o Gestor Autônomo detectou o desvio e abriu esta tarefa sozinho.',
        task_type: 'gestao', priority: :high, status: :todo,
        due_at: TZ.now.end_of_day,
        creator: account.administrators.first,
        assignee: owner_for(f['indicator'])
      )
      opened += 1
    rescue StandardError => e
      Rails.logger.error("[Gestor] tarefa falhou conta=#{account.id}: #{e.message}")
    end
    opened
  end

  # responsável certo por indicador: donos do atendimento (agenda_config)
  # quando definidos; senão o admin
  def owner_for(indicator)
    owners = (CrmSetting.find_by(account: account)&.agenda_config || {})['attendance_owners'] || {}
    user_id = case indicator
              when 'rate_attendance', 'consultations_attended', 'appointments_booked', 'rate_scheduling'
                owners['consulta_user_id']
              when 'surgeries_booked', 'rate_surgery', 'revenue_closed'
                owners['cirurgia_user_id']
              end
    account.users.find_by(id: user_id) || account.administrators.first
  end

  # ── AÇÃO 2: briefing diário (IA barata) ───────────────────────────────
  def write_brief(weeks, findings)
    return nil if api_key.blank?

    current = weeks.last[:values]
    baseline_rows = weeks[0..-2]
    summary = INDICATOR_LABELS.keys.map do |key|
      "#{INDICATOR_LABELS[key]}: semana atual #{round_for(key, current[key].to_f)} | " \
        "média 12s #{round_for(key, average(baseline_rows.map { |w| w[:values][key].to_f }))}"
    end.join("\n")
    desvios = findings.any? ? findings.map { |f| "#{f['label']} #{f['deviation_pct']}%" }.join(', ') : 'nenhum'

    message = client.messages.create(
      model: model, max_tokens: 512, system_: system_prompt,
      messages: [{ role: 'user', content: "Números:\n#{summary}\n\nDesvios detectados: #{desvios}.\nEscreva o briefing de hoje." }]
    )
    record_usage(message)
    message.content.find { |b| b.type == :text }&.text.to_s.strip.presence
  rescue StandardError => e
    Rails.logger.error("[Gestor] briefing falhou conta=#{account.id}: #{e.message}")
    nil
  end

  def config_drop_pct
    v = (agent_config['drop_pct'].presence || DEFAULT_DROP_PCT).to_i
    v.clamp(10, 60)
  end

  def write_state(new_state)
    settings = CrmSetting.find_by(account: account)
    settings.with_lock do
      ai = (settings.reload.ai_config || {}).deep_dup
      ai['manager_state'] = new_state
      settings.update_column(:ai_config, ai) # rubocop:disable Rails/SkipsModelValidations
    end
    @ai_config = nil
  end
end
