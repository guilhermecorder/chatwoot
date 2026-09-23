require 'rails_helper'

# 🤖 item 207 (23/09): botão "ligar/desligar a IA para esta pessoa" dentro da conversa
RSpec.describe 'CRM conversation_summary — toggle_responder', type: :request do
  let(:account) { create(:account) }
  let(:agent_user) { create(:user, account: account, role: :agent, name: 'Vaneide') }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/conversation_summary" }

  before do
    stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', true)
    CrmSetting.create!(account: account, ai_config: {
                         'agents' => { 'atendente_agendamento' => { 'enabled' => true, 'mode' => 'live', 'inbox_ids' => [inbox.id] } }
                       })
  end

  it 'desliga e liga o Atendente nesta conversa, com nota interna dizendo quem foi', :aggregate_failures do
    post "#{base}/toggle_responder", params: { conversation_id: conversation.display_id, paused: true },
                                     headers: agent_user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    rs = response.parsed_body['responder']
    expect(rs).to include('available' => true, 'live' => true, 'paused' => true, 'reason' => 'botao', 'by' => 'Vaneide')
    expect(rs['reason_text']).to eq('desligado pelo botão')
    state = conversation.reload.additional_attributes['cevico_atendente_wa']
    expect(state).to include('paused' => true, 'reason' => 'botao', 'by' => 'Vaneide')
    expect(conversation.messages.where(message_type: :activity).last.content).to include('DESLIGADO').and include('Vaneide')

    post "#{base}/toggle_responder", params: { conversation_id: conversation.display_id, paused: false },
                                     headers: agent_user.create_new_auth_token, as: :json
    expect(response.parsed_body['responder']).to include('paused' => false)
    expect(conversation.reload.additional_attributes['cevico_atendente_wa']).to eq({})
    expect(conversation.messages.where(message_type: :activity).last.content).to include('LIGADO')
  end

  it 'o resumo da conversa traz o estado do Atendente (available=false em caixa sem agente)' do
    other = create(:conversation, account: account, inbox: create(:inbox, account: account), contact: contact)
    get base, params: { conversation_id: other.display_id }, headers: agent_user.create_new_auth_token, as: :json
    expect(response.parsed_body['responder']).to include('available' => false, 'paused' => false)
  end
end
