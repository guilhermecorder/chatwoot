# 🔐 Resolvedor de acessos (rodada 334): dado uma conta e uma pessoa, diz
# o nível dela em cada nó do catálogo — none, view ou edit.
#
# De onde vem (ordem de força):
#   1. administrador → edita tudo que existe para o ramo da empresa;
#   2. marcação própria da pessoa (agent_permissions['tree'][uid]);
#   3. marcação do PAPEL da pessoa (agent_permissions['roles'][…]['tree']);
#   4. herança: a marcação do pai vale para os filhos sem marcação própria
#      — EXCETO nos nós `explicit` do catálogo (ex.: crm.funis), que só
#      valem com marcação própria (auditoria 12/10: "CRM = editar" não
#      pode liberar apagar funis por tabela);
#   5. padrão do catálogo (default de cada nó).
# Quem ainda não foi configurado no modelo novo é lido pelas concessões
# antigas (grants/menu/report_keys) convertidas na hora — ninguém perde
# acesso no deploy.
#
# Formato gravado em crm_settings.agent_permissions:
#   'tree'         => { '12' => { 'crm' => 'edit', 'relatorios.medicos' => 'none' } }
#   'roles'        => [{ 'id' => 'r_ab12', 'name' => 'Vendedor da loja', 'hint' => '',
#                        'tree' => {…}, 'units' => ['paulista'] }]
#   'role_by_user' => { '12' => 'r_ab12' }
#   'units'        => { '12' => ['paulista'] }   (vazio/ausente = todas)
class Cevico::Access
  LEVELS = Cevico::AccessCatalog::LEVELS
  RANK = Cevico::AccessCatalog::LEVEL_RANK

  attr_reader :account, :user, :perms, :company

  def self.for(account, user, account_user: nil)
    new(account, user, account_user: account_user)
  end

  def self.perms_for(account)
    (CrmSetting.find_by(account: account)&.agent_permissions || {}).to_h
  end

  def initialize(account, user, account_user: nil)
    @account = account
    @user = user
    @account_user = account_user || (account && user && account.account_users.find_by(user: user))
    @perms = self.class.perms_for(account)
    @company = Cevico::Company.for(account)
  end

  def uid = user&.id.to_s
  def admin? = @account_user&.administrator? == true

  # nós que existem para o ramo desta empresa
  def visible_keys
    @visible_keys ||= Cevico::AccessCatalog.keys_for(company.segment)
  end

  def visible?(key)
    visible_keys.include?(key.to_s)
  end

  # ── o papel e as marcações explícitas ─────────────────────────────────
  def role_id
    perms.dig('role_by_user', uid).to_s.presence
  end

  def role
    return nil if role_id.blank?

    Array(perms['roles']).find { |r| r['id'].to_s == role_id }
  end

  def own_tree
    (perms.dig('tree', uid) || {}).to_h
  end

  def role_tree
    (role&.dig('tree') || {}).to_h
  end

  # marcação própria vence a do papel; sem nada no modelo novo, lê o legado
  def explicit_tree
    @explicit_tree ||= begin
      merged = role_tree.merge(own_tree)
      merged = legacy_tree if merged.empty? && !configured_new_model?
      merged.select { |k, v| Cevico::AccessCatalog.exist?(k) && LEVELS.include?(v.to_s) }
    end
  end

  def configured_new_model?
    perms.dig('tree', uid).is_a?(Hash) || role_id.present?
  end

  # ── o nível efetivo ────────────────────────────────────────────────────
  def level(key)
    key = key.to_s
    return 'none' unless Cevico::AccessCatalog.exist?(key) && visible?(key)
    return 'edit' if admin? # admin faz tudo, até nos nós "só ver" (ações de sincronizar etc.)
    return 'none' if Cevico::AccessCatalog.admin_only?(key) || admin_only_ancestor?(key)

    explicit = explicit_level(key)
    return Cevico::AccessCatalog.clamp(key, explicit) if explicit

    Cevico::AccessCatalog.default_level(key)
  end

  def can?(key, needed = 'view')
    needed = needed.to_s
    return true if needed == 'none'

    RANK.fetch(level(key), 0) >= RANK.fetch(needed, 1)
  end

  def view?(key) = can?(key, 'view')
  def edit?(key) = can?(key, 'edit')

  # { 'crm' => 'edit', … } para todos os nós do ramo
  def effective
    visible_keys.index_with { |k| level(k) }
  end

  # ── unidades (lojas) ───────────────────────────────────────────────────
  # [] = todas as unidades
  def units
    return [] if admin?

    own = Array(perms.dig('units', uid)).map(&:to_s)
    list = own.presence || Array(role&.dig('units')).map(&:to_s)
    list & company.unit_keys
  end

  def unit_allowed?(unit_key)
    list = units
    list.empty? || unit_key.blank? || list.include?(unit_key.to_s)
  end

  # ── o que vai para a tela ──────────────────────────────────────────────
  def to_h
    {
      admin: admin?,
      me: effective,
      units: units,
      role_id: role_id,
      catalog: Cevico::AccessCatalog.tree_for(company),
      levels: LEVELS
    }
  end

  # tudo que o ADMIN precisa para a tela Acessos (todas as pessoas)
  def self.admin_payload(account) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    perms = perms_for(account)
    company = Cevico::Company.for(account)
    users = account.account_users.includes(:user).map do |au|
      uid = au.user_id.to_s
      access = new(account, au.user, account_user: au)
      {
        user_id: au.user_id,
        name: au.user&.name,
        email: au.user&.email,
        admin: au.administrator?,
        role_id: perms.dig('role_by_user', uid).to_s.presence,
        # quem ainda está no modelo antigo aparece com as concessões CONVERTIDAS
        # como marcação própria — ao salvar, nada do que tinha se perde
        tree: access.configured_new_model? ? (perms.dig('tree', uid) || {}).to_h : access.legacy_tree,
        legacy: !access.configured_new_model? && access.legacy_data?,
        effective: access.effective,
        units: Array(perms.dig('units', uid)).map(&:to_s)
      }
    end
    {
      roles: Array(perms['roles']),
      users: users,
      catalog: Cevico::AccessCatalog.tree_for(company),
      units: company.units,
      levels: LEVELS
    }
  end

  # ── legado (grants / menu / report_keys / lista de bloqueio) ───────────
  def legacy_data?
    perms.dig('grants', uid).present? || perms.dig('menu', uid).present? ||
      perms.dig('report_keys', uid).present? || perms[uid].is_a?(Array)
  end

  def legacy_tree # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    return {} unless legacy_data?

    out = {}
    menu = perms.dig('menu', uid) || (Cevico::AccessCatalog::LEGACY_DAY_DEFAULT - Array(perms[uid]).map(&:to_s))
    Cevico::AccessCatalog::LEGACY_DAY_ITEMS.each do |item, node|
      out[node] = menu.include?(item) ? Cevico::AccessCatalog.max_level(node) : 'none'
    end

    grants = Array(perms.dig('grants', uid)).map(&:to_s)
    grants.each do |cap|
      node, lvl = Cevico::AccessCatalog::LEGACY_CAPABILITIES[cap]
      out[node] = lvl if node
    end
    out['crm.jornada'] = 'edit' if grants.include?('campaigns')
    if grants.include?('automations')
      out['automacoes.fluxos'] = 'view'
      out['automacoes.resultados'] = 'view'
    end
    out['crm.formularios'] = 'edit' if grants.include?('pages')

    keys = Array(perms.dig('report_keys', uid)).map(&:to_s)
    if grants.include?('reports') && keys.any?
      Cevico::AccessCatalog::LEGACY_REPORT_KEYS.each do |k, node|
        next if node.start_with?('marketing')

        out[node] = keys.include?(k) ? 'view' : 'none'
      end
    end
    # o modelo antigo nunca abre um nó "sem herança" (ninguém tinha essa
    # porta antes; só marcação própria no modelo novo libera)
    out.except(*Cevico::AccessCatalog.explicit_keys)
  end

  private

  def explicit_level(key)
    return explicit_tree[key] if explicit_tree.key?(key)
    # nó "sem herança": a marcação do pai não desce até aqui
    return nil if Cevico::AccessCatalog.explicit?(key)

    Cevico::AccessCatalog.ancestors(key).each do |anc|
      return explicit_tree[anc] if explicit_tree.key?(anc)
    end
    nil
  end

  def admin_only_ancestor?(key)
    Cevico::AccessCatalog.ancestors(key).any? { |anc| Cevico::AccessCatalog.admin_only?(anc) }
  end
end
