require 'rails_helper'

# 🧹 item 342 (13/10) — "indicador de agendamento descontaminado". A Visão
# geral do Meu Painel separa quem agendou em LEAD NOVO (chegou no período) ×
# BASE, a taxa usa a mesma turma em cima e embaixo, mostra QUANDO chegaram os
# que agendaram (safra), por caixa de entrada, e o volume do período em nove
# números — sem paciente do Oftalmofácil contando como da CEVICO.
RSpec.describe Crm::OverviewService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:capture_inbox) { create(:inbox, account: account, name: 'Caixa Google') }
  let(:partner_inbox) { create(:inbox, account: account, name: 'Oftalmofácil') }
  let!(:cevico) do
    Crm::Pipeline.create!(account: account, name: 'CEVICO', position: 0).tap do |p|
      p.stages.create!(name: 'Novos Contatos', color: '#000', position: 0)
      p.stages.create!(name: 'Agendamento de Consulta', color: '#000', position: 1)
      p.stages.create!(name: 'Cirurgia Realizada', color: '#000', position: 2)
    end
  end
  let!(:partners) do
    Crm::Pipeline.create!(account: account, name: 'OFTALMOFÁCIL', position: 1).tap do |p|
      p.stages.create!(name: 'Consulta Agendada', color: '#000', position: 0)
    end
  end
  let(:now) { ActiveSupport::TimeZone['America/Sao_Paulo'].now }

  # Ana chegou hoje e agendou · Beto chegou há 10 dias e agendou hoje (base) ·
  # Caio chegou hoje e não agendou · Dani é do Oftalmofácil (carimbo) e Eva só
  # conversou pela caixa do parceiro — as duas ganharam card no funil da CEVICO
  let(:ana) { person('Ana') }
  let(:beto) { person('Beto', arrived: 10.days.ago) }
  let(:caio) { person('Caio') }
  let(:dani) { person('Dani') }
  let(:eva) { person('Eva', arrived: 5.days.ago, inbox: partner_inbox) }

  before do
    # meio-dia em São Paulo: "1 hora atrás" e "agora" caem HOJE
    travel_to Time.current.in_time_zone('America/Sao_Paulo').change(hour: 12)
    Rails.cache.clear
    Current.reset
    CrmSetting.create!(account: account, agenda_config: {
                         'oftalmofacil' => { 'provider_name' => 'CATARATA_SP', 'partner_pipeline_id' => partners.id,
                                             'partner_inbox_ids' => [partner_inbox.id] }
                       })
    caio
    Contact.where(id: dani.id).update_all(cevico_source_id: Crm::Sources.partner(account).id) # rubocop:disable Rails/SkipsModelValidations
    Contact.where(id: eva.id).update_all(cevico_source_id: Crm::Sources.own(account).id) # rubocop:disable Rails/SkipsModelValidations
    [ana, beto, dani, eva].each { |c| card!(c, 'Agendamento de Consulta') }
    Rails.cache.clear
  end

  after { Current.reset }

  def person(name, arrived: now, inbox: capture_inbox)
    create(:contact, account: account, name: name, created_at: arrived).tap do |c|
      create(:conversation, account: account, inbox: inbox, contact: c, created_at: arrived) if inbox
    end
  end

  # sem validação: a trava de ambiente do CRM barraria o card do paciente do
  # parceiro no funil da CEVICO — é justamente o passado contaminado que a
  # lente precisa limpar
  def card!(contact, stage_name)
    Crm::Contact.new(contact: contact, pipeline: cevico, stage: cevico.stages.find_by(name: stage_name)).tap { |c| c.save!(validate: false) }
  end

  def task(attrs = {})
    Task.create!({ account: account, creator: user, title: 'Consulta: Paciente', task_type: 'consulta', due_at: 2.days.from_now }.merge(attrs))
  end

  def overview
    described_class.new(account: account, since: now.beginning_of_day, until_at: now, admin: false).call
  end

  it 'separa quem agendou em lead novo × base e a taxa usa a mesma turma', :aggregate_failures do
    entrada = overview[:entrada]

    expect(entrada[:novos][:valor]).to eq(2)
    expect(entrada[:agendaram_novos][:valor]).to eq(1)
    expect(entrada[:agendaram_base][:valor]).to eq(1)
    expect(entrada[:agendaram_total][:valor]).to eq(2)
    expect(entrada[:taxa_agendamento]).to eq(50.0)
    expect(entrada[:pessoas][:agendaram].pluck(:nome)).to eq(['Ana'])
    expect(entrada[:pessoas][:agendaram_base].pluck(:nome, :dias)).to eq([['Beto', 10]])
  end

  it 'mostra quando chegaram os que agendaram (safra) e, por caixa, quem chegou e agendou', :aggregate_failures do
    entrada = overview[:entrada]
    faixas = entrada[:safra][:faixas].to_h { |f| [f[:key], f[:count]] }

    expect(faixas).to eq('periodo' => 1, 'periodo_fora' => 0, 'd1_7' => 0, 'd8_30' => 1, 'd31_90' => 0, 'd90' => 0)
    expect(entrada[:safra][:outros]).to include(count: 1, media_dias: 10.0)
    expect(entrada[:safra][:semanas].size).to eq(1)
    expect(entrada[:por_caixa][:linhas]).to eq([{ label: 'Caixa Google', chegaram: 2, agendaram: 1, pct: 50.0, media_dias: 0.0 }])
  end

  it 'a série conta pessoas e soma o mesmo que o número de cima' do
    series = overview[:series]
    expect([series[:agendaram_novos].sum, series[:agendaram_base].sum, series[:agendaram].sum]).to eq([1, 1, 2])
  end

  it 'na lente da casa, paciente do outro ambiente sai (carimbo do parceiro ou só caixa de parceiro)', :aggregate_failures do
    lens = Crm::SourceLens.for(account, 'cevico')
    expect(lens.partner_contact_ids).to contain_exactly(dani.id, eva.id)
    expect(lens.cards(Crm::Contact.all).map(&:contact_id)).to contain_exactly(ana.id, beto.id)
    expect(Crm::BookingRate.count(account, now.beginning_of_day, now, lens: lens)).to eq(2)
    ours = task(contact: ana)
    task(contact: dani)
    task(contact: eva)
    expect(lens.tasks(account.tasks)).to contain_exactly(ours)
    # tudo junto continua enxergando todo mundo
    expect(Crm::SourceLens.for(account, 'all').cards(Crm::Contact.all).count).to eq(4)
  end

  it 'volume do período: cada acontecimento um número, com fórmula e quebras', :aggregate_failures do
    seen = task(contact: ana, due_at: 1.hour.ago, attendance: 'attended', surgery_indication: 'indicated',
                confirmed_at: Time.current, unit: 'paulista', doctor: 'Dr. Corder')
    task(contact: beto, due_at: 2.hours.ago, attendance: 'missed')
    task(contact: caio, canceled_at: Time.current, cancel_reason: 'viagem')
    task(contact: dani, due_at: 1.hour.ago, attendance: 'attended') # Oftalmofácil: fica fora
    task(contact: ana, task_type: 'cirurgia', title: 'Cirurgia: Ana', due_at: 10.days.from_now)
    moved = task(contact: caio)
    moved.update_columns(rescheduled_count: 1, comments: [{ 'kind' => 'rescheduled', 'at' => Time.current.iso8601 }]) # rubocop:disable Rails/SkipsModelValidations
    card!(person('Fabio', arrived: 200.days.ago), 'Cirurgia Realizada')

    vol = overview[:volumes].index_by { |v| v[:key] }
    expect(vol.transform_values { |v| v[:valor] }).to eq(
      'agendamentos' => 2, 'reagendamentos' => 1, 'cancelamentos' => 1, 'confirmacoes' => 1, 'comparecimentos' => 1,
      'faltas' => 1, 'indicacoes' => 1, 'fechamentos' => 1, 'cirurgias_realizadas' => 1
    )
    expect(vol['agendamentos']).to include(novos: 1, base: 1, medida: 'pessoas')
    expect(vol.values.pluck(:formula)).to all(be_present)
    expect(vol['comparecimentos'][:quebras].find { |q| q[:titulo] == 'Unidade' }[:rows]).to eq([{ label: 'Av. Paulista', count: 1 }])
    expect(vol['cancelamentos'][:quebras].find { |q| q[:titulo] == 'Motivo' }[:rows]).to eq([{ label: 'viagem', count: 1 }])
    expect(vol['comparecimentos'][:pessoas].pluck(:id)).to eq([seen.contact_id])
    expect(vol['cirurgias_realizadas'][:quebras].first[:rows]).to eq([{ label: 'CEVICO', count: 1 }])
  end
end
