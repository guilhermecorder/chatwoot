# Consultor Comercial (agente de fechamento em DOIS papéis):
# 1) AJUDA AO VIVO: enquanto a vendedora atende, lê a conversa, identifica a
#    OBJEÇÃO do paciente e sugere 2-3 respostas prontas no tom CEVICO
#    (botão "💼 Ajuda com objeção" no painel da conversa).
# 2) INSIGHTS COMERCIAIS: analisa as conversas que geraram FECHAMENTO de
#    cirurgia e devolve padrões do que funciona (para a gestão) — botão no
#    card do agente em Automações → Agentes de IA.
# Como todo agente interno: NUNCA fala com o paciente; quem decide e envia
# é sempre a humana.
class Crm::SalesCoachService
  include Crm::AiAgentConfig

  AGENT_KEY = 'sales'.freeze
  MAX_MESSAGES = 60
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  COACH_SCHEMA = {
    type: 'object',
    properties: {
      objecao: {
        type: 'string',
        enum: %w[preco medo_cirurgia vou_pensar conversar_familia sem_tempo confianca distancia concorrencia sem_objecao outra],
        description: 'A objeção principal do paciente NESTE momento da conversa'
      },
      leitura: {
        type: 'string',
        description: 'Leitura em 1-2 frases do que está travando o paciente e do que ele valoriza'
      },
      respostas: {
        type: 'array',
        items: { type: 'string' },
        description: '2 a 3 respostas prontas (≤150 caracteres cada, tom CEVICO) para a vendedora escolher e enviar'
      },
      proximo_passo: {
        type: 'string',
        description: 'A ação que a vendedora deve buscar em seguida (ex.: convidar para reservar a data da cirurgia)'
      }
    },
    required: %w[objecao leitura respostas proximo_passo],
    additionalProperties: false
  }.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o CONSULTOR COMERCIAL interno da CEVICO, clínica oftalmológica
    premium com duas unidades em São Paulo (Av. Paulista e Tatuapé). Sua
    função é ajudar a VENDEDORA a conduzir o fechamento de cirurgias — você
    NUNCA fala com o paciente; quem decide e envia é sempre ela.

    CONTEXTO COMERCIAL DA CEVICO:
    - Procedimentos: cirurgia refrativa (PRK/Lasik), lentes fácicas (Artisan),
      catarata (lentes trifocais/foco estendido), ceratocone (anel), pterígio.
    - Cirurgias em clínicas parceiras: IOP (geralmente PRK) e Ocular Surgery
      (geralmente Lasik). Tecnologia de ponta: excimer laser Schwind Amaris.
    - Fale "INVESTIMENTO", nunca "preço/custo". Parcelamento é comum
      (cartão em até 10x, PIX à vista, boleto).
    - Autoridade: corpo clínico experiente, milhares de cirurgias realizadas,
      avaliação criteriosa antes de qualquer indicação.

    TOM DAS RESPOSTAS SUGERIDAS (regras invioláveis):
    - Máximo 150 caracteres por resposta, português natural de WhatsApp.
    - SEM emojis, SEM travessão, SEM listas, SEM markdown.
    - Consultivo e empático: valide a preocupação ANTES de responder.
    - Termine com pergunta leve que puxa o próximo passo quando fizer sentido.
    - Nunca invente valores, prazos ou promessas médicas; não dê desconto
      por conta própria — se o paciente pedir, sugira envolver a gestão.
    - Medo de cirurgia: acolha, cite a avaliação criteriosa e a experiência
      do corpo clínico; nunca minimize ("é rapidinho") nem garanta resultado.

    OBJEÇÕES E CAMINHOS:
    - preco → quebre em parcelas, foque no valor de enxergar bem todos os
      dias, ofereça condições sem inventar números.
    - vou_pensar / conversar_familia → valide, pergunte o que falta para
      decidir, ofereça reservar a data sem compromisso.
    - medo_cirurgia → acolhimento + autoridade + convite para tirar dúvidas
      com o médico.
    - sem_tempo → mostre que o processo é organizado pela clínica.
    - concorrencia → não fale mal de ninguém; reforce diferenciais CEVICO.
  PROMPT

  INSIGHTS_PROMPT = <<~PROMPT.freeze
    Você é o CONSULTOR COMERCIAL interno da CEVICO (clínica oftalmológica).
    Vai receber TRECHOS de várias conversas de WhatsApp que TERMINARAM EM
    FECHAMENTO de cirurgia. Analise o conjunto e produza um relatório
    comercial curto para a GESTÃO, em português, com estas seções:

    ## O que está funcionando
    (padrões concretos de condução que aparecem nas conversas fechadas:
    frases, momentos de conversão, gatilhos)

    ## Objeções mais comuns e como foram vencidas
    (objeção → resposta que funcionou, citando exemplos reais resumidos)

    ## Oportunidades de melhoria
    (o que teria acelerado fechamentos: follow-up, clareza de valores,
    momentos em que quase se perdeu a venda)

    ## Recomendações práticas
    (3 a 5 ações objetivas para a equipe aplicar já)

    Regras: seja específico e baseado SOMENTE no que está nas conversas;
    não invente números; proteja os pacientes citando só primeiro nome.
  PROMPT

  def initialize(conversation: nil, account: nil)
    @conversation = conversation
    @account = account || conversation&.account
  end

  # ── 1. ajuda ao vivo (objeção da conversa atual) ──
  def coach
    return { error: 'IA não configurada. Adicione a chave da API em Integrações → Claude.' } if api_key.blank?
    return { error: 'O Consultor Comercial está pausado. Reative em Automações → Agentes de IA.' } if agent_paused?

    transcript = build_transcript(@conversation)
    return { error: 'Conversa sem mensagens para analisar.' } if transcript.blank?

    message = client.messages.create(
      model: model,
      max_tokens: 1024,
      system_: system_prompt,
      output_config: output_config_for({ type: 'json_schema', schema: COACH_SCHEMA }),
      messages: [{ role: 'user', content: "Identifique a objeção e sugira respostas para a vendedora:\n\n#{transcript}" }]
    )
    record_usage(message)

    text = message.content.find { |block| block.type == :text }&.text
    return { error: 'A IA não retornou a ajuda.' } if text.blank?

    parsed = JSON.parse(text)
    {
      objection: parsed['objecao'],
      reading: parsed['leitura'].to_s.strip,
      replies: Array(parsed['respostas']).map(&:to_s).first(3),
      next_step: parsed['proximo_passo'].to_s.strip,
      model: model
    }
  rescue Anthropic::Errors::AuthenticationError
    { error: 'Chave da API inválida. Confira em CRM → Integrações → IA.' }
  rescue Anthropic::Errors::RateLimitError
    { error: 'Limite de uso da IA atingido. Tente novamente em instantes.' }
  rescue StandardError => e
    Rails.logger.error "[Crm::SalesCoach] #{e.class}: #{e.message}"
    { error: 'Erro na ajuda comercial.' }
  end

  # ── 2. insights comerciais das conversas FECHADAS (para a gestão) ──
  def insights(limit: 15)
    return { error: 'IA não configurada.' } if api_key.blank?
    return { error: 'O Consultor Comercial está pausado.' } if agent_paused?

    convs = closed_conversations(limit)
    return { error: 'Nenhuma conversa com fechamento encontrada ainda (o Monitor de Fechamento alimenta esta análise).' } if convs.empty?

    corpus = convs.map { |c| "=== CONVERSA (#{c.contact&.name&.split&.first || 'paciente'}) ===\n#{build_transcript(c, max: 30)}" }.join("\n\n")

    message = client.messages.create(
      model: model,
      max_tokens: 3000,
      system_: custom_prompt.presence || Segmento.prompt('sales_coach_insights') || INSIGHTS_PROMPT,
      messages: [{ role: 'user', content: "Analise estas #{convs.size} conversas que geraram fechamento de cirurgia:\n\n#{corpus.truncate(120_000)}" }]
    )
    record_usage(message)

    text = message.content.find { |block| block.type == :text }&.text
    return { error: 'A IA não retornou os insights.' } if text.blank?

    { text: text, conversations: convs.size, generated_at: Time.current.iso8601, model: model }
  rescue StandardError => e
    Rails.logger.error "[Crm::SalesCoach insights] #{e.class}: #{e.message}"
    { error: 'Erro ao gerar os insights comerciais.' }
  end

  private

  # conversas de contatos com fechamento registrado (surgery_closing do
  # Monitor de Fechamento), das mais recentes para trás
  def closed_conversations(limit)
    contacts = @account.contacts
                       .where("additional_attributes -> 'surgery_closing' IS NOT NULL")
                       .order(updated_at: :desc)
                       .limit(limit)
    contacts.filter_map { |c| c.conversations.order(Arel.sql('last_activity_at DESC NULLS LAST, created_at DESC')).first }
  end

  def build_transcript(conversation, max: MAX_MESSAGES)
    return nil if conversation.blank?

    # reorder: o default_scope do Message (created_at ASC) vence um .order
    # comum, então pegava as N mensagens mais ANTIGAS e a IA nunca via as novas
    messages = conversation.messages
                           .where(message_type: [:incoming, :outgoing])
                           .where(private: false)
                           .where.not(content: [nil, ''])
                           .reorder(created_at: :desc)
                           .limit(max)
                           .reverse
    return nil if messages.empty?

    messages.map do |m|
      author = m.incoming? ? 'PACIENTE' : 'CLÍNICA'
      "#{author}: #{m.content.to_s.strip.truncate(400)}"
    end.join("\n")
  end

  def custom_prompt
    cfg = CrmSetting.find_by(account: @account)&.ai_config || {}
    cfg.dig('agents', AGENT_KEY, 'prompt')
  end
end
