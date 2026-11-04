require 'rails_helper'

# 🔁 item 379 (03/11): campanha RECORRENTE — "campanhas periódicas para quem
# está na coluna de orçamento e de novos contatos". A mãe guarda a cadência em
# audience['recurrence']; cada rodada é uma filha (audience['parent_id']).
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe Crm::RecurringCampaign do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false).inbox
  end
  let(:pipeline) { account.crm_pipelines.create!(name: 'CEVICO | Jornada do Paciente') }
  let(:orcamento) { pipeline.stages.create!(name: 'Envio de Orçamento', position: 1) }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:rules) do
    { 'enabled' => true, 'every_days' => 15, 'hour' => 9, 'resend_after_days' => 30, 'quiet_hours' => 24, 'min_age_days' => 3, 'max_per_run' => 2 }
  end
  let(:mother) do
    Crm::Campaign.create!(account: account, inbox: inbox, sender: admin, name: 'Cirurgia este ano', template_params: { 'name' => 'x' },
                          audience: { 'include_stage_ids' => [orcamento.id], 'recurrence' => rules }, status: :draft)
  end

  def lead!(name, phone, created_at: 10.days.ago)
    contact = create(:contact, account: account, name: name, phone_number: phone, created_at: created_at)
    Crm::Contact.create!(pipeline: pipeline, stage: orcamento, contact: contact)
    contact
  end

  describe '.rules' do
    it 'limpa, aplica os padrões e devolve nil quando não é recorrente' do
      expect(described_class.rules({ 'recurrence' => { 'enabled' => '1', 'every_days' => '7', 'hour' => 99, 'max_per_run' => 'abc' } }))
        .to include('enabled' => true, 'every_days' => 7, 'hour' => 9, 'max_per_run' => 150, 'weekdays_only' => true)
      expect(described_class.rules({ 'recurrence' => { 'enabled' => false } })).to be_nil
      expect(described_class.rules({})).to be_nil
      expect(described_class.rules(nil)).to be_nil
    end
  end

  describe '.next_run_at' do
    it 'anda N dias na hora da regra e pula o fim de semana' do
      travel_to tz.parse('2026-11-03 10:00') do # terça
        proxima = described_class.next_run_at({ 'every_days' => 4, 'hour' => 9, 'weekdays_only' => true })
        expect(proxima).to eq(tz.parse('2026-11-09 09:00')) # 07/11 é sábado → segunda 09/11
        primeira = described_class.next_run_at({ 'every_days' => 15, 'hour' => 9, 'weekdays_only' => true }, first: true)
        expect(primeira).to eq(tz.parse('2026-11-04 09:00')) # hoje às 9h já passou → amanhã
        cedo = described_class.next_run_at({ 'every_days' => 15, 'hour' => 14, 'weekdays_only' => true }, first: true)
        expect(cedo).to eq(tz.parse('2026-11-03 14:00'))
      end
    end
  end

  describe 'o público da rodada (Crm::Campaign#resolve_audience)' do
    it 'tira quem recebeu há pouco, quem está conversando, quem tem consulta marcada e quem acabou de chegar; respeita o teto' do
      antiga = lead!('Antiga', '+5511999990001', created_at: 40.days.ago)
      media = lead!('Média', '+5511999990002', created_at: 20.days.ago)
      nova = lead!('Nova', '+5511999990003', created_at: 10.days.ago)
      recem = lead!('Recém-chegada', '+5511999990004', created_at: 1.day.ago)
      recebeu = lead!('Já recebeu', '+5511999990005', created_at: 30.days.ago)
      conversando = lead!('Conversando', '+5511999990006', created_at: 30.days.ago)
      marcada = lead!('Consulta marcada', '+5511999990007', created_at: 30.days.ago)

      rodada_antiga = account.crm_campaigns.create!(inbox: inbox, name: 'rodada', template_params: { 'name' => 'x' },
                                                    audience: mother.audience.merge('parent_id' => mother.id), status: :completed)
      Crm::CampaignContact.create!(campaign: rodada_antiga, contact: recebeu, sent_at: 5.days.ago)
      create(:conversation, account: account, inbox: inbox, contact: conversando, last_activity_at: 2.hours.ago)
      Task.create!(account: account, creator: admin, title: 'Consulta', task_type: 'consulta', due_at: 2.days.from_now, contact: marcada)

      ids = mother.resolve_audience.pluck(:id)
      expect(ids).not_to include(recem.id, recebeu.id, conversando.id, marcada.id)
      # teto 2 → as duas mais antigas primeiro
      expect(ids).to contain_exactly(antiga.id, media.id)
      expect(ids).not_to include(nova.id)
    end

    it 'sem regras o público é o de sempre' do
      pessoa = lead!('Qualquer', '+5511999990009', created_at: 1.hour.ago)
      comum = Crm::Campaign.new(account: account, audience: { 'include_stage_ids' => [orcamento.id] })
      expect(comum.resolve_audience.pluck(:id)).to eq([pessoa.id])
    end
  end

  describe '.spawn!' do
    it 'cria a rodada (filha) em envio, enfileira o job e marca a próxima data na mãe' do
      travel_to tz.parse('2026-11-03 09:01') do
        child = nil
        expect { child = described_class.spawn!(mother) }.to have_enqueued_job(Crm::CampaignRunJob)
        expect(child).to have_attributes(status: 'processing', inbox_id: inbox.id, parent_id: mother.id, recurring?: false)
        expect(child.name).to eq('Cirurgia este ano · rodada 03/11')
        expect(child.recurrence_rules).to include('every_days' => 15)
        mother.reload
        expect(mother).to have_attributes(status: 'scheduled', scheduled_at: tz.parse('2026-11-18 09:00'))
        expect(mother.stats).to include('runs' => 1, 'last_child_id' => child.id)
        expect(described_class.family_ids(child)).to contain_exactly(mother.id, child.id)
      end
    end

    it 'o agendador abre a rodada da mãe vencida em vez de pôr a mãe em envio' do
      mother.update!(status: :scheduled, scheduled_at: 1.minute.ago)
      Crm::SchedulerJob.perform_now
      expect(mother.reload.status).to eq('scheduled')
      expect(mother.scheduled_at).to be > Time.current
      child = account.crm_campaigns.where("audience ->> 'parent_id' = ?", mother.id.to_s).first
      expect(child).to be_processing
    end
  end

  describe 'API', type: :request do
    let(:base) { "/api/v1/accounts/#{account.id}/crm/campaigns" }

    it 'Enviar agora na mãe abre uma rodada; ativar sem data marca a primeira; a prévia desconta as rodadas' do
      post "#{base}/#{mother.id}/send_now", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['recurring']).to be(true)
      expect(body['status']).to eq('scheduled')
      expect(body['child']['parent_id']).to eq(mother.id)
      expect(body['recurrence_label']).to eq('a cada 15 dias às 9h, só dias úteis')

      # a rodada ainda em envio → não atropela
      post "#{base}/#{mother.id}/send_now", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      mother.update!(status: :paused)
      post "#{base}/#{mother.id}/schedule", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('scheduled')

      recebeu = lead!('Já recebeu', '+5511999990005', created_at: 30.days.ago)
      child = Crm::Campaign.find(body['child']['id'])
      Crm::CampaignContact.create!(campaign: child, contact: recebeu, sent_at: Time.current)
      livre = lead!('Livre', '+5511999990008', created_at: 30.days.ago)
      post "#{base}/preview_audience", params: { campaign_id: mother.id, inbox_id: inbox.id, audience: mother.audience },
                                       headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['count']).to eq(1)
      expect(response.parsed_body['sample'].pluck('id')).to eq([livre.id])
      expect(response.parsed_body['inbox_sent_30d']).to eq(1)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
