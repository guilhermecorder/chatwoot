require 'rails_helper'

# 🧠 item 329 (05/10): sugestões da IA para otimizar uma página — o que vai
# para a IA (textos da página + números + diagnósticos) e o que volta.
RSpec.describe Crm::PageOptimizerService do
  let(:account) { create(:account) }
  let(:page) do
    CevicoPage.create!(account: account, title: 'Catarata', slug: 'catarata-teste', status: 'published', category: 'captacao',
                       meta_title: 'Cirurgia de catarata', cta_label: 'Falar no WhatsApp',
                       sections: [{ 'type' => 'hero', 'title' => 'Volte a enxergar com nitidez', 'color' => '#0F5FA6',
                                    'image_url' => '/rails/blob/1.png', 'items' => [{ 'text' => 'Recuperação rápida' }] }])
  end
  let(:row) do
    { views: 200, cta: 6, leads: 2, booked: 1, conversions: 0, scroll: { '50' => 60, '100' => 20 },
      sources: { 'google_ads' => { views: 150, cta: 5, leads: 2 } } }
  end
  let(:insights) { [{ title: 'Muita visita, pouco clique no WhatsApp', evidence: '200 visitas viraram 6 cliques' }] }
  let(:service) { described_class.new(page: page, row: row, insights: insights, period: '01/09 a 30/09/2026') }
  let(:messages) { double('messages') } # rubocop:disable RSpec/VerifiedDoubles
  let(:answer) do
    { diagnostico: 'O topo não convida ao clique.',
      sugestoes: Array.new(7) { |i| { titulo: "Mudança #{i}", por_que: 'x', pedido: 'y' } } }.to_json
  end

  def enable_ai
    CrmSetting.create!(account: account, ai_config: { 'api_key' => 'sk-teste', 'agents' => { 'pagebuilder' => { 'enabled' => true } } })
    usage = double('usage', input_tokens: 10, output_tokens: 5, cache_creation_input_tokens: 0, cache_read_input_tokens: 0) # rubocop:disable RSpec/VerifiedDoubles
    message = double('message', content: [double('block', type: :text, text: answer)], usage: usage) # rubocop:disable RSpec/VerifiedDoubles
    allow(messages).to receive(:create).and_return(message)
    allow(Anthropic::Client).to receive(:new).and_return(double('client', messages: messages)) # rubocop:disable RSpec/VerifiedDoubles
  end

  it 'sem chave ou com o Construtor pausado, avisa em vez de chamar a IA' do
    expect(service.call[:error]).to include('IA não configurada')
    CrmSetting.create!(account: account, ai_config: { 'api_key' => 'sk-teste' })
    expect(described_class.new(page: page, row: row, insights: [], period: 'x').call[:error]).to include('pausado')
  end

  it 'manda os textos da página, os números e os diagnósticos; devolve no máximo 5 sugestões', :aggregate_failures do
    enable_ai
    result = service.call

    expect(result[:diagnostico]).to eq('O topo não convida ao clique.')
    expect(result[:sugestoes].size).to eq(5)
    expect(messages).to have_received(:create) do |args|
      briefing = args[:messages].first[:content]
      expect(briefing).to include('PÁGINA: Catarata (/catarata-teste) — publicada', 'Título para o Google: Cirurgia de catarata',
                                  '200 visitas → 6 cliques no WhatsApp → 2 leads na caixa → 1 agendaram',
                                  'Leitura: 50% da página = 60 · 100% da página = 20', 'Google Ads: 150 visitas, 5 cliques, 2 leads',
                                  '- Muita visita, pouco clique no WhatsApp: 200 visitas viraram 6 cliques',
                                  '[Seção 1]', 'Volte a enxergar com nitidez', 'Recuperação rápida')
      # cor e caminho de imagem não são texto de página
      expect(briefing).not_to include('#0F5FA6', '/rails/blob')
      expect(args[:system_].first[:text]).to include('Não sugira colocar preço na página', 'Não cite nome de médico')
    end
  end
end
