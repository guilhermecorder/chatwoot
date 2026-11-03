# 📣 PLANO DE REATIVAÇÃO EM FATIAS (item 381, 03/11 — Guilherme: "não posso
# ativar todo mundo de uma vez… 100, 200, 300 mensagens por dia… 10% daqui,
# 50% dessa coluna… reativar toda a base em 4 semanas, sem bloqueio do
# WhatsApp e sem afogar o atendimento; a caixa do Instagram manda para quem
# veio do Instagram").
#
# O plano é uma campanha-MÃE (Crm::Campaign) com a configuração em
# audience['reactivation_plan']; cada DIA × CAIXA vira uma campanha-filha
# (audience['parent_id'] + audience['reactivation_day']) que guarda os
# destinatários (CampaignContact) — assim resultados, respostas e recusas da
# Meta continuam nas telas de sempre. O robô Crm::ReactivationPlanJob roda de
# hora em hora e manda só a fatia daquela hora.
#
# Configuração (audience['reactivation_plan']):
#   daily_cap               mensagens por dia (padrão 300)
#   hour_from / hour_to     janela em SP (padrão 9 → 18; a última hora é 17h)
#   weekdays_only           só dias úteis (padrão true)
#   inbox_daily_cap         teto por caixa por dia (padrão 100; regra dos ~1000/mês)
#   route_by_origin         manda pela caixa da 1ª conversa do paciente (padrão true)
#   default_inbox_id        caixa de quem não tem origem conhecida (padrão: a da mãe)
#   max_open_conversations  pula a hora se houver mais conversas abertas que isto (0 = ignora)
#   quiet_hours / skip_future_appointment / min_age_days  mesmas regras do item 379
#   order                   'recent' (quem se moveu há menos tempo primeiro) | 'oldest'
#   slices[]                { key, stage_id, share (%), templates: { padrao|lentes|catarata => { template_params, message_preview } } }
#
# Cada pessoa recebe UMA mensagem no plano inteiro (quem já está nos
# destinatários da família nunca entra de novo).
module Crm::ReactivationPlan # rubocop:disable Metrics/ModuleLength
  module_function

  TZ = Crm::Campaign::TZ
  KEY = 'reactivation_plan'.freeze
  DAY_KEY = 'reactivation_day'.freeze
  NAME = 'Reativação de fim de ano'.freeze
  THROTTLE_SECONDS = 0.2
  POOL_LIMIT = 3000
  FRENTES = %w[padrao lentes catarata].freeze
  DEFAULTS = {
    'daily_cap' => 300, 'hour_from' => 9, 'hour_to' => 18, 'weekdays_only' => true, 'inbox_daily_cap' => 100,
    'route_by_origin' => true, 'default_inbox_id' => 0, 'max_open_conversations' => 0,
    'quiet_hours' => 24, 'skip_future_appointment' => true, 'min_age_days' => 3, 'order' => 'recent',
    # 🎛️ item 382: controle — aprovação manual de cada lote (padrão), modo de teste com lista de números
    'approval' => 'manual', 'test_mode' => false
  }.freeze
  LIMITS = { 'daily_cap' => 1..5000, 'hour_from' => 0..23, 'hour_to' => 1..24, 'inbox_daily_cap' => 1..5000,
             'default_inbox_id' => 0..999_999_999, 'max_open_conversations' => 0..100_000,
             'quiet_hours' => 0..720, 'min_age_days' => 0..365 }.freeze

  # ── configuração ─────────────────────────────────────────────────────────
  def normalize(raw) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    raw = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
    cfg = {}
    DEFAULTS.each do |key, default|
      value = raw.key?(key) ? raw[key] : default
      cfg[key] = case default
                 when true, false then ActiveModel::Type::Boolean.new.cast(value) == true
                 when Integer then clamp(value, default, LIMITS[key])
                 else enum_value(key, value, default)
                 end
    end
    cfg['hour_to'] = cfg['hour_from'] + 1 if cfg['hour_to'] <= cfg['hour_from']
    cfg['test_phones'] = Array(raw['test_phones']).map { |t| t.to_s.gsub(/\D/, '') }.select { |t| t.size >= 10 }.uniq.first(20)
    cfg['slices'] = normalize_slices(raw['slices'])
    cfg
  end

  ENUMS = { 'order' => %w[recent oldest], 'approval' => %w[manual auto] }.freeze

  def enum_value(key, value, default)
    ENUMS.fetch(key, []).include?(value.to_s) ? value.to_s : default
  end

  def normalize_slices(raw) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    Array(raw).filter_map do |s|
      next unless s.is_a?(Hash)

      s = s.deep_stringify_keys
      stage_id = s['stage_id'].to_i
      next if stage_id <= 0

      templates = (s['templates'].is_a?(Hash) ? s['templates'] : {}).each_with_object({}) do |(frente, t), out|
        next unless FRENTES.include?(frente.to_s) && t.is_a?(Hash) && t['template_params'].is_a?(Hash) && t.dig('template_params', 'name').present?

        out[frente.to_s] = { 'template_params' => t['template_params'], 'message_preview' => t['message_preview'].to_s }
      end
      { 'key' => s['key'].to_s.presence || "col#{stage_id}", 'stage_id' => stage_id,
        'share' => clamp(s['share'], 0, 0..100), 'templates' => templates }
    end
  end

  def clamp(value, default, range)
    n = Integer(value.to_s, 10)
    range.cover?(n) ? n : default
  rescue ArgumentError, TypeError
    default
  end

  def config(mother)
    normalize(mother.audience.is_a?(Hash) ? mother.audience[KEY] : nil)
  end

  def plan?(campaign)
    campaign.audience.is_a?(Hash) && campaign.audience[KEY].is_a?(Hash) && campaign.audience['parent_id'].blank?
  end

  # a mãe do plano desta conta (a mais recente)
  def find(account)
    account.crm_campaigns.where("jsonb_exists(audience, '#{KEY}') AND audience ->> 'parent_id' IS NULL").order(id: :desc).first
  end

  # cria ou atualiza a mãe com a configuração (status não muda; mãe nova = rascunho)
  def upsert!(account, raw, user: nil) # rubocop:disable Metrics/AbcSize
    cfg = normalize(raw)
    mother = find(account) || account.crm_campaigns.new(name: NAME, status: :draft, sender: user)
    inbox = default_inbox(account, cfg, mother)
    raise ArgumentError, 'Escolha uma caixa WhatsApp oficial como padrão' if inbox.nil?

    first = cfg['slices'].flat_map { |s| s['templates'].values }.first
    mother.inbox = inbox
    mother.template_params = first&.dig('template_params').presence || { 'name' => 'reativacao' }
    mother.message_preview = first&.dig('message_preview').to_s
    mother.apply_label = 'reativacao-fim-de-ano'
    mother.audience = (mother.audience || {}).merge(KEY => cfg)
    mother.save!
    mother
  end

  def default_inbox(account, cfg, mother)
    candidates = whatsapp_inboxes(account)
    candidates.find { |i| i.id == cfg['default_inbox_id'] } || candidates.find { |i| i.id == mother.inbox_id } || candidates.first
  end

  # caixas que podem mandar modelo (WhatsApp Cloud) e não são de parceiro
  def whatsapp_inboxes(account)
    partner = Crm::PartnerGuard.partner_inbox_ids(account)
    account.inboxes.where(channel_type: 'Channel::Whatsapp').order(:id).to_a
           .select { |i| i.channel.try(:provider) == 'whatsapp_cloud' && partner.exclude?(i.id) }
  end

  # ── estado ───────────────────────────────────────────────────────────────
  def family_ids(mother)
    Crm::RecurringCampaign.family_ids(mother)
  end

  def children(mother, day: nil)
    scope = mother.account.crm_campaigns.where("audience ->> 'parent_id' = ?", mother.id.to_s)
    day ? scope.where("audience ->> '#{DAY_KEY}' = ?", day.to_s) : scope
  end

  def recipients_ever(mother)
    Crm::CampaignContact.where(campaign_id: family_ids(mother))
  end

  def sent_today(mother, today)
    Crm::CampaignContact.where(campaign_id: children(mother, day: today).select(:id)).count
  end

  def sent_today_by_inbox(mother, today)
    children(mother, day: today).to_a.to_h { |c| [c.inbox_id, c.campaign_contacts.count] }
  end

  def day_stats(mother, today)
    (mother.stats || {}).dig('days', today.to_s) || {}
  end

  # ── a fatia de cada coluna ───────────────────────────────────────────────
  # cards da coluna com telefone, fora quem já recebeu no plano e fora das regras
  def pool(mother, cfg, slice, now: Time.current, limit: POOL_LIMIT)
    account = mother.account
    scope = Crm::Contact.joins(:contact).where(stage_id: slice['stage_id']).where.not(contacts: { phone_number: [nil, ''] })
    scope = scope.where.not(contact_id: recipients_ever(mother).select(:contact_id))
    excluded = excluded_contact_ids(account, cfg, now)
    scope = scope.where.not(contact_id: excluded) if excluded.any?
    scope = scope.where('contacts.created_at <= ?', now - cfg['min_age_days'].days) if cfg['min_age_days'].positive?
    order = cfg['order'] == 'oldest' ? 'crm_contacts.stage_moved_at ASC NULLS LAST' : 'crm_contacts.stage_moved_at DESC NULLS LAST'
    scope.reorder(Arel.sql("#{order}, crm_contacts.id ASC")).limit(limit)
  end

  def pool_rows(mother, cfg, slice, now: Time.current, limit: POOL_LIMIT)
    pool(mother, cfg, slice, now: now, limit: limit).pluck(:contact_id, :procedure_of_interest)
  end

  def excluded_contact_ids(account, cfg, now)
    ids = Crm::OptOut.excluded_contact_ids(account) | Crm::PartnerGuard.excluded_contact_ids(account)
    ids |= Crm::RecurringCampaign.active_conversation_contact_ids(account, cfg['quiet_hours'], now) if cfg['quiet_hours'].positive?
    ids |= Crm::RecurringCampaign.future_appointment_contact_ids(account, now) if cfg['skip_future_appointment']
    ids
  end

  # frente da mensagem pelo procedimento do card
  def frente_of(procedure)
    p = procedure.to_s.downcase
    return 'catarata' if p.include?('catarata')
    return 'lentes' if p.match?(/artisan|f[aá]cic|trifocal|faco|lente|presbi|\bicl\b|multifocal/)

    'padrao'
  end

  def template_for(slice, frente)
    slice['templates'][frente] || slice['templates']['padrao']
  end

  # ── a conta da hora ──────────────────────────────────────────────────────
  # quantas desta hora cabem em cada fatia: alvo do dia por share, menos o já
  # mandado hoje; fatia vazia cede a vez às outras
  def allocate(quota, deficits, pools) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    alloc = Hash.new(0)
    remaining = quota
    open = deficits.select { |k, d| d.positive? && pools[k].to_i.positive? }
    while remaining.positive? && open.any?
      total = open.values.sum.to_f
      step = open.transform_values { |d| [(remaining * d / total).floor, 1].max }
      step.each do |k, n|
        n = [n, open[k], pools[k] - alloc[k], remaining].min
        next if n <= 0

        alloc[k] += n
        remaining -= n
        open[k] -= n
      end
      open = open.select { |k, d| d.positive? && (pools[k] - alloc[k]).positive? }
      break if step.values.all?(&:zero?)
    end
    alloc
  end

  # ── a rodada de uma hora ─────────────────────────────────────────────────
  Source = Struct.new(:account, :inbox, :sender, :template_params, :message_preview, :name, keyword_init: true) do
    def account_id = account.id
    def inbox_id = inbox.id
    def auto_label = 'Campaign'
  end

  # 🎛️ item 382: a rodada passa pelo CONTROLE DO LOTE (Crm::ReactivationBatch):
  #   · aprovação manual (padrão): a hora só PREPARA o lote (pending_batch) e
  #     espera o "Aprovar e enviar" na tela (approved_ids);
  #   · aprovação automática: manda a fatia da hora sozinha;
  #   · force = ignora janela/dia útil (botão "agora"); teto e regras valem sempre.
  def run!(mother, now: Time.current, force: false, approved_ids: nil) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return skip(mother, 'plano não está ativo') unless mother.processing?

    batch = Crm::ReactivationBatch.plan(mother, now: now, force: force)
    if batch[:skip]
      finish_if_exhausted!(mother, batch[:pools]) if batch[:pools] && !batch[:cfg]['test_mode']
      return skip(mother, batch[:skip])
    end
    if batch[:cfg]['approval'] == 'manual' && approved_ids.nil?
      note!(mother, 'last_check_at' => now.iso8601, 'last_skip' => 'aguardando aprovação do lote',
                    'pending_batch' => { 'at' => now.iso8601, 'quota' => batch[:quota], 'remaining_today' => batch[:remaining_today],
                                         'warnings' => batch[:warnings], 'rows' => batch[:rows].first(500).map { |r| r.except(:tpl) } })
      return 0
    end

    rows = approved_ids ? batch[:rows].select { |r| approved_ids.include?(r[:contact_id]) } : batch[:rows]
    Crm::ReactivationBatch.send!(mother, batch, rows, now: now)
  end

  # o modelo precisa existir na caixa de destino; senão vai pela caixa padrão
  def resolve_template(inbox, default, tpl, slice, frente, warnings) # rubocop:disable Metrics/ParameterLists
    return [inbox, tpl] if tpl && template_in?(inbox, tpl)

    if tpl && inbox != default && template_in?(default, tpl)
      warnings << "modelo #{tpl.dig('template_params', 'name')} não existe na caixa #{inbox.name}: foi pela padrão"
      return [default, tpl]
    end

    warnings << "fatia #{slice['key']} (#{frente}) sem modelo aprovado na caixa #{inbox.name}"
    [inbox, nil]
  end

  def template_in?(inbox, tpl)
    name = tpl.dig('template_params', 'name').to_s
    Array(inbox.channel.try(:message_templates)).any? { |t| t['name'] == name && t['status'].to_s.downcase == 'approved' }
  end

  def child_for!(mother, today, inbox, tpl)
    children(mother, day: today).find_by(inbox_id: inbox.id) || mother.account.crm_campaigns.create!(
      inbox: inbox, sender_id: mother.sender_id, name: "#{NAME} · #{today.strftime('%d/%m')} · #{inbox.name}",
      template_params: tpl['template_params'], message_preview: tpl['message_preview'], apply_label: mother.apply_label,
      conversion_stage_ids: mother.conversion_stage_ids, conversion_label_ids: mother.conversion_label_ids,
      audience: { 'parent_id' => mother.id, DAY_KEY => today.to_s }, status: :completed, started_at: Time.current, finished_at: Time.current
    )
  end

  def deliver(child, inbox, tpl, contact, slice: nil, frente: nil) # rubocop:disable Metrics/ParameterLists
    source = Source.new(account: child.account, inbox: inbox, sender: child.sender, template_params: tpl['template_params'],
                        message_preview: tpl['message_preview'], name: child.name)
    sender = Crm::SendTemplateService.new(source: source, contact: contact)
    conversation = sender.perform
    meta = { 'plan_id' => child.parent_id, 'slice' => slice, 'frente' => frente, 'template' => tpl.dig('template_params', 'name') }
    attrs = (sender.message&.additional_attributes || {}).merge('cevico_reactivation' => meta)
    sender.message&.update_columns(additional_attributes: attrs) # rubocop:disable Rails/SkipsModelValidations
    conversation
  end

  def record!(child, contact, conversation, slice_key, frente, plan_id) # rubocop:disable Metrics/ParameterLists
    Crm::CampaignContact.create!(campaign: child, contact: contact, conversation: conversation, sent_at: Time.current)
    title = child.apply_label.to_s.strip.downcase
    return if title.blank?

    child.account.labels.find_or_create_by!(title: title)
    contact.label_list.add(title)
    contact.save!
  rescue ActiveRecord::RecordNotUnique
    nil
  ensure
    Rails.logger.info "[Crm::ReactivationPlan] plano #{plan_id} fatia #{slice_key}/#{frente} → contato #{contact.id}"
  end

  def bump_stats!(mother, today, slice_key, inbox, frente) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    stats = (mother.reload.stats || {}).deep_dup
    stats['sent'] = stats['sent'].to_i + 1
    stats['slices'] ||= {}
    stats['slices'][slice_key] = stats['slices'][slice_key].to_i + 1
    day = (stats['days'] ||= {})[today.to_s] ||= {}
    day['sent'] = day['sent'].to_i + 1
    (day['slices'] ||= {})[slice_key] = day.dig('slices', slice_key).to_i + 1
    (day['inboxes'] ||= {})[inbox.id.to_s] = day.dig('inboxes', inbox.id.to_s).to_i + 1
    (day['frentes'] ||= {})[frente] = day.dig('frentes', frente).to_i + 1
    mother.update_columns(stats: stats, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def note!(mother, extra)
    mother.update_columns(stats: (mother.reload.stats || {}).merge(extra), updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def skip(mother, reason)
    note!(mother, 'last_check_at' => Time.current.iso8601, 'last_skip' => reason)
    0
  end

  def finish_if_exhausted!(mother, pools)
    return if pools.blank? || pools.values.any?(&:present?)

    mother.update!(status: :completed, finished_at: Time.current)
  end

  def open_conversations(account)
    account.conversations.open.count
  end

  # ── para a tela ──────────────────────────────────────────────────────────
  def simulate(mother, cfg, now: Time.current) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    slices = cfg['slices']
    stages = Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: mother.account_id }, id: slices.pluck('stage_id')).index_by(&:id)
    total_share = slices.sum { |s| s['share'] }
    rows = slices.map do |s|
      pool_size = mother.persisted? ? pool(mother, cfg, s, now: now, limit: POOL_LIMIT).count : 0
      per_day = (cfg['daily_cap'] * s['share'] / 100.0).round
      { key: s['key'], stage_id: s['stage_id'], stage_name: stages[s['stage_id']]&.name, share: s['share'],
        pool: pool_size, per_day: per_day, days: per_day.positive? ? (pool_size / per_day.to_f).ceil : nil,
        sent: (mother.stats || {}).dig('slices', s['key']).to_i,
        templates: s['templates'].transform_values { |t| t.dig('template_params', 'name') } }
    end
    total_pool = rows.sum { |r| r[:pool] }
    { slices: rows, total_share: total_share, total_pool: total_pool,
      days_total: cfg['daily_cap'].positive? ? (total_pool / cfg['daily_cap'].to_f).ceil : nil,
      days_max_slice: rows.filter_map { |r| r[:days] }.max }
  end

  def payload(account, now: Time.current) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    mother = find(account)
    cfg = mother ? config(mother) : normalize({})
    inboxes = whatsapp_inboxes(account).map do |i|
      { id: i.id, name: i.name,
        templates: Array(i.channel.try(:message_templates))
          .select { |t| t['status'].to_s.downcase == 'approved' }
          .map { |t| t.slice('name', 'language', 'category', 'namespace', 'components') } }
    end
    today = now.in_time_zone(TZ).to_date
    {
      exists: mother.present?, id: mother&.id, status: mother&.status, config: cfg, inboxes: inboxes,
      stats: mother&.stats || {}, sent_today: mother ? sent_today(mother, today) : 0,
      simulation: mother ? simulate(mother, cfg, now: now) : nil,
      window_now: mother ? window_label(cfg, now) : nil,
      # 🎛️ item 382: lote preparado esperando aprovação (modo manual)
      pending_batch: mother&.stats&.dig('pending_batch')
    }
  end

  def window_label(cfg, now)
    local = now.in_time_zone(TZ)
    return 'fim de semana: não manda' if cfg['weekdays_only'] && (local.saturday? || local.sunday?)
    return "fora do horário (#{cfg['hour_from']}h–#{cfg['hour_to']}h)" unless local.hour >= cfg['hour_from'] && local.hour < cfg['hour_to']

    'dentro do horário de envio'
  end
end
