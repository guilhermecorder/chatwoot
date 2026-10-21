require 'rails_helper'

# 🛡️ Rodada 6 da auditoria — "Rede de segurança" (#255): a campanha manda
# mensagem modelo para a base inteira (custo real por balão desde 01/10). A
# correção de julho tem 3 proteções e nenhuma tinha teste de regressão:
#   1. trava por campanha (Redis::LockManager): o Sidekiq reiniciado no deploy
#      reenfileira o job — a 2ª instância não pode recomeçar o envio;
#   2. quem já está em campaign_contacts (CampaignContact) NUNCA recebe de novo;
#   3. envio que falhou não é registrado como recebido (a retomada manda).
# E a cerca: paciente de parceiro nunca entra no público. (Quem pode criar e
# disparar — 403 para o atendente — está em campaigns_access_spec.rb.)
RSpec.describe Crm::CampaignRunJob do
  let(:account) { create(:account) }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false).inbox
  end
  let(:label) { account.labels.create!(title: 'reativar') }
  let(:campaign) do
    Crm::Campaign.create!(account: account, inbox: inbox, name: 'Reativação', template_params: { 'name' => 'x' },
                          audience: { 'include_label_ids' => [label.id] }, status: :processing, apply_label: 'reativacao_enviada')
  end
  let!(:ana) { lead('Ana', '+5511999990001') }
  let!(:bia) { lead('Bia', '+5511999990002') }
  let!(:caio) { lead('Caio', '+5511999990003') }
  let(:sent_to) { [] }
  let(:lock_key) { "CRM_CAMPAIGN_RUN_LOCK::#{campaign.id}" }

  before { stub_const('Crm::CampaignRunJob::THROTTLE_SECONDS', 0) }

  def lead(name, phone, **attrs)
    create(:contact, account: account, name: name, phone_number: phone, **attrs).tap { |c| c.update!(label_list: ['reativar']) }
  end

  # envio falso: anota quem recebeu; o bloco decide o resultado (conversa, nil ou erro)
  def fake_sender
    allow(Crm::SendTemplateService).to receive(:new) do |source:, contact:|
      sender = instance_double(Crm::SendTemplateService)
      allow(sender).to receive(:perform) do
        sent_to << contact.id
        block_given? ? yield(contact) : create(:conversation, account: account, inbox: inbox, contact: contact)
      end
      expect(source).to eq(campaign)
      sender
    end
  end

  def recipients
    campaign.campaign_contacts.pluck(:contact_id)
  end

  it 'retomada com 1 que já recebeu: só os outros 2 recebem (CampaignContact é a fonte da verdade)', :aggregate_failures do
    conversa_da_ana = create(:conversation, account: account, inbox: inbox, contact: ana)
    Crm::CampaignContact.create!(campaign: campaign, contact: ana, conversation: conversa_da_ana, sent_at: 1.hour.ago)
    fake_sender

    described_class.perform_now(campaign.id)

    expect(sent_to).to contain_exactly(bia.id, caio.id)
    expect(Crm::SendTemplateService).to have_received(:new).twice
    expect(recipients).to contain_exactly(ana.id, bia.id, caio.id)
    campaign.reload
    expect(campaign).to be_completed
    expect(campaign.stats).to include('total' => 3, 'sent' => 3, 'skipped' => 1, 'failed' => 0)
  end

  it 'trava ocupada (outra instância rodando): não envia nada e não solta a trava da outra', :aggregate_failures do
    fake_sender
    lock_manager = Redis::LockManager.new
    expect(lock_manager.lock(lock_key, 1.minute)).to be_truthy

    begin
      described_class.perform_now(campaign.id)

      expect(sent_to).to be_empty
      expect(recipients).to be_empty
      expect(campaign.reload).to be_processing
      # a trava continua sendo da instância que está enviando
      expect(lock_manager.locked?(lock_key)).to be(true)
    ensure
      lock_manager.unlock(lock_key)
    end

    # trava livre: agora sim envia (e devolve a trava no fim)
    described_class.perform_now(campaign.id)
    expect(sent_to).to contain_exactly(ana.id, bia.id, caio.id)
    expect(lock_manager.locked?(lock_key)).to be(false)
  end

  it 'envio que falhou (erro ou pulado) não é registrado como recebido; a retomada manda para ele', :aggregate_failures do
    fake_sender do |contact|
      raise StandardError, 'Meta fora do ar' if contact == bia
      next nil if contact == caio # SendTemplateService devolve nil = não saiu

      create(:conversation, account: account, inbox: inbox, contact: contact)
    end

    described_class.perform_now(campaign.id)

    expect(recipients).to eq([ana.id])
    expect(campaign.reload.stats).to include('sent' => 1, 'failed' => 1, 'skipped' => 1)
    # a etiqueta da campanha quer dizer "recebeu": só a Ana ganha
    expect(ana.reload.label_list).to include('reativacao_enviada')
    expect(bia.reload.label_list).not_to include('reativacao_enviada')
    expect(caio.reload.label_list).not_to include('reativacao_enviada')

    # "Enviar agora" de novo: só quem não recebeu
    sent_to.clear
    fake_sender
    campaign.update!(status: :processing)
    described_class.perform_now(campaign.id)

    expect(sent_to).to contain_exactly(bia.id, caio.id)
    expect(recipients).to contain_exactly(ana.id, bia.id, caio.id)
  end

  it 'paciente de parceiro (Oftalmofácil) fica fora do público mesmo com a etiqueta da campanha', :aggregate_failures do
    Rails.cache.clear
    parceiro = lead('Paciente Parceiro', '+5511999990009', additional_attributes: { 'parceiro' => 'CLINICA VISAO NORTE' })
    fake_sender

    described_class.perform_now(campaign.id)

    expect(sent_to).to contain_exactly(ana.id, bia.id, caio.id)
    expect(sent_to).not_to include(parceiro.id)
    expect(campaign.reload.stats['total']).to eq(3)
  end

  it 'campanha que não está "em envio" (rascunho/pausada) não manda nada' do
    fake_sender
    campaign.update!(status: :paused)

    described_class.perform_now(campaign.id)

    expect(sent_to).to be_empty
  end
end
