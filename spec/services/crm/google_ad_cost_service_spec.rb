require 'rails_helper'

# 🩹 item 413: o GA4 só devolve o gasto acompanhado da campanha; o serviço pede
# por campanha e soma (antes pedia a métrica sozinha e o Google recusava).
RSpec.describe Crm::GoogleAdCostService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account, since_date: Date.new(2026, 11, 1), until_date: Date.new(2026, 11, 24)) }
  let(:ok) do
    instance_double(HTTParty::Response, success?: true, parsed_response: { 'rows' => [
                      { 'dimensionValues' => [{ 'value' => '[Search] Refrativa' }], 'metricValues' => [{ 'value' => '1200.504' }] },
                      { 'dimensionValues' => [{ 'value' => '(not set)' }], 'metricValues' => [{ 'value' => '0' }] },
                      { 'dimensionValues' => [{ 'value' => '[PMax] Catarata' }], 'metricValues' => [{ 'value' => '300.25' }] }
                    ] })
  end
  let(:refused) do
    instance_double(HTTParty::Response, success?: false, code: 400,
                                        parsed_response: { 'error' => { 'message' => 'Please add sessionCampaignName' } })
  end

  before do
    CrmSetting.create!(account: account, google_ads_config: { 'ga4_property_id' => '123456', 'service_account_json' => '{"x":1}' })
    allow(service).to receive(:access_token).and_return('token')
  end

  it 'asks for the cost by campaign and adds up every row' do
    allow(HTTParty).to receive(:post).and_return(ok)

    expect(service.call).to eq(configured: true, cost: 1500.75)
    expect(HTTParty).to have_received(:post).once.with(anything, hash_including(body: include('"dimensions":[{"name":"sessionCampaignName"}]')))
  end

  it 'tries the spare campaign dimension when Google refuses the first' do
    allow(HTTParty).to receive(:post).and_return(refused, ok)

    expect(service.call[:cost]).to eq(1500.75)
    expect(HTTParty).to have_received(:post).twice
  end

  it 'hands back the message from Google when both are refused' do
    allow(HTTParty).to receive(:post).and_return(refused)

    expect(service.call).to eq(configured: true, error: 'Please add sessionCampaignName')
  end

  it 'reads an empty report as zero' do
    allow(HTTParty).to receive(:post).and_return(instance_double(HTTParty::Response, success?: true, parsed_response: {}))

    expect(service.call[:cost]).to eq(0.0)
  end
end
