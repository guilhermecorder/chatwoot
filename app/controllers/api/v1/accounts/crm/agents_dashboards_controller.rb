# Dashboard dos AGENTES (equipe humana — análise do gestor): métricas de
# atendimento por pessoa para orientar feedbacks e treinamentos.
# Por atendente: conversas atribuídas, mensagens enviadas, tempo médio de
# 1ª resposta, conversas resolvidas, consultas agendadas e a RESPONSIVIDADE
# AO RADAR (dos avisos que o Radar de Oportunidades acendeu, quantos essa
# pessoa respondeu e em quanto tempo).
# Fontes: reporting_events do core + histórico do Radar + Agenda.
class Api::V1::Accounts::Crm::AgentsDashboardsController < Api::V1::Accounts::BaseController
  before_action :check_admin

  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  RADAR_SAMPLE = 400 # avisos do histórico avaliados por chamada

  def show
    since, until_at = resolve_range
    radar = radar_stats(since, until_at)

    render json: {
      period: params[:preset].presence || 'month',
      agents: agents_rows(since, until_at, radar[:by_responder]),
      radar: radar.except(:by_responder)
    }
  end

  private

  def account
    Current.account
  end

  def check_admin
    return if Current.account_user.administrator?

    render json: { error: 'Apenas administradores.' }, status: :forbidden
  end

  def resolve_range
    now = TZ.now
    case params[:preset]
    when 'today' then [now.beginning_of_day, now.end_of_day]
    when 'week'  then [now.beginning_of_week.beginning_of_day, now.end_of_week.end_of_day]
    when 'year'  then [now.beginning_of_year.beginning_of_day, now.end_of_year.end_of_day]
    when 'all'   then [Time.zone.at(0), now.end_of_day]
    when 'last_month' then [now.last_month.beginning_of_month, now.last_month.end_of_month]
    else [now.beginning_of_month.beginning_of_day, now.end_of_month.end_of_day]
    end
  end

  def agents_rows(since, until_at, radar_by_responder)
    range = since..until_at

    # agregações em lote (1 query por métrica, não por pessoa)
    assigned = account.conversations.where(created_at: range).where.not(assignee_id: nil)
                      .group(:assignee_id).count
    # reorder(nil) fura o default_scope do Message (ordena por created_at),
    # que quebra o GROUP BY no Postgres
    sent = account.messages.reorder(nil)
                  .where(message_type: :outgoing, private: false, created_at: range,
                         sender_type: 'User')
                  .group(:sender_id).count
    first_resp = account.reporting_events.where(name: 'first_response', created_at: range)
                        .where.not(user_id: nil).group(:user_id).average(:value)
    resolved = account.reporting_events.where(name: 'conversation_resolved', created_at: range)
                      .where.not(user_id: nil).group(:user_id).count
    consultas = account.tasks.where(task_type: 'consulta', created_at: range)
                       .group(:creator_id).count

    rows = account.users.map do |user|
      radar = radar_by_responder[user.id] || { responded: 0, total_minutes: 0.0 }
      {
        id: user.id,
        name: user.available_name,
        conversations_assigned: assigned[user.id] || 0,
        messages_sent: sent[user.id] || 0,
        avg_first_response_min: first_resp[user.id] ? (first_resp[user.id].to_f / 60).round(1) : nil,
        conversations_resolved: resolved[user.id] || 0,
        appointments_created: consultas[user.id] || 0,
        radar_responded: radar[:responded],
        radar_avg_response_min: radar[:responded].positive? ? (radar[:total_minutes] / radar[:responded]).round : nil
      }
    end

    # só quem trabalhou no período (evita listar contas de sistema paradas)
    rows.select { |r| r[:messages_sent].positive? || r[:conversations_assigned].positive? || r[:radar_responded].positive? }
        .sort_by { |r| -r[:messages_sent] }
  end

  # ── Responsividade ao Radar de Oportunidades ──
  # Para cada aviso do histórico no período: houve resposta da clínica DEPOIS
  # da detecção? quem respondeu? em quanto tempo? (a 1ª mensagem outgoing
  # após o aviso conta como a resposta ao aviso)
  def radar_stats(since, until_at)
    history = radar_history.select do |h|
      at = parse_time(h['detected_at'])
      at && at >= since && at <= until_at
    end.last(RADAR_SAMPLE)

    total = history.size
    responded = 0
    total_minutes = 0.0
    by_responder = Hash.new { |hash, key| hash[key] = { responded: 0, total_minutes: 0.0 } }
    by_target = Hash.new { |hash, key| hash[key] = { total: 0, responded: 0, total_minutes: 0.0 } }

    history.each do |h|
      detected_at = parse_time(h['detected_at'])
      target = by_target[h['user_id']] # nil = aviso geral (todos os painéis)
      target[:total] += 1

      conversation = account.conversations.find_by(display_id: h['conversation_id'])
      next if conversation.blank?

      first_reply = conversation.messages
                                .where(message_type: :outgoing, private: false)
                                .where('created_at > ?', detected_at)
                                .reorder(:created_at) # fura o default_scope de propósito
                                .first
      next if first_reply.blank?

      minutes = (first_reply.created_at - detected_at) / 60.0
      responded += 1
      total_minutes += minutes
      target[:responded] += 1
      target[:total_minutes] += minutes

      if first_reply.sender_type == 'User' && first_reply.sender_id.present?
        r = by_responder[first_reply.sender_id]
        r[:responded] += 1
        r[:total_minutes] += minutes
      end
    end

    {
      total_alerts: total,
      responded: responded,
      response_rate: total.positive? ? (responded.to_f / total * 100).round(1) : 0.0,
      avg_response_min: responded.positive? ? (total_minutes / responded).round : nil,
      by_target: by_target.map do |user_id, t|
        {
          user_id: user_id,
          user_name: user_id ? account.users.find_by(id: user_id)&.available_name : 'Todos os painéis',
          total: t[:total],
          responded: t[:responded],
          response_rate: t[:total].positive? ? (t[:responded].to_f / t[:total] * 100).round(1) : 0.0,
          avg_response_min: t[:responded].positive? ? (t[:total_minutes] / t[:responded]).round : nil
        }
      end.sort_by { |t| -t[:total] },
      by_responder: by_responder
    }
  end

  def radar_history
    cfg = CrmSetting.find_by(account: account)&.ai_config || {}
    Array(cfg.dig('opportunity_state', 'history'))
  end

  def parse_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
