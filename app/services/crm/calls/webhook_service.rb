# Processa o webhook `calls` da Meta (eventos connect/terminate e os
# statuses RINGING/ACCEPTED/REJECTED): cria a ligação, acha/cria paciente e
# conversa, avisa o time pelo cable e fecha a ligação no terminate. A
# simulação local (rake cevico:calls_simulate) passa por AQUI também, com a
# ligação marcada simulated — mesmo código do fluxo real, sem Graph/WebRTC.
class Crm::Calls::WebhookService
  END_REASONS = { 'completed' => 'completed', 'missed' => 'not_answered', 'rejected' => 'rejected',
                  'failed' => 'failed', 'canceled' => 'canceled' }.freeze

  attr_reader :channel, :value

  delegate :account, :inbox, to: :channel

  def initialize(channel:, value:, simulated: false)
    @channel = channel
    @value = normalize(value)
    @simulated = simulated
  end

  def perform
    Array(value[:calls]).each { |raw| handle_call(raw) }
    Array(value[:statuses]).each { |raw| handle_status(raw) if raw[:type].to_s == 'call' }
  end

  private

  def normalize(raw)
    hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    hash.with_indifferent_access
  end

  def settings
    @settings ||= Crm::Calls::Settings.new(account)
  end

  def handle_call(raw)
    case raw[:event].to_s
    when 'connect' then outbound_answer?(raw) ? handle_outbound_answer(raw) : handle_inbound_connect(raw)
    when 'terminate' then handle_terminate(raw)
    else Rails.logger.info("[CEVICO calls] evento ignorado: #{raw[:event]} (#{raw[:id]})")
    end
  end

  def outbound_answer?(raw)
    raw[:direction].to_s == 'BUSINESS_INITIATED' || raw.dig(:session, :sdp_type).to_s == 'answer'
  end

  # ── paciente ligou ────────────────────────────────────────────────────────
  def handle_inbound_connect(raw)
    if (existing = find_call(raw[:id], quiet: true))
      # webhook repetido: só lembra o time se ainda estiver tocando
      existing.add_event('connect_again', raw)
      existing.save!
      broadcast_ringing(existing) if existing.ringing?
      return
    end

    call = build_inbound_call(raw)
    call.add_event('connect', raw)
    call.save!

    return reject_outside_hours(call) if settings.business_hours_only? && !settings.within_hours?

    broadcast_ringing(call)
  end

  def build_inbound_call(raw)
    wa_id = digits(raw[:from])
    name = profile_name(wa_id)
    finder = Crm::Calls::ConversationFinder.new(inbox: inbox, wa_id: wa_id, name: name)
    Crm::Call.new(
      account: account, inbox: inbox, contact: finder.contact, conversation: finder.conversation,
      meta_call_id: raw[:id].to_s, direction: :inbound, status: :ringing, wa_id: wa_id, display_name: name,
      started_at: meta_time(raw[:timestamp]) || Time.current, sdp_offer: raw.dig(:session, :sdp), simulated: @simulated
    )
  end

  # fora do horário: recusa na Meta, registra como perdida e avisa o time
  def reject_outside_hours(call)
    safely_meta { meta_client(call).reject(call.meta_call_id) }
    call.add_event('rejected_outside_hours')
    call.update!(status: :rejected, end_reason: 'outside_hours', ended_at: Time.current, sdp_offer: nil)
    Crm::Calls::CardMessageBuilder.new(call).perform
    reopen_conversation(call)
    broadcast('cevico_call.missed', call: call.to_payload, reason: 'outside_hours')
  end

  def broadcast_ringing(call)
    broadcast('cevico_call.ringing', call: call.to_payload(include_sdp: true),
                                     ring_user_ids: settings.resolved_ring_user_ids(inbox))
  end

  # ── clínica ligou e a Meta devolveu a resposta SDP ────────────────────────
  def handle_outbound_answer(raw)
    call = find_call(raw[:id])
    return unless call

    sdp = raw.dig(:session, :sdp)
    call.add_event('connect', raw)
    call.sdp_answer = sdp if sdp.present?
    call.save!
    broadcast('cevico_call.outbound_answer', call_id: call.id, sdp_answer: sdp) if sdp.present?
  end

  # ── fim da ligação (a Meta manda sempre, atendida ou não) ─────────────────
  def handle_terminate(raw)
    call = find_call(raw[:id])
    return unless call

    call.add_event('terminate', raw)
    call.update!(terminate_attributes(call, raw))
    Crm::Calls::CardMessageBuilder.new(call).perform
    if call.missed? && call.inbound?
      reopen_conversation(call)
      broadcast('cevico_call.missed', call: call.to_payload, reason: call.end_reason)
    end
    broadcast('cevico_call.ended', call: call.to_payload)
  end

  def terminate_attributes(call, raw)
    ended_at = meta_time(raw[:end_time]) || meta_time(raw[:timestamp]) || Time.current
    attrs = { ended_at: ended_at, sdp_offer: nil, sdp_answer: nil, duration: duration_for(call, raw, ended_at) }
    attrs.merge!(final_attributes(call, raw)) unless call.final?
    attrs.merge!(error_attributes(raw))
  end

  # duração da Meta; senão a já gravada (desligou por aqui); senão fim − atendida
  def duration_for(call, raw, ended_at)
    return raw[:duration].to_i if raw[:duration].to_i.positive?
    return call.duration if call.duration.to_i.positive?
    return nil unless call.answered_at

    [(ended_at - call.answered_at).to_i, 0].max
  end

  def final_attributes(call, raw)
    status = final_status(call, raw)
    { status: status, end_reason: call.end_reason.presence || END_REASONS[status.to_s] }
  end

  def final_status(call, raw)
    return :completed if call.answered_at.present?
    return :failed if raw[:status].to_s.upcase == 'FAILED'

    :missed
  end

  def error_attributes(raw)
    error = Array(raw[:errors]).first
    return {} if error.blank?

    { error_code: error[:code].to_s, error_message: (error[:message].presence || error[:title]).to_s }
  end

  # ── statuses: RINGING / ACCEPTED / REJECTED ───────────────────────────────
  def handle_status(raw)
    call = find_call(raw[:id])
    return unless call

    state = raw[:status].to_s.upcase
    at = meta_time(raw[:timestamp]) || Time.current
    call.add_event(state.downcase, raw)
    apply_accepted(call, at) if state == 'ACCEPTED'
    apply_rejected(call, at) if state == 'REJECTED'
    call.save!
    broadcast('cevico_call.status', call_id: call.id, status: call.status)
    return unless state == 'REJECTED'

    # paciente recusou: fecha o card já (o terminate, se vier, só completa os tempos)
    Crm::Calls::CardMessageBuilder.new(call).perform
    broadcast('cevico_call.ended', call: call.to_payload)
  end

  def apply_accepted(call, at)
    call.answered_at ||= at
    call.status = :accepted if call.ringing?
  end

  def apply_rejected(call, at)
    return if call.final?

    call.status = :rejected
    call.end_reason ||= 'rejected'
    call.ended_at ||= at
    call.sdp_offer = nil
  end

  # ── apoio ─────────────────────────────────────────────────────────────────
  def find_call(meta_call_id, quiet: false)
    call = Crm::Call.find_by(account_id: account.id, meta_call_id: meta_call_id.to_s)
    Rails.logger.warn("[CEVICO calls] chamada #{meta_call_id} não encontrada na conta #{account.id}") if call.nil? && !quiet
    call
  end

  def meta_client(call)
    Crm::Calls::MetaClient.new(channel, simulated: call.simulated)
  end

  def safely_meta
    yield
  rescue Crm::Calls::MetaError => e
    Rails.logger.warn("[CEVICO calls] Meta recusou a ação: #{e.message}")
  end

  def reopen_conversation(call)
    conversation = call.conversation
    conversation.update!(status: :open) if conversation && !conversation.open?
  end

  def broadcast(event, data)
    Crm::Calls::Broadcaster.push(account, event, data)
  end

  def digits(raw)
    raw.to_s.gsub(/\D/, '')
  end

  def profile_name(wa_id)
    contacts = Array(value[:contacts])
    entry = contacts.find { |c| digits(c[:wa_id]) == wa_id } || contacts.first
    entry&.dig(:profile, :name).presence
  end

  # timestamps da Meta vêm em segundos (string); start/end_time idem
  def meta_time(raw)
    return nil if raw.blank?
    return Time.zone.at(raw.to_i) if raw.to_s.match?(/\A\d+\z/)

    Time.zone.parse(raw.to_s)
  rescue ArgumentError
    nil
  end
end
