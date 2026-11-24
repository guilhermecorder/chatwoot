require 'rails_helper'

# 💸 item 413: o gasto do Meta repartido pelas caixas. Antes cada caixa marcada
# "puxar do Meta" levava a conta inteira (o mesmo dinheiro em três caixas).
RSpec.describe Crm::MetaSpendByInbox do
  let(:account) { create(:account) }
  let(:insta) { create(:inbox, account: account, name: 'INSTAGRAM') }
  let(:insta2) { create(:inbox, account: account, name: 'INSTAGRAM 2') }
  let(:now) { ActiveSupport::TimeZone['America/Sao_Paulo'].now.change(hour: 12) }
  let(:since) { (now - 6.days).beginning_of_day }
  let(:until_at) { now.end_of_day }

  def ad(id, adset:, campaign:)
    Crm::AdCreative.create!(account: account, ad_id: id, adset_id: adset, campaign_id: campaign, campaign_name: "Campanha #{campaign}")
  end

  def spend(ad_id, value, day = now.to_date)
    Crm::AdInsight.create!(account: account, ad_id: ad_id, date: day, metrics: { 'spend' => value })
  end

  def talk(inbox, ad_id, count = 1, at: now)
    create_list(:conversation, count, account: account, inbox: inbox, created_at: at,
                                      additional_attributes: { 'meta_ads' => { 'source_id' => ad_id } })
  end

  def split(total: nil)
    described_class.new(account: account, since: since, until_at: until_at, total: total).call
  end

  it 'manda o gasto de cada anúncio para a caixa onde ele abriu conversa', :aggregate_failures do
    ad('A1', adset: 'S1', campaign: 'C1')
    ad('A2', adset: 'S2', campaign: 'C2')
    spend('A1', 100)
    spend('A2', 60)
    talk(insta, 'A1', 3)
    talk(insta2, 'A1', 1)
    talk(insta2, 'A2', 2)

    result = split

    expect(result[:by_inbox]).to eq(insta.id => 75.0, insta2.id => 85.0)
    expect(result).to include(unassigned: 0.0, total: 160.0, method: 'anuncio', ads: 2)
  end

  it 'anúncio sem conversa herda a proporção do conjunto e, depois, da campanha', :aggregate_failures do
    ad('A1', adset: 'S1', campaign: 'C1')
    ad('A2', adset: 'S1', campaign: 'C1') # irmão de conjunto, sem conversa
    ad('A3', adset: 'S9', campaign: 'C1') # só a campanha em comum
    spend('A1', 10)
    spend('A2', 20)
    spend('A3', 30)
    talk(insta, 'A1', 1)

    expect(split[:by_inbox]).to eq(insta.id => 60.0)
  end

  it 'deixa em "sem caixa" a campanha que não abriu conversa nenhuma (site)', :aggregate_failures do
    ad('A1', adset: 'S1', campaign: 'C1')
    ad('SITE', adset: 'S7', campaign: 'C7')
    spend('A1', 40)
    spend('SITE', 60)
    talk(insta, 'A1', 2)

    result = split

    expect(result[:by_inbox]).to eq(insta.id => 40.0)
    expect(result[:unassigned]).to eq(60.0)
  end

  it 'estica as fatias para fechar com o gasto oficial da conta', :aggregate_failures do
    ad('A1', adset: 'S1', campaign: 'C1')
    spend('A1', 100)
    talk(insta, 'A1', 1)
    talk(insta2, 'A1', 1)

    result = split(total: 120)

    expect(result[:by_inbox]).to eq(insta.id => 60.0, insta2.id => 60.0)
    expect(result[:total]).to eq(120.0)
  end

  it 'sem número por anúncio (o dia ainda não sincronizou), divide pela proporção das conversas', :aggregate_failures do
    talk(insta, 'A1', 3)
    talk(insta2, 'A2', 1)

    result = split(total: 200)

    expect(result[:by_inbox]).to eq(insta.id => 150.0, insta2.id => 50.0)
    expect(result[:method]).to eq('conversas')
  end

  it 'não conta conversa de fora do período, de teste nem sem anúncio', :aggregate_failures do
    simulator = create(:inbox, account: account, name: Crm::AgentSimulator::INBOX_NAME)
    ad('A1', adset: 'S1', campaign: 'C1')
    spend('A1', 50)
    talk(insta, 'A1', 1)
    talk(insta2, 'A1', 5, at: now - 20.days)
    talk(simulator, 'A1', 5)
    create(:conversation, account: account, inbox: insta2, created_at: now)

    expect(split[:by_inbox]).to eq(insta.id => 50.0)
  end

  it 'sem gasto e sem conversa, não inventa nada' do
    expect(split).to include(by_inbox: {}, unassigned: 0.0, total: 0.0, method: 'nenhum')
  end
end
