require 'rails_helper'

# 📦 SUA ÓTICA — FASE 2 (23/10/2026): o ESTOQUE de verdade.
#   · o saldo só muda por movimentação (livro): venda gravada baixa, alterar a
#     venda sai/volta só a diferença, cancelar devolve, orçamento não mexe;
#   · lente de grau e serviço não têm saldo; a venda nunca trava por estoque;
#   · compra por XML da NF-e: lê a nota, casa pelo código de barras/código,
#     receber dá entrada e atualiza o custo; inventário ajusta;
#   · visão: vendidos, cobertura e encalhados; CSV/edição do produto viram ajuste.
RSpec.describe 'Sua Ótica — fase 2 (estoque)', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/otica" }
  let(:headers) { admin.create_new_auth_token }
  let!(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Aquisição', position: 0) }

  before do
    Current.reset
    Crm::Stage.create!(pipeline: pipeline, name: 'Pedido fechado', color: '#000', position: 0)
    CrmSetting.create!(account: account, agenda_config: { 'company' => { 'segment' => 'otica' } })
  end

  def product!(**attrs)
    p = account.otica_products.create!({ kind: 'armacao', brand: 'Ray-Ban', model: 'RB5154', color: 'Preto', size: '49',
                                         sku: "ARM-#{SecureRandom.hex(2)}", cost: 180, list_price: 489 }.merge(attrs.except(:quantity)))
    Otica::StockLedger.set_quantity!(p, attrs.fetch(:quantity, 0), origin: 'cadastro') if attrs[:quantity].to_i.positive?
    p.reload
  end

  def order!(items, status: 'aberta')
    post "#{base}/orders", params: { contact: { name: 'Maria', phone_number: '11988887777' }, status: status,
                                     items: items.map { |p, q| { product_id: p.id, quantity: q } } }, headers: headers, as: :json
    Otica::Order.find(response.parsed_body['order']['id'])
  end

  describe 'venda × estoque' do
    let!(:armacao) { product!(sku: 'ARM-001', quantity: 3) }
    let!(:lente) { account.otica_products.create!(kind: 'lente', name: 'Lente multifocal', list_price: 1290) }

    it 'gravar baixa só o que é peça; alterar sai/volta a diferença; cancelar devolve; orçamento não mexe', :aggregate_failures do
      order = order!([[armacao, 1], [lente, 1]])
      expect(armacao.reload.quantity).to eq(2)
      expect(account.otica_stock_moves.where(reference: order).pluck(:origin, :delta)).to eq([['venda', -1]])
      expect(lente.reload.quantity).to eq(0)
      expect(account.otica_stock_moves.where(product: lente)).to be_empty

      patch "#{base}/orders/#{order.id}", params: { items: [{ product_id: armacao.id, quantity: 3 }] }, headers: headers, as: :json
      expect(armacao.reload.quantity).to eq(0)
      expect(account.otica_stock_moves.where(reference: order).sum(:delta)).to eq(-3)

      post "#{base}/orders/#{order.id}/set_status", params: { status: 'cancelada' }, headers: headers, as: :json
      expect(armacao.reload.quantity).to eq(3)
      expect(account.otica_stock_moves.where(reference: order).order(:id).last.origin).to eq('cancelamento')

      budget = order!([[armacao, 2]], status: 'orcamento')
      expect(armacao.reload.quantity).to eq(3)
      patch "#{base}/orders/#{budget.id}", params: { status: 'aberta' }, headers: headers, as: :json
      expect(armacao.reload.quantity).to eq(1)
    end

    it 'a venda não trava por estoque zerado (saldo fica negativo e aparece no livro)' do
      order!([[armacao, 5]])
      expect(armacao.reload.quantity).to eq(-2)
      expect(response).to have_http_status(:success)
    end

    it 'entregar e devolver: devolvida volta ao estoque' do
      order = order!([[armacao, 1]])
      post "#{base}/orders/#{order.id}/set_status", params: { status: 'entregue' }, headers: headers, as: :json
      expect(armacao.reload.quantity).to eq(2)
      post "#{base}/orders/#{order.id}/set_status", params: { status: 'devolvida' }, headers: headers, as: :json
      expect(armacao.reload.quantity).to eq(3)
      expect(account.otica_stock_moves.order(:id).last.origin).to eq('devolucao')
    end
  end

  describe 'livro, inventário e cadastro' do
    let!(:armacao) { product!(sku: 'ARM-001', quantity: 3) }

    it 'movimentação manual, ajuste e inventário gravam saldo depois', :aggregate_failures do
      post "#{base}/stock/moves", params: { product_id: armacao.id, kind: 'entrada', quantity: 2, notes: 'achei na gaveta' }, headers: headers,
                                  as: :json
      expect(response.parsed_body['move']).to include('delta' => 2, 'balance_after' => 5)
      post "#{base}/stock/moves", params: { product_id: armacao.id, kind: 'ajuste', quantity: 4 }, headers: headers, as: :json
      expect(response.parsed_body['move']).to include('delta' => -1, 'balance_after' => 4)

      post "#{base}/stock/inventory", params: { rows: [{ product_id: armacao.id, counted: 7 }, { product_id: armacao.id, counted: '' }] },
                                      headers: headers, as: :json
      expect(response.parsed_body).to include('adjusted' => 1)
      expect(armacao.reload.quantity).to eq(7)
      expect(account.otica_stock_moves.order(:id).last).to have_attributes(origin: 'inventario', delta: 3)

      get "#{base}/stock/moves", params: { product_id: armacao.id }, headers: headers, as: :json
      expect(response.parsed_body['moves'].size).to eq(4)
    end

    it 'editar o saldo no cadastro e o CSV do SavWin viram ajuste', :aggregate_failures do
      patch "#{base}/products/#{armacao.id}", params: { quantity: 10 }, headers: headers, as: :json
      expect(armacao.reload.quantity).to eq(10)
      expect(account.otica_stock_moves.order(:id).last).to have_attributes(origin: 'manual', delta: 7)

      post "#{base}/products/import_csv", params: { csv: "codigo;grife;modelo;saldo\nARM-001;Ray-Ban;RB5154;4\n" }, headers: headers, as: :json
      expect(armacao.reload.quantity).to eq(4)
      expect(account.otica_stock_moves.order(:id).last).to have_attributes(origin: 'importacao', delta: -6)
    end
  end

  describe 'compras' do
    let!(:armacao) { product!(sku: 'ARM-001', barcode: '7891234567890', quantity: 1, cost: 180) }
    let(:xml) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <nfeProc xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
          <NFe><infNFe Id="NFe35261012345678000199550010000001231000001234" versao="4.00">
            <ide><nNF>123</nNF><serie>1</serie><dhEmi>2026-10-20T10:00:00-03:00</dhEmi></ide>
            <emit><CNPJ>12345678000199</CNPJ><xNome>Distribuidora Exemplo LTDA</xNome></emit>
            <det nItem="1"><prod><cProd>ARM-001</cProd><cEAN>7891234567890</cEAN><xProd>ARMACAO RB5154 PRETO 49</xProd><NCM>90031100</NCM>
              <qCom>5.0000</qCom><vUnCom>190.0000000000</vUnCom></prod></det>
            <det nItem="2"><prod><cProd>NOVO-77</cProd><cEAN>SEM GTIN</cEAN><xProd>ARMACAO OAKLEY OX8046</xProd><NCM>90031100</NCM>
              <qCom>2.0000</qCom><vUnCom>210.00</vUnCom></prod></det>
            <total><ICMSTot><vNF>1370.00</vNF></ICMSTot></total>
          </infNFe></NFe>
        </nfeProc>
      XML
    end

    it 'lê o XML, casa pelo código de barras, cria produto novo e recebe com entrada e custo', :aggregate_failures do
      post "#{base}/stock/purchases/preview_xml", params: { xml: xml }, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      preview = response.parsed_body
      expect(preview['purchase']).to include('number' => '123', 'supplier_name' => 'Distribuidora Exemplo LTDA', 'total' => 1370.0,
                                             'access_key' => '35261012345678000199550010000001231000001234')
      expect(preview['items'][0]).to include('product_id' => armacao.id, 'quantity' => 5, 'unit_cost' => 190.0)
      expect(preview['items'][1]).to include('product_id' => nil, 'code' => 'NOVO-77', 'ean' => '')
      expect(account.otica_purchases.count).to eq(0)

      items = preview['items']
      items[1]['create_product'] = { kind: 'armacao', brand: 'Oakley', model: 'OX8046', color: 'Grafite', size: '54' }
      post "#{base}/stock/purchases", params: preview['purchase'].merge(items: items, receive: true), headers: headers, as: :json
      expect(response).to have_http_status(:success)
      purchase = response.parsed_body['purchase']
      expect(purchase).to include('status' => 'recebida', 'total' => 1370.0)
      expect(armacao.reload.quantity).to eq(6)
      expect(armacao.cost.to_f).to eq(190.0)
      novo = account.otica_products.find_by(sku: 'NOVO-77')
      expect(novo).to have_attributes(brand: 'Oakley', quantity: 2)
      expect(account.otica_stock_moves.where(origin: 'compra').sum(:delta)).to eq(7)

      post "#{base}/stock/purchases/#{purchase['id']}/receive", headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'XML que não é NF-e é recusado com frase' do
      post "#{base}/stock/purchases/preview_xml", params: { xml: '<a/>' }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('infNFe')
    end
  end

  describe 'visão do estoque' do
    it 'vendidos, cobertura e encalhados', :aggregate_failures do
      vendida = product!(sku: 'V', quantity: 6)
      parada = product!(sku: 'P', quantity: 2, created_at: 200.days.ago)
      order!([[vendida, 3]])
      get "#{base}/stock", params: { days: 90 }, headers: headers, as: :json
      body = response.parsed_body
      v = body['rows'].find { |r| r['id'] == vendida.id }
      p = body['rows'].find { |r| r['id'] == parada.id }
      expect(v).to include('sold' => 3, 'quantity' => 3, 'coverage_months' => 3.0, 'stale' => false)
      expect(p).to include('sold' => 0, 'coverage_months' => nil, 'stale' => true)
      expect(body['summary']).to include('stale_count' => 1, 'stale_cost' => 360.0, 'sold_units' => 3)
      expect(body['recent_moves'].first['origin']).to eq('venda')
    end
  end
end
