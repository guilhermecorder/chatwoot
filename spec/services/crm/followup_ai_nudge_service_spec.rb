require 'rails_helper'

# 🤖 Item 315: a cutucada escrita pela IA a partir da conversa
RSpec.describe Crm::FollowupAiNudgeService do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Clara') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:step) { { 'kind' => 'ai', 'delay_value' => 24, 'delay_unit' => 'hours', 'ai_instructions' => 'lembrar do orçamento' } }

  before do
    CrmSetting.create!(account: account, ai_config: { 'api_key' => 'sk-teste' })
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Quanto custa a refrativa?')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'R$ 5.000 por olho', sender: admin)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'nota interna',
                     private: true, sender: admin)
  end

  # a resposta da Anthropic é simulada (objetos do gem, sem classe pública estável)
  # rubocop:disable RSpec/VerifiedDoubles
  def stub_ai(json)
    usage = double('usage', input_tokens: 100, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 20)
    message = double('resposta', content: [double('bloco', type: :text, text: json)], usage: usage)
    messages = double('messages', create: message)
    allow_any_instance_of(described_class).to receive(:client).and_return(double('client', messages: messages)) # rubocop:disable RSpec/AnyInstance
    messages
  end
  # rubocop:enable RSpec/VerifiedDoubles

  it 'manda a conversa (sem notas internas) + orientação e devolve o texto, registrando o gasto', :aggregate_failures do
    resposta = { mensagem: 'Oi Maria! Ficou alguma dúvida sobre o orçamento da refrativa?', motivo: 'retoma o orçamento' }
    messages = stub_ai(resposta.to_json)

    result = described_class.new(conversation: conversation, step: step).call

    expect(result[:text]).to eq('Oi Maria! Ficou alguma dúvida sobre o orçamento da refrativa?')
    expect(messages).to have_received(:create) do |params|
      user_text = params[:messages].first[:content].map { |c| c[:text] }.join("\n")
      expect(user_text).to include('PACIENTE: Quanto custa a refrativa?', 'CLÍNICA: R$ 5.000 por olho',
                                   'ORIENTAÇÃO DO ADMIN PARA ESTA ETAPA: lembrar do orçamento')
      expect(user_text).not_to include('nota interna')
      expect(params[:system_].first[:text]).to include('REGRAS INEGOCIÁVEIS', 'Não cite nomes de médicos')
      expect(params[:system_].first[:text]).not_to include('== DADOS OFICIAIS') # tabela de preços fica fora
      expect(params[:model]).to eq('claude-sonnet-5')
    end
    expect(Crm::AiUsage.where(account: account, agent_key: 'followup_ia').count).to eq(1)
  end

  it 'devolve erro sem chave da API (marcado como erro de configuração) e com conversa vazia', :aggregate_failures do
    CrmSetting.find_by(account: account).update!(ai_config: {})
    result = described_class.new(conversation: conversation, step: step).call
    expect(result[:error]).to include('chave da API')
    expect(result[:config_error]).to be(true)

    CrmSetting.find_by(account: account).update!(ai_config: { 'api_key' => 'sk' })
    vazia = create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account))
    expect(described_class.new(conversation: vazia, step: step).call[:error]).to eq('Conversa vazia.')
  end
end
