# 🧠 FOLLOW-UP INTELIGENTE (13/10, pedido dele: "o robô ainda está meio
# burrinho — não entende que a conversa acabou"). Caso real: Adriano
# (Instagram, 13/10) — paciente "Ainda não", a IA se despediu ("qualquer dia é
# só me chamar aqui") e 25 min depois o robô mandou "Oi, pode falar?".
#
# Antes da 1ª cutucada de cada silêncio, este leitor diz EM QUE PÉ a conversa
# parou — uma leitura por silêncio (guardada na conversa), não a cada rodada:
#   aberta    → ficou pergunta/proposta da clínica sem resposta: cutucada faz sentido
#   encerrada → despedida, agradecimento final, consulta marcada, dúvida resolvida
#   adiada    → "ainda não", "vou pensar", "depois eu vejo": volta UMA vez, dias depois,
#               por mensagem modelo (decisão B dele, 13/10)
#   recusou   → "não tenho interesse", "já fiz em outro lugar": para e etiqueta
#
# Sem chave da API ou com a IA fora do ar, cai na REGRA (frases típicas) — o
# robô nunca fica sem leitura. O agente é INTERNO (só lê): trava operacional.
class Crm::FollowupConversationReader
  include Crm::AiAgentConfig

  AGENT_KEY = 'followup_leitor'.freeze
  SITUACOES = %w[aberta encerrada adiada recusou].freeze
  MAX_MESSAGES = 16
  OUTPUT_SCHEMA = {
    type: 'object',
    properties: {
      situacao: { type: 'string', enum: SITUACOES },
      motivo: { type: 'string', description: 'Para a EQUIPE: 1 frase curta (até 12 palavras) com o porquê' }
    },
    required: %w[situacao motivo],
    additionalProperties: false
  }.freeze

  SYSTEM_PROMPT = <<~TXT.freeze
    Você lê o fim de uma conversa entre um paciente e a clínica de olhos CEVICO (WhatsApp/Instagram) e decide se um
    robô de follow-up deve mandar uma "cutucada" para o paciente que está em silêncio. Mandar cutucada para quem já
    encerrou a conversa irrita o paciente e faz a clínica ser denunciada como spam. Classifique a SITUAÇÃO:

    - "aberta": a ÚLTIMA fala da clínica deixou algo para o paciente responder — uma pergunta, uma proposta de
      horário, um orçamento com pergunta, um pedido de dado — ou o paciente demonstrou interesse e parou no meio.
    - "encerrada": a conversa terminou de forma natural — despedida ("é só me chamar", "fico à disposição",
      "boa consulta"), agradecimento final do paciente ("obrigado", "ok, combinado"), consulta marcada ou confirmada,
      dúvida respondida sem nada pendente.
    - "adiada": o paciente disse que não é agora, sem recusar de vez — "ainda não", "vou pensar", "depois eu vejo",
      "mês que vem", "vou falar com meu marido", "agora não posso".
    - "recusou": o paciente disse com clareza que não quer — "não tenho interesse", "já fiz em outro lugar",
      "desisti", "não vou fazer", "achei caro, não vou fazer".

    DECIDA NESTA ORDEM (a primeira que valer é a resposta):
      1. A última fala do PACIENTE recusa de vez? → "recusou" (mesmo que a clínica tenha se despedido depois).
      2. A última fala do PACIENTE adia ("ainda não", "vou pensar"...)? → "adiada" (mesmo com despedida da clínica depois).
      3. A ÚLTIMA fala da clínica deixou pergunta/proposta sem resposta? → "aberta".
      4. Senão → "encerrada".
    Exemplo: PACIENTE "Ainda não" → CLÍNICA "Sem problemas, é só me chamar" = "adiada".
    Exemplo: PACIENTE "Já fiz em outra clínica, obrigado" → CLÍNICA "Ótima recuperação!" = "recusou".
    Responda em JSON: {"situacao": "...", "motivo": "..."}.
  TXT

  # ── REGRA (sem IA): frases típicas. Também é a reserva quando a IA falha ──
  RECUSOU = /n[aã]o\s+tenho\s+(mais\s+)?interesse|n[aã]o\s+(quero|vou)\s+(mais\s+)?(fazer|operar)|
    j[aá]\s+(fiz|operei|marquei|agendei)\b.{0,40}?\boutr[ao]s?\b|desist[iu]|n[aã]o\s+me\s+interessa/ix
  ADIADA = /ainda\s+n[aã]o|vou\s+pensar|preciso\s+pensar|depois\s+(eu\s+)?(vejo|falo|te\s+chamo|retorno|aviso)|
    mais\s+pra\s+frente|m[eê]s\s+que\s+vem|outra\s+hora|agora\s+n[aã]o|no\s+momento\s+n[aã]o|
    vou\s+(ver|falar)\s+com|quando\s+(eu\s+)?puder/ix
  DESPEDIDA = /[eé]\s+s[oó]\s+(me\s+)?chamar|fico\s+([àa]\s+)?disposi|estou\s+por\s+aqui|estamos\s+por\s+aqui|
    boa\s+consulta|at[eé]\s+(mais|logo|breve|l[aá])|tenha\s+um\s+([oó]timo|bom|excelente)|fico\s+tranquil|
    qualquer\s+(d[uú]vida|coisa)[^?]*$|disponha|por\s+nada|imagina/ix
  AGRADECEU = /\A\s*(obrigad[oa]|muito\s+obrigad|valeu|ok|okay|blz|beleza|combinado|perfeito|certo|t[aá]\s+bom|
    👍|🙏|😊|❤️)[\s!.,👍🙏😊❤️]*\z/ix

  def self.rule_verdict(last_patient_text, last_clinic_text)
    patient = last_patient_text.to_s
    clinic = last_clinic_text.to_s
    return 'recusou' if RECUSOU.match?(patient)
    return 'adiada' if ADIADA.match?(patient)
    return 'aberta' if clinic.include?('?')
    return 'encerrada' if DESPEDIDA.match?(clinic) || AGRADECEU.match?(patient)

    'aberta'
  end

  def initialize(conversation:)
    @conversation = conversation
    @account = conversation.account
  end

  # { situacao:, motivo:, fonte: 'ia' | 'regra' }
  def call
    return rule_result('sem chave da API') if api_key.blank?

    transcript = build_transcript
    return rule_result('conversa vazia') if transcript.blank?

    parsed = ask_ai(transcript)
    situacao = parsed.is_a?(Hash) ? parsed['situacao'].to_s : ''
    return rule_result(parsed[:error] || 'resposta inválida') unless SITUACOES.include?(situacao)

    { situacao: refine(situacao), motivo: parsed['motivo'].to_s.squish.truncate(140), fonte: 'ia' }
  rescue StandardError => e
    Rails.logger.warn "[Crm::FollowupConversationReader] #{e.class}: #{e.message}"
    rule_result(e.message)
  end

  # leitura curta: 20 s bastam (não segura a rodada do robô)
  def client
    @client ||= Anthropic::Client.new(api_key: api_key, timeout: 20)
  end

  private

  def agent_key
    AGENT_KEY
  end

  def system_prompt
    SYSTEM_PROMPT + OPERATIONAL_GUARDRAIL
  end

  def ask_ai(transcript)
    message = client.messages.create(
      model: model, max_tokens: 300, system_: cached_system(system_prompt),
      output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
      messages: [{ role: 'user', content: "CONVERSA (da mais antiga para a mais recente):\n#{transcript}\n\nQual é a situação?" }]
    )
    record_usage(message)
    parse_structured_response(message)
  end

  # rede de segurança: a IA disse "encerrada", mas a última fala do paciente é
  # recusa/adiamento clara pelas frases → vale a fala do paciente (garante a
  # etiqueta da recusa e a reativação de quem adiou). Nunca mexe num "aberta".
  def refine(situacao)
    return situacao unless situacao == 'encerrada'

    by_rule = self.class.rule_verdict(last_text(:incoming, limit: 1), '')
    %w[recusou adiada].include?(by_rule) ? by_rule : situacao
  end

  def rule_result(why)
    patient = last_text(:incoming)
    clinic = last_text(:outgoing)
    { situacao: self.class.rule_verdict(patient, clinic), motivo: "regra de frases (#{why.to_s.truncate(60)})", fonte: 'regra' }
  end

  def public_messages
    @conversation.messages.where(message_type: %i[incoming outgoing], private: false)
  end

  # últimas falas de um lado (as cutucadas do robô não contam como fala da clínica)
  def last_text(type, limit: 3)
    scope = public_messages.where(message_type: type)
    scope = scope.where("messages.additional_attributes ->> 'cevico_followup_bot_id' IS NULL") if type == :outgoing
    scope.reorder(created_at: :desc).limit(limit).pluck(:content).compact.reverse.join(' ')
  end

  def build_transcript
    messages = public_messages.reorder(created_at: :desc).limit(MAX_MESSAGES).to_a.reverse
    lines = messages.filter_map do |m|
      text = m.content.to_s.strip
      next if text.blank?

      who = if m.incoming?
              'PACIENTE'
            elsif m.additional_attributes&.dig('cevico_followup_bot_id').present?
              'CLÍNICA (cutucada automática)'
            else
              'CLÍNICA'
            end
      "[#{m.created_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m %H:%M')}] #{who}: #{text.truncate(400)}"
    end
    lines.empty? ? nil : lines.join("\n")
  end
end
