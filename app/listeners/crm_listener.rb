class CrmListener < BaseListener
  # Toda nova conversa garante um card no funil de entrada do CRM.
  # O card nasce na primeira coluna (menor position) do primeiro pipeline;
  # se o contato já tem card nesse pipeline, nada acontece.
  def conversation_created(event)
    conversation, account = extract_conversation_and_account(event)
    contact = conversation.contact
    return if contact.blank?

    pipeline = account.crm_pipelines.order(:position).first
    return if pipeline.blank?

    entry_stage = pipeline.stages.order(:position).first
    return if entry_stage.blank?

    Crm::Contact.find_or_create_by!(contact_id: contact.id, pipeline_id: pipeline.id) do |card|
      card.stage_id = entry_stage.id
      card.origin = conversation.inbox&.name
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    # corrida entre eventos simultâneos do mesmo contato — card já existe
    nil
  end

  # Gatilho "Mensagem criada" das automações de coluna: quando chega uma
  # mensagem na conversa, dispara as automações desse gatilho na coluna
  # onde o card do contato está AGORA. Config na automação (action_config):
  # - message_direction: incoming (padrão) | outgoing | both
  # - message_contains: frases-chave (vírgula = OU, "aspas" = frase exata;
  #   ignora acento/maiúsculas). Vazio = qualquer mensagem.
  # - throttle_minutes: no máximo 1 disparo a cada N min por contato
  #   (0/vazio = sem limite — ex.: acionar fluxo n8n a cada mensagem)
  def message_created(event)
    message = event.data[:message]
    return if message.blank? || message.private?
    return unless %w[incoming outgoing].include?(message.message_type)

    contact = message.conversation&.contact
    return if contact.blank?

    # 2 consultas leves por mensagem, indexadas — barato mesmo em produção
    stage_ids = Crm::Contact.where(contact_id: contact.id).pluck(:stage_id).compact
    return if stage_ids.empty?

    Crm::Automation.where(stage_id: stage_ids, active: true, trigger_type: 'message_created').find_each do |automation|
      next unless direction_matches?(automation, message)
      next unless content_matches?(automation, message)
      next if throttled?(automation, contact)

      delay = automation.delay_minutes.to_i
      job = delay.positive? ? CrmAutomationFireJob.set(wait: delay.minutes) : CrmAutomationFireJob
      job.perform_later(automation.id, contact.id, {
                          event_type: 'message_created',
                          message_id: message.id,
                          message_direction: message.message_type
                        })
    end
  end

  private

  def direction_matches?(automation, message)
    direction = automation.action_config&.dig('message_direction').presence || 'incoming'
    direction == 'both' || message.message_type == direction
  end

  # frases-chave: mesma sintaxe do Tratamento de dados (vírgula = OU,
  # "aspas" = frase exata como uma peça só), ignorando acento e caixa
  def content_matches?(automation, message)
    raw = automation.action_config&.dig('message_contains').to_s
    return true if raw.blank?

    terms = Crm::RetroLabelJob.parse_terms(raw)
    return true if terms.empty?

    content = normalize_text(message.content)
    return false if content.blank?

    terms.any? { |term| content.include?(normalize_text(term)) }
  end

  def normalize_text(text)
    ActiveSupport::Inflector.transliterate(text.to_s).downcase
  end

  def throttled?(automation, contact)
    throttle = automation.action_config&.dig('throttle_minutes').to_i
    return false unless throttle.positive?

    Crm::AutomationLog.where(automation: automation, contact_id: contact.id)
                      .where('fired_at > ?', throttle.minutes.ago)
                      .exists?
  end
end
