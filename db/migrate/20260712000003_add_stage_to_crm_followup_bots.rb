class AddStageToCrmFollowupBots < ActiveRecord::Migration[7.1]
  def change
    add_reference :crm_followup_bots, :pipeline, foreign_key: { to_table: :crm_pipelines }
    add_reference :crm_followup_bots, :stage, foreign_key: { to_table: :crm_stages }
    change_column_null :crm_followup_bots, :inbox_id, true
  end
end
