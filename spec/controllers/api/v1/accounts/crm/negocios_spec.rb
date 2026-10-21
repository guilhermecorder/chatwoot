require 'rails_helper'

# 🏢 Meus negócios (21/10): lançador do dono — lista sem token, login por SSO
RSpec.describe 'CEVICO Meus negócios API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, email: 'dono@teste.com') }
  let(:outro_admin) { create(:user, account: account, role: :administrator, email: 'outro@teste.com') }
  let(:agent) { create(:user, account: account, role: :agent, email: 'dono@teste.com') }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/negocios" }
  let(:config) do
    [
      { chave: 'cevico', nome: 'CEVICO', url: 'https://cevico.test', user_id: 7, account_id: 1, token: 'segredo' },
      { chave: 'life', nome: 'LIFE', local: true, account_id: account.id }
    ].to_json
  end

  before do
    stub_const('ENV', ENV.to_h.merge('MEUS_NEGOCIOS_DONOS' => 'dono@teste.com', 'MEUS_NEGOCIOS' => config))
  end

  it 'lista os negócios do dono sem expor token nem user_id', :aggregate_failures do
    get base, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['dono']).to be(true)
    expect(body['negocios'].pluck('chave')).to eq(%w[cevico life])
    expect(body['negocios'].first).not_to have_key('token')
    expect(body['negocios'].first).not_to have_key('user_id')
  end

  it 'esconde a lista de um administrador que não é dono' do
    get base, headers: outro_admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to eq('dono' => false, 'negocios' => [])
  end

  it 'esconde a lista de um atendente mesmo com o e-mail do dono' do
    get base, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['dono']).to be(false)
  end

  it 'gera o link de entrada pela API de plataforma do outro sistema', :aggregate_failures do
    resposta = instance_double(HTTParty::Response, success?: true,
                                                   parsed_response: { 'url' => 'https://cevico.test/app/login?email=d&sso_auth_token=t' })
    allow(HTTParty).to receive(:get).and_return(resposta)

    post "#{base}/cevico/login", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['url']).to eq('https://cevico.test/app/login?email=d&sso_auth_token=t&sso_account_id=1')
    expect(HTTParty).to have_received(:get).with('https://cevico.test/platform/api/v1/users/7/login',
                                                  hash_including(headers: { 'api_access_token' => 'segredo' }))
  end

  it 'abre o negócio local sem chamar ninguém' do
    allow(HTTParty).to receive(:get)
    post "#{base}/life/login", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['url']).to eq("/app/accounts/#{account.id}/inicio")
    expect(HTTParty).not_to have_received(:get)
  end

  it 'explica quando o outro sistema não responde' do
    allow(HTTParty).to receive(:get).and_return(instance_double(HTTParty::Response, success?: false, code: 401))
    post "#{base}/cevico/login", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:bad_gateway)
    expect(response.parsed_body['error']).to include('401')
  end

  it 'barra o login de quem não é dono' do
    post "#{base}/cevico/login", headers: outro_admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
