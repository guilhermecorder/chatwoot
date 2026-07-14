# Lê as respostas de um formulário e sintetiza os INSIGHTS DE MARKETING:
# dores, desejos, objeções e recomendações — o "entender melhor nosso
# público" do dashboard de formulários. Usa a mesma config de IA das
# Integrações (CRM → Integrações → IA).
class Crm::FormInsightService
  include Crm::AiAgentConfig

  AGENT_KEY = 'form'.freeze
  MAX_RESPONSES = 300

  OUTPUT_SCHEMA = {
    type: 'object',
    properties: {
      resumo: { type: 'string', description: 'Visão geral do público em 1 parágrafo' },
      dores: { type: 'array', items: { type: 'string' }, description: 'Principais dores citadas, da mais para a menos frequente' },
      desejos: { type: 'array', items: { type: 'string' }, description: 'Principais desejos e motivações' },
      objecoes: { type: 'array', items: { type: 'string' }, description: 'Objeções e medos que travam a decisão' },
      recomendacoes: { type: 'array', items: { type: 'string' }, description: 'Recomendações práticas de marketing e atendimento com base nos padrões' }
    },
    required: %w[resumo dores desejos objecoes recomendacoes],
    additionalProperties: false
  }.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é analista de marketing da CEVICO, clínica oftalmológica (cirurgia
    refrativa, catarata, ceratocone, lentes fácicas). Vai receber as respostas
    de um formulário respondido por pacientes.

    Sua missão: extrair padrões ÚTEIS para marketing e atendimento.
    - Dores: o que incomoda na vida com óculos/lentes ou com a condição
    - Desejos: o que os motiva (estética, esporte, praticidade, trabalho...)
    - Objeções: medos e travas (preço, medo de cirurgia, desconfiança...)
    - Recomendações: ângulos de anúncio, argumentos para as atendentes,
      ajustes de comunicação — concretos, baseados no que apareceu

    Cite frequências quando notar padrão ("7 de 20 mencionaram medo da
    cirurgia"). Escreva em português do Brasil, direto, sem enrolação.
  PROMPT

  def initialize(form:, responses:)
    @form = form
    @account = form.account
    @responses = responses.first(MAX_RESPONSES)
  end

  def call
    return { error: 'IA não configurada. Adicione a chave da API em Integrações → Claude.' } if api_key.blank?
    return { error: 'O Analista de Formulários está pausado. Reative em Automações → Agentes de IA.' } if agent_paused?
    return { error: 'Ainda não há respostas para analisar.' } if @responses.empty?

    message = client.messages.create(
      model: model,
      max_tokens: 2048,
      system_: system_prompt,
      output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
      messages: [{ role: 'user', content: build_corpus }]
    )
    record_usage(message)

    text = message.content.find { |block| block.type == :text }&.text
    return { error: 'A IA não retornou análise.' } if text.blank?

    JSON.parse(text).merge(
      'responses_analyzed' => @responses.size,
      'model' => model,
      'generated_at' => Time.current.iso8601
    ).symbolize_keys
  rescue Anthropic::Errors::AuthenticationError
    { error: 'Chave da API inválida. Confira em CRM → Integrações → IA.' }
  rescue Anthropic::Errors::RateLimitError
    { error: 'Limite de uso da IA atingido. Tente novamente em instantes.' }
  rescue StandardError => e
    Rails.logger.error "[Crm::FormInsight] #{e.class}: #{e.message}"
    { error: 'Erro ao gerar insights. Tente novamente.' }
  end

  private

  # formulários podem ter centenas de respostas — timeout maior
  def client
    @client ||= Anthropic::Client.new(api_key: api_key, timeout: 120)
  end

  def build_corpus
    lines = ["Formulário: #{@form.name} — #{@responses.size} respostas\n"]
    @responses.each_with_index do |r, i|
      lines << "--- Resposta #{i + 1} ---"
      r.answers.each do |a|
        value = a['value'].is_a?(Array) ? a['value'].join(', ') : a['value'].to_s
        next if value.blank?

        lines << "#{a['label']}: #{value.truncate(500)}"
      end
    end
    lines.join("\n")
  end
end
