require 'rails_helper'

# 🔒 item 366 (23/10): "as meninas precisam poder fazer isso ou aquilo na agenda".
# O cadeado de UM horário e o "fechar médico" gravavam pelo update_agenda (nó
# "Horários e regras", desligado para a equipe): o botão aparecia e o salvar
# dava erro. Agora têm porta própria, guardada pelo nó "Fechar e reabrir dias".
RSpec.describe 'Agenda — fechar/reabrir horário e médico pela equipe', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/settings" }

  # lê do banco a cada chamada (sem memo): o teste confere o que ficou gravado
  def cfg = CrmSetting.find_by(account: account).agenda_config

  before { CrmSetting.create!(account: account, agenda_config: { 'blocked_days' => ['2026-12-25'], 'windows' => [{ 'dow' => 1 }] }) }

  it 'atendente sem concessão fecha um horário e um médico — e o resto da agenda fica como estava', :aggregate_failures do
    post "#{base}/update_agenda_locks",
         params: { blocked: [{ date: '2026-10-27', time: '14:00', unit: 'tatuape', doctor: 'Dr. Gustavo Bittar' },
                             { date: 'x', time: '14:00' }, { date: '2026-10-27', time: 'meio-dia' }],
                   closed_doctors: ['Dr. Henrique Gemelli', ''] },
         headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(cfg['blocked']).to eq([{ 'date' => '2026-10-27', 'time' => '14:00', 'unit' => 'tatuape', 'doctor' => 'Dr. Gustavo Bittar' }])
    expect(cfg['closed_doctors']).to eq(['Dr. Henrique Gemelli'])
    expect(cfg['blocked_days']).to eq(['2026-12-25'])
    expect(cfg['windows']).to eq([{ 'dow' => 1 }])
  end

  it 'reabrir = mandar a lista sem o item; mandar só um campo não apaga o outro', :aggregate_failures do
    CrmSetting.find_by(account: account).update!(agenda_config: cfg.merge('blocked' => [{ 'date' => '2026-10-27', 'time' => '14:00' }],
                                                                          'closed_doctors' => ['Dr. Henrique Gemelli']))
    post "#{base}/update_agenda_locks", params: { blocked: [] }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(cfg['blocked']).to eq([])
    expect(cfg['closed_doctors']).to eq(['Dr. Henrique Gemelli'])
  end

  it 'quem teve "Fechar e reabrir dias" tirado leva 403 aqui e no fechar dia', :aggregate_failures do
    CrmSetting.find_by(account: account).update!(agent_permissions: { 'tree' => { agent.id.to_s => { 'agenda.bloqueios' => 'none' } } })
    post "#{base}/update_agenda_locks", params: { closed_doctors: ['Dr. Henrique Gemelli'] }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    post "#{base}/update_blocked_days", params: { blocked_days: ['2026-10-28'] }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(cfg['closed_doctors']).to be_nil
    expect(cfg['blocked_days']).to eq(['2026-12-25'])
  end

  it 'faixas, valores e regras seguem só com "Horários e regras" (update_agenda continua fechado à equipe)' do
    post "#{base}/update_agenda", params: { blocked: [{ date: '2026-10-27', time: '14:00' }] }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
