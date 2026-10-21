# 🎓 APRENDIZADO do Agente de Páginas (item 353): cada recomendação APLICADA
# ganha, LEARNING_DAYS depois, o antes × depois da própria página — lead por
# visita (quando a página já tinha leads) ou clique no WhatsApp por visita —
# e o veredito: better / worse / same / early (sem volume ainda). O placar
# por regra sai do mesmo Cevico::CampaignAgent::Learning.scoreboard (canal pages).
class Cevico::PageAgent::Learning
  LEARNING_DAYS = 7
  BETTER = 1.1
  WORSE = 0.9
  MIN_VIEWS = Cevico::PageAgent::Rates::MIN_VIEWS

  def initialize(account:, today: Date.current)
    @account = account
    @today = today
  end

  def call
    due.count { |action| learn(action) }
  end

  def due
    Crm::CampaignAction.where(account_id: @account.id, channel: Cevico::PageAgent::Daily::CHANNEL, status: 'applied', learned_at: nil)
                       .where('applied_at <= ?', (@today - LEARNING_DAYS).end_of_day)
  end

  private

  def learn(action)
    applied_on = action.applied_at.in_time_zone('America/Sao_Paulo').to_date
    from = applied_on + 1
    to = [from + LEARNING_DAYS - 1, @today - 1].min
    return false if to < from

    after = action.level == 'page' ? window(action.ref_id.to_i, from, to) : {}
    action.update!(metrics_after: after.merge('since' => from.iso8601, 'until' => to.iso8601),
                   outcome: outcome_for(action.metrics_before || {}, after), learned_at: Time.current)
    true
  rescue StandardError => e
    Rails.logger.error "[CEVICO páginas] aprendizado da ação #{action.id}: #{e.message}"
    false
  end

  def window(page_id, from, to)
    views, clicks = @account.cevico_page_traffic.where(cevico_page_id: page_id, date: from..to)
                            .pick(Arel.sql('COALESCE(SUM(views), 0)'), Arel.sql('COALESCE(SUM(cta_clicks), 0)'))
    leads = @account.contacts
                    .where("(additional_attributes -> 'page_ads' ->> 'page_id') = ?", page_id.to_s)
                    .where("(additional_attributes -> 'page_ads' ->> 'captured_at')::timestamptz BETWEEN ? AND ?",
                           from.beginning_of_day, to.end_of_day)
                    .count
    v = views.to_i
    { 'views' => v, 'cta' => clicks.to_i, 'leads' => leads,
      'click_rate' => v.positive? ? (clicks.to_f / v).round(4) : nil, 'lead_rate' => v.positive? ? (leads.to_f / v).round(4) : nil }
  end

  def outcome_for(before, after) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return 'early' if after['views'].to_i < MIN_VIEWS || before['views'].to_i < MIN_VIEWS

    key = before['leads'].to_i >= 3 ? 'lead_rate' : 'click_rate'
    b = before[key].to_f
    a = after[key].to_f
    return 'better' if b.zero? && a.positive?
    return 'same' if b.zero?

    ratio = a / b
    return 'better' if ratio >= BETTER
    return 'worse' if ratio <= WORSE

    'same'
  end
end
