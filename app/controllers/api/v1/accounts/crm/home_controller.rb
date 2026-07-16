# Meu Painel: boas-vindas + indicadores com preset de período
# (hoje/ontem/essa semana/este mês/mês passado/este ano) + avisos do Radar.
# Tudo no fuso da clínica (São Paulo).
#
# PAINÉIS POR PESSOA (?panel=): mesmo layout, indicadores da função de cada uma:
# - agendamento (Vaneide, padrão): espelha o CRM em coorte — leads que
#   chegaram no período e até onde avançaram no funil.
# - conducao (Elisangela): condução do paciente na clínica — consultas do
#   período, comparecimento, faltas e indicações de cirurgia (Agenda).
# - cirurgia (Gabriela): fechamento — indicações, cirurgias agendadas/
#   realizadas e taxa de fechamento.
# - medico (?doctor=Nome): a agenda de cada médico — consultas, presença,
#   indicações e cirurgias dele.
class Api::V1::Accounts::Crm::HomeController < Api::V1::Accounts::BaseController
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
      my_tasks: my_tasks_json
    }.merge(panel_key == 'agendamento' ? panel_data(since, until_at) : {}) # compat: campos antigos no topo
  end

  private

  def account
    Current.account
  end

  def panel_key
    key = params[:panel].presence || 'agendamento'
    # agente com painel ATRIBUÍDO pelo admin fica travado nele
    unless Current.account_user.administrator?
      assigned = crm_settings&.agenda_config&.dig('panel_assignments', Current.user.id.to_s)
      key = assigned if assigned.present?
    end
    %w[agendamento conducao cirurgia medico gestor].include?(key) ? key : 'agendamento'
  end

  def crm_settings
    @crm_settings ||= CrmSetting.find_by(account: account)
  end

  def panel_data(since, until_at)
    # painéis da AGENDA contam o período-calendário inteiro (a consulta de
    # hoje à tarde conta em "Hoje"); o de leads corta em "agora" (coorte)
    @panel_data ||= case panel_key
                    when 'conducao' then conducao_metrics(since, agenda_until(until_at))
                    when 'cirurgia' then cirurgia_metrics(since, agenda_until(until_at))
                    when 'medico'   then medico_metrics(since, agenda_until(until_at))
                    when 'gestor'   then gestor_metrics(since, until_at)
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
    when 'yesterday', 'last_month' then until_at
    else now.end_of_day # hoje
    end
  end

  # ── Painel Agendamento (Vaneide) — coorte pelo dia em que o lead chegou ──
  def agendamento_metrics(since, until_at)
    leads = leads_count(since, until_at)
    agendadas = reached_stage_count(/agendamento/i, since, until_at)
    {
      new_leads: leads,
      appointments_created: agendadas,
      # volume CONCRETO: consultas registradas na Agenda no período, mesmo
      # que o lead tenha chegado em outro dia (Vaneide agenda 15 → mostra 15;
      # o recorte por coorte continua na taxa de agendamento)
      appointments_booked: account.tasks.where(task_type: 'consulta', created_at: since..until_at).count,
      # e destes, quantos CHEGARAM E AGENDARAM no mesmo período (lead novo
      # que já saiu com consulta — o atendimento no timing perfeito)
      appointments_same_day: account.tasks.where(task_type: 'consulta', created_at: since..until_at)
                                    .joins(:contact).where(contacts: { created_at: since..until_at })
                                    .distinct.count(:contact_id),
      booking_conversion: pct(agendadas, leads),
      surgeries_closed: reached_stage_count(/cirurgia/i, since, until_at, exclude: /pós|indica/i),
      surgery_indications: reached_stage_count(/indica/i, since, until_at)
    }
  end

  # ── Painel Condução (Elisangela) — a jornada dentro da clínica (Agenda) ──
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

  # ── Painel Cirurgias (Gabriela) — fechamento e pós-operatório ──
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
    now = TZ.now
    case params[:preset]
    when 'yesterday'  then [now.yesterday.beginning_of_day, now.yesterday.end_of_day]
    when 'week'       then [now.beginning_of_week.beginning_of_day, now]
    when 'month'      then [now.beginning_of_month.beginning_of_day, now]
    when 'last_month' then [now.last_month.beginning_of_month, now.last_month.end_of_month]
    when 'year'       then [now.beginning_of_year.beginning_of_day, now]
    else [now.beginning_of_day, now] # hoje (padrão)
    end
  end

  # leads = contatos novos vindos das caixas de marketing (Google/Instagram).
  # Se a conta não tiver caixas com esses nomes (ex.: ambiente local),
  # conta todos os contatos novos para o painel não ficar zerado.
  def leads_count(since, until_at)
    scope = account.contacts.where(created_at: since..until_at)
    inbox_ids = account.inboxes
                       .where('name ILIKE :g OR name ILIKE :i', g: '%google%', i: '%instagram%')
                       .pluck(:id)
    return scope.count if inbox_ids.empty?

    scope.joins(:conversations).where(conversations: { inbox_id: inbox_ids }).distinct.count
  end

  # cards do CRM que CHEGARAM à etapa alvo (ou seguiram além dela), só de
  # leads que surgiram no período — espelha as colunas do funil sem sofrer
  # com movimentações em massa (a data usada é a do LEAD, não a do card)
  def reached_stage_count(pattern, since, until_at, exclude: /pós/i)
    account.crm_pipelines.includes(:stages).sum do |pipeline|
      ordered = pipeline.stages.sort_by(&:position)
      target = ordered.find { |s| s.name.match?(pattern) && !s.name.match?(exclude) }
      next 0 unless target

      stage_ids = ordered.select { |s| s.position >= target.position }.map(&:id)
      pipeline.crm_contacts
              .joins(:contact)
              .where(stage_id: stage_ids)
              .where(contacts: { created_at: since..until_at })
              .count
    end
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

  def opportunity_alerts_json
    settings = CrmSetting.find_by(account: account)
    state = settings&.ai_config&.dig('opportunity_state') || {}
    alerts = Array(state['alerts']).reverse
    unless Current.account_user.administrator?
      alerts = alerts.select { |a| a['user_id'].blank? || a['user_id'].to_i == Current.user.id }
    end
    {
      last_run_at: state['last_run_at'],
      alerts: alerts.first(10)
    }
  end

  def pct(part, total)
    total.positive? ? (part.to_f / total * 100).round(1) : 0.0
  end
end
