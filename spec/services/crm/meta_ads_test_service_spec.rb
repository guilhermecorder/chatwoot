require 'rails_helper'

# 📣 item 345 (14/10): o botão "Testar envio" testa o site e cada caixa do
# WhatsApp (conjunto da conta), sempre com código de teste e telefone de
# mentira — nunca conta nas campanhas
RSpec.describe Crm::MetaAdsTestService do
  let(:account) { create(:account) }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:site_endpoint) { %r{graph\.facebook\.com/v19\.0/PIXEL1/events} }
  let!(:setting) do
    CrmSetting.create!(account: account, meta_ads_config: { 'pixel_id' => 'PIXEL1', 'access_token' => 'token' })
  end

  def whatsapp_inbox(waba_id, name)
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                        validate_provider_config: false)
    # a fábrica grava a conta dela por cima: troca direto na coluna
    config = channel.provider_config.merge('business_account_id' => waba_id, 'api_key' => "key_#{waba_id}")
    channel.update_columns(provider_config: config) # rubocop:disable Rails/SkipsModelValidations
    channel.inbox.update!(name: name)
    channel.inbox
  end

  def sent_body(target)
    body = nil
    expect(WebMock).to(have_requested(:post, target).with { |req| body = JSON.parse(req.body) })
    body
  end

  before do
    stub_request(:post, site_endpoint).to_return(status: 200, body: { events_received: 1 }.to_json, headers: json)
  end

  it 'sends a valid TEST event to the site, even in production, with a hashed fake phone' do
    allow(Rails.env).to receive(:production?).and_return(true)

    result = described_class.new(account: account).call

    expect(result).to include(success: true, test_event_code: 'TEST_CEVICO')
    expect(result[:results]).to eq([{ target: 'Site (pixel PIXEL1)', dataset_id: 'PIXEL1', ok: true, error: nil, token: 'sistema' }])
    body = sent_body(site_endpoint)
    expect(body['test_event_code']).to eq('TEST_CEVICO')
    expect(body['data'].first['user_data']['ph']).to eq([Digest::SHA256.hexdigest('5511999999999')])
  end

  it 'uses the configured test code when there is one' do
    setting.update!(meta_ads_config: setting.meta_ads_config.merge('test_event_code' => 'TEST999'))

    described_class.new(account: account).call

    expect(sent_body(site_endpoint)['test_event_code']).to eq('TEST999')
  end

  it 'tests each WhatsApp inbox on its own dataset and skips the partner inbox' do
    instagram = whatsapp_inbox('WABA_A', 'INSTAGRAM')
    partner = whatsapp_inbox('WABA_P', 'Oftalmofácil')
    setting.update!(agenda_config: { 'oftalmofacil' => { 'partner_inbox_ids' => [partner.id] } })
    stub_request(:get, %r{v19\.0/WABA_A/dataset}).to_return(status: 200, body: { data: [] }.to_json, headers: json)
    stub_request(:post, %r{v19\.0/WABA_A/dataset}).to_return(status: 200, body: { id: 'DS_A' }.to_json, headers: json)
    stub_request(:post, %r{v19\.0/DS_A/events}).to_return(status: 200, body: { events_received: 1 }.to_json, headers: json)

    result = described_class.new(account: account).call

    expect(result[:success]).to be(true)
    expect(result[:results].pluck(:target)).to eq(['Site (pixel PIXEL1)', "Caixa #{instagram.id} INSTAGRAM"])
    expect(result[:results].last).to include(dataset_id: 'DS_A', ok: true, token: 'sistema')
    event = sent_body(%r{v19\.0/DS_A/events})['data'].first
    expect(event).to include('action_source' => 'business_messaging', 'messaging_channel' => 'whatsapp', 'event_name' => 'LeadSubmitted')
    expect(event['user_data']).to include('whatsapp_business_account_id' => 'WABA_A')
    expect(WebMock).not_to have_requested(:any, /WABA_P/)
    expect(setting.reload.meta_ads_config['waba_datasets']).to eq('WABA_A' => 'DS_A')
  end

  it 'reports what Meta answered for each target, and which token worked' do
    inbox = whatsapp_inbox('WABA_A', 'INSTAGRAM')
    setting.update!(meta_ads_config: setting.meta_ads_config.merge('waba_datasets' => { 'WABA_A' => 'DS_A' }))
    stub_request(:post, site_endpoint).to_return(
      status: 400, headers: json,
      body: { error: { message: 'Invalid parameter', code: 100, error_subcode: 2_804_132,
                       error_user_msg: 'Não há uma conta do WhatsApp Business vinculada' } }.to_json
    )
    stub_request(:post, %r{v19\.0/DS_A/events}).with(query: hash_including('access_token' => 'token'))
                                               .to_return(status: 403, headers: json,
                                                          body: { error: { message: 'No permission', code: 200 } }.to_json)
    stub_request(:post, %r{v19\.0/DS_A/events}).with(query: hash_including('access_token' => 'key_WABA_A'))
                                               .to_return(status: 200, body: { events_received: 1 }.to_json, headers: json)

    result = described_class.new(account: account).call

    expect(result[:success]).to be(false)
    expect(result[:results].first).to include(
      ok: false, error: 'Invalid parameter — Não há uma conta do WhatsApp Business vinculada (subcode 2804132)'
    )
    expect(result[:results].last).to include(target: "Caixa #{inbox.id} INSTAGRAM", ok: true, token: 'caixa')
    expect(result.to_s).not_to include('key_WABA_A')
  end

  it 'reports the inbox when its dataset cannot be found nor created' do
    whatsapp_inbox('WABA_A', 'INSTAGRAM')
    stub_request(:get, %r{v19\.0/WABA_A/dataset}).to_return(status: 403, headers: json,
                                                            body: { error: { message: 'Permission denied', code: 10 } }.to_json)

    result = described_class.new(account: account).call

    expect(result[:results].last).to include(ok: false, dataset_id: nil)
    expect(result[:results].last[:error]).to include('Permission denied')
  end

  it 'answers clearly when Meta is not configured' do
    setting.update!(meta_ads_config: {})

    expect(described_class.new(account: account).call).to include(success: false, error: 'Meta Ads não configurado')
  end
end
