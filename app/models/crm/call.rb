# 📞 Uma ligação de WhatsApp (item 167): recebida do paciente ou feita pela
# atendente pela API oficial da Meta. Guarda a linha do tempo crua (events),
# a gravação (Active Storage) e a transcrição/resumo do Gemini. O card na
# conversa é a Message apontada por message_id — ela recebe o mesmo
# to_payload em content_attributes.cevico_call e é atualizada a cada mudança.
# == Schema Information
#
# Table name: cevico_calls
#
#  id                 :bigint           not null, primary key
#  answered_at        :datetime
#  direction          :integer          default("inbound"), not null
#  display_name       :string
#  duration           :integer
#  end_reason         :string
#  ended_at           :datetime
#  error_code         :string
#  error_message      :text
#  events             :jsonb            not null
#  recording_duration :integer
#  recording_mime     :string
#  sdp_answer         :text
#  sdp_offer          :text
#  simulated          :boolean          default(FALSE), not null
#  started_at         :datetime
#  status             :integer          default("ringing"), not null
#  summary            :text
#  transcribed_at     :datetime
#  transcript         :text
#  transcript_error   :text
#  transcript_status  :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  contact_id         :bigint
#  conversation_id    :bigint
#  inbox_id           :bigint           not null
#  message_id         :bigint
#  meta_call_id       :string           not null
#  user_id            :bigint
#  wa_id              :string
#
# Indexes
#
#  index_cevico_calls_on_account_id                   (account_id)
#  index_cevico_calls_on_account_id_and_meta_call_id  (account_id,meta_call_id) UNIQUE
#  index_cevico_calls_on_account_id_and_started_at    (account_id,started_at)
#  index_cevico_calls_on_account_id_and_status        (account_id,status)
#  index_cevico_calls_on_contact_id                   (contact_id)
#  index_cevico_calls_on_user_id                      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => nullify
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => nullify
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class Crm::Call < ApplicationRecord
  self.table_name = 'cevico_calls'

  belongs_to :account
  belongs_to :inbox
  belongs_to :contact, class_name: '::Contact', optional: true
  belongs_to :conversation, optional: true
  belongs_to :user, optional: true

  has_one_attached :recording

  enum :direction, { inbound: 0, outbound: 1 }
  enum :status, { ringing: 0, accepted: 1, completed: 2, missed: 3, rejected: 4, failed: 5, canceled: 6 }

  # depois disso a ligação não muda mais de estado (só ganha gravação/transcrição)
  FINAL_STATUSES = %w[completed missed rejected failed canceled].freeze
  MAX_EVENTS = 60

  validates :meta_call_id, presence: true, uniqueness: { scope: :account_id }

  scope :in_period, ->(since, until_at) { where(started_at: since..until_at) }
  scope :answered, -> { where(status: [statuses[:accepted], statuses[:completed]]) }
  scope :recent_first, -> { order(started_at: :desc, id: :desc) }

  def final?
    FINAL_STATUSES.include?(status)
  end

  # segundos falados: duração da Meta; senão fim − atendida; senão 0
  def talk_seconds
    return duration.to_i if duration.to_i.positive?
    return 0 unless answered_at && ended_at

    [(ended_at - answered_at).to_i, 0].max
  end

  # quanto o paciente esperou até alguém atender (nil se ninguém atendeu)
  def wait_seconds
    return nil unless started_at && answered_at

    [(answered_at - started_at).to_i, 0].max
  end

  # anexa um evento cru à linha do tempo (sem o SDP, que é grande e inútil depois)
  def add_event(name, raw = {})
    raw_hash = raw.respond_to?(:to_h) ? raw.to_h.deep_stringify_keys.except('session') : {}
    entry = { 'at' => Time.current.iso8601, 'event' => name.to_s, 'status' => raw_hash['status'], 'raw' => raw_hash }
    self.events = (Array(events) + [entry]).last(MAX_EVENTS)
  end

  def recording_url
    return nil unless recording.attached?

    Rails.application.routes.url_helpers.rails_blob_path(recording, only_path: true)
  end

  # hash usado no JSON da API, no cable e no card da conversa (§4 do contrato)
  def to_payload(include_sdp: false)
    payload = {
      id: id, meta_call_id: meta_call_id, direction: direction, status: status, end_reason: end_reason,
      started_at: started_at&.iso8601, answered_at: answered_at&.iso8601, ended_at: ended_at&.iso8601,
      duration: talk_seconds, wait_seconds: wait_seconds, simulated: simulated
    }.merge(people_payload, media_payload)
    payload[:sdp_offer] = sdp_offer if include_sdp
    payload
  end

  # texto humano do card na conversa
  def card_content
    return outbound_card_content if outbound?

    case status
    when 'completed', 'accepted'
      ['📞 Chamada recebida', user && "atendida por #{user.available_name}", talk_label].compact.join(' · ')
    when 'rejected'
      end_reason == 'outside_hours' ? '📵 Chamada perdida · fora do horário de atendimento' : '📵 Chamada recusada'
    when 'failed'
      '📵 Chamada com falha'
    else
      '📵 Chamada perdida'
    end
  end

  # "42 s", "3 min 42 s", "1 h 05 min"
  def self.human_duration(seconds)
    total = seconds.to_i
    return "#{total} s" if total < 60

    minutes, secs = total.divmod(60)
    return secs.zero? ? "#{minutes} min" : "#{minutes} min #{secs} s" if minutes < 60

    hours, minutes = minutes.divmod(60)
    "#{hours} h #{minutes.to_s.rjust(2, '0')} min"
  end

  private

  def outbound_card_content
    case status
    when 'completed', 'accepted' then ['📞 Ligação para o paciente', talk_label].compact.join(' · ')
    when 'canceled' then '📵 Ligação para o paciente · cancelada antes de atender'
    when 'failed' then '📵 Ligação para o paciente · falhou'
    else '📵 Ligação para o paciente · não atendida'
    end
  end

  def talk_label
    talk_seconds.positive? ? self.class.human_duration(talk_seconds) : nil
  end

  def people_payload
    { contact: contact_payload, conversation_id: conversation&.display_id, inbox_id: inbox_id, user: user_payload }
  end

  def media_payload
    { recording_url: recording_url, recording_duration: recording_duration, transcript_status: transcript_status,
      has_transcript: transcript.present?, transcript: transcript, transcript_error: transcript_error, summary: summary }
  end

  def contact_payload
    return nil unless contact

    { id: contact.id, name: contact.name, phone_number: contact.phone_number, thumbnail: safe_avatar(contact) }
  end

  def user_payload
    return nil unless user

    { id: user.id, name: user.available_name, avatar_url: safe_avatar(user) }
  end

  # url_for pode reclamar de host fora de uma request; o card sobrevive sem foto
  def safe_avatar(record)
    record.avatar_url
  rescue StandardError
    ''
  end
end
