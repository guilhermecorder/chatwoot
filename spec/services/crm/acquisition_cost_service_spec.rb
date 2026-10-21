require 'rails_helper'

# 💰 item 318: Financeiro & CAC — cliente = 1ª cirurgia realizada no período;
# CAC de anúncios × CAC total; canal pelo 1º carimbo; Oftalmofácil à parte
RSpec.describe Crm::AcquisitionCostService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Jornada', position: 1) }
  let(:done) { Crm::Stage.create!(pipeline: pipeline, name: 'Cirurgia Realizada', position: 5, color: '#059669') }
  let(:since) { tz.parse('2026-09-01 00:00') }
  let(:until_at) { tz.parse('2026-09-30 23:59') }
  let(:result) { described_class.new(account: account, since: since, until_at: until_at, manual_usd: 5).call }

  def contact(name, attrs = {})
    create(:contact, account: account, name: name, additional_attributes: attrs)
  end

  def card_done(person, at:, value: 0, event: 'entered')
    card = Crm::Contact.create!(contact: person, pipeline: pipeline, stage: done, value: value)
    Crm::StageLog.create!(crm_contact: card, stage_id: done.id, stage_name: done.name, event_type: event, entered_at: at)
  end

  def of_surgery(token, date:, amount:, contact: nil, provider: 'CATARATA_SP', type: 'Cirurgia', **extra) # rubocop:disable Metrics/ParameterLists
    Crm::OftalmofacilSurgery.create!({ account: account, item_token: token, status_kind: 'agendada', contact: contact,
                                       surgery_date: Date.parse(date), amount: amount, provider_name: provider,
                                       procedure_type: type, patient_name: "Paciente #{token}" }.merge(extra))
  end

  def stub_service(klass, payload)
    allow(klass).to receive(:new).and_return(instance_double(klass, call: payload))
  end

  before do
    travel_to tz.parse('2026-10-03 10:00')
    Rails.cache.clear
    CrmSetting.create!(account: account, agenda_config: { 'oftalmofacil' => { 'provider_name' => 'CATARATA_SP' } })
    allow(Crm::UsdRateService).to receive(:rates_for).and_return({})
    stub_service(Crm::GoogleAdCostService, { configured: true, cost: 1000.0 })
    stub_service(Crm::GoogleKeywordsService, { configured: true, campaigns: { rows: [{ term: 'refrativa-sp', cost: 1000.0 }] } })
    stub_service(Crm::MetaInsightsService, { configured: true, spend: 3000.0 })

    # Meta (clique no anúncio → WhatsApp): card entrou em Cirurgia Realizada em 10/09
    meta = contact('Ana Meta', 'meta_ads' => { 'source_id' => 'ad1', 'captured_at' => '2026-08-20T10:00:00Z' })
    Crm::AdCreative.create!(account: account, ad_id: 'ad1', campaign_id: 'c1', campaign_name: 'Catarata CTWA')
    Crm::AdInsight.create!(account: account, ad_id: 'ad1', date: Date.new(2026, 9, 5), metrics: { 'spend' => 3000 })
    card_done(meta, at: tz.parse('2026-09-10 09:00'), value: 6000)

    # Google (landing page): presença na cirurgia da Agenda + valor pago no Oftalmofácil
    google = contact('Bruno Google', 'page_ads' => { 'source' => 'google_ads', 'campaign' => 'refrativa-sp',
                                                     'captured_at' => '2026-08-25T10:00:00Z' })
    account.tasks.create!(title: 'Cirurgia', task_type: 'cirurgia', attendance: 'attended', contact: google,
                          due_at: tz.parse('2026-09-15 08:00'), creator: user)
    of_surgery('g1', date: '2026-09-15', amount: 12_000, paid_amount: 10_000, contact: google)

    # orgânico: só no Oftalmofácil (o exame antes não conta como cirurgia)
    organic = contact('Carla Indicação')
    of_surgery('o1', date: '2026-09-20', amount: 8000, contact: organic)
    of_surgery('o0', date: '2026-09-01', amount: 300, contact: organic, type: 'Exame')
    # sem cadastro no sistema: conta pelo CPF
    of_surgery('s1', date: '2026-09-21', amount: 5000, patient_cpf: '123.456.789-00')
    # 2º olho de quem operou em maio: receita entra, cliente novo não
    old = contact('Dora Antiga')
    of_surgery('d1', date: '2026-05-01', amount: 7000, contact: old)
    of_surgery('d2', date: '2026-09-25', amount: 7000, contact: old)
    # parceiro do hub: bloco separado
    of_surgery('p1', date: '2026-09-12', amount: 4000, clinic_price: 3000, profit: 200, provider: 'CLINICA NORTE')
    # carga em massa: sem data confiável, fica fora
    card_done(contact('Eva Carga'), at: tz.parse('2026-09-03 10:00'), event: 'bulk')

    Crm::AiUsage.create!(account: account, agent_key: 'atendente', model: 'x', cost_usd: 10, created_at: tz.parse('2026-09-10 12:00'))
    Crm::WhatsappCharge.create!(account: account, waba_id: 'w1', phone_number: '5511', day: Date.new(2026, 9, 10), category: 'marketing',
                                pricing_type: 'regular', volume: 10, cost: 20, currency: 'BRL')
  end

  it 'separa o CAC de anúncios do CAC total', :aggregate_failures do
    expect(result[:spend]).to include(ads: 4000.0, tech: 70.0, total: 4070.0)
    expect(result[:spend][:ai]).to include(usd: 10.0, brl: 50.0)
    expect(result[:usd]).to include(mode: 'manual', manual: 5.0)
    expect(result[:summary]).to include(patients: 4, paid_patients: 2, cac_ads: 2000.0, cac_total: 1017.5,
                                        revenue: 36_000.0, paid_revenue: 16_000.0, roas_ads: 4.0)
    expect(result[:bulk_skipped]).to eq(1)
  end

  it 'abre por canal e por campanha', :aggregate_failures do
    by = result[:channels].index_by { |c| c[:key] }
    expect(by['google']).to include(spend: 1000.0, patients: 1, cac: 1000.0, revenue: 10_000.0, roas: 10.0)
    expect(by['meta']).to include(spend: 3000.0, patients: 1, cac: 3000.0, revenue: 6000.0, roas: 2.0)
    expect(by['organico']).to include(patients: 2, cac: nil, revenue: 20_000.0)
    expect(result[:campaigns]).to include(a_hash_including(channel: 'meta', name: 'Catarata CTWA', spend: 3000.0, patients: 1),
                                          a_hash_including(channel: 'google', name: 'refrativa-sp', spend: 1000.0, patients: 1))
  end

  it 'deixa o parceiro fora do CAC e mostra à parte', :aggregate_failures do
    expect(result[:partner]).to eq(patients: 1, revenue: 4000.0, result: 800.0)
    expect(result[:people].map { |p| p[:name] }).not_to include('Paciente p1')
    expect(result[:people].map { |p| p[:name] }).to include('Ana Meta', 'Bruno Google', 'Carla Indicação', 'Paciente s1')
    expect(result[:sources]).to eq('crm' => 1, 'agenda' => 1, 'oftalmofacil' => 2)
  end

  it 'sem gasto da Meta ao vivo usa o espelho diário dos anúncios' do
    stub_service(Crm::MetaInsightsService, { configured: true, error: 'token' })
    expect(result[:spend][:meta]).to include(spend: 3000.0, source: 'espelho')
  end
end
