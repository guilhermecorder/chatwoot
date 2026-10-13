require 'rails_helper'

# 🔁 Auditoria 10/2026 (#2/#133): no Painel de Agendamentos, "reagendada" vale
# pelo carimbo da remarcação — qualquer outro toque na consulta (✓ compareceu,
# médico, Lixeira) não vira remarcação no dia do toque; e quem confirmou
# DEPOIS de remarcar aparece como confirmada.
RSpec.describe 'CEVICO Appointments feed — remarcação com carimbo', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:tz) { Crm::AgendaSlots::TZ }
  let(:feed) { "/api/v1/accounts/#{account.id}/crm/appointments/feed" }

  def consulta(name, due_at, created_at: 40.days.ago)
    account.tasks.create!(title: "Consulta: #{name}", task_type: 'consulta', unit: 'paulista', creator: admin,
                          due_at: due_at, created_at: created_at, updated_at: created_at)
  end

  def kinds_for(name, params)
    get feed, params: params, headers: agent.create_new_auth_token, as: :json
    response.parsed_body['rows'].select { |r| r['name'] == name }.map { |r| r['kind'] }
  end

  it 'remarcada há semanas e tocada hoje (compareceu) NÃO aparece como reagendada hoje', :aggregate_failures do
    task = consulta('Bruno Lima', 1.day.ago)
    travel_to(35.days.ago) { task.update!(due_at: 1.day.ago, rescheduled_count: 1) }
    # hoje a equipe marca ✓ compareceu na conferência do dia (mexe no updated_at)
    put "/api/v1/accounts/#{account.id}/tasks/#{task.id}", params: { attendance: 'attended' },
                                                           headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)

    expect(kinds_for('Bruno Lima', { preset: 'today' })).to eq([])
    get feed, params: { preset: 'today' }, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['counts']['reagendada']).to eq(0)
  end

  it 'remarcar pela Agenda hoje aparece como reagendada hoje, com o horário da remarcação', :aggregate_failures do
    task = consulta('Carla Dias', tz.now + 2.days)
    put "/api/v1/accounts/#{account.id}/tasks/#{task.id}", params: { due_at: (tz.now + 5.days).iso8601 },
                                                           headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(task.reload.rescheduled_count).to eq(1)
    expect(task.comments.last).to include('kind' => 'rescheduled', 'by' => admin.id)

    get feed, params: { preset: 'today' }, headers: agent.create_new_auth_token, as: :json
    row = response.parsed_body['rows'].find { |r| r['name'] == 'Carla Dias' }
    expect(row['kind']).to eq('reagendada')
    expect(Time.zone.parse(row['event_at'])).to be_within(2.seconds).of(task.rescheduled_at)
  end

  it 'confirmada DEPOIS da remarcação vence no modo consultas; remarcada sem resposta segue reagendada', :aggregate_failures do
    tomorrow = tz.now + 1.day
    confirmed = consulta('Iara Luz', tomorrow)
    travel_to(3.days.ago) { confirmed.update!(due_at: tomorrow + 1.hour, rescheduled_count: 1) }
    confirmed.update!(confirmed_at: Time.current)
    pending = consulta('Hugo Neri', tomorrow)
    travel_to(3.days.ago) { pending.update!(due_at: tomorrow + 2.hours, rescheduled_count: 1) }

    range = { preset: 'custom', from: tz.today.to_s, to: (tz.today + 3).to_s, mode: 'consultas' }
    expect(kinds_for('Iara Luz', range)).to eq(['confirmada'])
    expect(kinds_for('Hugo Neri', range)).to eq(['reagendada'])
  end
end
