require 'rails_helper'

# 📅 item 200: painel de Agendamentos (marcadas / remarcadas / canceladas no período)
RSpec.describe 'CEVICO Appointments feed', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, name: 'FECHAMENTO') }
  let(:contact) { create(:contact, account: account, name: 'Ana Souza', phone_number: '+5511999990000') }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:tz) { Crm::AgendaSlots::TZ }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/appointments/feed" }

  before do
    contact.update!(label_list: %w[orcamento_catarata consulta_agendada])
    account.tasks.create!(title: 'Consulta: Ana Souza', task_type: 'consulta', unit: 'paulista', creator: admin,
                          contact: contact, phone: contact.phone_number, due_at: tz.now + 3.days,
                          description: "Conversa ##{conversation.display_id} — agendado pela IA")
    account.tasks.create!(title: 'Consulta: Bruno Lima', task_type: 'consulta', unit: 'tatuape', creator: admin,
                          due_at: tz.now + 5.days, rescheduled_count: 1, description: 'marcada pela recepção')
    account.tasks.create!(title: 'Consulta: Carla Dias', task_type: 'consulta', unit: 'paulista', creator: admin,
                          due_at: tz.now + 6.days, canceled_at: Time.current)
    account.tasks.create!(title: 'Ligar para fornecedor', task_type: 'ligacao', creator: admin)
    # 🔪 item 208: cirurgia fica no trilho de cirurgias (track=cirurgias), fora do de consultas
    account.tasks.create!(title: 'Cirurgia: Eva Prado', task_type: 'cirurgia', unit: 'iop', creator: admin,
                          contact: contact, due_at: tz.now + 8.days, description: 'catarata OD')
    # tarefa de revisão do Secretário (sem data) fica fora do painel
    account.tasks.create!(title: '⚠️ Confirmar consulta: Dora', task_type: 'consulta', creator: admin, contact: contact)
  end

  it 'lista o que aconteceu no período com tipo, origem, conversa, caixa, etiquetas e contagens' do # rubocop:disable RSpec/MultipleExpectations
    get base, params: { preset: 'today' }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['mode']).to eq('registradas')
    expect(body['counts']).to include('total' => 3, 'agendada' => 1, 'reagendada' => 1, 'cancelada' => 1, 'ia' => 1, 'equipe' => 2)

    ana = body['rows'].find { |r| r['name'] == 'Ana Souza' }
    expect(ana['kind']).to eq('agendada')
    expect(ana['source']).to eq('ia')
    expect(ana['unit_label']).to eq('Av. Paulista')
    expect(ana['conversation']).to include('display_id' => conversation.display_id, 'inbox_id' => inbox.id, 'inbox_name' => 'FECHAMENTO')
    expect(ana['contact']).to include('id' => contact.id, 'phone' => '+5511999990000')
    expect(ana['contact']['labels']).to include('orcamento_catarata', 'consulta_agendada')
    expect(body['rows'].find { |r| r['name'] == 'Bruno Lima' }['kind']).to eq('reagendada')
    expect(body['rows'].find { |r| r['name'] == 'Carla Dias' }['kind']).to eq('cancelada')
    expect(body['booking']).to include('labels_enabled' => true, 'can_edit' => false)
    expect(body['booking']['labels']).to include('created' => 'consulta_agendada')
  end

  it 'filtra por tipo, caixa e busca por dígitos do telefone; modo consultas usa o dia da consulta' do
    get base, params: { preset: 'today', kind: 'cancelada' }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['rows'].map { |r| r['name'] }).to eq(['Carla Dias'])

    get base, params: { preset: 'today', inbox_id: inbox.id }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['rows'].map { |r| r['name'] }).to eq(['Ana Souza'])

    get base, params: { preset: 'today', q: '9999 0000' }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['rows'].map { |r| r['name'] }).to eq(['Ana Souza'])

    get base, params: { preset: 'today', mode: 'consultas' }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['rows']).to eq([])
    expect(response.parsed_body['booking']['can_edit']).to be(true)
  end

  it 'admin salva os ajustes (etiquetas + colunas) em agenda_config booking' do
    pipeline = Crm::Pipeline.create!(account: account, name: 'CEVICO')
    stage = pipeline.stages.create!(name: 'Agendamento de Consulta', position: 0)
    post "/api/v1/accounts/#{account.id}/crm/settings/update_agenda",
         params: { booking: { labels_enabled: true, stage_id: stage.id, cancel_stage_id: 999_999,
                              labels: { created: 'Consulta Marcada!', rescheduled: 'consulta_reagendada', canceled: 'consulta_cancelada' } } },
         headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    cfg = Crm::BookingSideEffects.config(account)
    expect(cfg['stage_id']).to eq(stage.id)
    expect(cfg['cancel_stage_id']).to be_nil
    expect(cfg['labels']['created']).to eq('consultamarcada')
  end

  # 🔪 item 208 (23/09): chavinha Consultas | Cirurgias no painel
  it 'track=cirurgias lista só as cirurgias (e o padrão só as consultas)', :aggregate_failures do
    get base, params: { preset: 'custom', from: tz.today.to_s, to: (tz.today + 12).to_s, mode: 'consultas' }, headers: agent.create_new_auth_token, as: :json
    names = response.parsed_body['rows'].pluck('name')
    expect(names).to include('Ana Souza')
    expect(names).not_to include('Eva Prado')
    expect(response.parsed_body['track']).to eq('consultas')

    get base, params: { preset: 'custom', from: tz.today.to_s, to: (tz.today + 12).to_s, mode: 'consultas', track: 'cirurgias' },
              headers: agent.create_new_auth_token, as: :json
    rows = response.parsed_body['rows']
    expect(rows.pluck('name')).to eq(['Eva Prado'])
    expect(rows.first).to include('kind' => 'agendada', 'unit' => 'iop')
    expect(rows.first.keys).not_to include('price', 'valor')
    expect(response.parsed_body['track']).to eq('cirurgias')
  end
end
