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
          procedimento: { type: 'string' },
          # 👪 item 346: consulta de OUTRA pessoa → cadastro e card próprios dela
          para_outra_pessoa: {
            type: 'boolean',
            description: 'true quando a consulta é de OUTRA pessoa (mãe, filho, esposa, amigo): aí nome e telefone são os DO ' \
                         'PACIENTE, ditados por quem conversa. false quando é para quem está conversando.'
          }
        },
        required: %w[nome telefone dia hora unidade procedimento para_outra_pessoa],
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
  RESPONDER_TOOLS_KEYS = %w[atendente_agendamento atendente_pos atendente_pos_op atendente_visagista voice].freeze

  # 👪 item 346 (pedido dele 15/10): vale SEMPRE, mesmo com os passos do
  # atendente personalizados na tela — por isso fica no contexto e não no roteiro
  OTHER_PERSON_RULE = '- CONSULTA PARA OUTRA PESSOA (mãe, filho, esposa, amigo): antes de agendar, peça o NOME COMPLETO e o ' \
                      'TELEFONE COM DDD de quem vai passar na consulta ("Pra deixar reservado, me passa o nome completo e o ' \
                      'telefone com DDD de quem vai passar na consulta?"). No agendamento vão o nome e o telefone DO PACIENTE, ' \
                      'com para_outra_pessoa=true; nunca o nome de quem conversa. Se o paciente não tiver telefone próprio ' \
                      '(criança, idoso), deixe o telefone deste WhatsApp: os avisos da consulta chegam por aqui.'.freeze
  # voltas de tool use por resposta: a IA pede → o sistema executa → a IA lê.
  # Passou do teto, a última chamada vai com tool_choice none (tem que responder).
  MAX_TOOL_ROUNDS = 5
  # 🧰 22/11 (bug das ferramentas à toa): com o JSON obrigatório (output_config
  # json_schema) valendo também nas voltas de ferramenta, a IA que só queria FALAR
  # não conseguia: o texto tinha de abrir em JSON, e a saída que sobrava era chamar
  # ferramenta (horarios_do_dia, buscar_consulta, abrir_tarefa "placeholder/ignorar",
  # pedir_fotos fora de hora). Medido na bancada 6517: com o formato, chamada à toa já
  # na 2ª resposta; sem ele, 8 respostas sem nenhuma. Agora a resposta à pessoa é
  # uma ferramenta própria (`responder`, strict: o JSON sai igual, conferido pela API)
  # e as voltas não têm formato obrigatório; uma ferramenta por vez. Se a IA terminar
  # em texto solto (ou passar do teto), uma última chamada SEM ferramentas e COM o
  # formato escreve a resposta.
  ANSWER_TOOL_NAME = 'responder'.freeze
  REPEATED_CALL_TEXT = 'Esta ferramenta JÁ foi chamada com os mesmos dados nesta resposta: nada foi feito de novo. ' \
                       'Use o resultado anterior e responda pela ferramenta responder.'.freeze
  # item 399 (ótica): no ChatGPT a resposta final sai no formato, sem a ferramenta responder
  OPENAI_ANSWER_HINT = /responda pela ferramenta responder/i

  # spent_usd (item 400): quanto ESTA resposta custou, somando todas as chamadas
  attr_reader :agent_key, :script_version, :spent_usd

  # live: false (sombra/simulador) = nenhuma ferramenta escreve na Agenda
  # simulation: true = 🧪 Testar agente (caixa interna, nada sai): roda MESMO com o
  # interruptor desligado — o teste é justamente para antes de ligar (pedido 21/09)
  # script_version (22/09): 'v1' (oficial) ou 'v2' (Roteiro paralelo). Sem
  # informar, vale o que a conversa de teste guardou ao nascer; conversa real = v1.
  # 🪞 08/11: otica_live = no SIMULADOR (Testar agente) as ferramentas da ótica rodam de
  # verdade (foto → imagem no Gemini, lentes com imagem, conferência de desconto) dentro
  # da conversa de teste; a Agenda continua só simulando e nenhuma tarefa nasce
  # model_override (item 399): SÓ no 🧪 Testar agente — experimenta outro motor
  # (Claude ou ChatGPT) na conversa de teste sem mexer no que o agente usa de verdade
  def initialize(conversation:, agent_key:, live: false, simulation: false, script_version: nil, # rubocop:disable Metrics/ParameterLists
                 otica_live: false, model_override: nil)
    @conversation = conversation
    @account = conversation.account
    @spent_usd = 0.0
    @agent_key = agent_key.to_s
    @live = live == true
    @simulation = simulation == true
    @otica_live = otica_live == true
    @model_override = model_override.to_s if @simulation && engine_models.include?(model_override.to_s)
    @script_version = Crm::CevicoScript.normalize_version(
      script_version.presence || conversation.additional_attributes&.[]('cevico_simulado_script')
    )
  end

  def call # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return { error: 'Agente desligado.' } if agent_paused? && !@simulation
    return { error: missing_key_error } if engine_api_key.blank?

    transcript = build_transcript
    return { error: 'Conversa vazia.' } if transcript.blank?

    # 🧠 item 399: o MODELO escolhido decide o motor (gpt-… = OpenAI; o resto = Claude)
    result = openai_engine? ? openai_reply_or_fallback(transcript) : anthropic_reply(transcript)
    return result if result[:error]

    result[:acoes] = tools ? tools.acoes : []
    result[:modelo] = model
    result[:reserva] = @fallback_reason if @fallback_reason
    result
  rescue JSON::ParserError
    { error: 'Resposta da IA fora do formato.' }
  rescue StandardError => e
    Rails.logger.error "[Crm::ResponderAgent##{@agent_key}] #{e.class}: #{e.message}"
    { error: e.message }
  end

  # 🧰 22/11: a resposta à pessoa como ferramenta (strict = a API confere o esquema)
  def answer_tool_definition
    {
      name: ANSWER_TOOL_NAME,
      description: 'RESPOSTA FINAL: é por aqui que você responde à pessoa desta conversa, com todos os campos do formato. ' \
                   'Chame UMA vez, no fim. Use outra ferramenta antes SÓ quando a última mensagem da pessoa pede um dado ' \
                   'ou uma ação dela agora; sem isso, chame direto esta.',
      input_schema: output_schema,
      strict: true
    }
  end

  # 👓 08/11: o esquema da resposta com as UNIDADES DESTA CONTA (a ótica tem a
  # sua loja; a clínica segue com tatuape/paulista)
  def output_schema
    schema = OUTPUT_SCHEMA.deep_dup
    schema[:properties][:agendamento][:properties][:unidade] = { type: 'string', enum: Crm::AgendaSlots.unit_labels(@account).keys }
    schema
  end

  def otica?
    @otica = Crm::AgendaSlots.otica?(@account) if @otica.nil?
    @otica
  end

  # quais modelos este agente pode usar (Claude sempre; ChatGPT só os atendentes do WhatsApp)
  def engine_models
    MODELS + (Crm::LlmEngines.openai_agent?(@agent_key) ? Crm::LlmEngines::OPENAI_MODELS.keys : [])
  end

  # 🧪 item 400: variante do teste A/B de motor desta conversa ('a' | 'b' | nil).
  # Só conversa REAL entra (o 🧪 Testar agente tem o seletor de motor dele). Se a
  # variante B é do ChatGPT e a chave da OpenAI sumiu, a conversa fica FORA do
  # teste (segue no modelo do cartão e não suja o placar).
  def experiment_arm
    return @experiment_arm if defined?(@experiment_arm)

    @experiment_arm = resolve_experiment_arm
  end

  # o prompt completo, visível na tela do agente ("o que ele lê")
  def system_prompt
    return voice_system_prompt if voice?

    "#{Crm::CevicoScript.text(@account, @script_version)}\n\n== SUA ETAPA ==\n" \
      "#{Crm::CevicoScript.stage_prompt(@account, @agent_key, @script_version)}#{RESPONDER_GUARDRAIL}"
  end

  private

  # (#100) cliente da IA dos RESPONDEDORES: 90 s por chamada e só 1 nova
  # tentativa (o padrão do Crm::AiAgentConfig é 300 s × 3 tentativas, feito
  # para o Copywriter/Construtor gerar páginas inteiras). Quem responde
  # paciente não pode segurar a conversa por meia hora: o retry_later do job
  # (item 291) já cobre o erro passageiro, e a trava por conversa expira em
  # Crm::ResponderAgentJob::LOCK_TTL (conta feita em cima desses números).
  def client
    @client ||= Anthropic::Client.new(api_key: api_key, timeout: 90, max_retries: 1)
  end

  # ── MOTOR CLAUDE (Anthropic) — o de sempre ───────────────────────────────
  # 🧰 ótica (22/11): com ferramentas, a resposta chega pela ferramenta `responder`
  # (answer_with_tools); sem ferramentas, direto no formato (answer_in_format)
  def anthropic_reply(transcript)
    params = { model: model, max_tokens: 2048, system_: cached_system,
               messages: [{ role: 'user', content: user_content(transcript) }] }
    tools ? answer_with_tools(params) : answer_in_format(params)
  end

  # ── MOTOR CHATGPT (OpenAI, item 399) ─────────────────────────────────────
  # Mesmo prompt, mesmo contexto, mesmas ferramentas e mesmo formato de saída
  # do Claude: só muda quem pensa. Ordem da entrada = prompt → conversa →
  # contexto vivo (o que repete fica na frente e a OpenAI guarda em cache).
  def openai_engine?
    @fallback_model.nil? && Crm::LlmEngines.openai?(model)
  end

  def openai_api_key
    ai_config[Crm::LlmEngines::OPENAI_KEY].presence
  end

  def engine_api_key
    openai_engine? ? openai_api_key : api_key
  end

  def missing_key_error
    return 'Configure a chave da OpenAI em Integrações → ChatGPT.' if openai_engine?

    'Configure a chave da API em Integrações → Claude.'
  end

  # 🛟 REDE DE SEGURANÇA: paciente não fica sem resposta por causa do experimento.
  # Se a OpenAI falhar (fora do ar, sem créditos, chave revogada) numa conversa
  # REAL, o Claude recomendado do agente responde aquela mensagem e fica anotado
  # (result[:reserva]). Só vale se nenhuma ferramenta rodou ainda (não repete
  # remarcação/cancelamento) e nunca no 🧪 teste (lá o erro tem que aparecer).
  def openai_reply_or_fallback(transcript) # rubocop:disable Metrics/CyclomaticComplexity
    openai_reply(transcript)
  rescue Crm::LlmEngines::OpenaiResponses::Error => e
    raise if @simulation || api_key.blank? || tools&.acoes&.any?

    Rails.logger.warn "[Crm::ResponderAgent##{@agent_key}] ChatGPT falhou (#{e.message}) — o Claude responde no lugar"
    @fallback_reason = "ChatGPT falhou (#{e.message.truncate(80)}); o Claude respondeu no lugar"
    @fallback_model = recommended['model'] || DEFAULT_MODEL
    anthropic_reply(transcript)
  end

  # devolve o Hash da resposta, como o motor Claude. Na ótica o esquema leva as
  # unidades da conta (output_schema) e chamada repetida não roda de novo (22/11)
  def openai_reply(transcript) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    engine = Crm::LlmEngines::OpenaiResponses.new(api_key: openai_api_key, model: model, effort: effort)
    definitions = tools ? Crm::LlmEngines::OpenaiResponses.tool_definitions(tools.definitions) : nil
    input = [
      { role: 'developer', content: system_prompt },
      { role: 'user', content: user_content(transcript).map { |block| { type: 'input_text', text: block[:text] } } }
    ]
    seen = Set.new

    reply = nil
    (MAX_TOOL_ROUNDS + 1).times do |round|
      reply = engine.create(input: input, schema: output_schema, schema_name: 'resposta_do_atendente',
                            tools: definitions, allow_tools: round < MAX_TOOL_ROUNDS)
      record_openai_usage(reply.usage)
      break if tools.nil? || reply.tool_calls.empty?

      # a resposta volta inteira (raciocínio cifrado + pedidos) e, em seguida, o resultado de cada ferramenta
      input += reply.items
      reply.tool_calls.each do |call|
        input << { type: 'function_call_output', call_id: call['call_id'], output: openai_tool_output(call, seen) }
      end
    end
    return { error: 'Resposta vazia da IA.' } if reply.text.blank?

    JSON.parse(reply.text).symbolize_keys
  end

  # no ChatGPT não existe a ferramenta `responder` (a resposta final já sai no
  # formato pedido): os avisos que mandam "responder pela ferramenta" são trocados
  def openai_tool_output(call, seen)
    args = openai_arguments(call)
    outcome = if seen.add?("#{call['name']}:#{args.to_json}")
                tools.call(call['name'], args)
              else
                { ok: false, repetida: true, motivo: REPEATED_CALL_TEXT }
              end
    outcome.to_json.gsub(OPENAI_ANSWER_HINT, 'responda no formato da resposta final')
  end

  # os argumentos chegam como TEXTO em JSON; texto quebrado = sem argumentos
  # (a ferramenta responde ok=false e a IA corrige na volta seguinte)
  def openai_arguments(call)
    parsed = JSON.parse(call['arguments'].presence || '{}')
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  # tokens + custo da chamada no "Gasto da IA" (tabela de preços em Crm::LlmEngines)
  def record_openai_usage(usage)
    cost = Crm::LlmEngines.openai_cost(model, usage)
    @spent_usd += cost[:cost]
    Rails.logger.info("[Crm::AiUsage] #{agent_key} #{model} entrada=#{cost[:input]} cache_lido=#{cost[:read]} " \
                      "saida=#{cost[:output]} US$#{cost[:cost].round(4)}")
    Crm::AiUsage.create!(account: @account, agent_key: agent_key, model: model, input_tokens: cost[:input], output_tokens: cost[:output],
                         cache_read_tokens: cost[:read], cache_write_tokens: cost[:written], cost_usd: cost[:cost].round(6))
  rescue StandardError => e
    Rails.logger.warn "[Crm::AiUsage] falhou ao registrar: #{e.message}"
  end

  # modelo do respondedor: o do teste (🧪) > ChatGPT escolhido no cartão > a
  # regra de sempre do Crm::AiAgentConfig (escolha > recomendado > global)
  def model
    return @fallback_model if @fallback_model
    return @model_override if @model_override
    return experiment_model_b if experiment_arm == 'b'

    chosen = agent_config['model'].presence
    return super unless Crm::LlmEngines.openai?(chosen)
    return chosen if Crm::LlmEngines.openai_agent?(@agent_key)

    # modelo gpt gravado em agente que não pode usar a OpenAI: volta ao recomendado dele
    recommended['model'] || DEFAULT_MODEL
  end

  # 🧪 item 400: o modelo da variante B, se este agente pode usá-lo agora
  def experiment_model_b
    candidate = Crm::EngineExperiment.active(agent_config)&.dig('model_b').to_s
    return nil unless engine_models.include?(candidate)
    return nil if Crm::LlmEngines.openai?(candidate) && openai_api_key.blank?

    candidate
  end

  def resolve_experiment_arm
    return nil if @simulation || !Crm::LlmEngines.openai_agent?(@agent_key)

    arm = Crm::EngineExperiment.arm_for(@conversation, @agent_key, agent_config)
    arm == 'b' && experiment_model_b.nil? ? nil : arm
  end

  # soma o custo da chamada do Claude no total desta resposta (item 400)
  def record_usage(message)
    row = super
    @spent_usd += row.cost_usd.to_f if row.is_a?(Crm::AiUsage)
    row
  end

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

    @tools ||= Crm::ResponderTools.new(conversation: @conversation, agent_key: @agent_key, live: @live,
                                       otica_live: @otica_live, simulation: @simulation)
  end

  # sem ferramentas (instagram, comentários): uma chamada, JSON obrigatório
  def answer_in_format(params)
    message = create_message(params.merge(output_config: output_config_for(json_format)))
    parse_answer_text(message)
  end

  # 🧰 22/11: voltas de ferramenta SEM formato obrigatório, uma ferramenta por vez;
  # a resposta chega pela ferramenta `responder`. Chamada repetida (mesma ferramenta,
  # mesmos dados) na mesma resposta não roda de novo.
  def answer_with_tools(params) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    params = params.merge(tools: tools.definitions + [answer_tool_definition],
                          tool_choice: { type: 'auto', disable_parallel_tool_use: true })
    effort_only = output_config_for(nil).except(:format)
    params[:output_config] = effort_only if effort_only.any?
    seen = Set.new

    MAX_TOOL_ROUNDS.times do
      message = create_message(params)
      uses = message.content.select { |block| block.type == :tool_use }
      answer = uses.find { |use| use.name == ANSWER_TOOL_NAME }
      return answer_from_tool(answer) if answer
      break if message.stop_reason != :tool_use || uses.empty?

      params[:messages] << { role: 'assistant', content: assistant_content(message) }
      params[:messages] << { role: 'user', content: uses.map { |use| tool_result_block(use, seen) } }
    end

    # terminou em texto solto ou passou do teto: a última volta escreve no formato, sem ferramentas
    final = create_message(params.merge(tool_choice: { type: 'none' }, output_config: output_config_for(json_format)))
    parse_answer_text(final)
  end

  def json_format
    { type: 'json_schema', schema: output_schema }
  end

  def create_message(params)
    message = client.messages.create(**params)
    record_usage(message)
    message
  end

  def answer_from_tool(block)
    JSON.parse((block.input || {}).to_h.to_json).symbolize_keys
  end

  def parse_answer_text(message)
    text = message.content.find { |block| block.type == :text }&.text
    return { error: 'Resposta vazia da IA.' } if text.blank?

    JSON.parse(text).symbolize_keys
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

  def tool_result_block(use, seen = Set.new)
    signature = "#{use.name}:#{(use.input || {}).to_h.to_json}"
    outcome = if seen.add?(signature)
                tools.call(use.name, use.input)
              else
                { ok: false, repetida: true, motivo: REPEATED_CALL_TEXT }
              end
    { type: 'tool_result', tool_use_id: use.id, content: outcome.to_json }
  end

  # contexto vivo: agora, contato, coluna, vagas reais, consulta futura
  def context_block # rubocop:disable Metrics/CyclomaticComplexity
    now = Crm::AgendaSlots::TZ.now
    contact = @conversation.contact
    phone = contact&.phone_number.presence
    <<~CTX
      CONTEXTO (gerado pelo sistema agora):
      - Agora: #{Crm::AgendaSlots::WEEKDAYS[now.wday]}, #{now.strftime('%d/%m/%Y %H:%M')} (São Paulo). Use esta data para "hoje", "amanhã", "semana que vem". Nunca aceite data no passado.
      - Paciente (cadastro): #{contact&.name.presence || 'sem nome'} · telefone deste WhatsApp: #{phone || 'desconhecido (peça o número antes de agendar)'}
      - Coluna do paciente no CRM: #{card_stage_name || 'sem card (contato novo)'}
      - Consulta futura já marcada: #{future_appointment_text}
      #{OTHER_PERSON_RULE unless voice?}
      #{"- Motivo da ligação: #{call_objective}\n" if voice?}#{pos_op? ? (otica? ? otica_order_context : pos_op_context) : ''}
      HORÁRIOS DISPONÍVEIS (vagas LIVRES reais das próximas 4 semanas; ofereça no máximo 2 por vez, só destes; para um dia específico fora desta lista use a ferramenta horarios_do_dia — agendamento futuro é liberado):#{slots_note}
      #{Crm::AgendaSlots.free_slots_text(@account, days: 28, per_window: 3, modality: slots_modality)}
      #{otica_slots_block}

      #{Crm::AgendaSlots.rules_block(@account)}
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

  # 👓 08/11: na ótica a visita COM EXAME tem faixa própria (sábado, Fabi) e a
  # RETIRADA do óculos (pós-compra) também — cada uma com a sua lista de vagas
  def otica_slots_block
    return '' unless otica?

    parts = []
    if Crm::AgendaSlots.dedicated_windows?(@account, 'exame')
      parts << "HORÁRIOS DE EXAME DE VISTA (faixa exclusiva do exame; toda visita COM exame é marcada SÓ nestes horários, com procedimento \"Visita com exame\"; " \
               "a lista de cima serve só para visita SEM exame):\n" \
               "#{Crm::AgendaSlots.free_slots_text(@account, days: 28, per_window: 4, modality: 'exame')}"
    end
    if pos_op?
      parts << "HORÁRIOS PARA RETIRADA DO ÓCULOS (marque com procedimento \"Retirada do óculos\"):\n" \
               "#{Crm::AgendaSlots.free_slots_text(@account, days: 14, per_window: 3, modality: 'entrega')}"
    end
    parts.join("\n\n")
  end

  # 👓 08/11: o Atendente Pós-compra da ótica precisa saber do PEDIDO (O.S.):
  # em que etapa está, prazo, lentes no laboratório, pronto desde quando
  def otica_order_context
    cfg = Crm::NpsSurvey.config(@account)
    lines = ["- Pedido do cliente (O.S.): #{Otica::OrderWatch.summary_for(@conversation.contact)}"]
    nps = Crm::NpsSurvey.context_text(@conversation.contact)
    lines << "- Pesquisa de satisfação (NPS): #{nps}" if nps
    lines << "- Link para avaliar no Google: #{cfg['google_review_url']}" if cfg['google_review_url'].present?
    "#{lines.join("\n")}\n"
  end

  # 🩺 item 251: o Atendente de Pós-operatório precisa saber QUAL cirurgia e há
  # quantos dias — a orientação muda (PRK × LASIK, 2 dias × 20 dias)
  def pos_op?
    @agent_key == 'atendente_pos_op'
  end

  # item 256: cirurgia + pesquisa de satisfação + links oficiais (Google e formulário)
  def pos_op_context
    cfg = Crm::NpsSurvey.config(@account)
    lines = ["- Cirurgia realizada: #{surgery_text}"]
    nps = Crm::NpsSurvey.context_text(@conversation.contact)
    lines << "- Pesquisa de satisfação (NPS): #{nps}" if nps
    lines << "- Link para avaliar no Google: #{cfg['google_review_url']}" if cfg['google_review_url'].present?
    lines << "- Formulário de relato (notas baixas): #{cfg['complaint_form_url']}" if cfg['complaint_form_url'].present?
    "#{lines.join("\n")}\n"
  end

  SURGERY_UNKNOWN = 'não encontrada na Agenda (pergunte qual cirurgia e quando foi)'.freeze

  def surgery_text # rubocop:disable Metrics/AbcSize
    task = last_surgery_task
    return SURGERY_UNKNOWN if task.blank?

    at = task.due_at.in_time_zone(Crm::AgendaSlots::TZ)
    days = (Crm::AgendaSlots::TZ.now.to_date - at.to_date).to_i
    parts = ["#{at.strftime('%d/%m/%Y')} (há #{days} dia#{'s' unless days == 1})", task.procedure.presence, task.doctor.presence,
             Crm::AgendaSlots.unit_label(@account, task.unit.to_s) || task.unit.presence]
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

  def future_task
    return @future_task if defined?(@future_task)

    contact = @conversation.contact
    @future_task = Crm::AppointmentRecorder.future_appointment(@account, contact&.phone_number, nil, contact)
  end

  # item 307: paciente com RETORNO ou PÓS-OPERATÓRIO marcado recebe os horários
  # das faixas desse tipo (a remarcação não cai no período das consultas novas)
  def slots_modality
    Crm::AgendaSlots.slot_modality(future_task)
  end

  def slots_note
    return '' if slots_modality == Crm::AgendaSlots::AI_MODALITY

    "\n(o paciente tem #{Crm::AgendaSlots::MODALITY_LABELS[slots_modality]} marcado — a lista abaixo é das faixas desse tipo de atendimento)"
  end

  def future_appointment_text
    task = future_task
    return 'nenhuma' if task.blank?

    when_at = task.due_at.in_time_zone(Crm::AgendaSlots::TZ)
    unit = Crm::AgendaSlots.unit_label(@account, task.unit) || task.unit
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
