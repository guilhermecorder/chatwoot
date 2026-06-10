class CreateCrmAutomations < ActiveRecord::Migration[7.0]
  def change
    create_table :crm_automations do |t|
      t.references :stage, null: false, foreign_key: { to_table: :crm_stages }
      t.string  :name,           null: false
      t.string  :trigger_type,   null: false
      t.integer :delay_minutes,  null: false, default: 0
      t.string  :action_type,    null: false
      t.jsonb   :action_config,  null: false, default: {}
      t.boolean :active,         null: false, default: true
      t.timestamps
    end
  end
end
