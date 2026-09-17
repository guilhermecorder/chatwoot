# As 6 ferramentas (webhooks) que a assistente virtual chama durante a
# ligação, no formato tool_config da ElevenLabs. Cada uma aponta para
# /webhooks/cevico/voice/<conta>/tools/<nome> com o token da conta no
# header X-Cevico-Token. Campos com dynamic_variable são preenchidos pela
# própria ElevenLabs (telefone de quem ligou, id da conversa) — a IA só
# preenche o resto.
module Crm::VoiceAgent::ToolDefinitions
  UNIT_DESCRIPTION = 'Unidade da clínica: "tatuape" ou "paulista".'.freeze
  OUTCOMES = %w[agendou remarcou cancelou quer_whatsapp sem_interesse recado transferido outro].freeze

  module_function

  # todas as ferramentas → [tool_config, …] (ordem de Settings::TOOL_NAMES)
  def all(_account, settings)
    Crm::VoiceAgent::Settings::TOOL_NAMES.map { |name| build(name, settings) }
  end

  def build(name, settings)
    spec = SPECS.fetch(name)
    {
      type: 'webhook', name: name, description: spec[:description], response_timeout_secs: 20,
      api_schema: {
        url: settings.tool_url(name), method: 'POST',
        request_headers: { 'X-Cevico-Token' => settings.tools_token.to_s },
        request_body_schema: { type: 'object', required: spec[:required], properties: spec[:properties] }
      }
    }
  end

  def phone_property
    { type: 'string', dynamic_variable: 'system__caller_id' }
  end

  def conversation_property
    { type: 'string', dynamic_variable: 'system__conversation_id' }
  end

  def text(description, enum: nil)
    prop = { type: 'string', description: description }
    prop[:enum] = enum if enum
    prop
  end

  SPECS = {
    'buscar_paciente' => {
      description: 'Busca o paciente pelo telefone: nome, próxima consulta marcada, etapa no funil e unidade preferida.',
      required: %w[telefone conversa_id],
      properties: { telefone: phone_property, conversa_id: conversation_property }
    },
    'horarios_livres' => {
      description: 'Horários realmente livres da agenda nos próximos dias (no máximo 6). Só ofereça horários que vierem daqui.',
      required: %w[conversa_id],
      properties: {
        unidade: text("#{UNIT_DESCRIPTION} Vazio = qualquer unidade."),
        medico: text('Nome do médico, se o paciente tiver preferência. Vazio = qualquer médico.'),
        dias: { type: 'integer', description: 'Quantos dias à frente procurar (padrão 7, máximo 30).' },
        periodo: text('Preferência do paciente: "manha" ou "tarde". Vazio = qualquer período.'),
        telefone: phone_property, conversa_id: conversation_property
      }
    },
    'marcar_consulta' => {
      description: 'Marca (ou remarca) a consulta DEPOIS de o paciente confirmar dia, horário, unidade e telefone em voz alta.',
      required: %w[nome data hora unidade conversa_id],
      properties: {
        nome: text('Nome completo do paciente, como ele falou.'),
        telefone_informado: text('Telefone que o paciente ditou, se for diferente do número da ligação (só dígitos).'),
        data: text('Data da consulta no formato AAAA-MM-DD (use o campo "data" devolvido por horarios_livres).'),
        hora: text('Horário no formato HH:MM (use o campo "hora" devolvido por horarios_livres).'),
        unidade: text(UNIT_DESCRIPTION),
        medico: text('Médico do horário escolhido (campo "medico" de horarios_livres).'),
        procedimento: text('Motivo/procedimento de interesse (ex.: cirurgia refrativa, catarata, consulta de rotina).'),
        observacoes: text('Qualquer observação útil para a equipe (opcional).'),
        telefone: phone_property, conversa_id: conversation_property
      }
    },
    'minha_consulta' => {
      description: 'Consulta já marcada do paciente (para confirmar, remarcar ou cancelar).',
      required: %w[telefone conversa_id],
      properties: { telefone: phone_property, conversa_id: conversation_property }
    },
    'enviar_whatsapp' => {
      description: 'Envia mensagem pelo WhatsApp da clínica: "confirmacao" (dados da consulta marcada), ' \
                   '"continuar" (paciente prefere seguir por escrito) ou "resumo" (texto livre que você montar).',
      required: %w[tipo conversa_id],
      properties: {
        tipo: text('Tipo da mensagem.', enum: %w[confirmacao continuar resumo]),
        texto: text('Texto da mensagem quando tipo = "resumo" (curto, sem emojis).'),
        telefone: phone_property, conversa_id: conversation_property
      }
    },
    'registrar_resultado' => {
      description: 'Registra o resultado da ligação. Chame SEMPRE antes de encerrar.',
      required: %w[resultado resumo conversa_id],
      properties: {
        resultado: text('Resultado da ligação.', enum: OUTCOMES),
        resumo: text('Resumo de uma ou duas frases do que foi combinado.'),
        telefone: phone_property, conversa_id: conversation_property
      }
    }
  }.freeze
end
