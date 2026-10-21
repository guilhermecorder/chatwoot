require 'rails_helper'

# 🔐 Auditoria 10/2026 (achado #307, LGPD): o Espaço do Paciente entrega
# respostas de formulário só a quem tem acesso clínico, e dinheiro
# (fechamento, valor do card) só a admin ou a quem tem o Financeiro
RSpec.describe 'Espaço do Paciente — dados sensíveis', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:contact) do
    create(:contact, account: account, name: 'Maria', phone_number: '+5511999990000',
                     additional_attributes: {
                       'surgery_closing' => { 'at' => 1.day.ago.iso8601, 'value' => 5000, 'payment' => 'pix', 'note' => 'fechou no cartão' },
                       'nps' => { 'at' => 2.days.ago.iso8601, 'score' => 9, 'comment' => 'minha catarata melhorou' }
                     })
  end
  let(:form) { Crm::Form.create!(account: account, name: 'Pré-consulta', questions: [], funnel_stats: {}, ai_insight: {}) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/patients/#{contact.id}" }

  before do
    CrmSetting.create!(account: account)
    pipeline = Crm::Pipeline.create!(account: account, name: 'CEVICO')
    stage = Crm::Stage.create!(pipeline: pipeline, name: 'Fechamento', position: 1)
    Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage, value: 4500)
    Crm::FormResponse.create!(account: account, form: form, contact: contact, completed_at: 1.hour.ago,
                              answers: [{ 'id' => 'q1', 'label' => 'Usa colírio?', 'type' => 'text', 'value' => 'Sim, todo dia' }])
  end

  def fetch(user)
    get url, headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body
  end

  def event(body, type)
    body['timeline'].find { |e| e['type'] == type }
  end

  it 'atendente sem concessão: sem respostas, sem valor de fechamento, sem valor do card', :aggregate_failures do
    body = fetch(agent_user)
    expect(event(body, 'formulario')).to include('form' => 'Pré-consulta', 'restricted' => true, 'answers' => [])
    fechamento = event(body, 'fechamento')
    expect(fechamento).to be_present
    expect(fechamento.keys).not_to include('value', 'payment', 'note')
    expect(body['indicators']).to include('value' => nil, 'payment' => nil)
    expect(body['identity']['cards'].first['value']).to be_nil
    expect(body['identity']['money_restricted']).to be(true)
    # comentário livre do NPS: só com acesso clínico (lado mais fechado até o Guilherme decidir)
    expect(event(body, 'nps')).to include('score' => 9, 'comment' => nil, 'comment_restricted' => true)
    expect(response.body).not_to include('todo dia', 'pix', 'fechou no cartão', 'catarata melhorou')
  end

  it 'admin vê tudo', :aggregate_failures do
    body = fetch(admin)
    expect(event(body, 'formulario')['answers'].first['value']).to eq('Sim, todo dia')
    expect(event(body, 'nps')).to include('comment' => 'minha catarata melhorou', 'comment_restricted' => false)
    expect(body['identity']['money_restricted']).to be(false)
    expect(event(body, 'fechamento')).to include('value' => 5000, 'payment' => 'pix', 'note' => 'fechou no cartão')
    expect(body['indicators']).to include('value' => 5000, 'payment' => 'pix')
    expect(body['identity']['cards'].first['value']).to be_present
  end

  it 'equipe com team_view lê as respostas; quem tem o Financeiro vê o dinheiro', :aggregate_failures do
    CrmSetting.find_by!(account: account).update!(agenda_config: { 'clinical_access' => { 'doctor_user_ids' => [], 'team_view' => true } })
    body = fetch(agent_user)
    expect(event(body, 'formulario')).to include('restricted' => false)
    expect(event(body, 'formulario')['answers'].size).to eq(1)
    expect(event(body, 'nps')['comment']).to eq('minha catarata melhorou')
    expect(body['indicators']['value']).to be_nil

    CrmSetting.find_by!(account: account).update!(agent_permissions: { 'tree' => { agent_user.id.to_s => { 'financeiro' => 'view' } } })
    body = fetch(agent_user)
    expect(body['indicators']).to include('value' => 5000, 'payment' => 'pix')
    expect(event(body, 'fechamento')).to include('value' => 5000)
    expect(body['identity']['cards'].first['value']).to be_present
  end
end
