# Pedido da lente ao LABORATÓRIO: nasce de um item de lente da O.S., tem o
# laboratório (fornecedor tipo lab), quando foi enviado, a previsão, quando
# chegou e o custo. Quando todos os pedidos da O.S. chegam, a O.S. vira
# "pronta" sozinha (Otica::OrderStatus).
# == Schema Information
#
# Table name: otica_lab_orders
#
#  id            :bigint           not null, primary key
#  cost          :decimal(12, 2)   default(0.0), not null
#  expected_on   :date
#  notes         :string           default("")
#  received_at   :datetime
#  sent_at       :datetime
#  status        :string           default("pendente"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  order_id      :bigint           not null
#  order_item_id :bigint
#  supplier_id   :bigint
#
# Indexes
#
#  index_otica_lab_orders_on_account_id             (account_id)
#  index_otica_lab_orders_on_account_id_and_status  (account_id,status)
#  index_otica_lab_orders_on_order_id               (order_id)
#  index_otica_lab_orders_on_order_item_id          (order_item_id)
#  index_otica_lab_orders_on_supplier_id            (supplier_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (order_id => otica_orders.id) ON DELETE => cascade
#  fk_rails_...  (order_item_id => otica_order_items.id) ON DELETE => nullify
#  fk_rails_...  (supplier_id => otica_suppliers.id) ON DELETE => nullify
#
class Otica::LabOrder < ApplicationRecord
  belongs_to :account
  belongs_to :order, class_name: 'Otica::Order', inverse_of: :lab_orders
  belongs_to :order_item, class_name: 'Otica::OrderItem', optional: true, inverse_of: :lab_order
  belongs_to :supplier, class_name: 'Otica::Supplier', optional: true, inverse_of: :lab_orders

  STATUSES = {
    'pendente' => 'A enviar',
    'enviado' => 'No laboratório',
    'recebido' => 'Chegou',
    'cancelado' => 'Cancelado'
  }.freeze
  TRANSITIONS = {
    'pendente' => %w[enviado recebido cancelado],
    'enviado' => %w[recebido cancelado pendente],
    'recebido' => %w[enviado],
    'cancelado' => %w[pendente]
  }.freeze

  validates :status, inclusion: { in: STATUSES.keys }
  validates :cost, numericality: { greater_than_or_equal_to: 0 }

  def late?(today = Otica.today)
    expected_on.present? && expected_on < today && %w[pendente enviado].include?(status)
  end

  def as_json_otica
    { id: id, order_id: order_id, item_id: order_item_id, item_description: order_item&.description,
      supplier_id: supplier_id, supplier_name: supplier&.name, status: status, status_label: STATUSES[status],
      sent_at: sent_at&.iso8601, expected_on: expected_on&.iso8601, received_at: received_at&.iso8601,
      cost: cost.to_f, notes: notes, late: late? }
  end
end
