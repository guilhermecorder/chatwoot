require 'rails_helper'

# 🤖📞 item 333 (auditoria 07/10): "Agendar para…" nasce AGENDADA e a hora digitada é de São Paulo
RSpec.describe 'CEVICO call campaigns — agendamento', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/call_campaigns" }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:payload) { { name: 'Reativar', objective: 'reativar', audience: { include_label_ids: [1] }, daily_cap: 10, concurrency: 1 } }

  it 'agendar cria a campanha já agendada, na hora de São Paulo', :aggregate_failures do
    when_local = (tz.now + 2.days).change(hour: 10, min: 0)

    post base, params: { call_campaign: payload.merge(scheduled_at: when_local.strftime('%Y-%m-%dT%H:%M')) },
               headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:created)
    campaign = Crm::CallCampaign.find(response.parsed_body['id'])
    expect(campaign).to be_scheduled
    expect(campaign.scheduled_at.in_time_zone(tz).strftime('%H:%M')).to eq('10:00')
  end

  it 'data no passado ou inválida é recusada (não começa a ligar na hora)', :aggregate_failures do
    post base, params: { call_campaign: payload.merge(scheduled_at: '2020-01-01T10:00') }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    post base, params: { call_campaign: payload.merge(scheduled_at: '31/02 sei lá') }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Crm::CallCampaign.where(account_id: account.id).count).to eq(0)
  end

  it 'sem data continua rascunho' do
    post base, params: { call_campaign: payload.merge(scheduled_at: nil) }, headers: admin.create_new_auth_token, as: :json

    expect(Crm::CallCampaign.find(response.parsed_body['id'])).to be_draft
  end
end
