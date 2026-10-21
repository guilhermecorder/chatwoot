require 'rails_helper'

# 🧪 item 306: teste A/B em página HTML ANEXADA — headline no lugar do <h1>,
# mesma variação para quem volta, clique e lead contados por variação
RSpec.describe 'CEVICO página anexada em teste A/B', type: :request do
  let(:account) { create(:account) }
  let(:html) do
    '<html><head><title>Refrativa</title></head><body><h1>Enxergar bem,<br><span>o novo normal.</span></h1>' \
      '<a href="https://wa.me/5511999999999?text=Oi">WhatsApp</a></body></html>'
  end
  let(:variants) do
    [{ 'key' => 'b', 'name' => 'Sem depender', 'title' => 'Descubra se você pode *deixar os óculos para trás.*', 'active' => true },
     { 'key' => 'c', 'name' => 'Pausada', 'title' => 'Imagine acordar e enxergar bem', 'active' => false }]
  end
  let!(:page) do
    CevicoPage.create!(account: account, title: 'Refrativa', slug: 'refrativa-teste', status: 'published',
                       custom_html: html, ab_variants: variants, daily_stats: {}, sections: [], team_comments: [])
  end

  it '?v=b serve a headline da variação no lugar do h1 e conta a visita nela', :aggregate_failures do
    get "/p/#{page.slug}", params: { v: 'b' }

    expect(response.body).to include('Descubra se você pode <span>deixar os óculos para trás.</span></h1>')
    expect(response.body).not_to include('o novo normal')
    expect(response.body).to include("body.set('v', 'b')")
    expect(page.reload.ab_results['b']['view']).to eq(1)
  end

  it '?v=a serve a página original' do
    get "/p/#{page.slug}", params: { v: 'a' }
    expect(response.body).to include('<h1>Enxergar bem,<br><span>o novo normal.</span></h1>')
  end

  it 'variação pausada não entra no ar, só na prévia', :aggregate_failures do
    get "/p/#{page.slug}", params: { v: 'c' }
    expect(response.body).not_to include('Imagine acordar')

    get "/p/rascunho/#{page.preview_token}", params: { v: 'c' }
    expect(response.body).to include('Imagine acordar e enxergar bem</h1>')
  end

  it 'quem volta vê a mesma variação sorteada (cookie da página)', :aggregate_failures do
    get "/p/#{page.slug}"
    first = cookies["cv_ab_#{page.id}"]
    expect(first).to be_in(%w[a b])

    5.times { get "/p/#{page.slug}" }
    expect(cookies["cv_ab_#{page.id}"]).to eq(first)
    expect(page.reload.ab_results[first]['view']).to eq(6)
  end

  it 'clique no WhatsApp conta na variação e o Protocolo casado vira lead dela', :aggregate_failures do
    post "/p/#{page.slug}/ref", params: { v: 'b', utm_source: 'google', gclid: 'abc' }
    token = response.parsed_body['token']
    ref = CevicoPageRef.find_by(token: token)

    expect(ref.source_data['variant']).to eq('b')
    expect(page.reload.ab_results['b']).to include('cta' => 1, 'lead' => 0)

    ref.update!(contact: create(:contact, account: account))
    expect(page.reload.ab_results['b']['lead']).to eq(1)
    expect(page.ab_results['a']['lead']).to eq(0)
  end

  it 'clique sem teste (sem v) continua funcionando e não inventa variação', :aggregate_failures do
    post "/p/#{page.slug}/ref", params: { utm_source: 'google' }
    ref = CevicoPageRef.find_by(token: response.parsed_body['token'])
    expect(ref.source_data).not_to have_key('variant')
    expect(page.reload.cta_clicks_count).to eq(1)
  end
end
