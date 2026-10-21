require 'rails_helper'

# 📊 Auditoria 12/10 — Rodada 5 "Números certos" (#385): o Dashboard de
# Campanhas tinha UM contador só para "Cirurgias realizadas" e "% cirurgias
# agendadas", e ele pegava qualquer coluna com "cirurgia" no nome (inclusive
# "Indicação de Cirurgia" e "Cirurgia Agendada"). Agora são dois números:
#   agendadas  = entrou em "Cirurgia Agendada" (ou já chegou em "Cirurgia Realizada")
#   realizadas = entrou em "Cirurgia Realizada"
# sempre fora pós-operatório, indicação e carga em massa (item 309).
RSpec.describe 'CEVICO Dashboard de Campanhas — cirurgias agendadas × realizadas', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false).inbox
  end
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil', position: 1) }
  let(:stages) do
    ['Envio de Orçamento', 'Agendamento de Consulta', 'Indicação de Cirurgia', 'Cirurgia Agendada',
     'Cirurgia Realizada', 'Pós-operatório de Cirurgia'].each_with_index.to_h do |name, i|
      [name, Crm::Stage.create!(pipeline: pipeline, name: name, position: i + 1, color: '#2563EB')]
    end
  end
  let(:started_at) { 3.days.ago }
  let(:campaign) do
    Crm::Campaign.create!(account: account, inbox: inbox, name: 'Reativação', template_params: { 'name' => 'x' },
                          status: :completed, started_at: started_at)
  end

  before { Current.reset }

  # destinatário da campanha com cartão no funil (sem o histórico que o
  # cartão grava ao nascer — o teste escreve o histórico que quer)
  def recipient(name)
    contact = create(:contact, account: account, name: name)
    Crm::CampaignContact.create!(campaign: campaign, contact: contact, sent_at: started_at)
    card = Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stages['Envio de Orçamento'])
    Crm::StageLog.where(crm_contact_id: card.id).delete_all
    card
  end

  def enter(card, stage_name, at: 1.day.ago, event_type: 'entered')
    stage = stages[stage_name]
    Crm::StageLog.create!(crm_contact: card, stage_id: stage.id, stage_name: stage.name, event_type: event_type, entered_at: at)
  end

  it 'separa agendadas de realizadas, cada uma com o seu %, e ignora indicação, pós-op e carga em massa', :aggregate_failures do
    enter(recipient('Ana Indicada'), 'Indicação de Cirurgia')
    enter(recipient('Bia Agendou'), 'Cirurgia Agendada')
    operou = recipient('Caio Operou')
    enter(operou, 'Cirurgia Agendada', at: 2.days.ago)
    enter(operou, 'Cirurgia Realizada')
    enter(operou, 'Pós-operatório de Cirurgia')
    enter(recipient('Duda Carga'), 'Cirurgia Realizada', event_type: 'bulk')
    enter(recipient('Eva Antes'), 'Cirurgia Realizada', at: started_at - 1.day) # antes do disparo

    get "/api/v1/accounts/#{account.id}/crm/campaigns_dashboard", params: { period: 30 }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    totals = response.parsed_body['totals']
    expect(totals['sent']).to eq(5)
    # antes do conserto: 4 "cirurgias realizadas" (Ana, Bia, Caio e a carga da Duda)
    expect(totals['cirurgias_agendadas']).to eq(2)          # Bia + Caio
    expect(totals['cirurgias_agendadas_rate']).to eq(40.0)
    expect(totals['cirurgias_realizadas']).to eq(1)         # só o Caio
    expect(totals['cirurgias_realizadas_rate']).to eq(20.0)
    # a chave antiga segue = realizadas (aba aberta antes da atualização)
    expect(totals['cirurgias']).to eq(1)

    row = response.parsed_body['campaigns'].first
    expect(row).to include('cirurgias_agendadas' => 2, 'cirurgias_realizadas' => 1)
  end

  it 'quem foi direto para "Cirurgia Realizada" também conta como agendada (a realizada cabe na agendada)', :aggregate_failures do
    enter(recipient('Fábio Direto'), 'Cirurgia Realizada')

    get "/api/v1/accounts/#{account.id}/crm/campaigns_dashboard", params: { period: 30 }, headers: admin.create_new_auth_token, as: :json

    totals = response.parsed_body['totals']
    expect(totals['cirurgias_agendadas']).to eq(1)
    expect(totals['cirurgias_realizadas']).to eq(1)
  end
end
