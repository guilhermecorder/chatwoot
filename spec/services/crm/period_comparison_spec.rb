require 'rails_helper'

# 📐 item 394 (11/11) — BASE DE COMPARAÇÃO: "comparar com a semana passada, o
# mês passado, um mês com o outro". Um ponto só no servidor diz qual é o
# intervalo a comparar e como ele se chama na tela.
RSpec.describe Crm::PeriodComparison do
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }

  def at(text)
    tz.parse(text)
  end

  def dates(cmp)
    [cmp.since.to_date.to_s, cmp.until_at.to_date.to_s]
  end

  it 'sem escolha, compara com o período de mesmo tamanho logo antes', :aggregate_failures do
    cmp = described_class.new(at('2026-11-05 00:00'), at('2026-11-11 12:00').end_of_day, preset: 'last7')

    expect(cmp.mode).to eq('previous')
    expect(dates(cmp)).to eq(%w[2026-10-29 2026-11-04])
    expect(cmp.label).to eq('7 dias anteriores')
    expect(cmp.range_label).to eq('29/10–04/11')
  end

  it 'hoje compara com ontem' do
    cmp = described_class.new(at('2026-11-11 00:00'), at('2026-11-11 23:59:59'), preset: 'today')

    expect([dates(cmp), cmp.label, cmp.range_label]).to eq([%w[2026-11-10 2026-11-10], 'ontem', '10/11'])
  end

  it 'mês fechado compara com o mês fechado anterior (outubro × setembro)', :aggregate_failures do
    cmp = described_class.new(at('2026-10-01 00:00'), at('2026-10-31 23:59:59'), preset: 'last_month')

    expect(dates(cmp)).to eq(%w[2026-09-01 2026-09-30])
    expect(cmp.label).to eq('setembro')
  end

  it 'no modo "mês passado", o mesmo trecho um mês antes', :aggregate_failures do
    cmp = described_class.new(at('2026-11-01 00:00'), at('2026-11-11 23:59:59'), mode: 'month', preset: 'month')

    expect(dates(cmp)).to eq(%w[2026-10-01 2026-10-11])
    expect(cmp.label).to eq('mesmo período de outubro')
    expect(cmp.to_h).to include(modo: 'month', rotulo: 'mesmo período de outubro', datas: '01/10–11/10')
  end

  it 'o trecho não vaza para o mês seguinte quando o mês de antes é mais curto' do
    cmp = described_class.new(at('2026-10-01 00:00'), at('2026-10-31 12:00'), mode: 'month')

    expect(dates(cmp)).to eq(%w[2026-09-01 2026-09-30])
  end

  it 'no modo "outro mês", o mesmo trecho no mês escolhido', :aggregate_failures do
    cmp = described_class.new(at('2026-11-01 00:00'), at('2026-11-11 23:59:59'), mode: 'pick', month: '2026-08')
    cheio = described_class.new(at('2026-10-01 00:00'), at('2026-10-31 23:59:59'), mode: 'pick', month: '2025-12')

    expect(dates(cmp)).to eq(%w[2026-08-01 2026-08-11])
    expect(cmp.label).to eq('mesmo período de agosto')
    expect(dates(cheio)).to eq(%w[2025-12-01 2025-12-31])
    expect(cheio.label).to eq('dezembro/25')
  end

  it 'trecho que atravessa meses não ganha nome de mês', :aggregate_failures do
    since = at('2026-08-14 00:00')
    until_at = at('2026-11-11 12:00').end_of_day

    expect(described_class.new(since, until_at, mode: 'month').label).to eq('um mês antes')
    expect(described_class.new(since, until_at, mode: 'pick', month: '2026-05').label).to eq('3 meses antes')
    expect(described_class.new(since, until_at, mode: 'month').range_label).to eq('14/07–11/10')
  end

  it 'mês escolhido inválido ou igual ao do período volta para o padrão', :aggregate_failures do
    since = at('2026-11-05 00:00')
    until_at = at('2026-11-11 23:59:59')

    expect(described_class.new(since, until_at, mode: 'pick', month: 'abc').mode).to eq('previous')
    expect(described_class.new(since, until_at, mode: 'pick', month: '2026-11').mode).to eq('previous')
    expect(described_class.new(since, until_at, mode: 'qualquer').mode).to eq('previous')
  end

  it 'a chave de cache muda com a base escolhida' do
    since = at('2026-11-01 00:00')
    until_at = at('2026-11-11 23:59:59')
    keys = [nil, 'month', 'pick'].map { |mode| described_class.new(since, until_at, mode: mode, month: '2026-08').cache_key }

    expect(keys.uniq.size).to eq(3)
  end
end
