require 'rails_helper'

# 🛡️ auditoria 10/10 (#426): "Reenviar" na Fila de hoje não pode mandar
# mensagem de consulta cancelada/remarcada nem de um dia que já passou.
RSpec.describe 'CEVICO Jornada — reenviar', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:tz) { Crm::Journey::Settings::TZ }
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }
  let(:contact) { create(:contact, account: account, name: 'Maria Teste', phone_number: '+5511988887777') }
  let(:message) do
    Crm::JourneyMessage.create!(account: account, name: 'Consulta hoje', step: 'consulta', inbox: inbox,
                                trigger: { 'kind' => 'appointment', 'offset_days' => 0, 'at' => '09:00' },
                                content: { 'mode' => 'text', 'text' => 'Olá {{primeiro_nome}}, sua consulta é hoje às {{hora}}.' })
  end
  let(:task) do
    account.tasks.create!(task_type: 'consulta', modality: 'avaliacao', unit: 'paulista', creator: admin,
                          title: 'Consulta: Maria', due_at: tz.local(2026, 9, 18, 15, 0), contact: contact)
  end
  let!(:send) do
    Crm::JourneySend.create!(account: account, journey_message: message, contact: contact, source: task,
                             event_key: "task:#{task.id}", scheduled_for: tz.local(2026, 9, 18, 9, 0), status: 'expired',
                             error: 'A hora passou sem envio')
  end

  before { CrmSetting.create!(account: account, agenda_config: {}) }

  def retry!
    post "#{base}/journey_sends/#{send.id}/retry", headers: admin.create_new_auth_token, as: :json
  end

  it 'recusa reenviar no dia seguinte um envio que expirou (sairia com a data velha)', :aggregate_failures do
    travel_to(tz.local(2026, 9, 19, 10, 0)) { retry! }
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['error']).to include('era para 18/09')
    expect(send.reload.status).to eq('expired')
  end

  it 'recusa reenviar quando a consulta foi para a Lixeira', :aggregate_failures do
    task.to_trash!(by: admin)
    travel_to(tz.local(2026, 9, 18, 10, 0)) { retry! }
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['error']).to include('consulta foi cancelada')
    expect(send.reload.status).to eq('expired')
  end

  it 'deixa reenviar no mesmo dia com a consulta de pé (aqui falha só pela janela de 24h)', :aggregate_failures do
    travel_to(tz.local(2026, 9, 18, 10, 0)) { retry! }
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['outcome']).to eq('failed')
    expect(send.reload.error).to include('janela de 24h')
  end

  describe 'mensagem da véspera ("sua consulta é amanhã") reenviada no dia da consulta' do
    let(:message) do
      Crm::JourneyMessage.create!(account: account, name: 'Consulta amanhã', step: 'consulta', inbox: inbox,
                                  trigger: { 'kind' => 'appointment', 'offset_days' => -1, 'at' => '09:00' },
                                  content: { 'mode' => 'text', 'text' => 'Olá {{primeiro_nome}}, sua consulta é amanhã às {{hora}}.' })
    end
    let!(:send) do
      Crm::JourneySend.create!(account: account, journey_message: message, contact: contact, source: task,
                               event_key: "task:#{task.id}", scheduled_for: tz.local(2026, 9, 17, 9, 0), status: 'expired',
                               error: 'A hora passou sem envio')
    end

    it 'recusa na porta com o motivo certo e mantém o "Expirou"', :aggregate_failures do
      travel_to(tz.local(2026, 9, 18, 10, 0)) { retry! }
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to include('era para 17/09')
      expect(send.reload.status).to eq('expired')
      expect(send.error).to eq('A hora passou sem envio')
    end
  end
end
