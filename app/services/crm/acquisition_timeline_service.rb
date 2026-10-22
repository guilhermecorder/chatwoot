# 📈 CUSTO POR FONTE AO LONGO DO TEMPO + FATURAMENTO × ETAPAS DO CRM
# (pedido dele em 19/10/2026: "quero um gráfico que meça custo por lead,
# vindo de cada fonte… o histórico e as variações de preço… o mesmo com custo
# de agendamento de consulta e CAC… e o faturamento em barras sobrepondo as
# colunas do CRM que eu escolher").
#
# Tudo vem de fontes que o sistema JÁ tem — nada novo é coletado:
#   gasto Meta    = foto diária por anúncio (cevico_ad_insights, espelho do
#                   Agente de Campanhas e dos Criativos)
#   gasto Google  = foto diária por campanha (cevico_campaign_days, GA4)
#   lead novo     = contato novo do universo oficial (Crm::LeadsUniverse),
#                   fonte pelo 1º carimbo (Crm::AcquisitionChannel)
#   agendamento   = 1ª vez que o paciente entrou na coluna de agendamento
#                   (ou além) OU teve consulta marcada na Agenda
#   cirurgia      = 1ª vez em "Cirurgia Agendada" (ou além) OU cirurgia na
#   fechada         Agenda OU cirurgia ativa/aguardando pagamento no Oftalmofácil
#   faturamento   = a MESMA receita do Financeiro & CAC (Crm::AcquisitionPatients:
#                   cirurgia realizada — pago do Oftalmofácil, senão valor do card)
#   etapas        = entradas nas colunas dos funis (histórico crm_contact_stage_logs)
#   novas conversas = conversas criadas
# Agrupa por dia (até 31 dias), semana (até 4 meses) ou mês. Pacientes de
# parceiro (cerca do item 231) ficam fora, como em todo o Financeiro & CAC.
class Crm::AcquisitionTimelineService
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  TZ_DATE_SQL = "AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo'".freeze
  SOURCES = Crm::AcquisitionChannel::CHANNELS.keys.freeze # google meta organico
  COUNTS = %w[leads booked closed].freeze
  DAY_LIMIT = 31
  WEEK_LIMIT = 124

  def initialize(account:, since:, until_at:)
    @account = account
    @since = since
    @until_at = until_at
    @from = since.in_time_zone(TZ).to_date
    @to = until_at.in_time_zone(TZ).to_date
  end

  def call
    {
      period: { from: @from.iso8601, to: @to.iso8601, days: days, unit: unit },
      buckets: buckets.map(&:iso8601),
      sources: sources_block,
      revenue: series(revenue_by_day),
      conversations: series(conversations_by_day),
      pipelines: pipelines_block
    }
  end

  private

  # ══ BALDES ══
  def days
    (@to - @from).to_i + 1
  end

  def unit
    @unit ||= if days <= DAY_LIMIT
                'day'
              else
                days <= WEEK_LIMIT ? 'week' : 'month'
              end
  end

  def bucket_of(date)
    case unit
    when 'day' then date
    when 'week' then date.beginning_of_week(:monday)
    else date.beginning_of_month
    end
  end

  def buckets
    @buckets ||= begin
      list = []
      d = bucket_of(@from)
      while d <= @to
        list << d
        d = case unit
            when 'day' then d + 1
            when 'week' then d + 7
            else d.next_month
            end
      end
      list
    end
  end

  def index
    @index ||= buckets.each_with_index.to_h
  end

  def zeros
    Array.new(buckets.size, 0)
  end

  # { dia => n } → [n por balde]
  def series(by_day)
    out = zeros
    by_day.each do |day, value|
      i = index[bucket_of(day.to_date)]
      out[i] += value if i
    end
    out
  end

  def to_date(at)
    at.is_a?(Date) ? at : at.in_time_zone(TZ).to_date
  end

  # ══ FONTES: gasto e contagens por balde ══
  def sources_block
    out = (SOURCES + ['all']).index_with { { 'spend' => nil, 'leads' => zeros, 'booked' => zeros, 'closed' => zeros } }
    spend_series.each { |source, values| out[source]['spend'] = values }
    { 'leads' => lead_rows, 'booked' => first_booked.to_a, 'closed' => first_closed.to_a }.each do |kind, rows|
      count_into(out, kind, rows)
    end
    out
  end

  # gasto por balde: Google, Meta e a soma (orgânico não tem gasto de anúncio)
  def spend_series
    google = series(spend_by_day['google']).map { |v| v.round(2) }
    meta = series(spend_by_day['meta']).map { |v| v.round(2) }
    { 'google' => google, 'meta' => meta, 'all' => google.zip(meta).map { |g, m| (g + m).round(2) } }
  end

  # soma cada [contato, dia] no balde certo, na fonte do contato e no total
  def count_into(out, kind, rows)
    rows.each do |contact_id, on|
      i = index[bucket_of(on)]
      next unless i

      out[channel_of[contact_id] || 'organico'][kind][i] += 1
      out['all'][kind][i] += 1
    end
  end

  def spend_by_day
    @spend_by_day ||= {
      'google' => Crm::CampaignDay.where(account_id: @account.id).google.between(@from, @to)
                                  .group(:date).sum(:spend).transform_values(&:to_f),
      'meta' => Crm::AdInsight.where(account_id: @account.id).between(@from, @to).group(:date)
                              .sum(Arel.sql("COALESCE((metrics->>'spend')::numeric, 0)")).transform_values(&:to_f)
    }
  end

  # [[contact_id, dia]] dos leads novos do período
  def lead_rows
    @lead_rows ||= Crm::LeadsUniverse.scope(@account, @since, @until_at).pluck(:id, :created_at).map { |id, at| [id, to_date(at)] }
  end

  # 1ª vez que cada paciente agendou consulta, caída no período
  def first_booked
    @first_booked ||= firsts(funnel_stage_ids[:booked], @account.tasks.where(task_type: 'consulta'))
  end

  # 1ª vez que cada paciente fechou cirurgia (venda), caída no período
  def first_closed
    @first_closed ||= firsts(funnel_stage_ids[:closed], @account.tasks.where(task_type: 'cirurgia', canceled_at: nil), oftalmofacil: true)
  end

  def funnel_stage_ids
    @funnel_stage_ids ||= Crm::AdFunnelSteps.stage_ids_for(@account)
  end

  # { contact_id => dia } — o mais antigo entre CRM, Agenda (e Oftalmofácil),
  # só quem caiu no período e não é paciente de parceiro
  def firsts(stage_ids, tasks, oftalmofacil: false) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    out = {}
    keep = proc { |cid, at| out[cid] = [out[cid], to_date(at)].compact.min if cid && at }
    if stage_ids.present?
      Crm::StageLog.joins(:crm_contact).where(stage_id: stage_ids, event_type: 'entered')
                   .where(crm_contacts: { pipeline_id: @account.crm_pipelines.select(:id) })
                   .group('crm_contacts.contact_id').minimum(:entered_at).each(&keep)
    end
    tasks.where.not(contact_id: nil).group(:contact_id).minimum(:created_at).each(&keep)
    if oftalmofacil
      Crm::OftalmofacilSurgery.where(account_id: @account.id, status_kind: Crm::AdFunnelSteps::OF_CLOSED)
                              .where.not(contact_id: nil).group(:contact_id).minimum(:surgery_date).each(&keep)
    end
    out.select { |cid, on| on.between?(@from, @to) && partner_ids.exclude?(cid) }
  end

  def partner_ids
    @partner_ids ||= Crm::PartnerGuard.excluded_contact_ids(@account).to_set
  end

  # { contact_id => 'google' | 'meta' | 'organico' } de todo mundo que aparece
  def channel_of
    @channel_of ||= begin
      ids = (lead_rows.map(&:first) + first_booked.keys + first_closed.keys).uniq
      classifier = Crm::AcquisitionChannel.new(@account)
      ids.each_slice(2000).with_object({}) do |slice, acc|
        classifier.for_contacts(slice).each { |cid, r| acc[cid] = r.channel }
      end
    end
  end

  # ══ FATURAMENTO (a receita do CAC, com data) ══
  def revenue_by_day
    patients = Crm::AcquisitionPatients.new(@account, from: @from, to: @to)
    by_day = Hash.new(0.0)
    patients.revenue_events.each do |key, on, value|
      next if patients.partner?(key) || (key.is_a?(Integer) && partner_ids.include?(key))

      by_day[on.to_date] += value
    end
    by_day.transform_values { |v| v.round(2) }
  end

  # ══ NOVAS CONVERSAS ══
  def conversations_by_day
    @account.conversations.where(created_at: @since..@until_at)
            .group(Arel.sql("DATE(conversations.created_at #{TZ_DATE_SQL})")).count
            .transform_keys { |day| Date.parse(day.to_s) }
  end

  # ══ ETAPAS: entradas em cada coluna, por funil ══
  def pipelines_block
    pipelines = @account.crm_pipelines.order(:position).includes(:stages).to_a
    by_stage = stage_entries(pipelines.flat_map { |p| p.stages.map(&:id) })
    pipelines.map do |p|
      { id: p.id, name: p.name,
        stages: p.stages.map { |s| { id: s.id, name: s.name, color: s.color, values: series(by_stage[s.id] || {}) } } }
    end
  end

  def stage_entries(stage_ids)
    Crm::StageLog.where(stage_id: stage_ids, event_type: 'entered', entered_at: @since..@until_at)
                 .group(:stage_id, Arel.sql("DATE(crm_contact_stage_logs.entered_at #{TZ_DATE_SQL})")).count
                 .each_with_object(Hash.new { |h, k| h[k] = {} }) { |((sid, day), n), acc| acc[sid][Date.parse(day.to_s)] = n }
  end
end
