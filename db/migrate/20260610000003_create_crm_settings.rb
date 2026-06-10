class CreateCrmSettings < ActiveRecord::Migration[7.0]
  def change
    create_table :crm_settings do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.string  :n8n_base_url
      t.string  :n8n_api_key
      t.jsonb   :n8n_workflows,           null: false, default: []
      t.datetime :n8n_workflows_fetched_at
      t.timestamps
    end
  end
end
