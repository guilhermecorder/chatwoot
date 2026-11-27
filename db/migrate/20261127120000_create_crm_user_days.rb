# 27/11/2026 (LIFE, Guilherme): "quando ele entra no sistema, quando ele inicia a resposta…" — um registro por pessoa
# por dia: o 1º e o último acesso ao sistema (qualquer chamada da tela), para o Meu Painel mostrar a rotina da equipe.
class CreateCrmUserDays < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_user_days do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.bigint :user_id, null: false
      t.date :day, null: false
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.integer :hits, null: false, default: 1
      t.timestamps
    end
    add_index :crm_user_days, %i[account_id user_id day], unique: true
    add_index :crm_user_days, %i[account_id day]
  end
end
