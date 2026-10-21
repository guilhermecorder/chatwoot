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

  # item 314: modelos escolhidos para cada caixa de "também envia por"
  it 'guarda os modelos próprios de cada caixa marcada (e ignora caixa não marcada)', :aggregate_failures do
    tp = { name: 'confirma_ig_paulista', language: 'pt_BR', category: 'UTILITY', processed_params: { body: { '1' => '{{nome}}' } } }
    by_inbox = { instagram.id.to_s => { units: { paulista: { template_params: tp, message_preview: 'IG {{1}}' } },
                                        followup: { template_params: tp.merge(name: 'reforco_ig'), message_preview: 'R' } },
                 outra_conta.id.to_s => { template_params: tp } }
    post "/api/v1/accounts/#{account.id}/crm/settings/update_agenda",
         params: { appointment_reminders: { d2: { enabled: true, hour: 10, mode: 'shadow', inbox_id: google.id,
                                                  inbox_ids: [instagram.id], by_inbox: by_inbox } } },
         headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    saved = CrmSetting.find_by(account: account).agenda_config.dig('appointment_reminders', 'd2', 'by_inbox')
    expect(saved.keys).to eq([instagram.id.to_s])
    expect(saved.dig(instagram.id.to_s, 'units', 'paulista', 'template_params', 'name')).to eq('confirma_ig_paulista')
    expect(saved.dig(instagram.id.to_s, 'followup', 'template_params', 'name')).to eq('reforco_ig')
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

  # 🎯 item 327: modelos personalizados por tipo de atendimento e por médico — no lembrete e em cada caixa
  it 'guarda os modelos personalizados; sem tipo nem médico, ou sem modelo, não entra', :aggregate_failures do
    tp = ->(name) { { name: name, language: 'pt_BR', category: 'UTILITY', processed_params: { body: { '1' => '{{nome}}' } } } }
    variants = [
      { id: 'ret', modality: 'retorno', units: { tatuape: { template_params: tp.call('retorno_tatuape'), message_preview: 'R {{1}}' } },
        followup: { template_params: tp.call('reforco_retorno') } },
      { id: 'rob', doctor: ' Dra. Roberta Negri ', modality: 'inventado', template_params: tp.call('roberta_geral') },
      { id: 'ninguem', units: { paulista: { template_params: tp.call('sem_dono') } } },
      { id: 'vazio', modality: 'exames' }
    ]
    by_inbox = { instagram.id.to_s => { variants: [{ modality: 'pos_op', template_params: tp.call('ig_pos_op') }] } }
    post "/api/v1/accounts/#{account.id}/crm/settings/update_agenda",
         params: { appointment_reminders: { d2: { enabled: true, hour: 10, mode: 'shadow', inbox_id: google.id, inbox_ids: [instagram.id],
                                                  variants: variants, by_inbox: by_inbox } } },
         headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    d2 = CrmSetting.find_by(account: account).agenda_config.dig('appointment_reminders', 'd2')
    expect(d2['variants'].pluck('id')).to eq(%w[ret rob])
    expect(d2['variants'].first).to include('modality' => 'retorno')
    expect(d2['variants'].first.dig('followup', 'template_params', 'name')).to eq('reforco_retorno')
    expect(d2['variants'].last).to include('doctor' => 'Dra. Roberta Negri').and(satisfy { |v| !v.key?('modality') })
    expect(d2.dig('by_inbox', instagram.id.to_s, 'variants').first).to include('modality' => 'pos_op')
  end
end
