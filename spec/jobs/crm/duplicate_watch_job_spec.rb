require 'rails_helper'

# ⚠️ item 346: paciente novo parecido com um que já existe → alerta nos dois (nada é juntado)
RSpec.describe Crm::DuplicateWatchJob do
  let(:account) { create(:account) }

  def types(contact)
    Crm::PatientReview.list(contact.reload).map { |e| e['tipo'] }
  end

  it 'mesmo celular com/sem o 9 → possível duplicado nos dois', :aggregate_failures do
    old = account.contacts.create!(name: 'Francislene Borges', phone_number: '+553587017046')
    novo = account.contacts.create!(name: 'Francislene Pereira Borges', phone_number: '+5535987017046')
    described_class.perform_now(novo.id)
    expect(types(novo)).to eq(['possivel_duplicado'])
    expect(Crm::PatientReview.list(old.reload).first).to include('outro_contact_id' => novo.id)
  end

  it 'mesmo nome completo (acento e caixa não importam) com telefone diferente → possível duplicado (caso Samuel)' do
    account.contacts.create!(name: 'Samuel De Andrade Simões', phone_number: '+556984930293')
    novo = account.contacts.create!(name: 'samuel de andrade simoes', phone_number: '+5569981341130')
    described_class.perform_now(novo.id)
    expect(types(novo)).to eq(['possivel_duplicado'])
  end

  it 'nome de uma palavra só, nome diferente e telefone diferente não geram alerta' do
    account.contacts.create!(name: 'Maria', phone_number: '+5511911112222')
    account.contacts.create!(name: 'Maria Souza', phone_number: '+5511933334444')
    novo = account.contacts.create!(name: 'Maria', phone_number: '+5511955556666')
    described_class.perform_now(novo.id)
    expect(types(novo)).to be_empty
  end

  it 'nome de duas pessoas no cadastro → alerta "duas pessoas"' do
    novo = account.contacts.create!(name: 'Francislene Pereira Borges E Alice Quadros Schimit', phone_number: '+5535900001111')
    described_class.perform_now(novo.id)
    expect(types(novo)).to eq(['duas_pessoas'])
  end

  it 'todo contato que nasce entra na fila do vigia' do
    expect { account.contacts.create!(name: 'Novo Paciente', phone_number: '+5511977778888') }
      .to have_enqueued_job(described_class)
  end
end
