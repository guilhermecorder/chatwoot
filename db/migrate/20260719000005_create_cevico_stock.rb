# ESTOQUE (item 68): itens em estoque da clínica (lentes, insumos,
# medicamentos) com custo e preço de venda — alimenta o dashboard de
# Estoque dentro do Financeiro (custo parado + potencial de lucro) e a
# CONSULTA AUTOMÁTICA na indicação de cirurgia (tem a lente? agenda;
# não tem? abre PEDIDO vinculado ao card do paciente). Aditiva.
class CreateCevicoStock < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    create_table :cevico_stock_items do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false                                        # ex: Lente Trifocal
      t.string :category, null: false, default: 'lentes'                 # lentes | insumos | medicamentos | outros
      t.string :specification, default: ''                               # config: dioptria, cilindro, marca…
      t.integer :quantity, null: false, default: 0
      t.integer :min_quantity, null: false, default: 0                   # alerta de estoque baixo
      t.decimal :unit_cost, precision: 12, scale: 2, null: false, default: 0
      t.decimal :sale_price, precision: 12, scale: 2, null: false, default: 0
      t.string :supplier, default: ''
      t.string :notes, default: ''
      t.timestamps
    end
    add_index :cevico_stock_items, [:account_id, :category]

    create_table :cevico_stock_orders do |t|
      t.references :account, null: false, foreign_key: true
      t.references :stock_item, foreign_key: { to_table: :cevico_stock_items } # pode ser nil: encomenda de item fora do catálogo
      t.string :item_name, null: false                                   # o que encomendar (congelado no pedido)
      t.string :specification, default: ''
      t.integer :quantity, null: false, default: 1
      t.string :reason, default: ''                                      # motivo: "indicação p/ paciente X"
      t.string :status, null: false, default: 'pendente'                 # pendente | encomendado | recebido | cancelado
      t.integer :task_id                                                 # card do paciente no CRM (vínculo do pedido)
      t.integer :contact_id
      t.integer :created_by_id
      t.datetime :received_at
      t.timestamps
    end
    add_index :cevico_stock_orders, [:account_id, :status]
  end
end
