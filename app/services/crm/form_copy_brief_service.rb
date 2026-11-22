# 🪝 item 397 (18/11): "PUXAR O QUE IMPORTA" de um formulário para a COPY.
# Guilherme: "quando tiver resultado de formulário, que ele puxe as
# informações mais importantes, mais chave, para eu decidir como construir
# a copy, a narrativa — um botão de entender, de puxar, de importar".
#
# Diferente do Analista de Formulários (resumo de marketing), esta leitura
# é feita PARA ESCREVER: frases literais do público, as palavras que ele
# usa, dores/desejos/objeções com frequência e ÂNGULOS de narrativa já
# casados com um tipo de gancho do Banco de Ganchos. Os NÚMEROS das
# perguntas fechadas são contados aqui no Ruby (a IA não inventa número).
# Fica salvo em crm_forms.ai_insight['copy'] (sem migration).
class Crm::FormCopyBriefService
  include Crm::AiAgentConfig

  AGENT_KEY = 'form'.freeze # Analista de Formulários (mesmo liga/desliga)
  MAX_RESPONSES = 300
  TIPOS = (CevicoCopyBlock::GANCHO_CATEGORIAS.keys - ['cevico']).freeze

  ITEM = {
    type: 'object', additionalProperties: false, required: %w[texto frequencia],
    properties: { texto: { type: 'string' }, frequencia: { type: 'string' } }
  }.freeze

  OUTPUT_SCHEMA = {
    type: 'object', additionalProperties: false,
    required: %w[publico dores desejos objecoes frases palavras angulos],
    properties: {
      publico: { type: 'string' },
      dores: { type: 'array', items: ITEM },
      desejos: { type: 'array', items: ITEM },
      objecoes: { type: 'array', items: ITEM },
      frases: { type: 'array', items: { type: 'string' } },
      palavras: { type: 'array', items: { type: 'string' } },
      angulos: {
        type: 'array',
        items: {
          type: 'object', additionalProperties: false,
          required: %w[titulo porque tipo_gancho gancho_exemplo],
          properties: {
            titulo: { type: 'string' }, porque: { type: 'string' },
            tipo_gancho: { type: 'string', enum: TIPOS }, gancho_exemplo: { type: 'string' }
          }
        }
      }
    }
  }.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o estrategista de copy da empresa. Recebe as respostas de um
    formulário e entrega o que um redator precisa para escrever: quem é o
    público, as dores, os desejos e as objeções (do mais ao menos frequente,
    com a frequência no formato "7 de 20"), as FRASES LITERAIS mais fortes
    (copiadas exatamente como a pessoa escreveu, até 12, sem nome nem dado
    pessoal), as PALAVRAS que o público usa (vocabulário dele, até 15) e de
    3 a 5 ÂNGULOS de narrativa. Cada ângulo: título curto, por que funciona
    (apoiado no que apareceu nas respostas), o tipo de gancho que combina
    (educativo, comparacao, quebra_de_mito, storytelling, aleatorio,
    autoridade, dia_na_vida) e um gancho de exemplo.
    Use só o que está nas respostas; não invente número nem depoimento.
    Se a empresa for de saúde, nada de promessa de resultado. Português do
    Brasil, direto. Responda só no formato estruturado pedido.
  PROMPT

  def initialize(form:)
    @form = form
    @account = form.account
    @responses = form.responses.where.not(completed_at: nil).order(created_at: :desc).limit(MAX_RESPONSES).to_a
  end

  def call
    return { error: 'IA não configurada. Adicione a chave da API em Integrações → Claude.' } if api_key.blank?
    return { error: 'O Analista de Formulários está pausado. Reative em Automações → Agentes de IA.' } if agent_paused?
    return { error: 'Este formulário ainda não tem respostas.' } if @responses.empty?

    message = client.messages.create(
      # 12k: o esforço de raciocínio divide o mesmo teto (4096 cortava o JSON — teste 18/11)
      model: model, max_tokens: 12_000, system_: cached_system,
      output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
      messages: [{ role: 'user', content: corpus }]
    )
    record_usage(message)
    result = parse_structured_response(message)
    return result if result[:error]

    result.merge('numeros' => numeros, 'respostas' => @responses.size, 'generated_at' => Time.current.iso8601)
  rescue Anthropic::Errors::APIError => e
    { error: "Erro na IA: #{e.message}" }
  rescue StandardError => e
    Rails.logger.error "[Crm::FormCopyBrief] #{e.class}: #{e.message}"
    { error: 'Não consegui ler o formulário agora. Tente de novo.' }
  end

  FECHADAS = %w[choice multi yesno scale].freeze

  # perguntas fechadas: as 3 respostas mais escolhidas, com a porcentagem
  def numeros
    @numeros ||= @form.questions.select { |q| FECHADAS.include?(q['type']) }.filter_map { |q| numero(q) }
  end

  private

  def client
    @client ||= Anthropic::Client.new(api_key: api_key, timeout: 180)
  end

  def resposta(resp, question_id)
    resp.answers.find { |a| a['id'] == question_id }&.dig('value')
  end

  def numero(question)
    values = @responses.flat_map { |r| Array(resposta(r, question['id'])) }.map(&:to_s).compact_blank
    return nil if values.empty?

    quem = @responses.count { |r| resposta(r, question['id']).present? }
    top = values.tally.sort_by { |_, c| -c }.first(3).map do |v, c|
      { 'opcao' => v, 'pessoas' => c, 'pct' => (c * 100.0 / quem).round }
    end
    { 'pergunta' => question['label'], 'responderam' => quem, 'top' => top }
  end

  def system_prompt
    "#{SYSTEM_PROMPT}\n#{cevico_company.prompt_context}#{OPERATIONAL_GUARDRAIL}"
  end

  def corpus
    lines = ["Formulário: #{@form.name} — #{@responses.size} respostas", '', 'NÚMEROS (contados pelo sistema):']
    numeros.each do |n|
      lines << "- #{n['pergunta']}: #{n['top'].map { |t| "#{t['opcao']} #{t['pct']}%" }.join(' · ')} (#{n['responderam']} responderam)"
    end
    lines << ''
    @responses.each_with_index { |r, i| lines.concat(linhas_da_resposta(r, i)) }
    lines.join("\n")
  end

  def linhas_da_resposta(resp, index)
    ["--- Resposta #{index + 1} ---"] + resp.answer_items.filter_map do |a|
      value = a['value'].is_a?(Array) ? a['value'].join(', ') : a['value'].to_s
      "#{a['label']}: #{value.truncate(500)}" if value.present?
    end
  end
end
