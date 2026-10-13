require 'rails_helper'

# 🫁 Auditoria 12/10 — Rodada 7 "Fôlego" (achado #323):
# · "Carregar todos" (scope=all) não entrega mais o funil inteiro de uma vez:
#   vem a contagem verdadeira por coluna e no máximo 200 cards por coluna; o
#   resto chega pelo "Carregar mais" da coluna (stage_page com range=all);
# · a busca vai junto (q=) e é feita no servidor, então acha o paciente mesmo
#   que ele não esteja entre os cards já carregados;
# · os dados do card carregam só a conversa do balão (1 por card), não todas
#   as conversas de todos os contatos;
# · "N com conversa" fica guardado 5 minutos por funil;
# · os caminhos antigos (days=365 e recent) também param no teto por coluna.
RSpec.describe 'CEVICO board do CRM em páginas (Carregar todos)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil CEVICO') }
  let(:stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Novo Lead', position: 0) }
  let(:other_stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Envio de Orçamento', position: 1) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/contacts" }
  let(:inbox) { create(:inbox, account: account) }
  let(:main_inbox) { create(:inbox, account: account) }

  def card!(stage_record, name:, activity: Time.current, notes: nil)
    contact = create(:contact, account: account, name: name)
    contact.update_columns(last_activity_at: activity) # rubocop:disable Rails/SkipsModelValidations
    Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage_record, notes: notes)
  end

  def conversation!(contact, inbox_record, at)
    conv = create(:conversation, account: account, contact: contact, inbox: inbox_record)
    conv.update_columns(last_activity_at: at) # rubocop:disable Rails/SkipsModelValidations
    conv
  end

  def get_board(params)
    get base, params: params, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    response.parsed_body
  end

  describe 'scope=all em páginas por coluna' do
    before do
      12.times { |i| card!(stage, name: "Paciente #{i}", activity: i.hours.ago) }
      card!(other_stage, name: 'Outro Paciente')
    end

    it 'entrega no máximo N cards por coluna com a contagem verdadeira', :aggregate_failures do
      body = get_board(scope: 'all', per_stage: 10)

      expect(body['meta']['scope']).to eq('all')
      expect(body['meta']['per_stage']).to eq(10)
      expect(body['meta']['stage_counts']).to eq(stage.id.to_s => 12, other_stage.id.to_s => 1)
      expect(body['meta']['matching']).to eq(13)
      expect(body['meta']['total']).to eq(13)
      expect(body['payload'].count { |c| c['stage_id'] == stage.id }).to eq(10)
      expect(body['payload'].count { |c| c['stage_id'] == other_stage.id }).to eq(1)
      # os mais recentes primeiro (mesma ordem do período)
      expect(body['payload'].map { |c| c['name'] }).not_to include('Paciente 10', 'Paciente 11')
    end

    it 'usa 200 por coluna como padrão e nunca passa disso' do
      expect(get_board(scope: 'all')['meta']['per_stage']).to eq(200)
      expect(get_board(scope: 'all', per_stage: 5000)['meta']['per_stage']).to eq(200)
    end

    it '"Carregar mais" da coluna traz o restante da base toda (range=all)', :aggregate_failures do
      body = get_board(scope: 'stage_page', range: 'all', stage_id: stage.id, offset: 10, limit: 10)

      expect(body['meta']['stage_total']).to eq(12)
      expect(body['payload'].map { |c| c['name'] }).to contain_exactly('Paciente 10', 'Paciente 11')
    end

    it 'sem range=all a próxima página continua respeitando o período' do
      body = get_board(scope: 'stage_page', stage_id: stage.id, offset: 0,
                       date_from: 10.years.ago.to_date.iso8601, date_to: 9.years.ago.to_date.iso8601)
      expect(body['meta']['stage_total']).to eq(0)
    end
  end

  describe 'caminhos antigos (days e recent) também têm teto por coluna' do
    before do
      # teto pequeno só neste teste, para não criar 200 cards
      stub_const('Api::V1::Accounts::Crm::ContactsController::ALL_PER_STAGE', 5)
      7.times { |i| card!(stage, name: "Paciente #{i}", activity: i.hours.ago) }
      card!(other_stage, name: 'Outro Paciente')
    end

    it 'days=365 nunca passa de N cards por coluna', :aggregate_failures do
      body = get_board(scope: 'days', days: 365)

      expect(body['meta']['total']).to eq(8)
      expect(body['payload'].count { |c| c['stage_id'] == stage.id }).to eq(5)
      expect(body['payload'].count { |c| c['stage_id'] == other_stage.id }).to eq(1)
      # fica com os mais recentes
      expect(body['payload'].map { |c| c['name'] }).not_to include('Paciente 5', 'Paciente 6')
    end

    it 'recent (sem scope) nunca passa de N cards por coluna' do
      body = get_board({})
      expect(body['payload'].count { |c| c['stage_id'] == stage.id }).to eq(5)
    end
  end

  describe 'busca no servidor (q)' do
    before do
      12.times { |i| card!(stage, name: "Paciente #{i}") }
      antiga = card!(stage, name: 'Joana Antiga', activity: 3.years.ago, notes: 'quer lente trifocal')
      antiga.contact.update!(phone_number: '+5511988887777')
      antiga.contact.add_labels(['retorno_tatuape'])
    end

    it 'acha o paciente fora da primeira página por nome, telefone, anotação e etiqueta', :aggregate_failures do
      %w[joana 98888 TRIFOCAL tatuape].each do |termo|
        body = get_board(scope: 'all', per_stage: 10, q: termo)
        expect(body['payload'].map { |c| c['name'] }).to eq(['Joana Antiga']), "busca por #{termo}"
        expect(body['meta']['q']).to eq(termo)
        expect(body['meta']['stage_counts']).to eq(stage.id.to_s => 1)
      end
    end

    it 'trata % e _ como texto (não como curinga)' do
      body = get_board(scope: 'all', q: '%')
      expect(body['payload']).to be_empty
    end
  end

  describe 'dados do card (conversa do balão)' do
    let!(:card) { card!(stage, name: 'Carlos') }

    it 'escolhe a conversa mais recente e conta todas, carregando só a do balão', :aggregate_failures do
      old_ones = Array.new(4) { |i| conversation!(card.contact, inbox, (i + 2).days.ago) }
      newest = conversation!(card.contact, inbox, 1.hour.ago)

      loaded = []
      callback = lambda do |*, payload|
        loaded << payload[:record_count] if payload[:class_name] == 'Conversation'
      end
      body = ActiveSupport::Notifications.subscribed(callback, 'instantiation.active_record') do
        get_board(scope: 'all')
      end

      json = body['payload'].first
      expect(json['last_conversation_id']).to eq(newest.id)
      expect(json['conversations_count']).to eq(5)
      expect(old_ones.map(&:id)).not_to include(json['last_conversation_id'])
      # antes: as 5 conversas viravam objetos; agora só a do balão
      expect(loaded.sum).to eq(1)
    end

    it 'coluna com caixa principal prefere a conversa mais recente dessa caixa', :aggregate_failures do
      stage.update!(settings: { 'main_inbox_ids' => [main_inbox.id] })
      in_main = conversation!(card.contact, main_inbox, 3.days.ago)
      conversation!(card.contact, inbox, 1.hour.ago)

      json = get_board(scope: 'all')['payload'].first
      expect(json['last_conversation_id']).to eq(in_main.id)
      expect(json['last_conversation']['inbox_id']).to eq(main_inbox.id)
    end

    it 'sem conversa na caixa principal, cai na mais recente de qualquer caixa' do
      stage.update!(settings: { 'main_inbox_ids' => [main_inbox.id] })
      newest = conversation!(card.contact, inbox, 1.hour.ago)

      expect(get_board(scope: 'all')['payload'].first['last_conversation_id']).to eq(newest.id)
    end
  end

  describe '"N com conversa"' do
    it 'conta cards com pelo menos uma conversa e guarda por 5 minutos', :aggregate_failures do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      com = card!(stage, name: 'Com conversa')
      sem = card!(stage, name: 'Sem conversa')
      2.times { conversation!(com.contact, inbox, 1.hour.ago) }

      expect(get_board(scope: 'all')['meta']['with_conversations']).to eq(1)

      conversation!(sem.contact, inbox, 1.minute.ago)
      expect(get_board(scope: 'preview')['meta']['with_conversations']).to eq(1)

      travel 6.minutes do
        expect(get_board(scope: 'all')['meta']['with_conversations']).to eq(2)
      end
    end
  end
end
