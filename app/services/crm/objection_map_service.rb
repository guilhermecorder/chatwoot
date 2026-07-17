# MAPA DE OBJEÇÕES (ferramenta de fechamento high ticket): a IA lê as
# conversas de pacientes que AVANÇARAM pelos estágios-chave do funil e
# extrai, POR ESTÁGIO: as maiores objeções + as melhores respostas reais
# que geraram a conversão para o estágio seguinte — documentado e à
# disposição do time. Roda sob demanda (botão do admin) usando a config
# do agente Consultor Comercial (sales).
class Crm::ObjectionMapService
  include Crm::AiAgentConfig

  AGENT_KEY = 'sales'.freeze
  MAX_MESSAGES = 30
  CONVERSATIONS_PER_STAGE = 8
  LOOKBACK = 120.days

  # transições que interessam pro fechamento (regex do estágio de DESTINO)
  KEY_STAGES = [
    { key: 'agendamento', label: 'Chegou ao Agendamento de Consulta', pattern: '%agendamento%' },
    { key: 'indicacao', label: 'Recebeu Indicação de Cirurgia', pattern: '%indica%' },
    { key: 'cirurgia_agendada', label: 'Fechou a Cirurgia (agendada)', pattern: '%cirurgia agendada%' },
    { key: 'cirurgia_realizada', label: 'Realizou a Cirurgia', pattern: '%cirurgia realizada%' }
  ].freeze

  OUTPUT_SCHEMA = {
    type: 'object',
    properties: {
      objecoes: {
        type: 'array',
        description: 'As maiores objeções deste estágio, da mais frequente para a menos',
        items: {
          type: 'object',
          properties: {
            objecao: { type: 'string', description: 'A objeção como o paciente costuma dizer' },
            frequencia: { type: 'string', description: 'alta | média | baixa' },
            melhor_resposta: { type: 'string',
                               description: 'A melhor resposta REAL observada (a que converteu), em frase pronta para a equipe' },
            por_que_funciona: { type: 'string', description: 'Por que essa resposta converte, em 1 frase' }
          },
          required: %w[objecao frequencia melhor_resposta por_que_funciona],
          additionalProperties: false
        }
      }
    },
    required: %w[objecoes],
    additionalProperties: false
  }.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o analista comercial da CEVICO (clínica de oftalmologia, cirurgias
    high ticket: refrativa, catarata premium, Artisan). Vai receber conversas
    REAIS de pacientes que AVANÇARAM até um estágio do funil.

    Sua missão: extrair o MAPA DE OBJEÇÕES daquele estágio —
    - as objeções que mais apareceram ANTES do paciente avançar (preço,
      medo, "vou pensar", cônjuge, concorrente, tempo de recuperação...);
    - e a MELHOR RESPOSTA real observada: o que a equipe disse que fez o
      paciente destravar. Transforme em frase pronta, no tom CEVICO
      (acolhedor, seguro, sem pressão).
    Regras: só objeções que realmente apareceram; máximo 6 por estágio;
    respostas fiéis ao que funcionou (pode polir o texto, não inventar
    argumento novo); nunca prometa resultado cirúrgico.
  PROMPT

  def initialize(account)
    @account = account
  end

  def call # rubocop:disable Metrics/CyclomaticComplexity
    return { error: 'Configure a chave da Anthropic primeiro.' } if api_key.blank?
    return { error: 'Ligue o Consultor Comercial (Automações → Agentes de IA).' } if agent_paused?

    stages = KEY_STAGES.filter_map do |stage|
      convs = conversations_that_advanced(stage[:pattern])
      next if convs.empty?

      verdict = analyze_stage(stage, convs)
      next if verdict.blank? || verdict['error'].present?

      { 'key' => stage[:key], 'label' => stage[:label],
        'conversations' => convs.size, 'objecoes' => verdict['objecoes'] }
    end
    return { error: 'Nenhuma conversa com avanço de estágio encontrada no período.' } if stages.empty?

    map = { 'generated_at' => Time.current.iso8601, 'stages' => stages }
    save_map(map)
    { success: true, stages: stages.size }
  end

  private

  # conversas de contatos que ENTRARAM no estágio-alvo nos últimos meses
  def conversations_that_advanced(pattern)
    logs = Crm::StageLog.joins(crm_contact: :pipeline)
                        .where(crm_pipelines: { account_id: @account.id }, event_type: 'entered')
                        .where('stage_name ILIKE ?', pattern)
                        .where('entered_at >= ?', LOOKBACK.ago)
                        .order(entered_at: :desc)
                        .limit(CONVERSATIONS_PER_STAGE * 2)
    contact_ids = logs.filter_map { |l| l.crm_contact&.contact_id }.uniq.first(CONVERSATIONS_PER_STAGE)
    contact_ids.filter_map do |cid|
      @account.conversations.where(contact_id: cid)
              .order(Arel.sql('last_activity_at DESC NULLS LAST, created_at DESC')).first
    end
  end

  def analyze_stage(stage, convs)
    corpus = convs.map { |c| "=== CONVERSA ===\n#{transcript(c)}" }.join("\n\n")
    message = client.messages.create(
      model: model,
      max_tokens: 2048,
      system_: SYSTEM_PROMPT,
      output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
      messages: [{ role: 'user',
                   content: "Estágio: #{stage[:label]}. Extraia o mapa de objeções destas #{convs.size} conversas:\n\n#{corpus.truncate(90_000)}" }]
    )
    record_usage(message)
    parse_structured_response(message)
  rescue StandardError => e
    Rails.logger.error "[Crm::ObjectionMap] #{stage[:key]} #{e.class}: #{e.message}"
    nil
  end

  def transcript(conversation)
    conversation.messages.reorder(:created_at)
                .where(message_type: [:incoming, :outgoing], private: false)
                .last(MAX_MESSAGES)
                .map { |m| "#{m.message_type == 'incoming' ? 'PACIENTE' : 'CLÍNICA'}: #{m.content.to_s.truncate(400)}" }
                .join("\n")
  end

  def save_map(map)
    settings = CrmSetting.find_or_create_by!(account: @account)
    cfg = settings.ai_config || {}
    cfg['agents'] ||= {}
    cfg['agents']['sales'] ||= {}
    cfg['agents']['sales']['objection_map'] = map
    settings.update!(ai_config: cfg)
  end
end
