require 'rails_helper'

# 🚫 Rodada 3 da auditoria (#45): lead da Colheitadeira cuja mensagem a Meta
# recusou deixa de contar como enviado — vira pulado com o motivo, sem reenvio
# automático (o número recusado agora seria recusado de novo na hora seguinte).
RSpec.describe Crm::HarvestService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:tpl) do
    { 'name' => 'colheita', 'language' => 'pt_BR', 'category' => 'MARKETING', 'processed_params' => { 'body' => { '1' => '[gancho]' } } }
  end
  let(:harvest_cfg) do
    { 'enabled' => true, 'mode' => 'send', 'inbox_id' => inbox.id, 'template_params' => tpl, 'daily_cap' => 50, 'require_approval' => true }
  end
  let(:ana) { create(:contact, account: account, name: 'Ana', phone_number: '+5511911110001') }
  let(:bia) { create(:contact, account: account, name: 'Bia', phone_number: '+5511911110002') }
  let(:month_key) { described_class.new(account: account).month_key }
  let(:harvest_state) do
    {
      'month_key' => month_key, 'status' => 'approved', 'approved_at' => Time.current.iso8601,
      'selected' => [ana, bia].map do |c|
        { 'contact_id' => c.id, 'name' => c.name, 'phone' => c.phone_number, 'score' => 80, 'hook' => 'seu orçamento ficou guardado',
          'sent_at' => nil, 'conversation_id' => nil, 'skipped' => false }
      end
    }
  end
  let!(:settings) do
    CrmSetting.create!(account: account, ai_config: { 'agents' => { 'harvest' => harvest_cfg }, 'harvest_state' => harvest_state })
  end

  before do
    create(:user, account: account, role: :administrator)
    stub_const('Crm::HarvestService::THROTTLE_SECONDS', 0)
  end

  def lead_of(contact)
    settings.reload.ai_config.dig('harvest_state', 'selected').find { |l| l['contact_id'] == contact.id }
  end

  def harvest_messages
    Message.where("additional_attributes -> 'template_params' ->> 'name' = ?", 'colheita')
  end

  it 'enviado de verdade: o lead guarda o id da mensagem', :aggregate_failures do
    service = described_class.new(account: account)
    expect(service.send_batch!).to include(ok: true, sent: 2)
    expect(lead_of(ana)['message_id']).to eq(harvest_messages.find_by(conversation: account.conversations.find_by(contact: ana)).id)
    expect(lead_of(bia)['sent_at']).to be_present
  end

  it 'a Meta recusou a mensagem da Bia: ela vira pulada com o motivo e não recebe de novo; a Ana continua enviada', :aggregate_failures do
    described_class.new(account: account).send_batch!
    bia_message = harvest_messages.find_by(conversation: account.conversations.find_by(contact: bia))
    bia_message.update!(status: :failed, external_error: '131026: Message undeliverable')

    service = described_class.new(account: account)
    expect { service.send_batch! }.not_to change(harvest_messages, :count)

    expect(lead_of(bia)).to include('sent_at' => nil, 'conversation_id' => nil, 'message_id' => nil, 'skipped' => true,
                                    'skip_reason' => 'a Meta recusou: 131026: Message undeliverable')
    expect(lead_of(ana)['sent_at']).to be_present
    expect(lead_of(ana)['skipped']).to be(false)

    # a etiqueta colheita_AAAA_MM sai junto: a Bia nunca recebeu e pode entrar na próxima colheita
    expect(bia.reload.label_list).not_to include("colheita_#{month_key.tr('-', '_')}")
    expect(ana.reload.label_list).to include("colheita_#{month_key.tr('-', '_')}")

    stats = service.results['stats']
    expect(stats).to include('sent' => 1, 'skipped' => 1, 'pending' => 0)
  end
end
