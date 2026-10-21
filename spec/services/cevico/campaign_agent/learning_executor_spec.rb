require 'rails_helper'

# 🎯 item 352: aprendizado (antes × depois) e o executor (API da Meta × à mão)
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe 'Agente de Campanhas — aprendizado e executor' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:params) { Cevico::CampaignAgent::Params.merge({}) }
  let(:today) { Date.new(2026, 10, 18) }

  def action(attrs = {})
    Crm::CampaignAction.create!({ account: account, channel: 'meta', level: 'adset', ref_id: 'a1', ref_name: 'Conjunto', rule: 'custo_alto',
                                  kind: 'budget_down', severity: 'atencao', status: 'applied', key: 'meta:adset:a1:custo_alto',
                                  title: 'Custo acima', suggested_on: today - 10, applied_at: (today - 9).to_time.change(hour: 10),
                                  applied_mode: 'manual', metrics_before: { 'spend' => 500, 'goal_cost' => 100.0, 'goal_events' => 5 },
                                  payload: { 'budget_to' => 40.0 } }.merge(attrs))
  end

  def stub_reader(flat)
    reader = instance_double(Cevico::CampaignAgent::Reader, call: { flat: flat, totals: {}, campaigns: [] })
    allow(Cevico::CampaignAgent::Reader).to receive(:new).and_return(reader)
  end

  describe Cevico::CampaignAgent::Learning do
    it 'dá o veredito pelo custo da estrela-guia e monta o placar' do
      better = action
      worse = action(ref_id: 'a2', key: 'meta:adset:a2:custo_alto')
      paused = action(ref_id: 'a3', key: 'meta:adset:a3:sem_resultado', rule: 'sem_resultado', kind: 'pause')
      early = action(ref_id: 'a4', key: 'meta:adset:a4:custo_alto')
      stub_reader([
                    { 'channel' => 'meta', 'level' => 'adset', 'id' => 'a1', 'spend' => 400, 'goal_cost' => 80.0, 'goal_events' => 5, 'rates' => {} },
                    { 'channel' => 'meta', 'level' => 'adset', 'id' => 'a2', 'spend' => 400, 'goal_cost' => 130.0, 'goal_events' => 3,
                      'rates' => {} },
                    { 'channel' => 'meta', 'level' => 'adset', 'id' => 'a4', 'spend' => 20, 'goal_cost' => nil, 'goal_events' => 0, 'rates' => {} }
                  ])

      expect(described_class.new(account: account, params: params, today: today).call).to eq(4)
      expect(better.reload.outcome).to eq('better')
      expect(better.metrics_after).to include('goal_cost' => 80.0, 'since' => (today - 8).iso8601)
      expect(worse.reload.outcome).to eq('worse')
      expect(paused.reload.outcome).to eq('saved')
      expect(early.reload.outcome).to eq('early')

      board = described_class.scoreboard(account)
      expect(board.find { |r| r[:rule] == 'custo_alto' }).to include(better: 1, worse: 1, early: 1, learned: 3, confidence: 0.5, observing: false)
      expect(described_class.observing(account)).to be_empty
    end

    it 'põe em observação a regra que errou mais do que acertou' do
      5.times { |i| action(ref_id: "x#{i}", key: "k#{i}", outcome: 'worse', learned_at: Time.current) }
      action(ref_id: 'y', key: 'ky', outcome: 'better', learned_at: Time.current)
      expect(described_class.observing(account)).to eq(Set.new(['custo_alto']))
    end
  end

  describe Cevico::CampaignAgent::Executor do
    let(:user) { create(:user, account: account, role: :administrator) }

    before { CrmSetting.create!(account: account, meta_ads_config: { 'access_token' => 'simulate', 'ad_account_id' => 'act_1' }) }

    it 'aplica pela API da Meta quando a chavinha está ligada' do
      Cevico::CampaignAgent::Params.save!(account, 'execute_api' => true)
      a = action(status: 'approved', applied_at: nil, applied_mode: nil)
      result = described_class.new(account: account, user: user).apply(a)
      expect(result).to eq(ok: true, mode: 'api')
      expect(a.reload).to have_attributes(status: 'applied', applied_mode: 'api', decided_by_id: user.id)
      expect(a.applied_at).to be_present
    end

    it 'sem a chavinha devolve o passo a passo e aceita "fiz à mão"' do
      a = action(status: 'approved', applied_at: nil, applied_mode: nil)
      ex = described_class.new(account: account, user: user)
      result = ex.apply(a)
      expect(result[:mode]).to eq('manual')
      expect(result[:steps].join(' ')).to include('reduzir para R$ 40,00 por dia')
      expect(a.reload.status).to eq('approved')

      expect(ex.mark_manual(a)).to eq(ok: true, mode: 'manual')
      expect(a.reload).to have_attributes(status: 'applied', applied_mode: 'manual')
    end

    it 'recusa aplicar o que não foi aprovado' do
      a = action(status: 'suggested', applied_at: nil, applied_mode: nil)
      expect(described_class.new(account: account).apply(a)[:ok]).to be(false)
      expect(described_class.new(account: account).mark_manual(a)[:ok]).to be(false)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
