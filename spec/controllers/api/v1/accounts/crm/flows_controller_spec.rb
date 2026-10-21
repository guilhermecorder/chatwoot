require 'rails_helper'

RSpec.describe 'CEVICO Mapa de Fluxos API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/flows" }

  describe 'GET /crm/flows' do
    it 'devolve os fluxos e os grupos para o admin' do
      get base, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['groups']).to eq(Crm::FlowMap::Flow::GROUPS)
      expect(body['flows'].map { |f| f['key'] }).to include('scheduler', 'voice', 'calls', 'followup_bots')
      scheduler = body['flows'].find { |f| f['key'] == 'scheduler' }
      expect(scheduler['mermaid']).to start_with('flowchart TD')
      expect(scheduler['live']).to include('enabled', 'last_run_at', 'counters', 'note')
      expect(scheduler['config']).to eq('tab' => 'agentes', 'anchor' => 'scheduler')
    end

    it 'nega para atendente sem a concessão de Automações' do
      get base, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'libera para atendente com a concessão de Automações' do
      CrmSetting.create!(account: account, agent_permissions: { 'grants' => { agent.id.to_s => ['automations'] } })
      get base, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['flows']).not_to be_empty
    end
  end

  describe 'GET /crm/flows/:key' do
    it 'devolve um fluxo com o estado ao vivo' do
      CrmSetting.create!(account: account, ai_config: { 'agents' => { 'opportunity' => { 'enabled' => true } } })
      get "#{base}/opportunity", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['key']).to eq('opportunity')
      expect(body['live']['enabled']).to be(true)
      expect(body['mermaid']).not_to match(/class .* cv_off$/)
    end

    it 'devolve 404 para chave desconhecida' do
      get "#{base}/nao-existe", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
