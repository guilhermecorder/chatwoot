# 🗺️ Um ENVIO da jornada (item 168): 1 por paciente × evento (event_key
# único por mensagem) — o motor nunca manda a mesma coisa duas vezes.
# Estados: queued (vai sair na hora) → sent | failed | skipped | expired;
# pending_review espera a aprovação na "Fila de hoje".
# == Schema Information
#
# Table name: cevico_journey_sends
#
#  id                 :bigint           not null, primary key
#  error              :text
#  event_key          :string           not null
#  preview            :text
#  replied_at         :datetime
#  reply              :string
#  reply_text         :text
#  scheduled_for      :datetime         not null
#  sent_at            :datetime
#  source_type        :string
#  status             :string           default("queued"), not null
#  variables          :jsonb            not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  contact_id         :bigint           not null
#  conversation_id    :bigint
#  journey_message_id :bigint           not null
#  source_id          :bigint
#
# Indexes
#
#  index_cevico_journey_sends_on_account_id                        (account_id)
#  index_cevico_journey_sends_on_account_id_and_scheduled_for      (account_id,scheduled_for)
#  index_cevico_journey_sends_on_account_id_and_status             (account_id,status)
#  index_cevico_journey_sends_on_contact_id                        (contact_id)
#  index_cevico_journey_sends_on_journey_message_id                (journey_message_id)
#  index_cevico_journey_sends_on_journey_message_id_and_event_key  (journey_message_id,event_key) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#  fk_rails_...  (journey_message_id => cevico_journey_messages.id) ON DELETE => cascade
#
class Crm::JourneySend < ApplicationRecord
  self.table_name = 'cevico_journey_sends'

  STATUSES = %w[queued pending_review sent skipped failed expired].freeze
  STATUS_LABELS = {
    'queued' => 'Na fila', 'pending_review' => 'Aguardando aprovação', 'sent' => 'Enviada',
    'skipped' => 'Pulada', 'failed' => 'Falhou', 'expired' => 'Expirou'
  }.freeze
  REPLY_LABELS = { 'confirmed' => 'Confirmou', 'declined' => 'Não vai / remarcar', 'other' => 'Respondeu' }.freeze

  belongs_to :account
  belongs_to :journey_message, class_name: 'Crm::JourneyMessage', inverse_of: :sends
  belongs_to :contact, class_name: '::Contact'
  belongs_to :conversation, optional: true
  belongs_to :source, polymorphic: true, optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :for_day, ->(day, tz) { where(scheduled_for: tz.local(day.year, day.month, day.day)..tz.local(day.year, day.month, day.day).end_of_day) }
  scope :due, ->(now) { where(status: 'queued').where(scheduled_for: ..now) }
  scope :awaiting_reply, -> { where(status: 'sent', reply: nil) }

  def final? = %w[sent skipped failed expired].include?(status)

  def to_payload
    {
      id: id, journey_message_id: journey_message_id, message_name: journey_message&.name,
      contact: contact_payload, conversation_id: conversation&.display_id,
      event_key: event_key, scheduled_for: scheduled_for&.iso8601, status: status,
      status_label: STATUS_LABELS[status], sent_at: sent_at&.iso8601, reply: reply,
      reply_label: reply && REPLY_LABELS[reply], replied_at: replied_at&.iso8601, reply_text: reply_text,
      error: error, preview: preview, variables: variables
    }
  end

  private

  def contact_payload
    return nil unless contact

    { id: contact.id, name: contact.name, phone_number: contact.phone_number }
  end
end
