# Meu Painel: boas-vindas + indicadores com preset de período
# (hoje/ontem/essa semana/este mês/mês passado) + avisos do Radar.
# Tudo no fuso da clínica (São Paulo).
class Api::V1::Accounts::Crm::HomeController < Api::V1::Accounts::BaseController
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  def show
    since, until_at = resolve_range

    new_conversations = account.conversations.where(created_at: since..until_at).count
    appointments_created = consultas.where(created_at: since..until_at).count

    render json: {
      period: params[:preset].presence || 'today',
      # indicadores do período selecionado
      new_conversations: new_conversations,
      appointments_created: appointments_created,
      booking_conversion: pct(appointments_created, new_conversations),
      rescheduled: consultas.where('rescheduled_count > 0').where(updated_at: since..until_at).count,
      canceled: consultas.where(canceled_at: since..until_at).count,
      surgery_indications: surgery_entries(since..until_at),
      surgeries_closed: surgeries_closed(since, until_at),
      # termômetros de agora (independem do período)
      open_conversations: account.conversations.open.count,
      unanswered: account.conversations.open.where.not(waiting_since: nil).count,
      appointments_today: active_consultas.where(due_at: TZ.now.all_day).count,
      new_contacts_30d: account.contacts.where(created_at: 30.days.ago..Time.current).count,
      appointments_30d: consultas.where(created_at: 30.days.ago..Time.current).count,
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

  # indicações de cirurgia = cards que ENTRARAM na(s) etapa(s) Cirurgia
  def surgery_entries(range)
    stage_ids = Crm::Stage.joins(:pipeline)
                          .where(crm_pipelines: { account_id: account.id })
                          .where('crm_stages.name ILIKE ?', '%cirurgia%')
                          .where.not('crm_stages.name ILIKE ?', '%pós%')
                          .pluck(:id)
    return 0 if stage_ids.empty?

    Crm::StageLog.joins(:crm_contact)
                 .where(crm_contacts: { pipeline_id: account.crm_pipelines.select(:id) })
                 .where(stage_id: stage_ids, entered_at: range)
                 .distinct
                 .count(:crm_contact_id)
  end

  # cirurgias fechadas = linhas da planilha do Google Sheets no período
  def surgeries_closed(since, until_at)
    service = Crm::SheetsSurgeryService.new(account: account)
    return nil unless service.configured?

    range = since.to_date..until_at.to_date
    service.rows.count do |r|
      r['date'].present? && range.cover?(Date.parse(r['date']))
    rescue StandardError
      false
    end
  end

  def pct(part, total)
    total.positive? ? (part.to_f / total * 100).round(1) : 0.0
  end
end
