require 'rails_helper'

# 📝 11/11/2026 (LIFE): o resumo do cliente na Central do cliente e no cartão do funil.
RSpec.describe 'Central do cliente: resumo escrito do cliente', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Fernando') }
  let(:contact) { create(:contact, account: account, name: 'Ivan Coral') }
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }
  let(:campos) do
    [{ 'chave' => 'conta', 'rotulo' => 'Conta de luz' },
     { 'chave' => 'consumo_futuro', 'rotulo' => 'Vai aumentar o consumo', 'etiqueta' => 'consumo-vai-aumentar' }]
  end

  before do
    Rails.cache.clear
    Current.reset
    CrmSetting.find_or_create_by!(account: account).update!(ai_config: { 'ficha_cliente' => { 'campos' => campos } })
  end

  it 'a equipe completa o resumo pela página; ele volta na página e no cartão do funil', :aggregate_failures do
    ficha = { conta: 'R$ 300', consumo_futuro: '2 ar-condicionados', cpf: '1' }
    post "#{base}/patients/#{contact.id}/update_profile", params: { ficha: ficha }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body.dig('client_summary', 'filled')).to eq(2)
    expect(contact.reload.label_list).to eq(['consumo-vai-aumentar'])

    get "#{base}/patients/#{contact.id}", headers: admin.create_new_auth_token, as: :json
    campo = response.parsed_body.dig('client_summary', 'fields').first
    expect(campo).to include('key' => 'conta', 'label' => 'Conta de luz', 'value' => 'R$ 300', 'by' => 'Fernando')

    pipeline = Crm::Pipeline.create!(account: account, name: 'Life')
    stage = pipeline.stages.create!(name: 'Novos Contatos', color: '#000', position: 0)
    Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage)
    get "#{base}/pipelines/#{pipeline.id}/contacts", headers: admin.create_new_auth_token, as: :json
    body = response.parsed_body
    cards = body.is_a?(Hash) ? body.values.flatten : body
    card = cards.find { |c| c.is_a?(Hash) && c['contact_id'] == contact.id }
    expect(card['client_summary']).to eq([{ 'label' => 'Conta de luz', 'value' => 'R$ 300' },
                                          { 'label' => 'Vai aumentar o consumo', 'value' => '2 ar-condicionados' }])
  end
end
