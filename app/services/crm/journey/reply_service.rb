# RESPOSTA DO PACIENTE (item 168): quem recebeu uma mensagem da jornada que
# ESPERA resposta (ex.: confirmação de cirurgia) e responde "confirmo/sim"
# → envio marcado como confirmado + etiqueta + nota ✅ na conversa;
# "não/remarcar/cancelar" → marcado como recusado + nota ⚠️ + aviso no Radar
# para a atendente ligar/remarcar. Chamado pelo CrmListener a cada mensagem.
class Crm::Journey::ReplyService
  REPLY_WINDOW = 3.days
  DECLINE_WORDS = Regexp.union(
    /\b(nao|n|nope|negativo|cancelar|cancela|desmarcar|desmarca|remarcar|remarca|adiar|reagendar|transferir)\b/i,
    /\b(nao\s+vou|nao\s+posso|nao\s+consigo|nao\s+da|outro\s+dia|outra\s+data|impossivel)\b/i
  )
  CONFIRM_WORDS = Regexp.union(
    /\b(sim|s|confirmo|confirmado|confirmada|confirmar|estarei|confirmando)\b/i,
    /\b(vou\s+sim|pode\s+confirmar|presenca\s+confirmada|ok|okay|blz|beleza|combinado|certo|claro|com\s+certeza)\b/i
  )

  def self.handle(message, contact)
    return if message.message_type != 'incoming'

    new(message, contact).handle
  rescue StandardError => e
    Rails.logger.error("[CEVICO jornada] resposta: #{e.message}")
    nil
  end

  def initialize(message, contact)
    @message = message
    @contact = contact
  end

  def handle
    send = pending_send
    return nil if send.nil?

    verdict = classify(@message.content)
    return nil if verdict.nil?

    send.update!(reply: verdict, replied_at: Time.current, reply_text: @message.content.to_s.truncate(500))
    verdict == 'confirmed' ? confirmed!(send) : declined!(send)
    verdict
  end

  # "sim" e "não" na mesma frase: o "não" vence (é o caso de quem remarca)
  def classify(raw)
    return 'confirmed' if raw.to_s.include?('👍')

    text = raw.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.strip
    return nil if text.blank?
    return 'declined' if text.match?(DECLINE_WORDS)
    return 'confirmed' if text.match?(CONFIRM_WORDS)

    nil
  end

  private

  def pending_send
    Crm::JourneySend.joins(:journey_message)
                    .where(account_id: @contact.account_id, contact_id: @contact.id)
                    .where(cevico_journey_messages: { expects_reply: true })
                    .awaiting_reply.where(sent_at: REPLY_WINDOW.ago..)
                    .order(sent_at: :desc).first
  end

  def confirmed!(send)
    label = send.journey_message.confirm_label.presence
    @contact.add_labels([label]) if label
    note(send, "✅ Paciente CONFIRMOU (#{send.journey_message.name}) respondendo pelo WhatsApp: “#{@message.content.to_s.truncate(80)}”")
  end

  def declined!(send)
    note(send, "⚠️ Paciente respondeu que NÃO vai / quer remarcar (#{send.journey_message.name}): “#{@message.content.to_s.truncate(80)}”")
    conversation = @message.conversation
    conversation.update!(status: :open) if conversation && !conversation.open?
    Crm::Journey::RadarAlert.push(send, @message) if send.journey_message.decline_alert
  end

  def note(send, text)
    conversation = @message.conversation || send.conversation
    return unless conversation

    conversation.messages.create!(account_id: @contact.account_id, inbox_id: conversation.inbox_id,
                                  message_type: :outgoing, private: true, content: text)
  end
end
