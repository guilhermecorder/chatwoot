class CreateCrmForms < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_forms do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.boolean :active, null: false, default: true
      t.string :intro_title
      t.text :intro_text
      t.text :thank_you_text
      t.jsonb :questions, null: false, default: []
      t.jsonb :ai_insight, null: false, default: {}
      t.timestamps
    end
    add_index :crm_forms, :slug, unique: true

    create_table :crm_form_responses do |t|
      t.references :crm_form, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.references :contact, foreign_key: true
      t.jsonb :answers, null: false, default: []
      t.datetime :completed_at
      t.timestamps
    end
  end
end
