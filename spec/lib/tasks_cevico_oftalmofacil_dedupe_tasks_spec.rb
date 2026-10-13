require 'rails_helper'
require 'rake'

# 🔁 auditoria 10/2026 (#462/#472): une a consulta lançada pela recepção com a
# cópia vinda do hub — a da equipe fica (com o vínculo), a do hub vai para a Lixeira
RSpec.describe 'cevico:oftalmofacil_dedupe_tasks' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:paciente) { account.contacts.create!(name: 'Maria Teste', phone_number: '+5511988887777') }
  let(:dia) { tz.now.beginning_of_day + 2.days + 9.hours }

  before do
    CrmSetting.find_or_create_by!(account: account).update!(agenda_config: { 'oftalmofacil' => { 'agenda_enabled' => true } })
    Rake.application.rake_require('tasks/cevico_oftalmofacil_fix')
    Rake::Task.define_task(:environment)
    Rake::Task['cevico:oftalmofacil_dedupe_tasks'].reenable
  end

  def consulta(overrides = {})
    account.tasks.create!({ title: 'Consulta: Maria', task_type: 'consulta', modality: 'avaliacao', creator: admin, contact: paciente,
                            phone: paciente.phone_number, due_at: dia, unit: 'paulista' }.merge(overrides))
  end

  def run(env)
    stub_const('ENV', ENV.to_h.merge({ 'ACCOUNT_ID' => account.id.to_s }.merge(env)))
    Rake::Task['cevico:oftalmofacil_dedupe_tasks'].invoke
  end

  it 'DRY=1 só lista; DRY=0 deixa a da equipe com o vínculo e manda a cópia do hub para a Lixeira', :aggregate_failures do
    recepcao = consulta(description: 'Ligar antes')
    hub = consulta(due_at: dia + 15.minutes, external_ref: 'tok-dup', source: 'oftalmofacil', booking_kind: 'registro',
                   description: 'Oftalmofácil · IOP', confirmed_at: Time.current)
    sozinha = consulta(due_at: dia + 1.day, external_ref: 'tok-ok', source: 'oftalmofacil', booking_kind: 'registro', phone: nil, contact: nil)

    expect { run('DRY' => '1') }.to output(/1 consulta\(s\) duplicada\(s\).*DRY=0/m).to_stdout
    expect(recepcao.reload.external_ref).to be_nil
    expect(hub.reload.canceled_at).to be_nil

    Rake::Task['cevico:oftalmofacil_dedupe_tasks'].reenable
    expect { run('DRY' => '0') }.to output(/1 consulta\(s\) duplicada\(s\) unida\(s\)/).to_stdout
    recepcao.reload
    expect(recepcao.external_ref).to eq('tok-dup')
    expect(recepcao.source).to eq('oftalmofacil')
    expect(recepcao.description).to eq('Ligar antes')
    expect(recepcao.creator).to eq(admin)
    expect(recepcao.confirmed_at).to be_present # a resposta do paciente passa para a que fica
    hub.reload
    expect(hub.canceled_at).to be_present
    expect(hub.cancel_reason).to eq('duplicada_hub')
    expect(hub.external_ref).to be_nil
    expect(sozinha.reload.canceled_at).to be_nil
    expect(account.tasks.where(contact_id: paciente.id, canceled_at: nil).count).to eq(1)
  end
end
