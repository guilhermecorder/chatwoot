# GESTÃO FINANCEIRA: livro de lançamentos da clínica (só admin) — receitas,
# tributos, custos (serviços/comissões/distribuição de lucros/serviços
# médicos/sala cirúrgica), investimento em produto/estoque e em equipamentos.
# Alimenta o dashboard financeiro (indicadores + histórico + comparação de
# meses). Aditiva.
class CreateCevicoFinanceEntries < ActiveRecord::Migration[7.0]
  def change
    create_table :cevico_finance_entries do |t|
      t.references :account, null: false, foreign_key: true
      t.date :entry_date, null: false                                    # competência do lançamento
      t.string :kind, null: false                                        # receita | tributo | custo | investimento_produto | investimento_equipamento
      t.string :category                                                 # subcategoria dentro do tipo
      t.string :description, null: false, default: ''
      t.decimal :amount, precision: 12, scale: 2, null: false, default: 0
      t.integer :created_by_id                                           # quem lançou
      t.timestamps
    end
    add_index :cevico_finance_entries, [:account_id, :entry_date]
    add_index :cevico_finance_entries, [:account_id, :kind]
  end
end
