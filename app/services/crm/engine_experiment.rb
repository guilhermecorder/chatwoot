# 🧪 TESTE A/B DE MOTOR (item 400, 22/11): o MESMO atendente, com o MESMO
# Roteiro, em duas variantes — A = o modelo do cartão; B = outro modelo (Claude
# ou ChatGPT). Cada caixa de WhatsApp em que o agente lê fica em um de três modos:
#   'a'     → todas as conversas na variante A (o padrão de toda caixa)
#   'b'     → todas na variante B ("uma caixa inteira no ChatGPT")
#   'split' → sorteio meio a meio POR CONVERSA; a conversa fica na variante
#             sorteada até o fim (a comparação mais justa: mesmo número, mesmo
#             anúncio, mesmo horário; só o motor muda)
#
# A config mora em ai_config['agents'][agente]['ab']:
#   { 'enabled' => true, 'model_b' => 'gpt-6.2-sol', 'inboxes' => { '12' => 'b' },
#     'started_at' => '2026-11-22T…' }   ← started_at é o "número" do teste
#
# O PLACAR não precisa de tabela nova: cada conversa atendida ganha um carimbo
# em additional_attributes['cevico_ia_ab'][agente] com a variante, quantas
# respostas, quanto custou (US$) e se agendou / chamou humano. Zerar o placar =
# started_at novo (os carimbos antigos deixam de contar).
module Crm::EngineExperiment # rubocop:disable Metrics/ModuleLength
  module_function

  STAMP = 'cevico_ia_ab'.freeze
  CONFIG_KEY = 'ab'.freeze
  ARMS = %w[a b].freeze
  MODES = %w[a b split].freeze
  # antes disso, por variante, qualquer diferença pode ser acaso
  MIN_SAMPLE = 100
  # 95% de confiança (teste de duas proporções)
  Z_95 = 1.96
  ROW_CAP = 20_000

  # a config LIGADA e completa do agente, ou nil
  def active(agent_config)
    ab = agent_config.is_a?(Hash) ? agent_config[CONFIG_KEY] : nil
    return nil unless ab.is_a?(Hash) && ab['enabled'] == true && ab['model_b'].present? && ab['started_at'].present?

    ab
  end

  def mode_for(experiment, inbox_id)
    mode = (experiment['inboxes'] || {})[inbox_id.to_s]
    MODES.include?(mode) ? mode : 'a'
  end

  # variante desta conversa: 'a' | 'b' | nil (sem teste ligado)
  def arm_for(conversation, agent_key, agent_config)
    experiment = active(agent_config)
    return nil if experiment.nil?

    mode = mode_for(experiment, conversation.inbox_id)
    return mode unless mode == 'split'

    stamped = stamp_of(conversation, agent_key)
    return stamped['arm'] if stamped && stamped['test'] == experiment['started_at'] && ARMS.include?(stamped['arm'])

    draw(experiment, conversation)
  end

  # sorteio que não muda: a mesma conversa cai sempre na mesma variante
  def draw(experiment, conversation)
    Zlib.crc32("#{experiment['started_at']}:#{conversation.id}").even? ? 'a' : 'b'
  end

  def stamp_of(conversation, agent_key)
    stamp = conversation.additional_attributes&.dig(STAMP, agent_key.to_s)
    stamp.is_a?(Hash) ? stamp : nil
  end

  # soma UM acontecimento no carimbo da conversa. event (tudo opcional):
  #   'model', 'cost_usd', 'reply', 'shadow', 'would_book', 'booked', 'handoff',
  #   'error', 'fallback'
  def track!(conversation, agent_key, agent_config, arm, event = {}) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
    experiment = active(agent_config)
    return if experiment.nil? || ARMS.exclude?(arm.to_s)

    now = Time.current.iso8601
    Cevico::AttributeMerge.merge!(conversation) do |attrs|
      all = attrs[STAMP].is_a?(Hash) ? attrs[STAMP] : {}
      row = all[agent_key.to_s]
      row = { 'test' => experiment['started_at'], 'arm' => arm.to_s, 'at' => now } unless row.is_a?(Hash) && row['test'] == experiment['started_at']
      # a caixa mudou de variante no meio do teste: a conversa viu os dois motores e sai do placar
      row['misto'] = true if row['arm'] != arm.to_s
      row['model'] = event['model'] if event['model'].present?
      row['custo_usd'] = (row['custo_usd'].to_f + event['cost_usd'].to_f).round(6)
      %w[reply shadow would_book error fallback].zip(%w[respostas sombras agendaria erros reservas]).each do |flag, counter|
        row[counter] = row[counter].to_i + 1 if event[flag]
      end
      row['agendou_at'] ||= now if event['booked']
      row['humano_at'] ||= now if event['handoff']
      row['ultima_at'] = now
      attrs.merge(STAMP => all.merge(agent_key.to_s => row))
    end
  rescue StandardError => e
    Rails.logger.warn "[Crm::EngineExperiment] carimbo: #{e.class}: #{e.message}"
  end

  # ── PLACAR ──────────────────────────────────────────────────────────────
  def report(account, agent_key) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    agent_config = CrmSetting.find_by(account: account)&.ai_config&.dig('agents', agent_key.to_s) || {}
    experiment = agent_config[CONFIG_KEY]
    return empty_report unless experiment.is_a?(Hash) && experiment['started_at'].present?

    rows = stamped_rows(account, agent_key, experiment['started_at'])
    mixed, clean = rows.partition { |row| row[:stamp]['misto'] }
    with_task = contacts_with_appointment(account, clean)
    arms = ARMS.map { |arm| arm_summary(arm, clean.select { |row| row[:stamp]['arm'] == arm }, with_task) }
    { started_at: experiment['started_at'], arms: arms, mixed: mixed.size, min_sample: MIN_SAMPLE,
      verdict: verdict(arms), capped: rows.size >= ROW_CAP }
  end

  def empty_report
    { started_at: nil, arms: [], mixed: 0, min_sample: MIN_SAMPLE, verdict: nil, capped: false }
  end

  def stamped_rows(account, agent_key, test_id)
    account.conversations
           .where('additional_attributes -> ? -> ? ->> ? = ?', STAMP, agent_key.to_s, 'test', test_id)
           .limit(ROW_CAP).pluck(:id, :contact_id, :additional_attributes)
           .map { |id, contact_id, attrs| { id: id, contact_id: contact_id, stamp: attrs.dig(STAMP, agent_key.to_s) || {} } }
  end

  # ids das conversas cujo paciente ganhou uma consulta na Agenda DEPOIS de
  # entrar no teste (pela IA ou pela equipe; canceladas não contam)
  def contacts_with_appointment(account, rows)
    contact_ids = rows.pluck(:contact_id).compact.uniq
    return Set.new if contact_ids.empty?

    created = account.tasks.where(task_type: 'consulta', canceled_at: nil, contact_id: contact_ids)
                     .pluck(:contact_id, :created_at).group_by(&:first)
    booked = rows.select do |row|
      since = Time.zone.parse(row[:stamp]['at'].to_s)
      since && Array(created[row[:contact_id]]).any? { |(_, at)| at >= since }
    end
    booked.to_set { |row| row[:id] }
  end

  def arm_summary(arm, rows, with_task) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    served = rows.select { |row| row[:stamp]['respostas'].to_i.positive? || row[:stamp]['sombras'].to_i.positive? }
    sum = ->(key) { rows.sum { |row| row[:stamp][key].to_i } }
    cost = rows.sum { |row| row[:stamp]['custo_usd'].to_f }
    booked = served.count { |row| row[:stamp]['agendou_at'].present? }
    appointment = served.count { |row| with_task.include?(row[:id]) }
    models = rows.filter_map { |row| row[:stamp]['model'] }.tally
    {
      arm: arm, model: models.max_by(&:last)&.first,
      conversas: served.size, respostas: sum.call('respostas'), sombras: sum.call('sombras'),
      agendaria: served.count { |row| row[:stamp]['agendaria'].to_i.positive? },
      agendou: booked, taxa_agendou: rate(booked, served.size),
      com_consulta: appointment, taxa_consulta: rate(appointment, served.size),
      humano: served.count { |row| row[:stamp]['humano_at'].present? },
      erros: sum.call('erros'), reservas: sum.call('reservas'),
      custo_usd: cost.round(4),
      custo_por_conversa_usd: served.any? ? (cost / served.size).round(4) : nil,
      custo_por_consulta_usd: appointment.positive? ? (cost / appointment).round(4) : nil
    }
  end

  def rate(part, whole)
    whole.positive? ? (part * 100.0 / whole).round(1) : nil
  end

  # quem está na frente em "paciente com consulta marcada"? Só afirma com
  # amostra mínima E diferença que o acaso não explica (95%).
  def verdict(arms)
    a, b = arms
    return nil if a.nil? || b.nil?

    smallest = [a[:conversas], b[:conversas]].min
    return { status: 'cedo', missing: MIN_SAMPLE - smallest } if smallest < MIN_SAMPLE

    z = z_score(a[:com_consulta], a[:conversas], b[:com_consulta], b[:conversas])
    return { status: 'empate', z: z.round(2) } if z.abs < Z_95

    { status: z.positive? ? 'b' : 'a', z: z.round(2) }
  end

  # positivo = B converte mais
  def z_score(hits_a, total_a, hits_b, total_b)
    pooled = (hits_a + hits_b).to_f / (total_a + total_b)
    spread = Math.sqrt(pooled * (1 - pooled) * ((1.0 / total_a) + (1.0 / total_b)))
    return 0.0 if spread.zero?

    ((hits_b.to_f / total_b) - (hits_a.to_f / total_a)) / spread
  end
end
