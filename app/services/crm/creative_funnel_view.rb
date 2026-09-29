# 🔻 FUNIL do anúncio com a % DE CONVERSÃO de cada etapa (item 287, rodada 4):
# Exibições → Cliques no link → Conversas → Leads → Consultas marcadas →
# Compareceram → Cirurgias fechadas → Cirurgias realizadas.
#
# De onde vem: exibições, cliques e conversas são da Meta (Crm::AdMetrics); de
# leads em diante é a jornada do CRM (Crm::AdFunnel — aqui só se CONSOME o que
# ele devolve, inclusive `sources`, a origem de cada número).
# Como se ramifica: cada etapa mostra quantos por cento da etapa ANTERIOR
# chegaram nela e, de leads em diante, quantos por cento do total de leads.
# Para onde vai: a mesma conta feita para a conta inteira dá a seta de
# comparação (acima / abaixo da média da conta).
class Crm::CreativeFunnelView
  STEPS = [
    { key: 'impressions', label: 'Exibições', hint: 'vezes que o anúncio apareceu na tela de alguém', from: :meta },
    { key: 'link_clicks', label: 'Cliques no link', hint: 'clicaram para falar com a clínica', from: :meta,
      verb: 'das exibições viraram clique', digits: 2 },
    { key: 'conversations', label: 'Conversas', hint: 'conversas iniciadas no WhatsApp', from: :meta, verb: 'dos cliques viraram conversa' },
    { key: 'leads', label: 'Leads', hint: 'pessoas que chegaram ao atendimento por este anúncio', from: :crm,
      verb: 'das conversas viraram lead no atendimento' },
    { key: 'booked', label: 'Consultas marcadas', hint: 'desses leads, quantos marcaram consulta', from: :crm,
      verb: 'dos leads marcaram consulta' },
    { key: 'attended', label: 'Compareceram', hint: 'vieram à consulta', from: :crm, verb: 'de quem marcou compareceu' },
    { key: 'closed', label: 'Cirurgias fechadas', hint: 'cirurgia agendada — a venda', from: :crm,
      verb: 'de quem compareceu fechou a cirurgia' },
    { key: 'surgeries', label: 'Cirurgias realizadas', hint: 'já operou', from: :crm, verb: 'das cirurgias fechadas já foram realizadas' }
  ].freeze
  SOURCES = { 'booked' => [%w[booked_crm CRM], %w[booked_agenda Agenda]], 'attended' => [%w[attended_crm CRM], %w[attended_agenda Agenda]],
              'closed' => [%w[closed_crm CRM], %w[closed_agenda Agenda], %w[closed_of Oftalmofácil]],
              'surgeries' => [%w[surgeries_crm CRM], %w[surgeries_of Oftalmofácil]] }.freeze
  NEAR = 0.05
  NOTE = 'A largura de cada etapa é comprimida (as exibições são milhares de vezes maiores que as cirurgias); ' \
         'o número e a % ao lado são os valores exatos.'.freeze

  def initialize(totals:, funnel:, account_totals: nil, account_funnel: nil)
    @counts = counts_of(totals, funnel)
    @account = account_totals && counts_of(account_totals, account_funnel)
    @sources = ((funnel || {}).to_h.deep_stringify_keys['sources'] || {})
  end

  def call
    list = STEPS.select { |step| @counts.key?(step[:key]) }
    top = [@counts[list.first[:key]].to_f, 1].max
    rows = list.each_with_index.map { |step, index| row(step, index.zero? ? nil : list[index - 1], top) }
    { steps: rows, note: NOTE }
  end

  private

  def counts_of(totals, funnel)
    meta = (totals || {}).to_h.stringify_keys
    crm = (funnel || {}).to_h.stringify_keys
    # etapa sem número (anúncio sem nenhum lead no período) entra como zero: o funil aparece inteiro
    STEPS.to_h { |step| [step[:key], (step[:from] == :meta ? meta : crm)[step[:key]].to_i] }
  end

  def row(step, previous, top) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    count = @counts[step[:key]]
    rate = previous && share(count, @counts[previous[:key]])
    average = previous && @account && share(@account[step[:key]], @account[previous[:key]])
    digits = step[:digits] || 1
    step.slice(:key, :label, :hint).merge(
      count: count, width: width(count, top), rate: rate, rate_text: rate && percent(rate, digits),
      conversion_text: rate && "#{percent(rate, digits)} #{step[:verb]}", over: rate.present? && rate > 1,
      of_leads_text: of_leads(step, count), average: average, average_text: average && percent(average, digits),
      versus: versus(rate, average, digits), source_text: source_text(step, count)
    )
  end

  def share(part, whole)
    whole.to_i.positive? ? (part.to_f / whole.to_i).round(4) : nil
  end

  # escala comprimida (raiz cúbica), com piso para a etapa nunca sumir
  def width(count, top)
    return 0 unless count.positive?

    (Math.cbrt(count / top) * 100).round(1).clamp(6, 100)
  end

  def of_leads(step, count)
    leads = @counts['leads'].to_i
    return nil if step[:from] != :crm || step[:key] == 'leads' || leads.zero?

    "#{percent(count.to_f / leads, 1)} do total de leads"
  end

  def versus(rate, average, digits)
    return nil if rate.nil? || average.nil? || !average.positive?
    return 'even' if percent(rate, digits) == percent(average, digits) # iguais no que a tela mostra

    ratio = rate / average
    return 'even' if (ratio - 1).abs <= NEAR

    ratio > 1 ? 'above' : 'below'
  end

  # "de onde vem: 20 pelo CRM, 9 pela Agenda" (só na tela interna; a mesma pessoa
  # pode estar nos dois lugares, por isso a soma pode passar do total)
  def source_text(step, _count)
    parts = (SOURCES[step[:key]] || []).filter_map do |key, name|
      number = @sources[key].to_i
      "#{number} #{name == 'Agenda' ? 'pela' : 'pelo'} #{name}" if number.positive?
    end
    parts.any? ? "de onde vem: #{parts.join(', ')}" : nil
  end

  def percent(rate, digits)
    "#{format("%.#{digits}f", rate * 100).tr('.', ',')}%"
  end
end
