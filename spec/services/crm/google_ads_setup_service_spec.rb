require 'rails_helper'

# 🎯 item 371: prepara a conta do Google Ads (ações por etapa + variáveis)
RSpec.describe Crm::GoogleAdsSetupService do
  let(:account) { create(:account) }
  let!(:settings) do
    CrmSetting.create!(account: account, google_ads_config: {
                         'developer_token' => 'dev', 'customer_id' => '1234567890', 'oauth_client_id' => 'a',
                         'oauth_client_secret' => 'b', 'oauth_refresh_token' => 'c', 'sent_log' => { '2026-10-01' => { 'x' => 1 } }
                       })
  end
  let(:base) { 'https://googleads.googleapis.com/v26/customers/1234567890' }

  before do
    Rails.cache.clear
    stub_request(:post, 'https://oauth2.googleapis.com/token').to_return(status: 200, body: { access_token: 'tok' }.to_json,
                                                                         headers: { 'Content-Type' => 'application/json' })
  end

  def json(body)
    { status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  it 'reaproveita o que já existe e cria só o que falta, guardando os endereços', :aggregate_failures do
    stub_request(:post, "#{base}/googleAds:search").to_return(
      json(results: [{ conversionAction: { resourceName: 'customers/1234567890/conversionActions/11', name: 'CEVICO · Agendou consulta' } }]),
      json(results: [{ conversionCustomVariable: { resourceName: 'customers/1234567890/conversionCustomVariables/5', tag: 'procedimento' } }])
    )
    created = stub_request(:post, "#{base}/conversionActions:mutate").to_return do |req|
      name = JSON.parse(req.body).dig('operations', 0, 'create', 'name')
      json(results: [{ resourceName: "customers/1234567890/conversionActions/#{name.length}" }])
    end
    variable = stub_request(:post, "#{base}/conversionCustomVariables:mutate")
               .to_return(json(results: [{ resourceName: 'customers/1234567890/conversionCustomVariables/6' }]))

    result = described_class.new(account).call

    expect(result[:success]).to be(true)
    expect(result[:actions]['agendou_consulta']).to eq('customers/1234567890/conversionActions/11')
    expect(result[:actions].keys).to match_array(%w[lead_whatsapp orcamento_enviado agendou_consulta compareceu_consulta fechou_cirurgia])
    expect(created).to have_been_requested.times(4)
    expect(variable).to have_been_requested.once
    expect(result[:variables]).to eq('procedimento' => 'customers/1234567890/conversionCustomVariables/5',
                                     'pagina' => 'customers/1234567890/conversionCustomVariables/6')
    cfg = settings.reload.google_ads_config
    expect(cfg['ads_conversion_actions']['fechou_cirurgia']).to be_present
    expect(cfg['ads_prepared_at']).to be_present
    expect(cfg['sent_log']).to eq('2026-10-01' => { 'x' => 1 }) # não mexe no resto
  end

  it 'a ação de fechamento vai como compra, contando cada cirurgia (2º olho)' do
    stub_request(:post, "#{base}/googleAds:search").to_return(json(results: []))
    stub_request(:post, "#{base}/conversionCustomVariables:mutate").to_return(json(results: [{ resourceName: 'v' }]))
    bodies = []
    stub_request(:post, "#{base}/conversionActions:mutate").to_return do |req|
      bodies << JSON.parse(req.body).dig('operations', 0, 'create')
      json(results: [{ resourceName: "a#{bodies.size}" }])
    end

    described_class.new(account).call

    purchase = bodies.find { |b| b['name'] == 'CEVICO · Fechou cirurgia' }
    expect(purchase).to include('type' => 'UPLOAD_CLICKS', 'category' => 'PURCHASE', 'countingType' => 'MANY_PER_CLICK',
                                'clickThroughLookbackWindowDays' => 90)
  end

  it 'sem acesso configurado, explica o que falta' do
    settings.update!(google_ads_config: { 'developer_token' => 'dev' })

    expect(described_class.new(account).call).to include(success: false, error: /developer token/)
  end
end
