# 📣 CONTROLE DO LOTE (item 382, 03/11 — Guilherme: "como fazer de forma
# controlada, para eu saber exatamente para onde está indo, quem está
# recebendo, os lotes… qual é o tamanho 100% do lote, em que ordem, quem recebe
# hoje e quem recebe amanhã, mandar ou não no fim de semana").
#
# Aqui mora tudo que MOSTRA antes de mandar e REGISTRA depois:
#   plan    → a próxima fatia, pessoa por pessoa (coluna, frente, caixa, modelo), sem mandar nada
#   send!   → manda exatamente as linhas aprovadas (re-conferindo opt-out e teto)
#   queue   → a fila inteira projetada dia a dia (lote 1 = hoje, lote 2 = amanhã…)
#   batches → os lotes que já saíram, com o status de entrega de cada mensagem
#   modo de teste → só os números da lista de teste recebem (pode repetir)
module Crm::ReactivationBatch # rubocop:disable Metrics/ModuleLength
  module_function

  Plan = Crm::ReactivationPlan
  ROW_LIMIT = 2000
  DETAIL_DAYS = 3
  WEEKDAYS = %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado].freeze

  # ── a próxima fatia, sem mandar ──────────────────────────────────────────
  # devolve { skip: 'motivo' } ou { cfg, today, quota, remaining_today, rows, warnings, pools }
  def plan(mother, now: Time.current, force: false) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    cfg = Plan.config(mother)
    local = now.in_time_zone(Plan::TZ)
    today = local.to_date
    unless force
      return { cfg: cfg, skip: 'fim de semana' } if cfg['weekdays_only'] && (local.saturday? || local.sunday?)
      return { cfg: cfg, skip: 'fora do horário' } unless local.hour >= cfg['hour_from'] && local.hour < cfg['hour_to']
      if cfg['max_open_conversations'].positive? && Plan.open_conversations(mother.account) > cfg['max_open_conversations']
        return { cfg: cfg, skip: "atendimento cheio (#{Plan.open_conversations(mother.account)} conversas abertas)" }
      end
    end

    remaining_today = cfg['daily_cap'] - Plan.sent_today(mother, today)
    return { cfg: cfg, skip: 'teto do dia atingido' } if remaining_today <= 0

    hours_left = force ? 1 : [cfg['hour_to'] - local.hour, 1].max
    quota = (remaining_today / hours_left.to_f).ceil
    slices = slices_for_pools(cfg)
    return { cfg: cfg, skip: 'nenhuma fatia com porcentagem e modelo' } if slices.empty?

    pools = pools_for(mother, cfg, slices, now)
    deficits = deficits_for(cfg, slices, Plan.day_stats(mother, today))
    alloc = Plan.allocate(quota, deficits, pools.transform_values(&:size))
    if alloc.values.sum.zero?
      reason = pools.values.all?(&:empty?) ? 'ninguém mais para receber' : 'fatias do dia já completas'
      return { cfg: cfg, skip: reason, pools: pools }
    end

    picked = slices.flat_map { |s| pools[s['key']].first(alloc[s['key']]).map { |row| row.merge(slice: s) } }
    rows, warnings = route(mother, cfg, picked, Plan.sent_today_by_inbox(mother, today))
    { cfg: cfg, today: today, quota: quota, remaining_today: remaining_today, rows: rows, warnings: warnings, pools: pools }
  end

  def active_slices(cfg)
    cfg['slices'].select { |s| s['share'].positive? && s['templates'].any? }
  end

  # { key => [ {contact_id, name, phone, procedure, moved_at, stage_name}, … ] }
  def pools_for(mother, cfg, slices, now)
    return { 'teste' => test_pool(mother, cfg) } if cfg['test_mode']

    stages = stage_names(mother, slices)
    slices.to_h do |s|
      rows = Plan.pool(mother, cfg, s, now: now).pluck(:contact_id, 'contacts.name', 'contacts.phone_number', :procedure_of_interest, :stage_moved_at)
      [s['key'], rows.map do |id, name, phone, proc, moved|
        { contact_id: id, name: name, phone: phone, procedure: proc, moved_at: moved, stage_name: stages[s['stage_id']] }
      end]
    end
  end

  def stage_names(mother, slices)
    Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: mother.account_id }, id: slices.pluck('stage_id')).pluck(:id, :name).to_h
  end

  def deficits_for(cfg, slices, day)
    slices.to_h do |s|
      target = (cfg['daily_cap'] * s['share'] / 100.0).round
      [s['key'], target - day.dig('slices', s['key']).to_i]
    end
  end

  # 🧪 modo de teste: só os telefones da lista; pode repetir; opt-out ainda vale
  def test_pool(mother, cfg) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    digits = Array(cfg['test_phones']).map { |p| p.to_s.gsub(/\D/, '') }.reject(&:blank?)
    # a lista pode vir sem o 55 do Brasil; o cadastro guarda +55…
    digits = digits.flat_map { |d| d.size.between?(10, 11) ? [d, "55#{d}"] : [d] }.uniq
    return [] if digits.empty?

    account = mother.account
    quiet = Crm::OptOut.excluded_contact_ids(account)
    contacts = account.contacts.where("regexp_replace(COALESCE(phone_number, ''), '\\D', '', 'g') IN (?)", digits)
    contacts = contacts.where.not(id: quiet) if quiet.any?
    cards = Crm::Contact.where(contact_id: contacts.select(:id)).pluck(:contact_id, :procedure_of_interest).to_h
    contacts.order(:id).map do |c|
      { contact_id: c.id, name: c.name, phone: c.phone_number, procedure: cards[c.id], moved_at: nil, stage_name: 'lista de teste' }
    end
  end

  # em modo de teste a fatia é a primeira com modelo
  def slices_for_pools(cfg)
    base = active_slices(cfg)
    return base unless cfg['test_mode']

    base.first ? [base.first.merge('key' => 'teste', 'share' => 100)] : []
  end

  # ── caixa + modelo de cada linha ─────────────────────────────────────────
  # devolve [rows, warnings]; linha sem modelo possível fica de fora
  def route(mother, cfg, picked, by_inbox) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    account = mother.account
    inboxes = Plan.whatsapp_inboxes(account)
    default = Plan.default_inbox(account, cfg, mother)
    origin = cfg['route_by_origin'] ? Crm::PatientKind.origin_inbox_by_contact(account, picked.pluck(:contact_id)) : {}
    by_inbox = by_inbox.dup
    warnings = []
    rows = picked.filter_map do |r|
      slice = r[:slice]
      inbox = inboxes.find { |i| i.id == origin.dig(r[:contact_id], :id) } || default
      origem = inbox
      inbox = default if by_inbox[inbox.id].to_i >= cfg['inbox_daily_cap'] && inbox != default
      if by_inbox[inbox.id].to_i >= cfg['inbox_daily_cap']
        warnings << "teto da caixa #{inbox.name} atingido"
        next
      end
      frente = Plan.frente_of(r[:procedure])
      tpl = Plan.template_for(slice, frente)
      inbox, tpl = Plan.resolve_template(inbox, default, tpl, slice, frente, warnings)
      next if tpl.nil?

      by_inbox[inbox.id] = by_inbox[inbox.id].to_i + 1
      { contact_id: r[:contact_id], name: r[:name].presence || 'Sem nome', phone: r[:phone], slice_key: slice['key'],
        stage_name: r[:stage_name], frente: frente, inbox_id: inbox.id, inbox_name: inbox.name,
        origin_inbox: origem.name, fallback: inbox != origem, template: tpl.dig('template_params', 'name'),
        moved_at: r[:moved_at]&.iso8601, tpl: tpl }
    end
    [rows, warnings.uniq]
  end

  # ── mandar as linhas aprovadas ───────────────────────────────────────────
  def send!(mother, batch, rows, now: Time.current) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    cfg = batch[:cfg]
    today = batch[:today]
    account = mother.account
    inboxes = Plan.whatsapp_inboxes(account).index_by(&:id)
    quiet = Crm::OptOut.excluded_contact_ids(account)
    by_inbox = Plan.sent_today_by_inbox(mother, today)
    children = {}
    sent = 0
    warnings = Array(batch[:warnings]).dup
    rows.each do |row|
      contact = account.contacts.find_by(id: row[:contact_id])
      inbox = inboxes[row[:inbox_id]]
      next if contact.nil? || inbox.nil? || quiet.include?(contact.id)

      if by_inbox[inbox.id].to_i >= cfg['inbox_daily_cap']
        warnings << "teto da caixa #{inbox.name} atingido"
        next
      end

      child = children[inbox.id] ||= child_for!(mother, today, inbox, row[:tpl], cfg['test_mode'])
      conversation = Plan.deliver(child, inbox, row[:tpl], contact, slice: row[:slice_key], frente: row[:frente])
      next if conversation.nil?

      Plan.record!(child, contact, conversation, row[:slice_key], row[:frente], mother.id)
      by_inbox[inbox.id] = by_inbox[inbox.id].to_i + 1
      sent += 1
      Plan.bump_stats!(mother, today, row[:slice_key], inbox, row[:frente])
      sleep Plan::THROTTLE_SECONDS
    rescue StandardError => e
      Rails.logger.error "[Crm::ReactivationBatch] plano #{mother.id} contato #{row[:contact_id]}: #{e.message}"
      warnings << "falha com um contato: #{e.message.to_s.first(80)}"
    end
    children.each_value do |c|
      c.update!(stats: { 'total' => c.campaign_contacts.count, 'sent' => c.campaign_contacts.count })
      Crm::CampaignRunJob.set(wait: 10.minutes).perform_later(c.id, 'sweep')
    end
    Plan.note!(mother, 'last_run_at' => now.iso8601, 'last_check_at' => now.iso8601, 'last_run_sent' => sent,
                       'last_skip' => nil, 'pending_batch' => nil, 'warnings' => warnings.uniq.first(10))
    sent
  end

  # lote de teste = sempre uma campanha nova (a mesma pessoa pode receber de novo)
  def child_for!(mother, today, inbox, tpl, test)
    existing = Plan.children(mother, day: today).where(inbox_id: inbox.id).where("COALESCE(audience ->> 'test', 'false') <> 'true'").first
    return existing if existing && !test

    stamp = test ? "TESTE · #{Time.current.in_time_zone(Plan::TZ).strftime('%d/%m %H:%M')}" : today.strftime('%d/%m')
    mother.account.crm_campaigns.create!(
      inbox: inbox, sender_id: mother.sender_id,
      name: "#{Plan::NAME} · #{stamp} · #{inbox.name}",
      template_params: tpl['template_params'], message_preview: tpl['message_preview'], apply_label: test ? nil : mother.apply_label,
      conversion_stage_ids: mother.conversion_stage_ids, conversion_label_ids: mother.conversion_label_ids,
      audience: { 'parent_id' => mother.id, Plan::DAY_KEY => today.to_s, 'test' => test ? 'true' : 'false' },
      status: :completed, started_at: Time.current, finished_at: Time.current
    )
  end

  # ── a fila inteira, dia a dia ────────────────────────────────────────────
  # lote 1 = hoje (o que ainda cabe hoje), lote 2 = próximo dia de envio…
  def queue(mother, now: Time.current, days: 30, detail_days: DETAIL_DAYS) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    cfg = Plan.config(mother)
    slices = slices_for_pools(cfg)
    return { days: [], total: 0, cfg: cfg } if slices.empty?

    pools = pools_for(mother, cfg, slices, now).transform_values(&:dup)
    total = pools.values.sum(&:size)
    local = now.in_time_zone(Plan::TZ)
    date = local.to_date
    out = []
    lote = 0
    detailed = 0
    while pools.values.any?(&:present?) && out.size < days
      if cfg['weekdays_only'] && (date.saturday? || date.sunday?)
        date += 1
        next
      end
      cap = date == local.to_date ? [cfg['daily_cap'] - Plan.sent_today(mother, date), 0].max : cfg['daily_cap']
      day = date == local.to_date ? Plan.day_stats(mother, date) : {}
      alloc = Plan.allocate(cap, deficits_for(cfg, slices, day), pools.transform_values(&:size))
      if alloc.values.sum.zero?
        date += 1
        next
      end
      lote += 1
      picked = slices.flat_map { |s| pools[s['key']].shift(alloc[s['key']]).map { |r| r.merge(slice: s) } }
      entry = { lote: lote, date: date.iso8601, weekday: WEEKDAYS[date.wday],
                total: picked.size, por_fatia: picked.group_by { |r| r[:slice]['key'] }.transform_values(&:size) }
      if detailed < detail_days
        rows, = route(mother, cfg, picked, {})
        entry[:rows] = rows.map { |r| r.except(:tpl) }
        detailed += 1
      end
      out << entry
      date += 1
    end
    { days: out, total: total, lotes: lote, cfg: cfg,
      restam: pools.values.sum(&:size), order: cfg['order'], weekdays_only: cfg['weekdays_only'] }
  end

  # ── o que já saiu ────────────────────────────────────────────────────────
  def batches(mother, days: 14) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    since = (Time.current.in_time_zone(Plan::TZ).to_date - days).to_s
    Plan.children(mother).where("audience ->> '#{Plan::DAY_KEY}' >= ?", since).order(id: :desc).limit(60).map do |child|
      ccs = child.campaign_contacts.includes(:contact).order(:sent_at).to_a
      msgs = Message.where(conversation_id: ccs.filter_map(&:conversation_id), message_type: :outgoing)
                    .where("additional_attributes ? 'cevico_reactivation'")
                    .order(:created_at).group_by(&:conversation_id)
      rows = ccs.map do |cc|
        msg = (msgs[cc.conversation_id] || []).min_by { |m| (m.created_at - cc.sent_at).abs }
        meta = msg&.additional_attributes&.dig('cevico_reactivation') || {}
        { contact_id: cc.contact_id, name: cc.contact&.name.presence || 'Sem nome', phone: cc.contact&.phone_number,
          sent_at: cc.sent_at&.iso8601, conversation_id: cc.conversation_id,
          status: msg&.status || cc.delivery_status || 'sent', error: msg&.external_error.to_s.presence,
          slice_key: meta['slice'], frente: meta['frente'], template: meta['template'] }
      end
      { id: child.id, name: child.name, day: child.audience[Plan::DAY_KEY], inbox_id: child.inbox_id, inbox_name: child.inbox&.name,
        test: child.audience['test'] == 'true', total: rows.size,
        por_status: rows.group_by { |r| r[:status] }.transform_values(&:size), rows: rows }
    end
  end
end
