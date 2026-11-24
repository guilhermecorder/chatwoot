# 🧾 item 413 (24/11) — O REGISTRO PERMANENTE de quem atendeu cada conversa.
#
# Até aqui o sistema só guardava o motor, o Roteiro e o custo de uma conversa
# enquanto havia um teste A/B ligado (carimbo `cevico_ia_ab`, Crm::EngineExperiment).
# Para o COMPARATIVO DE CAIXAS ("comparar uma caixa com outra: prompt, modelo",
# Guilherme) isso precisa existir SEMPRE: toda resposta de atendente de IA soma
# num carimbo próprio da conversa, com ou sem teste.
#
# additional_attributes['cevico_ia_uso'] =
#   { 'desde' => '2026-11-24T…', 'ultima_at' => '…',
#     'chamadas' => 7, 'custo_usd' => 0.0123,
#     'modelos'  => { 'gpt-6-luna' => { 'n' => 5, 'usd' => 0.003 }, 'claude-sonnet-5' => { 'n' => 2, 'usd' => 0.0093 } },
#     'roteiros' => { 'v1' => 7 }, 'agentes' => { 'atendente_agendamento' => 7 },
#     'respostas' => 6, 'sombras' => 0, 'erros' => 1, 'reservas' => 0,
#     'agendou_at' => '…', 'humano_at' => '…' }
#
# Só SOMA e nunca decide nada: se falhar, o atendimento segue igual (rescue).
# Conversa anterior a 24/11 não tem o carimbo; a tela lê o do teste A/B quando
# houver e diz "sem registro" no resto.
module Crm::AttendanceUsage
  module_function

  STAMP = 'cevico_ia_uso'.freeze
  COUNTERS = { 'reply' => 'respostas', 'shadow' => 'sombras', 'error' => 'erros', 'fallback' => 'reservas' }.freeze

  # event (tudo opcional): 'model', 'cost_usd' (uma CHAMADA ao motor), 'script',
  # 'reply', 'shadow', 'error', 'fallback', 'booked', 'handoff'
  def track!(conversation, agent_key, event = {}) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return if conversation.nil? || event.blank?

    now = Time.current.iso8601
    Cevico::AttributeMerge.merge!(conversation) do |attrs|
      row = attrs[STAMP].is_a?(Hash) ? attrs[STAMP].deep_dup : { 'desde' => now }
      bump_call(row, agent_key, event) if event['model'].present?
      COUNTERS.each { |flag, counter| row[counter] = row[counter].to_i + 1 if event[flag] }
      row['agendou_at'] ||= now if event['booked']
      row['humano_at'] ||= now if event['handoff']
      row['ultima_at'] = now
      attrs.merge(STAMP => row)
    end
  rescue StandardError => e
    Rails.logger.warn "[Crm::AttendanceUsage] carimbo: #{e.class}: #{e.message}"
  end

  def bump_call(row, agent_key, event) # rubocop:disable Metrics/AbcSize
    cost = event['cost_usd'].to_f
    row['chamadas'] = row['chamadas'].to_i + 1
    row['custo_usd'] = (row['custo_usd'].to_f + cost).round(6)
    models = row['modelos'].is_a?(Hash) ? row['modelos'] : {}
    mine = models[event['model'].to_s].is_a?(Hash) ? models[event['model'].to_s] : {}
    row['modelos'] = models.merge(event['model'].to_s => { 'n' => mine['n'].to_i + 1, 'usd' => (mine['usd'].to_f + cost).round(6) })
    { 'roteiros' => event['script'], 'agentes' => agent_key }.each do |key, value|
      next if value.blank?

      tally = row[key].is_a?(Hash) ? row[key] : {}
      row[key] = tally.merge(value.to_s => tally[value.to_s].to_i + 1)
    end
  end

  # ── LEITURA (o Comparativo de caixas) ───────────────────────────────────
  # O que a conversa guarda, num formato só, venha do carimbo permanente ou,
  # nas conversas antigas, do carimbo do teste A/B. nil = sem registro.
  def read(attrs) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    attrs = {} unless attrs.is_a?(Hash)
    row = attrs[STAMP]
    if row.is_a?(Hash)
      return { custo_usd: row['custo_usd'].to_f, respostas: row['respostas'].to_i, chamadas: row['chamadas'].to_i,
               modelos: hash_of(row['modelos']).transform_values { |v| v.is_a?(Hash) ? v['n'].to_i : v.to_i },
               roteiros: hash_of(row['roteiros']).transform_values(&:to_i),
               agendou: row['agendou_at'].present?, humano: row['humano_at'].present? }
    end

    legacy = hash_of(attrs[Crm::EngineExperiment::STAMP]).values.select { |v| v.is_a?(Hash) }
    return nil if legacy.empty?

    { custo_usd: legacy.sum { |v| v['custo_usd'].to_f }, respostas: legacy.sum { |v| v['respostas'].to_i },
      chamadas: legacy.sum { |v| v['respostas'].to_i + v['sombras'].to_i },
      modelos: legacy.filter_map { |v| v['model'].presence }.tally,
      roteiros: legacy.filter_map { |v| v['script'].presence }.tally,
      agendou: legacy.any? { |v| v['agendou_at'].present? }, humano: legacy.any? { |v| v['humano_at'].present? } }
  end

  def hash_of(value)
    value.is_a?(Hash) ? value : {}
  end
end
