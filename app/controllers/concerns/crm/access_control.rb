# 🔐 Controle de acesso CEVICO — rodada 334: ÁRVORE pai/filho com ver × editar.
#
# A fonte é o catálogo (config/cevico/access_catalog.yml) lido por
# Cevico::AccessCatalog; o nível de cada pessoa vem de Cevico::Access
# (admin → tudo; marcação própria → papel → herança do pai → padrão).
#
# Três jeitos de travar um controller:
#   1. AUTOMÁTICO: o mapa Cevico::AccessCatalog::CONTROLLER_NODES diz o nó de
#      cada controller; ações de leitura pedem VER, as outras pedem EDITAR.
#      Vale para todo controller de api/v1/accounts/* (incluído no Base).
#   2. `require_access('crm.funis', :edit)` em before_action, quando a regra
#      é mais fina que o mapa.
#   3. `require_capability(:reports)` — o jeito antigo (17/07) continua
#      funcionando: cada capability vira um nó da árvore (LEGACY_CAPABILITIES).
#
# Regra que não muda: administrador SEMPRE passa; conceder acessos é só admin.
module Crm::AccessControl
  extend ActiveSupport::Concern

  # mantidos por compatibilidade (settings_controller e telas antigas)
  CAPABILITIES = Cevico::AccessCatalog::LEGACY_CAPABILITIES.keys.freeze
  DAY_MENU_ITEMS = Cevico::AccessCatalog::LEGACY_DAY_ITEMS.keys.freeze
  DAY_MENU_DEFAULT = Cevico::AccessCatalog::LEGACY_DAY_DEFAULT
  # HUB (rodada 34): MÓDULOS do mundo Saúde que o admin libera por pessoa
  # (lista vazia/ausente = todos). Só faz sentido com a área 'health'.
  HEALTH_MODULES = %w[treino cardio boxe corpo dieta dash rotina educacao].freeze

  included do
    before_action :cevico_catalog_guard
  end

  # HUB (rodada 34): MÓDULOS do mundo Saúde que o admin libera por pessoa
  # (lista vazia/ausente = todos). Só faz sentido com a área 'health'.
  HEALTH_MODULES = %w[treino cardio boxe corpo dieta dash rotina educacao].freeze

  private

  # a pessoa desta requisição, resolvida uma vez
  def cevico_access
    @cevico_access ||= Cevico::Access.for(Current.account, Current.user, account_user: Current.account_user)
  end

  def cevico_company
    @cevico_company ||= cevico_access.company
  end

  # ── a trava automática pelo mapa controller → nó ───────────────────────
  def cevico_catalog_guard
    return if Current.account.nil?

    requirement = cevico_access_requirement
    return if requirement.nil?

    node, level = requirement
    return if cevico_access.can?(node, level)

    render json: { error: cevico_denied_message(node, level) }, status: :forbidden
  end

  # controllers com regra que depende dos parâmetros (ex.: Tarefas × Agenda)
  # sobrescrevem este método; o padrão é o mapa do catálogo
  def cevico_access_requirement
    path = controller_path.delete_prefix('api/v1/accounts/')
    Cevico::AccessCatalog.requirement_for(path, action_name)
  end

  # ── travas explícitas ──────────────────────────────────────────────────
  def require_access(node, level = :view)
    return if cevico_access.can?(node, level)

    render json: { error: cevico_denied_message(node, level) }, status: :forbidden
  end

  def require_capability(capability)
    node, level = Cevico::AccessCatalog::LEGACY_CAPABILITIES[capability.to_s]
    return require_access(node, level) if node

    render json: { error: 'Você não tem acesso a esta área. Peça a um administrador.' }, status: :forbidden
  end

  # qualquer UMA das concessões libera (ex.: Central de Criativos = Relatórios OU Marketing)
  def require_any_capability(*capabilities)
    return if capabilities.any? { |capability| crm_can?(capability) }

    render json: { error: 'Você não tem acesso a esta área. Peça a um administrador.' }, status: :forbidden
  end

  # admin estrito (não delegável) — para ações como conceder acessos
  def require_administrator!
    return if Current.account_user&.administrator?

    render json: { error: 'Apenas administradores.' }, status: :forbidden
  end

  def crm_can?(capability)
    node, level = Cevico::AccessCatalog::LEGACY_CAPABILITIES[capability.to_s]
    return false unless node

    cevico_access.can?(node, level)
  end

  def cevico_can?(node, level = :view)
    cevico_access.can?(node, level)
  end

  def cevico_denied_message(node, level)
    label = Cevico::AccessCatalog.node(node)&.dig('label').to_s
    label = cevico_company.fill(label).presence || 'esta área'
    if level.to_s == 'edit' && cevico_access.view?(node)
      "Você só pode ver #{label}. Peça a um administrador para liberar a edição."
    else
      "Você não tem acesso a #{label}. Peça a um administrador."
    end
  end
end
