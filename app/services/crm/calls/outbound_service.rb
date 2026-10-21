# Ligar para o paciente (item 167): confere a caixa configurada e o
# telefone, pergunta à Meta se ele deu permissão, manda o pedido de
# permissão (mensagem interativa) e dispara o connect que cria a ligação
# de saída. Devolve hashes de resultado — o controller só traduz em HTTP.
class Crm::Calls::OutboundService
  NO_PERMISSION = 'O paciente ainda não autorizou ligações pelo WhatsApp. Peça a permissão primeiro.'.freeze
  NO_INBOX = 'Escolha a caixa do WhatsApp (API oficial) em Configurações → Ligações antes de ligar.'.freeze
  NO_PHONE = 'Este paciente não tem telefone cadastrado.'.freeze

  attr_reader :account, :user, :contact, :preferred_inbox_id

  # preferred_inbox_id: a caixa da conversa aberta (se for uma das configuradas)
  def initialize(account:, user:, contact:, preferred_inbox_id: nil)
    @account = account
    @user = user
    @contact = contact
    @preferred_inbox_id = preferred_inbox_id
  end

  # { status: temporary|permanent|no_permission|unknown, expires_at, can_call, can_request }
  def permission_status
    error = ready_error
    return { status: 'unknown', expires_at: nil, can_call: false, can_request: false, error: error } if error

    permission_info
  end

  # pedido de permissão com os limites da Meta travados localmente
  # (Crm::Calls::PermissionRequests: 1 por 24 h, 2 por 7 dias)
  def request_permission
    error = ready_error || Crm::Calls::PermissionRequests.limit_error(contact)
    return { ok: false, error: error } if error

    client.send_permission_request(to: wa_id, text: settings.permission_message)
    Crm::Calls::PermissionRequests.remember!(contact)
    leave_note('📨 Pedido de permissão para ligar enviado ao paciente pelo WhatsApp')
    { ok: true }
  rescue Crm::Calls::MetaError => e
    { ok: false, error: "A Meta não enviou o pedido: #{e.message}" }
  end

  def initiate(sdp_offer)
    error = ready_error || hours_error
    return { ok: false, error: error } if error

    permission = permission_info
    return { ok: false, error: NO_PERMISSION, permission: permission } unless permission[:can_call]

    { ok: true, call: connect_call(sdp_offer) }
  rescue Crm::Calls::MetaError => e
    { ok: false, error: "A Meta não iniciou a ligação: #{e.message}" }
  end

  private

  def settings
    @settings ||= Crm::Calls::Settings.new(account)
  end

  def inbox
    @inbox ||= settings.outbound_inbox_for(contact: contact, preferred_id: preferred_inbox_id)
  end

  def wa_id
    @wa_id ||= contact.phone_number.to_s.gsub(/\D/, '')
  end

  def client
    @client ||= Crm::Calls::MetaClient.new(inbox.channel)
  end

  # ligação manual de saída respeita o horário configurado (como a recebida)
  def hours_error
    return nil unless settings.business_hours_only? && !settings.within_hours?

    "Fora do horário de ligações (#{settings.hours['start']}–#{settings.hours['end']})."
  end

  def ready_error
    return NO_INBOX if inbox.nil? || !inbox.channel.is_a?(Channel::Whatsapp)
    return NO_PHONE if wa_id.length < 8

    nil
  end

  def connect_call(sdp_offer)
    meta_call_id = client.connect(to: wa_id, sdp: sdp_offer, callback_data: "cevico:#{account.id}:#{contact.id}")
    call = build_call(meta_call_id)
    call.add_event('connect_requested', user_id: user.id)
    call.save!
    call
  end

  def build_call(meta_call_id)
    finder = Crm::Calls::ConversationFinder.new(inbox: inbox, wa_id: wa_id, name: contact.name, contact: contact)
    Crm::Call.new(
      account: account, inbox: inbox, contact: contact, conversation: finder.conversation, user: user,
      meta_call_id: meta_call_id, direction: :outbound, status: :ringing, wa_id: wa_id, display_name: contact.name,
      started_at: Time.current, simulated: client.simulated?
    )
  end

  # permissão na Meta; se ela não responder, vale a última resposta do
  # paciente gravada no contato (PermissionReplyService)
  def permission_info
    from_meta(client.call_permissions(wa_id))
  rescue Crm::Calls::MetaError => e
    from_contact(e)
  end

  def from_meta(data)
    permission = data['permission'] || {}
    actions = Array(data['actions']).index_by { |a| a['action_name'] }
    status = permission['status'].presence || 'unknown'
    can_call = actions.dig('start_call', 'can_perform_action')
    can_call = %w[temporary permanent].include?(status) if can_call.nil?
    expires = permission['expiration_time'].present? ? Time.zone.at(permission['expiration_time'].to_i).iso8601 : nil
    { status: status, expires_at: expires, can_call: can_call == true,
      can_request: actions.dig('send_call_permission_request', 'can_perform_action') != false }
  end

  def from_contact(error)
    local = (contact.additional_attributes || {})['cevico_call_permission'] || {}
    granted = local_grant?(local)
    status = 'unknown'
    status = local['permanent'] == true ? 'permanent' : 'temporary' if granted
    { status: status, expires_at: local['expires_at'], can_call: granted, can_request: true, error: error.message }
  end

  def local_grant?(local)
    return false unless local['status'] == 'accept'
    return true if local['permanent'] == true

    valid_until = parse_time(local['expires_at'])
    valid_until.present? && valid_until > Time.current
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def leave_note(text)
    finder = Crm::Calls::ConversationFinder.new(inbox: inbox, wa_id: wa_id, name: contact.name, contact: contact)
    finder.conversation.messages.create!(account_id: account.id, inbox_id: inbox.id, message_type: :activity,
                                         private: true, content: text)
  rescue StandardError => e
    Rails.logger.warn("[CEVICO calls] nota não gravada: #{e.message}")
  end
end
