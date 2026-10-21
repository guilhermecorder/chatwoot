# 🔎 Search Console (16/10).
#   ACCOUNT_ID=1 bundle exec rake cevico:search_console_sync   foto nova agora (o mesmo do botão "Atualizar agora")
#   ACCOUNT_ID=3 bundle exec rake cevico:search_console_demo   dados de EXEMPLO (só fora da produção) para ver a tela
#   ACCOUNT_ID=3 CLEAR=1 bundle exec rake cevico:search_console_demo   apaga a foto de exemplo
namespace :cevico do # rubocop:disable Metrics/BlockLength
  desc 'Busca agora no Google Search Console a foto dos últimos 28 dias (impressões, cliques, CTR, posição, termos)'
  task search_console_sync: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID', 1))
    result = Cevico::SearchConsole.new(account).sync!
    puts result[:ok] ? "OK: #{result[:pages]} página(s), #{result[:terms]} termo(s) guardados." : "ERRO: #{result[:error]}"
  end

  desc 'Grava uma foto de EXEMPLO do Search Console para ver a tela no local (recusa em produção)'
  task search_console_demo: :environment do # rubocop:disable Metrics/BlockLength
    abort 'Recusado: dados de exemplo não entram em produção.' if Rails.env.production?

    account = Account.find(ENV.fetch('ACCOUNT_ID', 3))
    key = Cevico::SearchConsole::CACHE_KEY
    if ENV['CLEAR'] == '1'
      Cevico::SettingMerge.merge!(account, :google_ads_config) { |cfg| cfg.except(key) }
      next puts('Foto de exemplo apagada.')
    end

    published = account.cevico_pages.where(status: 'published').order(:id).to_a
    preferred = %w[refrativa catarata demo-construtor-v2].filter_map { |slug| published.find { |pg| pg.slug == slug } }
    pages = (preferred + (published - preferred)).first(4)
    abort 'A conta não tem página publicada para servir de exemplo.' if pages.empty?

    url = ->(page) { Cevico::PublicSite.page_url(page.slug, account: account) }
    # [cliques, impressões, posição] atual e [cliques, impressões, posição] anterior, por página
    shapes = [[14, 2400, 6.4, 9, 1700, 8.1], [61, 1350, 3.9, 40, 1100, 4.6], [5, 420, 12.3, 2, 260, 17.8], [1, 90, 24.0, nil, nil, nil]]
    term_sets = [
      [['cirurgia refrativa sao paulo', 4, 980, 7.2, 9.4], ['cirurgia para miopia', 3, 610, 6.0, 8.8],
       ['quanto custa cirurgia refrativa', 2, 330, 8.9, 11.2], ['lasik', 1, 290, 14.5, nil]],
      [['cirurgia de catarata', 28, 520, 3.1, 3.5], ['lente trifocal catarata', 17, 330, 2.8, 3.9],
       ['catarata recuperacao', 9, 270, 5.2, 6.0]],
      [['prk ou lasik', 2, 160, 11.4, 16.0], ['prk recuperacao', 2, 120, 9.8, 14.1], ['prk doi', 1, 90, 15.2, nil]],
      [['pagina em teste', 1, 40, 22.0, nil]]
    ]
    rows = []
    terms = []
    pages.each_with_index do |page, i|
      c, imp, pos, pc, pimp, ppos = shapes[i]
      prev = pc && { 'clicks' => pc, 'impressions' => pimp, 'ctr' => (pc * 100.0 / pimp).round(2), 'position' => ppos }
      rows << { 'url' => url.call(page), 'clicks' => c, 'impressions' => imp, 'ctr' => (c * 100.0 / imp).round(2),
                'position' => pos, 'previous' => prev }
      term_sets[i].each do |q, tc, timp, tpos, tprev|
        terms << { 'url' => url.call(page), 'query' => q, 'clicks' => tc, 'impressions' => timp,
                   'ctr' => (tc * 100.0 / timp).round(2), 'position' => tpos, 'previous_position' => tprev }
      end
    end
    # o site do WordPress (domínio inteiro) e um termo sem página própria
    wp = [['https://www.cevico.com.br/', 120, 900, 1.8, 'cevico', 96, 500, 1.2],
          ['https://www.cevico.com.br/ceratocone/', 11, 380, 9.6, 'ceratocone tratamento', 8, 240, 10.1]]
    wp.each do |u, c, imp, pos, q, tc, timp, tpos| # rubocop:disable Metrics/ParameterLists
      rows << { 'url' => u, 'clicks' => c, 'impressions' => imp, 'ctr' => (c * 100.0 / imp).round(2), 'position' => pos, 'previous' => nil }
      terms << { 'url' => u, 'query' => q, 'clicks' => tc, 'impressions' => timp, 'ctr' => (tc * 100.0 / timp).round(2),
                 'position' => tpos, 'previous_position' => nil }
    end

    win = Cevico::SearchConsole.new(account).windows
    clicks = rows.sum { |r| r['clicks'] }
    impressions = rows.sum { |r| r['impressions'] }
    prev_clicks = rows.sum { |r| r.dig('previous', 'clicks').to_i } + 95
    prev_impr = rows.sum { |r| r.dig('previous', 'impressions').to_i } + 1000
    daily = (win[:previous][0]..win[:current][1]).each_with_index.map do |day, i|
      [day.iso8601, ((clicks / 28.0 * (0.6 + (i / 56.0))) + (i % 7 == 5 ? -3 : 0)).round.clamp(0, 999),
       (impressions / 28.0 * (0.55 + (i / 50.0))).round]
    end
    snapshot = {
      'demo' => true, 'site' => Cevico::SearchConsole::DEFAULT_SITE, 'fetched_at' => Time.current.iso8601,
      'window' => { 'since' => win[:current][0].iso8601, 'until' => win[:current][1].iso8601 },
      'previous_window' => { 'since' => win[:previous][0].iso8601, 'until' => win[:previous][1].iso8601 },
      'totals' => {
        'current' => { 'clicks' => clicks, 'impressions' => impressions, 'ctr' => (clicks * 100.0 / impressions).round(2), 'position' => 7.9 },
        'previous' => { 'clicks' => prev_clicks, 'impressions' => prev_impr, 'ctr' => (prev_clicks * 100.0 / prev_impr).round(2), 'position' => 9.6 }
      },
      'pages' => rows, 'terms' => terms, 'daily' => daily
    }
    Cevico::SettingMerge.merge_key!(account, :google_ads_config, key) { |_old| snapshot }
    puts "Foto de exemplo gravada na conta #{account.id}: #{rows.size} endereço(s), #{terms.size} termo(s)."
  end
end
