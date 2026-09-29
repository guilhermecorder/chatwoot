# 📋 O que o link de leitura da análise MOSTRA (item 287) — e só isso.
#
# Recebe o detalhe do anúncio (Crm::CreativeAnalyticsService#detail) e monta
# uma lista FECHADA de campos: nome do anúncio, miniatura, textos, transcrição,
# números somados do período, jornada em quantidade e a curva de retenção.
# Tudo que não está nesta lista fica de fora — em especial qualquer dado de
# paciente (nome, telefone), ids internos e chaves da Meta.
#
# `blocks` = a análise em blocos, cada um com título e texto limpo (o botão
# "Copiar" de cada bloco); `text` = todos juntos ("Copiar tudo").
#
# DUAS VERSÕES (rodada 2): `finance: true` = com dados financeiros;
# `finance: false` (padrão) = SEM nenhum valor em R$ — sai investimento, custo
# por conversa/consulta/cirurgia, CPM, CPC, receita e ROAS. Ficam as taxas (%),
# a retenção, os cliques, a transcrição, os textos e as contagens da jornada.
class Crm::CreativeSharePayload # rubocop:disable Metrics/ClassLength
  STATUS = { 'ACTIVE' => 'no ar', 'PAUSED' => 'pausado', 'CAMPAIGN_PAUSED' => 'campanha pausada', 'ADSET_PAUSED' => 'conjunto pausado',
             'ARCHIVED' => 'arquivado', 'DELETED' => 'apagado', 'UNKNOWN' => 'sem detalhe' }.freeze
  ANGLES = { 'pergunta' => 'pergunta', 'dor' => 'dor', 'curiosidade' => 'curiosidade', 'prova' => 'prova', 'oferta' => 'oferta',
             'autoridade' => 'autoridade', 'historia' => 'história', 'outro' => 'outro' }.freeze

  MONEY_MARK = 'R$'.freeze
  NEUTRAL_READING = 'As peças da copy estão dentro dos parâmetros; o ponto de atenção está na entrega ' \
                    '(público, posicionamento ou orçamento).'.freeze

  def initialize(detail, since_date:, until_date:, finance: false)
    @d = detail.as_json
    @since_date = since_date
    @until_date = until_date
    @finance = finance == true
  end

  def call
    { finance: @finance, finance_label: Crm::CreativeShareLink.finance_label(@finance),
      ad: ad, period: period, reading: reading, numbers: numbers, funnel: funnel_steps, funnel_note: @d.dig('funnel_view', 'note'),
      journey: journey_numbers, journey_title: journey_title,
      indicators: indicators, radar: radar, daily: daily, placements: ranking('placement_ranking'), audience: ranking('audience_ranking'),
      texts: texts, transcript: transcript, retention: @d['retention_detail'], blocks: blocks, text: text }
  end

  def text
    header = ["ANÁLISE DO CRIATIVO: #{ad[:name]}", ad_line, "Período analisado: #{period[:label]}"].compact.join("\n")
    ([header] + blocks.map { |b| "#{b[:title].upcase}\n#{b[:text]}" }).join("\n\n")
  end

  def blocks # rubocop:disable Metrics/AbcSize
    @blocks ||= [
      block('leitura', 'Leitura', reading),
      block('numeros', 'Números do anúncio', lines(numbers)),
      block('indicadores', 'Indicadores contra a média e o recorde da conta', indicators_text),
      block('jornada', journey_title, journey_text),
      block('retencao', 'Curva de retenção', retention_text),
      block('quedas', 'Maiores quedas do vídeo', drops_text),
      block('cliques', 'Cliques por quem chegou até aqui', clicks_text),
      block('transcricao', 'Transcrição do vídeo', transcript_text),
      block('textos', 'Textos do anúncio na Meta', texts_text),
      block('onde', 'Onde apareceu: os mais e os menos', ranking_text(ranking('placement_ranking'))),
      block('quem', 'Quem viu: os mais e os menos', ranking_text(ranking('audience_ranking')))
    ].compact
  end

  private

  def block(key, title, body)
    body = without_money(body.to_s) unless @finance
    body.present? ? { key: key, title: title, text: body.to_s.strip } : nil
  end

  # trava final da versão sem financeiro: linha com valor em R$ não sai
  def without_money(body)
    body.lines.reject { |line| line.include?(MONEY_MARK) }.join.strip
  end

  def only_allowed(list)
    list = list.reject { |n| n[:money] || n[:value].to_s.include?(MONEY_MARK) } unless @finance
    list.map { |n| n.except(:money) }
  end

  # a leitura do link fala só de MÉDIA e RECORDE da conta (rodada 3); o diagnóstico
  # com os parâmetros bom/ruim continua nas telas internas. Sem ela (dado antigo),
  # cai no diagnóstico — e, na versão sem financeiro, texto que cita custo vira frase neutra
  def reading
    fresh = @d.dig('average_reading', @finance ? 'full' : 'without_money')
    return fresh if fresh.present?

    text = @d.dig('diagnosis', 'text').to_s
    return text.presence if @finance
    return NEUTRAL_READING if text.match?(/R\$|custo/i)

    text.presence
  end

  def journey_title
    @finance ? 'O que vale dinheiro' : 'Jornada no atendimento'
  end

  # 🔻 funil com a % de conversão de cada etapa (rodada 4). Lista FECHADA de campos:
  # a origem de cada número (`source_text`) é só da tela interna e fica de fora daqui.
  FUNNEL_KEYS = %w[key label hint count width rate rate_text conversion_text over of_leads_text average average_text versus].freeze

  def funnel_steps
    @funnel_steps ||= Array(@d.dig('funnel_view', 'steps')).map { |step| step.slice(*FUNNEL_KEYS) }
  end

  def journey_text
    rows = funnel_steps.map do |step|
      parts = [step['conversion_text'], step['of_leads_text'], step['average_text'] && "média da conta #{step['average_text']}"].compact
      "• #{step['label']}: #{int(step['count'])}#{" — #{parts.join(' · ')}" if parts.any?}"
    end
    [rows.join("\n"), lines(journey_numbers).presence].compact.join("\n\n")
  end

  # ── indicadores, teia e ritmo por dia (rodada 2) ─────────────────────────
  def indicators
    @indicators ||= Array(@d.dig('scorecard', 'indicators')).select { |i| @finance || !i['money'] }.map { |i| i.except('money') }
  end

  def indicators_text
    indicators.map do |i|
      parts = ["este anúncio #{i['value_text']}", i['avg_text'] && "média da conta #{i['avg_text']}", record_part(i)].compact
      "• #{i['label']} (#{i['metric']}): #{parts.join(' · ')} — #{[i['verdict_label'], i['phrase'], i['record_phrase']].compact.join(' · ')}"
    end.join("\n")
  end

  def record_part(indicator)
    return nil if indicator['record_text'].blank?

    holder = [indicator['record_ad'], indicator['record_when']].compact.join(', ')
    "recorde da conta #{indicator['record_text']}#{" (#{holder})" if holder.present?}"
  end

  def radar
    @d.dig('scorecard', 'radar')
  end

  DAILY_KEYS = %w[date label impressions link_clicks conversations hook_rate hold_rate link_ctr].freeze

  def daily
    Array(@d['daily']).map { |day| day.slice(*DAILY_KEYS) }
  end

  # ── onde apareceu / quem viu: os mais e os menos (rodada 3) ──────────────
  RANK_KEYS = %w[label impressions link_clicks conversations clicks_per_100 conversations_per_100 yield_1000 badges].freeze

  def ranking(name)
    @rankings ||= {}
    @rankings[name] ||= begin
      data = @d[name] || {}
      rows = Array(data['rows']).map do |row|
        money = @finance ? { 'spend_text' => money(row['spend']), 'cost_text' => row['cost_conversation'] && money(row['cost_conversation']) } : {}
        row.slice(*RANK_KEYS).merge(money)
      end
      { 'summary' => data['summary'], 'no_difference' => data['no_difference'] == true, 'rows' => rows }
    end
  end

  def ranking_text(data)
    return nil if data['rows'].empty?

    ([data['summary']].compact + data['rows'].map { |row| ranking_line(row) }).join("\n")
  end

  def ranking_line(row)
    parts = ["#{int(row['conversations'])} conversas", "#{int(row['link_clicks'])} cliques", "#{int(row['impressions'])} exibições",
             "#{rate(row['clicks_per_100'])} cliques a cada 100 exibições", "#{rate(row['conversations_per_100'])} conversas a cada 100 cliques"]
    parts += [row['spend_text'], row['cost_text'] && "#{row['cost_text']} por conversa"].compact
    badges = Array(row['badges']).pluck('label')
    "• #{row['label']}#{" [#{badges.join(' · ').upcase}]" if badges.any?}: #{parts.join(' · ')}"
  end

  def rate(value)
    value.nil? ? '—' : decimal(value.to_f.round(1))
  end

  def lines(list)
    list.map { |n| "• #{n[:label]}: #{n[:value]} — #{n[:hint]}" }.join("\n")
  end

  # ── ficha ─────────────────────────────────────────────────────────────────
  def ad
    @ad ||= { name: @d['ad_name'].presence || 'Anúncio sem nome', campaign: @d['campaign_name'], adset: @d['adset_name'],
              format: @d['format'], format_label: @d['format_label'], status: STATUS[@d['status']] || @d['status'].to_s.downcase.tr('_', ' '),
              thumbnail_url: @d['thumbnail_url'], permalink: @d['permalink'], video: video? }
  end

  def ad_line
    [ad[:campaign].presence && "Campanha: #{ad[:campaign]}", ad[:adset].presence && "Conjunto: #{ad[:adset]}",
     "Formato: #{ad[:format_label]}", "Situação: #{ad[:status]}"].compact.join(' · ')
  end

  def period
    @period ||= { since: @since_date.iso8601, until: @until_date.iso8601, days: (@until_date - @since_date).to_i + 1,
                  label: "#{@since_date.strftime('%d/%m/%Y')} a #{@until_date.strftime('%d/%m/%Y')}" }
  end

  def video?
    !rates['hook_rate'].nil?
  end

  def rates
    @d['rates'] || {}
  end

  def totals
    @d['totals'] || {}
  end

  def funnel
    @d['funnel'] || {}
  end

  # ── números: cada um com uma frase dizendo o que é ───────────────────────
  def numbers # rubocop:disable Metrics/AbcSize
    @numbers ||= begin
      list = [
        number('Investido', money(totals['spend']), 'quanto foi gasto neste anúncio no período', money: true),
        number('Impressões', int(totals['impressions']), 'quantas vezes o anúncio apareceu na tela de alguém'),
        number('Alcance', int(@d.dig('summary', 'reach') || totals['reach']), 'quantas pessoas diferentes viram o anúncio'),
        number('Cliques no link', int(totals['link_clicks']), 'quantas vezes clicaram para falar com a clínica'),
        number('CTR de link', pct(rates['link_ctr'], 2), 'de cada 100 vezes que o anúncio apareceu, quantas viraram clique'),
        number('Conversas', int(totals['conversations']), 'conversas iniciadas no WhatsApp a partir do anúncio'),
        number('Conversa por clique', pct(rates['conv_rate']), 'de cada 100 cliques, quantos viraram conversa'),
        number('Custo por conversa', money_or_dash(rates['cost_conversation']), 'investido dividido pelas conversas', money: true)
      ]
      list += video_numbers if video?
      only_allowed(list)
    end
  end

  def video_numbers
    [number('Taxa de parada (gancho)', pct(rates['hook_rate']), 'de cada 100 vezes que apareceu, quantas pararam para ver 3 segundos'),
     number('Retenção (corpo)', pct(rates['hold_rate']), 'de quem passou dos 3 segundos, quantos viram o vídeo quase todo'),
     number('Tempo médio assistido', "#{decimal(rates['avg_watch'])} s", 'quanto tempo, em média, cada pessoa ficou no vídeo')]
  end

  # o que o dinheiro comprou (só na versão com dados financeiros)
  def journey_numbers
    @journey_numbers ||= only_allowed(
      [number('Custo por consulta', money_or_dash(rates['cost_booked']), 'investido dividido pelas consultas marcadas', money: true),
       number('Custo por cirurgia fechada', money_or_dash(rates['cost_closed']), 'investido dividido pelas cirurgias fechadas', money: true),
       number('Custo por cirurgia realizada', money_or_dash(rates['cost_surgery']), 'investido dividido pelas cirurgias realizadas',
              money: true),
       number('Retorno (ROAS)', rates['roas'] ? "#{decimal(rates['roas'])}×" : '—', 'quanto voltou para cada real investido', money: true)]
    )
  end

  def number(label, value, hint, money: false)
    { label: label, value: value, hint: hint, money: money }
  end

  # ── textos do criativo e transcrição ─────────────────────────────────────
  def texts
    @texts ||= { title: @d['ad_hook'], body: @d['ad_body'], description: @d['description'], button: @d['cta_label'],
                 titles: Array(@d['titles']).map(&:to_s), bodies: Array(@d['bodies']).map(&:to_s),
                 buttons: Array(@d['ctas']).map { |c| Crm::AdCreativeParser.cta_label(c) } }
  end

  def texts_text # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    out = []
    out << "Título: #{texts[:title]}" if texts[:title].present?
    out << "Texto:\n#{texts[:body]}" if texts[:body].present?
    out << "Descrição: #{texts[:description]}" if texts[:description].present?
    out << "Botão: #{texts[:button]}" if texts[:button].present?
    out << variations('Títulos testados', texts[:titles]) if texts[:titles].size > 1
    out << variations('Textos testados', texts[:bodies]) if texts[:bodies].size > 1
    out << variations('Botões testados', texts[:buttons]) if texts[:buttons].size > 1
    out.join("\n\n")
  end

  def variations(title, list)
    "#{title}:\n#{list.each_with_index.map { |t, i| "#{i + 1}. #{t}" }.join("\n")}"
  end

  def transcript
    return nil unless @d['text_source'] == 'video'

    t = @d['transcript'] || {}
    @transcript ||= { hook: @d['hook'], body: @d['body'], cta: @d['video_cta'], text: t['text'], angle: ANGLES[t['angle']] || t['angle'],
                      segments: Array(t['segments']) }
  end

  def transcript_text # rubocop:disable Metrics/AbcSize
    return nil unless transcript

    out = ["Gancho (primeiros segundos): #{transcript[:hook]}"]
    out << "Tipo de gancho: #{transcript[:angle]}" if transcript[:angle].present?
    out << "Corpo:\n#{transcript[:body]}" if transcript[:body].present?
    out << "Pedido falado (CTA): #{transcript[:cta]}" if transcript[:cta].present?
    out << "Texto completo:\n#{transcript[:text]}"
    out << "Fala por trecho:\n#{segment_lines.join("\n")}" if segment_lines.any?
    out.join("\n\n")
  end

  def segment_lines
    @segment_lines ||= (transcript ? transcript[:segments] : []).map do |s|
      "[#{seconds(s['start'])} a #{seconds(s['end'])}] #{s['text']}"
    end
  end

  # ── curva de retenção e cliques ──────────────────────────────────────────
  def retention
    @d['retention_detail']
  end

  def retention_text # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return nil unless retention

    base = retention['base_label']
    out = [retention_source]
    out << "Duração do vídeo: #{seconds(retention['duration'])}#{' (estimada)' if retention['duration_estimated']}" if retention['duration']
    out << "Tempo médio assistido: #{seconds(retention['avg_watch'])}" if retention['avg_watch'].to_f.positive?
    out << retention['duration_note'] if retention['duration_note'].present?
    out << zones_line if zones_line
    out << "Marcos:\n#{retention['marks'].map { |m| "• #{mark_label(m)}: #{pct(m['pct'])} #{base} (#{int(m['people'])})" }.join("\n")}"
    out << "Segundo a segundo:\n#{retention['points'].map { |p| "• #{p['label']}: #{pct(p['pct'])} (#{int(p['people'])})" }.join("\n")}"
    out << "Queda por trecho falado:\n#{segment_drops.join("\n")}" if segment_drops.any?
    out.compact.join("\n\n")
  end

  def retention_source
    if retention['source'] == 'meta_curve'
      'De onde vem: a Meta informa, segundo a segundo, quantos por cento das reproduções ainda estavam assistindo. ' \
        "Base: #{int(retention['base_total'])} reproduções em #{retention['curve_days']} dia(s) do período."
    else
      'De onde vem: a Meta informa quantas pessoas chegaram a cada marco do vídeo (3 s, 25%, 50%, 75% e o fim). ' \
        "Base: #{int(retention['base_total'])} impressões. A curva segundo a segundo aparece depois da próxima carga de dados da Meta."
    end
  end

  def mark_label(mark)
    mark['axis_label'].presence || mark['label']
  end

  def zones_line
    zones = Array(retention['zones'])
    return nil if zones.empty?

    "Zonas do vídeo: #{zones.map { |z| "#{z['label']} de #{seconds(z['from'])} a #{seconds(z['to'])}" }.join(' · ')}. #{retention['zones_note']}"
  end

  # as 3 a 5 maiores quedas, numeradas (rodada 2)
  def drops_text
    drops = Array(retention && retention['top_drops'])
    return nil if drops.empty?

    ([retention['drops_summary']].compact + drops.map { |drop| drop_line(drop) }).join("\n")
  end

  # "1. Gancho · do segundo 0 ao 3 · caiu 74,2 pontos (de 100% para 25,8%) · 97.349 exibições se perderam"
  def drop_line(drop)
    line = "#{drop['rank']}. #{drop['zone_label']} · #{drop_span(drop)} · caiu #{points(drop['drop'])} " \
           "(de #{pct(drop['from_pct'])} para #{pct(drop['to_pct'])}) · #{int(drop['people_lost'])} #{base_word} se perderam"
    drop['speech'].present? ? "#{line} · fala: “#{drop['speech']}”" : line
  end

  def drop_span(drop)
    return "de #{drop['from_label']} a #{drop['to_label']}" if drop['from_t'].nil? || drop['to_t'].nil?

    "do segundo #{decimal(drop['from_t'])} ao #{decimal(drop['to_t'])}"
  end

  def base_word
    retention['base'] == 'plays' ? 'reproduções' : 'exibições'
  end

  def points(value)
    "#{decimal((value.to_f * 100).round(1))} pontos"
  end

  def segment_drops
    @segment_drops ||= Array(retention && retention['segments']).map do |s|
      "• [#{seconds(s['start'])} a #{seconds(s['end'])}] “#{s['text']}” — de #{pct(s['pct_start'])} para #{pct(s['pct_end'])} " \
        "(#{int(s['people_lost'])} saíram)"
    end
  end

  def clicks_text
    clicks = retention && retention['clicks']
    return nil unless clicks

    rows = clicks['marks'].map do |m|
      line = "• #{m['label']}: #{m['conversion_text'] || click_rate(m)} (#{int(m['reached'])} chegaram até aqui)"
      m['before_min'].to_i.positive? ? "#{line} · pelo menos #{int(m['before_min'])} cliques vieram antes deste ponto" : line
    end
    ["#{clicks['note']}\nCliques no link no período: #{int(clicks['link_clicks'])}.", rows.join("\n")].join("\n\n")
  end

  def click_rate(mark)
    return 'sem dado' if mark['rate'].nil?

    "#{decimal((mark['rate'] * 100).round(1))} cliques para cada 100 que chegaram"
  end

  # ── formatação pt-BR ─────────────────────────────────────────────────────
  def money(value)
    whole, cents = format('%.2f', value.to_f).split('.')
    "R$ #{whole.reverse.scan(/\d{1,3}/).join('.').reverse},#{cents}"
  end

  def money_or_dash(value)
    value.nil? ? '—' : money(value)
  end

  def int(value)
    value.to_i.to_s.reverse.scan(/\d{1,3}/).join('.').reverse
  end

  def pct(value, digits = 1)
    value.nil? ? '—' : "#{format("%.#{digits}f", value.to_f * 100).tr('.', ',')}%"
  end

  def decimal(value)
    number = value.to_f
    (number % 1).zero? ? number.to_i.to_s : number.round(2).to_s.tr('.', ',')
  end

  def seconds(value)
    "#{decimal(value.to_f.round(1))} s"
  end
end
