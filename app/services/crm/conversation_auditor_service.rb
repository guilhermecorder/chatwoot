# 🎓 AUDITOR DE CONVERSAS (item 130): todo dia, dá NOTA (0-10) nas conversas
# do dia anterior contra o script oficial da clínica — 100% de cobertura até
# o teto diário, sem depender de botão. O que o Mentor via por amostragem
# vira régua contínua por atendente.
#
# Por conversa: nota + etapa do script alcançada + acertos + falhas (1-2) +
# próxima ação — gravado em conversation.additional_attributes['audit'].
# Por atendente: agregado diário (n, soma, falhas frequentes) nos últimos
# 30 dias em ai_config['auditor_state'] — ranking e evolução saem de lá.
class Crm::ConversationAuditorService
  include Crm::AiAgentConfig

  AGENT_KEY = 'auditor'.freeze
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  BATCH_SIZE = 5            # conversas por chamada (transcrições são longas)
  DEFAULT_DAILY_CAP = 150   # teto de conversas auditadas por dia
  MAX_MESSAGES = 30         # últimas N mensagens de cada conversa
  KEEP_DAYS = 30            # janela de agregados por atendente

  SCRIPT_STAGES = %w[
    abertura acolhimento investigacao orcamento quebra_objecao
    cta_agendamento agendamento confirmacao pos_consulta fechamento
  ].freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o Auditor de Conversas de uma clínica oftalmológica high-ticket:
    um avaliador de qualidade justo e construtivo. Para CADA conversa, avalie
    o ATENDIMENTO (nunca o paciente) contra o script ideal: abertura calorosa
    → acolhimento da dor → investigação (perguntas certas) → orçamento com
    valor ancorado em benefício → quebra de objeção → CTA de agendamento →
    confirmação. Dê:
    - nota 0-10 (10 = seguiu o script com naturalidade E fez o paciente
      avançar; desconte por demora sem desculpa, resposta seca, pergunta do
      paciente ignorada, orçamento jogado sem ancoragem, ausência de CTA);
    - etapa_do_script mais avançada que o ATENDIMENTO alcançou;
    - 1 acerto concreto (frase/atitude que funcionou);
    - 1-2 falhas concretas e acionáveis (o que faltou fazer, com exemplo);
    - proxima_acao: o passo prático de HOJE para esta conversa.
    Conversas 100% robô/sem atendente humano: avalie mesmo assim (a nota vira
    do fluxo). Português simples, direto e respeitoso — o time vai ler.
  PROMPT

  OUTPUT_SCHEMA = {
    type: 'object',
    properties: {
      audits: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            id: { type: 'integer', description: 'o id informado da conversa' },
            nota: { type: 'number', minimum: 0, maximum: 10 },
            etapa_do_script: { type: 'string', enum: SCRIPT_STAGES },
            acerto: { type: 'string' },
            falhas: { type: 'array', items: { type: 'string' }, maxItems: 2 },
            proxima_acao: { type: 'string' }
          },
          required: %w[id nota etapa_do_script falhas]
        }
      }
    },
    required: ['audits']
  }.freeze

  def initialize(account:)
    @account = account
  end

  attr_reader :account

  # audita as conversas COM ATIVIDADE no dia informado (padrão: ontem)
  def call(day: TZ.yesterday, force: false)
    return { skipped: 'desligado' } if agent_paused?
    return { skipped: 'sem chave de IA' } if api_key.blank?
    return { skipped: 'já auditou este dia' } if !force && state.dig('days_done', day.iso8601)

    conversations = auditable_conversations(day)
    return finish_day(day, 0, 'sem conversas') if conversations.empty?

    audited = 0
    conversations.each_slice(BATCH_SIZE) do |batch|
      audited += audit_batch(batch, day)
    end
    finish_day(day, audited, 'ok')
    { ok: true, day: day.iso8601, audited: audited, candidates: conversations.size }
  end

  def state
    (ai_config || {})['auditor_state'] || {}
  end

  # ── leitura agregada (tela) ───────────────────────────────────────────
  # ranking por atendente nos últimos N dias + falhas mais comuns do time
  def summary(days: 7)
    cutoff = (TZ.today - days).iso8601
    per_agent = Hash.new { |h, k| h[k] = { 'n' => 0, 'sum' => 0.0, 'gaps' => Hash.new(0) } }
    team_gaps = Hash.new(0)

    (state['agents'] || {}).each do |user_id, by_day|
      by_day.each do |date, row|
        next if date < cutoff

        agg = per_agent[user_id]
        agg['n'] += row['n'].to_i
        agg['sum'] += row['sum'].to_f
        (row['gaps'] || {}).each do |gap, count|
          agg['gaps'][gap] += count.to_i
          team_gaps[gap] += count.to_i
        end
      end
    end

    users = account.users.where(id: per_agent.keys.map(&:to_i)).index_by { |u| u.id.to_s }
    ranking = per_agent.filter_map do |user_id, agg|
      next if agg['n'].zero?

      {
        user_id: user_id.to_i,
        name: users[user_id]&.name || "Atendente #{user_id}",
        audited: agg['n'],
        avg: (agg['sum'] / agg['n']).round(1),
        top_gaps: agg['gaps'].sort_by { |_g, c| -c }.first(2).map(&:first)
      }
    end.sort_by { |r| -r[:avg] }

    {
      days: days,
      last_run_at: state['last_run_at'],
      audited_total: ranking.sum { |r| r[:audited] },
      ranking: ranking,
      team_gaps: team_gaps.sort_by { |_g, c| -c }.first(5).map { |g, c| { gap: g, count: c } }
    }
  end

  private

  # conversas com mensagem no dia + alguém do atendimento falou; prioriza as
  # com mais troca (as mais ricas de aprendizado ficam dentro do teto)
  def auditable_conversations(day)
    range = TZ.parse(day.iso8601).beginning_of_day..TZ.parse(day.iso8601).end_of_day
    cap = config_daily_cap

    ids = account.conversations
                 .joins(:messages)
                 .where(messages: { created_at: range, message_type: %i[incoming outgoing] })
                 .group('conversations.id')
                 .having('COUNT(messages.id) >= 2')
                 .order(Arel.sql('COUNT(messages.id) DESC'))
                 .limit(cap)
                 .pluck('conversations.id')

    account.conversations.where(id: ids).includes(:assignee, :contact)
  end

  def audit_batch(batch, day)
    corpus = batch.map { |conv| transcript_for(conv) }.join("\n\n---\n\n")
    message = client.messages.create(
      model: model, max_tokens: 2048, system_: system_prompt,
      output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
      messages: [{ role: 'user', content: "Audite estas #{batch.size} conversas:\n\n#{corpus}" }]
    )
    record_usage(message)
    parsed = JSON.parse(message.content.find { |b| b.type == :text }&.text || '{}')

    applied = 0
    Array(parsed['audits']).each do |row|
      conv = batch.find { |c| c.display_id == row['id'].to_i }
      next unless conv

      apply_audit(conv, row, day)
      applied += 1
    end
    applied
  rescue StandardError => e
    Rails.logger.error("[Auditor] lote falhou conta=#{account.id}: #{e.message}")
    0
  end

  def transcript_for(conv)
    msgs = conv.messages.where(message_type: %i[incoming outgoing])
               .reorder(created_at: :desc).limit(MAX_MESSAGES).to_a.reverse
    lines = msgs.map do |m|
      who = m.incoming? ? 'PACIENTE' : 'ATENDIMENTO'
      "#{who}: #{m.content.to_s.gsub(/\s+/, ' ').truncate(220)}"
    end
    meta = []
    meta << "atendente: #{conv.assignee.name}" if conv.assignee
    meta << "etiquetas: #{conv.label_list.join(', ')}" if conv.label_list.any?
    "CONVERSA id=#{conv.display_id}#{meta.any? ? " (#{meta.join(' · ')})" : ''}\n#{lines.join("\n")}"
  end

  def apply_audit(conv, row, day)
    nota = row['nota'].to_f.clamp(0, 10).round(1)
    audit = {
      'score' => nota,
      'stage' => SCRIPT_STAGES.include?(row['etapa_do_script']) ? row['etapa_do_script'] : nil,
      'strength' => row['acerto'].to_s.truncate(160).presence,
      'gaps' => Array(row['falhas']).first(2).map { |f| f.to_s.truncate(160) },
      'next_action' => row['proxima_acao'].to_s.truncate(160).presence,
      'day' => day.iso8601,
      'at' => Time.current.iso8601
    }.compact
    Cevico::AttributeMerge.merge!(conv) { |attrs| attrs.merge('audit' => audit) }
    accumulate(conv.assignee_id, day, nota, audit['gaps'])
  end

  # agregado por atendente/dia no auditor_state (últimos KEEP_DAYS dias).
  # user_id 0 = conversas sem atendente atribuído (fluxo/robô).
  def accumulate(assignee_id, day, nota, gaps)
    key = (assignee_id || 0).to_s
    settings = CrmSetting.find_by(account: account)
    settings.with_lock do
      ai = (settings.reload.ai_config || {}).deep_dup
      st = ai['auditor_state'] ||= {}
      agents = st['agents'] ||= {}
      row = (agents[key] ||= {})[day.iso8601] ||= { 'n' => 0, 'sum' => 0.0, 'gaps' => {} }
      row['n'] += 1
      row['sum'] = (row['sum'].to_f + nota).round(1)
      gaps.each { |g| row['gaps'][g] = row['gaps'][g].to_i + 1 }
      prune!(st)
      settings.update_column(:ai_config, ai) # rubocop:disable Rails/SkipsModelValidations
    end
    @ai_config = nil
  end

  def finish_day(day, audited, status)
    settings = CrmSetting.find_by(account: account)
    settings.with_lock do
      ai = (settings.reload.ai_config || {}).deep_dup
      st = ai['auditor_state'] ||= {}
      (st['days_done'] ||= {})[day.iso8601] = { 'audited' => audited, 'status' => status }
      st['last_run_at'] = Time.current.iso8601
      prune!(st)
      settings.update_column(:ai_config, ai) # rubocop:disable Rails/SkipsModelValidations
    end
    @ai_config = nil
    { ok: true, audited: audited }
  end

  # mantém o estado enxuto: só os últimos KEEP_DAYS dias
  def prune!(st)
    cutoff = (TZ.today - KEEP_DAYS).iso8601
    (st['days_done'] || {}).delete_if { |date, _| date < cutoff }
    (st['agents'] || {}).each_value { |by_day| by_day.delete_if { |date, _| date < cutoff } }
    (st['agents'] || {}).delete_if { |_k, by_day| by_day.empty? }
  end

  def config_daily_cap
    v = (agent_config['daily_cap'].presence || DEFAULT_DAILY_CAP).to_i
    v.clamp(10, 500)
  end
end
