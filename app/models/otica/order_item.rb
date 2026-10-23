# Item da O.S.: o produto (quando é do catálogo) com a descrição CONGELADA
# na venda, quantidade, preço unitário, desconto do item e total.
# == Schema Information
#
# Table name: otica_order_items
#
#  id          :bigint           not null, primary key
#  description :string           default(""), not null
#  discount    :decimal(12, 2)   default(0.0), not null
#  kind        :string           default("outro"), not null
#  quantity    :integer          default(1), not null
#  total       :decimal(12, 2)   default(0.0), not null
#  unit_price  :decimal(12, 2)   default(0.0), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  order_id    :bigint           not null
#  product_id  :bigint
#
# Indexes
#
#  index_otica_order_items_on_account_id  (account_id)
#  index_otica_order_items_on_order_id    (order_id)
#  index_otica_order_items_on_product_id  (product_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (order_id => otica_orders.id) ON DELETE => cascade
#  fk_rails_...  (product_id => otica_products.id) ON DELETE => nullify
#
class Otica::OrderItem < ApplicationRecord
  belongs_to :account
  belongs_to :order, class_name: 'Otica::Order', inverse_of: :items
  belongs_to :product, class_name: 'Otica::Product', optional: true, inverse_of: :order_items
  has_one :lab_order, class_name: 'Otica::LabOrder', dependent: :nullify, inverse_of: :order_item

  before_validation :fill_from_product, :compute_total

  validates :kind, inclusion: { in: Otica::Product::KINDS.keys }
  validates :description, presence: true
  validates :quantity, numericality: { greater_than: 0, only_integer: true }
  validates :unit_price, :discount, numericality: { greater_than_or_equal_to: 0 }

  def lens?
    Otica::Product::LENS_KINDS.include?(kind)
  end

  def as_json_otica
    { id: id, product_id: product_id, kind: kind, kind_label: Otica::Product::KINDS[kind], description: description,
      quantity: quantity, unit_price: unit_price.to_f, discount: discount.to_f, total: total.to_f,
      lab_order: lab_order&.as_json_otica }
  end

  private

  def fill_from_product
    return if product.nil?

    self.kind = product.kind if kind.blank? || kind == 'outro'
    self.description = product.name if description.blank?
    self.unit_price = product.price if unit_price.to_f.zero? && new_record?
  end

  def compute_total
    self.total = [(quantity.to_i * unit_price.to_f) - discount.to_f, 0].max.round(2)
  end
end
