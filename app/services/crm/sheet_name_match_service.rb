# 🤖 Casador de nomes da planilha de fechamento (item 154, pedido 02/09:
# "um recurso de IA pra comparar a planilha com o banco e encontrar").
#
# Recebe os nomes que NÃO casaram exato e, para cada um, monta uma lista
# curta de candidatos do próprio banco (primeiro/último nome em comum) —
# a IA só decide ENTRE os candidatos apresentados, nunca inventa id.
# Regra conservadora: só casa quando dá pra afirmar que é a MESMA pessoa
# (abreviação, nome do meio faltando, acento, ordem trocada). Na dúvida,
# não casa — paciente novo é reversível, valor no card errado não.
#
# Não tem interruptor na aba Agentes de propósito: só roda no CLIQUE
# explícito do admin na prévia da planilha (nunca sozinho, sem cron,
# sem automação) e não grava nada — devolve sugestões pra prévia.
# O gasto entra no painel "Gasto com agentes de IA" (agent_key sheet_match).
class Crm::SheetNameMatchService
  include Crm::AiAgentConfig

  AGENT_KEY = 'sheet_match'.freeze
  MAX_ROWS = 400
  MAX_CANDIDATES = 6
  BATCH_SIZE = 40

  OUTPUT_SCHEMA = {
    type: 'object',
    properties: {
      matches: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            row: { type: 'integer', description: 'número do item da lista enviada' },
            contact_id: { type: %w[integer null], description: 'id do candidato escolhido, ou null se nenhum é a mesma pessoa' },
            confianca: { type: 'string', enum: %w[alta media],
                         description: 'alta = mesma pessoa com certeza prática; media = provável, com dúvida' }
          },
          required: %w[row contact_id confianca],
          additionalProperties: false
        }
      }
    },
    required: %w[matches],
    additionalProperties: false
  }.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você compara NOMES DE PESSOAS de uma planilha da clínica com candidatos
    do cadastro, e decide se são a MESMA pessoa.

    Conte como mesma pessoa: abreviações (José C. Silva = José Carlos Silva),
    nome do meio faltando ou sobrando, acentos/caixa, apelidos óbvios
    (Zé = José, Bia = Beatriz), pequenos erros de digitação, ordem trocada.

    NÃO conte como mesma pessoa: nomes de família iguais mas primeiro nome
    diferente (irmãos!), primeiro nome igual mas sobrenome final diferente,
    qualquer caso em que possa ser um parente ou homônimo.

    Confiança: 'alta' só quando você afirmaria sem medo que é a mesma pessoa.
    'media' quando é provável mas há margem real de dúvida. Na dúvida grande,
    contact_id null. Errar criando um paciente novo é barato; casar com a
    pessoa errada põe cirurgia e valor no prontuário de outro paciente.
  PROMPT

  def initialize(account:, rows:)
    @account = account
    @rows = rows.first(MAX_ROWS)
  end

  def call # rubocop:disable Metrics/CyclomaticComplexity
    return { error: 'IA não configurada. Adicione a chave da API em CRM → Integrações → IA.' } if api_key.blank?
    return { error: 'Nenhum nome pra procurar.' } if @rows.empty?

    with_candidates = @rows.each_with_index.filter_map do |row, i|
      cands = candidates_for(row[:name])
      { index: i, row: row, candidates: cands } if cands.any?
    end
    return { matches: [], no_candidates: @rows.size } if with_candidates.empty?

    matches = []
    with_candidates.each_slice(BATCH_SIZE) do |batch|
      matches.concat(ask_ai(batch))
    end

    { matches: matches, no_candidates: @rows.size - with_candidates.size }
  rescue Anthropic::Errors::AuthenticationError
    { error: 'Chave da API inválida. Confira em CRM → Integrações → IA.' }
  rescue Anthropic::Errors::RateLimitError
    { error: 'Limite de uso da IA atingido. Tente novamente em instantes.' }
  rescue StandardError => e
    Rails.logger.error "[Crm::SheetNameMatch] #{e.class}: #{e.message}"
    { error: 'Erro ao consultar a IA. Tente novamente.' }
  end

  private

  # índice do banco: id + nome + tokens normalizados (calculado uma vez)
  def contact_index
    @contact_index ||= @account.contacts.pluck(:id, :name).filter_map do |id, name|
      tokens = tokenize(name)
      { id: id, name: name, tokens: tokens } if tokens.any?
    end
  end

  def tokenize(name)
    name.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase
        .gsub(/[^a-z\s]/, ' ').split.reject { |t| %w[de da do dos das e].include?(t) }
  end

  # lista curta de candidatos: algum parentesco de nome com a linha da
  # planilha (primeiro+último, último+inicial, 2 nomes em comum...)
  # escada de pontuação é naturalmente cheia de ramos — disable consciente
  def candidates_for(sheet_name) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    st = tokenize(sheet_name)
    return [] if st.empty?

    first = st.first
    last = st.last
    scored = contact_index.filter_map do |c|
      ct = c[:tokens]
      score =
        if ct.first == first && ct.last == last then 3
        elsif (ct.last == last && ct.first[0] == first[0]) ||
              (ct.first == first && ct.last[0] == last[0]) then 2
        elsif (ct & st).size >= 2 then 1
        end
      [score, c] if score
    end
    scored.sort_by { |(s, c)| [-s, c[:id]] }.first(MAX_CANDIDATES).map(&:last)
  end

  # chamada + validação do retorno num método só (a trava dos candidatos
  # precisa viver colada na resposta) — disable consciente
  def ask_ai(batch) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    lines = batch.map do |item|
      cands = item[:candidates].map { |c| "[#{c[:id]}] #{c[:name]}" }.join(' · ')
      "#{item[:index]}. planilha: \"#{item[:row][:name]}\" | candidatos: #{cands}"
    end

    message = client.messages.create(
      model: model,
      max_tokens: 4096,
      system_: system_prompt,
      output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
      messages: [{ role: 'user', content: lines.join("\n") }]
    )
    record_usage(message)

    text = message.content.find { |block| block.type == :text }&.text
    return [] if text.blank?

    allowed = batch.index_by { |item| item[:index] }
    Array(JSON.parse(text)['matches']).filter_map do |m|
      item = allowed[m['row'].to_i]
      next unless item && m['contact_id'].present?

      # trava: a IA só pode escolher entre os candidatos que EU apresentei
      cand = item[:candidates].find { |c| c[:id] == m['contact_id'].to_i }
      next unless cand

      {
        name: item[:row][:name],
        contact_id: cand[:id],
        contact_name: cand[:name],
        confidence: m['confianca'] == 'alta' ? 'alta' : 'media'
      }
    end
  rescue JSON::ParserError
    []
  end
end
