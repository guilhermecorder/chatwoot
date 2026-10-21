require 'rails_helper'

# 🧠 Follow-up inteligente (item 339): o PUT da config grava pelo gravador único
# (Cevico::SettingMerge, Rodada 6) — só a chave followup_smart, sem apagar o que
# as outras telas guardam no agenda_config.
RSpec.describe 'Follow-up inteligente — gravar a config', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/followup_bots/smart" }

  it 'grava pelo Cevico::SettingMerge, mantém as outras chaves e o que não veio no pedido', :aggregate_failures do
    CrmSetting.create!(account: account, agenda_config: {
                         'followup_stop_labels' => ['att_encerrado'],
                         'followup_smart' => { 'lead_frio' => false, 'reativacao' => { 'ativa' => true, 'dias' => 10 } }
                       })
    expect(Cevico::SettingMerge).to receive(:merge!).with(account, :agenda_config).and_call_original

    put url, params: { followup_smart: { leitura: false, reativacao: { dias: 99 } } }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    cfg = CrmSetting.find_by!(account: account).agenda_config
    expect(cfg['followup_stop_labels']).to eq(['att_encerrado'])
    expect(cfg['followup_smart']).to include('leitura' => false, 'lead_frio' => false)
    expect(cfg['followup_smart']['reativacao']).to eq('ativa' => true, 'dias' => 60)
    expect(response.parsed_body).to include('leitura' => false, 'lead_frio' => false, 'fim_de_semana' => true)
  end

  it 'funciona numa conta sem CrmSetting (cria a linha)' do
    put url, params: { followup_smart: { fim_de_semana: false } }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(CrmSetting.find_by!(account: account).agenda_config['followup_smart']).to eq('fim_de_semana' => false)
  end
end
