require 'rails_helper'

# 📣 item 380 (03/11): mensagens prontas da Reativação de fim de ano — o YAML
# é o original; a edição da conta fica por cima (por id) e "restaurar" apaga
RSpec.describe 'CEVICO reativação de fim de ano — mensagens prontas', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/settings" }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO', position: 0) }
  let!(:stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Não Fechou Ainda', position: 2) }

  def publico(body, key)
    body['publicos'].find { |p| p['key'] == key }
  end

  it 'devolve os públicos em ordem de prioridade, 3 mensagens por frente e a coluna da casa', :aggregate_failures do
    2.times { Crm::Contact.create!(contact: create(:contact, account: account), pipeline: pipeline, stage: stage) }

    get "#{base}/reactivation_messages", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['publicos'].map { |p| p['prioridade'] }).to eq([1, 2, 3, 4, 5, 6])
    expect(body['frentes'].map { |f| f['key'] }).to eq(%w[refrativa lentes catarata])
    body['publicos'].each do |p|
      expect(p['mensagens'].keys).to match_array(%w[refrativa lentes catarata])
      expect(p['mensagens'].values.map(&:size)).to eq([3, 3, 3])
    end
    expect(body.dig('totais', 'mensagens')).to eq(54)
    expect(body.dig('totais', 'editadas')).to eq(0)
    expect(publico(body, 'nao_fechou')['funil']).to include('stage_id' => stage.id, 'stage_name' => 'Não Fechou Ainda', 'cards' => 2)
    expect(publico(body, 'novos')['funil']).to be_nil
  end

  it 'atendente comum (só vê campanhas) lê, mas não edita' do
    get "#{base}/reactivation_messages", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)

    post "#{base}/update_reactivation_message", params: { id: 'p1-refrativa-1', texto: 'Oi' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'edita, marca como editada e restaurar volta ao original', :aggregate_failures do
    post "#{base}/update_reactivation_message",
         params: { id: 'p1-refrativa-1', texto: '  Oi, {{nome}}! Texto novo.  ', titulo: 'Título novo' },
         headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    msg = response.parsed_body['message']
    expect(msg).to include('id' => 'p1-refrativa-1', 'texto' => 'Oi, {{nome}}! Texto novo.', 'titulo' => 'Título novo', 'editado' => true)
    expect(msg['editado_por']).to eq(admin.name)
    expect(msg['original']).to start_with('Oi, {{nome}}! Aqui é da CEVICO.')
    expect(CrmSetting.find_by(account: account).agenda_config.dig('reactivation_messages', 'p1-refrativa-1', 'por')).to eq(admin.id)

    get "#{base}/reactivation_messages", headers: admin.create_new_auth_token, as: :json
    body = response.parsed_body
    expect(body.dig('totais', 'editadas')).to eq(1)
    expect(publico(body, 'nao_fechou').dig('mensagens', 'refrativa', 0, 'texto')).to eq('Oi, {{nome}}! Texto novo.')

    post "#{base}/update_reactivation_message", params: { id: 'p1-refrativa-1', reset: 1 }, headers: admin.create_new_auth_token, as: :json
    msg = response.parsed_body['message']
    expect(msg['editado']).to be(false)
    expect(msg['texto']).to eq(msg['original'])
    expect(msg['titulo']).to eq('Fechar o ano enxergando')
    expect(CrmSetting.find_by(account: account).agenda_config['reactivation_messages']).to eq({})
  end

  it 'recusa id desconhecido e texto vazio ou longo demais', :aggregate_failures do
    post "#{base}/update_reactivation_message", params: { id: 'nada', texto: 'Oi' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)

    post "#{base}/update_reactivation_message", params: { id: 'p6-catarata-3', texto: '   ' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    post "#{base}/update_reactivation_message", params: { id: 'p6-catarata-3', texto: 'a' * 1501 }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
