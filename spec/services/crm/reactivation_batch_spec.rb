require 'rails_helper'

# 🎛️ item 382 (03/11): CONTROLE DO LOTE — ver quem recebe antes de mandar,
# aprovar cada lote, modo de teste com a lista de números, fila projetada dia a
# dia (pulando ou não o fim de semana) e o registro do que saiu.
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe Crm::ReactivationBatch do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:templates) { [{ 'name' => 'reativa', 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'MARKETING' }] }
  let!(:google) { whatsapp_inbox('GOOGLE') }
  let!(:insta) { whatsapp_inbox('INSTAGRAM') }
  let(:pipeline) { account.crm_pipelines.create!(name: 'CEVICO | Jornada do Paciente') }
  let(:nao_fechou) { pipeline.stages.create!(name: 'Não Fechou Ainda', position: 1) }
  let(:tpl) do
    { 'template_params' => { 'name' => 'reativa', 'language' => 'pt_BR', 'category' => 'MARKETING',
                             'processed_params' => { 'body' => { '1' => '{{contact.name}}' } } },
      'message_preview' => 'Oi {{1}}' }
  end
  let(:raw) do
    { 'daily_cap' => 10, 'hour_from' => 9, 'hour_to' => 11, 'inbox_daily_cap' => 100, 'default_inbox_id' => google.id,
      'quiet_hours' => 0, 'min_age_days' => 0, 'approval' => 'manual',
      'slices' => [{ 'key' => 'nao_fechou', 'stage_id' => nao_fechou.id, 'share' => 100, 'templates' => { 'padrao' => tpl } }] }
  end
  let(:sent_to) { [] }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/reactivation_plan" }

  def whatsapp_inbox(name)
    inbox = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
    inbox.update!(name: name)
    inbox.channel.update_columns(message_templates: templates) # rubocop:disable Rails/SkipsModelValidations
    inbox
  end

  def card!(name, phone, created_at: 10.days.ago)
    contact = create(:contact, account: account, name: name, phone_number: phone, created_at: created_at)
    card = Crm::Contact.create!(pipeline: pipeline, stage: nao_fechou, contact: contact)
    card.update_columns(stage_moved_at: created_at) # rubocop:disable Rails/SkipsModelValidations -- o callback põe "agora"
    contact
  end

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

  it 'aprovação manual: a hora só prepara o lote, a prévia mostra pessoa por pessoa e o Aprovar manda só quem foi escolhido', type: :request do
    ana = card!('Ana', '+5511999990001', created_at: 1.day.ago)
    bia = card!('Bia', '+5511999990002', created_at: 2.days.ago)
    create(:conversation, account: account, inbox: insta, contact: ana, created_at: 5.days.ago)
    mother = Crm::ReactivationPlan.upsert!(account, raw, user: admin)
    mother.update!(status: :processing)
    fake_sender

    travel_to tz.parse('2026-11-04 10:00') do
      expect(Crm::ReactivationPlan.run!(mother)).to eq(0)
      pending = mother.reload.stats['pending_batch']
      expect(mother.stats['last_skip']).to eq('aguardando aprovação do lote')
      expect(pending['rows'].map { |r| [r['name'], r['inbox_name'], r['stage_name'], r['template'], r['frente']] })
        .to eq([['Ana', 'INSTAGRAM', 'Não Fechou Ainda', 'reativa', 'padrao'], ['Bia', 'GOOGLE', 'Não Fechou Ainda', 'reativa', 'padrao']])
      expect(sent_to).to be_empty

      get "#{base}/preview_next", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['approval']).to eq('manual')
      expect(body['rows'].pluck('contact_id')).to eq([ana.id, bia.id])
      expect(body['rows'].first).to include('phone' => '+5511999990001', 'origin_inbox' => 'INSTAGRAM', 'fallback' => false)

      # 📤 24/11: o clique só põe o lote na fila; quem manda é o robô (com a trava do plano)
      post "#{base}/send_batch", params: { contact_ids: [bia.id] }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('sent_now' => 0, 'queued' => 1)
      expect(response.parsed_body['queued_batch']).to include('size' => 1)
      expect(sent_to).to be_empty

      # segundo clique (outra aba) com o lote ainda saindo: recusado, ninguém recebe duas vezes
      post "#{base}/send_batch", params: { contact_ids: [bia.id] }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      perform_enqueued_jobs
      expect(sent_to).to eq([[bia.id, google.id]])
      expect(mother.reload.stats['pending_batch']).to be_nil
      expect(mother.stats['queued_batch']).to be_nil

      get "#{base}/batches", headers: admin.create_new_auth_token, as: :json
      lotes = response.parsed_body['batches']
      expect(lotes.size).to eq(1)
      expect(lotes.first).to include('inbox_name' => 'GOOGLE', 'test' => false, 'total' => 1, 'day' => '2026-11-04')
      expect(lotes.first['rows'].first).to include('name' => 'Bia', 'phone' => '+5511999990002', 'status' => 'sent')
    end
  end

  it 'modo de teste manda só para os números da lista, pode repetir, e o lote fica marcado como TESTE' do
    card!('Ana', '+5511999990001')
    bia = card!('Bia', '+5511999990002')
    teste = raw.merge('approval' => 'auto', 'test_mode' => true, 'test_phones' => ['(11) 99999-0002'])
    mother = Crm::ReactivationPlan.upsert!(account, teste, user: admin)
    mother.update!(status: :processing)
    fake_sender
    travel_to tz.parse('2026-11-04 10:00') do
      expect(Crm::ReactivationPlan.run!(mother)).to eq(1)
      expect(Crm::ReactivationPlan.run!(mother)).to eq(1) # pode repetir
      expect(sent_to.map(&:first)).to eq([bia.id, bia.id])
      filha = Crm::ReactivationPlan.children(mother).first
      expect(filha.name).to include('TESTE')
      expect(filha.audience['test']).to eq('true')
      expect(mother.reload).to be_processing
    end
  end

  # 📱 pedido dele (24/11): "a mensagem seja enviada pelo número que a pessoa já tem conversa"
  describe 'por qual número cada pessoa recebe' do
    let!(:confirmacao) do
      inbox = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
      inbox.update!(name: 'CONFIRMAÇÃO') # este número NÃO tem o modelo de reativação
      inbox
    end

    def talk!(contact, inbox, at:, type: :incoming)
      conversation = Conversation.find_by(inbox: inbox, contact: contact) ||
                     create(:conversation, account: account, inbox: inbox, contact: contact, created_at: at)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: type, content: 'oi', created_at: at)
      conversation.update_columns(last_activity_at: at) # rubocop:disable Rails/SkipsModelValidations
    end

    def rows_now(mother)
      travel_to(tz.parse('2026-11-04 10:00')) { described_class.plan(mother)[:rows] }
    end

    it 'vale o número em que a pessoa falou por último, não o da primeira conversa' do
      ana = card!('Ana', '+5511999990001')
      talk!(ana, google, at: 60.days.ago)   # chegou pelo GOOGLE
      talk!(ana, insta, at: 5.days.ago)     # hoje conversa pelo INSTAGRAM
      mother = Crm::ReactivationPlan.upsert!(account, raw, user: admin)

      expect(rows_now(mother).first).to include(inbox_name: 'INSTAGRAM', origin_inbox: 'INSTAGRAM', fallback: false)
    end

    it 'se o modelo não está aprovado onde ela falou por último, vai por outro número em que ela já conversou (não pelo padrão)' do
      ana = card!('Ana', '+5511999990001')
      talk!(ana, insta, at: 30.days.ago)
      talk!(ana, confirmacao, at: 2.days.ago) # confirmou a consulta por aqui
      mother = Crm::ReactivationPlan.upsert!(account, raw, user: admin) # padrão = GOOGLE

      expect(rows_now(mother).first).to include(inbox_name: 'INSTAGRAM', origin_inbox: 'CONFIRMAÇÃO', fallback: true)
    end

    it 'quem não tem conversa nenhuma recebe pelo número padrão' do
      card!('Ana', '+5511999990001')
      mother = Crm::ReactivationPlan.upsert!(account, raw, user: admin)

      expect(rows_now(mother).first).to include(inbox_name: 'GOOGLE', origin_inbox: 'sem conversa', fallback: false)
    end
  end

  it 'a mesma pessoa com card em duas colunas escolhidas (um por funil) entra uma vez só' do
    ana = card!('Ana', '+5511999990001')
    outro_funil = account.crm_pipelines.create!(name: 'Outro funil')
    outra_coluna = outro_funil.stages.create!(name: 'Orçamento', position: 1)
    Crm::Contact.create!(pipeline: outro_funil, stage: outra_coluna, contact: ana).update_columns(stage_moved_at: 5.days.ago) # rubocop:disable Rails/SkipsModelValidations
    duas = raw.merge('slices' => [raw['slices'].first.merge('share' => 50),
                                  { 'key' => 'orcamento', 'stage_id' => outra_coluna.id, 'share' => 50, 'templates' => { 'padrao' => tpl } }])
    mother = Crm::ReactivationPlan.upsert!(account, duas, user: admin)

    travel_to tz.parse('2026-11-04 10:00') do
      expect(described_class.plan(mother)[:rows].pluck(:contact_id)).to eq([ana.id])
    end
  end

  it 'quem está com a equipe da indicação cirúrgica (pausa indicacao) fica de fora do lote' do
    ana = card!('Ana', '+5511999990001')
    bia = card!('Bia', '+5511999990002')
    conversa = create(:conversation, account: account, inbox: google, contact: ana, created_at: 9.days.ago)
    conversa.update!(additional_attributes: { Crm::ResponderAgentJob::STATE_KEY => {
                       'paused' => true, 'reason' => 'indicacao', 'at' => 3.days.ago.iso8601, 'until' => 27.days.from_now.iso8601
                     } })
    mother = Crm::ReactivationPlan.upsert!(account, raw, user: admin)

    travel_to tz.parse('2026-11-04 10:00') do
      expect(described_class.plan(mother)[:rows].pluck(:contact_id)).to eq([bia.id])
    end
  end

  it 'o teto por número soma todos os lotes do dia, inclusive o de teste' do
    ana = card!('Ana', '+5511999990001')
    bia = card!('Bia', '+5511999990002')
    mother = Crm::ReactivationPlan.upsert!(account, raw.merge('approval' => 'auto', 'daily_cap' => 1), user: admin)
    mother.update!(status: :processing)
    fake_sender
    travel_to tz.parse('2026-11-04 10:00') do
      expect(Crm::ReactivationPlan.run!(mother)).to eq(1) # lote real: 1 pessoa pelo GOOGLE
      Crm::ReactivationPlan.upsert!(account, raw.merge('approval' => 'auto', 'daily_cap' => 5, 'test_mode' => true,
                                                       'test_phones' => [bia.phone_number]), user: admin)
      expect(Crm::ReactivationPlan.run!(mother.reload)).to eq(1) # lote de teste, filha nova no mesmo número
      expect(Crm::ReactivationPlan.sent_today_by_inbox(mother, Date.new(2026, 11, 4))).to eq(google.id => 2)
      expect([ana.id, bia.id]).to include(*sent_to.map(&:first))
    end
  end

  it 'não ativa plano com campo do modelo em branco', type: :request do
    vazio = tpl.deep_merge('template_params' => { 'processed_params' => { 'body' => { '1' => ' ' } } })
    Crm::ReactivationPlan.upsert!(account, raw.merge('slices' => [raw['slices'].first.merge('templates' => { 'padrao' => vazio })]), user: admin)

    post "#{base}/activate", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.to_s).to include('Preencha todos os campos')
  end

  it 'a fila projeta os lotes dia a dia, pulando (ou não) o fim de semana, com as pessoas dos primeiros dias' do
    5.times { |i| card!("P#{i}", "+551199999100#{i}", created_at: (i + 1).days.ago) }
    mother = Crm::ReactivationPlan.upsert!(account, raw.merge('daily_cap' => 2), user: admin)
    travel_to tz.parse('2026-11-06 08:00') do # sexta
      fila = described_class.queue(mother)
      expect(fila[:total]).to eq(5)
      expect(fila[:days].map { |d| [d[:lote], d[:date], d[:total]] })
        .to eq([[1, '2026-11-06', 2], [2, '2026-11-09', 2], [3, '2026-11-10', 1]])
      expect(fila[:days].first[:rows].map { |r| r[:name] }).to eq(%w[P0 P1]) # mais recentes primeiro
      expect(fila[:days].first[:rows].first).to include(inbox_name: 'GOOGLE', template: 'reativa')

      mother = Crm::ReactivationPlan.upsert!(account, raw.merge('daily_cap' => 2, 'weekdays_only' => false), user: admin)
      fila = described_class.queue(mother, detail_days: 0)
      expect(fila[:days].map { |d| d[:date] }).to eq(%w[2026-11-06 2026-11-07 2026-11-08])
      expect(fila[:days].first).not_to have_key(:rows)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
