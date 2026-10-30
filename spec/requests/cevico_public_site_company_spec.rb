require 'rails_helper'

# 🏢 rodada 334: páginas públicas POR EMPRESA — o domínio da requisição diz
# de qual conta é o hub (Protocolo, páginas, WhatsApp, rastreio). Sem host
# casado, tudo continua como sempre (fallback: primeira página publicada).
RSpec.describe 'CEVICO site público por empresa', type: :request do
  let(:cevico) { create(:account, name: 'CEVICO') }
  let(:otica) { create(:account, name: 'Sua Ótica') }
  let(:cevico_page) do
    CevicoPage.create!(account: cevico, title: 'Refrativa', slug: 'refrativa-x', status: 'published', category: 'captacao',
                       daily_stats: {}, sections: [], team_comments: [])
  end
  let(:otica_page) do
    CevicoPage.create!(account: otica, title: 'Óculos de sol', slug: 'oculos-de-sol', status: 'published', category: 'captacao',
                       daily_stats: {}, sections: [], team_comments: [])
  end

  before do
    cevico_page
    otica_page
    Cevico::Company.save!(otica, 'name' => 'Sua Ótica', 'segment' => 'otica', 'public_host' => 'https://www.suaotica.com.br/',
                                 'hub' => { 'whatsapp' => '5511988887777' },
                                 'tracking' => { 'meta_pixel_id' => '999', 'ga4_measurement_id' => 'G-OTICA1' })
  end

  describe Cevico::PublicSite do
    it 'resolve host → conta e conta → host', :aggregate_failures do
      expect(described_class.account_for_host('www.suaotica.com.br')).to eq(otica)
      expect(described_class.account_for_host('WWW.SUAOTICA.COM.BR')).to eq(otica)
      expect(described_class.account_for_host('outro.com.br')).to be_nil
      expect(described_class.account_for_host(nil)).to be_nil
      expect(described_class.host_for(otica)).to eq('www.suaotica.com.br')
      expect(described_class.host_for(cevico)).to eq(described_class.host) # sem host próprio = o global
      expect(described_class.official_host?('www.suaotica.com.br')).to be(true)
      expect(described_class.public_root?('www.suaotica.com.br')).to be(true)
      expect(described_class.official_host?('nada.com.br')).to be(false)
    end

    it 'endereço da página no domínio da empresa dona dela; sem conta, como sempre', :aggregate_failures do
      expect(described_class.page_url('oculos-de-sol', account: otica)).to eq('https://www.suaotica.com.br/oculos-de-sol')
      expect(described_class.page_url('refrativa-x', account: cevico)).to eq(described_class.page_url('refrativa-x'))
    end

    it 'hub e rastreio: os da empresa quando preenchidos, senão os globais', :aggregate_failures do
      allow(described_class).to receive(:hub_config).and_return('whatsapp' => '5511900000000', 'tagline' => 'Frase global')
      allow(described_class).to receive(:tracking_config).and_return('meta_pixel_id' => '111', 'ga4_id' => 'G-GLOBAL', 'gtm_id' => 'GTM-X')

      expect(described_class.hub_config_for(otica)).to eq('whatsapp' => '5511988887777', 'tagline' => 'Frase global')
      expect(described_class.hub_config_for(cevico)).to eq('whatsapp' => '5511900000000', 'tagline' => 'Frase global')
      expect(described_class.hub_config_for(nil)).to eq(described_class.hub_config)
      expect(described_class.tracking_config_for(otica)).to eq('meta_pixel_id' => '999', 'ga4_id' => 'G-OTICA1', 'gtm_id' => 'GTM-X')
      expect(described_class.tracking_config_for(cevico)).to eq(described_class.tracking_config)
      expect(described_class.hub_whatsapp_url(otica)).to include('wa.me/5511988887777').and include(ERB::Util.url_encode('Vim do site da Sua Ótica'))
      expect(described_class.hub_whatsapp_url).to include('wa.me/5511900000000').and include(ERB::Util.url_encode('Vim do site da CEVICO'))
    end
  end

  describe 'POST /hub/ref' do
    it 'no domínio da empresa, o Protocolo nasce na conta dela' do
      host! 'www.suaotica.com.br'
      post '/hub/ref', params: { utm_source: 'google' }
      token = response.parsed_body['token']
      expect(CevicoPageRef.find_by(token: token).account).to eq(otica)
    end

    it 'sem host casado, cai no de sempre (conta da primeira página publicada)' do
      host! 'www.example.com'
      post '/hub/ref'
      token = response.parsed_body['token']
      expect(CevicoPageRef.find_by(token: token).account).to eq(CevicoPage.published.order(:id).first.account)
    end
  end

  describe 'GET / (hub)' do
    it 'no domínio da empresa lista só as páginas dela, com o nome e o rastreio dela', :aggregate_failures do
      host! 'www.suaotica.com.br'
      get '/'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Óculos de sol').and include('Sua Ótica')
      expect(response.body).not_to include('Refrativa')
      expect(response.body).not_to include('Cirurgia de Catarata') # portas da clínica não aparecem numa ótica
      expect(response.body).to include('wa.me/5511988887777')
      expect(response.body).to include('999').and include('G-OTICA1')
    end

    # 29/10: a raiz da CLÍNICA (domínio global) é institucional — portas e
    # WhatsApp, sem o catálogo de páginas (guias, variações de anúncio, Biblioteca)
    it 'no domínio da clínica a raiz é institucional e não lista as páginas', :aggregate_failures do
      allow(Cevico::PublicSite).to receive(:host).and_return('clinica.example.com')
      host! 'clinica.example.com'
      get '/'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Miopia').and include('Site institucional').and include('href="/refrativa-x"')
      expect(response.body).not_to include('class="card"')
      expect(response.body).not_to include('Óculos de sol')
    end
  end

  describe 'GET página' do
    it 'a página da empresa responde na raiz do domínio dela e /p/slug redireciona pra lá', :aggregate_failures do
      host! 'www.suaotica.com.br'
      get '/oculos-de-sol'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('G-OTICA1')

      host! 'www.example.com'
      get '/p/oculos-de-sol'
      expect(response).to redirect_to('https://www.suaotica.com.br/oculos-de-sol')
    end

    it 'página da clínica sem host próprio continua respondendo em /p/slug' do
      host! 'www.example.com'
      get '/p/refrativa-x'
      expect(response).to have_http_status(:ok)
    end
  end
end
