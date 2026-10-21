require 'rails_helper'
require 'rake'

# 💰 item 340: tira só a linha antiga "Valor da consulta: R$ 150" que a IA gravava
RSpec.describe 'cevico:limpar_valor_ia' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:legacy) { "Paciente prefere manhã\n\nReagendada pela IA:\nValor da consulta: R$ 150\nConversa #12 — agendado pela IA" }

  before do
    Rake.application.rake_require('tasks/cevico_limpar_valor_ia')
    Rake::Task.define_task(:environment)
    Rake::Task['cevico:limpar_valor_ia'].reenable
  end

  def consulta(description, due_at: 3.days.from_now)
    account.tasks.create!(title: 'Consulta: Alessandro Pires', task_type: 'consulta', modality: 'avaliacao',
                          due_at: due_at, description: description, procedure: 'CONSULTA | JÁ PAC | R$350', creator: user)
  end

  def run(env)
    stub_const('ENV', ENV.to_h.merge({ 'ACCOUNT_ID' => account.id.to_s }.merge(env)))
    Rake::Task['cevico:limpar_valor_ia'].invoke
  end

  it 'DRY=1 só lista; DRY=0 tira só a linha da IA nas consultas futuras', :aggregate_failures do
    futura = consulta(legacy)
    passada = consulta(legacy, due_at: 3.days.ago)
    equipe = consulta("Valor da consulta: R$ 350\nobs da recepção")

    expect { run('DRY' => '1') }.to output(/1 consulta\(s\).*Alessandro Pires.*DRY: nada mudou/m).to_stdout
    expect(futura.reload.description).to eq(legacy)

    Rake::Task['cevico:limpar_valor_ia'].reenable
    expect { run('DRY' => '0') }.to output(/APLICADO: 1/).to_stdout
    expect(futura.reload.description).to eq("Paciente prefere manhã\n\nReagendada pela IA:\nConversa #12 — agendado pela IA")
    expect(passada.reload.description).to eq(legacy)
    expect(equipe.reload.description).to eq("Valor da consulta: R$ 350\nobs da recepção")
  end
end
