# 💸 item 413 (24/11) — O GASTO DO META DIVIDIDO PELAS CAIXAS DE ENTRADA.
#
# Antes: cada caixa marcada como "puxar do Meta" recebia o gasto INTEIRO da
# conta de anúncios. INSTAGRAM, INSTAGRAM 2 e CONFIRMAÇÃO mostravam os mesmos
# R$ 5.077 cada: o dinheiro contado três vezes e o custo por lead de cada caixa
# errado ("o Dashboard CRM ficou contaminado", Guilherme).
#
# Agora cada real vai para a caixa onde o anúncio DELE abriu conversa:
#   1) o gasto de cada anúncio no período (cevico_ad_insights, por dia);
#   2) as conversas do período carimbadas com aquele anúncio (meta_ads.source_id,
#      o "referral" que o WhatsApp manda) contadas por caixa;
#   3) o gasto do anúncio se reparte na proporção dessas conversas. Anúncio sem
#      conversa carimbada herda a proporção do conjunto dele; sem conjunto, a da
#      campanha; sem nada (campanha do site, que não abre conversa) fica em
#      "sem caixa" — aparece na tela, nunca some nem é empurrado para alguém.
#
# `total` = o gasto oficial da conta no período (Crm::MetaInsightsService). Os
# números por anúncio chegam de madrugada; quando o total ao vivo é maior (o dia
# de hoje ainda não sincronizou), as fatias são esticadas para fechar com ele.
# Sem número por anúncio nenhum no período, a divisão é pela proporção das
# conversas carimbadas (método 'conversas').
class Crm::MetaSpendByInbox
  SOURCE_SQL = "conversations.additional_attributes -> 'meta_ads' ->> 'source_id'".freeze

  def initialize(account:, since:, until_at:, total: nil)
    @account = account
    @since = since
    @until_at = until_at
    @total = total&.to_f
  end

  # { by_inbox: { inbox_id => R$ }, unassigned: R$, total: R$, method:, ads: n }
  def call
    spend = ad_spend
    ad_total = spend.values.sum
    return by_conversations if ad_total <= 0

    shares = Hash.new(0.0)
    unassigned = 0.0
    spend.each do |ad_id, value|
      dist = distribution_for(ad_id)
      next unassigned += value if dist.blank?

      weight = dist.values.sum.to_f
      dist.each { |inbox_id, count| shares[inbox_id] += value * count / weight }
    end
    result(shares, unassigned, ad_total, 'anuncio', spend.size)
  end

  private

  def result(shares, unassigned, base, method, ads)
    scale = @total&.positive? && base.positive? ? @total / base : 1.0
    {
      by_inbox: shares.transform_values { |v| (v * scale).round(2) },
      unassigned: (unassigned * scale).round(2),
      total: (base * scale).round(2),
      method: method, ads: ads
    }
  end

  # sem número por anúncio (o dia ainda não sincronizou): proporção das conversas carimbadas
  def by_conversations
    total = @total.to_f
    by_inbox = conversations_by_ad.values.each_with_object(Hash.new(0)) { |dist, acc| dist.each { |inbox, n| acc[inbox] += n } }
    weight = by_inbox.values.sum.to_f
    return { by_inbox: {}, unassigned: total.round(2), total: total.round(2), method: 'nenhum', ads: 0 } if total <= 0 || weight <= 0

    { by_inbox: by_inbox.transform_values { |n| (total * n / weight).round(2) }, unassigned: 0.0,
      total: total.round(2), method: 'conversas', ads: 0 }
  end

  def date_range
    tz = Crm::JourneyService::TZ
    @since.in_time_zone(tz).to_date..@until_at.in_time_zone(tz).to_date
  end

  # { ad_id => R$ } só de quem gastou
  def ad_spend
    Crm::AdInsight.where(account_id: @account.id, date: date_range)
                  .group(:ad_id).sum(Arel.sql("COALESCE((metrics ->> 'spend')::numeric, 0)"))
                  .transform_values(&:to_f).select { |_, v| v.positive? }
  end

  # { ad_id => { inbox_id => conversas } }
  def conversations_by_ad
    @conversations_by_ad ||= begin
      scope = @account.conversations.where(created_at: @since..@until_at).where("#{SOURCE_SQL} IS NOT NULL")
      rows = Crm::AgentSimulator.without(@account, scope).group(Arel.sql(SOURCE_SQL), :inbox_id).count
      rows.each_with_object({}) { |((ad_id, inbox_id), n), acc| (acc[ad_id.to_s] ||= Hash.new(0))[inbox_id] += n }
    end
  end

  def distribution_for(ad_id)
    conversations_by_ad[ad_id].presence || group_distribution(:adset_id, ad_id) || group_distribution(:campaign_id, ad_id)
  end

  # a proporção somada dos anúncios irmãos (mesmo conjunto ou mesma campanha)
  def group_distribution(level, ad_id) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    group = creatives[ad_id]&.fetch(level, nil)
    return nil if group.blank?

    @group_distribution ||= {}
    @group_distribution[[level, group]] ||= begin
      siblings = creatives.select { |_, c| c[level] == group }.keys
      merged = siblings.each_with_object(Hash.new(0)) { |id, acc| (conversations_by_ad[id] || {}).each { |inbox, n| acc[inbox] += n } }
      merged.presence || false
    end
    @group_distribution[[level, group]] || nil
  end

  def creatives
    @creatives ||= Crm::AdCreative.where(account_id: @account.id).pluck(:ad_id, :adset_id, :campaign_id)
                                  .to_h { |ad_id, adset_id, campaign_id| [ad_id.to_s, { adset_id: adset_id, campaign_id: campaign_id }] }
  end
end
