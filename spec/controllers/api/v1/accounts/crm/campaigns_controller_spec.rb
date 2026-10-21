require 'rails_helper'

# 🕐🚦 Auditoria 12/10 — Rodada 3 "Mensagem certa" (CONTRATO-0, #411, #415):
# · a hora digitada em "Publicar em" é de SÃO PAULO (antes era gravada como
#   UTC e a campanha saía 3 h antes); data inválida ou no passado é recusada;
# · "Enviar agora" numa campanha AGENDADA só sai com a confirmação explícita
#   de ignorar o horário; numa campanha em envio não re-enfileira o job;
# · pausar (em envio) / cancelar agendamento; pausada não entra em `due`;
# · a prévia do público devolve o custo estimado (tabela do Gasto do WhatsApp).
RSpec.describe 'CEVICO campanhas WhatsApp — agendar no fuso de SP, confirmar e pausar', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false).inbox
  end
  let(:label) { account.labels.create!(title: 'reativar') }
  let(:campaign) do
    Crm::Campaign.create!(account: account, inbox: inbox, name: 'Reativação', template_params: { 'name' => 'x' },
                          audience: { 'include_label_ids' => [label.id] })
  end
  let(:base) { "/api/v1/accounts/#{account.id}/crm/campaigns" }

  before { Current.reset }

  def headers_for(user)
    user.create_new_auth_token
  end

  describe 'POST schedule (CONTRATO-0 / #411)' do
    it 'grava "amanhã 08:00" como 08:00 de São Paulo e devolve o rótulo no fuso da clínica', :aggregate_failures do
      when_local = (tz.now + 1.day).change(hour: 8, min: 0)

      post "#{base}/#{campaign.id}/schedule",
           params: { scheduled_at: when_local.strftime('%Y-%m-%dT%H:%M') }, headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:success)
      campaign.reload
      expect(campaign).to be_scheduled
      expect(campaign.scheduled_at.in_time_zone(tz).strftime('%H:%M')).to eq('08:00')
      # antes do conserto ficava 08:00 UTC = 05:00 em SP (a campanha saía de madrugada)
      expect(campaign.scheduled_at.utc.hour).to eq(11)
      expect(response.parsed_body['scheduled_at_label']).to eq(when_local.strftime('%d/%m/%Y 08:00'))
    end

    it 'data no passado ou inválida é recusada e a campanha continua rascunho', :aggregate_failures do
      post "#{base}/#{campaign.id}/schedule", params: { scheduled_at: '2020-01-01T10:00' }, headers: headers_for(admin), as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      post "#{base}/#{campaign.id}/schedule", params: { scheduled_at: '31/02 sei lá' }, headers: headers_for(admin), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('São Paulo')

      expect(campaign.reload).to be_draft
      expect(campaign.scheduled_at).to be_nil
    end
  end

  describe 'POST send_now (#415)' do
    it 'campanha agendada NÃO sai sem a confirmação de ignorar o horário', :aggregate_failures do
      campaign.update!(status: :scheduled, scheduled_at: tz.now + 1.day)

      expect do
        post "#{base}/#{campaign.id}/send_now", headers: headers_for(admin), as: :json
      end.not_to have_enqueued_job(Crm::CampaignRunJob)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('agendada para')
      expect(campaign.reload).to be_scheduled
    end

    it 'campanha agendada sai agora quando a pessoa confirma ignorar o agendamento', :aggregate_failures do
      campaign.update!(status: :scheduled, scheduled_at: tz.now + 1.day)

      expect do
        post "#{base}/#{campaign.id}/send_now", params: { ignore_schedule: 1 }, headers: headers_for(admin), as: :json
      end.to have_enqueued_job(Crm::CampaignRunJob).with(campaign.id)
      expect(response).to have_http_status(:success)
      expect(campaign.reload).to be_processing
    end

    it 'segundo clique numa campanha em envio não re-enfileira o job', :aggregate_failures do
      campaign.update!(status: :processing)

      expect do
        post "#{base}/#{campaign.id}/send_now", headers: headers_for(admin), as: :json
      end.not_to have_enqueued_job(Crm::CampaignRunJob)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('pause primeiro')
    end

    it 'campanha pausada retoma (o job pula quem já recebeu)' do
      campaign.update!(status: :paused)

      expect do
        post "#{base}/#{campaign.id}/send_now", headers: headers_for(admin), as: :json
      end.to have_enqueued_job(Crm::CampaignRunJob).with(campaign.id)
      expect(campaign.reload).to be_processing
    end
  end

  describe 'POST pause (#415)' do
    it 'pausa a campanha em envio e cancela a agendada; pausada não vence no cron', :aggregate_failures do
      campaign.update!(status: :processing)
      post "#{base}/#{campaign.id}/pause", headers: headers_for(admin), as: :json
      expect(response).to have_http_status(:success)
      expect(campaign.reload).to be_paused

      campaign.update!(status: :scheduled, scheduled_at: 1.minute.ago)
      expect(Crm::Campaign.due).to include(campaign)
      post "#{base}/#{campaign.id}/pause", headers: headers_for(admin), as: :json
      expect(campaign.reload).to be_paused
      expect(Crm::Campaign.due).not_to include(campaign)
    end

    it 'rascunho e concluída não têm o que pausar', :aggregate_failures do
      post "#{base}/#{campaign.id}/pause", headers: headers_for(admin), as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      campaign.update!(status: :completed)
      post "#{base}/#{campaign.id}/pause", headers: headers_for(admin), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'quem só VÊ campanhas não pausa (porta do catálogo)' do
      campaign.update!(status: :processing)
      post "#{base}/#{campaign.id}/pause", headers: headers_for(agent), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(campaign.reload).to be_processing
    end
  end

  describe 'POST preview_audience (#415 — custo estimado)' do
    before do
      create(:contact, account: account, phone_number: '+5511999990001').tap { |c| c.update!(label_list: ['reativar']) }
      create(:contact, account: account, phone_number: '+5511999990002').tap { |c| c.update!(label_list: ['reativar']) }
    end

    it 'devolve contagem e custo = tarifa de marketing da tabela × contatos', :aggregate_failures do
      post "#{base}/preview_audience", params: { audience: { include_label_ids: [label.id] } },
                                       headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['count']).to eq(2)
      expect(body['rate_category']).to eq('marketing')
      expect(body['rate']).to eq(Crm::WhatsappPricing::DEFAULTS['BRL']['marketing'])
      expect(body['estimated_cost']).to eq((Crm::WhatsappPricing::DEFAULTS['BRL']['marketing'] * 2).round(2))
      expect(body['currency']).to eq('BRL')
    end

    it 'modelo de utilidade usa a tarifa de utilidade; categoria desconhecida cai em marketing', :aggregate_failures do
      post "#{base}/preview_audience", params: { audience: { include_label_ids: [label.id] }, category: 'utility' },
                                       headers: headers_for(admin), as: :json
      expect(response.parsed_body['rate']).to eq(Crm::WhatsappPricing::DEFAULTS['BRL']['utility'])

      post "#{base}/preview_audience", params: { audience: { include_label_ids: [label.id] }, category: 'qualquer' },
                                       headers: headers_for(admin), as: :json
      expect(response.parsed_body['rate_category']).to eq('marketing')
    end
  end
end
