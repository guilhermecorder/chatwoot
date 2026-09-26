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
        description: 'Para a EQUIPE (não vai ao paciente): UMA frase curta, até 12 palavras, com o que entendeu e por que respondeu assim'
      }
    },
    required: %w[mensagens etapa agendar agendamento cancelar pausar chamar_humano leitura],
    additionalProperties: false
  }.freeze

  # 🔧 rodada 192: só estes respondedores recebem ferramentas (buscar/remarcar/
  # cancelar/confirmar presença — Crm::ResponderTools); os demais seguem iguais.
  # 🎙️ 195: o simulador por texto do Agente de Ligação também (é sempre sombra).
  # 🩺 item 251: o Atendente de Pós-operatório também (retorno pela Agenda + abrir_tarefa)
  RESPONDER_TOOLS_KEYS = %w[atendente_agendamento atendente_pos atendente_pos_op voice].freeze
  # voltas de tool use por resposta: a IA pede → o sistema executa → a IA lê.
  # Passou do teto, a última chamada vai com tool_choice none (tem que responder).
  MAX_TOOL_ROUNDS = 5

  attr_reader :agent_key, :script_version

  # live: false (sombra/simulador) = nenhuma ferramenta escreve na Agenda
  # simulation: true = 🧪 Testar agente (caixa interna, nada sai): roda MESMO com o
  # interruptor desligado — o teste é justamente para antes de ligar (pedido 21/09)
  # script_version (22/09): 'v1' (oficial) ou 'v2' (Roteiro paralelo). Sem
  # informar, vale o que a conversa de teste guardou ao nascer; conversa real = v1.
  def initialize(conversation:, agent_key:, live: false, simulation: false, script_version: nil)
    @conversation = conversation
    @account = conversation.account
    @agent_key = agent_key.to_s
    @live = live == true
    @simulation = simulation == true
    @script_version = Crm::CevicoScript.normalize_version(
      script_version.presence || conversation.additional_attributes&.[]('cevico_simulado_script')
    )
  end

  def call # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    return { error: 'Agente desligado.' } if agent_paused? && !@simulation
    return { error: 'Configure a chave da API em Integrações → Claude.' } if api_key.blank?

    transcript = build_transcript
    return { error: 'Conversa vazia.' } if transcript.blank?

    # tools + output_config (json_schema) convivem na mesma chamada (conferido
    # no gem anthropic 1.55, 21/09): o JSON vale para a resposta final em texto
    params = {
      model: model, max_tokens: 2048, system_: cached_system,
      output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
      messages: [{ role: 'user', content: user_content(transcript) }]
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

    "#{Crm::CevicoScript.text(@account, @script_version)}\n\n== SUA ETAPA ==\n" \
      "#{Crm::CevicoScript.stage_prompt(@account, @agent_key, @script_version)}#{RESPONDER_GUARDRAIL}"
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
      #{"- Motivo da ligação: #{call_objective}\n" if voice?}#{"- Cirurgia realizada: #{surgery_text}\n" if pos_op?}
      HORÁRIOS DISPONÍVEIS (vagas LIVRES reais das próximas 4 semanas; ofereça no máximo 2 por vez, só destes; para um dia específico fora desta lista use a ferramenta horarios_do_dia — agendamento futuro é liberado):
      #{Crm::AgendaSlots.free_slots_text(@account, days: 28, per_window: 3)}

    CTX
  end

  # 💸 item 232 (25/09): a CONVERSA vai primeiro, em bloco próprio marcado
  # para cache (5 min). Entre uma mensagem picada e a outra, e entre as voltas
  # de ferramenta da mesma resposta, esse prefixo repete e a Anthropic cobra
  # 10%. O contexto vivo (agora, vagas, coluna) muda a cada chamada — por isso
  # vem DEPOIS, fora do trecho guardado.
  def user_content(transcript)
    header = if voice?
               'LIGAÇÃO ATÉ AGORA (PACIENTE = quem está na linha; CLÍNICA = você, falando):'
             else
               'CONVERSA ATÉ AGORA (PACIENTE = quem você atende; CLÍNICA = você/equipe):'
             end
    [
      { type: 'text', text: "#{header}\n#{transcript}", cache_control: { type: 'ephemeral' } },
      { type: 'text', text: "#{context_block}\nResponda à ÚLTIMA mensagem do PACIENTE da conversa acima, seguindo o Roteiro." }
    ]
  end

  # 🩺 item 251: o Atendente de Pós-operatório precisa saber QUAL cirurgia e há
  # quantos dias — a orientação muda (PRK × LASIK, 2 dias × 20 dias)
  def pos_op?
    @agent_key == 'atendente_pos_op'
  end

  SURGERY_UNKNOWN = 'não encontrada na Agenda (pergunte qual cirurgia e quando foi)'.freeze

  def surgery_text # rubocop:disable Metrics/AbcSize
    task = last_surgery_task
    return SURGERY_UNKNOWN if task.blank?

    at = task.due_at.in_time_zone(Crm::AgendaSlots::TZ)
    days = (Crm::AgendaSlots::TZ.now.to_date - at.to_date).to_i
    parts = ["#{at.strftime('%d/%m/%Y')} (há #{days} dia#{'s' unless days == 1})", task.procedure.presence, task.doctor.presence,
             Crm::AgendaSlots::UNIT_LABELS[task.unit.to_s] || task.unit.presence]
    parts << "presença: #{task.attendance == 'attended' ? 'realizada' : task.attendance}" if task.attendance.present?
    parts.compact.join(' · ')
  end

  def last_surgery_task
    contact = @conversation.contact
    return nil if contact.blank?

    Task.for_patient(@account, contact)
        .where(task_type: 'cirurgia', canceled_at: nil)
        .where('due_at <= ?', Time.current)
        .order(due_at: :desc).first
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

  # últimas N mensagens reais (nada de notas internas); áudio/imagem entram
  # como TEXTO lido pelo Gemini (item 204: "[áudio transcrito: …]", "[imagem
  # (receita): … · texto na imagem: …]"); sem leitura, o marcador pede texto
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
      marks = m.attachments.map { |a| Crm::MediaReadingService.transcript_label(a) }
      text = [body.presence, marks.presence&.join(' ')].compact.join(' ')
      next if text.blank?

      author = m.incoming? ? 'PACIENTE' : 'CLÍNICA'
      # áudio transcrito/imagem lida podem passar de 600: o corte vale só para o texto digitado
      stamp = m.created_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m %H:%M')
      "[#{stamp}] #{author}: #{text.truncate(marks.any? ? 2400 : 600)}"
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
end
