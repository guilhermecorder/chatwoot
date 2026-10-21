require 'rails_helper'

# 🔎 item 249 (26/09): conferência do dia — hub × Agenda, item por item
RSpec.describe Crm::OftalmofacilDayCheck do
  let(:account) { create(:account) }
  let(:date) { Date.new(2026, 9, 28) } # segunda-feira
  let(:config) do
    { 'db_host' => 'h', 'db_name' => 'd', 'db_user' => 'u', 'db_password' => 'p', 'provider_name' => 'CATARATA_SP',
      'partners_enabled' => true, 'agenda_enabled' => true, 'agenda_from' => '2026-09-21',
      'clinics' => { 'IOP Paulista' => 'paulista' } }
  end
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:check) { described_class.new(account: account, date: date, config: config) }

  def mirror(token, overrides = {})
    Crm::OftalmofacilSurgery.create!({ account: account, item_token: token, status_kind: 'agendada', status_label: 'Ativo',
                                       surgery_date: date, surgery_hour: '09:00', clinic_name: 'IOP Paulista',
                                       provider_name: 'CATARATA_SP', patient_name: 'Maria Teste', patient_phone: '11988887777',
                                       procedure_name: 'Facoemulsificação', procedure_type: 'Cirurgia', eye: 'OD',
                                       raw: { 'SCH_ITE_TOKEN' => token } }.merge(overrides))
  end

  def task_for(token, overrides = {})
    account.tasks.create!({ title: 'Cirurgia: Maria Teste', task_type: 'cirurgia', creator: admin, external_ref: token,
                            source: 'oftalmofacil', unit: 'paulista', booking_kind: 'registro',
                            due_at: ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-09-28 09:00') }.merge(overrides))
  end

  it 'próximo dia útil pula o fim de semana' do
    saturday = ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-09-26 10:00')
    expect(described_class.default_date(saturday)).to eq(Date.new(2026, 9, 28))
    expect(described_class.default_date(saturday - 2.days)).to eq(Date.new(2026, 9, 25))
  end

  it 'classifica cada item: na Agenda, faltando, em outra hora, sem local, cancelada aqui e cancelada no hub', :aggregate_failures do
    mirror('ok')
    task_for('ok')
    mirror('falta')
    mirror('hora', surgery_hour: '11:00')
    task_for('hora', due_at: ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-09-27 21:00'))
    mirror('sem-local', clinic_name: 'Clinica Nova')
    task_for('sem-local', unit: nil)
    mirror('canc-aqui')
    task_for('canc-aqui', canceled_at: Time.current)
    mirror('canc-hub', status_kind: 'cancelada')

    rep = check.report
    by = rep[:rows].index_by { |r| r[:token] }
    expect(by['ok'][:situation]).to eq('ok')
    expect(by['falta'][:situation]).to eq('sem_agendamento')
    expect(by['hora'][:situation]).to eq('hora_errada')
    expect(by['hora'][:reason]).to include('27/09 21:00')
    expect(by['sem-local'][:situation]).to eq('sem_local')
    expect(by['canc-aqui'][:situation]).to eq('cancelado_aqui')
    expect(by['canc-hub'][:situation]).to eq('cancelada')
    expect(rep[:summary]).to include('total' => 6, 'problemas' => 4, 'corrigiveis' => 2)
    expect(rep[:hub]).to eq(checked: false)
  end

  it 'explica quando a Agenda unificada está desligada ou a data é anterior à janela', :aggregate_failures do
    mirror('x')
    off = described_class.new(account: account, date: date, config: config.merge('agenda_enabled' => false))
    expect(off.report[:rows].first[:situation]).to eq('agenda_desligada')
    late = described_class.new(account: account, date: date, config: config.merge('agenda_from' => '2026-10-01'))
    expect(late.report[:rows].first[:situation]).to eq('antes_da_janela')
  end

  it 'com hub: item que existe lá e não no espelho aparece como "nunca leu"', :aggregate_failures do
    mirror('lido')
    task_for('lido')
    remote = [{ 'SCH_ITE_TOKEN' => 'novo', 'SCH_PATIENT_NAME' => 'João Novo', 'SCH_PATIENT_PHONE' => '11977776666',
                'SCH_ITE_HOUR' => '39600.0', 'CLI_NAME' => 'IOP Paulista', 'PROV_NAME' => 'CATARATA_SP',
                'STATUS_LABEL' => 'Ativo', 'PRO_NAME' => 'Faco', 'EYE_VALUE' => 'OE', 'PRO_TYP_VALUE' => 'Cirurgia',
                'SCH_ITE_DATE_CREATION' => '2026-09-20 10:00:00' }]
    allow_any_instance_of(Crm::OftalmofacilSyncService).to receive(:pull_day).and_return(remote) # rubocop:disable RSpec/AnyInstance

    rep = check.report(hub: true)
    novo = rep[:rows].find { |r| r[:token] == 'novo' }
    expect(novo[:situation]).to eq('nao_lido')
    expect(novo[:hour]).to eq('11:00')
    expect(novo[:unit]).to eq('paulista')
    expect(rep[:hub]).to include(checked: true, total: 1)
    expect(rep[:summary]['corrigiveis']).to eq(1)
  end

  it 'agendamento do Oftalmofácil neste dia cujo item do hub está em outra data aparece como "solto"' do
    mirror('outro-dia', surgery_date: date + 1)
    task_for('outro-dia')
    rep = check.report
    expect(rep[:rows]).to be_empty
    expect(rep[:strays].first).to include(hub_date: '29/09/2026')
  end

  describe '#reconcile!' do
    it 'reprocessa só o corrigível e devolve o relatório depois', :aggregate_failures do
      admin
      row = { 'SCH_ITE_ID' => 1, 'SCH_ITE_SCH_ID' => 10, 'SCH_ITE_TOKEN' => 'falta', 'SCH_ITE_STATUS' => '1',
              'SCH_ITE_DATE' => '28/09/2026', 'SCH_ITE_HOUR' => '39600.0', 'SCH_ITE_AMOUNT' => 4500, 'SCH_ITE_CLINIC_PRICE' => 3000,
              'SCH_ITE_PROFIT' => 1500, 'SCH_ITE_REBATE' => 0, 'SCH_ITE_DATE_CREATION' => '2026-09-01 10:00:00',
              'SCH_ITE_LAST_MODIFICATION' => '2026-09-20 10:00:00', 'SCH_ITE_CLINIC' => 5, 'SCH_DOCTOR' => '1',
              'SCH_PATIENT_NAME' => 'Maria Teste', 'SCH_PATIENT_CPF' => '12345678901', 'SCH_PATIENT_PHONE' => '11988887777',
              'SCH_PATIENT_MAIL' => nil, 'PROV_NAME' => 'CATARATA_SP', 'CLI_NAME' => 'IOP Paulista',
              'PRO_NAME' => 'Facoemulsificação', 'PRO_TYP_VALUE' => 'Cirurgia', 'EYE_VALUE' => 'OD',
              'STATUS_LABEL' => 'Ativo', 'PAT_CPF' => nil, 'PAT_EMAIL' => nil, 'PAT_PHONE' => nil, 'PAID_AMOUNT' => 0 }
      mirror('falta', raw: row)
      mirror('ok')
      task_for('ok')
      allow_any_instance_of(Crm::OftalmofacilSyncService).to receive(:pull_day).and_return([row]) # rubocop:disable RSpec/AnyInstance

      rep = check.reconcile!
      expect(rep[:fixed]).to eq(1)
      expect(rep[:tasks_created]).to eq(1)
      task = account.tasks.find_by(external_ref: 'falta')
      expect(task.due_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m %H:%M')).to eq('28/09 11:00')
      expect(task.unit).to eq('paulista')
      expect(rep[:rows].find { |r| r[:token] == 'falta' }[:situation]).to eq('ok')
      expect(rep[:summary]['corrigiveis']).to eq(0)
    end

    it 'sem hub, reprocessa pelo espelho (linha crua guardada)' do
      admin
      row = { 'SCH_ITE_TOKEN' => 'falta', 'SCH_ITE_STATUS' => '1', 'SCH_ITE_DATE' => '2026-09-28', 'SCH_ITE_HOUR' => '09:00',
              'SCH_PATIENT_NAME' => 'Maria Teste', 'SCH_PATIENT_PHONE' => '11988887777', 'PROV_NAME' => 'CATARATA_SP',
              'CLI_NAME' => 'IOP Paulista', 'PRO_NAME' => 'Faco', 'PRO_TYP_VALUE' => 'Cirurgia', 'STATUS_LABEL' => 'Ativo' }
      mirror('falta', raw: row)
      allow_any_instance_of(Crm::OftalmofacilSyncService).to receive(:pull_day).and_raise(StandardError, 'sem rede') # rubocop:disable RSpec/AnyInstance

      rep = check.reconcile!
      expect(rep[:fixed]).to eq(1)
      expect(account.tasks.find_by(external_ref: 'falta')).to be_present
    end

    it 'não mexe quando a Agenda unificada está desligada' do
      mirror('falta')
      off = described_class.new(account: account, date: date, config: config.merge('agenda_enabled' => false))
      allow_any_instance_of(Crm::OftalmofacilSyncService).to receive(:pull_day).and_return([]) # rubocop:disable RSpec/AnyInstance
      rep = off.reconcile!
      expect(rep[:fixed]).to eq(0)
      expect(rep[:errors].first).to include('Ligue a Agenda unificada')
    end
  end
end
