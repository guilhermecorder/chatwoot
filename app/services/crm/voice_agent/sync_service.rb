# "Sincronizar com a ElevenLabs": cria/atualiza tudo o que o agente
# precisa lá, em ordem e de forma idempotente (rodar de novo só atualiza):
#   1. webhook pós-chamada (HMAC) — só quando ainda não há segredo
#   2. as 6 ferramentas (cria as sem id, atualiza as com id)
#   3. o agente (cria ou atualiza)
#   4. amarra o número do WhatsApp ao agente e desliga mensagens de texto
# Cada passo vira uma linha humana no log (mostrado na tela); o erro para
# a sincronização e fica em state.last_error.
class Crm::VoiceAgent::SyncService
  attr_reader :account, :log

  def initialize(account)
    @account = account
    @log = []
  end

  def perform
    blocker = precheck
    return failure(blocker) if blocker

    sync_webhook
    sync_tools
    sync_agent
    sync_whatsapp_account
    settings.persist_state!(synced_at: Time.current.iso8601, last_error: nil, last_sync_log: log)
    result(true, nil)
  rescue Crm::VoiceAgent::Error => e
    failure(e.message)
  end

  private

  def settings
    @settings ||= Crm::VoiceAgent::Settings.new(account)
  end

  def client
    @client ||= Crm::VoiceAgent::Client.new(settings.api_key)
  end

  def precheck
    return 'Configure a chave da API da ElevenLabs antes de sincronizar.' if settings.api_key.blank?
    return 'Configure FRONTEND_URL público (as ferramentas e o webhook apontam para lá).' if settings.base_url.blank?

    nil
  end

  def failure(message)
    log << "❌ #{message}"
    settings.persist_state!(last_error: message, last_sync_log: log)
    result(false, message)
  end

  def result(success, error)
    { ok: success, log: log, error: error, voice: settings.to_h }
  end

  # o segredo só aparece na criação: se já temos, não recriamos o webhook
  def sync_webhook
    return log << "✅ Webhook pós-chamada já existe (#{settings.webhook_id})" if webhook_ready?

    created = client.create_webhook(name: "CEVICO pós-chamada · conta #{account.id}", url: settings.post_call_url)
    settings.persist!(webhook_id: created['webhook_id'], webhook_secret: created['webhook_secret'])
    settings.persist_state!(webhook_created_at: Time.current.iso8601)
    log << "✅ Webhook pós-chamada criado (#{created['webhook_id']}) → #{settings.post_call_url}"
  end

  def webhook_ready?
    settings.webhook_secret.present? && settings.webhook_id.present?
  end

  def sync_tools
    settings.persist!(tools_token: SecureRandom.hex(24)) if settings.tools_token.blank?
    ids = settings.tool_ids.dup
    configs = Crm::VoiceAgent::ToolDefinitions.all(account, settings)
    configs.each { |cfg| sync_tool(cfg, ids) }
  end

  # cada ferramenta grava o id na hora: uma falha no meio não perde as anteriores
  def sync_tool(cfg, ids)
    name = cfg[:name]
    if ids[name].present?
      client.update_tool(ids[name], cfg)
      log << "✅ Ferramenta #{name} atualizada (#{ids[name]})"
    else
      ids[name] = client.create_tool(cfg)['id']
      log << "✅ Ferramenta #{name} criada (#{ids[name]})"
    end
    settings.persist!(tool_ids: ids)
  end

  def sync_agent
    ensure_library_voice
    body = Crm::VoiceAgent::AgentBody.build(account, settings, tool_ids: settings.tool_ids.values)
    settings.agent_id.present? ? update_agent(body) : create_agent(body)
    log << '⚠️ Sem voz escolhida: a ElevenLabs usa a voz padrão. Escolha uma em Persona e voz.' if settings.voice_id.blank?
  end

  # voz escolhida na BIBLIOTECA (conta free sem vozes em português): o agente
  # só aceita voz da própria conta, então ela é adicionada aqui, uma vez
  def ensure_library_voice # rubocop:disable Metrics/AbcSize
    owner = settings.voice_public_owner_id
    return if owner.blank? || settings.voice_id.blank?
    return if client.own_voice?(settings.voice_id)

    client.add_library_voice(owner, settings.voice_id, settings.voice_name)
    log << "✅ Voz \"#{settings.voice_name || settings.voice_id}\" adicionada à conta (biblioteca)"
  rescue StandardError => e
    log << "⚠️ Não deu para adicionar a voz da biblioteca: #{e.message.to_s.truncate(160)} — o agente sai com a voz padrão"
  end

  def update_agent(body)
    client.update_agent(settings.agent_id, body)
    log << "✅ Agente \"#{settings.agent_name}\" atualizado (#{settings.agent_id})"
  end

  def create_agent(body)
    agent_id = client.create_agent(body)['agent_id']
    settings.persist!(agent_id: agent_id)
    log << "✅ Agente \"#{settings.agent_name}\" criado (#{agent_id})"
  end

  def sync_whatsapp_account
    if settings.whatsapp_phone_number_id.blank?
      log << '⚠️ Nenhum número do WhatsApp escolhido: importe a conta na ElevenLabs e selecione o número aqui.'
      return
    end

    client.update_whatsapp_account(settings.whatsapp_phone_number_id, assigned_agent_id: settings.agent_id, enable_messaging: false)
    settings.persist_state!(whatsapp_assigned_at: Time.current.iso8601)
    log << "✅ Número #{settings.whatsapp_number || settings.whatsapp_phone_number_id} amarrado ao agente (mensagens de texto desligadas)"
  end
end
