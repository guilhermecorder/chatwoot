require 'rails_helper'

# 🗣️ item 200: o Atendente "roda solto" — agendar e encerrar não pausam; só chamar humano
RSpec.describe Crm::ResponderAgentJob do
  let(:job) { described_class.new }

  # auditoria 10/2026 (#443/#458): pause_reason_for virou hand_over! — a pausa
  # agora é testada pelo caminho de verdade (ao vivo, IA simulada)
  describe 'pausa ao vivo' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000') }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
    let(:ai_reply) do
      { mensagens: ['Combinado, obrigado!'], etapa: 'confirmacao', agendar: false, agendamento: {}, pausar: false, chamar_humano: false,
        leitura: 'Paciente encerrou a conversa.' }
    end

    before do
      stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', true)
      create(:user, account: account, role: :administrator)
      CrmSetting.create!(account: account, ai_config: { 'api_key' => 'sk-teste',
                                                        'agents' => { 'atendente_agendamento' => { 'enabled' => true, 'mode' => 'live',
                                                                                                   'inbox_ids' => [inbox.id], 'no_card' => true } } })
    end

    # cada rodada é uma mensagem NOVA do paciente (a anterior já foi respondida)
    def run_with(result)
      incoming = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'oi')
      allow(Crm::ResponderAgentService).to receive(:new).and_return(instance_double(Crm::ResponderAgentService, call: result))
      described_class.perform_now(conversation.id, incoming.id, 'atendente_agendamento')
      conversation.reload.additional_attributes&.dig(described_class::STATE_KEY)
    end

    it 'não pausa depois de agendar nem quando o paciente encerra', :aggregate_failures do
      allow_any_instance_of(described_class).to receive(:book!).and_return(true) # rubocop:disable RSpec/AnyInstance
      expect(run_with(ai_reply.merge(agendar: true, pausar: true))).to be_nil
      expect(run_with(ai_reply.merge(pausar: true))).to be_nil
    end

    it 'pausa só quando pede humano' do
      expect(run_with(ai_reply.merge(chamar_humano: true))).to include('paused' => true, 'reason' => 'chamou_humano')
    end
  end

  it 'espaça os balões em 3 s e tira a carinha que pausava' do
    expect(described_class::BALLOON_GAP).to eq(3)
    account = create(:account)
    inbox = create(:inbox, account: account)
    conversation = create(:conversation, account: account, inbox: inbox)
    incoming = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'oi')
    allow(job).to receive(:sleep)
    texts = ['Deu certo 😊 Consulta confirmada: quarta 30/09 às 13:00', 'PS1 - documento com foto']
    job.send(:send_replies, conversation, texts, incoming.id, 'atendente_agendamento')
    sent = conversation.messages.where(message_type: :outgoing).order(:id).pluck(:content)
    expect(sent).to eq(['Deu certo Consulta confirmada: quarta 30/09 às 13:00', 'PS1 - documento com foto'])
    expect(job).to have_received(:sleep).with(3).once
  end
end
