require 'rails_helper'

# 🗺️ item 355: mapa do site e robots.txt do domínio das páginas — o Google
# recebe só as páginas que devem ranquear (sem as variações de anúncio).
RSpec.describe 'CEVICO sitemap.xml e robots.txt', type: :request do
  let(:cevico) { create(:account, name: 'CEVICO') }
  let(:otica) { create(:account, name: 'Sua Ótica') }

  def page!(slug, account: cevico, status: 'published', html: nil)
    CevicoPage.create!(account: account, title: slug.titleize, slug: slug, status: status, category: 'captacao',
                       custom_html: html, daily_stats: {}, sections: [], team_comments: [])
  end

  before do
    allow(Cevico::PublicSite).to receive(:host).and_return('clinica.cevico.com.br')
    Cevico::Company.save!(otica, 'name' => 'Sua Ótica', 'segment' => 'otica', 'public_host' => 'www.suaotica.com.br')
  end

  describe 'GET /sitemap.xml' do
    before do
      page!('refrativa')
      page!('guias', html: '<html><head><meta name="robots" content="index, follow"></head><body></body></html>')
      page!('refrativa-g')
      page!('refrativa-m')
      page!('refrativa-gd')
      page!('miopia-oculta', html: '<html><head><meta content="noindex, follow" name="robots"></head></html>')
      page!('rascunho', status: 'draft')
      page!('oculos-de-sol', account: otica)
    end

    it 'lista só as páginas publicadas e indexáveis deste domínio', :aggregate_failures do
      host! 'clinica.cevico.com.br'
      get '/sitemap.xml'

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/xml')
      expect(response.headers['Cache-Control']).to include('public').and include('max-age=900')
      doc = Nokogiri::XML(response.body).remove_namespaces!
      locs = doc.xpath('//url/loc').map(&:text)
      expect(locs).to eq(%w[https://clinica.cevico.com.br/ https://clinica.cevico.com.br/guias https://clinica.cevico.com.br/refrativa])
      expect(doc.at_xpath("//url[loc='https://clinica.cevico.com.br/guias']/lastmod").text)
        .to eq(CevicoPage.find_by(slug: 'guias').updated_at.utc.iso8601)
    end

    it 'no domínio de outra empresa, só as páginas dela' do
      host! 'www.suaotica.com.br'
      get '/sitemap.xml'
      locs = Nokogiri::XML(response.body).remove_namespaces!.xpath('//url/loc').map(&:text)
      expect(locs).to eq(['https://www.suaotica.com.br/', 'https://www.suaotica.com.br/oculos-de-sol'])
    end

    it 'fora do domínio das páginas não existe' do
      host! 'sistema.example.com'
      get '/sitemap.xml'
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /robots.txt' do
    it 'no domínio das páginas libera tudo e aponta o sitemap', :aggregate_failures do
      host! 'clinica.cevico.com.br'
      get '/robots.txt'

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/plain')
      expect(response.body).to include("User-agent: *\nAllow: /\n")
      expect(response.body).to include('Sitemap: https://clinica.cevico.com.br/sitemap.xml')
      expect(response.body).not_to include('/landings')
    end

    it 'no host do sistema continua o de sempre', :aggregate_failures do
      host! 'sistema.example.com'
      get '/robots.txt'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Disallow: /widget')
      expect(response.body).not_to include('Sitemap')
    end
  end

  describe 'GET /biblioteca/numeros.json' do
    let(:marker_html) { '<html><body><main data-biblioteca="1"></main></body></html>' }
    let!(:library) { page!('biblioteca-cevico-7k3q9x', html: marker_html) }
    let!(:guia) { page!('guia-lasik') }

    before do
      2.times { CevicoPageTraffic.bump!(page: guia, kind: 'view', source: 'seo') }
      CevicoPageTraffic.bump!(page: guia, kind: 'cta', source: 'seo')
      host! 'clinica.cevico.com.br'
    end

    def numbers
      response.parsed_body
    end

    it 'entrega as contagens por página e o total', :aggregate_failures do
      get '/biblioteca/numeros.json', params: { de: library.slug, dias: 7 }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/json')
      expect(response.headers['Cache-Control']).to include('private').and include('max-age=300')
      expect(numbers['dias']).to eq(7)
      expect(numbers['since']).to eq((Date.current - 6).iso8601)
      expect(numbers['until']).to eq(Date.current.iso8601)
      expect(numbers['paginas']['guia-lasik']).to eq('acessos' => 2, 'cliques' => 1, 'leads' => 0, 'agendou' => 0,
                                                     'titulo' => 'Guia Lasik', 'tipo' => 'organica')
      expect(numbers['total']).to eq('acessos' => 2, 'cliques' => 1, 'leads' => 0, 'agendou' => 0)
    end

    it 'dias fora da lista cai em 30' do
      get '/biblioteca/numeros.json', params: { de: library.slug, dias: 12 }
      expect(numbers['dias']).to eq(30)
    end

    describe 'régua padrão do sistema (?preset=)' do
      let(:today) { Crm::ResolvesPeriod::PERIOD_TZ.today }

      it 'ontem = só o dia de ontem', :aggregate_failures do
        get '/biblioteca/numeros.json', params: { de: library.slug, preset: 'yesterday' }
        expect(numbers['preset']).to eq('yesterday')
        expect(numbers['since']).to eq((today - 1).iso8601)
        expect(numbers['until']).to eq((today - 1).iso8601)
        expect(numbers['dias']).to eq(1)
      end

      it 'semana passada = segunda a domingo anteriores', :aggregate_failures do
        get '/biblioteca/numeros.json', params: { de: library.slug, preset: 'last_week' }
        since_date = Date.parse(numbers['since'])
        expect(since_date).to be_monday
        expect(Date.parse(numbers['until'])).to eq(since_date + 6)
        expect(numbers['dias']).to eq(7)
      end

      it 'este mês termina hoje (nunca no futuro)', :aggregate_failures do
        get '/biblioteca/numeros.json', params: { de: library.slug, preset: 'month' }
        expect(numbers['since']).to eq(today.beginning_of_month.iso8601)
        expect(numbers['until']).to eq(today.iso8601)
      end

      it 'personalizado respeita De/Até e corta em 2 anos', :aggregate_failures do
        get '/biblioteca/numeros.json', params: { de: library.slug, preset: 'custom', from: '2026-10-01', to: '2026-10-05' }
        expect([numbers['since'], numbers['until'], numbers['dias']]).to eq(['2026-10-01', '2026-10-05', 5])

        get '/biblioteca/numeros.json', params: { de: library.slug, preset: 'custom', from: '2015-01-01', to: today.iso8601 }
        expect(numbers['dias']).to eq(731)
      end

      it 'preset desconhecido cai no ?dias= antigo' do
        get '/biblioteca/numeros.json', params: { de: library.slug, preset: 'semestre', dias: 7 }
        expect([numbers['preset'], numbers['dias']]).to eq(['dias', 7])
      end
    end

    it 'só contagens (mais o título e o tipo): sem a linha do hub', :aggregate_failures do
      rows = [{ slug: '', views: 9, cta: 9, leads: 9, booked: 9 },
              { slug: 'guia-lasik', views: 5, cta: 2, leads: 1, booked: 1, title: 'x', sources: { 'seo' => 5 }, campaigns: { 'c' => 1 } }]
      allow(Cevico::TrafficReport).to receive(:new).and_return(instance_double(Cevico::TrafficReport, rows: rows))
      get '/biblioteca/numeros.json', params: { de: library.slug }

      expect(numbers.keys).to match_array(%w[since until dias preset atualizado paginas total])
      expect(numbers['paginas']).to eq('guia-lasik' => { 'acessos' => 5, 'cliques' => 2, 'leads' => 1, 'agendou' => 1,
                                                         'titulo' => 'x', 'tipo' => 'organica' })
      expect(numbers['total']).to eq('acessos' => 5, 'cliques' => 2, 'leads' => 1, 'agendou' => 1)
    end

    it 'página sem o marcador não responde' do
      get '/biblioteca/numeros.json', params: { de: guia.slug }
      expect(response).to have_http_status(:not_found)
    end

    it 'biblioteca em rascunho não responde' do
      library.update!(status: 'draft')
      get '/biblioteca/numeros.json', params: { de: library.slug }
      expect(response).to have_http_status(:not_found)
    end

    it 'endereço inexistente ou vazio não responde', :aggregate_failures do
      get '/biblioteca/numeros.json', params: { de: 'biblioteca-outra' }
      expect(response).to have_http_status(:not_found)
      get '/biblioteca/numeros.json'
      expect(response).to have_http_status(:not_found)
    end

    it 'fora do domínio das páginas não existe', :aggregate_failures do
      host! 'sistema.example.com'
      get '/biblioteca/numeros.json', params: { de: library.slug }
      expect(response).to have_http_status(:not_found)
      host! 'www.suaotica.com.br' # domínio de outra empresa: a biblioteca não é dela
      get '/biblioteca/numeros.json', params: { de: library.slug }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /biblioteca/raio-x.json' do
    let(:marker_html) { '<html><body><main data-biblioteca="1"></main></body></html>' }
    let!(:library) { page!('biblioteca', html: marker_html) }
    let(:guia_html) do
      '<html><body><h1>Guia</h1><h2>Isso acontece<br>com você?</h2><a data-ev="cta_topo" href="https://wa.me/5511">Falar</a>' \
        '<h2 id="investimento">Quanto custa</h2><a href="https://wa.me/5511?text=oi">Perguntar</a><h2>Dúvidas</h2></body></html>'
    end
    let!(:guia) { page!('guia-lasik', html: guia_html) }
    let(:today) { Date.current.iso8601 }

    before do
      host! 'clinica.cevico.com.br'
      40.times { CevicoPageTraffic.bump!(page: guia, kind: 'view', source: 'seo') }
      CevicoPageTraffic.bump!(page: guia, kind: 'cta', source: 'seo')
      # 40 visitas medidas: todas viram o 1º título, 30 o investimento, 6 as dúvidas
      guia.update_columns(daily_stats: { today => { # rubocop:disable Rails/SkipsModelValidations
                            'scroll' => { '0' => 4, '25' => 6, '50' => 20, '100' => 10 },
                            'secoes' => { 'isso-acontececom-voce' => 40, 'investimento' => 30, 'duvidas' => 6 },
                            'botoes' => { 'cta_topo' => 1, 'investimento#1' => 0 },
                            'erros' => { 'investimento~foto' => 3, 'investimento~texto' => 1 }
                          } })
    end

    def xray
      response.parsed_body
    end

    it 'mostra o mapa de calor trecho a trecho e aponta onde mais gente para', :aggregate_failures do
      get '/biblioteca/raio-x.json', params: { de: library.slug, pagina: guia.slug, dias: 7 }

      expect(response).to have_http_status(:ok)
      expect(xray['numeros']).to include('acessos' => 40, 'cliques' => 1)
      expect(xray['leitura']['medidas']).to eq(40)
      expect(xray['leitura']['chegaram']).to eq('25' => 36, '50' => 30, '75' => 10, '100' => 10)
      trechos = xray['trechos'].map { |t| t.slice('key', 'tipo', 'viram', 'saida', 'perdidas', 'status') }
      expect(trechos).to eq([
                              { 'key' => 'topo', 'tipo' => 'abertura', 'viram' => 40, 'saida' => 0.0, 'perdidas' => 0, 'status' => 'boa' },
                              { 'key' => 'isso-acontececom-voce', 'tipo' => 'conteudo', 'viram' => 40, 'saida' => 0.25, 'perdidas' => 10,
                                'status' => 'atencao' },
                              { 'key' => 'investimento', 'tipo' => 'investimento', 'viram' => 30, 'saida' => 0.8, 'perdidas' => 24,
                                'status' => 'problema' },
                              { 'key' => 'duvidas', 'tipo' => 'fecho', 'viram' => 6, 'saida' => nil, 'perdidas' => 0, 'status' => 'pouco' }
                            ])
      investimento = xray['trechos'][2]
      expect(investimento['erros']).to eq('foto' => 3, 'texto' => 1)
      expect(investimento['recomendacoes'].join).to include('o que está incluso').and include('tocam na foto')
      expect(investimento['teste']).to eq('Investimento antes × depois das dúvidas.')
      expect(xray['botoes'].pluck('key', 'cliques', 'marco_titulo')).to eq([['cta_topo', 1, 'Isso acontece com você?'],
                                                                            ['investimento#1', 0, 'Quanto custa']])
      expect(xray['diagnostico'].first).to include('nivel' => 'alerta', 'titulo' => 'Onde mais gente para de ler: “Quanto custa”')
      expect(xray['parametros']['saida']).to eq('abertura' => [0.3, 0.45], 'padrao' => [0.1, 0.25])
      expect(xray['periodo']).to include('preset' => 'dias', 'dias' => 7)
    end

    it 'com pouca visita, avisa que é cedo em vez de concluir' do
      CevicoPageTraffic.where(cevico_page_id: guia.id).delete_all
      get '/biblioteca/raio-x.json', params: { de: library.slug, pagina: guia.slug }
      expect(xray['diagnostico'].first).to include('nivel' => 'info', 'titulo' => 'Ainda pouca visita para tirar conclusões')
    end

    it 'o painel de calor junta os trechos com problema de todas as páginas', :aggregate_failures do
      get '/biblioteca/calor.json', params: { de: library.slug, dias: 7 }

      heat = response.parsed_body
      expect(response).to have_http_status(:ok)
      expect(heat['paginas'].pluck('slug', 'medidas')).to eq([['guia-lasik', 40]])
      ranking = heat['ranking'].pluck('titulo', 'status', 'perdidas', 'erros')
      expect(ranking).to eq([['Quanto custa', 'problema', 24, 4], ['Isso acontece com você?', 'atencao', 10, 0]])
      expect(heat['totais']).to include('medidas' => 40, 'status' => { 'problema' => 1, 'atencao' => 1, 'boa' => 1 })
    end

    it 'só responde com a chave da biblioteca e para página publicada', :aggregate_failures do
      get '/biblioteca/raio-x.json', params: { de: guia.slug, pagina: guia.slug }
      expect(response).to have_http_status(:not_found)
      get '/biblioteca/raio-x.json', params: { de: library.slug, pagina: 'nao-existe' }
      expect(response).to have_http_status(:not_found)
      guia.update!(status: 'draft')
      get '/biblioteca/raio-x.json', params: { de: library.slug, pagina: guia.slug }
      expect(response).to have_http_status(:not_found)
    end
  end
end
