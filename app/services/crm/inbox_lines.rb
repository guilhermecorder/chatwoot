# 📈 item 418 (25/11) — MINI GRÁFICOS DE LINHA do Comparativo de caixas.
# Pedido do Guilherme: "eu gostaria de trazer mini dashboards de linha para
# todos os ambientes de caixa… esses gráficos (de cada 100 leads, quantos
# agendam consulta) eu quero que sejam temporizáveis… além de campanhas, um
# ambiente sanfonado para entrar mais no detalhe, com os criativos também".
#
# A MESMA turma do Comparativo (Crm::InboxComparison: contato novo no período,
# caixa de chegada = 1ª conversa numa porta de entrada, agendou = entrou na
# coluna de agendamento), contada em três recortes:
#   caixa → campanha (anúncio do Meta carimbado no contato) → criativo
#
# A linha é MÉDIA MÓVEL, para não virar serrote com pouca gente:
#   até 2 dias   → hora a hora, janela de 24 horas
#   até 45 dias  → dia a dia, janela de 7 dias
#   mais que isso → semana a semana, janela de 4 semanas (o desenho do painel
#                   de criativos de 21/11: "média de 4 semanas")
# Cada ponto = de quem chegou na janela que termina ali, quantos % agendaram.
# Para o primeiro ponto já nascer com a janela cheia, a conta lê também a
# gente que chegou logo ANTES do período (só para a linha; o total do cartão é
# só do período e bate com a tabela "Lado a lado").
# Janela com menos de MIN_BASE pessoas não vira ponto (nunca 0% ou 100% falso).
#
# Só LÊ. Sem dinheiro: é a mesma resposta para todo mundo que vê o relatório.
class Crm::InboxLines < Crm::InboxComparison
  MIN_BASE = 5
  MAX_CAMPAIGNS = 24
  MAX_ADS = 12
  NO_AD = 'Sem anúncio do Meta carimbado'.freeze
  NO_NAME = 'Anúncio do Meta (campanha sem nome)'.freeze
  REGIMES = {
    hora: { janela: 24, texto: 'média móvel de 24 horas', passo: 'hora a hora' },
    dia: { janela: 7, texto: 'média móvel de 7 dias', passo: 'dia a dia' },
    semana: { janela: 4, texto: 'média móvel de 4 semanas', passo: 'semana a semana' }
  }.freeze

  # marks = os marcos de teste da conta (Crm::AttendanceMilestones.list): os que
  # caem dentro da linha voltam com a posição do ponto, para a tela desenhar 📍
  def initialize(account:, since:, until_at:, compare:, now: Time.current, marks: []) # rubocop:disable Metrics/ParameterLists
    super(account: account, since: since, until_at: until_at, compare: compare, invest: nil, now: now)
    @marks = Array(marks)
    days = ((until_at - since) / 86_400).ceil
    @regime = if days <= 2
                :hora
              else
                days <= 45 ? :dia : :semana
              end
    @window = REGIMES[@regime][:janela]
  end

  def call
    @starts = bucket_starts
    @index = @starts.each_with_index.to_h { |start, i| [start.to_i, i] }
    @lead = @window - 1
    tally = tally_now
    before = tally_before
    {
      periodo: { de: @since.iso8601, ate: @until_at.iso8601, datas: range_label(@since, @until_at) },
      comparacao: @compare.to_h,
      regime: REGIMES[@regime].merge(balde: @regime.to_s, minimo: MIN_BASE),
      rotulos: @starts.drop(@lead).map { |start| start_label(start) },
      marcos: marks_json,
      caixas: inbox_rows(tally[:inboxes], before[:inboxes]),
      **campaign_rows(tally[:campaigns], before[:campaigns])
    }
  end

  private

  # ── os baldes: da folga (janela − 1) antes do período até agora ──────────
  def bucket_starts
    first = floor(@since.in_time_zone(TZ))
    last = floor([@until_at, @now].min.in_time_zone(TZ))
    list = (1..(@window - 1)).map { |back| step(first, -back) }.reverse
    cursor = first
    while cursor <= last
      list << cursor
      cursor = step(cursor, 1)
    end
    list
  end

  def floor(time)
    case @regime
    when :hora then time.beginning_of_hour
    when :dia then time.beginning_of_day
    else time.beginning_of_week
    end
  end

  def step(time, count)
    case @regime
    when :hora then time + count.hours
    when :dia then time + count.days
    else time + count.weeks
    end
  end

  def start_label(start)
    @regime == :hora ? start.strftime('%d/%m %Hh') : start.strftime('%d/%m')
  end

  # 📍 item 419: os marcos que caem dentro da linha, com o ponto em que ficam
  # (pos = índice do ponto visível cujo balde contém o instante do marco)
  def marks_json
    visible = @starts.drop(@lead)
    @marks.filter_map { |mark| mark_json(mark, visible) }
  end

  def mark_json(mark, visible)
    at = Crm::AttendanceMilestones.parse(mark['at'])&.in_time_zone(TZ)
    pos = at && visible.rindex { |start| start <= at }
    return if pos.nil? || at >= step(visible.last, 1)

    { id: mark['id'], titulo: mark['title'], quando: at.strftime('%d/%m %Hh%M'), pos: pos, inbox_ids: Array(mark['inbox_ids']).map(&:to_i) }
  end

  # ── a turma de agora (com a folga), em cada recorte ──────────────────────
  # serie = { a: [chegaram por balde, com folga], b: [agendaram], n: chegaram no período, k: agendaram no período,
  #           v: [chegaram por balde, só do período] }
  def blank_series
    { a: Array.new(@starts.size, 0), b: Array.new(@starts.size, 0), v: Array.new(@starts.size, 0), n: 0, k: 0 }
  end

  def tally_now # rubocop:disable Metrics/AbcSize
    cohort = entry_cohort(@starts.first, @until_at)
    booked = first_stage_entry(booking_stage_ids, cohort.keys, @starts.first, @now)
    ads = ad_ids_of(cohort.keys)
    @creatives = creatives_for(ads.values.uniq)
    inboxes = Hash.new { |hash, key| hash[key] = blank_series }
    campaigns = Hash.new { |hash, key| hash[key] = blank_series.merge(inboxes: Hash.new(0), ads: Hash.new { |h, k| h[k] = blank_series }) }
    cohort.each do |contact_id, (inbox_id, created_at)|
      idx = @index[floor(created_at.in_time_zone(TZ)).to_i]
      next if idx.nil?

      inside = created_at >= @since
      hit = booked.key?(contact_id)
      ad_id = ads[contact_id]
      campaign = campaigns[campaign_key(inbox_id, ad_id)]
      [inboxes[inbox_id], campaign, (campaign[:ads][ad_id] if ad_id)].compact.each { |series| add(series, idx, hit, inside) }
      campaign[:inboxes][inbox_id] += 1 if inside
    end
    { inboxes: inboxes, campaigns: campaigns }
  end

  def add(series, idx, hit, inside)
    series[:a][idx] += 1
    series[:b][idx] += 1 if hit
    return unless inside

    series[:v][idx] += 1
    series[:n] += 1
    series[:k] += 1 if hit
  end

  # campanha = o nome dela na Central de Criativos; sem anúncio carimbado, a
  # turma fica separada por caixa (Google e orgânico não se misturam)
  def campaign_key(inbox_id, ad_id)
    return [:sem, inbox_id] if ad_id.nil?

    [:campanha, @creatives.dig(ad_id, :campaign).presence || NO_NAME]
  end

  def creatives_for(ad_ids)
    return {} if ad_ids.empty?

    Crm::AdCreative.where(account_id: account.id, ad_id: ad_ids).pluck(:ad_id, :ad_name, :campaign_name)
                   .to_h { |ad_id, ad_name, campaign| [ad_id, { name: ad_name, campaign: campaign }] }
  end

  # ── a base de comparação: a mesma conta, com a mesma folga de tempo ──────
  # { inboxes: { id => [chegaram, agendaram] }, campaigns: { chave => { total: [..], ads: { ad_id => [..] } } } }
  def tally_before # rubocop:disable Metrics/AbcSize
    slack = [@now - @until_at, 0].max
    cohort = entry_cohort(@compare.since, @compare.until_at)
    booked = first_stage_entry(booking_stage_ids, cohort.keys, @compare.since, [@compare.until_at + slack, @now].min)
    ads = ad_ids_of(cohort.keys)
    @creatives = creatives_for((ads.values + @creatives.keys).uniq)
    inboxes = Hash.new { |hash, key| hash[key] = [0, 0] }
    campaigns = Hash.new { |hash, key| hash[key] = { total: [0, 0], ads: Hash.new { |h, k| h[k] = [0, 0] } } }
    cohort.each do |contact_id, (inbox_id, _)|
      ad_id = ads[contact_id]
      campaign = campaigns[campaign_key(inbox_id, ad_id)]
      [inboxes[inbox_id], campaign[:total], (campaign[:ads][ad_id] if ad_id)].compact.each do |pair|
        pair[0] += 1
        pair[1] += 1 if booked.key?(contact_id)
      end
    end
    { inboxes: inboxes, campaigns: campaigns }
  end

  # ── o JSON ───────────────────────────────────────────────────────────────
  def series_json(series, before) # rubocop:disable Metrics/AbcSize
    visible = (@lead...@starts.size)
    line = visible.map do |i|
      arrived = series[:a][(i - @lead)..i].sum
      arrived >= MIN_BASE ? (series[:b][(i - @lead)..i].sum * 100.0 / arrived).round(1) : nil
    end
    { chegaram: series[:n], agendaram: series[:k], taxa: series[:n].positive? ? (series[:k] * 100.0 / series[:n]).round(1) : nil,
      linha: line, chegaram_por: visible.map { |i| series[:v][i] },
      anterior: { chegaram: before.to_a[0].to_i, agendaram: before.to_a[1].to_i } }
  end

  def inbox_rows(inboxes, before)
    rows = inboxes.select { |_, series| series[:n].positive? }.map do |inbox_id, series|
      { inbox_id: inbox_id, nome: inbox_names[inbox_id] || 'Caixa removida', porta: capture_inbox_ids.include?(inbox_id) }
        .merge(series_json(series, before[inbox_id]))
    end
    rows.sort_by { |row| [row[:porta] ? 0 : 1, -row[:chegaram], row[:nome].to_s] }
  end

  # { campanhas: [...], campanhas_fora: quantas ficaram de fora da lista }
  def campaign_rows(campaigns, before) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    rows = campaigns.select { |_, series| series[:n].positive? }.map do |key, series|
      past = before.key?(key) ? before[key] : { total: nil, ads: {} }
      main = series[:inboxes].max_by { |inbox_id, count| [count, -inbox_id.to_i] }&.first
      { chave: key.join(':'), nome: campaign_name(key), meta: key.first == :campanha, caixa_id: main,
        caixas: series[:inboxes].sort_by { |_, count| -count }.map { |inbox_id, count| { inbox_id: inbox_id, chegaram: count } } }
        .merge(series_json(series, past[:total])).merge(ad_rows(series[:ads], past[:ads]))
    end
    rows = rows.sort_by { |row| [-row[:chegaram], -row[:agendaram], row[:nome]] }
    { campanhas: rows.first(MAX_CAMPAIGNS), campanhas_fora: [rows.size - MAX_CAMPAIGNS, 0].max }
  end

  def campaign_name(key)
    key.first == :campanha ? key.last : "#{NO_AD} · #{inbox_names[key.last] || 'Caixa removida'}"
  end

  def ad_rows(ads, before)
    rows = ads.select { |_, series| series[:n].positive? }.map do |ad_id, series|
      { ad_id: ad_id, nome: @creatives.dig(ad_id, :name).presence || "Anúncio #{ad_id}" }.merge(series_json(series, before[ad_id]))
    end
    rows = rows.sort_by { |row| [-row[:chegaram], -row[:agendaram], row[:nome]] }
    { criativos: rows.first(MAX_ADS), criativos_fora: [rows.size - MAX_ADS, 0].max }
  end
end
