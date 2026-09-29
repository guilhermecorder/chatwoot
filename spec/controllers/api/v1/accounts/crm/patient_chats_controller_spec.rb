require 'rails_helper'

# item 298: abrir a conversa do paciente a partir da Agenda e do Espaço do Paciente
RSpec.describe 'Conversa do paciente (popup)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, name: 'WhatsApp Paulista') }
  let(:contact) { create(:contact, account: account, name: 'Maria', phone_number: '+5511999990000') }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/patient_chat" }

  def fetch(user, params)
    get url, params: params, headers: user.create_new_auth_token, as: :json
    response.parsed_body
  end

  it 'devolve a conversa mais recente e o card do CRM', :aggregate_failures do
    pipeline = Crm::Pipeline.create!(account: account, name: 'CEVICO')
    stage = Crm::Stage.create!(pipeline: pipeline, name: 'Consulta Confirmada', position: 1)
    card = Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage)
    create(:conversation, account: account, inbox: inbox, contact: contact, last_activity_at: 3.days.ago)
    recent = create(:conversation, account: account, inbox: inbox, contact: contact, last_activity_at: 1.hour.ago)

    body = fetch(admin, contact_id: contact.id)

    expect(body).to include('found' => true, 'has_conversation' => true)
    expect(body['card']).to include('id' => card.id, 'contact_id' => contact.id, 'last_conversation_id' => recent.id,
                                    'stage_id' => stage.id)
    expect(body['card']['last_conversation']).to include('inbox_name' => 'WhatsApp Paulista')
    expect(body['stages'].pluck('name')).to eq(['Consulta Confirmada'])
  end

  it 'acha o paciente pelo telefone quando o agendamento não tem cadastro ligado' do
    create(:conversation, account: account, inbox: inbox, contact: contact)

    expect(fetch(admin, phone: '(11) 99999-0000')['card']).to include('contact_id' => contact.id)
  end

  it 'paciente sem conversa e sem card: avisa para começar uma conversa nova', :aggregate_failures do
    body = fetch(admin, contact_id: contact.id)

    expect(body).to include('found' => true, 'has_conversation' => false)
    expect(body['card']).to include('id' => nil, 'last_conversation_id' => nil)
  end

  it 'agente só enxerga conversa das caixas em que ele está', :aggregate_failures do
    create(:conversation, account: account, inbox: inbox, contact: contact)
    expect(fetch(agent, contact_id: contact.id)['has_conversation']).to be(false)

    create(:inbox_member, inbox: inbox, user: agent)
    expect(fetch(agent, contact_id: contact.id)['has_conversation']).to be(true)
  end

  it 'sem paciente encontrado não quebra' do
    expect(fetch(admin, phone: '000')).to include('found' => false)
  end
end
