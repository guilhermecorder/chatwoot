# Um item do ESTOQUE da clínica (lentes, insumos, medicamentos).
# Guarda custo unitário e preço de venda: o dashboard mostra quanto
# dinheiro está parado em estoque e o potencial de lucro se tudo vender.
# == Schema Information
#
# Table name: cevico_stock_items
#
#  id            :bigint           not null, primary key
#  category      :string           default("lentes"), not null
#  min_quantity  :integer          default(0), not null
#  name          :string           not null
#  notes         :string           default("")
#  quantity      :integer          default(0), not null
#  sale_price    :decimal(12, 2)   default(0.0), not null
#  specification :string           default("")
#  supplier      :string           default("")
#  unit_cost     :decimal(12, 2)   default(0.0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#
# Indexes
#
#  index_cevico_stock_items_on_account_id               (account_id)
#  index_cevico_stock_items_on_account_id_and_category  (account_id,category)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class CevicoStockItem < ApplicationRecord
  belongs_to :account
  has_many :orders, class_name: 'CevicoStockOrder', foreign_key: :stock_item_id, dependent: :nullify, inverse_of: :stock_item

  # KEYS fixas (gravadas nos itens); RÓTULOS do segmento (preset clínica
  # = Lentes/Insumos/Medicamentos, como sempre)
  CATEGORIES = (Segmento.estoque_categorias.presence || {
    'lentes' => 'Lentes',
    'insumos' => 'Insumos',
    'medicamentos' => 'Medicamentos',
    'outros' => 'Outros'
  }).freeze

  validates :name, presence: true
  validates :category, inclusion: { in: CATEGORIES.keys }
  validates :quantity, :min_quantity, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :unit_cost, :sale_price, numericality: { greater_than_or_equal_to: 0 }

  # auditoria S3: alerta só quando a pessoa DEFINIU um mínimo (> 0) —
  # item recém-criado zerado não nasce "em alerta"
  scope :low_stock, -> { where('min_quantity > 0 AND quantity <= min_quantity') }

  def low_stock?
    min_quantity.positive? && quantity <= min_quantity
  end

  def total_cost
    (quantity * unit_cost.to_f).round(2)
  end

  def potential_profit
    (quantity * (sale_price.to_f - unit_cost.to_f)).round(2)
  end

  def full_name
    specification.present? ? "#{name} — #{specification}" : name
  end
end
