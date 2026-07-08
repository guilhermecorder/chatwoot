# == Schema Information
#
# Table name: crm_campaign_contacts
#
#  id              :bigint           not null, primary key
#  delivery_status :string           default("sent"), not null
#  sent_at         :datetime
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  campaign_id     :bigint           not null
#  contact_id      :bigint           not null
#  conversation_id :bigint
#
# Indexes
#
#  index_crm_campaign_contacts_on_campaign_id                 (campaign_id)
#  index_crm_campaign_contacts_on_campaign_id_and_contact_id  (campaign_id,contact_id) UNIQUE
#  index_crm_campaign_contacts_on_contact_id                  (contact_id)
#  index_crm_campaign_contacts_on_conversation_id             (conversation_id)
#
# Foreign Keys
#
#  fk_rails_...  (campaign_id => crm_campaigns.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#
class Crm::CampaignContact < ApplicationRecord
  self.table_name = 'crm_campaign_contacts'

  belongs_to :campaign, class_name: 'Crm::Campaign'
  belongs_to :contact, class_name: '::Contact'
  belongs_to :conversation, optional: true

  validates :contact_id, uniqueness: { scope: :campaign_id }
end
