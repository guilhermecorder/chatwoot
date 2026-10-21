require 'rails_helper'

# 21/10: a lista de anúncios da Meta derrubava a carga inteira quando UM
# criativo Advantage+ falhava na validação (código 100/2446211) — de 14 a 21/10
# o agente de campanhas ficou sem gasto da Meta. Agora a lista cai para campos
# leves e, no pior caso, só avisa: os números continuam chegando.
RSpec.describe Crm::AdInsightsSyncService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account, days: 3) }
  let(:erro) { 'ads: Invalid parameter — graus de liberdade (código 100/2446211)' }

  before do
    CrmSetting.find_or_create_by!(account: account).update!(meta_ads_config: { 'access_token' => 'x', 'ad_account_id' => '1' })
  end

  def stub_ads(&)
    allow_any_instance_of(Crm::MetaGraph).to receive(:fetch_all, &) # rubocop:disable RSpec/AnyInstance
  end

  it 'usa os campos completos quando a Meta aceita' do
    stub_ads { |_g, _edge, query, **| query[:fields] == described_class::AD_FIELDS ? [{ 'id' => '1', 'name' => 'A' }] : raise('não deveria') }

    expect(service.send(:fetch_ads)).to eq([[{ 'id' => '1', 'name' => 'A' }], false])
  end

  it 'cai para os campos leves quando os completos são recusados e deixa um aviso', :aggregate_failures do
    stub_ads do |_g, _edge, query, **|
      raise Crm::MetaGraph::Error, erro if query[:fields] == described_class::AD_FIELDS

      [{ 'id' => '1', 'name' => 'A' }]
    end

    expect(service.send(:fetch_ads)).to eq([[{ 'id' => '1', 'name' => 'A' }], true])
    expect(described_class.state(account)['last_warning']).to include('campos leves', '2446211')
  end

  it 'se a Meta recusa tudo, avisa e devolve nil — os números seguem', :aggregate_failures do
    stub_ads { |_g, _edge, _query, **| raise Crm::MetaGraph::Error, erro }

    expect(service.send(:fetch_ads)).to eq([nil, false])
    expect(described_class.state(account)['last_warning']).to include('sem atualizar a lista de criativos')
    expect(service.send(:sync_creatives)).to eq(0)
  end

  it 'com campos leves preserva o que já estava guardado do criativo (texto da página, link)' do
    Crm::AdCreative.create!(account: account, ad_id: '1', ad_name: 'A', effective_status: 'ACTIVE', format: 'video',
                            creative: { 'link' => 'https://clinica.cevico.com.br/x', 'title' => 'velho', 'transcript' => 'fala' },
                            synced_at: Time.current)
    rows = [{ account_id: account.id, ad_id: '1', creative: { 'title' => 'novo', 'body' => nil } }]

    service.send(:keep_transcripts!, rows, keep_all: true)

    expect(rows.first[:creative]).to eq('link' => 'https://clinica.cevico.com.br/x', 'title' => 'novo', 'transcript' => 'fala')
  end
end
