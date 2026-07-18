# Monitor de Fechamento: lê a conversa quando o card entra na coluna (ação
# "Adicionar agente de IA" → Monitor de Fechamento) e extrai o FECHAMENTO da
# cirurgia: valor fechado, forma de pagamento e data. Grava no contato
# (additional_attributes.surgery_closing) e preenche o valor do card no CRM
# se ainda estiver vazio. O valor aparece (SÓ para admin) na Agenda de
# Cirurgias, na conferência do dia.
class Crm::SurgeryClosingService
  include Crm::AiAgentConfig

  AGENT_KEY = 'closing'.freeze
  MAX_MESSAGES = 60
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  OUTPUT_SCHEMA = {
    type: 'object',
    properties: {
      fechado: {
        type: 'boolean',
        description: 'true somente se a conversa mostra cirurgia FECHADA (valor combinado e aceito pelo paciente)'
      },
      valor: {
        type: 'number',
        description: 'Valor TOTAL fechado da cirurgia em reais, só números (ex.: 5000). 0 se não ficou claro.'
      },
      forma_pagamento: {
        type: 'string',
        description: 'Forma de pagamento combinada, curta: "PIX à vista", "cartão 10x", "boleto + cartão"... Vazio se não mencionada.'
      },
      data_cirurgia: {
        type: 'string',
        description: 'Data da cirurgia no formato YYYY-MM-DD, se combinada na conversa. Vazio se não confirmada.'
      },
      observacao: {
        type: 'string',
        description: 'Observação importante sobre o fechamento (desconto dado, pendência, exame que falta). 1 frase. Vazio se não houver.'
      }
    },
    required: %w[fechado valor forma_pagamento data_cirurgia observacao],
    additionalProperties: false
  }.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o MONITOR DE FECHAMENTO interno da CEVICO, clínica oftalmológica
    de São Paulo (unidades Av. Paulista e Tatuapé; cirurgias nas clínicas
    parceiras IOP — geralmente PRK — e Ocular Surgery — geralmente Lasik).
    Sua única função é ler a conversa de WhatsApp e extrair os dados do
    FECHAMENTO DA CIRURGIA para o controle interno. Você nunca fala com o
    paciente e nunca inventa informação.

    CONTEXTO DE VALORES (referência, não invente além do que está na conversa):
    - Cirurgia refrativa: na casa de R$ 5.000 (os dois olhos).
    - Lentes fácicas (Artisan): na casa de R$ 11.900.
    - A clínica fala "investimento"; parcelamento no cartão é comum (até 10x),
      além de PIX à vista e boleto.

    REGRAS DE EXTRAÇÃO:
    - fechado=true SOMENTE quando o paciente ACEITOU o valor/condição
      ("fechado", "vamos marcar", "pode parcelar assim que eu topo").
      Orçamento apresentado sem aceite explícito NÃO é fechamento.
    - valor: o valor TOTAL combinado, só números (ex.: "R$ 11.900" → 11900).
      Se houve desconto, use o valor FINAL aceito. 0 se não ficou claro.
    - forma_pagamento: exatamente como combinado, curto ("cartão 10x",
      "PIX à vista", "entrada + 6x"). Vazio se não mencionada.
    - data_cirurgia: só se a DATA da cirurgia foi confirmada pelos dois
      lados. Converta datas relativas ("sexta que vem") usando a data de
      hoje informada no início. Formato YYYY-MM-DD.
    - observacao: pendência que a gestão precisa saber (exame faltando,
      desconto prometido, condição especial). 1 frase. Vazio se não houver.
    - Se a conversa tiver mais de um orçamento, use o MAIS RECENTE aceito.
  PROMPT

  def initialize(conversation:)
    @conversation = conversation
    @account = conversation.account
  end

  def call
    return { error: 'IA não configurada. Adicione a chave da API em Integrações → Claude.' } if api_key.blank?
    return { error: 'O Monitor de Fechamento está pausado. Reative em Automações → Agentes de IA.' } if agent_paused?

    transcript = build_transcript
    return { error: 'Conversa sem mensagens para analisar.' } if transcript.blank?

    message = client.messages.create(
      model: model,
      max_tokens: 1024,
      system_: system_prompt,
      output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
      messages: [{ role: 'user', content: transcript }]
    )
    record_usage(message)

    text = message.content.find { |block| block.type == :text }&.text
    return { error: 'A IA não retornou os dados do fechamento.' } if text.blank?

    parsed = JSON.parse(text)
    {
      closed: parsed['fechado'] == true,
      value: parsed['valor'].to_f,
      payment: parsed['forma_pagamento'].to_s.strip,
      surgery_date: parse_date(parsed['data_cirurgia']),
      note: parsed['observacao'].to_s.strip,
      model: model
    }
  rescue Anthropic::Errors::AuthenticationError
    { error: 'Chave da API inválida. Confira em CRM → Integrações → IA.' }
  rescue Anthropic::Errors::RateLimitError
    { error: 'Limite de uso da IA atingido. Tente novamente em instantes.' }
  rescue StandardError => e
    Rails.logger.error "[Crm::SurgeryClosing] #{e.class}: #{e.message}"
    { error: 'Erro na extração do fechamento.' }
  end

  private

  def parse_date(date)
    return nil if date.blank?

    TZ.parse(date.to_s)
  rescue StandardError
    nil
  end

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
      "[#{m.created_at.in_time_zone(TZ).strftime('%d/%m/%Y %H:%M')}] #{author}: #{m.content.to_s.strip.truncate(600)}"
    end

    contact = @conversation.contact
    "Hoje é #{TZ.now.strftime('%d/%m/%Y')}.\n" \
      "Contato: #{contact&.name || 'sem nome'} — telefone #{contact&.phone_number || 'não informado'}.\n" \
      "Extraia os dados do fechamento de cirurgia desta conversa:\n\n" + lines.join("\n")
  end
end
