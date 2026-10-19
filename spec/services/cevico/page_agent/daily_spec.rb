require 'rails_helper'

# 📄 item 353: a rodada diária das páginas — pontos a melhorar viram recomendações, aprendizado e estado
RSpec.describe Cevico::PageAgent::Daily do
  let(:account) { create(:account) }
  let(:today) { Date.new(2026, 10, 19) }
  let!(:page) do
    CevicoPage.create!(account: account, title: 'Refrativa', slug: "refrativa-#{SecureRandom.hex(3)}", status: 'published', meta_title: '')
  end

  before do
    create(:user, account: account, role: :administrator)
    (1..7).each do |i|
      CevicoPageTraffic.create!(account: account, cevico_page: page, date: today - i, source: 'google_ads', views: 20, cta_clicks: 1)
    end
  end

  it 'grava as recomendações sem repetir, guarda o estado e abre a tarefa' do # rubocop:disable RSpec/MultipleExpectations
    first = described_class.new(account: account, today: today).call(force: true)
    expect(first[:ok]).to be(true)
    expect(first[:new]).to be > 0
    actions = Crm::CampaignAction.pages.where(account_id: account.id)
    expect(actions.pluck(:rule)).to include('cta_baixo').or include('seo_titulo')
    expect(actions.first.metrics_before).to include('views' => 140, 'cta' => 7)

    state = described_class.state(account)
    expect(state).to include('new' => first[:new], 'task_opened' => true)
    expect(state.dig('summary', 'views')).to eq(140)
    expect(state.dig('series', 'views').size).to eq(14)
    expect(account.tasks.where(task_type: 'gestao').count).to eq(1)

    again = described_class.new(account: account, today: today).call(force: true)
    expect(again[:new]).to eq(0)
  end

  it 'aprende com a recomendação feita: antes × depois da própria página' do
    action = Crm::CampaignAction.create!(account: account, channel: 'pages', level: 'page', ref_id: page.id.to_s, rule: 'cta_baixo', kind: 'page',
                                         key: "p#{page.id}:cta_baixo", title: 'x', status: 'applied', suggested_on: today - 10,
                                         applied_at: (today - 9).to_time.change(hour: 10), applied_mode: 'manual',
                                         metrics_before: { 'views' => 140, 'cta' => 7, 'leads' => 0, 'click_rate' => 0.05 })
    (1..7).each do |i|
      CevicoPageTraffic.create!(account: account, cevico_page: page, date: today - 8 + i, source: 'direto', views: 30, cta_clicks: 6)
    end
    expect(Cevico::PageAgent::Learning.new(account: account, today: today).call).to eq(1)
    expect(action.reload).to have_attributes(outcome: 'better')
    expect(action.metrics_after).to include('views' => 300, 'click_rate' => 0.14)
    expect(Cevico::CampaignAgent::Learning.scoreboard(account, channels: ['pages']).first).to include(rule: 'cta_baixo', better: 1)
  end
end
