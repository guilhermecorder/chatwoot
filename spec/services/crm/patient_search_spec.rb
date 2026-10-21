require 'rails_helper'

# 🔎 item 346: a busca que puxa o paciente
RSpec.describe Crm::PatientSearch do
  let(:account) { create(:account) }
  let!(:fran) { account.contacts.create!(name: 'Francislene Pereira Borges', phone_number: '+553587017046') }

  before { account.contacts.create!(name: 'Fernanda Simões', phone_number: '+5511977776666') }

  def names(query)
    described_class.new(account: account, query: query).call.map { |r| r[:name] }
  end

  it 'acha pelo nome sem acento, com pedaços de todas as palavras', :aggregate_failures do
    expect(names('francis')).to eq(['Francislene Pereira Borges'])
    expect(names('francis borg')).to eq(['Francislene Pereira Borges'])
    expect(names('simoes')).to eq(['Fernanda Simões'])
    expect(names('francis silva')).to be_empty
  end

  it 'acha pelo telefone com ou sem o 9, com ou sem máscara', :aggregate_failures do
    expect(names('(35) 98701-7046')).to eq(['Francislene Pereira Borges'])
    expect(names('3587017046')).to eq(['Francislene Pereira Borges'])
    expect(names('7046')).to eq(['Francislene Pereira Borges'])
  end

  it 'traz etapa do funil, próxima consulta, origem e alertas', :aggregate_failures do
    pipeline = Crm::Pipeline.create!(account: account, name: 'CEVICO | Jornada do Paciente')
    stage = Crm::Stage.create!(pipeline: pipeline, name: 'Cirurgia Agendada', color: '#FFD700')
    Crm::Contact.create!(contact_id: fran.id, pipeline_id: pipeline.id, stage_id: stage.id)
    admin = create(:user, account: account, role: :administrator)
    account.tasks.create!(title: 'Cirurgia: Francislene', contact: fran, due_at: 2.days.from_now, creator: admin, task_type: 'cirurgia')
    Crm::PatientReview.flag!(fran, 'duas_pessoas', 'teste')

    row = described_class.new(account: account, query: 'francislene').call.first
    expect(row[:stage]).to include(pipeline: 'CEVICO | Jornada do Paciente', name: 'Cirurgia Agendada')
    expect(row[:next_appointment]).to include(type: 'cirurgia')
    expect(row[:last_appointment]).to be_nil
    expect(row[:origin]).to eq('cevico')
    expect(row[:review]).to eq(1)
  end

  it 'dono do telefone: acha o cadastro pelo celular com/sem 9' do
    expect(described_class.phone_owner(account, '35 98701-7046')).to eq(fran)
  end

  it 'busca curta demais não devolve nada' do
    expect(names('f')).to be_empty
  end
end
