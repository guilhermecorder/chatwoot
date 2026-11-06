require 'rails_helper'

# 🎯 item 371: cliente mínimo da API do Google Ads
RSpec.describe Cevico::GoogleAdsApi do
  let(:config) do
    { 'developer_token' => 'dev-token-123456', 'customer_id' => '123-456-7890', 'login_customer_id' => '999-888-7777',
      'oauth_client_id' => 'cid', 'oauth_client_secret' => 'segredo-muito-secreto', 'oauth_refresh_token' => 'refresh-xyz-123' }
  end
  let(:api) { described_class.new(config) }

  before do
    Rails.cache.clear
    stub_request(:post, 'https://oauth2.googleapis.com/token').to_return(status: 200, body: { access_token: 'tok' }.to_json,
                                                                         headers: { 'Content-Type' => 'application/json' })
  end

  it 'sabe quando está configurado (OAuth ou conta de serviço representando alguém)' do
    expect(api).to be_configured
    expect(api.auth_mode).to eq('oauth')
    expect(described_class.new(config.except('oauth_refresh_token'))).not_to be_configured
    expect(described_class.new(config.except('developer_token'))).not_to be_configured
    expect(described_class.new('developer_token' => 'x', 'customer_id' => '1')).not_to be_configured
  end

  it 'envia a conversão com developer token, conta de login e partialFailure' do
    upload = stub_request(:post, 'https://googleads.googleapis.com/v26/customers/1234567890:uploadClickConversions')
             .to_return(status: 200, body: { results: [{ gclid: 'abc' }], jobId: '77' }.to_json, headers: { 'Content-Type' => 'application/json' })

    result = api.upload_click_conversions([{ gclid: 'abc' }])

    expect(result).to include(ok: true, job_id: '77')
    expect(upload).to have_been_requested
    expect(WebMock).to(have_requested(:post, /uploadClickConversions/).with do |req|
      body = JSON.parse(req.body)
      req.headers['Developer-Token'] == 'dev-token-123456' && req.headers['Login-Customer-Id'] == '9998887777' &&
        req.headers['Authorization'] == 'Bearer tok' && body['partialFailure'] == true && body['validateOnly'] == false
    end)
  end

  it 'traduz a falha parcial do Google (CLICK_NOT_FOUND) em texto' do
    stub_request(:post, /uploadClickConversions/).to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' },
      body: { partialFailureError: { message: 'erro', details: [{ errors: [
        { errorCode: { conversionUploadError: 'CLICK_NOT_FOUND' }, message: 'The click associated with the given identifier could not be found.',
          location: { fieldPathElements: [{ fieldName: 'conversions', index: 0 }, { fieldName: 'gclid' }] } }
      ] }] } }.to_json
    )

    result = api.upload_click_conversions([{ gclid: 'ruim' }])

    expect(result[:ok]).to be(false)
    expect(result[:errors].first).to include('CLICK_NOT_FOUND').and include('conversions.gclid')
  end

  it 'erro de HTTP vira mensagem sem vazar segredo' do
    stub_request(:post, /googleAds:search/).to_return(status: 401, body: { error: { message: 'token dev-token-123456 invalido' } }.to_json,
                                                      headers: { 'Content-Type' => 'application/json' })

    expect(api.search('SELECT x')).to be_nil
    expect(api.last_error).to include('HTTP 401').and include('[segredo]')
    expect(api.last_error).not_to include('dev-token-123456')
  end

  it 'usa a versão da API gravada na configuração' do
    expect(described_class.new(config.merge('api_version' => 'v27')).version).to eq('v27')
    expect(described_class.new(config.merge('api_version' => 'lixo')).version).to eq('v26')
  end
end
