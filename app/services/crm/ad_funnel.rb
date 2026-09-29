# 🧭 Jornada do CRM por anúncio (Central de Criativos v2, item 177): leads
# que chegaram por cada anúncio (CTWA, `additional_attributes.meta_ads`),
# quantos marcaram consulta, compareceram, viraram cirurgia e a receita —
# num intervalo de datas — mais as taxas que valem dinheiro: custo por lead,
# custo por consulta agendada, custo por cirurgia realizada (CAC), ROAS e
# % de agendamento. Usado pela análise do período e pelos recordes.
module Crm::AdFunnel # rubocop:disable Metrics/ModuleLength
  module_function

  EMPTY = { leads: 0, booked: 0, attended: 0, surgeries: 0, revenue: 0.0 }.freeze

  # 🩺 item 289 (29/09, "o CAC é mais baixo do que o preço da consulta… confirmar a
  # origem deste dado"): a régua antiga contava como CIRURGIA quem passou pelas
  # "colunas de conversão" do relatório de Anúncios — em produção [Agendamento de
  # Consulta, Cirurgia Realizada] — ou seja, agendamento virava cirurgia (197 × 9
  # de verdade) e o valor do orçamento virava receita. Agora cada degrau tem a
  # sua origem e um degrau sempre cabe no anterior:
  #   consultas   = card chegou na coluna de agendamento (regra oficial) ou além,
  #                 OU tem consulta na Agenda
  #   compareceram = card chegou em "Consulta Realizada" ou além, OU presença na Agenda
  #   cirurgias   = card chegou em "Cirurgia Realizada"/2º olho/pós-operatório,
  #                 OU cirurgia REALIZADA no Oftalmofácil
  #   receita     = valor pago/cobrado no Oftalmofácil; sem ele, o valor do card
  SURGERY_DONE = /cirurgia\s+realizada|2.{0,2}\s*olho|p[oó]s[\s-]?op/i
  ATTENDED_FROM = /consulta\s+realizada/i

  # { ad_id => { leads:, booked:, attended:, surgeries:, revenue:, sources: } }
  def by_ad(account, since_date, until_date, conversion_stage_ids: nil) # rubocop:disable Lint/UnusedMethodArgument
    contacts = leads_between(account, since_date, until_date)
    return {} if contacts.empty?

    sets = step_sets(account, contacts.map(&:first))
    contacts.group_by(&:last).transform_values { |pairs| funnel_row(pairs.map(&:first), sets) }
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

  # de onde vem cada degrau (CRM × Agenda × Oftalmofácil), em conjuntos de contact_id
  def step_sets(account, ids)
    steps = step_stage_ids(account)
    crm = steps.transform_values { |stage_ids| passed_contact_ids(account, ids, stage_ids) }
    of_done = Crm::OftalmofacilSurgery.where(account_id: account.id, contact_id: ids).realizadas
    surgeries = crm[:surgeries] | of_done.distinct.pluck(:contact_id).to_set
    attended_agenda = consult_contact_ids(account, ids, attended: true)
    attended = crm[:attended] | attended_agenda | surgeries
    booked_agenda = consult_contact_ids(account, ids)
    { crm: crm, booked_agenda: booked_agenda, attended_agenda: attended_agenda,
      of_done: of_done.group(:contact_id).sum('COALESCE(paid_amount, amount, 0)'),
      card_values: card_values(account, surgeries.to_a),
      booked: crm[:booked] | booked_agenda | attended, attended: attended, surgeries: surgeries }
  end

  # colunas de cada degrau, pelo funil da coluna oficial de agendamento
  def step_stage_ids(account) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    all = Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: account.id }).to_a
    booking = Crm::BookingRate.stage(account)
    line = booking ? all.select { |s| s.pipeline_id == booking.pipeline_id } : []
    from = ->(stage) { stage ? line.select { |s| s.position >= stage.position }.map(&:id) : [] }
    surgeries = all.select { |s| s.name.match?(SURGERY_DONE) }.map(&:id)
    { booked: from.call(booking) | surgeries,
      attended: from.call(line.select { |s| s.name.match?(ATTENDED_FROM) }.min_by(&:position)) | surgeries,
      surgeries: surgeries }
  end

  # quem está ou já passou por alguma dessas colunas
  def passed_contact_ids(account, contact_ids, stage_ids)
    return Set.new if contact_ids.empty? || stage_ids.empty?

    cards = Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: account.id }).where(contact_id: contact_ids)
    now = cards.where(stage_id: stage_ids).pluck(:contact_id)
    before = cards.where(id: Crm::StageLog.where(stage_id: stage_ids).select(:crm_contact_id)).pluck(:contact_id)
    (now + before).to_set
  end

  def card_values(account, contact_ids)
    return {} if contact_ids.empty?

    Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: account.id }, contact_id: contact_ids)
                .group(:contact_id).maximum(:value)
  end

  def funnel_row(cids, sets) # rubocop:disable Metrics/AbcSize
    count = ->(set) { cids.count { |id| set.include?(id) } }
    done = cids.select { |id| sets[:surgeries].include?(id) }
    revenue = done.sum { |id| sets[:of_done][id].to_f.positive? ? sets[:of_done][id].to_f : sets[:card_values][id].to_f }
    { leads: cids.size, booked: count.call(sets[:booked]), attended: count.call(sets[:attended]),
      surgeries: done.size, revenue: revenue.round(2),
      sources: { booked_crm: count.call(sets[:crm][:booked]), booked_agenda: count.call(sets[:booked_agenda]),
                 attended_crm: count.call(sets[:crm][:attended]), attended_agenda: count.call(sets[:attended_agenda]),
                 surgeries_crm: count.call(sets[:crm][:surgeries]), surgeries_of: done.count { |id| sets[:of_done].key?(id) } } }
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
  def sum(list) # rubocop:disable Metrics/AbcSize
    list.each_with_object(EMPTY.dup) do |f, acc|
      f = (f || {}).symbolize_keys
      acc[:leads] += f[:leads].to_i
      acc[:booked] += f[:booked].to_i
      acc[:attended] += f[:attended].to_i
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
