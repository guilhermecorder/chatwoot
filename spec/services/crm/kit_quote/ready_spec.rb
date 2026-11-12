require 'rails_helper'

# 🔓 Botão "Gerar orçamento" da conversa: libera quando o cliente mandou a conta de luz ou os dados.
RSpec.describe Crm::KitQuote::Ready do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Fernando') }
  let(:contact) { create(:contact, account: account, name: 'Marcos') }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Life', position: 0) }

  it 'fica travado enquanto não há conta, tarefa nem cartão na coluna do orçamento' do
    expect(described_class.new(account, contact).call).to eq('liberado' => false, 'falta' => described_class::WAITING)
  end

  it 'libera com a conta anotada na ficha do cliente' do
    CrmSetting.find_or_create_by!(account: account)
              .update!(ai_config: { 'ficha_cliente' => { 'campos' => [{ 'chave' => 'conta', 'rotulo' => 'Conta de luz' }] } })
    Crm::ClientSummary.write!(contact, { 'conta' => 'R$ 495' }, by: 'Fernando')
    expect(described_class.new(account, contact).call).to include('liberado' => true, 'motivo' => 'Conta de luz anotada: R$ 495')
  end

  it 'libera quando o atendente abriu a tarefa "Orçamento: conta recebida" (foto da conta, ficha sem valor)' do
    task = account.tasks.create!(title: '🙋 Atendimento · Marcos — Orçamento: conta recebida', creator: admin, assignee: admin,
                                 contact: contact)
    expect(described_class.new(account, contact).call).to include('liberado' => true, 'motivo' => "Conta recebida (tarefa ##{task.id})")
  end

  it 'não libera pela tarefa de outro cliente' do
    other = create(:contact, account: account)
    account.tasks.create!(title: '🙋 Atendimento · Outro — Orçamento: conta recebida', creator: admin, assignee: admin, contact: other)
    expect(described_class.new(account, contact).call['liberado']).to be(false)
  end
end
