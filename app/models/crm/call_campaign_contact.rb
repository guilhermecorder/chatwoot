# 🤖📞 Um contato dentro de uma campanha de ligação (item 169): entra na
# fila (queued), vira calling quando a ElevenLabs aceita o pedido de
# ligação e é fechado pelo pós-chamada (done + outcome) ou pelo discador
# (failed / skipped / no_permission). provider_conversation_id é a ponte
# com o webhook pós-chamada.
# == Schema Information
#
# Table name: cevico_call_campaign_contacts
#
#  id                       :bigint           not null, primary key
#  attempts                 :integer          default(0), not null
#  called_at                :datetime
#  error                    :text
#  outcome                  :string
#  status                   :string           default("queued"), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  call_campaign_id         :bigint           not null
#  call_id                  :bigint
#  contact_id               :bigint           not null
#  provider_conversation_id :string
#
# Indexes
#
#  idx_on_call_campaign_id_contact_id_354be64df7            (call_campaign_id,contact_id) UNIQUE
#  idx_on_provider_conversation_id_eaf197986e               (provider_conversation_id)
#  index_cevico_call_campaign_contacts_on_call_campaign_id  (call_campaign_id)
#  index_cevico_call_campaign_contacts_on_contact_id        (contact_id)
#
# Foreign Keys
#
#  fk_rails_...  (call_campaign_id => cevico_call_campaigns.id) ON DELETE => cascade
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#
class Crm::CallCampaignContact < ApplicationRecord
  self.table_name = 'cevico_call_campaign_contacts'

  STATUSES = %w[queued calling done failed skipped no_permission].freeze

  belongs_to :call_campaign, class_name: 'Crm::CallCampaign'
  belongs_to :contact, class_name: '::Contact'
  belongs_to :call, class_name: 'Crm::Call', optional: true

  validates :contact_id, uniqueness: { scope: :call_campaign_id }
  validates :status, inclusion: { in: STATUSES }

  scope :queued, -> { where(status: 'queued') }
  scope :calling, -> { where(status: 'calling') }
  scope :called_today, ->(tz) { where(called_at: tz.now.all_day) }

  # contato de campanha ligado a uma conversa da ElevenLabs (qualquer campanha da conta)
  def self.for_conversation(account, provider_conversation_id)
    return nil if provider_conversation_id.blank?

    joins(:call_campaign).where(cevico_call_campaigns: { account_id: account.id })
                         .find_by(provider_conversation_id: provider_conversation_id.to_s)
  end

  def outcome_label
    Crm::Call::OUTCOME_LABELS[outcome.to_s] || outcome.presence
  end

  def to_payload
    {
      id: id, status: status, outcome: outcome, outcome_label: outcome_label, error: error,
      called_at: called_at&.iso8601, call_id: call_id, attempts: attempts,
      conversation_id: call&.conversation&.display_id, duration: call&.talk_seconds,
      contact: contact && { id: contact.id, name: contact.name, phone_number: contact.phone_number }
    }
  end
end
