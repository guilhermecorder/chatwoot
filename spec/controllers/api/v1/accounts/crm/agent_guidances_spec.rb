require 'rails_helper'

# ✍️ rodada 191: orientações dos atendentes de IA (criar, aplicar no Roteiro / nos passos, ignorar, sinal do 👎)
RSpec.describe 'CRM agent guidances', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/agent_guidances" }
  let(:headers) { admin.create_new_auth_token }

  before { CrmSetting.create!(account: account, ai_config: {}) }

  it 'só admin entra' do
    get base, headers: agent_user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'cria, lista com contadores por status e edita', :aggregate_failures do
    post base, params: { agent_key: 'atendente_agendamento', patient_excerpt: 'vocês aceitam Unimed?',
                         agent_text: 'Aceitamos sim!', ideal_reply: 'Trabalhamos só com atendimento particular.',
                         rule: 'Nunca dizer que aceita convênio', target_section: 'objections', conversation_id: 12 },
               headers: headers, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body['id']
    expect(response.parsed_body).to include('status' => 'pending', 'source' => 'manual', 'target_section_title' => 'Objeções e dúvidas frequentes')
    expect(response.parsed_body['preview_line']).to start_with('"vocês aceitam Unimed?" → Trabalhamos só')

    get base, params: { agent_key: 'atendente_agendamento', status: 'pending' }, headers: headers, as: :json
    expect(response.parsed_body['guidances'].map { |g| g['id'] }).to eq([id])
    expect(response.parsed_body['counts']).to eq('pending' => 1, 'applied' => 0, 'ignored' => 0)
    expect(response.parsed_body['sections'].pluck('key')).to include('objections', 'stage')

    put "#{base}/#{id}", params: { rule: 'Só particular', source: 'sombra' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('rule' => 'Só particular', 'source' => 'manual')
  end

  it 'aplica em Objeções partindo do padrão, com foto do Roteiro antes', :aggregate_failures do
    g = Crm::AgentGuidance.create!(account: account, agent_key: 'atendente_agendamento', patient_excerpt: '  vocês aceitam  Unimed? ',
                                   ideal_reply: 'Só particular, mas parcela em 10x.', rule: 'nunca aceitar convênio', target_section: 'objections')
    post "#{base}/#{g.id}/apply", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.dig('guidance', 'status')).to eq('applied')
    expect(body.dig('section', 'key')).to eq('objections')
    expect(body.dig('section', 'text')).to start_with(Crm::CevicoScript::DEFAULT['objections'])
    expect(body.dig('section', 'text'))
      .to end_with("\n\"vocês aceitam Unimed?\" → Só particular, mas parcela em 10x. (regra: nunca aceitar convênio)")
    expect(body['script_updated_at']).to be_present

    expect(Crm::CevicoScript.section_text(account, 'objections')).to include('nunca aceitar convênio')
    expect(Crm::CevicoScript.text(account)).to include('Só particular, mas parcela em 10x.')
    expect(g.reload).to have_attributes(status: 'applied', applied_by: admin)
    expect(g.applied_at).to be_present

    version = Crm::ScriptVersion.find_by(account: account, kind: 'script')
    expect(version.content).to eq({}) # o Roteiro era todo padrão
    expect(version.guidance).to eq(g)

    post "#{base}/#{g.id}/apply", headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('já foi aplicada')
  end

  it 'aplica nos passos do agente (stage) no prompt PUBLICADO sem mexer no rascunho', :aggregate_failures do
    CrmSetting.find_by(account: account)
              .update!(ai_config: { 'agents' => { 'atendente_pos' => { 'prompt' => 'PASSOS ATUAIS', 'draft' => 'rascunho' } } })
    g = Crm::AgentGuidance.create!(account: account, agent_key: 'atendente_pos', target_section: 'stage',
                                   rule: 'Pergunte a unidade antes de remarcar')
    post "#{base}/#{g.id}/apply", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('section', 'text')).to eq("PASSOS ATUAIS\n- Pergunte a unidade antes de remarcar")

    agent = CrmSetting.find_by(account: account).ai_config.dig('agents', 'atendente_pos')
    expect(agent['prompt']).to eq("PASSOS ATUAIS\n- Pergunte a unidade antes de remarcar")
    expect(agent['draft']).to eq('rascunho')
    expect(Crm::CevicoScript.stage_prompt(account, 'atendente_pos')).to end_with('- Pergunte a unidade antes de remarcar')
    expect(Crm::ScriptVersion.find_by(account: account, kind: 'stage', agent_key: 'atendente_pos').content).to eq('prompt' => 'PASSOS ATUAIS')
  end

  it 'recusa aplicar sem seção ou sem texto' do
    g = Crm::AgentGuidance.create!(account: account, agent_key: 'atendente_pos', ideal_reply: 'x')
    post "#{base}/#{g.id}/apply", headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('seção')
  end

  it 'ignora, reabre e apaga', :aggregate_failures do
    g = Crm::AgentGuidance.create!(account: account, agent_key: 'atendente_pos', ideal_reply: 'x', target_section: 'handoff')
    post "#{base}/#{g.id}/ignore", headers: headers, as: :json
    expect(response.parsed_body['status']).to eq('ignored')
    post "#{base}/#{g.id}/reopen", headers: headers, as: :json
    expect(response.parsed_body['status']).to eq('pending')
    delete "#{base}/#{g.id}", headers: headers, as: :json
    expect(response).to have_http_status(:no_content)
    expect(Crm::AgentGuidance.exists?(g.id)).to be(false)
  end

  it 'não enxerga orientação de outra conta' do
    other = Crm::AgentGuidance.create!(account: create(:account), agent_key: 'atendente_pos', ideal_reply: 'x')
    post "#{base}/#{other.id}/ignore", headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
  end

  describe 'sinal automático do 👎 na tela Sombra' do
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let!(:patient_msg) do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'tem desconto?')
    end
    let!(:note) do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :activity, private: true,
                       content: 'sombra', additional_attributes: { 'cevico_ia_shadow' => {
                         'agent' => 'atendente_agendamento', 'mensagens' => ['Tem sim!', 'Quer agendar?'], 'trigger_message_id' => patient_msg.id
                       } })
    end
    let(:rate_url) { "/api/v1/accounts/#{account.id}/crm/settings/ai_shadow_rate" }

    it 'cria uma orientação pendente por nota, sem duplicar, e guarda a nota do 👎 como regra', :aggregate_failures do
      post rate_url, params: { message_id: note.id, rating: 'bad', note: 'nunca prometer desconto' }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      post rate_url, params: { message_id: note.id, rating: 'bad' }, headers: headers, as: :json

      guidances = Crm::AgentGuidance.where(account: account)
      expect(guidances.count).to eq(1)
      g = guidances.first
      expect(g).to have_attributes(source: 'sombra', status: 'pending', agent_key: 'atendente_agendamento', message_id: note.id,
                                   conversation_id: conversation.display_id, patient_excerpt: 'tem desconto?',
                                   agent_text: "Tem sim!\nQuer agendar?", rule: 'nunca prometer desconto', created_by: admin)
    end

    it 'não cria nada com 👍' do
      post rate_url, params: { message_id: note.id, rating: 'good' }, headers: headers, as: :json
      expect(Crm::AgentGuidance.where(account: account).count).to eq(0)
    end
  end
end
