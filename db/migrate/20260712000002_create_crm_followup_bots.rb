class CreateCrmFollowupBots < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_followup_bots do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.references :sender, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      # steps: [{ "delay_hours": 3, "message": "oi, pode falar?" }, ...]
      t.jsonb :steps, null: false, default: []

      t.timestamps
    end

    add_index :crm_followup_bots, [:account_id, :active]
  end
end
