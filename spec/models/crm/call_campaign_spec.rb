require 'rails_helper'

RSpec.describe Crm::CallCampaign do
  let(:account) { create(:account) }
  let(:label) { create(:label, account: account, title: 'reativar') }

  it 'start! enfileira o público sem duplicar e marca em andamento' do
    with_phone = create(:contact, account: account, phone_number: '+5511999990001')
    without_phone = create(:contact, account: account, phone_number: nil)
    [with_phone, without_phone].each { |c| c.update!(label_list: [label.title]) }
    campaign = described_class.create!(account: account, name: 'Teste', audience: { 'include_label_ids' => [label.id] })

    campaign.start!
    campaign.start!

    expect(campaign).to be_processing
    expect(campaign.started_at).to be_present
    expect(campaign.campaign_contacts.count).to eq(1)
    expect(campaign.campaign_contacts.first.contact).to eq(with_phone)
    expect(campaign.progress).to include(total: 1, queued: 1, calling: 0, done: 0)
  end

  it 'finish_if_done! conclui quando a fila esvazia e traduz os resultados' do
    contact = create(:contact, account: account, phone_number: '+5511999990002')
    campaign = described_class.create!(account: account, name: 'Teste', status: :processing)
    campaign.campaign_contacts.create!(contact: contact, status: 'done', outcome: 'agendou')

    campaign.finish_if_done!

    expect(campaign.reload).to be_completed
    expect(campaign.outcomes).to eq({ 'agendou consulta' => 1 })
  end
end
