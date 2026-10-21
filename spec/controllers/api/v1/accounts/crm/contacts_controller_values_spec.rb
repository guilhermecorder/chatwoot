require 'rails_helper'

# 🔐💰 Auditoria 12/10 — Rodada 2 "Portas fechadas" (achados #0, #287, #300):
# · valor em R$ do card (e a soma por coluna) só chega a quem vê o Financeiro
#   (admin ou nó "financeiro"); só quem EDITA o Financeiro grava valor;
# · "detectar valor" de um card pede o Financeiro; a varredura em lote pede
#   "tratamento de dados" e nunca sobrescreve valor preenchido, a não ser que
#   o admin peça de propósito;
# · "Remover do funil" é de quem trata dados/admin, deixa nota de quem removeu
#   e preserva o histórico de colunas (stage_logs).
RSpec.describe 'CEVICO cards do CRM (valor R$ e remover com rastro)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil CEVICO') }
  let(:stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Envio de Orçamento', position: 0) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/contacts" }
  let(:patient) { create(:contact, account: account, name: 'Maria Teste') }
  let!(:card) { Crm::Contact.create!(contact: patient, pipeline: pipeline, stage: stage, value: 8500) }

  def perms!(hash)
    CrmSetting.find_or_create_by!(account: account).update!(agent_permissions: hash)
  end

  def headers_for(user)
    user.create_new_auth_token
  end

  describe 'valor em R$ (#287)' do
    it 'atendente sem Financeiro não recebe o valor do card nem a soma por coluna', :aggregate_failures do
      get base, params: { scope: 'all' }, headers: headers_for(agent), as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].first['value']).to be_nil

      get base, params: { scope: 'period', date_from: 1.day.ago.to_date.iso8601, date_to: Date.current.iso8601 },
                headers: headers_for(agent), as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['meta']['stage_values']).to eq({})
    end

    it 'admin e quem vê o Financeiro recebem o valor e a soma', :aggregate_failures do
      get base, params: { scope: 'all' }, headers: headers_for(admin), as: :json
      expect(response.parsed_body['payload'].first['value'].to_f).to eq(8500.0)

      perms!('tree' => { agent.id.to_s => { 'financeiro' => 'view' } })
      get base, params: { scope: 'period', date_from: 1.day.ago.to_date.iso8601, date_to: Date.current.iso8601 },
                headers: headers_for(agent), as: :json
      expect(response.parsed_body['payload'].first['value'].to_f).to eq(8500.0)
      expect(response.parsed_body['meta']['stage_values'][stage.id.to_s]).to eq(8500.0)
    end

    it 'atendente sem Financeiro não grava valor (o resto do card salva normalmente)', :aggregate_failures do
      put "#{base}/#{card.id}", params: { value: 1, notes: 'ligou de volta' }, headers: headers_for(agent), as: :json
      expect(response).to have_http_status(:success)
      expect(card.reload.value.to_f).to eq(8500.0)
      expect(card.notes).to eq('ligou de volta')
    end

    it 'atendente sem Financeiro também não cria card já com valor' do
      novo = create(:contact, account: account)
      post base, params: { contact_id: novo.id, stage_id: stage.id, value: 999 }, headers: headers_for(agent), as: :json
      expect(response).to have_http_status(:created)
      expect(Crm::Contact.find(response.parsed_body['id']).value).to be_nil
    end

    it 'quem edita o Financeiro (concessão antiga "finance" ou nó) grava valor', :aggregate_failures do
      perms!('grants' => { agent.id.to_s => ['finance'] })
      put "#{base}/#{card.id}", params: { value: 12_000 }, headers: headers_for(agent), as: :json
      expect(response).to have_http_status(:success)
      expect(card.reload.value.to_f).to eq(12_000.0)

      put "#{base}/#{card.id}", params: { value: 13_000 }, headers: headers_for(admin), as: :json
      expect(card.reload.value.to_f).to eq(13_000.0)
    end

    it 'detectar valor de um card pede o Financeiro' do
      post "#{base}/#{card.id}/detect_value", headers: headers_for(agent), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(card.reload.value.to_f).to eq(8500.0)
    end
  end

  describe 'varredura de valores em lote (#0)' do
    include ActiveJob::TestHelper

    it 'atendente sem "tratamento de dados" não dispara a varredura', :aggregate_failures do
      expect do
        post "#{base}/detect_values_bulk", params: { only_empty: 'false' }, headers: headers_for(agent), as: :json
      end.not_to have_enqueued_job(Crm::BulkDetectValuesJob)
      expect(response).to have_http_status(:forbidden)
    end

    it 'quem trata dados (não admin) só preenche cards vazios, mesmo pedindo para sobrescrever', :aggregate_failures do
      perms!('grants' => { agent.id.to_s => ['data_tools'] })
      expect do
        post "#{base}/detect_values_bulk", params: { only_empty: 'false' }, headers: headers_for(agent), as: :json
      end.to have_enqueued_job(Crm::BulkDetectValuesJob).with(pipeline.id, true)
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['only_empty']).to be(true)
    end

    it 'admin pode sobrescrever de propósito (only_empty=false)' do
      expect do
        post "#{base}/detect_values_bulk", params: { only_empty: 'false' }, headers: headers_for(admin), as: :json
      end.to have_enqueued_job(Crm::BulkDetectValuesJob).with(pipeline.id, false)
    end

    it 'admin sem pedir para sobrescrever também só preenche vazios' do
      expect do
        post "#{base}/detect_values_bulk", headers: headers_for(admin), as: :json
      end.to have_enqueued_job(Crm::BulkDetectValuesJob).with(pipeline.id, true)
    end
  end

  describe 'remover do funil (#300)' do
    let(:other_stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Agendamento de Consulta', position: 1) }

    before { card.update!(stage: other_stage) } # 2 entradas no histórico

    it 'atendente do dia a dia não remove o card (antes qualquer um apagava tudo)', :aggregate_failures do
      delete "#{base}/#{card.id}", headers: headers_for(agent), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Crm::Contact.exists?(card.id)).to be(true)
      expect(Crm::StageLog.where(crm_contact_id: card.id).count).to eq(2)
    end

    it 'admin remove com rastro: nota de quem removeu, histórico de colunas preservado e log fechado', :aggregate_failures do
      delete "#{base}/#{card.id}", headers: headers_for(admin), as: :json
      expect(response).to have_http_status(:no_content)
      expect(Crm::Contact.exists?(card.id)).to be(false)

      logs = Crm::StageLog.where(crm_contact_id: card.id).order(:entered_at)
      expect(logs.count).to eq(2)
      expect(logs.pluck(:left_at)).to all(be_present)
      expect(logs.last.stage_id).to eq(other_stage.id)

      note = patient.notes.order(:id).last
      expect(note.user_id).to eq(admin.id)
      expect(note.content).to include('Removido do funil «Funil CEVICO»', 'Agendamento de Consulta', admin.name)
    end

    it 'quem trata dados também pode remover (com o mesmo rastro)' do
      perms!('tree' => { agent.id.to_s => { 'automacoes.tratamento' => 'edit' } })
      delete "#{base}/#{card.id}", headers: headers_for(agent), as: :json
      expect(response).to have_http_status(:no_content)
      expect(patient.notes.order(:id).last.content).to include(agent.name)
    end
  end

  # Revisão da R2: o valor do card ainda saía por OUTRAS portas abertas ao time
  describe 'outras portas do valor (#287): popup da conversa e resultados de campanha' do
    it 'popup da Agenda/Espaço do Paciente só traz o valor para quem vê o Financeiro', :aggregate_failures do
      url = "/api/v1/accounts/#{account.id}/crm/patient_chat"
      get url, params: { contact_id: patient.id }, headers: headers_for(agent), as: :json
      expect(response.parsed_body['card']).to include('id' => card.id, 'value' => nil)

      get url, params: { contact_id: patient.id }, headers: headers_for(admin), as: :json
      expect(response.parsed_body['card']['value'].to_f).to eq(8500.0)

      perms!('tree' => { agent.id.to_s => { 'financeiro' => 'view' } })
      get url, params: { contact_id: patient.id }, headers: headers_for(agent), as: :json
      expect(response.parsed_body['card']['value'].to_f).to eq(8500.0)
    end

    it 'resultados da campanha: soma e valor dos convertidos só para quem vê o Financeiro', :aggregate_failures do
      inbox = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                        validate_provider_config: false).inbox
      campaign = Crm::Campaign.create!(account: account, inbox: inbox, name: 'Reativação', template_params: { 'name' => 'x' },
                                       conversion_stage_ids: [stage.id])
      Crm::CampaignContact.create!(campaign: campaign, contact: patient, sent_at: 1.day.ago)
      url = "/api/v1/accounts/#{account.id}/crm/campaigns/#{campaign.id}/results"

      get url, headers: headers_for(agent), as: :json
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['conversions']).to include('count' => 1, 'total_value' => nil)
      expect(body['by_procedure'].first).to include('count' => 1, 'total_value' => nil)
      expect(body['converted_contacts'].first).to include('contact_id' => patient.id, 'value' => nil)

      get url, headers: headers_for(admin), as: :json
      body = response.parsed_body
      expect(body['conversions']['total_value'].to_f).to eq(8500.0)
      expect(body['by_procedure'].first['total_value'].to_f).to eq(8500.0)
      expect(body['converted_contacts'].first['value'].to_f).to eq(8500.0)
    end
  end

  describe 'varredura em lote no modo sobrescrever (job)' do
    let(:extractor) { instance_double(Crm::BudgetValueExtractor, max_value: 5000) }

    before { allow(Crm::BudgetValueExtractor).to receive(:new).and_return(extractor) }

    it 'não troca o valor de quem tem FECHAMENTO registrado pelo médico, mas troca os demais', :aggregate_failures do
      Crm::ClinicalNote.create!(account: account, contact: patient, author: admin, performed_at: Time.current,
                                fields: { 'indicated_value' => '8500' })
      outro = create(:contact, account: account)
      outro_card = Crm::Contact.create!(contact: outro, pipeline: pipeline, stage: stage, value: 100)

      expect do
        Crm::BulkDetectValuesJob.perform_now(pipeline.id, false)
      end.not_to have_enqueued_job(CrmAutomationFireJob) # lote grava sem disparar "valor adicionado"
      expect(card.reload.value.to_f).to eq(8500.0)
      expect(outro_card.reload.value.to_f).to eq(5000.0)
    end
  end
end
