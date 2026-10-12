require 'rails_helper'

# 🔐 rodada 334: a trava automática pelo catálogo vale na API (ver × editar),
# e os endpoints de Acessos/Papéis/Empresa são só do administrador.
RSpec.describe 'CEVICO acessos em árvore (API)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }

  def perms!(hash)
    CrmSetting.find_or_create_by!(account: account).update!(agent_permissions: hash)
  end

  describe 'funis (crm.funis)' do
    it 'atendente vê a lista mas não cria; com a concessão, cria', :aggregate_failures do
      get "#{base}/pipelines", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)

      post "#{base}/pipelines", params: { pipeline: { name: 'Novo' } }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to include('Funis e colunas')

      perms!('tree' => { agent.id.to_s => { 'crm.funis' => 'edit' } })
      post "#{base}/pipelines", params: { pipeline: { name: 'Novo' } }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
    end

    it 'administrador sempre passa' do
      post "#{base}/pipelines", params: { pipeline: { name: 'Novo' } }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
    end
  end

  describe 'ver × editar (financeiro)' do
    it 'quem só VÊ abre a tela e é barrado ao lançar, com mensagem que explica', :aggregate_failures do
      get "#{base}/finance", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)

      perms!('tree' => { agent.id.to_s => { 'financeiro' => 'view' } })
      get "#{base}/finance", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)

      post "#{base}/finance/create_entry", params: { kind: 'income', amount: 10, description: 'x' },
                                           headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to include('só pode ver')
    end
  end

  describe 'Tarefas × Agenda pela mesma API' do
    it 'consulta cobra a Agenda (padrão: edita); tarefa comum cobra Tarefas (padrão: nada)', :aggregate_failures do
      post "/api/v1/accounts/#{account.id}/tasks", params: { title: 'Ligar', task_type: 'tarefa' },
                                                   headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/accounts/#{account.id}/tasks",
           params: { title: 'Consulta', task_type: 'consulta', due_at: 2.days.from_now.iso8601 },
           headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)

      perms!('tree' => { agent.id.to_s => { 'tarefas' => 'edit', 'agenda' => 'view' } })
      post "/api/v1/accounts/#{account.id}/tasks", params: { title: 'Ligar', task_type: 'tarefa' },
                                                   headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      post "/api/v1/accounts/#{account.id}/tasks",
           params: { title: 'Consulta', task_type: 'consulta', due_at: 2.days.from_now.iso8601 },
           headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'unidades (lojas)' do
    it 'pessoa presa a uma unidade só vê e só marca consultas dela', :aggregate_failures do
      Cevico::Company.save!(account, segment: 'otica', units: [{ label: 'Loja Tatuapé' }, { label: 'Loja Paulista' }])
      Task.create!(account: account, creator: agent, assignee: agent, title: 'Tatuapé', task_type: 'consulta', unit: 'loja_tatuape',
                   due_at: 1.day.from_now)
      Task.create!(account: account, creator: agent, assignee: agent, title: 'Paulista', task_type: 'consulta', unit: 'loja_paulista',
                   due_at: 1.day.from_now)
      perms!('units' => { agent.id.to_s => ['loja_tatuape'] })

      get "/api/v1/accounts/#{account.id}/tasks", headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body.pluck('unit')).to eq(['loja_tatuape'])

      post "/api/v1/accounts/#{account.id}/tasks",
           params: { title: 'x', task_type: 'consulta', unit: 'loja_paulista', due_at: 2.days.from_now.iso8601 },
           headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to include('unidade')

      get "/api/v1/accounts/#{account.id}/crm/appointments/feed", params: { preset: 'next7' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  describe 'concessão antiga continua valendo' do
    it 'grants reports abre o Dashboard de Agentes e o relatório específico filtra', :aggregate_failures do
      perms!('grants' => { agent.id.to_s => %w[reports] }, 'report_keys' => { agent.id.to_s => %w[agents_dashboard] })
      get "#{base}/agents_dashboard", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      get "#{base}/traffic_report", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)

      # a tela Acessos já mostra o legado convertido como marcação própria
      get "#{base}/settings/access_admin", headers: admin.create_new_auth_token, as: :json
      me = response.parsed_body['users'].find { |u| u['user_id'] == agent.id }
      expect(me['legacy']).to be(true)
      expect(me['tree']).to include('relatorios' => 'view', 'relatorios.agentes' => 'view', 'relatorios.crm' => 'none')
    end
  end

  describe 'endpoints de acessos (só admin)' do
    it 'grava marcação, papel e unidades; devolve o efetivo; o próprio atendente não mexe', :aggregate_failures do
      post "#{base}/settings/update_access_roles",
           params: { roles: [{ name: 'Gerente de loja', hint: 'cuida da loja',
                               tree: { 'financeiro' => 'edit', 'relatorios' => 'view', 'configuracoes.acessos' => 'edit' } }] },
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      role = response.parsed_body['roles'].first
      expect(role['id']).to start_with('r_')
      expect(role['tree']).to eq('financeiro' => 'edit', 'relatorios' => 'view') # admin-only não entra

      post "#{base}/settings/update_agent_access",
           params: { user_id: agent.id, role_id: role['id'],
                     tree: { 'financeiro.estoque' => 'none', 'crm.funis' => 'edit', 'inexistente' => 'edit', 'relatorios' => 'edit' } },
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      me = response.parsed_body['users'].find { |u| u['user_id'] == agent.id }
      expect(me['role_id']).to eq(role['id'])
      expect(me['tree']).to eq('financeiro.estoque' => 'none', 'crm.funis' => 'edit', 'relatorios' => 'view')
      expect(me['effective']).to include('financeiro.lancamentos' => 'edit', 'financeiro.estoque' => 'none', 'crm.funis' => 'edit')

      get "#{base}/settings", headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body.dig('access', 'me', 'financeiro.estoque')).to eq('none')
      expect(response.parsed_body.dig('access', 'role_id')).to eq(role['id'])
      expect(response.parsed_body.dig('company', 'segment')).to eq('clinica')

      post "#{base}/settings/update_agent_access", params: { user_id: agent.id, tree: { 'configuracoes.acessos' => 'edit' } },
                                                   headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      get "#{base}/settings/access_admin", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)

      # apagar o papel tira a referência da pessoa
      post "#{base}/settings/update_access_roles", params: { roles: [] }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['users'].find { |u| u['user_id'] == agent.id }['role_id']).to be_nil
    end

    it 'identidade da empresa: grava e o catálogo acompanha o ramo', :aggregate_failures do
      post "#{base}/settings/update_company",
           params: { company: { name: 'Sua Ótica', segment: 'otica', units: [{ label: 'Loja Tatuapé' }], assistant: { name: 'Lia', gender: 'f' } } },
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body.dig('company', 'name')).to eq('Sua Ótica')
      expect(response.parsed_body.dig('company', 'vocabulary', 'paciente')).to eq('cliente')
      expect(response.parsed_body.dig('company', 'units').first['key']).to eq('loja_tatuape')
      keys = response.parsed_body.dig('access', 'catalog').map { |n| n['key'] }
      expect(keys).to include('crm').and include('relatorios')
      expect(response.parsed_body.dig('access', 'me', 'relatorios.medicos')).to be_nil

      post "#{base}/settings/update_company", params: { company: { name: 'x' } }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
