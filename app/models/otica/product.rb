# Produto da ótica em GRADE (grife · linha · modelo · cor · tamanho) com
# custo, preço de tabela, promoção com validade e saldo. Para lente, ainda
# tipo (visão simples / multifocal / bifocal), material, tratamento e o
# prazo do laboratório. Saldo fica aqui (uma loja); a movimentação
# (entrada por compra, baixa por venda, inventário) é a fase 2.
# == Schema Information
#
# Table name: otica_products
#
#  id             :bigint           not null, primary key
#  active         :boolean          default(TRUE), not null
#  barcode        :string           default("")
#  brand          :string           default("")
#  color          :string           default("")
#  cost           :decimal(12, 2)   default(0.0), not null
#  kind           :string           default("armacao"), not null
#  lab_days       :integer          default(0), not null
#  lens_material  :string           default("")
#  lens_treatment :string           default("")
#  lens_type      :string           default("")
#  line           :string           default("")
#  list_price     :decimal(12, 2)   default(0.0), not null
#  min_quantity   :integer          default(0), not null
#  model          :string           default("")
#  name           :string           default(""), not null
#  ncm            :string           default("")
#  notes          :string           default("")
#  promo_price    :decimal(12, 2)
#  promo_until    :date
#  quantity       :integer          default(0), not null
#  size           :string           default("")
#  sku            :string           default("")
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  supplier_id    :bigint
#
# Indexes
#
#  index_otica_products_on_account_id              (account_id)
#  index_otica_products_on_account_id_and_barcode  (account_id,barcode)
#  index_otica_products_on_account_id_and_kind     (account_id,kind)
#  index_otica_products_on_account_id_and_sku      (account_id,sku)
#  index_otica_products_on_supplier_id             (supplier_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (supplier_id => otica_suppliers.id)
#
class Otica::Product < ApplicationRecord
  belongs_to :account
  belongs_to :supplier, class_name: 'Otica::Supplier', optional: true, inverse_of: :products
  has_many :order_items, class_name: 'Otica::OrderItem', dependent: :nullify, inverse_of: :product

  KINDS = {
    'armacao' => 'Armação',
    'solar' => 'Óculos de sol',
    'lente' => 'Lentes de grau',
    'lente_contato' => 'Lentes de contato',
    'servico' => 'Serviço',
    'outro' => 'Outro'
  }.freeze
  LENS_TYPES = { 'visao_simples' => 'Visão simples', 'multifocal' => 'Multifocal', 'bifocal' => 'Bifocal' }.freeze
  LENS_KINDS = %w[lente lente_contato].freeze

  before_validation :compose_name

  validates :kind, inclusion: { in: KINDS.keys }
  validates :name, presence: true
  validates :lens_type, inclusion: { in: LENS_TYPES.keys }, allow_blank: true
  validates :quantity, :min_quantity, :lab_days, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :cost, :list_price, numericality: { greater_than_or_equal_to: 0 }
  validates :promo_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :active, -> { where(active: true) }
  scope :low_stock, -> { where('min_quantity > 0 AND quantity <= min_quantity') }
  scope :priced, -> { where('list_price > 0') }

  # busca por grife, modelo, código, nome, cor (vários termos = todos precisam bater)
  def self.search(term)
    terms = term.to_s.strip.split(/\s+/).reject(&:blank?).first(5)
    return all if terms.empty?

    terms.reduce(all) do |scope, t|
      like = "%#{sanitize_sql_like(t)}%"
      scope.where('name ILIKE :q OR brand ILIKE :q OR model ILIKE :q OR sku ILIKE :q OR barcode ILIKE :q OR color ILIKE :q OR line ILIKE :q', q: like)
    end
  end

  def lens?
    LENS_KINDS.include?(kind)
  end

  # promoção vale se tem valor, é menor que a tabela e não venceu
  def promo_active?
    promo_price.present? && promo_price.to_f.positive? && promo_price.to_f < list_price.to_f &&
      (promo_until.nil? || promo_until >= Otica.today)
  end

  # o preço que vale hoje
  def price
    (promo_active? ? promo_price : list_price).to_f.round(2)
  end

  def low_stock?
    min_quantity.positive? && quantity <= min_quantity
  end

  def grade
    [brand, line, model, color, size].map(&:to_s).map(&:strip).compact_blank.join(' ')
  end

  def as_json_otica # rubocop:disable Metrics/AbcSize
    {
      id: id, kind: kind, kind_label: KINDS[kind], name: name,
      brand: brand, line: line, model: model, color: color, size: size,
      sku: sku, barcode: barcode, ncm: ncm,
      cost: cost.to_f, list_price: list_price.to_f,
      promo_price: promo_price&.to_f, promo_until: promo_until&.iso8601, price: price,
      active: active, quantity: quantity, min_quantity: min_quantity, low: low_stock?,
      lens_type: lens_type, lens_type_label: LENS_TYPES[lens_type], lens_material: lens_material,
      lens_treatment: lens_treatment, lab_days: lab_days,
      supplier_id: supplier_id, supplier_name: supplier&.name, notes: notes,
      updated_at: updated_at&.iso8601
    }
  end

  private

  def compose_name
    self.name = name.to_s.strip
    self.name = grade.presence || KINDS[kind].to_s if name.blank?
  end
end
