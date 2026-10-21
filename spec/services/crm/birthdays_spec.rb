require 'rails_helper'

# 🎂 item 331 (06/10): aniversários da equipe — cada um informa o seu, o Meu
# Painel avisa o aniversariante do dia e lista os do mês.
RSpec.describe Crm::Birthdays, type: :request do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account, name: 'Ana', role: :administrator) }
  let(:bia) { create(:user, account: account, name: 'Bia') }
  let(:caio) { create(:user, account: account, name: 'Caio') }
  let(:service) { described_class.new(account) }
  let(:today) { described_class::TZ.today }

  before { [ana, bia, caio] }

  it 'grava dia e mês (ano opcional), lista o dia e o mês e sabe quem falta', :aggregate_failures do
    service.set!(ana.id, day: today.day, month: today.month, year: today.year - 30)
    service.set!(bia.id, day: today.day == 1 ? 2 : 1, month: today.month)

    payload = service.payload(caio, admin: true)
    expect(payload[:mine]).to be_nil
    expect(payload[:today].map { |e| e[:name] }).to eq(['Ana'])
    expect(payload[:today].first[:age]).to eq(30)
    expect(payload[:month].map { |e| e[:name] }).to contain_exactly('Ana', 'Bia')
    expect(payload[:missing]).to eq(['Caio'])
    expect(service.payload(caio)[:missing]).to eq(1)
    expect(service.payload(ana)[:mine]).to include('day' => today.day, 'month' => today.month)

    service.clear!(ana.id)
    expect(service.payload(caio, admin: true)[:missing]).to contain_exactly('Ana', 'Caio')
  end

  it 'recusa data que não existe e ano fora do razoável' do
    expect { service.set!(ana.id, day: 31, month: 2) }.to raise_error(Date::Error)
    expect { service.set!(ana.id, day: 29, month: 2) }.not_to raise_error # sem ano, 29/02 vale
    expect { service.set!(ana.id, day: 1, month: 1, year: 1800) }.to raise_error(ArgumentError)
  end

  it 'pela API: a pessoa grava o próprio; admin grava por alguém; data inválida avisa', :aggregate_failures do
    base = "/api/v1/accounts/#{account.id}/crm/home/birthday"
    post base, params: { day: 6, month: 10 }, headers: bia.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['birthdays']['mine']).to include('day' => 6, 'month' => 10)

    post base, params: { day: 7, month: 10, user_id: caio.id }, headers: bia.create_new_auth_token, as: :json
    expect(described_class.new(account).payload(caio)[:mine]).to be_nil # atendente não grava por outro: gravou o dela de novo
    post base, params: { day: 7, month: 10, user_id: caio.id }, headers: ana.create_new_auth_token, as: :json
    expect(described_class.new(account).payload(caio)[:mine]).to include('day' => 7)

    post base, params: { day: 31, month: 2 }, headers: bia.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    get "/api/v1/accounts/#{account.id}/crm/home", params: { preset: 'today' }, headers: ana.create_new_auth_token, as: :json
    expect(response.parsed_body['birthdays']['month'].map { |e| e['name'] }).to include('Bia', 'Caio') if today.month == 10
    expect(response.parsed_body['birthdays']).to include('missing')
  end
end
