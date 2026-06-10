# == Schema Information
#
# Table name: crm_stages
#
#  id          :bigint           not null, primary key
#  color       :string           default("#6B7280"), not null
#  description :text
#  name        :string           not null
#  position    :integer          default(0), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  pipeline_id :bigint           not null
#
# Indexes
#
#  index_crm_stages_on_pipeline_id               (pipeline_id)
#  index_crm_stages_on_pipeline_id_and_position  (pipeline_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (pipeline_id => crm_pipelines.id)
#
class Crm::Stage < ApplicationRecord
  self.table_name = 'crm_stages'

  belongs_to :pipeline, class_name: 'Crm::Pipeline'
  has_many :crm_contacts, class_name: 'Crm::Contact', foreign_key: :stage_id, dependent: :nullify

  validates :name, presence: true
  validates :color, presence: true
end
