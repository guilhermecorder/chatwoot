# 🤖📞 Agente de Ligação (item 169): ações de configuração do agente na
# ElevenLabs, incluídas no Api::V1::Accounts::Crm::SettingsController
# (já na lista ADMIN_SETTINGS_ACTIONS e nas rotas). Tudo mora em
# crm_settings.ai_config['voice'] (padrões em Crm::VoiceAgent::Settings);
# chave da API e segredo do webhook só entram quando enviados e nunca
# voltam para a tela.
module Crm::VoiceAgentSettings
  extend ActiveSupport::Concern

  VOICE_TEXT_FIELDS = %w[agent_name agent_id webhook_id whatsapp_phone_number_id whatsapp_number voice_id voice_name voice_public_owner_id
                         first_message outbound_first_message partner_message persona_name prompt inbound_prompt
                         transfer_condition].freeze

  def update_voice
    voice = voice_settings.raw.deep_dup
    apply_voice_secrets(voice)
    apply_voice_flags(voice)
    apply_voice_texts(voice)
    apply_voice_choices(voice)
    apply_voice_targets(voice)
    apply_voice_limits(voice)
    apply_voice_after_call(voice)
    apply_voice_pronunciations(voice)
    # token das ferramentas nasce no 1º save e não muda (as ferramentas na ElevenLabs guardam ele)
    voice['tools_token'] ||= SecureRandom.hex(24)
    voice['updated_at'] = Time.current.iso8601
    # item 333: o bloco state é do pós-chamada/sincronização (persist_state!) — a tela não o regrava
    voice_settings.persist!(voice.except('state'))
    render json: { voice: voice_json(crm_settings.reload) }
  end

  # testa a chave de verdade (GET /v1/user)
  def test_voice
    user = voice_client.user
    render json: { ok: true, name: [user['first_name'], user['last_name']].compact_blank.join(' ').presence || user['email'],
                   tier: user.dig('subscription', 'tier') }
  rescue Crm::VoiceAgent::Error => e
    render json: { ok: false, error: e.message }
  end

  def sync_voice
    render json: Crm::VoiceAgent::SyncService.new(Current.account).perform
  end

  # contas WhatsApp importadas na ElevenLabs (p/ escolher o número da assistente)
  def voice_whatsapp_accounts
    render json: { ok: true, items: voice_client.whatsapp_accounts }
  rescue Crm::VoiceAgent::Error => e
    render json: { ok: false, error: e.message, items: [] }
  end

  def voice_voices
    render json: { ok: true, voices: voice_client.voices(search: params[:search]) }
  rescue Crm::VoiceAgent::Error => e
    render json: { ok: false, error: e.message, voices: [] }
  end

  # estado + últimas 10 ligações da assistente
  def voice_state
    calls = Crm::Call.where(account: Current.account, handled_by: 'ai').recent_first.with_attached_recording
                     .includes(:contact, :conversation).limit(10)
    render json: { state: voice_settings.state, configured: voice_settings.configured?, enabled: voice_settings.enabled?,
                   calls: calls.map(&:to_payload) }
  end

  private

  def voice_settings
    @voice_settings ||= Crm::VoiceAgent::Settings.new(Current.account, crm_settings: crm_settings)
  end

  def voice_client
    key = params[:api_key].presence || voice_settings.api_key
    Crm::VoiceAgent::Client.new(key)
  end

  # chave da API e segredo do webhook: só quando enviados (nunca apagados por um save da tela)
  def apply_voice_secrets(voice)
    voice['api_key'] = params[:api_key].to_s.strip if params[:api_key].present?
    voice['webhook_secret'] = params[:webhook_secret].to_s.strip if params[:webhook_secret].present?
  end

  def apply_voice_flags(voice)
    voice['enabled'] = ActiveModel::Type::Boolean.new.cast(params[:enabled]) == true if params.key?(:enabled)
  end

  # textos livres (prompt vazio = volta ao script padrão)
  def apply_voice_texts(voice)
    VOICE_TEXT_FIELDS.each do |field|
      next unless params.key?(field)

      voice[field] = params[field].to_s.strip[0, 20_000].presence
    end
    voice['transfer_number'] = sanitize_e164(params[:transfer_number]) if params.key?(:transfer_number)
  end

  # listas fechadas: modelo, idioma e tipo de conexão
  def apply_voice_choices(voice)
    voice['llm'] = params[:llm] if params.key?(:llm) && Crm::VoiceAgent::Settings::LLM_OPTIONS.include?(params[:llm])
    voice['language'] = params[:language] if params.key?(:language) && Crm::VoiceAgent::Settings::LANGUAGE_OPTIONS.include?(params[:language])
    voice['connection'] = params[:connection] if params.key?(:connection) && Crm::VoiceAgent::Settings::CONNECTIONS.include?(params[:connection])
    voice['tts_model'] = params[:tts_model] if Crm::VoiceAgent::Settings::TTS_MODEL_OPTIONS.include?(params[:tts_model])
    voice['persona_gender'] = params[:persona_gender] if Crm::VoiceAgent::Settings::GENDERS.include?(params[:persona_gender])
  end

  # caixa da clínica (só da conta), modelo de continuidade e modelo de permissão
  def apply_voice_targets(voice)
    voice['handoff_inbox_id'] = Current.account.inboxes.find_by(id: params[:handoff_inbox_id])&.id if params.key?(:handoff_inbox_id)
    voice['handoff_template_params'] = hash_param(params[:handoff_template_params]) if params.key?(:handoff_template_params)
    voice['permission_template'] = permission_template_param if params.key?(:permission_template)
  end

  # { name, language } do modelo call_permission_request (Meta)
  def permission_template_param
    tpl = hash_param(params[:permission_template])
    { 'name' => tpl['name'].to_s.strip[0, 512], 'language' => tpl['language'].to_s.strip[0, 16] }
  end

  def apply_voice_limits(voice)
    voice['max_duration_seconds'] = params[:max_duration_seconds].to_i.clamp(60, 3600) if params.key?(:max_duration_seconds)
    voice['daily_limit'] = params[:daily_limit].to_i.clamp(1, 5000) if params.key?(:daily_limit)
    voice['hours'] = sanitize_voice_hours(params[:hours]) if params.key?(:hours)
    voice['call_days'] = Array(params[:call_days]).map(&:to_i).select { |d| d.between?(0, 6) }.uniq.sort if params.key?(:call_days)
  end

  # item 333: depois da ligação — coluna por resultado (só colunas da conta)
  def apply_voice_after_call(voice)
    return unless params.key?(:outcome_stages)

    wanted = hash_param(params[:outcome_stages]).slice(*Crm::VoiceAgent::Settings::STAGE_OUTCOMES)
    voice['outcome_stages'] = wanted.transform_values { |id| account_stage_id(id) }.compact
  end

  def account_stage_id(raw)
    return nil if raw.to_i <= 0

    Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: Current.account.id }).find_by(id: raw.to_i)&.id
  end

  # item 333: [{ from, to }] — como a voz deve falar nomes difíceis
  def apply_voice_pronunciations(voice)
    return unless params.key?(:pronunciations)

    rows = Array(params[:pronunciations]).map { |row| hash_param(row) }
    voice['pronunciations'] = rows.filter_map do |row|
      from = row['from'].to_s.strip[0, 60]
      to = row['to'].to_s.strip[0, 80]
      { 'from' => from, 'to' => to } if from.present? && to.present?
    end.first(Crm::VoiceAgent::Settings::MAX_PRONUNCIATIONS)
  end

  # "HH:MM" válidos e início < fim; senão volta ao padrão 08:00–19:00
  def sanitize_voice_hours(raw)
    h = hash_param(raw)
    start_at = h['start'].to_s.strip
    end_at = h['end'].to_s.strip
    valid = [start_at, end_at].all? { |v| v.match?(/\A([01]\d|2[0-3]):[0-5]\d\z/) } && start_at < end_at
    valid ? { 'start' => start_at, 'end' => end_at } : Crm::VoiceAgent::Settings::DEFAULT_HOURS.dup
  end

  # "+55 11 99999-0000" → "+5511999990000"; vazio = sem transferência
  def sanitize_e164(raw)
    digits = raw.to_s.gsub(/\D/, '')
    return nil if digits.length < 10

    "+#{digits}"
  end

  def hash_param(raw)
    (raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : (raw || {}).to_h).deep_stringify_keys
  end
end
