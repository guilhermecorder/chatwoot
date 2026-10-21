require 'rails_helper'

# rubocop:disable Rails/SkipsModelValidations

# 🔒 Rodada 6 (#200): unificação de duplicados
#   - leva consulta/card do duplicado (antes: falha por chave estrangeira)
#   - e-mail igual sozinho NÃO junta (mãe e filho com o mesmo e-mail)
#   - as falhas voltam para a tela (preview → last_run)
RSpec.describe Crm::ContactUnificationService do
  subject(:service) { described_class.new(account: account) }

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  after { Redis::Alfred.delete(described_class.last_run_key(account.id)) }

  # o e-mail é único por conta (sem diferenciar maiúsculas) na validação, mas
  # na base real existem variações gravadas por fora da validação
  def com_email(contact, email)
    contact.update_columns(email: email)
    contact
  end

  context 'when o duplicado (mesmo telefone) tem consulta na Agenda' do
    let!(:base) { create(:contact, account: account, name: 'Maria Teste', phone_number: '+5511988887777') }
    let!(:duplicado) do
      create(:contact, account: account, name: 'Maria Teste', phone_number: '+5511999990000').tap do |c|
        c.update_columns(phone_number: '5511988887777', created_at: 1.day.from_now)
      end
    end
    let!(:consulta) do
      Task.create!(account: account, creator: user, title: 'Consulta: Maria Teste', task_type: 'consulta', unit: 'tatuape',
                   contact: duplicado, due_at: 1.day.from_now)
    end

    it 'mescla (antes: failed 1 por chave estrangeira) e a consulta passa para o contato que fica' do
      result = service.apply!
      expect(result).to include(merged: 1, failed: 0)
      expect(Contact.exists?(duplicado.id)).to be(false)
      expect(consulta.reload.contact_id).to eq(base.id)
    end
  end

  context 'when dois contatos têm o mesmo e-mail' do
    it 'NÃO junta pessoas de nomes diferentes (mãe e filho)' do
      create(:contact, account: account, name: 'Maria Silva', email: 'familia@exemplo.com')
      com_email(create(:contact, account: account, name: 'Pedro Silva'), 'Familia@exemplo.com')

      expect(service.preview[:contacts_to_merge]).to eq(0)
      expect(service.apply!).to include(merged: 0, failed: 0)
      expect(account.contacts.count).to eq(2)
    end

    it 'junta quando o nome também bate' do
      create(:contact, account: account, name: 'Maria Silva', email: 'maria@exemplo.com')
      com_email(create(:contact, account: account, name: 'maria  silva'), 'MARIA@exemplo.com')

      expect(service.preview[:contacts_to_merge]).to eq(1)
      expect(service.apply!).to include(merged: 1, failed: 0)
      expect(account.contacts.count).to eq(1)
    end

    it 'junta quando o telefone é a mesma linha (com e sem +55)' do
      create(:contact, account: account, name: 'Maria Silva', email: 'm@exemplo.com', phone_number: '+5511988887777')
      com_email(create(:contact, account: account, name: 'Filha', phone_number: '+11988887777'), 'M@exemplo.com')

      expect(service.preview[:contacts_to_merge]).to eq(1)
    end

    it 'NÃO junta pai e filho (Filho/Júnior) só porque o nome é parecido' do
      create(:contact, account: account, name: 'Jose Carlos Santos', email: 'santos@exemplo.com')
      com_email(create(:contact, account: account, name: 'José Carlos Santos Filho'), 'Santos@exemplo.com')

      expect(service.preview[:contacts_to_merge]).to eq(0)
    end

    it 'NÃO junta cadastro de uma palavra só ("Maria") com outra pessoa de mesmo primeiro nome' do
      create(:contact, account: account, name: 'Maria', email: 'souza@exemplo.com')
      com_email(create(:contact, account: account, name: 'Maria Eduarda Souza'), 'SOUZA@exemplo.com')
      com_email(create(:contact, account: account, name: 'maria'), 'souza@exemplo.com ')

      expect(service.preview[:contacts_to_merge]).to eq(0)
    end

    it 'junta em corrente, sem depender da ordem (A=B pelo nome, B=C pelo telefone)' do
      # ordem "ruim" de propósito: C, A e só depois B (o elo entre os dois)
      create(:contact, account: account, name: 'Outro Nome', email: 'ana@exemplo.com', phone_number: '+5511977776666')
      com_email(create(:contact, account: account, name: 'ana souza lima'), 'ANA@exemplo.com')
      com_email(create(:contact, account: account, name: 'Ana Lima Souza', phone_number: '+11977776666'), 'Ana@exemplo.com')

      expect(service.preview).to include(groups: 1, contacts_to_merge: 2)
    end

    it 'nome "Paciente" (sem informação) não conta como nome igual' do
      create(:contact, account: account, name: 'Paciente', email: 'p@exemplo.com')
      com_email(create(:contact, account: account, name: 'Paciente'), 'P@exemplo.com')

      expect(service.preview[:contacts_to_merge]).to eq(0)
    end
  end

  context 'when uma mesclagem falha' do
    let!(:base) { create(:contact, account: account, name: 'Ana Souza', phone_number: '+5511911112222') }
    let!(:duplicado) do
      create(:contact, account: account, name: 'Ana Souza', phone_number: '+5511900000000').tap do |c|
        c.add_labels(['so_do_duplicado'])
        c.update_columns(phone_number: '5511911112222', created_at: 1.day.from_now)
      end
    end

    before do
      merge = instance_double(ContactMergeAction)
      allow(ContactMergeAction).to receive(:new).and_return(merge)
      allow(merge).to receive(:perform).and_raise(StandardError, 'deu ruim')
    end

    it 'devolve quem falhou e por quê, e a tela vê isso no preview (last_run)' do
      result = service.apply!
      expect(result[:failed]).to eq(1)
      expect(result[:failures].first).to include(contact_id: duplicado.id, base_contact_id: base.id, name: 'Ana Souza')
      expect(result[:failures].first[:reason]).to include('deu ruim')

      last_run = described_class.new(account: account).preview[:last_run]
      expect(last_run['failed']).to eq(1)
      expect(last_run['failures'].first['contact_id']).to eq(duplicado.id)
    end

    it 'não passa as etiquetas do duplicado para a base quando a mesclagem falha' do
      service.apply!
      expect(base.reload.label_list).not_to include('so_do_duplicado')
    end
  end
end
# rubocop:enable Rails/SkipsModelValidations
