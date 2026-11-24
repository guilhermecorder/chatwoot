require 'rails_helper'

# 🧠 22/11: tomada universal — o mesmo pedido no formato da Anthropic sai para
# a OpenAI ou o Gemini e volta no formato da Anthropic
RSpec.describe Crm::LlmGateway do
  let(:cfg) { { 'api_key' => 'sk-ant', 'openai_api_key' => 'sk-openai', 'gemini_api_key' => 'g-key' } }
  let(:schema) do
    { type: 'object', properties: { nota: { type: 'integer' } }, required: %w[nota], additionalProperties: false }
  end
  let(:tools) { [{ name: 'buscar', description: 'busca', input_schema: { type: 'object', properties: { q: { type: 'string' } } } }] }

  describe 'catálogo' do
    it 'reconhece o fornecedor pelo nome do modelo' do
      expect(Crm::LlmCatalog.provider('claude-opus-5-5')).to eq('anthropic')
      expect(Crm::LlmCatalog.provider('gpt-6.2-sol')).to eq('openai')
      expect(Crm::LlmCatalog.provider('o9-mini')).to eq('openai')
      expect(Crm::LlmCatalog.provider('gemini-4-neon')).to eq('google')
      expect(Crm::LlmCatalog.provider('openai:ft-meu-modelo')).to eq('openai')
      expect(Crm::LlmCatalog.api_id('openai:ft-meu-modelo')).to eq('ft-meu-modelo')
      expect(Crm::LlmCatalog.provider('llama-9')).to be_nil
    end

    it 'só deixa usar outro fornecedor com a chave dele salva' do
      expect(Crm::LlmCatalog.usable?({ 'api_key' => 'x' }, 'gemini-4-neon')).to be(false)
      expect(Crm::LlmCatalog.usable?(cfg, 'gemini-4-neon')).to be(true)
    end

    it 'aplica o preço novo na data anunciada' do
      expect(Crm::LlmCatalog.price('gemini-4-carbon', at: Time.zone.parse('2026-11-22'))[0]).to eq(2.0)
      expect(Crm::LlmCatalog.price('gemini-4-carbon', at: Time.zone.parse('2026-12-02'))[0]).to eq(4.0)
    end

    it 'devolve o cliente oficial da Anthropic para o Claude' do
      expect(described_class.client(model: 'claude-sonnet-5', ai_config: cfg)).to be_a(Anthropic::Client)
      expect(described_class.client(model: 'gpt-6.2-sol', ai_config: cfg)).to be_a(Crm::LlmGateway::Client)
    end
  end

  describe 'OpenAI (Responses API)' do
    let(:client) { described_class.client(model: 'gpt-6.2-sol', ai_config: cfg, max_retries: 0) }

    it 'traduz prompt, schema e esforço e devolve blocos no formato da Anthropic' do
      stub = stub_request(:post, 'https://api.openai.com/v1/responses').with do |req|
        body = JSON.parse(req.body)
        body['input'][0] == { 'role' => 'developer', 'content' => 'Você é o analista.' } &&
          body['text']['format']['strict'] == true && body['reasoning'] == { 'effort' => 'high' } && body['store'] == false
      end.to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: {
        id: 'resp_1', status: 'completed',
        output: [{ type: 'message', content: [{ type: 'output_text', text: '{"nota":9}' }] }],
        usage: { input_tokens: 1000, output_tokens: 20, input_tokens_details: { cached_tokens: 800 } }
      }.to_json)

      reply = client.messages.create(model: 'gpt-6.2-sol', max_tokens: 512,
                                     system_: [{ type: 'text', text: 'Você é o analista.', cache_control: { type: 'ephemeral' } }],
                                     output_config: { format: { type: 'json_schema', schema: schema }, effort: 'high' },
                                     messages: [{ role: 'user', content: 'Conversa' }])
      expect(stub).to have_been_requested
      expect(reply.content.find { |b| b.type == :text }.text).to eq('{"nota":9}')
      expect(reply.stop_reason).to eq(:end_turn)
      expect(reply.usage.input_tokens).to eq(200)
      expect(reply.usage.cache_read_input_tokens).to eq(800)
    end

    it 'faz o laço de ferramentas reenviando a saída crua (raciocínio cifrado)' do
      first = { id: 'r1', status: 'completed', usage: {},
                output: [{ type: 'reasoning', encrypted_content: 'xyz' },
                         { type: 'function_call', call_id: 'call_1', name: 'buscar', arguments: '{"q":"agenda"}' }] }
      second = { id: 'r2', status: 'completed', usage: {}, output: [{ type: 'message', content: [{ type: 'output_text', text: 'pronto' }] }] }
      stub_request(:post, 'https://api.openai.com/v1/responses')
        .to_return({ status: 200, headers: { 'Content-Type' => 'application/json' }, body: first.to_json },
                   { status: 200, headers: { 'Content-Type' => 'application/json' }, body: second.to_json })

      params = { model: 'gpt-6.2-sol', max_tokens: 100, tools: tools, messages: [{ role: 'user', content: 'oi' }] }
      reply = client.messages.create(**params)
      use = reply.content.find { |b| b.type == :tool_use }
      expect(reply.stop_reason).to eq(:tool_use)
      expect(use.input).to eq('q' => 'agenda')

      params[:messages] << { role: 'assistant', content: [{ type: 'tool_use', id: use.id, name: use.name, input: use.input }] }
      params[:messages] << { role: 'user', content: [{ type: 'tool_result', tool_use_id: use.id, content: '{"ok":true}' }] }
      reply = client.messages.create(**params)
      expect(reply.content.first.text).to eq('pronto')
      expect(WebMock).to(have_requested(:post, 'https://api.openai.com/v1/responses').with do |req|
        input = JSON.parse(req.body)['input']
        input.any? { |i| i['type'] == 'reasoning' && i['encrypted_content'] == 'xyz' } &&
          input.any? { |i| i['type'] == 'function_call_output' && i['call_id'] == 'call_1' }
      end)
    end

    it 'erro da OpenAI vira Anthropic::Errors::APIError com mensagem em português' do
      stub_request(:post, 'https://api.openai.com/v1/responses')
        .to_return(status: 429, headers: { 'Content-Type' => 'application/json' }, body: { error: { code: 'insufficient_quota',
                                                                                                    message: 'quota' } }.to_json)
      expect { client.messages.create(model: 'gpt-6.2-sol', max_tokens: 10, messages: [{ role: 'user', content: 'oi' }]) }
        .to raise_error(Anthropic::Errors::APIError, /sem créditos/)
    end

    # 24/11: o aviso de limite de velocidade da OpenAI cita a página de billing; com saldo
    # na conta a tela dizia "sem créditos". Agora mostra o motivo que a OpenAI devolveu.
    it 'limite de velocidade (429) não vira "sem créditos" e leva o motivo da OpenAI', :aggregate_failures do
      detail = 'Rate limit reached for gpt-6.2-sol on tokens per min (TPM): Limit 30000. Visit https://platform.openai.com/account/billing'
      stub_request(:post, 'https://api.openai.com/v1/responses')
        .to_return(status: 429, headers: { 'Content-Type' => 'application/json' },
                   body: { error: { code: 'rate_limit_exceeded', message: detail } }.to_json)
      expect { client.messages.create(model: 'gpt-6.2-sol', max_tokens: 10, messages: [{ role: 'user', content: 'oi' }]) }
        .to raise_error(Anthropic::Errors::APIError) { |error|
          expect(error.message).to include('limite de uso atingido (429)', 'tokens per min')
          expect(error.message).not_to include('sem créditos')
        }
    end
  end

  describe 'Gemini (camada compatível do Google)' do
    let(:url) { 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions' }
    let(:client) { described_class.client(model: 'gemini-4-neon', ai_config: cfg, max_retries: 0) }

    it 'traduz e devolve tool_use; na volta reenvia a mensagem crua com a assinatura' do
      call = { id: 'c1', type: 'function', function: { name: 'buscar', arguments: '{"q":"x"}' } }
      assistant = { role: 'assistant', content: nil, extra_content: { google: { thought_signature: 'sig' } }, tool_calls: [call] }
      first = { choices: [{ finish_reason: 'tool_calls', message: assistant }], usage: { prompt_tokens: 50, completion_tokens: 5 } }
      second = { choices: [{ finish_reason: 'stop', message: { role: 'assistant', content: "```json\n{\"nota\":7}\n```" } }],
                 usage: { prompt_tokens: 60, completion_tokens: 6 } }
      stub_request(:post, url).with(headers: { 'Authorization' => 'Bearer g-key' })
                              .to_return({ status: 200, headers: { 'Content-Type' => 'application/json' }, body: first.to_json },
                                         { status: 200, headers: { 'Content-Type' => 'application/json' }, body: second.to_json })

      params = { model: 'gemini-4-neon', max_tokens: 100, system_: 'Prompt', tools: tools,
                 output_config: { format: { type: 'json_schema', schema: schema }, effort: 'max' },
                 messages: [{ role: 'user', content: 'oi' }] }
      reply = client.messages.create(**params)
      use = reply.content.find { |b| b.type == :tool_use }
      expect(use.name).to eq('buscar')
      params[:messages] << { role: 'assistant', content: [use.to_h] }
      params[:messages] << { role: 'user', content: [{ type: 'tool_result', tool_use_id: 'c1', content: 'ok' }] }
      reply = client.messages.create(**params)
      expect(JSON.parse(reply.content.first.text)).to eq('nota' => 7)
      expect(WebMock).to(have_requested(:post, url).with do |req|
        body = JSON.parse(req.body)
        body['reasoning_effort'] == 'xhigh' &&
          body['messages'].any? { |m| m.dig('extra_content', 'google', 'thought_signature') == 'sig' } &&
          body['messages'].any? { |m| m['role'] == 'tool' && m['tool_call_id'] == 'c1' }
      end)
    end

    it 'schema recusado → repete em modo JSON simples' do
      stub_request(:post, url).to_return(
        { status: 400, headers: { 'Content-Type' => 'application/json' }, body: [{ error: { message: 'Invalid JSON schema' } }].to_json },
        { status: 200, headers: { 'Content-Type' => 'application/json' },
          body: { choices: [{ finish_reason: 'stop', message: { content: '{"nota":5}' } }], usage: {} }.to_json }
      )
      reply = client.messages.create(model: 'gemini-4-neon', max_tokens: 10, output_config: { format: { type: 'json_schema', schema: schema } },
                                     messages: [{ role: 'user', content: 'oi' }])
      expect(reply.content.first.text).to eq('{"nota":5}')
      expect(WebMock).to have_requested(:post, url).with(body: hash_including('response_format' => { 'type' => 'json_object' }))
    end
  end

  describe 'agente comum (Crm::AiAgentConfig)' do
    let(:account) { create(:account) }

    it 'roda no Gemini quando o cartão escolhe Gemini e a chave está salva; sem chave, volta ao Claude' do
      setting = CrmSetting.find_or_create_by!(account: account)
      setting.update!(ai_config: cfg.merge('agents' => { 'nps' => { 'enabled' => true, 'model' => 'gemini-4-neon' } }))
      service = Crm::NpsService.allocate
      service.instance_variable_set(:@account, account)
      expect(service.send(:model)).to eq('gemini-4-neon')
      expect(service.send(:api_key)).to eq('g-key')

      setting.update!(ai_config: { 'api_key' => 'sk-ant', 'agents' => { 'nps' => { 'enabled' => true, 'model' => 'gemini-4-neon' } } })
      service = Crm::NpsService.allocate
      service.instance_variable_set(:@account, account)
      expect(service.send(:model)).to eq('claude-haiku-4-5')
    end
  end
end
