require 'rails_helper'

# 📅 item 375 (28/10): a equipe abre um dia/turno a mais pela mesma porta do fechar dia
RSpec.describe 'Agenda — abertura pontual pela equipe', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/settings" }

  def cfg = CrmSetting.find_by(account: account).agenda_config
  def one_opening = { date: '2026-10-30', doctor: 'Dra. R', unit: 'tatuape', start: '13:00', end: '17:30' }

  before { CrmSetting.create!(account: account, agenda_config: { 'blocked_days' => ['2026-12-25'], 'windows' => [{ 'dow' => 1 }] }) }

  it 'grava só as aberturas válidas e não mexe no resto', :aggregate_failures do
    post "#{base}/update_blocked_days",
         params: { open_days: [
           { date: '2026-10-30', doctor: 'Dra. Roberta Negri', unit: 'tatuape', start: '13:00', end: '17:30', block: 10 },
           { date: '2026-10-30', doctor: 'Dra. Roberta Negri', unit: 'tatuape', start: '13:00', end: '17:30', block: 10 }, # repetida
           { date: '2026-11-06', doctor: 'Dra. Roberta Negri', unit: 'paulista', start: '09:00', end: '13:30', block: 999 },
           { date: '30/10', doctor: 'Dra. Roberta Negri', unit: 'tatuape', start: '13:00', end: '17:30' },
           { date: '2026-11-07', doctor: '', unit: 'tatuape', start: '13:00', end: '17:30' },
           { date: '2026-11-08', doctor: 'Dr. A', unit: 'tatuape', start: '17:00', end: '13:00' }
         ] },
         headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(cfg['open_days']).to eq([
                                     { 'date' => '2026-10-30', 'doctor' => 'Dra. Roberta Negri', 'unit' => 'tatuape',
                                       'start' => '13:00', 'end' => '17:30', 'block' => 10 },
                                     { 'date' => '2026-11-06', 'doctor' => 'Dra. Roberta Negri', 'unit' => 'paulista',
                                       'start' => '09:00', 'end' => '13:30', 'block' => 15 }
                                   ])
    expect(cfg['blocked_days']).to eq(['2026-12-25'])
    expect(cfg['windows']).to eq([{ 'dow' => 1 }])
    expect(response.parsed_body['agenda_open_days'].size).to eq(2)
  end

  it 'mandar só os dias fechados não apaga as aberturas (e vice-versa)', :aggregate_failures do
    post "#{base}/update_blocked_days", params: { open_days: [one_opening] }, headers: agent.create_new_auth_token, as: :json
    post "#{base}/update_blocked_days", params: { blocked_days: ['2026-12-24'] }, headers: agent.create_new_auth_token, as: :json
    expect(cfg['blocked_days']).to eq(['2026-12-24'])
    expect(cfg['open_days'].size).to eq(1)
    post "#{base}/update_blocked_days", params: { open_days: [] }, headers: agent.create_new_auth_token, as: :json
    expect(cfg['open_days']).to eq([])
    expect(cfg['blocked_days']).to eq(['2026-12-24'])
  end

  it 'a leitura das configurações devolve agenda_open_days' do
    post "#{base}/update_blocked_days", params: { open_days: [one_opening] }, headers: agent.create_new_auth_token, as: :json
    get base, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['agenda_open_days'].first['date']).to eq('2026-10-30')
  end
end
