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

  # 👂🖼️ item 204: antes de montar a resposta, lê o que faltar e anota no registro do card
  it 'lê áudio/imagem pendentes antes da IA e registra "midia" no card' do
    stub_ai(ai_reply)
    allow(Crm::MediaReadingService).to receive(:read_pending!).with(conversation).and_return('audio' => 1, 'image' => 2)
    run
    events = settings.reload.ai_config.dig('atendente_agendamento_state', 'events')
    midia = events.find { |e| e['type'] == 'midia' }
    expect(midia['note']).to eq('1 áudio(s) transcrito(s) · 2 imagem(ns) lida(s)')
  end

  # 🔁 item 340: antes de responder, espera a leitura do áudio da MENSAGEM que disparou
  it 'espera/lê o áudio da mensagem que disparou antes da IA e soma no registro', :aggregate_failures do
    order = []
    allow(Crm::MediaReadingService).to receive(:settle!) do |msg|
      order << [:settle, msg.id]
      { 'audio' => 1 }
    end
    allow(Crm::MediaReadingService).to receive(:read_pending!) do
      order << [:pending]
      { 'image' => 1 }
    end
    allow(Crm::ResponderAgentService).to receive(:new) do
      order << [:ia]
      instance_double(Crm::ResponderAgentService, call: ai_reply)
    end

    run
    expect(order).to eq([[:settle, incoming.id], [:pending], [:ia]])
    midia = settings.reload.ai_config.dig('atendente_agendamento_state', 'events').find { |e| e['type'] == 'midia' }
    expect(midia['note']).to eq('1 áudio(s) transcrito(s) · 1 imagem(ns) lida(s)')
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

    # 🚨 (#443): ao vivo mas fora da janela, urgência clínica não fica só na nota de sombra
    it 'fora da janela, urgência clínica abre a tarefa 🔴 de verdade (sem responder ao paciente)', :aggregate_failures do
      travel_to(now) do
        live_cfg = { 'mode' => 'live', 'live_days' => [1] }
        settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => live_cfg }))
        stub_ai(ai_reply.merge(chamar_humano: true, mensagens: ['Procure um pronto atendimento oftalmológico agora.'],
                               leitura: 'Dor forte e perda súbita de visão.', acoes: []))
        run
        expect(conversation.messages.where(message_type: :outgoing)).to be_empty
        task = account.tasks.find_by(task_type: 'pos_op')
        expect(task.priority).to eq('urgent')
        expect(task.description).to include('Fora da janela ao vivo')
        expect(settings.reload.ai_config.dig('atendente_agendamento_state', 'events').first).to include('type' => 'urgencia_fora_da_janela')
        expect(conversation.reload.additional_attributes['cevico_atendente_wa']).to be_nil # sombra não pausa
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

    it 'item 291: erro passageiro da IA agenda nova tentativa (até 3) em vez de deixar o paciente sem resposta', :aggregate_failures do
      travel_to(now) do
        live_cfg = { 'mode' => 'live', 'live_days' => [6, 0] }
        settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => live_cfg }))
        stub_ai({ error: 'Overloaded' })
        allow(Redis::Alfred).to receive(:incr).and_return(1, 2, 3, 4)
        allow(Redis::Alfred).to receive(:expire)

        expect { 3.times { run } }.to have_enqueued_job(described_class)
          .with(conversation.id, incoming.id, 'atendente_agendamento').exactly(3).times
        expect { run }.not_to have_enqueued_job(described_class)
        events = settings.reload.ai_config.dig('atendente_agendamento_state', 'events')
        expect(events.last['note']).to include('vou tentar de novo (1/3)')
        expect(events.first['note']).not_to include('vou tentar')
      end
    end

    it 'item 291: erro de configuração não é repetido' do
      travel_to(now) do
        live_cfg = { 'mode' => 'live', 'live_days' => [6, 0] }
        settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => live_cfg }))
        stub_ai({ error: 'Configure a chave da API em Integrações → Claude.' })

        expect { run }.not_to have_enqueued_job(described_class)
      end
    end

    # 💰 auditoria 10/2026 (#132): a IA não grava mais "R$ 150" fixo — o valor vem do pré-configurado (item 324)
    it 'ao vivo, agendar grava a consulta SEM preço fixo na observação (o lembrete usa o pré-configurado)', :aggregate_failures do
      travel_to(now) do
        settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'mode' => 'live' } }))
        stub_ai(ai_reply.merge(agendar: true, agendamento: { nome: 'Maria Silva', telefone: '11999990000', dia: '2026-09-28', hora: '08:30',
                                                             unidade: 'paulista' }))
        allow(Crm::AgendaSlots).to receive_messages(slot_available?: true, doctor_at: nil)
        run
        task = account.tasks.find_by!(title: 'Consulta: Maria Silva')
        expect(task.description).not_to include('R$ 150')
        expect(Crm::AppointmentPrice.from_notes(task.description)).to be_nil
        cfg = Crm::AppointmentPrice::DEFAULTS.merge('avaliacao' => '200,00')
        expect(Crm::AppointmentPrice.resolve(cfg, task)).to include(text: '200,00', source: 'preset')
      end
    end

    it 'ao vivo, agendar sem dia/hora pede o que falta (não diz que o horário foi preenchido) e não grava nada', :aggregate_failures do
      travel_to(now) do
        settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'mode' => 'live' } }))
        stub_ai(ai_reply.merge(agendar: true, agendamento: { nome: 'Maria Silva', telefone: '11999990000', dia: '', hora: '', unidade: 'paulista' }))
        run
        expect(conversation.messages.where(message_type: :outgoing).map(&:content)).to eq([described_class::MISSING_SLOT_TEXT])
        expect(account.tasks.count).to eq(0)
      end
    end

    it 'ao vivo, a Agenda não gravou (:skipped): não confirma ao paciente', :aggregate_failures do
      travel_to(now) do
        settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'mode' => 'live' } }))
        stub_ai(ai_reply.merge(agendar: true, agendamento: { nome: 'Maria Silva', telefone: '11999990000', dia: '2026-09-28', hora: '08:30',
                                                             unidade: 'paulista' }))
        allow(Crm::AgendaSlots).to receive_messages(slot_available?: true, doctor_at: nil)
        allow(Crm::AppointmentRecorder).to receive(:record).and_return(:skipped)
        run
        expect(conversation.messages.where(message_type: :outgoing).map(&:content)).to eq([described_class::SLOT_TAKEN_TEXT])
        expect(conversation.messages.where(message_type: :activity).where('content LIKE ?', '📅%')).to be_empty
      end
    end

    # 👪 item 346: "quero marcar para o meu filho" — cadastro e consulta DELE, amarrados a quem agendou
    describe 'consulta para OUTRA pessoa' do
      def book_for(nome:, telefone:, outra: true)
        settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'mode' => 'live' } }))
        stub_ai(ai_reply.merge(agendar: true, agendamento: { nome: nome, telefone: telefone, dia: '2026-09-28', hora: '08:30',
                                                             unidade: 'paulista', procedimento: 'refrativa', para_outra_pessoa: outra }))
        allow(Crm::AgendaSlots).to receive_messages(slot_available?: true, doctor_at: nil)
        run
      end

      it 'com telefone próprio: a consulta é do paciente novo e os dois ficam amarrados', :aggregate_failures do
        travel_to(now) do
          book_for(nome: 'Ricardo Lima', telefone: '11977776666')
          task = account.tasks.find_by!(title: 'Consulta: Ricardo Lima')
          ricardo = task.contact
          expect(ricardo).not_to eq(contact)
          expect(ricardo.phone_number).to eq('+5511977776666')
          expect(task.phone).to eq('+5511977776666')
          expect(task.description).to include('agendado por Maria Silva')
          expect(ricardo.additional_attributes.dig('agendado_por', 'contact_id')).to eq(contact.id)
          expect(contact.reload.additional_attributes['agendou_para'].first['contact_id']).to eq(ricardo.id)
          expect(account.tasks.where(contact_id: contact.id)).to be_empty
          note = conversation.messages.where(message_type: :activity).where('content LIKE ?', '📅%').last
          expect(note.content).to include('👪 agendado por Maria Silva')
        end
      end

      it 'sem telefone próprio: cadastro só com o nome, consulta com o telefone de quem agendou', :aggregate_failures do
        travel_to(now) do
          book_for(nome: 'Joãozinho Silva', telefone: '11999990000')
          task = account.tasks.find_by!(title: 'Consulta: Joãozinho Silva')
          expect(task.contact).not_to eq(contact)
          expect(task.contact.phone_number).to be_blank
          expect(task.phone).to eq('+5511999990000')
        end
      end

      it 'marcou "outra pessoa" mas o nome e o telefone são do próprio contato: é para ele mesmo' do
        travel_to(now) do
          book_for(nome: 'Maria Silva', telefone: '11999990000')
          expect(account.tasks.find_by!(title: 'Consulta: Maria Silva').contact).to eq(contact)
        end
      end
    end

    it 'ao vivo, remarcação feita pela ferramenta não tenta reservar de novo' do
      travel_to(now) do
        settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'mode' => 'live' } }))
        stub_ai(ai_reply.merge(agendar: true, agendamento: { nome: 'Maria', telefone: '11', dia: '2026-09-28', hora: '08:30', unidade: 'paulista' },
                               acoes: [{ 'ferramenta' => 'remarcar_consulta', 'ok' => true, 'resumo' => 'remarcou Maria p/ seg 28/09 08:30' }]))
        expect_any_instance_of(described_class).not_to receive(:book!) # rubocop:disable RSpec/AnyInstance
        run
        expect(conversation.messages.where(message_type: :outgoing).order(:id).map(&:content)).to eq(ai_reply[:mensagens])
        expect(account.tasks.count).to eq(0)
      end
    end
  end

  # 🚧 auditoria 10/2026 (#63/#98/#253/#459): a cerca dos parceiros mora DENTRO do
  # job — venha de onde vier (listener, resgate, nova tentativa), nada sai
  describe 'cerca dos parceiros' do
    before { contact.add_labels(%w[oftalmofacil of_clinica_parceira]) }

    it 'ao vivo: não chama a IA nem manda balão para paciente do Oftalmofácil', :aggregate_failures do
      settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'mode' => 'live' } }))
      stub_ai(ai_reply)
      allow(Crm::PartnerGuard).to receive(:block!).and_call_original
      run
      expect(Crm::ResponderAgentService).not_to have_received(:new)
      expect(conversation.messages.where(message_type: :outgoing)).to be_empty
      expect(Crm::PartnerGuard).to have_received(:block!).with('atendente atendente_agendamento', conversation: conversation)
    end

    it 'em sombra: nem a nota interna é escrita' do
      stub_ai(ai_reply)
      expect { run }.not_to(change { conversation.messages.where(message_type: :activity).count })
      expect(Crm::ResponderAgentService).not_to have_received(:new)
    end
  end

  # 🔒 auditoria 10/2026 (#100): a mesma mensagem nunca é respondida duas vezes
  describe 'trava por conversa e "já respondi"' do
    let(:lock_key) { format(described_class::LOCK_KEY, id: conversation.id) }

    before do
      settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'mode' => 'live' } }))
      stub_ai(ai_reply)
    end

    after { Redis::LockManager.new.unlock(lock_key) }

    it 'não repete a tentativa pelo Sidekiq (o retry_later e o resgate cuidam disso), mas o erro aparece em "Mortos"' do
      expect(described_class.get_sidekiq_options['retry']).to eq(0)
    end

    it 'com a conversa ocupada por outro job, NÃO sai: volta à fila em 15 s e responde quando a trava libera', :aggregate_failures do
      Redis::LockManager.new.lock(lock_key, 60)
      expect { run }.to have_enqueued_job(described_class).with(conversation.id, incoming.id, 'atendente_agendamento')
      expect(Crm::ResponderAgentService).not_to have_received(:new)
      expect(conversation.messages.where(message_type: :outgoing)).to be_empty

      Redis::LockManager.new.unlock(lock_key)
      run
      expect(conversation.messages.where(message_type: :outgoing).count).to eq(2)
      expect(Crm::ResponderAgentService).to have_received(:new).once
    end

    it 'conversa ocupada há tempo demais: para de voltar à fila (o resgate cuida)' do
      Redis::LockManager.new.lock(lock_key, 60)
      allow(Redis::Alfred).to receive(:incr).and_return(described_class::BUSY_MAX + 1)
      allow(Redis::Alfred).to receive(:expire)
      expect { run }.not_to have_enqueued_job(described_class)
    end

    it 'WhatsApp do Agente de Ligação (voice) depois da mensagem NÃO conta como "já respondi"' do
      incoming
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Tentei ligar e não atendeu.',
                       additional_attributes: { 'cevico_ia_agent' => 'voice' })
      expect { run }.to change { conversation.messages.where(message_type: :outgoing).count }.by(2)
    end

    it 'solta a trava ao terminar (a mensagem seguinte é respondida normalmente)', :aggregate_failures do
      run
      expect(Redis::LockManager.new.locked?(lock_key)).to be(false)
      expect(conversation.messages.where(message_type: :outgoing).count).to eq(2)
    end

    it 'solta a trava mesmo se a IA estourar um erro' do
      allow(Crm::ResponderAgentService).to receive(:new).and_raise(StandardError, 'caiu')
      expect { run }.to raise_error(StandardError, 'caiu')
      expect(Redis::LockManager.new.locked?(lock_key)).to be(false)
    end

    it 'segundo job da MESMA mensagem (resgate depois do original) não manda os balões de novo', :aggregate_failures do
      run
      expect { run }.not_to(change { conversation.messages.where(message_type: :outgoing).count })
      expect(Crm::ResponderAgentService).to have_received(:new).once
    end

    it 'balão do agente ANTES da mensagem do paciente não conta como "já respondi"' do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Oi!',
                       additional_attributes: { 'cevico_ia_agent' => 'atendente_agendamento' })
      incoming
      expect { run }.to change { conversation.messages.where(message_type: :outgoing).count }.by(2)
    end
  end

  # 🚨 auditoria 10/2026 (#443/#457/#458): chamar humano abre tarefa com dono nos
  # três atendentes; urgência não deixa o paciente no silêncio; cancelar=true
  # sem ferramenta cancela de verdade (ou fala a verdade)
  describe 'passagem para humano e cancelamento AO VIVO (#443/#457/#458)' do
    let(:vaneide) { create(:user, account: account, role: :agent, name: 'Vaneide') }
    let(:handoff_reply) do
      ai_reply.merge(mensagens: ['Pelo que você descreve, o ideal é procurar um pronto atendimento oftalmológico agora, combinado?'],
                     etapa: 'sondagem', chamar_humano: true, leitura: 'Dor forte e perda súbita de visão: urgência.', acoes: [])
    end

    def new_incoming(content)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content)
    end

    before do
      settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'mode' => 'live' } }))
    end

    it 'chamar_humano no Atendente de Agendamento abre tarefa urgente com responsável, aviso no Radar e pausa por urgência', :aggregate_failures do
      settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'task_assignee_id' => vaneide.id } }))
      stub_ai(handoff_reply)
      run
      task = account.tasks.find_by(task_type: 'pos_op')
      expect(task).to be_present
      expect(task.priority).to eq('urgent')
      expect(task.assignee).to eq(vaneide)
      expect(task.title).to start_with('🔴 Atendimento · Maria Silva')
      alert = settings.reload.ai_config.dig('opportunity_state', 'alerts').last
      expect(alert).to include('kind' => 'atendimento_atencao', 'task_id' => task.id, 'user_id' => vaneide.id, 'acao' => 'Falar com o paciente agora')
      expect(conversation.reload.additional_attributes['cevico_atendente_wa'])
        .to include('paused' => true, 'reason' => 'chamou_humano', 'urgente' => true)
      expect(conversation.messages.where(message_type: :outgoing).count).to eq(1)
      expect(conversation.messages.where(message_type: :activity).pluck(:content).join).to include('tarefa aberta no Meu Painel')
    end

    it 'sem responsável configurado, a tarefa vai para o administrador da conta' do
      stub_ai(handoff_reply)
      run
      expect(account.tasks.find_by(task_type: 'pos_op').assignee).to eq(account.administrators.order(:id).first)
    end

    it 'chamar_humano sem urgência clínica abre tarefa NORMAL (sem vermelho no Radar) e pausa sem a marca de urgência', :aggregate_failures do
      # a palavra "urgência" sozinha ("sem urgência") não pode marcar a conversa como urgente
      stub_ai(handoff_reply.merge(mensagens: ['Vou pedir para a equipe conferir o pedido médico, tudo bem?'],
                                  leitura: 'Exame avulso com pedido médico, sem urgência.'))
      run
      task = account.tasks.find_by(task_type: 'pos_op')
      expect(task.priority).to eq('high')
      expect(task.title).to start_with('🙋 Atendimento')
      expect(Array(settings.reload.ai_config.dig('opportunity_state', 'alerts')).map { |a| a['kind'] }).not_to include('atendimento_atencao')
      state = conversation.reload.additional_attributes['cevico_atendente_wa']
      expect(state).to include('paused' => true)
      expect(state).not_to include('urgente')
    end

    it 'depois que uma pessoa da equipe respondeu, a mensagem seguinte do paciente pausado por urgência fica em silêncio', :aggregate_failures do
      stub_ai(handoff_reply)
      run
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'vem agora pra clínica',
                       sender: vaneide)
      expect { run(new_incoming('ok, estou indo')) }.not_to(change { conversation.messages.where(message_type: :outgoing).count })
      expect(Crm::ResponderAgentService).to have_received(:new).once
    end

    it 'pausado por urgência, a mensagem seguinte recebe a orientação fixa sem chamar a IA (uma vez por hora)', :aggregate_failures do
      stub_ai(handoff_reply)
      run
      run(new_incoming('piorou, e agora?'))
      expect(Crm::ResponderAgentService).to have_received(:new).once
      sent = conversation.messages.where(message_type: :outgoing).order(:id)
      expect(sent.count).to eq(2)
      expect(sent.last.content).to eq(described_class::URGENT_WAIT_TEXT)
      state = conversation.reload.additional_attributes['cevico_atendente_wa']
      expect(state).to include('paused' => true, 'urgente' => true)
      expect(state['orientacao_at']).to be_present
      expect { run(new_incoming('socorro')) }.not_to(change { conversation.messages.where(message_type: :outgoing).count })
      expect(settings.reload.ai_config.dig('atendente_agendamento_state', 'events').first).to include('type' => 'orientacao_urgencia')
    end

    it 'pausado sem urgência, a mensagem seguinte fica em silêncio (a equipe assume)' do
      conversation.update!(additional_attributes: { 'cevico_atendente_wa' => { 'paused' => true, 'reason' => 'chamou_humano' } })
      stub_ai(ai_reply)
      expect { run }.not_to(change { conversation.messages.where(message_type: :outgoing).count })
      expect(Crm::ResponderAgentService).not_to have_received(:new)
    end

    describe 'cancelar=true sem a IA ter chamado a ferramenta (#457)' do
      let(:admin) { account.administrators.first }
      let(:tz) { Crm::AgendaSlots::TZ }
      let(:cancel_reply) do
        ai_reply.merge(mensagens: ['Tudo bem, sua consulta será cancelada.', 'Te chamo daqui a duas semanas pra ver se faz sentido remarcar?'],
                       etapa: 'reagendamento', cancelar: true, leitura: 'Paciente manteve o cancelamento.', acoes: [])
      end

      def consulta(title, phone:, contact: nil)
        account.tasks.create!(title: title, task_type: 'consulta', due_at: tz.now + 3.days, unit: 'paulista', phone: phone,
                              contact: contact, creator: admin, status: :todo)
      end

      it 'cancela a consulta do PRÓPRIO contato pela ferramenta ANTES de falar e deixa o rastro', :aggregate_failures do
        own = consulta('Consulta: Maria Silva', phone: '+5511999990000', contact: contact)
        stub_ai(cancel_reply)
        run
        expect(own.reload.canceled_at).to be_present
        expect(own.description).to include('Cancelada pelo Atendente de Agendamento')
        expect(conversation.messages.where(message_type: :outgoing).order(:id).map(&:content)).to eq(cancel_reply[:mensagens])
        expect(settings.reload.ai_config.dig('opportunity_state', 'alerts').last).to include('kind' => 'agente_cancelou', 'task_id' => own.id)
        expect(settings.ai_config.dig('atendente_agendamento_state', 'events').first['note']).to include('cancelou a consulta de Maria Silva')
        expect(account.tasks.where(task_type: 'pos_op')).to be_empty
      end

      it 'sem consulta própria na Agenda: NÃO diz que cancelou, abre tarefa para a equipe e fala a verdade', :aggregate_failures do
        other = consulta('Consulta: João Pereira', phone: '+5511977776666')
        stub_ai(cancel_reply)
        run
        expect(other.reload.canceled_at).to be_nil
        expect(conversation.messages.where(message_type: :outgoing).map(&:content)).to eq([described_class::CANCEL_PENDING_TEXT])
        handoff = account.tasks.find_by(task_type: 'pos_op')
        expect(handoff.title).to include('cancelar a consulta')
        expect(handoff.assignee).to eq(admin)
        expect(settings.reload.ai_config.dig('atendente_agendamento_state', 'events').first).to include('type' => 'cancelar_pendente')
        # a equipe assume daqui: pausa como em qualquer passagem (senão o "ok" seguinte repetiria o pedido)
        expect(conversation.reload.additional_attributes['cevico_atendente_wa']).to include('paused' => true, 'reason' => 'chamou_humano')
        expect(conversation.messages.where(message_type: :activity).pluck(:content).join).to include('tarefa aberta no Meu Painel')
      end

      it 'IA chamou cancelar_consulta com id errado (não encontrada) e ainda marcou cancelar=true: cancela a do próprio contato antes de falar',
         :aggregate_failures do
        own = consulta('Consulta: Maria Silva', phone: '+5511999990000', contact: contact)
        wrong = [{ 'ferramenta' => 'cancelar_consulta', 'ok' => false, 'resumo' => 'Consulta não encontrada (confira o id com buscar_consulta).' }]
        stub_ai(cancel_reply.merge(acoes: wrong))
        run
        expect(own.reload.canceled_at).to be_present
        expect(conversation.messages.where(message_type: :outgoing).order(:id).map(&:content)).to eq(cancel_reply[:mensagens])
      end

      it 'pedido de cancelar a consulta da MÃE: não cancela a do próprio contato no lugar; tarefa para a equipe', :aggregate_failures do
        own = consulta('Consulta: Maria Silva', phone: '+5511999990000', contact: contact)
        stub_ai(cancel_reply.merge(leitura: 'Paciente quer cancelar a consulta da mãe e não vai remarcar.'))
        run
        expect(own.reload.canceled_at).to be_nil
        expect(conversation.messages.where(message_type: :outgoing).map(&:content)).to eq([described_class::CANCEL_PENDING_TEXT])
        expect(account.tasks.find_by(task_type: 'pos_op').title).to include('OUTRA pessoa')
      end

      it 'cancelar junto com chamar_humano por urgência: a passagem não se perde (pausa com a marca de urgência)', :aggregate_failures do
        stub_ai(cancel_reply.merge(chamar_humano: true, leitura: 'Quer cancelar porque está com dor forte no olho.'))
        run
        state = conversation.reload.additional_attributes['cevico_atendente_wa']
        expect(state).to include('paused' => true, 'reason' => 'chamou_humano', 'urgente' => true)
        expect(account.tasks.find_by(task_type: 'pos_op').priority).to eq('urgent')
      end

      it 'se a IA já chamou cancelar_consulta e a ferramenta recusou (outra pessoa), não cancela a do contato no lugar', :aggregate_failures do
        own = consulta('Consulta: Maria Silva', phone: '+5511999990000', contact: contact)
        refused = [{ 'ferramenta' => 'cancelar_consulta', 'ok' => false, 'resumo' => 'Pediu para cancelar a consulta de outra pessoa: não fez' }]
        stub_ai(cancel_reply.merge(mensagens: ['Essa consulta é de outra pessoa; a equipe vai cuidar disso com o titular, tudo bem?'],
                                   acoes: refused))
        run
        expect(own.reload.canceled_at).to be_nil
        expect(conversation.messages.where(message_type: :outgoing).count).to eq(1)
        expect(account.tasks.where(task_type: 'pos_op')).to be_empty
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
