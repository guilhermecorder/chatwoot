class AddLabelFiltersToCrmFollowupBots < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_followup_bots, :required_labels, :jsonb, null: false, default: []
    add_column :crm_followup_bots, :exclude_labels, :jsonb, null: false, default: []
  end
end
