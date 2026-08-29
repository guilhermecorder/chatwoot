class CrmAutomationFireJob < ApplicationJob
  queue_as :default

  def perform(automation_id, contact_id, extra_payload = {})
    automation = Crm::Automation.find_by(id: automation_id)
    return unless automation&.active?

    stage    = automation.stage
    pipeline = stage.pipeline

    # contato SEMPRE resolvido dentro da conta da automação (sem isso, um
    # contact_id de outra conta — o endpoint trigger recebe cru — vazava)
    contact = pipeline.account.contacts.find_by(id: contact_id)
    return unless contact

    return unless should_fire?(automation, contact)

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
    when 'closing_extract'
      closing_extract(contact, pipeline)
    when 'nps_score'
      nps_score(contact)
    when 'set_value'
      set_value(automation, contact, pipeline)
    end

    stamp_automation_trail(automation, contact, stage)

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

  # Condições que seguram o disparo:
  # (a) automação de "entrou na coluna" com ATRASO: se o paciente já saiu da
  #     coluna nesse meio tempo, não dispara (evita mensagem fora de contexto
  #     pra quem já avançou). Disparo imediato (sem atraso) não é afetado.
  # (b) condição "caixa de chegada" (missão 03/08): automação restrita a
  #     leads que CHEGARAM pela(s) caixa(s) escolhida(s) — ex.: evento de
  #     conversão do Google só para a caixa GOOGLE. Mesma régua do Dashboard
  #     CRM (caixa da primeira conversa do contato).
  def should_fire?(automation, contact)
    return false if automation.trigger_type == 'card_entered' &&
                    automation.delay_minutes.to_i.positive? &&
                    !card_in_stage?(automation, contact)

    entry_inbox_matches?(automation, contact)
  end

  def entry_inbox_matches?(automation, contact)
    wanted = Array(automation.action_config&.dig('inbox_ids')).map(&:to_i).reject(&:zero?)
    return true if wanted.empty?

    # mesma régua do Dashboard: primeira conversa numa PORTA DE ENTRADA
    # (caixa de captação) vence; sem nenhuma, primeira conversa geral
    capture_ids = Crm::LeadsUniverse.capture_inbox_ids(contact.account)
    scope = contact.conversations
    entry_inbox_id = if capture_ids.any?
                       scope.reorder(Arel.sql("(CASE WHEN inbox_id IN (#{capture_ids.join(',')}) THEN 0 ELSE 1 END), created_at, id"))
                            .pick(:inbox_id)
                     else
                       scope.reorder(:created_at, :id).pick(:inbox_id)
                     end
    return false if entry_inbox_id.nil? # lead sem conversa não pertence a caixa nenhuma

    wanted.include?(entry_inbox_id)
  end

  # o card do contato ainda está na coluna da automação? (usado p/ segurar
  # disparo atrasado de card_entered quando o paciente já avançou)
  def card_in_stage?(automation, contact)
    Crm::Contact.exists?(
      contact_id: contact.id,
      pipeline_id: automation.stage.pipeline_id,
      stage_id: automation.stage_id
    )
  end

  # trilha de automações do PACIENTE: cada disparo fica gravado no contato
  # (o Espaço do Paciente mostra "por quais automações ele passou e quando" —
  # é assim que dá pra saber qual automação realmente ajudou)
  def stamp_automation_trail(automation, contact, stage)
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      trail = Array(attrs['cevico_automation_trail'])
      trail << {
        'name' => automation.name,
        'action' => automation.action_type,
        'stage' => stage&.name,
        'at' => Time.current.iso8601
      }
      attrs.merge('cevico_automation_trail' => trail.last(60))
    end
  rescue StandardError => e
    Rails.logger.warn "[CrmAutomationFire] trilha: #{e.message}"
  end

  # A conversa que os agentes leem é a de ATIVIDADE mais recente — não a
  # criada por último. Paciente que segue conversando na mesma conversa
  # antiga (padrão no WhatsApp) era lido errado quando existia qualquer
  # conversa mais nova em outra caixa/canal.
  def latest_conversation(contact)
    contact.conversations.order(Arel.sql('last_activity_at DESC NULLS LAST, created_at DESC')).first
  end

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
    # já tinha a etiqueta → nada a fazer (e nada de redisparar cadeia)
    return if existing.map(&:downcase).include?(label_title.downcase)

    contact.update!(label_list: (existing + [label_title]).uniq)

    # A etiqueta NOVA dispara as automações "Etiqueta adicionada" da coluna
    # atual do card — permite cadeias: mensagem com "catarata" → etiqueta
    # "catarata" → mover de coluna / definir valor. Antes, só a etiqueta
    # aplicada pela tela disparava; a aplicada por automação ficava muda.
    pipeline = automation.stage.pipeline
    card = Crm::Contact.find_by(contact_id: contact.id, pipeline_id: pipeline.id)
    return unless card&.stage

    CrmAutomationTriggerService.new(crm_contact: card, new_stage: card.stage,
                                    event_type: 'label_added', label: label_title).call
  end

  def log_timeline(automation, contact, pipeline)
    # Registra como nota interna na conversa mais recente do contato
    conversation = latest_conversation(contact)
    return unless conversation

    # inbox é obrigatória no Message — sem ela a nota falhava em silêncio
    conversation.messages.create!(
      account:     pipeline.account,
      inbox:       conversation.inbox,
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
    conversation = latest_conversation(contact)

    if conversation
      content_lines = ["📣 *Automação:* #{automation.name}"]
      content_lines << "👤 *Lead:* #{contact.name}" if contact.name.present?
      content_lines << "📌 *Etapa:* #{payload[:current_column_name]}" if payload[:current_column_name]
      content_lines << "💬 #{cfg['message']}" if cfg['message'].present?

      conversation.messages.create!(
        account:      pipeline.account,
        inbox:        conversation.inbox,
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
  # Adiciona/define o preço (value) do card do contato neste funil.
  # Modos: always (substitui) | if_empty (só se o card não tem valor) |
  # add (soma ao valor atual)
  def set_value(automation, contact, pipeline)
    amount = automation.action_config&.dig('value').to_f
    return if amount <= 0

    card = Crm::Contact.find_by(contact_id: contact.id, pipeline_id: pipeline.id)
    return unless card

    case automation.action_config&.dig('value_mode').presence || 'always'
    when 'if_empty'
      card.update!(value: amount) if card.value.to_f.zero?
    when 'add'
      card.update!(value: card.value.to_f + amount)
    else
      card.update!(value: amount)
    end
  end

  # Monitor de Fechamento: extrai valor/forma de pagamento/data da cirurgia
  # e grava no contato + preenche o valor do card se estiver vazio.
  def closing_extract(contact, pipeline)
    conversation = latest_conversation(contact)
    return unless conversation

    result = Crm::SurgeryClosingService.new(conversation: conversation).call
    if result[:error]
      Rails.logger.warn("[CrmAutomation] closing_extract: #{result[:error]}")
      return
    end
    return unless result[:closed]

    closing = {
      'value' => result[:value].positive? ? result[:value] : nil,
      'payment' => result[:payment].presence,
      'surgery_date' => result[:surgery_date]&.iso8601,
      'note' => result[:note].presence,
      'at' => Time.current.iso8601
    }.compact
    Cevico::AttributeMerge.merge!(contact) { |attrs| attrs.merge('surgery_closing' => closing) }

    # valor do card: preenche se ainda estiver vazio (não sobrescreve o manual)
    card = Crm::Contact.find_by(pipeline_id: pipeline.id, contact_id: contact.id)
    card.update!(value: result[:value]) if card && result[:value].positive? && card.value.to_f.zero?
  end

  # Agente de NPS: identifica a nota 0-10 e etiqueta o contato com a faixa
  # (nps-9-10 / nps-7-8 / nps-0-6) — alimenta o bloco de NPS do Dashboard CRM.
  def nps_score(contact)
    conversation = latest_conversation(contact)
    return unless conversation

    result = Crm::NpsService.new(conversation: conversation).call
    if result[:error]
      Rails.logger.warn("[CrmAutomation] nps_score: #{result[:error]}")
      return
    end
    return unless result[:answered]

    label = Crm::NpsService.label_for(result[:score])
    kept = contact.label_list.reject { |l| Crm::NpsService::NPS_LABELS.include?(l.to_s) }
    contact.update_labels(kept + [label])

    nps = { 'score' => result[:score], 'comment' => result[:comment].presence, 'at' => Time.current.iso8601 }.compact
    Cevico::AttributeMerge.merge!(contact) { |attrs| attrs.merge('nps' => nps) }
  end

  def ai_analyze(contact)
    conversation = latest_conversation(contact)
    return unless conversation

    result = Crm::ConversationInsightService.new(conversation: conversation).call
    return if result[:error]

    # merge atômico: a chamada de IA demora segundos — gravar com snapshot
    # velho apagava chaves recém-escritas (foi o gatilho do incidente do
    # follow-up de 18/07: o marcador de cutucadas enviadas sumia e o robô
    # reenviava a cada rodada)
    Cevico::AttributeMerge.merge!(conversation) do |attrs|
      attrs.merge('ai_insight' => result.stringify_keys)
    end
  end

  # Agente de Agendamento: lê a conversa e escreve o resultado na Agenda —
  # cria, REAGENDA ou CANCELA a consulta; sem dia/hora confirmados, cria uma
  # tarefa de revisão. A lógica inteira mora no Crm::AppointmentApplier
  # (rodada 148) — mesmo caminho da releitura automática do CrmListener.
  def schedule_appointment(automation, contact, pipeline)
    Crm::AppointmentApplier.call(
      account: pipeline.account,
      contact: contact,
      conversation: latest_conversation(contact),
      default_unit: automation.action_config['default_unit'].presence
    )
  end

  # Envia o link do formulário (ex: perguntas pré-operatórias) na conversa
  # mais recente do contato. Cada contato recebe seu link único (assinado).
  def send_form(automation, contact, pipeline)
    form = Crm::Form.find_by(id: automation.action_config['form_id'], account: pipeline.account)
    return unless form&.active

    # não reenvia para quem já respondeu este formulário
    return if form.responses.where(contact_id: contact.id).where.not(completed_at: nil).exists?
    # nem para quem JÁ RECEBEU o link há pouco (evita rajada de links quando o
    # gatilho é "mensagem recebida": o paciente responde, dispara de novo...)
    return if form_sent_recently?(contact, form)

    conversation = latest_conversation(contact)
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
    mark_form_sent(contact, form)
    # contador de ENVIOS do hub dos Formulários (envio × respostas × %)
    Crm::Form.where(id: form.id).update_all('sent_count = sent_count + 1') # rubocop:disable Rails/SkipsModelValidations
  end

  FORM_RESEND_COOLDOWN = 7.days

  def form_sent_recently?(contact, form)
    sent_at = contact.additional_attributes&.dig('cevico_forms_sent', form.id.to_s)
    return false if sent_at.blank?

    Time.zone.parse(sent_at.to_s) > FORM_RESEND_COOLDOWN.ago
  rescue ArgumentError, TypeError
    false
  end

  def mark_form_sent(contact, form)
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      sent = attrs['cevico_forms_sent'] || {}
      sent[form.id.to_s] = Time.current.iso8601
      attrs.merge('cevico_forms_sent' => sent)
    end
  rescue StandardError => e
    Rails.logger.warn "[CrmAutomationFire] mark_form_sent: #{e.message}"
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
