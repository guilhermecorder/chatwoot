require 'rails_helper'

# 📄 item 353: a tecnologia dos criativos nas páginas — taxas, placar e pódio
RSpec.describe 'Agente de Páginas — placar e pódio' do # rubocop:disable RSpec/DescribeClass
  def row(id, title, views:, cta:, leads:, booked: 0, scroll: nil, seo: nil) # rubocop:disable Metrics/ParameterLists
    { page_id: id, title: title, emoji: '📄', slug: "p#{id}", views: views, cta: cta, leads: leads, booked: booked, conversions: 0,
      revenue: 0.0, scroll: scroll, seo: seo, public_url: "https://x/#{id}" }
  end

  let(:rows) do
    [row(1, 'Refrativa', views: 400, cta: 60, leads: 20, booked: 8, scroll: { '25' => 300, '50' => 240, '75' => 150, '100' => 100 },
                         seo: { title: 'Cirurgia refrativa' }),
     row(2, 'Catarata', views: 200, cta: 10, leads: 2, booked: 0, scroll: { '25' => 100, '50' => 40, '75' => 20, '100' => 10 }),
     row(3, 'Pequena', views: 10, cta: 1, leads: 0)]
  end

  describe Cevico::PageAgent::Rates do
    it 'calcula as taxas com volume mínimo e nil abaixo dele' do
      r = described_class.for(rows[0], { impressions: 1000, ctr: 2.5 })
      expect(r).to include('google' => 0.025, 'reading' => 0.6, 'cta' => 0.15, 'arrival' => 0.3333, 'booking' => 0.4, 'result' => 0.05)
      small = described_class.for(rows[2])
      expect(small.values).to all(be_nil)
      expect(described_class.for(rows[1])).to include('booking' => nil, 'arrival' => 0.2)
    end
  end

  describe Cevico::PageAgent::Scorecard do
    it 'compara com a média e o recorde da casa e lê em frases' do
      averages = Cevico::PageAgent::Rates.for(Cevico::PageAgent::Rates.sum(rows))
      records = { 'cta' => { 'value' => 0.2, 'page_id' => 9, 'page_title' => 'Antiga', 'emoji' => '📄', 'since' => '2026-07-20',
                             'until' => '2026-10-17' },
                  'result' => { 'value' => 0.05, 'page_id' => 1, 'page_title' => 'Refrativa', 'emoji' => '📄', 'since' => '2026-07-20',
                                'until' => '2026-10-17' } }
      card = described_class.new(rates: Cevico::PageAgent::Rates.for(rows[0]), averages: averages, records: records, page_id: 1).call
      cta = card[:indicators].find { |i| i[:key] == 'cta' }
      expect(cta).to include(value: 0.15, verdict: 'good', is_record: false, record: 0.2, record_ad: '📄 Antiga')
      expect(cta[:record_phrase]).to eq('faltam 5 pontos para o recorde')
      result = card[:indicators].find { |i| i[:key] == 'result' }
      expect(result[:is_record]).to be(true)
      expect(card[:radar][:axes].map { |a| a[:key] }).to eq(%w[reading cta arrival booking])
      expect(card[:reading]).to include('Supera a média da casa em').and include('🏆 É o recorde da casa em resultado')
    end
  end

  describe Cevico::PageAgent::Podium do
    it 'monta o pódio de título, corpo e convite só com quem tem volume' do
      podium = described_class.new(rows: rows, gsc: {}, pages: {}).call
      expect(podium[:titulo].map { |i| i[:page_id] }).to eq([1, 2])
      expect(podium[:titulo].first).to include(rank: 1, text: 'Cirurgia refrativa', source: 'leads', value_text: '5,0%')
      expect(podium[:corpo].first).to include(page_id: 1, value_text: '25,0%')
      expect(podium[:convite].first).to include(page_id: 1, text: 'Falar no WhatsApp', value_text: '15,0%')
    end

    it 'usa o Google no título quando há duas páginas com aparições' do
      gsc = { 1 => { impressions: 500, ctr: 3.0, position: 8.2 }, 2 => { impressions: 900, ctr: 6.0, position: 4.1 } }
      podium = described_class.new(rows: rows, gsc: gsc, pages: {}).call
      expect(podium[:titulo].first).to include(page_id: 2, source: 'google', value_text: '6,0%')
    end
  end
end
