require 'rails_helper'

# 🚫 Rodada 3 da auditoria (#45): destinatário da campanha cuja mensagem a
# Meta recusou vira delivery_status 'failed' e sai de 'sent' nos números —
# no fim da rodada e numa varredura 10 min depois (a Meta avisa por webhook).
RSpec.describe Crm::CampaignRunJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false).inbox
  end
  let(:label) { account.labels.create!(title: 'reativar') }
  let!(:ana) { create(:contact, account: account, name: 'Ana', phone_number: '+5511999990001').tap { |c| c.update!(label_list: ['reativar']) } }
  let!(:bia) { create(:contact, account: account, name: 'Bia', phone_number: '+5511999990002').tap { |c| c.update!(label_list: ['reativar']) } }
  let(:tpl) do
    { 'name' => 'reativacao', 'language' => 'pt_BR', 'category' => 'MARKETING', 'processed_params' => { 'body' => { '1' => 'oi' } } }
  end
  let(:campaign) do
    Crm::Campaign.create!(account: account, inbox: inbox, name: 'Reativação', template_params: tpl, message_preview: 'Olá {{1}}',
                          audience: { 'include_label_ids' => [label.id] }, status: :processing, apply_label: 'reativacao_enviada')
  end

  before { stub_const('Crm::CampaignRunJob::THROTTLE_SECONDS', 0) }

  def recipient(contact)
    campaign.campaign_contacts.find_by(contact: contact)
  end

  def campaign_message(contact)
    Message.where(conversation_id: recipient(contact).conversation_id).where("additional_attributes ->> 'cevico_auto' = ?", 'Campaign').last
  end

  it 'rodada normal: todos "sent", números certos e varredura agendada para 10 min depois', :aggregate_failures do
    described_class.perform_now(campaign.id)

    campaign.reload
    expect(campaign).to be_completed
    expect(campaign.stats).to include('sent' => 2, 'failed' => 0)
    expect(campaign.campaign_contacts.pluck(:delivery_status)).to eq(%w[sent sent])
    expect(described_class).to have_been_enqueued.with(campaign.id, 'sweep')
  end

  it 'a Meta recusou a da Bia: a varredura marca o destinatário como failed e corrige os números (uma vez só)', :aggregate_failures do
    described_class.perform_now(campaign.id)
    campaign_message(bia).update!(status: :failed, external_error: '131026: Message undeliverable')

    described_class.perform_now(campaign.id, 'sweep')

    expect(recipient(bia).delivery_status).to eq('failed')
    expect(recipient(ana).delivery_status).to eq('sent')
    campaign.reload
    expect(campaign.stats).to include('sent' => 1, 'failed' => 1)
    expect(campaign.stats['meta_refused']).to eq([{ 'name' => 'Bia', 'error' => '131026: Message undeliverable' }])
    expect(campaign).to be_completed
    # a etiqueta da campanha quer dizer "recebeu": sai de quem a Meta recusou
    expect(bia.reload.label_list).not_to include('reativacao_enviada')
    expect(ana.reload.label_list).to include('reativacao_enviada')

    # segunda varredura: nada muda (quem já virou failed não conta de novo)
    described_class.perform_now(campaign.id, 'sweep')
    expect(campaign.reload.stats).to include('sent' => 1, 'failed' => 1)
    expect(campaign.stats['meta_refused'].size).to eq(1)
  end

  it 'recusa que chega ainda durante a rodada já sai certa no fim dela', :aggregate_failures do
    allow(Crm::SendTemplateService).to receive(:new).and_wrap_original do |m, **kw|
      svc = m.call(**kw)
      allow(svc).to receive(:perform).and_wrap_original do |perform|
        conversation = perform.call
        svc.message.update!(status: :failed, external_error: '132012: Parameter format does not match') if kw[:contact] == ana
        conversation
      end
      svc
    end

    described_class.perform_now(campaign.id)

    expect(recipient(ana).delivery_status).to eq('failed')
    expect(recipient(bia).delivery_status).to eq('sent')
    expect(campaign.reload.stats).to include('sent' => 1, 'failed' => 1)
  end
end
