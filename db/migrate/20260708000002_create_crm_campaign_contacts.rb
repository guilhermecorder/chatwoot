class CreateCrmCampaignContacts < ActiveRecord::Migration[7.0]
  def change
    create_table :crm_campaign_contacts do |t|
      t.references :campaign, null: false, foreign_key: { to_table: :crm_campaigns }
      t.references :contact, null: false, foreign_key: true
      t.references :conversation, foreign_key: true
      t.datetime :sent_at
      t.string :delivery_status, default: 'sent', null: false
      t.timestamps
    end

    add_index :crm_campaign_contacts, [:campaign_id, :contact_id], unique: true

    # Colunas do CRM que contam como conversão para o painel de resultados
    add_column :crm_campaigns, :conversion_stage_ids, :jsonb, default: [], null: false
  end
end
