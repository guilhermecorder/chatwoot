require 'rails_helper'

# 🎨 item 387 (04/11, "está tudo travado no strawberry"): a escolha "para todo
# mundo" das telas novas era jogada fora porque o servidor só aceitava uma
# lista fixa de telas. Agora vale qualquer tela com nome seguro, '*' = todas
# as telas, e o modo 'random' (aleatória).
RSpec.describe 'CRM settings — paletas por tela', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/settings/update_agenda" }

  def save(palettes)
    post url, params: { panel_palettes: palettes }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    CrmSetting.find_by(account: account).agenda_config['panel_palettes'] || {}
  end

  it 'guarda telas novas, "todas as telas" e o modo aleatório; nome estranho cai fora', :aggregate_failures do
    saved = save('report:segmentacao' => { mode: 'fixed', key: 'lime' },
                 '*' => { mode: 'random' },
                 'crm:sources' => { mode: 'salad' },
                 '<script>' => { mode: 'fixed', key: 'lime' },
                 'report:x' => { mode: 'fixed', key: 'roxo-inventado' })
    expect(saved['report:segmentacao']).to eq('mode' => 'fixed', 'key' => 'lime', 'blocks' => {})
    expect(saved['*']).to eq('mode' => 'random', 'key' => '', 'blocks' => {})
    expect(saved['crm:sources']).to include('mode' => 'salad')
    expect(saved).not_to have_key('<script>')
    expect(saved).not_to have_key('report:x') # fixo sem paleta válida = cor do dia sem bloco = nada a guardar
  end

  it 'mescla tela a tela e null apaga só aquela tela', :aggregate_failures do
    save('report:segmentacao' => { mode: 'fixed', key: 'lime' }, '*' => { mode: 'salad' })
    saved = save('report:segmentacao' => nil)
    expect(saved).not_to have_key('report:segmentacao')
    expect(saved['*']).to include('mode' => 'salad')
  end
end
