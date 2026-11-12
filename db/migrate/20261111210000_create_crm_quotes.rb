# 📄 ORÇAMENTOS GUARDADOS POR CLIENTE (LIFE, 11/11/2026 · pedido do Guilherme): "DRE por projeto,
# com o preço ajustado na mão". Cada vez que o Gerador de proposta gera os documentos, fica aqui
# o orçamento inteiro (conta, cotações, DRE, preço) com os PDFs anexados (Active Storage).
class CreateCrmQuotes < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_quotes do |t|
      t.bigint :account_id, null: false
      t.bigint :contact_id, null: false
      t.bigint :user_id
      t.string :kind # micro | string
      t.decimal :price, precision: 12, scale: 2, null: false, default: 0
      t.decimal :margin, precision: 6, scale: 4
      t.jsonb :payload, null: false, default: {}
      t.datetime :sent_at
      t.timestamps
    end
    add_index :crm_quotes, [:account_id, :contact_id, :created_at]
  end
end
