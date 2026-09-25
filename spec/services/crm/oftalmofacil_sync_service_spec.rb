require 'rails_helper'

# 🏥 item 228 (24/09): hub de parceiros + Agenda unificada
RSpec.describe Crm::OftalmofacilSyncService do
  let(:account) { create(:account) }
  let!(:cevico) do
    Crm::Pipeline.create!(account: account, name: 'CEVICO | Jornada do Paciente', position: 0).tap do |p|
      p.stages.create!(name: 'Lead', color: '#000', position: 0)
      p.stages.create!(name: 'Cirurgia Agendada', color: '#000', position: 1)
      p.stages.create!(name: 'Cirurgia Realizada', color: '#000', position: 2)
    end
  end
  let!(:partners) do
    Crm::Pipeline.create!(account: account, name: 'OFTALMOFÁCIL', position: 1).tap do |p|
      p.stages.create!(name: 'Cirurgia Agendada', color: '#000', position: 0)
      p.stages.create!(name: 'Cirurgia Realizada', color: '#000', position: 1)
    end
  end
  let(:config) do
    { 'db_host' => 'h', 'db_name' => 'd', 'db_user' => 'u', 'db_password' => 'p', 'provider_name' => 'CATARATA_SP',
      'partners_enabled' => true, 'partner_pipeline_id' => partners.id, 'agenda_enabled' => true,
      'agenda_from' => '2026-09-21', 'doctors' => { '170937' => 'Dr. Henrique Gemelli' },
      'clinics' => { 'IOP Paulista' => 'iop' } }
  end
  let(:service) { described_class.new(account: account, config: config, silent: true, since: nil) }
  before { create(:user, account: account, role: :administrator) } # criador dos agendamentos

  def row(overrides = {})
    {
      'SCH_ITE_ID' => 1, 'SCH_ITE_SCH_ID' => 10, 'SCH_ITE_TOKEN' => 'tok-1', 'SCH_ITE_STATUS' => '1',
      'SCH_ITE_DATE' => '30/09/2026', 'SCH_ITE_HOUR' => '09:30', 'SCH_ITE_AMOUNT' => 4500, 'SCH_ITE_CLINIC_PRICE' => 3000,
      'SCH_ITE_PROFIT' => 1500, 'SCH_ITE_REBATE' => 0, 'SCH_ITE_DATE_CREATION' => '2026-09-01 10:00:00',
      'SCH_ITE_LAST_MODIFICATION' => '2026-09-20 10:00:00', 'SCH_ITE_CLINIC' => 5, 'SCH_DOCTOR' => '170937',
      'SCH_PATIENT_NAME' => 'Maria Parceira', 'SCH_PATIENT_CPF' => '12345678901', 'SCH_PATIENT_PHONE' => '11988887777',
      'SCH_PATIENT_MAIL' => nil, 'PROV_NAME' => 'CLINICA VISAO NORTE', 'CLI_NAME' => 'IOP Paulista',
      'PRO_NAME' => 'Facoemulsificação', 'PRO_TYP_VALUE' => 'Cirurgia', 'EYE_VALUE' => 'OD',
      'STATUS_LABEL' => 'Ativo', 'PAT_CPF' => nil, 'PAT_EMAIL' => nil, 'PAT_PHONE' => nil, 'PAID_AMOUNT' => 0
    }.merge(overrides)
  end

  def run_with(rows)
    allow(service).to receive(:query).and_return(rows, [])
    service.call
  end

  it 'parceiro → contato com etiqueta de origem, card só no funil dos parceiros e agendamento na Agenda', :aggregate_failures do
    result = run_with([row])
    expect(result.errors).to be_empty
    expect(result.partners).to eq(1)
    contact = account.contacts.find_by(phone_number: '+5511988887777')
    expect(contact.additional_attributes).to include('origem' => 'oftalmofacil', 'parceiro' => 'CLINICA VISAO NORTE')
    expect(contact.label_list).to include('oftalmofacil', 'of_clinica_visao_norte')
    expect(Crm::Contact.where(contact_id: contact.id, pipeline_id: partners.id).count).to eq(1)
    expect(Crm::Contact.where(contact_id: contact.id, pipeline_id: cevico.id).count).to eq(0)
    expect(Crm::Contact.find_by(contact_id: contact.id).origin).to eq('oftalmofacil')

    task = account.tasks.find_by(external_ref: 'tok-1')
    expect(task).to be_present
    expect(task.task_type).to eq('cirurgia')
    expect(task.title).to eq('Cirurgia: Maria Parceira')
    expect(task.due_at.in_time_zone('America/Sao_Paulo').strftime('%Y-%m-%d %H:%M')).to eq('2026-09-30 09:30')
    expect(task.unit).to eq('iop')
    expect(task.doctor).to eq('Dr. Henrique Gemelli')
    expect(task.source).to eq('oftalmofacil')
    expect(task.source_detail).to eq('CLINICA VISAO NORTE')
    expect(task.booking_kind).to eq('registro')
    expect(task.description).to start_with('Oftalmofácil · CLINICA VISAO NORTE · IOP Paulista')
    expect(result.tasks_created).to eq(1)
  end

  # 🕐 item 242: o MySQL do hub manda a hora em SEGUNDOS ("39600.0" = 11:00) e o
  # app roda em UTC — o agendamento tem que cair às 11:00 de São Paulo
  it 'hora em segundos vira HH:MM e o agendamento cai na hora certa de São Paulo', :aggregate_failures do
    run_with([row('SCH_ITE_HOUR' => '39600.0', 'SCH_ITE_TOKEN' => 'tok-h')])
    surgery = Crm::OftalmofacilSurgery.find_by(item_token: 'tok-h')
    expect(surgery.surgery_hour).to eq('11:00')
    task = account.tasks.find_by(external_ref: 'tok-h')
    expect(task.due_at.in_time_zone('America/Sao_Paulo').strftime('%Y-%m-%d %H:%M')).to eq('2026-09-30 11:00')
    expect(Crm::OftalmofacilSurgery.normalize_hour('40800.0')).to eq('11:20')
    expect(Crm::OftalmofacilSurgery.normalize_hour('14:05:00')).to eq('14:05')
    expect(Crm::OftalmofacilSurgery.normalize_hour('0')).to be_nil
    expect(Crm::OftalmofacilSurgery.new(surgery_hour: '54000.0').hour_hhmm).to eq('15:00')
  end

  it 'nosso (CATARATA_SP) → card no funil da CEVICO, sem etiqueta de parceiro, agendamento sem parceiro', :aggregate_failures do
    run_with([row('PROV_NAME' => 'CATARATA_SP', 'SCH_ITE_TOKEN' => 'tok-2')])
    contact = account.contacts.find_by(phone_number: '+5511988887777')
    expect(contact.label_list).to include('oftalmofacil')
    expect(contact.label_list.grep(/^of_/)).to be_empty
    expect(contact.additional_attributes).not_to have_key('parceiro')
    expect(Crm::Contact.find_by(contact_id: contact.id).pipeline_id).to eq(cevico.id)
    expect(account.tasks.find_by(external_ref: 'tok-2').source_detail).to be_nil
  end

  it 'acompanha o OftalmoFácil: realizada conclui, cancelada cancela, exame vai para o trilho de exames', :aggregate_failures do
    run_with([row])
    run_with([row('STATUS_LABEL' => 'Realizado', 'SCH_ITE_STATUS' => '2', 'SCH_ITE_DATE' => '22/09/2026')])
    task = account.tasks.find_by(external_ref: 'tok-1')
    expect(task.status).to eq('done')
    expect(task.attendance).to eq('attended')
    expect(account.tasks.where(external_ref: 'tok-1').count).to eq(1)

    run_with([row('STATUS_LABEL' => 'Cancelado', 'SCH_ITE_STATUS' => '0')])
    expect(task.reload.canceled_at).to be_present

    run_with([row('SCH_ITE_TOKEN' => 'tok-3', 'PRO_TYP_VALUE' => 'Exame', 'PRO_NAME' => 'OCT')])
    exam = account.tasks.find_by(external_ref: 'tok-3')
    expect(exam.task_type).to eq('consulta')
    expect(exam.modality).to eq('exames')
    expect(exam.title).to eq('Exame: Maria Parceira')
  end

  it 'respeita a janela da Agenda e não cria card de parceiro sem funil configurado', :aggregate_failures do
    old = row('SCH_ITE_TOKEN' => 'tok-old', 'SCH_ITE_DATE' => '10/09/2026', 'SCH_PATIENT_PHONE' => '11955554444',
              'SCH_PATIENT_CPF' => '11122233344')
    run_with([old])
    expect(account.tasks.find_by(external_ref: 'tok-old')).to be_nil
    # parceiro antes da janela: só no espelho, sem paciente nem card
    expect(account.contacts.find_by(phone_number: '+5511955554444')).to be_nil
    expect(Crm::OftalmofacilSurgery.find_by(item_token: 'tok-old').applied_action).to eq('mirror_only')
    # a CEVICO (CATARATA_SP) antiga continua ganhando paciente e card
    run_with([row('SCH_ITE_TOKEN' => 'tok-own-old', 'SCH_ITE_DATE' => '10/09/2026', 'PROV_NAME' => 'CATARATA_SP',
                  'SCH_PATIENT_PHONE' => '11933332222', 'SCH_PATIENT_CPF' => '55566677788')])
    expect(account.contacts.find_by(phone_number: '+5511933332222')).to be_present

    svc = described_class.new(account: account, config: config.merge('partner_pipeline_id' => nil), silent: true, since: nil)
    allow(svc).to receive(:query).and_return([row('SCH_ITE_TOKEN' => 'tok-4', 'SCH_PATIENT_PHONE' => '11977776666',
                                                  'SCH_PATIENT_CPF' => '99988877766', 'SCH_PATIENT_NAME' => 'João Novo')], [])
    result = svc.call
    expect(result.skipped_partners).to eq(1)
    contact = account.contacts.find_by(phone_number: '+5511977776666')
    expect(Crm::Contact.where(contact_id: contact.id).count).to eq(0)
    expect(account.tasks.find_by(external_ref: 'tok-4')).to be_present
  end

  it 'com parceiros desligados, a consulta filtra pelo fornecedor da CEVICO' do
    svc = described_class.new(account: account, config: config.merge('partners_enabled' => false), silent: true, since: nil)
    captured = nil
    allow(svc).to receive(:query) { |sql, binds|
      captured = [sql, binds]
      []
    }
    svc.call
    expect(captured[0]).to include('PROV_NAME LIKE ?')
    expect(captured[1]).to eq(['%CATARATA_SP%', '%CATARATA_SP%'])
  end
end
