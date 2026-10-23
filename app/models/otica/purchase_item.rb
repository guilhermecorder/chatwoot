# Item da compra: o que veio na nota, casado (ou não) com um produto.
# == Schema Information
#
# Table name: otica_purchase_items
#
#  id          :bigint           not null, primary key
#  code        :string           default("")
#  description :string           default(""), not null
#  ean         :string           default("")
#  ncm         :string           default("")
#  quantity    :integer          default(1), not null
#  total       :decimal(12, 2)   default(0.0), not null
#  unit_cost   :decimal(12, 2)   default(0.0), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  product_id  :bigint
#  purchase_id :bigint           not null
#
# Indexes
#
#  index_otica_purchase_items_on_account_id   (account_id)
#  index_otica_purchase_items_on_product_id   (product_id)
#  index_otica_purchase_items_on_purchase_id  (purchase_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (product_id => otica_products.id) ON DELETE => nullify
#  fk_rails_...  (purchase_id => otica_purchases.id) ON DELETE => cascade
#
class Otica::PurchaseItem < ApplicationRecord
  belongs_to :account
  belongs_to :purchase, class_name: 'Otica::Purchase', inverse_of: :items
  belongs_to :product, class_name: 'Otica::Product', optional: true

  before_validation { self.total = (quantity.to_i * unit_cost.to_f).round(2) }

  validates :description, presence: true
  validates :quantity, numericality: { greater_than: 0, only_integer: true }
  validates :unit_cost, numericality: { greater_than_or_equal_to: 0 }

  def as_json_otica
    { id: id, product_id: product_id, product_name: product&.name, description: description, ean: ean, ncm: ncm,
      code: code, quantity: quantity, unit_cost: unit_cost.to_f, total: total.to_f }
  end
end
