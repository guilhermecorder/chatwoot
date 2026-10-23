require 'rails_helper'

# 🩻 Raio-X (23/10): o beacon da página ANEXADA conta rolagem, títulos vistos e
# botões tocados — só as chaves que existem no HTML da própria página
RSpec.describe 'CEVICO leitura da página anexada', type: :request do
  let(:account) { create(:account) }
  let(:html) do
    '<html><body><h1>Guia</h1><h2>Como é feita</h2><a data-ev="cta_topo" href="https://wa.me/5511">Falar</a>' \
      '<h2 id="investimento">Quanto custa</h2><a href="https://wa.me/5511?text=oi">Perguntar</a></body></html>'
  end
  let!(:page) do
    CevicoPage.create!(account: account, title: 'Guia', slug: 'guia-leitura', status: 'published', custom_html: html,
                       daily_stats: {}, sections: [], team_comments: [])
  end
  let(:today) { Date.current.iso8601 }

  def day
    page.reload.daily_stats[today]
  end

  it 'a página no ar leva o beacon de leitura' do
    get "/p/#{page.slug}"
    expect(response.body).to include('data-cv-marco').and include("/p/#{page.slug}/track")
  end

  it 'soma rolagem, títulos e botões da visita', :aggregate_failures do
    post "/p/#{page.slug}/track", params: { depth: '0', secoes: 'como-e-feita,investimento', botoes: 'cta_topo,investimento#1' }
    post "/p/#{page.slug}/track", params: { depth: '50', secoes: 'como-e-feita' }

    expect(response).to have_http_status(:no_content)
    expect(day['scroll']).to eq('0' => 1, '50' => 1)
    expect(day['secoes']).to eq('como-e-feita' => 2, 'investimento' => 1)
    expect(day['botoes']).to eq('cta_topo' => 1, 'investimento#1' => 1)
  end

  it 'a rolagem sobe de faixa sem contar a visita duas vezes (beacon aos poucos)', :aggregate_failures do
    post "/p/#{page.slug}/track", params: { depth: '0', secoes: 'como-e-feita' }
    post "/p/#{page.slug}/track", params: { de: '0', depth: '50', secoes: 'investimento' }
    post "/p/#{page.slug}/track", params: { de: '50', depth: '100' }

    expect(day['scroll']).to eq('100' => 1)
    expect(day['secoes']).to eq('como-e-feita' => 1, 'investimento' => 1)
  end

  it 'subida de faixa estranha não tira nada: faixa antiga maior, igual ou zerada', :aggregate_failures do
    post "/p/#{page.slug}/track", params: { depth: '75' }
    post "/p/#{page.slug}/track", params: { de: '100', depth: '25' } # anda para trás: só soma a nova
    post "/p/#{page.slug}/track", params: { de: '50', depth: '50' } # igual: só soma
    post "/p/#{page.slug}/track", params: { de: '0', depth: '25' } # faixa 0 vazia (visita de ontem): não fica negativa

    expect(day['scroll']).to eq('75' => 1, '25' => 2, '50' => 1)
  end

  it 'conta os toques errados por trecho, só de tipos e trechos que existem', :aggregate_failures do
    post "/p/#{page.slug}/track", params: { erros: 'investimento~foto,topo~parece-botao,inventado~foto,investimento~bomba' }
    expect(day['erros']).to eq('investimento~foto' => 1, 'topo~parece-botao' => 1)
  end

  it 'ignora chave que não existe na página e rolagem fora da régua', :aggregate_failures do
    post "/p/#{page.slug}/track", params: { depth: '33', secoes: 'inventada,<script>', botoes: 'cta_topo#9' }

    expect(response).to have_http_status(:no_content)
    expect(page.reload.daily_stats).to eq({})
  end

  it 'um aviso não apaga o outro (visita do teste A/B + leitura)', :aggregate_failures do
    stale = CevicoPage.find(page.id) # foi carregada antes do beacon chegar
    post "/p/#{page.slug}/track", params: { depth: '100', secoes: 'investimento' }
    stale.track_hit!('view', variant: 'b')

    expect(day).to include('view' => 1, 'view_b' => 1, 'scroll' => { '100' => 1 }, 'secoes' => { 'investimento' => 1 })
    expect(page.reload.views_count).to eq(1)
  end

  it 'página montada (sem HTML anexado) continua só com a rolagem', :aggregate_failures do
    page.update!(custom_html: nil)
    post "/p/#{page.slug}/track", params: { depth: '75', secoes: 'como-e-feita' }
    expect(day).to eq('scroll' => { '75' => 1 })
  end
end
