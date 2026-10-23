# Pagamento SIMPLES da O.S.: meio, nº de parcelas e valor. As parcelas
# detalhadas (vencimento, recebimento, adquirente, taxa, conciliação) são a
# fase 3 — esta tabela é a origem delas.
# == Schema Information
#
# Table name: otica_payments
#
#  id           :bigint           not null, primary key
#  amount       :decimal(12, 2)   default(0.0), not null
#  installments :integer          default(1), not null
#  method       :string           default("pix"), not null
#  notes        :string           default("")
#  paid_on      :date
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  order_id     :bigint           not null
#
# Indexes
#
#  index_otica_payments_on_account_id  (account_id)
#  index_otica_payments_on_order_id    (order_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (order_id => otica_orders.id) ON DELETE => cascade
#
class Otica::Payment < ApplicationRecord
  belongs_to :account
  belongs_to :order, class_name: 'Otica::Order', inverse_of: :payments

  METHODS = {
    'pix' => 'Pix',
    'dinheiro' => 'Dinheiro',
    'debito' => 'Débito',
    'credito' => 'Crédito',
    'crediario' => 'Crediário',
    'boleto' => 'Boleto'
  }.freeze

  validates :method, inclusion: { in: METHODS.keys }
  validates :installments, numericality: { greater_than: 0, only_integer: true }
  validates :amount, numericality: { greater_than: 0 }

  def as_json_otica
    { id: id, method: method, method_label: METHODS[method], installments: installments, amount: amount.to_f,
      paid_on: paid_on&.iso8601, notes: notes }
  end
end
