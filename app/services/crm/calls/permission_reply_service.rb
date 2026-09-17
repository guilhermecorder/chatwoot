# Resposta do paciente ao pedido de permissão para ligar (interactive
# call_permission_reply): grava no contato (additional_attributes.
# cevico_call_permission), deixa uma nota na conversa e avisa o time.
class Crm::Calls::PermissionReplyService
  attr_reader :channel, :value

  def initialize(channel:, value:)
    @channel = channel
    @value = (value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value.to_h).with_indifferent_access
  end

  def perform
    message = Array(value[:messages]).first
    reply = message&.dig(:interactive, :call_permission_reply)
    return if reply.blank?

    contact = find_contact(message[:from].to_s.gsub(/\D/, ''))
    return if contact.nil?

    permission = build_permission(reply)
    Cevico::AttributeMerge.merge!(contact) { |attrs| attrs.merge('cevico_call_permission' => permission) }
    leave_note(contact, permission)
    Crm::Calls::Broadcaster.push(account, 'cevico_call.permission',
                                 contact_id: contact.id, status: permission['status'], expires_at: permission['expires_at'])
  end

  private

  def account
    channel.account
  end

  def inbox
    channel.inbox
  end

  def find_contact(wa_id)
    inbox.contact_inboxes.find_by(source_id: wa_id)&.contact || Task.match_contact(account, wa_id)
  end

  def build_permission(reply)
    expires = reply[:expiration_timestamp]
    {
      'status' => reply[:response].to_s == 'accept' ? 'accept' : 'reject',
      'permanent' => reply[:is_permanent] == true,
      'expires_at' => expires.present? ? Time.zone.at(expires.to_i).iso8601 : nil,
      'replied_at' => Time.current.iso8601
    }
  end

  def leave_note(contact, permission)
    conversation = account.conversations.where(inbox_id: inbox.id, contact_id: contact.id).order(created_at: :desc).first
    return unless conversation

    conversation.messages.create!(
      account_id: account.id, inbox_id: inbox.id, message_type: :activity, private: true, content: note_text(permission)
    )
  end

  def note_text(permission)
    return '🚫 Paciente não autorizou ligações pelo WhatsApp' if permission['status'] == 'reject'
    return '✅ Paciente autorizou ligações pelo WhatsApp (sem prazo)' if permission['permanent'] || permission['expires_at'].blank?

    until_at = Time.zone.parse(permission['expires_at']).in_time_zone(Crm::Calls::Settings::TZ)
    "✅ Paciente autorizou ligações até #{until_at.strftime('%d/%m %H:%M')}"
  end
end
