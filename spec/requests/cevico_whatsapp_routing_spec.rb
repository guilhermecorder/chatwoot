require 'rails_helper'

# 02/11: WhatsApp POR ORIGEM — o script da página recebe os números por canal
# (Configurações → Domínio) e troca o destino do clique conforme a origem
RSpec.describe 'CEVICO WhatsApp por origem no script das páginas', type: :request do
  let(:account) { create(:account) }
  let!(:page) do
    CevicoPage.create!(account: account, title: 'Guia', slug: 'lasik-ou-prk', status: 'published', category: 'captacao',
                       custom_html: '<html><body><a href="https://wa.me/5511960593996?text=Oi">WhatsApp</a></body></html>',
                       daily_stats: {}, sections: [], team_comments: [])
  end

  after { Cevico::PublicSite.save_hub!({}) }

  it 'desligado (padrão): o script não carrega número nenhum' do
    get "/p/#{page.slug}"

    expect(response.body).to include('var ROUTE = {};')
  end

  it 'ligado: os três números vão para o script, só dígitos', :aggregate_failures do
    saved = Cevico::PublicSite.save_hub!('whatsapp' => '+55 11 96059-3996', 'whatsapp_google' => '5511991651628',
                                         'whatsapp_meta' => '(11) 99808-5773', 'roteamento' => 'true')

    expect(saved).to include('whatsapp' => '5511960593996', 'whatsapp_google' => '5511991651628',
                             'whatsapp_meta' => '5511998085773', 'roteamento' => '1')
    expect(Cevico::PublicSite.whatsapp_routing).to eq('organico' => '5511960593996', 'google' => '5511991651628', 'meta' => '5511998085773')

    get "/p/#{page.slug}"

    expect(response.body).to include('var ROUTE = {"organico":"5511960593996","google":"5511991651628","meta":"5511998085773"};')
    expect(response.body).to include('href = routed(href, trk)')
  end

  it 'chavinha desligada guarda os números mas não roteia' do
    Cevico::PublicSite.save_hub!('whatsapp' => '5511960593996', 'whatsapp_google' => '5511991651628', 'roteamento' => '0')

    expect(Cevico::PublicSite.whatsapp_routing).to be_nil
  end
end
