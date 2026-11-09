require 'rails_helper'

# 🔊🛟 09/11/2026 (LIFE): áudio pronto na lista das imagens do roteiro + gatilho que
# garante a foto dos telhados quando a IA pergunta em texto.
RSpec.describe Crm::ScriptImages do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Isabel', phone_number: '+5519999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:legenda) { "Cada tipo de telhado tem um jeito certo de fixar as placas.\n\nO seu se parece com qual? Responde só o número." }

  before do
    CrmSetting.find_or_create_by!(account: account).update!(ai_config: {
                                                              'imagens_roteiro' => [
                                                                { 'chave' => 'telhados', 'quando' => 'na pergunta do telhado',
                                                                  'arquivo' => 'brand-assets/life/roteiro/telhados.jpg', 'legenda' => legenda,
                                                                  'gatilho' => 'tipo de telhado|telha,? laje|laje ou|ou metalic' },
                                                                { 'chave' => 'apresentacao_fernando', 'quando' => 'depois da conta',
                                                                  'arquivo' => 'brand-assets/life/roteiro/fernando-apresentacao.ogg',
                                                                  'legenda' => 'Ouve o Fernando contando quem é a Life:', 'faz_pergunta' => false },
                                                                { 'chave' => 'quebrado', 'quando' => 'nunca', 'gatilho' => '(',
                                                                  'arquivo' => 'brand-assets/life/roteiro/google.jpg' }
                                                              ]
                                                            })
  end

  it 'separa imagem e áudio pela extensão e guarda o gatilho', :aggregate_failures do
    lista = described_class.for(account)
    expect(lista.map { |m| [m['chave'], m['tipo']] }).to eq([%w[telhados imagem], %w[apresentacao_fernando audio], %w[quebrado imagem]])
    expect(lista.first['gatilho']).to eq('tipo de telhado|telha,? laje|laje ou|ou metalic')
    expect(described_class.images(account).pluck('chave')).to eq(%w[telhados quebrado])
    expect(described_class.audios(account).pluck('chave')).to eq(%w[apresentacao_fernando])
  end

  it 'manda o áudio com a frase de apresentação num balão antes (o WhatsApp não aceita legenda em áudio)', :aggregate_failures do
    audio = described_class.audios(account).first
    described_class.send!(conversation, audio, 'atendente_agendamento')
    msgs = conversation.messages.outgoing.order(:id).to_a
    expect(msgs.size).to eq(2)
    expect(msgs.first.content).to eq('Ouve o Fernando contando quem é a Life:')
    expect(msgs.first.attachments).to be_empty
    expect(msgs.first.additional_attributes[described_class::MEDIA_STAMP])
      .to eq('chave' => 'apresentacao_fernando', 'tipo' => 'audio', 'legenda' => true)
    expect(msgs.last.content).to be_nil
    expect(msgs.last.attachments.first.file_type).to eq('audio')
    expect(msgs.last.attachments.first.file.content_type).to eq('audio/ogg')
    expect(msgs.last.additional_attributes[described_class::MEDIA_STAMP]).to eq('chave' => 'apresentacao_fernando', 'tipo' => 'audio')
    expect(described_class.sent_count(conversation, 'apresentacao_fernando')).to eq(2)
  end

  describe '.triggered_by (a IA perguntou em texto o que a foto pergunta)' do
    it 'acha a foto dos telhados numa pergunta em texto, sem acento e sem maiúscula' do
      balao = 'Cada tipo de telhado tem um jeito certo de fixar as placas. O seu é de telha, laje ou METÁLICO?'
      expect(described_class.triggered_by(conversation, balao)&.dig('chave')).to eq('telhados')
    end

    it 'não dispara em comentário sem pergunta, nem em texto que não fala do telhado', :aggregate_failures do
      expect(described_class.triggered_by(conversation, 'Telha, beleza, anotado!')).to be_nil
      expect(described_class.triggered_by(conversation, 'O imóvel é seu?')).to be_nil
      expect(described_class.triggered_by(conversation, '')).to be_nil
    end

    it 'não dispara de novo depois que a foto já foi, e ignora gatilho quebrado' do
      described_class.send!(conversation, described_class.images(account).first, 'atendente_agendamento')
      expect(described_class.triggered_by(conversation, 'O seu telhado é de telha, laje ou metálico?')).to be_nil
      expect(described_class.trigger_regexp('(')).to be_nil
    end
  end
end
