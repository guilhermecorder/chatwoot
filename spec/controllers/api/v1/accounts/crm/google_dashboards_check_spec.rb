require 'rails_helper'

# Item 313: a CONFERÊNCIA do painel Google — cada evento plugado está pronto
# para o Google contar? (nome aceito · evento-chave no Analytics · amarradas)
RSpec.describe 'Painel Google — conferência dos eventos', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil') }
  let(:stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Consulta Agendada') }
  let(:today) { Date.current.iso8601 }

  before do
    CrmSetting.create!(account: account, google_ads_config: {
                         'measurement_id' => 'G-TESTE12345', 'api_secret' => 's',
                         'sent_log' => { today => { 'agendou_consulta' => 5, 'Refrativa_PRK' => 2 } },
                         'tied_log' => { today => { 'agendou_consulta' => 3 } }
                       })
    stage.automations.create!(name: 'Agendou', trigger_type: 'card_entered', action_type: 'google_ads_conversion',
                              action_config: { 'ga4_event_name' => 'agendou_consulta', 'required_label' => 'refrativa' })
    stage.automations.create!(name: 'PRK', trigger_type: 'card_entered', action_type: 'google_ads_conversion',
                              action_config: { 'ga4_event_name' => 'Refrativa PRK' })
    allow(Crm::GoogleKeywordsService).to receive(:new).and_return(instance_double(Crm::GoogleKeywordsService, call: { configured: false }))
    allow(Crm::GoogleKeyEventsService).to receive(:new)
      .and_return(instance_double(Crm::GoogleKeyEventsService, call: { configured: true, key_events: %w[agendou_consulta generate_lead] }))
    allow(Cevico::PublicSite).to receive(:tracking_config).and_return('ga4_id' => 'G-TESTE12345')
    allow(Cevico::Gtm).to receive(:ga4_ids).and_return([])
    Rails.cache.clear
  end

  it 'says, event by event, what is ready and what is missing' do
    get "/api/v1/accounts/#{account.id}/crm/google_dashboard", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    check = response.parsed_body['check']
    expect(check['same_property']).to be(true)

    agendou = check['events'].find { |e| e['name'] == 'agendou_consulta' }
    expect(agendou).to include('sends_as' => 'agendou_consulta', 'key_event' => true, 'sent' => 5, 'tied' => 3,
                               'columns' => ['Consulta Agendada · refrativa'])

    prk = check['events'].find { |e| e['name'] == 'Refrativa PRK' }
    expect(prk).to include('sends_as' => 'Refrativa_PRK', 'key_event' => false, 'sent' => 2, 'tied' => 0)
    # o nome corrigido não vira linha à parte
    expect(check['events'].pluck('name')).not_to include('Refrativa_PRK')
  end

  it 'warns when the page measures in another GA4 property (a do GTM incluída)' do
    allow(Cevico::PublicSite).to receive(:tracking_config).and_return('gtm_id' => 'GTM-ABC1234')
    allow(Cevico::Gtm).to receive(:ga4_ids).with('GTM-ABC1234').and_return(['G-OUTRA99999'])

    get "/api/v1/accounts/#{account.id}/crm/google_dashboard", headers: admin.create_new_auth_token, as: :json

    check = response.parsed_body['check']
    expect(check['same_property']).to be(false)
    expect(check['page_ga4_ids']).to eq([{ 'id' => 'G-OUTRA99999', 'via' => 'GTM' }])
  end

  it 'accepts when the property that receives the events is the one the GTM loads' do
    allow(Cevico::PublicSite).to receive(:tracking_config).and_return('gtm_id' => 'GTM-ABC1234')
    allow(Cevico::Gtm).to receive(:ga4_ids).and_return(['G-TESTE12345'])

    get "/api/v1/accounts/#{account.id}/crm/google_dashboard", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body.dig('check', 'same_property')).to be(true)
  end
end
