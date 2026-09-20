# 🧭 Jornada do CRM por anúncio (Central de Criativos v2, item 177): leads
# que chegaram por cada anúncio (CTWA, `additional_attributes.meta_ads`),
# quantos marcaram consulta, compareceram, viraram cirurgia e a receita —
# num intervalo de datas — mais as taxas que valem dinheiro: custo por lead,
# custo por consulta agendada, custo por cirurgia realizada (CAC), ROAS e
# % de agendamento. Usado pela análise do período e pelos recordes.
module Crm::AdFunnel
  module_function

  EMPTY = { leads: 0, booked: 0, attended: 0, surgeries: 0, revenue: 0.0 }.freeze

  # { ad_id => { leads:, booked:, attended:, surgeries:, revenue: } }
  def by_ad(account, since_date, until_date, conversion_stage_ids: nil)
    contacts = leads_between(account, since_date, until_date)
    return {} if contacts.empty?

    ids = contacts.map(&:first)
    booked = consult_contact_ids(account, ids)
    attended = consult_contact_ids(account, ids, attended: true)
    converted = converted_values(account, ids, conversion_stage_ids || stage_ids(account))
    contacts.group_by(&:last).transform_values do |pairs|
      funnel_row(pairs.map(&:first), booked, attended, converted)
    end
  end

  # [[contact_id, ad_id], …] dos leads que chegaram por anúncio no intervalo
  def leads_between(account, since_date, until_date)
    account.contacts
           .where("additional_attributes -> 'meta_ads' ->> 'source_id' IS NOT NULL")
           .where("(additional_attributes -> 'meta_ads' ->> 'captured_at')::timestamptz >= ?", since_date.beginning_of_day)
           .where("(additional_attributes -> 'meta_ads' ->> 'captured_at')::timestamptz <= ?", until_date.end_of_day)
           .pluck(:id, Arel.sql("additional_attributes -> 'meta_ads' ->> 'source_id'"))
  end

  def consult_contact_ids(account, ids, attended: false)
    scope = account.tasks.where(task_type: 'consulta', contact_id: ids)
    scope = scope.where(attendance: 'attended') if attended
    scope.distinct.pluck(:contact_id).to_set
  end

  def funnel_row(cids, booked, attended, converted)
    { leads: cids.size, booked: cids.count { |id| booked.include?(id) },
      attended: cids.count { |id| attended.include?(id) },
      surgeries: cids.count { |id| converted.key?(id) },
      revenue: cids.sum { |id| converted[id].to_f }.round(2) }
  end

  # taxas em cima da jornada + investimento (nil quando não dá para calcular)
  def rates(funnel, spend)
    f = EMPTY.merge((funnel || {}).symbolize_keys)
    spend = spend.to_f
    {
      cost_lead: per_unit(spend, f[:leads]), cost_booked: per_unit(spend, f[:booked]),
      cost_surgery: per_unit(spend, f[:surgeries]),
      roas: spend.positive? && f[:revenue].to_f.positive? ? (f[:revenue].to_f / spend).round(2) : nil,
      booking_rate: share(f[:booked], f[:leads]), surgery_rate: share(f[:surgeries], f[:leads])
    }
  end

  def per_unit(spend, count)
    count.to_i.positive? && spend.positive? ? (spend / count).round(2) : nil
  end

  def share(part, total)
    total.to_i.positive? ? (part.to_f / total).round(4) : nil
  end

  # soma de várias jornadas (totais da conta)
  def sum(list)
    list.each_with_object(EMPTY.dup) do |f, acc|
      f = (f || {}).symbolize_keys
      acc[:leads] += f[:leads].to_i
      acc[:booked] += f[:booked].to_i
      acc[:attended] += f[:attended].to_i
      acc[:surgeries] += f[:surgeries].to_i
      acc[:revenue] = (acc[:revenue] + f[:revenue].to_f).round(2)
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

  def converted_values(account, contact_ids, stage_ids)
    return {} if contact_ids.empty? || stage_ids.empty?

    cards = Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: account.id }).where(contact_id: contact_ids)
    converted_ids = cards.where(stage_id: stage_ids).pluck(:id) |
                    Crm::StageLog.where(crm_contact_id: cards.select(:id), stage_id: stage_ids).pluck(:crm_contact_id)
    cards.where(id: converted_ids).pluck(:contact_id, :value).to_h
  end
end
