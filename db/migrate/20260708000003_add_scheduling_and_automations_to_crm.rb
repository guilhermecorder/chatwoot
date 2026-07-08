class AddSchedulingAndAutomationsToCrm < ActiveRecord::Migration[7.0]
  def change
    add_column :crm_campaigns, :scheduled_at, :datetime
    add_column :crm_campaigns, :conversion_label_ids, :jsonb, default: [], null: false
    add_index :crm_campaigns, :scheduled_at

    # Réguas de mensagens: etiqueta gatilho + espera em dias → template
    create_table :crm_message_automations do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.references :sender, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.string :trigger_label, null: false
      t.integer :delay_days, default: 7, null: false
      t.jsonb :required_labels, default: [], null: false
      t.jsonb :exclude_labels, default: [], null: false
      t.string :marker_label
      t.jsonb :template_params, default: {}, null: false
      t.text :message_preview
      t.boolean :active, default: true, null: false
      t.jsonb :stats, default: {}, null: false
      t.timestamps
    end

    add_index :crm_message_automations, [:account_id, :active]
  end
end
