# Desempenho por pessoa do time — conversas, mensagens, tempos de resposta,
# consultas agendadas, responsividade ao Radar e a jornada de atendimento
# (1ª/última mensagem, pausas). Extraído do Dashboard dos Agentes (item 138)
# para o Meu Painel reusar no bloco "Meu desempenho" (a pessoa + o robô).
# O controller que inclui precisa definir `account`.
module Crm
  module AgentPerformance
    PERF_TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
    # catálogo das métricas individuais do bloco "Meu desempenho" (item 139)
    # — o admin propõe as de cada pessoa em Configurações → Painéis
    METRIC_KEYS = %w[touched assigned messages reply_commercial first_response
                     resolved appointments surgeries_created surgeries_closed
                     attendance days_worked].freeze
    DEFAULT_METRICS = %w[touched reply_commercial days_worked resolved
                         appointments surgeries_closed].freeze
    RADAR_SAMPLE = 400 # avisos do histórico avaliados por chamada
    WEEKDAYS_PT = %w[dom seg ter qua qui sex sáb].freeze
    MIN_GAP_MINUTES = 30 # pausa menor que isso é ritmo normal, não intervalo

    # user_ids: filtro opcional (Meu Painel pede só a pessoa + o Atendimento
    # IA — as queries ficam leves e ninguém inativo é filtrado fora)
    def agents_rows(since, until_at, radar_by_responder, user_ids: nil) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      range = since..until_at

      # agregações em lote (1 query por métrica, não por pessoa)
      assigned = account.conversations.where(created_at: range).where.not(assignee_id: nil)
      assigned = assigned.where(assignee_id: user_ids) if user_ids
      assigned = assigned.group(:assignee_id).count
      # reorder(nil) fura o default_scope do Message (ordena por created_at),
      # que quebra o GROUP BY no Postgres
      sent = account.messages.reorder(nil)
                    .where(message_type: :outgoing, private: false, created_at: range,
                           sender_type: 'User')
      sent = sent.where(sender_id: user_ids) if user_ids
      # conversas em que a pessoa ATUOU (mandou >= 1 mensagem), independente
      # de quem é o atribuído — pedido 20/08 (item 139)
      touched = account.messages.reorder(nil)
                       .where(message_type: :outgoing, private: false, created_at: range,
                              sender_type: 'User')
      touched = touched.where(sender_id: user_ids) if user_ids
      touched = touched.group(:sender_id).distinct.count(:conversation_id)
      sent = sent.group(:sender_id).count
      first_resp = account.reporting_events.where(name: 'first_response', created_at: range)
                          .where.not(user_id: nil)
      first_resp = first_resp.where(user_id: user_ids) if user_ids
      first_resp = first_resp.group(:user_id).average(:value)
      resolved = account.reporting_events.where(name: 'conversation_resolved', created_at: range)
                        .where.not(user_id: nil)
      resolved = resolved.where(user_id: user_ids) if user_ids
      resolved = resolved.group(:user_id).count
      consultas = account.tasks.where(task_type: 'consulta', created_at: range)
      consultas = consultas.where(creator_id: user_ids) if user_ids
      consultas = consultas.group(:creator_id).count
      # cirurgias AGENDADAS pela pessoa (papel da Elizangela — item 139)
      cirurgias_criadas = account.tasks.where(task_type: 'cirurgia', created_at: range)
      cirurgias_criadas = cirurgias_criadas.where(creator_id: user_ids) if user_ids
      cirurgias_criadas = cirurgias_criadas.group(:creator_id).count
      reply_scope = account.reporting_events.where(name: 'reply_time', created_at: range)
                           .where('value > 0').where.not(user_id: nil)
      reply_scope = reply_scope.where(user_id: user_ids) if user_ids
      reply_avg = reply_scope.group(:user_id).average(:value)
      reply_count = reply_scope.group(:user_id).count
      workdays = workday_stats(range, user_ids: user_ids)

      users_scope = user_ids ? account.users.where(id: user_ids) : account.users
      rows = users_scope.map do |user|
        radar = radar_by_responder[user.id] || { responded: 0, total_minutes: 0.0 }
        {
          id: user.id,
          name: user.available_name,
          conversations_assigned: assigned[user.id] || 0,
          conversations_touched: touched[user.id] || 0,
          messages_sent: sent[user.id] || 0,
          avg_first_response_min: first_resp[user.id] ? (first_resp[user.id].to_f / 60).round(1) : nil,
          # "lead response time": média de TODAS as respostas (não só a 1ª)
          avg_reply_min: reply_avg[user.id] ? (reply_avg[user.id].to_f / 60).round(1) : nil,
          replies_count: reply_count[user.id] || 0,
          conversations_resolved: resolved[user.id] || 0,
          appointments_created: consultas[user.id] || 0,
          surgeries_created: cirurgias_criadas[user.id] || 0,
          radar_responded: radar[:responded],
          radar_avg_response_min: radar[:responded].positive? ? (radar[:total_minutes] / radar[:responded]).round : nil,
          # jornada de atendimento: 1ª/última mensagem e maiores pausas
          workday: workdays[user.id]
        }
      end

      # só quem trabalhou no período (evita listar contas de sistema paradas);
      # com user_ids explícitos devolve todo mundo (o Meu Painel mostra zeros)
      if user_ids.nil?
        rows = rows.select do |r|
          r[:messages_sent].positive? || r[:conversations_assigned].positive? || r[:radar_responded].positive?
        end
      end
      rows.sort_by { |r| -r[:messages_sent] }
    end

    # ── Jornada de atendimento por pessoa (pedido 17/07) ──
    # A partir das mensagens ENVIADAS por cada pessoa, dia a dia: horário da
    # primeira e da última mensagem (média do período) e as MAIORES PAUSAS
    # entre uma mensagem e outra dentro do expediente — retrato honesto do
    # horário de atendimento real, para feedback.

    def workday_stats(range, user_ids: nil) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      scope = account.messages.reorder(nil)
                     .where(message_type: :outgoing, private: false, created_at: range, sender_type: 'User')
                     .where.not(sender_id: nil)
      scope = scope.where(sender_id: user_ids) if user_ids
      rows = scope.pluck(:sender_id, :created_at)

      by_user = Hash.new { |h, k| h[k] = [] }
      rows.each { |uid, at| by_user[uid] << at.in_time_zone(PERF_TZ) }

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

        next unless first_reply.sender_type == 'User' && first_reply.sender_id.present?

        r = by_responder[first_reply.sender_id]
        r[:responded] += 1
        r[:total_minutes] += minutes
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
end
