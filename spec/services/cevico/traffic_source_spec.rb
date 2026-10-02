require 'rails_helper'

# Item 313: códigos de clique e identidade do navegador que amarram a
# conversão ao anúncio
RSpec.describe Cevico::TrafficSource do
  it 'treats gbraid/wbraid (iPhone) as Google Ads, like gclid' do
    expect(described_class.classify({ 'gbraid' => 'abc' })[:source]).to eq('google_ads')
    expect(described_class.classify({ 'wbraid' => 'abc' })[:source]).to eq('google_ads')
  end

  it 'keeps long click ids whole and with the original case' do
    fbclid = "IwZX#{'a' * 300}"
    ids = described_class.click_ids({ 'fbclid' => fbclid, 'gclid' => 'CjwK_AbC', 'gbraid' => '0AAAA' })

    expect(ids['fbclid']).to eq(fbclid)
    expect(ids['gclid']).to eq('CjwK_AbC')
    expect(ids['gbraid']).to eq('0AAAA')
  end

  it 'reads the GA4 and Pixel identity from the browser cookies when the page did not send it' do
    cookies = { '_ga' => 'GA1.1.1234567890.1700000000', '_ga_3EDHXBTSBG' => 'GS2.1.s1747323152$o28$g0$t1747323152$j60$l0$h0',
                '_fbp' => 'fb.1.1700000000000.99887766', '_fbc' => 'fb.1.1700000000001.IwAR123' }
    ids = described_class.click_ids({}, cookies)

    expect(ids['ga_client_id']).to eq('1234567890.1700000000')
    expect(ids['ga_session_id']).to eq('1747323152')
    expect(ids['fbp']).to eq('fb.1.1700000000000.99887766')
    expect(ids['fbc']).to eq('fb.1.1700000000001.IwAR123')
  end

  it 'reads the old session cookie format too, and lets the page value win' do
    cookies = { '_ga' => 'GA1.1.111.222', '_ga_X' => 'GS1.1.1700000555.3.1.1700000600.0.0.0' }

    expect(described_class.click_ids({}, cookies)['ga_session_id']).to eq('1700000555')
    expect(described_class.click_ids({ 'ga_client_id' => '999.888' }, cookies)['ga_client_id']).to eq('999.888')
  end

  it 'keeps the session of the property that receives the conversions when the page has more than one Analytics' do
    cookies = { '_ga' => 'GA1.1.111.222', '_ga_OUTRA12345' => 'GS2.1.s1111111111$o1', '_ga_3EDHXBTSBG' => 'GS2.1.s2222222222$o1' }

    expect(described_class.click_ids({ 'ga_session_id' => '1111111111' }, cookies, 'G-3EDHXBTSBG')['ga_session_id']).to eq('2222222222')
    expect(described_class.click_ids({ 'ga_session_id' => '1111111111' }, cookies, 'G-NAOEXISTE1')['ga_session_id']).to eq('1111111111')
  end

  it 'stamps the identity in the Protocol snapshot' do
    snapshot = described_class.snapshot({ 'gclid' => 'Abc' }, page: nil, cookies: { '_ga' => 'GA1.1.111.222' })

    expect(snapshot).to include('source' => 'google_ads', 'gclid' => 'Abc', 'ga_client_id' => '111.222')
  end
end
