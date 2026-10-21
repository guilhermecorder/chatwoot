require 'rails_helper'

# 🤖 Item 315: caixas/colunas do robô e a prévia da cutucada da IA
RSpec.describe 'Robôs de follow-up — caixas, colunas e prévia da IA', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, name: 'GOOGLE') }
  # a prévia só olha caixas de WhatsApp
  let(:whatsapp) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
  end
  let(:outra_conta) { create(:inbox) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil', position: 1) }
  let(:stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Envio de Orçamento', position: 1, color: '#059669') }

  it 'guarda as caixas e colunas (só as da conta) e a etapa de IA', :aggregate_failures do
    post "/api/v1/accounts/#{account.id}/crm/followup_bots",
         params: { followup_bot: { name: 'Robô 24h', inbox_ids: [inbox.id, outra_conta.id], stage_ids: [stage.id, 999_999],
                                   steps: [{ delay_value: 24, delay_unit: 'hours', kind: 'ai', message: '',
                                             ai_instructions: 'lembrar do orçamento' }] } },
         headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    bot = Crm::FollowupBot.find(response.parsed_body['id'])
    expect(bot.inbox_ids).to eq([inbox.id])
    expect(bot.stage_ids).to eq([stage.id])
    expect(bot.steps.first).to include('kind' => 'ai', 'ai_instructions' => 'lembrar do orçamento')
    expect(response.parsed_body).to include('inbox_ids' => [inbox.id], 'stage_ids' => [stage.id])
  end

  it 'as fichas zeram a caixa única antiga (ela não segue valendo escondida)' do
    bot = Crm::FollowupBot.create!(account: account, name: 'Antigo', inbox_id: inbox.id, sender: admin,
                                   steps: [{ 'delay_value' => 1, 'delay_unit' => 'hours', 'message' => 'oi' }])

    put "/api/v1/accounts/#{account.id}/crm/followup_bots/#{bot.id}",
        params: { followup_bot: { name: 'Antigo', inbox_ids: [] } }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(bot.reload.inbox_id).to be_nil
    expect(bot.acting_inbox_ids).to eq([])
  end

  it 'lista na coluna o robô global que marcou aquela coluna' do
    global = Crm::FollowupBot.create!(account: account, name: 'Global', stage_ids: [stage.id], sender: admin,
                                      steps: [{ 'delay_value' => 1, 'delay_unit' => 'hours', 'message' => 'oi' }])
    Crm::FollowupBot.create!(account: account, name: 'Fora', sender: admin,
                             steps: [{ 'delay_value' => 1, 'delay_unit' => 'hours', 'message' => 'oi' }])

    get "/api/v1/accounts/#{account.id}/crm/followup_bots", params: { stage_id: stage.id }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body.pluck('id')).to eq([global.id])
  end

  it 'prévia: respeita a cerca dos parceiros (paciente do Oftalmofácil nunca passa por IA)', :aggregate_failures do
    parceiro = create(:contact, account: account, name: 'Do Oftalmofacil')
    parceiro.add_labels(['of_agenda']) # etiqueta de parceiro (prefixo of_)
    conv_parceiro = create(:conversation, account: account, inbox: whatsapp, contact: parceiro)
    conv_parceiro.update!(last_activity_at: 10.minutes.ago)
    allow(Crm::FollowupAiNudgeService).to receive(:new)
      .and_return(instance_double(Crm::FollowupAiNudgeService, call: { text: 'x', reason: 'y' }))

    post "/api/v1/accounts/#{account.id}/crm/followup_bots/ai_preview",
         params: { inbox_ids: [whatsapp.id], ai_instructions: 'lembrar' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity) # só havia a conversa do parceiro
    expect(Crm::FollowupAiNudgeService).not_to have_received(:new)
  end

  it 'prévia: usa a conversa recente mais nova das caixas e nada é enviado', :aggregate_failures do
    conv = create(:conversation, account: account, inbox: whatsapp, contact: create(:contact, account: account, name: 'Ana'))
    conv.update!(last_activity_at: 1.hour.ago)
    ia = instance_double(Crm::FollowupAiNudgeService, call: { text: 'Oi Ana, ficou alguma dúvida?', reason: 'retoma' })
    allow(Crm::FollowupAiNudgeService).to receive(:new).and_return(ia)

    expect do
      post "/api/v1/accounts/#{account.id}/crm/followup_bots/ai_preview",
           params: { inbox_ids: [whatsapp.id], ai_instructions: 'lembrar', delay_value: 24, delay_unit: 'hours' },
           headers: admin.create_new_auth_token, as: :json
    end.not_to change(Message, :count)

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('text' => 'Oi Ana, ficou alguma dúvida?', 'conversation_id' => conv.id, 'contact_name' => 'Ana')
    expect(Crm::FollowupAiNudgeService).to have_received(:new)
      .with(conversation: conv, step: hash_including('kind' => 'ai', 'ai_instructions' => 'lembrar'))
  end
end
