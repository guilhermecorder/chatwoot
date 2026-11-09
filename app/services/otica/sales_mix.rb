# 📊 O QUE VENDE × O QUE COMPRAR (08/11/2026, pedido do Guilherme): as vendas
# agrupadas por CATEGORIA — formato da armação (gatinho, quadrada, aviador…),
# marca, tipo de lente e tipo de produto — no período, com o saldo atual de
# cada categoria, a velocidade mensal e a META DE ESTOQUE MÍNIMO MENSAL:
#   meta automática = velocidade mensal × cobertura (padrão 1,5 mês)
#   meta manual     = a que a loja gravar na tela (vale sobre a automática)
#   comprar         = meta − saldo (só categorias com saldo: armação, solar…)
# É o fechamento do ciclo: o agente só mostra o que tem; a venda registra o
# que saiu; aqui a loja vê o que mais sai e repõe antes de faltar.
# Config em CrmSetting.ai_config['otica_estoque'] = {'cobertura_meses' => 1.5,
# 'metas' => {'frame_shape:gatinho' => 12, 'brand:HB' => 20}}.
class Otica::SalesMix
  CONFIG_KEY = 'otica_estoque'.freeze
  DEFAULT_COVERAGE = 1.5
  COVERAGE_RANGE = (0.5..6.0)
  SOLD_STATUSES = Otica::StockReport::SOLD_STATUSES
  TOP_PER_ROW = 3
  DIMENSIONS = {
    'frame_shape' => { label: 'Formato da armação', kinds: Otica::Product::FRAME_KINDS, stock: true },
    'brand' => { label: 'Marca (armações e solares)', kinds: Otica::Product::FRAME_KINDS, stock: true },
    'lens_type' => { label: 'Tipo de lente', kinds: %w[lente], stock: false },
    'kind' => { label: 'Tipo de produto', kinds: Otica::Product::KINDS.keys, stock: true }
  }.freeze

  def self.config(account)
    cfg = (CrmSetting.find_by(account: account)&.ai_config&.dig(CONFIG_KEY) || {}).to_h
    { 'cobertura_meses' => cfg['cobertura_meses'].to_f.positive? ? cfg['cobertura_meses'].to_f.clamp(COVERAGE_RANGE) : DEFAULT_COVERAGE,
      'metas' => (cfg['metas'] || {}).to_h }
  end

  # attrs: {'cobertura_meses' => 2, 'metas' => {'frame_shape:gatinho' => 12}} — meta vazia/zero apaga a manual
  def self.save_config!(account, attrs)
    setting = CrmSetting.find_or_create_by!(account: account)
    cfg = (setting.ai_config || {}).dup
    current = (cfg[CONFIG_KEY] || {}).to_h.dup
    current['cobertura_meses'] = attrs['cobertura_meses'].to_s.tr(',', '.').to_f.clamp(COVERAGE_RANGE).round(1) if attrs.key?('cobertura_meses')
    if attrs['metas'].is_a?(Hash)
      metas = (current['metas'] || {}).to_h.dup
      attrs['metas'].each do |key, value|
        k = key.to_s[0, 80]
        next unless DIMENSIONS.key?(k.split(':', 2).first)

        v = value.to_i
        v.positive? ? metas[k] = v : metas.delete(k)
      end
      current['metas'] = metas
    end
    cfg[CONFIG_KEY] = current
    setting.update!(ai_config: cfg)
    config(account)
  end

  def initialize(account, days: 90)
    @account = account
    @days = days.to_i.clamp(7, 730)
    @today = Otica.today
    @months = @days / 30.0
    @cfg = self.class.config(account)
  end

  def call
    {
      in_days: @days, months: @months.round(2), cobertura_meses: @cfg['cobertura_meses'],
      dimensions: DIMENSIONS.to_h { |dim, meta| [dim, { label: meta[:label], stock: meta[:stock], rows: rows_for(dim, meta) }] }
    }
  end

  private

  # uma linha por valor da dimensão (ex.: gatinho), com vendas, saldo, meta e o que comprar
  def rows_for(dim, meta) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    sold = sold_by(dim, meta[:kinds])
    stock = meta[:stock] ? stock_by(dim, meta[:kinds]) : {}
    total_units = sold.values.sum { |v| v[:units] }
    keys = (sold.keys + stock.keys).uniq
    rows = keys.map do |key|
      s = sold[key] || { units: 0, value: 0.0, orders: 0 }
      per_month = (s[:units] / @months).round(1)
      meta_key = "#{dim}:#{key}"
      manual = @cfg['metas'][meta_key].to_i
      auto = (per_month * @cfg['cobertura_meses']).ceil
      target = manual.positive? ? manual : auto
      saldo = stock[key]
      {
        key: key, label: label_for(dim, key),
        sold_units: s[:units], sold_value: s[:value].round(2), orders: s[:orders],
        share: total_units.positive? ? (100.0 * s[:units] / total_units).round(1) : 0.0,
        per_month: per_month, stock_units: saldo,
        meta: target, meta_auto: auto, meta_manual: (manual.positive? ? manual : nil),
        comprar: (saldo.nil? ? nil : [target - saldo, 0].max),
        top: top_products(dim, key, meta[:kinds])
      }
    end
    rows.sort_by { |r| [-r[:sold_units], -(r[:stock_units] || 0), r[:label]] }
  end

  def sold_items(kinds)
    Otica::OrderItem.joins(:order, :product).where(account_id: @account.id)
                    .where(otica_orders: { status: SOLD_STATUSES, sold_on: (@today - @days)..@today })
                    .where(otica_products: { kind: kinds })
  end

  # {valor da dimensão => {units, value, orders}}
  def sold_by(dim, kinds)
    col = "otica_products.#{dim}"
    units = sold_items(kinds).group(Arel.sql(col)).sum(:quantity)
    value = sold_items(kinds).group(Arel.sql(col)).sum(:total)
    orders = sold_items(kinds).group(Arel.sql(col)).distinct.count(:order_id)
    units.to_h { |k, u| [k.to_s, { units: u.to_i, value: value[k].to_f, orders: orders[k].to_i }] }
  end

  # saldo atual por valor da dimensão (só produtos ativos que têm saldo)
  def stock_by(dim, kinds)
    @account.otica_products.active.where(kind: kinds & Otica::Product::STOCK_KINDS)
            .group(Arel.sql("otica_products.#{dim}")).sum(:quantity).to_h { |k, q| [k.to_s, q.to_i] }
  end

  # os produtos que mais venderam dentro da categoria (pra saber O QUE repor)
  def top_products(dim, key, kinds)
    sold_items(kinds).where(otica_products: { dim => key }).group(:product_id).sum(:quantity)
                     .sort_by { |_, u| -u }.first(TOP_PER_ROW).filter_map do |product_id, units|
      p = Otica::Product.find_by(id: product_id)
      next if p.nil?

      { id: p.id, name: p.name, brand: p.brand, sold_units: units.to_i, stock_units: (p.stock_tracked? ? p.quantity : nil), price: p.price }
    end
  end

  def label_for(dim, key) # rubocop:disable Metrics/CyclomaticComplexity
    return '(sem formato)' if key.blank? && dim == 'frame_shape'
    return '(sem marca)' if key.blank?

    case dim
    when 'frame_shape' then Otica::Visagismo.frame_label(key)
    when 'lens_type' then Otica::Product::LENS_TYPES[key] || key
    when 'kind' then Otica::Product::KINDS[key] || key
    else key
    end
  end
end
