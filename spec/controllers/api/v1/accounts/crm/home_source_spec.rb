require 'rails_helper'

# 🔎 item 328 (Fase 2 das Fontes): a chavinha CEVICO | Oftalmofácil | Tudo do
# Meu Painel (?source=) + o recorde que não pode ser gravado com o painel
# "desde sempre" quando o miolo vem do cache.
RSpec.describe 'CEVICO Meu Painel por fonte', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/home" }
  let(:partners) do
    Crm::Pipeline.create!(account: account, name: 'OFTALMOFÁCIL', position: 1).tap do |p|
      p.stages.create!(name: 'Consulta Agendada', color: '#000', position: 0)
    end
  end

  before do
    Rails.cache.clear
    Current.reset
    # a casa nasce primeiro: o funil principal é o mais antigo da conta
    Crm::Pipeline.create!(account: account, name: 'CEVICO', position: 0).stages.create!(name: 'Agendamento de Consulta', color: '#000', position: 0)
    CrmSetting.create!(account: account, agenda_config: { 'oftalmofacil' => { 'provider_name' => 'CATARATA_SP',
                                                                              'partner_pipeline_id' => partners.id } })
  end

  def book(attrs = {})
    Task.create!({ account: account, creator: admin, title: 'Consulta: Paciente', task_type: 'consulta',
                   due_at: 2.days.from_now }.merge(attrs))
  end

  def panel(params = {})
    get base, params: { preset: 'today' }.merge(params), headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    response.parsed_body
  end

  it 'sem escolha mostra a casa; a chavinha separa Oftalmofácil e soma em Tudo', :aggregate_failures do
    book
    book(origin: 'oftalmofacil')

    body = panel
    expect(body['source']).to eq('cevico')
    expect(body['sources'].pluck('key')).to eq(%w[cevico oftalmofacil])
    expect(body['panel_data']).to include('appointments_booked' => 1)
    expect(body['panel_data']['booking_cuts']).to include('total' => 1, 'source' => 'cevico')

    expect(panel(source: 'oftalmofacil')['panel_data']).to include('appointments_booked' => 1)
    all = panel(source: 'all')
    expect(all['panel_data']).to include('appointments_booked' => 2)
    expect(all['panel_data']['booking_cuts']['sources'].pluck('key', 'count')).to eq([['cevico', 1], ['oftalmofacil', 1]])
  end

  it 'o cesto de indicadores segue a fonte pedida' do
    book(due_at: 1.hour.from_now)
    book(due_at: 1.hour.from_now, origin: 'oftalmofacil')

    due = lambda do |source|
      get "#{base}/kpis", params: { preset: 'today', source: source }.compact, headers: admin.create_new_auth_token, as: :json
      response.parsed_body['metrics']['appointments_due']['value']
    end
    expect([due.call('cevico'), due.call('oftalmofacil'), due.call('all'), due.call(nil)]).to eq([1.0, 1.0, 2.0, 2.0])
  end

  it 'recorde é só da casa e nunca é gravado com o total de todos os tempos (painel vindo do cache)', :aggregate_failures do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    book(created_at: 40.days.ago, due_at: 30.days.ago)
    book(created_at: 39.days.ago, due_at: 30.days.ago)
    book

    panel # 1ª visita calcula e guarda
    panel # 2ª visita lê do cache — antes recalculava sem período e gravava 3 como recorde do dia
    records = CrmSetting.find_by(account: account).agenda_config['panel_records'] || {}
    expect(records['agendamento.appointments_booked.day']).to include('best' => 1)

    book(origin: 'oftalmofacil')
    book(origin: 'oftalmofacil')
    expect(panel(source: 'all')['goals']['records']).to eq({})
    expect(CrmSetting.find_by(account: account).agenda_config['panel_records']['agendamento.appointments_booked.day']).to include('best' => 1)
  end
end
