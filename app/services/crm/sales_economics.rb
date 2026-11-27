# 📊 CUSTOS E RETORNO NO MEU PAINEL (27/11/2026 · LIFE, pedido do Guilherme): "quanto está custando, qual que é o
# nosso ROAS… quanto a gente está investindo, tanto em anúncio, quanto em API e inteligência artificial, e quanto
# está voltando. Quanto tempo mais ou menos demora para a gente fechar". Fica exposto para ele e para o Fernando.
#
# Régua (no período escolhido, a mesma régua de período da Jornada da venda):
#   · CUSTO por categoria (tráfego, API de IA, WhatsApp API): o LANÇADO à mão (Crm::SalesCosts, rateado pelos dias)
#     vence; sem lançamento cobrindo o período, vale o MEDIDO pelo sistema (Crm::AcquisitionCostService: gasto da
#     conta de anúncios da Meta/Google, consumo de IA gravado em crm_ai_usages e fatura do WhatsApp da Meta).
#   · RETORNO = soma do valor das vendas: cartões que ENTRARAM em "Contrato Assinado" (ou depois: Homologação,
#     Instalação) no período. Valor = o do cartão; sem valor, o do último orçamento enviado ao cliente.
#   · ROAS = retorno ÷ custo total; ROAS do anúncio = retorno ÷ tráfego.
#   · CUSTO POR ETAPA = custo total ÷ pessoas da coorte (Crm::QuoteJourney) que chegaram a cada etapa.
#   · TEMPOS (medianas, de quem chegou no período): chegada → conta recebida, chegada → orçamento enviado e
#     chegada → contrato (este, das vendas do período).
#   · EQUIPE: Crm::TeamResponse (espera do cliente pelo humano e intervalos no horário comercial).
class Crm::SalesEconomics
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  CLOSED = /\A(contrato (assinado|fechado)|homologacao|instalacao)\z/
  BILL = /\A(orcamento a fazer|recebimento da conta)\z/

  def initialize(account, since:, until_at:)
    @account = account
    @since = since
    @until = until_at
    @from = since.in_time_zone(TZ).to_date
    @to = until_at.in_time_zone(TZ).to_date
  end

  def call
    cost = costs
    sales = closed_sales
    revenue = sales.sum { |s| s[:value] }.round(2)
    {
      since: @since, until: @until,
      costs: cost, revenue: revenue_json(sales, revenue),
      roas: ratio(revenue, cost[:total]), roas_ads: ratio(revenue, cost[:by_key]['trafego']),
      per_step: per_step(cost[:total]), pipeline: pipeline_json, times: times_json(sales),
      team: Crm::TeamResponse.new(@account, since: @since, until_at: @until).call,
      entries: Crm::SalesCosts.new(@account).list
    }
  end

  private

  # ── custos ────────────────────────────────────────────────────────────────
  def costs
    manual = Crm::SalesCosts.new(@account).spread(@from, @to)
    covered = Crm::SalesCosts.new(@account).covered(@from, @to)
    auto = measured
    rows = Crm::SalesCosts::CATEGORIES.map do |key, label|
      used_manual = covered.include?(key)
      { key: key, label: label, lancado: manual[key], medido: auto[key],
        valor: used_manual ? manual[key] : auto[key].to_f, fonte: if used_manual
                                                                    'lancado'
                                                                  else
                                                                    (auto[key] ? 'medido' : nil)
                                                                  end }
    end
    by_key = rows.to_h { |r| [r[:key], r[:valor].to_f.round(2)] }
    { rows: rows, by_key: by_key, total: by_key.values.sum.round(2) }
  end

  # o que o sistema já mede sozinho (nil = não mede essa categoria nesta conta)
  def measured
    svc = Crm::AcquisitionCostService.new(account: @account, since: @since, until_at: @until)
    m = svc.measured_costs
    { 'trafego' => m[:ads_configured] ? m[:ads] : nil, 'ia' => m[:ai], 'whatsapp' => m[:whatsapp_synced] ? m[:whatsapp] : nil }
  rescue StandardError => e
    Rails.logger.warn "[Crm::SalesEconomics] custo medido indisponível: #{e.message}"
    { 'trafego' => nil, 'ia' => nil, 'whatsapp' => nil }
  end

  # ── retorno ───────────────────────────────────────────────────────────────
  def closed_sales # rubocop:disable Metrics/AbcSize
    ids = stage_ids(CLOSED)
    return [] if ids.empty?

    logs = Crm::StageLog.where(stage_id: ids, entered_at: @since..@until).order(:entered_at)
    first_by_card = logs.group_by(&:crm_contact_id).transform_values(&:first)
    # só conta a venda uma vez: quem já tinha entrado numa coluna de contrato ANTES do período fica de fora
    before = Crm::StageLog.where(stage_id: ids, crm_contact_id: first_by_card.keys).where(entered_at: ...@since)
                          .distinct.pluck(:crm_contact_id)
    cards = Crm::Contact.where(id: first_by_card.keys - before).includes(:contact).index_by(&:id)
    cards.values.map do |card|
      entered = first_by_card[card.id].entered_at
      { contact_id: card.contact_id, name: card.contact&.name, value: sale_value(card),
        days: ((entered - card.created_at) / 1.day).round(1), at: entered }
    end
  end

  def sale_value(card)
    return card.value.to_f if card.value.to_f.positive?

    Crm::Quote.where(account_id: @account.id, contact_id: card.contact_id, deleted_at: nil).where.not(sent_at: nil)
              .order(sent_at: :desc).pick(:price).to_f
  end

  def revenue_json(sales, revenue)
    { total: revenue, sales: sales.size, ticket: sales.any? ? (revenue / sales.size).round(2) : nil,
      people: sales.sort_by { |s| -s[:value] }.first(20).map { |s| s.except(:at) } }
  end

  # ── orçamentos enviados no período (o que está "na mesa") ────────────────
  def pipeline_json
    quotes = Crm::Quote.where(account_id: @account.id, deleted_at: nil, sent_at: @since..@until)
    sent = quotes.group(:contact_id).maximum(:price)
    { quotes: sent.size, value: sent.values.sum(&:to_f).round(2),
      ticket: sent.any? ? (sent.values.sum(&:to_f) / sent.size).round(2) : nil }
  end

  # ── custo por etapa ───────────────────────────────────────────────────────
  def per_step(total)
    journey = Crm::QuoteJourney.new(@account, since: @since, until_at: @until).call
    counts = journey[:steps].to_h { |s| [s[:key], s[:count]] }
    %w[leads conta enviado fechado].map do |key|
      step = journey[:steps].find { |s| s[:key] == key }
      { key: key, label: step[:label], people: counts[key].to_i, cost: ratio_money(total, counts[key]) }
    end
  end

  # ── tempos ────────────────────────────────────────────────────────────────
  def times_json(sales)
    arrivals = cohort_arrivals
    bill = first_entry_by_contact(stage_ids(BILL), arrivals.keys)
    quote = Crm::Quote.where(account_id: @account.id, contact_id: arrivals.keys, deleted_at: nil).where.not(sent_at: nil)
                      .group(:contact_id).minimum(:sent_at)
    {
      ate_conta: median_hours(bill, arrivals),
      ate_orcamento: median_hours(quote, arrivals),
      ate_fechar: { n: sales.size, mediana_dias: median(sales.pluck(:days)) }
    }
  end

  # contact_id => quando a pessoa chegou (cartão do funil criado no período)
  def cohort_arrivals
    @cohort_arrivals ||= Crm::Contact.where(pipeline_id: main_pipeline&.id, created_at: @since..@until)
                                     .pluck(:contact_id, :created_at).to_h
  end

  # crm card → contact: a primeira entrada de cada contato numa das colunas
  def first_entry_by_contact(ids, contact_ids)
    return {} if ids.empty? || contact_ids.empty?

    Crm::StageLog.joins('INNER JOIN crm_contacts ON crm_contacts.id = crm_contact_stage_logs.crm_contact_id')
                 .where(stage_id: ids, crm_contacts: { contact_id: contact_ids })
                 .group('crm_contacts.contact_id').minimum(:entered_at)
  end

  def median_hours(reached, arrivals)
    hours = reached.filter_map do |contact_id, at|
      start = arrivals[contact_id]
      ((at - start) / 1.hour).round(1) if start && at && at >= start
    end
    { n: hours.size, mediana_horas: median(hours) }
  end

  # ── apoio ─────────────────────────────────────────────────────────────────
  def main_pipeline
    @main_pipeline ||= Crm::Pipeline.where(account: @account).order(:position, :id).first
  end

  def stage_ids(pattern)
    return [] unless main_pipeline

    main_pipeline.stages.select { |s| I18n.transliterate(s.name.to_s).downcase.squish.match?(pattern) }.map(&:id)
  end

  def median(values)
    list = values.compact.sort
    return nil if list.empty?

    mid = list.size / 2
    (list.size.odd? ? list[mid] : (list[mid - 1] + list[mid]) / 2.0).round(1)
  end

  def ratio(num, den)
    den.to_f.positive? ? (num.to_f / den).round(2) : nil
  end

  def ratio_money(total, count)
    count.to_i.positive? && total.to_f.positive? ? (total.to_f / count).round(2) : nil
  end
end
