require 'rails_helper'

# 🧭 Rodada 5 da auditoria (#196): mover o card "direto da conversa" nunca
# troca o funil do card. Antes, escolher uma coluna de outro funil fazia
# card.update!(pipeline_id: ...) — paciente da CEVICO virava "parceiro" (sem
# IA nem automação) ou o índice único contato+funil estourava (422).
RSpec.describe 'CRM conversation_summary — move_stage', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/conversation_summary" }

  let(:cevico) { Crm::Pipeline.create!(account: account, name: 'CEVICO', position: 0) }
  let(:lead) { Crm::Stage.create!(pipeline: cevico, name: 'Lead', position: 0) }
  let(:budget) { Crm::Stage.create!(pipeline: cevico, name: 'Orçamento', position: 1) }
  let(:partner) { Crm::Pipeline.create!(account: account, name: 'Parceiros', position: 1) }
  let(:partner_stage) { Crm::Stage.create!(pipeline: partner, name: 'Parceiro', position: 0) }
  let(:partner_other) { Crm::Stage.create!(pipeline: partner, name: 'Parceiro 2', position: 1) }
  let!(:card) { Crm::Contact.create!(contact: contact, pipeline: cevico, stage: lead) }

  def move!(stage)
    post "#{base}/move_stage", params: { conversation_id: conversation.display_id, stage_id: stage.id },
                               headers: agent_user.create_new_auth_token, as: :json
  end

  it 'coluna do mesmo funil: move o card e dispara "entrou na coluna"', :aggregate_failures do
    automation = Crm::Automation.create!(stage: budget, name: 'Entrou', trigger_type: 'card_entered', action_type: 'webhook',
                                         delay_minutes: 0, active: true, action_config: { 'webhook_url' => 'https://exemplo.test' })
    clear_enqueued_jobs

    move!(budget)

    expect(response).to have_http_status(:success)
    expect(card.reload).to have_attributes(stage_id: budget.id, pipeline_id: cevico.id)
    expect(enqueued_jobs.count { |j| j['job_class'] == 'CrmAutomationFireJob' && j['arguments'].first == automation.id }).to eq(1)
  end

  it 'coluna de OUTRO funil onde o contato não tem card: recusa e o card fica no funil da CEVICO', :aggregate_failures do
    move!(partner_stage)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(card.reload).to have_attributes(stage_id: lead.id, pipeline_id: cevico.id)
    expect(Crm::Contact.where(contact_id: contact.id).pluck(:pipeline_id)).to eq([cevico.id])
  end

  it 'coluna de OUTRO funil onde o contato já tem card: move ESSE card (sem estourar o índice único)', :aggregate_failures do
    other_card = Crm::Contact.create!(contact: contact, pipeline: partner, stage: partner_stage)

    move!(partner_other)

    expect(response).to have_http_status(:success)
    expect(other_card.reload).to have_attributes(stage_id: partner_other.id, pipeline_id: partner.id)
    expect(card.reload).to have_attributes(stage_id: lead.id, pipeline_id: cevico.id)
  end
end
