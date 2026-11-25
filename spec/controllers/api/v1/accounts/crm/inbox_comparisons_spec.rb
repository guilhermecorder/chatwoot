require 'rails_helper'

# 🆚 item 413 — a porta do Comparativo de caixas: mesmo acesso do Dashboard CRM;
# dinheiro só para administrador.
RSpec.describe 'Comparativo de caixas API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/inbox_comparison" }
  let(:inbox) { create(:inbox, account: account, name: 'INSTAGRAM') }

  before do
    travel_to Time.current.in_time_zone('America/Sao_Paulo').change(hour: 12)
    Rails.cache.clear
    CrmSetting.create!(account: account, agenda_config: {})
    contact = create(:contact, account: account, created_at: 1.hour.ago)
    create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 1.hour.ago)
    allow(Crm::MetaInsightsService).to receive(:new).and_return(instance_double(Crm::MetaInsightsService, call: { configured: false }))
  end

  it 'pede login' do
    get url

    expect(response).to have_http_status(:unauthorized)
  end

  it 'devolve o comparativo do período com o dinheiro para o administrador', :aggregate_failures do
    get url, params: { preset: 'today', compare: 'previous' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['financeiro']).to be(true)
    expect(body['meta']).to include('aviso' => 'Meta Ads não configurado em Integrações')
    expect(body['caixas'].first).to include('nome' => 'INSTAGRAM', 'porta' => true)
    expect(body['caixas'].first['funil']).to include('chegaram' => 1)
    expect(body['caixas'].first['custo']).to include('investimento' => 0.0)
    expect(body['comparacao']).to include('modo' => 'previous', 'rotulo' => 'ontem')
  end

  it 'entende o período "Hoje + ontem" (item 418)', :aggregate_failures do
    get url, params: { preset: 'last2' }, headers: admin.create_new_auth_token, as: :json

    sp = Time.current.in_time_zone('America/Sao_Paulo')
    expect(response.parsed_body['periodo']['de']).to start_with(sp.yesterday.strftime('%Y-%m-%d'))
    expect(response.parsed_body['periodo']['ate']).to start_with(sp.strftime('%Y-%m-%d'))
    expect(response.parsed_body['comparacao']).to include('rotulo' => '2 dias anteriores')
  end

  it 'devolve as linhas por caixa, campanha e criativo para quem vê o relatório (item 418)', :aggregate_failures do
    get "#{url}/lines", params: { preset: 'last7' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['regime']).to include('balde' => 'dia', 'janela' => 7)
    expect(body['caixas'].first).to include('nome' => 'INSTAGRAM', 'chegaram' => 1)
    expect(body['campanhas'].first).to include('nome' => 'Sem anúncio do Meta carimbado · INSTAGRAM')
  end

  it 'as linhas também pedem login' do
    get "#{url}/lines"

    expect(response).to have_http_status(:unauthorized)
  end

  it 'usa a régua padrão de período (mês, quando não vem preset)' do
    get url, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['periodo']['de']).to start_with(Time.current.in_time_zone('America/Sao_Paulo').strftime('%Y-%m-01'))
  end
end
