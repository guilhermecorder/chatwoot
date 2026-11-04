require 'rails_helper'

# 🧪 item 383 (03/11): SEGMENTAÇÃO DA BASE + TESTES DE MENSAGEM — a peneira
# regra a regra, a reserva com sorteio equilibrado entre as mensagens, o
# isolamento (quem está num segmento não entra em outro), o envio no ritmo
# e os resultados por mensagem.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Crm::SegmentBuilder do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:templates) do
    [{ 'name' => 'msg_a', 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'MARKETING' },
     { 'name' => 'msg_b', 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'MARKETING' }]
  end
  let!(:google) { whatsapp_inbox('GOOGLE') }
  let(:pipeline) { account.crm_pipelines.create!(name: 'CEVICO | Jornada do Paciente') }
  let(:orcamento) { pipeline.stages.create!(name: 'Envio de Orçamento', position: 1) }
  let(:variants) do
    %w[msg_a msg_b].map.with_index do |name, i|
      { 'label' => "Mensagem #{%w[A B][i]}",
        'template_params' => { 'name' => name, 'language' => 'pt_BR', 'category' => 'MARKETING', 'processed_params' => { 'body' => { '1' => '{{contact.name}}' } } },
        'message_preview' => "Oi {{1}} (#{name})" }
    end
  end
  let(:source) { { 'stage_ids' => [orcamento.id], 'size' => 4, 'min_age_days' => 0, 'quiet_hours' => 0, 'exclude_campaign_days' => 30 } }
  let(:pace) { { 'per_hour' => 120, 'step_minutes' => 5, 'default_inbox_id' => google.id, 'daily_cap' => 1000 } }
  let(:sent_to) { [] }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/segments" }

  def whatsapp_inbox(name)
    inbox = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
    inbox.update!(name: name)
    inbox.channel.update_columns(message_templates: templates) # rubocop:disable Rails/SkipsModelValidations
    inbox
  end

  def card!(name, phone)
    contact = create(:contact, account: account, name: name, phone_number: phone, created_at: 10.days.ago)
    Crm::Contact.create!(pipeline: pipeline, stage: orcamento, contact: contact)
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

  it 'peneira regra a regra, reserva com sorteio equilibrado e isola quem já está em segmento' do
    six = (1..6).map { |i| card!("Pessoa #{i}", "+551199999000#{i}") }
    # consulta marcada fica de fora
    Task.create!(account: account, creator: admin, title: 'Consulta', task_type: 'consulta', due_at: 2.days.from_now, contact: six[5])

    preview = described_class.preview(account, described_class.normalize_source(source))
    expect(preview[:base_total]).to eq(6)
    expect(preview[:eligible]).to eq(5)
    expect(preview[:will_take]).to eq(4)
    expect(preview[:removed].find { |r| r[:key] == 'consulta_marcada' }[:count]).to eq(1)

    seg = described_class.reserve!(account, name: 'Teste 1', kind: 'teste', source: source, variants: variants, pace: pace, user: admin)
    expect(seg.members.count).to eq(4)
    expect(seg.members.group(:variant_key).count).to eq('A' => 2, 'B' => 2)
    expect(seg.stats['by_variant']).to eq('A' => 2, 'B' => 2)

    # os 4 reservados não entram no próximo segmento; sobra 1 (o 6º tem consulta)
    again = described_class.preview(account, described_class.normalize_source(source))
    expect(again[:removed].find { |r| r[:key] == 'em_segmento' }[:count]).to eq(4)
    expect(again[:eligible]).to eq(1)

    # campanha comum e plano de reativação não encostam em quem está num segmento
    campaign = account.crm_campaigns.new(inbox: google, name: 'comum', template_params: { 'name' => 'msg_a' },
                                         audience: { 'include_stage_ids' => [orcamento.id] })
    expect(campaign.resolve_audience.count).to eq(2) # 6 cards − 4 em segmento
    mother = Crm::ReactivationPlan.upsert!(account, { 'default_inbox_id' => google.id, 'quiet_hours' => 0, 'min_age_days' => 0,
                                                      'slices' => [{ 'key' => 'orc', 'stage_id' => orcamento.id, 'share' => 100, 'templates' => { 'padrao' => variants.first } }] },
                                           user: admin)
    expect(Crm::ReactivationPlan.pool(mother, Crm::ReactivationPlan.config(mother), mother.audience['reactivation_plan']['slices'].first).count).to eq(1)

    # lote de escala leva uma mensagem só
    expect { described_class.reserve!(account, name: 'x', kind: 'escala', source: source, variants: variants, pace: pace) }
      .to raise_error(ArgumentError, /UMA mensagem/)
  end

  it 'manda no ritmo (leva = por hora × minutos/60), registra por pessoa e campanha-filha, e conclui quando acabar' do
    fake_sender
    (1..4).each { |i| card!("Pessoa #{i}", "+551199999000#{i}") }
    seg = described_class.reserve!(account, name: 'Teste 2', kind: 'teste', source: source, variants: variants, pace: pace, user: admin)
    cfg = Crm::SegmentSender.pace(seg)
    expect(Crm::SegmentSender.step_size(cfg)).to eq(10) # 120/h de 5 em 5 min
    expect(Crm::SegmentSender.step_size(Crm::SegmentSender.normalize_pace('per_hour' => 150, 'step_minutes' => 60))).to eq(150)

    expect(Crm::SegmentSender.tick!(seg, force: true)).to eq(0) # ainda não iniciou
    seg.update!(status: 'enviando', started_at: Time.current)

    # consulta marcada DEPOIS da reserva: pulada na hora do envio, com motivo
    marcada = seg.members.order(:id).first.contact
    Task.create!(account: account, creator: admin, title: 'Consulta', task_type: 'consulta', due_at: 2.days.from_now, contact: marcada)

    # leva de 3 = a marcada (pulada) + 2 enviadas; sobra 1 na fila
    expect(Crm::SegmentSender.tick!(seg, force: true, limit: 3)).to eq(2)
    expect(seg.members.find_by(contact_id: marcada.id).status).to eq('pulado')
    expect(seg.reload.stats['warnings'].join).to include('consulta marcada')
    expect(sent_to.size).to eq(2)
    expect(seg.members.sent.count).to eq(2)
    expect(seg.members.reserved.count).to eq(1)
    expect(seg.reload.status).to eq('enviando')
    expect(seg.stats['sent']).to eq(2)
    children = account.crm_campaigns.where("audience ->> 'segment_id' = ?", seg.id.to_s)
    expect(children.pluck(:name)).to all(include('Teste 2'))
    expect(Crm::CampaignContact.where(campaign_id: children.select(:id)).count).to eq(2)

    # relógio da leva: sem force, a segunda leva só sai depois de step_minutes
    expect(Crm::SegmentSender.tick!(seg, now: Time.current + 1.minute)).to eq(0)

    # a última pessoa fica sem nome e o modelo não rende → pulada, e o segmento conclui mesmo assim
    allow(Crm::SendTemplateService).to receive(:new) do |source:, contact:| # rubocop:disable Lint/UnusedBlockArgument
      instance_double(Crm::SendTemplateService, message: nil, perform: nil)
    end
    expect(Crm::SegmentSender.tick!(seg, force: true)).to eq(0)
    expect(seg.members.where(status: 'pulado').count).to eq(2)
    expect(seg.members.where(status: 'enviando')).to be_empty
    expect(seg.reload.status).to eq('concluido')

    results = Crm::SegmentResults.for(seg)
    expect(results[:totals][:sent]).to eq(2)
    expect(results[:variants].map { |v| v[:key] }).to eq(%w[A B])
    expect(results[:winner]).to be_nil # amostra pequena
    expect(results[:timeline][:days].size).to eq(1)
  end

  it 'API: base, prévia, criar, iniciar, leva agora, resultados e escalar a vencedora', type: :request do
    fake_sender
    (1..6).each { |i| card!("Pessoa #{i}", "+551199999000#{i}") }

    get "#{base}/base", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['stages'].first['name']).to eq('Envio de Orçamento')
    expect(body['inboxes'].first['templates'].size).to eq(2)

    post "#{base}/preview", params: { source: source }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['will_take']).to eq(4)

    post base, params: { name: 'Teste API', kind: 'teste', source: source, variants: variants, pace: pace },
               headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    id = response.parsed_body['id']
    expect(response.parsed_body['reserved']).to eq(4)

    post "#{base}/#{id}/start", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['status']).to eq('enviando')

    # a leva manual é enfileirada no robô (fora da requisição) e sai com a trava
    post "#{base}/#{id}/tick_now", params: { limit: 4 }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['queued']).to eq(4)
    expect(Crm::SegmentDripJob).to have_been_enqueued.with(id, force: true, limit: 4)
    Crm::SegmentDripJob.perform_now(id, force: true, limit: 4)
    expect(Crm::Segment.find(id).status).to eq('concluido')

    get "#{base}/#{id}/results", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['totals']['sent']).to eq(4)

    # escalar a mensagem B para quem sobrou (2 pessoas)
    post "#{base}/#{id}/escalar", params: { variant: 'B', size: 0 }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['kind']).to eq('escala')
    expect(response.parsed_body['reserved']).to eq(2)
    expect(response.parsed_body['variants'].map { |v| v['template'] }).to eq(['msg_b'])

    get "#{base}/dashboard", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['totals']['segments']).to eq(2)
    expect(response.parsed_body['totals']['sent']).to eq(4)
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
