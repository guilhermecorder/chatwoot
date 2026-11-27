require 'rails_helper'

# 📊 27/11/2026 (LIFE): bloco "Custos e retorno" do Meu Painel — todos veem; lançar e apagar custo é só administrador.
RSpec.describe 'Meu Painel: custos e retorno', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/home" }

  before do
    Rails.cache.clear
    Current.reset
    allow(Crm::UsdRateService).to receive_messages(rates_for: {}, last_known: { rate: 5.0 })
    Crm::Pipeline.create!(account: account, name: 'Life', position: 0).stages.create!(name: 'Novos Contatos', color: '#000', position: 0)
  end

  it 'o administrador lança um custo do mês e ele aparece no bloco', :aggregate_failures do
    post "#{base}/sales_cost", params: { category: 'trafego', amount: '1.200,00', date: Date.current.iso8601, span: 'mes' },
                               headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body.dig('entry', 'amount')).to eq(1200.0)

    get base, params: { only: 'economics', preset: 'month' }, headers: agent.create_new_auth_token, as: :json
    body = response.parsed_body['economics']
    expect(body['entries'].size).to eq(1)
    expect(body.dig('costs', 'rows').find { |r| r['key'] == 'trafego' }['fonte']).to eq('lancado')
    expect(body['team']).to include('hours', 'people', 'human_requests')
  end

  it 'atendente não lança nem apaga custo', :aggregate_failures do
    post "#{base}/sales_cost", params: { category: 'ia', amount: '100', date: Date.current.iso8601, span: 'semana' },
                               headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    entry = Crm::SalesCosts.new(account).create!(category: 'ia', amount: 100, date: Date.current, span: 'semana')
    delete "#{base}/sales_cost", params: { id: entry.id }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    delete "#{base}/sales_cost", params: { id: entry.id }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:no_content)
    expect(CevicoFinanceEntry.exists?(entry.id)).to be(false)
  end

  it 'valor inválido volta com a explicação' do
    post "#{base}/sales_cost", params: { category: 'aluguel', amount: '100', date: Date.current.iso8601, span: 'mes' },
                               headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
