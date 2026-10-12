require 'rails_helper'

# 🔐 rodada 334: catálogo em árvore + resolvedor (ver × editar, herança,
# papéis, conversão do modelo antigo, ramo da empresa, unidades)
RSpec.describe Cevico::Access do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:catalog) { Cevico::AccessCatalog }

  def perms!(hash)
    settings = CrmSetting.find_or_create_by!(account: account)
    settings.update!(agent_permissions: hash)
  end

  def access_for(user)
    described_class.for(account, user)
  end

  describe 'catálogo' do
    it 'tem chaves únicas e todo mapa aponta para nós que existem', :aggregate_failures do
      flat = catalog.send(:flatten, catalog.tree).map { |n| n['key'] }
      expect(flat.uniq.size).to eq(flat.size)
      catalog::CONTROLLER_NODES.each_value do |spec|
        expect(catalog.exist?(spec[:node])).to be(true), "nó #{spec[:node]} não existe"
        (spec[:actions] || {}).each_value { |(node, _)| expect(catalog.exist?(node)).to be(true), "nó #{node} não existe" }
      end
      (catalog::LEGACY_CAPABILITIES.values.map(&:first) + catalog::LEGACY_DAY_ITEMS.values + catalog::LEGACY_REPORT_KEYS.values).each do |node|
        expect(catalog.exist?(node)).to be(true), "nó legado #{node} não existe"
      end
    end

    it 'resolve padrão, herança de padrão e trava de nível', :aggregate_failures do
      expect(catalog.default_level('crm')).to eq('edit')
      expect(catalog.default_level('crm.funis')).to eq('none')
      expect(catalog.default_level('agenda.exames')).to eq('edit') # inherit → agenda (edit)
      expect(catalog.default_level('relatorios.crm')).to eq('none') # inherit → relatorios (none)
      expect(catalog.clamp('relatorios', 'edit')).to eq('view') # relatórios é só-ver
      expect(catalog.requirement_for('crm/pipelines', 'create')).to eq(%w[crm.funis edit])
      expect(catalog.requirement_for('crm/pipelines', 'index')).to eq(%w[crm view])
      expect(catalog.requirement_for('crm/finance', 'show')).to eq(%w[financeiro.lancamentos view])
      expect(catalog.requirement_for('crm/stock', 'lookup')).to be_nil
      expect(catalog.requirement_for('crm/home', 'show')).to be_nil
    end

    it 'esconde os nós de clínica para outro ramo' do
      expect(catalog.keys_for('otica')).not_to include('relatorios.medicos', 'agenda.cirurgias')
      expect(catalog.keys_for('clinica')).to include('relatorios.medicos')
    end
  end

  describe 'administrador' do
    it 'edita tudo do ramo e perde só o que o ramo não tem', :aggregate_failures do
      access = access_for(admin)
      expect(access.level('crm.funis')).to eq('edit')
      expect(access.level('relatorios')).to eq('edit') # admin faz tudo, até no nó só-ver
      expect(access.level('configuracoes.acessos')).to eq('edit')
      expect(access.units).to eq([])

      Cevico::Company.save!(account, segment: 'otica')
      expect(access_for(admin).level('relatorios.medicos')).to eq('none')
    end
  end

  describe 'atendente' do
    it 'sem configuração usa o padrão do catálogo', :aggregate_failures do
      access = access_for(agent)
      expect(access.level('crm')).to eq('edit')
      expect(access.level('crm.funis')).to eq('none')
      expect(access.level('relatorios.crm')).to eq('none')
      expect(access.level('metas')).to eq('view')
      expect(access.level('tarefas')).to eq('none')
      expect(access.level('configuracoes.acessos')).to eq('none')
      expect(access.can?('crm', :view)).to be(true)
      expect(access.can?('crm.funis', :edit)).to be(false)
    end

    it 'marcação própria vale para os filhos, salvo filho marcado; só-ver trava o editar', :aggregate_failures do
      perms!('tree' => { agent.id.to_s => { 'relatorios' => 'edit', 'relatorios.medicos' => 'none', 'crm' => 'view' } })
      access = access_for(agent)
      expect(access.level('relatorios')).to eq('view')
      expect(access.level('relatorios.agenda')).to eq('view')
      expect(access.level('relatorios.medicos')).to eq('none')
      expect(access.level('relatorios.gasto_whatsapp')).to eq('none') # admin-only nunca é concedido
      expect(access.level('crm')).to eq('view')
      expect(access.level('crm.campanhas')).to eq('view') # herda do pai (view), não o padrão (none)
      expect(access.edit?('crm')).to be(false)
    end

    it 'papel dá a base e a marcação própria vence', :aggregate_failures do
      role = { 'id' => 'r_loja01', 'name' => 'Vendedor', 'tree' => { 'financeiro' => 'view', 'tarefas' => 'edit' }, 'units' => ['paulista'] }
      perms!('roles' => [role],
             'role_by_user' => { agent.id.to_s => 'r_loja01' },
             'tree' => { agent.id.to_s => { 'financeiro.estoque' => 'edit' } })
      access = access_for(agent)
      expect(access.level('financeiro.lancamentos')).to eq('view')
      expect(access.level('financeiro.estoque')).to eq('edit')
      expect(access.level('tarefas')).to eq('edit')
      expect(access.units).to eq(['paulista'])
      expect(access.unit_allowed?('tatuape')).to be(false)
      expect(access.unit_allowed?(nil)).to be(true)
    end

    it 'converte as concessões antigas (grants/menu/report_keys) sem ninguém perder acesso', :aggregate_failures do
      perms!('grants' => { agent.id.to_s => %w[reports finance] },
             'menu' => { agent.id.to_s => %w[crm conversation tasks] },
             'report_keys' => { agent.id.to_s => %w[crm_dashboard agents_dashboard] })
      access = access_for(agent)
      expect(access.configured_new_model?).to be(false)
      expect(access.level('relatorios.crm')).to eq('view')
      expect(access.level('relatorios.agentes')).to eq('view')
      expect(access.level('relatorios.agenda')).to eq('none')
      expect(access.level('financeiro.lancamentos')).to eq('edit')
      expect(access.level('tarefas')).to eq('edit')
      expect(access.level('agenda')).to eq('none') # saiu do menu antigo
      expect(access.level('metas')).to eq('none')
    end

    it 'lista de bloqueio legada (modelo mais antigo) tira do padrão' do
      perms!(agent.id.to_s => ['agenda'])
      expect(access_for(agent).level('agenda')).to eq('none')
      expect(access_for(agent).level('crm')).to eq('edit')
    end
  end

  describe 'identidade da empresa' do
    it 'preenche o vocabulário por ramo e aceita troca de palavra', :aggregate_failures do
      company = Cevico::Company.for(account)
      expect(company.segment).to eq('clinica')
      expect(company.fill('Jornada do {{paciente}}')).to eq('Jornada do paciente')
      Cevico::Company.save!(account, name: 'Sua Ótica', segment: 'otica', vocabulary: { 'medico' => 'vendedor' },
                                     units: [{ label: 'Loja Tatuapé' }, { key: 'paulista', label: 'Loja Paulista' }])
      company = Cevico::Company.for(account)
      expect(company.fill('{{Paciente_plural}} e {{medico_plural}}')).to eq('Clientes e consultores')
      expect(company.word(:medico)).to eq('vendedor')
      expect(company.unit_keys).to eq(%w[loja_tatuape paulista])
      expect(company.module?(:cirurgias)).to be(false)
      expect(company.prompt_context).to include('Sua Ótica').and include('cliente')
      reports = Cevico::AccessCatalog.tree_for(company).find { |n| n['key'] == 'relatorios' }
      expect(reports['children'].pluck('key')).not_to include('relatorios.medicos')
    end
  end
end
