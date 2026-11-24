require 'rails_helper'

# 📨 24/11/2026 (LIFE): mensagem modelo só abre a conversa; o conteúdo fica guardado e sai quando o cliente responde
RSpec.describe Crm::PendingContent do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Souza') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  def reply(text)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: text)
  end

  before { described_class.store!(conversation, text: 'Com energia solar você economiza R$ 4.920 em 1 ano.', origin: 'teste') }

  it '"Pode mandar" (o botão): o conteúdo sai e o atendente não responde junto', :aggregate_failures do
    expect(described_class.handle_reply(reply('Pode mandar'))).to eq(:curto)
    sent = conversation.messages.outgoing.last
    expect(sent.content).to eq('Com energia solar você economiza R$ 4.920 em 1 ano.')
    expect(sent.additional_attributes).to include('cevico_conteudo_guardado' => 'teste')
    expect(described_class.pending(conversation.reload)).to be_nil
  end

  it 'respondeu com uma pergunta: o conteúdo sai e o atendente responde depois' do
    expect(described_class.handle_reply(reply('quanto fica a parcela?'))).to eq(:saiu)
    expect(conversation.messages.outgoing.count).to eq(1)
  end

  it '"Agora não": descarta e não manda nada', :aggregate_failures do
    expect(described_class.handle_reply(reply('Agora não'))).to be_nil
    expect(conversation.messages.outgoing).to be_empty
    expect(described_class.pending(conversation.reload)).to be_nil
  end

  it 'guardado há mais de 7 dias não sai' do
    travel_to(8.days.from_now) do
      expect(described_class.handle_reply(reply('Pode mandar'))).to be_nil
      expect(conversation.messages.outgoing).to be_empty
    end
  end

  it 'manda a imagem do resumo junto quando foi guardada' do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('png'), filename: 'resumo.png', content_type: 'image/png')
    described_class.store!(conversation, text: 'Seu resumo:', image_blob_id: blob.id, origin: 'teste')

    described_class.handle_reply(reply('sim'))
    expect(conversation.messages.outgoing.last.attachments.first.file.blob).to eq(blob)
  end
end
