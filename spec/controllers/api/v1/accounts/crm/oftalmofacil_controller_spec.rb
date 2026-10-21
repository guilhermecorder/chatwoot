require 'rails_helper'

# 🏥 item 229: ambiente Oftalmofácil (espelho do hub) dentro do sistema
RSpec.describe 'CEVICO Oftalmofácil hub', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, name: 'Maria Parceira', phone_number: '+5511988887777') }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/oftalmofacil" }

  before do
    CrmSetting.create!(account: account, agenda_config: { 'oftalmofacil' => {
                         'provider_name' => 'CATARATA_SP', 'clinics' => { 'IOP Paulista' => 'iop' },
                         'doctors' => { '170937' => 'Dr. Henrique Gemelli' }, 'partners_enabled' => true
                       } })
    Crm::OftalmofacilSurgery.create!(account: account, item_token: 't1', status_kind: 'agendada', patient_name: 'Maria Parceira',
                                     patient_phone: '11988887777', provider_name: 'CLINICA NORTE', clinic_name: 'IOP Paulista',
                                     doctor_crm: '170937', procedure_name: 'Faco', procedure_type: 'Cirurgia', eye: 'OD',
                                     surgery_date: Date.current + 3, surgery_hour: '09:30', amount: 4500, contact_id: contact.id)
    Crm::OftalmofacilSurgery.create!(account: account, item_token: 't2', status_kind: 'realizada', patient_name: 'José Nosso',
                                     provider_name: 'CATARATA_SP', clinic_name: 'Clínica Sem Mapa', procedure_type: 'Cirurgia',
                                     surgery_date: Date.current - 2, amount: 3000)
    Crm::OftalmofacilSurgery.create!(account: account, item_token: 't3', status_kind: 'agendada', patient_name: 'Sem Contato',
                                     provider_name: 'CLINICA NORTE', clinic_name: 'Clínica Sem Mapa', procedure_type: 'Exame',
                                     surgery_date: Date.current + 5)
    account.tasks.create!(title: 'Cirurgia: Maria Parceira', task_type: 'cirurgia', creator: admin, unit: 'iop',
                          due_at: 3.days.from_now, source: 'oftalmofacil', source_detail: 'CLINICA NORTE',
                          external_ref: 't1', booking_kind: 'registro', contact: contact)
  end

  # Rodada 4 (achado #172): com outra sincronização rodando, os botões avisam (409)
  describe 'trava do sync nos botões' do
    let(:lock_key) { Crm::OftalmofacilSyncJob.lock_key(account.id) }
    let(:on_config) do
      { 'db_host' => 'h', 'db_name' => 'd', 'db_user' => 'u', 'db_password' => 'p', 'provider_name' => 'CATARATA_SP',
        'enabled' => true, 'agenda_enabled' => true }
    end

    before do
      CrmSetting.find_by(account: account).update!(agenda_config: { 'oftalmofacil' => on_config })
      Redis::LockManager.new.lock(lock_key, 1.minute)
    end

    after { Redis::Alfred.delete(lock_key) }

    it '"Trazer para a Agenda" devolve 409 com o aviso, sem reprocessar', :aggregate_failures do
      allow(Crm::OftalmofacilSyncService).to receive(:new)

      post "#{base}/reconcile_day", params: { date: Date.current.iso8601 }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to eq(Crm::OftalmofacilSyncJob::BUSY_MESSAGE)
      expect(Crm::OftalmofacilSyncService).not_to have_received(:new)
    end

    it '"Sincronizar agora" devolve 409 com o aviso e não enfileira o job', :aggregate_failures do
      allow(Crm::OftalmofacilSyncJob).to receive(:perform_later)

      post "/api/v1/accounts/#{account.id}/crm/settings/sync_oftalmofacil",
           params: { full: true }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to eq(Crm::OftalmofacilSyncJob::BUSY_MESSAGE)
      expect(Crm::OftalmofacilSyncJob).not_to have_received(:perform_later)
    end

    it 'com a trava livre, "Sincronizar agora" enfileira o job normalmente' do
      Redis::Alfred.delete(lock_key)
      allow(Crm::OftalmofacilSyncJob).to receive(:perform_later)

      post "/api/v1/accounts/#{account.id}/crm/settings/sync_oftalmofacil", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(Crm::OftalmofacilSyncJob).to have_received(:perform_later).with(account.id, full: false)
    end
  end

  it 'overview: parceiros com nosso × parceiro, saúde da Agenda e valores só para admin', :aggregate_failures do
    get "#{base}/overview", params: { from: (Date.current - 10).iso8601, to: (Date.current + 10).iso8601 },
                            headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['totals']['total']).to eq(3)
    norte = body['partners'].find { |p| p['name'] == 'CLINICA NORTE' }
    own = body['partners'].find { |p| p['name'] == 'CATARATA_SP' }
    expect(norte['own']).to be(false)
    expect(norte['total']).to eq(2)
    expect(norte['with_task']).to eq(1)
    expect(own['own']).to be(true)
    expect(own['amount_done']).to eq(3000.0)
    expect(body['agenda']['upcoming']).to eq(2)
    expect(body['agenda']['without_task']).to eq(1)
    expect(body['agenda']['unmatched_contacts']).to eq(1)
    expect(body['agenda']['clinics_unmapped']).to eq(['Clínica Sem Mapa'])
    expect(body['clinics'].find { |c| c['name'] == 'IOP Paulista' }['unit']).to eq('iop')
    expect(body['procedures'].find { |x| x['name'] == 'Faco' }).to include('total' => 1, 'realizada' => 0)
    expect(norte['top_procedures'].map { |x| x['name'] }).to include('Faco')
    expect(body['clinics'].find { |c| c['name'] == 'Clínica Sem Mapa' }['realizada']).to eq(1)

    get "#{base}/overview", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['partners'].filter_map { |p| p['amount'] }).to be_empty
  end

  it 'items: filtros por lado, agenda e busca; ficha com o estado na Agenda e no CRM', :aggregate_failures do
    get "#{base}/items", params: { side: 'partners' }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['total']).to eq(2)
    row = response.parsed_body['rows'].find { |r| r['item_token'] == 't1' }
    expect(row['task']['unit']).to eq('iop')
    expect(row['doctor']).to eq('Dr. Henrique Gemelli')
    expect(row['contact']['id']).to eq(contact.id)
    expect(row['amount']).to eq('4500.0')

    get "#{base}/items", params: { agenda: 'without' }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['rows'].map { |r| r['item_token'] }).to contain_exactly('t2', 't3')

    get "#{base}/items", params: { q: '8887777' }, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['rows'].map { |r| r['item_token'] }).to eq(['t1'])
    expect(response.parsed_body['rows'].first['amount']).to be_nil

    get "#{base}/patients", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['total']).to eq(3)
    maria = response.parsed_body['rows'].find { |r| r['patient_name'] == 'Maria Parceira' }
    expect(maria['contact']['id']).to eq(contact.id)
    expect(maria['has_upcoming']).to be(true)
    expect(maria['providers']).to eq(['CLINICA NORTE'])

    get "#{base}/items/#{Crm::OftalmofacilSurgery.find_by(item_token: 't1').id}", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['card']).to be_nil
    expect(response.parsed_body).to have_key('raw')
  end

  # Rodada 5 (#173, revisão): o hub nunca marca "realizada" — na lista, no mês
  # e no chip de filtro, ativa com a data já passada = realizada (concluidas)
  it 'items: chip "Realizada" usa a régua do resumo e cada item traz a situação para a tela', :aggregate_failures do
    Crm::OftalmofacilSurgery.create!(account: account, item_token: 't4', status_kind: 'agendada', patient_name: 'Já Operou',
                                     provider_name: 'CATARATA_SP', surgery_date: Date.current - 4, amount: 5000)
    Crm::OftalmofacilSurgery.create!(account: account, item_token: 't5', status_kind: 'aguardando_pagamento', patient_name: 'Não Pagou',
                                     provider_name: 'CATARATA_SP', surgery_date: Date.current - 4)

    get "#{base}/items", params: { status: 'realizada' }, headers: admin.create_new_auth_token, as: :json
    # antes: só t2 (o rótulo cru do hub); a ativa que já passou ficava de fora
    expect(response.parsed_body['rows'].map { |r| r['item_token'] }).to contain_exactly('t2', 't4')

    get "#{base}/items", params: { status: 'agendada' }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['rows'].map { |r| r['item_token'] }).to contain_exactly('t1', 't3')

    get "#{base}/items", headers: admin.create_new_auth_token, as: :json
    view = response.parsed_body['rows'].to_h { |r| [r['item_token'], [r['status_view'], r['status_view_label']]] }
    expect(view['t4']).to eq(%w[realizada Realizada])
    expect(view['t1']).to eq(%w[agendada Agendada])
    expect(view['t5']).to eq(['aguardando_pagamento', 'Aguardando pagamento'])
    expect(response.parsed_body['rows'].find { |r| r['item_token'] == 't4' }['status_kind']).to eq('agendada')
  end
end
