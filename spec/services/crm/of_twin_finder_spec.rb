require 'rails_helper'

# 👯 Ponta 2 (22/10): paciente criado pelo sync do OftalmoFácil × provável
# gêmeo que já existia aqui. Só lista — nunca junta.
RSpec.describe Crm::OfTwinFinder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:finder) { described_class.new(account, own_provider: 'CATARATA_SP') }

  def created(name, phone, cpf: nil)
    contact = create(:contact, account: account, name: name, phone_number: phone, custom_attributes: cpf ? { 'cpf' => cpf } : {})
    Crm::OftalmofacilSurgery.create!(account: account, item_token: "t#{contact.id}", status_kind: 'agendada', contact_id: contact.id,
                                     match_via: 'created', patient_name: name, provider_name: 'CATARATA_SP', surgery_date: Date.current)
    contact
  end

  def existing(name, phone, cpf: nil, talked: false)
    contact = create(:contact, account: account, name: name, phone_number: phone, custom_attributes: cpf ? { 'cpf' => cpf } : {})
    create(:conversation, account: account, inbox: inbox, contact: contact) if talked
    contact
  end

  def pairs
    finder.call.to_h { |t| [[t.created_id, t.other_id], [t.strength, t.reasons]] }
  end

  it 'acha pelo CPF, pelo telefone quase igual e pelo nome completo', :aggregate_failures do
    by_cpf = created('Maria Aparecida Souza', '+5511900000001', cpf: '12345678901')
    twin_cpf = existing('Cida Souza', '+5511988887777', cpf: '12345678901')
    by_ddd = created('Melissa Lee Soares Leitao', '+5525985410780')
    twin_ddd = existing('Melissa Lee Soares Leitão', '+558585410780')
    by_digit = created('Norbela Da Silva', '+5511988749256')
    twin_digit = existing('Norbela Silva', '+5511988742956')

    found = pairs
    expect(found[[by_cpf.id, twin_cpf.id]]).to eq(['alta', ['mesmo CPF']])
    expect(found[[by_ddd.id, twin_ddd.id]]).to eq(['alta', ['telefone quase igual', 'mesmo nome']])
    expect(found[[by_digit.id, twin_digit.id]]&.first).to eq('alta')
  end

  it 'nome curto contido só vale para quem já conversou; e "pessoas diferentes" não volta', :aggregate_failures do
    hub = created('Eliana Campos de Carvalho', '+5511911112222')
    lead = existing('Eliana Carvalho', '+5511933334444', talked: true)
    existing('Eliana Rocha', '+5511955556666', talked: true)
    quiet = existing('Eliana Campos', '+5511977778888')

    expect(pairs[[hub.id, lead.id]]).to eq(['baixa', ['nome curto contido']])
    expect(pairs.keys).not_to include([hub.id, quiet.id])

    Crm::PatientReview.not_same!(hub.reload, lead.reload)
    expect(pairs.keys).not_to include([hub.id, lead.id])
  end

  it 'nome de 2 palavras igual é força média; homônimo com telefone longe e sem CPF não vira alta' do
    hub = created('Sandra Rodrigues', '+5511962650274')
    other = existing('Sandra Rodrigues', '+5511999725832')

    expect(pairs[[hub.id, other.id]]).to eq(['media', ['mesmo nome']])
  end
end
