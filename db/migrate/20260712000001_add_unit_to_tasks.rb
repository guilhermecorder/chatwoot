class AddUnitToTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :unit, :string
    add_index :tasks, [:account_id, :unit]
  end
end
