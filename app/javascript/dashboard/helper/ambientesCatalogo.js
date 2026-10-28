// 🎨 CATÁLOGO DOS AMBIENTES (Personalização por conta, 28/10)
//
// Cada ambiente do sistema que a conta pode RENOMEAR em Configurações →
// Personalização → Nomes dos ambientes. `chave` = o `name` do item no menu
// (Sidebar.vue, label: nomeAmbiente(chave, padrão)); `rotas` = as rotas
// cujas telas mostram esse nome no cabeçalho (CevicoHero troca o título).
// O padrão é SEMPRE o texto de hoje — sem nome salvo, nada muda.
export const AMBIENTES = [
  // ── atendimento ──
  { chave: 'Inicio', padrao: 'Meu Painel', grupo: 'Atendimento', rotas: ['inicio_home'] },
  { chave: 'CRM', padrao: 'CRM', grupo: 'Atendimento', rotas: ['crm_board'] },
  { chave: 'Cevico Appointments', padrao: 'Agendamentos', grupo: 'Atendimento', rotas: ['crm_appointments'] },
  { chave: 'Cevico Appointment Alerts', padrao: 'Notificações', grupo: 'Atendimento', rotas: ['crm_appointment_alerts'] },
  { chave: 'Agenda', padrao: 'Agenda', grupo: 'Atendimento', rotas: ['agenda_board'] },
  { chave: 'Tasks', padrao: 'Tarefas', grupo: 'Atendimento', rotas: ['tasks_board'] },
  { chave: 'Cevico Calls', padrao: 'Chamadas', grupo: 'Atendimento', rotas: ['crm_calls'] },
  { chave: 'Campanha WhatsApp', padrao: 'Campanha WhatsApp', grupo: 'Atendimento', rotas: ['crm_campaigns'] },
  { chave: 'Jornada do paciente', padrao: 'Jornada do paciente', grupo: 'Atendimento', rotas: ['crm_journey'] },
  { chave: 'Forms', padrao: 'Formulários', grupo: 'Atendimento', rotas: ['crm_forms'] },
  { chave: 'Cevico Oftalmofacil', padrao: 'Oftalmofácil', grupo: 'Atendimento', rotas: ['crm_oftalmofacil'] },
  { chave: 'Canned', padrao: 'Respostas prontas', grupo: 'Atendimento', rotas: ['canned_list'] },
  // ── automações e marketing ──
  { chave: 'Automations Hub', padrao: 'Automações', grupo: 'Automações', rotas: [] },
  { chave: 'Integrations Hub', padrao: 'Integrações', grupo: 'Automações', rotas: ['crm_integrations'] },
  { chave: 'Cevico Pages', padrao: 'Conteúdos', grupo: 'Marketing', rotas: [] },
  { chave: 'Pages List', padrao: 'Páginas', grupo: 'Marketing', rotas: ['cevico_pages_home'] },
  { chave: 'Content Planner', padrao: 'Planejamento', grupo: 'Marketing', rotas: ['cevico_content_board'] },
  { chave: 'Pages Results', padrao: 'Resultados de tráfego', grupo: 'Marketing', rotas: ['cevico_pages_results'] },
  { chave: 'Pages Analytics', padrao: 'Análise de funis', grupo: 'Marketing', rotas: ['cevico_pages_analytics'] },
  { chave: 'Funnel Builder', padrao: 'Montador de Funis', grupo: 'Marketing', rotas: ['cevico_funnel_builder'] },
  { chave: 'AB Center', padrao: 'Testes A/B', grupo: 'Marketing', rotas: ['cevico_ab_center'] },
  { chave: 'Creatives Center', padrao: 'Central de Criativos', grupo: 'Marketing', rotas: ['creatives_reports'] },
  { chave: 'Builder', padrao: 'Construtor', grupo: 'Marketing', rotas: ['cevico_builder'] },
  // ── análises ──
  { chave: 'Reports', padrao: 'Relatórios', grupo: 'Análises', rotas: [] },
  { chave: 'CRM Dashboard', padrao: 'Dashboard CRM', grupo: 'Análises', rotas: ['crm_dashboard_reports'] },
  { chave: 'Campaigns Dashboard', padrao: 'Dashboard Campanhas', grupo: 'Análises', rotas: ['crm_campaigns_dashboard'] },
  { chave: 'Traffic Funnel', padrao: 'Funil de Tráfego', grupo: 'Análises', rotas: ['traffic_funnel_reports'] },
  { chave: 'Doctors Dashboard', padrao: 'Dashboard dos Médicos', grupo: 'Análises', rotas: ['doctors_reports'] },
  { chave: 'Agents Dashboard', padrao: 'Dashboard dos Agentes', grupo: 'Análises', rotas: ['agents_dashboard_reports'] },
  { chave: 'Agenda Dashboard', padrao: 'Dashboard da Agenda', grupo: 'Análises', rotas: ['agenda_dashboard_reports'] },
  { chave: 'Calls Dashboard', padrao: 'Dashboard de Ligações', grupo: 'Análises', rotas: ['calls_dashboard_reports'] },
  { chave: 'Ads Report', padrao: 'Anúncios (Meta)', grupo: 'Análises', rotas: ['ads_reports'] },
  { chave: 'Google Dashboard', padrao: 'Google (Ads + GA4)', grupo: 'Análises', rotas: ['google_dashboard_reports'] },
  { chave: 'WhatsApp Health', padrao: 'Saúde do WhatsApp', grupo: 'Análises', rotas: ['whatsapp_health_reports'] },
  { chave: 'WhatsApp Spend', padrao: 'Gasto do WhatsApp', grupo: 'Análises', rotas: ['whatsapp_spend_reports'] },
  { chave: 'Acquisition Cost', padrao: 'Financeiro & CAC', grupo: 'Análises', rotas: ['acquisition_cost_reports'] },
  { chave: 'Campaign Agent', padrao: 'Campanhas (agente)', grupo: 'Análises', rotas: ['campaign_agent_reports'] },
  // ── gestão ──
  { chave: 'Business', padrao: 'Painel do empresário', grupo: 'Gestão', rotas: ['cevico_business'] },
  { chave: 'Strategy', padrao: 'Estratégia', grupo: 'Gestão', rotas: ['cevico_strategy'] },
  { chave: 'Finance', padrao: 'Financeiro', grupo: 'Gestão', rotas: ['cevico_finance'] },
  { chave: 'Goals', padrao: 'Metas', grupo: 'Gestão', rotas: ['cevico_goals'] },
  { chave: 'People', padrao: 'Pessoas', grupo: 'Gestão', rotas: ['cevico_people'] },
  { chave: 'Academy', padrao: 'Academia', grupo: 'Gestão', rotas: ['academy_home'] },
  // ── espaços ──
  { chave: 'PatientSpace', padrao: 'Espaço do Paciente', grupo: 'Espaços', rotas: ['patient_space'] },
];

export const AMBIENTES_POR_GRUPO = AMBIENTES.reduce((acc, a) => {
  (acc[a.grupo] ||= []).push(a);
  return acc;
}, {});

const CHAVE_POR_ROTA = AMBIENTES.reduce((acc, a) => {
  a.rotas.forEach(r => {
    acc[r] = a.chave;
  });
  return acc;
}, {});

// nome da rota → chave do ambiente (CevicoHero usa para renomear o título)
export const chaveDaRota = rota => (rota ? CHAVE_POR_ROTA[String(rota)] || null : null);
