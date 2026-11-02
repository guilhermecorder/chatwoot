# 📊 SUA ÓTICA — ANÁLISE DA LOJA (02/11/2026): a página de análise do SavWin
# (gerada no Mac por OTICA/analise/savwin.py) passa a morar DENTRO do sistema,
# só para quem está logado na conta da ótica. Cada envio é uma versão
# (otica_reports + arquivo HTML no ActiveStorage); a mais nova é a que aparece.
# Reversível (só create_table).
class CreateOticaReports < ActiveRecord::Migration[7.1]
  def change
    create_table :otica_reports do |t|
      t.references :account, null: false, foreign_key: true
      t.string :title, null: false, default: ''
      t.string :note, null: false, default: ''
      t.integer :size_bytes, null: false, default: 0
      t.integer :created_by_id
      t.timestamps
    end
    add_index :otica_reports, [:account_id, :created_at]
  end
end
