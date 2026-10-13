require 'rails_helper'

# 🔒 auditoria R2 (seção 6, 12/10): três portas com dados de pacientes que a
# auditoria apontou como abertas ANTES do catálogo de acessos (rodada 334):
# o CSV de ligações, a lista de pacientes dos parceiros e o resultado das
# campanhas. Hoje cada uma exige o nó do catálogo — este spec prova que a
# porta fecha quando a pessoa não tem o nó e abre quando ganha.
RSpec.describe 'CEVICO portas: CSV de ligações, pacientes dos parceiros e campanhas', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }

  before { Current.reset }

  def perms!(hash)
    CrmSetting.find_or_create_by!(account: account).update!(agent_permissions: hash)
  end

  it 'CSV de ligações exige o nó Chamadas (padrão: todos têm; sem ele, barra)', :aggregate_failures do
    get "#{base}/calls/export", params: { preset: 'today' }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:success)

    perms!('tree' => { agent.id.to_s => { 'chamadas' => 'none' } })
    get "#{base}/calls/export", params: { preset: 'today' }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  it 'lista de pacientes dos parceiros exige o nó Oftalmofácil (padrão: ver; sem ele, barra)', :aggregate_failures do
    get "#{base}/oftalmofacil/patients", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)

    perms!('tree' => { agent.id.to_s => { 'pacientes.oftalmofacil' => 'none' } })
    get "#{base}/oftalmofacil/patients", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['error']).to include('Oftalmofácil')
  end

  it 'resultado das campanhas exige o Dashboard Campanhas (padrão: ninguém; com a concessão, abre)', :aggregate_failures do
    get "#{base}/campaigns_dashboard", params: { preset: 'month' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    perms!('tree' => { agent.id.to_s => { 'relatorios.campanhas' => 'view' } })
    get "#{base}/campaigns_dashboard", params: { preset: 'month' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
  end
end
