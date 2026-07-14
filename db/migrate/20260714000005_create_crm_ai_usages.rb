# Registro de uso dos agentes de IA: cada chamada à Claude grava tokens e
# custo estimado — alimenta o relatório de gastos em Automações → Agentes de IA.
class CreateCrmAiUsages < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_ai_usages do |t|
      t.references :account, null: false, foreign_key: true
      t.string :agent_key, null: false # conversation | form | scheduler | opportunity
      t.string :model, null: false
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.decimal :cost_usd, precision: 12, scale: 6, null: false, default: 0
      t.timestamps
    end
    add_index :crm_ai_usages, [:account_id, :created_at]
    add_index :crm_ai_usages, [:account_id, :agent_key]
  end
end
