# == Schema Information
#
# Table name: crm_pipelines
#
#  id          :bigint           not null, primary key
#  description :text
#  name        :string           not null
#  position    :integer          default(0), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_crm_pipelines_on_account_id               (account_id)
#  index_crm_pipelines_on_account_id_and_position  (account_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Crm::Pipeline < ApplicationRecord
  self.table_name = 'crm_pipelines'

  belongs_to :account
  has_many :stages, -> { order(:position) }, class_name: 'Crm::Stage', foreign_key: :pipeline_id, dependent: :destroy
  has_many :crm_contacts, class_name: 'Crm::Contact', foreign_key: :pipeline_id, dependent: :destroy

  validates :name, presence: true
end
