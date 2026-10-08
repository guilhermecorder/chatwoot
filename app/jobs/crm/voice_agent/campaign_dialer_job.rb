# 🤖📞 Discador das campanhas de ligação (item 169). Cron a cada 5 min:
# para cada conta com o agente ligado, pega as campanhas em andamento
# (e promove as agendadas cujo horário chegou), dentro do horário
# configurado, e pede à ElevenLabs uma ligação de saída pelo WhatsApp
# nativo para os próximos contatos da fila — respeitando o número de
# ligações simultâneas (concurrency) e o teto do dia (daily_cap).
# A ElevenLabs manda o modelo de permissão e liga quando o paciente aceita;
# o pós-chamada fecha o contato. Uma trava Redis por conta evita duas
# rodadas ao mesmo tempo (deploy no meio da rodada).
#
# Item 333 (08/10, achados da auditoria de 07/10): nada é discado sem a trava
# geral dos robôs (CEVICO_RESPONDERS_LIVE); campanha só nos DIAS escolhidos
# (Integrações → Limites); a campanha automática de leads parados só disca
# enquanto o card do agente está AO VIVO e dentro da janela dele, e a fila que
# sobrou de um dia anterior é descartada; e cada pessoa é reconferida NA HORA
# de ligar: pediu para parar, virou paciente de parceiro, recusou a ligação
# (30 dias), ou — nos leads parados — respondeu / marcou consulta depois de
# entrar na fila. Cada ligação leva o roteiro de LIGAR (o do agente é o de atender).
class Crm::VoiceAgent::CampaignDialerJob < ApplicationJob
  queue_as :low

  TZ = Crm::VoiceAgent::Settings::TZ
  LOCK_TTL = 4.minutes
  STALE_AFTER = 30.minutes # calling sem pós-chamada há mais que isso = perdido
  # ligação da IA aberta pelas ferramentas (ou discada) sem pós-chamada há mais
  # que isso = a ElevenLabs não avisou o fim; fecha p/ não ficar "em chamada"
  STALE_CALL_AFTER = 2.hours
  # recusou o pedido de permissão: fica sem ligação da assistente por este tempo
  REFUSAL_COOLDOWN = 30.days
  UNRESPONSIVE_KIND = 'unresponsive_leads'.freeze

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
    return unless settings.enabled? && settings.configured? && Crm::ResponderAgentJob::LIVE_ENABLED

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

  def run_campaign(campaign, settings) # rubocop:disable Metrics/CyclomaticComplexity
    close_stale(campaign)
    expire_old_queue(campaign) if unresponsive?(campaign)
    campaign.finish_if_done!
    return unless campaign.processing?
    return unless may_dial_now?(campaign, settings)
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

  def unresponsive?(campaign)
    (campaign.audience || {})['kind'] == UNRESPONSIVE_KIND
  end

  # leads parados: só com o card do agente AO VIVO e dentro da janela dele
  # (dias + horas); campanhas manuais: nos dias escolhidos em Integrações
  def may_dial_now?(campaign, settings)
    return settings.within_days?(@now) unless unresponsive?(campaign)

    cfg = (CrmSetting.find_by(account_id: campaign.account_id)&.ai_config || {}).dig('agents', 'voice') || {}
    Crm::VoiceAgent::UnresponsiveLeadsJob.live_now?(campaign.account, cfg, settings: settings, now: @now)
  end

  # a campanha do dia dos leads parados não liga no dia seguinte com motivo velho
  def expire_old_queue(campaign)
    return if campaign.created_at.in_time_zone(TZ).to_date >= @now.to_date

    campaign.campaign_contacts.queued.find_each { |row| row.update!(status: 'skipped', error: 'Fila de um dia anterior') }
    campaign.refresh_stats!
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

    reason = skip_reason(campaign, row, contact)
    return row.update!(status: 'skipped', error: reason) if reason

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

  # reconferido NA HORA de ligar (a pessoa pode ter mudado desde que entrou na fila)
  def skip_reason(campaign, row, contact)
    return 'Pediu para não ser incomodado' if opted_out?(campaign.account, contact)
    return 'Paciente de clínica parceira' if Crm::PartnerGuard.partner_contact?(contact)
    return 'Recusou ligações nos últimos 30 dias' if refused_recently?(contact)
    return nil unless unresponsive?(campaign)
    return 'Respondeu depois de entrar na fila' if replied_since?(contact, row.created_at)
    return 'Já tem consulta marcada' if Crm::AppointmentRecorder.future_appointment(contact.account, contact.phone_number, nil, contact)

    nil
  end

  def opted_out?(account, contact)
    @quiet_titles ||= {}
    titles = (@quiet_titles[account.id] ||= Crm::OptOut.quiet_titles(account))
    contact.label_list.map(&:to_s).intersect?(titles)
  end

  def refused_recently?(contact)
    answer = (contact.additional_attributes || {})['cevico_call_permission'] || {}
    return false unless answer['status'] == 'reject'

    replied = Time.zone.parse(answer['replied_at'].to_s) if answer['replied_at'].present?
    replied.nil? || replied > @now - REFUSAL_COOLDOWN
  rescue ArgumentError
    true
  end

  def replied_since?(contact, since)
    Message.joins(:conversation).where(conversations: { contact_id: contact.id, account_id: contact.account_id })
           .where(message_type: :incoming).exists?(created_at: since..)
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
          campanha_objetivo: contact_objective(campaign, row), campanha_id: campaign.id.to_s, contato_id: row.contact_id.to_s,
          proxima_consulta: next_appointment_text(contact, digits)
        },
        # item 333: o roteiro de LIGAR (o do agente na ElevenLabs é o de atender)
        conversation_config_override: { agent: { first_message: first_message(campaign, settings, first_name),
                                                 prompt: { prompt: outbound_prompt(campaign.account, settings) } } }
      }
    }
  end

  # 📞 rodada 195: a campanha de leads não responsivos guarda o motivo de CADA
  # pessoa em audience.objectives ("orçamento enviado, sem resposta há dois
  # dias"); as campanhas normais seguem com o objetivo único
  def contact_objective(campaign, row)
    (campaign.audience || {}).dig('objectives', row.contact_id.to_s).presence || campaign.objective.to_s
  end

  def next_appointment_text(contact, digits)
    task = Crm::AppointmentRecorder.future_appointment(contact.account, digits, nil, contact)
    return '' unless task

    due = task.due_at.in_time_zone(TZ)
    "#{Crm::VoiceAgent::Script.spoken_date(due.to_date)}, às #{Crm::VoiceAgent::Script.spoken_time(due.strftime('%H:%M'))}"
  end

  def outbound_prompt(account, settings)
    @outbound_prompts ||= {}
    @outbound_prompts[account.id] ||= Crm::VoiceAgent::Script.build(account, settings, direction: :outbound)
  end

  # primeira frase da campanha (ou a de LIGAR da Integração) com o nome do paciente
  def first_message(campaign, settings, first_name)
    text = Crm::VoiceAgent::Script.persona_fill(campaign.first_message.presence || settings.outbound_first_message,
                                                campaign.account, settings)
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
