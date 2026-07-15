# Agente de NPS: lê a conversa (pós-operatório) e identifica a NOTA de
# satisfação que o paciente deu (0 a 10). Etiqueta o contato com a faixa
# (nps-9-10 / nps-7-8 / nps-0-6) e grava a nota no contato — o Dashboard CRM
# mostra a % de satisfação a partir dessas etiquetas.
class Crm::NpsService
  include Crm::AiAgentConfig

  AGENT_KEY = 'nps'.freeze
  MAX_MESSAGES = 40
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  OUTPUT_SCHEMA = {
    type: 'object',
    properties: {
      respondeu: {
        type: 'boolean',
        description: 'true somente se o paciente deu uma NOTA de satisfação (0 a 10) na conversa'
      },
      nota: {
        type: 'integer',
        description: 'A nota que o paciente deu, de 0 a 10. -1 se não respondeu.'
      },
      comentario: {
        type: 'string',
        description: 'Resumo em 1 frase do que o paciente disse sobre a experiência (elogio ou reclamação). Vazio se não comentou.'
      }
    },
    required: %w[respondeu nota comentario],
    additionalProperties: false
  }.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o AGENTE DE NPS interno da CEVICO, clínica oftalmológica. Sua
    única função é ler a conversa de pós-atendimento/pós-operatório e
    identificar a NOTA DE SATISFAÇÃO (0 a 10) que o PACIENTE deu quando a
    clínica perguntou "de 0 a 10, quanto você recomendaria...". Você nunca
    fala com o paciente e nunca inventa nota.

    REGRAS:
    - respondeu=true SOMENTE se o paciente escreveu uma nota numérica de 0 a
      10 ("10!", "dou nota 9", "uns 8"). Elogio sem número ("adorei",
      "excelente") NÃO vale como nota — nesse caso respondeu=false.
    - Cuidado para não confundir: números que são horário, valor, idade ou
      quantidade NÃO são nota de NPS. Considere nota apenas quando o
      contexto é avaliação da experiência.
    - Se o paciente deu mais de uma nota, use a MAIS RECENTE.
    - comentario: resuma em 1 frase o motivo/percepção do paciente (elogio à
      equipe, demora, resultado da cirurgia, atendimento do médico). Vazio
      se ele só mandou o número. Não invente sentimentos.
  PROMPT

  # faixa da nota → etiqueta aplicada no contato (5 faixas oficiais):
  # 9-10 promotores · 7-8 · 5-6 · 3-4 · 1-2 detratores (0 entra em 1-2)
  def self.label_for(score)
    return 'nps-9-10' if score >= 9
    return 'nps-7-8' if score >= 7
    return 'nps-5-6' if score >= 5
    return 'nps-3-4' if score >= 3

    'nps-1-2'
  end

  NPS_LABELS = %w[nps-9-10 nps-7-8 nps-5-6 nps-3-4 nps-1-2].freeze

  def initialize(conversation:)
    @conversation = conversation
    @account = conversation.account
  end

  def call
    return { error: 'IA não configurada. Adicione a chave da API em Integrações → Claude.' } if api_key.blank?
    return { error: 'O agente de NPS está pausado. Reative em Automações → Agentes de IA.' } if agent_paused?

    transcript = build_transcript
    return { error: 'Conversa sem mensagens para analisar.' } if transcript.blank?

    message = client.messages.create(
      model: model,
      max_tokens: 512,
      system_: system_prompt,
      output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
      messages: [{ role: 'user', content: transcript }]
    )
    record_usage(message)

    text = message.content.find { |block| block.type == :text }&.text
    return { error: 'A IA não retornou a leitura do NPS.' } if text.blank?

    parsed = JSON.parse(text)
    score = parsed['nota'].to_i
    {
      answered: parsed['respondeu'] == true && score.between?(0, 10),
      score: score,
      comment: parsed['comentario'].to_s.strip,
      model: model
    }
  rescue Anthropic::Errors::AuthenticationError
    { error: 'Chave da API inválida. Confira em CRM → Integrações → IA.' }
  rescue Anthropic::Errors::RateLimitError
    { error: 'Limite de uso da IA atingido. Tente novamente em instantes.' }
  rescue StandardError => e
    Rails.logger.error "[Crm::Nps] #{e.class}: #{e.message}"
    { error: 'Erro na leitura do NPS.' }
  end

  private

  def build_transcript
    messages = @conversation.messages
                            .where(message_type: [:incoming, :outgoing])
                            .where(private: false)
                            .where.not(content: [nil, ''])
                            .order(created_at: :desc)
                            .limit(MAX_MESSAGES)
                            .reverse

    return nil if messages.empty?

    lines = messages.map do |m|
      author = m.incoming? ? 'PACIENTE' : 'CLÍNICA'
      "#{author}: #{m.content.to_s.strip.truncate(400)}"
    end

    "Identifique a nota de satisfação (0-10) que o paciente deu nesta conversa:\n\n" + lines.join("\n")
  end
end
