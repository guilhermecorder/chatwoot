# 📞 Agente de Ligação — leads não responsivos (rodada 195). Cron de hora em
# hora: para cada conta com o card "Agente de Ligação" LIGADO no hub
# (agents.voice.enabled), monta a lista de quem ele ligaria hoje
# (Crm::VoiceAgent::UnresponsiveLeads) e decide:
# - SOMBRA (modo shadow, trava do servidor fechada, fora da janela ou
#   ElevenLabs sem configurar): guarda a lista em voice_state.shadow e registra
#   'ligaria'. NADA é discado. A tela mostra "Ligaria hoje para N pessoas".
# - AO VIVO (modo live + CEVICO_RESPONDERS_LIVE + dentro da janela + ElevenLabs
#   configurada e ligada): enfileira os candidatos na campanha do dia
#   "🤖 Leads não responsivos — dd/mm" (status processing) e quem disca é o
#   Crm::VoiceAgent::CampaignDialerJob de sempre (5 em 5 min, horário, teto,
#   permissão da Meta). Registra 'enfileirou'. Uma pessoa nunca entra duas
#   vezes na campanha do dia (unicidade) nem recebe 2 ligações em 48 h.
class Crm::VoiceAgent::UnresponsiveLeadsJob < ApplicationJob
  queue_as :low

  AGENT_KEY = 'voice'.freeze
  TZ = Crm::VoiceAgent::Settings::TZ
  CAMPAIGN_PREFIX = '🤖 Leads não responsivos — '.freeze
  CAMPAIGN_OBJECTIVE = 'retomar a conversa que parou no WhatsApp: tirar dúvidas e marcar a consulta de avaliação, ' \
                       'ou continuar pelo WhatsApp'.freeze

  def perform(now = nil)
    @now = now ? now.in_time_zone(TZ) : TZ.now
    CrmSetting.where("ai_config -> 'agents' -> 'voice' ->> 'enabled' = 'true'").includes(:account).find_each do |settings|
      account = settings.account
      next if account.blank?

      run_account(account, settings.ai_config.dig('agents', AGENT_KEY) || {})
    rescue StandardError => e
      Rails.logger.error("[CEVICO voice leads] conta #{settings.account_id}: #{e.class}: #{e.message}")
    end
  end

  # ao vivo AGORA? modo live + trava do servidor + janela + ElevenLabs pronta e ligada
  def self.live_now?(account, cfg, settings: nil, now: TZ.now)
    return false unless cfg['mode'] == 'live' && Crm::ResponderAgentJob::LIVE_ENABLED && Crm::AgentWindow.within?(cfg, now)

    settings ||= Crm::VoiceAgent::Settings.new(account)
    settings.configured? && settings.enabled?
  end

  # SOMBRA: monta a lista e guarda em voice_state.shadow (também é o que o
  # botão "Ver quem ligaria hoje" chama, com log: false). Devolve a lista.
  def self.shadow!(account, cfg, now: TZ.now, log: true)
    leads = Crm::VoiceAgent::UnresponsiveLeads.new(account, cfg, now: now)
    items = leads.candidates(limit: leads.daily_cap)
    previous = Crm::AgentState.read(account, AGENT_KEY)['shadow'] || {}
    Crm::AgentState.update(account, AGENT_KEY) do |state|
      state['shadow'] = { 'date' => now.to_date.to_s, 'at' => Time.current.iso8601, 'mode' => 'shadow', 'items' => items }
      state
    end
    log_shadow(account, items, previous, now) if log
    items
  end

  # registra 'ligaria' quando a lista mudou (ou no 1º giro do dia) — sem
  # encher o registro a cada hora com o mesmo aviso
  def self.log_shadow(account, items, previous, now)
    same_day = previous['date'] == now.to_date.to_s
    same_list = Array(previous['items']).pluck('contact_id').sort == items.pluck('contact_id').sort
    return if same_day && same_list

    note = items.empty? ? 'ninguém para ligar hoje (sombra)' : "ligaria hoje para #{items.size} pessoa(s): #{items.first(3).pluck('name').join(', ')}"
    Crm::AgentState.log(account, AGENT_KEY, 'ligaria', note)
  end

  private

  def run_account(account, cfg)
    settings = Crm::VoiceAgent::Settings.new(account)
    if self.class.live_now?(account, cfg, settings: settings, now: @now)
      live!(account, cfg, settings)
    else
      self.class.shadow!(account, cfg, now: @now)
    end
  end

  # AO VIVO: candidatos → campanha do dia (fila queued); o discador faz o resto
  def live!(account, cfg, settings) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
    leads = Crm::VoiceAgent::UnresponsiveLeads.new(account, cfg, now: @now)
    campaign = daily_campaign(account, cfg, settings, leads.daily_cap)
    room = leads.daily_cap - campaign.campaign_contacts.count
    items = room.positive? ? leads.candidates(limit: room) : []
    objectives = (campaign.audience || {})['objectives'] || {}
    added = []
    items.each do |item|
      next if campaign.campaign_contacts.exists?(contact_id: item['contact_id'])

      campaign.campaign_contacts.create!(contact_id: item['contact_id'], status: 'queued')
      objectives[item['contact_id'].to_s] = item['objective']
      added << item
    end
    campaign.update!(audience: (campaign.audience || {}).merge('objectives' => objectives), status: :processing, finished_at: nil)
    campaign.refresh_stats!

    Crm::AgentState.update(account, AGENT_KEY) do |state|
      state['shadow'] = { 'date' => @now.to_date.to_s, 'at' => Time.current.iso8601, 'mode' => 'live', 'campaign_id' => campaign.id,
                          'items' => todays_items(campaign, state) }
      state
    end
    return if added.empty?

    Crm::AgentState.log(account, AGENT_KEY, 'enfileirou',
                        "#{added.size} pessoa(s) na campanha de hoje: #{added.first(3).pluck('name').join(', ')}")
  end

  # a lista do dia ao vivo = quem já está na campanha (com o status de lá)
  def todays_items(campaign, state)
    known = Array(state.dig('shadow', 'items')).index_by { |i| i['contact_id'] }
    campaign.campaign_contacts.includes(:contact).order(:id).map do |row|
      base = known[row.contact_id] || fallback_item(campaign, row)
      base.merge('status' => row.status, 'outcome' => row.outcome_label, 'called_at' => row.called_at&.iso8601)
    end
  end

  # pessoa enfileirada num giro anterior (o estado não guardava a lista): monta o mínimo
  def fallback_item(campaign, row)
    contact = row.contact
    { 'contact_id' => row.contact_id, 'name' => contact&.name.to_s, 'phone_final' => contact&.phone_number.to_s.gsub(/\D/, '').last(4),
      'stage' => '', 'motivo' => (campaign.audience || {}).dig('objectives', row.contact_id.to_s).to_s }
  end

  # campanha do dia: uma por conta e data (reaproveitada em cada giro)
  def daily_campaign(account, cfg, settings, cap)
    name = "#{CAMPAIGN_PREFIX}#{@now.strftime('%d/%m')}"
    existing = Crm::CallCampaign.where(account_id: account.id, name: name).where(created_at: @now.all_day).order(:id).first
    return existing if existing

    Crm::CallCampaign.create!(
      account: account, name: name, objective: CAMPAIGN_OBJECTIVE, first_message: Crm::VoiceAgent::Script::UNRESPONSIVE_FIRST_MESSAGE,
      audience: { 'kind' => 'unresponsive_leads', 'objectives' => {} }, hours: campaign_hours(cfg, settings),
      daily_cap: cap, concurrency: 1, status: :processing, started_at: Time.current, stats: {}
    )
  end

  # janela do agente ("HH:MM" válidos e início < fim); senão o horário da Integração
  def campaign_hours(cfg, settings)
    start_at = cfg['hours_start'].to_s
    end_at = cfg['hours_end'].to_s
    valid = [start_at, end_at].all? { |v| v.match?(/\A([01]\d|2[0-3]):[0-5]\d\z/) } && start_at < end_at
    valid ? { 'start' => start_at, 'end' => end_at } : settings.hours
  end
end
