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
  before_action -> { require_capability(:reports) }

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

  def agents_rows(since, until_at, radar_by_responder) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
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
    reply_scope = account.reporting_events.where(name: 'reply_time', created_at: range)
                         .where('value > 0').where.not(user_id: nil)
    reply_avg = reply_scope.group(:user_id).average(:value)
    reply_count = reply_scope.group(:user_id).count
    workdays = workday_stats(range)

    rows = account.users.map do |user|
      radar = radar_by_responder[user.id] || { responded: 0, total_minutes: 0.0 }
      {
        id: user.id,
        name: user.available_name,
        conversations_assigned: assigned[user.id] || 0,
        messages_sent: sent[user.id] || 0,
        avg_first_response_min: first_resp[user.id] ? (first_resp[user.id].to_f / 60).round(1) : nil,
        # "lead response time": média de TODAS as respostas (não só a 1ª)
        avg_reply_min: reply_avg[user.id] ? (reply_avg[user.id].to_f / 60).round(1) : nil,
        replies_count: reply_count[user.id] || 0,
        conversations_resolved: resolved[user.id] || 0,
        appointments_created: consultas[user.id] || 0,
        radar_responded: radar[:responded],
        radar_avg_response_min: radar[:responded].positive? ? (radar[:total_minutes] / radar[:responded]).round : nil,
        # jornada de atendimento: 1ª/última mensagem e maiores pausas
        workday: workdays[user.id]
      }
    end

    # só quem trabalhou no período (evita listar contas de sistema paradas)
    rows.select { |r| r[:messages_sent].positive? || r[:conversations_assigned].positive? || r[:radar_responded].positive? }
        .sort_by { |r| -r[:messages_sent] }
  end

  # ── Jornada de atendimento por pessoa (pedido 17/07) ──
  # A partir das mensagens ENVIADAS por cada pessoa, dia a dia: horário da
  # primeira e da última mensagem (média do período) e as MAIORES PAUSAS
  # entre uma mensagem e outra dentro do expediente — retrato honesto do
  # horário de atendimento real, para feedback.
  WEEKDAYS_PT = %w[dom seg ter qua qui sex sáb].freeze
  MIN_GAP_MINUTES = 30 # pausa menor que isso é ritmo normal, não intervalo

  def workday_stats(range) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    rows = account.messages.reorder(nil)
                  .where(message_type: :outgoing, private: false, created_at: range, sender_type: 'User')
                  .where.not(sender_id: nil)
                  .pluck(:sender_id, :created_at)

    by_user = Hash.new { |h, k| h[k] = [] }
    rows.each { |uid, at| by_user[uid] << at.in_time_zone(TZ) }

    by_user.transform_values do |times|
      per_day = times.sort.group_by(&:to_date)
      firsts = []
      lasts = []
      gaps = []
      per_day.each do |date, list|
        firsts << minutes_of_day(list.first)
        lasts << minutes_of_day(list.last)
        list.each_cons(2) do |a, b|
          diff = ((b - a) / 60).round
          gaps << { date: date, from: a, to: b, minutes: diff } if diff >= MIN_GAP_MINUTES
        end
      end
      {
        days_active: per_day.size,
        avg_first_msg: fmt_time_of_day(firsts.sum / firsts.size),
        avg_last_msg: fmt_time_of_day(lasts.sum / lasts.size),
        top_gaps: gaps.max_by(3) { |g| g[:minutes] }.map do |g|
          {
            day: "#{WEEKDAYS_PT[g[:date].wday]} #{g[:date].strftime('%d/%m')}",
            from: g[:from].strftime('%H:%M'),
            to: g[:to].strftime('%H:%M'),
            minutes: g[:minutes]
          }
        end
      }
    end
  end

  def minutes_of_day(time)
    (time.hour * 60) + time.min
  end

  def fmt_time_of_day(total_minutes)
    format('%<h>02d:%<m>02d', h: total_minutes / 60, m: total_minutes % 60)
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

    # carrega TODAS as conversas do histórico de uma vez (antes era 1 query por
    # aviso — até 400 idas ao banco por abertura do dashboard)
    display_ids = history.filter_map { |h| h['conversation_id'] }.uniq
    conv_by_display = account.conversations.where(display_id: display_ids).index_by(&:display_id)

    history.each do |h|
      detected_at = parse_time(h['detected_at'])
      target = by_target[h['user_id']] # nil = aviso geral (todos os painéis)
      target[:total] += 1

      conversation = conv_by_display[h['conversation_id']]
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
