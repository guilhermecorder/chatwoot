# == Schema Information
#
# Table name: crm_message_automations
#
#  id              :bigint           not null, primary key
#  active          :boolean          default(TRUE), not null
#  delay_days      :integer          default(7), not null
#  exclude_labels  :jsonb            not null
#  marker_label    :string
#  message_preview :text
#  name            :string           not null
#  required_labels :jsonb            not null
#  stats           :jsonb            not null
#  template_params :jsonb            not null
#  trigger_label   :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  inbox_id        :bigint           not null
#  sender_id       :bigint
#
# Indexes
#
#  index_crm_message_automations_on_account_id             (account_id)
#  index_crm_message_automations_on_account_id_and_active  (account_id,active)
#  index_crm_message_automations_on_inbox_id               (inbox_id)
#  index_crm_message_automations_on_sender_id              (sender_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#  fk_rails_...  (sender_id => users.id)
#
class Crm::MessageAutomation < ApplicationRecord
  self.table_name = 'crm_message_automations'

  belongs_to :account
  belongs_to :inbox
  belongs_to :sender, class_name: 'User', optional: true

  validates :name, presence: true
  validates :trigger_label, presence: true
  validates :delay_days, numericality: { greater_than_or_equal_to: 0 }
  validates :template_params, presence: true

  before_create :ensure_marker_label

  scope :active, -> { where(active: true) }

  # Contatos elegíveis: receberam a etiqueta gatilho há >= delay_days,
  # têm todas as etiquetas obrigatórias, nenhuma das excluídas,
  # e ainda não têm a etiqueta marcadora (garante envio único).
  def eligible_contacts
    tag = ActsAsTaggableOn::Tag.find_by(name: trigger_label)
    return ::Contact.none if tag.blank?

    tagged_ids = ActsAsTaggableOn::Tagging.where(
      tag_id: tag.id, taggable_type: 'Contact', context: 'labels'
    ).where('created_at <= ?', delay_days.days.ago).pluck(:taggable_id)

    contacts = account.contacts.where(id: tagged_ids).where.not(phone_number: [nil, ''])
    contacts = contacts.tagged_with(Array(required_labels), any: false) if Array(required_labels).any?

    to_exclude = Array(exclude_labels) + [marker_label]
    excluded_ids = account.contacts.tagged_with(to_exclude.compact, any: true).pluck(:id)
    contacts = contacts.where.not(id: excluded_ids) if excluded_ids.any?
    contacts.distinct
  end

  private

  def ensure_marker_label
    self.marker_label = marker_label.presence || "auto-#{SecureRandom.hex(3)}-enviado"
  end
end
