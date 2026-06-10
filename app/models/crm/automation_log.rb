# == Schema Information
#
# Table name: crm_automation_logs
#
#  id            :bigint           not null, primary key
#  error_message :text
#  fired_at      :datetime
#  payload       :jsonb            not null
#  scheduled_at  :datetime
#  status        :string           default("pending"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  automation_id :bigint           not null
#  contact_id    :bigint           not null
#
# Indexes
#
#  index_crm_automation_logs_on_automation_id  (automation_id)
#  index_crm_automation_logs_on_contact_id     (contact_id)
#  index_crm_automation_logs_on_scheduled_at   (scheduled_at)
#  index_crm_automation_logs_on_status         (status)
#
# Foreign Keys
#
#  fk_rails_...  (automation_id => crm_automations.id)
#
class Crm::AutomationLog < ApplicationRecord
  self.table_name = 'crm_automation_logs'

  belongs_to :automation, class_name: 'Crm::Automation'

  STATUSES = %w[pending fired failed cancelled].freeze
  validates :status, inclusion: { in: STATUSES }

  scope :pending,   -> { where(status: 'pending') }
  scope :due,       -> { pending.where('scheduled_at <= ?', Time.current) }
end
