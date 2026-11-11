require 'rails_helper'

# ↪ item 395: redirecionamento permanente (301) por página. O endereço que
# sai (guia juntado a outro) manda visitante e Google para o endereço que
# fica, no MESMO domínio, com a query string (utm, gclid, fbclid) e a âncora.
# Sem migration: status 'redirected' + chave reservada 'redirect' no daily_stats.
RSpec.describe 'CEVICO página redirecionada (301)', type: :request do
  let(:account) { create(:account, name: 'CEVICO') }
  let(:other_account) { create(:account, name: 'Sua Ótica') }
  let!(:destino) { page!('diferenca-miopia-astigmatismo-hipermetropia') }
  let!(:antiga) { page!('astigmatismo-e-miopia') }

  def page!(slug, account: self.account, status: 'published', **attrs)
    CevicoPage.create!({ account: account, title: slug.titleize, slug: slug, status: status, category: 'captacao',
                         daily_stats: {}, sections: [], ab_variants: [], team_comments: [] }.merge(attrs))
  end

  describe 'GET /p/:slug (host do sistema, sem domínio oficial)' do
    it 'responde 301 para o endereço da página de destino, no mesmo host', :aggregate_failures do
      antiga.redirect_to_page!(destino)

      get '/p/astigmatismo-e-miopia'

      expect(response).to have_http_status(:moved_permanently)
      expect(response.headers['Location']).to eq('http://www.example.com/p/diferenca-miopia-astigmatismo-hipermetropia')
    end

    it 'preserva a query string inteira e acrescenta a âncora no fim', :aggregate_failures do
      antiga.redirect_to_page!(destino, anchor: 'juntos')

      get '/p/astigmatismo-e-miopia?utm_source=google&utm_campaign=Guias+SEO&gclid=AbC-123_x&fbclid=IwAR0'

      expect(response).to have_http_status(:moved_permanently)
      expect(response.headers['Location']).to eq(
        'http://www.example.com/p/diferenca-miopia-astigmatismo-hipermetropia' \
        '?utm_source=google&utm_campaign=Guias+SEO&gclid=AbC-123_x&fbclid=IwAR0#juntos'
      )
    end

    it 'não conta visita nem na página que saiu nem na de destino', :aggregate_failures do
      antiga.redirect_to_page!(destino)

      expect { get '/p/astigmatismo-e-miopia' }.not_to change(CevicoPageTraffic, :count)
      expect(antiga.reload.views_count).to eq(0)
      expect(destino.reload.views_count).to eq(0)
    end

    it 'cliques e avisos da página redirecionada respondem 404 (ela não está no ar)', :aggregate_failures do
      antiga.update!(cta_url: 'https://wa.me/5511999999999')
      antiga.redirect_to_page!(destino)

      get '/p/astigmatismo-e-miopia/cta'
      expect(response).to have_http_status(:not_found)
      post '/p/astigmatismo-e-miopia/track', params: { depth: '50' }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'no domínio oficial das páginas (endereço na raiz)' do
    before { allow(Cevico::PublicSite).to receive_messages(host: 'clinica.cevico.com.br', app_host: 'sistema.example.com') }

    it 'redireciona na raiz do mesmo domínio, com utm e âncora', :aggregate_failures do
      antiga.redirect_to_page!(destino, anchor: 'juntos')
      host! 'clinica.cevico.com.br'

      get '/astigmatismo-e-miopia?utm_source=google&gclid=XyZ'

      expect(response).to have_http_status(:moved_permanently)
      expect(response.headers['Location'])
        .to eq('http://clinica.cevico.com.br/diferenca-miopia-astigmatismo-hipermetropia?utm_source=google&gclid=XyZ#juntos')
    end

    it 'página redirecionada sai do sitemap; a de destino continua', :aggregate_failures do
      antiga.redirect_to_page!(destino)
      host! 'clinica.cevico.com.br'

      get '/sitemap.xml'

      locs = Nokogiri::XML(response.body).remove_namespaces!.xpath('//url/loc').map(&:text)
      expect(locs).to eq(%w[https://clinica.cevico.com.br/ https://clinica.cevico.com.br/diferenca-miopia-astigmatismo-hipermetropia])
    end
  end

  describe 'proteções (nunca em laço, nunca para página fora do ar)' do
    it 'destino despublicado: 404, sem redirecionar', :aggregate_failures do
      antiga.redirect_to_page!(destino)
      destino.update!(status: 'draft')

      get '/p/astigmatismo-e-miopia'

      expect(response).to have_http_status(:not_found)
      expect(response.headers['Location']).to be_nil
    end

    it 'destino apagado: 404' do
      antiga.redirect_to_page!(destino)
      destino.destroy!

      get '/p/astigmatismo-e-miopia'
      expect(response).to have_http_status(:not_found)
    end

    it 'laço A → B → A: as duas respondem 404', :aggregate_failures do
      antiga.redirect_to_page!(destino)
      destino.redirect_to_page!(antiga)

      get '/p/astigmatismo-e-miopia'
      expect(response).to have_http_status(:not_found)
      get '/p/diferenca-miopia-astigmatismo-hipermetropia'
      expect(response).to have_http_status(:not_found)
    end

    it 'página apontando para ela mesma: 404' do
      antiga.update!(status: 'redirected', daily_stats: { 'redirect' => { 'page_id' => antiga.id } })

      get '/p/astigmatismo-e-miopia'
      expect(response).to have_http_status(:not_found)
    end

    it 'cadeia A → B → C: segue UM nível e responde direto para C, com a âncora do último trecho', :aggregate_failures do
      final = page!('cirurgia-de-astigmatismo')
      antiga.redirect_to_page!(destino, anchor: 'juntos')
      destino.redirect_to_page!(final, anchor: 'grau')

      get '/p/astigmatismo-e-miopia?gclid=1'

      expect(response).to have_http_status(:moved_permanently)
      expect(response.headers['Location']).to eq('http://www.example.com/p/cirurgia-de-astigmatismo?gclid=1#grau')
    end

    it 'cadeia mais funda que um nível (A → B → C → D): 404' do
      meio = page!('grau-maximo-astigmatismo-cirurgia')
      final = page!('cirurgia-de-astigmatismo')
      antiga.redirect_to_page!(destino)
      destino.redirect_to_page!(meio)
      meio.redirect_to_page!(final)

      get '/p/astigmatismo-e-miopia'
      expect(response).to have_http_status(:not_found)
    end

    it 'destino de outra conta nunca vale: 404' do
      alheia = page!('oculos-de-sol', account: other_account)
      antiga.update!(status: 'redirected', daily_stats: { 'redirect' => { 'page_id' => alheia.id } })

      get '/p/astigmatismo-e-miopia'
      expect(response).to have_http_status(:not_found)
    end

    it 'âncora fora da régua gravada à mão não vai para o endereço', :aggregate_failures do
      antiga.update!(status: 'redirected',
                     daily_stats: { 'redirect' => { 'page_id' => destino.id, 'anchor' => "x\r\nSet-Cookie: a=b" } })

      get '/p/astigmatismo-e-miopia'

      expect(response).to have_http_status(:moved_permanently)
      expect(response.headers['Location']).to eq('http://www.example.com/p/diferenca-miopia-astigmatismo-hipermetropia')
    end

    it 'página que nunca existiu e rascunho continuam 404', :aggregate_failures do
      page!('rascunho-qualquer', status: 'draft')

      get '/p/nao-existe'
      expect(response).to have_http_status(:not_found)
      get '/p/rascunho-qualquer'
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'guardar e desfazer (modelo)' do
    it 'guarda destino, âncora e a etapa de antes sem mexer nos números nem no funil', :aggregate_failures do
      proxima = page!('refrativa')
      antiga.update!(next_page: proxima)
      antiga.track_hit!('view', variant: 'a')

      antiga.reload.redirect_to_page!(destino, anchor: 'juntos')
      antiga.reload

      expect(antiga).to be_redirected
      expect(antiga.redirect_info).to include('page_id' => destino.id, 'anchor' => 'juntos', 'was' => 'published')
      expect(antiga.daily_stats[Date.current.iso8601]).to include('view' => 1)
      expect(antiga.next_page_id).to eq(proxima.id)
      expect(antiga.ab_results['a']['view']).to eq(1) # a chave reservada não entra na soma dos dias
    end

    it 'desfazer devolve a página para a etapa em que estava e limpa a chave', :aggregate_failures do
      antiga.redirect_to_page!(destino, anchor: 'juntos')
      antiga.redirect_to_page!(page!('cirurgia-de-astigmatismo')) # trocar o destino não perde a etapa original

      antiga.undo_redirect!
      antiga.reload

      expect(antiga.status).to eq('published')
      expect(antiga.daily_stats).not_to have_key('redirect')
      get '/p/astigmatismo-e-miopia'
      expect(response).to have_http_status(:ok)
    end

    it 'rascunho redirecionado volta a ser rascunho ao desfazer' do
      rascunho = page!('guia-velho', status: 'draft')
      rascunho.redirect_to_page!(destino)

      rascunho.undo_redirect!
      expect(rascunho.reload.status).to eq('draft')
    end
  end

  describe 'relatório das páginas (pages_report) com página redirecionada' do
    let(:admin) { create(:user, account: account, role: :administrator) }

    it 'responde normalmente e lista a página com o estado novo', :aggregate_failures do
      antiga.track_hit!('view')
      CevicoPageTraffic.bump!(page: antiga, kind: 'view', source: 'seo', campaign: nil)
      antiga.reload.redirect_to_page!(destino)

      get "/api/v1/accounts/#{account.id}/crm/pages_report?preset=last7", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      listed = response.parsed_body['pages'].find { |pg| pg['id'] == antiga.id }
      expect(listed['status']).to eq('redirected')

      get "/api/v1/accounts/#{account.id}/crm/pages_dashboard", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end
end
