require 'rails_helper'

# 19/10: o clique no WhatsApp da página vira "Contact" na Meta pelo servidor —
# o do Pixel se perdia quando o celular abria o WhatsApp (zero Contact em 28 dias)
RSpec.describe 'CEVICO clique no WhatsApp → Contact na Meta', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:endpoint) { %r{graph\.facebook\.com/v19\.0/123456/events} }
  let!(:page) do
    CevicoPage.create!(account: account, title: 'Cirurgia de miopia', slug: 'cirurgia-de-miopia-m', status: 'published',
                       category: 'captacao', custom_html: '<html><body><a href="https://wa.me/5511999999999">WhatsApp</a></body></html>',
                       daily_stats: {}, sections: [], team_comments: [])
  end

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

  it 'manda o Contact do site com o Protocolo como event_id e a identidade do navegador', :aggregate_failures do
    perform_enqueued_jobs do
      post "/p/#{page.slug}/ref", params: { utm_source: 'meta', utm_content: 'CV-020 · CARR', fbp: 'fb.1.17.99', fbc: 'fb.1.170.IwAR1' },
                                  headers: { 'User-Agent' => 'Mozilla/5.0 (iPhone)', 'Referer' => 'https://clinica.cevico.com.br/cirurgia-de-miopia-m' }
    end
    token = response.parsed_body['token']

    expect(token).to be_present
    expect(sent_event).to include('event_name' => 'Contact', 'event_id' => token, 'action_source' => 'website',
                                  'event_source_url' => 'https://clinica.cevico.com.br/cirurgia-de-miopia-m')
    expect(sent_event['user_data']).to include('client_user_agent' => 'Mozilla/5.0 (iPhone)', 'fbp' => 'fb.1.17.99',
                                               'fbc' => 'fb.1.170.IwAR1')
    expect(sent_event['user_data']['client_ip_address']).to be_present
    expect(sent_event['custom_data']).to eq('content_name' => page.slug, 'content_category' => 'captacao')
  end

  it 'o clique segue mesmo se a Meta recusar' do
    stub_request(:post, endpoint).to_return(status: 400, body: { error: { message: 'token vencido' } }.to_json,
                                            headers: { 'Content-Type' => 'application/json' })

    perform_enqueued_jobs { post "/p/#{page.slug}/ref" }

    expect(response.parsed_body['token']).to be_present
  end

  it 'sem Meta configurada não manda nada' do
    CrmSetting.find_by(account: account).update!(meta_ads_config: {})

    perform_enqueued_jobs { post "/p/#{page.slug}/ref" }

    expect(response.parsed_body['token']).to be_present
    expect(WebMock).not_to have_requested(:post, endpoint)
  end
end
