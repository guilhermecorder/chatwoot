# 🔐 Catálogo de acessos (rodada 334): lê config/cevico/access_catalog.yml,
# achata a árvore em chaves com ponto (crm.funis) e responde perguntas
# simples: "esse nó existe?", "quais níveis aceita?", "qual o padrão?".
#
# Também guarda o MAPA controller → nó, que é o que faz a trava valer na
# API sem cada controller repetir a lista (ver Cevico::CatalogGuard).
module Cevico::AccessCatalog # rubocop:disable Metrics/ModuleLength
  module_function

  LEVELS = %w[none view edit].freeze
  LEVEL_RANK = { 'none' => 0, 'view' => 1, 'edit' => 2 }.freeze
  PATH = Rails.root.join('config/cevico/access_catalog.yml')

  # ── árvore e índice ────────────────────────────────────────────────────
  def tree
    @tree ||= normalize(YAML.safe_load(File.read(PATH)), nil)
  end

  # { 'crm.funis' => { 'key' => 'crm.funis', 'parent' => 'crm', ... } }
  def index
    @index ||= flatten(tree).index_by { |n| n['key'] }
  end

  def keys
    index.keys
  end

  def node(key)
    index[key.to_s]
  end

  def exist?(key)
    index.key?(key.to_s)
  end

  def parent_of(key)
    node(key)&.dig('parent')
  end

  def ancestors(key)
    out = []
    current = parent_of(key)
    while current
      out << current
      current = parent_of(current)
    end
    out
  end

  def children_of(key)
    (node(key)&.dig('children') || []).pluck('key')
  end

  def descendants(key)
    children_of(key).flat_map { |c| [c] + descendants(c) }
  end

  def admin_only?(key)
    node(key)&.dig('admin') == true
  end

  # nó que NÃO herda do pai: só vale com marcação própria (auditoria 12/10,
  # ex.: crm.funis — "CRM = editar" não pode liberar apagar funis por tabela)
  def explicit?(key)
    node(key)&.dig('explicit') == true
  end

  def explicit_keys
    keys.select { |k| explicit?(k) }
  end

  # o maior nível que o nó aceita ('view' ou 'edit')
  def max_level(key)
    levels = node(key)&.dig('levels') || %w[view]
    levels.include?('edit') ? 'edit' : 'view'
  end

  # trava um nível ao que o nó aceita (nó só-ver nunca vira 'edit')
  def clamp(key, level)
    level = level.to_s
    return 'none' unless LEVELS.include?(level)
    return level if level == 'none'

    LEVEL_RANK[level] > LEVEL_RANK[max_level(key)] ? max_level(key) : level
  end

  # padrão de um atendente SEM configuração (resolve 'inherit' subindo)
  def default_level(key)
    n = node(key)
    return 'none' unless n
    return 'none' if n['admin'] == true

    raw = n['default'].to_s
    return clamp(key, raw) if LEVELS.include?(raw)
    return clamp(key, default_level(n['parent'])) if n['parent']

    'none'
  end

  # nós visíveis para uma empresa (ramo clínica vê tudo; outros perdem os
  # nós marcados com segment: clinica)
  def keys_for(segment)
    segment = segment.to_s
    keys.reject do |key|
      seg = node(key)['segment'].to_s
      seg.present? && seg != segment
    end
  end

  # árvore pronta para a tela (rótulos com o vocabulário da empresa)
  def tree_for(company)
    segment = company.segment
    prune = lambda do |nodes|
      nodes.filter_map do |n|
        seg = n['segment'].to_s
        next if seg.present? && seg != segment

        n.merge(
          'label' => company.fill(n['label']),
          'hint' => company.fill(n['hint']),
          'children' => prune.call(n['children'] || [])
        )
      end
    end
    prune.call(tree)
  end

  # ── mapa controller → nó (a trava da API) ──────────────────────────────
  # 'crm/nome_do_controller' (caminho depois de api/v1/accounts/) => { node:, view: [ações que só precisam VER],
  #                           skip: [ações livres], actions: { 'acao' => [nó, nível] } }
  # Ação não listada em view/skip/actions precisa EDITAR o nó.
  # Ações de leitura comuns (index, show, feed, overview, dashboard…) são
  # tratadas como VER por padrão (READ_ACTIONS).
  READ_ACTIONS = %w[index show feed overview history dashboard export analytics graph timeline assets
                    status summary preview_link map settings_show rates items orders entries compare
                    profitability acquisition clinic permission_status recording settings
                    load_history share sync_status import_status options_params].freeze

  CONTROLLER_NODES = {
    # ── CRM ──
    'crm/pipelines' => { node: 'crm.funis', actions: { 'index' => %w[crm view], 'show' => %w[crm view] } },
    'crm/stages' => { node: 'crm.funis', actions: { 'index' => %w[crm view] } },
    'crm/contacts' => { node: 'crm', view: %w[index history detect_value detect_values_bulk] },
    'crm/funnels' => { node: 'crm', view: %w[acquisition clinic] },
    'crm/campaigns' => { node: 'crm.campanhas', view: %w[index show results templates] },
    'crm/call_campaigns' => { node: 'crm.campanhas', view: %w[index show] },
    'crm/message_automations' => { node: 'crm.campanhas', view: %w[index preview_eligible] },
    'crm/campaigns_dashboards' => { node: 'relatorios.campanhas', view: %w[show] },
    'crm/journey_messages' => { node: 'crm.jornada', view: %w[index map settings_show] },
    'crm/journey_sends' => { node: 'crm.jornada', view: %w[index queue] },
    'crm/forms' => { node: 'crm.formularios', view: %w[index summary preview_link] },
    'crm/appointments' => { node: 'crm.agendamentos', view: %w[feed] },
    'crm/appointment_alerts' => { node: 'agenda.notificacoes', view: %w[index count] }, # 🔔 item 346
    'crm/sources' => { node: 'crm.fontes' },
    # ── Agenda / pacientes ──
    'crm/patients' => { node: 'pacientes', view: %w[show search phone_owner] }, # 🔎 item 346: a busca só lê
    'crm/patient_chats' => { node: 'pacientes', view: %w[show] },
    'crm/patient_notes' => { node: 'pacientes', view: %w[index] },
    'crm/clinical_notes' => { node: 'pacientes.notas_clinicas', view: %w[index] },
    'crm/oftalmofacil' => { node: 'pacientes.oftalmofacil', view: %w[overview items patients show] },
    'crm/conversation_summaries' => { node: 'conversas', view: %w[show] },
    'crm/calls' => { node: 'chamadas', view: %w[index overview show recording export permission_status],
                     actions: { 'dashboard' => %w[relatorios.ligacoes view] } },
    # ── Tarefas e metas ──
    'tasks' => { node: 'tarefas', view: %w[index agenda_details] }, # a Agenda refina em TasksController
    'crm/goal_plans' => { node: 'metas', view: %w[show] },
    'crm/closing_tools' => { node: 'metas.ferramentas', view: %w[show] },
    'crm/team_tools' => { node: 'metas.ferramentas', view: %w[index] },
    'crm/people' => { node: 'pessoas', view: %w[show] },
    # ── Relatórios ──
    'crm/dashboards' => { node: 'relatorios.crm', view: %w[show pro_series loss_contacts] },
    'crm/traffic_reports' => { node: 'relatorios.funil_trafego', view: %w[show] },
    'crm/doctors_dashboards' => { node: 'relatorios.medicos', view: %w[show] },
    'crm/agents_dashboards' => { node: 'relatorios.agentes', view: %w[show] },
    'crm/agenda_dashboards' => { node: 'relatorios.agenda', view: %w[show] },
    'crm/ads_reports' => { node: 'relatorios.anuncios', view: %w[show backfill] },
    'crm/google_dashboards' => { node: 'relatorios.google', view: %w[show] },
    'crm/whatsapp_spends' => { node: 'relatorios.gasto_whatsapp', view: %w[show rates] },
    'crm/whatsapp_healths' => { node: 'relatorios.whatsapp_saude', view: %w[show] },
    'crm/acquisition_costs' => { node: 'financeiro.cac', view: %w[show] },
    # ── Automações ──
    'crm/automations' => { node: 'automacoes.robos', view: %w[index] },
    'crm/followup_bots' => { node: 'automacoes.robos', view: %w[index ai_preview smart results], skip: %w[toggle] },
    'crm/flows' => { node: 'automacoes.fluxos', view: %w[index show] },
    'crm/automations_dashboards' => { node: 'automacoes.resultados', view: %w[show] },
    'crm/agent_guidances' => { node: 'automacoes.agentes_ia', view: %w[index] },
    'crm/script_versions' => { node: 'automacoes.agentes_ia', view: %w[index] },
    'crm/ai_dashboards' => { node: 'automacoes.agentes_ia', view: %w[show] },
    'crm/batch_updates' => { node: 'automacoes.tratamento', view: %w[preview] },
    'crm/retro_labels' => { node: 'automacoes.tratamento', view: %w[preview] },
    'crm/label_replacements' => { node: 'automacoes.tratamento', view: %w[preview] },
    'crm/label_removals' => { node: 'automacoes.tratamento', view: %w[preview] },
    'crm/contact_unifications' => { node: 'automacoes.tratamento', view: %w[preview] },
    'crm/external_surgeries' => { node: 'automacoes.tratamento', view: %w[preview preview_sheet import_status] },
    # ── Marketing ──
    'crm/creatives' => { node: 'marketing.criativos',
                         view: %w[index show timeline history assets analytics graph sync_status load_history export] },
    # quem só VÊ páginas lê e COMENTA (delete_comment confere autor/admin sozinho)
    'crm/pages' => { node: 'marketing.paginas', view: %w[index generate_status add_comment delete_comment] },
    'crm/content_items' => { node: 'marketing.paginas', view: %w[index] },
    'crm/pages_dashboards' => { node: 'marketing.resultados', view: %w[show] },
    'crm/pages_reports' => { node: 'marketing.resultados', view: %w[show] },
    'crm/campaign_agent' => { node: 'marketing.campanhas', view: %w[show] }, # 🎯 item 352
    'crm/page_agent' => { node: 'marketing.resultados', view: %w[show timeline steps] }, # 📄 item 353
    # ── Financeiro / estratégia ──
    'crm/finance' => { node: 'financeiro.lancamentos', view: %w[show profitability compare entries] },
    'crm/stock' => { node: 'financeiro.estoque', view: %w[show items orders], skip: %w[lookup create_order] },
    'crm/strategy' => { node: 'estrategia', view: %w[show] },
    # ── Configurações ──
    'crm/appointment_reminders' => { node: 'configuracoes.modelos' }
  }.freeze

  # [nó, nível] exigidos por uma ação de um controller — nil = livre
  def requirement_for(controller_name, action_name)
    spec = CONTROLLER_NODES[controller_name.to_s]
    return nil unless spec

    action = action_name.to_s
    return nil if Array(spec[:skip]).include?(action)
    return spec[:actions][action] if spec[:actions]&.key?(action)
    return [spec[:node], 'view'] if Array(spec[:view]).include?(action) || READ_ACTIONS.include?(action)

    [spec[:node], 'edit']
  end

  # ── compatibilidade com as concessões antigas (grants) ────────────────
  # capability antiga → [nó, nível] (os controllers que ainda chamam
  # require_capability continuam valendo, agora lendo a árvore)
  LEGACY_CAPABILITIES = {
    'reports' => %w[relatorios view],
    'campaigns' => %w[crm.campanhas edit],
    'automations' => %w[automacoes.robos edit],
    'data_tools' => %w[automacoes.tratamento edit],
    'settings' => %w[configuracoes.integracoes edit],
    'finance' => %w[financeiro edit],
    'strategy' => %w[estrategia edit],
    'pages' => %w[marketing edit],
    # HUB: mundo Saúde (treino/dieta/corpo) concedível por pessoa
    'health' => %w[saude edit]
  }.freeze

  # item do menu do dia a dia (modelo antigo) → nó
  LEGACY_DAY_ITEMS = {
    'crm' => 'crm', 'conversation' => 'conversas', 'calls' => 'chamadas', 'agenda' => 'agenda',
    'goals' => 'metas', 'canned' => 'respostas', 'tasks' => 'tarefas', 'people' => 'pessoas',
    'academy' => 'academia'
  }.freeze
  LEGACY_DAY_DEFAULT = %w[crm conversation calls agenda goals canned].freeze

  # relatório específico (report_keys antigo) → nó filho de relatorios
  LEGACY_REPORT_KEYS = {
    'crm_dashboard' => 'relatorios.crm', 'campaigns_dashboard' => 'relatorios.campanhas',
    'traffic_funnel' => 'relatorios.funil_trafego', 'doctors' => 'relatorios.medicos',
    'agents_dashboard' => 'relatorios.agentes', 'agenda_dashboard' => 'relatorios.agenda',
    'calls_dashboard' => 'relatorios.ligacoes', 'ads' => 'relatorios.anuncios',
    'creatives' => 'marketing.criativos', 'google' => 'relatorios.google',
    'whatsapp_health' => 'relatorios.whatsapp_saude'
  }.freeze

  # ── internos ───────────────────────────────────────────────────────────
  def normalize(nodes, parent) # rubocop:disable Metrics/AbcSize
    Array(nodes).map do |raw|
      key = parent ? "#{parent}.#{raw['key']}" : raw['key'].to_s
      {
        'key' => key,
        'short' => raw['key'].to_s,
        'parent' => parent,
        'label' => raw['label'].to_s,
        'hint' => raw['hint'].to_s,
        'levels' => Array(raw['levels']).map(&:to_s).presence || %w[view],
        'default' => raw['default'].to_s.presence || (raw['admin'] ? 'none' : 'inherit'),
        'admin' => raw['admin'] == true,
        'explicit' => raw['explicit'] == true,
        'segment' => raw['segment'].to_s.presence,
        'children' => normalize(raw['children'], key)
      }
    end
  end

  def flatten(nodes)
    nodes.flat_map { |n| [n] + flatten(n['children']) }
  end

  def reload!
    @tree = nil
    @index = nil
  end
end
