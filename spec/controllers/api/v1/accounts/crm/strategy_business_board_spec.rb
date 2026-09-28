require 'rails_helper'

# 👑 27/09: Painel do empresário em ambiente próprio — datas, histórico,
# layout do ímã, teia radar e linha do tempo guardados (e limpos) no servidor
RSpec.describe 'CRM strategy — Painel do empresário', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/strategy/save_business_board" }
  let(:board) do
    {
      kanban: { todo: [{ id: 'k1', text: 'Nova campanha', created_at: '2026-09-20T10:00:00Z',
                         history: [{ at: '2026-09-25T10:00:00Z', kind: 'pivot', note: 'mudou para catarata' },
                                   { kind: 'hack', note: 'x' }] }] },
      objectives: ['Dobrar cirurgias', { id: 'o2', text: 'Abrir unidade', status: 'conquistado' }, { text: '' }],
      layout: [{ id: 'radar', x: 40, y: 0, w: 99, h: 1 }, { id: '<script>', x: 0, y: 0, w: 4, h: 5 },
               { id: 'radar', x: 1, y: 1, w: 4, h: 5 }],
      radar: { areas: [{ key: 'marketing', label: 'Marketing' }, { key: 'BAD KEY', label: 'x' }],
               current: { marketing: 7.3, intruso: 3 }, desired: { marketing: 42 },
               snapshots: [{ at: '2026-09-01T00:00:00Z', note: 'antes', current: { marketing: 4 } }] },
      events: [{ kind: 'conquista', card: 'Objetivos do ano', text: 'Abrir unidade' }, { kind: 'invalido', text: 'x' }]
    }
  end

  it 'guarda datas, histórico, layout na grade, teia e linha do tempo — e limpa o lixo', :aggregate_failures do
    post url, params: { business: board }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    saved = CrmSetting.find_by(account: account).agenda_config['business_board']

    item = saved.dig('kanban', 'todo', 0)
    expect(item['created_at']).to start_with('2026-09-20')
    expect(item['history'].map { |h| h['kind'] }).to eq(%w[pivot ajuste])

    expect(saved['objectives'].pluck('text')).to eq(['Dobrar cirurgias', 'Abrir unidade'])
    expect(saved['objectives'].first['created_at']).to be_present
    expect(saved['objectives'].last['status']).to eq('conquistado')

    expect(saved['layout']).to eq([{ 'id' => 'radar', 'x' => 0, 'y' => 0, 'w' => 12, 'h' => 3, 'hidden' => false }])

    expect(saved.dig('radar', 'areas')).to eq([{ 'key' => 'marketing', 'label' => 'Marketing' }])
    expect(saved.dig('radar', 'current')).to eq('marketing' => 7.5)
    expect(saved.dig('radar', 'desired')).to eq('marketing' => 10.0)
    expect(saved.dig('radar', 'snapshots', 0, 'note')).to eq('antes')

    expect(saved['events'].map { |e| e['kind'] }).to eq(['conquista'])
  end

  it 'atendente não salva o quadro do dono' do
    post url, params: { business: board }, headers: agent_user.create_new_auth_token, as: :json
    expect(response.status).to be_in([401, 403])
  end
end
