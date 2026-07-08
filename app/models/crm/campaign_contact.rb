class Crm::CampaignContact < ApplicationRecord
  self.table_name = 'crm_campaign_contacts'

  belongs_to :campaign, class_name: 'Crm::Campaign'
  belongs_to :contact, class_name: '::Contact'
  belongs_to :conversation, optional: true

  validates :contact_id, uniqueness: { scope: :campaign_id }
end
