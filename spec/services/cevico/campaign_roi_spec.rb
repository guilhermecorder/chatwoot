require 'rails_helper'

# 18/10: custo do Google × resultado por campanha, mesmo quando duas campanhas
# mandam para a mesma página
RSpec.describe Cevico::CampaignRoi do
  let(:account) { create(:account) }
  let(:since_date) { Date.new(2026, 10, 1) }
  let(:until_date) { Date.new(2026, 10, 18) }
  let(:report) { Struct.new(:rows, :since_date, :until_date).new(rows, since_date, until_date) }

  let(:rows) do
    [
      { title: 'Refrativa', campaigns: {
        'refrativa-search' => bucket(views: 400, cta: 40, leads: 20, booked: 8, conversions: 2, revenue: 12_000.0),
        'refrativa-gd' => bucket(views: 900, cta: 30, leads: 10, booked: 2)
      } },
      { title: 'Refrativa GD', campaigns: { 'refrativa-gd' => bucket(views: 100, cta: 10, leads: 5, booked: 1) } },
      { title: 'Miopia', campaigns: { 'c2-cenas' => bucket(views: 50, cta: 5, leads: 3) } }
    ]
  end

  let(:costs) do
    { configured: true, campaigns: [
      { id: '111', name: '[Search] Refrativa SP', cost: 2000.0, clicks: 500 },
      { id: '222', name: 'Refrativa GD', cost: 1500.0, clicks: 2000 },
      { id: '333', name: 'Catarata Search', cost: 700.0, clicks: 90 }
    ] }
  end

  def bucket(numbers)
    { views: 0, cta: 0, leads: 0, booked: 0, conversions: 0, revenue: 0.0 }.merge(numbers)
  end

  def click(campaign, utm_id)
    CevicoPageRef.create!(account: account, token: SecureRandom.alphanumeric(5).upcase,
                          source_data: { 'campaign' => campaign, 'utm_id' => utm_id }, created_at: Time.zone.parse('2026-10-10 10:00'))
  end

  it 'joins each campaign to its Google cost by the campaign ID the click carried' do
    click('refrativa-search', '111')
    click('refrativa-search', '111')
    click('refrativa-gd', '222')

    result = described_class.new(account: account, report: report, costs: costs).call
    search = result[:campaigns].find { |c| c[:name] == 'refrativa-search' }
    gd = result[:campaigns].find { |c| c[:name] == 'refrativa-gd' }

    expect(search).to include(cost: 2000.0, matched_by: 'id', leads: 20, booked: 8, cpl: 100.0, cost_per_booked: 250.0, roas: 6.0)
    expect(search[:roi]).to eq(500.0)
    # a GD soma as duas páginas (a /refrativa e a gêmea /refrativa-gd)
    expect(gd).to include(cost: 1500.0, leads: 15, booked: 3, cpl: 100.0, cost_per_booked: 500.0)
    expect(gd[:pages]).to contain_exactly('Refrativa', 'Refrativa GD')
  end

  it 'falls back to the campaign name and shows Google spend that no tracked campaign claimed' do
    result = described_class.new(account: account, report: report, costs: costs).call

    gd = result[:campaigns].find { |c| c[:name] == 'refrativa-gd' }
    expect(gd).to include(cost: 1500.0, matched_by: 'nome')
    expect(result[:campaigns].find { |c| c[:name] == 'refrativa-search' }[:cost]).to be_nil
    expect(result[:untracked].pluck(:id)).to contain_exactly('111', '333')
    expect(result[:totals]).to include(cost: 1500.0, untracked_cost: 2700.0)
  end

  it 'never counts the same Google campaign twice' do
    click('refrativa-search', '111')
    click('refrativa-gd', '111')

    result = described_class.new(account: account, report: report, costs: costs).call
    with_cost = result[:campaigns].select { |c| c[:campaign_id] == '111' }

    expect(with_cost.size).to eq(1)
  end

  it 'keeps the results without cost when Google is not connected' do
    result = described_class.new(account: account, report: report, costs: { configured: false }).call

    expect(result[:configured]).to be(false)
    expect(result[:campaigns].size).to eq(3)
    expect(result[:campaigns].map { |c| c[:cost] }.uniq).to eq([nil])
  end
end
