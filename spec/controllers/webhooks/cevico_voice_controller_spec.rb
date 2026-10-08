require 'rails_helper'

RSpec.describe 'CEVICO Voice webhooks', type: :request do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:tools_token) { "tok_#{'a' * 40}" }
  let(:webhook_secret) { "wsec_#{'b' * 40}" }
  let(:base) { "/webhooks/cevico/voice/#{account.id}" }

  before do
    CrmSetting.create!(account: account,
                       ai_config: { 'voice' => { 'enabled' => true, 'tools_token' => tools_token, 'webhook_secret' => webhook_secret,
                                                 'handoff_inbox_id' => inbox.id, 'api_key' => 'sim', 'agent_id' => 'sim_agent' } })
  end

  describe 'POST /tools/:tool' do
    it 'executa a ferramenta com o token certo' do
      post "#{base}/tools/horarios_livres", params: { dias: 5, conversa_id: 'conv_1' }.to_json,
                                            headers: { 'X-Cevico-Token' => tools_token, 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('horarios', 'texto')
    end

    it 'recusa com 401 quando o token está errado' do
      post "#{base}/tools/horarios_livres", params: { dias: 5 }.to_json,
                                            headers: { 'X-Cevico-Token' => 'errado', 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'devolve erro legível (200) para ferramenta desconhecida' do
      post "#{base}/tools/inventada", params: {}.to_json,
                                      headers: { 'X-Cevico-Token' => tools_token, 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['ok']).to be(false)
    end
  end

  describe 'POST /initiation' do
    it 'devolve as variáveis dinâmicas e a primeira frase com o nome' do
      create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000')
      post "#{base}/initiation", params: { caller_id: '+5511999990000', agent_id: 'sim_agent', conversation_id: 'conv_2' }.to_json,
                                 headers: { 'X-Cevico-Token' => tools_token, 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['type']).to eq('conversation_initiation_client_data')
      expect(body['dynamic_variables']['primeiro_nome']).to eq('Maria')
      expect(body.dig('conversation_config_override', 'agent', 'first_message')).to include('Olá, Maria!')
    end

    # item 333 — regra de ouro: paciente de parceiro nunca conversa com IA
    it 'paciente de clínica parceira: frase fixa, roteiro trocado para só encerrar e tarefa para a equipe', :aggregate_failures do
      create(:user, account: account, role: :administrator)
      partner = create(:contact, account: account, name: 'João Parceiro', phone_number: '+5511999990009')
      partner.add_labels(['of_clinica_x'])
      post "#{base}/initiation", params: { caller_id: '+5511999990009', agent_id: 'sim_agent', conversation_id: 'conv_9' }.to_json,
                                 headers: { 'X-Cevico-Token' => tools_token, 'CONTENT_TYPE' => 'application/json' }

      agent = response.parsed_body.dig('conversation_config_override', 'agent')
      expect(agent['first_message']).to include('a equipe da clínica vai falar com você')
      expect(agent['first_message']).not_to include('João')
      expect(agent.dig('prompt', 'prompt')).to eq(Crm::VoiceAgent::Script::PARTNER_PROMPT)
      expect(response.parsed_body['dynamic_variables']['primeiro_nome']).to eq('')
      task = account.tasks.where(contact_id: partner.id).last
      expect(task.title).to include('Ligação').and include('parceira')
    end
  end

  describe 'POST /post_call' do
    let(:payload) { { type: 'post_call_transcription', data: { conversation_id: 'conv_3', status: 'done', transcript: [] } }.to_json }

    def signature_for(body, secret, at = Time.current.to_i)
      "t=#{at},v0=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{at}.#{body}")}"
    end

    it 'aceita a assinatura válida e enfileira o pós-chamada' do
      post "#{base}/post_call", params: payload,
                                headers: { 'ElevenLabs-Signature' => signature_for(payload, webhook_secret), 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(Crm::VoiceAgent::PostCallJob).to have_been_enqueued.with(account.id, hash_including('type' => 'post_call_transcription'))
    end

    it 'recusa assinatura com segredo errado' do
      post "#{base}/post_call", params: payload,
                                headers: { 'ElevenLabs-Signature' => signature_for(payload, 'outro'), 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
      expect(Crm::VoiceAgent::PostCallJob).not_to have_been_enqueued
    end

    it 'recusa assinatura velha (mais de 30 minutos)' do
      old_signature = signature_for(payload, webhook_secret, 31.minutes.ago.to_i)
      post "#{base}/post_call", params: payload,
                                headers: { 'ElevenLabs-Signature' => old_signature, 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
