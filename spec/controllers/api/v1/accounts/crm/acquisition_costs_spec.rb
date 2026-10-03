require 'rails_helper'

# 💰 item 318: Financeiro & CAC — mesmo acesso do Financeiro; ?usd = projeção
RSpec.describe 'CEVICO Acquisition Cost API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/acquisition_cost" }

  before do
    Rails.cache.clear
    allow(Crm::UsdRateService).to receive(:rates_for).and_return({})
  end

  it 'devolve os blocos da tela para o admin, com o dólar manual', :aggregate_failures do
    get base, params: { preset: 'last90', usd: '5.5' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['period']['days']).to eq(90)
    expect(body['usd']).to include('mode' => 'manual', 'manual' => 5.5)
    expect(body['summary']).to include('patients' => 0, 'cac_ads' => nil)
    expect(body['channels'].pluck('key')).to eq(%w[google meta organico])
    expect(body['partner']).to include('patients' => 0)
  end

  it 'barra atendente sem a concessão Financeiro' do
    get base, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
