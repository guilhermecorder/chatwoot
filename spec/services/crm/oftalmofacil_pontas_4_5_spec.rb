require 'rails_helper'

# 🩺 Ponta 4 (22/10): agendamento do hub que faltava (mais de 14 dias à
# frente) e médico que aparece sozinho quando o CRM ganha nome.
# 🧮 Ponta 5 (22/10): exame do hub é item, não cirurgia — em toda tela.
RSpec.describe 'OftalmoFácil — pontas 4 e 5' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:config) do
    { 'db_host' => 'h', 'db_name' => 'd', 'db_user' => 'u', 'db_password' => 'p', 'provider_name' => 'CATARATA_SP',
      'agenda_enabled' => true, 'agenda_from' => (today - 30).iso8601, 'doctors' => { '170937' => 'Dr. Henrique Gemelli' } }
  end
  let(:service) { Crm::OftalmofacilSyncService.new(account: account, config: config, silent: true, since: nil) }
  let(:contact) { create(:contact, account: account, name: 'Lia Futura', phone_number: '+5511912345678') }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:today) { Crm::OftalmofacilSurgery.today_sp }

  before do
    Crm::Pipeline.create!(account: account, name: 'CEVICO | Jornada do Paciente', position: 0)
                 .stages.create!(name: 'Cirurgia Agendada', color: '#000', position: 1)
  end

  def item(token, date, **extra)
    Crm::OftalmofacilSurgery.create!({ account: account, item_token: token, status_kind: 'agendada', contact_id: contact.id,
                                       match_via: 'phone', patient_name: contact.name, patient_phone: '11912345678',
                                       provider_name: 'CATARATA_SP', procedure_type: 'Cirurgias', procedure_name: 'Faco',
                                       surgery_date: date, surgery_hour: '08:00', amount: 5000 }.merge(extra))
  end

  describe 'ponta 4' do
    it 'refaz o agendamento que faltava mais à frente que os 14 dias da janela curta' do
      item('longe', today + 40)

      expect { service.heal_agenda! }.to change { account.tasks.where(external_ref: 'longe').count }.from(0).to(1)
    end

    it 'agendamento sem médico ganha o nome assim que o CRM entra no de-para', :aggregate_failures do
      item('sem-medico', today + 3, doctor_crm: '170937')
      task = account.tasks.create!(title: 'Cirurgia: Lia', task_type: 'cirurgia', due_at: (today + 3).in_time_zone.change(hour: 11),
                                   contact: contact, creator: admin, status: :todo, source: 'oftalmofacil', external_ref: 'sem-medico')

      expect(service.fill_doctors!).to eq(1)
      expect(task.reload.doctor).to eq('Dr. Henrique Gemelli')
    end
  end

  describe 'ponta 5', type: :request do
    it 'scope cirurgias e cirurgia? deixam exame, consulta e pós-op de fora', :aggregate_failures do
      faco = item('c1', today - 2)
      item('e1', today - 2, procedure_type: 'Exames')
      item('p1', today - 2, procedure_type: 'Pós-operatório')

      expect(Crm::OftalmofacilSurgery.cirurgias).to contain_exactly(faco)
      expect(faco.cirurgia?).to be(true)
    end

    it 'Central/Campanhas: quem só fez exame não conta como operado' do
      item('e2', today - 2, procedure_type: 'Exames', paid_amount: 130)

      steps = Crm::AdFunnelSteps.new(account, [contact.id])
      expect(steps.surgeries).not_to include(contact.id)
    end

    it 'Lucratividade: cirurgia = olho, paciente à parte, exame fora da receita das cirurgias', :aggregate_failures do
      CrmSetting.create!(account: account, agenda_config: { 'oftalmofacil' => { 'provider_name' => 'CATARATA_SP' } })
      item('od', today - 3, eye: 'OD')
      item('oe', today - 2, eye: 'OE')
      item('ex', today - 2, procedure_type: 'Exames', amount: 130)

      get "/api/v1/accounts/#{account.id}/crm/finance/profitability", params: { preset: 'last90' }, headers: admin.create_new_auth_token, as: :json
      summary = response.parsed_body['summary']
      expect(summary).to include('count' => 2, 'pacientes' => 1, 'receita' => 10_000.0)
      expect(summary['exames']).to include('count' => 1, 'receita' => 130.0)
    end
  end
end
