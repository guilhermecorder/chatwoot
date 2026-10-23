# 👓 SUA ÓTICA — FASE 1 (22/10/2026): o núcleo da loja no NOSSO sistema.
# Produtos em grade (grife · modelo · cor · tamanho) com custo/preço/saldo,
# fornecedores e laboratórios, receita (grau), a O.S. (venda) com itens,
# pedido da lente ao laboratório e pagamentos simples (parcelas detalhadas
# e conciliação ficam para a fase 3). Tudo por conta (account_id); nada das
# tabelas da clínica muda. Reversível: só create_table.
class CreateOticaCore < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    create_table :otica_suppliers do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false, default: 'fornecedor'               # lab | fornecedor
      t.string :phone, default: ''
      t.string :email, default: ''
      t.integer :lab_days, null: false, default: 0                      # prazo padrão do laboratório (dias)
      t.string :notes, default: ''
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :otica_suppliers, [:account_id, :kind]

    create_table :otica_products do |t|
      t.references :account, null: false, foreign_key: true
      t.references :supplier, foreign_key: { to_table: :otica_suppliers }
      t.string :kind, null: false, default: 'armacao'                   # armacao | solar | lente | lente_contato | servico | outro
      t.string :name, null: false, default: ''                          # nome de exibição (montado da grade quando vazio)
      t.string :brand, default: ''                                      # grife
      t.string :line, default: ''                                       # linha
      t.string :model, default: ''
      t.string :color, default: ''
      t.string :size, default: ''
      t.string :sku, default: ''                                        # código (o do SavWin na importação)
      t.string :barcode, default: ''
      t.string :ncm, default: ''
      t.decimal :cost, precision: 12, scale: 2, null: false, default: 0
      t.decimal :list_price, precision: 12, scale: 2, null: false, default: 0
      t.decimal :promo_price, precision: 12, scale: 2
      t.date :promo_until
      t.boolean :active, null: false, default: true
      t.integer :quantity, null: false, default: 0                      # saldo (uma loja; movimentação = fase 2)
      t.integer :min_quantity, null: false, default: 0
      t.string :lens_type, default: ''                                  # visao_simples | multifocal | bifocal
      t.string :lens_material, default: ''
      t.string :lens_treatment, default: ''
      t.integer :lab_days, null: false, default: 0                      # prazo do laboratório para esta lente
      t.string :notes, default: ''
      t.timestamps
    end
    add_index :otica_products, [:account_id, :kind]
    add_index :otica_products, [:account_id, :sku]
    add_index :otica_products, [:account_id, :barcode]

    create_table :otica_prescriptions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }
      t.string :doctor_name, default: ''
      t.date :prescribed_on
      t.date :valid_until
      t.decimal :od_sphere, precision: 6, scale: 2
      t.decimal :od_cylinder, precision: 6, scale: 2
      t.integer :od_axis
      t.decimal :od_addition, precision: 6, scale: 2
      t.decimal :od_dnp, precision: 6, scale: 2
      t.decimal :od_height, precision: 6, scale: 2
      t.decimal :oe_sphere, precision: 6, scale: 2
      t.decimal :oe_cylinder, precision: 6, scale: 2
      t.integer :oe_axis
      t.decimal :oe_addition, precision: 6, scale: 2
      t.decimal :oe_dnp, precision: 6, scale: 2
      t.decimal :oe_height, precision: 6, scale: 2
      t.string :photo_url, default: ''
      t.string :notes, default: ''
      t.timestamps
    end

    create_table :otica_orders do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }
      t.references :seller, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :prescription, foreign_key: { to_table: :otica_prescriptions, on_delete: :nullify }
      t.references :second_pair_of, foreign_key: { to_table: :otica_orders, on_delete: :nullify }
      t.integer :number, null: false                                    # nº da O.S. por conta
      t.string :status, null: false, default: 'aberta'                  # orcamento | aberta | em_producao | pronta | entregue | cancelada | devolvida
      t.string :doctor_name, default: ''
      t.date :sold_on, null: false
      t.date :due_on                                                    # previsão de entrega
      t.datetime :delivered_at
      t.decimal :gross, precision: 12, scale: 2, null: false, default: 0
      t.decimal :discount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :net, precision: 12, scale: 2, null: false, default: 0
      t.text :notes
      t.integer :crm_contact_id                                         # card do CRM que a O.S. moveu por último
      t.integer :created_by_id
      t.timestamps
    end
    add_index :otica_orders, [:account_id, :number], unique: true
    add_index :otica_orders, [:account_id, :status]
    add_index :otica_orders, [:account_id, :sold_on]

    create_table :otica_order_items do |t|
      t.references :account, null: false, foreign_key: true
      t.references :order, null: false, foreign_key: { to_table: :otica_orders, on_delete: :cascade }
      t.references :product, foreign_key: { to_table: :otica_products, on_delete: :nullify }
      t.string :kind, null: false, default: 'outro'
      t.string :description, null: false, default: ''                   # congelado na venda
      t.integer :quantity, null: false, default: 1
      t.decimal :unit_price, precision: 12, scale: 2, null: false, default: 0
      t.decimal :discount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :total, precision: 12, scale: 2, null: false, default: 0
      t.timestamps
    end

    create_table :otica_lab_orders do |t|
      t.references :account, null: false, foreign_key: true
      t.references :order, null: false, foreign_key: { to_table: :otica_orders, on_delete: :cascade }
      t.references :order_item, foreign_key: { to_table: :otica_order_items, on_delete: :nullify }
      t.references :supplier, foreign_key: { to_table: :otica_suppliers, on_delete: :nullify }
      t.string :status, null: false, default: 'pendente'                # pendente | enviado | recebido | cancelado
      t.datetime :sent_at
      t.date :expected_on
      t.datetime :received_at
      t.decimal :cost, precision: 12, scale: 2, null: false, default: 0
      t.string :notes, default: ''
      t.timestamps
    end
    add_index :otica_lab_orders, [:account_id, :status]

    create_table :otica_payments do |t|
      t.references :account, null: false, foreign_key: true
      t.references :order, null: false, foreign_key: { to_table: :otica_orders, on_delete: :cascade }
      t.string :method, null: false, default: 'pix'                     # pix | dinheiro | debito | credito | crediario | boleto
      t.integer :installments, null: false, default: 1
      t.decimal :amount, precision: 12, scale: 2, null: false, default: 0
      t.date :paid_on
      t.string :notes, default: ''
      t.timestamps
    end
  end
end
