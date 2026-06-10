# == Schema Information
#
# Table name: crm_contact_stage_logs
#
#  id               :bigint           not null, primary key
#  duration_minutes :integer
#  entered_at       :datetime         not null
#  event_type       :string           default("entered"), not null
#  left_at          :datetime
#  stage_color      :string
#  stage_name       :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  crm_contact_id   :bigint           not null
#  stage_id         :bigint           not null
#
# Indexes
#
#  index_crm_contact_stage_logs_on_crm_contact_id                 (crm_contact_id)
#  index_crm_contact_stage_logs_on_crm_contact_id_and_entered_at  (crm_contact_id,entered_at)
#
class Crm::StageLog < ApplicationRecord
  self.table_name = 'crm_contact_stage_logs'

  belongs_to :crm_contact, class_name: 'Crm::Contact', foreign_key: :crm_contact_id

  scope :for_contact, ->(id) { where(crm_contact_id: id).order(entered_at: :asc) }

  # Fecha o log atual e calcula duração
  def close!(left_at_time = Time.current)
    duration = ((left_at_time - entered_at) / 60).round
    update!(left_at: left_at_time, duration_minutes: duration)
  end
end
