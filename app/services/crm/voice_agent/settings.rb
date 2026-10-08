# 🤖📞 Agente de Ligação (item 169): leitor de crm_settings.ai_config['voice']
# com os padrões preenchidos — controller, ferramentas, discador e webhook
# leem daqui para nunca divergirem. Segredos (chave da API, segredo do
# webhook, token das ferramentas) NUNCA saem no to_h: só "está gravado".
class Crm::VoiceAgent::Settings
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  DEFAULT_HOURS = { 'start' => '08:00', 'end' => '19:00' }.freeze
  LLM_OPTIONS = %w[gemini-2.5-flash gemini-3.5-flash claude-haiku-4-5 claude-sonnet-4-5 gpt-4.1-mini].freeze
  LANGUAGE_OPTIONS = %w[pt-br pt].freeze
  CONNECTIONS = %w[whatsapp sip].freeze
  TOOL_NAMES = %w[buscar_paciente horarios_livres marcar_consulta minha_consulta confirmar_presenca enviar_whatsapp
                  chamar_equipe registrar_resultado].freeze
  # motores de voz que a ElevenLabs aceita para agentes (OpenAPI 08/10: TTSConversationalModel)
  TTS_MODEL_OPTIONS = %w[eleven_flash_v2_5 eleven_turbo_v2_5 eleven_v4_turbo eleven_v4 eleven_multilingual_v2
                         eleven_v3_conversational].freeze
  GENDERS = %w[f m].freeze
  # dias em que as CAMPANHAS podem ligar (0 = domingo); recebidas: sempre
  DEFAULT_CALL_DAYS = [1, 2, 3, 4, 5].freeze
  MAX_PRONUNCIATIONS = 30
  # resultados da ligação que podem levar o card para uma coluna (agendou e
  # remarcou seguem "Ao marcar"; confirmou segue a coluna de Consulta Confirmada)
  STAGE_OUTCOMES = %w[cancelou quer_whatsapp sem_interesse recado transferido nao_atendeu outro].freeze
  INBOUND_AGENT_KEY = 'voice_inbound'.freeze
  DEFAULTS = {
    'agent_name' => 'Assistente virtual da CEVICO', 'llm' => 'gemini-2.5-flash', 'language' => 'pt-br',
    'tts_model' => 'eleven_flash_v2_5', 'connection' => 'whatsapp', 'max_duration_seconds' => 600, 'daily_limit' => 200
  }.freeze

  attr_reader :account

  def initialize(account, crm_settings: nil)
    @account = account
    @crm_settings = crm_settings
  end

  # CEVICO_VOICE_SIMULATE=1 → nada sai para a ElevenLabs (ambiente local)
  def self.simulate_env?
    ENV['CEVICO_VOICE_SIMULATE'] == '1'
  end

  def raw
    @raw ||= (crm_settings&.ai_config || {})['voice'] || {}
  end

  # o card do agente no hub (ai_config.agents.voice): modo, colunas vigiadas,
  # janela, tetos e o bloco da etapa — rodada 195
  def agent_raw
    @agent_raw ||= (crm_settings&.ai_config || {}).dig('agents', 'voice') || {}
  end

  def enabled?
    raw['enabled'] == true
  end

  # pronta para atender: chave da API + agente criado na ElevenLabs
  def configured?
    api_key.present? && agent_id.present?
  end

  # ── segredos (só uso interno) ────────────────────────────────────────────
  def api_key = raw['api_key'].presence
  def webhook_secret = raw['webhook_secret'].presence
  def tools_token = raw['tools_token'].presence

  # ── identidade na ElevenLabs ─────────────────────────────────────────────
  def webhook_id = raw['webhook_id'].presence
  def agent_id = raw['agent_id'].presence
  def agent_name = raw['agent_name'].presence || DEFAULTS['agent_name']
  def tool_ids = (raw['tool_ids'] || {}).to_h.slice(*TOOL_NAMES).compact_blank
  def whatsapp_phone_number_id = raw['whatsapp_phone_number_id'].presence
  def whatsapp_number = raw['whatsapp_number'].presence
  def connection = CONNECTIONS.include?(raw['connection']) ? raw['connection'] : DEFAULTS['connection']

  # ── persona e voz ────────────────────────────────────────────────────────
  def voice_id = raw['voice_id'].presence
  def voice_name = raw['voice_name'].presence
  # voz escolhida na biblioteca pública (o Sincronizar a adiciona à conta)
  def voice_public_owner_id = raw['voice_public_owner_id'].presence
  def llm = LLM_OPTIONS.include?(raw['llm']) ? raw['llm'] : DEFAULTS['llm']
  def language = LANGUAGE_OPTIONS.include?(raw['language']) ? raw['language'] : DEFAULTS['language']
  def tts_model = TTS_MODEL_OPTIONS.include?(raw['tts_model']) ? raw['tts_model'] : DEFAULTS['tts_model']

  # 🎙️ item 333: como ela se apresenta — nome ("Guilherme") e gênero (o/a)
  def persona_name = raw['persona_name'].to_s.strip.presence
  def persona_gender = GENDERS.include?(raw['persona_gender']) ? raw['persona_gender'] : 'f'
  def masculine? = persona_gender == 'm'

  # 1ª frase ao ATENDER (recebidas) e ao LIGAR (campanhas e leads parados)
  def first_message = raw['first_message'].presence || Crm::VoiceAgent::Script.default_first_message(self, :inbound)
  def outbound_first_message = raw['outbound_first_message'].presence || Crm::VoiceAgent::Script.default_first_message(self, :outbound)

  # o que ela diz a quem é paciente de parceiro (regra de ouro: sem IA) antes de encerrar
  def partner_message = raw['partner_message'].presence || Crm::VoiceAgent::Script.default_partner_message(self)

  # [{ 'from' => 'Gemelli', 'to' => 'Jeméli' }] — como a voz deve falar nomes difíceis
  def pronunciations
    Array(raw['pronunciations']).filter_map do |row|
      row = row.to_h
      from = row['from'].to_s.strip
      to = row['to'].to_s.strip
      { 'from' => from, 'to' => to } if from.present? && to.present?
    end.first(MAX_PRONUNCIATIONS)
  end
  # 🎙️ rodada 195: "prompt" é o bloco da ETAPA (Passos desta ligação), o mesmo
  # que o card do agente edita (agents.voice.prompt); o script inteiro é montado
  # por Crm::VoiceAgent::Script.build (Roteiro + regras de voz + etapa)
  def prompt = agent_raw['prompt'].presence
  # item 333: bloco da etapa ao ATENDER (ligação recebida) — agents.voice_inbound.prompt
  def inbound_prompt = (crm_settings&.ai_config || {}).dig('agents', INBOUND_AGENT_KEY, 'prompt').presence
  def transfer_number = raw['transfer_number'].presence
  def transfer_condition = raw['transfer_condition'].presence || Crm::VoiceAgent::Script::TRANSFER_CONDITION

  # ── WhatsApp da clínica (mensagens e conversa/card) ──────────────────────
  def handoff_inbox_id = raw['handoff_inbox_id'].presence&.to_i

  def handoff_inbox
    return nil if handoff_inbox_id.blank?

    @handoff_inbox ||= account.inboxes.find_by(id: handoff_inbox_id)
  end

  # caixa onde a Crm::Call nasce: a de handoff; senão a das Ligações (item
  # 167); senão a 1ª caixa WhatsApp — a ligação nunca fica sem casa
  def call_inbox
    @call_inbox ||= handoff_inbox || Crm::Calls::Settings.new(account, crm_settings: crm_settings).inbox ||
                    account.inboxes.find_by(channel_type: 'Channel::Whatsapp')
  end

  def handoff_template_params = (raw['handoff_template_params'] || {}).to_h

  def permission_template
    tpl = (raw['permission_template'] || {}).to_h
    { 'name' => tpl['name'].to_s.strip, 'language' => tpl['language'].to_s.strip.presence || 'pt_BR' }
  end

  # ── limites ──────────────────────────────────────────────────────────────
  def max_duration_seconds = raw['max_duration_seconds'].to_i.positive? ? raw['max_duration_seconds'].to_i : DEFAULTS['max_duration_seconds']
  def daily_limit = raw['daily_limit'].to_i.positive? ? raw['daily_limit'].to_i : DEFAULTS['daily_limit']

  def hours
    DEFAULT_HOURS.merge((raw['hours'] || {}).to_h.slice('start', 'end').compact_blank)
  end

  # campanhas só ligam nesta janela (recebidas: sempre)
  def within_hours?(now = TZ.now, window = hours)
    hhmm = now.strftime('%H:%M')
    hhmm >= window['start'].to_s && hhmm < window['end'].to_s
  end

  # dias da semana em que as campanhas ligam (vazio no banco = seg a sex)
  def call_days
    days = Array(raw['call_days']).map(&:to_i).select { |d| d.between?(0, 6) }.uniq.sort
    raw.key?('call_days') && days.any? ? days : DEFAULT_CALL_DAYS.dup
  end

  def within_days?(now = TZ.now)
    call_days.include?(now.wday)
  end

  # ── depois da ligação (item 333) ─────────────────────────────────────────
  # marcou/remarcou: a coluna de Agendamentos → Ajustes (a mesma do WhatsApp);
  # os outros resultados: { 'sem_interesse' => 15, … } — só STAGE_OUTCOMES
  def outcome_stages
    (raw['outcome_stages'] || {}).to_h.slice(*STAGE_OUTCOMES).transform_values(&:to_i).select { |_k, v| v.positive? }
  end

  def state = (raw['state'] || {}).to_h

  # ── URLs públicas (ferramentas + webhooks apontam para cá) ───────────────
  def base_url = ENV['FRONTEND_URL'].to_s.chomp('/')
  def tools_base_url = "#{base_url}/webhooks/cevico/voice/#{account.id}"
  def tool_url(name) = "#{tools_base_url}/tools/#{name}"
  def post_call_url = "#{tools_base_url}/post_call"
  def initiation_url = "#{tools_base_url}/initiation"

  # grava mudanças em ai_config['voice'] (merge raso) e espelha o interruptor
  # no Painel dos agentes (ai_config['agents']['voice']['enabled']). Desde a
  # rodada 195 "prompt" NÃO mora mais em voice: vai para agents.voice.prompt
  # (bloco da etapa), a mesma chave que o card do hub edita.
  # item 333: lê→altera→grava DENTRO da trava da linha (o padrão corrigido em
  # julho): o pós-chamada, o Radar e a tela não apagam o que o outro gravou
  def persist!(changes)
    record = crm_settings || CrmSetting.find_or_create_by!(account: account)
    voice = nil
    record.with_lock do
      cfg = (record.ai_config || {}).deep_dup
      changes = changes.deep_stringify_keys
      voice = (cfg['voice'] || {}).merge(changes.except('prompt', 'inbound_prompt'))
      voice.delete('prompt') # resquício do script inteiro custom (antes da 195)
      cfg['voice'] = voice
      cfg['agents'] = mirror_agent(cfg['agents'] || {}, voice, changes)
      record.update!(ai_config: cfg)
    end
    @crm_settings = record
    @raw = nil
    @agent_raw = nil
    voice
  end

  # agents.voice recebe o interruptor e (quando veio) o bloco da etapa ao
  # LIGAR; agents.voice_inbound guarda o bloco da etapa ao ATENDER
  def mirror_agent(agents, voice, changes)
    agent = (agents['voice'] || {}).merge('enabled' => voice['enabled'] == true)
    agent['prompt'] = changes['prompt'].presence if changes.key?('prompt')
    agents = agents.merge('voice' => agent)
    return agents unless changes.key?('inbound_prompt')

    agents.merge(INBOUND_AGENT_KEY => (agents[INBOUND_AGENT_KEY] || {}).merge('prompt' => changes['inbound_prompt'].presence))
  end

  # só o bloco state (synced_at, last_error, last_sync_log, last_call_at…),
  # mesclado dentro da trava: duas ligações terminando juntas não se apagam
  def persist_state!(changes)
    record = crm_settings || CrmSetting.find_or_create_by!(account: account)
    record.with_lock do
      cfg = (record.ai_config || {}).deep_dup
      voice = cfg['voice'] || {}
      voice['state'] = (voice['state'] || {}).to_h.merge(changes.deep_stringify_keys)
      cfg['voice'] = voice
      record.update!(ai_config: cfg)
    end
    @crm_settings = record
    @raw = nil
    @agent_raw = nil
  end

  # o que vai em settings_json.voice — nunca com segredos
  def to_h # rubocop:disable Metrics/AbcSize
    {
      enabled: enabled?, configured: configured?,
      api_key_set: api_key.present?, webhook_secret_set: webhook_secret.present?, tools_token_set: tools_token.present?,
      webhook_id: webhook_id, agent_id: agent_id, agent_name: agent_name, tool_ids: tool_ids,
      whatsapp_phone_number_id: whatsapp_phone_number_id, whatsapp_number: whatsapp_number, connection: connection,
      voice_id: voice_id, voice_name: voice_name, voice_public_owner_id: voice_public_owner_id, llm: llm, language: language, tts_model: tts_model,
      # item 333: persona, falas por caso e pronúncia
      persona_name: persona_name, persona_gender: persona_gender,
      first_message: first_message, outbound_first_message: outbound_first_message,
      first_message_custom: raw['first_message'].present?, outbound_first_message_custom: raw['outbound_first_message'].present?,
      partner_message: partner_message, partner_message_custom: raw['partner_message'].present?, pronunciations: pronunciations,
      partner_pipeline_id: Crm::PartnerGuard.partner_pipeline_id(account),
      # rodada 195: prompt = bloco da etapa ao LIGAR (mesmo do card do hub); item 333: inbound_prompt = ao ATENDER
      prompt: prompt, default_prompt: Crm::CevicoScript::STAGE_PROMPTS['voice'],
      inbound_prompt: inbound_prompt, default_inbound_prompt: Crm::CevicoScript::STAGE_PROMPTS[INBOUND_AGENT_KEY],
      full_prompt: Crm::VoiceAgent::Script.build(account, self),
      transfer_number: transfer_number, transfer_condition: transfer_condition,
      handoff_inbox_id: handoff_inbox_id, handoff_template_params: handoff_template_params, permission_template: permission_template,
      max_duration_seconds: max_duration_seconds, daily_limit: daily_limit, hours: hours, call_days: call_days,
      outcome_stages: outcome_stages, booking_stage_id: Crm::BookingSideEffects.booking_stage_id(account),
      tools_base_url: tools_base_url, post_call_url: post_call_url, initiation_url: initiation_url,
      llm_options: LLM_OPTIONS, language_options: LANGUAGE_OPTIONS, tts_model_options: TTS_MODEL_OPTIONS,
      state: state, updated_at: raw['updated_at']
    }
  end

  private

  def crm_settings
    @crm_settings ||= CrmSetting.find_by(account: account)
  end
end
