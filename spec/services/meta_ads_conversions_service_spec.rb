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

  def sent_event(target = endpoint)
    event = nil
    expect(WebMock).to(have_requested(:post, target).with { |req| event = JSON.parse(req.body)['data'].first })
    event
  end

  def save_datasets(map)
    setting = CrmSetting.find_by(account: account)
    setting.update!(meta_ads_config: setting.meta_ads_config.merge('waba_datasets' => map))
  end

  def meta_json(status, body)
    { status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def meta_error(code, message)
    { error: { message: message, type: 'OAuthException', code: code } }
  end

  def whatsapp_conversation(waba_id)
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                        validate_provider_config: false,
                                        provider_config: { 'api_key' => 'k', 'phone_number_id' => 'p', 'business_account_id' => waba_id })
    create(:conversation, account: account, inbox: channel.inbox, contact: contact)
  end

  context 'when the lead came from a click-to-WhatsApp ad' do
    before { contact.update!(additional_attributes: { 'meta_ads' => { 'ctwa_clid' => 'CLIQUE123' } }) }

    # 📣 item 345: o evento de mensagem vai para o conjunto da conta do WhatsApp
    context 'when the WhatsApp account already has its dataset saved' do
      let(:dataset_endpoint) { %r{graph\.facebook\.com/v19\.0/DS777/events} }

      before do
        stub_request(:post, dataset_endpoint).to_return(status: 200, body: { events_received: 1 }.to_json,
                                                        headers: { 'Content-Type' => 'application/json' })
      end

      it 'sends as a messaging event to the WhatsApp account dataset, not to the site pixel' do
        waba_id = whatsapp_conversation('WABA999').inbox.channel.provider_config['business_account_id']
        save_datasets(waba_id => 'DS777')

        result = described_class.new(account: account, event_name: 'Lead', contact: contact).call

        expect(result).to include(success: true, messaging: true, event_name: 'LeadSubmitted', dataset_id: 'DS777',
                                  token: 'sistema', fallback: false)
        expect(WebMock).not_to have_requested(:post, endpoint)
        event = sent_event(dataset_endpoint)
        expect(event).to include('event_name' => 'LeadSubmitted', 'action_source' => 'business_messaging',
                                 'messaging_channel' => 'whatsapp')
        expect(event['user_data']).to include('ctwa_clid' => 'CLIQUE123', 'whatsapp_business_account_id' => waba_id)
      end

      # 🔗 item 345b: clique e conta do WhatsApp da MESMA conversa (subcode 2804117)
      it 'uses the click stamped on the ad conversation, paired with that conversation account' do
        ad_conv = whatsapp_conversation('WABA999')
        ad_conv.update!(additional_attributes: { 'meta_ads' => { 'ctwa_clid' => 'CLIQUE_DA_CONVERSA' } })
        waba_id = ad_conv.inbox.channel.provider_config['business_account_id']
        save_datasets(waba_id => 'DS777')

        described_class.new(account: account, event_name: 'Lead', contact: contact).call

        expect(sent_event(dataset_endpoint)['user_data']).to include('ctwa_clid' => 'CLIQUE_DA_CONVERSA',
                                                                     'whatsapp_business_account_id' => waba_id)
      end

      it 'retries once with the inbox token when Meta refuses the system token' do
        waba_id = whatsapp_conversation('WABA999').inbox.channel.provider_config['business_account_id']
        save_datasets(waba_id => 'DS777')
        stub_request(:post, dataset_endpoint).with(query: hash_including('access_token' => 'token'))
                                             .to_return(status: 403, body: meta_error(200, 'Permissions error').to_json,
                                                        headers: { 'Content-Type' => 'application/json' })

        result = described_class.new(account: account, event_name: 'Schedule', contact: contact).call

        expect(result).to include(success: true, token: 'caixa', event_name: 'QualifiedLead')
        expect(WebMock).to have_requested(:post, dataset_endpoint).with(query: hash_including('access_token' => 'test_key'))
        expect(result.to_s).not_to include('test_key')
      end

      it 'remembers which token worked for the WhatsApp account' do
        allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
        waba_id = whatsapp_conversation('WABA999').inbox.channel.provider_config['business_account_id']
        save_datasets(waba_id => 'DS777')
        stub_request(:post, dataset_endpoint).with(query: hash_including('access_token' => 'token'))
                                             .to_return(status: 400, body: meta_error(190, 'Invalid OAuth access token').to_json,
                                                        headers: { 'Content-Type' => 'application/json' })

        2.times { described_class.new(account: account, event_name: 'Lead', contact: contact).call }

        expect(WebMock).to have_requested(:post, dataset_endpoint).with(query: hash_including('access_token' => 'token')).once
        expect(WebMock).to have_requested(:post, dataset_endpoint).with(query: hash_including('access_token' => 'test_key')).twice
      end

      it 'does not retry with the other token when Meta refuses the event itself' do
        waba_id = whatsapp_conversation('WABA999').inbox.channel.provider_config['business_account_id']
        save_datasets(waba_id => 'DS777')
        stub_request(:post, dataset_endpoint).to_return(
          status: 400, headers: { 'Content-Type' => 'application/json' },
          body: { error: { message: 'Invalid parameter', code: 100, error_subcode: 2_804_050,
                           error_user_msg: 'O parâmetro ctwa_clid é inválido.' } }.to_json
        )

        result = described_class.new(account: account, event_name: 'Lead', contact: contact).call

        expect(result).to include(success: false, error: 'Invalid parameter — O parâmetro ctwa_clid é inválido. (subcode 2804050)')
        expect(WebMock).to have_requested(:post, dataset_endpoint).once
      end
    end

    it 'finds the dataset of the WhatsApp account, creating it when Meta has none, and saves it' do
      waba_id = whatsapp_conversation('WABA999').inbox.channel.provider_config['business_account_id']
      dataset_url = %r{graph\.facebook\.com/v19\.0/#{waba_id}/dataset}
      stub_request(:get, dataset_url).to_return(meta_json(200, { data: [] }))
      stub_request(:post, dataset_url).to_return(meta_json(200, { id: 'DS_NOVO' }))
      stub_request(:post, %r{v19\.0/DS_NOVO/events}).to_return(meta_json(200, { events_received: 1 }))

      result = described_class.new(account: account, event_name: 'Lead', contact: contact).call

      expect(result).to include(success: true, messaging: true, dataset_id: 'DS_NOVO')
      expect(WebMock).to have_requested(:get, dataset_url).with(query: hash_including('access_token' => 'test_key'))
      expect(WebMock).to have_requested(:post, dataset_url)
      expect(CrmSetting.find_by(account: account).meta_ads_config['waba_datasets']).to eq(waba_id => 'DS_NOVO')
    end

    it 'uses the dataset Meta already has without creating another one' do
      waba_id = whatsapp_conversation('WABA999').inbox.channel.provider_config['business_account_id']
      dataset_url = %r{graph\.facebook\.com/v19\.0/#{waba_id}/dataset}
      stub_request(:get, dataset_url).to_return(meta_json(200, { data: [{ id: 'DS_VELHO' }] }))
      stub_request(:post, %r{v19\.0/DS_VELHO/events}).to_return(meta_json(200, { events_received: 1 }))

      result = described_class.new(account: account, event_name: 'Lead', contact: contact).call

      expect(result).to include(success: true, dataset_id: 'DS_VELHO')
      expect(WebMock).not_to have_requested(:post, dataset_url)
    end

    it 'falls back to the site pixel as a common event when the dataset cannot be resolved' do
      waba_id = whatsapp_conversation('WABA999').inbox.channel.provider_config['business_account_id']
      stub_request(:get, %r{v19\.0/#{waba_id}/dataset}).to_return(meta_json(403, meta_error(10, 'Permission denied')))

      result = described_class.new(account: account, event_name: 'Schedule', contact: contact).call

      expect(result).to include(success: true, messaging: false, fallback: true, event_name: 'Schedule')
      expect(result[:fallback_reason]).to include('Permission denied')
      expect(sent_event['action_source']).to eq('system_generated')
      expect(sent_event['user_data']).not_to include('ctwa_clid', 'whatsapp_business_account_id')
      expect(sent_event).not_to include('messaging_channel')
      expect(sent_event['user_data']['ph']).to be_present
    end

    it 'never uses the WhatsApp account of a partner inbox (Oftalmofácil)' do
      conversation = whatsapp_conversation('WABA999')
      CrmSetting.find_by(account: account).update!(agenda_config: { 'oftalmofacil' => { 'partner_inbox_ids' => [conversation.inbox_id] } })

      result = described_class.new(account: account, event_name: 'Lead', contact: contact).call

      expect(result).to include(success: true, messaging: false, event_name: 'Lead')
      expect(WebMock).not_to have_requested(:any, /dataset/)
      expect(sent_event['user_data']).not_to include('ctwa_clid')
    end

    it 'falls back to the common path when the WhatsApp account id is unknown' do
      result = described_class.new(account: account, event_name: 'Lead', contact: contact).call

      expect(result).to include(success: true, messaging: false, event_name: 'Lead')
      expect(sent_event['action_source']).to eq('system_generated')
      expect(sent_event['user_data']).not_to include('ctwa_clid')
      expect(sent_event['user_data']['ph']).to be_present
    end
  end

  it 'shows the error_user_msg of Meta instead of only "Invalid parameter"' do
    stub_request(:post, endpoint).to_return(
      status: 400, headers: { 'Content-Type' => 'application/json' },
      body: { error: { message: 'Invalid parameter', code: 100, error_user_msg: 'Dados do cliente vazios' } }.to_json
    )

    result = described_class.new(account: account, event_name: 'Lead', contact: contact).call

    expect(result).to include(success: false, error: 'Invalid parameter — Dados do cliente vazios')
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
