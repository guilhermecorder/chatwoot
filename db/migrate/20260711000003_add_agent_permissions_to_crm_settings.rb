class AddAgentPermissionsToCrmSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_settings, :agent_permissions, :jsonb, null: false, default: {}
  end
end
