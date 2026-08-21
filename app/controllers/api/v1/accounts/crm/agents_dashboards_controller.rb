# Dashboard dos AGENTES (equipe humana — análise do gestor): métricas de
# atendimento por pessoa para orientar feedbacks e treinamentos.
# Por atendente: conversas atribuídas, mensagens enviadas, tempo médio de
# 1ª resposta, conversas resolvidas, consultas agendadas e a RESPONSIVIDADE
# AO RADAR (dos avisos que o Radar de Oportunidades acendeu, quantos essa
# pessoa respondeu e em quanto tempo).
# Fontes: reporting_events do core + histórico do Radar + Agenda.
class Api::V1::Accounts::Crm::AgentsDashboardsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  include Crm::ResolvesPeriod
  include Crm::ResponseGoal
  include Crm::AgentPerformance
  before_action -> { require_capability(:reports) }

  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  def show
    since, until_at = resolve_range
    radar = radar_stats(since, until_at)

    render json: {
      period: params[:preset].presence || 'month',
      agents: agents_rows(since, until_at, radar[:by_responder]),
      radar: radar.except(:by_responder),
      # Meta de tempo de atendimento (veio do Meu Painel no item 136)
      response_goal: response_goal_json(since, until_at)
    }
  end

  private

  def account
    Current.account
  end


  def resolve_range
    # régua padrão CEVICO (06/08) resolve primeiro; presets antigos seguem abaixo
    range = standard_period_range
    return range if range

    now = TZ.now
    case params[:preset]
    when 'week'  then [now.beginning_of_week.beginning_of_day, now.end_of_week.end_of_day]
    when 'all'   then [Time.zone.at(0), now.end_of_day]
    when 'last_month' then [now.last_month.beginning_of_month, now.last_month.end_of_month]
    else [now.beginning_of_month.beginning_of_day, now.end_of_month.end_of_day]
    end
  end

end
