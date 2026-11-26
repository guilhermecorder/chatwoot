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

  def journey(compare: nil, days: nil)
    described_class.new(account: account, since: since, until_at: until_at, compare: compare, days: days).call
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

  # 🧾 item 413: "quanto por cento de envio de orçamento resultou em agendamento?"
  it 'diz quantos dos que receberam orçamento agendaram depois (conta de turma)', :aggregate_failures do
    dani = person('Dani', now - 1.day)
    enter(dani, 'Envio de Orçamento', now - 1.day) # recebeu orçamento e não agendou
    edu = person('Edu', now - 3.days)
    enter(edu, 'Agendamento de Consulta', now - 3.days) # agendou ANTES do orçamento: não é conversão dele
    enter(edu, 'Envio de Orçamento', now - 2.days)

    payload = journey

    expect(payload[:orcamento_consulta][:agora]).to eq(orcamentos: 3, agendaram: 1, taxa: 33.3)
    expect(payload[:orcamento_consulta][:antes]).to eq(orcamentos: 0, agendaram: 0, taxa: nil)
    expect(step(payload, 'orcamento')[:base]).to be_nil # sem "% de Chegaram" (dava mais de 100%)
  end

  # 🧹 item 413: o teste do Luna abriu ~400 conversas e o "Conversaram" foi a 469
  it 'não conta as conversas de teste do 🧪 Simulador', :aggregate_failures do
    simulator = create(:inbox, account: account, name: Crm::AgentSimulator::INBOX_NAME)
    patient = create(:contact, account: account, name: 'Paciente de teste', created_at: now - 40.days)
    create_list(:conversation, 3, account: account, inbox: simulator, contact: patient, created_at: now)

    expect(step(journey, 'conversaram')[:valor]).to eq(2)
    expect(Crm::KpiBagService.new(account: account, since: since, until_at: until_at).send(:conversations, since, until_at).count).to eq(2)
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

  # 📈 item 421 (26/11): "o Hoje aponta só um pontinho… um histórico de pelo menos 7 dias, já carregado junto"
  describe 'período curto traz os dias anteriores como contexto' do
    it 'Hoje vem com os 6 dias de antes na mesma linha; o número grande continua só de hoje', :aggregate_failures do
      payload = described_class.new(account: account, since: now.beginning_of_day, until_at: now.end_of_day).call
      chegaram = step(payload, 'chegaram')

      expect(payload[:rotulos]).to eq([now.strftime('%d/%m')])
      expect(payload[:contexto]).to include(dias: 6, rotulos: (1..6).map { |d| (now - d.days).strftime('%d/%m') }.reverse)
      expect(payload[:contexto][:fins_de_semana].size).to eq(6)
      expect([chegaram[:valor], chegaram[:serie]]).to eq([1, [1]]) # só a Ana, que chegou hoje
      expect(chegaram[:contexto]).to eq([0, 0, 0, 0, 1, 0]) # a Bia, há 2 dias
      expect(step(payload, 'compareceram')[:contexto].sum).to eq(0) # a do Caio foi há 8 dias: fora do contexto
      expect(payload[:parcial]).to be(true) # hoje ainda não acabou
    end

    it 'Hoje + ontem completa com 5 dias; período de 7 dias ou mais não ganha contexto', :aggregate_failures do
      dois = described_class.new(account: account, since: (now - 1.day).beginning_of_day, until_at: now.end_of_day).call
      expect([dois[:rotulos].size, dois[:contexto][:dias], step(dois, 'chegaram')[:contexto]]).to eq([2, 5, [0, 0, 0, 0, 1]])

      semana = journey
      expect(semana[:contexto]).to be_nil
      expect(step(semana, 'chegaram')).not_to have_key(:contexto)
      expect(semana[:fins_de_semana].count(true)).to eq(2)

      ontem = described_class.new(account: account, since: (now - 1.day).beginning_of_day, until_at: (now - 1.day).end_of_day).call
      expect(ontem[:parcial]).to be(false)
    end
  end

  # 📅 item 421: "uma pré-seleção especial, tipo dias de semana e finais de semana, para poder comparar"
  describe 'quais dias entram na conta' do
    it 'dias úteis + fim de semana somam o período inteiro, e a linha só tem os dias que entram', :aggregate_failures do
      todos = journey
      uteis = journey(days: 'weekdays')
      fds = journey(days: 'weekends')

      %w[chegaram conversaram agendaram compareceram].each do |key|
        expect(step(uteis, key)[:valor] + step(fds, key)[:valor]).to eq(step(todos, key)[:valor]), "#{key} não fecha"
        expect(step(uteis, key)[:serie].sum).to eq(step(uteis, key)[:valor])
      end
      expect([uteis[:rotulos].size, fds[:rotulos].size]).to eq([5, 2])
      expect([uteis[:fins_de_semana].uniq, fds[:fins_de_semana].uniq]).to eq([[false], [true]])
      expect([uteis[:dias], fds[:dias], todos[:dias]]).to eq(%w[weekdays weekends all])
    end

    it 'úteis × fim de semana compara a MÉDIA POR DIA dentro do mesmo período', :aggregate_failures do
      todos = journey
      versus = journey(days: 'versus')
      chegaram = step(versus, 'chegaram')

      expect(versus[:comparacao]).to include(modo: 'versus', rotulo: 'fim de semana', dias_uteis: 5, dias_fds: 2)
      expect(chegaram[:total]).to eq(step(todos, 'chegaram')[:valor])
      expect(chegaram[:total_uteis] + chegaram[:total_fds]).to eq(chegaram[:total])
      expect(chegaram[:valor]).to eq((chegaram[:total_uteis] / 5.0).round(1))
      expect(chegaram[:anterior]).to eq((chegaram[:total_fds] / 2.0).round(1))
      expect(chegaram[:serie]).to eq(step(todos, 'chegaram')[:serie]) # a linha é o período inteiro, dia a dia
      expect(chegaram[:serie_anterior].compact).to be_empty
      expect(versus[:contexto]).to be_nil
      expect(versus[:orcamento_consulta][:antes]).to be_nil
    end

    it 'valor desconhecido cai em todos os dias' do
      expect(journey(days: 'feriados')[:dias]).to eq('all')
    end
  end

  it 'período longo vira balde por mês' do
    payload = described_class.new(account: account, since: (now - 200.days).beginning_of_day, until_at: until_at).call

    expect([payload[:balde], step(payload, 'chegaram')[:valor], payload[:rotulos].last]).to eq(['mes', 3, now.strftime('%m/%y')])
  end
end
