require 'rails_helper'

# Item 313: o envio ao Google confere o nome do evento e separa a conversão
# AMARRADA à visita do anúncio da conversão solta
RSpec.describe GoogleAdsConversionsService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let!(:settings) do
    CrmSetting.create!(account: account, google_ads_config: { 'measurement_id' => 'G-TESTE12345', 'api_secret' => 'segredo' })
  end
  let(:endpoint) { %r{www\.google-analytics\.com/mp/collect} }

  before { stub_request(:post, endpoint).to_return(status: 204) }

  def sent_body
    body = nil
    expect(WebMock).to(have_requested(:post, endpoint).with { |req| body = JSON.parse(req.body) })
    body
  end

  it 'sends with the real browser identity when the lead came through the page (amarrada)' do
    contact.update!(additional_attributes: { 'page_ads' => { 'ga_client_id' => '111.222', 'ga_session_id' => '333' } })

    result = described_class.new(account: account, event_name: 'agendou_consulta', contact: contact).call

    expect(result).to include(success: true, tied: true, event_name: 'agendou_consulta')
    expect(sent_body['client_id']).to eq('111.222')
    expect(sent_body.dig('events', 0, 'params', 'session_id')).to eq('333')
    cfg = settings.reload.google_ads_config
    expect(cfg.dig('sent_log', Date.current.iso8601, 'agendou_consulta')).to eq(1)
    expect(cfg.dig('tied_log', Date.current.iso8601, 'agendou_consulta')).to eq(1)
  end

  it 'counts as loose (solta) when the contact has no page identity' do
    result = described_class.new(account: account, event_name: 'agendou_consulta', contact: contact).call

    expect(result).to include(success: true, tied: false)
    expect(sent_body['client_id']).to eq("crm.#{contact.id}")
    cfg = settings.reload.google_ads_config
    expect(cfg.dig('sent_log', Date.current.iso8601, 'agendou_consulta')).to eq(1)
    expect(cfg['tied_log']).to be_nil
  end

  it 'fixes a name the GA4 would drop in silence' do
    result = described_class.new(account: account, event_name: 'Refrativa PRK', contact: contact).call

    expect(result[:event_name]).to eq('Refrativa_PRK')
    expect(sent_body.dig('events', 0, 'name')).to eq('Refrativa_PRK')
  end

  it 'does not send when the name cannot be fixed' do
    result = described_class.new(account: account, event_name: '!!!', contact: contact).call

    expect(result[:success]).to be(false)
    expect(WebMock).not_to have_requested(:post, endpoint)
  end

  it 'carries extra params (procedimento, valor) inside the event' do
    described_class.new(account: account, event_name: 'fechou_cirurgia', contact: contact,
                        params: { procedimento: 'refrativa', value: 5700.0, currency: 'BRL' }).call

    expect(sent_body.dig('events', 0, 'params')).to include('procedimento' => 'refrativa', 'value' => 5700.0, 'currency' => 'BRL')
  end
end
