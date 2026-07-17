# MENTOR DO TIME: feedback semanal automático por usuário. O sistema coleta
# os dados de uso da semana (tempo de resposta, conversas resolvidas,
# mensagens, tarefas) e a IA aponta o ponto forte, O ponto fraco a corrigir
# e soluções simples de implementar que geram grande resultado. Aditiva.
class CreateCrmWeeklyFeedbacks < ActiveRecord::Migration[7.0]
  def change
    create_table :crm_weekly_feedbacks do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.date :week_start, null: false # segunda-feira da semana analisada
      t.jsonb :stats, null: false, default: {}    # números coletados da semana
      t.jsonb :feedback, null: false, default: {} # resposta do Mentor (resumo, forte, fraco, soluções)
      t.timestamps
    end
    add_index :crm_weekly_feedbacks, [:account_id, :user_id, :week_start],
              unique: true, name: 'idx_crm_weekly_feedbacks_unique'
  end
end
