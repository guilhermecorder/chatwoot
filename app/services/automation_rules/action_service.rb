class AutomationRules::ActionService < ActionService
  def initialize(rule, account, conversation)
    super(conversation)
    @rule = rule
    @account = account
    Current.executed_by = rule
  end

  def perform
    @rule.actions.each do |action|
      @conversation.reload
      action = action.with_indifferent_access
      begin
        send(action[:action_name], action[:action_params])
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
      end
    end
  ensure
    Current.reset
  end

  private

  def send_attachment(blob_ids)
    return if conversation_a_tweet?

    return unless @rule.files.attached?

    blobs = ActiveStorage::Blob.where(id: blob_ids)

    return if blobs.blank?

    params = { content: nil, private: false, attachments: blobs }
    Messages::MessageBuilder.new(nil, @conversation, params).perform
  end

  def send_webhook_event(webhook_url)
    payload = @conversation.webhook_data.merge(event: "automation_event.#{@rule.event_name}")
    WebhookJob.perform_later(webhook_url[0], payload)
  end

  def send_message(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: false, content_attributes: { automation_rule_id: @rule.id } }
    Messages::MessageBuilder.new(nil, @conversation, params).perform
  end

  def add_private_note(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: true, content_attributes: { automation_rule_id: @rule.id } }
    Messages::MessageBuilder.new(nil, @conversation.reload, params).perform
  end

  def send_email_to_team(params)
    teams = Team.where(id: params[0][:team_ids])

    teams.each do |team|
      break unless @account.within_email_rate_limit?

      TeamNotifications::AutomationNotificationMailer.conversation_creation(@conversation, team, params[0][:message])&.deliver_now
      @account.increment_email_sent_count
    end
  end

  # CEVICO: move o card do CRM do contato da conversa para a coluna escolhida.
  # Ex.: "ao adicionar a etiqueta X, mover o card para Agendamento de Consulta".
  # Se o contato ainda não tem card no pipeline da coluna, o card é criado.
  def move_crm_card(stage_ids)
    stage = Crm::Stage.find_by(id: Array(stage_ids).first)
    return if stage.blank? || stage.pipeline.account_id != @account.id

    contact = @conversation.contact
    return if contact.blank?

    crm_contact = Crm::Contact.find_by(pipeline_id: stage.pipeline_id, contact_id: contact.id)
    if crm_contact
      return if crm_contact.stage_id == stage.id

      previous_stage = crm_contact.stage
      crm_contact.update!(stage_id: stage.id)
      trigger_crm_automations(crm_contact, stage, previous_stage)
    else
      Crm::Contact.create!(pipeline_id: stage.pipeline_id, contact_id: contact.id, stage_id: stage.id)
    end
  end

  def trigger_crm_automations(crm_contact, new_stage, previous_stage)
    CrmAutomationTriggerService.new(
      crm_contact: crm_contact, new_stage: new_stage,
      previous_stage: previous_stage, event_type: 'card_entered'
    ).call
    CrmAutomationTriggerService.new(
      crm_contact: crm_contact, new_stage: previous_stage,
      previous_stage: previous_stage, event_type: 'card_left'
    ).call
  end
end
