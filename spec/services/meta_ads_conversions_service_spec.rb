require 'rails_helper'

# Item 313: evento de anúncio de WhatsApp vai com a conta do WhatsApp e o nome
# da lista da Meta; lead da página leva o clique (fbc) e o navegador (fbp)
RSpec.describe MetaAdsConversionsService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999990000') }
  let(:endpoint) { %r{graph\.facebook\.com/v19\.0/123456/events} }

  before do
    CrmSetting.create!(account: account, meta_ads_config: { 'pixel_id' => '123456', 'access_token' => 'token' })
    stub_request(:post, endpoint).to_return(status: 200, body: { events_received: 1 }.to_json,
                                            headers: { 'Content-Type' => 'application/json' })
  end

  def sent_event
    event = nil
    expect(WebMock).to(have_requested(:post, endpoint).with { |req| event = JSON.parse(req.body)['data'].first })
    event
  end

  def whatsapp_conversation(waba_id)
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                        validate_provider_config: false,
                                        provider_config: { 'api_key' => 'k', 'phone_number_id' => 'p', 'business_account_id' => waba_id })
    create(:conversation, account: account, inbox: channel.inbox, contact: contact)
  end

  context 'when the lead came from a click-to-WhatsApp ad' do
    before { contact.update!(additional_attributes: { 'meta_ads' => { 'ctwa_clid' => 'CLIQUE123' } }) }

    it 'sends as a messaging event with the WhatsApp account id and the Meta name' do
      # a fábrica de teste grava a conta do WhatsApp dela por cima
      waba_id = whatsapp_conversation('WABA999').inbox.channel.provider_config['business_account_id']

      result = described_class.new(account: account, event_name: 'Lead', contact: contact).call

      expect(result).to include(success: true, messaging: true, event_name: 'LeadSubmitted')
      expect(sent_event).to include('event_name' => 'LeadSubmitted', 'action_source' => 'business_messaging',
                                    'messaging_channel' => 'whatsapp')
      expect(sent_event['user_data']).to include('ctwa_clid' => 'CLIQUE123', 'whatsapp_business_account_id' => waba_id)
    end

    it 'falls back to the common path when the WhatsApp account id is unknown' do
      result = described_class.new(account: account, event_name: 'Lead', contact: contact).call

      expect(result).to include(success: true, messaging: false, event_name: 'Lead')
      expect(sent_event['action_source']).to eq('system_generated')
      expect(sent_event['user_data']).not_to include('ctwa_clid')
      expect(sent_event['user_data']['ph']).to be_present
    end
  end

  context 'when the lead came from a Meta ad through the page' do
    it 'sends the browser cookies kept in the Protocol' do
      contact.update!(additional_attributes: { 'page_ads' => { 'fbc' => 'fb.1.1700000000001.IwAR123', 'fbp' => 'fb.1.17.99' } })

      described_class.new(account: account, event_name: 'Schedule', contact: contact).call

      expect(sent_event['event_name']).to eq('Schedule')
      expect(sent_event['user_data']).to include('fbc' => 'fb.1.1700000000001.IwAR123', 'fbp' => 'fb.1.17.99')
    end

    it 'builds fbc from the fbclid and the click time when the cookie is missing' do
      contact.update!(additional_attributes: { 'page_ads' => { 'fbclid' => 'IwAR_xYz', 'clicked_at' => '2026-10-01T12:00:00Z' } })

      described_class.new(account: account, event_name: 'Lead', contact: contact).call

      expect(sent_event['user_data']['fbc']).to eq("fb.1.#{Time.utc(2026, 10, 1, 12).to_i * 1000}.IwAR_xYz")
    end
  end

  it 'sends value and currency inside custom_data' do
    described_class.new(account: account, event_name: 'Purchase', contact: contact,
                        custom_data: { value: 5700.0, currency: 'BRL' }).call

    expect(sent_event['custom_data']).to include('value' => 5700.0, 'currency' => 'BRL')
  end
end
