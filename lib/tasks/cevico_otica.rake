# 👓 SUA ÓTICA — tarefas da loja.
#   rake "cevico:otica:exemplos[6517]"  → dados de exemplo da fase 1 na conta
#     (3 produtos de cada tipo, 1 laboratório, 1 cliente, 1 O.S. completa com
#      pedido ao laboratório e entrega). Idempotente: roda de novo sem duplicar.
namespace :cevico do # rubocop:disable Metrics/BlockLength
  namespace :otica do # rubocop:disable Metrics/BlockLength
    desc 'Dados de exemplo da fase 1 (produtos, laboratório, cliente, O.S.) na conta informada'
    task :exemplos, [:account_id] => :environment do |_t, args| # rubocop:disable Metrics/BlockLength
      account = Account.find(args[:account_id] || ENV.fetch('ACCOUNT_ID'))
      user = account.users.order(:id).first

      lab = account.otica_suppliers.find_or_create_by!(name: 'Laboratório Exemplo') do |s|
        s.kind = 'lab'
        s.lab_days = 7
      end
      account.otica_suppliers.find_or_create_by!(name: 'Distribuidora Exemplo') { |s| s.kind = 'fornecedor' }

      produtos = [
        { kind: 'armacao', brand: 'Ray-Ban', model: 'RB5154', color: 'Preto', size: '49', sku: 'ARM-001', cost: 180, list_price: 489, quantity: 3 },
        { kind: 'armacao', brand: 'Oakley', model: 'OX8046', color: 'Grafite', size: '54', sku: 'ARM-002', cost: 210, list_price: 599, quantity: 2 },
        { kind: 'armacao', brand: 'Chilli Beans', model: 'LV.MT.0789', color: 'Tartaruga', size: '52', sku: 'ARM-003', cost: 95, list_price: 279,
          quantity: 4, min_quantity: 5 },
        { kind: 'solar', brand: 'Ray-Ban', model: 'Aviador RB3025', color: 'Dourado', size: '58', sku: 'SOL-001', cost: 320, list_price: 799,
          quantity: 2 },
        { kind: 'solar', brand: 'Oakley', model: 'Holbrook', color: 'Preto fosco', size: '57', sku: 'SOL-002', cost: 350, list_price: 899,
          quantity: 1 },
        { kind: 'solar', brand: 'Chilli Beans', model: 'OC.CL.4212', color: 'Rosé', size: '55', sku: 'SOL-003', cost: 110, list_price: 299,
          quantity: 3 },
        { kind: 'lente', name: 'Lente visão simples CR-39 antirreflexo', lens_type: 'visao_simples', lens_material: 'CR-39',
          lens_treatment: 'Antirreflexo', sku: 'LEN-001', cost: 60, list_price: 290, lab_days: 5, supplier_id: lab.id },
        { kind: 'lente', name: 'Lente multifocal digital antirreflexo + azul', lens_type: 'multifocal', lens_material: 'Policarbonato',
          lens_treatment: 'Antirreflexo e filtro azul', sku: 'LEN-002', cost: 320, list_price: 1290, promo_price: 990,
          promo_until: Time.zone.today + 60, lab_days: 10, supplier_id: lab.id },
        { kind: 'lente', name: 'Lente bifocal', lens_type: 'bifocal', lens_material: 'CR-39', lens_treatment: '', sku: 'LEN-003', cost: 90,
          list_price: 420, lab_days: 7, supplier_id: lab.id },
        { kind: 'lente_contato', name: 'Lente de contato mensal (caixa 6)', brand: 'Acuvue', sku: 'LC-001', cost: 120, list_price: 260, quantity: 6 },
        { kind: 'lente_contato', name: 'Lente de contato diária (caixa 30)', brand: 'Biotrue', sku: 'LC-002', cost: 150, list_price: 320,
          quantity: 4 },
        { kind: 'lente_contato', name: 'Lente de contato colorida', brand: 'FreshLook', sku: 'LC-003', cost: 70, list_price: 180, quantity: 2 },
        { kind: 'servico', name: 'Ajuste e limpeza', sku: 'SRV-001', cost: 0, list_price: 0 },
        { kind: 'servico', name: 'Troca de plaquetas', sku: 'SRV-002', cost: 5, list_price: 25 },
        { kind: 'servico', name: 'Montagem de lente avulsa', sku: 'SRV-003', cost: 0, list_price: 60 },
        { kind: 'outro', name: 'Estojo rígido', sku: 'OUT-001', cost: 8, list_price: 35, quantity: 20 },
        { kind: 'outro', name: 'Cordão para óculos', sku: 'OUT-002', cost: 4, list_price: 19.9, quantity: 15 },
        { kind: 'outro', name: 'Spray de limpeza 60 ml', sku: 'OUT-003', cost: 6, list_price: 29.9, quantity: 10, min_quantity: 12 }
      ]
      produtos.each do |attrs|
        p = account.otica_products.find_or_initialize_by(sku: attrs[:sku])
        p.assign_attributes(attrs)
        p.save!
      end

      contact = account.contacts.find_by(phone_number: '+5511988887777') ||
                account.contacts.create!(name: 'Maria Exemplo', phone_number: '+5511988887777', additional_attributes: { 'origem' => 'loja' })

      unless account.otica_orders.exists?(contact: contact)
        order = Otica::OrderForm.new(account: account, user: user, params: ActionController::Parameters.new(
          contact_id: contact.id, seller_id: user&.id, doctor_name: 'Dra. Ana Souza', due_on: (Time.zone.today + 10).iso8601,
          discount: '50,00', notes: 'Cliente prefere armação leve.',
          prescription: { doctor_name: 'Dra. Ana Souza', prescribed_on: (Time.zone.today - 3).iso8601, valid_until: (Time.zone.today + 362).iso8601,
                          od: { sphere: '-2,00', cylinder: '-0,50', axis: 180, dnp: 32 },
                          oe: { sphere: '-1,75', cylinder: '-0,25', axis: 10, dnp: 31 } },
          items: [
            { product_id: account.otica_products.find_by(sku: 'ARM-001').id, quantity: 1 },
            { product_id: account.otica_products.find_by(sku: 'LEN-002').id, quantity: 1 },
            { product_id: account.otica_products.find_by(sku: 'OUT-001').id, quantity: 1 }
          ],
          payments: [{ method: 'pix', installments: 1, amount: '500,00' }, { method: 'credito', installments: 6, amount: '964,00' }]
        )).create
        lens_item = order.items.detect(&:lens?)
        order.lab_orders.create!(account: account, order_item: lens_item, supplier: lab, status: 'enviado', sent_at: 2.days.ago,
                                 expected_on: Time.zone.today + 5, cost: 320)
        Otica::OrderStatus.change!(order, 'em_producao')
        puts "O.S. #{order.number} criada para #{contact.name} (#{order.status}, líquido R$ #{order.net})"

        # uma segunda venda já entregue (para o quadro ter as 3 colunas)
        second = account.contacts.find_by(phone_number: '+5511977776666') ||
                 account.contacts.create!(name: 'João Exemplo', phone_number: '+5511977776666', additional_attributes: { 'origem' => 'loja' })
        delivered = Otica::OrderForm.new(account: account, user: user, params: ActionController::Parameters.new(
          contact_id: second.id, seller_id: user&.id, sold_on: (Time.zone.today - 12).iso8601, due_on: (Time.zone.today - 2).iso8601,
          items: [{ product_id: account.otica_products.find_by(sku: 'SOL-001').id, quantity: 1 }],
          payments: [{ method: 'debito', installments: 1, amount: '799,00' }]
        )).create
        Otica::OrderStatus.change!(delivered, 'pronta')
        Otica::OrderStatus.change!(delivered, 'entregue', delivered_at: 1.day.ago)
        puts "O.S. #{delivered.number} entregue para #{second.name}"
      end

      puts "Produtos: #{account.otica_products.count} · Fornecedores: #{account.otica_suppliers.count} · O.S.: #{account.otica_orders.count}"
    end
  end
end
