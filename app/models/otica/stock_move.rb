# Uma linha do LIVRO DE ESTOQUE: o que entrou, saiu ou foi ajustado em cada
# produto, por quê (origem), com o saldo depois. Só nasce pelo
# Otica::StockLedger — nunca à mão.
# == Schema Information
#
# Table name: otica_stock_moves
#
#  id             :bigint           not null, primary key
#  balance_after  :integer          not null
#  delta          :integer          not null
#  kind           :string           not null
#  notes          :string           default("")
#  origin         :string           default("manual"), not null
#  quantity       :integer          not null
#  reference_type :string
#  unit_cost      :decimal(12, 2)
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  created_by_id  :integer
#  product_id     :bigint           not null
#  reference_id   :bigint
#
# Indexes
#
#  index_otica_stock_moves_on_account_id                       (account_id)
#  index_otica_stock_moves_on_account_id_and_created_at        (account_id,created_at)
#  index_otica_stock_moves_on_account_id_and_product_id        (account_id,product_id)
#  index_otica_stock_moves_on_product_id                       (product_id)
#  index_otica_stock_moves_on_reference_type_and_reference_id  (reference_type,reference_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (product_id => otica_products.id) ON DELETE => cascade
#
class Otica::StockMove < ApplicationRecord
  belongs_to :account
  belongs_to :product, class_name: 'Otica::Product', inverse_of: :stock_moves
  belongs_to :reference, polymorphic: true, optional: true

  KINDS = { 'entrada' => 'Entrada', 'saida' => 'Saída', 'ajuste' => 'Ajuste' }.freeze
  ORIGINS = {
    'venda' => 'Venda',
    'cancelamento' => 'Cancelamento de venda',
    'devolucao' => 'Devolução',
    'compra' => 'Compra',
    'inventario' => 'Inventário',
    'manual' => 'Manual',
    'importacao' => 'Importação (CSV)',
    'cadastro' => 'Cadastro'
  }.freeze

  validates :kind, inclusion: { in: KINDS.keys }
  validates :origin, inclusion: { in: ORIGINS.keys }
  validates :quantity, numericality: { greater_than: 0, only_integer: true }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def reference_label
    reference.respond_to?(:label) ? reference.label : nil
  end

  def as_json_otica
    { id: id, product_id: product_id, product_name: product&.name, kind: kind, kind_label: KINDS[kind],
      origin: origin, origin_label: ORIGINS[origin], quantity: quantity, delta: delta, balance_after: balance_after,
      unit_cost: unit_cost&.to_f, reference: reference_label, notes: notes,
      user_name: created_by_id && User.find_by(id: created_by_id)&.name, created_at: created_at.iso8601 }
  end
end
