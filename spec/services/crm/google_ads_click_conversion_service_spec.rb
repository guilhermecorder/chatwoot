require 'rails_helper'

# 🎯 item 371: conversão direto no Google Ads — gclid, aprimorada, valor, procedimento
RSpec.describe Crm::GoogleAdsClickConversionService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511987654321', email: 'Maria@Email.com') }
  let(:actions) do
    { 'agendou_consulta' => 'customers/1234567890/conversionActions/11', 'fechou_cirurgia' => 'customers/1234567890/conversionActions/12' }
  end
  let!(:settings) do
    CrmSetting.create!(account: account, google_ads_config: {
                         'developer_token' => 'dev', 'customer_id' => '1234567890', 'oauth_client_id' => 'a',
                         'oauth_client_secret' => 'b', 'oauth_refresh_token' => 'c', 'conversions_via' => 'ads_api',
                         'ads_conversion_actions' => actions,
                         'ads_custom_variables' => { 'procedimento' => 'customers/1234567890/conversionCustomVariables/5' }
                       })
  end
  let(:endpoint) { 'https://googleads.googleapis.com/v26/customers/1234567890:uploadClickConversions' }

  before do
    Rails.cache.clear
    stub_request(:post, 'https://oauth2.googleapis.com/token').to_return(status: 200, body: { access_token: 'tok' }.to_json,
                                                                         headers: { 'Content-Type' => 'application/json' })
    stub_request(:post, endpoint).to_return(status: 200, body: { results: [{}] }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def sent_conversion
    body = nil
    expect(WebMock).to(have_requested(:post, endpoint).with { |req| body = JSON.parse(req.body) })
    body['conversions'].first
  end

  it 'está ligado só com a chave conversions_via = ads_api e o acesso completo' do
    expect(described_class.enabled?(account)).to be(true)
    settings.update!(google_ads_config: settings.google_ads_config.merge('conversions_via' => 'ga4'))
    expect(described_class.enabled?(account)).to be(false)
  end

  it 'com gclid no Protocolo, vai amarrada ao clique com valor, moeda e procedimento' do
    contact.update!(additional_attributes: { 'page_ads' => { 'gclid' => 'Cj0KCQ-abc', 'slug' => 'refrativa' } })

    result = described_class.new(account: account, event_name: 'agendou_consulta', contact: contact, value: 350,
                                 procedure: 'refrativa', page: 'refrativa', order_id: 'crm_1_2_2026-10-27',
                                 occurred_at: Time.zone.parse('2026-10-27 14:05:00 -03:00')).call

    expect(result).to include(success: true, tied: true, mode: 'gclid')
    c = sent_conversion
    expect(c).to include('gclid' => 'Cj0KCQ-abc', 'conversionAction' => actions['agendou_consulta'],
                         'conversionDateTime' => '2026-10-27 14:05:00-03:00', 'conversionValue' => 350.0, 'currencyCode' => 'BRL',
                         'orderId' => 'crm_1_2_2026-10-27')
    expect(c['customVariables']).to eq([{ 'conversionCustomVariable' => 'customers/1234567890/conversionCustomVariables/5', 'value' => 'refrativa' }])
    expect(c).not_to have_key('userIdentifiers') # com o clique, o telefone não precisa sair
    cfg = settings.reload.google_ads_config
    expect(cfg.dig('sent_log', Date.current.iso8601, 'agendou_consulta')).to eq(1)
    expect(cfg.dig('tied_log', Date.current.iso8601, 'agendou_consulta')).to eq(1)
    expect(cfg.dig('ads_sent_log', Date.current.iso8601, 'agendou_consulta')).to eq(1)
  end

  it 'no iPhone vai o gbraid/wbraid' do
    contact.update!(additional_attributes: { 'page_ads' => { 'wbraid' => 'w-123' } })

    result = described_class.new(account: account, event_name: 'agendou_consulta', contact: contact).call

    expect(result).to include(success: true, mode: 'wbraid')
    expect(sent_conversion).to include('wbraid' => 'w-123')
  end

  it 'sem código de clique, cai na conversão APRIMORADA (telefone e e-mail embaralhados)' do
    result = described_class.new(account: account, event_name: 'fechou_cirurgia', contact: contact, value: 5700).call

    expect(result).to include(success: true, tied: false, mode: 'aprimorada')
    c = sent_conversion
    expect(c).not_to have_key('gclid')
    expect(c['userIdentifiers']).to eq([{ 'hashedPhoneNumber' => Digest::SHA256.hexdigest('+5511987654321') },
                                        { 'hashedEmail' => Digest::SHA256.hexdigest('maria@email.com') }])
    expect(c['conversionValue']).to eq(5700.0)
    expect(settings.reload.google_ads_config['tied_log']).to be_nil
  end

  it 'telefone sem o país ganha o +55' do
    contact.update!(email: nil)
    allow(contact).to receive(:phone_number).and_return('11987654321')
    described_class.new(account: account, event_name: 'agendou_consulta', contact: contact).call

    expect(sent_conversion['userIdentifiers']).to eq([{ 'hashedPhoneNumber' => Digest::SHA256.hexdigest('+5511987654321') }])
  end

  it 'evento sem ação preparada não sai e explica' do
    result = described_class.new(account: account, event_name: 'lead_whatsapp', contact: contact).call

    expect(result[:success]).to be(false)
    expect(result[:error]).to include('Preparar no Google Ads')
    expect(WebMock).not_to have_requested(:post, endpoint)
  end

  it 'recusa do Google vira erro legível e fica guardada para a tela' do
    refusal = { errorCode: { conversionUploadError: 'EXPIRED_CLICK' }, message: 'Click expired' }
    stub_request(:post, endpoint).to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                                            body: { partialFailureError: { details: [{ errors: [refusal] }] } }.to_json)
    contact.update!(additional_attributes: { 'page_ads' => { 'gclid' => 'velho' } })

    result = described_class.new(account: account, event_name: 'agendou_consulta', contact: contact).call

    expect(result[:success]).to be(false)
    expect(result[:error]).to include('EXPIRED_CLICK')
    expect(settings.reload.google_ads_config.dig('ads_last_error', 'message')).to include('EXPIRED_CLICK')
    expect(settings.google_ads_config['sent_log']).to be_nil
  end

  it 'envio de teste (validateOnly) não grava no log' do
    result = described_class.new(account: account, event_name: 'agendou_consulta', contact: contact, validate_only: true).call

    expect(result).to include(success: true, validate_only: true)
    expect(WebMock).to(have_requested(:post, endpoint).with { |req| JSON.parse(req.body)['validateOnly'] == true })
    expect(settings.reload.google_ads_config['sent_log']).to be_nil
  end
end
