# COMPRA (entrada de mercadoria): a NF-e lida do XML ou uma entrada manual,
# com os itens. "Receber" é o que põe as peças no estoque (StockLedger) e
# atualiza o custo do produto.
# == Schema Information
#
# Table name: otica_purchases
#
#  id            :bigint           not null, primary key
#  access_key    :string           default("")
#  issued_on     :date
#  notes         :string           default("")
#  number        :string           default("")
#  received_at   :datetime
#  series        :string           default("")
#  status        :string           default("rascunho"), not null
#  supplier_cnpj :string           default("")
#  supplier_name :string           default("")
#  total         :decimal(12, 2)   default(0.0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :integer
#  supplier_id   :bigint
#
# Indexes
#
#  index_otica_purchases_on_account_id                 (account_id)
#  index_otica_purchases_on_account_id_and_access_key  (account_id,access_key)
#  index_otica_purchases_on_account_id_and_status      (account_id,status)
#  index_otica_purchases_on_supplier_id                (supplier_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (supplier_id => otica_suppliers.id) ON DELETE => nullify
#
class Otica::Purchase < ApplicationRecord
  belongs_to :account
  belongs_to :supplier, class_name: 'Otica::Supplier', optional: true
  has_many :items, class_name: 'Otica::PurchaseItem', dependent: :destroy, inverse_of: :purchase
  has_many :stock_moves, class_name: 'Otica::StockMove', as: :reference, dependent: :nullify

  STATUSES = { 'rascunho' => 'Conferindo', 'recebida' => 'Recebida', 'cancelada' => 'Cancelada' }.freeze

  validates :status, inclusion: { in: STATUSES.keys }

  def label
    number.present? ? "NF #{number}" : "Compra #{id}"
  end

  def recalculate!
    update_columns(total: items.reload.sum { |i| i.total.to_f }.round(2)) # rubocop:disable Rails/SkipsModelValidations
  end

  def as_json_otica
    { id: id, status: status, status_label: STATUSES[status], supplier_id: supplier_id,
      supplier_name: supplier&.name.presence || supplier_name, supplier_cnpj: supplier_cnpj,
      number: number, series: series, access_key: access_key, issued_on: issued_on&.iso8601,
      received_at: received_at&.iso8601, total: total.to_f, notes: notes,
      items: items.order(:id).map(&:as_json_otica), created_at: created_at.iso8601 }
  end
end
