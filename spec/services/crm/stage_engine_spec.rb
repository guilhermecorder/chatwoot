require 'rails_helper'

# 🧭 MOTOR POR COLUNA DO CRM (23/11): o mesmo atendente responde com um modelo
# diferente conforme a coluna em que o card do paciente está.
RSpec.describe Crm::StageEngine do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO') }
  let!(:stage_new) { pipeline.stages.create!(name: 'Novos Contatos', position: 0) }
  let!(:stage_budget) { pipeline.stages.create!(name: 'Envio de Orçamento', position: 1) }
  let!(:stage_other) { pipeline.stages.create!(name: 'Consulta Realizada', position: 2) }
  let(:stage_models) { { stage_new.id.to_s => 'gpt-6-luna', stage_budget.id.to_s => 'claude-opus-5-5', 'sem_card' => 'gpt-6.1-terra' } }
  let(:agent) do
    { 'enabled' => true, 'model' => 'claude-sonnet-5', 'inbox_ids' => [inbox.id], 'no_card' => true,
      'stage_ids' => [stage_new.id, stage_budget.id], 'stage_models' => stage_models }
  end
  let(:ai_config) { { 'api_key' => 'sk-ant-teste', 'openai_api_key' => 'sk-openai-teste', 'agents' => { 'atendente_agendamento' => agent } } }
  let!(:settings) { CrmSetting.create!(account: account, ai_config: ai_config) }

  def card_in(stage)
    Crm::Contact.where(contact_id: contact.id).delete_all
    Crm::Contact.create!(contact_id: contact.id, pipeline_id: pipeline.id, stage_id: stage.id) if stage
  end

  def model_now(**)
    Crm::ResponderAgentService.new(conversation: conversation, agent_key: 'atendente_agendamento', **).send(:model)
  end

  describe 'qual modelo responde' do
    it 'cada coluna usa o modelo escolhido para ela', :aggregate_failures do
      card_in(stage_new)
      expect(model_now).to eq('gpt-6-luna')

      card_in(stage_budget)
      expect(model_now).to eq('claude-opus-5-5')
    end

    it 'paciente sem card usa o modelo de "sem card"' do
      card_in(nil)
      expect(model_now).to eq('gpt-6.1-terra')
    end

    it 'coluna sem escolha fica com o modelo do cartão' do
      card_in(stage_other)
      expect(model_now).to eq('claude-sonnet-5')
    end

    it 'sem a chave do fornecedor, cai no modelo do cartão (o atendente não fica mudo)' do
      settings.update!(ai_config: ai_config.except('openai_api_key'))
      card_in(stage_new)
      expect(model_now).to eq('claude-sonnet-5')
    end

    it 'modelo desconhecido gravado na config é ignorado' do
      unknown = { 'stage_models' => { stage_new.id.to_s => 'modelo-que-nao-existe' } }
      settings.update!(ai_config: ai_config.deep_merge('agents' => { 'atendente_agendamento' => unknown }))
      card_in(stage_new)
      expect(model_now).to eq('claude-sonnet-5')
    end

    it 'no 🧪 Testar agente a coluna não manda (vale o seletor do teste)' do
      card_in(stage_new)
      expect(model_now(simulation: true)).to eq('claude-sonnet-5')
    end
  end

  describe '.sanitize' do
    it 'só aceita coluna que o agente lê (e sem_card quando ele atende contato novo); em branco sai', :aggregate_failures do
      raw = { stage_new.id.to_s => ' gpt-6-luna ', stage_budget.id.to_s => '', stage_other.id.to_s => 'claude-opus-5-5', 'sem_card' => 'gpt-6-luna' }
      expect(described_class.sanitize(raw, agent)).to eq(stage_new.id.to_s => 'gpt-6-luna', 'sem_card' => 'gpt-6-luna')
      expect(described_class.sanitize(raw, agent.merge('no_card' => false))).to eq(stage_new.id.to_s => 'gpt-6-luna')
    end
  end

  describe 'tela (CRM → settings)', type: :request do
    let!(:admin) { create(:user, account: account, role: :administrator) }
    let(:base) { "/api/v1/accounts/#{account.id}/crm/settings" }

    it 'devolve as colunas do agente na ordem do funil, com "sem card" na frente', :aggregate_failures do
      get "#{base}/ai_stage_models", params: { agent: 'atendente_agendamento' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['stages'].pluck('name')).to eq(['Sem card ainda (contato novo)', 'Novos Contatos', 'Envio de Orçamento'])
      expect(body['stage_models']).to eq(stage_models)
      expect(body['default_model']).to eq('claude-sonnet-5')
    end

    it 'salva a escolha por coluna e descarta coluna que não é do agente', :aggregate_failures do
      post "#{base}/save_ai_stage_models",
           params: { agent: 'atendente_agendamento',
                     stage_models: { stage_budget.id.to_s => 'claude-opus-5-5', stage_other.id.to_s => 'gpt-6-luna' } },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      saved = settings.reload.ai_config.dig('agents', 'atendente_agendamento', 'stage_models')
      expect(saved).to eq(stage_budget.id.to_s => 'claude-opus-5-5')
    end

    it 'recusa modelo de fornecedor sem chave salva, com mensagem clara', :aggregate_failures do
      settings.update!(ai_config: ai_config.except('openai_api_key'))
      post "#{base}/save_ai_stage_models", params: { agent: 'atendente_agendamento', stage_models: { stage_new.id.to_s => 'gpt-6-luna' } },
                                           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('salve antes a chave')
    end

    it 'só vale para os atendentes do WhatsApp' do
      get "#{base}/ai_stage_models", params: { agent: 'copywriter' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # 🧪🧭 item 405: o teste A/B convive com o motor por coluna, e o lembrete com
  # IA do follow-up sai pelo motor da coluna
  describe 'com teste A/B ligado (item 405)' do
    let(:test_id) { '2026-11-23T10:00:00Z' }

    def with_test(experiment)
      ab = { 'enabled' => true, 'started_at' => test_id, 'inboxes' => { inbox.id.to_s => 'b' } }.merge(experiment)
      settings.update!(ai_config: ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'ab' => ab } }))
    end

    def service
      Crm::ResponderAgentService.new(conversation: conversation, agent_key: 'atendente_agendamento', live: true)
    end

    it 'teste de prompt: a B lê o Roteiro 2 e segue o MESMO mapa de motor da A', :aggregate_failures do
      with_test('script_b' => 'v2')
      card_in(stage_new)

      expect(service.experiment_arm).to eq('b')
      expect(service.script_version).to eq('v2')
      expect(service.send(:model)).to eq('gpt-6-luna')
    end

    it 'teste de cérebro só na recepção: a B troca o motor na coluna escolhida e fica igual à A nas outras', :aggregate_failures do
      with_test('model_b' => 'gpt-6.2-sol', 'stages_b' => [stage_new.id.to_s])

      card_in(stage_new)
      expect(service.send(:model)).to eq('gpt-6.2-sol')
      card_in(stage_budget)
      expect(service.send(:model)).to eq('claude-opus-5-5')
    end

    it 'sem colunas escolhidas, o motor da B vale em todas' do
      with_test('model_b' => 'gpt-6.2-sol')
      card_in(stage_budget)

      expect(service.send(:model)).to eq('gpt-6.2-sol')
    end

    it 'com mapa de colunas, o modelo do cartão na B também é um teste de motor', :aggregate_failures do
      expect(Crm::EngineExperiment.kind({ 'model_b' => 'claude-sonnet-5' }, 'claude-sonnet-5', staged: true)).to eq('motor')
      expect(Crm::EngineExperiment.kind({ 'model_b' => 'claude-sonnet-5', 'script_b' => 'v2' }, 'claude-sonnet-5', staged: true)).to eq('ambos')
    end

    it 'o carimbo guarda a coluna em que a conversa entrou no teste' do
      with_test('script_b' => 'v2')
      card_in(stage_budget)
      Crm::EngineExperiment.track!(conversation, 'atendente_agendamento', settings.reload.ai_config.dig('agents', 'atendente_agendamento'), 'b',
                                   'reply' => true)

      expect(conversation.reload.additional_attributes.dig('cevico_ia_ab', 'atendente_agendamento', 'slot')).to eq(stage_budget.id.to_s)
    end
  end

  describe 'lembrete com IA do follow-up (item 405)' do
    def nudge_model
      Crm::FollowupAiNudgeService.new(conversation: conversation).send(:model)
    end

    it 'sai pelo motor da coluna em que o paciente está', :aggregate_failures do
      card_in(stage_new)
      expect(nudge_model).to eq('gpt-6-luna')

      card_in(stage_budget)
      expect(nudge_model).to eq('claude-opus-5-5')
    end

    it 'coluna sem escolha usa o modelo do cartão "Lembrete com IA"' do
      card_in(stage_other)

      expect(nudge_model).to eq(Crm::AiAgentConfig::RECOMMENDED.dig('followup_ia', 'model') || Crm::AiAgentConfig::DEFAULT_MODEL)
    end

    it 'sem a chave do fornecedor da coluna, cai no modelo do cartão' do
      settings.update!(ai_config: ai_config.except('openai_api_key'))
      card_in(stage_new)

      expect(nudge_model).not_to eq('gpt-6-luna')
    end
  end

  describe 'lista de colunas para a tela' do
    it 'vem na ordem do funil, com "sem card" na frente e o modelo de cada uma' do
      rows = described_class.rows(account, agent)

      expect(rows).to eq([{ slot: 'sem_card', name: 'Sem card ainda (contato novo)', model: 'gpt-6.1-terra' },
                          { slot: stage_new.id.to_s, name: 'Novos Contatos', model: 'gpt-6-luna' },
                          { slot: stage_budget.id.to_s, name: 'Envio de Orçamento', model: 'claude-opus-5-5' }])
    end
  end
end
