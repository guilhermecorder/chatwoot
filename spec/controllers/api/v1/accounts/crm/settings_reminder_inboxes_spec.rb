require 'rails_helper'

# item 310: lembrete de confirmação com mais de uma caixa — sai pela caixa em que o paciente já conversa
RSpec.describe 'CRM settings — caixas do lembrete de confirmação', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:google) { create(:inbox, account: account, name: 'GOOGLE') }
  let(:instagram) { create(:inbox, account: account, name: 'INSTAGRAM') }
  let(:outra_conta) { create(:inbox) }

  it 'guarda as outras caixas (só as da conta, sem repetir a padrão)', :aggregate_failures do
    post "/api/v1/accounts/#{account.id}/crm/settings/update_agenda",
         params: { appointment_reminders: { d2: { enabled: true, hour: 10, mode: 'shadow', inbox_id: google.id,
                                                  inbox_ids: [instagram.id, google.id, outra_conta.id, 0] } } },
         headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    d2 = CrmSetting.find_by(account: account).agenda_config.dig('appointment_reminders', 'd2')
    expect(d2['inbox_id']).to eq(google.id)
    expect(d2['inbox_ids']).to eq([instagram.id])
  end

  it 'guarda as colunas do CRM que recebem (só as da conta)', :aggregate_failures do
    pipeline = Crm::Pipeline.create!(account: account, name: 'Funil', position: 1)
    stage = Crm::Stage.create!(pipeline: pipeline, name: 'Agendamento de Consulta', position: 1, color: '#059669')
    post "/api/v1/accounts/#{account.id}/crm/settings/update_agenda",
         params: { appointment_reminders: { d2: { enabled: true, hour: 10, mode: 'shadow', inbox_id: google.id,
                                                  stage_ids: [stage.id, 999_999] } } },
         headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(CrmSetting.find_by(account: account).agenda_config.dig('appointment_reminders', 'd2', 'stage_ids')).to eq([stage.id])
  end

  it 'sem outras caixas, a chave nem é gravada' do
    post "/api/v1/accounts/#{account.id}/crm/settings/update_agenda",
         params: { appointment_reminders: { d2: { enabled: true, hour: 10, mode: 'shadow', inbox_id: google.id } } },
         headers: admin.create_new_auth_token, as: :json

    expect(CrmSetting.find_by(account: account).agenda_config.dig('appointment_reminders', 'd2')).not_to have_key('inbox_ids')
  end
end
