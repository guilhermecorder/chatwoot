require 'rails_helper'

# 🎯 item 352: a rodada diária inteira com Meta e Google simulados
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe Cevico::CampaignAgent::Daily do
  around { |example| travel_to(ActiveSupport::TimeZone['America/Sao_Paulo'].now.change(hour: 12)) { example.run } }

  let(:account) { create(:account) }

  before do
    create(:user, account: account, role: :administrator)
    CrmSetting.create!(account: account, meta_ads_config: { 'access_token' => 'simulate', 'ad_account_id' => 'act_1' },
                       google_ads_config: { 'service_account_json' => 'simulate' })
    Crm::AdInsightsSyncService.new(account: account, days: 70).call
  end

  it 'lê, recomenda sem repetir, guarda o estado e abre a tarefa' do
    first = described_class.new(account: account).call(force: true)
    expect(first[:ok]).to be(true)
    expect(first[:google]).to include(configured: true)
    expect(Crm::CampaignDay.where(account_id: account.id).count).to be > 300
    expect(first[:new]).to be > 0

    state = described_class.state(account)
    expect(state).to include('new' => first[:new], 'task_opened' => true)
    expect(state.dig('summary', 'all')).to include('window_days' => 7, 'baseline_days' => 30)
    expect(account.tasks.where(task_type: 'gestao').count).to eq(1)

    second = described_class.new(account: account).call
    expect(second).to eq(skipped: 'já rodou hoje')
    forced = described_class.new(account: account).call(force: true)
    expect(forced[:new]).to eq(0)
    expect(Crm::CampaignAction.where(account_id: account.id).count).to eq(first[:new])
  end

  it 'expira sugestão velha e fica desligado quando pedido' do
    Crm::CampaignAction.create!(account: account, channel: 'meta', level: 'adset', ref_id: 'z', rule: 'custo_alto', kind: 'pause',
                                key: 'meta:adset:z:custo_alto', title: 'velha', suggested_on: Date.current - 20)
    described_class.new(account: account).call(force: true)
    expect(Crm::CampaignAction.find_by(ref_id: 'z').status).to eq('expired')

    Cevico::CampaignAgent::Params.save!(account, 'enabled' => false)
    expect(described_class.new(account: account).call(force: true)).to eq(skipped: 'desligado')
  end
end
# rubocop:enable RSpec/MultipleExpectations
