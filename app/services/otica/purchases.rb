# 🛒 COMPRAS: criar a compra (da NF lida ou manual), criar produto novo a
# partir do item quando pedido, e RECEBER = entrada no estoque pelo livro
# + custo do produto atualizado com o custo da nota.
class Otica::Purchases
  def self.create!(account:, user:, params:) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    p = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
    p = p.with_indifferent_access
    rows = Array(p[:items]).map { |r| r.to_h.with_indifferent_access }
    raise ArgumentError, 'A compra precisa de pelo menos um item.' if rows.empty?

    purchase = nil
    ActiveRecord::Base.transaction do
      purchase = account.otica_purchases.create!(
        supplier_id: p[:supplier_id].presence && account.otica_suppliers.find_by(id: p[:supplier_id])&.id,
        supplier_name: p[:supplier_name].to_s.strip[0, 160], supplier_cnpj: p[:supplier_cnpj].to_s.gsub(/\D/, '')[0, 14],
        number: p[:number].to_s.strip[0, 20], series: p[:series].to_s.strip[0, 10], access_key: p[:access_key].to_s.gsub(/\D/, '')[0, 44],
        issued_on: (Date.parse(p[:issued_on].to_s) rescue nil), notes: p[:notes].to_s.strip[0, 300], created_by_id: user&.id # rubocop:disable Style/RescueModifier
      )
      rows.each do |row|
        product = row[:product_id].present? ? account.otica_products.find_by(id: row[:product_id]) : nil
        product ||= create_product(account, row) if row[:create_product].present?
        purchase.items.create!(
          account: account, product: product, description: row[:description].to_s.strip[0, 200].presence || product&.name.to_s,
          ean: row[:ean].to_s.strip[0, 14], ncm: row[:ncm].to_s.strip[0, 10], code: row[:code].to_s.strip[0, 60],
          quantity: [row[:quantity].to_i, 1].max, unit_cost: Cevico::Money.parse(row[:unit_cost]) || 0.0
        )
      end
      purchase.recalculate!
    end
    receive!(purchase, user: user) if ActiveModel::Type::Boolean.new.cast(p[:receive])
    purchase.reload
  end

  def self.create_product(account, row) # rubocop:disable Metrics/AbcSize
    cp = row[:create_product].to_h.with_indifferent_access
    account.otica_products.create!(
      kind: Otica::Product::KINDS.key?(cp[:kind].to_s) ? cp[:kind].to_s : 'armacao',
      brand: cp[:brand].to_s.strip[0, 120], model: cp[:model].to_s.strip[0, 120], color: cp[:color].to_s.strip[0, 60],
      size: cp[:size].to_s.strip[0, 20], name: cp[:name].to_s.strip[0, 160],
      sku: row[:code].to_s.strip[0, 60], barcode: row[:ean].to_s.strip[0, 14], ncm: row[:ncm].to_s.strip[0, 10],
      cost: Cevico::Money.parse(row[:unit_cost]) || 0.0,
      list_price: Cevico::Money.parse(cp[:list_price]) || 0.0, quantity: 0
    )
  end

  def self.receive!(purchase, user: nil) # rubocop:disable Metrics/AbcSize
    raise ArgumentError, "#{purchase.label} já foi #{Otica::Purchase::STATUSES[purchase.status].downcase}." unless purchase.status == 'rascunho'

    ActiveRecord::Base.transaction do
      purchase.items.includes(:product).find_each do |item|
        next if item.product.nil?

        Otica::StockLedger.record!(product: item.product, kind: 'entrada', quantity: item.quantity, origin: 'compra',
                                   reference: purchase, unit_cost: item.unit_cost, user: user, notes: "entrada pela #{purchase.label}")
        item.product.update!(cost: item.unit_cost) if item.unit_cost.to_f.positive?
      end
      purchase.update!(status: 'recebida', received_at: Time.zone.now)
    end
    purchase
  end
end
