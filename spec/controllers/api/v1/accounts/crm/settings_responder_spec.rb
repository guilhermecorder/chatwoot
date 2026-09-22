require 'rails_helper'

# 🗣️ rodada 188: config do Atendente de Agendamento + Roteiro + tela Sombra
RSpec.describe 'CRM settings — Atendente de Agendamento', type: :request do
  # o ao vivo é trancado por variável de ambiente; aqui destravamos para testar
  before do
    stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', true)
    CrmSetting.create!(account: account, ai_config: {})
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/settings" }

  it 'Ao vivo sem caixa marcada é recusado com mensagem clara (193)' do
    post "#{base}/update_ai", params: { agents: { atendente_agendamento: { mode: 'live', enabled: true } } },
                              headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('marque pelo menos uma caixa')
    expect(CrmSetting.find_by(account: account).ai_config.dig('agents', 'atendente_agendamento')).to be_nil
  end

  it 'Ao vivo com caixa: grava mode + live_days (só 0..6, sem repetir) e devolve live_enabled true', :aggregate_failures do
    post "#{base}/update_ai",
         params: { agents: { atendente_pos: { mode: 'live', enabled: true, inbox_ids: [7], live_days: [6, 0, 6, 9, -1],
                                              hours_start: '08:00', hours_end: '18:00' } } },
         headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    saved = CrmSetting.find_by(account: account).ai_config.dig('agents', 'atendente_pos')
    expect(saved).to include('mode' => 'live', 'live_days' => [6, 0], 'inbox_ids' => [7])
    agent = response.parsed_body.dig('agents', 'atendente_pos')
    expect(agent).to include('mode' => 'live', 'live_days' => [6, 0], 'hours_start' => '08:00', 'hours_end' => '18:00')
    expect(response.parsed_body['live_enabled']).to be(true)

    # caixa já gravada vale; live_days vazio = todos os dias
    post "#{base}/update_ai", params: { agents: { atendente_pos: { mode: 'live', live_days: [] } } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('agents', 'atendente_pos', 'live_days')).to eq([])
  end

  it 'grava caixas, colunas, sem card, teto e coluna pós-agendamento em sombra', :aggregate_failures do
    post "#{base}/update_ai",
         params: { agents: { atendente_agendamento: { mode: 'shadow', inbox_ids: [7], stage_ids: [1, 2], no_card: true,
                                                      shadow_daily_cap: 15, after_booking_stage_id: 3, hours_start: '08:00', hours_end: '20:00' } } },
         headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    saved = CrmSetting.find_by(account: account).ai_config.dig('agents', 'atendente_agendamento')
    expect(saved).to include('mode' => 'shadow', 'inbox_ids' => [7], 'stage_ids' => [1, 2], 'no_card' => true, 'shadow_daily_cap' => 15)
    agent = response.parsed_body.dig('agents', 'atendente_agendamento')
    expect(agent).to include('no_card' => true, 'shadow_daily_cap' => 15, 'after_booking_stage_id' => 3, 'hours_start' => '08:00')
    expect(agent['default_prompt']).to include('SEU PAPEL NESTA ETAPA')
    expect(agent['live_days']).to eq([])
    expect(response.parsed_body['live_enabled']).to be(true)
  end

  it 'salva o Roteiro por seção e devolve as seções com padrão × personalizado', :aggregate_failures do
    post "#{base}/update_ai", params: { script: { persona: 'Você é a Clara, da CEVICO.', form_rules: '' } },
                              headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    sections = response.parsed_body['script'].index_by { |sec| sec['key'] }
    expect(sections['persona']).to include('text' => 'Você é a Clara, da CEVICO.', 'custom' => true)
    expect(sections['form_rules']['custom']).to be(false)
    expect(response.parsed_body['script_updated_at']).to be_present
    expect(Crm::CevicoScript.text(account)).to include('Você é a Clara')
  end

  it 'simulador: abre conversa numa caixa interna sem envio e responde como nota de sombra', :aggregate_failures do
    reply = { mensagens: ['Olá! Aqui é o Guilherme, da CEVICO.', 'É para você ou para um familiar?'], etapa: 'recepcao',
              agendar: false, agendamento: {}, pausar: false, chamar_humano: false, leitura: 'primeiro contato' }
    allow(Crm::ResponderAgentService).to receive(:new).and_return(instance_double(Crm::ResponderAgentService, call: reply))

    post "#{base}/ai_simulate", params: { agent: 'atendente_agendamento' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    conv_id = response.parsed_body['conversation_id']
    conversation = Conversation.find(conv_id)
    expect(conversation.inbox.channel).to be_a(Channel::Api)
    expect(conversation.inbox.name).to eq(Crm::AgentSimulator::INBOX_NAME)
    expect(conversation.additional_attributes['cevico_simulado']).to be(true)

    post "#{base}/ai_simulate", params: { agent: 'atendente_agendamento', conversation_id: conv_id, text: 'oi, quero refrativa' },
                                headers: admin.create_new_auth_token, as: :json
    turns = response.parsed_body['turns']
    expect(turns.map { |t| t['role'] }).to eq(%w[patient agent])
    expect(turns.last['messages']).to eq(reply[:mensagens])
    expect(turns.last.dig('meta', 'etapa')).to eq('recepcao')
    expect(conversation.messages.where(message_type: :outgoing)).to be_empty # nada de envio, nunca
    expect(conversation.messages.where(message_type: :incoming).count).to eq(1)

    post "#{base}/ai_simulate", params: { agent: 'scheduler' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity) # só agentes que falam com paciente
  end

  it 'tela Sombra: lista as notas com a fala do paciente e a resposta real; 👍 grava a avaliação', :aggregate_failures do
    inbox = create(:inbox, account: account)
    contact = create(:contact, account: account, name: 'Ana')
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
    trigger = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'quanto custa?')
    note = conversation.messages.create!(account_id: account.id, inbox_id: inbox.id, message_type: :activity, private: true,
                                         content: '🕶️ Sombra',
                                         additional_attributes: { 'cevico_ia_shadow' => { 'agent' => 'atendente_agendamento', 'etapa' => 'orcamento',
                                                                                          'mensagens' => ['O investimento é...'], 'agendar' => false,
                                                                                          'trigger_message_id' => trigger.id } })
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Resposta do N8N')

    get "#{base}/ai_shadow", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    item = response.parsed_body['items'].first
    expect(item).to include('id' => note.id, 'contact' => 'Ana', 'patient_said' => 'quanto custa?')
    expect(item['real_replies'].first).to include('content' => 'Resposta do N8N')
    expect(response.parsed_body['summary']).to include('total' => 1, 'by_stage' => { 'orcamento' => 1 })

    post "#{base}/ai_shadow_rate", params: { message_id: note.id, rating: 'good' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(note.reload.additional_attributes.dig('cevico_ia_shadow', 'rating')).to eq('good')

    get "#{base}/ai_shadow", headers: agent_user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  # 🧪 22/09: Roteiro v2 paralelo — salvar num card só e testar um, depois o outro
  it 'salva o v2 paralelo (seções + passos) sem encostar no Roteiro atual', :aggregate_failures do
    post "#{base}/update_ai", params: { script_v2: { persona: 'Persona v2.', stage_atendente_pos: 'Passos v2 do pós.' } },
                              headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    cfg = CrmSetting.find_by(account: account).ai_config
    expect(cfg.dig('script_v2', 'persona')).to eq('Persona v2.')
    expect(cfg.dig('script_v2', 'updated_at')).to be_present
    expect(cfg.dig('agents', 'atendente_pos', 'prompt_v2')).to eq('Passos v2 do pós.')
    expect(cfg['script']).to be_nil
    v2 = response.parsed_body.dig('ai', 'script_v2') || response.parsed_body['script_v2']
    expect(v2.find { |x| x['key'] == 'persona' }['custom']).to be(true)
    expect(v2.find { |x| x['key'] == 'stage_atendente_pos' }['text']).to eq('Passos v2 do pós.')
    expect(v2.find { |x| x['key'] == 'stage_atendente_agendamento' }['custom']).to be(false)
  end

  it 'simulador: a conversa de teste nasce presa à versão do Roteiro pedida', :aggregate_failures do
    post "#{base}/ai_simulate", params: { agent: 'atendente_agendamento', script_version: 'v2' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['script_version']).to eq('v2')
    conv = Conversation.find(response.parsed_body['conversation_id'])
    expect(conv.additional_attributes['cevico_simulado_script']).to eq('v2')

    post "#{base}/ai_simulate", params: { agent: 'atendente_agendamento', script_version: 'v9' }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['script_version']).to eq('v1')
  end
end
