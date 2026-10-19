require 'rails_helper'

# 📄 item 353: Análise de Páginas v2 — placar, pódio, linha do tempo e fila (nó marketing.resultados)
RSpec.describe 'CEVICO Page Agent API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/page_agent" }
  let!(:page) { CevicoPage.create!(account: account, title: 'Refrativa', slug: "refrativa-#{SecureRandom.hex(3)}", status: 'published') }

  before do
    Rails.cache.clear
    (1..5).each do |i|
      CevicoPageTraffic.create!(account: account, cevico_page: page, date: Date.current - i, source: 'google_ads', views: 40, cta_clicks: 4)
    end
  end

  it 'devolve placar, pódio, fila e a linha do tempo para o admin' do # rubocop:disable RSpec/MultipleExpectations
    action = Crm::CampaignAction.create!(account: account, channel: 'pages', level: 'page', ref_id: page.id.to_s, rule: 'cta_baixo', kind: 'page',
                                         key: 'k', title: 'Muita visita', suggested_on: Date.current)
    get base, params: { preset: 'month' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['scorecards'][page.id.to_s]).to include('title' => 'Refrativa', 'views' => 200)
    expect(body['scorecards'][page.id.to_s]['indicators'].pluck('key')).to include('cta', 'result')
    expect(body['podium']['convite'].first).to include('page_id' => page.id)
    expect(body['actions']['open'].pluck('id')).to eq([action.id])

    get "#{base}/timeline", params: { page_id: page.id, days: 30 }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['views'].sum).to eq(200)

    post "#{base}/manual", params: { id: action.id }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(action.reload).to have_attributes(status: 'applied', applied_mode: 'manual')
  end

  it 'barra atendente sem a concessão de Resultados de tráfego' do
    get base, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
