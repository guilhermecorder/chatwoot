# 🔎 CONFERÊNCIA DO DIA — hub do Oftalmofácil × nossa Agenda (item 249, 26/09).
#
# Pergunta que a equipe faz toda semana: "as cirurgias de segunda estão na
# Agenda?". Este serviço responde item por item, para UMA data:
#   · o que o hub tem marcado para o dia (espelho e, se pedido, o próprio
#     banco do hub, só leitura — pega o que o incremental nunca leu);
#   · se cada item virou agendamento na nossa Agenda;
#   · quando não virou (ou virou errado), POR QUÊ — em palavras simples;
#   · e `reconcile!` traz para a Agenda o que faltou, sem recarregar tudo.
#
# Situações de um item (campo `situation`):
#   ok              está na Agenda, no dia certo, com local
#   sem_agendamento o hub tem, a Agenda não (reprocessar resolve)
#   nao_lido        está no hub e nunca chegou ao espelho (cursor pulou)
#   hora_errada     está na Agenda mas em outro dia/hora (ex.: 21h da véspera)
#   sem_local       está na Agenda sem local (clínica sem de-para) — some nas
#                   abas por unidade, aparece só na visão geral
#   cancelado_aqui  o hub diz marcada, mas a equipe cancelou na nossa Agenda
#   arquivado       agendamento arquivado na nossa Agenda
#   antes_da_janela data anterior à janela da Agenda unificada (agenda_from)
#   agenda_desligada a Agenda unificada está desligada no card do Oftalmofácil
#   cancelada       cancelada no hub (não deve aparecer na Agenda — normal)
class Crm::OftalmofacilDayCheck # rubocop:disable Metrics/ClassLength
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  PROBLEMS = %w[sem_agendamento nao_lido hora_errada sem_local cancelado_aqui arquivado antes_da_janela agenda_desligada].freeze
  FIXABLE = %w[sem_agendamento nao_lido hora_errada].freeze
  LABELS = {
    'ok' => 'Na Agenda', 'sem_agendamento' => 'Falta na Agenda', 'nao_lido' => 'Hub tem, sistema nunca leu',
    'hora_errada' => 'Na Agenda em outro dia/hora', 'sem_local' => 'Na Agenda sem local', 'cancelado_aqui' => 'Cancelada na nossa Agenda',
    'arquivado' => 'Arquivada na nossa Agenda', 'antes_da_janela' => 'Antes da janela da Agenda',
    'agenda_desligada' => 'Agenda unificada desligada', 'cancelada' => 'Cancelada no hub'
  }.freeze

  attr_reader :account, :date, :config

  # próximo dia útil: sábado/domingo → segunda; senão amanhã
  def self.default_date(now = TZ.now)
    d = now.to_date + 1
    d += 1 while d.saturday? || d.sunday?
    d
  end

  def initialize(account:, date:, config: nil)
    @account = account
    @date = date.to_date
    @config = config || (CrmSetting.find_by(account: account)&.agenda_config || {})['oftalmofacil'] || {}
  end

  # hub: true = também consulta o banco do hub (só leitura) para achar itens que nunca vieram
  def report(hub: false)
    mirror = mirror_scope.order(:surgery_hour, :id).to_a
    tokens = mirror.map(&:item_token)
    remote = hub ? remote_rows : { checked: false }
    rows = mirror_rows(mirror, tokens) + unread_rows(remote, tokens)
    {
      date: date.iso8601, weekday: Crm::AgendaSlots::WEEKDAYS[date.wday],
      config: config_summary, hub: remote.except(:rows),
      rows: rows.sort_by { |r| [r[:hour].to_s, r[:patient].to_s] },
      strays: stray_tasks(tokens).map { |t| stray_row(t) },
      summary: summary_for(rows)
    }
  end

  # traz para a Agenda o que dá para trazer: primeiro pelo hub (linhas frescas);
  # se o hub não responder, pelo espelho. Devolve o relatório depois da correção.
  def reconcile!
    before = report(hub: true)
    if config['agenda_enabled'] != true && before[:summary]['problemas'].to_i.positive?
      return before.merge(fixed: 0,
                          errors: ['Ligue a Agenda unificada no card do Oftalmofácil (Integrações) antes de trazer os agendamentos.'])
    end

    fix_tokens = before[:rows].select { |r| FIXABLE.include?(r[:situation]) }.pluck(:token)
    return before.merge(fixed: 0, errors: ['Nada a corrigir neste dia.']) if fix_tokens.empty?

    result = reprocess(fix_tokens, hub_ok: before[:hub][:checked])
    report(hub: false).merge(fixed: result.pulled, tasks_created: result.tasks_created, tasks_updated: result.tasks_updated,
                             errors: result.errors.first(10))
  end

  private

  def mirror_rows(mirror, tokens)
    tasks = account.tasks.where(external_ref: tokens).index_by(&:external_ref)
    mirror.map { |s| row_for(s, tasks[s.item_token]) }
  end

  def reprocess(fix_tokens, hub_ok:)
    service = Crm::OftalmofacilSyncService.new(account: account, config: config, silent: true, since: nil)
    return service.reapply_from_mirror!(mirror_scope.where(item_token: fix_tokens)) unless hub_ok

    fresh = Array(remote_rows[:rows]).select { |raw| fix_tokens.include?(raw['SCH_ITE_TOKEN'].to_s) }
    service.reprocess_rows!(fresh)
  end

  # itens que estão no hub e não no espelho (o incremental nunca leu)
  def unread_rows(remote, tokens)
    Array(remote[:rows]).filter_map do |raw|
      token = raw['SCH_ITE_TOKEN'].to_s
      next if token.blank? || tokens.include?(token)

      remote_row(raw)
    end
  end

  def summary_for(rows)
    summary = rows.group_by { |r| r[:situation] }.transform_values(&:size)
    summary.merge('total' => rows.size,
                  'problemas' => rows.count { |r| PROBLEMS.include?(r[:situation]) },
                  'corrigiveis' => rows.count { |r| FIXABLE.include?(r[:situation]) })
  end

  def mirror_scope
    Crm::OftalmofacilSurgery.where(account_id: account.id, surgery_date: date)
  end

  def config_summary
    {
      enabled: config['enabled'] == true, agenda_enabled: config['agenda_enabled'] == true,
      agenda_from: agenda_from.iso8601, partners_enabled: config['partners_enabled'] == true,
      last_sync_at: config['last_sync_at'], last_run_at: config['last_run_at'],
      last_errors: Array(config.dig('last_result', 'errors')).first(5), error_count: config.dig('last_result', 'error_count').to_i
    }
  end

  def agenda_from
    Date.parse(config['agenda_from'].to_s)
  rescue ArgumentError, TypeError
    Date.current.beginning_of_week
  end

  def own_provider?(name)
    own = config['provider_name'].to_s.strip.downcase
    own.present? && name.to_s.downcase.include?(own)
  end

  def unit_for(clinic_name)
    map = config['clinics'] || {}
    key = clinic_name.to_s.strip.downcase
    return nil if key.blank?

    hit = map.find { |name, _u| name.to_s.strip.downcase == key }
    hit && hit[1].presence
  end

  def kind_label(procedure_type)
    t = procedure_type.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase
    return 'exame' if t.include?('exam')
    return 'pós-op' if t.match?(/p[o]s.?op|pos.?operat|retorno p/)
    return 'consulta' if t.include?('consult')

    'cirurgia'
  end

  def row_for(surgery, task) # rubocop:disable Metrics/AbcSize
    partner = !own_provider?(surgery.provider_name)
    unit = unit_for(surgery.clinic_name) || task&.unit
    situation, reason = situation_for(surgery, task, partner, unit)
    base_row(token: surgery.item_token, patient: surgery.patient_name, phone: surgery.patient_phone, hour: surgery.hour_hhmm,
             clinic: surgery.clinic_name, unit: unit, provider: surgery.provider_name,
             status_label: surgery.status_kind_label, procedure: [surgery.procedure_name, surgery.eye],
             kind: kind_label(surgery.procedure_type), situation: situation, reason: reason)
      .merge(mirror_id: surgery.id, status_kind: surgery.status_kind, contact_id: surgery.contact_id,
             applied_action: surgery.applied_action, applied_at: surgery.applied_at, task: task_json(task))
  end

  def task_json(task)
    return nil if task.nil?

    { id: task.id, due_at: task.due_at&.in_time_zone(TZ)&.iso8601, unit: task.unit, status: task.status,
      canceled: task.canceled_at.present?, archived: task.archived_at.present? }
  end

  def base_row(token:, patient:, phone:, hour:, clinic:, unit:, provider:, status_label:, procedure:, kind:, situation:, reason:) # rubocop:disable Metrics/ParameterLists
    {
      token: token, patient: patient.to_s.presence || 'Paciente', phone_tail: phone.to_s.gsub(/\D/, '').last(4).presence,
      hour: hour, clinic: clinic, unit: unit, unit_label: Crm::AgendaSlots::UNIT_LABELS[unit.to_s] || unit,
      provider: provider, own: own_provider?(provider), status_label: status_label,
      procedure: Array(procedure).compact_blank.join(' · '), kind: kind,
      situation: situation, situation_label: LABELS[situation], reason: reason
    }
  end

  def situation_for(surgery, task, partner, unit) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return ['cancelada', nil] if surgery.status_kind == 'cancelada' && (task.nil? || task.canceled_at.present?)
    return missing_situation(surgery, partner) if task.nil?
    return ['arquivado', nil] if task.archived_at.present?
    return ['cancelado_aqui', 'o hub diz marcada; confira antes de reabrir'] if task.canceled_at.present?

    due = task.due_at&.in_time_zone(TZ)
    return ['hora_errada', due ? "na Agenda está em #{due.strftime('%d/%m %H:%M')}" : 'sem data na Agenda'] if due.nil? || due.to_date != date
    return ['sem_local', "clínica \"#{surgery.clinic_name}\" sem de-para em Integrações"] if unit.blank?

    ['ok', nil]
  end

  def missing_situation(surgery, partner)
    return ['agenda_desligada', 'ligue a Agenda unificada no card do Oftalmofácil'] unless config['agenda_enabled'] == true
    return ['antes_da_janela', "a janela começa em #{agenda_from.strftime('%d/%m/%Y')}"] if surgery.surgery_date < agenda_from

    why = if surgery.applied_at.present?
            "tratado em #{surgery.applied_at.in_time_zone(TZ).strftime('%d/%m %H:%M')} sem virar agendamento"
          else
            'nunca tratado'
          end
    why = "#{why} · parceiro #{surgery.provider_name}" if partner
    ['sem_agendamento', why]
  end

  # item que está no hub e não no espelho (o incremental nunca leu)
  def remote_row(raw)
    base_row(token: raw['SCH_ITE_TOKEN'].to_s, patient: raw['SCH_PATIENT_NAME'], phone: raw['SCH_PATIENT_PHONE'],
             hour: Crm::OftalmofacilSurgery.normalize_hour(raw['SCH_ITE_HOUR']), clinic: raw['CLI_NAME'],
             unit: unit_for(raw['CLI_NAME']), provider: raw['PROV_NAME'], status_label: raw['STATUS_LABEL'].to_s,
             procedure: [raw['PRO_NAME'], raw['EYE_VALUE']], kind: kind_label(raw['PRO_TYP_VALUE']),
             situation: 'nao_lido', reason: "criado no hub em #{raw['SCH_ITE_DATE_CREATION'].to_s[0, 16]}; reprocessar traz")
      .merge(mirror_id: nil, status_kind: nil, task: nil)
  end

  def remote_rows
    return { checked: false, error: 'Conexão com o hub não configurada.' } unless Crm::OftalmofacilSyncService.configured?(config)

    service = Crm::OftalmofacilSyncService.new(account: account, config: config, silent: true, since: nil)
    rows = service.pull_day(date)
    raw = begin
      service.count_raw_dates([date])
    rescue StandardError
      nil
    end
    { checked: true, total: rows.size, raw_total: raw, incomplete: raw ? [raw - rows.size, 0].max : nil, rows: rows }
  rescue StandardError => e
    { checked: false, error: "Hub não respondeu: #{e.message.truncate(120)}" }
  end

  # agendamentos do Oftalmofácil que estão NESTE dia na Agenda, mas cujo item
  # do hub está em outra data (ou sumiu do espelho)
  def stray_tasks(tokens)
    day = TZ.local(date.year, date.month, date.day)
    scope = account.tasks.where(source: 'oftalmofacil', archived_at: nil).where(due_at: day..day.end_of_day)
    scope = scope.where.not(external_ref: tokens) if tokens.any?
    scope.order(:due_at).limit(50)
  end

  def stray_row(task)
    hub = Crm::OftalmofacilSurgery.find_by(account_id: account.id, item_token: task.external_ref)
    { task_id: task.id, title: task.title, due_at: task.due_at&.in_time_zone(TZ)&.iso8601,
      hub_date: hub&.surgery_date&.strftime('%d/%m/%Y'), hub_status: hub&.status_kind_label }
  end
end
