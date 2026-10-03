# Item 315 (03/10): robô de follow-up escolhe as CAIXAS de entrada e as
# COLUNAS do CRM em que atua (listas; vazio = como era: todas as caixas /
# qualquer coluna). inbox_id e stage_id antigos continuam valendo.
class AddInboxIdsAndStageIdsToCrmFollowupBots < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_followup_bots, :inbox_ids, :jsonb, default: [], null: false
    add_column :crm_followup_bots, :stage_ids, :jsonb, default: [], null: false
  end
end
