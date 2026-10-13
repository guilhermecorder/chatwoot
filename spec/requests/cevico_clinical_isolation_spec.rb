require 'rails_helper'

# 🛡️ Rodada 6 da auditoria — "Rede de segurança" (#259, LGPD): dado de saúde
# é sensível. Nenhum teste provava que:
#   · o atendente FORA do acesso clínico (agenda_config.clinical_access) leva
#     403 nas anotações clínicas — ler, criar, editar e apagar;
#   · a anotação / o paciente / as notas / as pessoas / os indicadores de uma
#     clínica (conta A) NUNCA aparecem para outra clínica (conta B) — nem pela
#     URL da conta A (401) nem colando o id na URL da conta B (404).
# Padrão adotado nos specs novos: "a conta B não enxerga a conta A" é caso
# obrigatório.
RSpec.describe 'CEVICO dados clínicos e do paciente — acesso e isolamento entre contas', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  # let! = as pessoas nascem antes do 1º pedido (o 1º request pode recarregar as classes)
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Admin A') }
  let!(:agent) { create(:user, account: account, role: :agent, name: 'Atendente A') }
  let!(:doctor) { create(:user, account: account, role: :agent, name: 'Médica A') }
  let!(:intruder) { create(:user, account: other_account, role: :administrator, name: 'Admin B') }
  let(:patient) do
    create(:contact, account: account, name: 'Maria Sigilo', phone_number: '+5511999990000',
                     additional_attributes: { 'sexo' => 'feminino' })
  end
  let(:other_patient) { create(:contact, account: other_account, name: 'João Outra Clínica', phone_number: '+5511988880000') }
  let!(:note) do
    Crm::ClinicalNote.create!(account_id: account.id, contact_id: patient.id, author: doctor, performed_at: 1.day.ago,
                              fields: { 'eye' => 'OD' }, observations: 'glaucoma inicial — sigilo A')
  end
  let!(:other_note) do
    Crm::ClinicalNote.create!(account_id: other_account.id, contact_id: other_patient.id, author: intruder, performed_at: 1.day.ago,
                              fields: {}, observations: 'anotação da clínica B')
  end

  before do
    Current.reset
    Rails.cache.clear
    CrmSetting.create!(account: account, agenda_config: { 'clinical_access' => { 'doctor_user_ids' => [doctor.id], 'team_view' => false } })
    CrmSetting.create!(account: other_account)
  end

  def crm(acc, path)
    "/api/v1/accounts/#{acc.id}/crm/#{path}"
  end

  def notes_path(acc, patient_id, note_id = nil)
    crm(acc, ['patients', patient_id, 'clinical_notes', note_id].compact.join('/'))
  end

  def grant!(user, tree)
    CrmSetting.find_by!(account: account).update!(agent_permissions: { 'tree' => { user.id.to_s => tree } })
  end

  describe 'anotações clínicas (acesso clínico)' do
    it 'atendente fora do acesso clínico: 403 em ler, criar, editar e apagar — e nada muda', :aggregate_failures do
      headers = agent.create_new_auth_token

      get notes_path(account, patient.id), headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include('glaucoma')

      # mesmo com a concessão "editar" do catálogo, o cadeado do acesso clínico continua valendo
      grant!(agent, { 'pacientes.notas_clinicas' => 'edit' })
      expect do
        post notes_path(account, patient.id), params: { observations: 'tentativa' }, headers: headers, as: :json
      end.not_to change(Crm::ClinicalNote, :count)
      expect(response).to have_http_status(:forbidden)

      patch notes_path(account, patient.id, note.id), params: { observations: 'apagado' }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      delete notes_path(account, patient.id, note.id), headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(note.reload.observations).to eq('glaucoma inicial — sigilo A')
    end

    it 'equipe com "ver" (team_view) lê, mas não escreve', :aggregate_failures do
      CrmSetting.find_by!(account: account).update!(agenda_config: { 'clinical_access' => { 'doctor_user_ids' => [doctor.id], 'team_view' => true } })

      get notes_path(account, patient.id), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('can_edit' => false)
      expect(response.parsed_body['notes'].pluck('observations')).to eq(['glaucoma inicial — sigilo A'])

      post notes_path(account, patient.id), params: { observations: 'x' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'a médica do acesso clínico lê e (com "editar" no catálogo) escreve as suas', :aggregate_failures do
      headers = doctor.create_new_auth_token
      get notes_path(account, patient.id), headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['can_edit']).to be(true)

      # duas chaves: estar no acesso clínico E ter "editar" em Notas clínicas no catálogo
      # (padrão do catálogo = só ver) — ver pendência no relatório da Rodada 6
      post notes_path(account, patient.id), params: { observations: 'sem a concessão' }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)

      grant!(doctor, { 'pacientes.notas_clinicas' => 'edit' })
      post notes_path(account, patient.id), params: { observations: 'retorno em 30 dias' }, headers: headers, as: :json
      expect(response).to have_http_status(:created)
    end

    it 'a conta B não enxerga a nota da conta A: 401 pela URL de A; 404 colando os ids na URL de B', :aggregate_failures do
      headers = intruder.create_new_auth_token

      get notes_path(account, patient.id), headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)

      get notes_path(other_account, patient.id), headers: headers, as: :json
      expect(response).to have_http_status(:not_found)

      # nota de A pendurada no paciente de B: também não acha
      patch notes_path(other_account, other_patient.id, note.id), params: { observations: 'invadido' }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      delete notes_path(other_account, other_patient.id, note.id), headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(note.reload.observations).to eq('glaucoma inicial — sigilo A')

      # o próprio paciente de B só traz a nota de B
      get notes_path(other_account, other_patient.id), headers: headers, as: :json
      expect(response.parsed_body['notes'].pluck('id')).to eq([other_note.id])
      expect(response.body).not_to include('sigilo A')
    end
  end

  describe 'Espaço do Paciente (patients#show / update_profile)' do
    it 'a conta B não abre nem altera o paciente da conta A', :aggregate_failures do
      headers = intruder.create_new_auth_token

      get crm(account, "patients/#{patient.id}"), headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)

      get crm(other_account, "patients/#{patient.id}"), headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('Maria Sigilo')

      post crm(other_account, "patients/#{patient.id}/update_profile"), params: { sexo: 'masculino' }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(patient.reload.additional_attributes['sexo']).to eq('feminino')
    end

    it 'na própria conta abre normalmente (controle do teste)' do
      get crm(account, "patients/#{patient.id}"), headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'notas dos pacientes (patient_notes)' do
    let!(:patient_note) { patient.notes.create!(account: account, content: 'pediu orçamento de trifocal — A', user: admin) }

    it 'a conta B não lista, não escreve no paciente de A e não apaga a nota de A', :aggregate_failures do
      headers = intruder.create_new_auth_token

      get crm(other_account, 'patient_notes'), headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('trifocal — A')

      expect do
        post crm(other_account, 'patient_notes'), params: { contact_id: patient.id, content: 'invasão' }, headers: headers, as: :json
      end.not_to change(Note, :count)
      expect(response).to have_http_status(:not_found)

      delete crm(other_account, "patient_notes/#{patient_note.id}"), headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(Note.exists?(patient_note.id)).to be(true)

      get crm(account, 'patient_notes'), headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'Pessoas (DISC e metas)' do
    it 'o admin da conta B só vê o time dele e não grava metas de quem é da conta A', :aggregate_failures do
      headers = intruder.create_new_auth_token

      get crm(other_account, 'people'), headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['people'].pluck('user_id')).to eq([intruder.id])

      post crm(other_account, 'people/save_goals'), params: { user_id: agent.id, goals: [] }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(other_account.cevico_people_profiles.where(user_id: agent.id)).to be_empty
    end
  end

  describe 'indicadores (home#kpis) e dashboard do CRM' do
    let(:inbox) { create(:inbox, account: account) }
    let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO', position: 0) }

    it 'o cesto da conta B não soma as conversas da conta A (cache separado por conta)', :aggregate_failures do
      create_list(:conversation, 2, account: account, inbox: inbox)

      get crm(account, 'home/kpis'), params: { preset: 'today' }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body.dig('metrics', 'new_conversations', 'value')).to eq(2.0)

      get crm(other_account, 'home/kpis'), params: { preset: 'today' }, headers: intruder.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('metrics', 'new_conversations', 'value')).to eq(0.0)

      get crm(account, 'home/kpis'), params: { preset: 'today' }, headers: intruder.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'o funil da conta A não abre pela conta B (dashboard do CRM)', :aggregate_failures do
      get crm(account, "pipelines/#{pipeline.id}/dashboard"), headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)

      get crm(other_account, "pipelines/#{pipeline.id}/dashboard"), headers: intruder.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('CEVICO')
    end
  end
end
