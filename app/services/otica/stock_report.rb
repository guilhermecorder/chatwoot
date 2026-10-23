# 📊 A visão do estoque: vendidos no período, última venda, cobertura
# (meses de estoque no ritmo atual) e encalhados (saldo parado há 180+
# dias sem vender). Lê as O.S. que venderam (não orçamento/cancelada).
class Otica::StockReport
  STALE_DAYS = 180
  SOLD_STATUSES = %w[aberta em_producao pronta entregue].freeze

  def initialize(account, days: 90)
    @account = account
    @days = days.to_i.clamp(7, 730)
    @today = Otica.today
  end

  def call # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    products = @account.otica_products.active.where(kind: Otica::Product::STOCK_KINDS).order(:kind, :brand, :model, :color, :size).to_a
    sold, last_sale = sales_by_product
    months = @days / 30.0
    rows = products.map do |p|
      n = sold[p.id].to_i
      last = last_sale[p.id]
      since = last || p.created_at.in_time_zone(Otica::TZ).to_date
      days_without = (@today - since).to_i
      coverage = n.positive? ? (p.quantity / (n / months)).round(1) : nil
      p.as_json_otica.slice(:id, :name, :kind, :kind_label, :brand, :model, :color, :size, :sku, :quantity, :min_quantity, :low, :cost, :price).merge(
        sold: n, last_sale_on: last&.iso8601, coverage_months: coverage,
        stale: p.quantity.positive? && days_without >= STALE_DAYS, days_without_sale: days_without
      )
    end
    stale = rows.select { |r| r[:stale] }
    sold_units = rows.sum { |r| r[:sold] }
    total_units = rows.sum { |r| r[:quantity] }
    {
      summary: {
        products: rows.size, units: total_units,
        total_cost: rows.sum { |r| r[:quantity] * r[:cost].to_f }.round(2),
        low_stock: rows.count { |r| r[:low] },
        stale_count: stale.size, stale_cost: stale.sum { |r| r[:quantity] * r[:cost].to_f }.round(2),
        coverage_months: sold_units.positive? ? (total_units / (sold_units / months)).round(1) : nil,
        sold_units: sold_units,
        sold_cost: rows.sum { |r| r[:sold] * r[:cost].to_f }.round(2),
        in_days: @days
      },
      rows: rows
    }
  end

  private

  # [vendidos por produto no período, última venda por produto (sem limite de período)]
  def sales_by_product
    items = Otica::OrderItem.joins(:order).where(account_id: @account.id).where.not(product_id: nil)
                            .where(otica_orders: { status: SOLD_STATUSES })
    sold = items.where(otica_orders: { sold_on: (@today - @days)..@today }).group(:product_id).sum(:quantity)
    last = items.group(:product_id).maximum('otica_orders.sold_on')
    [sold, last]
  end
end
