require 'rails_helper'

# 🧲 item 266 (28/09): o ímã do Painel do empresário chega ao Meu Painel —
# grade por área ({id,x,y,w}) e trava, mais a linha de tendência dos gráficos
RSpec.describe 'CRM settings — grade do ímã e tendência do Meu Painel', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/settings/update_agenda" }

  it 'guarda a grade por área, a trava e a tendência — limpando o que não cabe', :aggregate_failures do
    post url,
         params: {
           block_layout: {
             agendamento: {
               top: %w[tarefas radar], main: %w[indicadores desempenho], half: ['desempenho'],
               grid_top: [{ id: 'tarefas', x: 0, y: 0, w: 12 }, { id: 'radar', x: 40, y: -3, w: 99 }, { id: '', x: 0, y: 0, w: 6 }],
               grid_main: [{ id: 'indicadores', x: 0, y: 0, w: 8 }, { id: 'desempenho', x: 8, y: 0, w: 1 }],
               locked: 'true'
             },
             intruso: { top: [], main: [], grid_top: [] }
           },
           kpi_layout: { agendamento: { order: ['leads'], trend: true, judge: false,
                                        grid: [{ id: 'leads', x: 0, y: 0, w: 3, h: 6 }, { id: 'big', x: 9, y: 0, w: 6, h: 99 }, { id: '' }] } }
         },
         headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    cfg = CrmSetting.find_by(account: account).agenda_config

    bl = cfg.dig('block_layout', 'agendamento')
    expect(bl['grid_top']).to eq([{ 'id' => 'tarefas', 'x' => 0, 'y' => 0, 'w' => 12 },
                                  { 'id' => 'radar', 'x' => 0, 'y' => 0, 'w' => 12 }])
    expect(bl['grid_main']).to eq([{ 'id' => 'indicadores', 'x' => 0, 'y' => 0, 'w' => 8 },
                                   { 'id' => 'desempenho', 'x' => 8, 'y' => 0, 'w' => 2 }])
    expect(bl['locked']).to be(true)
    expect(bl['half']).to eq(['desempenho'])
    expect(cfg['block_layout']).not_to have_key('intruso')

    expect(cfg.dig('kpi_layout', 'agendamento', 'trend')).to be(true)
    expect(cfg.dig('kpi_layout', 'agendamento', 'grid')).to eq([{ 'id' => 'leads', 'x' => 0, 'y' => 0, 'w' => 3, 'h' => 6 },
                                                                { 'id' => 'big', 'x' => 6, 'y' => 0, 'w' => 6, 'h' => 80 }])
    expect(cfg.dig('kpi_layout', 'agendamento', 'judge')).to be(false)
  end

  it 'sem grade enviada, a entrada fica só com a ordem antiga (o painel monta a grade)' do
    post url, params: { block_layout: { gestor: { top: ['mentor'], main: ['atalhos'] } } },
              headers: admin.create_new_auth_token, as: :json
    bl = CrmSetting.find_by(account: account).agenda_config.dig('block_layout', 'gestor')
    expect(bl.keys).to contain_exactly('top', 'main', 'half', 'locked')
  end
end
