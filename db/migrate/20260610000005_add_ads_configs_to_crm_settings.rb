class AddAdsConfigsToCrmSettings < ActiveRecord::Migration[7.0]
  def change
    add_column :crm_settings, :meta_ads_config,   :jsonb, null: false, default: {}
    add_column :crm_settings, :google_ads_config,  :jsonb, null: false, default: {}
  end
end
