require 'rails_helper'

# 🧑‍🏫 item 414 (24/11): cartão do consultor superior (config + contador) e o
# 🧪 Testar agente em segundo plano (a chamada da tela morria em 15 s).
RSpec.describe 'CRM settings — consultor superior e simulador em segundo plano', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/settings" }
  let(:ai_config) { { 'api_key' => 'sk-ant-teste', 'agents' => { 'atendente_agendamento' => { 'enabled' => true, 'model' => 'claude-haiku-4-5' } } } }
  let!(:settings) { CrmSetting.create!(account: account, ai_config: ai_config) }
  let(:reply) do
    { mensagens: ['Olá! Aqui é o Guilherme, da CEVICO.', 'É para você ou para um familiar?'], etapa: 'recepcao',
      agendar: false, agendamento: {}, pausar: false, chamar_humano: false, leitura: 'primeiro contato' }
  end

  def saved
    settings.reload.ai_config.dig('agents', 'atendente_agendamento', 'consultor')
  end

  describe 'cartão do consultor' do
    it 'sem nada salvo devolve o padrão: desligado, em sombra, três gatilhos', :aggregate_failures do
      get "#{base}/ai_consultant", params: { agent: 'atendente_agendamento' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['config']).to include('enabled' => false, 'mode' => 'sombra', 'daily_cap' => 50)
      expect(body['config']['triggers'].values).to all(be(true))
      expect(body).to include('ready' => false, 'default_model' => 'claude-haiku-4-5', 'recent' => [])
      expect(body['stats']['today']).to include('consultas' => 0)
    end

    it 'salva na hora sem encostar no resto do agente', :aggregate_failures do
      post "#{base}/save_ai_consultant",
           params: { agent: 'atendente_agendamento',
                     consultor: { enabled: true, model: 'claude-sonnet-5', mode: 'sombra', daily_cap: 30,
                                  triggers: { chamar_humano: true, vaga_invalida: true, sem_pergunta: false } } },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('ready' => true)
      expect(saved).to include('enabled' => true, 'model' => 'claude-sonnet-5', 'mode' => 'sombra', 'daily_cap' => 30)
      expect(saved['triggers']).to eq('chamar_humano' => true, 'vaga_invalida' => true, 'sem_pergunta' => false)
      expect(settings.reload.ai_config.dig('agents', 'atendente_agendamento')).to include('enabled' => true, 'model' => 'claude-haiku-4-5')
    end

    it 'guarda só as caixas em que o agente lê', :aggregate_failures do
      settings.update!(ai_config: ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'inbox_ids' => [7, 8] } }))
      post "#{base}/save_ai_consultant",
           params: { agent: 'atendente_agendamento', consultor: { enabled: true, model: 'claude-sonnet-5', inbox_ids: [8, 99] } },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(saved['inbox_ids']).to eq([8])
    end

    it 'recusa ligar sem modelo, com modelo sem chave ou sem nenhum gatilho', :aggregate_failures do
      post "#{base}/save_ai_consultant", params: { agent: 'atendente_agendamento', consultor: { enabled: true } },
                                         headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('Escolha o modelo')

      post "#{base}/save_ai_consultant", params: { agent: 'atendente_agendamento', consultor: { enabled: true, model: 'gpt-6.2-sol' } },
                                         headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('salve antes a chave')

      post "#{base}/save_ai_consultant",
           params: { agent: 'atendente_agendamento',
                     consultor: { enabled: true, model: 'claude-sonnet-5',
                                  triggers: { chamar_humano: false, vaga_invalida: false, sem_pergunta: false } } },
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('pelo menos um gatilho')
      expect(saved).to be_nil
    end

    it 'só administrador, e só nos atendentes do WhatsApp', :aggregate_failures do
      get "#{base}/ai_consultant", params: { agent: 'atendente_agendamento' }, headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)

      post "#{base}/save_ai_consultant", params: { agent: 'atendente_agendamento', consultor: { enabled: false } },
                                         headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)

      get "#{base}/ai_consultant", params: { agent: 'copywriter' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'lista as últimas consultas com o que o principal ia fazer × o que saiu', :aggregate_failures do
      conversation = create(:conversation, account: account, contact: create(:contact, account: account, name: 'Ana'))
      record = { 'gatilho' => 'chamar_humano', 'modo' => 'sombra', 'modelo' => 'claude-sonnet-5', 'principal' => 'gpt-6-luna',
                 'status' => 'ok', 'efeito' => 'evitou_equipe', 'mudou' => true, 'aplicado' => false,
                 'antes' => { 'mensagens' => ['Vou passar para a equipe.'], 'chamar_humano' => true },
                 'depois' => { 'mensagens' => ['É R$ 300. Quer um horário?'], 'chamar_humano' => false } }
      Crm::ResponderAgentJob.write_consultant_note!(conversation, record)

      get "#{base}/ai_consultant", params: { agent: 'atendente_agendamento' }, headers: admin.create_new_auth_token, as: :json
      item = response.parsed_body['recent'].first
      expect(item).to include('conversation_id' => conversation.display_id, 'contact' => 'Ana')
      expect(item['headline']).to include('Consultor superior', 'não precisava chamar a equipe')
      expect(item['record']).to include('gatilho' => 'chamar_humano', 'mudou' => true)
      expect(item.dig('record', 'depois', 'mensagens')).to eq(['É R$ 300. Quer um horário?'])
    end
  end

  describe '🧪 Testar agente em segundo plano' do
    let(:service) { instance_double(Crm::ResponderAgentService, call: reply) }

    before { allow(Crm::ResponderAgentService).to receive(:new).and_return(service) }

    def simulate(params)
      post "#{base}/ai_simulate", params: { agent: 'atendente_agendamento' }.merge(params), headers: admin.create_new_auth_token, as: :json
      response.parsed_body
    end

    it 'com async a fala entra, a resposta vai para a fila e a tela busca o resultado', :aggregate_failures do
      conv_id = simulate({})['conversation_id']

      body = nil
      expect { body = simulate(conversation_id: conv_id, text: 'oi, quero refrativa', async: true) }
        .to have_enqueued_job(Crm::AgentSimulatorJob).on_queue('ai_fundo')
      expect(body).to include('pending' => true, 'error' => nil)
      expect(body['turns'].pluck('role')).to eq(['patient'])
      expect(Crm::ResponderAgentService).not_to have_received(:new)
      # enquanto a fila não roda, a tela continua ouvindo "pendente"
      expect(simulate(conversation_id: conv_id)).to include('pending' => true)

      message = Conversation.find(conv_id).messages.where(message_type: :incoming).last
      Crm::AgentSimulatorJob.perform_now(conv_id, message.id, 'atendente_agendamento', 'gpt-6-luna',
                                         { 'model' => 'claude-sonnet-5', 'mode' => 'ativo' })

      done = simulate(conversation_id: conv_id)
      expect(done).to include('pending' => false, 'error' => nil)
      expect(done['turns'].pluck('role')).to eq(%w[patient agent])
      expect(done['turns'].last['messages']).to eq(reply[:mensagens])
      expect(Crm::ResponderAgentService).to have_received(:new).with(
        hash_including(simulation: true, live: false, model_override: 'gpt-6-luna',
                       consultant_override: { 'model' => 'claude-sonnet-5', 'mode' => 'ativo' })
      )
      expect(Conversation.find(conv_id)).to be_resolved # item 412: a conversa de teste volta a ficar arquivada
    end

    it 'erro da IA em segundo plano aparece na tela do teste', :aggregate_failures do
      allow(service).to receive(:call).and_return(error: 'Chave da OpenAI inválida.')
      conv_id = simulate({})['conversation_id']
      simulate(conversation_id: conv_id, text: 'oi', async: true)
      message = Conversation.find(conv_id).messages.where(message_type: :incoming).last
      Crm::AgentSimulatorJob.perform_now(conv_id, message.id, 'atendente_agendamento')

      expect(simulate(conversation_id: conv_id)).to include('pending' => false, 'error' => 'Chave da OpenAI inválida.')
    end

    it 'sem async continua respondendo na hora, como sempre', :aggregate_failures do
      conv_id = simulate({})['conversation_id']

      body = nil
      expect { body = simulate(conversation_id: conv_id, text: 'oi') }.not_to have_enqueued_job(Crm::AgentSimulatorJob)
      expect(body).to include('pending' => false)
      expect(body['turns'].pluck('role')).to eq(%w[patient agent])
    end

    it 'a tela manda o consultor do teste e o servidor só aceita modelo com chave salva', :aggregate_failures do
      conv_id = simulate({})['conversation_id']
      simulate(conversation_id: conv_id, text: 'oi', consultant: { model: 'claude-sonnet-5', mode: 'sombra' })
      expect(Crm::ResponderAgentService).to have_received(:new).with(
        hash_including(consultant_override: { 'model' => 'claude-sonnet-5', 'mode' => 'sombra', 'tool' => false })
      )

      simulate(conversation_id: conv_id, text: 'oi de novo', consultant: { model: 'gpt-6.2-sol', mode: 'ativo' })
      expect(Crm::ResponderAgentService).to have_received(:new).with(hash_including(consultant_override: nil))
    end

    it 'sem ninguém ouvindo a fila do teste, o async responde na hora (não deixa a tela esperando)', :aggregate_failures do
      allow(Crm::AgentSimulator).to receive(:background_ready?).and_return(false)
      conv_id = simulate({})['conversation_id']

      body = nil
      expect { body = simulate(conversation_id: conv_id, text: 'oi', async: true) }.not_to have_enqueued_job(Crm::AgentSimulatorJob)
      expect(body).to include('pending' => false)
      expect(body['turns'].pluck('role')).to eq(%w[patient agent])
    end

    it 'o job não toca em conversa que não é de teste' do
      real = create(:conversation, account: account)
      message = create(:message, account: account, inbox: real.inbox, conversation: real, message_type: :incoming, content: 'oi')

      Crm::AgentSimulatorJob.perform_now(real.id, message.id, 'atendente_agendamento')
      expect(Crm::ResponderAgentService).not_to have_received(:new)
    end
  end
end
