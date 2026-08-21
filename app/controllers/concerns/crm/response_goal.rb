# Meta de tempo de atendimento (itens 50/108; extraída no 136): médias do
# reply_time por atendente contra a meta configurada no agente Radar,
# separando HORÁRIO COMERCIAL (seg–sex 08–17h, sem feriado — quando o time
# está presente) de fora do horário (média informativa, sem julgamento).
# Usada pelo Meu Painel (widgets do Construtor) e pelo relatório completo
# no Dashboard dos Agentes.
module Crm
  module ResponseGoal
    # meta configurada no agente Radar (nil = admin ainda não definiu; usa 15)
    def response_goal_minutes
      @response_goal_minutes ||= response_goal_settings&.ai_config&.dig('agents', 'opportunity', 'response_goal_minutes').presence&.to_i
    end

    def response_goal_json(since, until_at)
      rows = response_goal_rows(since, until_at, response_goal_minutes || 15)
      {
        goal_minutes: response_goal_minutes || 15,
        configured: response_goal_minutes.present?,
        mine: rows.find { |r| r[:user_id] == Current.user.id },
        agents: Current.account_user.administrator? ? rows : []
      }
    end

    # user_ids: pedido explícito (Meu Painel: a pessoa + o Atendimento IA) —
    # com ele o recorte por papel não se aplica (os dados do robô são de todos)
    def response_goal_rows(since, until_at, goal_minutes, user_ids: nil) # rubocop:disable Metrics/AbcSize
      scope = Current.account.reporting_events.where(name: 'reply_time', created_at: since..until_at).where('value > 0')
      scope = if user_ids
                scope.where(user_id: user_ids)
              elsif Current.account_user.administrator?
                scope
              else
                scope.where(user_id: Current.user.id)
              end
      commercial = Crm::BusinessHours.sql_condition('reporting_events.created_at', since, until_at)
      biz = scope.where(commercial)
      off = scope.where("NOT (#{commercial})")

      counts = biz.group(:user_id).count
      avgs = biz.group(:user_id).average(:value)
      within = biz.where(value: ..goal_minutes * 60).group(:user_id).count
      off_counts = off.group(:user_id).count
      off_avgs = off.group(:user_id).average(:value)

      user_ids = (counts.keys + off_counts.keys).compact.uniq
      names = Current.account.users.where(id: user_ids).index_by(&:id)
      rows = user_ids.map do |uid|
        replies = counts.fetch(uid, 0)
        hits = within.fetch(uid, 0)
        {
          user_id: uid,
          name: names[uid]&.available_name || 'Atendente',
          replies: replies,
          avg_minutes: replies.positive? ? (avgs[uid].to_f / 60).round(1) : nil,
          within_goal: hits,
          within_rate: response_goal_pct(hits, replies),
          off_replies: off_counts.fetch(uid, 0),
          off_avg_minutes: off_counts[uid].to_i.positive? ? (off_avgs[uid].to_f / 60).round(1) : nil
        }
      end
      rows.sort_by { |r| -(r[:replies] + r[:off_replies]) }
    end

    private

    def response_goal_pct(part, total)
      total.positive? ? (part * 100.0 / total).round(1) : 0
    end

    def response_goal_settings
      @response_goal_settings ||= CrmSetting.find_by(account: Current.account)
    end
  end
end
