require 'rails_helper'

# 🧹 item 342 (13/10): o popup de "Entrou em Agendamento" contava PESSOAS em
# cima e CONSULTAS nas quebras (34 × 45). Agora há a quebra das pessoas, que
# soma o número de cima; a das consultas diz quantas pessoas são; e a "Fonte de
# pacientes" é contada sem a lente (antes dava CEVICO 100% por construção).
RSpec.describe 'CEVICO Meu Painel: agendamento descontaminado', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/home" }
  let(:inbox) { create(:inbox, account: account, name: 'Caixa Google') }
  let(:partners) do
    Crm::Pipeline.create!(account: account, name: 'OFTALMOFÁCIL', position: 1).tap do |p|
      p.stages.create!(name: 'Consulta Agendada', color: '#000', position: 0)
    end
  end
  let(:cevico) do
    Crm::Pipeline.create!(account: account, name: 'CEVICO', position: 0).tap do |p|
      p.stages.create!(name: 'Agendamento de Consulta', color: '#000', position: 0)
    end
  end

  before do
    travel_to Time.current.in_time_zone('America/Sao_Paulo').change(hour: 12)
    Rails.cache.clear
    Current.reset
    cevico
    CrmSetting.create!(account: account, agenda_config: { 'oftalmofacil' => { 'provider_name' => 'CATARATA_SP',
                                                                              'partner_pipeline_id' => partners.id } })
  end

  def person(name, arrived: Time.current)
    create(:contact, account: account, name: name, created_at: arrived).tap do |c|
      create(:conversation, account: account, inbox: inbox, contact: c, created_at: arrived)
    end
  end

  def book(contact, attrs = {})
    Task.create!({ account: account, creator: admin, contact: contact, title: 'Consulta: Paciente', task_type: 'consulta',
                   due_at: 2.days.from_now }.merge(attrs))
  end

  it 'quebra de pessoas soma o número de cima; consultas dizem quantas pessoas são; fonte sem a lente', :aggregate_failures do
    ana = person('Ana')
    beto = person('Beto', arrived: 60.days.ago)
    [ana, beto].each { |c| Crm::Contact.create!(contact: c, pipeline: cevico, stage: cevico.stages.first) }
    book(ana)
    book(ana, due_at: 3.days.from_now)
    book(beto)
    book(person('Caio'), origin: 'oftalmofacil')

    get base, params: { preset: 'today' }, headers: admin.create_new_auth_token, as: :json
    data = response.parsed_body['panel_data']

    expect(data['appointments_created']).to eq(2)
    expect(data['booking_people']).to include('total' => 2, 'new_leads' => 1, 'base' => 1)
    expect(data['booking_people']['by_origin_inbox'].sum { |r| r['count'] }).to eq(2)
    expect(data['booked_breakdown']).to include('total' => 3, 'people' => 2, 'by_stamp_all_sources' => true)
    expect(data['booked_breakdown']['by_stamp'].pluck('label', 'count')).to contain_exactly(['CEVICO', 3], ['Oftalmofácil', 1])
  end

  it 'a Visão geral devolve o volume do período e o agendamento separado em novos × base' do
    agent = create(:user, account: account, role: :agent) # admin puxaria o CAC (cotação do dólar de fora)
    get "#{base}/overview", params: { preset: 'today' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['entrada'].keys).to include('agendaram_novos', 'agendaram_base', 'agendaram_total', 'safra', 'por_caixa')
    keys = %w[agendamentos reagendamentos cancelamentos confirmacoes comparecimentos faltas indicacoes fechamentos cirurgias_realizadas]
    expect(body['volumes'].pluck('key')).to eq(keys)
  end
end
