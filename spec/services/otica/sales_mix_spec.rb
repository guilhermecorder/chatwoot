require 'rails_helper'

# 📊 08/11 (noite): o que vende por categoria → meta de estoque mínimo mensal → o que comprar
RSpec.describe Otica::SalesMix do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, name: 'Maria', phone_number: '+5511999990000') }

  def produto(name, kind: 'armacao', shape: '', brand: '', lens_type: '', quantity: 0, price: 300) # rubocop:disable Metrics/ParameterLists
    Otica::Product.create!(account: account, kind: kind, name: name, frame_shape: shape, brand: brand, lens_type: lens_type,
                           list_price: price, quantity: quantity)
  end

  def venda!(items, sold_on: Otica.today - 3, status: 'entregue')
    order = account.otica_orders.create!(contact: contact, status: status, sold_on: sold_on, created_by_id: admin.id)
    items.each do |product, qty|
      Otica::OrderItem.create!(account: account, order: order, product: product, kind: product.kind, description: product.name,
                               quantity: qty, unit_price: product.price)
    end
    order
  end

  it 'agrupa as vendas do período por formato, marca, lente e tipo, com saldo, meta e o que comprar', :aggregate_failures do
    gatinho = produto('Gatinho HB', shape: 'gatinho', brand: 'HB', quantity: 2)
    gatinho2 = produto('Gatinho Roma', shape: 'gatinho', brand: 'Roma', quantity: 1)
    quadrada = produto('Quadrada HB', shape: 'quadrada', brand: 'HB', quantity: 10)
    redonda = produto('Redonda parada', shape: 'redonda', brand: 'Smart', quantity: 6)
    multi = produto('Multifocal digital', kind: 'lente', lens_type: 'multifocal', price: 1200)
    simples = produto('Visão simples', kind: 'lente', lens_type: 'visao_simples', price: 300)

    venda!([[gatinho, 2], [multi, 1]])
    venda!([[gatinho2, 1], [simples, 1]], sold_on: Otica.today - 20)
    venda!([[quadrada, 1], [multi, 1]], sold_on: Otica.today - 50)
    venda!([[gatinho, 5]], sold_on: Otica.today - 200) # fora do período
    venda!([[redonda, 3]], status: 'cancelada') # cancelada não vende
    venda!([[quadrada, 2]], status: 'orcamento') # orçamento não vende

    out = described_class.new(account, days: 90).call
    expect(out).to include(in_days: 90, cobertura_meses: 1.5)
    shapes = out[:dimensions]['frame_shape'][:rows]
    gat = shapes.find { |r| r[:key] == 'gatinho' }
    expect(gat).to include(label: 'gatinho', sold_units: 3, orders: 2, stock_units: 3, share: 75.0, per_month: 1.0, meta_auto: 2, meta: 2, comprar: 0)
    expect(gat[:top].map { |t| [t[:name], t[:sold_units]] }).to eq([['Gatinho HB', 2], ['Gatinho Roma', 1]])
    quad = shapes.find { |r| r[:key] == 'quadrada' }
    expect(quad).to include(sold_units: 1, stock_units: 10, comprar: 0)
    red = shapes.find { |r| r[:key] == 'redonda' }
    expect(red).to include(sold_units: 0, stock_units: 6, meta: 0) # parada: aparece pelo saldo, sem compra

    marcas = out[:dimensions]['brand'][:rows]
    expect(marcas.first).to include(key: 'HB', sold_units: 3, stock_units: 12)
    lentes = out[:dimensions]['lens_type'][:rows]
    expect(lentes.first).to include(key: 'multifocal', label: 'Multifocal', sold_units: 2, sold_value: 2400.0, stock_units: nil, comprar: nil)
    tipos = out[:dimensions]['kind'][:rows]
    expect(tipos.map { |r| r[:key] }).to include('armacao', 'lente')
  end

  it 'meta manual vale sobre a automática e a cobertura muda a meta automática; chave inválida é ignorada', :aggregate_failures do
    gatinho = produto('Gatinho', shape: 'gatinho', quantity: 1)
    venda!([[gatinho, 6]], sold_on: Otica.today - 10) # 6 em 30 dias → 6/mês

    out = described_class.new(account, days: 30).call
    gat = out[:dimensions]['frame_shape'][:rows].find { |r| r[:key] == 'gatinho' }
    expect(gat).to include(per_month: 6.0, meta_auto: 9, meta: 9, comprar: 8)

    cfg = described_class.save_config!(account, 'cobertura_meses' => '2',
                                                'metas' => { 'frame_shape:gatinho' => 20, 'marciano:x' => 5, 'brand:HB' => 0 })
    expect(cfg).to eq('cobertura_meses' => 2.0, 'metas' => { 'frame_shape:gatinho' => 20 })
    gat = described_class.new(account, days: 30).call[:dimensions]['frame_shape'][:rows].find { |r| r[:key] == 'gatinho' }
    expect(gat).to include(meta_auto: 12, meta_manual: 20, meta: 20, comprar: 19)

    described_class.save_config!(account, 'metas' => { 'frame_shape:gatinho' => '' }) # apaga a manual
    expect(described_class.config(account)['metas']).to eq({})
  end
end
