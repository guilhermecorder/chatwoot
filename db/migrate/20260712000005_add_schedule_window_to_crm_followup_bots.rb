class AddScheduleWindowToCrmFollowupBots < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_followup_bots, :starts_at, :datetime
    add_column :crm_followup_bots, :ends_at, :datetime
  end
end
