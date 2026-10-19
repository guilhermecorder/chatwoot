# 🎓 APRENDIZADO do Agente de Campanhas (item 352): toda recomendação APLICADA
# ganha um antes × depois — a janela de `learning_days` depois da mudança
# contra a janela que gerou a sugestão — e um veredito:
#   better  a estrela-guia (custo por agendamento/cirurgia) melhorou ≥ 10 %
#   worse   piorou ≥ 10 %
#   same    ficou parecido
#   saved   pausa: o gasto parou (mede o que deixou de gastar)
#   early   ainda não há volume para concluir
# O PLACAR por regra (acertos × erros) é o que faz o agente aprender: regra
# que erra mais do que acerta entra "em observação" (só avisa, não propõe
# mudança) até o placar virar.
class Cevico::CampaignAgent::Learning
  ROW = Cevico::CampaignAgent::Row
  BETTER = 0.9
  WORSE = 1.1
  MIN_LEARNED = 5
  OBSERVE_BELOW = 0.4

  def initialize(account:, params:, today: Date.current)
    @account = account
    @p = params
    @today = today
  end

  # avalia o que já tem janela fechada; devolve quantas aprenderam
  def call
    due.count { |action| learn(action) }
  end

  def due
    limit = @today - @p['learning_days'].to_i
    Crm::CampaignAction.ads.where(account_id: @account.id, status: 'applied', learned_at: nil).where('applied_at <= ?', limit.end_of_day)
  end

  # placar por regra: [{ rule, label, better, worse, same, saved, early, learned, confidence, observing }]
  # channels: %w[meta google] (anúncios) ou %w[pages] (item 353: Agente de Páginas)
  def self.scoreboard(account, channels: %w[meta google]) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    rows = Crm::CampaignAction.where(account_id: account.id, channel: channels, status: 'applied').where.not(outcome: nil)
                              .group(:rule, :outcome).count
    list = rows.keys.map(&:first).uniq.map do |rule|
      counts = Crm::CampaignAction::OUTCOMES.to_h { |o| [o.to_sym, rows[[rule, o]].to_i] }
      judged = counts[:better] + counts[:worse]
      confidence = judged.positive? ? (counts[:better].to_f / judged).round(2) : nil
      label = Cevico::CampaignAgent::Rules::LABELS[rule] || Cevico::PageAgent::Executor::LABELS[rule] || rule
      { rule: rule, label: label, learned: counts.values.sum, confidence: confidence,
        observing: judged >= MIN_LEARNED && confidence < OBSERVE_BELOW }.merge(counts)
    end
    list.sort_by { |r| -r[:learned] }
  end

  def self.observing(account)
    scoreboard(account).select { |r| r[:observing] }.to_set { |r| r[:rule] }
  end

  private

  def learn(action) # rubocop:disable Metrics/AbcSize
    applied_on = action.applied_at.in_time_zone('America/Sao_Paulo').to_date
    from = applied_on + 1
    to = [from + @p['learning_days'].to_i - 1, @today - 1].min
    return false if to < from

    after = row_for(action, from, to)
    before = action.metrics_before || {}
    after_row = after || ROW.finish(ROW.blank, goal: @p['goal'])
    action.update!(metrics_after: ROW.snapshot(after_row).merge('since' => from.iso8601, 'until' => to.iso8601),
                   outcome: outcome_for(action, before, after), learned_at: Time.current)
    true
  rescue StandardError => e
    Rails.logger.error "[CEVICO campanhas] aprendizado da ação #{action.id}: #{e.message}"
    false
  end

  def row_for(action, from, to)
    result = Cevico::CampaignAgent::Reader.new(account: @account, since_date: from, until_date: to, goal: @p['goal'], channels: [action.channel]).call
    return result[:totals][action.channel] if action.level == 'channel'

    result[:flat].find { |r| r['channel'] == action.channel && r['level'] == action.level && r['id'] == action.ref_id }
  end

  def outcome_for(action, before, after) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return 'saved' if action.kind == 'pause'
    return 'early' if after.nil? || after['spend'].to_f < @p.dig('min', 'spend').to_f / 2

    b = before['goal_cost']
    a = after['goal_cost']
    return 'early' if b.nil? && a.nil?
    return 'worse' if a.nil? # gastou e não trouxe nenhum resultado
    return 'better' if b.nil? # antes não tinha resultado, agora tem

    ratio = a.to_f / b
    return 'better' if ratio <= BETTER
    return 'worse' if ratio >= WORSE

    'same'
  end
end
