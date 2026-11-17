require 'rails_helper'

# 🧭 12/11/2026 (LIFE): jornada da venda — quem chegou no período, até onde andou, a conversão de
# cada etapa para a seguinte e a quebra por fonte de tráfego.
# ☀️ 16/11/2026: etapas no fluxo da energia solar (novo contato → sondagem → conta → orçamento → crédito →
# proposta → contrato) e período pela régua normal do sistema.
RSpec.describe Crm::QuoteJourney do
  let(:now) { Time.zone.local(2026, 11, 12, 12, 0) }
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Fernando') }
  let(:inbox) { create(:inbox, account: account) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Life', position: 0) }
  let!(:stages) do
    ['Novos Contatos', 'Solicitação da Conta', 'Orçamento a fazer', 'Orçamento pronto', 'Orçamento Enviado', 'Sem Interesse',
     'Negociação', 'Contrato Assinado', 'Instalação'].each_with_index.to_h do |name, i|
      [name,
       Crm::Stage.create!(pipeline: pipeline, name: name,
                          position: i)]
    end
  end

  before { travel_to now }

  # um lead que chegou há `days_ago` dias, com a etiqueta de origem na conversa
  def lead(name, days_ago: 3, origin: nil)
    contact = create(:contact, account: account, name: name, created_at: now - days_ago.days)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, created_at: now - days_ago.days)
    conversation.add_labels(["origem-#{origin}"]) if origin
    contact
  end

  def card(contact, *stage_names)
    record = Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stages[stage_names.first])
    stage_names.drop(1).each { |name| record.update!(stage: stages[name]) }
    record
  end

  def journey(days: 30)
    described_class.new(account, since: now - days.days, until_at: now).call
  end

  it 'sem ninguém no período devolve tudo zerado, sem conversão inventada', :aggregate_failures do
    result = journey
    expect(result[:steps].pluck(:count)).to eq([0, 0, 0, 0, 0, 0, 0])
    expect(result[:steps].pluck(:to_next)).to eq([nil, nil, nil, nil, nil, nil, nil])
    expect(result[:jumps].pluck(:pct)).to eq([nil, nil])
    expect(result[:sources]).to eq([])
  end

  it 'conta até onde cada pessoa andou no fluxo da energia solar e a conversão de cada etapa', :aggregate_failures do
    lead('Só chegou')
    card(lead('Em sondagem'), 'Novos Contatos', 'Solicitação da Conta')
    card(lead('Mandou a conta'), 'Novos Contatos', 'Solicitação da Conta', 'Orçamento a fazer')
    card(lead('Recebeu o orçamento'), 'Novos Contatos', 'Solicitação da Conta', 'Orçamento a fazer', 'Orçamento pronto', 'Orçamento Enviado')
    card(lead('Crédito aprovado'), 'Novos Contatos', 'Orçamento Enviado').contact.add_labels(['credito-pre-aprovado'])
    card(lead('Recebeu a proposta'), 'Novos Contatos', 'Orçamento Enviado', 'Negociação')
    card(lead('Fechou'), 'Novos Contatos', 'Orçamento Enviado', 'Contrato Assinado') # pulou colunas: conta nas anteriores também
    card(lead('Já instalando'), 'Novos Contatos', 'Instalação')

    result = journey

    expect(result[:steps].pluck(:label)).to eq(['Novos contatos', 'Sondagem', 'Conta para orçamento', 'Orçamento enviado',
                                                'Crédito pré-aprovado', 'Proposta de fechamento', 'Contrato fechado'])
    expect(result[:steps].pluck(:count)).to eq([8, 7, 6, 5, 4, 3, 2])
    expect(result[:steps].pluck(:to_next)).to eq([88, 86, 83, 80, 75, 67, nil])
    expect(result[:jumps]).to eq([
                                   { from: 'leads', to: 'enviado', from_label: 'Novos contatos', to_label: 'Orçamento enviado', count: 5, pct: 63 },
                                   { from: 'leads', to: 'fechado', from_label: 'Novos contatos', to_label: 'Contrato fechado', count: 2, pct: 25 }
                                 ])
  end

  it 'vale também o que não passa pelo funil: resumo do cliente, tarefa do atendente, orçamento do Gerador e etiquetas', :aggregate_failures do
    CrmSetting.find_or_create_by!(account: account).update!(ai_config: { 'ficha_cliente' => { 'campos' => [
                                                              { 'chave' => 'conta', 'rotulo' => 'Conta de luz' },
                                                              { 'chave' => 'cidade', 'rotulo' => 'Cidade' }
                                                            ] } })
    Crm::ClientSummary.write!(lead('Só contou a cidade'), { 'cidade' => 'Piracicaba' }, by: 'Fernando')
    Crm::ClientSummary.write!(lead('Conta anotada no resumo'), { 'conta' => 'R$ 300' }, by: 'Fernando')
    com_tarefa = lead('Tarefa do atendente')
    account.tasks.create!(title: '🙋 Atendimento · Tarefa do atendente — Orçamento: conta recebida', creator: admin, assignee: admin,
                          contact: com_tarefa)
    Crm::Quote.create!(account: account, contact: lead('Orçamento gerado, ainda não enviado'), price: 20_000)
    Crm::Quote.create!(account: account, contact: lead('Orçamento enviado pelo Gerador'), price: 30_000, sent_at: now - 1.hour)
    lead('Etiqueta posta à mão').add_labels(['orcamento-enviado'])
    aprovado = lead('Crédito aprovado, etiqueta na conversa')
    account.conversations.find_by(contact: aprovado).add_labels(['credito-pre-aprovado'])

    expect(journey[:steps].pluck(:count)).to eq([7, 6, 5, 3, 1, 0, 0])
  end

  it 'quebra por fonte de tráfego pela etiqueta de origem da conversa', :aggregate_failures do
    card(lead('Anúncio 1', origin: 'anuncio'), 'Novos Contatos', 'Orçamento Enviado')
    lead('Anúncio 2', origin: 'anuncio')
    card(lead('Site', origin: 'site'), 'Novos Contatos', 'Solicitação da Conta')
    lead('Antigo sem etiqueta')

    sources = journey[:sources]

    expect(sources.pluck(:label)).to eq(['Anúncio', 'Site', 'Sem origem'])
    expect(sources.first).to include(key: 'anuncio', counts: [2, 1, 1, 1, 0, 0, 0], lead_to_sent: 50, lead_to_closed: 0)
    expect(sources.second).to include(counts: [1, 1, 0, 0, 0, 0, 0], lead_to_sent: 0)
    expect(sources.sum { |s| s[:counts].first }).to eq(4)
  end

  it 'só entra quem chegou no período escolhido', :aggregate_failures do
    lead('Há 3 dias', days_ago: 3)
    lead('Há 20 dias', days_ago: 20)
    lead('Há 60 dias', days_ago: 60)

    expect(journey(days: 7)[:steps].first[:count]).to eq(1)
    expect(journey(days: 30)[:steps].first[:count]).to eq(2)
    expect(journey(days: 90)[:steps].first[:count]).to eq(3)
    expect(described_class.new(account, since: now - 30.days, until_at: now - 10.days).call[:steps].first[:count]).to eq(1)
  end
end
