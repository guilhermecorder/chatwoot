require 'rails_helper'

# 🎯 item 352: as regras do Agente de Campanhas contra a NOSSA média
RSpec.describe Cevico::CampaignAgent::Rules do
  let(:account) { create(:account) }
  # nossa média de 30 dias: custo por agendamento R$ 100, CTR 1 %, CPM R$ 10, lead por clique 10 %, agendamento 10 %
  let(:baseline_row) do
    row(level: 'channel', channel: 'meta', id: 'meta', name: 'Meta', spend: 3000, impressions: 300_000, clicks: 3000, leads: 300, booked: 30)
      .merge('days' => 30, 'daily_spend' => 100.0)
  end
  let(:baselines) do
    { 'meta' => { 30 => baseline_row }, 'google' => { 30 => baseline_row.merge('channel' => 'google') }, 'all' => { 30 => baseline_row } }
  end
  let(:today) { Date.new(2026, 10, 18) }
  let(:params) { Cevico::CampaignAgent::Params.merge({}) }
  let(:row_mod) { Cevico::CampaignAgent::Row }

  # linha fechada no formato do Reader
  def row(level:, channel:, id:, name:, spend:, **extra) # rubocop:disable Metrics/ParameterLists
    base = row_mod.blank.merge(
      'spend' => spend, 'impressions' => extra.fetch(:impressions, 0), 'reach' => extra.fetch(:reach, 0),
      'link_clicks' => extra.fetch(:clicks, 0), 'clicks' => extra.fetch(:clicks, 0), 'leads' => extra.fetch(:leads, 0),
      'booked' => extra.fetch(:booked, 0), 'surgeries' => extra.fetch(:surgeries, 0), 'revenue' => extra.fetch(:revenue, 0)
    )
    row_mod.finish(base, goal: 'booked', video: false).merge(
      'level' => level, 'channel' => channel, 'id' => id, 'name' => name, 'status' => extra.fetch(:status, 'ACTIVE'),
      'first_day' => extra[:first_day], 'daily_budget' => extra[:daily_budget], 'children' => extra.fetch(:children, []),
      'campaign_id' => extra[:campaign_id], 'campaign_name' => extra[:campaign_name], 'parent_id' => extra[:parent_id]
    )
  end

  def window_for(campaigns)
    flat = campaigns.flat_map { |c| [c] + c['children'].flat_map { |s| [s] + s['children'] } }
    { campaigns: campaigns, flat: flat, totals: {} }
  end

  def run(campaigns, previous: [], month: {}, touched: Set.new, observing: Set.new, prm: params) # rubocop:disable Metrics/ParameterLists
    described_class.new(account: account, params: prm, baselines: baselines, window: window_for(campaigns),
                        previous: { flat: previous }, month: { totals: month }, touched: touched, observing: observing, today: today).call
  end

  def meta_campaign(adsets)
    row(level: 'campaign', channel: 'meta', id: 'c1', name: 'Campanha X', spend: adsets.sum { |a| a['spend'] }, booked: adsets.sum do |a|
      a['booked']
    end,
        children: adsets)
  end

  it 'pausa o conjunto com custo 2× a nossa média e reduz verba em quem está 40 % acima' do
    bad = row(level: 'adset', channel: 'meta', id: 'a1', name: 'Conjunto caro', spend: 600, booked: 3, daily_budget: 50, campaign_id: 'c1',
              campaign_name: 'Campanha X')
    meh = row(level: 'adset', channel: 'meta', id: 'a2', name: 'Conjunto morno', spend: 560, booked: 4, daily_budget: 50, campaign_id: 'c1',
              campaign_name: 'Campanha X')
    list = run([meta_campaign([bad, meh])])

    pause = list.find { |a| a[:ref_id] == 'a1' && a[:rule] == 'custo_alto' }
    expect(pause).to include(kind: 'pause', severity: 'alerta', level: 'adset', campaign_name: 'Campanha X')
    expect(pause[:title]).to include('2× acima')
    down = list.find { |a| a[:ref_id] == 'a2' && a[:rule] == 'custo_alto' }
    expect(down).to include(kind: 'budget_down', severity: 'atencao')
    expect(down[:payload]).to include('budget_from' => 50.0, 'budget_to' => 40.0, 'pct' => -20, 'window_days' => 7)
    expect(down[:metrics_before]).to include('spend' => 560.0, 'goal_events' => 4, 'goal_cost' => 140.0)
  end

  it 'pausa quem gastou o que a média cobraria por 2 resultados e não trouxe nenhum' do
    empty = row(level: 'adset', channel: 'meta', id: 'a3', name: 'Sem resultado', spend: 300, clicks: 40, leads: 1, campaign_id: 'c1')
    list = run([meta_campaign([empty])])
    found = list.find { |a| a[:rule] == 'sem_resultado' }
    expect(found).to include(kind: 'pause', severity: 'alerta', ref_id: 'a3')
    expect(found[:evidence]).to include('R$ 300').and include('nenhum agendamento')
  end

  it 'sobe a verba da campeã um passo, respeitando o teto diário' do
    champ = row(level: 'adset', channel: 'meta', id: 'a4', name: 'Campeã', spend: 400, booked: 8, daily_budget: 100, campaign_id: 'c1')
    found = run([meta_campaign([champ])]).find { |a| a[:rule] == 'campea' }
    expect(found).to include(kind: 'budget_up', severity: 'oportunidade')
    expect(found[:payload]).to include('budget_from' => 100.0, 'budget_to' => 120.0, 'capped' => false)

    capped = run([meta_campaign([champ])], prm: params.merge('daily_cap' => 110.0)).find { |a| a[:rule] == 'campea' }
    expect(capped[:payload]).to include('budget_to' => 110.0, 'capped' => true)
  end

  it 'campeã vira só aviso quando a verba do mês do canal já passou do ritmo' do
    champ = row(level: 'adset', channel: 'meta', id: 'a4', name: 'Campeã', spend: 400, booked: 8, daily_budget: 100, campaign_id: 'c1')
    month = { 'meta' => row(level: 'channel', channel: 'meta', id: 'meta', name: 'Meta', spend: 12_000) }
    found = run([meta_campaign([champ])], month: month).find { |a| a[:rule] == 'campea' }
    expect(found).to include(kind: 'watch', severity: 'info')
  end

  it 'detecta anúncio cansado (frequência alta + CTR caindo) e CTR baixo sem fadiga' do
    tired = row(level: 'ad', channel: 'meta', id: 'ad1', name: 'Cansado', spend: 100, impressions: 5000, reach: 1000, clicks: 20, campaign_id: 'c1',
                parent_id: 'a5')
    weak = row(level: 'ad', channel: 'meta', id: 'ad2', name: 'Fraco', spend: 100, impressions: 5000, reach: 4000, clicks: 25, campaign_id: 'c1',
               parent_id: 'a5')
    adset = row(level: 'adset', channel: 'meta', id: 'a5', name: 'Conjunto', spend: 200, booked: 2, campaign_id: 'c1', children: [tired, weak])
    prev_tired = row(level: 'ad', channel: 'meta', id: 'ad1', name: 'Cansado', spend: 100, impressions: 5000, reach: 4000, clicks: 50)
    list = run([meta_campaign([adset])], previous: [prev_tired])

    fatigue = list.find { |a| a[:ref_id] == 'ad1' }
    expect(fatigue).to include(rule: 'fadiga', kind: 'new_creative')
    expect(fatigue[:evidence]).to include('Frequência 5')
    ctr = list.find { |a| a[:ref_id] == 'ad2' }
    expect(ctr).to include(rule: 'ctr_baixo', kind: 'new_creative')
  end

  it 'no Google: campanha que clica e não vira lead + custo 2× → página e pausa' do
    g = row(level: 'campaign', channel: 'google', id: 'g1', name: '[Search] Catarata', spend: 700, clicks: 100, leads: 2, booked: 2)
    list = run([g])
    expect(list.map { |a| [a[:rule], a[:kind]] }).to include(%w[pagina_nao_converte page], %w[custo_alto pause])
    expect(list.find { |a| a[:rule] == 'pagina_nao_converte' }[:suggestion]).to include('Otimizar')
  end

  it 'lê o ritmo da verba do mês por canal' do
    month = { 'meta' => row(level: 'channel', channel: 'meta', id: 'meta', name: 'Meta', spend: 2000),
              'google' => row(level: 'channel', channel: 'google', id: 'google', name: 'Google', spend: 9000) }
    list = run([], month: month)
    expect(list.map { |a| a[:rule] }).to eq(['verba_parada'])
    expect(list.first).to include(channel: 'meta', level: 'channel', kind: 'pacing', severity: 'oportunidade')
    expect(list.first[:expected]).to include('R$ 13.000')
  end

  it 'respeita o aprendizado: item mexido há pouco e item novo não recebem regra de custo' do
    bad = row(level: 'adset', channel: 'meta', id: 'a1', name: 'Caro', spend: 600, booked: 3, campaign_id: 'c1')
    fresh = row(level: 'adset', channel: 'meta', id: 'a9', name: 'Novo', spend: 600, booked: 3, first_day: (today - 3).iso8601, campaign_id: 'c1')
    list = run([meta_campaign([bad, fresh])], touched: Set.new(['a1']))
    expect(list.none? { |a| a[:ref_id] == 'a1' }).to be(true)
    expect(list.find { |a| a[:ref_id] == 'a9' }).to include(rule: 'em_aprendizado', kind: 'watch', severity: 'info')
  end

  it 'regra em observação só avisa' do
    champ = row(level: 'adset', channel: 'meta', id: 'a4', name: 'Campeã', spend: 400, booked: 8, daily_budget: 100, campaign_id: 'c1')
    found = run([meta_campaign([champ])], observing: Set.new(['campea'])).find { |a| a[:rule] == 'campea' }
    expect(found).to include(kind: 'watch', severity: 'info')
    expect(found[:title]).to start_with('(em observação)')
  end

  it 'fica calado abaixo do volume mínimo e no fim de semana quando pedido' do
    small = row(level: 'adset', channel: 'meta', id: 'a7', name: 'Pequeno', spend: 80, booked: 0, campaign_id: 'c1')
    expect(run([meta_campaign([small])])).to eq([])
    bad = row(level: 'adset', channel: 'meta', id: 'a1', name: 'Caro', spend: 600, booked: 3, campaign_id: 'c1')
    weekend = described_class.new(account: account, params: params.merge('weekend' => true), baselines: baselines,
                                  window: window_for([meta_campaign([bad])]), previous: { flat: [] }, month: { totals: {} },
                                  today: Date.new(2026, 10, 17)).call
    expect(weekend).to eq([])
  end
end
