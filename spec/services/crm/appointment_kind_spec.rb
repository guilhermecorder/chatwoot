require 'rails_helper'

# 🏷️ item 344 (13/10): o TIPO do atendimento vira etiqueta + filtro no card do
# CRM (decisão "Etapas + tipo no cartão")
RSpec.describe Crm::AppointmentKind do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:patient) { create(:contact, account: account, name: 'Paciente Tipo') }

  def task(attrs)
    account.tasks.create!({ title: 'Consulta: Paciente', task_type: 'consulta', creator: user, contact_id: patient.id,
                            due_at: 3.days.from_now }.merge(attrs))
  end

  it 'lê o tipo pelo tipo da Agenda e pelo procedimento (sem confundir LIO de catarata com lente rígida)', :aggregate_failures do
    expect(described_class.kind_of(Task.new(task_type: 'cirurgia', procedure: 'FACECTOMIA COM LIO (lente intraocular)'))).to eq('cirurgia')
    expect(described_class.kind_of(Task.new(task_type: 'consulta', procedure: 'Adaptação de Lente Rígida'))).to eq('lente')
    expect(described_class.kind_of(Task.new(task_type: 'cirurgia', procedure: 'Aplicação Intravítrea'))).to eq('intravitrea')
    expect(described_class.kind_of(Task.new(task_type: 'consulta', modality: 'exames'))).to eq('exame')
    expect(described_class.kind_of(Task.new(task_type: 'consulta', modality: 'retorno'))).to eq('retorno')
    expect(described_class.kind_of(Task.new(task_type: 'consulta', modality: 'pos_op'))).to eq('pos_op')
    expect(described_class.kind_of(Task.new(task_type: 'consulta', modality: 'avaliacao'))).to eq('consulta')
  end

  it 'vale o PRÓXIMO agendamento; sem próximo, o último; cancelado não conta', :aggregate_failures do
    task(modality: 'exames', due_at: 10.days.ago)
    task(modality: 'retorno', due_at: 5.days.from_now, canceled_at: Time.current)
    expect(described_class.for_contacts(account, [patient.id])[patient.id]).to include(key: 'exame', label: 'Exame', upcoming: false)

    task(modality: 'retorno', due_at: 2.days.from_now)
    expect(described_class.for_contacts(account, [patient.id])[patient.id]).to include(key: 'retorno', upcoming: true)
  end
end
