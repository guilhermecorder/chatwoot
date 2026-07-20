# METAS MULTI-PERÍODO (item 58): além do plano do MÊS, o Painel de Metas
# passa a ter planos do DIA, da SEMANA, do FIM DE SEMANA, do TRIMESTRE e do
# ANO. A coluna `month` vira o INÍCIO do período; `period_type` diz qual é.
# Aditiva: linhas existentes ganham 'month' por padrão e seguem valendo.
class AddPeriodTypeToCevicoGoalPlans < ActiveRecord::Migration[7.1]
  def change
    add_column :cevico_goal_plans, :period_type, :string, null: false, default: 'month'
    remove_index :cevico_goal_plans, [:account_id, :month], unique: true
    add_index :cevico_goal_plans, [:account_id, :period_type, :month], unique: true,
                                                                       name: 'index_cevico_goal_plans_on_account_period_start'
  end
end
