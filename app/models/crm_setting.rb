# == Schema Information
#
# Table name: crm_settings
#
#  id                       :bigint           not null, primary key
#  agent_permissions        :jsonb            not null
#  column_presets           :jsonb            not null
#  google_ads_config        :jsonb            not null
#  meta_ads_config          :jsonb            not null
#  n8n_api_key              :string
#  n8n_base_url             :string
#  n8n_workflows            :jsonb            not null
#  n8n_workflows_fetched_at :datetime
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#
# Indexes
#
#  index_crm_settings_on_account_id  (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class CrmSetting < ApplicationRecord
  belongs_to :account

  def n8n_configured?
    n8n_base_url.present? && n8n_api_key.present?
  end

  def n8n_base_url_clean
    n8n_base_url&.chomp('/')
  end
end
