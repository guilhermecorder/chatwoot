require 'rails_helper'

# 🔒 auditoria R2 — achados #33/#350 (12/10): o cesto de indicadores do Meu
# Painel (/crm/home/kpis) entregava faturamento e gasto do WhatsApp a QUALQUER
# atendente. Agora: faturamento = administrador ou quem tem a área Financeiro;
# gasto do WhatsApp = só quem tem o nó "Gasto do WhatsApp" (administrador).
# O cesto é guardado por conta, então o corte acontece DEPOIS do cache.
RSpec.describe 'CEVICO cesto de indicadores sem dinheiro para quem não pode', type: :request do
  let(:account) { create(:account) }
  # let! = as duas pessoas nascem ANTES do 1º pedido (o 1º request do processo
  # pode recarregar as classes e a factory reclamaria da conta "antiga")
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/home/kpis" }

  before do
    Rails.cache.clear
    Current.reset
    # com funil na conta, o cesto monta a métrica 'revenue'
    Crm::Pipeline.create!(account: account, name: 'CEVICO', position: 0)
                 .stages.create!(name: 'Cirurgia Realizada', color: '#000', position: 0)
  end

  def perms!(hash)
    CrmSetting.find_or_create_by!(account: account).update!(agent_permissions: hash)
  end

  def metrics_for(user)
    get base, params: { preset: 'today' }, headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    response.parsed_body['metrics']
  end

  it 'atendente sem concessão não recebe faturamento nem gasto do WhatsApp; o resto do cesto continua', :aggregate_failures do
    metrics = metrics_for(agent)
    expect(metrics.keys).not_to include('revenue', 'wa_cost', 'wa_cost_meta')
    expect(metrics.keys).to include('new_leads', 'appointments_booked', 'wa_messages_sent')
  end

  it 'administrador recebe o cesto inteiro' do
    expect(metrics_for(admin).keys).to include('revenue', 'wa_cost', 'wa_cost_meta')
  end

  # DECISÃO PENDENTE (Guilherme, 12/10): ficou o lado mais fechado — só quem
  # EDITA o Financeiro (régua da concessão antiga 'finance') vê o faturamento;
  # "só ver" não abre. Se ele decidir abrir para "ver", este exemplo muda junto
  # com can_see_revenue? (home_controller.rb) e canSeeRevenue (InicioPage.vue).
  it 'Financeiro "só ver" não abre o faturamento; "editar" abre, e o gasto do WhatsApp segue só para admin', :aggregate_failures do
    perms!('tree' => { agent.id.to_s => { 'financeiro' => 'view' } })
    expect(metrics_for(agent).keys).not_to include('revenue')

    perms!('tree' => { agent.id.to_s => { 'financeiro' => 'edit' } })
    metrics = metrics_for(agent)
    expect(metrics.keys).to include('revenue')
    expect(metrics.keys).not_to include('wa_cost', 'wa_cost_meta')
  end

  it 'o R$ das cirurgias fechadas do "Meu desempenho" (home#show) só vai para quem pode ver dinheiro', :aggregate_failures do
    home = "/api/v1/accounts/#{account.id}/crm/home"
    me_for = lambda do |user|
      get home, params: { preset: 'today' }, headers: user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      response.parsed_body.dig('my_performance', 'me', 'surgeries')
    end

    expect(me_for.call(agent)).to eq('count' => 0)
    expect(me_for.call(admin)).to eq('count' => 0, 'revenue' => 0.0)

    perms!('tree' => { agent.id.to_s => { 'financeiro' => 'edit' } })
    Rails.cache.clear
    expect(me_for.call(agent)).to include('revenue')
  end

  it 'a marca "só Financeiro" dos modelos prontos é gravada junto com o card' do
    post "/api/v1/accounts/#{account.id}/crm/settings/update_agenda",
         params: { custom_kpis: [{ id: 'gestor_p_fat', label: 'Faturamento', expr: 'revenue', format: 'currency', finance: true },
                                 { id: 'gestor_p_leads', label: 'Leads', expr: 'new_leads' }] },
         headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)

    saved = CrmSetting.find_by!(account: account).agenda_config['custom_kpis']
    expect(saved.map { |k| [k['id'], k['finance']] }).to eq([['gestor_p_fat', true], ['gestor_p_leads', false]])
  end

  it 'o corte vale mesmo quando o cesto vem do cache (chave por conta, não por pessoa)', :aggregate_failures do
    store = ActiveSupport::Cache::MemoryStore.new
    allow(Rails).to receive(:cache).and_return(store)

    # o admin esquenta o cache com o cesto completo…
    expect(metrics_for(admin).keys).to include('revenue')
    expect(store.instance_variable_get(:@data).keys.grep(/cevico:kpibag/)).not_to be_empty
    # …e o atendente, lendo o MESMO cesto guardado, não recebe o dinheiro
    expect(metrics_for(agent).keys).not_to include('revenue', 'wa_cost', 'wa_cost_meta')
    # e o cache não foi mutilado: o admin continua vendo tudo
    expect(metrics_for(admin).keys).to include('revenue', 'wa_cost', 'wa_cost_meta')
  end

  describe 'Crm::KpiBagService.without_keys' do
    it 'tira só as chaves pedidas, com chaves string ou símbolo', :aggregate_failures do
      sym = { metrics: { 'revenue' => 1, 'new_leads' => 2 }, points: [] }
      str = { 'metrics' => { 'revenue' => 1, 'new_leads' => 2 }, 'points' => [] }
      expect(Crm::KpiBagService.without_keys(sym, Crm::KpiBagService::MONEY_KEYS)).to eq(metrics: { 'new_leads' => 2 }, points: [])
      expect(Crm::KpiBagService.without_keys(str, Crm::KpiBagService::MONEY_KEYS)).to eq('metrics' => { 'new_leads' => 2 }, 'points' => [])
      expect(Crm::KpiBagService.without_keys(sym, [])).to equal(sym)
    end
  end
end
