# DESPACHANTE (item 168): manda os envios da fila cuja hora chegou, dentro
# da janela da conta, respeitando etiquetas de silêncio e o teto diário.
# Modelo aprovado sai pelo Crm::SendTemplateService (chega com a janela de
# 24h fechada); texto livre só sai se a conversa ainda aceita resposta.
# Envio pendente há mais de 12 h vira "expirou" (ninguém aprovou / hora
# passou demais) — nunca manda "sua cirurgia é amanhã" dois dias depois.
class Crm::Journey::Dispatcher
  TZ = Crm::Journey::Settings::TZ
  EXPIRE_AFTER = 12.hours
  TEXT_WINDOW_CLOSED = 'A janela de 24h desta conversa está fechada — só mensagem modelo chega.'.freeze

  attr_reader :account, :now, :settings

  def initialize(account:, now: nil)
    @account = account
    @now = (now || TZ.now).in_time_zone(TZ)
    @settings = Crm::Journey::Settings.new(account)
  end

  # devolve { sent:, failed:, skipped:, expired: }
  def perform
    result = Hash.new(0)
    result[:expired] = expire_stale!
    return result unless settings.within_hours?(now)

    budget = settings.daily_cap - sent_today
    Crm::JourneySend.where(account: account).due(now).includes(:journey_message, :contact).find_each do |send|
      break if budget <= 0

      outcome = dispatch(send)
      result[outcome] += 1
      budget -= 1 if outcome == :sent
    end
    result
  end

  # envia UM (usado pela aprovação manual também). Devolve :sent | :failed | :skipped
  def dispatch(send)
    message = send.journey_message
    contact = send.contact
    blocked = blocker_for(message, contact)
    return finish(send, blocked[0], blocked[1]) if blocked

    inbox = message.inbox || account.inboxes.find_by(id: message.inbox_id)
    return finish(send, 'failed', 'Escolha a caixa do WhatsApp da mensagem') if inbox.nil?

    deliver(send, message, inbox, contact)
  rescue StandardError => e
    Rails.logger.error("[CEVICO jornada] envio #{send.id}: #{e.message}")
    finish(send, 'failed', e.message.truncate(300))
  end

  # texto final que o paciente lê (modelo com as variáveis trocadas)
  def preview_text(message, values)
    return Crm::Journey::Variables.substitute(message.text, values) if message.mode == 'text'

    body = (message.template_params || {}).dig('processed_params', 'body') || {}
    base = message.message_preview.presence || message.name
    text = body.reduce(base) { |acc, (k, v)| acc.gsub("{{#{k}}}", Crm::Journey::Variables.substitute(v, values)) }
    text.gsub('{{contact.name}}', values['nome'].to_s)
  end

  private

  def deliver(send, message, inbox, contact)
    values = Crm::Journey::Variables.build(send.source, contact, settings)
    conversation = message.mode == 'text' ? send_text(message, inbox, contact, values) : send_template(message, inbox, contact, values)
    return finish(send, 'failed', @last_error || 'O envio não saiu (veja a caixa e o modelo)') if conversation.nil?

    send.update!(status: 'sent', sent_at: Time.current, conversation: conversation, variables: values,
                 preview: preview_text(message, values), error: nil)
    :sent
  end

  # [status, motivo] quando o envio não deve sair; nil quando pode
  def blocker_for(message, contact)
    return ['skipped', 'Mensagem desligada'] unless message&.active?
    return ['skipped', 'Paciente sem telefone'] if contact.nil? || contact.phone_number.blank?
    # 🚧 item 231 (cerca dos parceiros)
    return ['skipped', 'Paciente de parceiro do Oftalmofácil: sem mensagens automáticas'] if Crm::PartnerGuard.partner_contact?(contact)
    return ['skipped', 'Paciente pediu para não receber mensagens'] if message.respect_quiet && settings.quiet?(contact.label_list)

    nil
  end

  def sent_today
    day_start = TZ.local(now.year, now.month, now.day)
    Crm::JourneySend.where(account: account, status: 'sent', sent_at: day_start..now).count
  end

  def expire_stale!
    Crm::JourneySend.where(account: account, status: %w[queued pending_review])
                    .where(scheduled_for: ...(now - EXPIRE_AFTER))
                    .update_all(status: 'expired', error: 'A hora passou sem envio', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def finish(send, status, error)
    send.update!(status: status, error: error)
    status.to_sym
  end

  def send_template(message, inbox, contact, values)
    params = Crm::Journey::Variables.apply(message.template_params, values)
    source = Crm::TemplateSource.new(account, inbox, nil, params, message.message_preview, message.name)
    Crm::SendTemplateService.new(source: source, contact: contact).perform
  end

  def send_text(message, inbox, contact, values)
    finder = Crm::Calls::ConversationFinder.new(inbox: inbox, wa_id: contact.phone_number.to_s.delete('^0-9'),
                                                name: contact.name, contact: contact)
    conversation = finder.conversation
    unless conversation.can_reply?
      @last_error = TEXT_WINDOW_CLOSED
      return nil
    end
    text = Crm::Journey::Variables.substitute(message.text, values)
    conversation.messages.create!(account_id: account.id, inbox_id: inbox.id, message_type: :outgoing,
                                  content: text, additional_attributes: { 'cevico_journey' => message.id })
    conversation
  end
end
