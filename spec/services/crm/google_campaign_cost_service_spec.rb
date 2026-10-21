require 'rails_helper'

RSpec.describe Crm::GoogleCampaignCostService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account, since_date: Date.new(2026, 10, 1), until_date: Date.new(2026, 10, 18)) }
  let(:ok) { instance_double(HTTParty::Response, success?: true, parsed_response: payload) }
  let(:payload) do
    { 'rows' => [
      { 'dimensionValues' => [{ 'value' => '111' }, { 'value' => '[Search] Refrativa' }],
        'metricValues' => [{ 'value' => '1234.567' }, { 'value' => '321' }] },
      { 'dimensionValues' => [{ 'value' => '(not set)' }, { 'value' => '(not set)' }],
        'metricValues' => [{ 'value' => '0' }, { 'value' => '0' }] }
    ] }
  end

  before do
    CrmSetting.create!(account: account, google_ads_config: { 'ga4_property_id' => '123456', 'service_account_json' => '{"x":1}' })
    allow(service).to receive(:access_token).and_return('token')
    allow(Rails.cache).to receive(:read).and_return(nil)
    allow(Rails.cache).to receive(:write)
  end

  it 'reads the cost and clicks of each Google Ads campaign by ID and name' do
    allow(HTTParty).to receive(:post).and_return(ok)

    result = service.call

    expect(result[:campaigns]).to eq([{ id: '111', name: '[Search] Refrativa', cost: 1234.57, clicks: 321 }])
    expect(Rails.cache).to have_received(:write)
  end

  it 'does not keep an error in the cache, so the next opening tries again' do
    denied = instance_double(HTTParty::Response, success?: false, code: 403,
                                                 parsed_response: { 'error' => { 'message' => 'denied' } })
    allow(HTTParty).to receive(:post).and_return(denied)

    result = service.call

    expect(result[:error]).to include('denied')
    expect(Rails.cache).not_to have_received(:write)
  end

  it 'says it is not configured without the GA4 property' do
    CrmSetting.find_by(account: account).update!(google_ads_config: {})

    expect(described_class.new(account: account, since_date: Date.current, until_date: Date.current).call).to eq(configured: false)
  end
end
