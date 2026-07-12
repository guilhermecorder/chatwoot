# Roda a cada 15 min (schedule.yml). Para cada robô ativo, procura conversas
# em que o PACIENTE ficou em silêncio (última mensagem foi do atendimento) e
# envia as "cutucadas" da cadência conforme o tempo decorrido.
#
# Âncora = primeira mensagem outgoing depois da última mensagem do paciente.
# Assim, enviar uma cutucada (nova outgoing) NÃO reinicia o cronômetro.
# Se o paciente responder (nova incoming), a âncora deixa de existir e o
# marcador é limpo — a cadência para sozinha.
class Crm::FollowupBotJob < ApplicationJob
  queue_as :scheduled_jobs

  LOOKBACK = 3.days # não cutuca conversas antigas demais

  def perform
    Crm::FollowupBot.active.includes(:inbox).find_each { |bot| process_bot(bot) }
  end

  private

  def process_bot(bot)
    return unless bot.within_window? # janela "começa em / para em"

    steps = bot.ordered_steps
    return if steps.blank?

    conversations(bot).find_each do |conversation|
      process_conversation(bot, conversation, steps)
    rescue StandardError => e
      Rails.logger.error("[CEVICO followup] conversa #{conversation.id}: #{e.message}")
    end
  end

  def conversations(bot)
    scope = bot.account.conversations
               .where(status: :open)
               .where('conversations.last_activity_at >= ?', LOOKBACK.ago)

    if bot.stage_scoped?
      # cards que estão na coluna → conversas desses contatos
      contact_ids = Crm::Contact.where(stage_id: bot.stage_id).select(:contact_id)
      scope = scope.where(contact_id: contact_ids)
      # caixa escolhida no robô de coluna → restringe a esse número
      scope = scope.where(inbox_id: bot.inbox_id) if bot.inbox_id.present?
    else
      scope = scope.where(inbox_id: bot.inbox_id)
    end
    scope
  end

  def process_conversation(bot, conversation, steps)
    return unless labels_match?(bot, conversation.contact)

    anchor = silence_anchor(conversation)
    return if anchor.nil? # paciente falou por último (ou sem mensagens do agente)

    state = followup_state(conversation, bot, anchor)
    hours = (Time.current - anchor) / 3600.0

    steps.each_with_index do |step, index|
      next if state['sent'].include?(index)
      next if hours < Crm::FollowupBot.step_delay_hours(step)

      send_nudge(bot, conversation, step)
      state['sent'] << index
    end

    persist_state(conversation, bot, anchor, state)
  end

  # Filtros "tem / não tem": só cutuca quem TEM todas as etiquetas exigidas
  # e NÃO TEM nenhuma das excluídas (etiquetas do contato).
  def labels_match?(bot, contact)
    return false if contact.blank?

    required = Array(bot.required_labels).map(&:to_s)
    excluded = Array(bot.exclude_labels).map(&:to_s)
    return true if required.empty? && excluded.empty?

    contact_labels = contact.label_list.map(&:to_s)
    return false if required.any? && (required - contact_labels).any?
    return false if excluded.any? && contact_labels.intersect?(excluded)

    true
  end

  # primeira outgoing depois da última incoming; nil se a última msg for do paciente
  def silence_anchor(conversation)
    msgs = conversation.messages.where(message_type: [:incoming, :outgoing])
    last = msgs.order(created_at: :desc).first
    return nil unless last&.outgoing?

    last_incoming_at = msgs.incoming.maximum(:created_at)
    scope = msgs.outgoing
    scope = scope.where('created_at > ?', last_incoming_at) if last_incoming_at
    scope.minimum(:created_at)
  end

  def followup_state(conversation, bot, anchor)
    stored = conversation.additional_attributes&.dig('cevico_followup') || {}
    same = stored['bot_id'] == bot.id && stored['anchor'] == anchor.iso8601
    same ? { 'sent' => Array(stored['sent']) } : { 'sent' => [] }
  end

  def persist_state(conversation, bot, anchor, state)
    attrs = conversation.additional_attributes || {}
    attrs['cevico_followup'] = { 'bot_id' => bot.id, 'anchor' => anchor.iso8601, 'sent' => state['sent'] }
    conversation.update_column(:additional_attributes, attrs)
  end

  def send_nudge(bot, conversation, step)
    attrs = { cevico_followup_bot_id: bot.id }
    # etapa de MENSAGEM MODELO: envia o template oficial (funciona fora da
    # janela de 24h do WhatsApp — ideal para cadências em dias)
    attrs[:template_params] = render_template_params(step['template_params'], conversation) if step['template_params'].present?

    conversation.messages.create!(
      account_id: bot.account_id,
      inbox_id: conversation.inbox_id, # robô por coluna envia na caixa da própria conversa
      message_type: :outgoing,
      content: render_message(step['message'], conversation),
      sender: bot.sender,
      additional_attributes: attrs
    )
  end

  # variáveis simples: [nome] → primeiro nome do paciente
  def render_message(text, conversation)
    name = conversation.contact&.name.to_s.split.first || ''
    text.to_s.gsub(/\[nome\]/i, name)
  end

  # substitui [nome] também nos parâmetros preenchidos do modelo
  def render_template_params(params, conversation)
    JSON.parse(render_message(params.to_json, conversation))
  rescue JSON::ParserError
    params
  end
end
