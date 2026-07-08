class CreateCrmCampaigns < ActiveRecord::Migration[7.0]
  def change
    create_table :crm_campaigns do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.references :sender, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.jsonb :template_params, default: {}, null: false
      t.text :message_preview
      t.jsonb :audience, default: {}, null: false
      t.string :apply_label
      t.integer :status, default: 0, null: false
      t.jsonb :stats, default: {}, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    add_index :crm_campaigns, [:account_id, :status]
  end
end
