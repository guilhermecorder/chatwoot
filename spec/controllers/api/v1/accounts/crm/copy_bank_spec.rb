require 'rails_helper'

# 🪝 item 397: Banco de Ganchos (gancho → história → oferta)
RSpec.describe 'CRM copy bank', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/copy_bank" }
  let(:headers) { admin.create_new_auth_token }

  before { CrmSetting.create!(account: account, ai_config: {}) }

  it 'enche o banco na 1ª abertura, uma vez só', :aggregate_failures do
    get base, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    kinds = response.parsed_body['blocks'].group_by { |b| b['kind'] }.transform_values(&:size)
    expect(kinds['gancho']).to be > 900
    expect(kinds).to include('historia' => 8, 'oferta' => 8, 'regancho' => 19)
    gancho = response.parsed_body['blocks'].find { |b| b['kind'] == 'gancho' }
    expect(gancho['referencia']).to start_with('https://')
    expect(gancho['original']).to be_present

    expect { get base, headers: headers, as: :json }.not_to(change { account.cevico_copy_blocks.count })
  end

  it 'cria peça com as lacunas lidas do texto, marca uso e favorito', :aggregate_failures do
    post "#{base}/blocks", params: { block: { kind: 'gancho', categoria: 'cevico', texto: 'Você [ação] há [tempo]? Então [ação].' } },
                           headers: headers, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body['id']
    expect(response.parsed_body).to include('lacunas' => %w[ação tempo], 'fonte' => 'manual')

    post "#{base}/blocks/#{id}/use", headers: headers, as: :json
    expect(response.parsed_body['usos']).to eq(1)

    patch "#{base}/blocks/#{id}", params: { block: { favorito: true } }, headers: headers, as: :json
    expect(response.parsed_body['favorito']).to be(true)

    delete "#{base}/blocks/#{id}", headers: headers, as: :json
    expect(response).to have_http_status(:no_content)
  end

  it 'salva, lista e muda o status de uma criação', :aggregate_failures do
    post "#{base}/drafts", params: { draft: { titulo: 'Teste', tema: 'refrativa', formato: 'reels', texto_final: 'G\n\nH\n\nO',
                                              partes: { gancho: { texto: 'G', block_id: 1 }, historia: { texto: 'H' } } } },
                           headers: headers, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body['id']
    expect(response.parsed_body.dig('partes', 'gancho', 'texto')).to eq('G')

    patch "#{base}/drafts/#{id}", params: { draft: { status: 'aprovado' } }, headers: headers, as: :json
    expect(response.parsed_body['status']).to eq('aprovado')

    get "#{base}/drafts", headers: headers, as: :json
    expect(response.parsed_body['drafts'].pluck('id')).to eq([id])
  end

  it 'IA desligada devolve aviso claro, sem chamar a API' do
    post "#{base}/generate_copy", params: { gancho: 'Oi' }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('IA não configurada')
  end
end
