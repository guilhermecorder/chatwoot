require 'rails_helper'

# 🧑‍🏫 item 414 (24/11): CONSULTOR SUPERIOR dos atendentes. O motor principal é
# o ChatGPT barato (simulado por WebMock) e o consultor é o Claude (o cliente
# da tomada universal é um dublê): nenhuma chamada sai de verdade.
RSpec.describe Crm::ResponderConsultant do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:consultor) { { 'enabled' => true, 'model' => 'claude-sonnet-5', 'mode' => 'sombra' } }
  let(:agent) { { 'enabled' => true, 'model' => 'gpt-6-luna', 'consultor' => consultor } }
  let(:ai_config) { { 'api_key' => 'sk-ant-teste', 'openai_api_key' => 'sk-openai-teste', 'agents' => { agent_key => agent } } }
  let!(:settings) { CrmSetting.create!(account: account, ai_config: ai_config) }
  let(:free_slot) { Crm::AgendaSlots.free_slots(account, days: 10, per_window: 1).first }
  let(:messages_api) { instance_double(Anthropic::Resources::Messages) }

  before do
    create(:user, account: account, role: :administrator) # a Agenda trabalha em nome do 1º admin
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     content: 'to com suspeita de glaucoma, quanto é a consulta?')
    allow(Crm::LlmGateway).to receive(:client).and_return(instance_double(Anthropic::Client, messages: messages_api))
  end

  def openai_url
    Crm::LlmEngines::OpenaiResponses::URL
  end

  def agent_key
    'atendente_agendamento'
  end

  def usage
    Crm::LlmGateway::Usage.new(input_tokens: 1000, output_tokens: 100, cache_read_input_tokens: 0, cache_creation_input_tokens: 0)
  end

  def reply(overrides = {})
    { mensagens: ['A avaliação com a Dra. Roberta, especialista em glaucoma, é R$ 300. Quer que eu veja um horário?'], etapa: 'sondagem',
      agendar: false,
      agendamento: { nome: '', telefone: '', dia: '', hora: '', unidade: 'paulista', procedimento: '', para_outra_pessoa: false },
      cancelar: false, pausar: false, chamar_humano: false, leitura: 'suspeita de glaucoma, informou o valor' }.merge(overrides)
  end

  def booking(day, time, unit = 'paulista')
    { nome: 'Maria Silva', telefone: '11999990000', dia: day.to_s, hora: time, unidade: unit, procedimento: 'avaliação',
      para_outra_pessoa: false }
  end

  def json_response(body, status: 200)
    { status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def openai_text(text)
    { 'status' => 'completed', 'usage' => { 'input_tokens' => 1000, 'output_tokens' => 100 },
      'output' => [{ 'type' => 'message', 'role' => 'assistant', 'content' => [{ 'type' => 'output_text', 'text' => text }] }] }
  end

  # o principal (ChatGPT barato) devolve estas respostas, uma por chamada
  def stub_primary(*hashes)
    stub_request(:post, openai_url).to_return(*hashes.map { |hash| json_response(openai_text(hash.is_a?(String) ? hash : hash.to_json)) })
  end

  def claude_message(content, stop_reason: :end_turn)
    content = [Crm::LlmGateway::TextBlock.new(text: content.is_a?(String) ? content : content.to_json)] unless content.is_a?(Array)
    Crm::LlmGateway::Response.new(content: content, stop_reason: stop_reason, usage: usage)
  end

  # o consultor (Claude) devolve estas respostas, uma por chamada
  def stub_consultant(*answers)
    replies = answers.map { |answer| answer.is_a?(Crm::LlmGateway::Response) ? answer : claude_message(answer) }
    allow(messages_api).to receive(:create).and_return(*replies)
  end

  def service(**)
    Crm::ResponderAgentService.new(conversation: conversation, agent_key: agent_key, **)
  end

  # troca a configuração do consultor deste agente
  def consultor!(config)
    settings.update!(ai_config: ai_config.merge('agents' => { agent_key => agent.merge('consultor' => config) }))
  end

  def today_counter
    settings.reload.ai_config.dig("#{agent_key}_state", 'consultor_days', Crm::ConsultantConfig.today) || {}
  end

  def plain(hash)
    JSON.parse(hash.to_json).symbolize_keys
  end

  describe 'desligado = igual a hoje' do
    let(:handoff) { reply(chamar_humano: true) }

    before { stub_primary(handoff) }

    it 'sem a configuração, a resposta do principal sai intocada e ninguém é consultado', :aggregate_failures do
      settings.update!(ai_config: ai_config.merge('agents' => { agent_key => agent.except('consultor') }))

      result = service(live: true).call
      expect(result).to eq(plain(handoff).merge(acoes: [], modelo: 'gpt-6-luna'))
      expect(Crm::LlmGateway).not_to have_received(:client)
      expect(today_counter).to eq({})
    end

    it 'com o interruptor desligado, idem', :aggregate_failures do
      consultor!(consultor.merge('enabled' => false))

      result = service(live: true).call
      expect(result).to eq(plain(handoff).merge(acoes: [], modelo: 'gpt-6-luna'))
      expect(Crm::LlmGateway).not_to have_received(:client)
    end

    it 'ligado, mas sem a chave do fornecedor do modelo escolhido: fica desligado', :aggregate_failures do
      settings.update!(ai_config: ai_config.except('api_key'))

      expect(service(live: true).call).not_to have_key(:consultor)
      expect(Crm::LlmGateway).not_to have_received(:client)
    end

    it 'resposta comum (nenhum gatilho) não consulta nem com o consultor ligado', :aggregate_failures do
      stub_primary(reply)

      expect(service(live: true).call).to eq(plain(reply).merge(acoes: [], modelo: 'gpt-6-luna'))
      expect(Crm::LlmGateway).not_to have_received(:client)
    end

    it 'o mesmo modelo não pede segunda opinião a si mesmo' do
      consultor!(consultor.merge('model' => 'gpt-6-luna'))

      expect(service(live: true).call).not_to have_key(:consultor)
    end
  end

  describe 'gatilho: chamou a equipe sem urgência clínica' do
    let(:handoff) { reply(chamar_humano: true, leitura: 'glaucoma: passei para a equipe') }
    let(:fixed) { reply(leitura: 'glaucoma não exige a equipe: informei e ofereci horário') }

    before do
      stub_primary(handoff)
      stub_consultant(fixed)
    end

    it 'em SOMBRA a resposta não muda: só o registro do que o consultor faria', :aggregate_failures do
      result = service(live: true).call

      expect(result.except(:consultor)).to eq(plain(handoff).merge(acoes: [], modelo: 'gpt-6-luna'))
      expect(result[:consultor]).to include('gatilho' => 'chamar_humano', 'modo' => 'sombra', 'modelo' => 'claude-sonnet-5',
                                            'principal' => 'gpt-6-luna', 'status' => 'ok', 'efeito' => 'evitou_equipe',
                                            'mudou' => true, 'aplicado' => false)
      expect(result[:consultor]['antes']).to include('chamar_humano' => true)
      expect(result[:consultor]['depois']).to include('chamar_humano' => false)
      expect(result[:consultor]['custo_usd']).to be > 0
      expect(today_counter).to include('consultas' => 1, 'mudou' => 1, 'gatilhos' => { 'chamar_humano' => 1 },
                                       'efeitos' => { 'evitou_equipe' => 1 })
      expect(today_counter['aplicadas'].to_i).to eq(0)
    end

    it 'o consultor recebe o mesmo prompt, a mesma conversa e o que o principal ia responder', :aggregate_failures do
      service(live: true).call

      expect(Crm::LlmGateway).to have_received(:client).with(hash_including(model: 'claude-sonnet-5', max_retries: 0))
      expect(messages_api).to have_received(:create) do |**params|
        expect(params[:model]).to eq('claude-sonnet-5')
        expect(params[:system_].first[:text]).to include('REGRAS INEGOCIÁVEIS')
        expect(params.dig(:output_config, :format, :schema)).to eq(Crm::ResponderAgentService::OUTPUT_SCHEMA)
        blocks = params[:messages].first[:content].pluck(:text)
        expect(blocks[0]).to include('PACIENTE: to com suspeita de glaucoma')
        expect(blocks[1]).to include('HORÁRIOS DISPONÍVEIS')
        expect(blocks[2]).to include('SEGUNDA OPINIÃO', 'chamar_humano=true', 'glaucoma: passei para a equipe')
        expect(params[:tools].pluck(:name)).to eq(Crm::ResponderTools::ALL_NAMES)
      end
    end

    it 'em modo ATIVO vale a resposta do consultor (e o gasto dele entra na conta)', :aggregate_failures do
      consultor!(consultor.merge('mode' => 'ativo'))

      svc = service(live: true)
      result = svc.call
      expect(result[:chamar_humano]).to be(false)
      expect(result[:leitura]).to eq('glaucoma não exige a equipe: informei e ofereci horário')
      expect(result[:modelo]).to eq('claude-sonnet-5')
      expect(result[:consultor]).to include('aplicado' => true, 'efeito' => 'evitou_equipe')
      expect(today_counter).to include('aplicadas' => 1)
      # 1.000 de entrada × US$ 2 + 100 de saída × US$ 10 (Sonnet 5), por milhão, somado ao principal
      expect(svc.spent_usd).to be > ((1000 * 2.0) + (100 * 10.0)) / 1_000_000.0
      expect(Crm::AiUsage.where(account: account, agent_key: agent_key).pluck(:model)).to contain_exactly('gpt-6-luna', 'claude-sonnet-5')
    end

    it 'o consultor confirma a equipe: nada muda e fica anotado', :aggregate_failures do
      consultor!(consultor.merge('mode' => 'ativo'))
      stub_consultant(handoff)

      result = service(live: true).call
      expect(result[:chamar_humano]).to be(true)
      expect(result[:modelo]).to eq('gpt-6-luna')
      expect(result[:consultor]).to include('efeito' => 'confirmou_equipe', 'mudou' => false, 'aplicado' => false)
    end

    it 'URGÊNCIA CLÍNICA nunca espera o consultor', :aggregate_failures do
      stub_primary(reply(chamar_humano: true, mensagens: ['Procure um pronto atendimento oftalmológico agora.'],
                         leitura: 'dor forte e perda de visão'))

      result = service(live: true).call
      expect(result).not_to have_key(:consultor)
      expect(Crm::LlmGateway).not_to have_received(:client)
    end

    it 'com caixas escolhidas, só consulta nas conversas dessas caixas', :aggregate_failures do
      other = create(:inbox, account: account)
      consultor!(consultor.merge('inbox_ids' => [other.id]))
      expect(service(live: true).call).not_to have_key(:consultor)

      consultor!(consultor.merge('inbox_ids' => [inbox.id]))
      stub_primary(handoff)
      expect(service(live: true).call[:consultor]).to include('status' => 'ok')
    end

    it 'gatilho desligado na configuração não consulta' do
      consultor!(consultor.merge('triggers' => { 'chamar_humano' => false }))

      expect(service(live: true).call).not_to have_key(:consultor)
    end
  end

  describe 'gatilho: agendar em horário que não validou' do
    let(:active) { consultor.merge('mode' => 'ativo') }
    let(:bad_booking) do
      reply(etapa: 'agendamento', agendar: true, mensagens: ['Deu certo! Sua avaliação está marcada.'],
            agendamento: booking(Date.new(2020, 1, 6), '08:00'), leitura: 'confirmou o horário')
    end

    before { settings.update!(ai_config: ai_config.merge('agents' => { agent_key => agent.merge('consultor' => active) })) }

    it 'horário livre não consulta ninguém', :aggregate_failures do
      stub_primary(reply(etapa: 'agendamento', agendar: true, agendamento: booking(free_slot[:date], free_slot[:time], free_slot[:unit])))

      expect(service(live: true).call).not_to have_key(:consultor)
      expect(Crm::LlmGateway).not_to have_received(:client)
    end

    it 'o consultor desfaz o "Deu certo" e oferece outro horário', :aggregate_failures do
      stub_primary(bad_booking)
      stub_consultant(reply(etapa: 'agendamento', mensagens: ['Esse horário não está mais livre. Pode ser amanhã às 09:00?']))

      result = service(live: true).call
      expect(result[:agendar]).to be(false)
      expect(result[:mensagens]).to eq(['Esse horário não está mais livre. Pode ser amanhã às 09:00?'])
      expect(result[:consultor]).to include('gatilho' => 'vaga_invalida', 'efeito' => 'ofereceu_outro_horario', 'aplicado' => true)
      expect(result[:consultor]['antes']).to include('agendar' => true, 'agendamento' => hash_including('dia' => '2020-01-06'))
    end

    it 'o consultor corrige para um horário livre (ex.: ano errado)', :aggregate_failures do
      stub_primary(bad_booking)
      stub_consultant(bad_booking.merge(agendamento: booking(free_slot[:date], free_slot[:time], free_slot[:unit])))

      result = service(live: true).call
      expect(result[:agendar]).to be(true)
      expect(result[:agendamento]).to include('dia' => free_slot[:date].to_s, 'hora' => free_slot[:time])
      expect(result[:consultor]).to include('efeito' => 'corrigiu_vaga', 'aplicado' => true)
    end

    it 'se o consultor também devolve horário inválido, a resposta dele NÃO é aplicada', :aggregate_failures do
      stub_primary(bad_booking)
      stub_consultant(bad_booking.merge(agendamento: booking(Date.new(2020, 1, 7), '09:00')))

      result = service(live: true).call
      expect(result[:agendamento]).to include('dia' => '2020-01-06')
      expect(result[:modelo]).to eq('gpt-6-luna')
      expect(result[:consultor]).to include('efeito' => 'vaga_ainda_invalida', 'aplicado' => false)
    end

    it 'agendar sem dia e hora também é horário que não validou' do
      stub_primary(reply(etapa: 'agendamento', agendar: true))
      stub_consultant(reply(etapa: 'agendamento', mensagens: ['Qual dia e horário você prefere?']))

      expect(service(live: true).call[:consultor]).to include('gatilho' => 'vaga_invalida')
    end
  end

  describe 'gatilho: resposta vazia ou sem pergunta' do
    let(:active) { consultor.merge('mode' => 'ativo') }
    let(:stuck) { reply(mensagens: ['Combinado, obrigado! A avaliação do Rogério ainda não está reservada.'], etapa: 'agendamento') }
    let(:completed) { reply(mensagens: ['Combinado! Me passa o nome completo e o telefone do Rogério?'], etapa: 'agendamento') }

    before { stub_consultant(completed) }

    it 'sem pergunta numa etapa que conduz com pergunta: consulta (sombra não muda a resposta)', :aggregate_failures do
      stub_primary(stuck)

      result = service(live: true).call
      expect(result[:mensagens]).to eq(stuck[:mensagens])
      expect(result[:consultor]).to include('gatilho' => 'sem_pergunta', 'efeito' => 'completou', 'mudou' => true, 'aplicado' => false)
    end

    it 'no modo ativo a resposta completada é a que vale' do
      consultor!(active)
      stub_primary(stuck)

      expect(service(live: true).call[:mensagens]).to eq(completed[:mensagens])
    end

    it 'fora das etapas marcadas, ou com a resposta já decidida, não consulta', :aggregate_failures do
      stub_primary(reply(mensagens: ['Qualquer dúvida é só chamar.'], etapa: 'pos_agendamento'))
      expect(service(live: true).call).not_to have_key(:consultor)

      stub_primary(reply(mensagens: ['Combinado, obrigado!'], etapa: 'agendamento', pausar: true))
      expect(service(live: true).call).not_to have_key(:consultor)

      custom = consultor.merge('question_stages' => ['recepcao'])
      consultor!(custom)
      stub_primary(stuck)
      expect(service(live: true).call).not_to have_key(:consultor)
    end

    it 'nenhuma mensagem e nenhuma decisão: consulta' do
      stub_primary(reply(mensagens: [], etapa: 'pos_agendamento'))

      expect(service(live: true).call[:consultor]).to include('gatilho' => 'sem_pergunta')
    end

    it 'principal fora do formato: em sombra o erro continua e fica o que o consultor responderia', :aggregate_failures do
      stub_primary('isto não é JSON')

      result = service(live: true).call
      expect(result[:error]).to eq('Resposta da IA fora do formato.')
      expect(result[:consultor]).to include('gatilho' => 'sem_pergunta', 'efeito' => 'respondeu', 'aplicado' => false)
      expect(result[:consultor]['antes']).to eq('erro' => 'Resposta da IA fora do formato.')
    end

    it 'principal fora do formato: no modo ativo o consultor responde no lugar', :aggregate_failures do
      consultor!(active)
      stub_primary('isto não é JSON')

      result = service(live: true).call
      expect(result[:error]).to be_nil
      expect(result[:mensagens]).to eq(completed[:mensagens])
      expect(result[:modelo]).to eq('claude-sonnet-5')
      expect(result[:acoes]).to eq([])
    end
  end

  describe 'redes de segurança' do
    let(:active) { consultor.merge('mode' => 'ativo') }
    let(:handoff) { reply(chamar_humano: true) }
    let(:expected_primary) { plain(handoff).merge(acoes: [], modelo: 'gpt-6-luna') }

    before do
      consultor!(active)
      stub_primary(handoff)
    end

    it 'o consultor falhou (rede, limite, tempo): vale a resposta do principal', :aggregate_failures do
      allow(messages_api).to receive(:create).and_raise(Crm::LlmGateway::Error.new('Claude não respondeu a tempo (ReadTimeout).'))

      result = service(live: true).call
      expect(result.except(:consultor)).to eq(expected_primary)
      expect(result[:consultor]).to include('status' => 'falhou', 'erro' => 'Claude não respondeu a tempo (ReadTimeout).')
      expect(today_counter).to include('consultas' => 1, 'falhas' => 1)
    end

    it 'o consultor devolveu algo fora do formato: vale a resposta do principal', :aggregate_failures do
      stub_consultant('desculpe, não entendi')

      result = service(live: true).call
      expect(result.except(:consultor)).to eq(expected_primary)
      expect(result[:consultor]).to include('status' => 'falhou')
    end

    it 'o consultor passou do tempo entre uma volta e outra: vale a resposta do principal', :aggregate_failures do
      lookup = Crm::LlmGateway::ToolUseBlock.new(id: 'tu_1', name: 'horarios_do_dia', input: { 'dia' => free_slot[:date].to_s })
      stub_consultant(claude_message([lookup], stop_reason: :tool_use), reply)
      # começo, prazo e 1ª volta no segundo 0; a 2ª volta já chega depois do prazo
      allow(described_class).to receive(:now).and_return(0.0, 0.0, 0.0, 999.0)

      result = service(live: true).call
      expect(result.except(:consultor)).to eq(expected_primary)
      expect(result[:consultor]).to include('status' => 'falhou')
      expect(result[:consultor]['erro']).to include('passou do tempo')
      expect(messages_api).to have_received(:create).once
    end

    it 'TETO DIÁRIO atingido: sem consulta, vale a resposta do principal', :aggregate_failures do
      consultor!(active.merge('daily_cap' => 1))
      stub_consultant(handoff)
      service(live: true).call

      stub_primary(handoff)
      result = service(live: true).call
      expect(result.except(:consultor)).to eq(expected_primary)
      expect(result[:consultor]).to include('status' => 'teto')
      expect(messages_api).to have_received(:create).once
      expect(today_counter).to include('consultas' => 1, 'barradas' => 1)
    end

    it 'no 🧪 teste o consultor roda, conta como teste e NÃO gasta o teto do dia', :aggregate_failures do
      consultor!(active.merge('daily_cap' => 1))
      stub_consultant(reply)

      2.times do
        stub_primary(handoff)
        result = service(simulation: true).call
        expect(result[:consultor]).to include('status' => 'ok', 'teste' => true, 'aplicado' => true)
      end
      expect(today_counter).to include('testes' => 2)
      expect(today_counter['consultas'].to_i).to eq(0)
    end

    it 'no 🧪 teste dá para escolher o consultor sem ligá-lo no agente', :aggregate_failures do
      settings.update!(ai_config: ai_config.merge('agents' => { agent_key => agent.except('consultor') }))
      stub_consultant(reply)

      expect(service(simulation: true).call).not_to have_key(:consultor)

      stub_primary(handoff)
      result = service(simulation: true, consultant_override: { 'model' => 'claude-sonnet-5', 'mode' => 'ativo' }).call
      expect(result[:chamar_humano]).to be(false)
      expect(result[:consultor]).to include('modelo' => 'claude-sonnet-5', 'aplicado' => true)
      # fora do teste a escolha da tela não vale nada
      stub_primary(handoff)
      expect(service(live: true, consultant_override: { 'model' => 'claude-sonnet-5', 'mode' => 'ativo' }).call).not_to have_key(:consultor)
    end
  end

  describe 'o consultor nunca escreve na Agenda' do
    let(:config) { Crm::ConsultantConfig.active({ 'consultor' => consultor.merge('mode' => 'ativo') }, ai_config) }
    let(:advisor) do
      described_class.new(account: account, conversation: conversation, agent_key: agent_key, ai_config: ai_config, config: config,
                          system: [{ type: 'text', text: 'prompt' }], user_content: [{ type: 'text', text: 'conversa' }],
                          tool_definitions: Crm::ResponderTools.new(conversation: conversation, agent_key: agent_key, live: true).definitions,
                          primary_model: 'gpt-6-luna')
    end
    let(:handoff) { plain(reply(chamar_humano: true)).merge(acoes: [], modelo: 'gpt-6-luna') }

    it 'se o principal já alterou a Agenda nesta resposta, não há segunda opinião', :aggregate_failures do
      done = handoff.merge(acoes: [{ 'ferramenta' => 'remarcar_consulta', 'ok' => true, 'resumo' => 'remarcou Maria p/ seg 30/11 08:00' }])
      allow(messages_api).to receive(:create)

      result = advisor.review(done)
      expect(result.except(:consultor)).to eq(done)
      expect(result[:consultor]).to include('status' => 'pulou', 'erro' => described_class::SKIP_WROTE)
      expect(messages_api).not_to have_received(:create)
      expect(today_counter).to include('puladas' => 1)
      expect(today_counter['consultas'].to_i).to eq(0)
    end

    it 'ferramenta que escreve é recusada sem executar; a de leitura responde', :aggregate_failures do
      task = account.tasks.create!(title: 'Consulta: Maria Silva', task_type: 'consulta', due_at: 2.days.from_now, unit: 'paulista',
                                   contact_id: contact.id, phone: contact.phone_number, creator: account.users.first)
      write = Crm::LlmGateway::ToolUseBlock.new(id: 'tu_1', name: 'cancelar_consulta', input: { 'id' => task.id })
      task_tool = Crm::LlmGateway::ToolUseBlock.new(id: 'tu_2', name: 'abrir_tarefa', input: { 'motivo' => 'x', 'urgencia' => 'normal' })
      read = Crm::LlmGateway::ToolUseBlock.new(id: 'tu_3', name: 'buscar_consulta', input: {})
      sent = []
      answers = [claude_message([write, task_tool, read], stop_reason: :tool_use), claude_message(reply)]
      allow(messages_api).to receive(:create) do |**params|
        sent << params[:messages].map(&:dup)
        answers.shift
      end

      result = advisor.review(handoff)
      expect(task.reload.canceled_at).to be_nil
      expect(account.tasks.where(task_type: 'consulta').count).to eq(1)
      outcomes = sent.last.last[:content].to_h { |block| [block[:tool_use_id], JSON.parse(block[:content])] }
      expect(outcomes['tu_1']).to include('ok' => false, 'motivo' => described_class::REFUSED_TOOL)
      expect(outcomes['tu_2']).to include('ok' => false)
      expect(outcomes['tu_3']).to include('total' => 1)
      # só a leitura entra no que foi feito; a resposta final é a do consultor
      expect(result[:acoes].pluck('ferramenta')).to eq(['buscar_consulta'])
      expect(result[:chamar_humano]).to be(false)
    end

    it 'na última volta o consultor é obrigado a responder (sem ferramenta)', :aggregate_failures do
      read = Crm::LlmGateway::ToolUseBlock.new(id: 'tu_1', name: 'buscar_consulta', input: {})
      choices = []
      allow(messages_api).to receive(:create) do |**params|
        choices << params[:tool_choice]
        choices.size > described_class::MAX_TOOL_ROUNDS ? claude_message(reply) : claude_message([read], stop_reason: :tool_use)
      end

      advisor.review(handoff)
      expect(choices.size).to eq(described_class::MAX_TOOL_ROUNDS + 1)
      expect(choices.last).to eq(type: 'none')
    end
  end

  describe 'ferramenta consultar_superior (o principal pede orientação)' do
    let(:with_tool) { consultor.merge('mode' => 'ativo', 'tool' => true) }
    let(:ask) do
      { 'status' => 'completed', 'usage' => { 'input_tokens' => 1000, 'output_tokens' => 50 },
        'output' => [{ 'type' => 'function_call', 'id' => 'fc_1', 'call_id' => 'call_1', 'name' => 'consultar_superior',
                       'arguments' => { duvida: 'paciente quer reembolso do convênio, respondo ou chamo a equipe?' }.to_json }] }
    end

    def sent_bodies
      bodies = []
      expect(WebMock).to(have_requested(:post, openai_url).with { |req| bodies << JSON.parse(req.body) }.at_least_once)
      bodies
    end

    it 'com a chave ligada e modo ativo, o principal ganha a ferramenta e recebe a orientação', :aggregate_failures do
      consultor!(with_tool)
      stub_request(:post, openai_url).to_return(json_response(ask), json_response(openai_text(reply.to_json)))
      stub_consultant(claude_message('Responda que a clínica emite recibo para reembolso e siga para os horários. Não chame a equipe.'))

      result = service(live: true).call
      first, second = sent_bodies
      expect(first['tools'].pluck('name')).to eq(Crm::ResponderTools::ALL_NAMES + ['consultar_superior'])
      output = JSON.parse(second['input'].last['output'])
      expect(output).to include('ok' => true)
      expect(output['orientacao']).to include('emite recibo')
      # quem escreve ao paciente continua sendo o principal
      expect(result[:modelo]).to eq('gpt-6-luna')
      expect(result[:mensagens]).to eq(reply[:mensagens])
      expect(result[:acoes].last).to include('ferramenta' => 'consultar_superior', 'ok' => true)
      expect(result[:consultor]).to include('gatilho' => 'ferramenta', 'status' => 'ok', 'efeito' => 'orientou')
      expect(result[:consultor]['duvida']).to include('reembolso')
      expect(today_counter).to include('consultas' => 1, 'gatilhos' => { 'ferramenta' => 1 })
      # a orientação é texto livre: sem formato de saída e sem deixar o consultor usar ferramenta
      expect(messages_api).to have_received(:create).once.with(hash_including(tool_choice: { type: 'none' }))
    end

    it 'o consultor falhou: o principal recebe "siga o Roteiro" e responde sozinho', :aggregate_failures do
      consultor!(with_tool)
      stub_request(:post, openai_url).to_return(json_response(ask), json_response(openai_text(reply.to_json)))
      allow(messages_api).to receive(:create).and_raise(Crm::LlmGateway::Error.new('fora do ar'))

      result = service(live: true).call
      expect(JSON.parse(sent_bodies.last['input'].last['output'])).to include('ok' => false, 'motivo' => described_class::ADVICE_FAILED)
      expect(result[:mensagens]).to eq(reply[:mensagens])
      expect(result[:consultor]).to include('gatilho' => 'ferramenta', 'status' => 'falhou')
    end

    it 'em sombra, ou com a chave desligada, a ferramenta não existe para o principal', :aggregate_failures do
      [consultor.merge('tool' => true), consultor.merge('mode' => 'ativo')].each do |config|
        consultor!(config)
        stub_primary(reply)
        service(live: true).call
      end

      sent_bodies.each { |body| expect(body['tools'].pluck('name')).to eq(Crm::ResponderTools::ALL_NAMES) }
    end
  end

  describe Crm::ConsultantConfig do
    it 'sem nada salvo: desligado, em sombra, com os três gatilhos e o teto padrão', :aggregate_failures do
      config = described_class.normalize({})
      expect(config).to include('enabled' => false, 'mode' => 'sombra', 'tool' => false, 'daily_cap' => 50, 'timeout' => 40, 'inbox_ids' => [])
      expect(config['triggers']).to eq('chamar_humano' => true, 'vaga_invalida' => true, 'sem_pergunta' => true)
      expect(config['question_stages']).to eq(described_class::DEFAULT_QUESTION_STAGES)
      expect(described_class.active({}, ai_config)).to be_nil
    end

    it 'limpa o que chega da tela e guarda o que não veio', :aggregate_failures do
      clean = described_class.sanitize({ enabled: 'true', model: ' claude-opus-5-5 ', mode: 'qualquer', daily_cap: 999_999, timeout: 2,
                                         triggers: { sem_pergunta: false, inventado: true }, question_stages: %w[recepcao inventada] },
                                       { 'mode' => 'ativo', 'tool' => true })
      expect(clean).to include('enabled' => true, 'model' => 'claude-opus-5-5', 'mode' => 'ativo', 'tool' => true,
                               'daily_cap' => described_class::MAX_CAP, 'timeout' => 10, 'question_stages' => ['recepcao'])
      expect(clean['triggers']).to eq('chamar_humano' => true, 'vaga_invalida' => true, 'sem_pergunta' => false)
    end

    it 'soma os dias no resumo para a tela e o Laboratório', :aggregate_failures do
      described_class.record!(account, agent_key, 'gatilho' => 'chamar_humano', 'status' => 'ok', 'efeito' => 'evitou_equipe',
                                                  'mudou' => true, 'aplicado' => true, 'custo_usd' => 0.02)
      described_class.record!(account, agent_key, 'gatilho' => 'vaga_invalida', 'status' => 'falhou', 'custo_usd' => 0.01)
      expect(described_class.reserve!(account, agent_key, 1)).to be(true)
      expect(described_class.reserve!(account, agent_key, 1)).to be(false)

      summary = described_class.summary(settings.reload.ai_config, agent_key)
      expect(summary[:today]).to include(consultas: 1, barradas: 1, mudou: 1, aplicadas: 1, falhas: 1, custo_usd: 0.03)
      expect(summary[:total][:gatilhos]).to eq('chamar_humano' => 1, 'vaga_invalida' => 1)
      expect(summary[:cap]).to eq(50)
    end
  end
end
