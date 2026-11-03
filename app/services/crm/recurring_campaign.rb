# 🔁 CAMPANHA RECORRENTE (item 379, 03/11 — Guilherme: "campanhas periódicas
# para quem está na coluna de orçamento e de novos contatos, para fazer a
# cirurgia ainda este ano").
#
# Uma campanha "mãe" guarda o público e a cadência em audience['recurrence'];
# a cada vencimento o agendador (Crm::SchedulerJob, a cada 5 min) cria uma
# campanha-FILHA (cópia da mãe, audience['parent_id'] = mãe) e manda rodar
# pelo Crm::CampaignRunJob de sempre. Assim cada rodada tem os seus próprios
# números, resultados e recusas da Meta, e a mãe só marca a próxima data.
#
# Regras da cadência (audience['recurrence'], todas opcionais):
#   enabled                 true = recorrente (a mãe fica "Agendada" com a próxima rodada)
#   every_days              a cada N dias (padrão 15)
#   hour                    hora de São Paulo da rodada (padrão 9)
#   weekdays_only           cai em sábado/domingo → próxima segunda (padrão true)
#   resend_after_days       não repete para quem recebeu QUALQUER rodada desta
#                           campanha há menos de N dias (padrão 30; 0 = pode repetir)
#   quiet_hours             pula quem teve conversa com movimento nas últimas N horas
#                           (padrão 24; 0 = não pula) — atendimento em andamento
#   skip_future_appointment pula quem tem consulta/cirurgia marcada daqui para frente (padrão true)
#   min_age_days            só quem chegou há pelo menos N dias (padrão 3; 0 = todos)
#   max_per_run             teto de pessoas por rodada (padrão 150; os mais antigos primeiro)
#
# Sem migration: tudo mora no jsonb `audience` que a campanha já tem.
module Crm::RecurringCampaign # rubocop:disable Metrics/ModuleLength
  module_function

  TZ = Crm::Campaign::TZ
  DEFAULTS = {
    'every_days' => 15, 'hour' => 9, 'weekdays_only' => true, 'resend_after_days' => 30,
    'quiet_hours' => 24, 'skip_future_appointment' => true, 'min_age_days' => 3, 'max_per_run' => 150
  }.freeze
  LIMITS = { 'every_days' => 1..365, 'hour' => 0..23, 'resend_after_days' => 0..365, 'quiet_hours' => 0..720,
             'min_age_days' => 0..365, 'max_per_run' => 1..5000 }.freeze
  NAME_DATE = '%d/%m'.freeze

  # regras limpas (tipos certos, dentro dos limites) ou nil quando não é recorrente
  def rules(audience)
    raw = audience.is_a?(Hash) ? audience['recurrence'] : nil
    return nil unless raw.is_a?(Hash) && truthy?(raw['enabled'])

    out = { 'enabled' => true }
    DEFAULTS.each do |key, default|
      value = raw.key?(key) ? raw[key] : default
      out[key] = if [true, false].include?(default)
                   truthy?(value)
                 else
                   clamp(value, default, LIMITS[key])
                 end
    end
    out
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

  # mãe = tem regras e não é filha de ninguém
  def mother?(campaign)
    rules(campaign.audience).present? && campaign.audience['parent_id'].blank?
  end

  def parent_id(campaign)
    campaign.audience.is_a?(Hash) ? campaign.audience['parent_id'].to_i : 0
  end

  # a mãe e todas as rodadas dela (para "quem já recebeu")
  def family_ids(campaign)
    root = parent_id(campaign).positive? ? parent_id(campaign) : campaign.id
    return [] if root.blank?

    children = Crm::Campaign.where(account_id: campaign.account_id)
                            .where("audience ->> 'parent_id' = ?", root.to_s).pluck(:id)
    ([root] + children).uniq
  end

  # ── a próxima rodada ────────────────────────────────────────────────────
  # depois de `from` (hora de SP): mesma hora da regra, N dias à frente; sábado
  # e domingo pulam para segunda quando weekdays_only. Nunca no passado.
  # first: true = a PRIMEIRA rodada (hoje na hora da regra se ainda não passou;
  # senão o próximo dia na mesma hora).
  def next_run_at(rules, from: Time.current, first: false)
    now = Time.current
    candidate = from.in_time_zone(TZ).change(hour: rules['hour'], min: 0, sec: 0)
    step = first ? 1.day : rules['every_days'].days
    candidate += step unless first
    candidate += step while candidate <= now
    candidate = skip_weekend(candidate) if rules['weekdays_only']
    candidate
  end

  def skip_weekend(time)
    time += 1.day while time.saturday? || time.sunday?
    time
  end

  # ── a rodada ─────────────────────────────────────────────────────────────
  # cria a filha (cópia da mãe com parent_id), manda rodar e marca a próxima
  # data na mãe. Devolve a filha (ou nil se a mãe não é recorrente).
  def spawn!(mother, now: Time.current) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    r = rules(mother.audience)
    return nil if r.blank?

    child = nil
    Crm::Campaign.transaction do
      child = mother.account.crm_campaigns.create!(
        inbox_id: mother.inbox_id, sender_id: mother.sender_id,
        name: "#{mother.name} · rodada #{now.in_time_zone(TZ).strftime(NAME_DATE)}",
        template_params: mother.template_params, message_preview: mother.message_preview,
        apply_label: mother.apply_label, conversion_stage_ids: mother.conversion_stage_ids,
        conversion_label_ids: mother.conversion_label_ids,
        audience: mother.audience.merge('parent_id' => mother.id),
        status: :processing, started_at: now
      )
      stats = (mother.stats || {}).merge(
        'runs' => (mother.stats || {})['runs'].to_i + 1, 'last_run_at' => now.iso8601, 'last_child_id' => child.id
      )
      mother.update!(status: :scheduled, scheduled_at: next_run_at(r, from: now), stats: stats)
    end
    Crm::CampaignRunJob.perform_later(child.id)
    child
  end

  # ── exclusões da rodada (usadas por Crm::Campaign#resolve_audience) ──────
  # ids de quem fica de fora por causa das regras da cadência
  def excluded_ids(campaign, rules, now: Time.current)
    ids = []
    ids |= recent_recipient_ids(campaign, rules['resend_after_days'], now) if rules['resend_after_days'].positive?
    ids |= active_conversation_contact_ids(campaign.account, rules['quiet_hours'], now) if rules['quiet_hours'].positive?
    ids |= future_appointment_contact_ids(campaign.account, now) if rules['skip_future_appointment']
    ids
  end

  # recebeu qualquer rodada desta campanha há menos de N dias
  def recent_recipient_ids(campaign, days, now)
    family = family_ids(campaign)
    return [] if family.empty?

    Crm::CampaignContact.where(campaign_id: family).where('sent_at > ?', now - days.days).distinct.pluck(:contact_id)
  end

  # conversa com movimento (qualquer caixa) nas últimas N horas = atendimento em andamento
  def active_conversation_contact_ids(account, hours, now)
    account.conversations.where('last_activity_at > ?', now - hours.hours).where.not(contact_id: nil).distinct.pluck(:contact_id)
  end

  # consulta ou cirurgia marcada daqui para frente (não cancelada)
  def future_appointment_contact_ids(account, now)
    account.tasks.where(task_type: %w[consulta cirurgia], canceled_at: nil).where('due_at >= ?', now)
           .where.not(contact_id: nil).distinct.pluck(:contact_id)
  end

  # só quem chegou há pelo menos N dias; e o teto da rodada (mais antigos primeiro)
  def shape(contacts, rules, now: Time.current)
    contacts = contacts.where('contacts.created_at <= ?', now - rules['min_age_days'].days) if rules['min_age_days'].positive?
    capped = contacts.reorder('contacts.created_at ASC, contacts.id ASC').limit(rules['max_per_run']).pluck(:id, :created_at).map(&:first)
    contacts.unscope(:order).where(id: capped)
  end

  # texto da cadência para a tela ("a cada 15 dias às 9h, só dias úteis")
  def label(rules)
    return nil if rules.blank?

    dias = rules['every_days'] == 1 ? 'todo dia' : "a cada #{rules['every_days']} dias"
    "#{dias} às #{rules['hour']}h#{rules['weekdays_only'] ? ', só dias úteis' : ''}"
  end
end
