require 'rails_helper'

# 🔌 24/11/2026: "Testar conexão" do ChatGPT dava verde só por conseguir LISTAR os
# modelos, o que funciona até com a chave de uma conta sem saldo. Em produção a
# chave gravada era de outra organização da OpenAI e a tela dizia "todos os
# modelos liberados". Agora o botão pede uma resposta de verdade.
RSpec.describe 'CRM — Testar conexão do ChatGPT', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/settings/test_openai" }
  let(:ok_body) do
    { id: 'resp_1', status: 'completed', output: [{ type: 'message', content: [{ type: 'output_text', text: 'ok' }] }],
      usage: { input_tokens: 10, output_tokens: 1 } }.to_json
  end

  before do
    CrmSetting.create!(account: account, ai_config: { 'api_key' => 'sk-ant-teste', 'openai_api_key' => 'sk-teste-9abc' })
    stub_request(:get, 'https://api.openai.com/v1/models')
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                 body: { data: Crm::LlmEngines::OPENAI_MODELS.keys.map { |id| { id: id } } }.to_json)
  end

  def stub_reply(model, status:, body:)
    stub_request(:post, 'https://api.openai.com/v1/responses')
      .with { |req| JSON.parse(req.body)['model'] == model }
      .to_return(status: status, headers: { 'Content-Type' => 'application/json' }, body: body)
  end

  it 'verde só quando o Luna e o Terra respondem de verdade; mostra o final da chave', :aggregate_failures do
    stub_reply('gpt-6-luna', status: 200, body: ok_body)
    stub_reply('gpt-6.1-terra', status: 200, body: ok_body)

    post url, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('success' => true)
    expect(response.parsed_body['message']).to include('respondendo de verdade', 'final 9abc')
  end

  it 'chave válida de conta sem saldo: vermelho, com o motivo e o final da chave para conferir na OpenAI', :aggregate_failures do
    stub_reply('gpt-6-luna', status: 200, body: ok_body)
    stub_reply('gpt-6.1-terra', status: 429, body: { error: { code: 'insufficient_quota', message: 'You exceeded your current quota' } }.to_json)

    post url, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('success' => false)
    expect(response.parsed_body['message']).to include('recusou responder', 'GPT-6.1 Terra', 'sem créditos', 'final 9abc')
  end

  it 'a leitura das configurações devolve só o final da chave, nunca a chave' do
    get "/api/v1/accounts/#{account.id}/crm/settings", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body.dig('ai', 'openai_key_hint')).to eq('9abc')
    expect(response.body).not_to include('sk-teste-9abc')
  end
end
