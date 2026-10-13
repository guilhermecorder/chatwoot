require 'rails_helper'

# 🛡️ Rodada 6 da auditoria — "Rede de segurança" (#255): só quem EDITA
# "Campanha WhatsApp" cria ou dispara campanha (o atendente, por padrão, só
# vê); e uma clínica não dispara a campanha de outra.
RSpec.describe 'CEVICO campanhas WhatsApp — quem pode criar e disparar', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false).inbox
  end
  let(:label) { account.labels.create!(title: 'reativar') }
  let(:campaign) do
    Crm::Campaign.create!(account: account, inbox: inbox, name: 'Reativação', template_params: { 'name' => 'x' },
                          audience: { 'include_label_ids' => [label.id] })
  end
  let(:base) { "/api/v1/accounts/#{account.id}/crm/campaigns" }
  let(:new_campaign) do
    { name: 'Nova', inbox_id: inbox.id, template_params: { name: 'x' }, audience: { include_label_ids: [label.id] } }
  end

  before { Current.reset }

  it 'atendente sem "editar Campanha WhatsApp" leva 403 ao criar e ao disparar; nada é enfileirado', :aggregate_failures do
    expect do
      post base, params: { campaign: new_campaign }, headers: agent.create_new_auth_token, as: :json
    end.not_to change(Crm::Campaign, :count)
    expect(response).to have_http_status(:forbidden)

    expect do
      post "#{base}/#{campaign.id}/send_now", headers: agent.create_new_auth_token, as: :json
    end.not_to have_enqueued_job(Crm::CampaignRunJob)
    expect(response).to have_http_status(:forbidden)
    expect(campaign.reload).to be_draft

    # mas continua VENDO as campanhas (padrão do catálogo: ver)
    get base, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
  end

  it 'com a concessão "editar", o atendente cria e dispara', :aggregate_failures do
    CrmSetting.find_or_create_by!(account: account)
              .update!(agent_permissions: { 'tree' => { agent.id.to_s => { 'crm.campanhas' => 'edit' } } })

    post base, params: { campaign: new_campaign }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)

    expect do
      post "#{base}/#{campaign.id}/send_now", headers: agent.create_new_auth_token, as: :json
    end.to have_enqueued_job(Crm::CampaignRunJob).with(campaign.id)
    expect(response).to have_http_status(:success)
  end

  it 'atendente de OUTRA conta não enxerga nem dispara a campanha desta conta', :aggregate_failures do
    outra = create(:account)
    intruso = create(:user, account: outra, role: :administrator)

    post "#{base}/#{campaign.id}/send_now", headers: intruso.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    post "/api/v1/accounts/#{outra.id}/crm/campaigns/#{campaign.id}/send_now", headers: intruso.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(campaign.reload).to be_draft
  end
end
