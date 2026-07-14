class AddAiConfigToCrmSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_settings, :ai_config, :jsonb, null: false, default: {}
  end
end
