require 'rails_helper'
require 'rake'

# 🩺 item 311: consultas de terça à tarde gravadas com o Dr. Henrique (a faixa é da Dra. Roberta)
RSpec.describe 'cevico:agenda_fix_doctors' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tz) { Crm::AgendaSlots::TZ }
  let(:tuesday) do
    d = tz.now.to_date + 7
    d += 1 until d.tuesday?
    d
  end

  before do
    Rake.application.rake_require('tasks/cevico_agenda_fix_doctors')
    Rake::Task.define_task(:environment)
    Rake::Task['cevico:agenda_fix_doctors'].reenable
  end

  def consulta(time, doctor)
    account.tasks.create!(title: "Consulta #{time}", task_type: 'consulta', modality: 'avaliacao', unit: 'paulista',
                          due_at: tz.parse("#{tuesday} #{time}"), doctor: doctor, creator: user)
  end

  def run(env)
    stub_const('ENV', ENV.to_h.merge({ 'ACCOUNT_ID' => account.id.to_s }.merge(env)))
    Rake::Task['cevico:agenda_fix_doctors'].invoke
  end

  it 'DRY=1 só lista; DRY=0 corrige a tarde e não mexe em manhã certa nem em nome escrito pela equipe', :aggregate_failures do
    tarde = consulta('14:45', 'Dr. Henrique Gemelli')
    manha = consulta('09:00', 'Dr. Henrique Gemelli')
    outro = consulta('15:00', 'Paulo Henrique Telles')

    expect { run('DRY' => '1') }.to output(/1 consulta\(s\).*Dr\. Henrique Gemelli → Dra\. Roberta Negri/m).to_stdout
    expect(tarde.reload.doctor).to eq('Dr. Henrique Gemelli')

    Rake::Task['cevico:agenda_fix_doctors'].reenable
    expect { run('DRY' => '0') }.to output(/CORRIGIDO/).to_stdout
    expect(tarde.reload.doctor).to eq('Dra. Roberta Negri')
    expect(manha.reload.doctor).to eq('Dr. Henrique Gemelli')
    expect(outro.reload.doctor).to eq('Paulo Henrique Telles')
  end
end
