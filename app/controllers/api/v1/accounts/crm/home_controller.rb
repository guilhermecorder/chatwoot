# Meu Painel: boas-vindas + indicadores com preset de período
# (hoje/ontem/essa semana/este mês/mês passado/este ano) + avisos do Radar.
# Tudo no fuso da clínica (São Paulo).
#
# PAINÉIS POR TEMA (?panel=): mesmo layout, indicadores da função:
# - agendamento (padrão): espelha o CRM em coorte — leads que
#   chegaram no período e até onde avançaram no funil.
# - conducao: condução do paciente na clínica — consultas do
#   período, comparecimento, faltas e indicações de cirurgia (Agenda).
# - cirurgia: fechamento — indicações, cirurgias agendadas/
#   realizadas e taxa de fechamento.
# - medico (?doctor=Nome): a agenda de cada médico — consultas, presença,
#   indicações e cirurgias dele.
class Api::V1::Accounts::Crm::HomeController < Api::V1::Accounts::BaseController
  include Crm::ResolvesPeriod
  include Crm::ResponseGoal

  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  def show
    since, until_at = resolve_range

    render json: {
      period: params[:preset].presence || 'today',
      panel: panel_key,
      panel_data: panel_data(since, until_at),
      # termômetros de agora (independem do período)
      open_conversations: account.conversations.open.count,
      unanswered: account.conversations.open.where.not(waiting_since: nil).count,
      appointments_today: active_consultas.where(due_at: TZ.now.all_day).count,
      new_contacts_30d: leads_count(30.days.ago, Time.current),
      appointments_30d: reached_stage_count(/agendamento/i, 30.days.ago, Time.current),
      next_appointments: next_appointments_json,
      opportunity_alerts: opportunity_alerts_json,
      # meta de tempo de atendimento (relatório pessoal por atendente)
      response_goal: response_goal_json(since, until_at),
      # Mentor do Time: feedback semanal individual (admin vê o time)
      weekly_feedback: weekly_feedback_json,
      my_tasks: my_tasks_json,
      bug_reports: bug_reports_json,
      # status dos números de WhatsApp (item 88 — só o gestor vê)
      whatsapp_status: whatsapp_status_json,
      # 📊 Gestor Autônomo (item 128): briefing do dia + desvios (gestão)
      manager_brief: manager_brief_json,
      # metas do painel + fator do período + recordes (cards vivos)
      goals: goals_json
    }.merge(panel_key == 'agendamento' ? panel_data(since, until_at) : {}) # compat: campos antigos no topo
  end

  # briefing diário do Gestor Autônomo — admin vê tudo; atendente comum não
  # (as tarefas dos desvios já chegam a cada responsável pelo "esperando você")
  def manager_brief_json
    return nil unless Current.account_user.administrator?

    state = (CrmSetting.find_by(account: account)&.ai_config || {})['manager_state']
    return nil if state.blank? || state['last_run_at'].blank?

    {
      last_run_at: state['last_run_at'],
      brief: state['brief'],
      findings: Array(state['findings']).first(3),
      tasks_opened: state['tasks_opened']
    }
  end

  # item 88: cada número de WhatsApp com o estado evidente — precisa
  # reautorizar? teve falha de envio nas últimas 24h?
  def whatsapp_status_json
    return nil unless Current.account_user.administrator?

    inboxes = account.inboxes.where(channel_type: 'Channel::Whatsapp').includes(:channel)
    return nil if inboxes.empty?

    inboxes.map do |inbox|
      channel = inbox.channel
      reauth = channel.try(:reauthorization_required?) || false
      failed = inbox.messages.outgoing.where(status: :failed)
                    .where('messages.created_at >= ?', 24.hours.ago).count
      health = whatsapp_health_cached(channel)
      {
        id: inbox.id,
        name: inbox.name,
        phone: channel.try(:phone_number),
        reauthorization_required: reauth,
        failed_24h: failed,
        ok: !reauth && failed.zero?,
        # status da CONTA na Meta (pedido 20/07): qualidade + limite de
        # mensagens/dia + situação do nome — o que interessa ao gestor
        quality: health&.dig(:quality_rating),
        limit_tier: health&.dig(:messaging_limit_tier),
        name_status: health&.dig(:name_status),
        verified_name: health&.dig(:verified_name)
      }
    end
  end

  # a Meta é consultada no máximo a cada 10 min por número (falha também
  # fica em cache — canal que não é Cloud API não trava o painel)
  def whatsapp_health_cached(channel)
    Rails.cache.fetch("cevico/wa_health/#{channel.id}", expires_in: 10.minutes) do
      Whatsapp::HealthService.new(channel).fetch_health_status || {}
    rescue StandardError
      {}
    end.presence
  end

  # ── popup "prioridade máxima" do Radar ──
  # Checagem LEVE chamada pelo painel global: devolve o aviso mais urgente
  # do usuário logado cuja conversa AINDA está esperando há 20+ minutos
  # (re-checa ao vivo — se alguém já respondeu, não incomoda ninguém).
  POPUP_WAIT_MINUTES = 20

  def radar_ping # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    settings = CrmSetting.find_by(account: account)
    cfg = settings&.ai_config || {}
    return render json: { alert: nil, radar: radar_status(cfg) } unless cfg.dig('agents', 'opportunity', 'enabled') == true

    alerts = Array(cfg.dig('opportunity_state', 'alerts')).reverse
    # o popup é da tela do atendente ESPECÍFICO: aviso direcionado a mim,
    # ou aviso geral (sem destino) quando não sou admin
    alerts = alerts.select do |a|
      a['user_id'].present? ? a['user_id'].to_i == Current.user.id : !Current.account_user.administrator?
    end

    live = alerts.lazy.filter_map do |a|
      conversation = account.conversations.find_by(display_id: a['conversation_id'])
      next unless conversation&.open? && conversation.waiting_since.present?

      minutes = ((Time.current - conversation.waiting_since) / 60).floor
      next if minutes < POPUP_WAIT_MINUTES

      a.merge('waiting_minutes' => minutes)
    end.first

    render json: { alert: live, radar: radar_status(cfg) }
  end

  # pausar/reativar o radar é decisão de gestão — SÓ ADMIN (pedido 17/07);
  # fica registrado quem e quando
  def toggle_radar # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    return render json: { error: 'Só administradores pausam o Radar.' }, status: :forbidden unless Current.account_user.administrator?

    settings = CrmSetting.find_by(account: account) || CrmSetting.create!(account: account)
    cfg = settings.ai_config || {}
    cfg['agents'] ||= {}
    cfg['agents']['opportunity'] ||= {}
    enabled = cfg['agents']['opportunity']['enabled'] == true
    cfg['agents']['opportunity']['enabled'] = !enabled
    state = cfg['opportunity_state'] ||= {}
    log = Array(state['manual_log'])
    log << { 'action' => enabled ? 'desativado' : 'ativado', 'user' => Current.user.name, 'at' => Time.current.iso8601 }
    state['manual_log'] = log.last(20)
    settings.update!(ai_config: cfg)
    render json: { radar: radar_status(cfg) }
  end

  private

  def radar_status(cfg)
    last = Array(cfg.dig('opportunity_state', 'manual_log')).last
    {
      enabled: cfg.dig('agents', 'opportunity', 'enabled') == true,
      last_action: last
    }
  end

  def account
    Current.account
  end

  BUILTIN_PANELS = %w[agendamento conducao cirurgia medico gestor].freeze

  # painéis salvos no Construtor ('custom:<id>') — valem como painel do Meu
  # Painel e como atribuição do time
  def custom_panel_keys
    Array(crm_settings&.agenda_config&.dig('custom_panels')).map { |p| "custom:#{p['id']}" }
  end

  def panel_key
    @panel_key ||= begin
      valid = BUILTIN_PANELS + custom_panel_keys
      default_key = crm_settings&.agenda_config&.dig('main_panel').presence || 'agendamento'
      default_key = 'agendamento' unless valid.include?(default_key)
      key = params[:panel].presence || default_key
      # agente com painel ATRIBUÍDO pelo admin fica travado nele
      unless Current.account_user.administrator?
        assigned = crm_settings&.agenda_config&.dig('panel_assignments', Current.user.id.to_s)
        key = assigned if assigned.present?
      end
      valid.include?(key) ? key : default_key
    end
  end

  def crm_settings
    @crm_settings ||= CrmSetting.find_by(account: account)
  end

  def panel_data(since, until_at)
    # painéis da AGENDA contam o período-calendário inteiro (a consulta de
    # hoje à tarde conta em "Hoje"); o de leads corta em "agora" (coorte).
    # Painéis do Construtor (custom:*) usam o superset do gestor — é dele
    # que os widgets do Construtor leem os indicadores.
    @panel_data ||= case panel_key
                    when 'conducao' then conducao_metrics(since, agenda_until(until_at))
                    when 'cirurgia' then cirurgia_metrics(since, agenda_until(until_at))
                    when 'medico'   then medico_metrics(since, agenda_until(until_at))
                    when 'gestor', /\Acustom:/ then gestor_metrics(since, until_at)
                    else agendamento_metrics(since, until_at)
                    end
  end

  # ── Painel Gestor — indicadores-chave do processo INTEIRO ──
  def gestor_metrics(since, until_at)
    ag = agendamento_metrics(since, until_at)
    full_until = agenda_until(until_at)
    periodo = consultas.where(canceled_at: nil, due_at: since..full_until)
    compareceu = periodo.where(attendance: 'attended').count
    faltou = periodo.where(attendance: 'missed').count
    indicacoes = periodo.where(surgery_indication: 'indicated').count
    agendadas = cirurgias.where(created_at: since..until_at).count
    realizadas_scope = cirurgias.where(due_at: since..full_until)
    ag.merge(
      show_rate: pct(compareceu, compareceu + faltou),
      indications: indicacoes,
      surgeries_booked: agendadas,
      closing_rate: pct(agendadas, indicacoes),
      surgeries_done: realizadas_scope.where(attendance: 'attended').or(realizadas_scope.where(status: :done)).count,
      nps: nps_summary
    )
  end

  # NPS via etiquetas do agente de NPS (5 faixas: 9-10 ... 1-2)
  def nps_summary
    counts = Crm::NpsService::NPS_LABELS.index_with do |tag|
      account.contacts.tagged_with(tag).count
    rescue StandardError
      0
    end
    total = counts.values.sum
    {
      promoters: counts['nps-9-10'], passives: counts['nps-7-8'],
      detractors: counts['nps-1-2'] + counts['nps-3-4'],
      total: total,
      satisfaction: total.positive? ? (counts['nps-9-10'].to_f / total * 100).round(1) : nil
    }
  end

  def agenda_until(until_at)
    now = TZ.now
    case params[:preset]
    when 'week'  then now.end_of_week.end_of_day
    when 'month' then now.end_of_month.end_of_day
    when 'year'  then now.end_of_year.end_of_day
    when 'yesterday', 'last_week', 'last_month' then until_at
    else now.end_of_day # hoje
    end
  end

  # ── Painel Agendamento — coorte pelo dia em que o lead chegou ──
  def agendamento_metrics(since, until_at)
    universe = leads_scope(since, until_at)
    leads = universe.count
    agendadas = reached_stage_count(/agendamento/i, since, until_at, universe: universe)
    {
      new_leads: leads,
      appointments_created: agendadas,
      # volume CONCRETO: consultas registradas na Agenda no período, mesmo
      # que o lead tenha chegado em outro dia (a atendente agenda 15 → mostra 15;
      # o recorte por coorte continua na taxa de agendamento).
      # Consulta marcada PARA O PASSADO = preenchimento de histórico
      # (Preencher histórico / disparo retroativo) — fica FORA do contador
      # (foi o "88 agendadas" fantasma de 15/07).
      appointments_booked: booked_scope(account, since, until_at).count,
      # e destes, quantos CHEGARAM E AGENDARAM no mesmo período (lead novo
      # que já saiu com consulta — o atendimento no timing perfeito)
      appointments_same_day: booked_scope(account, since, until_at)
        .joins(:contact).where(contacts: { created_at: since..until_at })
        .distinct.count(:contact_id),
      booking_conversion: pct(agendadas, leads),
      surgeries_closed: reached_stage_count(/cirurgia/i, since, until_at, exclude: /pós|indica/i, universe: universe),
      surgery_indications: reached_stage_count(/indica/i, since, until_at, universe: universe)
    }
  end

  # ── Painel Condução — a jornada dentro da clínica (Agenda) ──
  def conducao_metrics(since, until_at)
    periodo = consultas.where(canceled_at: nil, due_at: since..until_at)
    compareceu = periodo.where(attendance: 'attended').count
    faltou = periodo.where(attendance: 'missed').count
    {
      consultations: periodo.count,
      attended: compareceu,
      missed: faltou,
      show_rate: pct(compareceu, compareceu + faltou),
      indications: periodo.where(surgery_indication: 'indicated').count,
      # consultas que já passaram e ninguém marcou Compareceu/Faltou
      unconfirmed: periodo.where(attendance: nil).where('due_at < ?', Time.current).count
    }
  end

  # ── Painel Cirurgias — fechamento e pós-operatório ──
  def cirurgia_metrics(since, until_at)
    indicacoes = consultas.where(canceled_at: nil, due_at: since..until_at, surgery_indication: 'indicated').count
    agendadas = cirurgias.where(created_at: since..until_at).count
    realizadas_scope = cirurgias.where(due_at: since..until_at)
    {
      indications: indicacoes,
      surgeries_booked: agendadas,
      closing_rate: pct(agendadas, indicacoes),
      surgeries_done: realizadas_scope.where(attendance: 'attended').or(realizadas_scope.where(status: :done)).count,
      surgeries_missed: realizadas_scope.where(attendance: 'missed').count,
      # indicados do período que ainda não viraram cirurgia marcada
      awaiting_closing: [indicacoes - agendadas, 0].max,
      upcoming_surgeries: cirurgias.where(due_at: Time.current..).count
    }
  end

  # ── Painel Médicos — a agenda de cada médico (?doctor=Nome) ──
  def medico_metrics(since, until_at)
    scope = consultas.where(canceled_at: nil, due_at: since..until_at)
    surgery_scope = cirurgias.where(due_at: since..until_at)
    if params[:doctor].present?
      # tolerante a grafia ("Roberta Negri" e "Dra. Roberta Negri" são a mesma)
      scope = Crm::DoctorNames.filter(scope, params[:doctor])
      surgery_scope = Crm::DoctorNames.filter(surgery_scope, params[:doctor])
    end
    compareceu = scope.where(attendance: 'attended').count
    faltou = scope.where(attendance: 'missed').count
    indicated = scope.where(surgery_indication: 'indicated').limit(300).to_a
    conversions = count_conversions(indicated)
    nps_scores = nps_scores_for(scope.where(attendance: 'attended'))
    # entre quem COMPARECEU: quantos saíram com indicação × sem indicação
    sem_indicacao = [compareceu - indicated.size, 0].max
    {
      doctor: params[:doctor].presence,
      consultations: scope.count,
      attended: compareceu,
      missed: faltou,
      show_rate: pct(compareceu, compareceu + faltou),
      indications: indicated.size,
      indication_rate: pct(indicated.size, compareceu),
      no_indication: sem_indicacao,
      no_indication_rate: pct(sem_indicacao, compareceu),
      conversions: conversions,
      conversion_rate: pct(conversions, indicated.size),
      nps_avg: nps_scores.any? ? (nps_scores.sum.to_f / nps_scores.size).round(1) : nil,
      nps_count: nps_scores.size,
      surgeries: surgery_scope.count
    }
  end

  # indicados que têm cirurgia MARCADA — em lote pelo contact_id (Fase 0);
  # telefone só como fallback dos registros antigos sem link
  def count_conversions(indicated)
    linked, legacy = indicated.partition { |t| t.contact_id.present? }
    booked_ids = cirurgias.where(contact_id: linked.map(&:contact_id).uniq)
                          .distinct.pluck(:contact_id).to_set
    linked.count { |t| booked_ids.include?(t.contact_id) } +
      legacy.count { |t| surgery_booked_for_phone?(t.phone) }
  end

  def surgery_booked_for_phone?(phone)
    digits = phone.to_s.gsub(/\D/, '')
    return false if digits.length < 8

    cirurgias.where("regexp_replace(COALESCE(phone, ''), '\\D', '', 'g') LIKE ?", "%#{digits.last(8)}").exists?
  end

  # notas de NPS dos pacientes dessas consultas: 1 query pelos contact_ids
  def nps_scores_for(tasks_scope)
    contact_ids = tasks_scope.limit(200).pluck(:contact_id).compact
    return [] if contact_ids.empty?

    account.contacts.where(id: contact_ids.uniq)
           .filter_map { |c| c.additional_attributes&.dig('nps', 'score') }
  end

  def cirurgias
    account.tasks.where(task_type: 'cirurgia', canceled_at: nil)
  end

  def resolve_range
    # régua padrão (06/08): today/yesterday/last7/month/year/custom
    if (range = standard_period_range)
      return range
    end

    now = TZ.now
    case params[:preset]
    when 'week'       then [now.beginning_of_week.beginning_of_day, now] # legado
    when 'last_month' then [now.last_month.beginning_of_month, now.last_month.end_of_month]
    else [now.beginning_of_day, now] # hoje (padrão)
    end
  end

  # leads = contatos novos vindos das caixas de marketing (Google/Instagram).
  # Se a conta não tiver caixas com esses nomes (ex.: ambiente local),
  # conta todos os contatos novos para o painel não ficar zerado.
  def leads_scope(since, until_at)
    Crm::LeadsUniverse.scope(account, since, until_at)
  end

  def leads_count(since, until_at)
    leads_scope(since, until_at).count
  end

  # cards do CRM que CHEGARAM à etapa alvo (ou seguiram além dela), só de
  # leads que surgiram no período — espelha as colunas do funil sem sofrer
  # com movimentações em massa (a data usada é a do LEAD, não a do card).
  # universe: restringe ao MESMO conjunto de leads do card "Novos contatos"
  # (caixas de marketing) — numerador e denominador na mesma régua.
  def reached_stage_count(pattern, since, until_at, exclude: /pós/i, universe: nil)
    account.crm_pipelines.includes(:stages).sum do |pipeline|
      stage_ids = reached_stage_ids(pipeline, pattern, exclude)
      next 0 if stage_ids.empty?

      scope = pipeline.crm_contacts
                      .joins(:contact)
                      .where(stage_id: stage_ids)
                      .where(contacts: { created_at: since..until_at })
      scope = scope.where(contacts: { id: universe.select(:id) }) if universe
      scope.count
    end
  end

  def reached_stage_ids(pipeline, pattern, exclude)
    ordered = pipeline.stages.sort_by(&:position)
    target = ordered.find { |s| s.name.match?(pattern) && !s.name.match?(exclude) }
    return [] unless target

    ordered.select { |s| s.position >= target.position }.map(&:id)
  end

  def consultas
    account.tasks.where(task_type: 'consulta')
  end

  def active_consultas
    consultas.where(canceled_at: nil).where.not(status: :done)
  end

  def next_appointments_json
    active_consultas
      .where('due_at >= ?', Time.current)
      .order(:due_at)
      .limit(6)
      .map do |t|
        {
          id: t.id,
          title: t.title,
          due_at: t.due_at,
          unit: t.unit,
          procedure: t.procedure,
          doctor: t.doctor,
          task_type: t.task_type
        }
      end
  end

  # avisos do Radar de Oportunidades (cards quentes sem atendimento).
  # Cada aviso pode ter um painel de destino (user_id): o admin vê todos
  # (com o nome de quem vai atender); a atendente só vê os dela + os gerais.
  # tarefas esperando VOCÊ (aviso dourado no painel — criador atribuiu)
  def my_tasks_json
    open_tasks = account.tasks.where(assignee_id: Current.user.id, status: %w[todo doing])
                        .where.not(task_type: %w[consulta cirurgia])
                        .order(Arel.sql('priority DESC, due_at ASC NULLS LAST, created_at DESC'))
    {
      count: open_tasks.count,
      items: open_tasks.limit(5).map do |t|
        {
          id: t.id,
          title: t.title,
          priority: t.priority,
          status: t.status,
          due_at: t.due_at,
          creator_name: t.creator&.name,
          comments_count: Array(t.comments).size
        }
      end
    }
  end

  # reports 🐞 de quem está logado: abertos + resolvidos na última semana
  # (o resolvido vira a notificação "seu report foi corrigido" no painel)
  def bug_reports_json
    mine = account.tasks.where(creator_id: Current.user.id).where("title LIKE '🐞%'")
    {
      open: mine.where(status: %i[todo doing]).count,
      resolved: mine.where(status: :done)
                    .where(completed_at: 7.days.ago..)
                    .order(completed_at: :desc).limit(3)
                    .map { |t| { id: t.id, title: t.title, completed_at: t.completed_at } }
    }
  end

  # ── Mentor do Time: o feedback da última semana gerada ──
  # Cada pessoa vê o SEU feedback; admin também recebe o do time inteiro
  # (para acompanhar quem precisa de ajuda em quê).
  def weekly_feedback_json
    # o card do Meu Painel mostra o ciclo SEMANAL; o mensal vive em Pessoas
    scope = Crm::WeeklyFeedback.where(account: account, cadence: 'weekly')
    latest_week = scope.maximum(:week_start)
    return { mine: nil, team: [] } if latest_week.blank?

    rows = scope.where(week_start: latest_week).includes(:user).order(:user_id)
    as_json = rows.map do |row|
      {
        user_id: row.user_id,
        user_name: row.user.available_name,
        week_start: row.week_start,
        stats: row.stats,
        feedback: row.feedback
      }
    end
    {
      mine: as_json.find { |r| r[:user_id] == Current.user.id },
      team: Current.account_user.administrator? ? as_json : []
    }
  end

  # Meta de tempo de atendimento: métodos no concern Crm::ResponseGoal
  # (compartilhado com o Dashboard dos Agentes — o payload continua aqui
  # porque os widgets do Construtor bebem dele).

  def opportunity_alerts_json
    settings = CrmSetting.find_by(account: account)
    state = settings&.ai_config&.dig('opportunity_state') || {}
    alerts = Array(state['alerts']).reverse
    alerts = alerts.select { |a| a['user_id'].blank? || a['user_id'].to_i == Current.user.id } unless Current.account_user.administrator?
    {
      last_run_at: state['last_run_at'],
      alerts: with_conversation_info(alerts.first(10)),
      efficacy: radar_efficacy_json(state)
    }
  end

  # o balão de conversa do card do Radar (mesmo do CRM) precisa da caixa,
  # canal e status — enriquece na LEITURA (1 consulta em lote), valendo
  # também para avisos antigos já salvos no estado
  def with_conversation_info(alerts)
    conversations = account.conversations
                           .where(display_id: alerts.map { |a| a['conversation_id'] })
                           .includes(:inbox).index_by(&:display_id)
    alerts.map do |alert|
      conversation = conversations[alert['conversation_id']]
      next alert if conversation.blank?

      alert.merge(
        'inbox_id' => conversation.inbox_id,
        'inbox_name' => conversation.inbox&.name,
        'channel_type' => conversation.inbox&.channel_type,
        'conversation_status' => conversation.status
      )
    end
  end

  # item 83 — EFICÁCIA do Radar: dos avisos ATENDIDOS nos últimos 30 dias,
  # quantos pacientes AGENDARAM consulta depois do aviso (a consulta nasceu
  # após o toque em "Atender agora", até 14 dias depois)
  RADAR_CONVERSION_WINDOW = 14.days

  def radar_efficacy_json(state) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    log = Array(state['attended_log']).select do |entry|
      entry['attended_at'].present? && Time.zone.parse(entry['attended_at'].to_s) >= 30.days.ago
    rescue ArgumentError, TypeError
      false
    end
    return nil if log.empty?

    contact_ids = log.filter_map { |entry| entry['contact_id'].presence&.to_i }.uniq
    consultas = account.tasks.where(task_type: 'consulta', contact_id: contact_ids)
                       .where('created_at >= ?', 45.days.ago)
                       .pluck(:contact_id, :created_at)

    converted = log.count do |entry|
      cid = entry['contact_id'].presence&.to_i
      next false if cid.blank?

      at = Time.zone.parse(entry['attended_at'].to_s)
      consultas.any? { |contact_id, created| contact_id == cid && created > at && created <= at + RADAR_CONVERSION_WINDOW }
    end

    { attended_30d: log.size, converted_30d: converted,
      rate: log.any? ? ((converted.to_f / log.size) * 100).round : 0 }
  end

  # ── metas + recordes dos cards do painel ──
  # Meta é MENSAL por indicador (config do admin). O fator converte a meta
  # para o período visualizado (hoje = fatia diária; semana = 7 dias;
  # este mês = proporcional aos dias corridos...). Indicadores de % não
  # usam fator (meta direta). Recordes: melhor valor já visto por período
  # equivalente (dia/semana/mês/ano) — batido = gravado na hora.
  RECORD_KEYS = {
    'agendamento' => %w[new_leads appointments_booked surgeries_closed],
    'conducao' => %w[consultations attended indications],
    'cirurgia' => %w[indications surgeries_booked surgeries_done],
    'medico' => %w[consultations indications conversions],
    'gestor' => %w[new_leads indications surgeries_booked]
  }.freeze

  def goals_json
    cfg = crm_settings&.agenda_config || {}
    {
      targets: (cfg['panel_goals'] || {})[panel_key] || {},
      factor: goal_factor,
      records: records_json
    }
  end

  def goal_factor
    now = TZ.now
    days_in_month = now.end_of_month.day.to_f
    case params[:preset]
    when 'week', 'last7', 'last_week' then 7 / days_in_month
    when 'month' then now.day / days_in_month
    when 'last_month' then 1.0
    when 'year' then (now.month - 1) + (now.day / days_in_month)
    when 'custom'
      from, to = custom_period_range
      (((to.to_date - from.to_date).to_i + 1) / days_in_month)
    else 1 / days_in_month # hoje e ontem = fatia diária
    end.round(4)
  end

  def record_period_key
    now = TZ.now
    case params[:preset]
    when 'yesterday' then (now - 1.day).strftime('%Y-%m-%d')
    when 'week', 'last7' then now.strftime('%G-w%V')
    when 'last_week' then (now - 1.week).strftime('%G-w%V')
    when 'month' then now.strftime('%Y-%m')
    when 'last_month' then (now - 1.month).strftime('%Y-%m')
    when 'year' then now.strftime('%Y')
    else now.strftime('%Y-%m-%d')
    end
  end

  def record_basis
    { 'yesterday' => 'day', 'week' => 'week', 'last7' => 'week', 'last_week' => 'week',
      'month' => 'month', 'last_month' => 'month', 'year' => 'year' }[params[:preset]] || 'day'
  end

  def records_json # rubocop:disable Metrics/AbcSize
    return {} if params[:preset] == 'custom' # intervalo livre não compete com recorde

    keys = RECORD_KEYS[panel_key] || []
    return {} if keys.empty?

    data = panel_data(nil, nil) # já memoizado pelo show
    settings = crm_settings || CrmSetting.create!(account: account)
    # cópia profunda: mexer no hash DO ATRIBUTO em memória deixava o
    # registro "sujo" e o with_lock logo abaixo estourava (500 no painel
    # na primeira vez que uma métrica batia recorde) — hotfix 20/07
    all = ((settings.agenda_config || {})['panel_records'] || {}).deep_dup
    changed = false
    period = record_period_key

    result = keys.index_with do |key|
      value = data[key.to_sym] || data[key] # panel_data usa chaves símbolo
      next { best: 0, is_record: false } unless value.is_a?(Numeric)

      slot_key = "#{panel_key}.#{key}.#{record_basis}"
      slot = all[slot_key] || {}
      if value.positive? && value > slot['best'].to_f
        slot = { 'best' => value, 'period' => period }
        all[slot_key] = slot
        changed = true
      end
      { best: slot['best'].to_f, is_record: slot['period'] == period && slot['best'].to_f.positive? }
    end
    # esta é uma requisição GET (carga do painel): só grava quando bate um
    # recorde, e sob trava relendo o agenda_config fresco — assim não atropela
    # uma config que o admin tenha salvo em paralelo (só a chave panel_records muda)
    if changed
      settings.with_lock do
        fresh = settings.reload.agenda_config || {}
        settings.update!(agenda_config: fresh.merge('panel_records' => all))
      end
    end
    result
  end

  # consultas AGENDADAS de verdade no período: criadas no período e marcadas
  # para a frente (due_at >= criação). Registro retroativo de histórico
  # (consulta que já tinha acontecido) não é agendamento novo.
  def booked_scope(account, since, until_at)
    account.tasks.where(task_type: 'consulta', created_at: since..until_at)
           .where('tasks.due_at IS NULL OR tasks.due_at >= tasks.created_at')
  end

  def pct(part, total)
    total.positive? ? (part.to_f / total * 100).round(1) : 0.0
  end
end
