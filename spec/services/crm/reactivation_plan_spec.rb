require 'rails_helper'

# 📣 item 381 (03/11): plano de reativação em FATIAS — X mensagens por dia,
# divididas por coluna em %, pela caixa da 1ª conversa de cada paciente, só na
# janela de horário, cada pessoa uma vez no plano inteiro.
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe Crm::ReactivationPlan do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:templates) do
    [{ 'name' => 'reativa', 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'MARKETING' },
     { 'name' => 'catarata', 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'MARKETING' }]
  end
  let!(:google) { whatsapp_inbox('GOOGLE') }
  let!(:insta) { whatsapp_inbox('INSTAGRAM') }
  let(:pipeline) { account.crm_pipelines.create!(name: 'CEVICO | Jornada do Paciente') }
  let(:nao_fechou) { pipeline.stages.create!(name: 'Não Fechou Ainda', position: 1) }
  let(:orcamento) { pipeline.stages.create!(name: 'Envio de Orçamento', position: 2) }
  let(:tpl) do
    { 'template_params' => { 'name' => 'reativa', 'language' => 'pt_BR', 'category' => 'MARKETING',
                             'processed_params' => { 'body' => { '1' => '{{contact.name}}' } } },
      'message_preview' => 'Oi {{1}}' }
  end
  let(:raw) do
    { 'daily_cap' => 10, 'hour_from' => 9, 'hour_to' => 11, 'inbox_daily_cap' => 100, 'default_inbox_id' => google.id, 'approval' => 'auto',
      'quiet_hours' => 0, 'min_age_days' => 0,
      'slices' => [{ 'key' => 'nao_fechou', 'stage_id' => nao_fechou.id, 'share' => 70, 'templates' => { 'padrao' => tpl } },
                   { 'key' => 'orcamento', 'stage_id' => orcamento.id, 'share' => 30,
                     'templates' => { 'padrao' => tpl, 'catarata' => tpl.deep_merge('template_params' => { 'name' => 'catarata' }) } }] }
  end
  let(:sent_to) { [] }

  def whatsapp_inbox(name)
    inbox = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
    inbox.update!(name: name)
    inbox.channel.update_columns(message_templates: templates) # rubocop:disable Rails/SkipsModelValidations
    inbox
  end

  def card!(name, phone, stage, procedure: nil, created_at: 10.days.ago)
    contact = create(:contact, account: account, name: name, phone_number: phone, created_at: created_at)
    card = Crm::Contact.create!(pipeline: pipeline, stage: stage, contact: contact, procedure_of_interest: procedure)
    card.update_columns(stage_moved_at: created_at) # rubocop:disable Rails/SkipsModelValidations -- o callback põe "agora"
    contact
  end

  # envio falso: anota [contato, caixa] e devolve uma conversa NA CAIXA do source
  def fake_sender
    allow(Crm::SendTemplateService).to receive(:new) do |source:, contact:|
      sender = instance_double(Crm::SendTemplateService, message: nil)
      allow(sender).to receive(:perform) do
        sent_to << [contact.id, source.inbox_id]
        create(:conversation, account: account, inbox: source.inbox, contact: contact)
      end
      sender
    end
  end

  before { stub_const('Crm::ReactivationPlan::THROTTLE_SECONDS', 0) }

  describe '.normalize' do
    it 'aplica padrões, limites e limpa as fatias' do
      slices = [{ 'stage_id' => 0 }, { 'stage_id' => 5, 'share' => '150', 'templates' => { 'padrao' => { 'template_params' => {} } } }]
      cfg = described_class.normalize('daily_cap' => '99999', 'hour_from' => 10, 'hour_to' => 8, 'order' => 'x', 'slices' => slices)
      expect(cfg).to include('daily_cap' => 300, 'hour_from' => 10, 'hour_to' => 11, 'order' => 'recent', 'weekdays_only' => true)
      expect(cfg['slices']).to eq([{ 'key' => 'col5', 'stage_id' => 5, 'share' => 0, 'templates' => {} }])
    end
  end

  describe '.allocate' do
    it 'divide a cota da hora pelos déficits e fatia vazia cede a vez' do
      alloc = described_class.allocate(10, { 'a' => 7, 'b' => 3, 'c' => 5 }, { 'a' => 100, 'b' => 100, 'c' => 0 })
      expect(alloc.values.sum).to eq(10)
      expect(alloc['c']).to eq(0)
      expect(alloc['a']).to be > alloc['b']
      expect(described_class.allocate(10, { 'a' => 2 }, { 'a' => 1 })).to eq('a' => 1)
    end
  end

  describe '.frente_of' do
    it 'classifica pelo procedimento do card' do
      expect(described_class.frente_of('Catarata OD')).to eq('catarata')
      expect(described_class.frente_of('Lente fácica Artisan')).to eq('lentes')
      expect(described_class.frente_of('LASIK')).to eq('padrao')
      expect(described_class.frente_of(nil)).to eq('padrao')
    end
  end

  describe 'o plano inteiro' do
    it 'salva a mãe, manda a fatia da hora pela caixa de origem, uma vez por pessoa, e respeita janela e teto' do
      ana = card!('Ana', '+5511999990001', nao_fechou, created_at: 1.day.ago)
      bia = card!('Bia', '+5511999990002', nao_fechou, created_at: 2.days.ago)
      caio = card!('Caio', '+5511999990003', orcamento, procedure: 'Catarata', created_at: 3.days.ago)
      quieto = card!('Quieto', '+5511999990004', nao_fechou)
      quieto.update!(label_list: ['nao_perturbe'])
      marcado = card!('Marcado', '+5511999990005', orcamento)
      Task.create!(account: account, creator: admin, title: 'Consulta', task_type: 'consulta', due_at: 2.days.from_now, contact: marcado)
      create(:conversation, account: account, inbox: insta, contact: ana, created_at: 5.days.ago) # Ana veio pelo Instagram

      mother = described_class.upsert!(account, raw, user: admin)
      expect(mother).to be_draft
      expect(mother.reactivation_plan?).to be(true)
      expect(described_class.find(account)).to eq(mother)

      sim = described_class.simulate(mother, described_class.config(mother))
      expect(sim[:slices].map { |s| [s[:key], s[:pool], s[:per_day]] }).to eq([['nao_fechou', 2, 7], ['orcamento', 1, 3]])
      expect(sim[:total_pool]).to eq(3)

      fake_sender
      mother.update!(status: :processing)
      travel_to tz.parse('2026-11-04 20:00') do # quarta, fora da janela
        expect(described_class.run!(mother)).to eq(0)
        expect(mother.reload.stats['last_skip']).to eq('fora do horário')
      end
      travel_to tz.parse('2026-11-07 10:00') do # sábado
        expect(described_class.run!(mother)).to eq(0)
        expect(mother.reload.stats['last_skip']).to eq('fim de semana')
      end
      travel_to tz.parse('2026-11-04 10:00') do # última hora da janela: a cota é o resto do dia
        expect(described_class.run!(mother)).to eq(3)
        expect(sent_to.to_h).to eq(ana.id => insta.id, bia.id => google.id, caio.id => google.id)
        expect(sent_to.map(&:first)).not_to include(quieto.id, marcado.id)
        filhas = described_class.children(mother, day: Date.new(2026, 11, 4)).order(:inbox_id)
        expect(filhas.map { |c| [c.inbox_id, c.campaign_contacts.count, c.status] })
          .to eq([[google.id, 2, 'completed'], [insta.id, 1, 'completed']])
        expect(filhas.first.name).to eq('Reativação de fim de ano · 04/11 · GOOGLE')
        stats = mother.reload.stats
        expect(stats['sent']).to eq(3)
        expect(stats['slices']).to eq('nao_fechou' => 2, 'orcamento' => 1)
        expect(stats.dig('days', '2026-11-04', 'frentes')).to eq('padrao' => 2, 'catarata' => 1)
        expect(mother.recipients.count).to eq(3)

        # segunda rodada da mesma hora: ninguém sobrou → plano concluído
        expect(described_class.run!(mother)).to eq(0)
        expect(mother.reload).to be_completed
        expect(sent_to.size).to eq(3)
      end
    end

    it 'respeita o teto do dia e o teto por caixa' do
      6.times { |i| card!("P#{i}", "+551199999100#{i}", nao_fechou) }
      so_uma = [raw['slices'].first.merge('share' => 100)]
      teto = raw.merge('daily_cap' => 4, 'inbox_daily_cap' => 3, 'hour_from' => 9, 'hour_to' => 10, 'slices' => so_uma)
      mother = described_class.upsert!(account, teto, user: admin)
      mother.update!(status: :processing)
      fake_sender
      travel_to tz.parse('2026-11-04 09:30') do
        expect(described_class.run!(mother)).to eq(3) # teto da caixa GOOGLE (3) segura antes do teto do dia (4)
        expect(mother.reload.stats['warnings']).to include('teto da caixa GOOGLE atingido')
        expect(described_class.run!(mother)).to eq(0) # a 4ª tenta, mas a caixa já deu 3 hoje
        expect(mother.reload.stats['warnings']).to include('teto da caixa GOOGLE atingido')
        expect(mother.stats['sent']).to eq(3)
      end
    end
  end

  describe 'API', type: :request do
    let(:base) { "/api/v1/accounts/#{account.id}/crm/reactivation_plan" }

    it 'salva, simula, ativa (só com 100%), roda agora e pausa' do
      card!('Ana', '+5511999990001', nao_fechou)
      fake_sender
      put base, params: { plan: raw }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['exists']).to be(true)
      expect(body['status']).to eq('draft')
      expect(body['config']['slices'].size).to eq(2)
      expect(body['inboxes'].pluck('name')).to contain_exactly('GOOGLE', 'INSTAGRAM')
      expect(body['simulation']['total_pool']).to eq(1)

      post "#{base}/simulate", params: { plan: raw.merge('daily_cap' => 50) }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['slices'].first['per_day']).to eq(35)

      put base, params: { plan: raw.merge('slices' => [raw['slices'].first]) }, headers: admin.create_new_auth_token, as: :json
      post "#{base}/activate", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      put base, params: { plan: raw }, headers: admin.create_new_auth_token, as: :json
      post "#{base}/activate", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['status']).to eq('processing')

      post "#{base}/run_now", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['sent_now']).to eq(1)
      expect(response.parsed_body['sent_today']).to eq(1)

      post "#{base}/pause", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['status']).to eq('paused')

      agent = create(:user, account: account, role: :agent)
      get base, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      post "#{base}/activate", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
