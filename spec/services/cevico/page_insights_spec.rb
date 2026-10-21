require 'rails_helper'

# 💡 item 329 (05/10): diagnósticos automáticos das páginas — onde o funil
# vaza, comparado com a média das próprias páginas e só com volume mínimo.
RSpec.describe Cevico::PageInsights do
  def row(attrs = {})
    { page_id: 1, title: 'Catarata', slug: 'catarata', emoji: '👁️', status: 'published', views: 0, cta: 0, leads: 0, booked: 0,
      conversions: 0, revenue: 0.0, sources: {}, scroll: {}, age_days: 60,
      seo: { title: 'Cirurgia de catarata em São Paulo', description: 'a' * 100, keywords: %w[catarata] } }.merge(attrs)
  end

  def bucket(views, cta = 0, leads = 0)
    { views: views, cta: cta, leads: leads, booked: 0, conversions: 0, revenue: 0.0 }
  end

  def totals_of(rows)
    %i[views cta leads booked conversions].index_with { |key| rows.sum { |r| r[key] } }
  end

  def insights(rows)
    described_class.new(rows: rows, totals: totals_of(rows)).call
  end

  def rules(rows, page_id = nil)
    insights(rows).select { |i| page_id.nil? || i[:page_id] == page_id }.pluck(:rule)
  end

  it 'aponta a página com muita visita e pouco clique, com a conta do ganho até a média' do
    good = row(page_id: 1, views: 200, cta: 30, leads: 20, booked: 10)
    weak = row(page_id: 2, title: 'PRK', views: 200, cta: 2, leads: 1)
    found = insights([good, weak]).find { |i| i[:rule] == 'cta_baixo' }

    expect(found).to include(page_id: 2, level: 'alerta', gain: '+14 clique(s) no período se chegasse na média')
    expect(found[:evidence]).to include('200 visitas viraram 2 clique(s)', 'média das suas páginas no período é 8%')
    expect(rules([good, weak], 1)).not_to include('cta_baixo')
  end

  it 'não fala nada sem volume mínimo (pouca visita é ruído)' do
    expect(rules([row(views: 12, cta: 0), row(page_id: 2, views: 20, cta: 9, leads: 5)])).to be_empty
  end

  it 'lê a rolagem: sai antes da metade × lê até o fim e não clica' do
    short = row(page_id: 1, views: 100, cta: 10, leads: 6, scroll: { '25' => 60, '50' => 30, '75' => 15, '100' => 8 })
    reads = row(page_id: 2, views: 100, cta: 3, leads: 3, scroll: { '25' => 90, '50' => 70, '75' => 55, '100' => 45 })

    expect(rules([short, reads], 1)).to include('leitura_curta')
    expect(rules([short, reads], 2)).to include('le_e_nao_clica')
  end

  it 'clique que não chega na caixa e lead que não agenda' do
    lost = row(page_id: 1, views: 300, cta: 30, leads: 4, booked: 4)
    cold = row(page_id: 2, views: 300, cta: 30, leads: 20, booked: 2)
    hot = row(page_id: 3, views: 300, cta: 30, leads: 20, booked: 16)

    expect(rules([lost, cold, hot], 1)).to include('protocolo_perdido')
    expect(rules([lost, cold, hot], 2)).to include('lead_nao_agenda')
    expect(rules([lost, cold, hot], 3)).not_to include('protocolo_perdido', 'lead_nao_agenda')
  end

  it 'origem paga sem retorno e origem que converte bem mais do que a página' do
    page = row(views: 200, cta: 20, leads: 8, sources: {
                 'meta_ads' => bucket(120, 2, 0), 'google_organico' => bucket(40, 12, 6), 'direto' => bucket(40, 6, 2)
               })
    list = insights([page])

    paid = list.find { |i| i[:key] == 'p1:anuncio_sem_retorno:meta_ads' }
    standout = list.find { |i| i[:key] == 'p1:origem_destaque:google_organico' }
    expect(paid).to include(level: 'alerta', title: 'Meta Ads: visita paga que não vira lead')
    expect(standout[:title]).to eq('Google orgânico (SEO) converte 3,8 vezes mais nesta página')
  end

  it 'SEO: título, descrição, palavras-chave e nenhuma visita do Google orgânico' do
    page = row(views: 80, cta: 8, leads: 4, seo: { title: 'x' * 75, description: '', keywords: [] }, sources: { 'google_ads' => bucket(80, 8, 4) })
    found = insights([page]).select { |i| i[:level] == 'seo' }

    expect(found.pluck(:rule)).to contain_exactly('seo_titulo', 'seo_descricao', 'seo_palavras', 'seo_sem_organico')
    expect(found.find { |i| i[:rule] == 'seo_titulo' }[:title]).to eq('Título do Google longo demais (75 letras)')
    # rascunho e a porta de entrada (hub) não entram
    expect(insights([page.merge(status: 'draft')]).pluck(:level)).not_to include('seo')
    expect(insights([page.merge(page_id: nil)])).to be_empty
  end

  it 'publicada sem visita (há mais de uma semana) e a página campeã; os vazamentos vêm primeiro' do
    idle = row(page_id: 3, title: 'Parada', idle: true)
    fresh = row(page_id: 4, title: 'Nova', idle: true, age_days: 2)
    best = row(page_id: 1, views: 100, cta: 20, leads: 12, booked: 6)
    weak = row(page_id: 2, views: 100, cta: 1, leads: 0)
    list = insights([best, weak, idle, fresh])

    expect(list.find { |i| i[:rule] == 'sem_visita' }).to include(page_id: 3)
    expect(list.count { |i| i[:rule] == 'sem_visita' }).to eq(1)
    expect(list.find { |i| i[:rule] == 'campea' }).to include(page_id: 1, level: 'oportunidade')
    expect(list.first[:level]).to eq('alerta')
  end

  # 🔎 16/10: Search Console (o que acontece ANTES da visita)
  describe 'Search Console' do
    def gsc_page(page_id, impressions, clicks, position, terms = [])
      { page_id: page_id, url: "https://clinica.cevico.com.br/p#{page_id}", impressions: impressions, clicks: clicks,
        ctr: (clicks * 100.0 / impressions).round(2), position: position, terms: terms }
    end

    def term(query, clicks, impressions, position, page_ids: [], urls: ['https://www.cevico.com.br/x/']) # rubocop:disable Metrics/ParameterLists
      { query: query, clicks: clicks, impressions: impressions, position: position, page_ids: page_ids, urls: urls }
    end

    def gsc(pages, terms = [])
      { ready: true, pages: pages, terms: terms, totals: { 'current' => { 'clicks' => 50, 'impressions' => 2000 } } }
    end

    def gsc_rules(rows, search_console)
      described_class.new(rows: rows, totals: totals_of(rows), search_console: search_console).call
    end

    let(:pages) { [row(page_id: 1), row(page_id: 2, title: 'PRK', slug: 'prk', seo: { title: 'PRK', description: 'a' * 100, keywords: [] })] }

    it 'aparece muito e ninguém clica (só na 1ª página do Google), com o termo mais buscado na evidência' do
      low = gsc_page(1, 2400, 14, 6.4, [{ query: 'cirurgia de catarata', impressions: 900, position: 6.0 }])
      list = gsc_rules(pages, gsc([low, gsc_page(2, 1200, 60, 4.0)]))
      found = list.find { |i| i[:rule] == 'gsc_ctr_baixo' }

      expect(found).to include(page_id: 1, level: 'seo')
      expect(found[:evidence]).to include('2400 aparições', '"cirurgia de catarata" (900)')
      expect(found[:gain]).to start_with('+')
      expect(list.pluck(:rule)).not_to include('gsc_quase_topo')
    end

    it 'posição 8 a 20 com volume vira "quase na 1ª página"; abaixo do volume mínimo, silêncio' do
      near = gsc_page(2, 420, 5, 12.3, [{ query: 'prk ou lasik', impressions: 160, position: 11.4 }])

      expect(gsc_rules(pages, gsc([near])).find { |i| i[:rule] == 'gsc_quase_topo' }).to include(page_id: 2)
      expect(gsc_rules(pages, gsc([gsc_page(2, 12, 0, 12.0)])).pluck(:rule)).not_to include('gsc_quase_topo')
    end

    it 'termo com clique sem página dona sugere página nova; marca e termo de página existente, não' do
      terms = [term('ceratocone tratamento', 8, 240, 10.1), term('cevico', 96, 500, 1.2),
               term('catarata recuperação', 9, 270, 5.2, page_ids: [1]), term('miopia grau', 1, 50, 9.0)]
      found = gsc_rules(pages, gsc([], terms)).select { |i| i[:rule] == 'gsc_termo_sem_pagina' }

      expect(found.size).to eq(1)
      expect(found.first).to include(page_id: nil, title: '"ceratocone tratamento" traz clique e não tem página própria')
    end

    it 'sem foto do Search Console, nenhum diagnóstico do Google' do
      expect(gsc_rules(pages, { ready: false }).pluck(:rule).grep(/gsc/)).to be_empty
    end
  end
end
