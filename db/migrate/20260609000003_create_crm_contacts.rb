class CreateCrmContacts < ActiveRecord::Migration[7.0]
  def change
    create_table :crm_contacts do |t|
      t.references :contact, null: false, foreign_key: true
      t.references :pipeline, null: false, foreign_key: { to_table: :crm_pipelines }
      t.references :stage, null: false, foreign_key: { to_table: :crm_stages }
      t.references :assignee, foreign_key: { to_table: :users }
      t.decimal :value, precision: 15, scale: 2
      t.string :origin
      t.string :procedure_of_interest
      t.text :notes
      t.timestamps
    end

    add_index :crm_contacts, [:contact_id, :pipeline_id], unique: true
  end
end
