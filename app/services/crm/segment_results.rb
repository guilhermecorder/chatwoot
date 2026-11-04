# 🧪 RESULTADOS DE UM SEGMENTO, MENSAGEM POR MENSAGEM (item 383, 03/11 —
# Guilherme: "testei 5 mensagens, cada uma foi para 100 pessoas; vejo a taxa
# de conversão de cada mensagem e, quando encontrar a melhor, sei qual foi").
#
# Para cada mensagem (A, B, C…): reservadas, enviadas, entregues, lidas,
# falharam, respondeu, agendou consulta, chegou à cirurgia — e as taxas sobre
# as enviadas. A vencedora = maior taxa de consulta (desempate: respostas),
# só entre mensagens com amostra mínima. E a linha do tempo por dia para o
# gráfico de linha (enviadas, respostas, consultas), por mensagem.
module Crm::SegmentResults # rubocop:disable Metrics/ModuleLength
  module_function

  TZ = Crm::Campaign::TZ
  MIN_SAMPLE = 20
  SURGERY_STAGE = /cirurgia (agendada|marcada|realizada)/i
  TIMELINE_DAYS = 60

  # ── por mensagem ─────────────────────────────────────────────────────────
  def for(segment, now: Time.current) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    counts = segment.members.group(:variant_key, :status).count
    delivery = delivery_counts(segment)
    rows = member_rows(segment)
    by_day = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = Hash.new(0) } }
    per_variant = Hash.new { |h, k| h[k] = { 'replied' => 0, 'booked' => 0, 'surgery' => 0 } }
    rows.each do |variant, replied_at, booked_at, surgery_at, sent_at|
      by_day[variant][day_key(sent_at)]['sent'] += 1
      if replied_at
        per_variant[variant]['replied'] += 1
        by_day[variant][day_key(replied_at)]['replied'] += 1
      end
      if booked_at
        per_variant[variant]['booked'] += 1
        by_day[variant][day_key(booked_at)]['booked'] += 1
      end
      per_variant[variant]['surgery'] += 1 if surgery_at
    end

    variants = Array(segment.variants).map do |v|
      key = v['key']
      sent = counts[[key, 'enviado']].to_i
      row = {
        key: key, label: v['label'], template: v.dig('template_params', 'name'), preview: v['message_preview'],
        reserved: counts[[key, 'reservado']].to_i, sent: sent, failed: counts[[key, 'falhou']].to_i, skipped: counts[[key, 'pulado']].to_i,
        delivered: delivery[[key, 'delivered']].to_i + delivery[[key, 'read']].to_i, read: delivery[[key, 'read']].to_i,
        refused: delivery[[key, 'failed']].to_i,
        replied: per_variant[key]['replied'], booked: per_variant[key]['booked'], surgery: per_variant[key]['surgery']
      }
      base = [sent - row[:refused], 0].max # entregáveis: enviadas menos as recusadas pela Meta
      row.merge(deliverable: base, replied_rate: rate(row[:replied], base), booked_rate: rate(row[:booked], base),
                surgery_rate: rate(row[:surgery], base), read_rate: rate(row[:read], base))
    end
    totals = sum_rows(variants)
    { variants: variants, totals: totals, winner: winner(variants), min_sample: MIN_SAMPLE,
      timeline: timeline(segment, by_day, now) }
  end

  def rate(part, whole)
    whole.positive? ? (part.to_f / whole * 100).round(1) : 0.0
  end

  def sum_rows(variants)
    keys = %i[reserved sent failed skipped delivered read refused replied booked surgery]
    t = keys.index_with { |k| variants.sum { |v| v[k] } }
    base = [t[:sent] - t[:refused], 0].max
    t.merge(deliverable: base, replied_rate: rate(t[:replied], base), booked_rate: rate(t[:booked], base), surgery_rate: rate(t[:surgery], base))
  end

  # a melhor mensagem entre as que já têm amostra: consulta primeiro, resposta desempata
  def winner(variants)
    ok = variants.select { |v| v[:sent] >= MIN_SAMPLE }
    return nil if ok.empty?

    best = ok.max_by { |v| [v[:booked_rate], v[:replied_rate], v[:sent]] }
    return nil if best[:booked] + best[:replied] <= 0

    best[:key]
  end

  # status da mensagem modelo (Meta) por mensagem: enviada/entregue/lida/falhou
  def delivery_counts(segment)
    Message.where(conversation_id: segment.members.sent.select(:conversation_id), message_type: :outgoing)
           .where("additional_attributes -> 'cevico_segment' ->> 'segment_id' = ?", segment.id.to_s)
           .unscope(:order)
           .group(Arel.sql("additional_attributes -> 'cevico_segment' ->> 'variant'"), :status).count
  end

  # [variant, 1ª resposta, 1ª consulta marcada, entrada na cirurgia, enviada em]
  def member_rows(segment)
    surgery_ids = surgery_stage_ids(segment.account)
    surgery_sql = if surgery_ids.any?
                    '(SELECT MIN(l.entered_at) FROM crm_contact_stage_logs l INNER JOIN crm_contacts c ON c.id = l.crm_contact_id ' \
                      'WHERE c.contact_id = crm_segment_members.contact_id AND l.entered_at > crm_segment_members.sent_at ' \
                      "AND l.stage_id IN (#{surgery_ids.join(',')}))"
                  else
                    'NULL::timestamp'
                  end
    segment.members.sent.pluck(
      :variant_key,
      Arel.sql('(SELECT MIN(m.created_at) FROM messages m WHERE m.conversation_id = crm_segment_members.conversation_id ' \
               'AND m.message_type = 0 AND m.created_at > crm_segment_members.sent_at)'),
      Arel.sql(booked_sql(segment.account_id)),
      Arel.sql(surgery_sql),
      :sent_at
    )
  end

  def booked_sql(account_id)
    '(SELECT MIN(t.created_at) FROM tasks t WHERE t.contact_id = crm_segment_members.contact_id ' \
      "AND t.account_id = #{account_id.to_i} AND t.task_type = 'consulta' AND t.canceled_at IS NULL " \
      'AND t.created_at > crm_segment_members.sent_at)'
  end

  def surgery_stage_ids(account)
    Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: account.id }).pluck(:id, :name)
              .select { |_, name| name.to_s.match?(SURGERY_STAGE) }.map(&:first)
  end

  def day_key(time)
    time.in_time_zone(TZ).to_date.to_s
  end

  # dias desde o 1º envio (até 60) × mensagem: enviadas, respostas, consultas por dia
  def timeline(segment, by_day, now) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    first = segment.members.sent.minimum(:sent_at)
    return { days: [], series: [] } if first.nil?

    from = first.in_time_zone(TZ).to_date
    to = now.in_time_zone(TZ).to_date
    from = to - TIMELINE_DAYS if (to - from).to_i > TIMELINE_DAYS
    days = (from..to).map(&:to_s)
    series = Array(segment.variants).map do |v|
      k = v['key']
      { key: k, label: v['label'],
        sent: days.map { |d| by_day[k][d]['sent'] },
        replied: days.map { |d| by_day[k][d]['replied'] },
        booked: days.map { |d| by_day[k][d]['booked'] } }
    end
    { days: days, series: series }
  end

  # ── resumo leve (lista e painel) ─────────────────────────────────────────
  def summary(segment, now: Time.current) # rubocop:disable Metrics/AbcSize
    counts = segment.members.group(:status).count
    {
      id: segment.id, name: segment.name, kind: segment.kind, status: segment.status, parent_id: segment.parent_id,
      created_at: segment.created_at.iso8601, started_at: segment.started_at&.iso8601, finished_at: segment.finished_at&.iso8601,
      source: segment.source, variants: variants_json(segment),
      pace: Crm::SegmentSender.pace(segment), pace_label: Crm::SegmentSender.label(Crm::SegmentSender.pace(segment)),
      reserved: counts['reservado'].to_i, sent: counts['enviado'].to_i, failed: counts['falhou'].to_i, skipped: counts['pulado'].to_i,
      total: counts.values.sum, stats: segment.stats || {}, projection: Crm::SegmentSender.project(segment, now: now),
      creator: segment.creator&.name
    }
  end

  def variants_json(segment)
    Array(segment.variants).map { |v| v.slice('key', 'label', 'message_preview').merge('template' => v.dig('template_params', 'name')) }
  end

  # painel: números de todos os segmentos + linha do tempo dos últimos 30 dias
  def dashboard(account, now: Time.current) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
    segments = Crm::Segment.where(account_id: account.id)
    members = Crm::SegmentMember.where(segment_id: segments.select(:id))
    counts = members.group(:status).count
    to = now.in_time_zone(TZ).to_date
    from = to - 29
    rows = members.sent.where('sent_at >= ?', from.in_time_zone(TZ).beginning_of_day).pluck(
      :sent_at,
      Arel.sql('(SELECT MIN(m.created_at) FROM messages m WHERE m.conversation_id = crm_segment_members.conversation_id ' \
               'AND m.message_type = 0 AND m.created_at > crm_segment_members.sent_at)'),
      Arel.sql(booked_sql(account.id))
    )
    by_day = Hash.new { |h, k| h[k] = Hash.new(0) }
    replied = 0
    booked = 0
    rows.each do |sent_at, replied_at, booked_at|
      by_day[day_key(sent_at)]['sent'] += 1
      if replied_at
        replied += 1
        by_day[day_key(replied_at)]['replied'] += 1
      end
      if booked_at
        booked += 1
        by_day[day_key(booked_at)]['booked'] += 1
      end
    end
    days = (from..to).map(&:to_s)
    sent30 = rows.size
    {
      totals: { segments: segments.count, testes: segments.where(kind: 'teste').count, escalas: segments.where(kind: 'escala').count,
                sending: segments.sending.count, reserved: counts['reservado'].to_i, sent: counts['enviado'].to_i,
                sent_30d: sent30, replied_30d: replied, booked_30d: booked,
                replied_rate_30d: rate(replied, sent30), booked_rate_30d: rate(booked, sent30) },
      timeline: { days: days, sent: days.map { |d| by_day[d]['sent'] }, replied: days.map { |d| by_day[d]['replied'] },
                  booked: days.map { |d| by_day[d]['booked'] } }
    }
  end
end
