require 'rails_helper'

# 🎯 item 352: Análises → Campanhas — nó marketing.campanhas (ver × editar)
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe 'CEVICO Campaign Agent API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/campaign_agent" }

  before { Rails.cache.clear }

  it 'devolve a leitura, a nossa média, as recomendações e os parâmetros para o admin' do
    action = Crm::CampaignAction.create!(account: account, channel: 'meta', level: 'adset', ref_id: 'a1', ref_name: 'Conjunto', rule: 'custo_alto',
                                         kind: 'budget_down', key: 'k', title: 'Custo acima', suggested_on: Date.current)
    get base, params: { preset: 'last7' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['period']['days']).to eq(7)
    expect(body['params']).to include('goal' => 'booked')
    expect(body['goal_label']).to eq('custo por agendamento de consulta')
    expect(body['baselines'].keys).to include('all', 'meta', 'google')
    expect(body['actions']['open'].pluck('id')).to eq([action.id])
    expect(body['can_edit']).to be(true)

    post "#{base}/decide", params: { id: action.id, decision: 'approve' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(action.reload.status).to eq('approved')

    post "#{base}/manual", params: { id: action.id }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(action.reload).to have_attributes(status: 'applied', applied_mode: 'manual')

    post "#{base}/params", params: { params: { goal: 'surgery', budget: { meta: 9000 } } }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['params']).to include('goal' => 'surgery')
  end

  it 'monta o plano da ficha e guarda' do
    post "#{base}/brief", params: { brief: { name: 'Miopia cenas', daily_budget: 50, whatsapp: '5511998085773' } },
                          headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    plan = response.parsed_body['brief']['plan']
    expect(plan['campaign_name']).to start_with('CV · Miopia cenas · Leads pelo WhatsApp')
    expect(plan['utm']).to include('utm_campaign=miopia-cenas')
    expect(plan['steps'].size).to eq(5)
  end

  it 'barra atendente sem a concessão e deixa quem só vê apenas ver' do
    get base, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    CrmSetting.create!(account: account, agent_permissions: { 'tree' => { agent.id.to_s => { 'marketing.campanhas' => 'view' } } })
    get base, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['can_edit']).to be(false)
    post "#{base}/run", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
# rubocop:enable RSpec/MultipleExpectations
