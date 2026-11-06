# 🧪 ENVIO DE UM SEGMENTO NO RITMO (item 383, 03/11 — Guilherme: "mil por
# dia, divididas em várias horas: às 9h 150 pessoas, às 10h 150… ou 10
# abordagens a cada 2 ou 5 minutos, dando respiro para o sistema").
#
# O ritmo (pace) de cada segmento:
#   per_hour        quantas mensagens por hora (padrão 150)
#   step_minutes    de quanto em quanto tempo sai uma leva: 2, 5, 10, 15, 30 ou 60 (padrão 60)
#                   → cada leva = per_hour × step/60 (150/h de 60 em 60 = 150 às 9h, 150 às 10h…;
#                     120/h de 5 em 5 = 10 a cada 5 minutos)
#   hour_from/to    janela em São Paulo (padrão 9 → 18)
#   weekdays_only   só dias úteis (padrão true)
#   daily_cap       teto do dia (padrão 1000; 0 = sem teto)
#   inbox_daily_cap teto por caixa por dia (padrão 300)
#   route_by_origin manda pela caixa da 1ª conversa da pessoa (padrão true)
#   default_inbox_id caixa de quem não tem origem (ou cujo modelo não existe na caixa de origem)
#
# O robô Crm::SegmentDripJob passa a cada 2 minutos e chama tick!: se a leva
# está vencida (e dentro da janela/teto), manda a próxima leva. Cada pessoa
# recebe UMA vez; o registro vai para crm_segment_members e também para uma
# campanha-filha por mensagem × caixa (Crm::Campaign), para os resultados,
# respostas e recusas da Meta continuarem nas telas de sempre.
module Crm::SegmentSender # rubocop:disable Metrics/ModuleLength
  module_function

  Plan = Crm::ReactivationPlan
  TZ = Plan::TZ
  STEPS = [2, 5, 10, 15, 30, 60].freeze
  DEFAULTS = {
    'per_hour' => 150, 'step_minutes' => 60, 'hour_from' => 9, 'hour_to' => 18, 'weekdays_only' => true,
    'daily_cap' => 1000, 'inbox_daily_cap' => 1000, 'default_inbox_id' => 0, 'route_by_origin' => true
  }.freeze
  LIMITS = { 'per_hour' => 1..5000, 'hour_from' => 0..23, 'hour_to' => 1..24, 'daily_cap' => 0..50_000,
             'inbox_daily_cap' => 1..5000, 'default_inbox_id' => 0..999_999_999 }.freeze

  def normalize_pace(raw) # rubocop:disable Metrics/AbcSize
    raw = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
    cfg = {}
    LIMITS.each_key { |k| cfg[k] = Crm::SegmentBuilder.clamp(raw[k], DEFAULTS[k], LIMITS[k]) }
    step = raw['step_minutes'].to_i
    cfg['step_minutes'] = STEPS.include?(step) ? step : DEFAULTS['step_minutes']
    cfg['weekdays_only'] = raw.key?('weekdays_only') ? Crm::SegmentBuilder.truthy?(raw['weekdays_only']) : true
    cfg['route_by_origin'] = raw.key?('route_by_origin') ? Crm::SegmentBuilder.truthy?(raw['route_by_origin']) : true
    cfg['hour_to'] = cfg['hour_from'] + 1 if cfg['hour_to'] <= cfg['hour_from']
    cfg
  end

  def pace(segment)
    normalize_pace(segment.pace)
  end

  # quantas saem em cada leva
  def step_size(cfg)
    [(cfg['per_hour'] * cfg['step_minutes'] / 60.0).round, 1].max
  end

  def window_open?(cfg, now)
    local = now.in_time_zone(TZ)
    return false if cfg['weekdays_only'] && (local.saturday? || local.sunday?)

    local.hour >= cfg['hour_from'] && local.hour < cfg['hour_to']
  end

  def window_label(cfg, now)
    local = now.in_time_zone(TZ)
    return 'fim de semana: não manda' if cfg['weekdays_only'] && (local.saturday? || local.sunday?)
    return "fora do horário (#{cfg['hour_from']}h–#{cfg['hour_to']}h)" unless local.hour >= cfg['hour_from'] && local.hour < cfg['hour_to']

    'dentro do horário de envio'
  end

  def day_range(now)
    local = now.in_time_zone(TZ)
    local.all_day
  end

  def sent_today(segment, now)
    segment.members.sent.where(sent_at: day_range(now)).count
  end

  def sent_today_by_inbox(segment, now)
    segment.members.sent.where(sent_at: day_range(now)).group(:inbox_id).count
  end

  # frase do ritmo para a tela ("150 por hora, de 60 em 60 min · 9h–18h · só dias úteis · teto 1000/dia")
  def label(cfg)
    bits = ["#{cfg['per_hour']} por hora", "de #{cfg['step_minutes']} em #{cfg['step_minutes']} min (#{step_size(cfg)} por leva)",
            "#{cfg['hour_from']}h–#{cfg['hour_to']}h", cfg['weekdays_only'] ? 'só dias úteis' : 'todos os dias']
    bits << "teto #{cfg['daily_cap']}/dia" if cfg['daily_cap'].positive?
    bits << "#{cfg['inbox_daily_cap']} por caixa/dia"
    bits << 'pela caixa de origem' if cfg['route_by_origin']
    bits.join(' · ')
  end

  # ── a leva ───────────────────────────────────────────────────────────────
  # devolve o número de mensagens que saíram. force = ignora janela e relógio
  # (botão "mandar a próxima leva agora"); teto do dia e regras valem sempre.
  LOCK_TTL = 30.minutes

  # 🔒 uma leva por vez por segmento: o robô (a cada 2 min) e o botão "mandar a
  # próxima leva agora" nunca rodam juntos — senão os dois pegariam as mesmas
  # pessoas reservadas e alguém receberia duas vezes
  def tick!(segment, now: Time.current, force: false, limit: nil)
    lock_manager = Redis::LockManager.new
    lock_key = "CRM_SEGMENT_TICK_LOCK::#{segment.id}"
    return skip(segment, 'outra leva deste segmento ainda está saindo') unless lock_manager.lock(lock_key, LOCK_TTL)

    begin
      tick_unlocked!(segment, now: now, force: force, limit: limit)
    ensure
      lock_manager.unlock(lock_key)
    end
  end

  def tick_unlocked!(segment, now: Time.current, force: false, limit: nil) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    return skip(segment, 'segmento não está enviando') unless segment.sending? || (force && segment.status == 'pausado')

    cfg = pace(segment)
    unless force
      return skip(segment, window_label(cfg, now)) unless window_open?(cfg, now)
      # o robô passa a cada 2 min: 1 min de tolerância para a leva de "60 em 60" sair às 10:00 e não às 10:02
      return 0 if segment.last_tick_at && segment.last_tick_at > now - (cfg['step_minutes'] - 1).minutes
    end
    today_sent = sent_today(segment, now)
    remaining_today = cfg['daily_cap'].positive? ? cfg['daily_cap'] - today_sent : Float::INFINITY
    return skip(segment, 'teto do dia atingido') if remaining_today <= 0

    account = segment.account
    inboxes = Plan.whatsapp_inboxes(account)
    default = inboxes.find { |i| i.id == cfg['default_inbox_id'] } || inboxes.first
    return skip(segment, 'nenhuma caixa WhatsApp oficial disponível') if default.nil?

    missing = Array(segment.variants).reject { |v| Plan.template_in?(default, tpl_of(v)) }
    return skip(segment, "modelo da #{missing.first['label']} não está aprovado na caixa #{default.name}") if missing.any?

    n = [limit || step_size(cfg), remaining_today].min.to_i
    members = claim!(segment, n, now)
    if members.empty?
      finish!(segment, now) if segment.members.reserved.none?
      return 0
    end

    contacts = account.contacts.where(id: members.map(&:contact_id)).index_by(&:id)
    origin = cfg['route_by_origin'] ? Crm::PatientKind.origin_inbox_by_contact(account, members.map(&:contact_id)) : {}
    blocked = blocked_now(segment, members.map(&:contact_id), now)
    by_inbox = sent_today_by_inbox(segment, now)
    children = {}
    warnings = []
    sent = 0
    members.each_with_index do |member, idx| # rubocop:disable Metrics/BlockLength
      # "Pausar" vale no meio da leva (o robô relê a cada 10 pessoas); a leva forçada vai até o fim
      break if !force && (idx % 10 == 9) && !segment.reload.sending?

      contact = contacts[member.contact_id]
      variant = segment.variant(member.variant_key)
      reason = blocked[member.contact_id]
      reason ||= 'sem telefone' if contact.nil? || contact.phone_number.blank?
      reason ||= 'mensagem não existe mais' if variant.nil?
      if reason
        mark!(member, 'pulado')
        warnings << "#{contact&.name.presence || 'contato'}: pulado (#{reason})" if warnings.size < 10
        next
      end

      inbox = inboxes.find { |i| i.id == origin.dig(member.contact_id, :id) } || default
      origem = inbox
      inbox = default if inbox != default && (by_inbox[inbox.id].to_i >= cfg['inbox_daily_cap'] || !Plan.template_in?(inbox, tpl_of(variant)))
      if by_inbox[inbox.id].to_i >= cfg['inbox_daily_cap']
        warnings << "teto da caixa #{inbox.name} atingido hoje"
        break
      end

      child = children[[variant['key'], inbox.id]] ||= child_for!(segment, variant, inbox)
      conversation = deliver(segment, child, inbox, variant, contact)
      if conversation.nil?
        # o modelo não rendeu (ex.: pessoa sem nome com {{nome}}) ou a pessoa não tem conversa possível
        mark!(member, 'pulado')
        warnings << "#{contact.name.presence || 'contato'}: pulado (a mensagem não pôde ser montada)" if warnings.size < 10
        next
      end

      record!(child, contact, conversation)
      member.update_columns(status: 'enviado', sent_at: Time.current, campaign_id: child.id, conversation_id: conversation.id, # rubocop:disable Rails/SkipsModelValidations
                            inbox_id: inbox.id, updated_at: Time.current)
      by_inbox[inbox.id] = by_inbox[inbox.id].to_i + 1
      sent += 1
      warnings << "#{contact.name.presence || 'contato'}: foi pela caixa padrão (origem #{origem.name})" if inbox != origem && warnings.size < 10
      sleep Plan::THROTTLE_SECONDS
    rescue StandardError => e
      Rails.logger.error "[Crm::SegmentSender] segmento #{segment.id} contato #{member.contact_id}: #{e.message}"
      mark!(member, 'falhou')
      warnings << "falha com um contato: #{e.message.to_s.first(80)}"
    end

    # quem ficou "enviando" sem sair (pausa, teto da caixa) volta para a fila
    segment.members.where(id: members.map(&:id), status: 'enviando').update_all(status: 'reservado', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    children.each_value { |c| refresh_child_stats!(c) }
    bump!(segment, now, sent, warnings)
    finish!(segment, now) if segment.members.reserved.none? && segment.members.where(status: 'enviando').none?
    sent
  end

  # 🔒 reserva da leva: as pessoas desta leva saem de "reservado" para "enviando"
  # numa tacada só — outra leva (mesmo que a trava falhasse) não as pega
  def claim!(segment, size, now)
    ids = segment.members.reserved.order(:id).limit(size).pluck(:id)
    return [] if ids.empty?

    Crm::SegmentMember.where(id: ids, status: 'reservado').update_all(status: 'enviando', updated_at: now) # rubocop:disable Rails/SkipsModelValidations
    segment.members.where(id: ids, status: 'enviando').order(:id).to_a
  end

  # as regras da peneira valem também NA HORA do envio (a fila pode levar dias):
  # não perturbe, consulta/cirurgia marcada e conversa recente → pulado com motivo
  def blocked_now(segment, contact_ids, now) # rubocop:disable Metrics/CyclomaticComplexity
    account = segment.account
    src = Crm::SegmentBuilder.normalize_source(segment.source)
    out = {}
    (Crm::OptOut.excluded_contact_ids(account) & contact_ids).each { |id| out[id] = 'não perturbe' }
    if src['skip_future_appointment']
      (Crm::RecurringCampaign.future_appointment_contact_ids(account, now) & contact_ids).each { |id| out[id] ||= 'consulta marcada' }
    end
    if src['quiet_hours'].positive?
      (Crm::RecurringCampaign.active_conversation_contact_ids(account, src['quiet_hours'], now) & contact_ids).each do |id|
        out[id] ||= 'conversou há pouco'
      end
    end
    out
  end

  def mark!(member, status)
    member.update_columns(status: status, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  # a campanha-filha mostra os números na tela Campanha WhatsApp: total, enviadas e recusadas pela Meta
  def refresh_child_stats!(child)
    total = child.campaign_contacts.count
    failed = child.campaign_contacts.where(delivery_status: 'failed').count
    child.update!(stats: (child.stats || {}).merge('total' => total, 'sent' => total - failed, 'failed' => failed))
    Crm::CampaignRunJob.set(wait: 10.minutes).perform_later(child.id, 'sweep')
  end

  def tpl_of(variant)
    { 'template_params' => variant['template_params'], 'message_preview' => variant['message_preview'] }
  end

  # uma campanha-filha por mensagem × caixa — os resultados aparecem em Campanha WhatsApp
  def child_for!(segment, variant, inbox)
    scope = segment.account.crm_campaigns.where("audience ->> 'segment_id' = ? AND audience ->> 'variant' = ?", segment.id.to_s, variant['key'])
    scope.find_by(inbox_id: inbox.id) || segment.account.crm_campaigns.create!(
      inbox: inbox, sender_id: segment.creator_id,
      name: "#{segment.name} · #{variant['label']} · #{inbox.name}",
      template_params: variant['template_params'], message_preview: variant['message_preview'],
      audience: { 'segment_id' => segment.id, 'variant' => variant['key'], 'segment_kind' => segment.kind },
      status: :completed, started_at: Time.current, finished_at: Time.current
    )
  end

  def deliver(segment, child, inbox, variant, contact)
    source = Plan::Source.new(account: child.account, inbox: inbox, sender: child.sender, template_params: variant['template_params'],
                              message_preview: variant['message_preview'], name: child.name)
    sender = Crm::SendTemplateService.new(source: source, contact: contact)
    conversation = sender.perform
    meta = { 'segment_id' => segment.id, 'variant' => variant['key'], 'kind' => segment.kind, 'template' => variant.dig('template_params', 'name') }
    attrs = (sender.message&.additional_attributes || {}).merge('cevico_segment' => meta)
    sender.message&.update_columns(additional_attributes: attrs) # rubocop:disable Rails/SkipsModelValidations
    conversation
  end

  def record!(child, contact, conversation)
    Crm::CampaignContact.create!(campaign: child, contact: contact, conversation: conversation, sent_at: Time.current)
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def bump!(segment, now, sent, warnings) # rubocop:disable Metrics/AbcSize
    stats = (segment.reload.stats || {}).deep_dup
    stats['sent'] = stats['sent'].to_i + sent
    day = (stats['days'] ||= {})[now.in_time_zone(TZ).to_date.to_s] ||= {}
    day['sent'] = day['sent'].to_i + sent
    stats['last_run_at'] = now.iso8601
    stats['last_run_sent'] = sent
    stats['last_skip'] = nil
    stats['warnings'] = warnings.uniq.first(10)
    segment.update_columns(stats: stats, last_tick_at: now, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
  end

  def skip(segment, reason)
    stats = (segment.reload.stats || {}).merge('last_check_at' => Time.current.iso8601, 'last_skip' => reason)
    segment.update_columns(stats: stats, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    0
  end

  def finish!(segment, now)
    segment.update!(status: 'concluido', finished_at: now)
  end

  # ── projeção para a tela ─────────────────────────────────────────────────
  # quanto tempo falta: levas, horas úteis e dias úteis, no ritmo configurado
  def project(segment, now: Time.current) # rubocop:disable Metrics/AbcSize
    cfg = pace(segment)
    remaining = segment.remaining
    inbox_count = [Plan.whatsapp_inboxes(segment.account).size, 1].max
    per_day = [cfg['per_hour'] * (cfg['hour_to'] - cfg['hour_from']), cfg['daily_cap'].positive? ? cfg['daily_cap'] : Float::INFINITY,
               cfg['inbox_daily_cap'] * inbox_count].min
    { remaining: remaining, step: step_size(cfg), per_day: per_day.to_i,
      steps_left: remaining.positive? ? (remaining / step_size(cfg).to_f).ceil : 0,
      days_left: remaining.positive? && per_day.positive? ? (remaining / per_day.to_f).ceil : 0,
      window_now: window_label(cfg, now),
      next_at: next_at(segment, cfg, now)&.iso8601 }
  end

  # a próxima leva: o relógio da leva (se dentro da janela) ou o começo da próxima janela
  def next_at(segment, cfg, now) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return nil unless segment.sending?

    base = segment.last_tick_at ? segment.last_tick_at + cfg['step_minutes'].minutes : now
    base = now if base < now
    local = base.in_time_zone(TZ)
    8.times do
      return local if (!cfg['weekdays_only'] || !(local.saturday? || local.sunday?)) && local.hour >= cfg['hour_from'] && local.hour < cfg['hour_to']

      local = if local.hour >= cfg['hour_to'] || (cfg['weekdays_only'] && (local.saturday? || local.sunday?))
                (local + 1.day).change(hour: cfg['hour_from'])
              else
                local.change(hour: cfg['hour_from'])
              end
    end
    nil
  end
end
