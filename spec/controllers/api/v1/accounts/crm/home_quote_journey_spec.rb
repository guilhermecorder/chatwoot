require 'rails_helper'

# 🧭 12/11/2026 (LIFE): a faixa "Jornada do orçamento" do Meu Painel pede só o pedaço dela.
RSpec.describe 'Meu Painel: jornada do orçamento', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }

  before do
    Rails.cache.clear
    Current.reset
    Crm::Pipeline.create!(account: account, name: 'Life', position: 0).stages.create!(name: 'Novos Contatos', color: '#000', position: 0)
  end

  it 'devolve as 10 etapas da energia solar, os saltos e as fontes no período pedido', :aggregate_failures do
    contact = create(:contact, account: account, name: 'Ivan Coral', created_at: 2.days.ago)
    create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 2.days.ago).add_labels(['origem-site'])

    get "/api/v1/accounts/#{account.id}/crm/home", params: { only: 'quote_journey', preset: 'last7' }, headers: admin.create_new_auth_token,
                                                   as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body.keys).to eq(['quote_journey'])
    journey = body['quote_journey']
    expect(journey['steps'].pluck('key')).to eq(%w[leads sondagem conta enviado investimento pagamento credito proposta fechado instalado])
    expect(journey['steps'].first['count']).to eq(1)
    expect(journey['jumps'].pluck('to')).to eq(%w[enviado fechado])
    expect(journey['sources'].pluck('key')).to eq(['site'])
  end

  it 'a régua normal do período vale: quem chegou há 2 dias não aparece em "hoje" nem em "ontem"', :aggregate_failures do
    contact = create(:contact, account: account, name: 'Ivan Coral', created_at: 2.days.ago)
    create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 2.days.ago)

    counts = %w[today yesterday last7].map do |preset|
      get "/api/v1/accounts/#{account.id}/crm/home", params: { only: 'quote_journey', preset: preset }, headers: admin.create_new_auth_token,
                                                     as: :json
      response.parsed_body.dig('quote_journey', 'steps', 0, 'count')
    end

    expect(counts).to eq([0, 0, 1])
  end
end
