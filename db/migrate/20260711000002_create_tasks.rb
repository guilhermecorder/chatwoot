class CreateTasks < ActiveRecord::Migration[7.1]
  def change
    create_table :tasks do |t|
      t.references :account, null: false, foreign_key: true
      t.references :creator, null: false, foreign_key: { to_table: :users }
      t.references :assignee, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.text :description
      t.string :task_type
      t.integer :priority, null: false, default: 1
      t.integer :status, null: false, default: 0
      t.datetime :due_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :tasks, [:account_id, :status]
  end
end
