# 🧪 TESTE A/B DO ATENDENTE (item 400, 22/11 → item 403, 23/11): o MESMO
# atendente em duas variantes. Cada variante é PROMPT + MOTOR:
#   A = o oficial: Roteiro 1 + o modelo do cartão
#   B = o desafiante: Roteiro 1 ou Roteiro 2 (o paralelo, editável na tela)
#       + o mesmo modelo da A ou outro (Claude, ChatGPT, Gemini)
# Uma coisa de cada vez: primeiro acerta-se o PROMPT (mesmo motor nas duas),
# depois testa-se a INTELIGÊNCIA (mesmo prompt nas duas). Se as duas coisas
# mudam juntas, o tipo vira 'ambos' e a tela avisa que não dá para saber a causa.
#
# Cada caixa de WhatsApp em que o agente lê fica em um de três modos:
#   'a'     → todas as conversas na variante A (o padrão de toda caixa)
#   'b'     → todas na variante B
#   'split' → sorteio meio a meio POR CONVERSA; a conversa fica na variante
#             sorteada até o fim (a comparação mais justa: mesmo número, mesmo
#             anúncio, mesmo horário; só a variante muda)
#
# A config mora em ai_config['agents'][agente]['ab']:
#   { 'enabled' => true, 'name' => 'Recepção sem a palavra cirurgia',
#     'script_b' => 'v2', 'model_b' => nil, 'inboxes' => { '12' => 'split' },
#     'started_at' => '2026-11-23T…',          ← o "número" do teste
#     'digests' => { 'a' => '…', 'b' => '…' } } ← impressão digital dos prompts
#
# O PLACAR não precisa de tabela nova: cada conversa atendida ganha um carimbo
# em additional_attributes['cevico_ia_ab'][agente] com a variante, o Roteiro,
# quantas respostas, quanto custou (US$) e se agendou / chamou humano. Zerar o
# placar = started_at novo (os carimbos antigos deixam de contar, mas continuam
# lá: o teste encerrado vai para ai_config['agents'][agente]['ab_history'] e o
# Laboratório relê o funil dele quando quiser — comparecimento e cirurgia
# amadurecem semanas depois).
module Crm::EngineExperiment # rubocop:disable Metrics/ModuleLength
  module_function

  STAMP = 'cevico_ia_ab'.freeze
  CONFIG_KEY = 'ab'.freeze
  HISTORY_KEY = 'ab_history'.freeze
  HISTORY_CAP = 30
  KINDS = %w[prompt motor ambos].freeze
  ARMS = %w[a b].freeze
  MODES = %w[a b split].freeze
  # antes disso, por variante, qualquer diferença pode ser acaso
  MIN_SAMPLE = 100
  # 95% de confiança (teste de duas proporções)
  Z_95 = 1.96
  # 80% de poder: a chance de o teste enxergar uma diferença que existe
  Z_POWER = 0.84
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  ROW_CAP = 20_000

  # a config LIGADA e completa do agente, ou nil
  def active(agent_config)
    ab = agent_config.is_a?(Hash) ? agent_config[CONFIG_KEY] : nil
    return nil unless ab.is_a?(Hash) && ab['enabled'] == true && ab['started_at'].present? && variant_b?(ab)

    ab
  end

  # a B só existe se muda ALGUMA coisa: o Roteiro, o motor ou os dois
  def variant_b?(experiment)
    experiment['model_b'].present? || script_b(experiment) == 'v2'
  end

  def script_b(experiment)
    Crm::CevicoScript.normalize_version(experiment.is_a?(Hash) ? experiment['script_b'] : nil)
  end

  # o Roteiro que a variante lê ('v1' = oficial; 'v2' = o paralelo)
  def script_for(experiment, arm)
    arm.to_s == 'b' ? script_b(experiment) : 'v1'
  end

  # 🧭 item 405 (motor por coluna): em quais colunas a B troca o motor. Lista de
  # "slots" do Crm::StageEngine (id da coluna em texto ou 'sem_card'); vazia =
  # em todas. Assim dá para testar o cérebro SÓ da recepção, por exemplo, e
  # deixar o resto do mapa igual nas duas variantes.
  def stages_b(experiment)
    list = experiment.is_a?(Hash) ? experiment['stages_b'] : nil
    Array(list).map(&:to_s).compact_blank.uniq
  end

  # nesta conversa (pela coluna do card) a B usa o motor dela?
  def model_b_here?(experiment, conversation)
    return false unless experiment.is_a?(Hash) && experiment['model_b'].present?

    slots = stages_b(experiment)
    slots.empty? || slots.include?(Crm::StageEngine.slot_for(conversation))
  end

  # o que este teste compara: 'prompt' | 'motor' | 'ambos'.
  # staged = o atendente tem motor por coluna: aí o motor da B conta como
  # diferença mesmo sendo igual ao modelo do cartão (o mapa da A é outro).
  def kind(experiment, model_a, staged: false)
    prompt = script_b(experiment) == 'v2'
    motor = experiment['model_b'].present? && (staged || experiment['model_b'] != model_a)
    return 'ambos' if prompt && motor

    prompt ? 'prompt' : 'motor'
  end

  # o modelo que a variante A usa de verdade (o do cartão; em branco = recomendado)
  def model_a(agent_key, agent_config)
    (agent_config || {})['model'].presence || Crm::AiAgentConfig::RECOMMENDED.dig(agent_key.to_s, 'model') || Crm::AiAgentConfig::DEFAULT_MODEL
  end

  # impressão digital do prompt de uma variante (Roteiro + passos do agente):
  # se alguém editar o texto no meio do teste, o Laboratório avisa
  def prompt_digest(account, agent_key, version)
    body = "#{Crm::CevicoScript.text(account, version)}\n#{Crm::CevicoScript.stage_prompt(account, agent_key.to_s, version)}"
    Digest::SHA1.hexdigest(body)[0, 12]
  end

  def digests(account, agent_key, experiment)
    ARMS.index_with { |arm| prompt_digest(account, agent_key, script_for(experiment, arm)) }
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
      unless row.is_a?(Hash) && row['test'] == experiment['started_at']
        row = { 'test' => experiment['started_at'], 'arm' => arm.to_s, 'at' => now, 'script' => script_for(experiment, arm),
                'slot' => Crm::StageEngine.slot_for(conversation) } # a coluna em que a conversa ENTROU no teste
      end
      # a caixa mudou de variante no meio do teste: a conversa viu as duas e sai do placar
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
  # test_id = qual teste ler (o do histórico); em branco = o teste de agora
  def report(account, agent_key, test_id = nil) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    agent_config = CrmSetting.find_by(account: account)&.ai_config&.dig('agents', agent_key.to_s) || {}
    experiment = agent_config[CONFIG_KEY]
    test_id = test_id.presence || (experiment.is_a?(Hash) ? experiment['started_at'] : nil)
    return empty_report if test_id.blank?

    rows = stamped_rows(account, agent_key, test_id)
    mixed, clean = rows.partition { |row| row[:stamp]['misto'] }
    outcomes = outcomes_for(account, clean)
    replied = replied_ids(account, agent_key, test_id)
    arms = ARMS.map { |arm| arm_summary(arm, clean.select { |row| row[:stamp]['arm'] == arm }, outcomes, replied) }
    ended_at = history(agent_config).find { |entry| entry['id'] == test_id }&.dig('ended_at')
    days = days_running(test_id, ended_at)
    stats = stats_for(arms, days)
    { started_at: test_id, ended_at: ended_at, days: days.round(1), arms: arms, mixed: mixed.size, min_sample: MIN_SAMPLE,
      verdict: verdict(arms), stats: stats, projection: projection(arms, days), daily: daily(clean, outcomes),
      capped: rows.size >= ROW_CAP }
  end

  def empty_report
    { started_at: nil, ended_at: nil, days: 0, arms: [], mixed: 0, min_sample: MIN_SAMPLE, verdict: nil, stats: nil,
      projection: nil, daily: [], capped: false }
  end

  def stamped_rows(account, agent_key, test_id)
    account.conversations
           .where('additional_attributes -> ? -> ? ->> ? = ?', STAMP, agent_key.to_s, 'test', test_id)
           .limit(ROW_CAP).pluck(:id, :contact_id, :additional_attributes)
           .map { |id, contact_id, attrs| { id: id, contact_id: contact_id, stamp: attrs.dig(STAMP, agent_key.to_s) || {} } }
  end

  def any_rows?(account, agent_key, test_id)
    return false if test_id.blank?

    account.conversations.exists?(['additional_attributes -> ? -> ? ->> ? = ?', STAMP, agent_key.to_s, 'test', test_id])
  end

  # O RETORNO de cada conversa, lido na Agenda: o paciente ganhou consulta
  # DEPOIS de entrar no teste (pela IA ou pela equipe; cancelada não conta)?
  # Compareceu? Saiu com indicação de cirurgia? Marcou a cirurgia?
  # Devolve { id da conversa => { marcou:, compareceu:, indicacao:, cirurgia: } }
  def outcomes_for(account, rows) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    contact_ids = rows.pluck(:contact_id).compact.uniq
    return {} if contact_ids.empty?

    tasks = account.tasks.where(task_type: %w[consulta cirurgia], canceled_at: nil, contact_id: contact_ids)
                   .pluck(:contact_id, :created_at, :task_type, :attendance, :surgery_indication).group_by(&:first)
    rows.each_with_object({}) do |row, map|
      since = Time.zone.parse(row[:stamp]['at'].to_s)
      next if since.nil?

      mine = Array(tasks[row[:contact_id]]).select { |(_, created_at)| created_at >= since }
      consultas = mine.select { |task| task[2] == 'consulta' }
      next if mine.empty?

      map[row[:id]] = { marcou: consultas.any?, compareceu: consultas.any? { |task| task[3] == 'attended' },
                        indicacao: consultas.any? { |task| task[4] == 'indicated' },
                        cirurgia: mine.any? { |task| task[2] == 'cirurgia' } }
    end
  end

  # conversas em que o paciente ESCREVEU DE NOVO depois da 1ª resposta do
  # atendente no teste — o sinal mais rápido de um prompt melhor (não espera a consulta)
  def replied_ids(account, agent_key, test_id)
    Message.where(account_id: account.id, message_type: :incoming).joins(:conversation)
           .where('conversations.additional_attributes -> ? -> ? ->> ? = ?', STAMP, agent_key.to_s, 'test', test_id)
           .where('messages.created_at > (conversations.additional_attributes -> ? -> ? ->> ?)::timestamptz', STAMP, agent_key.to_s, 'at')
           .reorder(nil).distinct.pluck(:conversation_id).to_set
  end

  def arm_summary(arm, rows, outcomes, replied) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
    served = rows.select { |row| row[:stamp]['respostas'].to_i.positive? || row[:stamp]['sombras'].to_i.positive? }
    sum = ->(key) { rows.sum { |row| row[:stamp][key].to_i } }
    hit = ->(key) { served.count { |row| outcomes.dig(row[:id], key) } }
    cost = rows.sum { |row| row[:stamp]['custo_usd'].to_f }
    booked = served.count { |row| row[:stamp]['agendou_at'].present? }
    answered = served.count { |row| replied.include?(row[:id]) }
    appointment = hit.call(:marcou)
    attended = hit.call(:compareceu)
    surgery = hit.call(:cirurgia)
    per = ->(count) { count.positive? ? (cost / count).round(4) : nil }
    {
      arm: arm, model: top(rows, 'model'), script: top(rows, 'script'),
      conversas: served.size, respostas: sum.call('respostas'), sombras: sum.call('sombras'),
      respondeu: answered, taxa_respondeu: rate(answered, served.size),
      agendaria: served.count { |row| row[:stamp]['agendaria'].to_i.positive? },
      agendou: booked, taxa_agendou: rate(booked, served.size),
      com_consulta: appointment, taxa_consulta: rate(appointment, served.size),
      compareceu: attended, taxa_compareceu: rate(attended, served.size),
      indicacao: hit.call(:indicacao), cirurgia: surgery, taxa_cirurgia: rate(surgery, served.size),
      humano: served.count { |row| row[:stamp]['humano_at'].present? },
      erros: sum.call('erros'), reservas: sum.call('reservas'),
      custo_usd: cost.round(4),
      custo_por_conversa_usd: per.call(served.size),
      custo_por_consulta_usd: per.call(appointment),
      custo_por_comparecimento_usd: per.call(attended),
      custo_por_cirurgia_usd: per.call(surgery)
    }
  end

  def top(rows, key)
    rows.filter_map { |row| row[:stamp][key].presence }.tally.max_by(&:last)&.first
  end

  def rate(part, whole)
    whole.positive? ? (part * 100.0 / whole).round(1) : nil
  end

  # há quantos dias o teste roda (ou rodou, se já foi encerrado)
  def days_running(test_id, ended_at = nil)
    from = Time.zone.parse(test_id.to_s)
    upto = ended_at.present? ? Time.zone.parse(ended_at.to_s) : Time.current
    return 1.0 if from.nil? || upto.nil?

    [(upto - from) / 1.day, 1.0].max
  end

  # dia a dia (fuso de São Paulo, pelo dia em que a conversa ENTROU no teste):
  # conversas atendidas, com consulta marcada e custo de cada variante. A tela
  # acumula e desenha a taxa andando no tempo.
  def daily(rows, outcomes) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    days = Hash.new { |hash, day| hash[day] = ARMS.index_with { { 'conversas' => 0, 'consultas' => 0, 'custo_usd' => 0.0 } } }
    rows.each do |row|
      stamp = row[:stamp]
      at = Time.zone.parse(stamp['at'].to_s)
      next if at.nil? || ARMS.exclude?(stamp['arm'])

      cell = days[at.in_time_zone(TZ).to_date.iso8601][stamp['arm']]
      cell['custo_usd'] = (cell['custo_usd'] + stamp['custo_usd'].to_f).round(6)
      next unless stamp['respostas'].to_i.positive? || stamp['sombras'].to_i.positive?

      cell['conversas'] += 1
      cell['consultas'] += 1 if outcomes.dig(row[:id], :marcou)
    end
    days.sort.map { |day, arms| { date: day }.merge(arms.transform_keys(&:to_sym)) }
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
    return 0.0 if total_a.zero? || total_b.zero?

    pooled = (hits_a + hits_b).to_f / (total_a + total_b)
    spread = Math.sqrt(pooled * (1 - pooled) * ((1.0 / total_a) + (1.0 / total_b)))
    return 0.0 if spread.zero?

    ((hits_b.to_f / total_b) - (hits_a.to_f / total_a)) / spread
  end

  # ── A CONTA DA CONFIANÇA ────────────────────────────────────────────────
  # chance_b = de 0 a 100, quanto os números de hoje apontam para a B marcar
  # mais consulta (50 = cara ou coroa; 95 = a casa decide). needed = quantas
  # conversas POR VARIANTE a diferença de hoje pede para virar certeza;
  # days_left = no ritmo atual, quantos dias faltam.
  def stats_for(arms, days) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    a, b = arms
    return nil if a.nil? || b.nil? || a[:conversas].zero? || b[:conversas].zero?

    z = z_score(a[:com_consulta], a[:conversas], b[:com_consulta], b[:conversas])
    needed = sample_needed(a[:com_consulta].to_f / a[:conversas], b[:com_consulta].to_f / b[:conversas])
    smallest = [a[:conversas], b[:conversas]].min
    pace = smallest / days
    missing = needed ? [needed - smallest, 0].max : nil
    {
      z: z.round(2), chance_b: (normal_cdf(z) * 100).round(1), needed: needed, missing: missing,
      pace_per_day: pace.round(1),
      days_left: missing && pace.positive? ? (missing / pace).ceil : nil
    }
  end

  def normal_cdf(z_value)
    0.5 * (1 + Math.erf(z_value / Math.sqrt(2)))
  end

  # tamanho de amostra por variante para enxergar a diferença observada
  # (95% de confiança, 80% de poder); nil = as duas estão iguais até agora
  def sample_needed(rate_a, rate_b)
    gap = (rate_b - rate_a).abs
    return nil if gap < 0.0005

    variance = (rate_a * (1 - rate_a)) + (rate_b * (1 - rate_b))
    [(((Z_95 + Z_POWER)**2) * variance / (gap**2)).ceil, MIN_SAMPLE].max
  end

  # ── A CONTA DA DECISÃO ──────────────────────────────────────────────────
  # "e se TODAS as conversas do mês fossem em uma variante só?" — custo de IA
  # e consultas marcadas de cada lado, no volume real do teste. É o que diz
  # quanto custa cada consulta A MAIS que a variante melhor traz.
  def projection(arms, days) # rubocop:disable Metrics/AbcSize
    a, b = arms
    return nil if a.nil? || b.nil? || a[:conversas].zero? || b[:conversas].zero?

    monthly = ((a[:conversas] + b[:conversas]) / days * 30).round
    side = lambda do |arm|
      { custo_usd: (arm[:custo_usd] / arm[:conversas] * monthly).round(2),
        consultas: (arm[:com_consulta].to_f / arm[:conversas] * monthly).round(1) }
    end
    month_a = side.call(a)
    month_b = side.call(b)
    extra_cost = (month_b[:custo_usd] - month_a[:custo_usd]).round(2)
    extra_hits = (month_b[:consultas] - month_a[:consultas]).round(1)
    # só faz sentido quando custo e consultas andam para o mesmo lado (mais caro e marca mais, ou o contrário)
    per_extra = extra_hits.abs >= 0.5 && (extra_cost.positive? == extra_hits.positive?) ? (extra_cost / extra_hits).round(2) : nil
    { conversas_mes: monthly, a: month_a, b: month_b, extra_custo_usd: extra_cost, extra_consultas: extra_hits,
      custo_por_consulta_extra_usd: per_extra }
  end

  # ── HISTÓRICO DOS TESTES ────────────────────────────────────────────────
  def history(agent_config)
    list = agent_config.is_a?(Hash) ? agent_config[HISTORY_KEY] : nil
    list.is_a?(Array) ? list.select { |entry| entry.is_a?(Hash) && entry['id'].present? } : []
  end

  # a ficha de um teste que termina: o que comparava e o que foi decidido.
  # decision: 'a' (fica a oficial) | 'b' (adota a desafiante) | nil (sem decisão)
  def history_entry(experiment, agent_key, agent_config, by: nil, decision: nil, note: nil) # rubocop:disable Metrics/ParameterLists, Metrics/AbcSize
    first = model_a(agent_key, agent_config)
    {
      'id' => experiment['started_at'], 'started_at' => experiment['started_at'], 'ended_at' => Time.current.iso8601,
      'name' => experiment['name'].presence, 'kind' => kind(experiment, first, staged: Crm::StageEngine.config(agent_config).any?),
      'model_a' => first, 'model_b' => experiment['model_b'].presence || first, 'script_b' => script_b(experiment),
      'stage_models' => Crm::StageEngine.config(agent_config).presence, 'stages_b' => stages_b(experiment).presence,
      'inboxes' => experiment['inboxes'] || {},
      'decision' => ARMS.include?(decision.to_s) ? decision.to_s : nil, 'note' => note.to_s.strip.first(300).presence,
      'ended_by' => by
    }.compact
  end

  # a foto do placar na hora em que o teste terminou (para a lista do histórico;
  # o Laboratório relê o funil completo pelo id quando o teste é aberto)
  def snapshot(report)
    Array(report[:arms]).to_h do |arm|
      [arm[:arm], arm.slice(:conversas, :com_consulta, :taxa_consulta, :custo_usd, :custo_por_conversa_usd).stringify_keys]
    end
  end

  # guarda a ficha (a mais nova na frente; o mesmo teste nunca entra duas vezes)
  def push_history(agent_config, entry)
    kept = history(agent_config).reject { |old| old['id'] == entry['id'] }
    ([entry] + kept).first(HISTORY_CAP)
  end
end
