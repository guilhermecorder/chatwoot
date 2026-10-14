require 'rails_helper'
require 'rake'

# 🧭 item 341 (13/10): AMBIENTES DO CRM — cada número (caixa) e cada funil
# pertencem a um ambiente; a caixa 12 (Oftalmofácil) nunca cai no CRM da CEVICO.
RSpec.describe Crm::Environments do
  let(:account) { create(:account) }
  let(:cevico_inbox) { create(:inbox, account: account, name: 'WhatsApp Principal') }
  let(:partner_inbox) { create(:inbox, account: account, name: 'Oftalmofácil') }
  let!(:cevico) do
    Crm::Pipeline.create!(account: account, name: 'CEVICO', position: 0).tap do |p|
      p.stages.create!(name: 'Novos Contatos', color: '#000', position: 0)
      p.stages.create!(name: 'Agendamento de Consulta', color: '#000', position: 1)
      p.stages.create!(name: 'Cirurgia Agendada', color: '#000', position: 2)
      p.stages.create!(name: 'Cirurgia Realizada', color: '#000', position: 3)
    end
  end
  let!(:partners) do
    Crm::Pipeline.create!(account: account, name: 'OFTALMOFÁCIL', position: 1).tap do |p|
      p.stages.create!(name: 'Consulta Agendada', color: '#000', position: 0)
      p.stages.create!(name: 'Consulta Confirmada', color: '#000', position: 1)
      p.stages.create!(name: 'Cirurgia Agendada', color: '#000', position: 2)
      p.stages.create!(name: 'Pós Operatório', color: '#000', position: 3)
    end
  end
  let(:partner_source) { Crm::Sources.partner(account) }

  before do
    Rails.cache.clear
    Current.reset
    CrmSetting.create!(account: account, agenda_config: { 'oftalmofacil' => { 'provider_name' => 'CATARATA_SP',
                                                                              'partner_pipeline_id' => partners.id } })
    # o número do Oftalmofácil escolhido na tela Ambientes do CRM (config da fonte)
    partner_source.update!(config: { 'inbox_ids' => [partner_inbox.id] })
    Crm::Sources.forget!(account)
  end

  def person(name, phone)
    create(:contact, account: account, name: name, phone_number: phone)
  end

  def talk(contact, inbox, at: Time.current)
    conv = create(:conversation, account: account, inbox: inbox, contact: contact, created_at: at)
    create(:message, account: account, inbox: inbox, conversation: conv, message_type: :incoming, content: 'oi', created_at: at)
    conv
  end

  def open_conversation(conv)
    CrmListener.instance.conversation_created(Events::Base.new('conversation.created', Time.zone.now, conversation: conv))
  end

  describe 'caixas e funis' do
    it 'a caixa escolhida na tela vale para a cerca e o mapa; funil da casa esconde a caixa do parceiro', :aggregate_failures do
      expect(Crm::PartnerGuard.partner_inbox_ids(account)).to include(partner_inbox.id)
      expect(described_class.environment_for_inbox(account, partner_inbox.id)).to eq(partner_source)
      expect(described_class.environment_for_inbox(account, cevico_inbox.id).key).to eq('cevico')
      expect(described_class.entry_pipeline_for_inbox(account, partner_inbox.id)).to eq(partners)
      expect(described_class.entry_pipeline_for_inbox(account, cevico_inbox.id)).to eq(cevico)
      expect(described_class.foreign_inbox_ids(account, cevico)).to contain_exactly(partner_inbox.id)
      expect(described_class.foreign_inbox_ids(account, partners)).to include(cevico_inbox.id)
      expect(described_class.foreign_inbox_ids(account, partners)).not_to include(partner_inbox.id)
    end
  end

  describe 'quem é o paciente' do
    it 'só conversou pela caixa 12 = Oftalmofácil (G1); falou antes com a CEVICO = CEVICO (regra B)', :aggregate_failures do
      only_partner = person('Só caixa 12', '+5511900000001')
      talk(only_partner, partner_inbox)
      expect(described_class.contact_environment(account, only_partner)).to eq(partner_source)
      expect(Crm::PartnerGuard.partner_contact?(only_partner)).to be true

      cevico_first = person('CEVICO antes', '+5511900000002')
      talk(cevico_first, cevico_inbox, at: 3.days.ago)
      talk(cevico_first, partner_inbox)
      expect(described_class.contact_environment(account, cevico_first).key).to eq('cevico')
      expect(Crm::PartnerGuard.partner_contact?(cevico_first)).to be false
    end

    it 'o card automático que a caixa 12 abria no funil da CEVICO não faz o paciente virar CEVICO (G2)' do
      old = person('Antigo da caixa 12', '+5511900000003')
      talk(old, partner_inbox, at: 30.days.ago)
      Crm::CardRouter.bypass('carga') do
        Crm::Contact.create!(contact: old, pipeline: cevico, stage: cevico.stages.first, origin: 'Oftalmofácil', created_at: 30.days.ago)
      end
      expect(described_class.contact_environment(account, old)).to eq(partner_source)
    end

    it 'agendamento marcado CEVICO na Agenda mantém o paciente na CEVICO' do
      marked = person('Marcado CEVICO', '+5511900000004')
      talk(marked, partner_inbox)
      Task.create!(account: account, creator: create(:user, account: account), title: 'Consulta', task_type: 'consulta',
                   due_at: 2.days.from_now, contact: marked, origin: 'cevico')
      expect(described_class.contact_environment(account, marked).key).to eq('cevico')
    end

    it 'paciente antigo que chega pela caixa 12 é carimbado Oftalmofácil (G3)' do
      old = create(:contact, account: account, phone_number: '+5511900000005', created_at: 2.months.ago)
      open_conversation(talk(old, partner_inbox))
      expect(old.reload.cevico_source_id).to eq(partner_source.id)
    end
  end

  describe 'porta de entrada (CrmListener)' do
    it 'conversa nova na caixa 12 abre card no funil do Oftalmofácil em Novo Contato, nunca na CEVICO', :aggregate_failures do
      patient = person('Nova', '+5511900000006')
      open_conversation(talk(patient, partner_inbox))
      card = Crm::Contact.find_by(contact_id: patient.id, pipeline_id: partners.id)
      expect(card.stage.name).to eq('Novo Contato')
      expect(card.stage.position).to be < partners.stages.where(name: 'Consulta Agendada').pick(:position)
      expect(Crm::Contact.where(contact_id: patient.id, pipeline_id: cevico.id)).not_to exist
    end

    it 'conversa na caixa da CEVICO continua abrindo card no funil da CEVICO' do
      patient = person('Da casa', '+5511900000007')
      open_conversation(talk(patient, cevico_inbox))
      expect(Crm::Contact.where(contact_id: patient.id, pipeline_id: cevico.id)).to exist
    end
  end

  describe Crm::CardRouter do
    let(:patient) { person('Paciente OF', '+5511900000008').tap { |c| talk(c, partner_inbox) } }

    it 'card da CEVICO pedido para paciente do Oftalmofácil nasce no funil dele, na coluna equivalente', :aggregate_failures do
      card = Crm::Contact.create!(contact: patient, pipeline: cevico, stage: cevico.stages.find_by(name: 'Agendamento de Consulta'))
      expect(card.pipeline_id).to eq(partners.id)
      expect(card.stage.name).to eq('Consulta Agendada')
      expect(card.cevico_source_id).to eq(partner_source.id)
      expect(Crm::Contact.where(contact_id: patient.id, pipeline_id: cevico.id)).not_to exist
    end

    it 'se já tem card lá, o card de lá anda (nunca para trás) e o da CEVICO não nasce', :aggregate_failures do
      existing = Crm::Contact.create!(contact: patient, pipeline: partners, stage: partners.stages.find_by(name: 'Consulta Agendada'))
      expect do
        Crm::Contact.create!(contact: patient, pipeline: cevico, stage: cevico.stages.find_by(name: 'Cirurgia Realizada'))
      end.to raise_error(ActiveRecord::RecordInvalid)
      expect(existing.reload.stage.name).to eq('Cirurgia Realizada') # a coluna nasce no funil do parceiro
      expect(Crm::Contact.where(contact_id: patient.id, pipeline_id: cevico.id)).not_to exist
    end

    it 'o passe livre (administrador / migração) deixa o card no funil pedido' do
      card = described_class.bypass('admin') { Crm::Contact.create!(contact: patient, pipeline: cevico, stage: cevico.stages.first) }
      expect(card.pipeline_id).to eq(cevico.id)
    end

    it 'paciente da CEVICO não é tocado' do
      ours = person('Nosso', '+5511900000009')
      card = Crm::Contact.create!(contact: ours, pipeline: cevico, stage: cevico.stages.second)
      expect(card.pipeline_id).to eq(cevico.id)
    end
  end

  describe Crm::PartnerFunnel do
    it 'garante as colunas da jornada, cada uma no lugar certo' do
      described_class.ensure_stages!(account)
      names = partners.stages.reload.order(:position).pluck(:name)
      # 🧩 item 344: a pré-definição completa (11 colunas da jornada)
      expect(names).to eq(['Novo Contato', 'Consulta Agendada', 'Desmarcou a Consulta', 'Consulta Confirmada', 'Não Foi à Consulta',
                           'Consulta Realizada',
                           'Indicação de Cirurgia', 'Sem Indicação Cirúrgica', 'Não Fechou Ainda', 'Cirurgia Agendada',
                           'Cirurgia Realizada', 'Pós Operatório', 'Retorno'])
      expect { described_class.ensure_stages!(account) }.not_to change(Crm::Stage, :count)
    end

    # o funil de PRODUÇÃO em 13/10 (organizado por tipo de procedimento)
    it 'no funil de produção: reconhece "Novo paciente"/"Cirurgia", cria o resto e põe a jornada na frente', :aggregate_failures do
      partners.stages.destroy_all
      ['Consulta Agendada', 'Consulta Confirmada', 'Cirurgia', 'Exame', 'Consulta', 'Adaptação de Lente Rígida', 'Retornos',
       'Aplicação Intravítrea', 'Novo paciente'].each_with_index { |name, i| partners.stages.create!(name: name, color: '#000', position: i) }
      exame = partners.stages.find_by(name: 'Exame')

      described_class.apply_preset!(account)
      names = partners.stages.reload.order(:position).pluck(:name)
      expect(names).to eq(['Novo paciente', 'Consulta Agendada', 'Desmarcou a Consulta', 'Consulta Confirmada', 'Não Foi à Consulta',
                           'Consulta Realizada', 'Indicação de Cirurgia', 'Sem Indicação Cirúrgica', 'Não Fechou Ainda', 'Cirurgia',
                           'Cirurgia Realizada', 'Pós Operatório', 'Retornos', 'Exame', 'Consulta', 'Adaptação de Lente Rígida',
                           'Aplicação Intravítrea'])
      expect(exame.reload.pipeline_id).to eq(partners.id) # nada é apagado
      expect(described_class.preset_preview(account)[:in_order]).to be(true)
      expect(described_class.find_stage(partners, :surgery).name).to eq('Cirurgia')
    end
  end

  describe Crm::EnvironmentMigration do
    let!(:mover) do
      person('Mover', '+5511911112222').tap do |c|
        talk(c, partner_inbox, at: 20.days.ago)
        Crm::CardRouter.bypass('carga') do
          card = Crm::Contact.create!(contact: c, pipeline: cevico, stage: cevico.stages.first, created_at: 20.days.ago)
          card.update!(stage_id: cevico.stages.find_by(name: 'Agendamento de Consulta').id)
        end
        c.update_column(:cevico_source_id, Crm::Sources.own_id(account)) # rubocop:disable Rails/SkipsModelValidations
      end
    end
    let!(:keeper) do
      person('Manter', '+5511933334444').tap do |c|
        talk(c, cevico_inbox, at: 40.days.ago)
        Crm::Contact.create!(contact: c, pipeline: cevico, stage: cevico.stages.first, created_at: 40.days.ago)
        talk(c, partner_inbox, at: 2.days.ago)
      end
    end

    it 'DRY separa MOVER e MANTER sem mudar nada', :aggregate_failures do
      migration = described_class.new(account)
      buckets = migration.rows.to_h { |row| [row.contact.id, row.bucket] }
      expect(buckets).to eq(mover.id => 'MOVER', keeper.id => 'MANTER')
      expect(migration.describe(migration.rows.find { |r| r.contact.id == mover.id })).to include('…2222', 'MOVER', 'Consulta Agendada')
      expect(Crm::Contact.where(contact_id: mover.id, pipeline_id: cevico.id)).to exist
      expect(Crm::Contact.where(contact_id: mover.id, pipeline_id: partners.id)).not_to exist
    end

    it 'gravando: o card sai da CEVICO, o histórico vai junto e nada conta como hoje', :aggregate_failures do
      old_card = Crm::Contact.find_by(contact_id: mover.id, pipeline_id: cevico.id)
      old_logs = old_card.stage_logs.pluck(:id)
      expect(described_class.new(account).run!).to eq(1)

      expect(Crm::Contact.where(contact_id: mover.id, pipeline_id: cevico.id)).not_to exist
      card = Crm::Contact.find_by(contact_id: mover.id, pipeline_id: partners.id)
      expect(card.stage.name).to eq('Consulta Agendada')
      expect(card.created_at).to be < 19.days.ago
      expect(Crm::StageLog.where(id: old_logs).pluck(:crm_contact_id).uniq).to eq([card.id])
      expect(Crm::StageLog.where(id: old_logs).pluck(:cevico_source_id).uniq).to eq([partner_source.id])
      expect(card.stage_logs.where.not(id: old_logs).pluck(:event_type)).to eq([Crm::StageLogBulk::BULK])
      expect(mover.reload.cevico_source_id).to eq(partner_source.id)
      expect(Crm::Contact.where(contact_id: keeper.id, pipeline_id: cevico.id)).to exist
    end

    it 'o rake: DRY só lista; MODO=resumo conta' do
      Rails.application.load_tasks unless Rake::Task.task_defined?('cevico:ambientes_migrar')
      task = Rake::Task['cevico:ambientes_migrar']
      ClimateControl.modify(ACCOUNT_ID: account.id.to_s, DRY: '1') do
        expect { task.invoke }.to output(/MOVER 1 · MANTER 1 · REVISAR 0.*DRY: nada mudou/m).to_stdout
      end
      task.reenable
      ClimateControl.modify(ACCOUNT_ID: account.id.to_s, MODO: 'resumo') do
        expect { task.invoke }.to output(/MOVER\s+1 pacientes/).to_stdout
      end
      task.reenable
      expect(Crm::Contact.where(contact_id: mover.id, pipeline_id: cevico.id)).to exist
    end
  end

  describe 'tela Ambientes do CRM', type: :request do
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:other) { Crm::Source.create!(account: account, key: 'outra', name: 'Outra clínica', kind: 'partner') }

    it 'o número que já é do Oftalmofácil não entra em outro ambiente (422); o do Oftalmofácil se escolhe aqui', :aggregate_failures do
      patch "/api/v1/accounts/#{account.id}/crm/sources/#{other.id}", params: { inbox_ids: [partner_inbox.id] },
                                                                      headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('Oftalmofácil')

      patch "/api/v1/accounts/#{account.id}/crm/sources/#{partner_source.id}", params: { inbox_ids: [cevico_inbox.id] },
                                                                               headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(Crm::PartnerGuard.partner_inbox_ids(account)).to contain_exactly(cevico_inbox.id)
      expect(CrmSetting.find_by(account: account).agenda_config.dig('oftalmofacil', 'partner_inbox_ids')).to eq([cevico_inbox.id])
      # 🧩 item 344: salvar não cria colunas sozinho — quem cria é a pré-definição
      expect(partners.stages.reload.pluck(:name)).not_to include('Novo Contato')
    end

    it 'pré-definição: mostra o que falta e cria as colunas da jornada no lugar certo', :aggregate_failures do
      get "/api/v1/accounts/#{account.id}/crm/sources/funnel_preset", headers: admin.create_new_auth_token, as: :json
      missing = response.parsed_body.dig('preset', 'columns').reject { |c| c['exists'] }.pluck('name')
      expect(missing).to include('Novo Contato', 'Consulta Realizada', 'Sem Indicação Cirúrgica')

      post "/api/v1/accounts/#{account.id}/crm/sources/funnel_preset", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body.dig('preset', 'columns').all? { |c| c['exists'] }).to be(true)
      expect(partners.stages.reload.order(:position).pick(:name)).to eq('Novo Contato')
    end
  end
end
