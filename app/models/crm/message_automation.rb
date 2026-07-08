# == Schema Information
#
# Table name: crm_message_automations
#
#  id               :bigint           not null, primary key
#  active           :boolean          default(TRUE), not null
#  delay_days       :integer          default(7), not null
#  exclude_labels   :jsonb            not null
#  marker_label     :string
#  message_preview  :text
#  name             :string           not null
#  required_labels  :jsonb            not null
#  stats            :jsonb            not null
#  template_params  :jsonb            not null
#  trigger_label    :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  inbox_id         :bigint           not null
#  sender_id        :bigint
#  trigger_stage_id :bigint
#
# Indexes
#
#  index_crm_message_automations_on_account_id             (account_id)
#  index_crm_message_automations_on_account_id_and_active  (account_id,active)
#  index_crm_message_automations_on_inbox_id               (inbox_id)
#  index_crm_message_automations_on_sender_id              (sender_id)
#  index_crm_message_automations_on_trigger_stage_id       (trigger_stage_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#  fk_rails_...  (sender_id => users.id)
#  fk_rails_...  (trigger_stage_id => crm_stages.id)
#
class Crm::MessageAutomation < ApplicationRecord
  self.table_name = 'crm_message_automations'

  belongs_to :account
  belongs_to :inbox
  belongs_to :sender, class_name: 'User', optional: true
  belongs_to :trigger_stage, class_name: 'Crm::Stage', optional: true

  validates :name, presence: true
  validates :delay_days, numericality: { greater_than_or_equal_to: 0 }
  validates :template_params, presence: true
  validate :trigger_must_be_present

  before_create :ensure_marker_label

  scope :active, -> { where(active: true) }

  # Contatos elegíveis — o gatilho pode ser etiqueta, coluna do CRM ou ambos:
  #   etiqueta: recebeu a etiqueta gatilho há >= delay_days
  #   coluna:   o card está na coluna há >= delay_days (stage_moved_at)
  # Sempre: todas as etiquetas obrigatórias, nenhuma excluída,
  # e sem a etiqueta marcadora (garante envio único).
  def eligible_contacts
    base_ids = trigger_candidate_ids
    return ::Contact.none if base_ids.blank?

    contacts = account.contacts.where(id: base_ids).where.not(phone_number: [nil, ''])
    contacts = contacts.tagged_with(Array(required_labels), any: false) if Array(required_labels).any?

    to_exclude = Array(exclude_labels) + [marker_label]
    excluded_ids = account.contacts.tagged_with(to_exclude.compact, any: true).pluck(:id)
    contacts = contacts.where.not(id: excluded_ids) if excluded_ids.any?
    contacts.distinct
  end

  private

  def trigger_candidate_ids
    sets = []
    sets << label_candidate_ids if trigger_label.present?
    sets << stage_candidate_ids if trigger_stage_id.present?
    return [] if sets.empty?

    sets.reduce(:&)
  end

  def label_candidate_ids
    tag = ActsAsTaggableOn::Tag.find_by(name: trigger_label)
    return [] if tag.blank?

    ActsAsTaggableOn::Tagging.where(
      tag_id: tag.id, taggable_type: 'Contact', context: 'labels'
    ).where('created_at <= ?', delay_days.days.ago).pluck(:taggable_id)
  end

  def stage_candidate_ids
    Crm::Contact.where(stage_id: trigger_stage_id)
                .where('stage_moved_at IS NULL OR stage_moved_at <= ?', delay_days.days.ago)
                .pluck(:contact_id)
  end

  def trigger_must_be_present
    return if trigger_label.present? || trigger_stage_id.present?

    errors.add(:base, 'Defina uma etiqueta ou uma coluna como gatilho')
  end

  def ensure_marker_label
    self.marker_label = marker_label.presence || "auto-#{SecureRandom.hex(3)}-enviado"
  end
end
