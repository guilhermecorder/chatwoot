# Meu Painel: boas-vindas + indicadores com preset de período
# (hoje/ontem/essa semana/este mês/mês passado) + avisos do Radar.
# Tudo no fuso da clínica (São Paulo).
#
# Os indicadores ESPELHAM O CRM (é onde a operação vive), em visão de
# coorte: leads que chegaram no período e até onde avançaram no funil.
# - Novos contatos (leads) = contatos novos das caixas Google + Instagram
# - Consultas agendadas    = leads que chegaram à coluna "Agendamento..."
# - Taxa de agendamento    = consultas ÷ leads × 100
# - Cirurgias fechadas     = leads que chegaram à coluna "Cirurgia Agendada"
# - Indicações de cirurgia = leads que chegaram à "Indicação de Cirurgia"
class Api::V1::Accounts::Crm::HomeController < Api::V1::Accounts::BaseController
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  def show
    since, until_at = resolve_range

    leads = leads_count(since, until_at)
    agendadas = reached_stage_count(/agendamento/i, since, until_at)

    render json: {
      period: params[:preset].presence || 'today',
      # indicadores do período selecionado (coorte pelo dia em que o lead chegou)
      new_leads: leads,
      appointments_created: agendadas,
      booking_conversion: pct(agendadas, leads),
      surgeries_closed: reached_stage_count(/cirurgia/i, since, until_at, exclude: /pós|indica/i),
      surgery_indications: reached_stage_count(/indica/i, since, until_at),
      # termômetros de agora (independem do período)
      open_conversations: account.conversations.open.count,
      unanswered: account.conversations.open.where.not(waiting_since: nil).count,
      appointments_today: active_consultas.where(due_at: TZ.now.all_day).count,
      new_contacts_30d: leads_count(30.days.ago, Time.current),
      appointments_30d: reached_stage_count(/agendamento/i, 30.days.ago, Time.current),
      next_appointments: next_appointments_json,
      opportunity_alerts: opportunity_alerts_json
    }
  end

  private

  def account
    Current.account
  end

  def resolve_range
    now = TZ.now
    case params[:preset]
    when 'yesterday'  then [now.yesterday.beginning_of_day, now.yesterday.end_of_day]
    when 'week'       then [now.beginning_of_week.beginning_of_day, now]
    when 'month'      then [now.beginning_of_month.beginning_of_day, now]
    when 'last_month' then [now.last_month.beginning_of_month, now.last_month.end_of_month]
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
