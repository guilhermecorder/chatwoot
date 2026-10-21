# 🧭 Jornada do CRM por anúncio (Central de Criativos v2, item 177): leads
# que chegaram por cada anúncio (CTWA, `additional_attributes.meta_ads`),
# quantos marcaram consulta, compareceram, viraram cirurgia e a receita —
# num intervalo de datas — mais as taxas que valem dinheiro: custo por lead,
# custo por consulta agendada, custo por cirurgia realizada (CAC), ROAS e
# % de agendamento. Usado pela análise do período e pelos recordes.
module Crm::AdFunnel
  module_function

  EMPTY = { leads: 0, booked: 0, attended: 0, closed: 0, surgeries: 0, revenue: 0.0 }.freeze

  # 🩺 itens 289 e 294: os degraus e a origem de cada um moram em Crm::AdFunnelSteps
  # { ad_id => { leads:, booked:, attended:, closed:, surgeries:, revenue:, sources: } }
  def by_ad(account, since_date, until_date, conversion_stage_ids: nil) # rubocop:disable Lint/UnusedMethodArgument
    contacts = leads_between(account, since_date, until_date)
    return {} if contacts.empty?

    steps = Crm::AdFunnelSteps.new(account, contacts.map(&:first))
    contacts.group_by(&:last).transform_values { |pairs| funnel_row(pairs.map(&:first), steps) }
  end

  # [[contact_id, ad_id], …] dos leads que chegaram por anúncio no intervalo
  def leads_between(account, since_date, until_date)
    account.contacts
           .where("additional_attributes -> 'meta_ads' ->> 'source_id' IS NOT NULL")
           .where("(additional_attributes -> 'meta_ads' ->> 'captured_at')::timestamptz >= ?", since_date.beginning_of_day)
           .where("(additional_attributes -> 'meta_ads' ->> 'captured_at')::timestamptz <= ?", until_date.end_of_day)
           .pluck(:id, Arel.sql("additional_attributes -> 'meta_ads' ->> 'source_id'"))
  end

  def funnel_row(cids, steps) # rubocop:disable Metrics/AbcSize
    count = ->(set) { cids.count { |id| set.include?(id) } }
    done = cids.select { |id| steps.surgeries.include?(id) }
    { leads: cids.size, booked: count.call(steps.booked), attended: count.call(steps.attended),
      closed: count.call(steps.closed), surgeries: done.size, revenue: done.sum { |id| steps.revenue_of(id) }.round(2),
      sources: { booked_crm: count.call(steps.crm[:booked]), booked_agenda: count.call(steps.booked_agenda),
                 attended_crm: count.call(steps.crm[:attended]), attended_agenda: count.call(steps.attended_agenda),
                 closed_crm: count.call(steps.crm[:closed]), closed_agenda: count.call(steps.closed_agenda),
                 closed_of: count.call(steps.of_closed),
                 surgeries_crm: count.call(steps.crm[:surgeries]), surgeries_of: count.call(steps.of_done.keys.to_set) } }
  end

  # taxas em cima da jornada + investimento (nil quando não dá para calcular)
  def rates(funnel, spend) # rubocop:disable Metrics/AbcSize
    f = EMPTY.merge((funnel || {}).symbolize_keys)
    spend = spend.to_f
    {
      cost_lead: per_unit(spend, f[:leads]), cost_booked: per_unit(spend, f[:booked]),
      cost_closed: per_unit(spend, f[:closed]), cost_surgery: per_unit(spend, f[:surgeries]),
      roas: spend.positive? && f[:revenue].to_f.positive? ? (f[:revenue].to_f / spend).round(2) : nil,
      booking_rate: share(f[:booked], f[:leads]), closed_rate: share(f[:closed], f[:leads]),
      surgery_rate: share(f[:surgeries], f[:leads])
    }
  end

  def per_unit(spend, count)
    count.to_i.positive? && spend.positive? ? (spend / count).round(2) : nil
  end

  def share(part, total)
    total.to_i.positive? ? (part.to_f / total).round(4) : nil
  end

  # soma de várias jornadas (totais da conta)
  def sum(list) # rubocop:disable Metrics/AbcSize
    list.each_with_object(EMPTY.dup) do |f, acc|
      f = (f || {}).symbolize_keys
      acc[:leads] += f[:leads].to_i
      acc[:booked] += f[:booked].to_i
      acc[:attended] += f[:attended].to_i
      acc[:closed] += f[:closed].to_i
      acc[:surgeries] += f[:surgeries].to_i
      acc[:revenue] = (acc[:revenue] + f[:revenue].to_f).round(2)
      (f[:sources] || {}).each { |key, n| (acc[:sources] ||= {})[key.to_sym] = acc[:sources][key.to_sym].to_i + n.to_i }
    end
  end

  # etapas que contam como "cirurgia realizada": configuradas no relatório de
  # Anúncios (conversion_stage_ids) ou, sem configuração, toda etapa com
  # "cirurgia" no nome (sem "indica…")
  def stage_ids(account)
    cfg = CrmSetting.find_by(account: account)&.meta_ads_config || {}
    configured = Array(cfg['conversion_stage_ids']).map(&:to_i).reject(&:zero?)
    return configured if configured.any?

    base = Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: account.id }).where('crm_stages.name ILIKE ?', '%cirurgia%')
    strict = base.where.not('crm_stages.name ILIKE ?', '%indica%').pluck(:id)
    strict.any? ? strict : base.pluck(:id)
  end
end
