require 'rails_helper'

# 🔒 Rodada 4 da auditoria (#66/#174/#229): o Cevico::AttributeMerge é a única
# porta para gravar additional_attributes, agora também em Message (e em
# registro "sujo", com mudança em memória ainda sem save).
RSpec.describe Cevico::AttributeMerge do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let!(:message) do
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation,
                     message_type: :outgoing, status: :sent, additional_attributes: { 'cevico_ia_agent' => 'atendente' })
  end

  it 'na Message, relê a coluna fresca na trava e não apaga a chave que outro escritor gravou' do
    foto_velha = Message.find(message.id) # carregada ANTES da outra gravação
    Message.find(message.id).update_column(:additional_attributes, # rubocop:disable Rails/SkipsModelValidations
                                           { 'cevico_ia_agent' => 'atendente', 'cevico_followup' => true })

    described_class.merge!(foto_velha) { |attrs| attrs.merge('cevico_wa_billing' => { 'billable' => true }) }

    expect(message.reload.additional_attributes).to eq(
      'cevico_ia_agent' => 'atendente', 'cevico_followup' => true, 'cevico_wa_billing' => { 'billable' => true }
    )
  end

  it 'aceita registro com mudança pendente: grava a coluna travada e deixa o resto para o save!' do
    message.status = 'read'

    expect do
      described_class.merge!(message) { |attrs| attrs.merge('cevico_wa_billing' => { 'billable' => false }) }
    end.not_to raise_error

    expect(message.additional_attributes['cevico_wa_billing']).to eq('billable' => false)
    expect(message.changed).to eq(['status']) # a coluna travada não fica "suja"
    message.save!
    expect(message.reload).to have_attributes(status: 'read')
    expect(message.additional_attributes).to eq('cevico_ia_agent' => 'atendente', 'cevico_wa_billing' => { 'billable' => false })
  end

  it 'recusa registro que não tem a coluna' do
    expect { described_class.merge!(account) { |attrs| attrs } }
      .to raise_error(ArgumentError, /não tem additional_attributes/)
  end

  it 'recusa registro com a PRÓPRIA coluna alterada em memória (a mudança sumiria sem aviso)' do
    message.additional_attributes['solto'] = 1
    expect { described_class.merge!(message) { |attrs| attrs.merge('x' => 1) } }
      .to raise_error(ArgumentError, /alterado em memória/)
    expect(Message.find(message.id).additional_attributes).not_to have_key('x')
  end

  it 'continua funcionando na Conversation (caminho de sempre)' do
    described_class.merge!(conversation) { |attrs| attrs.merge('x' => 1) }
    expect(conversation.reload.additional_attributes['x']).to eq(1)
  end
end
