# == Schema Information
#
# Table name: crm_automations
#
#  id            :bigint           not null, primary key
#  action_config :jsonb            not null
#  action_type   :string           not null
#  active        :boolean          default(TRUE), not null
#  delay_minutes :integer          default(0), not null
#  name          :string           not null
#  trigger_type  :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  stage_id      :bigint           not null
#
# Indexes
#
#  index_crm_automations_on_stage_id  (stage_id)
#
# Foreign Keys
#
#  fk_rails_...  (stage_id => crm_stages.id)
#
class Crm::Automation < ApplicationRecord
  self.table_name = 'crm_automations'

  belongs_to :stage, class_name: 'Crm::Stage'
  has_many :logs, class_name: 'Crm::AutomationLog', foreign_key: :automation_id, dependent: :destroy

  TRIGGER_TYPES = %w[card_entered card_left card_stalled label_added label_removed message_created value_added].freeze
  ACTION_TYPES  = %w[webhook n8n_flow apply_label move_card log_timeline notify_team meta_ads_event google_ads_conversion send_form ai_analyze
                     schedule_appointment set_value send_template].freeze

  validates :name,         presence: true
  validates :trigger_type, inclusion: { in: TRIGGER_TYPES }
  validates :action_type,  inclusion: { in: ACTION_TYPES }
  validates :delay_minutes, numericality: { greater_than_or_equal_to: 0 }
end
