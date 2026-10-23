# 👓 SUA ÓTICA — FASE 2 (23/10/2026): ESTOQUE de verdade. O saldo do produto
# passa a mudar SÓ por movimentação (otica_stock_moves): venda baixa,
# cancelamento/devolução devolve, compra (NF-e por XML ou manual) entra,
# inventário ajusta. Compras ficam em otica_purchases(+items). Reversível.
class CreateOticaStock < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    create_table :otica_stock_moves do |t|
      t.references :account, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: { to_table: :otica_products, on_delete: :cascade }
      t.string :kind, null: false                                       # entrada | saida | ajuste
      t.string :origin, null: false, default: 'manual' # venda|cancelamento|devolucao|compra|inventario|manual|importacao|cadastro
      t.integer :quantity, null: false                                  # sempre positivo
      t.integer :delta, null: false                                     # +entrada / −saída / ±ajuste
      t.integer :balance_after, null: false
      t.decimal :unit_cost, precision: 12, scale: 2
      t.string :reference_type                                          # Otica::Order | Otica::Purchase
      t.bigint :reference_id
      t.string :notes, default: ''
      t.integer :created_by_id
      t.timestamps
    end
    add_index :otica_stock_moves, [:account_id, :created_at]
    add_index :otica_stock_moves, [:account_id, :product_id]
    add_index :otica_stock_moves, [:reference_type, :reference_id]

    create_table :otica_purchases do |t|
      t.references :account, null: false, foreign_key: true
      t.references :supplier, foreign_key: { to_table: :otica_suppliers, on_delete: :nullify }
      t.string :status, null: false, default: 'rascunho'                # rascunho | recebida | cancelada
      t.string :supplier_name, default: ''
      t.string :supplier_cnpj, default: ''
      t.string :number, default: ''
      t.string :series, default: ''
      t.string :access_key, default: ''                                 # chave da NF-e (44 dígitos)
      t.date :issued_on
      t.datetime :received_at
      t.decimal :total, precision: 12, scale: 2, null: false, default: 0
      t.string :notes, default: ''
      t.integer :created_by_id
      t.timestamps
    end
    add_index :otica_purchases, [:account_id, :status]
    add_index :otica_purchases, [:account_id, :access_key]

    create_table :otica_purchase_items do |t|
      t.references :account, null: false, foreign_key: true
      t.references :purchase, null: false, foreign_key: { to_table: :otica_purchases, on_delete: :cascade }
      t.references :product, foreign_key: { to_table: :otica_products, on_delete: :nullify }
      t.string :description, null: false, default: ''
      t.string :ean, default: ''
      t.string :ncm, default: ''
      t.string :code, default: ''
      t.integer :quantity, null: false, default: 1
      t.decimal :unit_cost, precision: 12, scale: 2, null: false, default: 0
      t.decimal :total, precision: 12, scale: 2, null: false, default: 0
      t.timestamps
    end
  end
end
