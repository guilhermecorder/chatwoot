require 'rails_helper'

# rubocop:disable RSpec/MultipleExpectations
RSpec.describe 'CEVICO Central de Criativos API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/creatives" }

  it 'sem Meta configurada devolve configured=false e recusa atualizar' do
    CrmSetting.create!(account: account)
    get base, params: { preset: 'month' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['configured']).to be(false)
    post "#{base}/sync", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  context 'when a Meta está configurada (simulação)' do
    before do
      CrmSetting.create!(account: account, meta_ads_config: { 'access_token' => 'simulate', 'ad_account_id' => 'act_1' })
      Crm::AdInsightsSyncService.new(account: account).call
    end

    it 'lista, detalha, ranqueia ativos e enfileira a atualização com trava de tempo' do
      get base, params: { preset: 'last7' }, headers: admin.create_new_auth_token, as: :json
      body = response.parsed_body
      expect(body['rows'].size).to eq(8)
      expect(body['simulated']).to be(true)
      expect(body['sync']['synced_at']).to be_present

      get "#{base}/2301", params: { preset: 'last7' }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['daily'].size).to eq(7)

      get "#{base}/assets", params: { preset: 'last7' }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['titles']['rows']).not_to be_empty

      get "#{base}/history", params: { months: 2 }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['records']['link_ctr']['best_week']).to include('value')
      expect(response.parsed_body['assets_months'].first['title']).to include('label')

      post "#{base}/sync", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:too_many_requests)

      allow(Crm::AdInsightsSyncJob).to receive(:perform_later)
      post "#{base}/sync", params: { force: true, days: 30 }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(Crm::AdInsightsSyncJob).to have_received(:perform_later).with(account.id, 30)
    end

    it 'só admin enfileira a carga completa (37 meses); exporta CSV; resumo do que está guardado' do
      post "#{base}/load_history", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden).or have_http_status(:unauthorized)
      post "#{base}/load_history", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['days']).to eq(1125)

      get "#{base}/export", params: { all: 1 }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/csv')
      expect(response.body).to include('Data;ID do anúncio')

      get "#{base}/sync_status", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['storage']['ads']).to eq(9)
      expect(response.parsed_body['storage']['gone_on_meta']).to eq(1)
    end

    it 'barra atendente sem a área de relatórios' do
      get base, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
