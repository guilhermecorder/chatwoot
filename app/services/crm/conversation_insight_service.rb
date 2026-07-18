# Analisa a conversa com a Claude e devolve o indicador de interesse do
# paciente + um parágrafo de observações para a atendente. Usado pelo card
# de resumo no painel da conversa (botão "Analisar com IA").
#
# Config em CRM → Integrações → IA: api_key (Anthropic) e modelo (padrão
# claude-opus-4-8 — pode trocar por claude-haiku-4-5 para reduzir custo).
class Crm::ConversationInsightService
  include Crm::AiAgentConfig

  AGENT_KEY = 'conversation'.freeze
  MAX_MESSAGES = 60
  DEFAULT_MODEL = Crm::AiAgentConfig::DEFAULT_MODEL

  OUTPUT_SCHEMA = {
    type: 'object',
    properties: {
      interesse: {
        type: 'string',
        enum: %w[alto medio baixo perdido],
        description: 'Nível de interesse do paciente em fechar consulta/cirurgia'
      },
      resumo: {
        type: 'string',
        description: 'Um parágrafo (3-5 frases) com a análise da conversa: o que o paciente quer, objeções, responsividade e momento da jornada'
      },
      proximo_passo: {
        type: 'string',
        description: 'Sugestão curta e prática do próximo passo para a atendente (1 frase)'
      },
      etapa_do_script: {
        type: 'string',
        enum: %w[recepcao sondagem autoridade orcamento objecoes agendamento
                 pos_agendamento pos_consulta pos_cirurgico reagendamento],
        description: 'Etapa do script de atendimento CEVICO em que a conversa está'
      },
      frases_sugeridas: {
        type: 'array',
        # a API de structured outputs só aceita minItems 0 ou 1 — a
        # quantidade (2 a 3) é garantida pela description + prompt
        minItems: 1,
        items: { type: 'string' },
        description: 'EXATAMENTE 2 a 3 frases prontas, no tom do script CEVICO, para a atendente enviar agora'
      }
    },
    required: %w[interesse resumo proximo_passo etapa_do_script frases_sugeridas],
    additionalProperties: false
  }.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você analisa conversas de atendimento da CEVICO, uma clínica oftalmológica
    (cirurgias refrativas, catarata, ceratocone, lentes fácicas). Sua análise é
    lida pela atendente para decidir como conduzir o paciente.

    Avalie o nível de interesse do paciente:
    - alto: engajado, pergunta valores/datas, quer agendar ou avançar
    - medio: interessado mas com objeções (preço, medo, tempo) ou respondendo devagar
    - baixo: respostas curtas/frias, adiando, sem sinal de avanço
    - perdido: disse que não quer, fechou com concorrente ou parou de responder há muito tempo

    No resumo, seja concreto: o que a pessoa procura, objeções levantadas,
    como está a responsividade e em que ponto da jornada ela está.
    Escreva em português do Brasil, direto e sem jargão.

    ETAPA DO SCRIPT (etapa_do_script) — o atendimento CEVICO segue um script;
    identifique onde a conversa está:
    - recepcao: primeiro contato, ainda sem saber para quem é o atendimento
    - sondagem: descobrindo o procedimento desejado e quando quer resolver
    - autoridade: hora de apresentar médicos, clínica (IOP), unidades e equipamento
    - orcamento: hora de enviar (ou acabou de enviar) os valores e perguntar
      se o investimento é possível
    - objecoes: paciente com dúvidas ou objeções (valor, medo, família,
      convênio, pesquisar mais) que precisam ser acolhidas
    - agendamento: investimento confirmado — coletar nome completo, telefone,
      dia, turno e unidade (Av. Paulista ou Tatuapé)
    - pos_agendamento: consulta já confirmada — só responder dúvidas, sem
      fazer novas perguntas nem reabrir a venda
    - pos_consulta: já passou com o médico — aguarda indicação da cirurgia
    - pos_cirurgico: já operou — acolher e, se houver problema, encaminhar
      ao pós-operatório
    - reagendamento: quer remarcar — reconduzir para novo dia/turno/unidade

    FRASES SUGERIDAS (frases_sugeridas): escreva 2 a 3 frases PRONTAS para a
    ATENDENTE enviar em seguida, adequadas à etapa e ao momento exato da
    conversa, no tom do script CEVICO:
    - curtas e diretas (até ~150 caracteres cada), tratando o paciente por "você"
    - SEM emoji, SEM travessão (—), SEM listas
    - nunca usar "preço", "custo", "caro", "barato", "desconto", "pagar" —
      falar em "investimento" e "valor"; NUNCA oferecer desconto
    - consultivo, sem pressão: acolher primeiro, agendar depois; na maioria
      dos casos terminar com uma pergunta que mantém o diálogo aberto
    - não repetir pergunta que o paciente já respondeu; não insistir no
      agendamento se ele já foi convidado duas vezes

    Dados oficiais da CEVICO para usar nas frases (nunca invente outros):
    - Consulta de avaliação: R$ 150 com exames inclusos (biometria,
      microscopia, fundo de olho e pentacam); avaliação de glaucoma R$ 300
    - Refrativa (dois olhos): PRK R$ 4.900, Lasik R$ 5.700 — a técnica é
      definida pelo médico com base nos exames
    - Catarata (por olho): R$ 2.800 lente nacional, R$ 3.200 Rayner
      importada, R$ 5.690 Rayner de foco estendido
    - Pagamento: à vista no PIX ou em até 10x sem juros no cartão; não
      atendemos convênio nem reembolso
    - Médicos: Dr. Henrique Gemelli, Dra. Roberta Negri e Dr. Gustavo Bittar
      (refrativa: Dr. Gustavo Bittar, especialista em córnea); a cirurgia de
      catarata é do Dr. Jorge Haddad (mais de 30.000 cirurgias)
    - Equipamento de refrativa: Schwind Amaris 1050RS, considerado o padrão
      ouro mundial
    - Unidades: Av. Paulista, 1499, 9º andar (metrô Trianon-MASP) e Tatuapé,
      R. Serra de Botucatu, 880, 4º andar (estação Carrão)
    - Consultas: segunda a quinta na Av. Paulista; quarta e sexta no Tatuapé;
      sábado e domingo não há agenda
    - Pós-operatório e casos específicos: encaminhar para a Vaneide,
      (11) 98769-0286
  PROMPT

  def initialize(conversation:)
    @conversation = conversation
    @account = conversation.account
  end

  def call
    return { error: 'IA não configurada. Adicione a chave da API em Integrações → Claude.' } if api_key.blank?
    return { error: 'O Analista de Conversas está pausado. Reative em Automações → Agentes de IA.' } if agent_paused?

    transcript = build_transcript
    return { error: 'Conversa sem mensagens para analisar.' } if transcript.blank?

    message = client.messages.create(
      model: model,
      max_tokens: 2048,
      system_: system_prompt,
      output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
      messages: [{ role: 'user', content: transcript }]
    )
    record_usage(message)

    text = message.content.find { |block| block.type == :text }&.text
    return { error: 'A IA não retornou análise.' } if text.blank?

    parsed = JSON.parse(text)
    {
      level: parsed['interesse'],
      summary: parsed['resumo'],
      next_step: parsed['proximo_passo'],
      script_stage: parsed['etapa_do_script'],
      suggested_phrases: Array(parsed['frases_sugeridas']).first(3),
      model: model,
      analyzed_at: Time.current.iso8601
    }
  rescue Anthropic::Errors::AuthenticationError
    { error: 'Chave da API inválida. Confira em CRM → Integrações → IA.' }
  rescue Anthropic::Errors::RateLimitError
    { error: 'Limite de uso da IA atingido. Tente novamente em instantes.' }
  rescue Anthropic::Errors::APIStatusError => e
    Rails.logger.error "[Crm::ConversationInsight] API #{e.class}: #{e.message}"
    { error: 'Erro na análise de IA. Tente novamente.' }
  rescue StandardError => e
    Rails.logger.error "[Crm::ConversationInsight] #{e.class}: #{e.message}"
    { error: 'Erro na análise de IA. Tente novamente.' }
  end

  private

  # transcript legível: só mensagens reais (paciente/atendente), da mais
  # antiga pra mais nova, limitado às últimas MAX_MESSAGES
  def build_transcript
    # reorder: o default_scope do Message (created_at ASC) vence um .order
    # comum, então pegava as N mensagens mais ANTIGAS e a IA nunca via as novas
    messages = @conversation.messages
                            .where(message_type: [:incoming, :outgoing])
                            .where(private: false)
                            .where.not(content: [nil, ''])
                            .reorder(created_at: :desc)
                            .limit(MAX_MESSAGES)
                            .reverse

    return nil if messages.empty?

    lines = messages.map do |m|
      author = m.incoming? ? 'PACIENTE' : 'CLÍNICA'
      "[#{m.created_at.strftime('%d/%m %H:%M')}] #{author}: #{m.content.to_s.strip.truncate(600)}"
    end

    header = "Conversa com #{@conversation.contact&.name || 'paciente'} " \
             "(iniciada em #{@conversation.created_at.strftime('%d/%m/%Y')}, " \
             "hoje é #{Date.current.strftime('%d/%m/%Y')}):\n\n"
    header + lines.join("\n")
  end
end
