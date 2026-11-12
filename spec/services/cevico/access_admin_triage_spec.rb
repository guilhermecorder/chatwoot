require 'rails_helper'

# 🧭 11/11/2026 (LIFE): o DONO da conta deixa outro administrador vendo só o essencial.
RSpec.describe Cevico::Access do
  let(:account) { create(:account) }
  let(:dono) { create(:user, account: account, role: :administrator, name: 'Guilherme') }
  let(:socio) { create(:user, account: account, role: :administrator, name: 'Fernando') }
  let(:atendente) { create(:user, account: account, role: :agent, name: 'Lucas') }
  let(:setting) { CrmSetting.find_or_create_by!(account: account) }

  def acesso(user) = described_class.for(account, user)

  it 'sem dono definido (ou sem lista), administrador segue vendo tudo', :aggregate_failures do
    setting.update!(agent_permissions: { 'admin_limits' => { socio.id.to_s => { 'liberados' => %w[inicio] } } })
    expect(acesso(socio).admin_limited?).to be(false)
    expect(acesso(socio).level('financeiro')).to eq('edit')

    setting.update!(agent_permissions: { 'owner_ids' => [dono.id] })
    expect(acesso(socio).admin_limited?).to be(false)
    expect(acesso(socio).level('crm')).to eq('edit')
  end

  it 'administrador em triagem só tem o que o dono liberou (e os filhos); o dono nunca é limitado', :aggregate_failures do
    setting.update!(agent_permissions: { 'owner_ids' => [dono.id],
                                         'admin_limits' => { socio.id.to_s => { 'liberados' => %w[inicio conversas crm tarefas agenda] },
                                                             dono.id.to_s => { 'liberados' => [] } } })
    a = acesso(socio)
    expect(a.admin_limited?).to be(true)
    expect(a.level('crm')).to eq('edit')
    expect(a.level('crm.funis')).to eq('edit')
    expect(a.level('inicio')).to eq('edit')
    expect(a.level('financeiro')).to eq('none')
    expect(a.level('configuracoes.acessos')).to eq('none')
    expect(a.to_h).to include(admin: true, owner: false, limited: true)

    d = acesso(dono)
    expect(d.owner?).to be(true)
    expect(d.admin_limited?).to be(false)
    expect(d.level('financeiro')).to eq('edit')
    expect(acesso(atendente).owner?).to be(false)
  end

  it 'dentro de uma área liberada, o dono pode esconder um item (a marcação mais próxima vence)', :aggregate_failures do
    setting.update!(agent_permissions: { 'owner_ids' => [dono.id],
                                         'admin_limits' => { socio.id.to_s => { 'liberados' => %w[crm agenda],
                                                                                'escondidos' => %w[crm.campanhas agenda.configuracao] } } })
    a = acesso(socio)
    expect(a.level('crm')).to eq('edit')
    expect(a.level('crm.agendamentos')).to eq('edit')
    expect(a.level('crm.campanhas')).to eq('none')
    expect(a.level('agenda.configuracao')).to eq('none')
    expect(a.level('agenda.notificacoes')).to eq('edit')
  end

  it 'a tela de Acessos recebe quem é dono e a lista de cada administrador', :aggregate_failures do
    setting.update!(agent_permissions: { 'owner_ids' => [dono.id], 'admin_limits' => { socio.id.to_s => { 'liberados' => %w[inicio crm] } } })
    payload = described_class.admin_payload(account)
    expect(payload[:owner_ids]).to eq([dono.id])
    by_id = payload[:users].index_by { |u| u[:user_id] }
    expect(by_id[socio.id]).to include(owner: false, liberados: %w[inicio crm])
    expect(by_id[dono.id]).to include(owner: true, liberados: nil)
  end
end
