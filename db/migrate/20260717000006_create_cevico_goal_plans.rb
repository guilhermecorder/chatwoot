# PAINEL DE METAS: um plano por mês (só admin cria) — alvos por indicador,
# orientações de como chegar lá, notas de ajuste de processo por pessoa e
# MARCOS com check. O histórico dos indicadores mês a mês alimenta a
# definição da meta seguinte. Aditiva.
class CreateCevicoGoalPlans < ActiveRecord::Migration[7.0]
  def change
    create_table :cevico_goal_plans do |t|
      t.references :account, null: false, foreign_key: true
      t.date :month, null: false # dia 1 do mês vigente da meta
      t.jsonb :targets, null: false, default: {}       # { indicador => alvo }
      t.text :guidance                                  # orientações: como vamos chegar lá
      t.jsonb :process_notes, null: false, default: [] # ajustes por pessoa [{id,user_id,name,text,at}]
      t.jsonb :milestones, null: false, default: []    # marcos [{id,title,due_on,done,done_at}]
      t.timestamps
    end
    add_index :cevico_goal_plans, [:account_id, :month], unique: true
  end
end
