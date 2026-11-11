require 'rails_helper'

# 11/11: o mesmo nome de anúncio em dois conjuntos — o lead da página tem de cair
# no anúncio que estava no ar no dia do clique, não num conjunto pausado qualquer.
RSpec.describe Cevico::CampaignAgent::Reader do
  let(:account) { create(:account) }
  let(:name) { 'Corrigir miopia v4 · página' }
  let(:old_ad) { '120250552493670611' } # conjunto antigo, pausado
  let(:new_ad) { '120250570071030611' } # conjunto no ar

  before do
    creative(old_ad, 'conjunto-30', 'ADSET_PAUSED')
    creative(new_ad, 'conjunto-36', 'ACTIVE')
    spend(old_ad, '2026-10-20', 11.15)
    spend(new_ad, '2026-11-05', 30)
    spend(new_ad, '2026-11-06', 31)
    allow(Crm::AdFunnelSteps).to receive(:new).and_return(instance_double(Crm::AdFunnelSteps))
    allow(Crm::AdFunnel).to receive(:funnel_row) { |ids, _steps| { 'leads' => ids.size } }
  end

  def creative(ad_id, adset, status, ad_name: name)
    Crm::AdCreative.create!(account: account, ad_id: ad_id, ad_name: ad_name, adset_id: adset, adset_name: adset, campaign_id: 'c1',
                            campaign_name: 'Site', effective_status: status, format: 'video', synced_at: Time.current)
  end

  def spend(ad_id, date, value)
    Crm::AdInsight.create!(account: account, ad_id: ad_id, date: Date.parse(date), metrics: { 'spend' => value })
  end

  def lead(captured_at, content: name)
    create(:contact, account: account, additional_attributes: {
             'page_ads' => { 'source' => 'meta_ads', 'campaign' => 'refrativa-pagina', 'utm_content' => content, 'captured_at' => captured_at }
           })
  end

  def leads_by_ad
    reader = described_class.new(account: account, since_date: Date.new(2026, 10, 1), until_date: Date.new(2026, 11, 30), channels: %w[meta])
    reader.send(:meta_page_funnels)[:ad].transform_values { |row| row['leads'] }
  end

  it 'credita o lead ao anúncio que gastou no dia do clique' do
    lead('2026-11-06T15:00:00Z')

    expect(leads_by_ad).to eq(new_ad => 1)
  end

  it 'conta o dia pelo horário de Brasília' do
    lead('2026-11-07T01:30:00Z') # 22h30 do dia 06 em São Paulo

    expect(leads_by_ad).to eq(new_ad => 1)
  end

  it 'sem gasto no dia, vai para quem gastou por último até ali' do
    lead('2026-11-09T15:00:00Z')
    lead('2026-10-25T15:00:00Z')

    expect(leads_by_ad).to eq(new_ad => 1, old_ad => 1)
  end

  it 'sem gasto nenhum registrado, fica com o anúncio mais novo' do
    Crm::AdInsight.where(account: account).delete_all
    lead('2026-11-06T15:00:00Z')

    expect(leads_by_ad).to eq(new_ad => 1)
  end

  it 'não muda nome único nem o utm_content que já traz o código do anúncio' do
    creative('120250000000000001', 'conjunto-35', 'ACTIVE', ad_name: 'Gustavo 2 · página')
    lead('2026-11-06T15:00:00Z', content: 'Gustavo 2 · página')
    lead('2026-11-06T15:00:00Z', content: '120250999999999999')

    expect(leads_by_ad).to eq('120250000000000001' => 1, '120250999999999999' => 1)
  end
end
