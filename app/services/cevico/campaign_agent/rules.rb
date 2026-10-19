# 🧠 AS REGRAS do Agente de Campanhas (item 352). Lê a JANELA (os últimos N
# dias fechados) de cada campanha, conjunto e anúncio e compara com a NOSSA
# MÉDIA (Cevico::CampaignAgent::Baselines). Regras simples, sem IA, para a
# pessoa entender e conferir a conta — e cada uma só fala com volume mínimo
# (abaixo disso é ruído, não sinal):
#
#   custo_alto           a estrela-guia (custo por agendamento ou por cirurgia)
#                        está X % acima da nossa média → reduz verba; 2× → pausa
#   sem_resultado        gastou o que a média cobraria por 2 resultados e não
#                        trouxe nenhum → pausa
#   campea               bem abaixo da média com volume → sobe verba um passo
#   fadiga               (anúncio) frequência alta e o CTR caiu vs a janela
#                        anterior → pedir variações ao núcleo criativo
#   ctr_baixo            (anúncio) CTR bem abaixo da média → criativo novo
#   cpm_alto             (conjunto) CPM bem acima da média → rever público/posição
#   pagina_nao_converte  clica muito e vira pouco lead → é a página
#   lead_nao_agenda      lead chega e agenda pouco → público/mensagem + atendimento
#   verba_parada /       ritmo do mês contra a verba combinada do canal
#   verba_acima
#   em_aprendizado       item novo na janela: observar, não mexer
#
# Guardas: item com mudança aplicada há menos de `respect_days` não recebe
# nova sugestão de verba/pausa (fase de aprendizado); regra cuja pontuação
# no aprendizado ficou ruim entra "em observação" (vira aviso, não ação).
class Cevico::CampaignAgent::Rules # rubocop:disable Metrics/ClassLength
  ROW = Cevico::CampaignAgent::Row
  FATIGUE_FREQUENCY = 3.0
  FATIGUE_DROP = 0.7   # CTR caiu para 70 % (ou menos) da janela anterior
  BELOW = 0.6          # "bem abaixo da média" = 60 % dela
  CPM_ABOVE = 1.5
  PACING_LOW = 0.7
  PACING_HIGH = 1.15
  EXPIRE_DAYS = 14

  LABELS = {
    'custo_alto' => 'Custo acima da nossa média', 'sem_resultado' => 'Gasto sem resultado', 'campea' => 'Campeã: vale mais verba',
    'fadiga' => 'Anúncio cansado', 'ctr_baixo' => 'Poucos cliques para tanta exibição', 'cpm_alto' => 'Exibição cara',
    'pagina_nao_converte' => 'Clica e não vira lead', 'lead_nao_agenda' => 'Lead chega e não agenda',
    'verba_parada' => 'Verba parada', 'verba_acima' => 'Verba acima do ritmo', 'em_aprendizado' => 'Em aprendizado'
  }.freeze

  # window: resultado do Reader na janela; previous: o mesmo para a janela anterior
  def initialize(account:, params:, baselines:, window:, previous:, month:, touched: Set.new, observing: Set.new, today: Date.current) # rubocop:disable Metrics/ParameterLists
    @account = account
    @p = params
    @baselines = baselines
    @window = window
    @previous = previous
    @month = month
    @touched = touched
    @observing = observing
    @today = today
    @window_days = params['window_days'].to_i
  end

  def call
    return [] if @p['weekend'] && (@today.saturday? || @today.sunday?)

    list = []
    @window[:campaigns].each { |campaign| list.concat(campaign_rules(campaign)) }
    list.concat(pacing_rules)
    list.compact.sort_by { |a| -a[:weight] }
  end

  private

  # ── por entidade ───────────────────────────────────────────────────────
  def campaign_rules(campaign)
    return [] if campaign['untracked'] || campaign['status'] != 'ACTIVE'

    out = []
    if campaign['channel'] == 'google'
      out.concat(cost_rules(campaign))
    else
      Array(campaign['children']).each { |adset| out.concat(adset_rules(adset)) }
    end
    out << page_rule(campaign) << booking_rule(campaign)
    out
  end

  def adset_rules(adset)
    return [] if adset['status'] != 'ACTIVE'

    out = cost_rules(adset)
    out << cpm_rule(adset)
    ads = Array(adset['children']).select { |a| a['status'] == 'ACTIVE' }
    ads.each { |ad| out.concat(ad_rules(ad, ads.size)) }
    out
  end

  def ad_rules(row, active_siblings)
    out = []
    fatigue = fatigue_rule(row)
    out << fatigue
    out << ctr_rule(row) if fatigue.nil?
    out << ad_pause_rule(row) if active_siblings >= 2
    out
  end

  # ── custo (a estrela-guia) ─────────────────────────────────────────────
  def cost_rules(row)
    return [learning_rule(row)].compact if new?(row)
    return [] if @touched.include?(row['id'])

    [high_cost_rule(row), no_result_rule(row), champion_rule(row)].compact
  end

  def high_cost_rule(row) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    b = baseline(row)
    return unless b && row['goal_cost'] && row['goal_events'].to_i >= 1 && enough_spend?(row)

    limit = b['goal_cost'] * (1 + (@p['worse_pct'].to_f / 100))
    return unless row['goal_cost'] >= limit

    double = row['goal_cost'] >= b['goal_cost'] * 2
    pause = double
    kind = pause ? 'pause' : 'budget_down'
    budget = budget_change(row, -@p['budget_step_pct'].to_i) unless pause
    title = pause ? "#{goal_cap} 2× acima da nossa média: pausar" : "#{goal_cap} #{pct_over(row['goal_cost'], b['goal_cost'])} acima da nossa média"
    evidence = "#{money(row['spend'])} em #{@window_days} dias trouxeram #{row['goal_events']} #{goal_unit(row['goal_events'])} " \
               "(#{money(row['goal_cost'])} cada). A nossa média de #{b['days']} dias é #{money(b['goal_cost'])}."
    suggestion = if pause
                   'Pausar e levar a verba para o item que está na média ou melhor. ' \
                     'Se quiser insistir, troque o criativo ou o público antes de religar.'
                 else
                   "Reduzir a verba em #{@p['budget_step_pct']}%#{budget_text(budget)} e observar por #{@p['learning_days']} dias."
                 end
    build(row, 'custo_alto', kind, pause ? 'alerta' : 'atencao', title, evidence, suggestion,
          expected: pause ? saving_text(row) : "custo por #{goal_word} de volta para perto de #{money(b['goal_cost'])}",
          payload: (budget || {}).merge('baseline' => b['goal_cost'], 'ratio' => (row['goal_cost'] / b['goal_cost']).round(2)),
          bonus: (row['spend'] / 50).round)
  end

  def no_result_rule(row) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    b = baseline(row)
    return unless row['goal_events'].to_i.zero?

    floor = [@p.dig('min', 'spend').to_f, b && b['goal_cost'] ? b['goal_cost'] * 2 : 0].max
    return unless row['spend'].to_f >= floor && floor.positive?

    evidence = "#{money(row['spend'])} em #{@window_days} dias e nenhum #{goal_word}" \
               "#{b && b['goal_cost'] ? " — na nossa média, esse gasto traria #{(row['spend'] / b['goal_cost']).floor}." : '.'} " \
               "Leads: #{row['leads']}, cliques: #{row['link_clicks']}."
    build(row, 'sem_resultado', 'pause', 'alerta', "Gasto sem #{goal_word}: pausar", evidence,
          'Pausar agora. Antes de religar, confira o que mudou: criativo, público, página ou o atendimento dos leads.',
          expected: "economiza ~#{money(row['spend'] / @window_days)} por dia", payload: { 'baseline' => b&.dig('goal_cost') },
          bonus: (row['spend'] / 50).round)
  end

  def champion_rule(row) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    b = baseline(row)
    return unless b && row['goal_cost'] && row['goal_events'].to_i >= @p.dig('min', 'goal_events').to_i && enough_spend?(row)

    limit = b['goal_cost'] * (1 - (@p['better_pct'].to_f / 100))
    return unless row['goal_cost'] <= limit

    budget = budget_change(row, @p['budget_step_pct'].to_i)
    at_cap = budget && budget['capped']
    over = month_over_budget?(row['channel'])
    severity = over ? 'info' : 'oportunidade'
    evidence = "#{row['goal_events']} #{goal_unit(row['goal_events'])} a #{money(row['goal_cost'])} cada, com #{money(row['spend'])} " \
               "em #{@window_days} dias. A nossa média de #{b['days']} dias é #{money(b['goal_cost'])}."
    suggestion = if over
                   "Está #{pct_under(row['goal_cost'], b['goal_cost'])} melhor que a média, mas a verba do mês do canal já passou do ritmo. " \
                     'Para subir aqui, tire de quem está pior.'
                 else
                   "Subir a verba em #{@p['budget_step_pct']}%#{budget_text(budget)}#{at_cap ? ' (no teto diário)' : ''} " \
                     "e medir por #{@p['learning_days']} dias. " \
                     'Um passo por vez: salto grande reinicia o aprendizado da plataforma.'
                 end
    build(row, 'campea', over ? 'watch' : 'budget_up', severity, "#{pct_under(row['goal_cost'], b['goal_cost'])} mais barata que a nossa média",
          evidence, suggestion, expected: over ? nil : champion_expected(row),
                                payload: (budget || {}).merge('baseline' => b['goal_cost'], 'ratio' => (row['goal_cost'] / b['goal_cost']).round(2)),
                                bonus: row['goal_events'].to_i * 5)
  end

  def ad_pause_rule(row) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return if new?(row) || @touched.include?(row['id'])

    b = baseline(row)
    return unless b && b['goal_cost'] && row['spend'].to_f >= [@p.dig('min', 'spend').to_f, b['goal_cost']].max

    bad = row['goal_events'].to_i.zero? || (row['goal_cost'] && row['goal_cost'] >= b['goal_cost'] * 2)
    return unless bad

    evidence = "#{money(row['spend'])} em #{@window_days} dias, #{row['goal_events']} #{goal_unit(row['goal_events'])}" \
               "#{row['goal_cost'] ? " (#{money(row['goal_cost'])} cada)" : ''}. A nossa média é #{money(b['goal_cost'])}. " \
               'O conjunto tem outros anúncios ativos para receber a verba.'
    build(row, 'custo_alto', 'pause', 'atencao', 'Anúncio puxando o custo para cima: pausar', evidence,
          'Pausar este anúncio; a verba do conjunto vai sozinha para os irmãos que convertem.',
          expected: saving_text(row), payload: { 'baseline' => b['goal_cost'] }, bonus: (row['spend'] / 50).round)
  end

  # ── secundários ────────────────────────────────────────────────────────
  def fatigue_rule(row) # rubocop:disable Metrics/CyclomaticComplexity
    return unless row['impressions'].to_i >= @p.dig('min', 'impressions').to_i && row['frequency'].to_f >= FATIGUE_FREQUENCY

    prev = previous_row(row)
    ctr = row.dig('rates', 'ctr')
    prev_ctr = prev&.dig('rates', 'ctr')
    return unless ctr && prev_ctr&.positive? && ctr <= prev_ctr * FATIGUE_DROP

    evidence = "Frequência #{num(row['frequency'])} (cada pessoa viu ~#{num(row['frequency'])} vezes) e o CTR caiu de #{pct(prev_ctr)} " \
               "para #{pct(ctr)} em relação aos #{@window_days} dias anteriores."
    build(row, 'fadiga', 'new_creative', 'atencao', 'Anúncio cansado: pedir variações', evidence,
          'Pedir ao núcleo criativo 2 ou 3 variações (gancho novo, mesma promessa) e trocar; enquanto isso, reduzir a verba do conjunto.',
          expected: 'CTR de volta ao nível de antes', payload: { 'ctr' => ctr, 'ctr_before' => prev_ctr, 'frequency' => row['frequency'] }, bonus: 20)
  end

  def ctr_rule(row)
    b = baseline(row)
    ctr = row.dig('rates', 'ctr')
    return unless b&.dig('rates', 'ctr')&.positive? && ctr && row['impressions'].to_i >= @p.dig('min', 'impressions').to_i
    return unless ctr <= b.dig('rates', 'ctr') * BELOW

    evidence = "#{fmt(row['impressions'])} exibições e #{fmt(row['link_clicks'])} cliques (CTR #{pct(ctr)}). A nossa média é #{pct(b.dig('rates',
                                                                                                                                         'ctr'))}."
    build(row, 'ctr_baixo', 'new_creative', 'atencao', 'Poucos cliques para tanta exibição', evidence,
          'O gancho não para o dedo. Pedir variações ao núcleo criativo (primeiros 3 segundos / primeira linha) ou trocar pelo criativo campeão.',
          expected: "CTR perto de #{pct(b.dig('rates', 'ctr'))}", payload: { 'ctr' => ctr, 'baseline' => b.dig('rates', 'ctr') }, bonus: 10)
  end

  def cpm_rule(adset)
    b = baseline(adset)
    cpm = adset.dig('rates', 'cpm')
    return unless b&.dig('rates', 'cpm')&.positive? && cpm && adset['impressions'].to_i >= @p.dig('min', 'impressions').to_i
    return unless cpm >= b.dig('rates', 'cpm') * CPM_ABOVE

    evidence = "CPM #{money(cpm)} contra #{money(b.dig('rates', 'cpm'))} da nossa média (#{pct_over(cpm, b.dig('rates', 'cpm'))} mais caro)."
    build(adset, 'cpm_alto', 'audience', 'atencao', 'Exibição cara neste conjunto', evidence,
          'Público apertado demais ou posicionamento caro. Abrir o público (ou usar o Advantage+), ' \
          'tirar posicionamentos caros e conferir a concorrência de leilão.',
          expected: "CPM perto de #{money(b.dig('rates', 'cpm'))}", payload: { 'cpm' => cpm, 'baseline' => b.dig('rates', 'cpm') }, bonus: 8)
  end

  def page_rule(campaign)
    b = baseline(campaign)
    rate = campaign.dig('rates', 'lead_rate')
    return unless b&.dig('rates', 'lead_rate')&.positive? && rate && campaign['link_clicks'].to_i >= @p.dig('min', 'clicks').to_i
    return unless rate <= b.dig('rates', 'lead_rate') * BELOW

    evidence = "#{fmt(campaign['link_clicks'])} cliques viraram #{fmt(campaign['leads'])} leads (#{pct(rate)}). " \
               "A nossa média é #{pct(b.dig('rates', 'lead_rate'))}."
    build(campaign, 'pagina_nao_converte', 'page', 'atencao', 'Clica e não vira lead', evidence,
          'O problema está depois do clique: a página (ou a mensagem pronta do WhatsApp). ' \
          'Abrir Resultados de tráfego → Otimizar da página desta campanha ' \
          'e conferir se a promessa do anúncio é a mesma da página.',
          expected: "leads por clique perto de #{pct(b.dig('rates', 'lead_rate'))}",
          payload: { 'lead_rate' => rate, 'baseline' => b.dig('rates', 'lead_rate') }, bonus: 12)
  end

  def booking_rule(campaign)
    b = baseline(campaign)
    rate = campaign.dig('rates', 'booking_rate')
    return unless b&.dig('rates', 'booking_rate')&.positive? && rate && campaign['leads'].to_i >= @p.dig('min', 'leads').to_i
    return unless rate <= b.dig('rates', 'booking_rate') * BELOW

    evidence = "#{fmt(campaign['leads'])} leads e #{fmt(campaign['booked'])} agendaram (#{pct(rate)}). A nossa média é #{pct(b.dig('rates',
                                                                                                                                   'booking_rate'))}."
    build(campaign, 'lead_nao_agenda', 'quality', 'atencao', 'Lead chega e não agenda', evidence,
          'Lead frio ou promessa que o atendimento não confirma. Ler as conversas desses leads, apertar o público (idade, interesse) ' \
          'e alinhar o texto do anúncio com o Roteiro.',
          expected: "agendamento perto de #{pct(b.dig('rates', 'booking_rate'))}",
          payload: { 'booking_rate' => rate, 'baseline' => b.dig('rates', 'booking_rate') }, bonus: 12)
  end

  def learning_rule(row)
    return unless row['spend'].to_f >= @p.dig('min', 'spend').to_f / 2

    days = row['first_day'] ? (@today - Date.iso8601(row['first_day'])).to_i : nil
    build(row, 'em_aprendizado', 'watch', 'info', "Em aprendizado#{days ? " (#{days} dia#{'s' if days != 1})" : ''}",
          "Começou dentro da janela de #{@window_days} dias: #{money(row['spend'])} gastos, #{row['leads']} leads, " \
          "#{row['goal_events']} #{goal_unit(row['goal_events'])}.",
          'Não mexer ainda: a plataforma está aprendendo. O agente volta a julgar quando houver volume.', bonus: 0)
  end

  # ── ritmo da verba do mês, por canal ──────────────────────────────────
  def pacing_rules # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    %w[meta google].filter_map do |channel|
      budget = @p.dig('budget', channel).to_f
      next if budget <= 0

      mtd = @month[:totals][channel]
      next if mtd.nil? || mtd['spend'].to_f.zero?

      expected = budget * (@today.day - 1) / @today.end_of_month.day
      ratio = expected.positive? ? mtd['spend'].to_f / expected : nil
      next if ratio.nil? || (ratio > PACING_LOW && ratio < PACING_HIGH)

      pacing_rule(channel, mtd, budget, expected, ratio)
    end
  end

  def pacing_rule(channel, mtd, budget, expected, ratio)
    low = ratio <= PACING_LOW
    row = mtd.merge('level' => 'channel', 'id' => channel, 'name' => channel_label(channel), 'channel' => channel)
    evidence = "No mês: #{money(mtd['spend'])} gastos até ontem; no ritmo da verba combinada (#{money(budget)}/mês) seriam #{money(expected)}."
    if low
      build(row, 'verba_parada', 'pacing', 'oportunidade', "#{channel_label(channel)}: verba parada (#{pct(ratio)} do ritmo)", evidence,
            'Tem verba sobrando: subir nas campeãs ou subir campanha nova (ficha abaixo). Verba parada é paciente que não chega.',
            expected: "#{money(budget - mtd['spend'].to_f)} ainda cabem no mês",
            bonus: 15)
    else
      build(row, 'verba_acima', 'pacing', 'atencao', "#{channel_label(channel)}: #{pct(ratio - 1)} acima do ritmo", evidence,
            'Está gastando mais rápido que o combinado. Se o custo por resultado está bom, vale aceitar e ajustar a verba; ' \
            'se não, reduzir nos piores.',
            expected: nil, bonus: 15)
    end
  end

  # ── apoios ─────────────────────────────────────────────────────────────
  def baseline(row)
    Cevico::CampaignAgent::Baselines.pick(@baselines, row['channel'], @p['baseline_days'].to_i)
  end

  def enough_spend?(row)
    row['spend'].to_f >= @p.dig('min', 'spend').to_f
  end

  def new?(row)
    row['first_day'].present? && Date.iso8601(row['first_day']) >= (@today - @window_days)
  rescue ArgumentError
    false
  end

  def previous_row(row)
    @previous_index ||= @previous[:flat].index_by { |r| [r['channel'], r['level'], r['id']] }
    @previous_index[[row['channel'], row['level'], row['id']]]
  end

  def month_over_budget?(channel)
    budget = @p.dig('budget', channel).to_f
    return false if budget <= 0

    mtd = @month[:totals][channel]
    expected = budget * (@today.day - 1) / @today.end_of_month.day
    mtd.present? && expected.positive? && mtd['spend'].to_f > expected * PACING_HIGH
  end

  # verba de hoje → verba sugerida (R$/dia); só quando a plataforma nos disse a verba atual
  def budget_change(row, pct)
    current = row['daily_budget'].to_f
    return nil unless current.positive?

    target = (current * (1 + (pct / 100.0))).round(2)
    cap = @p['daily_cap'].to_f
    capped = cap.positive? && target > cap
    target = cap if capped
    { 'pct' => pct, 'budget_from' => current, 'budget_to' => target, 'capped' => capped }
  end

  def budget_text(budget)
    budget ? " (de #{money(budget['budget_from'])} para #{money(budget['budget_to'])} por dia)" : ''
  end

  def build(row, rule, kind, severity, title, evidence, suggestion, expected: nil, payload: {}, bonus: 0) # rubocop:disable Metrics/ParameterLists, Metrics/AbcSize, Metrics/CyclomaticComplexity
    observing = @observing.include?(rule) && Crm::CampaignAction::PLATFORM_KINDS.include?(kind)
    weight = { 'alerta' => 300, 'atencao' => 200, 'oportunidade' => 150, 'info' => 50 }[severity] + bonus.to_i.clamp(0, 99)
    {
      channel: row['channel'], level: row['level'], ref_id: row['id'].to_s, ref_name: row['name'],
      campaign_id: row['level'] == 'campaign' ? row['id'].to_s : row['campaign_id'].to_s.presence,
      campaign_name: row['level'] == 'campaign' ? row['name'] : row['campaign_name'],
      rule: rule, kind: observing ? 'watch' : kind, severity: observing ? 'info' : severity,
      key: "#{row['channel']}:#{row['level']}:#{row['id']}:#{rule}",
      title: observing ? "(em observação) #{title}" : title, evidence: evidence,
      suggestion: observing ? "#{suggestion} — esta regra errou mais do que acertou no aprendizado: por enquanto só avisa." : suggestion,
      expected: expected,
      payload: payload.merge('window_days' => @window_days, 'goal' => @p['goal'], 'observing' => observing).compact,
      metrics_before: ROW.snapshot(row), weight: weight
    }
  end

  def saving_text(row)
    "economiza ~#{money(row['spend'] / @window_days)} por dia"
  end

  # +N agendamentos por semana se a verba subir um passo e o custo se mantiver
  def champion_expected(row)
    weekly = (row['goal_events'] * @p['budget_step_pct'].to_f / 100) / @window_days * 7
    "+#{weekly.round(1)} #{goal_unit(2)} por semana"
  end

  def goal_word
    @p['goal'] == 'surgery' ? 'cirurgia' : 'agendamento'
  end

  def goal_cap
    @p['goal'] == 'surgery' ? 'Custo por cirurgia' : 'Custo por agendamento'
  end

  def goal_unit(count)
    count.to_i == 1 ? goal_word : "#{goal_word}s"
  end

  def channel_label(channel)
    channel == 'meta' ? 'Meta' : 'Google'
  end

  def money(value)
    "R$ #{format('%.2f', value.to_f).tr('.', ',').delete_suffix(',00')}".gsub(/\B(?=(\d{3})+(?!\d))/, '.')
  end

  def fmt(value)
    value.to_i.to_s.gsub(/\B(?=(\d{3})+(?!\d))/, '.')
  end

  def num(value)
    value.to_f.round(1).to_s.delete_suffix('.0').tr('.', ',')
  end

  def pct(rate)
    "#{(rate.to_f * 100).round(1).to_s.delete_suffix('.0').tr('.', ',')}%"
  end

  def pct_over(value, base)
    pct((value.to_f / base) - 1)
  end

  def pct_under(value, base)
    pct(1 - (value.to_f / base))
  end
end
