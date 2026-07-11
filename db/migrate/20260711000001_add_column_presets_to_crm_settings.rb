class AddColumnPresetsToCrmSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_settings, :column_presets, :jsonb, null: false, default: []
  end
end
