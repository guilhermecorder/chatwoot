# PESSOAS PRO: perfil de cada pessoa do time (diagnóstico DISC / 4
# temperamentos + objetivos e metas de desenvolvimento pessoal) e o
# Mentor do Time ganha ciclo MENSAL além do semanal. Aditiva (o índice
# único dos feedbacks só ganha a coluna cadence).
class CreatePessoasPro < ActiveRecord::Migration[7.0]
  def change
    create_table :cevico_people_profiles do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.jsonb :disc, null: false, default: {}  # respostas + placar D/I/S/C + perfil dominante
      t.jsonb :goals, null: false, default: [] # objetivos com metas/tarefas e progresso
      t.timestamps
    end
    add_index :cevico_people_profiles, [:account_id, :user_id], unique: true

    add_column :crm_weekly_feedbacks, :cadence, :string, null: false, default: 'weekly'
    remove_index :crm_weekly_feedbacks, name: 'idx_crm_weekly_feedbacks_unique'
    add_index :crm_weekly_feedbacks, [:account_id, :user_id, :week_start, :cadence],
              unique: true, name: 'idx_crm_weekly_feedbacks_unique'
  end
end
