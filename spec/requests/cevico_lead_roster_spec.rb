require 'rails_helper'

# 02/11: QUEM SÃO os leads — lista por período e origem em Resultados de tráfego
RSpec.describe 'CEVICO quem são os leads (GET /crm/pages_report/leads)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }
  let!(:page) do
    CevicoPage.create!(account: account, title: 'Hipermetropia em SP', slug: 'cirurgia-de-hipermetropia-em-sao-paulo', status: 'published',
                       category: 'captacao', custom_html: '<html><body>x</body></html>', daily_stats: {}, sections: [], team_comments: [])
  end
  let!(:inbox) { create(:inbox, account: account, name: 'ORGÂNICO') }
  let!(:lead) do
    account.contacts.create!(name: 'Jhe', phone_number: '+5511988887777',
                             additional_attributes: { 'page_ads' => { 'page_id' => page.id, 'slug' => page.slug, 'source' => 'google_ads',
                                                                      'campaign' => 'refrativa-2026', 'captured_at' => 1.day.ago.iso8601 } })
  end
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: lead) }

  before do
    # lead do linktree (sem página) dentro do período + um lead velho, fora dele
    account.contacts.create!(name: 'Mari', phone_number: '+5511977776666',
                             additional_attributes: { 'page_ads' => { 'slug' => 'hub', 'source' => 'google_organico',
                                                                      'captured_at' => 2.days.ago.iso8601 } })
    account.contacts.create!(name: 'Antigo', phone_number: '+5511966665555',
                             additional_attributes: { 'page_ads' => { 'page_id' => page.id, 'source' => 'google_ads',
                                                                      'captured_at' => 60.days.ago.iso8601 } })
  end

  it 'lista os leads do período com página, origem, caixa e conversa', :aggregate_failures do
    get "#{base}/pages_report/leads", params: { preset: 'last7' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    rows = response.parsed_body['leads']
    expect(rows.map { |r| r['nome'] }).to eq(%w[Jhe Mari])

    jhe = rows.first
    expect(jhe).to include('pagina' => 'Hipermetropia em SP', 'slug' => page.slug, 'origem' => 'google_ads', 'campanha' => 'refrativa-2026',
                           'agendou' => false)
    expect(jhe['conversa']).to include('id' => conversation.id, 'inbox' => 'ORGÂNICO')

    mari = rows.last
    expect(mari).to include('pagina' => 'Linktree (porta de entrada)', 'slug' => 'hub', 'origem' => 'google_organico')
    expect(mari['conversa']).to be_nil
  end

  it 'filtra por origem' do
    get "#{base}/pages_report/leads", params: { preset: 'last7', source: 'google_organico' }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['leads'].map { |r| r['nome'] }).to eq(['Mari'])
  end
end
