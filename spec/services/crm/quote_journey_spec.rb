require 'rails_helper'

# 🧭 12/11/2026 (LIFE): jornada da venda — quem chegou no período, até onde andou, a conversão de
# cada etapa para a seguinte e a quebra por fonte de tráfego.
# ☀️ 16/11/2026: etapas no fluxo da energia solar (novo contato → sondagem → conta → orçamento → crédito →
# proposta → contrato) e período pela régua normal do sistema.
# 🧭 18/11/2026: depois do orçamento são 6 etapas (investimento possível → forma de pagamento → CPF e crédito →
# proposta de fechamento → contrato fechado → instalação realizada); cartão e à vista passam direto pelo crédito.
RSpec.describe Crm::QuoteJourney do
  let(:now) { Time.zone.local(2026, 11, 12, 12, 0) }
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Fernando') }
  let(:inbox) { create(:inbox, account: account) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Life', position: 0) }
  let!(:stages) do
    ['Novos Contatos', 'Solicitação da Conta', 'Orçamento a fazer', 'Orçamento pronto', 'Orçamento Enviado', 'Sem Interesse',
     'Vistoria Técnica Agendada', 'Negociação', 'Contrato Assinado', 'Instalação',
     'NPS - Indicação - Pós venda'].each_with_index.to_h do |name, i|
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

  def ficha!
    CrmSetting.find_or_create_by!(account: account).update!(ai_config: { 'ficha_cliente' => { 'campos' => [
                                                              { 'chave' => 'conta', 'rotulo' => 'Conta de luz' },
                                                              { 'chave' => 'cidade', 'rotulo' => 'Cidade' },
                                                              { 'chave' => 'forma_pagamento', 'rotulo' => 'Forma de pagamento',
                                                                'etiqueta' => 'quer-fechar' },
                                                              { 'chave' => 'cpf', 'rotulo' => 'CPF do responsável' }
                                                            ] } })
  end

  def journey(days: 30)
    described_class.new(account, since: now - days.days, until_at: now).call
  end

  it 'sem ninguém no período devolve tudo zerado, sem conversão inventada', :aggregate_failures do
    result = journey
    expect(result[:steps].pluck(:count)).to eq([0] * 10)
    expect(result[:steps].pluck(:to_next)).to eq([nil] * 10)
    expect(result[:jumps].pluck(:pct)).to eq([nil, nil])
    expect(result[:sources]).to eq([])
  end

  it 'conta até onde cada pessoa andou no fluxo da energia solar e a conversão de cada etapa', :aggregate_failures do
    ficha!
    enviado = ['Novos Contatos', 'Orçamento Enviado']
    lead('Só chegou')
    card(lead('Em sondagem'), 'Novos Contatos', 'Solicitação da Conta')
    card(lead('Mandou a conta'), 'Novos Contatos', 'Solicitação da Conta', 'Orçamento a fazer')
    card(lead('Recebeu o orçamento'), 'Novos Contatos', 'Solicitação da Conta', 'Orçamento a fazer', 'Orçamento pronto', 'Orçamento Enviado')
    card(lead('Disse que é possível'), *enviado).contact.add_labels(['investimento-possivel'])
    Crm::ClientSummary.write!(card(lead('Vai financiar, falta o CPF'), *enviado).contact, { 'forma_pagamento' => 'financiamento' }, by: 'IA')
    Crm::ClientSummary.write!(card(lead('Vai no cartão'), *enviado).contact, { 'forma_pagamento' => 'cartão de crédito' }, by: 'IA')
    Crm::ClientSummary.write!(card(lead('Financia e mandou o CPF'), *enviado).contact,
                              { 'forma_pagamento' => 'financiamento', 'cpf' => '111.222.333-44' }, by: 'IA')
    card(lead('Recebeu a proposta'), *enviado, 'Negociação')
    card(lead('Fechou'), *enviado, 'Contrato Assinado') # pulou colunas: conta nas anteriores também
    card(lead('Já instalando'), 'Novos Contatos', 'Instalação')
    card(lead('Instalado'), 'Novos Contatos', 'NPS - Indicação - Pós venda')

    result = journey

    expect(result[:steps].pluck(:label)).to eq(['Novos contatos', 'Sondagem', 'Conta para orçamento', 'Orçamento enviado',
                                                'Investimento possível', 'Forma de pagamento', 'CPF e crédito',
                                                'Proposta de fechamento', 'Contrato fechado', 'Instalação realizada'])
    expect(result[:steps].pluck(:count)).to eq([12, 11, 10, 9, 8, 7, 6, 4, 3, 1])
    expect(result[:steps].pluck(:to_next)).to eq([92, 91, 90, 89, 88, 86, 67, 75, 33, nil])
    expect(result[:jumps]).to eq([
                                   { from: 'leads', to: 'enviado', from_label: 'Novos contatos', to_label: 'Orçamento enviado', count: 9, pct: 75 },
                                   { from: 'leads', to: 'fechado', from_label: 'Novos contatos', to_label: 'Contrato fechado', count: 3, pct: 25 }
                                 ])
  end

  it 'quem escolheu a forma de pagamento e foi para a coluna da vistoria conta (era o que o painel não registrava)', :aggregate_failures do
    ficha!
    card(lead('Na coluna da vistoria'), 'Novos Contatos', 'Orçamento Enviado', 'Vistoria Técnica Agendada')
    lead('Etiqueta do fechamento posta à mão').add_labels(['proposta-de-fechamento'])
    lead('Contrato pela etiqueta').add_labels(['contrato-fechado'])
    lead('Instalado pela etiqueta').add_labels(['instalacao-realizada'])

    expect(journey[:steps].pluck(:count)).to eq([4, 4, 4, 4, 4, 4, 3, 3, 2, 1])
  end

  it 'vale também o que não passa pelo funil: resumo do cliente, tarefa do atendente, orçamento do Gerador e etiquetas', :aggregate_failures do
    ficha!
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

    expect(journey[:steps].pluck(:count)).to eq([7, 6, 5, 3, 1, 1, 1, 0, 0, 0])
  end

  it 'quebra por fonte de tráfego pela etiqueta de origem da conversa', :aggregate_failures do
    card(lead('Anúncio 1', origin: 'anuncio'), 'Novos Contatos', 'Orçamento Enviado')
    lead('Anúncio 2', origin: 'anuncio')
    card(lead('Site', origin: 'site'), 'Novos Contatos', 'Solicitação da Conta')
    lead('Antigo sem etiqueta')

    sources = journey[:sources]

    expect(sources.pluck(:label)).to eq(['Anúncio', 'Site', 'Sem origem'])
    expect(sources.first).to include(key: 'anuncio', counts: [2, 1, 1, 1, 0, 0, 0, 0, 0, 0], lead_to_sent: 50, lead_to_closed: 0)
    expect(sources.second).to include(counts: [1, 1, 0, 0, 0, 0, 0, 0, 0, 0], lead_to_sent: 0)
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
