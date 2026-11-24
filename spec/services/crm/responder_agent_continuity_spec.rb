require 'rails_helper'

# 🔁 23/11 (atendimento sem buraco) no motor dos respondedores:
# - avisos de situação no contexto do modelo (IA que voltou sem a equipe ter
#   respondido; resposta saindo com atraso);
# - motor reserva no sentido que faltava: Claude falhou → ChatGPT, depois Gemini.
# Nenhuma chamada sai de verdade (Claude por dublê; OpenAI por WebMock).
RSpec.describe Crm::ResponderAgentService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:ai_config) { { 'api_key' => 'sk-ant-teste', 'agents' => { 'atendente_agendamento' => { 'enabled' => true } } } }
  let(:state_key) { Crm::ResponderAgentJob::STATE_KEY }

  before do
    create(:user, account: account, role: :administrator)
    CrmSetting.create!(account: account, ai_config: ai_config)
    allow(Crm::ResponderAgentJob).to receive(:outcome).and_return(nil)
  end

  def message(type, content, minutes_ago: 0)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: type, content: content,
                     created_at: minutes_ago.minutes.ago)
  end

  def service(**opts)
    described_class.new(conversation: conversation.reload, agent_key: 'atendente_agendamento', **opts)
  end

  def context(**opts)
    service(**opts).send(:context_block)
  end

  # ── item 3: a IA voltou sem a equipe ter respondido ──────────────────────
  describe 'aviso "você já encaminhou para a equipe"' do
    before do
      message(:incoming, 'tem horário amanhã?')
      Cevico::AttributeMerge.merge!(conversation) do |attrs|
        attrs.merge(state_key => { 'handoff_pending' => { 'at' => 30.minutes.ago.iso8601, 'resumed_at' => Time.current.iso8601 } })
      end
    end

    it 'entra no contexto quando a IA voltou a responder sem resposta da equipe', :aggregate_failures do
      text = context(live: true)

      expect(text).to include('ATENÇÃO: você já encaminhou este assunto para a equipe e ninguém respondeu ainda')
      expect(text).to include('Não prometa de novo que a equipe vai responder')
    end

    it 'não entra na sombra nem depois de 24 h do pedido', :aggregate_failures do
      expect(context(live: false)).not_to include('você já encaminhou este assunto')

      Cevico::AttributeMerge.merge!(conversation) { |attrs| attrs.merge(state_key => { 'handoff_pending' => { 'at' => 2.days.ago.iso8601 } }) }
      expect(context(live: true)).not_to include('você já encaminhou este assunto')
    end

    it 'some quando alguém da equipe responde (a pausa nova sobrescreve a marca)' do
      Cevico::AttributeMerge.merge!(conversation) do |attrs|
        attrs.merge(state_key => { 'paused' => true, 'reason' => 'humano_assumiu', 'at' => Time.current.iso8601 })
      end

      expect(context(live: true)).not_to include('você já encaminhou este assunto')
    end
  end

  # ── item 5: resposta saindo com atraso ───────────────────────────────────
  describe 'aviso de resposta com atraso (mensagem do paciente com mais de 15 min)' do
    it 'motor falhou naquela espera: pede desculpas pela instabilidade e continua de onde parou', :aggregate_failures do
      message(:outgoing, 'Olá! Aqui é o Guilherme, da CEVICO.', minutes_ago: 120)
      waiting = message(:incoming, 'pode ser quinta de manhã?', minutes_ago: 40)
      allow(Crm::ResponderAgentJob).to receive(:outcome).with(waiting.id).and_return('erro')

      text = context(live: true)
      expect(text).to include('ATENÇÃO: esta resposta está saindo com atraso de 40 minutos por uma instabilidade do nosso sistema')
      expect(text).to include("'Desculpa a demora, tivemos uma instabilidade no sistema e só agora consegui te responder.'")
      expect(text).to include('sem se apresentar de novo se já se apresentou e sem recomeçar')
      expect(text).not_to include('primeiro contato do paciente')
    end

    it 'atraso sem erro do motor (pausa que venceu, fora do horário): pede desculpas sem inventar motivo', :aggregate_failures do
      message(:outgoing, 'Olá! Aqui é o Guilherme, da CEVICO.', minutes_ago: 300)
      message(:incoming, 'pode ser quinta de manhã?', minutes_ago: 135)

      text = context(live: true)
      expect(text).to include('saindo com atraso de 2 horas e 15 minutos.')
      expect(text).to include('sem inventar motivo para a demora')
      expect(text).not_to include('instabilidade do nosso sistema')
    end

    it 'primeiro contato que ficou sem resposta: desculpas + recepção normal do roteiro' do
      message(:incoming, 'oi, quero saber da cirurgia', minutes_ago: 20)

      expect(context(live: true)).to include('atraso de 20 minutos').and include('faça a recepção normal do roteiro')
    end

    it 'paciente cutucou agora, mas o motor tinha falhado na mensagem anterior: o atraso conta da que falhou', :aggregate_failures do
      failed = message(:incoming, 'tem horário amanhã?', minutes_ago: 50)
      message(:incoming, 'alguém aí?')
      allow(Crm::ResponderAgentJob).to receive(:outcome).with(failed.id).and_return('erro')

      expect(context(live: true)).to include('atraso de 50 minutos por uma instabilidade')
    end

    it 'resposta na hora, mensagem antiga já respondida, sombra: sem aviso', :aggregate_failures do
      message(:incoming, 'obrigada!', minutes_ago: 90) # ficou sem resposta, mas sem erro do motor
      message(:incoming, 'oi, quero remarcar')
      expect(context(live: true)).not_to include('saindo com atraso')

      message(:outgoing, 'Claro, vamos remarcar.')
      message(:incoming, 'pode ser sexta?', minutes_ago: 0)
      expect(context(live: true)).not_to include('saindo com atraso')

      message(:incoming, 'e aí?', minutes_ago: 0)
      expect(context(live: false)).not_to include('saindo com atraso')
    end
  end

  # ── item 4: motor reserva do Claude ──────────────────────────────────────
  describe 'motor reserva: Claude falhou → ChatGPT, depois Gemini' do
    let(:final_hash) do
      { mensagens: ['Tenho terça às 10h, pode ser?'], etapa: 'agendamento', agendar: false,
        agendamento: { nome: '', telefone: '', dia: '', hora: '', unidade: 'paulista', procedimento: '', para_outra_pessoa: false },
        cancelar: false, pausar: false, chamar_humano: false, leitura: 'pediu horário' }
    end
    let(:openai_url) { Crm::LlmEngines::OpenaiResponses::URL }
    let(:openai_ok) do
      { 'status' => 'completed', 'usage' => { 'input_tokens' => 1000, 'output_tokens' => 100 },
        'output' => [{ 'type' => 'message', 'role' => 'assistant', 'content' => [{ 'type' => 'output_text', 'text' => final_hash.to_json }] }] }
    end
    # o limite de uso da chave da Anthropic chega como erro da API (400)
    let(:claude_down) { Crm::LlmGateway::Error.new('You have reached your specified API usage limits', status: 400) }
    let(:usage) { instance_double(Anthropic::Usage, input_tokens: 10, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 5) }
    let(:reply_message) do
      instance_double(Anthropic::Message, stop_reason: :end_turn, usage: usage,
                                          content: [instance_double(Anthropic::TextBlock, type: :text, text: final_hash.to_json)])
    end
    let(:messages_api) { instance_double(Anthropic::Resources::Messages) }

    before { message(:incoming, 'tem horário essa semana?') }

    def json_response(body, status: 200)
      { status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
    end

    # o cliente (Claude ou tomada universal) é o mesmo dublê: dá para ver com que modelo cada chamada saiu
    def engine(**opts)
      svc = service(**opts)
      allow(svc).to receive(:client).and_return(instance_double(Anthropic::Client, messages: messages_api))
      svc
    end

    context 'with a chave da OpenAI salva' do
      let(:ai_config) { super().merge('openai_api_key' => 'sk-openai-teste', 'gemini_api_key' => 'g-teste') }

      it 'o ChatGPT responde aquela mensagem na mesma hora e fica anotado', :aggregate_failures do
        allow(messages_api).to receive(:create).and_raise(claude_down)
        stub_request(:post, openai_url).to_return(json_response(openai_ok))

        result = engine(live: true).call
        expect(result[:error]).to be_nil
        expect(result[:mensagens]).to eq(['Tenho terça às 10h, pode ser?'])
        expect(result[:modelo]).to eq('gpt-6.2-sol')
        expect(result[:reserva]).to include('Claude falhou').and include('ChatGPT respondeu no lugar')
        expect(messages_api).to have_received(:create).once
        expect(WebMock).to(have_requested(:post, openai_url).with { |req| JSON.parse(req.body)['model'] == 'gpt-6.2-sol' }.once)
      end

      it 'ChatGPT também falhou: o Gemini é a próxima reserva (cada um tentado uma vez, sem laço)', :aggregate_failures do
        models = []
        allow(messages_api).to receive(:create) do |**params|
          models << params[:model]
          raise claude_down if models.size == 1

          reply_message
        end
        stub_request(:post, openai_url).to_return(json_response({ error: { message: 'bad request' } }, status: 400))

        result = engine(live: true).call
        expect(result[:error]).to be_nil
        expect(result[:modelo]).to eq('gemini-4-carbon')
        expect(result[:reserva]).to include('Claude falhou').and include('ChatGPT também').and include('Gemini respondeu no lugar')
        expect(models.last).to eq('gemini-4-carbon')
        expect(models.size).to eq(2)
        expect(WebMock).to have_requested(:post, openai_url).once
      end

      it 'todas falharam: devolve o erro (o job tenta de novo e o resgate insiste), sem chamar ninguém duas vezes', :aggregate_failures do
        allow(messages_api).to receive(:create).and_raise(claude_down)
        stub_request(:post, openai_url).to_return(json_response({ error: { message: 'bad request' } }, status: 400))

        result = engine(live: true).call
        expect(result[:error]).to include('Claude falhou').and include('também')
        expect(result[:error]).not_to match(Crm::ResponderAgentJob::PERMANENT_ERRORS)
        expect(messages_api).to have_received(:create).twice # Claude + Gemini
        expect(WebMock).to have_requested(:post, openai_url).once
      end

      it 'no 🧪 teste o erro aparece (sem reserva)', :aggregate_failures do
        allow(messages_api).to receive(:create).and_raise(claude_down)

        result = engine(simulation: true).call
        expect(result[:error]).to include('usage limits')
        expect(WebMock).not_to have_requested(:post, openai_url)
      end

      it 'reserva desligada na conta (responder_engine_reserve = false): erro como antes', :aggregate_failures do
        CrmSetting.find_by(account: account).update!(ai_config: ai_config.merge('responder_engine_reserve' => false))
        allow(messages_api).to receive(:create).and_raise(claude_down)

        result = engine(live: true).call
        expect(result[:error]).to include('usage limits')
        expect(WebMock).not_to have_requested(:post, openai_url)
      end

      it 'modelo da reserva pode ser trocado na conta' do
        CrmSetting.find_by(account: account).update!(ai_config: ai_config.merge('responder_reserve_openai_model' => 'gpt-6.1-terra'))
        allow(messages_api).to receive(:create).and_raise(claude_down)
        stub_request(:post, openai_url).to_return(json_response(openai_ok))

        expect(engine(live: true).call[:modelo]).to eq('gpt-6.1-terra')
      end
    end

    context 'with só a chave do Gemini salva' do
      let(:ai_config) { super().merge('gemini_api_key' => 'g-teste') }

      it 'o Gemini responde no lugar pela tomada universal', :aggregate_failures do
        models = []
        allow(messages_api).to receive(:create) do |**params|
          models << params[:model]
          raise claude_down if models.size == 1

          reply_message
        end

        result = engine(live: true).call
        expect(result[:error]).to be_nil
        expect(result[:modelo]).to eq('gemini-4-carbon')
        expect(result[:reserva]).to include('Gemini respondeu no lugar')
        expect(models).to eq(%w[claude-sonnet-5 gemini-4-carbon])
      end
    end

    it 'sem chave de outro fornecedor: nada muda (o erro do Claude volta como sempre)' do
      allow(messages_api).to receive(:create).and_raise(claude_down)

      expect(engine(live: true).call[:error]).to include('usage limits')
    end
  end
end
