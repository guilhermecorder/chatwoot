class AddDescriptionToCrmStages < ActiveRecord::Migration[7.0]
  def change
    add_column :crm_stages, :description, :text
  end
end
