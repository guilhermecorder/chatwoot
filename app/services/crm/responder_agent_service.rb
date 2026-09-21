# 🗣️ MOTOR DOS RESPONDEDORES (rodada 188): um serviço para todo agente que
# FALA com o paciente pelo WhatsApp. O prompt é sempre a soma de três partes:
#   Roteiro CEVICO (fonte única, Crm::CevicoScript)
#   + bloco da ETAPA do agente (o que muda de um agente para o outro)
#   + trava do sistema (RESPONDER_GUARDRAIL, não editável).
# O sistema injeta o contexto VIVO em toda chamada: agora, nome e telefone do
# contato, coluna do card no CRM, vagas LIVRES da Agenda interna, consulta
# futura do paciente e as últimas 40 mensagens reais da conversa.
# Este serviço NÃO envia nada: devolve o JSON (mensagens + decisões) e quem
# decide o que fazer com ele é o Crm::ResponderAgentJob (sombra × ao vivo).
class Crm::ResponderAgentService # rubocop:disable Metrics/ClassLength
  include Crm::AiAgentConfig

  MAX_MESSAGES = 40
  ETAPAS = %w[recepcao sondagem autoridade orcamento objecoes agendamento pos_agendamento
              reagendamento pos_consulta pos_cirurgico encerramento].freeze

  OUTPUT_SCHEMA = {
    type: 'object',
    properties: {
      mensagens: {
        type: 'array', items: { type: 'string' },
        description: 'Mensagens curtas a enviar ao paciente, em ordem (máx 3, até ~200 caracteres cada; ' \
                     'textos prontos do roteiro podem ser maiores)'
      },
      etapa: { type: 'string', enum: ETAPAS, description: 'Etapa do roteiro em que a conversa está' },
      agendar: {
        type: 'boolean',
        description: 'true SOMENTE quando nome + telefone + dia + hora + unidade estão confirmados pelo paciente e o horário está ' \
                     'na lista HORÁRIOS DISPONÍVEIS'
      },
      agendamento: {
        type: 'object',
        properties: {
          nome: { type: 'string' },
          telefone: { type: 'string' },
          dia: { type: 'string', description: 'YYYY-MM-DD' },
          hora: { type: 'string', description: 'HH:MM' },
          unidade: { type: 'string', enum: %w[tatuape paulista] },
          procedimento: { type: 'string' }
        },
        required: %w[nome telefone dia hora unidade procedimento],
        additionalProperties: false,
        description: 'Dados da consulta (obrigatório quando agendar=true; strings vazias quando agendar=false)'
      },
      cancelar: { type: 'boolean', description: 'true SOMENTE quando o paciente confirmou que quer CANCELAR a consulta futura sem remarcar' },
      pausar: { type: 'boolean', description: 'true quando sua função terminou nesta conversa (agendou, paciente encerrou)' },
      chamar_humano: { type: 'boolean', description: 'true quando a equipe humana precisa assumir (urgência, caso clínico, insatisfação, falha)' },
      leitura: {
        type: 'string',
        description: 'Para a EQUIPE (não vai ao paciente): em 1 frase, o que você entendeu da situação e por que respondeu assim'
      }
    },
    required: %w[mensagens etapa agendar agendamento cancelar pausar chamar_humano leitura],
    additionalProperties: false
  }.freeze

  # 🔧 rodada 192: só estes respondedores recebem ferramentas (buscar/remarcar/
  # cancelar/confirmar presença — Crm::ResponderTools); os demais seguem iguais.
  # 🎙️ 195: o simulador por texto do Agente de Ligação também (é sempre sombra).
  RESPONDER_TOOLS_KEYS = %w[atendente_agendamento atendente_pos voice].freeze
  # voltas de tool use por resposta: a IA pede → o sistema executa → a IA lê.
  # Passou do teto, a última chamada vai com tool_choice none (tem que responder).
  MAX_TOOL_ROUNDS = 5

  attr_reader :agent_key

  # live: false (sombra/simulador) = nenhuma ferramenta escreve na Agenda
  def initialize(conversation:, agent_key:, live: false)
    @conversation = conversation
    @account = conversation.account
    @agent_key = agent_key.to_s
    @live = live == true
  end

  def call # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    return { error: 'Agente desligado.' } if agent_paused?
    return { error: 'Configure a chave da API em Integrações → Claude.' } if api_key.blank?

    transcript = build_transcript
    return { error: 'Conversa vazia.' } if transcript.blank?

    # tools + output_config (json_schema) convivem na mesma chamada (conferido
    # no gem anthropic 1.55, 21/09): o JSON vale para a resposta final em texto
    params = {
      model: model, max_tokens: 2048, system_: system_prompt,
      output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
      messages: [{ role: 'user', content: context_block + transcript }]
    }
    params[:tools] = tools.definitions if tools

    message = nil
    (MAX_TOOL_ROUNDS + 1).times do |round|
      params[:tool_choice] = { type: 'none' } if tools && round == MAX_TOOL_ROUNDS
      message = client.messages.create(**params)
      record_usage(message)
      break unless tools && message.stop_reason == :tool_use

      uses = message.content.select { |block| block.type == :tool_use }
      break if uses.empty?

      params[:messages] << { role: 'assistant', content: assistant_content(message) }
      params[:messages] << { role: 'user', content: uses.map { |use| tool_result_block(use) } }
    end

    text = message.content.find { |block| block.type == :text }&.text
    return { error: 'Resposta vazia da IA.' } if text.blank?

    result = JSON.parse(text).symbolize_keys
    result[:acoes] = tools ? tools.acoes : []
    result
  rescue JSON::ParserError
    { error: 'Resposta da IA fora do formato.' }
  rescue StandardError => e
    Rails.logger.error "[Crm::ResponderAgent##{@agent_key}] #{e.class}: #{e.message}"
    { error: e.message }
  end

  # o prompt completo, visível na tela do agente ("o que ele lê")
  def system_prompt
    return voice_system_prompt if voice?

    "#{Crm::CevicoScript.text(@account)}\n\n== SUA ETAPA ==\n#{Crm::CevicoScript.stage_prompt(@account, @agent_key)}#{RESPONDER_GUARDRAIL}"
  end

  private

  # 🎙️ rodada 195: simulador POR TEXTO do Agente de Ligação — mesmo Roteiro,
  # regras de voz e etapa da ligação real, com as ferramentas mapeadas para as
  # deste motor (Crm::VoiceAgent::Script::SIMULATOR_TOOLS). As "mensagens" da
  # saída são as FALAS da assistente.
  def voice?
    @agent_key == 'voice'
  end

  def voice_system_prompt
    next_appointment = future_appointment_text
    Crm::VoiceAgent::Script.simulator_prompt(@account, contact: @conversation.contact, objective: call_objective,
                                                       next_appointment: next_appointment == 'nenhuma' ? '' : next_appointment)
  end

  # motivo da ligação simulada: o que a tela mandou (guardado na conversa) ou o padrão
  def call_objective
    @conversation.additional_attributes&.[]('cevico_simulado_objective').presence || Crm::VoiceAgent::Script::DEFAULT_OBJECTIVE
  end

  def tools
    return nil unless RESPONDER_TOOLS_KEYS.include?(@agent_key)

    @tools ||= Crm::ResponderTools.new(conversation: @conversation, agent_key: @agent_key, live: @live)
  end

  # a resposta da IA volta como turno do assistente: texto e tool_use viram
  # blocos simples; thinking (quando vier) vai de volta inteiro, com assinatura
  def assistant_content(message)
    message.content.map do |block|
      case block.type
      when :text then { type: 'text', text: block.text }
      when :tool_use then { type: 'tool_use', id: block.id, name: block.name, input: (block.input || {}).to_h }
      else block.to_h
      end
    end
  end

  def tool_result_block(use)
    outcome = tools.call(use.name, use.input)
    { type: 'tool_result', tool_use_id: use.id, content: outcome.to_json }
  end

  # contexto vivo: agora, contato, coluna, vagas reais, consulta futura
  def context_block
    now = Crm::AgendaSlots::TZ.now
    contact = @conversation.contact
    phone = contact&.phone_number.presence
    <<~CTX
      CONTEXTO (gerado pelo sistema agora):
      - Agora: #{Crm::AgendaSlots::WEEKDAYS[now.wday]}, #{now.strftime('%d/%m/%Y %H:%M')} (São Paulo). Use esta data para "hoje", "amanhã", "semana que vem". Nunca aceite data no passado.
      - Paciente (cadastro): #{contact&.name.presence || 'sem nome'} · telefone deste WhatsApp: #{phone || 'desconhecido (peça o número antes de agendar)'}
      - Coluna do paciente no CRM: #{card_stage_name || 'sem card (contato novo)'}
      - Consulta futura já marcada: #{future_appointment_text}
      #{"- Motivo da ligação: #{call_objective}\n" if voice?}
      HORÁRIOS DISPONÍVEIS (vagas LIVRES reais dos próximos dias; ofereça no máximo 2 por vez, só destes):
      #{Crm::AgendaSlots.free_slots_text(@account, days: 12, per_window: 4)}

      #{voice? ? 'LIGAÇÃO ATÉ AGORA (PACIENTE = quem está na linha; CLÍNICA = você, falando)' : 'CONVERSA ATÉ AGORA (PACIENTE = quem você atende; CLÍNICA = você/equipe)'}:

    CTX
  end

  def card_stage_name
    contact = @conversation.contact
    return nil if contact.blank?

    Crm::Contact.where(contact_id: contact.id).includes(:stage).order(:updated_at).last&.stage&.name
  end

  def future_appointment_text
    contact = @conversation.contact
    task = Crm::AppointmentRecorder.future_appointment(@account, contact&.phone_number, nil, contact)
    return 'nenhuma' if task.blank?

    when_at = task.due_at.in_time_zone(Crm::AgendaSlots::TZ)
    unit = Crm::AgendaSlots::UNIT_LABELS[task.unit] || task.unit
    # o id entra para as ferramentas (remarcar/cancelar/confirmar) sem precisar buscar
    "#{Crm::AgendaSlots::WEEKDAYS[when_at.wday]} #{when_at.strftime('%d/%m/%Y às %H:%M')} · #{unit} · " \
      "#{task.doctor.presence || 'médico a definir'} (id #{task.id})"
  end

  # últimas N mensagens reais (nada de notas internas); áudio/imagem viram
  # marcadores — na Rodada 1 o agente pede por texto (transcrição vem na R2)
  # Conversa SIMULADA (rake cevico:wa_agent_simulate): ninguém responde de
  # verdade, então as próprias notas de sombra entram como falas da CLÍNICA —
  # senão o agente acha que toda mensagem é o primeiro contato.
  def build_transcript # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    types = simulated? ? %i[incoming outgoing activity] : %i[incoming outgoing]
    messages = @conversation.messages
                            .where(message_type: types)
                            .includes(:attachments)
                            .reorder(created_at: :desc)
                            .limit(MAX_MESSAGES)
                            .reverse

    lines = messages.filter_map do |m|
      next transcript_shadow_line(m) if m.activity?
      next if m.private?

      body = m.content.to_s.strip
      marks = m.attachments.map { |a| "[#{attachment_label(a.file_type)}]" }
      text = [body.presence, marks.presence&.join(' ')].compact.join(' ')
      next if text.blank?

      author = m.incoming? ? 'PACIENTE' : 'CLÍNICA'
      "[#{m.created_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m %H:%M')}] #{author}: #{text.truncate(600)}"
    end
    lines.empty? ? nil : lines.join("\n")
  end

  def simulated?
    @conversation.additional_attributes&.[]('cevico_simulado') == true
  end

  def transcript_shadow_line(message)
    shadow = message.additional_attributes&.[]('cevico_ia_shadow')
    return nil if shadow.blank?

    text = Array(shadow['mensagens']).join(' ')
    "[#{message.created_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m %H:%M')}] CLÍNICA: #{text.truncate(900)}"
  end

  def attachment_label(file_type)
    { 'audio' => 'áudio: peça para o paciente escrever', 'image' => 'imagem', 'video' => 'vídeo',
      'file' => 'arquivo', 'location' => 'localização', 'contact' => 'contato' }[file_type.to_s] || file_type.to_s
  end
end
