require 'rails_helper'

# 👓 22/11/2026: a jornada da ótica no Meu Painel — a mesma régua da LIFE (quem chegou no período e até onde
# andou), no caminho da ótica: foto → prova virtual → agendou → confirmou → veio → comprou → pronto → retirou.
RSpec.describe Otica::Journey do
  let(:now) { Time.zone.local(2026, 11, 22, 12, 0) }
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Val') }
  let(:inbox) { create(:inbox, account: account) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Aquisição', position: 0) }
  let(:pos_venda) { Crm::Pipeline.create!(account: account, name: 'Pós-venda e relacionamento', position: 1) }
  let!(:stages) do
    names = ['Novos contatos', 'Orçamento prévio enviado', 'Agendamento da visita', 'Visita confirmada',
             'Desmarcou ou não veio', 'Visita realizada', 'Pedido fechado (1ª compra)']
    out = names.each_with_index.to_h { |name, i| [name, Crm::Stage.create!(pipeline: pipeline, name: name, position: i)] }
    ['Pedido em produção', 'Pronto para retirar', 'Retirou o óculos'].each_with_index do |name, i|
      out[name] = Crm::Stage.create!(pipeline: pos_venda, name: name, position: i)
    end
    out
  end

  before { travel_to now }

  def lead(name, days_ago: 2, origin: nil)
    contact = create(:contact, account: account, name: name, created_at: now - days_ago.days)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, created_at: now - days_ago.days)
    conversation.add_labels(["origem-#{origin}"]) if origin
    [contact, conversation]
  end

  def selfie!(conversation)
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                               sender: conversation.contact, content: nil)
    message.attachments.create!(account_id: account.id, file_type: :image, external_url: 'https://example.com/selfie.jpg',
                                meta: { 'cevico_media' => { 'status' => 'done', 'tipo' => 'selfie' } })
  end

  def try_on!(conversation)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: admin,
                     content: 'Qual você já se imagina usando: o 1 ou o 2?',
                     additional_attributes: { Otica::VirtualTryOn::STAMP_KEY => { 'lote' => 'abc', 'product_ids' => [1, 2] } })
  end

  def booking!(contact, **attrs)
    account.tasks.create!({ creator: admin, title: "Visita — #{contact.name}", task_type: 'consulta', contact_id: contact.id,
                            due_at: now + 1.day }.merge(attrs))
  end

  def order!(contact, status:, net:, number:)
    Otica::Order.create!(account: account, contact: contact, number: number, status: status, sold_on: now.to_date,
                         net: net, gross: net)
  end

  def report
    described_class.new(account, since: now - 7.days, until_at: now).call
  end

  def counts(result)
    result[:steps].to_h { |s| [s[:key], s[:count]] }
  end

  it 'conta até onde cada pessoa andou, da foto à retirada, e quem parou em cada etapa', :aggregate_failures do
    _, so_chegou = lead('Só chegou')
    _, foto = lead('Mandou foto')
    selfie!(foto)
    _, prova = lead('Recebeu prova', origin: 'anuncio')
    selfie!(prova)
    try_on!(prova)
    agendou, = lead('Agendou', origin: 'anuncio')
    booking!(agendou)
    veio, = lead('Veio e comprou', origin: 'anuncio')
    booking!(veio, confirmed_at: now - 1.day, attendance: 'attended')
    order!(veio, status: 'entregue', net: 900, number: 1)
    pronto, = lead('Óculos pronto')
    Crm::Contact.create!(contact: pronto, pipeline: pos_venda, stage: stages['Pronto para retirar'])
    lead('Antigo', days_ago: 30)

    result = report
    # quem foi mais longe conta também nas etapas de antes (o "Óculos pronto" e o "Veio" mandaram foto, sim)
    expect(counts(result)).to eq('leads' => 6, 'foto' => 5, 'prova' => 4, 'agendou' => 3, 'confirmou' => 2, 'veio' => 2,
                                 'comprou' => 2, 'pronto' => 2, 'retirou' => 1)
    stopped = result[:steps].to_h { |s| [s[:key], s[:people].pluck(:name)] }
    expect(stopped['leads']).to eq(['Só chegou'])
    expect(stopped['agendou']).to eq(['Agendou'])
    expect(stopped['retirou']).to eq(['Veio e comprou'])
    expect(result[:steps].find { |s| s[:key] == 'leads' }[:people].first[:conversation_id]).to eq(so_chegou.id)
    expect(result[:jumps].map { |j| [j[:to], j[:pct]] }).to eq([['agendou', 50], ['comprou', 33]])
    expect(result[:money]).to eq(sales: 1, revenue: 900.0, ticket: 900.0)
    anuncio = result[:sources].find { |s| s[:key] == 'anuncio' }
    expect(anuncio).to include(counts: [3, 3, 3, 2, 1, 1, 1, 1, 1], lead_to_booked: 67, revenue: 900.0)
  end

  it 'mostra quem desmarcou ou faltou e o exame pago no PIX só quando a conta tem essas colunas', :aggregate_failures do
    faltou, = lead('Faltou')
    booking!(faltou, attendance: 'missed', modality: 'exame')
    expect(report[:extras]).to eq(missed: 1, exams: 1)

    pix = Crm::Stage.create!(pipeline: pipeline, name: 'PIX do exame enviado', position: 8)
    pago_stage = Crm::Stage.create!(pipeline: pipeline, name: 'Exame pago (PIX)', position: 9)
    pediu, = lead('Pediu PIX')
    Crm::Contact.create!(contact: pediu, pipeline: pipeline, stage: pix)
    pagou, pagou_conv = lead('Pagou')
    pagou_conv.add_labels(['exame-pago'])
    pagou_card = Crm::Contact.create!(contact: pagou, pipeline: pipeline, stage: pix)
    pagou_card.update!(stage: pago_stage)
    expect(report[:extras]).to include(pix_asked: 2, pix_paid: 1)
  end
end
