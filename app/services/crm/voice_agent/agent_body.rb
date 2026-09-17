# Corpo de criação/atualização do agente na ElevenLabs (POST
# /v1/convai/agents/create e PATCH /v1/convai/agents/{id}): persona, LLM,
# ferramentas (ids já criados), ferramentas de sistema (encerrar /
# transferir), voz, limites, e os webhooks pós-chamada e de início.
# Campos e nomes seguem a OpenAPI oficial (verificada em 17/09).
module Crm::VoiceAgent::AgentBody
  TEMPERATURE = 0.3
  TURN_TIMEOUT = 7
  # variáveis dinâmicas com valor padrão vazio: ligação recebida sem o
  # webhook de início não pode falhar por variável ausente no prompt
  DYNAMIC_PLACEHOLDERS = { 'paciente_nome' => '', 'primeiro_nome' => '', 'proxima_consulta' => '',
                           'campanha_objetivo' => '', 'telefone' => '' }.freeze

  module_function

  def build(account, settings, tool_ids:, webhook_id: nil)
    {
      name: settings.agent_name,
      conversation_config: conversation_config(account, settings, tool_ids),
      platform_settings: platform_settings(settings, webhook_id || settings.webhook_id)
    }
  end

  def conversation_config(account, settings, tool_ids)
    {
      agent: {
        first_message: settings.first_message, language: settings.language,
        dynamic_variables: { dynamic_variable_placeholders: DYNAMIC_PLACEHOLDERS },
        prompt: {
          prompt: Crm::VoiceAgent::Script.build(account, settings), llm: settings.llm, temperature: TEMPERATURE,
          tool_ids: Array(tool_ids), built_in_tools: built_in_tools(settings)
        }
      },
      tts: { voice_id: settings.voice_id, model_id: settings.tts_model, stability: 0.5, similarity_boost: 0.8 }.compact,
      turn: { turn_timeout: TURN_TIMEOUT },
      conversation: { max_duration_seconds: settings.max_duration_seconds }
    }
  end

  # end_call sempre; transfer_to_number só quando há número da equipe
  def built_in_tools(settings)
    tools = { end_call: { type: 'system', name: 'end_call', params: { system_tool_type: 'end_call' } } }
    return tools if settings.transfer_number.blank?

    tools[:transfer_to_number] = {
      type: 'system', name: 'transfer_to_number',
      params: {
        system_tool_type: 'transfer_to_number',
        transfers: [{ transfer_destination: { type: 'phone', phone_number: settings.transfer_number },
                      condition: settings.transfer_condition, transfer_type: 'conference' }]
      }
    }
    tools
  end

  def platform_settings(settings, webhook_id)
    workspace = {
      conversation_initiation_client_data_webhook: {
        url: settings.initiation_url, request_headers: { 'X-Cevico-Token' => settings.tools_token.to_s }
      }
    }
    workspace[:webhooks] = { post_call_webhook_id: webhook_id, events: %w[transcript audio] } if webhook_id.present?
    {
      workspace_overrides: workspace,
      overrides: {
        conversation_config_override: { agent: { first_message: true, language: true, prompt: { prompt: true } } },
        enable_conversation_initiation_client_data_from_webhook: true
      },
      call_limits: { daily_limit: settings.daily_limit }
    }
  end
end
