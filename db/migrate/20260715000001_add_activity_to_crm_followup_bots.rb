# Registro de atividade do robô de follow-up: o que ele fez (e por que NÃO
# cutucou) em cada rodada — visível na aba Robôs. Aditiva.
class AddActivityToCrmFollowupBots < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_followup_bots, :activity_log, :jsonb, default: {}, null: false
    add_column :crm_followup_bots, :last_run_at, :datetime
  end
end
