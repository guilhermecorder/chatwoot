# == Schema Information
#
# Table name: crm_contacts
#
#  id                    :bigint           not null, primary key
#  notes                 :text
#  origin                :string
#  procedure_of_interest :string
#  value                 :decimal(15, 2)
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  assignee_id           :bigint
#  contact_id            :bigint           not null
#  pipeline_id           :bigint           not null
#  stage_id              :bigint           not null
#
# Indexes
#
#  index_crm_contacts_on_assignee_id                 (assignee_id)
#  index_crm_contacts_on_contact_id                  (contact_id)
#  index_crm_contacts_on_contact_id_and_pipeline_id  (contact_id,pipeline_id) UNIQUE
#  index_crm_contacts_on_pipeline_id                 (pipeline_id)
#  index_crm_contacts_on_stage_id                    (stage_id)
#
# Foreign Keys
#
#  fk_rails_...  (assignee_id => users.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (pipeline_id => crm_pipelines.id)
#  fk_rails_...  (stage_id => crm_stages.id)
#
class Crm::Contact < ApplicationRecord
  self.table_name = 'crm_contacts'

  belongs_to :contact, class_name: '::Contact'
  belongs_to :pipeline, class_name: 'Crm::Pipeline'
  belongs_to :stage, class_name: 'Crm::Stage'
  belongs_to :assignee, class_name: 'User', optional: true

  validates :contact_id, uniqueness: { scope: :pipeline_id, message: 'already exists in this pipeline' }
end
