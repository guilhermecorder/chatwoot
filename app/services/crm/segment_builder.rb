# 🧪 SEGMENTAÇÃO DA BASE (item 383, 03/11 — Guilherme: "quero um ambiente em
# que eu seleciono a base, isolo o que já foi testado, testo 5 mensagens com
# 100 pessoas cada e, quando achar a melhor, escalo de mil em mil").
#
# Aqui mora o que MONTA e RESERVA um segmento:
#   preview  → quantos podem receber e quem ficou de fora (regra a regra)
#   reserve! → congela as pessoas no segmento e sorteia a mensagem de cada uma
#   release! → desfaz uma reserva que ainda não mandou nada
#
# Regras de quem pode entrar (source):
#   stage_ids               colunas do CRM de onde a base sai
#   procedure               'todas' | 'refrativa' | 'lentes' | 'catarata' (pelo procedimento do card)
#   min_age_days            só quem chegou há pelo menos N dias (padrão 3)
#   quiet_hours             fora quem conversou nas últimas N horas (padrão 24)
#   skip_future_appointment fora quem tem consulta/cirurgia marcada (padrão true)
#   exclude_campaign_days   fora quem recebeu QUALQUER campanha há menos de N dias (padrão 30)
#   size                    quantas pessoas (0 = todas as que podem)
#   order                   'random' (sorteio, padrão) | 'recent' | 'oldest' (pela data em que se moveu de coluna)
#   seed                    semente do sorteio (gravada na reserva: o mesmo sorteio sai igual de novo)
# Quem está em QUALQUER segmento (reservado ou enviado) nunca entra em outro:
# é isso que isola o que já foi testado.
module Crm::SegmentBuilder # rubocop:disable Metrics/ModuleLength
  module_function

  TZ = Crm::Campaign::TZ
  POOL_LIMIT = 50_000
  PROCEDURES = %w[todas refrativa lentes catarata].freeze
  ORDERS = %w[random recent oldest].freeze
  LENTES_SQL = 'artisan|f[aá]cic|trifocal|faco|lente|presbi|\yicl\y|multifocal'.freeze
  DEFAULTS = {
    'stage_ids' => [], 'procedure' => 'todas', 'min_age_days' => 3, 'quiet_hours' => 24,
    'skip_future_appointment' => true, 'exclude_campaign_days' => 30, 'size' => 100, 'order' => 'random', 'seed' => ''
  }.freeze
  LIMITS = { 'min_age_days' => 0..365, 'quiet_hours' => 0..720, 'exclude_campaign_days' => 0..365, 'size' => 0..50_000 }.freeze
  # as etapas da peneira, na ordem, com o nome que a tela mostra
  STEPS = {
    'protegidos' => 'não perturbe / paciente de parceiro',
    'conversando' => 'conversou nas últimas horas',
    'consulta_marcada' => 'tem consulta ou cirurgia marcada',
    'muito_novos' => 'chegou há poucos dias',
    'em_segmento' => 'já está em outro segmento',
    'campanha_recente' => 'recebeu campanha há pouco'
  }.freeze

  # ── configuração ─────────────────────────────────────────────────────────
  def normalize_source(raw) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    raw = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
    cfg = {}
    cfg['stage_ids'] = Array(raw['stage_ids']).map(&:to_i).select(&:positive?).uniq.first(30)
    cfg['procedure'] = PROCEDURES.include?(raw['procedure'].to_s) ? raw['procedure'].to_s : 'todas'
    cfg['order'] = ORDERS.include?(raw['order'].to_s) ? raw['order'].to_s : 'random'
    cfg['skip_future_appointment'] = raw.key?('skip_future_appointment') ? truthy?(raw['skip_future_appointment']) : true
    LIMITS.each_key { |k| cfg[k] = clamp(raw[k], DEFAULTS[k], LIMITS[k]) }
    cfg['seed'] = raw['seed'].to_s.first(40)
    cfg
  end

  # até 5 mensagens (A, B, C, D, E); cada uma precisa de um modelo da Meta com nome
  def normalize_variants(raw)
    Array(raw).filter_map { |v| v.is_a?(Hash) ? v.deep_stringify_keys : nil }
              .select { |v| v['template_params'].is_a?(Hash) && v.dig('template_params', 'name').present? }
              .first(Crm::Segment::MAX_VARIANTS)
              .each_with_index.map do |v, i|
      key = ('A'.ord + i).chr
      { 'key' => key, 'label' => v['label'].to_s.strip.presence || "Mensagem #{key}",
        'template_params' => v['template_params'], 'message_preview' => v['message_preview'].to_s }
    end
  end

  def truthy?(value)
    ActiveModel::Type::Boolean.new.cast(value) == true
  end

  def clamp(value, default, range)
    n = Integer(value.to_s, 10)
    range.cover?(n) ? n : default
  rescue ArgumentError, TypeError
    default
  end

  # ── a base ───────────────────────────────────────────────────────────────
  def account_stage_ids(account, ids)
    return [] if ids.empty?

    Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: account.id }, id: ids).pluck(:id)
  end

  # cards das colunas com telefone (a matéria-prima, antes de qualquer regra)
  def base_scope(account, src)
    ids = account_stage_ids(account, src['stage_ids'])
    return Crm::Contact.none if ids.empty?

    scope = Crm::Contact.joins(:contact).where(stage_id: ids).where.not(contacts: { phone_number: [nil, ''] })
    procedure_filter(scope, src['procedure'])
  end

  def procedure_filter(scope, procedure)
    col = "COALESCE(crm_contacts.procedure_of_interest, '')"
    case procedure
    when 'catarata' then scope.where("#{col} ILIKE '%catarata%'")
    when 'lentes' then scope.where("#{col} !~* ? AND #{col} ~* ?", 'catarata', LENTES_SQL)
    when 'refrativa' then scope.where("#{col} !~* ? AND #{col} !~* ?", 'catarata', LENTES_SQL)
    else scope
    end
  end

  # ids que cada regra tira (calculados uma vez por chamada)
  def exclusions(account, src, now) # rubocop:disable Metrics/AbcSize
    out = {}
    out['protegidos'] = Crm::OptOut.excluded_contact_ids(account) | Crm::PartnerGuard.excluded_contact_ids(account)
    out['conversando'] = src['quiet_hours'].positive? ? Crm::RecurringCampaign.active_conversation_contact_ids(account, src['quiet_hours'], now) : []
    out['consulta_marcada'] = src['skip_future_appointment'] ? Crm::RecurringCampaign.future_appointment_contact_ids(account, now) : []
    out['em_segmento'] = Crm::SegmentMember.holding.joins(:segment).where(crm_segments: { account_id: account.id }).distinct.pluck(:contact_id)
    out['campanha_recente'] =
      if src['exclude_campaign_days'].positive?
        Crm::CampaignContact.joins(:campaign).where(crm_campaigns: { account_id: account.id })
                            .where('crm_campaign_contacts.sent_at > ?', now - src['exclude_campaign_days'].days).distinct.pluck(:contact_id)
      else
        []
      end
    out
  end

  # quem pode receber, já peneirado e na ordem pedida
  def pool(account, src, now: Time.current, exclusions: nil)
    scope = base_scope(account, src)
    (exclusions || exclusions(account, src, now)).each_value { |ids| scope = scope.where.not(contact_id: ids) if ids.any? }
    scope = scope.where('contacts.created_at <= ?', now - src['min_age_days'].days) if src['min_age_days'].positive?
    scope.reorder(Arel.sql(order_sql(src)))
  end

  def order_sql(src)
    case src['order']
    when 'recent' then 'crm_contacts.stage_moved_at DESC NULLS LAST, crm_contacts.id ASC'
    when 'oldest' then 'crm_contacts.stage_moved_at ASC NULLS LAST, crm_contacts.id ASC'
    else "md5(crm_contacts.id::text || #{ActiveRecord::Base.connection.quote(src['seed'].to_s)})"
    end
  end

  # ── a peneira, regra a regra (para a tela) ───────────────────────────────
  def preview(account, src, now: Time.current) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    base = base_scope(account, src)
    total = base.count
    ex = exclusions(account, src, now)
    removed = {}
    scope = base
    STEPS.each_key do |key|
      next if key == 'muito_novos'

      before = scope.count
      scope = scope.where.not(contact_id: ex[key]) if ex[key].any?
      removed[key] = before - scope.count
    end
    before = scope.count
    scope = scope.where('contacts.created_at <= ?', now - src['min_age_days'].days) if src['min_age_days'].positive?
    removed['muito_novos'] = before - scope.count
    eligible = scope.count
    will_take = src['size'].positive? ? [src['size'], eligible].min : eligible
    by_stage = stage_rows(account, src, base, scope)
    { base_total: total, eligible: eligible, will_take: will_take,
      removed: STEPS.map { |k, label| { key: k, label: label, count: removed[k].to_i } },
      by_stage: by_stage }
  end

  def stage_rows(account, src, base, eligible_scope)
    names = Crm::Stage.where(id: account_stage_ids(account, src['stage_ids'])).pluck(:id, :name).to_h
    totals = base.group(:stage_id).count
    ok = eligible_scope.group(:stage_id).count
    names.map { |id, name| { stage_id: id, name: name, total: totals[id].to_i, eligible: ok[id].to_i } }
  end

  # visão da base inteira para o topo da tela: cada coluna da casa com
  # quantos têm telefone, quantos já estão em segmento e quantos podem receber
  def base_overview(account, now: Time.current) # rubocop:disable Metrics/AbcSize
    stages = Cevico::ReactivationMessages.house_stages(account)
    return [] if stages.empty?

    ids = stages.pluck(:id)
    src = normalize_source('stage_ids' => ids, 'size' => 0)
    base = base_scope(account, src)
    with_phone = base.group(:stage_id).count
    holding = Crm::SegmentMember.holding.joins(:segment).where(crm_segments: { account_id: account.id }).select(:contact_id)
    in_segment = base.where(contact_id: holding).group(:stage_id).count
    eligible = pool(account, src, now: now).unscope(:order).group(:stage_id).count
    stages.map do |s|
      { stage_id: s[:id], name: s[:name], cards: s[:cards], with_phone: with_phone[s[:id]].to_i,
        in_segment: in_segment[s[:id]].to_i, eligible: eligible[s[:id]].to_i }
    end
  end

  # ── reservar ─────────────────────────────────────────────────────────────
  # congela as pessoas e sorteia a mensagem (A, B, C…) em rodízio, para cada
  # mensagem ficar com o mesmo tanto de gente
  def reserve!(account, name:, kind:, source:, variants:, pace:, user: nil, parent: nil) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    src = normalize_source(source)
    src['seed'] = src['seed'].presence || SecureRandom.hex(4)
    vars = normalize_variants(variants)
    raise ArgumentError, 'Escolha pelo menos uma coluna do CRM' if account_stage_ids(account, src['stage_ids']).empty?
    raise ArgumentError, 'Escolha pelo menos uma mensagem (modelo aprovado)' if vars.empty?
    raise ArgumentError, 'Lote de escala leva UMA mensagem só' if kind == 'escala' && vars.size > 1

    now = Time.current
    rows = pool(account, src, now: now).limit(src['size'].positive? ? src['size'] : POOL_LIMIT).pluck(:contact_id,
                                                                                                      :procedure_of_interest).uniq(&:first)
    raise ArgumentError, 'Ninguém pode receber com essas regras — afrouxe a peneira ou escolha outra coluna' if rows.empty?
    raise ArgumentError, "Poucas pessoas (#{rows.size}) para #{vars.size} mensagens" if rows.size < vars.size

    segment = nil
    Crm::Segment.transaction do
      segment = account_segments(account).create!(
        name: name.to_s.strip.presence || default_name(kind, now), kind: kind, status: 'reservado', creator: user, parent: parent,
        source: src, variants: vars, pace: Crm::SegmentSender.normalize_pace(pace),
        stats: { 'reserved' => rows.size, 'by_variant' => rows.each_index.group_by { |i| vars[i % vars.size]['key'] }.transform_values(&:size) }
      )
      members = rows.each_with_index.map do |(contact_id, procedure), i|
        { segment_id: segment.id, contact_id: contact_id, variant_key: vars[i % vars.size]['key'], status: 'reservado',
          frente: Crm::ReactivationPlan.frente_of(procedure), created_at: now, updated_at: now }
      end
      members.each_slice(2000) { |slice| Crm::SegmentMember.insert_all(slice) } # rubocop:disable Rails/SkipsModelValidations
    end
    segment
  end

  def account_segments(account)
    Crm::Segment.where(account_id: account.id)
  end

  def default_name(kind, now)
    "#{kind == 'escala' ? 'Escala' : 'Teste'} · #{now.in_time_zone(TZ).strftime('%d/%m %H:%M')}"
  end

  # desfaz uma reserva que ainda não mandou nada (as pessoas voltam para a base)
  def release!(segment)
    raise ArgumentError, 'Este segmento já mandou mensagem: não dá para apagar (pause ou deixe concluir)' unless segment.editable_variants?

    segment.destroy!
  end
end
