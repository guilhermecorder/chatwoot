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
  TOOL_NAMES = %w[buscar_paciente horarios_livres marcar_consulta minha_consulta enviar_whatsapp registrar_resultado].freeze
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
  def llm = LLM_OPTIONS.include?(raw['llm']) ? raw['llm'] : DEFAULTS['llm']
  def language = LANGUAGE_OPTIONS.include?(raw['language']) ? raw['language'] : DEFAULTS['language']
  def tts_model = raw['tts_model'].presence || DEFAULTS['tts_model']
  def first_message = raw['first_message'].presence || Crm::VoiceAgent::Script::FIRST_MESSAGE
  def prompt = raw['prompt'].presence
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

  def state = (raw['state'] || {}).to_h

  # ── URLs públicas (ferramentas + webhooks apontam para cá) ───────────────
  def base_url = ENV['FRONTEND_URL'].to_s.chomp('/')
  def tools_base_url = "#{base_url}/webhooks/cevico/voice/#{account.id}"
  def tool_url(name) = "#{tools_base_url}/tools/#{name}"
  def post_call_url = "#{tools_base_url}/post_call"
  def initiation_url = "#{tools_base_url}/initiation"

  # grava mudanças em ai_config['voice'] (merge raso) e espelha o interruptor
  # no Painel dos agentes (ai_config['agents']['voice']['enabled'])
  def persist!(changes)
    record = crm_settings || CrmSetting.find_or_create_by!(account: account)
    record.reload if record.persisted?
    cfg = (record.ai_config || {}).deep_dup
    voice = (cfg['voice'] || {}).merge(changes.deep_stringify_keys)
    cfg['voice'] = voice
    agents = cfg['agents'] || {}
    cfg['agents'] = agents.merge('voice' => (agents['voice'] || {}).merge('enabled' => voice['enabled'] == true))
    record.update!(ai_config: cfg)
    @crm_settings = record
    @raw = nil
    voice
  end

  # só o bloco state (synced_at, last_error, last_sync_log, last_call_at…)
  def persist_state!(changes)
    persist!('state' => state.merge(changes.deep_stringify_keys))
  end

  # o que vai em settings_json.voice — nunca com segredos
  def to_h # rubocop:disable Metrics/AbcSize
    {
      enabled: enabled?, configured: configured?,
      api_key_set: api_key.present?, webhook_secret_set: webhook_secret.present?, tools_token_set: tools_token.present?,
      webhook_id: webhook_id, agent_id: agent_id, agent_name: agent_name, tool_ids: tool_ids,
      whatsapp_phone_number_id: whatsapp_phone_number_id, whatsapp_number: whatsapp_number, connection: connection,
      voice_id: voice_id, voice_name: voice_name, llm: llm, language: language, tts_model: tts_model,
      first_message: first_message, prompt: prompt, default_prompt: Crm::VoiceAgent::Script::SYSTEM_PROMPT,
      transfer_number: transfer_number, transfer_condition: transfer_condition,
      handoff_inbox_id: handoff_inbox_id, handoff_template_params: handoff_template_params, permission_template: permission_template,
      max_duration_seconds: max_duration_seconds, daily_limit: daily_limit, hours: hours,
      tools_base_url: tools_base_url, post_call_url: post_call_url, initiation_url: initiation_url,
      llm_options: LLM_OPTIONS, language_options: LANGUAGE_OPTIONS,
      state: state, updated_at: raw['updated_at']
    }
  end

  private

  def crm_settings
    @crm_settings ||= CrmSetting.find_by(account: account)
  end
end
