require 'rails_helper'

# 🏷️ Rodada 5 da auditoria (#17): a automação "Etiqueta adicionada/removida"
# sai do SERVIDOR quando a etiqueta do contato muda de verdade — venha de onde
# vier (tela Contatos do Chatwoot, API/N8N, automação, conversa). Antes só a
# etiqueta salva pelas telas do CRM disparava (o navegador mandava o diff).
RSpec.describe Contact, type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil CEVICO') }
  let(:stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Orçamento') }
  let(:contact) { create(:contact, account: account) }
  let!(:card) { Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage) }

  def automation!(trigger, filter: nil, on_stage: stage)
    Crm::Automation.create!(stage: on_stage, name: "Auto #{trigger}", trigger_type: trigger, action_type: 'webhook',
                            delay_minutes: 0, active: true,
                            action_config: { 'webhook_url' => 'https://exemplo.test/hook', 'label_filter' => filter }.compact)
  end

  def fire_jobs_for(automation)
    enqueued_jobs.select { |j| j['job_class'] == 'CrmAutomationFireJob' && j['arguments'].first == automation.id }
  end

  before { clear_enqueued_jobs }
  after { Current.reset }

  # etiqueta posta por uma PESSOA da equipe (tela com login)
  def as_person
    Current.user = admin
    yield
  ensure
    Current.user = nil
  end

  describe 'etiqueta aplicada fora das telas do CRM' do
    it 'tela Contatos do Chatwoot (PUT /contacts/:id/labels) dispara "Etiqueta adicionada"' do
      automation = automation!('label_added', filter: 'catarata')

      post "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/labels",
           params: { labels: ['catarata'] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(fire_jobs_for(automation).size).to eq(1)
      expect(fire_jobs_for(automation).first['arguments'].second).to eq(contact.id)
    end

    it 'API/N8N/automação (update_labels) dispara só para a etiqueta do filtro' do
      catarata = automation!('label_added', filter: 'catarata')
      miopia = automation!('label_added', filter: 'miopia')

      contact.update_labels(['catarata'])

      expect(fire_jobs_for(catarata).size).to eq(1)
      expect(fire_jobs_for(miopia)).to be_empty
    end

    it 'etiqueta que sai do contato dispara "Etiqueta removida"' do
      contact.update_labels(%w[catarata vip])
      removed = automation!('label_removed', filter: 'vip')
      clear_enqueued_jobs

      contact.update_labels(['catarata'])

      expect(fire_jobs_for(removed).size).to eq(1)
    end

    it 'dispara na coluna de CADA card do contato (um por funil)' do
      other_pipeline = Crm::Pipeline.create!(account: account, name: 'Outro funil')
      other_stage = Crm::Stage.create!(pipeline: other_pipeline, name: 'Lead')
      Crm::Contact.create!(contact: contact, pipeline: other_pipeline, stage: other_stage)
      here = automation!('label_added')
      there = automation!('label_added', on_stage: other_stage)

      as_person { contact.add_labels(['catarata']) }

      expect(fire_jobs_for(here).size).to eq(1)
      expect(fire_jobs_for(there).size).to eq(1)
    end

    it 'salvar o contato sem mexer na etiqueta não dispara nada' do
      contact.update_labels(['catarata'])
      automation = automation!('label_added')
      clear_enqueued_jobs

      contact.update!(name: 'Outro nome')
      contact.update_labels(['catarata'])

      expect(fire_jobs_for(automation)).to be_empty
    end
  end

  describe 'um disparo só (contato + etiqueta + automação)' do
    it 'a tela do CRM avisando depois do salvamento não dispara de novo' do
      automation = automation!('label_added', filter: 'catarata')

      contact.update_labels(['catarata'])
      post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/contacts/#{card.id}/trigger_label_change",
           params: { added: ['catarata'] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(fire_jobs_for(automation).size).to eq(1)
    end

    it 'trigger_label_change não dispara nada: etiqueta que NÃO está no contato' do
      automation = automation!('label_added', filter: 'catarata')

      post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/contacts/#{card.id}/trigger_label_change",
           params: { added: ['catarata'] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(fire_jobs_for(automation)).to be_empty
    end

    it 'trigger_label_change com foto velha da tela não repete o disparo depois que a marca vence' do
      automation = automation!('label_added', filter: 'catarata')
      contact.update_labels(['catarata']) # a IA pôs a etiqueta há tempo
      Redis::LockManager.new.unlock(
        CrmAutomationTriggerService.label_dedup_key('label_added', automation.id, contact.id, 'catarata')
      )
      clear_enqueued_jobs

      post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/contacts/#{card.id}/trigger_label_change",
           params: { added: ['catarata'] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(fire_jobs_for(automation)).to be_empty
    end

    it 'trigger_label_change: "removida" que ainda está no contato não dispara' do
      contact.update_labels(['vip'])
      automation = automation!('label_removed', filter: 'vip')
      clear_enqueued_jobs

      post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/contacts/#{card.id}/trigger_label_change",
           params: { removed: ['vip'] }, headers: admin.create_new_auth_token, as: :json

      expect(fire_jobs_for(automation)).to be_empty
    end
  end

  describe 'carga em massa não dispara' do
    it 'ação em lote da tela Contatos (BulkAssignLabelsService) fica muda' do
      automation = automation!('label_added', filter: 'catarata')

      Contacts::BulkAssignLabelsService.new(account: account, contact_ids: [contact.id], labels: ['catarata']).perform

      expect(contact.reload.label_list).to include('catarata')
      expect(fire_jobs_for(automation)).to be_empty
    end

    it 'remoção em lote também fica muda' do
      contact.update_labels(['vip'])
      automation = automation!('label_removed', filter: 'vip')
      clear_enqueued_jobs

      Contacts::BulkRemoveLabelsService.new(account: account, contact_ids: [contact.id], labels: ['vip']).perform

      expect(fire_jobs_for(automation)).to be_empty
    end

    it 'Tratamento de dados: trocar etiqueta em massa (LabelReplaceService) fica mudo' do
      contact.update_labels(['refrativa'])
      added = automation!('label_added')
      removed = automation!('label_removed')
      clear_enqueued_jobs

      Crm::LabelReplaceService.new(account: account, from_label: 'refrativa', to_label: 'orcamento-refrativa').apply!

      expect(contact.reload.label_list).to eq(['orcamento-refrativa'])
      expect(fire_jobs_for(added)).to be_empty
      expect(fire_jobs_for(removed)).to be_empty
    end

    it 'Tratamento de dados: remover etiqueta da coluna (LabelRemoveService) fica mudo' do
      contact.update_labels(['vip'])
      removed = automation!('label_removed', filter: 'vip')
      clear_enqueued_jobs

      Crm::LabelRemoveService.new(account: account, label: 'vip', stage_id: stage.id).apply!

      expect(contact.reload.label_list).to be_empty
      expect(fire_jobs_for(removed)).to be_empty
    end

    it 'Tratamento de dados: unificar duplicados (ContactUnificationService) fica mudo' do
      contact.update!(phone_number: '+5511999990001')
      duplicate = create(:contact, account: account, email: nil)
      duplicate.update_labels(['catarata'])
      # mesmo número, escrito de outro jeito (como os duplicados reais)
      duplicate.update_column(:phone_number, '+55 11 99999-0001') # rubocop:disable Rails/SkipsModelValidations
      added = automation!('label_added', filter: 'catarata')
      clear_enqueued_jobs

      result = Crm::ContactUnificationService.new(account: account).apply!

      expect(result[:merged]).to eq(1)
      expect(fire_jobs_for(added)).to be_empty
    end

    it 'fora do bloco de lote volta a disparar normalmente' do
      automation = automation!('label_added', filter: 'catarata')
      described_class.without_label_triggers { nil }

      contact.update_labels(['catarata'])

      expect(fire_jobs_for(automation).size).to eq(1)
    end
  end

  describe 'paciente em silêncio (Crm::OptOut)' do
    it '"Qualquer etiqueta" não manda nada para fora de quem pediu para parar' do
      webhook = automation!('label_added')
      interna = Crm::Automation.create!(stage: stage, name: 'Etiqueta interna', trigger_type: 'label_added',
                                        action_type: 'apply_label', delay_minutes: 0, active: true,
                                        action_config: { 'label' => 'revisar' })

      as_person { contact.add_labels([Crm::OptOut::LABEL]) }

      expect(fire_jobs_for(webhook)).to be_empty
      expect(fire_jobs_for(interna).size).to eq(1)
    end

    it 'quem não está em silêncio segue recebendo normalmente' do
      webhook = automation!('label_added')

      as_person { contact.add_labels(['catarata']) }

      expect(fire_jobs_for(webhook).size).to eq(1)
    end
  end

  # 🚧 item 345 (14/10): a "Ag. Consulta – Google" sem filtro jogava em
  # Agendamento todo lead que ganhava etiqueta de robô (refrativa, att_encerrado…)
  describe '"Qualquer etiqueta" só com etiqueta posta por pessoa' do
    let(:move_to) { Crm::Stage.create!(pipeline: pipeline, name: 'Agendamento de Consulta') }

    def mover!(filter: nil)
      Crm::Automation.create!(stage: stage, name: 'Ag. Consulta', trigger_type: 'label_added', action_type: 'move_card',
                              delay_minutes: 0, active: true,
                              action_config: { 'target_stage_id' => move_to.id, 'label_filter' => filter }.compact)
    end

    it 'etiqueta de ROBÔ (sem pessoa logada) não dispara a automação sem filtro' do
      automation = mover!

      contact.add_labels(['refrativa'])
      contact.add_labels(['att_encerrado'])

      expect(fire_jobs_for(automation)).to be_empty
    end

    it 'etiqueta de robô continua disparando a automação que pediu ESSA etiqueta' do
      automation = mover!(filter: 'consulta_google')

      contact.add_labels(['consulta_google'])

      expect(fire_jobs_for(automation).size).to eq(1)
    end

    it 'etiqueta posta pela equipe na tela dispara a automação sem filtro' do
      automation = mover!

      post "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/labels",
           params: { labels: ['refrativa'] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(fire_jobs_for(automation).size).to eq(1)
    end

    it 'remover etiqueta por robô também não dispara a automação sem filtro' do
      contact.update_labels(['refrativa'])
      removed = automation!('label_removed')
      clear_enqueued_jobs

      contact.update_labels([])

      expect(fire_jobs_for(removed)).to be_empty
    end
  end
end
