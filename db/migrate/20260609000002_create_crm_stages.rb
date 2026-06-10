class CreateCrmStages < ActiveRecord::Migration[7.0]
  def change
    create_table :crm_stages do |t|
      t.references :pipeline, null: false, foreign_key: { to_table: :crm_pipelines }
      t.string :name, null: false
      t.string :color, default: '#6B7280', null: false
      t.integer :position, default: 0, null: false
      t.timestamps
    end

    add_index :crm_stages, [:pipeline_id, :position]
  end
end
