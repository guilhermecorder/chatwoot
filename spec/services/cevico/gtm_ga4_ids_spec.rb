require 'rails_helper'

# Item 313: a Conferência lê do contêiner do GTM em qual Analytics a página mede
RSpec.describe Cevico::Gtm do
  let(:url) { 'https://www.googletagmanager.com/gtm.js?id=GTM-ABC1234' }

  before { Rails.cache.clear }

  it 'lists the GA4 properties the container loads, without repeating' do
    stub_request(:get, url).to_return(status: 200, body: 'x={"vtp_tagId":"G-QT6Y7BJ6SB"};y=["G-QT6Y7BJ6SB","AW-123456789","G-OUTRA12345"]')

    expect(described_class.ga4_ids('gtm-abc1234')).to eq(%w[G-QT6Y7BJ6SB G-OUTRA12345])
  end

  it 'returns nothing for a bad id or when Google does not answer (sem derrubar a tela)' do
    stub_request(:get, url).to_timeout

    expect(described_class.ga4_ids('GTM-ABC1234')).to eq([])
    expect(described_class.ga4_ids('qualquer coisa')).to eq([])
    expect(described_class.ga4_ids(nil)).to eq([])
  end
end
