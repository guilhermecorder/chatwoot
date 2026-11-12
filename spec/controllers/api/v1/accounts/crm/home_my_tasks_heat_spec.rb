require 'rails_helper'

# 🌡️ 11/11/2026 (LIFE): as tarefas do Meu Painel saem em ordem de TEMPERATURA fora da clínica;
# na clínica a lista continua como sempre (sem os campos novos, na ordem antiga).
RSpec.describe 'Meu Painel: tarefas por temperatura', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Fernando') }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/home" }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Life', position: 0) }
  let(:novos) { pipeline.stages.create!(name: 'Novos Contatos', color: '#000', position: 0) }
  let(:enviado) { pipeline.stages.create!(name: 'Orçamento Enviado', color: '#000', position: 3) }

  before do
    Rails.cache.clear
    Current.reset
    novos
  end

  def my_tasks
    get base, params: { preset: 'today' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    response.parsed_body['my_tasks']
  end

  def task_for(name, due_at:, stage: nil, value: nil)
    contact = create(:contact, account: account, name: name)
    Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage, value: value, stage_moved_at: 1.day.ago) if stage
    account.tasks.create!(title: "⏰ #{name} — Enviar o orçamento", creator: admin, assignee: admin, contact: contact,
                          task_type: 'pos_op', priority: :high, status: :todo, due_at: due_at)
  end

  it 'fora da clínica: cliente, etapa, valor e temperatura, com a mais quente em cima', :aggregate_failures do
    Cevico::Company.save!(account, name: 'Life Energia Solar', segment: 'outro')
    task_for('Fria da Silva', due_at: 3.days.from_now)
    task_for('Quente de Souza', due_at: 2.hours.ago, stage: enviado, value: 24_800)

    body = my_tasks

    expect(body['by_heat']).to be(true)
    expect(body['count']).to eq(2)
    expect(body['items'].map { |i| i.dig('contact', 'name') }).to eq(['Quente de Souza', 'Fria da Silva'])
    quente = body['items'].first
    expect(quente.dig('card', 'stage', 'name')).to eq('Orçamento Enviado')
    expect(quente.dig('card', 'value')).to eq(24_800.0)
    expect(quente['heat']).to include('level' => 'morna', 'points' => 4)
    expect(body['items'].last['heat']).to include('level' => 'fria', 'points' => 0)
  end

  it 'na clínica nada muda: mesma ordem de antes e nenhum campo novo', :aggregate_failures do
    task_for('Paciente A', due_at: 3.days.from_now)
    task_for('Paciente B', due_at: 2.hours.ago, stage: enviado)

    body = my_tasks

    expect(body['by_heat']).to be(false)
    expect(body['items'].pluck('title')).to eq(['⏰ Paciente B — Enviar o orçamento', '⏰ Paciente A — Enviar o orçamento'])
    expect(body['items'].first.keys).to contain_exactly('id', 'title', 'priority', 'status', 'due_at', 'creator_name', 'comments_count')
  end
end
