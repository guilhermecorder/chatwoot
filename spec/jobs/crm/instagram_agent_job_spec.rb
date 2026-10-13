require 'rails_helper'

# 🚧🔒 auditoria 10/2026 (#459 cerca dentro do job + #100 trava por conversa):
# o Atendente Instagram tem as mesmas proteções do Atendente do WhatsApp
RSpec.describe Crm::InstagramAgentJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:incoming) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'oi') }
  let(:ai_reply) do
    { mensagens: ['Olá! Aqui é o Guilherme, da CEVICO.', 'É para você ou para um familiar?'],
      etapa: 'recepcao', agendar: false, agendamento: {}, pausar: false, chamar_humano: false }
  end
  let(:lock_key) { format(Crm::ResponderAgentJob::LOCK_KEY, id: conversation.id) }

  before do
    CrmSetting.create!(account: account, ai_config: { 'api_key' => 'sk-teste', 'agents' => { 'instagram' => { 'enabled' => true } } })
    service = instance_double(Crm::InstagramAgentService, call: ai_reply)
    allow(Crm::InstagramAgentService).to receive(:new).and_return(service)
    allow_any_instance_of(described_class).to receive(:sleep) # rubocop:disable RSpec/AnyInstance
  end

  after { Redis::LockManager.new.unlock(lock_key) }

  def run(message = incoming)
    described_class.perform_now(conversation.id, message.id)
  end

  def sent
    conversation.messages.where(message_type: :outgoing).order(:id)
  end

  it 'responde a mensagem do paciente e solta a trava ao terminar', :aggregate_failures do
    run
    expect(sent.map(&:content)).to eq(ai_reply[:mensagens])
    expect(sent.first.additional_attributes['cevico_ia_agent']).to eq('instagram')
    expect(Redis::LockManager.new.locked?(lock_key)).to be(false)
  end

  it 'cerca dos parceiros: paciente do Oftalmofácil (etiqueta of_) não recebe IA', :aggregate_failures do
    contact.add_labels(%w[oftalmofacil of_clinica_parceira])
    allow(Crm::PartnerGuard).to receive(:block!).and_call_original
    run
    expect(Crm::InstagramAgentService).not_to have_received(:new)
    expect(sent).to be_empty
    expect(Crm::PartnerGuard).to have_received(:block!).with('atendente instagram', conversation: conversation)
  end

  it 'com a conversa ocupada por outro job, NÃO sai: volta à fila em 15 s e responde quando a trava libera', :aggregate_failures do
    Redis::LockManager.new.lock(lock_key, 60)
    expect { run }.to have_enqueued_job(described_class).with(conversation.id, incoming.id)
    expect(Crm::InstagramAgentService).not_to have_received(:new)
    expect(sent).to be_empty

    Redis::LockManager.new.unlock(lock_key)
    run
    expect(sent.map(&:content)).to eq(ai_reply[:mensagens])
    expect(Crm::InstagramAgentService).to have_received(:new).once
  end

  it 'conversa ocupada há tempo demais: para de voltar à fila' do
    Redis::LockManager.new.lock(lock_key, 60)
    allow(Redis::Alfred).to receive(:incr).and_return(Crm::ResponderAgentJob::BUSY_MAX + 1)
    allow(Redis::Alfred).to receive(:expire)
    expect { run }.not_to have_enqueued_job(described_class)
  end

  it 'segundo job da MESMA mensagem não manda os balões de novo', :aggregate_failures do
    run
    expect { run }.not_to change(sent, :count)
    expect(Crm::InstagramAgentService).to have_received(:new).once
  end

  it 'solta a trava mesmo se a IA estourar um erro' do
    allow(Crm::InstagramAgentService).to receive(:new).and_raise(StandardError, 'caiu')
    expect { run }.to raise_error(StandardError, 'caiu')
    expect(Redis::LockManager.new.locked?(lock_key)).to be(false)
  end

  # 🔐 achado #148: a tarefa ⚠️ do Instagram nasce como card do quadro (não
  # 'consulta' sem data, que nenhuma tela desenha) e carimbada pelo robô
  it 'horário que não validou: a tarefa ⚠️ nasce como card do quadro, visível à equipe', :aggregate_failures do
    create(:user, account: account, role: :administrator)
    ai_reply.merge!(agendar: true, agendamento: { 'dia' => 'amanhã', 'hora' => '', 'nome' => 'Maria', 'unidade' => 'tatuape' })
    run
    task = account.tasks.find_by!('title LIKE ?', '⚠️ Confirmar consulta (Instagram)%')
    expect(task.task_type).to eq('Atendimento')
    expect(task.appointment?).to be(false)
    expect(task.unit).to be_nil
    expect(task.cevico_born_via).to eq('robo')
    expect(task.shared_with_team?).to be(true)
    expect(account.tasks.board_cards).to include(task)
  end

  # 📅 auditoria 10/2026 (#103): ORDEM SEGURA — confere e grava ANTES do "Deu certo"
  describe 'agendar ao vivo (ordem segura)' do
    let(:ai_reply) do
      { mensagens: ['Perfeito, anotei tudo: Maria Silva, 11 99999-0000, 20/10 às 10:00. Deu certo 😊'],
        etapa: 'confirmacao', agendar: true, pausar: true, chamar_humano: false,
        agendamento: { 'nome' => 'Maria Silva', 'telefone' => '11999990000', 'dia' => '2026-10-20', 'hora' => '10:00',
                       'unidade' => 'paulista', 'procedimento' => 'avaliação' } }
    end

    before do
      create(:user, account: account, role: :administrator)
      allow(Crm::AgendaSlots).to receive(:doctor_at).and_return(nil)
    end

    it 'vaga que não validou: o paciente NÃO recebe o "Deu certo", recebe o pedido de outro horário e o agente segue ativo',
       :aggregate_failures do
      allow(Crm::AgendaSlots).to receive(:slot_available?).and_return(false)
      run
      expect(sent.map(&:content)).to eq([Crm::ResponderAgentJob::SLOT_TAKEN_TEXT])
      expect(account.tasks.where(task_type: 'consulta')).to be_empty
      expect(account.tasks.find_by('title LIKE ?', '⚠️ Confirmar consulta (Instagram)%')).to be_present
      expect(conversation.reload.additional_attributes['cevico_atendente_ia']).to be_nil # não pausa: a resposta dele precisa de atendimento
    end

    it 'a IA mandou agendar sem dia/hora: pede o dia e a hora (não diz que a vaga foi preenchida) e abre a tarefa ⚠️',
       :aggregate_failures do
      ai_reply[:agendamento].merge!('dia' => '', 'hora' => '')
      run
      expect(sent.map(&:content)).to eq([Crm::ResponderAgentJob::MISSING_SLOT_TEXT])
      expect(account.tasks.where(task_type: 'consulta')).to be_empty
      expect(account.tasks.find_by('title LIKE ?', '⚠️ Confirmar consulta (Instagram)%').description).to include('sem dia/hora')
    end

    it 'a Agenda não gravou (:skipped): o paciente NÃO recebe o "Deu certo" e a tarefa ⚠️ nasce', :aggregate_failures do
      allow(Crm::AgendaSlots).to receive(:slot_available?).and_return(true)
      allow(Crm::AppointmentRecorder).to receive(:record).and_return(:skipped)
      run
      expect(sent.map(&:content)).to eq([Crm::ResponderAgentJob::SLOT_TAKEN_TEXT])
      expect(account.tasks.find_by('title LIKE ?', '⚠️ Confirmar consulta (Instagram)%')).to be_present
      expect(conversation.reload.additional_attributes['cevico_atendente_ia']).to be_nil
    end

    it 'vaga livre: grava na Agenda ANTES de confirmar, sem preço fixo na observação, e pausa', :aggregate_failures do
      allow(Crm::AgendaSlots).to receive(:slot_available?).and_return(true)
      run
      task = account.tasks.find_by!(title: 'Consulta: Maria Silva')
      expect(task.description).not_to include('R$ 150')
      expect(Crm::AppointmentPrice.from_notes(task.description)).to be_nil
      expect(sent.map(&:content)).to eq(ai_reply[:mensagens])
      expect(task.created_at).to be <= sent.first.created_at
      expect(conversation.reload.additional_attributes.dig('cevico_atendente_ia', 'reason')).to eq('agendou')
    end
  end
end
