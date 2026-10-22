require 'rails_helper'

# 📈 19/10/2026: custo por fonte ao longo do tempo (gasto ÷ lead/agendamento/
# cirurgia fechada, por balde) + faturamento × etapas do CRM
RSpec.describe Crm::AcquisitionTimelineService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Jornada', position: 1) }
  let(:booking) { Crm::Stage.create!(pipeline: pipeline, name: 'Agendamento de Consulta', position: 2, color: '#8B5CF6') }
  let(:closed) { Crm::Stage.create!(pipeline: pipeline, name: 'Cirurgia Agendada', position: 5, color: '#0EA5E9') }
  let(:done) { Crm::Stage.create!(pipeline: pipeline, name: 'Cirurgia Realizada', position: 6, color: '#10B981') }
  let(:inbox) { create(:inbox, account: account, name: 'Google Principal') }
  let(:since) { tz.parse('2026-09-01 00:00') }
  let(:until_at) { tz.parse('2026-09-30 23:59') }
  let(:result) { described_class.new(account: account, since: since, until_at: until_at).call }

  before do
    travel_to tz.parse('2026-10-03 10:00')
    Rails.cache.clear
    booking
    closed
    done

    # gasto: Google por campanha e dia (GA4), Meta por anúncio e dia (espelho)
    Crm::CampaignDay.create!(account: account, channel: 'google', campaign_id: '1', date: Date.new(2026, 9, 3), spend: 300)
    Crm::CampaignDay.create!(account: account, channel: 'google', campaign_id: '1', date: Date.new(2026, 9, 10), spend: 200)
    Crm::AdInsight.create!(account: account, ad_id: 'ad1', date: Date.new(2026, 9, 3), metrics: { 'spend' => 100 })

    # lead do Google em 03/09 (página) que agendou em 10/09 e fechou em 20/09
    google = create(:contact, account: account, name: 'Bruno Google', created_at: tz.parse('2026-09-03 09:00'),
                              additional_attributes: { 'page_ads' => { 'source' => 'google_ads', 'captured_at' => '2026-09-03T12:00:00Z' } })
    create(:conversation, account: account, inbox: inbox, contact: google, created_at: tz.parse('2026-09-03 09:01'))
    card = Crm::Contact.create!(contact: google, pipeline: pipeline, stage: closed, value: 9000)
    Crm::StageLog.create!(crm_contact: card, stage_id: booking.id, stage_name: booking.name, entered_at: tz.parse('2026-09-10 09:00'))
    Crm::StageLog.create!(crm_contact: card, stage_id: closed.id, stage_name: closed.name, entered_at: tz.parse('2026-09-20 09:00'))
    # remarcou: entrada repetida na coluna não vira agendamento novo
    Crm::StageLog.create!(crm_contact: card, stage_id: booking.id, stage_name: booking.name, entered_at: tz.parse('2026-09-25 09:00'))

    # lead da Meta em 03/09 (clique no anúncio) sem agendamento ainda
    meta = create(:contact, account: account, name: 'Ana Meta', created_at: tz.parse('2026-09-03 15:00'),
                            additional_attributes: { 'meta_ads' => { 'source_id' => 'ad1', 'captured_at' => '2026-09-03T18:00:00Z' } })
    create(:conversation, account: account, inbox: inbox, contact: meta, created_at: tz.parse('2026-09-03 15:01'))

    # orgânico: agendou pela Agenda em 10/09 (já era paciente de agosto)
    organic = create(:contact, account: account, name: 'Carla Indicação', created_at: tz.parse('2026-08-10 09:00'))
    account.tasks.create!(title: 'Consulta', task_type: 'consulta', contact: organic, due_at: tz.parse('2026-09-12 08:00'),
                          creator: user, created_at: tz.parse('2026-09-10 11:00'))

    # faturamento: cirurgia realizada em 20/09 (valor do card) — paciente antigo
    old = create(:contact, account: account, name: 'Dora Operada', created_at: tz.parse('2026-07-01 09:00'))
    old_card = Crm::Contact.create!(contact: old, pipeline: pipeline, stage: done, value: 6000)
    Crm::StageLog.create!(crm_contact: old_card, stage_id: done.id, stage_name: done.name, entered_at: tz.parse('2026-09-20 10:00'))
  end

  it 'agrupa por dia e separa gasto e contagens por fonte', :aggregate_failures do
    expect(result[:period]).to include(unit: 'day', days: 30)
    expect(result[:buckets].size).to eq(30)
    day3 = result[:buckets].index('2026-09-03')
    day10 = result[:buckets].index('2026-09-10')
    day20 = result[:buckets].index('2026-09-20')

    google = result[:sources]['google']
    expect(google['spend'][day3]).to eq(300.0)
    expect(google['spend'][day10]).to eq(200.0)
    expect(google['leads'][day3]).to eq(1)
    expect(google['booked'][day10]).to eq(1)
    expect(google['booked'].sum).to eq(1) # a remarcação de 25/09 não conta
    expect(google['closed'][day20]).to eq(1)

    expect(result[:sources]['meta']['spend'][day3]).to eq(100.0)
    expect(result[:sources]['meta']['leads'][day3]).to eq(1)
    expect(result[:sources]['organico']['spend']).to be_nil
    expect(result[:sources]['organico']['booked'][day10]).to eq(1)
    expect(result[:sources]['all']['spend'][day3]).to eq(400.0)
    expect(result[:sources]['all']['leads'].sum).to eq(2)
    # Bruno (coluna) + Carla (Agenda) + Dora: quem chegou em "Cirurgia Realizada" passou pelo agendamento
    expect(result[:sources]['all']['booked'].sum).to eq(3)
    expect(result[:sources]['organico']['booked'][day20]).to eq(1)
  end

  it 'traz o faturamento, as novas conversas e as entradas por coluna do funil', :aggregate_failures do
    day3 = result[:buckets].index('2026-09-03')
    day20 = result[:buckets].index('2026-09-20')
    expect(result[:revenue][day20]).to eq(6000.0)
    expect(result[:revenue].sum).to eq(6000.0)
    expect(result[:conversations][day3]).to eq(2)

    funnel = result[:pipelines].first
    expect(funnel[:name]).to eq('Jornada')
    stages = funnel[:stages].index_by { |s| s[:name] }
    expect(stages['Agendamento de Consulta'][:values].sum).to eq(2) # entrada + remarcação
    expect(stages['Cirurgia Agendada'][:values][day20]).to eq(1)
    expect(stages['Cirurgia Realizada'][:color]).to eq('#10B981')
  end

  it 'agrupa por semana até 4 meses e por mês acima disso', :aggregate_failures do
    weekly = described_class.new(account: account, since: tz.parse('2026-07-10 00:00'), until_at: until_at).call
    expect(weekly[:period][:unit]).to eq('week')
    expect(weekly[:buckets].first).to eq('2026-07-06') # segunda-feira da semana do 10/07
    expect(weekly[:revenue].sum).to eq(6000.0)

    monthly = described_class.new(account: account, since: tz.parse('2026-01-01 00:00'), until_at: until_at).call
    expect(monthly[:period][:unit]).to eq('month')
    expect(monthly[:buckets]).to eq(%w[2026-01-01 2026-02-01 2026-03-01 2026-04-01 2026-05-01 2026-06-01 2026-07-01 2026-08-01 2026-09-01])
    expect(monthly[:sources]['google']['spend'][8]).to eq(500.0)
  end
end
