require 'rails_helper'

# 🔒 auditoria 10/10 (#99/#442): agendar pela IA com o telefone de OUTRA pessoa não pode trocar o dono da consulta dela
RSpec.describe Crm::AppointmentRecorder do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:tz) { Crm::AgendaSlots::TZ }
  let(:tomorrow_10) { tz.now.beginning_of_day + 1.day + 10.hours }
  let(:next_week_15) { tz.now.beginning_of_day + 7.days + 15.hours }
  let(:caller) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000') }
  let(:mother) { create(:contact, account: account, name: 'Maísa Teste', phone_number: '+5511988887777') }
  let!(:mother_task) do
    account.tasks.create!(title: 'Consulta: Maísa Teste', task_type: 'consulta', due_at: tomorrow_10, unit: 'paulista',
                          phone: '+5511988887777', contact: mother, creator: admin, status: :todo)
  end

  def record(name:, phone:, contact: caller)
    described_class.record(account: account, contact: contact,
                           result: { found: true, starts_at: next_week_15, name: name, phone: phone, unit: 'paulista' })
  end

  it 'nome diferente + telefone da outra pessoa: nasce consulta nova e a dela fica como estava', :aggregate_failures do
    expect(record(name: 'Maria Silva', phone: '+5511988887777')).to eq(:created)
    expect(mother_task.reload.contact).to eq(mother)
    expect(mother_task.due_at).to be_within(1.second).of(tomorrow_10)
    created = account.tasks.find_by(title: 'Consulta: Maria Silva')
    expect(created.contact).to eq(caller)
    expect(created.due_at).to be_within(1.second).of(next_week_15)
  end

  it 'nome igual + telefone da outra pessoa: reagenda a consulta dela, mas o dono NÃO muda', :aggregate_failures do
    expect(record(name: 'Maísa Teste', phone: '+5511988887777')).to eq(:rescheduled)
    mother_task.reload
    expect(mother_task.contact).to eq(mother)
    expect(mother_task.due_at).to be_within(1.second).of(next_week_15)
    expect(mother_task.rescheduled_count).to eq(1)
    # 🔁 auditoria #2/#133: a remarcação pela IA também ganha o carimbo próprio
    expect(mother_task.rescheduled_at).to be_within(2.seconds).of(Time.current)
  end

  it 'a consulta do próprio contato continua sendo reagendada normalmente' do
    own = account.tasks.create!(title: 'Consulta: Maria Silva', task_type: 'consulta', due_at: tomorrow_10 + 2.hours, unit: 'paulista',
                                phone: '+5511999990000', contact: caller, creator: admin, status: :todo)
    expect(record(name: 'Maria Silva', phone: '+5511999990000')).to eq(:rescheduled)
    expect(own.reload.due_at).to be_within(1.second).of(next_week_15)
    expect(own.contact).to eq(caller)
  end

  # 👪 auditoria 10/2026 (#101): "marca para a minha mãe" não pode mover a consulta de quem conversa
  describe 'consulta para um familiar pelo mesmo contato' do
    let!(:own) do
      account.tasks.create!(title: 'Consulta: Maria Silva', task_type: 'consulta', due_at: tomorrow_10 + 2.hours, unit: 'paulista',
                            phone: '+5511999990000', contact: caller, creator: admin, status: :todo)
    end

    it 'nome de OUTRA pessoa: a consulta da paciente fica como estava e nasce uma nova, sem o contato dela', :aggregate_failures do
      expect(record(name: 'Dona Lúcia Pereira', phone: '+5511977776666')).to eq(:created)
      expect(own.reload.due_at).to be_within(1.second).of(tomorrow_10 + 2.hours)
      expect(own.rescheduled_count).to eq(0)
      created = account.tasks.find_by!(title: 'Consulta: Dona Lúcia Pereira')
      expect(created.contact).to be_nil
      expect(created.phone).to eq('+5511977776666')
      expect(created.due_at).to be_within(1.second).of(next_week_15)
    end

    it 'sem nome ditado é o próprio paciente: reagenda normalmente' do
      result = { found: true, starts_at: next_week_15, name: nil, phone: '+5511999990000', unit: 'paulista' }
      expect(described_class.record(account: account, contact: caller, result: result)).to eq(:rescheduled)
      expect(own.reload.due_at).to be_within(1.second).of(next_week_15)
    end

    it 'nome que bate com o CONTATO (título da consulta sem o nome): reagenda a dele' do
      own.update!(title: 'Consulta: Paciente')
      expect(record(name: 'Maria Silva', phone: '+5511999990000')).to eq(:rescheduled)
      expect(own.reload.due_at).to be_within(1.second).of(next_week_15)
    end

    it 'só o primeiro nome do próprio paciente: reagenda normalmente (não duplica)', :aggregate_failures do
      expect(record(name: 'Maria', phone: '+5511999990000')).to eq(:rescheduled)
      expect(own.reload.due_at).to be_within(1.second).of(next_week_15)
      expect(account.tasks.where(task_type: 'consulta', contact: caller).count).to eq(1)
    end

    it 'uma palavra só, diferente do primeiro nome: é outra pessoa (nasce nova)', :aggregate_failures do
      expect(record(name: 'Lúcia', phone: '+5511977776666')).to eq(:created)
      expect(own.reload.due_at).to be_within(1.second).of(tomorrow_10 + 2.hours)
      expect(account.tasks.find_by!(title: 'Consulta: Lúcia').contact).to be_nil
    end
  end

  # 👪 (#101, sentido inverso): a consulta da mãe marcada pelo MESMO WhatsApp fica
  # amarrada ao contato da filha (telefone) — o nome da filha não pode movê-la
  describe 'marcou para a mãe primeiro (mesmo telefone) e depois para si' do
    let!(:mother_by_phone) do
      account.tasks.create!(title: 'Consulta: Dona Lúcia Pereira', task_type: 'consulta', due_at: tomorrow_10 + 2.hours, unit: 'paulista',
                            phone: '+5511999990000', contact: caller, creator: admin, status: :todo)
    end

    it 'a da mãe não anda e nasce a própria, amarrada ao contato', :aggregate_failures do
      expect(record(name: 'Maria Silva', phone: '+5511999990000')).to eq(:created)
      mother_by_phone.reload
      expect(mother_by_phone.due_at).to be_within(1.second).of(tomorrow_10 + 2.hours)
      expect(mother_by_phone.rescheduled_count).to eq(0)
      created = account.tasks.find_by!(title: 'Consulta: Maria Silva')
      expect(created.contact).to eq(caller)
      expect(created.due_at).to be_within(1.second).of(next_week_15)
    end

    it 'com as duas consultas futuras, remarcar pelo nome da mãe move a da mãe (não a mais próxima)', :aggregate_failures do
      own = account.tasks.create!(title: 'Consulta: Maria Silva', task_type: 'consulta', due_at: tomorrow_10, unit: 'paulista',
                                  phone: '+5511999990000', contact: caller, creator: admin, status: :todo)
      expect(record(name: 'Dona Lúcia Pereira', phone: '+5511999990000')).to eq(:rescheduled)
      expect(mother_by_phone.reload.due_at).to be_within(1.second).of(next_week_15)
      expect(own.reload.due_at).to be_within(1.second).of(tomorrow_10)
    end
  end

  # 💰 auditoria 10/2026 (#132): valor falado pela IA não vira "valor da consulta"
  it 'o preço citado pela IA fica só como registro: o lembrete segue o pré-configurado do item 324', :aggregate_failures do
    result = { found: true, starts_at: next_week_15, name: 'Maria Silva', phone: '+5511999990000', unit: 'paulista', price: 'R$ 150' }
    expect(described_class.record(account: account, contact: caller, result: result)).to eq(:created)
    task = account.tasks.find_by!(title: 'Consulta: Maria Silva')
    expect(task.description).to include('Valor citado na conversa pela IA').and include('150')
    expect(Crm::AppointmentPrice.from_notes(task.description)).to be_nil
    cfg = Crm::AppointmentPrice::DEFAULTS.merge('avaliacao' => '200,00')
    expect(Crm::AppointmentPrice.resolve(cfg, task)).to include(text: '200,00', source: 'preset')
  end

  it 'preço "Valor: R$ 150" e observação livre "combinou R$ 150" (Secretário) também não viram valor da consulta', :aggregate_failures do
    result = { found: true, starts_at: next_week_15, name: 'Maria Silva', phone: '+5511999990000', unit: 'paulista',
               price: 'Valor: R$ 150', notes: 'combinou R$ 150, valor: 150 à vista' }
    expect(described_class.record(account: account, contact: caller, result: result)).to eq(:created)
    task = account.tasks.find_by!(title: 'Consulta: Maria Silva')
    expect(task.description).to include('combinou 150').and include('Valor 150')
    expect(Crm::AppointmentPrice.from_notes(task.description)).to be_nil
  end

  describe '.same_person?' do
    it 'nome completo segue a régua forte; uma palavra só vale pelo primeiro nome', :aggregate_failures do
      expect(described_class.same_person?('Maria', 'Maria da Silva')).to be(true)
      expect(described_class.same_person?('maria', 'Maria')).to be(true)
      expect(described_class.same_person?('Lúcia', 'Maria da Silva')).to be(false)
      expect(described_class.same_person?('Maria Silva', 'Maria da Silva')).to be(true)
      expect(described_class.same_person?('Joao da Silva', 'Maria da Silva')).to be(false)
      expect(described_class.same_person?('Maria', nil)).to be(false)
      expect(described_class.same_person?('', 'Maria')).to be(false)
    end
  end

  describe '.same_patient_name?' do
    it 'exige 2+ palavras de verdade com o primeiro nome; da/de/do não contam como prova', :aggregate_failures do
      expect(described_class.same_patient_name?('Maria da Silva', 'Maria da Silva')).to be(true)
      expect(described_class.same_patient_name?('maria silva', 'Maria da Silva')).to be(true)
      expect(described_class.same_patient_name?('Joao da Silva', 'Maria da Silva')).to be(false)
      expect(described_class.same_patient_name?('Maria', 'Maria da Silva')).to be(false)
      expect(described_class.same_patient_name?('Silva Santos', 'Maria da Silva')).to be(false)
      expect(described_class.same_patient_name?('Ana Souza', 'Ana')).to be(true)
      expect(described_class.same_patient_name?('', 'Maria da Silva')).to be(false)
    end
  end
end
