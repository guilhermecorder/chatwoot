require 'rails_helper'

# 🧭 item 394 (11/11) — JORNADA DO PACIENTE com linha e base de comparação em
# cada etapa. As réguas são as mesmas do "Volume do período" da Visão geral:
# o número de cada etapa tem de bater com o de lá.
RSpec.describe Crm::JourneyService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account, name: 'Caixa Google') }
  let!(:pipeline) do
    Crm::Pipeline.create!(account: account, name: 'CEVICO', position: 0).tap do |p|
      ['Novos Contatos', 'Envio de Orçamento', 'Agendamento de Consulta', 'Cirurgia Realizada'].each_with_index do |name, i|
        p.stages.create!(name: name, color: '#000', position: i)
      end
    end
  end
  let(:now) { ActiveSupport::TimeZone['America/Sao_Paulo'].now }
  let(:since) { (now - 6.days).beginning_of_day }
  let(:until_at) { now.end_of_day }

  before do
    travel_to Time.current.in_time_zone('America/Sao_Paulo').change(hour: 12)
    Rails.cache.clear
    Current.reset
    CrmSetting.create!(account: account, agenda_config: {})

    # ESTA semana: Ana chegou hoje, recebeu orçamento, agendou, confirmou e veio com
    # indicação; Bia chegou há 2 dias e só agendou. SEMANA PASSADA: Caio chegou e agendou.
    ana = person('Ana', now)
    bia = person('Bia', now - 2.days)
    caio = person('Caio', now - 8.days)
    enter(ana, 'Envio de Orçamento', now)
    enter(ana, 'Agendamento de Consulta', now)
    enter(bia, 'Agendamento de Consulta', now - 2.days)
    enter(caio, 'Agendamento de Consulta', now - 8.days)
    task(contact: ana, due_at: now - 1.hour, confirmed_at: now - 3.hours, attendance: 'attended', surgery_indication: 'indicated')
    task(contact: bia, due_at: now - 1.day, attendance: 'missed')
    task(contact: caio, due_at: now - 8.days, attendance: 'attended')
    task(contact: ana, task_type: 'cirurgia', title: 'Cirurgia: Ana', due_at: now + 5.days)
    task(contact: caio, due_at: now - 1.day, modality: 'pos_op')
    Rails.cache.clear
  end

  after { Current.reset }

  def person(name, arrived)
    create(:contact, account: account, name: name, created_at: arrived).tap do |c|
      create(:conversation, account: account, inbox: inbox, contact: c, created_at: arrived)
    end
  end

  def enter(contact, stage_name, moment)
    stage = pipeline.stages.find_by(name: stage_name)
    card = Crm::Contact.find_by(contact: contact, pipeline: pipeline) ||
           Crm::Contact.new(contact: contact, pipeline: pipeline, stage: stage).tap { |c| c.save!(validate: false) }
    Crm::StageLog.where(crm_contact_id: card.id, stage_id: stage.id).delete_all
    Crm::StageLog.create!(crm_contact_id: card.id, stage_id: stage.id, stage_name: stage.name, event_type: 'entered', entered_at: moment)
  end

  def task(attrs = {})
    Task.create!({ account: account, creator: user, title: 'Consulta: Paciente', task_type: 'consulta' }.merge(attrs))
  end

  def journey(compare: nil)
    described_class.new(account: account, since: since, until_at: until_at, compare: compare).call
  end

  def step(payload, key)
    payload[:etapas].find { |e| e[:key] == key }
  end

  it 'conta cada etapa da jornada no período e na base de comparação', :aggregate_failures do
    payload = journey
    valores = payload[:etapas].to_h { |e| [e[:key], [e[:valor], e[:anterior]]] }

    expect(payload[:etapas].pluck(:key)).to eq(%w[chegaram conversaram orcamento agendaram confirmaram compareceram indicacoes fecharam
                                                  operaram pos_op])
    expect(valores).to include('chegaram' => [2, 1], 'conversaram' => [2, 1], 'orcamento' => [1, 0], 'agendaram' => [2, 1],
                               'confirmaram' => [1, 0], 'compareceram' => [1, 1], 'indicacoes' => [1, 0], 'fecharam' => [1, 0],
                               'operaram' => [0, 0], 'pos_op' => [1, 0])
    expect(payload[:comparacao]).to include(modo: 'previous')
  end

  it 'a linha de agora e a de antes têm o mesmo tamanho e somam o número de cima', :aggregate_failures do
    payload = journey
    agendaram = step(payload, 'agendaram')

    expect(payload[:balde]).to eq('dia')
    expect(payload[:rotulos].size).to eq(7)
    expect(payload[:rotulos_anterior].size).to eq(7)
    expect(agendaram[:serie].size).to eq(7)
    expect(agendaram[:serie_anterior].size).to eq(7)
    expect(agendaram[:serie].sum).to eq(agendaram[:valor])
    expect(agendaram[:serie].last).to eq(1) # Ana, hoje
    expect(agendaram[:serie_anterior].compact.sum).to eq(agendaram[:anterior])
  end

  it 'bate com o "Volume do período" da Visão geral nas mesmas etapas' do
    volumes = Crm::OverviewService.new(account: account, since: since, until_at: until_at, admin: false).call[:volumes]
                                  .to_h { |v| [v[:key], v[:valor]] }
    payload = journey
    pares = { 'agendaram' => 'agendamentos', 'confirmaram' => 'confirmacoes', 'compareceram' => 'comparecimentos',
              'indicacoes' => 'indicacoes', 'fecharam' => 'fechamentos', 'operaram' => 'cirurgias_realizadas' }

    expect(pares.keys.index_with { |mine| step(payload, mine)[:valor] })
      .to eq(pares.transform_values { |theirs| volumes[theirs] })
  end

  it 'usa a base de comparação escolhida (mesmo trecho um mês antes)', :aggregate_failures do
    compare = Crm::PeriodComparison.new(since, until_at, mode: 'month')
    payload = journey(compare: compare)

    expect(payload[:comparacao][:modo]).to eq('month')
    expect(step(payload, 'chegaram')[:anterior]).to eq(0)
    expect(step(payload, 'chegaram')[:serie_anterior].size).to eq(7)
  end

  it 'período longo vira balde por mês' do
    payload = described_class.new(account: account, since: (now - 200.days).beginning_of_day, until_at: until_at).call

    expect([payload[:balde], step(payload, 'chegaram')[:valor], payload[:rotulos].last]).to eq(['mes', 3, now.strftime('%m/%y')])
  end
end
