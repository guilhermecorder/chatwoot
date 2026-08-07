// Catálogo ÚNICO dos painéis do Construtor (06/08): widgets, paletas e
// tamanhos usados pelo Construtor (montagem) e pelo Meu Painel (exibição
// dos painéis salvos da conta). Mexeu aqui, mexeu nos dois.

export const CATALOG = [
  // Indicadores de agora (independem do período)
  {
    section: 'Indicadores — agora',
    key: 'open_conversations',
    label: 'Conversas abertas',
    icon: 'i-lucide-message-circle',
    kind: 'kpi',
  },
  {
    section: 'Indicadores — agora',
    key: 'unanswered',
    label: 'Aguardando resposta',
    icon: 'i-lucide-clock-alert',
    kind: 'kpi',
  },
  {
    section: 'Indicadores — agora',
    key: 'appointments_today',
    label: 'Consultas hoje',
    icon: 'i-lucide-calendar-check',
    kind: 'kpi',
  },
  {
    section: 'Indicadores — agora',
    key: 'new_contacts_30d',
    label: 'Novos leads (30 dias)',
    icon: 'i-lucide-user-plus',
    kind: 'kpi',
  },
  {
    section: 'Indicadores — agora',
    key: 'appointments_30d',
    label: 'Agendamentos (30 dias)',
    icon: 'i-lucide-calendar-plus',
    kind: 'kpi',
  },
  // Indicadores do dia (processo inteiro — mesmos números do Meu Painel)
  {
    section: 'Indicadores — hoje',
    key: 'new_leads',
    label: 'Novos leads (hoje)',
    icon: 'i-lucide-user-round-plus',
    kind: 'kpi',
  },
  {
    section: 'Indicadores — hoje',
    key: 'appointments_created',
    label: 'Consultas agendadas (hoje)',
    icon: 'i-lucide-calendar-plus-2',
    kind: 'kpi',
  },
  {
    section: 'Indicadores — hoje',
    key: 'appointments_booked',
    label: 'Marcadas na Agenda (hoje)',
    icon: 'i-lucide-notebook-pen',
    kind: 'kpi',
  },
  {
    section: 'Indicadores — hoje',
    key: 'appointments_same_day',
    label: 'Chegou e agendou no dia',
    icon: 'i-lucide-zap',
    kind: 'kpi',
  },
  {
    section: 'Indicadores — hoje',
    key: 'booking_conversion',
    label: 'Taxa de agendamento',
    icon: 'i-lucide-percent',
    kind: 'kpi',
    pct: true,
  },
  {
    section: 'Indicadores — hoje',
    key: 'show_rate',
    label: 'Comparecimento',
    icon: 'i-lucide-door-open',
    kind: 'kpi',
    pct: true,
  },
  {
    section: 'Indicadores — hoje',
    key: 'surgery_indications',
    label: 'Indicações de cirurgia',
    icon: 'i-lucide-stethoscope',
    kind: 'kpi',
  },
  {
    section: 'Indicadores — hoje',
    key: 'surgeries_booked',
    label: 'Cirurgias agendadas',
    icon: 'i-lucide-calendar-heart',
    kind: 'kpi',
  },
  {
    section: 'Indicadores — hoje',
    key: 'closing_rate',
    label: 'Fechamento pós-indicação',
    icon: 'i-lucide-handshake',
    kind: 'kpi',
    pct: true,
  },
  {
    section: 'Indicadores — hoje',
    key: 'surgeries_done',
    label: 'Cirurgias realizadas',
    icon: 'i-lucide-heart-pulse',
    kind: 'kpi',
  },
  {
    section: 'Indicadores — hoje',
    key: 'nps_satisfaction',
    label: 'NPS — satisfação',
    icon: 'i-lucide-star',
    kind: 'kpi',
    pct: true,
  },
  // Blocos vivos
  {
    section: 'Blocos vivos',
    key: 'goals',
    label: 'Metas do mês',
    icon: 'i-lucide-target',
    kind: 'goals',
  },
  {
    section: 'Blocos vivos',
    key: 'radar',
    label: 'Radar de Oportunidades',
    icon: 'i-lucide-radar',
    kind: 'radar',
  },
  {
    section: 'Blocos vivos',
    key: 'tasks',
    label: 'Tarefas esperando você',
    icon: 'i-lucide-list-checks',
    kind: 'tasks',
  },
  {
    section: 'Blocos vivos',
    key: 'next_appointments',
    label: 'Próximas consultas',
    icon: 'i-lucide-calendar-range',
    kind: 'appointments',
  },
  {
    section: 'Blocos vivos',
    key: 'response_goal',
    label: 'Minha meta de tempo',
    icon: 'i-lucide-timer',
    kind: 'response',
  },
  // Dashboards criados (atalhos vivos — clique e abra)
  {
    section: 'Dashboards',
    key: 'dash_crm',
    label: 'Dashboard CRM',
    icon: 'i-lucide-layout-dashboard',
    kind: 'dash',
    to: 'reports/crm_dashboard',
  },
  {
    section: 'Dashboards',
    key: 'dash_campanhas',
    label: 'Painel de Campanhas',
    icon: 'i-lucide-megaphone',
    kind: 'dash',
    to: 'crm/campaigns?tab=panel',
  },
  {
    section: 'Dashboards',
    key: 'dash_funil',
    label: 'Funil de Tráfego',
    icon: 'i-lucide-filter',
    kind: 'dash',
    to: 'reports/traffic_funnel',
  },
  {
    section: 'Dashboards',
    key: 'dash_medicos',
    label: 'Dashboard dos Médicos',
    icon: 'i-lucide-stethoscope',
    kind: 'dash',
    to: 'reports/doctors',
  },
  {
    section: 'Dashboards',
    key: 'dash_agentes',
    label: 'Dashboard dos Agentes',
    icon: 'i-lucide-users',
    kind: 'dash',
    to: 'reports/agents_dashboard',
  },
  {
    section: 'Dashboards',
    key: 'dash_agenda',
    label: 'Dashboard da Agenda',
    icon: 'i-lucide-calendar-days',
    kind: 'dash',
    to: 'reports/agenda_dashboard',
  },
  {
    section: 'Dashboards',
    key: 'dash_google',
    label: 'Google (Ads + GA4)',
    icon: 'i-lucide-trending-up',
    kind: 'dash',
    to: 'reports/google_dashboard',
  },
  {
    section: 'Dashboards',
    key: 'dash_ads',
    label: 'Anúncios (Meta)',
    icon: 'i-lucide-badge-dollar-sign',
    kind: 'dash',
    to: 'reports/ads',
  },
  {
    section: 'Dashboards',
    key: 'dash_whatsapp',
    label: 'Saúde do WhatsApp',
    icon: 'i-lucide-message-square-heart',
    kind: 'dash',
    to: 'reports/whatsapp_health',
  },
  {
    section: 'Dashboards',
    key: 'dash_financeiro',
    label: 'Gestão Financeira',
    icon: 'i-lucide-wallet',
    kind: 'dash',
    to: 'finance',
  },
  {
    section: 'Dashboards',
    key: 'dash_metas',
    label: 'Painel de Metas',
    icon: 'i-lucide-goal',
    kind: 'dash',
    to: 'goals',
  },
  {
    section: 'Dashboards',
    key: 'dash_estrategia',
    label: 'Painel Estratégico',
    icon: 'i-lucide-compass',
    kind: 'dash',
    to: 'strategy',
  },
  {
    section: 'Dashboards',
    key: 'dash_ia',
    label: 'Painel dos agentes de IA',
    icon: 'i-lucide-activity',
    kind: 'dash',
    to: 'cevico-automations?tab=painel_ia',
  },
];

export const CATALOG_SECTIONS = [...new Set(CATALOG.map(c => c.section))];

export const PALETTES = [
  {
    key: 'cevico',
    label: 'CEVICO',
    grads: [
      'linear-gradient(135deg, #0F5FA6, #7C3AED)',
      'linear-gradient(135deg, #B8860B, #D4A017)',
      'linear-gradient(135deg, #047857, #34D399)',
      'linear-gradient(135deg, #0284C7, #38BDF8)',
    ],
  },
  {
    key: 'dourado',
    label: 'Dourado',
    grads: [
      'linear-gradient(135deg, #92600A, #D4AF37)',
      'linear-gradient(135deg, #B8860B, #F1C40F)',
      'linear-gradient(135deg, #7C5E10, #D4A017)',
      'linear-gradient(135deg, #A16207, #FACC15)',
    ],
  },
  {
    key: 'oceano',
    label: 'Oceano',
    grads: [
      'linear-gradient(135deg, #075985, #38BDF8)',
      'linear-gradient(135deg, #0E7490, #67E8F9)',
      'linear-gradient(135deg, #1D4ED8, #93C5FD)',
      'linear-gradient(135deg, #0F766E, #5EEAD4)',
    ],
  },
  {
    key: 'verde',
    label: 'Verde vivo',
    grads: [
      'linear-gradient(135deg, #047857, #4ADE80)',
      'linear-gradient(135deg, #15803D, #86EFAC)',
      'linear-gradient(135deg, #0F766E, #2DD4BF)',
      'linear-gradient(135deg, #3F6212, #A3E635)',
    ],
  },
  {
    key: 'rosa',
    label: 'Flor del Mar',
    grads: [
      'linear-gradient(135deg, #9D174D, #F472B6)',
      'linear-gradient(135deg, #BE123C, #FDA4AF)',
      'linear-gradient(135deg, #7C3AED, #C4B5FD)',
      'linear-gradient(135deg, #C2410C, #FDBA74)',
    ],
  },
];

// tamanhos na grade de 12 colunas (P/M/G) — classes por extenso: o Tailwind
// só gera o que enxerga literalmente
export const SIZE_CLASS = {
  sm: 'sm:col-span-3',
  md: 'sm:col-span-6',
  lg: 'sm:col-span-12',
};

export const paletteByKey = key =>
  PALETTES.find(p => p.key === key) || PALETTES[0];
export const catalogMetaOf = key => CATALOG.find(c => c.key === key) || {};
