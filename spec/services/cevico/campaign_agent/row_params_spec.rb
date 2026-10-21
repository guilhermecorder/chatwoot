require 'rails_helper'

# 🎯 item 352: a linha de indicadores e os parâmetros do agente
RSpec.describe 'Agente de Campanhas — linha e parâmetros' do # rubocop:disable RSpec/DescribeClass
  describe Cevico::CampaignAgent::Row do
    it 'fecha a linha com as taxas das três camadas e a estrela-guia' do
      base = described_class.blank.merge('spend' => 1000, 'impressions' => 50_000, 'reach' => 20_000, 'link_clicks' => 500,
                                         'conversations' => 200, 'plays_3s' => 15_000, 'thruplay' => 6000,
                                         'leads' => 50, 'booked' => 10, 'attended' => 6, 'closed' => 3, 'surgeries' => 2, 'revenue' => 24_000)
      row = described_class.finish(base, goal: 'booked')
      expect(row['rates']).to include('cpl' => 20.0, 'cost_booked' => 100.0, 'cost_surgery' => 500.0, 'roas' => 24.0,
                                      'ctr' => 0.01, 'cpm' => 20.0, 'cpc' => 2.0, 'conv_rate' => 0.4, 'lead_rate' => 0.1,
                                      'hook_rate' => 0.3, 'hold_rate' => 0.4, 'booking_rate' => 0.2, 'attend_rate' => 0.6,
                                      'close_rate' => 0.5, 'surgery_rate' => 0.04)
      expect(row).to include('frequency' => 2.5, 'goal_events' => 10, 'goal_cost' => 100.0)
      expect(described_class.finish(base, goal: 'surgery')).to include('goal_events' => 2, 'goal_cost' => 500.0)
      expect(described_class.snapshot(row).keys).to include('spend', 'goal_cost', 'rates')
    end

    it 'soma linhas e devolve nil onde não dá para calcular' do
      a = described_class.blank.merge('spend' => 10, 'leads' => 1)
      b = described_class.blank.merge('spend' => 5, 'leads' => 0)
      total = described_class.add!(a, b)
      row = described_class.finish(total)
      expect(row).to include('spend' => 15.0, 'leads' => 1)
      expect(row['rates']).to include('cost_booked' => nil, 'ctr' => nil, 'hook_rate' => nil)
    end
  end

  describe Cevico::CampaignAgent::Params do
    let(:account) { create(:account) }

    it 'nasce com os padrões combinados e limpa o que não vale' do
      p = described_class.for(account)
      expect(p).to include('goal' => 'booked', 'autonomy' => 'suggest', 'execute_api' => false, 'window_days' => 7, 'baseline_days' => 30)
      expect(p['budget']).to eq('meta' => 15_000.0, 'google' => 15_000.0)

      saved = described_class.save!(account, { 'goal' => 'surgery', 'budget' => { 'meta' => '20000', 'google' => 'x' }, 'window_days' => 99,
                                               'baseline_days' => 45, 'execute_api' => 'true', 'min' => { 'leads' => 8 }, 'bogus' => 1 })
      expect(saved).to include('goal' => 'surgery', 'window_days' => 30, 'baseline_days' => 30, 'execute_api' => true)
      expect(saved['budget']).to eq('meta' => 20_000.0, 'google' => 15_000.0)
      expect(saved['min']).to include('leads' => 8, 'spend' => 150.0)
      expect(saved).not_to have_key('bogus')
      expect(described_class.goal_label(saved)).to eq('custo por cirurgia')
    end
  end
end
