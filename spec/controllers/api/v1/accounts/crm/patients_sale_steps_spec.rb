require 'rails_helper'

# 🧭 18/11/2026 (LIFE): botões "Etapa da venda" na conversa e na Central do cliente.
RSpec.describe 'Etapa da venda do cliente', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent, name: 'Fernando') }
  let(:contact) { create(:contact, account: account, name: 'Marlene') }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/patients/#{contact.id}" }

  before { Current.reset }

  it 'lê a etapa, marca e desfaz', :aggregate_failures do
    get "#{base}/sale_steps", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['current']).to eq('leads')

    post "#{base}/sale_step", params: { step: 'proposta' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['current']).to eq('proposta')
    expect(contact.reload.label_list).to include('proposta-de-fechamento')

    post "#{base}/sale_step", params: { step: 'proposta', undo: true }, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['current']).to eq('leads')
  end

  it 'recusa etapa que não é de marcar à mão' do
    post "#{base}/sale_step", params: { step: 'enviado' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
