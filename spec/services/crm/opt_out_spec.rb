require 'rails_helper'

# 🛑 Opt-out automático (varredura de conformidade 20/09)
RSpec.describe Crm::OptOut do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999990000') }

  it 'reconhece pedidos de parar e ignora conversa normal' do
    expect(described_class.opt_out_message?('PARE')).to be(true)
    expect(described_class.opt_out_message?('não quero mais receber mensagens')).to be(true)
    expect(described_class.opt_out_message?('quero remarcar a consulta')).to be(false)
    expect(described_class.opt_out_message?('pare de me ligar? não, pode ligar sim, só queria saber o horário e ver se dá para vir na sexta com a minha mãe')).to be(false)
  end

  it 'aplica a etiqueta nao_perturbe e a campanha/régua passam a excluir o contato' do
    expect(described_class.apply!(contact)).to be(true)
    expect(contact.reload.label_list).to include('nao_perturbe')
    expect(described_class.excluded_contact_ids(account)).to include(contact.id)
    expect(described_class.apply!(contact)).to be(false) # já estava silenciado
  end

  it 'perda_* também silencia' do
    account.labels.create!(title: 'perda_desistiu', color: '#000000')
    contact.add_labels(['perda_desistiu'])
    expect(described_class.excluded_contact_ids(account)).to include(contact.id)
  end
end
