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
  RESPONDER_TOOLS_KEYS = %w[atendente_agendamento atendente_pos atendente_pos_op voice].freeze

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

  # spent_usd (item 400): quanto ESTA resposta custou, somando todas as chamadas
  attr_reader :agent_key, :script_version, :spent_usd

  # live: false (sombra/simulador) = nenhuma ferramenta escreve na Agenda
  # simulation: true = 🧪 Testar agente (caixa interna, nada sai): roda MESMO com o
  # interruptor desligado — o teste é justamente para antes de ligar (pedido 21/09)
  # script_version (22/09): 'v1' (oficial) ou 'v2' (Roteiro paralelo). Sem
  # informar, vale o que a conversa de teste guardou ao nascer; conversa real = v1.
  # model_override (item 399): SÓ no 🧪 Testar agente — experimenta outro motor
  # (Claude ou ChatGPT) na conversa de teste sem mexer no que o agente usa de verdade
  def initialize(conversation:, agent_key:, live: false, simulation: false, script_version: nil, model_override: nil) # rubocop:disable Metrics/ParameterLists
    @conversation = conversation
    @account = conversation.account
    @spent_usd = 0.0
    @agent_key = agent_key.to_s
    @live = live == true
    @simulation = simulation == true
    @model_override = model_override.to_s if @simulation && engine_model?(model_override.to_s)
    @script_version = Crm::CevicoScript.normalize_version(
      script_version.presence || conversation.additional_attributes&.[]('cevico_simulado_script')
    )
    # 🧪 item 403: conversa REAL dentro de um teste A/B lê o Roteiro da variante dela
    @script_version = Crm::EngineExperiment.script_for(Crm::EngineExperiment.active(agent_config), experiment_arm) if experiment_arm
  end

  def call # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return { error: 'Agente desligado.' } if agent_paused? && !@simulation
    return { error: missing_key_error } if engine_api_key.blank?

    transcript = build_transcript
    return { error: 'Conversa vazia.' } if transcript.blank?

    # 🧠 item 399: o MODELO escolhido decide o motor (gpt-… = OpenAI; o resto = Claude)
    # 🧠 22/11: Gemini (ou qualquer outro modelo fora do Claude) pela tomada universal
    text = if openai_engine? then openai_reply_or_fallback(transcript)
           elsif gateway_engine? then gateway_reply_or_fallback(transcript)
           else claude_reply_or_reserve(transcript) # 🛟 23/11: Claude falhou → ChatGPT ou Gemini no lugar
           end
    return { error: 'Resposta vazia da IA.' } if text.blank?

    result = JSON.parse(text).symbolize_keys
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

  # 🧠 22/11: qualquer modelo dos 3 fornecedores (Claude, ChatGPT, Gemini)
  def engine_model?(candidate)
    MODELS.include?(candidate) || Crm::LlmCatalog.valid_id?(candidate)
  end

  # 🧪 itens 400/403: variante do teste A/B desta conversa ('a' | 'b' | nil).
  # Só conversa REAL entra (o 🧪 Testar agente tem os seletores dele). Se a
  # variante B pede um motor cuja chave sumiu, a conversa fica FORA do teste
  # (segue no oficial e não suja o placar).
  def experiment_arm
    return @experiment_arm if defined?(@experiment_arm)

    @experiment_arm = resolve_experiment_arm
  end

  # o prompt completo, visível na tela do agente ("o que ele lê")
  def system_prompt
    return voice_system_prompt if voice?

    "#{Crm::CevicoScript.text(@account, @script_version)}\n\n== SUA ETAPA ==\n" \
      "#{Crm::CevicoScript.stage_prompt(@account, @agent_key, @script_version)}#{motor_block}#{RESPONDER_GUARDRAIL}"
  end

  private

  # 🎓 item 389: aprendizados aprovados do Motor de Educação — só nas caixas
  # piloto e só no Roteiro 1 (o Roteiro 2 é laboratório à parte). 🧪 item 403:
  # numa conversa REAL do teste A/B as duas variantes recebem o mesmo bloco —
  # a única diferença entre elas tem que ser o que está sendo testado
  def motor_block
    return '' if @script_version != 'v1' && experiment_arm.nil?

    Crm::EducationEngine.prompt_block(@conversation, @agent_key).to_s
  end

  # (#100) cliente da IA dos RESPONDEDORES: 90 s por chamada e só 1 nova
  # tentativa (o padrão do Crm::AiAgentConfig é 300 s × 3 tentativas, feito
  # para o Copywriter/Construtor gerar páginas inteiras). Quem responde
  # paciente não pode segurar a conversa por meia hora: o retry_later do job
  # (item 291) já cobre o erro passageiro, e a trava por conversa expira em
  # Crm::ResponderAgentJob::LOCK_TTL (conta feita em cima desses números).
  def client
    @client ||= llm_client(timeout: 90, max_retries: 1)
  end

  # ── MOTOR CLAUDE (Anthropic) — o de sempre ───────────────────────────────
  def anthropic_reply(transcript) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
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

    message.content.find { |block| block.type == :text }&.text
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
    return 'Configure a chave da OpenAI em Integrações → ChatGPT.' if Crm::LlmCatalog.provider(model) == 'openai'
    return 'Configure a chave do Google em Integrações → Gemini.' if Crm::LlmCatalog.provider(model) == 'google'

    'Configure a chave da API em Integrações → Claude.'
  end

  # 🧠 22/11: modelo de fora do Claude que não é um dos 4 do motor ChatGPT
  # dedicado (Gemini, ou outro gpt digitado à mão) — vai pelo Crm::LlmGateway
  # com as mesmas ferramentas e o mesmo formato de saída do Claude
  def gateway_engine?
    @fallback_model.nil? && !Crm::LlmCatalog.anthropic?(model) && !Crm::LlmEngines.openai?(model)
  end

  def gateway_reply_or_fallback(transcript)
    anthropic_reply(transcript)
  rescue Crm::LlmGateway::Error => e
    claude_fallback!(e) { anthropic_reply(transcript) }
  end

  # 🛟 rede de segurança comum (ChatGPT e Gemini): ver openai_reply_or_fallback
  def claude_fallback!(error)
    raise error if @simulation || ai_config['api_key'].blank? || tools&.acoes&.any?

    engine = Crm::LlmCatalog::PROVIDERS.dig(Crm::LlmCatalog.provider(model), :label) || model
    Rails.logger.warn "[Crm::ResponderAgent##{@agent_key}] #{engine} falhou (#{error.message}) — o Claude responde no lugar"
    @fallback_reason = "#{engine} falhou (#{error.message.truncate(80)}); o Claude respondeu no lugar"
    @fallback_model = Crm::LlmCatalog.anthropic?(recommended['model']) ? recommended['model'] : DEFAULT_MODEL
    @client = nil
    yield
  end

  # 🛟 REDE DE SEGURANÇA: paciente não fica sem resposta por causa do experimento.
  # Se a OpenAI falhar (fora do ar, sem créditos, chave revogada) numa conversa
  # REAL, o Claude recomendado do agente responde aquela mensagem e fica anotado
  # (result[:reserva]). Só vale se nenhuma ferramenta rodou ainda (não repete
  # remarcação/cancelamento) e nunca no 🧪 teste (lá o erro tem que aparecer).
  def openai_reply_or_fallback(transcript)
    openai_reply(transcript)
  rescue Crm::LlmEngines::OpenaiResponses::Error => e
    claude_fallback!(e) { anthropic_reply(transcript) }
  end

  # ── 🛟 MOTOR RESERVA DO CLAUDE (23/11, atendimento sem buraco) ───────────
  # O sentido que faltava: quando o motor principal é o Claude e a chamada
  # falha (limite de uso da chave, serviço fora do ar, rede), outro fornecedor
  # responde AQUELA mensagem na mesma hora: primeiro o ChatGPT, depois o
  # Gemini, cada um só se a chave dele estiver salva. Em 23/11 a chave da
  # Anthropic bateu no limite e todo paciente ficou sem resposta.
  # Sem laço: cada reserva é tentada UMA vez e o erro dela não chama outra
  # rede de segurança (aqui dentro o Claude já está fora do jogo). Mesmas
  # cercas do sentido inverso: nunca no 🧪 teste (o erro tem que aparecer) e
  # nunca depois de uma ferramenta já ter rodado (não repete remarcação).
  # Desliga com ai_config['responder_engine_reserve'] = false; os modelos
  # podem ser trocados em responder_reserve_openai_model / _gemini_model.
  # Tempo: uma queda rápida (erro 400/429) cabe com folga na trava da conversa;
  # o pior caso teórico (três motores estourando o tempo) passa dela e o
  # resgate cobre.
  RESERVE_MODELS = { 'openai' => 'gpt-6.2-sol', 'google' => 'gemini-4-carbon' }.freeze
  RESERVE_MODEL_KEYS = { 'openai' => 'responder_reserve_openai_model', 'google' => 'responder_reserve_gemini_model' }.freeze

  def claude_reply_or_reserve(transcript)
    anthropic_reply(transcript)
  rescue Anthropic::Errors::APIError => e
    reserve_reply!(e, transcript)
  end

  def reserve_reply!(error, transcript)
    candidates = reserve_models
    raise error if @simulation || candidates.empty? || tool_ran?

    failures = ["#{provider_label(model)} falhou (#{error.message.to_s.truncate(60)})"]
    candidates.each do |candidate|
      return reserve_attempt(candidate, transcript, failures)
    rescue Crm::LlmEngines::OpenaiResponses::Error, Anthropic::Errors::APIError => e
      @fallback_reason = nil
      failures << "#{provider_label(candidate)} também (#{e.message.to_s.truncate(60)})"
      break if tool_ran? # uma ferramenta já rodou: não repete com o próximo
    end
    raise StandardError, failures.join('; ')
  end

  def reserve_attempt(candidate, transcript, failures)
    Rails.logger.warn "[Crm::ResponderAgent##{@agent_key}] #{failures.join('; ')} — #{provider_label(candidate)} responde no lugar"
    @fallback_reason = "#{failures.join('; ')}; #{provider_label(candidate)} respondeu no lugar"
    @fallback_model = candidate
    @client = nil
    # os 4 modelos do motor ChatGPT dedicado vão por ele; o resto (Gemini) pela tomada universal
    Crm::LlmEngines.openai?(candidate) ? openai_reply(transcript) : anthropic_reply(transcript)
  end

  # alguma ferramenta (buscar, remarcar, cancelar…) já rodou nesta resposta?
  def tool_ran?
    tools&.acoes&.any? == true
  end

  # reservas que podem rodar AGORA (chave do fornecedor salva), na ordem: ChatGPT, Gemini
  def reserve_models
    return [] if ai_config['responder_engine_reserve'] == false

    RESERVE_MODELS.filter_map do |provider, default|
      chosen = ai_config[RESERVE_MODEL_KEYS[provider]].to_s.strip
      candidate = Crm::LlmCatalog.valid_id?(chosen) && Crm::LlmCatalog.provider(chosen) == provider ? chosen : default
      candidate if Crm::LlmCatalog.usable?(ai_config, candidate)
    end
  end

  def provider_label(model_id)
    Crm::LlmCatalog::PROVIDERS.dig(Crm::LlmCatalog.provider(model_id), :label) || model_id
  end

  def openai_reply(transcript) # rubocop:disable Metrics/AbcSize
    engine = Crm::LlmEngines::OpenaiResponses.new(api_key: openai_api_key, model: model, effort: effort)
    definitions = tools ? Crm::LlmEngines::OpenaiResponses.tool_definitions(tools.definitions) : nil
    input = [
      { role: 'developer', content: system_prompt },
      { role: 'user', content: user_content(transcript).map { |block| { type: 'input_text', text: block[:text] } } }
    ]

    reply = nil
    (MAX_TOOL_ROUNDS + 1).times do |round|
      reply = engine.create(input: input, schema: OUTPUT_SCHEMA, schema_name: 'resposta_do_atendente',
                            tools: definitions, allow_tools: round < MAX_TOOL_ROUNDS)
      record_openai_usage(reply.usage)
      break if tools.nil? || reply.tool_calls.empty?

      # a resposta volta inteira (raciocínio cifrado + pedidos) e, em seguida, o resultado de cada ferramenta
      input += reply.items
      reply.tool_calls.each do |call|
        input << { type: 'function_call_output', call_id: call['call_id'], output: tools.call(call['name'], openai_arguments(call)).to_json }
      end
    end
    reply.text
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
    return experiment_model_b if experiment_b_motor?

    # 🧭 23/11: motor POR COLUNA do CRM (Crm::StageEngine) > o modelo do cartão
    # 🧠 22/11: qualquer modelo dos 3 fornecedores, com a chave salva (Crm::AiAgentConfig#model)
    stage_model || super
  end

  # 🧭 23/11 (motor por coluna): o modelo escolhido para a coluna em que o card
  # deste paciente está, se ele pode rodar agora (id reconhecido + chave do
  # fornecedor salva). Só em conversa REAL: o 🧪 Testar agente tem o seletor
  # dele. Calculado uma vez por resposta (a coluna não muda no meio dela).
  def stage_model
    return @stage_model if defined?(@stage_model)

    @stage_model = resolve_stage_model
  end

  def resolve_stage_model
    return nil if @simulation || !Crm::LlmEngines.openai_agent?(@agent_key)

    candidate = Crm::StageEngine.model_for(@conversation, agent_config).to_s
    candidate if engine_model?(candidate) && model_runnable?(candidate)
  rescue StandardError => e
    Rails.logger.warn "[Crm::ResponderAgent##{@agent_key}] motor por coluna: #{e.message}"
    nil
  end

  # 🧪🧭 item 405: a variante B troca o motor NESTA conversa? Só se ela tem
  # motor próprio e a coluna do card está entre as escolhidas para a troca
  # (sem colunas escolhidas = em todas). Fora disso a B segue o mesmo mapa de
  # motor por coluna da A — é o que deixa o teste de prompt limpo.
  def experiment_b_motor?
    experiment_arm == 'b' && experiment_model_b.present? &&
      Crm::EngineExperiment.model_b_here?(Crm::EngineExperiment.active(agent_config), @conversation)
  end

  # 🧪 item 400: o modelo da variante B, se este agente pode usá-lo agora.
  # 🧪 item 403: em branco = a B usa o MESMO motor da A (teste só de prompt)
  def experiment_model_b
    return @experiment_model_b if defined?(@experiment_model_b)

    candidate = Crm::EngineExperiment.active(agent_config)&.dig('model_b').to_s
    @experiment_model_b = candidate.present? && engine_model?(candidate) && model_runnable?(candidate) ? candidate : nil
  end

  def resolve_experiment_arm
    return nil if @simulation || !Crm::LlmEngines.openai_agent?(@agent_key)

    experiment = Crm::EngineExperiment.active(agent_config)
    arm = Crm::EngineExperiment.arm_for(@conversation, @agent_key, agent_config)
    # a B pede um motor que não dá para usar agora: conversa fora do teste
    arm == 'b' && experiment['model_b'].present? && experiment_model_b.nil? ? nil : arm
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
      #{attention_lines}
      #{OTHER_PERSON_RULE unless voice?}
      #{"- Motivo da ligação: #{call_objective}\n" if voice?}#{pos_op_context if pos_op?}
      HORÁRIOS DISPONÍVEIS (vagas LIVRES reais das próximas 4 semanas; ofereça no máximo 2 por vez, só destes; para um dia específico fora desta lista use a ferramenta horarios_do_dia — agendamento futuro é liberado):#{slots_note}
      #{Crm::AgendaSlots.free_slots_text(@account, days: 28, per_window: 3, modality: slots_modality)}

      #{Crm::AgendaSlots.rules_block(@account)}
    CTX
  end

  # ── 🔁 23/11 (atendimento sem buraco): avisos de SITUAÇÃO para o modelo ────
  # Só ao vivo (sombra e 🧪 teste seguem iguais). Duas situações:
  # 1) a IA chamou a equipe, ninguém respondeu no prazo e ela voltou a atender
  #    (Crm::ResponderPause deixa a marca handoff_pending na conversa);
  # 2) o paciente está esperando há mais de 15 min (motor fora do ar, pausa
  #    que venceu, mensagem fora do horário): pede desculpas em meia frase e
  #    continua de onde parou. Só fala em "instabilidade do sistema" quando
  #    houve mesmo erro do motor registrado para aquela espera; nos outros
  #    casos pede desculpas pela demora sem inventar motivo.
  LATE_AFTER = 15.minutes
  HANDOFF_PENDING_LINE = '- ATENÇÃO: você já encaminhou este assunto para a equipe e ninguém respondeu ainda. Não prometa de novo ' \
                         'que a equipe vai responder; resolva o que estiver ao seu alcance com o roteiro e ofereça o próximo passo.'.freeze
  LATE_TAIL = 'e continue do ponto exato em que a conversa estava, sem se apresentar de novo se já se apresentou e sem recomeçar.'.freeze
  FIRST_CONTACT_TAIL = ' Como este é o primeiro contato do paciente (ele ainda não recebeu nenhuma resposta nossa), faça a recepção ' \
                       'normal do roteiro logo depois do pedido de desculpas.'.freeze

  def attention_lines
    return '' unless @live && !voice?

    [(HANDOFF_PENDING_LINE if Crm::ResponderPause.handoff_pending?(@conversation)), late_reply_line].compact.join("\n")
  rescue StandardError => e
    Rails.logger.warn "[Crm::ResponderAgent##{@agent_key}] avisos de situação: #{e.message}"
    ''
  end

  # mensagens do paciente ainda SEM resposta (depois da última fala da
  # clínica), só das últimas 24 h: [[id, hora], …] + se é o primeiro contato
  def unanswered_incoming
    messages = @conversation.messages.where(private: false)
    last_out = messages.where(message_type: :outgoing).maximum(:id)
    waiting = messages.where(message_type: :incoming).where('id > ?', last_out.to_i).where('created_at > ?', 24.hours.ago)
                      .order(:id).limit(20).pluck(:id, :created_at)
    [waiting, last_out.nil?]
  end

  # De quando contar o atraso: se o motor FALHOU em alguma mensagem ainda sem
  # resposta (desfecho 'erro' gravado pelo job), conta da mais antiga delas e a
  # causa é instabilidade; senão conta da última mensagem do paciente (a que
  # está sendo respondida) e o pedido de desculpas não inventa motivo.
  def late_reply_line
    waiting, first_contact = unanswered_incoming
    return nil if waiting.empty?

    failed = waiting.find { |id, _| Crm::ResponderAgentJob.outcome(id) == 'erro' }
    waited = Time.current - (failed || waiting.last).last
    return nil if waited < LATE_AFTER

    opening = if failed
                "- ATENÇÃO: esta resposta está saindo com atraso de #{waited_text(waited)} por uma instabilidade do nosso sistema. " \
                  "Comece com um pedido de desculpas em meia frase (ex.: 'Desculpa a demora, tivemos uma instabilidade no sistema e " \
                  "só agora consegui te responder.')"
              else
                "- ATENÇÃO: esta resposta está saindo com atraso de #{waited_text(waited)}. Comece com um pedido de desculpas em " \
                  "meia frase (ex.: 'Desculpa a demora, só agora consegui te responder.'), sem inventar motivo para a demora,"
              end
    "#{opening} #{LATE_TAIL}#{FIRST_CONTACT_TAIL if first_contact}"
  end

  # "25 minutos" · "1 hora" · "3 horas e 20 minutos"
  def waited_text(seconds)
    minutes = (seconds / 60).round
    return "#{minutes} minutos" if minutes < 60

    hours, rest = minutes.divmod(60)
    text = "#{hours} hora#{'s' unless hours == 1}"
    rest >= 5 ? "#{text} e #{rest} minutos" : text
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
