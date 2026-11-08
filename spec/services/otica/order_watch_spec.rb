require 'rails_helper'

# 👓📦 08/11: o vigia dos pedidos — tarefas para a equipe e o resumo para a Val virtual
RSpec.describe Otica::OrderWatch do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000') }
  let(:lab) { Otica::Supplier.create!(account: account, name: 'HB Lab', kind: 'lab') }
  let(:today) { Otica.today }

  before { Cevico::Company.save!(account, 'segment' => 'otica') }

  def order(status:, sold_on: today - 8, due_on: nil, ready_at: nil)
    o = account.otica_orders.create!(contact: contact, status: status, sold_on: sold_on, due_on: due_on, ready_at: ready_at, created_by_id: admin.id)
    o.items.create!(account: account, description: 'Armação + lente', quantity: 1, unit_price: 500, total: 500)
    o.recalculate!
    o
  end

  it 'nasce com prazo prometido de 7 dias e guarda a hora em que ficou pronta', :aggregate_failures do
    o = account.otica_orders.create!(contact: contact, status: 'aberta', sold_on: today, created_by_id: admin.id)
    expect(o.due_on).to eq(today + 7)
    Otica::OrderStatus.change!(o, 'em_producao')
    Otica::OrderStatus.change!(o, 'pronta')
    expect(o.reload.ready_at).to be_present
    expect(o.days_ready).to eq(0)
    Otica::OrderStatus.change!(o, 'em_producao')
    expect(o.reload.ready_at).to be_nil
  end

  it 'abre uma tarefa por motivo e por O.S., sem repetir no dia seguinte', :aggregate_failures do
    late = order(status: 'em_producao', due_on: today - 1)
    late.lab_orders.create!(account: account, order_item: late.items.first, supplier: lab, status: 'enviado', sent_at: 5.days.ago, expected_on: today - 2)
    ready = order(status: 'pronta', ready_at: 4.days.ago)
    order(status: 'aberta', sold_on: today - 3)
    order(status: 'aberta', sold_on: today) # recente: sem alerta
    order(status: 'entregue') # fechada: fora do vigia

    expect(described_class.new(account).run!).to eq(4)
    titles = account.tasks.where(task_type: described_class::TASK_TYPE).pluck(:title)
    expect(titles).to include(match(/Laboratório atrasado: O\.S\./), match(/Passou do prazo prometido/), match(/pronto há 4 dias sem retirada/),
                              match(/Pedir as lentes ao laboratório/))
    task = account.tasks.where('external_ref LIKE ?', "otica:os:#{late.id}:lab_atrasado:%").first
    expect(task.description).to include('HB Lab prometeu para').and include('Maria Silva')
    expect(task.assignee).to eq(admin)

    expect(described_class.new(account).run!).to eq(0) # mesmas O.S., mesmos motivos: nada novo
    expect(described_class.run_all!).to eq(0)
    task.update!(status: :done)
    expect(described_class.new(account).run!).to eq(1) # tarefa concluída e o atraso continua: abre de novo
  end

  it 'resume o pedido em palavras simples para a Val virtual', :aggregate_failures do
    expect(described_class.summary_for(contact)).to include('nenhum pedido')
    o = order(status: 'em_producao', due_on: today + 3)
    o.lab_orders.create!(account: account, order_item: o.items.first, supplier: lab, status: 'enviado', sent_at: Time.zone.now, expected_on: today + 2)
    text = described_class.summary_for(contact)
    expect(text).to include('em produção').and include('lentes no laboratório (HB Lab), previsão de chegada')
    expect(text).to include('prazo prometido ao cliente').and include('valor R$ 500,00')

    Otica::OrderStatus.change!(o, 'pronta')
    expect(described_class.summary_for(contact)).to include('PRONTO para retirar na loja').and include('pronto para retirar desde')
  end
end
