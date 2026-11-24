require 'rails_helper'

# 🧪 item 403 (23/11): Laboratório de atendimento — montar o teste A/B de
# prompt/motor pelo cartão, comparar e DECIDIR (encerrar, adotar a B, copiar
# o Roteiro 1 para o 2).
RSpec.describe 'CRM — Laboratório de atendimento', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:settings_url) { "/api/v1/accounts/#{account.id}/crm/settings" }
  let(:lab_url) { "/api/v1/accounts/#{account.id}/crm/attendance_lab" }
  let(:agent_cfg) { { 'enabled' => true, 'mode' => 'live', 'inbox_ids' => [inbox.id], 'model' => 'claude-sonnet-5' } }
  let(:first_section) { Crm::CevicoScript::SECTIONS.first['key'] }
  let!(:settings) do
    CrmSetting.create!(account: account, ai_config: { 'api_key' => 'sk-ant-teste', 'agents' => { 'atendente_agendamento' => agent_cfg } })
  end

  def saved_agent
    settings.reload.ai_config.dig('agents', 'atendente_agendamento')
  end

  def save_test(**params)
    post "#{settings_url}/save_ai_experiment",
         params: { agent: 'atendente_agendamento', enabled: true, inboxes: { inbox.id.to_s => 'split' } }.merge(params),
         headers: admin.create_new_auth_token, as: :json
  end

  def stamp_conversation(arm)
    conversation = create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account))
    Crm::EngineExperiment.track!(conversation, 'atendente_agendamento', saved_agent, arm, 'reply' => true, 'cost_usd' => 0.01)
    conversation
  end

  describe 'montar o teste (cartão do agente)' do
    it 'teste de prompt: Roteiro 2 na B com o mesmo motor da A', :aggregate_failures do
      save_test(script_b: 'v2', model_b: '', name: 'Recepção sem a palavra cirurgia')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['config']).to include('enabled' => true, 'script_b' => 'v2', 'kind' => 'prompt',
                                                        'name' => 'Recepção sem a palavra cirurgia')
      expect(saved_agent['ab']).to include('script_b' => 'v2', 'inboxes' => { inbox.id.to_s => 'split' })
      expect(saved_agent['ab']['model_b']).to be_nil
      expect(saved_agent['ab']['digests'].keys).to match_array(%w[a b])
    end

    it 'recusa a B igual à A', :aggregate_failures do
      save_test(script_b: 'v1', model_b: 'claude-sonnet-5')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('igual à A')
    end

    it 'trocar o que a B é começa um teste novo e manda o anterior para o histórico', :aggregate_failures do
      save_test(script_b: 'v2', model_b: '')
      first_id = saved_agent.dig('ab', 'started_at')
      stamp_conversation('b')

      travel_to(1.hour.from_now) { save_test(script_b: 'v1', model_b: 'claude-haiku-4-5') }

      expect(response.parsed_body['config']).to include('kind' => 'motor')
      expect(saved_agent.dig('ab', 'started_at')).not_to eq(first_id)
      expect(saved_agent['ab_history'].first).to include('id' => first_id, 'kind' => 'prompt', 'script_b' => 'v2')
      expect(saved_agent['ab_history'].first.dig('snapshot', 'b', 'conversas')).to eq(1)
    end
  end

  describe 'o Laboratório' do
    it 'só administrador entra' do
      get lab_url, headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'mostra o teste de agora, o placar e o que muda entre os Roteiros', :aggregate_failures do
      settings.update!(ai_config: settings.ai_config.merge('script_v2' => { first_section => 'Texto da B' }))
      save_test(script_b: 'v2', model_b: '')
      stamp_conversation('a')
      stamp_conversation('b')

      get lab_url, params: { agent: 'atendente_agendamento' }, headers: admin.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(response).to have_http_status(:ok)
      expect(body['test']).to include('current' => true, 'kind' => 'prompt', 'script_b' => 'v2', 'enabled' => true)
      expect(body['report']['arms'].pluck('conversas')).to eq([1, 1])
      expect(body['inboxes']).to eq([{ 'id' => inbox.id, 'name' => inbox.name, 'mode' => 'split' }])
      expect(body['prompt']['different'].pluck('key')).to include(first_section)
      expect(body['agents'].first).to include('key' => 'atendente_agendamento', 'running' => true, 'kind' => 'prompt')
    end

    it 'avisa quando o Roteiro da B foi editado depois que o teste começou' do
      save_test(script_b: 'v2', model_b: '')
      Cevico::SettingMerge.merge!(settings, :ai_config) { |cfg| cfg.merge('script_v2' => { first_section => 'Mudei no meio do teste' }) }

      get lab_url, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body.dig('prompt', 'changed_since_start')).to eq('a' => false, 'b' => true)
    end
  end

  describe 'decidir' do
    it 'ficar com a A encerra o teste, guarda no histórico e não muda o atendimento', :aggregate_failures do
      save_test(script_b: 'v1', model_b: 'claude-haiku-4-5')
      test_id = saved_agent.dig('ab', 'started_at')

      post "#{lab_url}/finish", params: { agent: 'atendente_agendamento', decision: 'a', note: 'custo igual, A converte mais' },
                                headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(saved_agent['ab']).to include('enabled' => false)
      expect(saved_agent['ab']['ended_at']).to be_present
      expect(saved_agent['model']).to eq('claude-sonnet-5')
      expect(saved_agent['ab_history'].first).to include('id' => test_id, 'decision' => 'a', 'adopted' => false,
                                                         'note' => 'custo igual, A converte mais')
      expect(Crm::EngineExperiment.active(saved_agent)).to be_nil
    end

    it 'adotar a B num teste de motor troca o modelo do cartão', :aggregate_failures do
      save_test(script_b: 'v1', model_b: 'claude-haiku-4-5')

      post "#{lab_url}/finish", params: { agent: 'atendente_agendamento', decision: 'b', apply: true },
                                headers: admin.create_new_auth_token, as: :json

      expect(saved_agent['model']).to eq('claude-haiku-4-5')
      expect(saved_agent['ab_history'].first).to include('decision' => 'b', 'adopted' => true)
    end

    it 'adotar a B num teste de prompt faz o Roteiro 2 virar o oficial, com foto do anterior', :aggregate_failures do
      settings.update!(ai_config: settings.ai_config.merge('script' => { first_section => 'Texto oficial antigo' },
                                                           'script_v2' => { first_section => 'Texto vencedor da B' }))
      save_test(script_b: 'v2', model_b: '')

      post "#{lab_url}/finish", params: { agent: 'atendente_agendamento', decision: 'b', apply: true },
                                headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(Crm::CevicoScript.section_text(account, first_section, 'v1')).to eq('Texto vencedor da B')
      expect(saved_agent['prompt']).to eq(Crm::CevicoScript.stage_prompt(account, 'atendente_agendamento', 'v2'))
      photo = Crm::ScriptVersion.where(account: account, kind: 'script').recent.first
      expect(photo.content[first_section]).to eq('Texto oficial antigo')
      expect(saved_agent['model']).to eq('claude-sonnet-5')
    end

    it 'B ainda igual à A não é teste: não há o que encerrar', :aggregate_failures do
      save_test(enabled: false, script_b: 'v1', model_b: '')

      post "#{lab_url}/finish", params: { agent: 'atendente_agendamento', decision: 'a' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(saved_agent['ab_history']).to be_nil
    end

    it 'encerrar e começar outro no mesmo segundo não repete o número do teste', :aggregate_failures do
      freeze_time do
        save_test(script_b: 'v1', model_b: 'claude-haiku-4-5')
        first_id = saved_agent.dig('ab', 'started_at')
        post "#{lab_url}/finish", params: { agent: 'atendente_agendamento', decision: 'a' }, headers: admin.create_new_auth_token, as: :json
        save_test(script_b: 'v2', model_b: '')

        expect(saved_agent.dig('ab', 'started_at')).not_to eq(first_id)
        expect(saved_agent['ab_history'].pluck('id')).to eq([first_id])
      end
    end

    it 'com motor por coluna, adotar a B grava o motor dela só nas colunas do teste', :aggregate_failures do
      pipeline = Crm::Pipeline.create!(account: account, name: 'CEVICO')
      first = pipeline.stages.create!(name: 'Novos Contatos', position: 0)
      second = pipeline.stages.create!(name: 'Envio de Orçamento', position: 1)
      staged = agent_cfg.merge('stage_ids' => [first.id, second.id],
                               'stage_models' => { first.id.to_s => 'claude-haiku-4-5', second.id.to_s => 'claude-sonnet-5' })
      settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => staged }))
      save_test(script_b: 'v1', model_b: 'claude-sonnet-5', stages_b: [first.id.to_s, '999'])

      expect(response.parsed_body['config']).to include('kind' => 'motor', 'stages_b' => [first.id.to_s])

      get lab_url, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body.dig('test', 'stages')).to eq(
        [{ 'slot' => first.id.to_s, 'name' => 'Novos Contatos', 'a' => 'claude-haiku-4-5', 'b' => 'claude-sonnet-5' },
         { 'slot' => second.id.to_s, 'name' => 'Envio de Orçamento', 'a' => 'claude-sonnet-5', 'b' => 'claude-sonnet-5' }]
      )

      post "#{lab_url}/finish", params: { agent: 'atendente_agendamento', decision: 'b', apply: true },
                                headers: admin.create_new_auth_token, as: :json

      expect(saved_agent['stage_models']).to eq(first.id.to_s => 'claude-sonnet-5', second.id.to_s => 'claude-sonnet-5')
      expect(saved_agent['model']).to eq('claude-sonnet-5')
    end

    it 'teste já encerrado não encerra de novo' do
      save_test(script_b: 'v1', model_b: 'claude-haiku-4-5')
      2.times { post "#{lab_url}/finish", params: { agent: 'atendente_agendamento' }, headers: admin.create_new_auth_token, as: :json }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'copiar o Roteiro 1 para o 2' do
    it 'o Roteiro 2 fica idêntico ao 1 e o texto de antes fica guardado', :aggregate_failures do
      settings.update!(ai_config: settings.ai_config.merge('script' => { first_section => 'Oficial personalizado' },
                                                           'script_v2' => { first_section => 'Rascunho antigo da B' }))

      post "#{lab_url}/copy_script", params: { agent: 'atendente_agendamento' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('prompt', 'different')).to eq([])
      expect(Crm::CevicoScript.section_text(account, first_section, 'v2')).to eq('Oficial personalizado')
      expect(settings.reload.ai_config.dig('script_v2_backup', 'script_v2', first_section)).to eq('Rascunho antigo da B')
    end

    it 'não copia com um teste ligado lendo o Roteiro 2', :aggregate_failures do
      save_test(script_b: 'v2', model_b: '')

      post "#{lab_url}/copy_script", params: { agent: 'atendente_agendamento' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('Encerre o teste')
    end
  end
end
