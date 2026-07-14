class CrmAutomationFireJob < ApplicationJob
  queue_as :default

  def perform(automation_id, contact_id, extra_payload = {})
    automation = Crm::Automation.find_by(id: automation_id)
    return unless automation&.active?

    contact = Contact.find_by(id: contact_id)
    return unless contact

    stage    = automation.stage
    pipeline = stage.pipeline

    payload = build_payload(automation, contact, stage, pipeline, extra_payload)

    case automation.action_type
    when 'webhook'
      fire_webhook(automation, payload)
    when 'apply_label'
      apply_label(automation, contact)
    when 'log_timeline'
      log_timeline(automation, contact, pipeline)
    when 'n8n_flow'
      fire_n8n(automation, payload)
    when 'move_card'
      move_card(automation, contact, pipeline)
    when 'notify_team'
      notify_team(automation, contact, pipeline, payload)
    when 'meta_ads_event'
      fire_meta_ads(automation, contact, pipeline)
    when 'google_ads_conversion'
      fire_google_ads(automation, contact, pipeline)
    when 'send_form'
      send_form(automation, contact, pipeline)
    when 'ai_analyze'
      ai_analyze(contact)
    when 'schedule_appointment'
      schedule_appointment(automation, contact, pipeline)
    end

    # Registra log de sucesso
    Crm::AutomationLog.create!(
      automation: automation,
      contact_id: contact_id,
      status:     'fired',
      payload:    payload,
      fired_at:   Time.current
    )
  rescue => e
    Rails.logger.error("[CrmAutomation] Failed for automation #{automation_id}: #{e.message}")
    Crm::AutomationLog.create!(
      automation_id: automation_id,
      contact_id:    contact_id,
      status:        'failed',
      payload:       extra_payload,
      error_message: e.message
    )
  end

  private

  def build_payload(automation, contact, stage, pipeline, extra)
    previous = extra[:previous_stage] || {}
    {
      event_type:            extra[:event_type] || 'automation_fired',
      automation_id:         automation.id,
      automation_name:       automation.name,
      contact_id:            contact.id,
      contact_name:          contact.name,
      contact_phone:         contact.phone_number,
      contact_email:         contact.email,
      funnel_id:             pipeline.id,
      funnel_name:           pipeline.name,
      previous_column_id:    previous[:id],
      previous_column_name:  previous[:name],
      current_column_id:     stage.id,
      current_column_name:   stage.name,
      tags:                  contact.label_list,
      fired_at:              Time.current.iso8601
    }
  end

  def fire_webhook(automation, payload)
    url = automation.action_config['webhook_url']
    return unless url.present?

    HTTParty.post(
      url,
      body:    payload.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: 10
    )
  end

  def apply_label(automation, contact)
    label_title = automation.action_config['label']
    return unless label_title.present?

    existing = contact.label_list
    contact.update!(label_list: (existing + [label_title]).uniq)
  end

  def log_timeline(automation, contact, pipeline)
    # Registra como nota interna na conversa mais recente do contato
    conversation = contact.conversations.order(created_at: :desc).first
    return unless conversation

    conversation.messages.create!(
      account:     pipeline.account,
      message_type: :activity,
      content:     "🤖 Automação \"#{automation.name}\" disparada automaticamente.",
      private:     true
    )
  end

  def move_card(automation, contact, pipeline)
    target_stage_id = automation.action_config['target_stage_id']
    return unless target_stage_id.present?

    target_stage = pipeline.stages.find_by(id: target_stage_id)
    return unless target_stage

    crm_contact = Crm::Contact.find_by(contact: contact, pipeline: pipeline)
    return unless crm_contact
    return if crm_contact.stage_id == target_stage.id # já está lá

    previous_stage = crm_contact.stage
    crm_contact.update!(stage: target_stage)

    # Dispara automações da nova coluna em background
    CrmAutomationTriggerService.new(
      crm_contact:    crm_contact,
      new_stage:      target_stage,
      previous_stage: previous_stage,
      event_type:     'card_entered'
    ).call
  end

  def notify_team(automation, contact, pipeline, payload)
    cfg = automation.action_config

    # Envia mensagem privada na última conversa do contato
    conversation = contact.conversations.order(created_at: :desc).first

    if conversation
      content_lines = ["📣 *Automação:* #{automation.name}"]
      content_lines << "👤 *Lead:* #{contact.name}" if contact.name.present?
      content_lines << "📌 *Etapa:* #{payload[:current_column_name]}" if payload[:current_column_name]
      content_lines << "💬 #{cfg['message']}" if cfg['message'].present?

      conversation.messages.create!(
        account:      pipeline.account,
        message_type: :activity,
        content:      content_lines.join("\n"),
        private:      true
      )
    end

    # Se configurado um agente específico para notificar
    if cfg['assignee_id'].present?
      assignee = User.find_by(id: cfg['assignee_id'])
      if assignee && conversation
        # Atribui a conversa ao agente
        conversation.update!(assignee: assignee)
      end
    end
  end

  def fire_meta_ads(automation, contact, pipeline)
    event_name = automation.action_config['meta_event_name'].presence || 'Lead'
    MetaAdsConversionsService.new(
      account:     pipeline.account,
      event_name:  event_name,
      contact:     contact,
      event_id:    "crm_auto_#{automation.id}_#{contact.id}_#{Time.current.to_i}",
    ).call
  end

  def fire_google_ads(automation, contact, pipeline)
    event_name = automation.action_config['ga4_event_name'].presence || 'generate_lead'
    extra = {}
    extra[:value]    = automation.action_config['conversion_value'].to_f if automation.action_config['conversion_value'].present?
    extra[:currency] = automation.action_config['currency'].presence || 'BRL'

    GoogleAdsConversionsService.new(
      account:    pipeline.account,
      event_name: event_name,
      contact:    contact,
      params:     extra,
    ).call
  end

  # Roda o Analista de Conversas (Claude) na conversa mais recente do
  # contato e salva o parecer — aparece no painel da conversa e no balão.
  def ai_analyze(contact)
    conversation = contact.conversations.order(created_at: :desc).first
    return unless conversation

    result = Crm::ConversationInsightService.new(conversation: conversation).call
    return if result[:error]

    attrs = conversation.additional_attributes || {}
    conversation.update!(additional_attributes: attrs.merge('ai_insight' => result.stringify_keys))
  end

  # Agente de Agendamento: lê a conversa, extrai nome/telefone/dia/hora/unidade
  # e cria o compromisso na Agenda (tarefa com unidade). Se a IA não confirmar
  # dia e hora, cria uma tarefa de revisão para a equipe completar.
  def schedule_appointment(automation, contact, pipeline)
    conversation = contact.conversations.order(created_at: :desc).first
    return unless conversation

    result = Crm::AppointmentExtractionService.new(conversation: conversation).call
    if result[:error]
      Rails.logger.warn("[CrmAutomation] schedule_appointment: #{result[:error]}")
      return
    end

    account = pipeline.account
    name    = result[:name].presence || contact.name.presence || 'Paciente'
    phone   = result[:phone].presence || contact.phone_number
    unit    = result[:unit].presence || automation.action_config['default_unit'].presence
    creator = account.administrators.first || account.users.first
    return unless creator

    notes = [result[:notes].presence, "Conversa ##{conversation.display_id} — agendado pela IA"].compact.join("\n")

    if result[:found] && result[:starts_at].present?
      # não duplica: mesmo paciente, mesmo horário
      return if account.tasks.exists?(due_at: result[:starts_at], title: "Consulta: #{name}")

      account.tasks.create!(
        title: "Consulta: #{name}",
        description: notes,
        due_at: result[:starts_at],
        unit: unit,
        phone: phone,
        procedure: result[:procedure].presence,
        doctor: result[:doctor].presence,
        task_type: 'consulta',
        priority: :medium,
        status: :todo,
        creator: creator
      )
      when_str = result[:starts_at].in_time_zone('America/Sao_Paulo').strftime('%d/%m/%Y às %H:%M')
      note = "📅 Consulta agendada pela IA: #{name} — #{when_str}" \
             "#{unit ? " (#{unit == 'tatuape' ? 'Tatuapé' : 'Av. Paulista'})" : ''}. Registrada na Agenda."
    else
      # sem dia/hora confirmados → tarefa de revisão para a equipe
      return if account.tasks.where(status: %i[todo doing]).exists?(title: "⚠️ Confirmar consulta: #{name}")

      account.tasks.create!(
        title: "⚠️ Confirmar consulta: #{name}",
        description: "A IA não encontrou dia e hora confirmados na conversa.\n#{notes}",
        unit: unit,
        phone: phone,
        procedure: result[:procedure].presence,
        doctor: result[:doctor].presence,
        task_type: 'consulta',
        priority: :high,
        status: :todo,
        creator: creator
      )
      note = "📅 A IA não conseguiu confirmar dia e hora da consulta de #{name} — criei uma tarefa de revisão para a equipe."
    end

    conversation.messages.create!(
      account: account,
      message_type: :activity,
      content: note,
      private: true
    )
  end

  # Envia o link do formulário (ex: perguntas pré-operatórias) na conversa
  # mais recente do contato. Cada contato recebe seu link único (assinado).
  def send_form(automation, contact, pipeline)
    form = Crm::Form.find_by(id: automation.action_config['form_id'], account: pipeline.account)
    return unless form&.active

    # não reenvia para quem já respondeu este formulário
    return if form.responses.where(contact_id: contact.id).where.not(completed_at: nil).exists?

    conversation = contact.conversations.order(created_at: :desc).first
    return unless conversation

    link = form.public_link_for(contact)
    template = automation.action_config['message'].presence ||
               'Para agilizar seu atendimento, responda nosso formulário (leva 2 minutinhos): {{link}}'
    content = template.gsub('{{link}}', link)
                      .gsub('{{nome}}', contact.name.to_s.split(' ').first.to_s)

    conversation.messages.create!(
      account: pipeline.account,
      inbox: conversation.inbox,
      message_type: :outgoing,
      content: content
    )
  end

  def fire_n8n(automation, payload)
    cfg    = automation.action_config
    stage  = automation.stage
    settings = CrmSetting.find_by(account: stage.pipeline.account)

    # 1) URL direta do webhook configurada no n8n (campo manual ou auto-detectado)
    webhook_url = cfg['n8n_webhook_url']

    # 2) Se tiver workflow_id + settings configuradas → tenta via webhook path cacheado
    if webhook_url.blank? && cfg['n8n_workflow_id'].present? && settings&.n8n_configured?
      cached = settings.n8n_workflows.find { |w| w['id'].to_s == cfg['n8n_workflow_id'].to_s }
      webhook_url = cached&.dig('webhook_url')

      # 3) Fallback: executa via API REST do n8n
      if webhook_url.blank?
        HTTParty.post(
          "#{settings.n8n_base_url_clean}/api/v1/workflows/#{cfg['n8n_workflow_id']}/execute",
          body:    { data: payload }.to_json,
          headers: {
            'Content-Type'  => 'application/json',
            'X-N8N-API-KEY' => settings.n8n_api_key,
          },
          timeout: 15
        )
        return
      end
    end

    return unless webhook_url.present?

    HTTParty.post(
      webhook_url,
      body:    payload.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: 15
    )
  end
end
