# 🌅 A RODADA DIÁRIA do Agente de Páginas (item 353): de manhã, depois da
# foto do Search Console, lê os últimos 7 dias das páginas contra a média das
# próprias páginas (Cevico::PageInsights — as mesmas regras da aba Otimizar),
# grava os pontos a melhorar como RECOMENDAÇÕES (mesma fila do Agente de
# Campanhas, canal "pages"), expira as velhas, aprende com as aplicadas
# (antes × depois pela visita → clique → lead da própria página), guarda o
# resumo para o Meu Painel e abre uma tarefa para o administrador.
class Cevico::PageAgent::Daily
  STATE_KEY = 'page_agent_state'.freeze
  CHANNEL = 'pages'.freeze
  WINDOW_DAYS = 7
  EXPIRE_DAYS = 14
  SERIES_DAYS = 14
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  KINDS = { 'cta_baixo' => 'page', 'leitura_curta' => 'content', 'le_e_nao_clica' => 'page', 'protocolo_perdido' => 'page',
            'lead_nao_agenda' => 'quality', 'anuncio_sem_retorno' => 'traffic', 'origem_destaque' => 'traffic', 'sem_visita' => 'traffic',
            'campea' => 'watch', 'seo_titulo' => 'seo', 'seo_descricao' => 'seo', 'seo_palavras' => 'seo', 'seo_sem_organico' => 'seo',
            'gsc_ctr_baixo' => 'seo', 'gsc_quase_topo' => 'content', 'gsc_termo_sem_pagina' => 'content' }.freeze

  def initialize(account:, today: TZ.today)
    @account = account
    @today = today
  end

  def self.state(account)
    (CrmSetting.find_by(account: account)&.agenda_config || {})[STATE_KEY] || {}
  end

  def call(force: false) # rubocop:disable Metrics/AbcSize
    return { skipped: 'já rodou hoje' } if !force && self.class.state(@account)['last_run_date'] == @today.iso8601

    expired = expire_old
    insights = Cevico::PageInsights.new(rows: report.rows_with_idle, totals: report.totals, search_console: search_console).call
    created = persist(insights)
    learned = Cevico::PageAgent::Learning.new(account: @account, today: @today).call
    open_count = Crm::CampaignAction.where(account_id: @account.id, channel: CHANNEL, status: 'suggested').count
    task = open_task(created.size, open_count)
    write_state('last_run_date' => @today.iso8601, 'last_run_at' => Time.current.iso8601, 'new' => created.size, 'open' => open_count,
                'learned' => learned, 'expired' => expired, 'summary' => summary, 'series' => series, 'champion' => champion,
                'top' => created.first(3).map { |a| a.slice(:title, :severity, :ref_name, :kind) }, 'task_opened' => task)
    { ok: true, new: created.size, learned: learned, expired: expired, open: open_count }
  end

  # os números de uma página numa janela (o "antes" de cada recomendação)
  def self.snapshot(row, from, to)
    views = row[:views].to_i
    { 'views' => views, 'cta' => row[:cta].to_i, 'leads' => row[:leads].to_i, 'booked' => row[:booked].to_i,
      'click_rate' => views.positive? ? (row[:cta].to_f / views).round(4) : nil,
      'lead_rate' => views.positive? ? (row[:leads].to_f / views).round(4) : nil,
      'since' => from.iso8601, 'until' => to.iso8601 }
  end

  private

  def since
    @today - WINDOW_DAYS
  end

  def report
    @report ||= Cevico::TrafficReport.new(@account, since, @today - 1)
  end

  def search_console
    @search_console ||= begin
      data = Cevico::SearchConsoleReport.new(@account).call
      data.is_a?(Hash) && data[:ready] ? data : nil
    rescue StandardError
      nil
    end
  end

  def rows_by_id
    @rows_by_id ||= report.rows_with_idle.select { |r| r[:page_id] }.index_by { |r| r[:page_id] }
  end

  def expire_old
    Crm::CampaignAction.where(account_id: @account.id, channel: CHANNEL, status: 'suggested')
                       .where('suggested_on < ?', @today - EXPIRE_DAYS)
                       .update_all(status: 'expired', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def persist(insights) # rubocop:disable Metrics/AbcSize
    keys = insights.pluck(:key)
    open_keys = Crm::CampaignAction.where(account_id: @account.id, key: keys, status: Crm::CampaignAction::OPEN).pluck(:key).to_set
    dismissed = Crm::CampaignAction.where(account_id: @account.id, key: keys, status: 'dismissed').where('decided_at >= ?',
                                                                                                         7.days.ago).pluck(:key).to_set
    insights.reject { |i| open_keys.include?(i[:key]) || dismissed.include?(i[:key]) }.filter_map do |insight|
      attrs = attributes_for(insight)
      Crm::CampaignAction.create!(attrs.merge(account_id: @account.id, status: 'suggested', suggested_on: @today))
      attrs
    rescue StandardError => e
      Rails.logger.error "[CEVICO páginas] não gravou a sugestão #{insight[:key]}: #{e.message}"
      nil
    end
  end

  def attributes_for(insight)
    row = rows_by_id[insight[:page_id]]
    { channel: CHANNEL, level: insight[:page_id] ? 'page' : 'termo', ref_id: (insight[:page_id] || insight[:key]).to_s,
      ref_name: insight[:page_title], rule: insight[:rule], kind: KINDS.fetch(insight[:rule], 'page'),
      severity: insight[:level], key: insight[:key], title: insight[:title], evidence: insight[:evidence],
      suggestion: insight[:suggestion], expected: insight[:gain],
      payload: { 'slug' => insight[:slug], 'emoji' => insight[:emoji], 'weight' => insight[:weight], 'window_days' => WINDOW_DAYS },
      metrics_before: row ? self.class.snapshot(row, since, @today - 1) : {} }
  end

  # janela de 7 dias × média das próprias páginas (90 dias)
  def summary
    t = report.totals
    avg = Cevico::PageAgent::Records.new(account: @account, until_date: @today - 1).call[:averages]
    { 'views' => t[:views], 'cta' => t[:cta], 'leads' => t[:leads], 'booked' => t[:booked], 'conversions' => t[:conversions],
      'click_rate' => rate(t[:cta], t[:views]), 'lead_rate' => rate(t[:leads], t[:views]), 'booking_rate' => rate(t[:booked], t[:leads]),
      'avg_click_rate' => avg['cta'], 'avg_lead_rate' => avg['result'], 'avg_booking_rate' => avg['booking'],
      'window_days' => WINDOW_DAYS, 'baseline_days' => Cevico::PageAgent::Records::DAYS }
  end

  # 14 dias de visitas, cliques e leads de todas as páginas (a linha do Meu Painel)
  def series # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    from = @today - SERIES_DAYS
    to = @today - 1
    traffic = @account.cevico_page_traffic.where(date: from..to).group(:date).pluck(:date, Arel.sql('SUM(views)'),
                                                                                    Arel.sql('SUM(cta_clicks)')).to_h do |d, v, c|
      [d, [v, c]]
    end
    leads = @account.contacts
                    .where("additional_attributes -> 'page_ads' ->> 'source' IS NOT NULL")
                    .where("(additional_attributes -> 'page_ads' ->> 'captured_at')::timestamptz BETWEEN ? AND ?",
                           from.beginning_of_day, to.end_of_day)
                    .pluck(Arel.sql("additional_attributes -> 'page_ads' ->> 'captured_at'"))
                    .each_with_object(Hash.new(0)) { |at, h| h[Time.zone.parse(at.to_s)&.to_date] += 1 }
    dates = (from..to).to_a
    { 'labels' => dates.map { |d| d.strftime('%d/%m') }, 'views' => dates.map { |d| traffic.dig(d, 0).to_i },
      'cta' => dates.map { |d| traffic.dig(d, 1).to_i }, 'leads' => dates.map { |d| leads[d].to_i } }
  end

  # a página campeã da janela (mais leads por visita com volume)
  def champion
    best = report.rows.select { |r| r[:page_id] && r[:views].to_i >= Cevico::PageAgent::Rates::MIN_VIEWS && r[:leads].to_i >= 3 }
                 .max_by { |r| r[:leads].to_f / r[:views] }
    return nil if best.nil?

    { 'page_id' => best[:page_id], 'title' => best[:title], 'emoji' => best[:emoji], 'slug' => best[:slug], 'views' => best[:views],
      'leads' => best[:leads], 'lead_rate' => rate(best[:leads], best[:views]) }
  end

  def open_task(new_count, open_count)
    return false if new_count.zero?

    title = "📄 Páginas: #{open_count} ponto(s) a melhorar esperando seu ok — #{@today.strftime('%d/%m')}"
    return false if @account.tasks.exists?(title: title)

    admin = @account.administrators.first
    return false if admin.nil?

    @account.tasks.create!(
      title: title, task_type: 'gestao', priority: :medium, status: :todo, due_at: TZ.now.end_of_day, creator: admin, assignee: admin,
      description: "O Agente de Páginas leu os últimos #{WINDOW_DAYS} dias contra a média das próprias páginas e deixou #{new_count} " \
                   'recomendação(ões) nova(s) em Marketing → Análise de Páginas. Nada muda na página sem o seu ok.'
    )
    true
  rescue StandardError => e
    Rails.logger.error "[CEVICO páginas] tarefa falhou conta=#{@account.id}: #{e.message}"
    false
  end

  def rate(part, total)
    total.to_i.positive? ? (part.to_f / total.to_i).round(4) : nil
  end

  def write_state(patch)
    settings = CrmSetting.find_or_create_by!(account: @account)
    Cevico::SettingMerge.merge_key!(settings, :agenda_config, STATE_KEY) { |h| (h || {}).merge(patch.deep_stringify_keys) }
  end
end
