require 'rails_helper'

# 🔁 23/11 (atendimento sem buraco) no job do Atendente, AO VIVO e com a IA
# simulada: pausa com prazo vencido não segura a resposta; a IA que voltou sem
# a equipe ter respondido não cala de novo nem duplica a tarefa; o desfecho de
# cada tentativa fica gravado para o resgate; motor reserva entra no registro.
RSpec.describe Crm::ResponderAgentJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:agent_cfg) { { 'enabled' => true, 'mode' => 'live', 'inbox_ids' => [inbox.id], 'no_card' => true } }
  let!(:settings) do
    CrmSetting.create!(account: account, ai_config: { 'api_key' => 'sk-teste', 'agents' => { 'atendente_agendamento' => agent_cfg } })
  end
  let(:ai_reply) do
    { mensagens: ['Claro! Tenho terça às 10h ou quinta às 15h, qual fica melhor?'], etapa: 'agendamento', agendar: false, agendamento: {},
      cancelar: false, pausar: false, chamar_humano: false, leitura: 'Paciente pediu horário.', acoes: [] }
  end
  # passagem SEM urgência clínica (a palavra "urgência" sozinha não marca)
  let(:handoff_reply) do
    ai_reply.merge(mensagens: ['Vou pedir para a equipe conferir o pedido médico, tudo bem?'], etapa: 'sondagem', chamar_humano: true,
                   leitura: 'Exame avulso com pedido médico.')
  end
  let(:state_key) { described_class::STATE_KEY }

  before do
    stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', true)
    create(:user, account: account, role: :administrator) # dono das tarefas de passagem
    # o desfecho vai para o Redis: aqui só conferimos o que o job grava
    allow(described_class).to receive(:mark_outcome)
    allow(described_class).to receive(:outcome).and_return(nil)
  end

  def stub_ai(result)
    allow(Crm::ResponderAgentService).to receive(:new).and_return(instance_double(Crm::ResponderAgentService, call: result))
  end

  def patient(content, minutes_ago: 0)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content,
                     created_at: minutes_ago.minutes.ago)
  end

  def run(message)
    described_class.perform_now(conversation.id, message.id, 'atendente_agendamento')
  end

  def pause!(state)
    Cevico::AttributeMerge.merge!(conversation) { |attrs| attrs.merge(state_key => state) }
  end

  def state
    conversation.reload.additional_attributes[state_key]
  end

  def sent
    conversation.messages.where(message_type: :outgoing).order(:id).pluck(:content)
  end

  def notes
    conversation.messages.where(message_type: :activity).order(:id).pluck(:content)
  end

  def events
    settings.reload.ai_config.dig('atendente_agendamento_state', 'events') || []
  end

  # ── item 2 (camada preguiçosa dentro do job) ─────────────────────────────
  describe 'pausa de quem assumiu (humano_assumiu)' do
    it 'vencida (equipe em silêncio há mais de 2 min): limpa, deixa a nota e responde', :aggregate_failures do
      pause!('paused' => true, 'reason' => 'humano_assumiu', 'by' => 'Vaneide', 'at' => 5.minutes.ago.iso8601)
      stub_ai(ai_reply)

      run(patient('tem horário essa semana?'))
      expect(sent).to eq(ai_reply[:mensagens])
      expect(state).to eq({})
      expect(notes.join).to include('religado sozinho')
    end

    it 'ainda dentro do prazo: silêncio, sem chamar a IA', :aggregate_failures do
      pause!('paused' => true, 'reason' => 'humano_assumiu', 'by' => 'Vaneide', 'at' => 30.seconds.ago.iso8601)
      stub_ai(ai_reply)

      run(patient('tem horário essa semana?'))
      expect(sent).to be_empty
      expect(Crm::ResponderAgentService).not_to have_received(:new)
    end

    it 'a equipe escreveu enquanto o job esperava a vez: a pausa nova é respeitada (estado relido do banco)' do
      message = patient('tem horário essa semana?')
      stub_ai(ai_reply)
      # a pausa entra no banco por OUTRO objeto, depois de o job já ter carregado a conversa
      allow(Crm::MediaReadingService).to receive(:read_pending!) do
        Cevico::AttributeMerge.merge!(Conversation.find(conversation.id)) do |attrs|
          attrs.merge(state_key => { 'paused' => true, 'reason' => 'humano_assumiu', 'at' => Time.current.iso8601 })
        end
        {}
      end

      expect { run(message) }.not_to(change { conversation.messages.where(message_type: :outgoing).count })
    end
  end

  # ── item 3 ───────────────────────────────────────────────────────────────
  describe 'a IA chamou a equipe (chamou_humano)' do
    it 'a pausa guarda a mensagem que a IA respondeu (o prazo conta do que o paciente escrever depois)', :aggregate_failures do
      message = patient('tenho um pedido médico de exame')
      stub_ai(handoff_reply)

      run(message)
      expect(state).to include('paused' => true, 'reason' => 'chamou_humano', 'msg' => message.id)
      expect(state).not_to include('urgente')
    end

    context 'when o paciente escreveu depois e ninguém respondeu em 10 min' do
      let!(:answered) { patient('tenho um pedido médico de exame', minutes_ago: 40) }

      before do
        Crm::HandoffTask.open!(account: account, contact: contact, conversation: conversation, agent_key: 'atendente_agendamento',
                               motivo: 'Exame avulso com pedido médico')
        pause!('paused' => true, 'reason' => 'chamou_humano', 'agent' => 'atendente_agendamento', 'at' => 39.minutes.ago.iso8601,
               'msg' => answered.id)
      end

      it 'a IA volta a responder, com a nota e a marca de pedido pendente', :aggregate_failures do
        stub_ai(ai_reply)

        run(patient('tem horário amanhã?', minutes_ago: 12))
        expect(sent).to eq(ai_reply[:mensagens])
        expect(state).not_to include('paused')
        expect(state['handoff_pending']).to be_present
        expect(notes.join).to include('voltou a responder sozinho')
      end

      it 'se ela pedir a equipe de novo: NÃO cala o paciente outra vez nem abre outra tarefa', :aggregate_failures do
        stub_ai(handoff_reply)

        run(patient('tem horário amanhã?', minutes_ago: 12))
        expect(sent).to eq(handoff_reply[:mensagens])
        expect(state).not_to include('paused')
        expect(account.tasks.where(task_type: 'pos_op').count).to eq(1)
        expect(notes.join).not_to include('pediu ATENDIMENTO HUMANO')
        expect(events.first).to include('type' => 'respondeu')
        expect(events.first['note']).to include('pediu a equipe de novo')
      end

      it 'urgência clínica segue o caminho inteiro: pausa com a marca de urgência', :aggregate_failures do
        stub_ai(handoff_reply.merge(mensagens: ['Procure um pronto atendimento oftalmológico agora, combinado?'],
                                    leitura: 'Dor forte e perda súbita de visão.'))

        run(patient('meu olho está doendo muito', minutes_ago: 12))
        expect(state).to include('paused' => true, 'reason' => 'chamou_humano', 'urgente' => true)
        expect(account.tasks.where(task_type: 'pos_op').count).to eq(1)
      end

      it 'paciente escreveu há menos de 10 min: ainda espera a equipe (sem IA)', :aggregate_failures do
        stub_ai(ai_reply)

        run(patient('tem horário amanhã?', minutes_ago: 3))
        expect(sent).to be_empty
        expect(Crm::ResponderAgentService).not_to have_received(:new)
        expect(state).to include('paused' => true, 'reason' => 'chamou_humano')
      end
    end
  end

  # ── item 5: o desfecho de cada tentativa fica gravado para o resgate ─────
  describe 'desfecho da tentativa' do
    it 'resposta que deu certo: pendente → ok', :aggregate_failures do
      message = patient('oi')
      stub_ai(ai_reply)

      run(message)
      expect(described_class).to have_received(:mark_outcome).with(message.id, 'pendente').ordered
      expect(described_class).to have_received(:mark_outcome).with(message.id, 'ok').ordered
    end

    it 'erro do motor: fica "erro" (o resgate volta nesta mensagem)', :aggregate_failures do
      message = patient('oi')
      stub_ai({ error: 'Your credit balance is too low' })
      allow(Redis::Alfred).to receive(:incr).and_return(4) # as 3 tentativas rápidas já foram gastas
      allow(Redis::Alfred).to receive(:expire)

      run(message)
      expect(described_class).to have_received(:mark_outcome).with(message.id, 'erro')
      expect(described_class).not_to have_received(:mark_outcome).with(message.id, 'ok')
      expect(sent).to be_empty
    end

    it 'um "erro" anterior não é apagado pela tentativa seguinte (é ele que explica o atraso ao modelo)' do
      message = patient('oi')
      allow(described_class).to receive(:outcome).with(message.id).and_return('erro')
      stub_ai(ai_reply)

      run(message)
      expect(described_class).not_to have_received(:mark_outcome).with(message.id, 'pendente')
    end

    it 'erro de configuração (sem chave) não é coisa de tentar de novo' do
      message = patient('oi')
      stub_ai({ error: 'Configure a chave da API em Integrações → Claude.' })

      run(message)
      expect(described_class).to have_received(:mark_outcome).with(message.id, 'config')
    end
  end

  # ── item 4: o motor reserva entra no registro do card ────────────────────
  it 'motor reserva respondeu no lugar: evento próprio no registro, antes do "respondeu"', :aggregate_failures do
    reserva = 'Anthropic · Claude falhou (limite de uso); OpenAI · ChatGPT respondeu no lugar'
    stub_ai(ai_reply.merge(reserva: reserva, modelo: 'gpt-6.2-sol'))

    run(patient('oi'))
    expect(events.first).to include('type' => 'respondeu')
    reserve_event = events.find { |event| event['type'] == 'motor_reserva' }
    expect(reserve_event['note']).to include('ChatGPT respondeu no lugar').and include('gpt-6.2-sol')
    expect(conversation.messages.where(message_type: :outgoing).last.additional_attributes['cevico_ia_model']).to eq('gpt-6.2-sol')
  end
end
