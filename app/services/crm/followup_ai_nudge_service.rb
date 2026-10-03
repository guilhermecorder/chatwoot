# 🤖 Item 315 (03/10, pedido dele: "lembrete com a IA, contextualizado com a
# conversa"): etapa de robô de follow-up em que a cutucada é ESCRITA pela IA
# a partir da conversa — retoma o ponto em que o paciente parou, no tom do
# Roteiro CEVICO, em vez do texto fixo.
#
# Trava: a mensagem SAI para o paciente (RESPONDER_GUARDRAIL). A IA não
# oferece horário, não dá preço novo, não promete resultado: só reabre a
# conversa com uma pergunta simples. Texto simples = só dentro da janela de
# 24h do WhatsApp (o robô já trata isso antes de chamar aqui).
#
# Quem liga/desliga é a etapa do robô (o admin escolheu "IA" na cadência) —
# não há interruptor separado em Agentes de IA; o gasto aparece lá como
# "Lembrete com IA" (agent_key followup_ia).
class Crm::FollowupAiNudgeService
  include Crm::AiAgentConfig

  AGENT_KEY = 'followup_ia'.freeze
  MAX_MESSAGES = 24
  MAX_CHARS = 420
  OUTPUT_SCHEMA = {
    type: 'object',
    properties: { mensagem: { type: 'string' }, motivo: { type: 'string' } },
    required: %w[mensagem motivo],
    additionalProperties: false
  }.freeze

  SYSTEM_PROMPT = <<~TXT.freeze
    Você escreve UMA mensagem curta de follow-up no WhatsApp para um paciente da clínica CEVICO que PAROU de responder.
    A conversa até aqui e a orientação do robô estão abaixo. Sua tarefa: retomar exatamente o ponto em que a conversa
    parou (o que o paciente perguntou, o que a clínica ofereceu, a dúvida que ficou no ar) e reabrir com leveza.

    REGRAS:
    - Português do Brasil, tom humano e acolhedor, como a equipe da clínica fala (sem jargão, sem "prezado").
    - No máximo 2 frases curtas + UMA pergunta simples no fim. Sem listas, sem títulos, sem emoji em excesso (no máximo 1).
    - Use o primeiro nome do paciente se ele aparecer na conversa; se não aparecer, não invente nome.
    - NÃO repita a última mensagem da clínica; NÃO envie uma segunda cobrança igual às cutucadas anteriores.
    - NÃO ofereça horário, NÃO fale de preço que não esteja na conversa, NÃO prometa resultado, NÃO dê orientação médica.
    - Não cite nomes de médicos. Autoridade = equipe cirúrgica especializada e estrutura de alta tecnologia.
    - Se a conversa já terminou com o paciente recusando ("não tenho interesse", "depois eu vejo"), respeite: uma
      mensagem gentil deixando a porta aberta, sem insistir.
    Responda em JSON: {"mensagem": "<texto que vai ao paciente>", "motivo": "<em 1 frase, por que esta mensagem>"}.
  TXT

  def initialize(conversation:, bot: nil, step: {})
    @conversation = conversation
    @account = conversation.account
    @bot = bot
    @step = step || {}
  end

  # { text: '...' } ou { error: '...' }
  def call
    return { error: 'Configure a chave da API em Integrações → Claude.', config_error: true } if api_key.blank?

    transcript = build_transcript
    return { error: 'Conversa vazia.' } if transcript.blank?

    parsed = ask_ai(transcript)
    return { error: parsed[:error] } if parsed[:error].present?

    text = parsed['mensagem'].to_s.squish
    return { error: 'A IA não escreveu a mensagem.' } if text.blank?

    { text: text[0, MAX_CHARS], reason: parsed['motivo'].to_s }
  rescue StandardError => e
    Rails.logger.error "[Crm::FollowupAiNudge] #{e.class}: #{e.message}"
    { error: e.message }
  end

  # prompt do agente: instrução fixa + do Roteiro CEVICO SÓ a persona e as
  # regras de forma (tom, tamanho, palavras proibidas) + trava de quem fala com
  # paciente. Os dados oficiais/tabela de preços ficam de fora de propósito: a
  # cutucada não fala de preço nem de horário, e o roteiro inteiro (~10k
  # tokens) custaria 2x de cache a cada chamada esparsa (varredura 03/10).
  def system_prompt
    version = Crm::CevicoScript.normalize_version(nil)
    tone = %w[persona form_rules].map { |key| Crm::CevicoScript.section_text(@account, key, version) }.join("\n\n")
    "#{SYSTEM_PROMPT}\n\n== ROTEIRO CEVICO (quem fala e como) ==\n#{tone}#{RESPONDER_GUARDRAIL}"
  end

  # cutucada curta: 30 s bastam — o cliente padrão espera até 300 s (páginas
  # inteiras) e seguraria a rodada do robô
  def client
    @client ||= Anthropic::Client.new(api_key: api_key, timeout: 30)
  end

  private

  def agent_key
    AGENT_KEY
  end

  def ask_ai(transcript)
    message = client.messages.create(
      model: model, max_tokens: 600, system_: cached_system(system_prompt),
      output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
      messages: [{ role: 'user', content: user_content(transcript) }]
    )
    record_usage(message)
    parse_structured_response(message)
  end

  def user_content(transcript)
    guidance = @step['ai_instructions'].to_s.strip
    stage = card_stage_name
    [
      { type: 'text', text: "CONVERSA ATÉ AGORA (PACIENTE = quem você escreve; CLÍNICA = equipe/robô):\n#{transcript}",
        cache_control: { type: 'ephemeral' } },
      { type: 'text', text: <<~CTX }
        CONTEXTO:
        - Agora: #{Crm::AgendaSlots::TZ.now.strftime('%d/%m/%Y %H:%M')} (São Paulo).
        - Coluna do paciente no CRM: #{stage || 'sem card'}.
        - Esta é a cutucada "#{step_label}" do robô "#{@bot&.name || 'follow-up'}" — o paciente está em silêncio desde a última mensagem da clínica.
        #{"- ORIENTAÇÃO DO ADMIN PARA ESTA ETAPA: #{guidance}\n" if guidance.present?}
        Escreva a mensagem agora.
      CTX
    ]
  end

  def step_label
    value = @step['delay_value'].presence || @step['delay_hours']
    unit = { 'minutes' => 'min', 'days' => 'dias' }.fetch(@step['delay_unit'], 'h')
    "#{value}#{unit} sem resposta"
  end

  def card_stage_name
    contact_id = @conversation.contact_id
    Crm::Contact.joins(:stage).where(contact_id: contact_id).order(updated_at: :desc).pick('crm_stages.name')
  rescue StandardError
    nil
  end

  # últimas mensagens reais (paciente e clínica), com data — as cutucadas
  # anteriores do robô entram como CLÍNICA, para a IA não repetir. Áudio
  # transcrito/imagem lida (item 204) entram como no Atendente.
  def build_transcript
    messages = @conversation.messages
                            .where(message_type: %i[incoming outgoing])
                            .where(private: false)
                            .includes(:attachments)
                            .reorder(created_at: :desc)
                            .limit(MAX_MESSAGES)
                            .reverse
    lines = messages.filter_map { |m| transcript_line(m) }
    lines.empty? ? nil : lines.join("\n")
  end

  def transcript_line(message)
    marks = message.attachments.map { |a| Crm::MediaReadingService.transcript_label(a) }
    text = [message.content.to_s.strip.presence, marks.presence&.join(' ')].compact.join(' ')
    return if text.blank?

    stamp = message.created_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m %H:%M')
    "[#{stamp}] #{message.incoming? ? 'PACIENTE' : 'CLÍNICA'}: #{text.truncate(600)}"
  end
end
