# == Schema Information
#
# Table name: crm_settings
#
#  id                       :bigint           not null, primary key
#  agenda_config            :jsonb            not null
#  agent_permissions        :jsonb            not null
#  ai_config                :jsonb            not null
#  column_presets           :jsonb            not null
#  google_ads_config        :jsonb            not null
#  meta_ads_config          :jsonb            not null
#  n8n_api_key              :string
#  n8n_base_url             :string
#  n8n_workflows            :jsonb            not null
#  n8n_workflows_fetched_at :datetime
#  sheets_config            :jsonb            not null
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

  # 🎨 Personalização por conta (28/10): imagens da identidade visual da
  # EMPRESA (não da instalação) — logo claro/escuro, ícone e imagem do
  # cabeçalho. Entram no plano de backup como todo o storage.
  has_one_attached :brand_logo
  has_one_attached :brand_logo_dark
  has_one_attached :brand_icon
  has_one_attached :brand_hero

  def n8n_configured?
    n8n_base_url.present? && n8n_api_key.present?
  end

  def n8n_base_url_clean
    n8n_base_url&.chomp('/')
  end
end
