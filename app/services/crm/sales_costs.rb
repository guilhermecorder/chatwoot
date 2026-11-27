# 💸 CUSTOS DA VENDA (27/11/2026 · LIFE, pedido do Guilherme): "colocar todo mês o valor que foi investido em
# tráfego, ou até toda semana… em tráfego, em API de IA e na WhatsApp API oficial… à disposição no meu painel para
# que todos que acessem ali tenham acesso a quanto está custando".
#
# Cada lançamento é um CevicoFinanceEntry (a mesma tabela da Gestão Financeira, sem migration nova) com
# kind 'custo' e uma das 3 categorias abaixo. O lançamento cobre um PERÍODO: a semana (7 dias a partir da data)
# ou o mês da data. A descrição guarda o período ("semana" | "mes") e uma observação opcional: "mes · obs".
# Para o painel, o valor é espalhado pelos dias que ele cobre (rateio): R$ 700 da semana = R$ 100 por dia, e o
# período escolhido no painel soma só os dias que caem dentro dele.
class Crm::SalesCosts
  CATEGORIES = {
    'trafego' => 'Tráfego (anúncios)',
    'ia' => 'API de IA',
    'whatsapp' => 'WhatsApp API oficial'
  }.freeze
  SPANS = %w[semana mes].freeze
  KIND = 'custo'.freeze

  def initialize(account)
    @account = account
  end

  def entries
    CevicoFinanceEntry.where(account_id: @account.id, kind: KIND, category: CATEGORIES.keys)
  end

  def create!(category:, amount:, date:, span:, note: nil, user: nil) # rubocop:disable Metrics/ParameterLists
    raise ArgumentError, 'categoria' unless CATEGORIES.key?(category.to_s)
    raise ArgumentError, 'período' unless SPANS.include?(span.to_s)

    day = date.is_a?(Date) ? date : Date.parse(date.to_s)
    day = day.beginning_of_month if span.to_s == 'mes'
    value = Cevico::Money.parse(amount) || 0.0
    entries.create!(category: category.to_s, amount: value, entry_date: day,
                    description: [span, note.to_s.strip.presence].compact.join(' · ')[0, 300],
                    created_by_id: user&.id)
  end

  # rateio por categoria no período [from, to] (datas): { 'trafego' => 1234.5, … }
  def spread(from, to) # rubocop:disable Metrics/AbcSize
    totals = CATEGORIES.keys.index_with { 0.0 }
    entries.where(entry_date: (from - 31.days)..to).find_each do |entry|
      first, last = coverage(entry)
      overlap = ([last, to].min - [first, from].max).to_i + 1
      next unless overlap.positive?

      totals[entry.category] += entry.amount.to_f * overlap / ((last - first).to_i + 1)
    end
    totals.transform_values { |v| v.round(2) }
  end

  # categorias que têm ALGUM lançamento cobrindo o período (o lançado vence o medido)
  def covered(from, to)
    entries.where(entry_date: (from - 31.days)..to).each_with_object(Set.new) do |entry, set|
      first, last = coverage(entry)
      set << entry.category if first <= to && last >= from
    end
  end

  def list(limit: 60)
    entries.order(entry_date: :desc, id: :desc).limit(limit).map { |e| json(e) }
  end

  def json(entry)
    first, last = coverage(entry)
    span, note = entry.description.to_s.split(' · ', 2)
    { id: entry.id, category: entry.category, label: CATEGORIES[entry.category], amount: entry.amount.to_f,
      span: SPANS.include?(span) ? span : 'mes', note: note, from: first.iso8601, to: last.iso8601 }
  end

  private

  def coverage(entry)
    first = entry.entry_date
    span = entry.description.to_s.split(' · ', 2).first
    last = span == 'semana' ? first + 6.days : first.end_of_month
    [first, last]
  end
end
