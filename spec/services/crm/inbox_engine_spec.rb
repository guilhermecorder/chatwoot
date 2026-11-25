require 'rails_helper'

# 📥 MOTOR POR CAIXA (item 416, 25/11): uma caixa de entrada com motor, esforço
# e Roteiro próprios no mesmo atendente, sem mexer nas outras caixas.
RSpec.describe Crm::InboxEngine do
  let(:account) { create(:account) }
  let(:inbox_test) { create(:inbox, account: account, name: 'CONFIRMAÇÃO DE CONSULTA') }
  let(:inbox_other) { create(:inbox, account: account, name: 'INSTAGRAM 2') }
  let(:inbox_outside) { create(:inbox, account: account, name: 'Oftalmofacil') }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999990001') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox_test, contact: contact) }
  let(:other_conversation) { create(:conversation, account: account, inbox: inbox_other, contact: contact) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO') }
  let!(:stage_new) { pipeline.stages.create!(name: 'Novos Contatos', position: 0) }
  let!(:stage_budget) { pipeline.stages.create!(name: 'Envio de Orçamento', position: 1) }
  let(:own) { { inbox_test.id.to_s => { 'model' => 'gpt-6-luna', 'effort' => 'high', 'script' => 'v2' } } }
  let(:agent) do
    { 'enabled' => true, 'model' => 'claude-sonnet-5', 'effort' => 'medium', 'inbox_ids' => [inbox_test.id, inbox_other.id],
      'no_card' => true, 'stage_ids' => [stage_new.id, stage_budget.id],
      'stage_models' => { stage_new.id.to_s => 'gpt-6-luna', stage_budget.id.to_s => 'claude-sonnet-5', 'sem_card' => 'gpt-6-luna' },
      'inbox_engines' => own }
  end
  let(:ai_config) { { 'api_key' => 'sk-ant-teste', 'openai_api_key' => 'sk-openai-teste', 'agents' => { 'atendente_agendamento' => agent } } }
  let!(:settings) { CrmSetting.create!(account: account, ai_config: ai_config) }

  def card_in(stage)
    Crm::Contact.where(contact_id: contact.id).delete_all
    Crm::Contact.create!(contact_id: contact.id, pipeline_id: pipeline.id, stage_id: stage.id) if stage
  end

  def service(conv = conversation, **)
    Crm::ResponderAgentService.new(conversation: conv, agent_key: 'atendente_agendamento', live: true, **)
  end

  def with_agent(changes)
    settings.update!(ai_config: ai_config.deep_merge('agents' => { 'atendente_agendamento' => changes }))
  end

  describe 'na caixa com motor próprio' do
    it 'responde com o motor da caixa em TODAS as colunas, até onde o mapa manda o Sonnet', :aggregate_failures do
      card_in(stage_new)
      expect(service.send(:model)).to eq('gpt-6-luna')
      card_in(stage_budget)
      expect(service.send(:model)).to eq('gpt-6-luna')
      card_in(nil)
      expect(service.send(:model)).to eq('gpt-6-luna')
    end

    it 'usa o esforço e o Roteiro da caixa', :aggregate_failures do
      card_in(stage_budget)
      expect(service.send(:effort)).to eq('high')
      expect(service.script_version).to eq('v2')
    end

    it 'vence o teste A/B: a caixa na variante B com outro motor continua com o motor e o Roteiro da caixa', :aggregate_failures do
      with_agent('ab' => { 'enabled' => true, 'started_at' => '2026-11-24T03:02:24Z', 'model_b' => 'gpt-6.1-terra', 'script_b' => 'v1',
                           'inboxes' => { inbox_test.id.to_s => 'b', inbox_other.id.to_s => 'b' } })
      card_in(stage_budget)

      expect(service.experiment_arm).to eq('b')
      expect(service.send(:model)).to eq('gpt-6-luna')
      expect(service.script_version).to eq('v2')
    end

    it 'campo em branco segue o caminho de sempre (só o Roteiro próprio, motor do mapa e esforço do cartão)', :aggregate_failures do
      only_script = ai_config.deep_dup
      only_script['agents']['atendente_agendamento']['inbox_engines'] = { inbox_test.id.to_s => { 'script' => 'v2' } }
      settings.update!(ai_config: only_script)
      card_in(stage_budget)

      expect(service.send(:model)).to eq('claude-sonnet-5')
      expect(service.send(:effort)).to eq('medium')
      expect(service.script_version).to eq('v2')
    end

    it 'sem a chave do fornecedor do motor da caixa, cai no caminho de sempre (nunca fica mudo)' do
      settings.update!(ai_config: ai_config.except('openai_api_key'))
      card_in(stage_budget)

      expect(service.send(:model)).to eq('claude-sonnet-5')
    end

    it 'no 🧪 Testar agente a caixa não manda (vale o seletor do teste)', :aggregate_failures do
      card_in(stage_budget)
      simulated = service(simulation: true, script_version: 'v1')

      expect(simulated.send(:model)).to eq('claude-sonnet-5')
      expect(simulated.script_version).to eq('v1')
    end
  end

  describe 'nas outras caixas' do
    it 'nada muda: mapa por coluna, esforço do cartão e Roteiro oficial', :aggregate_failures do
      card_in(stage_budget)
      other = service(other_conversation)

      expect(other.send(:model)).to eq('claude-sonnet-5')
      expect(other.send(:effort)).to eq('medium')
      expect(other.script_version).to eq('v1')
    end
  end

  describe 'lembrete com IA do follow-up' do
    it 'na caixa com motor próprio sai por ele, mesmo na coluna do Sonnet', :aggregate_failures do
      card_in(stage_budget)
      expect(Crm::StageEngine.owner_model_for(conversation, settings.reload.ai_config)).to eq('gpt-6-luna')
      expect(Crm::StageEngine.owner_model_for(other_conversation, settings.ai_config)).to eq('claude-sonnet-5')
    end
  end

  describe '.sanitize' do
    it 'só caixa que o agente lê, só modelo reconhecido, esforço da lista e Roteiro v1/v2; caixa vazia sai' do
      raw = {
        inbox_test.id.to_s => { 'model' => ' gpt-6-luna ', 'effort' => 'alto', 'script' => 'v2' },
        inbox_other.id.to_s => { 'model' => 'modelo-que-nao-existe', 'effort' => '', 'script' => 'v9' },
        inbox_outside.id.to_s => { 'model' => 'gpt-6-luna' }
      }

      expect(described_class.sanitize(raw, agent)).to eq(inbox_test.id.to_s => { 'model' => 'gpt-6-luna', 'script' => 'v2' })
    end
  end

  describe 'tela (CRM → settings)', type: :request do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let!(:admin) { create(:user, account: account, role: :administrator) }
    let(:base) { "/api/v1/accounts/#{account.id}/crm/settings" }

    it 'devolve as caixas do agente e o motor de cada uma', :aggregate_failures do
      get "#{base}/ai_stage_models", params: { agent: 'atendente_agendamento' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['inboxes'].pluck('name')).to contain_exactly('CONFIRMAÇÃO DE CONSULTA', 'INSTAGRAM 2')
      expect(body['inbox_engines']).to eq(own)
      expect(body['default_effort']).to eq('medium')
    end

    it 'salvar só as caixas não apaga o motor por coluna', :aggregate_failures do
      post "#{base}/save_ai_stage_models",
           params: { agent: 'atendente_agendamento', part: 'inbox',
                     inbox_engines: { inbox_other.id.to_s => { model: 'gpt-6-luna', effort: 'low' } } },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      saved = settings.reload.ai_config.dig('agents', 'atendente_agendamento')
      expect(saved['inbox_engines']).to eq(inbox_other.id.to_s => { 'model' => 'gpt-6-luna', 'effort' => 'low' })
      expect(saved['stage_models']).to eq(agent['stage_models'])
    end

    it 'tirar todas as caixas não apaga o motor por coluna', :aggregate_failures do
      post "#{base}/save_ai_stage_models", params: { agent: 'atendente_agendamento', part: 'inbox', inbox_engines: {} },
                                           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      saved = settings.reload.ai_config.dig('agents', 'atendente_agendamento')
      expect(saved['inbox_engines']).to eq({})
      expect(saved['stage_models']).to eq(agent['stage_models'])
    end

    it 'salvar só as colunas não apaga o motor por caixa', :aggregate_failures do
      post "#{base}/save_ai_stage_models", params: { agent: 'atendente_agendamento', stage_models: { stage_new.id.to_s => 'gpt-6-luna' } },
                                           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      saved = settings.reload.ai_config.dig('agents', 'atendente_agendamento')
      expect(saved['stage_models']).to eq(stage_new.id.to_s => 'gpt-6-luna')
      expect(saved['inbox_engines']).to eq(own)
    end

    it 'recusa motor de fornecedor sem chave salva', :aggregate_failures do
      settings.update!(ai_config: ai_config.except('openai_api_key'))
      post "#{base}/save_ai_stage_models",
           params: { agent: 'atendente_agendamento', part: 'inbox', inbox_engines: { inbox_test.id.to_s => { model: 'gpt-6-luna' } } },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('salve antes a chave')
    end
  end

  describe 'Comparativo de caixas' do
    it 'mostra o motor próprio da caixa no "quem atende"' do
      comparison = Crm::InboxComparison.new(account: account, since: 7.days.ago, until_at: Time.current, compare: 'previous')
      config = comparison.send(:config_for, inbox_test.id)

      expect(config.first[:caixa]).to eq(motor: 'GPT-6 Luna', esforco: 'high', roteiro: 'v2')
    end
  end
end
