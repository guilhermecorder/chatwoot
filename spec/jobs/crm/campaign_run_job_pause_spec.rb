require 'rails_helper'

# ⏸ Auditoria 12/10 — Rodada 3 (#415): a equipe clicou "Pausar" no meio do
# envio → o job para no próximo contato, guarda quem já recebeu e NÃO marca
# a campanha como concluída. "Enviar agora" depois retoma sem repetir ninguém.
RSpec.describe Crm::CampaignRunJob do
  let(:account) { create(:account) }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false).inbox
  end
  let(:label) { account.labels.create!(title: 'reativar') }
  let(:campaign) do
    Crm::Campaign.create!(account: account, inbox: inbox, name: 'Reativação', template_params: { 'name' => 'x' },
                          audience: { 'include_label_ids' => [label.id] }, status: :processing)
  end

  before do
    (1..3).each do |i|
      create(:contact, account: account, name: "Lead #{i}", phone_number: "+551199999000#{i}")
        .tap { |c| c.update!(label_list: ['reativar']) }
    end
  end

  # o "clique em Pausar" chegando pelo banco enquanto a 1ª mensagem sai
  def pause_from_screen!
    Crm::Campaign.where(id: campaign.id).update_all(status: Crm::Campaign.statuses[:paused]) # rubocop:disable Rails/SkipsModelValidations
  end

  def fake_sender(&on_send)
    sender = instance_double(Crm::SendTemplateService)
    allow(sender).to receive(:perform) do
      on_send&.call
      create(:conversation, account: account, inbox: inbox)
    end
    allow(Crm::SendTemplateService).to receive(:new).and_return(sender)
    sender
  end

  it 'pausada depois do 1º envio: para, registra quem recebeu e fica "pausada"', :aggregate_failures do
    fake_sender { pause_from_screen! }
    job = described_class.new
    allow(job).to receive(:sleep)

    job.perform(campaign.id)

    campaign.reload
    expect(campaign).to be_paused
    expect(campaign.campaign_contacts.count).to eq(1)
    expect(campaign.stats).to include('sent' => 1, 'total' => 3)
    expect(campaign.finished_at).to be_nil
  end

  it 'retomar (Enviar agora) continua de onde parou sem repetir quem já recebeu', :aggregate_failures do
    fake_sender { pause_from_screen! }
    job = described_class.new
    allow(job).to receive(:sleep)
    job.perform(campaign.id)
    first_recipient = campaign.campaign_contacts.first.contact_id

    sender = fake_sender
    campaign.reload.update!(status: :processing)
    job2 = described_class.new
    allow(job2).to receive(:sleep)
    job2.perform(campaign.id)

    campaign.reload
    expect(campaign).to be_completed
    expect(campaign.campaign_contacts.count).to eq(3)
    expect(campaign.campaign_contacts.where(contact_id: first_recipient).count).to eq(1)
    expect(sender).to have_received(:perform).twice
    expect(campaign.stats).to include('sent' => 3)
  end

  it 'sem pausa, manda para todos e conclui' do
    fake_sender
    job = described_class.new
    allow(job).to receive(:sleep)

    job.perform(campaign.id)

    expect(campaign.reload).to be_completed
    expect(campaign.campaign_contacts.count).to eq(3)
  end
end
