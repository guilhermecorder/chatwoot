require 'rails_helper'

# 🧠 item 399 (22/11): ChatGPT (OpenAI) como motor dos atendentes do WhatsApp.
# A OpenAI é simulada (WebMock): nenhuma chamada sai de verdade.
RSpec.describe Crm::ResponderAgentService do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:tz) { Crm::AgendaSlots::TZ }
  let(:url) { Crm::LlmEngines::OpenaiResponses::URL }
  let(:final_hash) do
    { mensagens: ['Achei a consulta da Maísa.'], etapa: 'pos_agendamento', agendar: false,
      agendamento: { nome: '', telefone: '', dia: '', hora: '', unidade: 'paulista', procedimento: '', para_outra_pessoa: false },
      cancelar: false, pausar: false, chamar_humano: false, leitura: 'buscou a consulta da mãe' }
  end
  let(:usage) { { 'input_tokens' => 1000, 'input_tokens_details' => { 'cached_tokens' => 400 }, 'output_tokens' => 100 } }
  let(:reasoning_item) { { 'type' => 'reasoning', 'id' => 'rs_1', 'encrypted_content' => 'cifrado', 'summary' => [] } }
  let(:call_item) do
    { 'type' => 'function_call', 'id' => 'fc_1', 'call_id' => 'call_1', 'name' => 'buscar_consulta', 'arguments' => '{"nome":"Maísa"}' }
  end
  let(:round1) { { 'status' => 'completed', 'output' => [reasoning_item, call_item], 'usage' => usage } }
  let(:round2) do
    { 'status' => 'completed', 'usage' => usage,
      'output' => [{ 'type' => 'message', 'role' => 'assistant', 'content' => [{ 'type' => 'output_text', 'text' => final_hash.to_json }] }] }
  end
  let(:agents) { { 'atendente_pos' => { 'enabled' => true, 'model' => 'gpt-6.2-sol' } } }
  let(:ai_config) { { 'api_key' => 'sk-ant-teste', 'openai_api_key' => 'sk-openai-teste', 'agents' => agents } }

  before do
    CrmSetting.create!(account: account, ai_config: ai_config)
    account.tasks.create!(title: 'Consulta: Maísa Teste', task_type: 'consulta', due_at: tz.now.beginning_of_day + 14.hours,
                          unit: 'paulista', phone: '+5511988887777', creator: admin)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     content: 'minha mãe Maísa tem consulta hoje?')
  end

  def json_response(body, status: 200)
    { status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def service(**opts)
    described_class.new(conversation: conversation, agent_key: 'atendente_pos', **opts)
  end

  def sent_bodies
    bodies = []
    expect(WebMock).to(have_requested(:post, url).with { |req| bodies << JSON.parse(req.body) }.at_least_once)
    bodies
  end

  it 'roda o laço de ferramentas na OpenAI e devolve o mesmo formato do Claude', :aggregate_failures do
    stub_request(:post, url).to_return(json_response(round1), json_response(round2))

    result = service.call
    expect(result[:error]).to be_nil
    expect(result[:mensagens]).to eq(['Achei a consulta da Maísa.'])
    expect(result[:modelo]).to eq('gpt-6.2-sol')
    expect(result[:acoes].first).to include('ferramenta' => 'buscar_consulta', 'ok' => true)

    first, second = sent_bodies
    expect(first).to include('model' => 'gpt-6.2-sol', 'store' => false, 'tool_choice' => 'auto')
    expect(first['input'].first['role']).to eq('developer')
    expect(first['input'].first['content']).to include('REGRAS INEGOCIÁVEIS')
    expect(first['input'].last['content'].first['text']).to include('PACIENTE: minha mãe Maísa tem consulta hoje?')
    expect(first['tools'].pluck('name')).to include('buscar_consulta', 'remarcar_consulta', 'horarios_do_dia', 'abrir_tarefa') # LIFE: as demais dependem da conta
    expect(first['tools'].first).to include('type' => 'function', 'strict' => false)
    expect(first.dig('text', 'format')).to include('type' => 'json_schema', 'strict' => true)
    # volta 2: raciocínio cifrado + pedido voltam inteiros, seguidos do resultado da ferramenta
    expect(second['input'][2]).to eq(reasoning_item)
    expect(second['input'][3]).to eq(call_item)
    expect(second['input'][4]).to include('type' => 'function_call_output', 'call_id' => 'call_1')
    # 🔒 mesma trava do Claude: consulta de outra pessoa não vaza para a IA
    expect(second['input'][4]['output']).not_to include('Maísa')
    expect(WebMock).to have_requested(:post, url).with(headers: { 'Authorization' => 'Bearer sk-openai-teste' }).twice
  end

  it 'grava o gasto com o preço da OpenAI (entrada do cache mais barata)', :aggregate_failures do
    stub_request(:post, url).to_return(json_response(round2))

    service.call
    row = Crm::AiUsage.where(account: account, agent_key: 'atendente_pos').last
    expect(row.model).to eq('gpt-6.2-sol')
    expect(row.input_tokens).to eq(1000)
    expect(row.cache_read_tokens).to eq(400)
    # 600 novos × US$ 2 + 400 do cache × US$ 0,10 + 100 de saída × US$ 10, por milhão
    expect(row.cost_usd.to_f).to be_within(0.0000001).of(((600 * 2.0) + (400 * 0.10) + (100 * 10.0)) / 1_000_000.0)
  end

  it 'na última volta proíbe ferramenta: a IA tem que responder', :aggregate_failures do
    stub_request(:post, url).to_return(*Array.new(described_class::MAX_TOOL_ROUNDS) { json_response(round1) }, json_response(round2))

    expect(service.call[:mensagens]).to be_present
    bodies = sent_bodies
    expect(bodies.size).to eq(described_class::MAX_TOOL_ROUNDS + 1)
    expect(bodies.last['tool_choice']).to eq('none')
  end

  # 🧠 22/11: sem a chave do fornecedor escolhido, o atendente NÃO fica mudo —
  # cai no Claude recomendado (a tela já não deixa salvar gpt sem a chave)
  it 'sem a chave da OpenAI volta ao Claude recomendado e não chama a OpenAI', :aggregate_failures do
    CrmSetting.find_by(account: account).update!(ai_config: ai_config.except('openai_api_key'))

    expect(service.send(:model)).to eq('claude-haiku-4-5')
    expect(service.send(:openai_engine?)).to be(false)
    expect(WebMock).not_to have_requested(:post, url)
  end

  it 'no 🧪 teste, erro da OpenAI vira mensagem clara (chave inválida, sem créditos, resposta cortada)', :aggregate_failures do
    stub_request(:post, url).to_return(json_response({ error: { message: 'bad key' } }, status: 401))
    expect(service(simulation: true).call[:error]).to eq('Chave da OpenAI inválida.')

    stub_request(:post, url).to_return(json_response({ error: { message: 'quota', code: 'insufficient_quota' } }, status: 429))
    expect(service(simulation: true).call[:error]).to include('sem créditos')

    stub_request(:post, url).to_return(json_response({ status: 'incomplete', incomplete_details: { reason: 'max_output_tokens' }, output: [] }))
    expect(service(simulation: true).call[:error]).to include('cortada (max_output_tokens)')
  end

  describe 'rede de segurança (ChatGPT falhou numa conversa real)' do
    let(:claude_usage) do
      instance_double(Anthropic::Usage, input_tokens: 10, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 5)
    end
    let(:claude_message) do
      instance_double(Anthropic::Message, stop_reason: :end_turn, usage: claude_usage,
                                          content: [instance_double(Anthropic::TextBlock, type: :text, text: final_hash.to_json)])
    end
    let(:messages_api) { instance_double(Anthropic::Resources::Messages, create: claude_message) }

    def with_claude(svc)
      allow(svc).to receive(:client).and_return(instance_double(Anthropic::Client, messages: messages_api))
      svc
    end

    it 'o Claude recomendado do agente responde no lugar e fica anotado', :aggregate_failures do
      stub_request(:post, url).to_return(json_response({ error: { message: 'quota', code: 'insufficient_quota' } }, status: 429))

      result = with_claude(service(live: true)).call
      expect(result[:error]).to be_nil
      expect(result[:mensagens]).to eq(['Achei a consulta da Maísa.'])
      expect(result[:modelo]).to eq('claude-haiku-4-5')
      expect(result[:reserva]).to include('ChatGPT falhou', 'sem créditos')
      expect(messages_api).to have_received(:create).with(hash_including(model: 'claude-haiku-4-5'))
    end

    it 'no 🧪 teste o erro aparece (sem reserva)', :aggregate_failures do
      stub_request(:post, url).to_return(json_response({ error: { message: 'bad key' } }, status: 401))

      result = with_claude(service(simulation: true)).call
      expect(result).to eq(error: 'Chave da OpenAI inválida.')
      expect(messages_api).not_to have_received(:create)
    end

    it 'se uma ferramenta já rodou, não repete com o Claude: devolve o erro', :aggregate_failures do
      stub_request(:post, url).to_return(json_response(round1), json_response({ error: { message: 'x' } }, status: 400))

      result = with_claude(service(live: true)).call
      expect(result[:error]).to include('OpenAI respondeu com erro 400')
      expect(messages_api).not_to have_received(:create)
    end
  end

  describe 'quem escolhe o motor' do
    it 'modelo do Claude no cartão = nada muda (não encosta na OpenAI)' do
      CrmSetting.find_by(account: account).update!(ai_config: ai_config.merge('agents' => { 'atendente_pos' => { 'enabled' => true } }))

      expect(service.send(:model)).to eq('claude-haiku-4-5')
      expect(service.send(:openai_engine?)).to be(false)
    end

    # 🧠 22/11: liberdade de modelo — todo agente pode rodar no ChatGPT (e no Gemini)
    it 'agente que não é atendente do WhatsApp também pode usar o ChatGPT' do
      CrmSetting.find_by(account: account).update!(
        ai_config: ai_config.merge('agents' => { 'voice' => { 'enabled' => true, 'model' => 'gpt-6.2-sol' } })
      )
      voice = described_class.new(conversation: conversation, agent_key: 'voice')

      expect(voice.send(:model)).to eq('gpt-6.2-sol')
      expect(voice.engine_model?('gemini-4-neon')).to be(true)
    end

    it 'o motor do teste (🧪) vale só em simulação', :aggregate_failures do
      expect(service(simulation: true, model_override: 'gpt-6-luna').send(:model)).to eq('gpt-6-luna')
      expect(service(simulation: true, model_override: 'claude-sonnet-5').send(:model)).to eq('claude-sonnet-5')
      expect(service(simulation: true, model_override: 'modelo-inventado').send(:model)).to eq('gpt-6.2-sol')
      expect(service(live: true, model_override: 'gpt-6-luna').send(:model)).to eq('gpt-6.2-sol')
    end
  end

  describe Crm::LlmEngines do
    it 'tem preço (entrada, saída, cache) para todo modelo oferecido' do
      expect(described_class::OPENAI_MODELS.values.map { |meta| meta[:price].size }.uniq).to eq([3])
    end

    it 'guarda a data da tabela conferida' do
      expect(Date.iso8601(described_class::OPENAI_PRICING_TABLE_DATE)).to eq(Date.new(2026, 11, 22))
    end
  end
end
