require 'rails_helper'

# 🗣️ item 200: o Atendente "roda solto" — agendar e encerrar não pausam; só chamar humano
RSpec.describe Crm::ResponderAgentJob do
  let(:job) { described_class.new }

  it 'não pausa depois de agendar nem quando o paciente encerra' do
    expect(job.send(:pause_reason_for, { agendar: true, pausar: true, chamar_humano: false }, true)).to be_nil
    expect(job.send(:pause_reason_for, { pausar: true, chamar_humano: false }, false)).to be_nil
  end

  it 'pausa só quando pede humano' do
    expect(job.send(:pause_reason_for, { chamar_humano: true }, false)).to eq('chamou_humano')
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
