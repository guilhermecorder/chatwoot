# == Schema Information
#
# Table name: tasks
#
#  id                  :bigint           not null, primary key
#  attendance          :string
#  canceled_at         :datetime
#  comments            :jsonb            not null
#  completed_at        :datetime
#  description         :text
#  doctor              :string
#  due_at              :datetime
#  indicated_procedure :string
#  phone               :string
#  priority            :integer          default("medium"), not null
#  procedure           :string
#  rescheduled_count   :integer          default(0), not null
#  status              :integer          default("todo"), not null
#  surgery_indication  :string
#  task_type           :string
#  title               :string           not null
#  unit                :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  assignee_id         :bigint
#  creator_id          :bigint           not null
#
# Indexes
#
#  index_tasks_on_account_id             (account_id)
#  index_tasks_on_account_id_and_status  (account_id,status)
#  index_tasks_on_account_id_and_unit    (account_id,unit)
#  index_tasks_on_assignee_id            (assignee_id)
#  index_tasks_on_creator_id             (creator_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (assignee_id => users.id)
#  fk_rails_...  (creator_id => users.id)
#
class Task < ApplicationRecord
  belongs_to :account
  belongs_to :creator, class_name: 'User'
  belongs_to :assignee, class_name: 'User', optional: true

  validates :title, presence: true

  enum status: { todo: 0, doing: 1, done: 2 }
  enum priority: { low: 0, medium: 1, high: 2, urgent: 3 }

  before_save :track_completion

  private

  def track_completion
    return unless status_changed?

    self.completed_at = done? ? Time.current : nil
  end
end
