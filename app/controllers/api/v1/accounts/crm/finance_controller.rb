# GESTÃO FINANCEIRA (só admin): dashboard com indicadores do período
# (presets ou datas livres), histórico mensal de 12 meses para o gráfico
# de linha, lançamentos (CRUD) e comparação de dois meses lado a lado.
class Api::V1::Accounts::Crm::FinanceController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  before_action -> { require_capability(:finance) }

  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  HISTORY_MONTHS = 12
  ENTRIES_LIMIT = 300

  def show
    from, to = resolve_period
    scope = entries.in_period(from, to)
    render json: {
      period: { from: from.iso8601, to: to.iso8601, preset: params[:preset].presence },
      kinds: CevicoFinanceEntry::KINDS,
      categories: CevicoFinanceEntry::CATEGORIES,
      summary: build_summary(scope),
      by_category: build_by_category(scope),
      monthly: monthly_series,
      entries: scope.order(entry_date: :desc, id: :desc).limit(ENTRIES_LIMIT).map { |e| entry_json(e) }
    }
  end

  def create_entry
    entry = entries.new(entry_params.merge(created_by_id: Current.user.id))
    return render json: { error: entry.errors.full_messages.first }, status: :unprocessable_entity unless entry.save

    render json: entry_json(entry)
  end

  def update_entry
    entry = entries.find(params[:entry_id])
    return render json: { error: entry.errors.full_messages.first }, status: :unprocessable_entity unless entry.update(entry_params)

    render json: entry_json(entry)
  end

  def delete_entry
    entries.find(params[:entry_id]).destroy!
    head :ok
  end

  # dois meses lado a lado: totais por tipo + quebra por categoria
  def compare
    month_a = parse_month(params[:month_a])
    month_b = parse_month(params[:month_b])
    return render json: { error: 'Escolha os dois meses.' }, status: :unprocessable_entity if month_a.nil? || month_b.nil?

    render json: {
      kinds: CevicoFinanceEntry::KINDS,
      categories: CevicoFinanceEntry::CATEGORIES,
      a: month_snapshot(month_a),
      b: month_snapshot(month_b)
    }
  end

  private

  def entries
    Current.account.cevico_finance_entries
  end


  def entry_params
    {
      entry_date: (Date.parse(params[:entry_date].to_s) rescue nil) || TZ.now.to_date, # rubocop:disable Style/RescueModifier
      kind: params[:kind].to_s,
      category: params[:category].to_s.presence,
      description: params[:description].to_s.strip[0, 300],
      amount: params[:amount].to_f.round(2)
    }
  end

  # presets iguais aos dos outros painéis + "personalizado" (from/to livres)
  def resolve_period # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    today = TZ.now.to_date
    case params[:preset].presence
    when 'today' then [today, today]
    when 'yesterday' then [today - 1, today - 1]
    when 'week' then [today.beginning_of_week, today]
    when 'last_month' then [(today << 1).beginning_of_month, (today << 1).end_of_month]
    when 'year' then [today.beginning_of_year, today]
    when 'custom'
      from = Date.parse(params[:from].to_s) rescue nil # rubocop:disable Style/RescueModifier
      to = Date.parse(params[:to].to_s) rescue nil # rubocop:disable Style/RescueModifier
      from && to && from <= to ? [from, to] : [today.beginning_of_month, today]
    else [today.beginning_of_month, today] # 'month' (padrão)
    end
  end

  def totals_by_kind(scope)
    sums = scope.group(:kind).sum(:amount)
    CevicoFinanceEntry::KINDS.keys.index_with { |k| sums[k].to_f.round(2) }
  end

  def build_summary(scope)
    t = totals_by_kind(scope)
    receita = t['receita']
    custos = t['custo']
    tributos = t['tributo']
    investimentos = t['investimento_produto'] + t['investimento_equipamento']
    lucro = (receita - custos - tributos).round(2)
    t.merge(
      'investimentos' => investimentos.round(2),
      'lucro' => lucro,
      'margem' => receita.positive? ? ((lucro / receita) * 100).round(1) : nil,
      'caixa' => (lucro - investimentos).round(2),
      'lancamentos' => scope.count
    )
  end

  def build_by_category(scope)
    sums = scope.group(:kind, :category).sum(:amount)
    CevicoFinanceEntry::KINDS.keys.index_with do |kind|
      sums.select { |(k, _c), _v| k == kind }
          .map { |(_k, cat), v| { category: cat, label: category_label(kind, cat), total: v.to_f.round(2) } }
          .sort_by { |row| -row[:total] }
    end
  end

  def category_label(kind, category)
    CevicoFinanceEntry::CATEGORIES.dig(kind, category) || category.presence || 'Sem categoria'
  end

  # série de 12 meses para o gráfico de linha (receita, saídas, lucro)
  def monthly_series # rubocop:disable Metrics/AbcSize
    from = (TZ.now.to_date << (HISTORY_MONTHS - 1)).beginning_of_month
    sums = entries.where(entry_date: from..).group(:kind, Arel.sql("date_trunc('month', entry_date)")).sum(:amount)

    (0...HISTORY_MONTHS).map do |i|
      month = (from >> i).beginning_of_month
      value = ->(kind) { (sums.find { |(k, m), _v| k == kind && m.to_date == month }&.last || 0).to_f.round(2) }
      receita = value.call('receita')
      tributos = value.call('tributo')
      custos = value.call('custo')
      invest = (value.call('investimento_produto') + value.call('investimento_equipamento')).round(2)
      {
        month: month.iso8601,
        receita: receita,
        tributos: tributos,
        custos: custos,
        investimentos: invest,
        lucro: (receita - tributos - custos).round(2)
      }
    end
  end

  def month_snapshot(month)
    scope = entries.in_period(month, month.end_of_month)
    {
      month: month.iso8601,
      summary: build_summary(scope),
      by_category: build_by_category(scope)
    }
  end

  def parse_month(value)
    Date.parse(value.to_s).beginning_of_month
  rescue ArgumentError, TypeError
    nil
  end

  def entry_json(entry)
    {
      id: entry.id,
      entry_date: entry.entry_date.iso8601,
      kind: entry.kind,
      category: entry.category,
      category_label: category_label(entry.kind, entry.category),
      kind_label: CevicoFinanceEntry::KINDS[entry.kind],
      description: entry.description,
      amount: entry.amount.to_f
    }
  end
end
