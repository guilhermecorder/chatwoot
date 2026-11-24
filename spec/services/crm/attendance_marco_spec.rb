require 'rails_helper'

# 📍🔙 24/11/2026: marco do atendimento (antes × depois por caixa) e ponto de
# volta ao formato de antes de 24/11.
RSpec.describe 'CRM — marco do atendimento e ponto de volta' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:instagram) { create(:inbox, account: account, name: 'INSTAGRAM 2') }
  let(:google) { create(:inbox, account: account, name: 'GOOGLE') }
  let(:marco_at) { Time.zone.parse('2026-11-24 03:00') }
  let!(:settings) do
    CrmSetting.create!(account: account, ai_config: {
                         'agents' => {
                           'atendente_agendamento' => {
                             'enabled' => true, 'mode' => 'live', 'inbox_ids' => [instagram.id, google.id],
                             'stage_models' => { 'sem_card' => 'gpt-6-luna', '2' => 'claude-sonnet-5' },
                             'ab' => { 'enabled' => true, 'script_b' => 'v2', 'inboxes' => { instagram.id.to_s => 'b' },
                                       'started_at' => '2026-11-24T03:02:24Z' }
                           }
                         }
                       })
  end

  def conversation_at(inbox, time, booked_after: nil)
    contact = create(:contact, account: account)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, created_at: time)
    if booked_after
      account.tasks.create!(title: 'Consulta', task_type: 'consulta', due_at: time + 3.days, unit: 'paulista',
                            contact_id: contact.id, creator: admin, created_at: time + booked_after)
    end
    conversation
  end

  describe Crm::AttendanceMilestones do
    it 'guarda os marcos do mais novo para o mais antigo e apaga só a anotação', :aggregate_failures do
      old = described_class.add!(account, title: 'Prompt novo na INSTAGRAM 2', at: '2026-11-20T10:00:00Z')
      described_class.add!(account, title: 'ChatGPT na recepção', at: marco_at.iso8601, by: 'Guilherme')

      expect(described_class.list(account).pluck('title')).to eq(['ChatGPT na recepção', 'Prompt novo na INSTAGRAM 2'])
      expect(described_class.find(account, nil)['title']).to eq('ChatGPT na recepção')

      described_class.remove!(account, old['id'])
      expect(described_class.list(account).size).to eq(1)
      expect(settings.reload.ai_config.dig('agents', 'atendente_agendamento', 'enabled')).to be(true) # o resto fica como estava
    end
  end

  describe Crm::AttendanceBeforeAfter do
    it 'compara por caixa com o MESMO prazo nos dois lados', :aggregate_failures do
      now = marco_at + 2.days # horizonte = 2 dias
      # antes do marco: 4 conversas no Instagram; 1 marcou em 1 dia (conta), 1 marcou só 5 dias depois (fora do prazo)
      conversation_at(instagram, marco_at - 6.days, booked_after: 1.day)
      conversation_at(instagram, marco_at - 9.days, booked_after: 5.days)
      2.times { conversation_at(instagram, marco_at - 3.days) }
      # depois do marco: 2 conversas, 1 marcou
      conversation_at(instagram, marco_at + 2.hours, booked_after: 3.hours)
      conversation_at(instagram, marco_at + 5.hours)
      conversation_at(google, marco_at + 1.hour)

      result = described_class.new(account, at: marco_at, now: now).call
      row = result[:rows].find { |r| r[:inbox_id] == instagram.id }

      expect(result[:horizon_hours]).to eq(48.0)
      expect(row[:before]).to include(conversas: 4, consultas: 1, taxa: 25.0)
      expect(row[:after]).to include(conversas: 2, consultas: 1, taxa: 50.0)
      expect(result[:total][:after]).to include(conversas: 3, consultas: 1)
    end

    it 'marco no futuro não tem o que comparar' do
      expect(described_class.new(account, at: 1.day.from_now).call).to be_nil
    end
  end

  describe Crm::AttendanceRestorePoint do
    it 'volta o Roteiro 1 e os Passos ao texto de 23/11, apaga o motor por coluna e encerra o teste, guardando o que havia', :aggregate_failures do
      described_class.apply!(account, by: admin)
      cfg = settings.reload.ai_config
      agent = cfg.dig('agents', 'atendente_agendamento')

      expect(Crm::CevicoScript.section_text(account, 'official_data')).to eq(described_class.data['script']['official_data'].strip)
      expect(Crm::CevicoScript.section_text(account, 'official_data')).not_to include('R$ 250')
      expect(agent['prompt']).to eq(described_class.data['stage']['atendente_agendamento'].strip)
      expect(agent['prompt']).not_to include('PROIBIDO NA SONDAGEM')
      expect(agent).not_to have_key('stage_models')
      expect(agent['ab']).to include('enabled' => false)
      expect(agent['ab']['ended_at']).to be_present
      expect(agent['ab_history'].first).to include('decision' => 'a', 'note' => 'encerrado pelo ponto de volta')
      expect(cfg.dig('restore_point', 'undo', 'atendente_agendamento', 'stage_models')).to eq('sem_card' => 'gpt-6-luna', '2' => 'claude-sonnet-5')
      expect(Crm::ScriptVersion.where(account: account).pluck(:kind)).to include('script', 'stage')
      expect(Crm::AttendanceMilestones.list(account).first['title']).to include('Voltou ao atendimento')
    end
  end

  describe 'pela tela (só admin)', type: :request do
    let(:lab_url) { "/api/v1/accounts/#{account.id}/crm/attendance_lab" }

    it 'anota o marco e devolve o antes × depois; ponto de volta exige confirmação', :aggregate_failures do
      conversation_at(instagram, 2.hours.ago)

      post "#{lab_url}/mark", params: { title: 'ChatGPT na recepção', at: 3.hours.ago.iso8601 }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['marcos'].first['title']).to eq('ChatGPT na recepção')
      expect(body.dig('before_after', 'total', 'after', 'conversas')).to eq(1)
      expect(body.dig('restore_point', 'id')).to eq('antes-de-24-11-2026')

      post "#{lab_url}/mark", params: { title: '' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      post "#{lab_url}/restore_point", params: {}, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(settings.reload.ai_config.dig('agents', 'atendente_agendamento', 'stage_models')).to be_present

      post "#{lab_url}/restore_point", params: { confirm: true }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('restore_point', 'applied_at')).to be_present
      expect(settings.reload.ai_config.dig('agents', 'atendente_agendamento', 'stage_models')).to be_nil
    end

    it 'quem não é admin não anota marco' do
      agent_user = create(:user, account: account, role: :agent)
      post "#{lab_url}/mark", params: { title: 'x' }, headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
