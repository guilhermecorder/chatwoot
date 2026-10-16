// 🔐 rodada 334 — mapas de ACESSO EM ÁRVORE do front (ver × editar).
//
// O servidor monta `access.me = { 'crm': 'edit', 'agenda.lixeira': 'view', … }`
// para quem está logado (já resolvido: herança, papel, padrão, ramo da
// empresa). Aqui ficam só os DOIS mapas que ligam o que a pessoa vê na tela ao
// nó do catálogo (config/cevico/access_catalog.yml):
//   - ROUTE_NODES: nome da rota (vue-router) → nó, ou LISTA de nós ("qualquer
//     um libera" — ex.: Financeiro abre se a pessoa vê lançamentos OU estoque)
//   - MENU_NODES:  `name` do item do menu lateral → nó
// Rota/item que NÃO está aqui é do core do Chatwoot e segue a regra antiga
// (admin, ou a permissão do próprio core).
// (mesma escada do composable useCevicoAccess — repetida aqui para o helper
// não puxar vuex/store no guard de rota nem nos specs)
export const LEVEL_RANK = { none: 0, view: 1, edit: 2 };

export const ROUTE_NODES = {
  inicio_home: 'inicio',
  crm_board: 'crm',
  crm_journey: 'crm.jornada',
  crm_calls: 'chamadas',
  crm_appointments: 'crm.agendamentos',
  crm_appointment_alerts: 'agenda.notificacoes',
  crm_oftalmofacil: 'pacientes.oftalmofacil',
  crm_campaigns: 'crm.campanhas',
  crm_campaigns_dashboard: 'relatorios.campanhas',
  crm_forms: 'crm.formularios',
  crm_sources: 'crm.fontes',
  crm_integrations: 'configuracoes.integracoes',
  agenda_board: 'agenda',
  cevico_goals: 'metas',
  cevico_tools: 'metas.ferramentas',
  cevico_finance: [
    'financeiro',
    'financeiro.lancamentos',
    'financeiro.estoque',
    'financeiro.cac',
  ],
  cevico_strategy: 'estrategia',
  cevico_automations: [
    'automacoes',
    'automacoes.robos',
    'automacoes.fluxos',
    'automacoes.agentes_ia',
    'automacoes.regras',
    'automacoes.resultados',
    'automacoes.tratamento',
  ],
  cevico_pages_home: 'marketing.paginas',
  cevico_content_board: 'marketing.paginas',
  cevico_pages_results: 'marketing.resultados',
  cevico_pages_analytics: 'marketing.resultados',
  cevico_funnel_builder: 'marketing.funis',
  cevico_ab_center: 'marketing.funis',
  cevico_people: 'pessoas',
  tasks_board: 'tarefas',
  academy_home: 'academia',
  cevico_builder: 'inicio',
  patient_space: 'pacientes',
  cevico_business: 'empresario',
  crm_dashboard_reports: 'relatorios.crm',
  traffic_funnel_reports: 'relatorios.funil_trafego',
  doctors_reports: 'relatorios.medicos',
  agents_dashboard_reports: 'relatorios.agentes',
  agenda_dashboard_reports: 'relatorios.agenda',
  calls_dashboard_reports: 'relatorios.ligacoes',
  ads_reports: 'relatorios.anuncios',
  creatives_reports: 'marketing.criativos',
  google_dashboard_reports: 'relatorios.google',
  whatsapp_health_reports: 'relatorios.whatsapp_saude',
  whatsapp_spend_reports: 'relatorios.gasto_whatsapp',
  acquisition_cost_reports: 'financeiro.cac',
  paineis_settings_index: 'configuracoes.paineis',
  precos_settings_index: 'configuracoes.precos',
  dominio_settings_index: 'configuracoes.dominio',
  acessos_settings_index: 'configuracoes.acessos',
  empresa_settings_index: 'configuracoes.empresa',
};

export const MENU_NODES = {
  Business: 'empresario',
  Inicio: 'inicio',
  CRM: 'crm',
  Conversation: 'conversas',
  'Cevico Calls': 'chamadas',
  Agenda: 'agenda',
  'Cevico Appointments': 'crm.agendamentos',
  'Cevico Appointment Alerts': 'agenda.notificacoes',
  'Cevico Oftalmofacil': 'pacientes.oftalmofacil',
  Canned: 'respostas',
  Tasks: 'tarefas',
  Goals: 'metas',
  People: 'pessoas',
  Academy: 'academia',
  'Campanha WhatsApp': 'crm.campanhas',
  'Jornada do paciente': 'crm.jornada',
  Forms: 'crm.formularios',
  'Creatives Center': 'marketing.criativos',
  Builder: 'inicio',
  Strategy: 'estrategia',
  Finance: 'financeiro',
  // Conteúdos (pai) e filhos
  'Cevico Pages': 'marketing.paginas',
  'Pages List': 'marketing.paginas',
  'Content Planner': 'marketing.paginas',
  'Pages Results': 'marketing.resultados',
  'Pages Analytics': 'marketing.resultados',
  'Funnel Builder': 'marketing.funis',
  'AB Center': 'marketing.funis',
  // Relatórios (filhos) — o pai "Reports" aparece se algum filho aparecer
  'CRM Dashboard': 'relatorios.crm',
  'Campaigns Dashboard': 'relatorios.campanhas',
  'Traffic Funnel': 'relatorios.funil_trafego',
  'Doctors Dashboard': 'relatorios.medicos',
  'Agents Dashboard': 'relatorios.agentes',
  'Agenda Dashboard': 'relatorios.agenda',
  'Calls Dashboard': 'relatorios.ligacoes',
  'Ads Report': 'relatorios.anuncios',
  'Google Dashboard': 'relatorios.google',
  'WhatsApp Health': 'relatorios.whatsapp_saude',
  'WhatsApp Spend': 'relatorios.gasto_whatsapp',
  'Acquisition Cost': 'financeiro.cac',
  // relatórios do core do Chatwoot (a API deles só aceita admin)
  'Label Dashboard': 'relatorios.core',
  'Report Overview': 'relatorios.core',
  'Report Conversation': 'relatorios.core',
  'Reports Agent': 'relatorios.core',
  'Reports Label': 'relatorios.core',
  'Reports Inbox': 'relatorios.core',
  'Reports Team': 'relatorios.core',
  'Reports CSAT': 'relatorios.core',
  'Reports SLA': 'relatorios.core',
  'Reports Bot': 'relatorios.core',
  'All Contacts': 'relatorios.core',
  // Automações (filhos)
  'Automations Robos': 'automacoes.robos',
  'Automations Flows': 'automacoes.fluxos',
  'Automations Rules': 'automacoes.regras',
  'Automations AI Agents': 'automacoes.agentes_ia',
  'Automations AI Panel': 'automacoes.agentes_ia',
  'Automations Programming': 'automacoes.agentes_ia',
  'Automations Results': 'automacoes.resultados',
  'Automations Treatment': 'automacoes.tratamento',
  // Configurações (filhos CEVICO)
  'Integrations Hub': 'configuracoes.integracoes',
  'Settings Panels': 'configuracoes.paineis',
  'Settings Prices': 'configuracoes.precos',
  'Settings Domain': 'configuracoes.dominio',
  'Settings Access': 'configuracoes.acessos',
  'Settings Company': 'configuracoes.empresa',
};

// abas do ambiente Automações (query `tab`) → nó
export const AUTOMATION_TAB_NODES = {
  robos: 'automacoes.robos',
  fluxos: 'automacoes.fluxos',
  regras: 'automacoes.regras',
  agentes: 'automacoes.agentes_ia',
  painel_ia: 'automacoes.agentes_ia',
  programacao: 'automacoes.agentes_ia',
  resultados: 'automacoes.resultados',
  tratamento: 'automacoes.tratamento',
};

// nó do item do menu (null = item do core, sem nó)
export const menuNodeFor = name => MENU_NODES[name] ?? null;

// nós que uma rota pede (sempre lista; [] = rota sem nó no mapa)
export const routeNodesFor = routeName => {
  const nodes = ROUTE_NODES[routeName];
  if (!nodes) return [];
  return Array.isArray(nodes) ? nodes : [nodes];
};

// a pessoa pode abrir esta rota?
//   - rota sem nó no mapa → true (segue a regra antiga de quem chama)
//   - settings ainda não carregadas (accessMe vazio): admin passa (fail-open,
//     admin tem tudo), atendente NÃO passa (fail-closed)
//   - carregadas: precisa de pelo menos VER em qualquer nó da lista — vale
//     também para admin (nó que não está em `me` não existe nesta empresa,
//     ex.: cirurgias numa ótica)
export const routeAllowed = (routeName, accessMe, isAdmin = false) => {
  const nodes = routeNodesFor(routeName);
  if (!nodes.length) return true;
  if (!accessMe) return Boolean(isAdmin);
  return nodes.some(
    node => (LEVEL_RANK[accessMe[node]] ?? 0) >= LEVEL_RANK.view
  );
};
