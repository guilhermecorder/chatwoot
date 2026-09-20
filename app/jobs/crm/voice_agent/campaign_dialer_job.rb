# 🤖📞 Discador das campanhas de ligação (item 169). Cron a cada 5 min:
# para cada conta com o agente ligado, pega as campanhas em andamento
# (e promove as agendadas cujo horário chegou), dentro do horário
# configurado, e pede à ElevenLabs uma ligação de saída pelo WhatsApp
# nativo para os próximos contatos da fila — respeitando o número de
# ligações simultâneas (concurrency) e o teto do dia (daily_cap).
# A ElevenLabs manda o modelo de permissão e liga quando o paciente aceita;
# o pós-chamada fecha o contato. Uma trava Redis por conta evita duas
# rodadas ao mesmo tempo (deploy no meio da rodada).
class Crm::VoiceAgent::CampaignDialerJob < ApplicationJob
  queue_as :low

  TZ = Crm::VoiceAgent::Settings::TZ
  LOCK_TTL = 4.minutes
  STALE_AFTER = 30.minutes # calling sem pós-chamada há mais que isso = perdido
  # ligação da IA aberta pelas ferramentas (ou discada) sem pós-chamada há mais
  # que isso = a ElevenLabs não avisou o fim; fecha p/ não ficar "em chamada"
  STALE_CALL_AFTER = 2.hours

  def perform(now = nil)
    @now = now ? now.in_time_zone(TZ) : TZ.now
    sweep_stale_ai_calls
    Crm::CallCampaign.due.find_each { |campaign| safely(campaign) { campaign.start! } }

    Crm::CallCampaign.processing.includes(:account).group_by(&:account).each do |account, campaigns|
      run_account(account, campaigns)
    end
  end

  private

  # tocando/em chamada há mais de 2 h sem o webhook de fim: vira "sem retorno"
  # (status failed) e o card da conversa é atualizado — vale p/ todas as contas
  def sweep_stale_ai_calls
    Crm::Call.by_ai.where(status: %w[ringing accepted]).where(started_at: ...(@now - STALE_CALL_AFTER)).find_each do |call|
      call.update!(status: :failed, end_reason: 'sem_pos_chamada', ended_at: @now,
                   error_message: 'A ElevenLabs não enviou o fim da ligação (pós-chamada) em 2 horas')
      Crm::Calls::CardMessageBuilder.new(call).perform if call.conversation_id
    rescue StandardError => e
      Rails.logger.error("[CEVICO voice] ligação #{call.id} sem retorno: #{e.class}: #{e.message}")
    end
  end

  def run_account(account, campaigns)
    settings = Crm::VoiceAgent::Settings.new(account)
    return unless settings.enabled? && settings.configured?

    lock_manager = Redis::LockManager.new
    lock_key = "CRM_VOICE_DIALER_LOCK::#{account.id}"
    return unless lock_manager.lock(lock_key, LOCK_TTL)

    begin
      campaigns.each { |campaign| safely(campaign) { run_campaign(campaign, settings) } }
    ensure
      lock_manager.unlock(lock_key)
    end
  end

  def safely(campaign)
    yield
  rescue StandardError => e
    Rails.logger.error("[CEVICO voice] campanha #{campaign.id}: #{e.class}: #{e.message}")
  end

  def run_campaign(campaign, settings)
    close_stale(campaign)
    campaign.finish_if_done!
    return unless campaign.processing?
    return unless settings.within_hours?(@now, campaign_hours(campaign, settings))
    if settings.permission_template['name'].blank?
      return campaign.update!(stats: campaign.stats.merge('error' => 'Modelo de permissão não configurado'))
    end

    available = free_slots(campaign, settings)
    return if available <= 0

    campaign.campaign_contacts.queued.order(:id).limit(available).includes(:contact).each do |row|
      dial(campaign, row, settings)
    end
    campaign.refresh_stats!
    campaign.finish_if_done!
  end

  # horário da campanha; senão o da configuração
  def campaign_hours(campaign, settings)
    hours = (campaign.hours || {}).to_h.slice('start', 'end').compact_blank
    settings.hours.merge(hours)
  end

  # calling há mais de 30 min sem pós-chamada → failed 'sem retorno'
  def close_stale(campaign)
    campaign.campaign_contacts.calling.where(called_at: ...(@now - STALE_AFTER)).find_each do |row|
      row.update!(status: 'failed', error: 'Sem retorno da ElevenLabs em 30 minutos')
      row.call&.update!(status: :failed, end_reason: 'failed', ended_at: Time.current) unless row.call&.final?
    end
  end

  # quantas ligações cabem agora: simultâneas livres × o que sobra do teto do dia
  def free_slots(campaign, settings)
    calling = campaign.campaign_contacts.calling.count
    today = campaign.campaign_contacts.called_today(TZ).count
    [campaign.concurrency - calling, campaign.daily_cap - today, settings.daily_limit - account_calls_today(campaign.account)].min
  end

  def account_calls_today(account)
    Crm::Call.where(account_id: account.id, handled_by: 'ai').where(started_at: @now.all_day).count
  end

  def dial(campaign, row, settings)
    contact = row.contact
    digits = contact&.phone_number.to_s.gsub(/\D/, '')
    return row.update!(status: 'skipped', error: 'Contato sem telefone') if digits.length < 8

    # a ElevenLabs manda o pedido de permissão da Meta quando falta: os limites
    # (1/24 h, 2/7 dias) valem aqui também (conformidade 20/09)
    return if permission_blocked?(row, contact)

    conversation_id = request_call(campaign, row, contact, digits, settings)
    Crm::Calls::PermissionRequests.remember!(contact)
    row.update!(status: 'calling', provider_conversation_id: conversation_id, called_at: Time.current, attempts: row.attempts + 1, error: nil)
    call = build_call(campaign, contact, digits, conversation_id, settings)
    row.update!(call_id: call.id)
  rescue StandardError => e
    row.update!(status: failure_status(e.message), error: e.message.to_s.truncate(500), attempts: row.attempts + 1)
  end

  def permission_blocked?(row, contact)
    limit = Crm::Calls::PermissionRequests.limit_error(contact)
    row.update!(status: 'no_permission', error: limit) if limit
    limit.present?
  end

  # pede a ligação à ElevenLabs → conversation_id (erro dela vira exceção com a mensagem crua)
  def request_call(campaign, row, contact, digits, settings)
    response = client(settings).whatsapp_outbound_call(outbound_body(campaign, row, contact, digits, settings))
    conversation_id = response['conversation_id'].to_s
    refused = response['success'] == false || conversation_id.blank?
    raise Crm::VoiceAgent::Error, (response['message'].presence || 'A ElevenLabs não aceitou a ligação.') if refused

    conversation_id
  end

  def failure_status(message)
    message.to_s.downcase.include?('permission') ? 'no_permission' : 'failed'
  end

  def outbound_body(campaign, row, contact, digits, settings)
    first_name = contact.name.to_s.strip.split(/\s+/).first.to_s
    {
      whatsapp_phone_number_id: settings.whatsapp_phone_number_id, whatsapp_user_id: digits,
      whatsapp_call_permission_request_template_name: settings.permission_template['name'],
      whatsapp_call_permission_request_template_language_code: settings.permission_template['language'],
      agent_id: settings.agent_id,
      conversation_initiation_client_data: {
        dynamic_variables: {
          paciente_nome: contact.name.to_s, primeiro_nome: first_name, telefone: digits,
          campanha_objetivo: campaign.objective.to_s, campanha_id: campaign.id.to_s, contato_id: row.contact_id.to_s,
          proxima_consulta: next_appointment_text(contact, digits)
        },
        conversation_config_override: { agent: { first_message: first_message(campaign, settings, first_name) } }
      }
    }
  end

  def next_appointment_text(contact, digits)
    task = Crm::AppointmentRecorder.future_appointment(contact.account, digits, nil, contact)
    return '' unless task

    due = task.due_at.in_time_zone(TZ)
    "#{Crm::VoiceAgent::Script.spoken_date(due.to_date)}, às #{Crm::VoiceAgent::Script.spoken_time(due.strftime('%H:%M'))}"
  end

  # primeira frase da campanha (ou a padrão) com o nome do paciente
  def first_message(campaign, settings, first_name)
    text = campaign.first_message.presence || settings.first_message
    return text if first_name.blank? || text.include?(first_name)

    text.sub(/\AOlá!?\s*/i, "Olá, #{first_name}! ")
  end

  def build_call(campaign, contact, digits, conversation_id, settings)
    inbox = settings.call_inbox
    finder = Crm::Calls::ConversationFinder.new(inbox: inbox, wa_id: digits, name: contact.name, contact: contact)
    Crm::Call.create!(
      account: campaign.account, inbox: inbox, contact: contact, conversation: finder.conversation,
      meta_call_id: "el:#{conversation_id}", provider: 'elevenlabs', provider_call_id: conversation_id, handled_by: 'ai',
      direction: :outbound, status: :ringing, campaign_id: campaign.id, wa_id: digits, display_name: contact.name,
      started_at: Time.current, simulated: Crm::VoiceAgent::Settings.simulate_env?
    )
  end

  def client(settings)
    @clients ||= {}
    @clients[settings.account.id] ||= Crm::VoiceAgent::Client.new(settings.api_key)
  end
end
