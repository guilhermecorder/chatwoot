class AddTriggerStageToMessageAutomations < ActiveRecord::Migration[7.0]
  def change
    add_reference :crm_message_automations, :trigger_stage, foreign_key: { to_table: :crm_stages }
    change_column_null :crm_message_automations, :trigger_label, true
  end
end
