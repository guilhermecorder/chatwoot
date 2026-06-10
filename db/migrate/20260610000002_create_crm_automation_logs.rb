class CreateCrmAutomationLogs < ActiveRecord::Migration[7.0]
  def change
    create_table :crm_automation_logs do |t|
      t.references :automation, null: false, foreign_key: { to_table: :crm_automations }
      t.bigint  :contact_id,   null: false
      t.string  :status,       null: false, default: 'pending'  # pending | fired | failed
      t.jsonb   :payload,      null: false, default: {}
      t.text    :error_message
      t.datetime :scheduled_at
      t.datetime :fired_at
      t.timestamps
    end

    add_index :crm_automation_logs, :contact_id
    add_index :crm_automation_logs, :status
    add_index :crm_automation_logs, :scheduled_at
  end
end
