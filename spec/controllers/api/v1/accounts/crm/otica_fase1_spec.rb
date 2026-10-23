require 'rails_helper'

# 👓 SUA ÓTICA — FASE 1 (22/10/2026): a O.S., os produtos e a ponte com o CRM.
#   · acesso: o nó `otica` só existe no ramo ótica; atendente sem concessão = 403;
#   · produtos: grade, preço vigente (promoção com validade), busca, CSV do SavWin;
#   · O.S.: totais (bruto − desconto), cliente novo pelo telefone (sem duplicar),
#     gravar move o card para "Pedido fechado" (achado pelo nome), "retirou" leva
#     ao funil de pós-venda em "Retirou o óculos" e dispara as automações da coluna;
#   · laboratório: último pedido recebido → O.S. pronta sozinha;
#   · tabela de preços do agente: conta de ótica com produtos lê os produtos;
#     conta de clínica segue idêntica.
RSpec.describe 'Sua Ótica — fase 1 (O.S., produtos, produção)', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:other_admin) { create(:user, account: other_account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/otica" }
  let(:headers) { admin.create_new_auth_token }

  let!(:pipeline1) { Crm::Pipeline.create!(account: account, name: 'Aquisição', position: 0) }
  let!(:pipeline2) { Crm::Pipeline.create!(account: account, name: 'Pós-venda e relacionamento', position: 1) }
  let!(:fechado) { Crm::Stage.create!(pipeline: pipeline1, name: 'Pedido fechado (1ª compra)', color: '#000', position: 1) }
  let!(:producao) { Crm::Stage.create!(pipeline: pipeline2, name: 'Pedido em produção', color: '#000', position: 0) }
  let!(:pronto) { Crm::Stage.create!(pipeline: pipeline2, name: 'Pronto para retirar', color: '#000', position: 1) }
  let!(:retirou) { Crm::Stage.create!(pipeline: pipeline2, name: 'Retirou o óculos', color: '#000', position: 2) }

  before do
    Current.reset
    Crm::Stage.create!(pipeline: pipeline1, name: 'Novos contatos', color: '#000', position: 0)
    CrmSetting.create!(account: account, agenda_config: { 'company' => { 'segment' => 'otica' } })
  end

  def product!(acc, **attrs)
    acc.otica_products.create!({ kind: 'armacao', brand: 'Ray-Ban', model: 'RB5154', color: 'Preto', size: '49',
                                 sku: "ARM-#{SecureRandom.hex(2)}", cost: 180, list_price: 489, quantity: 3 }.merge(attrs))
  end

  describe 'acesso' do
    # padrão do catálogo: a vendedora grava venda (otica = editar), consulta
    # produtos e preços (produtos = ver) mas não cadastra produto nem muda custo
    it 'atendente sem configuração: vende e consulta produtos, mas não cadastra produto', :aggregate_failures do
      get "#{base}/products", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)

      post "#{base}/products", params: { kind: 'armacao', brand: 'X', model: 'Y', list_price: 10 }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Otica::Product.count).to eq(0)

      post "#{base}/orders", params: { contact: { name: 'Cliente', phone_number: '11988887777' },
                                       items: [{ description: 'Ajuste', unit_price: '20' }] },
                             headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(Otica::Order.count).to eq(1)
    end

    it 'o nó otica não aparece na árvore de uma clínica, mas aparece na ótica', :aggregate_failures do
      clinica = Cevico::Company.for(other_account)
      expect(Cevico::AccessCatalog.tree_for(clinica).map { |n| n['key'] }).not_to include('otica')
      otica = Cevico::Company.for(account)
      expect(Cevico::AccessCatalog.tree_for(otica).map { |n| n['key'] }).to include('otica')
    end
  end

  describe 'produtos' do
    it 'cadastra com a grade, monta o nome e isola por conta', :aggregate_failures do
      post "#{base}/products", params: { kind: 'armacao', brand: 'Oakley', model: 'OX8046', color: 'Grafite', size: '54',
                                         cost: '210,00', list_price: '599', quantity: 2 }, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['name']).to eq('Oakley OX8046 Grafite 54')
      expect(body['list_price']).to eq(599.0)
      expect(body['cost']).to eq(210.0)

      product!(other_account, brand: 'Alheia')
      get "#{base}/products", headers: headers, as: :json
      expect(response.parsed_body['products'].map { |p| p['brand'] }).to eq(['Oakley'])
    end

    it 'preço vigente = promoção válida; promoção vencida ou maior que a tabela não vale', :aggregate_failures do
      valid = product!(account, list_price: 1290, promo_price: 990, promo_until: Otica.today + 10)
      expired = product!(account, list_price: 1290, promo_price: 990, promo_until: Otica.today - 1)
      bigger = product!(account, list_price: 100, promo_price: 150)
      expect(valid.price).to eq(990.0)
      expect(expired.price).to eq(1290.0)
      expect(bigger.price).to eq(100.0)
    end

    it 'busca por grife/modelo/código' do
      product!(account, brand: 'Ray-Ban', model: 'RB5154', sku: 'ARM-001')
      product!(account, brand: 'Oakley', model: 'Holbrook', sku: 'SOL-002', kind: 'solar')
      get "#{base}/products", params: { q: 'ray 5154' }, headers: headers, as: :json
      expect(response.parsed_body['products'].map { |p| p['sku'] }).to eq(['ARM-001'])
      get "#{base}/products", params: { q: 'SOL-002' }, headers: headers, as: :json
      expect(response.parsed_body['products'].map { |p| p['sku'] }).to eq(['SOL-002'])
    end

    it 'importa o CSV do SavWin (cria, atualiza pelo código, pula linha vazia)', :aggregate_failures do
      csv = <<~CSV
        Código;Grife;Modelo;Cor;Tamanho;Custo;Preço;Saldo
        ARM-001;Ray-Ban;RB5154;Preto;49;180,00;489,00;3
        LEN-002;;Lente multifocal digital;;;320,00;1.290,00;0
        ;;;;;;;
      CSV
      post "#{base}/products/import_csv", params: { csv: csv }, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('created' => 2, 'updated' => 0)
      lens = account.otica_products.find_by(sku: 'LEN-002')
      expect(lens.kind).to eq('lente')
      expect(lens.list_price.to_f).to eq(1290.0)

      post "#{base}/products/import_csv", params: { csv: csv.sub('489,00;3', '519,00;5') }, headers: headers, as: :json
      expect(response.parsed_body).to include('created' => 0, 'updated' => 2)
      expect(account.otica_products.find_by(sku: 'ARM-001').list_price.to_f).to eq(519.0)
      expect(account.otica_products.find_by(sku: 'ARM-001').quantity).to eq(5)
    end
  end

  describe 'O.S.' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let!(:armacao) { product!(account, sku: 'ARM-001', list_price: 489) }
    let!(:lente) { product!(account, sku: 'LEN-002', kind: 'lente', name: 'Lente multifocal', brand: '', model: '', list_price: 1290, lab_days: 10) }
    let!(:lab) { account.otica_suppliers.create!(name: 'Lab', kind: 'lab', lab_days: 7) }

    def create_order!(extra = {})
      post "#{base}/orders", params: {
        contact: { name: 'Maria Exemplo', phone_number: '(11) 98888-7777' },
        seller_id: admin.id, due_on: (Otica.today + 10).iso8601, discount: '50,00',
        prescription: { doctor_name: 'Dra. Ana', od: { sphere: '-2,00', cylinder: '-0,50', axis: 180 }, oe: { sphere: '-1,75' } },
        items: [{ product_id: armacao.id, quantity: 1 }, { product_id: lente.id, quantity: 1, discount: '90,00' }],
        payments: [{ method: 'pix', amount: '500' }, { method: 'credito', installments: 6, amount: '1.139,00' }]
      }.merge(extra), headers: headers, as: :json
      response.parsed_body['order']
    end

    it 'grava com totais certos, cria o cliente pelo telefone e move o card para Pedido fechado', :aggregate_failures do
      order = create_order!
      expect(response).to have_http_status(:success)
      expect(order['gross']).to eq(489.0 + 1200.0)
      expect(order['net']).to eq(1639.0)
      expect(order['paid']).to eq(1639.0)
      expect(order['balance']).to eq(0.0)
      expect(order['number']).to eq(1)
      expect(order['status']).to eq('aberta')
      expect(order['prescription']['od']['sphere']).to eq(-2.0)
      expect(order['prescription']['od']['axis']).to eq(180)
      expect(order['items'].map { |i| i['description'] }).to eq(['Ray-Ban RB5154 Preto 49', 'Lente multifocal'])

      contact = account.contacts.find_by(phone_number: '+5511988887777')
      expect(contact.name).to eq('Maria Exemplo')
      card = Crm::Contact.find_by(contact: contact, pipeline: pipeline1)
      expect(card.stage).to eq(fechado)
      expect(order['crm_card']).to eq('pipeline_name' => 'Aquisição', 'stage_name' => 'Pedido fechado (1ª compra)')
    end

    it 'cliente que já existe com outra máscara de telefone não duplica' do
      existing = account.contacts.create!(name: 'Maria', phone_number: '+5511988887777')
      create_order!
      expect(account.contacts.count).to eq(1)
      expect(Otica::Order.last.contact).to eq(existing)
    end

    it 'orçamento não mexe no card; virar aberta move' do
      create_order!(status: 'orcamento')
      order = Otica::Order.last
      expect(Crm::Contact.where(contact: order.contact)).to be_empty

      patch "#{base}/orders/#{order.id}", params: { status: 'aberta' }, headers: headers, as: :json
      expect(Crm::Contact.find_by(contact: order.contact, pipeline: pipeline1).stage).to eq(fechado)
    end

    it 'pedido ao laboratório → em produção; último recebido → pronta; retirou → Retirou o óculos e dispara a coluna', :aggregate_failures do
      order_json = create_order!
      order = Otica::Order.find(order_json['id'])
      lens_item = order.items.detect(&:lens?)

      post "#{base}/orders/#{order.id}/lab_orders", params: { item_ids: [lens_item.id], supplier_id: lab.id, cost: '320' }, headers: headers,
                                                    as: :json
      expect(response).to have_http_status(:success)
      expect(order.reload.status).to eq('em_producao')
      lab_order = order.lab_orders.first
      expect(lab_order.status).to eq('enviado')
      expect(lab_order.expected_on).to eq(Otica.today + 10) # prazo da lente
      expect(Crm::Contact.find_by(contact: order.contact, pipeline: pipeline2).stage).to eq(producao)

      patch "#{base}/lab_orders/#{lab_order.id}", params: { status: 'recebido' }, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(order.reload.status).to eq('pronta')
      expect(Crm::Contact.find_by(contact: order.contact, pipeline: pipeline2).stage).to eq(pronto)

      allow(CrmAutomationTriggerService).to receive(:new).and_call_original
      post "#{base}/orders/#{order.id}/set_status", params: { status: 'entregue' }, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(order.reload.status).to eq('entregue')
      expect(order.delivered_at).to be_present
      expect(Crm::Contact.find_by(contact: order.contact, pipeline: pipeline2).stage).to eq(retirou)
      expect(CrmAutomationTriggerService).to have_received(:new).with(hash_including(new_stage: retirou, event_type: 'card_entered'))
      # o card do funil 1 continua em Pedido fechado (a recompra não volta ao funil 1)
      expect(Crm::Contact.find_by(contact: order.contact, pipeline: pipeline1).stage).to eq(fechado)
    end

    it 'transição proibida é recusada com frase para a equipe' do
      create_order!(status: 'orcamento')
      post "#{base}/orders/#{Otica::Order.last.id}/set_status", params: { status: 'entregue' }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('não pode ir para entregue')
    end

    it 'resumo do WhatsApp traz itens, total e link com o telefone' do
      order = create_order!
      get "#{base}/orders/#{order['id']}/whatsapp", headers: headers, as: :json
      body = response.parsed_body
      expect(body['text']).to include('Ray-Ban RB5154 Preto 49', 'Total: R$ 1.639,00', 'OD -2,00 -0,50 180°')
      expect(body['link']).to start_with('https://wa.me/5511988887777?text=')
    end

    it 'venda da outra conta não aparece nem abre', :aggregate_failures do
      create_order!
      get "#{base}/orders", headers: other_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden).or have_http_status(:not_found)
      get "/api/v1/accounts/#{other_account.id}/crm/otica/orders", headers: other_admin.create_new_auth_token, as: :json
      expect(response.parsed_body['orders']).to eq([])
    end
  end

  describe 'tabela de preços do agente' do
    it 'ótica com produtos: o roteiro lê os produtos; sem produtos (ou clínica) segue como sempre', :aggregate_failures do
      before_block = Cevico::PriceList.prompt_block(account)
      expect(before_block).to include('PRK') # padrão de sempre

      product!(account, brand: 'Ray-Ban', list_price: 489)
      product!(account, brand: 'Ray-Ban', list_price: 980)
      product!(account, kind: 'lente', name: 'Lente multifocal digital', brand: '', model: '', lens_type: 'multifocal', list_price: 1290,
                        promo_price: 990, promo_until: Otica.today + 5, lab_days: 10)
      block = Cevico::PriceList.prompt_block(account)
      expect(block).to include('Armação: Ray-Ban de R$ 489 a R$ 980 (2 modelos)')
      expect(block).to include('Lente multifocal digital, multifocal R$ 990 (promoção; preço normal R$ 1.290) — prazo do laboratório 10 dias')
      expect(block).not_to include('PRK')

      # clínica com produtos de ótica (não deveria ter, mas se tiver) não muda nada
      product!(other_account, list_price: 100)
      expect(Cevico::PriceList.prompt_block(other_account)).to include('PRK')
      expect(Cevico::PriceList.prompt_block(other_account)).not_to include('Ray-Ban')
    end
  end

  describe 'Crm::AttendanceReflector (clínica intacta)' do
    it 'não cria card para quem não tem card em funil nenhum' do
      contact = other_account.contacts.create!(name: 'Paciente', phone_number: '+5511977776666')
      pipe = Crm::Pipeline.create!(account: other_account, name: 'Funil', position: 0)
      stage = Crm::Stage.create!(pipeline: pipe, name: 'Compareceu', color: '#000', position: 0)
      expect(Crm::AttendanceReflector.move_contact_to_stage(account: other_account, contact: contact, new_stage: stage)).to be_nil
      expect(Crm::Contact.where(contact: contact)).to be_empty
    end
  end
end
