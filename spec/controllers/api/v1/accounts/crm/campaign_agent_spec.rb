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
    expect(body['series']['labels'].size).to eq(7) # 358c: dia a dia dos gráficos
    expect(body['series']['all'].keys).to contain_exactly('spend', 'leads', 'booked')
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

  it 'item 359: o canal SEO / orgânico lê as páginas sem anúncio pago', :aggregate_failures do
    page = CevicoPage.create!(account: account, title: 'Cirurgia de miopia', slug: 'cirurgia-de-miopia', status: 'published')
    CevicoPageTraffic.create!(account: account, cevico_page: page, date: Date.current - 1, source: 'google_organico', views: 120, cta_clicks: 9)
    CevicoPageTraffic.create!(account: account, cevico_page: page, date: Date.current - 1, source: 'google_ads', views: 50, cta_clicks: 5)
    organico = create(:contact, account: account, additional_attributes: { 'page_ads' => { 'page_id' => page.id, 'source' => 'google_organico',
                                                                                           'captured_at' => (1.day.ago).iso8601 } })
    create(:contact, account: account, additional_attributes: { 'page_ads' => { 'page_id' => page.id, 'source' => 'google_ads',
                                                                                'captured_at' => (1.day.ago).iso8601 } })

    get base, params: { preset: 'last7', channel: 'seo' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    row = body['campaigns'].find { |c| c['id'] == "page-#{page.id}" }
    expect(row).to include('channel' => 'seo', 'name' => 'Cirurgia de miopia', 'impressions' => 120, 'link_clicks' => 9, 'leads' => 1, 'spend' => 0.0)
    expect(body['totals']['seo']).to include('leads' => 1, 'impressions' => 120)
    expect(body['totals']['seo']['goal_cost']).to be_nil
    expect(body['series']['seo']['views'].sum).to eq(120)
    expect(body['baselines']['seo'].keys).to include('30')
    expect(body['channels']['seo']).to include('pages' => 1)
    expect(organico.reload.id).to be_present
  end

  it 'item 362: paciente cujo "como chegou" a equipe informou vira a linha "(informado pela equipe)" do canal' do
    create(:contact, account: account, additional_attributes: { 'canal_origem' => { 'key' => 'meta_anuncio', 'por' => 'Vaneide',
                                                                                    'em' => (1.day.ago).iso8601 } })
    get base, params: { preset: 'last7', channel: 'meta' }, headers: admin.create_new_auth_token, as: :json
    row = response.parsed_body['campaigns'].find { |c| c['id'] == 'meta-team' }
    expect(row).to include('team' => true, 'leads' => 1, 'channel' => 'meta')
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
