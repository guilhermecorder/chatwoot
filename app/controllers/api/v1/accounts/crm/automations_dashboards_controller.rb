# Dashboard de resultados das automações de coluna: quantas vezes cada
# automação disparou no período (presets iguais ao Meu Painel), falhas,
# contatos alcançados e série por dia. Fonte: crm_automation_logs.
class Api::V1::Accounts::Crm::AutomationsDashboardsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  include Crm::ResolvesPeriod

  before_action -> { require_capability(:automations) }
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  def show
    from, to = preset_range

    logs = Crm::AutomationLog.joins(automation: { stage: :pipeline })
                             .where(crm_pipelines: { account_id: Current.account.id })
                             .where(crm_automation_logs: { created_at: from..to })

    totals = logs.group(:status).count
    by_automation = logs.group(:automation_id, :status).count
    last_by_automation = logs.group(:automation_id).maximum(:created_at)
    contacts_by_automation = logs.group(:automation_id).distinct.count(:contact_id)

    automations = Crm::Automation.joins(stage: :pipeline)
                                 .where(crm_pipelines: { account_id: Current.account.id })
                                 .includes(stage: :pipeline)

    rows = automations.filter_map do |a|
      fired  = by_automation[[a.id, 'fired']].to_i
      failed = by_automation[[a.id, 'failed']].to_i
      # sem movimento no período E desligada = não polui o ranking
      next if fired.zero? && failed.zero? && !a.active

      {
        id: a.id,
        name: a.name,
        stage_name: a.stage.name,
        stage_color: a.stage.color,
        pipeline_name: a.stage.pipeline.name,
        trigger_type: a.trigger_type,
        action_type: a.action_type,
        active: a.active,
        fired: fired,
        failed: failed,
        contacts: contacts_by_automation[a.id].to_i,
        last_fired_at: last_by_automation[a.id]
      }
    end.sort_by { |r| [-r[:fired], -r[:failed]] }

    render json: {
      period: params[:preset].presence || 'today',
      from: from.iso8601,
      to: to.iso8601,
      totals: {
        fired: totals['fired'].to_i,
        failed: totals['failed'].to_i,
        contacts: logs.distinct.count(:contact_id),
        active_automations: automations.count { |a| a.active }
      },
      automations: rows,
      timeline: build_timeline(logs, from, to)
    }
  end

  private

  # disparos por dia (fuso SP), limitado a 62 pontos por segurança
  def build_timeline(logs, from, to)
    by_day = logs.where(status: 'fired')
                 .group(Arel.sql("DATE(crm_automation_logs.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')"))
                 .count
    last_day = [to.to_date, from.to_date + 61].min
    (from.to_date..last_day).map do |d|
      { date: d.to_s, fired: by_day[d].to_i }
    end
  end

  # régua padrão CEVICO (06/08) via concern; presets antigos (week /
  # last_month) continuam valendo por compatibilidade
  def preset_range
    standard_period_range || legacy_range
  end

  def legacy_range
    now = TZ.now
    case params[:preset]
    when 'yesterday'  then [now.yesterday.beginning_of_day, now.yesterday.end_of_day]
    when 'week'       then [now.beginning_of_week.beginning_of_day, now]
    when 'month'      then [now.beginning_of_month.beginning_of_day, now]
    when 'last_month' then [now.last_month.beginning_of_month, now.last_month.end_of_month]
    else [now.beginning_of_day, now] # hoje (padrão)
    end
  end
end
