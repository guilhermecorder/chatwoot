require 'rails_helper'

RSpec.describe Crm::ResponderAgentJob do
  let(:account) { create(:account) }
  let(:ai_reply) do
    { mensagens: ['Olá! Aqui é o Guilherme, da CEVICO. Vou te ajudar com isso.', 'É para você ou para um familiar?'],
      etapa: 'recepcao', agendar: false, agendamento: {}, pausar: false, chamar_humano: false,
      leitura: 'Primeiro contato: paciente novo pesquisando refrativa.' }
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:agent_cfg) { { 'enabled' => true, 'mode' => 'shadow', 'inbox_ids' => [inbox.id], 'no_card' => true, 'shadow_daily_cap' => 2 } }
  let!(:settings) do
    CrmSetting.create!(account: account, ai_config: { 'api_key' => 'sk-teste', 'agents' => { 'atendente_agendamento' => agent_cfg } })
  end
  let(:incoming) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'oi, quero fazer refrativa')
  end

  # a IA é simulada: o que importa aqui é o que o job FAZ com a resposta
  before do
    # o ao vivo é trancado por variável de ambiente; aqui destravamos para testar
    stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', true)
    create(:user, account: account, role: :administrator) # a Agenda grava em nome do 1º admin
  end

  def stub_ai(result)
    service = instance_double(Crm::ResponderAgentService, call: result)
    allow(Crm::ResponderAgentService).to receive(:new).and_return(service)
  end

  def run(message = incoming)
    described_class.perform_now(conversation.id, message.id, 'atendente_agendamento')
  end

  describe 'SOMBRA' do
    it 'escreve a nota interna com o que teria respondido e NÃO manda nada ao paciente', :aggregate_failures do
      stub_ai(ai_reply)
      expect { run }.to change { conversation.messages.where(message_type: :activity, private: true).count }.by(1)

      note = conversation.messages.where(message_type: :activity).last
      expect(note.content).to include('🕶️ Sombra').and include('1) Olá! Aqui é o Guilherme').and include('etapa: recepcao')
      expect(note.additional_attributes['cevico_ia_shadow']).to include('agent' => 'atendente_agendamento', 'etapa' => 'recepcao',
                                                                        'trigger_message_id' => incoming.id, 'agendar' => false)
      expect(conversation.messages.where(message_type: :outgoing)).to be_empty
      expect(conversation.reload.additional_attributes['cevico_atendente_wa']).to be_nil # sombra nunca pausa
      expect(account.tasks.count).to eq(0)

      events = settings.reload.ai_config.dig('atendente_agendamento_state', 'events')
      expect(events.first).to include('type' => 'sombra', 'conversation_id' => conversation.display_id)
    end

    it 'diz se a vaga que agendaria é válida na Agenda, sem agendar de verdade', :aggregate_failures do
      slot = Crm::AgendaSlots.free_slots(account, days: 10, per_window: 1).first
      stub_ai(ai_reply.merge(etapa: 'agendamento', agendar: true, pausar: true,
                             agendamento: { nome: 'Maria Silva', telefone: '11999990000', dia: slot[:date].to_s, hora: slot[:time],
                                            unidade: slot[:unit], procedimento: 'refrativa' }))
      run
      note = conversation.messages.where(message_type: :activity).last
      expect(note.content).to include('vaga válida ✓')
      expect(note.additional_attributes.dig('cevico_ia_shadow', 'slot_valid')).to be(true)
      expect(account.tasks.where(task_type: 'consulta')).to be_empty
    end

    it 'não duplica a nota da mesma mensagem (simulador na hora + job da fila depois)' do
      stub_ai(ai_reply)
      run
      expect { run }.not_to(change { conversation.messages.where(message_type: :activity).count })
    end

    it 'não escreve nada se o paciente já mandou outra mensagem depois (anti-picada)' do
      stub_ai(ai_reply)
      older = incoming
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'e o valor?')
      expect { run(older) }.not_to(change { conversation.messages.where(message_type: :activity).count })
    end

    it 'respeita o teto de conversas por dia da sombra (a mesma conversa conta uma vez)', :aggregate_failures do
      stub_ai(ai_reply)
      run
      run(create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'mais uma'))
      other = create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account))
      other_msg = create(:message, account: account, inbox: inbox, conversation: other, message_type: :incoming, content: 'oi')
      described_class.perform_now(other.id, other_msg.id, 'atendente_agendamento')
      third = create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account))
      third_msg = create(:message, account: account, inbox: inbox, conversation: third, message_type: :incoming, content: 'oi')
      expect { described_class.perform_now(third.id, third_msg.id, 'atendente_agendamento') }
        .not_to(change { third.messages.where(message_type: :activity).count })
      expect(settings.reload.ai_config.dig('atendente_agendamento_state', 'events').first).to include('type' => 'teto_sombra')
    end

    it 'com o agente desligado não faz nada' do
      settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'enabled' => false } }))
      stub_ai(ai_reply)
      incoming
      expect { run }.not_to(change { conversation.messages.where(message_type: :activity).count })
    end
  end

  describe 'nota de sombra com ferramentas (192)' do
    it 'guarda e mostra as ações simuladas' do
      acoes = [{ 'ferramenta' => 'buscar_consulta', 'ok' => true, 'resumo' => 'buscou consulta: 1 encontrada (Maísa, hoje 14:00)' },
               { 'ferramenta' => 'remarcar_consulta', 'ok' => true, 'resumo' => 'remarcaria Maísa p/ sáb 27/09 10:00 (simulado)' }]
      stub_ai(ai_reply.merge(acoes: acoes))
      run
      note = conversation.messages.where(message_type: :activity).last
      expect(note.content).to include('🔧 buscou consulta: 1 encontrada (Maísa, hoje 14:00) · remarcaria Maísa p/ sáb 27/09 10:00 (simulado)')
      expect(note.additional_attributes.dig('cevico_ia_shadow', 'acoes').size).to eq(2)
      expect(settings.reload.ai_config.dig('atendente_agendamento_state', 'events').first['note']).to include('🔧 buscou consulta')
    end
  end

  describe 'JANELA AO VIVO (193)' do
    let(:now) { described_class::TZ.parse('2026-09-26 10:00') } # sábado

    it 'within_window?: dias da semana e horas (inclusive virando a noite)', :aggregate_failures do
      expect(described_class.within_window?({}, now)).to be(true)
      expect(described_class.within_window?({ 'live_days' => [6, 0] }, now)).to be(true)
      expect(described_class.within_window?({ 'live_days' => [1, 2] }, now)).to be(false)
      expect(described_class.within_window?({ 'hours_start' => '08:00', 'hours_end' => '12:00' }, now)).to be(true)
      expect(described_class.within_window?({ 'hours_start' => '13:00', 'hours_end' => '18:00' }, now)).to be(false)
      expect(described_class.within_window?({ 'hours_start' => '20:00', 'hours_end' => '11:00' }, now)).to be(true) # vira a noite
      expect(described_class.within_window?({ 'hours_start' => '20:00', 'hours_end' => '09:00' }, now)).to be(false)
      expect(described_class.within_window?({ 'live_days' => ['6'], 'hours_start' => '09:00', 'hours_end' => '' }, now)).to be(true)
    end

    it 'fora da janela continua em SOMBRA (nada sai ao paciente)' do
      travel_to(now) do
        live_cfg = { 'mode' => 'live', 'live_days' => [1] }
        settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => live_cfg }))
        stub_ai(ai_reply)
        run
        expect(conversation.messages.where(message_type: :outgoing)).to be_empty
        expect(conversation.messages.where(message_type: :activity).last.content).to include('🕶️ Sombra')
      end
    end

    it 'dentro da janela responde AO VIVO ao paciente e não escreve nota de sombra', :aggregate_failures do
      travel_to(now) do
        live_cfg = { 'mode' => 'live', 'live_days' => [6, 0], 'hours_start' => '08:00', 'hours_end' => '18:00' }
        settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => live_cfg }))
        service = instance_double(Crm::ResponderAgentService, call: ai_reply)
        allow(Crm::ResponderAgentService).to receive(:new).and_return(service)
        run
        expect(Crm::ResponderAgentService).to have_received(:new).with(hash_including(live: true))
        sent = conversation.messages.where(message_type: :outgoing).order(:id)
        expect(sent.map(&:content)).to eq(ai_reply[:mensagens])
        expect(sent.first.additional_attributes['cevico_ia_agent']).to eq('atendente_agendamento')
        expect(conversation.messages.where(message_type: :activity)).to be_empty
        expect(settings.reload.ai_config.dig('atendente_agendamento_state', 'events').first).to include('type' => 'respondeu')
      end
    end

    it 'ao vivo, remarcação feita pela ferramenta não tenta reservar de novo' do
      travel_to(now) do
        settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'mode' => 'live' } }))
        stub_ai(ai_reply.merge(agendar: true, agendamento: { nome: 'Maria', telefone: '11', dia: '2026-09-28', hora: '08:30', unidade: 'paulista' },
                               acoes: [{ 'ferramenta' => 'remarcar_consulta', 'ok' => true, 'resumo' => 'remarcou Maria p/ seg 28/09 08:30' }]))
        expect_any_instance_of(described_class).not_to receive(:book!) # rubocop:disable RSpec/AnyInstance
        run
        expect(conversation.messages.where(message_type: :outgoing).map(&:content)).to eq(ai_reply[:mensagens])
        expect(account.tasks.count).to eq(0)
      end
    end
  end

  # 🔒 21/09: sem CEVICO_RESPONDERS_LIVE no servidor, "Ao vivo" na tela não vale nada
  context 'without a variável CEVICO_RESPONDERS_LIVE (trava do servidor fechada)' do
    before { stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', false) }

    it 'live_mode? é falso mesmo com mode live e janela aberta' do
      expect(described_class.live_mode?({ 'mode' => 'live', 'live_days' => [] })).to be(false)
    end
  end
end
