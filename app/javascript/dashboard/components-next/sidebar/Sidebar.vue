<script setup>
import { h, ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { provideSidebarContext, useSidebarResize } from './provider';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useConfig } from 'dashboard/composables/useConfig';
import { useKbd } from 'dashboard/composables/utils/useKbd';
import { useMapGetter } from 'dashboard/composables/store';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useSidebarKeyboardShortcuts } from './useSidebarKeyboardShortcuts';
import { vOnClickOutside } from '@vueuse/components';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useWindowSize, useEventListener } from '@vueuse/core';

import Button from 'dashboard/components-next/button/Button.vue';
import SidebarGroup from './SidebarGroup.vue';
import SidebarProfileMenu from './SidebarProfileMenu.vue';
import SidebarChangelogCard from './SidebarChangelogCard.vue';
import SidebarChangelogButton from './SidebarChangelogButton.vue';
import ChannelLeaf from './ChannelLeaf.vue';
import ChannelIcon from 'next/icon/ChannelIcon.vue';
import SidebarAccountSwitcher from './SidebarAccountSwitcher.vue';
import Logo from 'next/icon/Logo.vue';
import { openNovaConversa } from 'dashboard/helper/cevicoNovaConversa';
import { useCevicoAccess } from 'dashboard/composables/useCevicoAccess';
import { menuNodeFor, routeNodesFor } from 'dashboard/helper/cevicoAccess';
import {
  SIDEBAR_SORT_SECTIONS,
  getSidebarSortOptions,
  resolveSidebarSort,
  sortSidebarItems,
} from 'dashboard/helper/sidebarSort';

const props = defineProps({
  isMobileSidebarOpen: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'closeKeyShortcutModal',
  'openKeyShortcutModal',
  'showCreateAccountModal',
  'closeMobileSidebar',
]);

const { accountScopedRoute, isOnChatwootCloud } = useAccount();
const { isAdmin } = useAdmin();
const { isEnterprise } = useConfig();
const store = useStore();

// Calls run on the enterprise-only API (cloud runs enterprise); hide the entry
// on community so it doesn't lead to a dashboard/CTA the backend can't serve.
const isCallsAvailable = computed(
  () => isOnChatwootCloud.value || isEnterprise
);
const searchShortcut = useKbd([`$mod`, 'k']);
const { t } = useI18n();

const isACustomBrandedInstance = useMapGetter(
  'globalConfig/isACustomBrandedInstance'
);
const isRTL = useMapGetter('accounts/isRTL');

const { width: windowWidth } = useWindowSize();
const isMobile = computed(() => windowWidth.value < 768);

const accountId = useMapGetter('getCurrentAccountId');
const currentUserId = useMapGetter('getCurrentUserID');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const hasAdvancedAssignment = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.ADVANCED_ASSIGNMENT
  );
});

const hasConversationUnreadCounts = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.CONVERSATION_UNREAD_COUNTS
  );
});

const hasFilteredUnreadCounts = computed(() => {
  return (
    hasConversationUnreadCounts.value &&
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.UNREAD_COUNT_FOR_FILTERS
    )
  );
});

const hasDataImport = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.DATA_IMPORT
  );
});

const fetchConversationUnreadCounts = ([currentAccountId, isEnabled]) => {
  if (!currentAccountId) return;

  if (!isEnabled) {
    store.dispatch('conversationUnreadCounts/clear');
    return;
  }

  store.dispatch('conversationUnreadCounts/get');
};

const fetchSidebarSortPreferences = ([currentAccountId, userId]) => {
  if (!currentAccountId || !userId) return;
  store.dispatch('sidebarSortPreferences/initialize');
};

const toggleShortcutModalFn = show => {
  if (show) {
    emit('openKeyShortcutModal');
  } else {
    emit('closeKeyShortcutModal');
  }
};

useSidebarKeyboardShortcuts(toggleShortcutModalFn);

const expandedItem = ref(null);

const setExpandedItem = name => {
  expandedItem.value = expandedItem.value === name ? null : name;
};

const {
  sidebarWidth,
  isCollapsed,
  setSidebarWidth,
  saveWidth,
  snapToCollapsed,
  snapToExpanded,
  COLLAPSED_THRESHOLD,
} = useSidebarResize();

// On mobile, sidebar is always expanded (flyout mode)
const isEffectivelyCollapsed = computed(
  () => !isMobile.value && isCollapsed.value
);

// Resize handle logic
const isResizing = ref(false);
const startX = ref(0);
const startWidth = ref(0);

provideSidebarContext({
  expandedItem,
  setExpandedItem,
  isCollapsed: isEffectivelyCollapsed,
  sidebarWidth,
  isResizing,
});

// Get clientX from mouse or touch event
const getClientX = event =>
  event.touches ? event.touches[0].clientX : event.clientX;

const onResizeStart = event => {
  isResizing.value = true;
  startX.value = getClientX(event);
  startWidth.value = sidebarWidth.value;
  Object.assign(document.body.style, {
    cursor: 'col-resize',
    userSelect: 'none',
  });
  // Prevent default to avoid scrolling on touch
  event.preventDefault();
};

const onResizeMove = event => {
  if (!isResizing.value) return;

  const delta = isRTL.value
    ? startX.value - getClientX(event)
    : getClientX(event) - startX.value;
  setSidebarWidth(startWidth.value + delta);
};

const onResizeEnd = () => {
  if (!isResizing.value) return;

  isResizing.value = false;
  Object.assign(document.body.style, { cursor: '', userSelect: '' });

  // Snap to collapsed state if below threshold
  if (sidebarWidth.value < COLLAPSED_THRESHOLD) {
    snapToCollapsed();
  } else {
    saveWidth();
  }
};

const onResizeHandleDoubleClick = () => {
  if (isCollapsed.value) snapToExpanded();
  else snapToCollapsed();
};

// Support both mouse and touch events
useEventListener(document, 'mousemove', onResizeMove);
useEventListener(document, 'mouseup', onResizeEnd);
useEventListener(document, 'touchmove', onResizeMove, { passive: false });
useEventListener(document, 'touchend', onResizeEnd);

const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabelsOnSidebar');
const allUnreadCount = useMapGetter(
  'conversationUnreadCounts/getAllUnreadCount'
);
const getInboxUnreadCount = useMapGetter(
  'conversationUnreadCounts/getInboxUnreadCount'
);
const getLabelUnreadCount = useMapGetter(
  'conversationUnreadCounts/getLabelUnreadCount'
);
const getTeamUnreadCount = useMapGetter(
  'conversationUnreadCounts/getTeamUnreadCount'
);
const mentionsUnreadCount = useMapGetter(
  'conversationUnreadCounts/getMentionsUnreadCount'
);
const participatingUnreadCount = useMapGetter(
  'conversationUnreadCounts/getParticipatingUnreadCount'
);
const unattendedUnreadCount = useMapGetter(
  'conversationUnreadCounts/getUnattendedUnreadCount'
);
const getFolderUnreadCount = useMapGetter(
  'conversationUnreadCounts/getFolderUnreadCount'
);
const teams = useMapGetter('teams/getMyTeams');
const contactCustomViews = useMapGetter('customViews/getContactCustomViews');
const conversationCustomViews = useMapGetter(
  'customViews/getConversationCustomViews'
);
const getSidebarSectionSort = useMapGetter(
  'sidebarSortPreferences/getSectionSort'
);

onMounted(() => {
  store.dispatch('labels/get');
  store.dispatch('inboxes/get');
  store.dispatch('notifications/unReadCount');
  store.dispatch('teams/get');
  store.dispatch('attributes/get');
  store.dispatch('customViews/get', 'conversation');
  store.dispatch('customViews/get', 'contact');
});

watch([accountId, hasConversationUnreadCounts], fetchConversationUnreadCounts, {
  immediate: true,
});

watch([accountId, currentUserId], fetchSidebarSortPreferences, {
  immediate: true,
});

const hasUnreadCountsForSection = section => {
  if (section === SIDEBAR_SORT_SECTIONS.FOLDERS) {
    return hasFilteredUnreadCounts.value;
  }

  return hasConversationUnreadCounts.value;
};

const getSortOptionsForSection = section =>
  getSidebarSortOptions(section, {
    hasUnreadCounts: hasUnreadCountsForSection(section),
  });

const getSortForSection = section =>
  resolveSidebarSort(section, getSidebarSectionSort.value(section), {
    hasUnreadCounts: hasUnreadCountsForSection(section),
  });

const updateSortPreference = (section, sortBy) => {
  store.dispatch('sidebarSortPreferences/setSectionSort', {
    section,
    sortBy,
  });
};

const buildSortConfig = section => ({
  sortOptions: getSortOptionsForSection(section),
  activeSort: getSortForSection(section),
  onSortChange: sortBy => updateSortPreference(section, sortBy),
});

const sortedFolders = computed(() =>
  sortSidebarItems(conversationCustomViews.value, {
    sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.FOLDERS),
    labelKey: view => view.name,
    unreadCountKey: view => getFolderUnreadCount.value(view.id),
  })
);

const sortedTeams = computed(() =>
  sortSidebarItems(teams.value, {
    sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.TEAMS),
    labelKey: team => team.name,
    unreadCountKey: team => getTeamUnreadCount.value(team.id),
  })
);

const sortedInboxes = computed(() =>
  sortSidebarItems(inboxes.value, {
    sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.CHANNELS),
    labelKey: inbox => inbox.name,
    unreadCountKey: inbox => getInboxUnreadCount.value(inbox.id),
  })
);

const sortedLabels = computed(() =>
  sortSidebarItems(labels.value, {
    sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.LABELS),
    labelKey: label => label.title,
    unreadCountKey: label => getLabelUnreadCount.value(label.id),
  })
);

const closeMobileSidebar = () => {
  if (!props.isMobileSidebarOpen) return;
  emit('closeMobileSidebar');
};

const newReportRoutes = () => [
  {
    name: 'Reports Agent',
    label: t('SIDEBAR.REPORTS_AGENT'),
    to: accountScopedRoute('agent_reports_index'),
    activeOn: ['agent_reports_show'],
  },
  {
    name: 'Reports Label',
    label: t('SIDEBAR.REPORTS_LABEL'),
    to: accountScopedRoute('label_reports_index'),
    activeOn: ['label_reports_show'],
  },
  {
    name: 'Reports Inbox',
    label: t('SIDEBAR.REPORTS_INBOX'),
    to: accountScopedRoute('inbox_reports_index'),
    activeOn: ['inbox_reports_show'],
  },
  {
    name: 'Reports Team',
    label: t('SIDEBAR.REPORTS_TEAM'),
    to: accountScopedRoute('team_reports_index'),
    activeOn: ['team_reports_show'],
  },
];

const reportRoutes = computed(() => newReportRoutes());

// ── 🔐 CEVICO rodada 334: acessos em ÁRVORE (ver × editar) ──
// O servidor devolve `access.me = { nó: 'none'|'view'|'edit' }` já resolvido
// para quem está logado. Um item do menu aparece se o nó dele (MENU_NODES em
// helper/cevicoAccess.js) for pelo menos VER. Item sem nó = core do Chatwoot
// (segue como sempre: admin). Vale para admin também: depois de carregado,
// nó que não está em `me` (ex.: cirurgias numa ótica) some para todo mundo.
const { canAny, fill, company, loaded } = useCevicoAccess();

// itens cujo nó-pai pode estar em 'none' mas um filho liberado — abrem
// se QUALQUER nó da rota liberar (mesma regra do guard de rota)
const ITEM_ROUTE_ANY = {
  Finance: 'cevico_finance',
  'Automations Hub': 'cevico_automations',
};
// null = item sem nó (core); true/false = decidido pela árvore
const itemVisible = name => {
  const node = menuNodeFor(name);
  if (!node) return null;
  const extra = ITEM_ROUTE_ANY[name] ? routeNodesFor(ITEM_ROUTE_ANY[name]) : [];
  return canAny([node, ...extra]);
};
// atalho para o catálogo de itens: CEVICO decide pela árvore, core pelo admin
const show = name => itemVisible(name) ?? isAdmin.value;

// 🏢 vocabulário da empresa nos rótulos (ótica: "Jornada do cliente")
const jornadaLabel = computed(() => {
  const label = fill('Jornada do {{paciente}}');
  return label.includes('{{') ? 'Jornada do paciente' : label;
});
const academiaLabel = computed(
  () => `Academia ${company.value?.name ?? 'CEVICO'}`
);

// chaves usadas pelo "Personalizar menu" (ocultar por conta própria)
const FEATURE_BY_ITEM_NAME = {
  Inbox: 'inbox',
  Conversation: 'conversation',
  'Cevico Calls': 'calls',
  Captain: 'captain',
  Companies: 'companies',
  Reports: 'reports',
  CRM: 'crm',
  'Campanha WhatsApp': 'crm_campaigns',
  'Jornada do paciente': 'crm_journey',
  Tasks: 'tasks',
  Agenda: 'agenda',
  'Cevico Appointments': 'appointments',
  'Cevico Oftalmofacil': 'oftalmofacil',
  Academy: 'academy',
  Settings: 'settings',
  Goals: 'goals',
  People: 'people',
  Canned: 'canned',
};

const hiddenFeatures = ref(
  JSON.parse(localStorage.getItem('cevico_hidden_menu') ?? '[]')
);

const showCustomizeMenu = ref(false);

const toggleHiddenFeature = key => {
  const idx = hiddenFeatures.value.indexOf(key);
  if (idx === -1) hiddenFeatures.value.push(key);
  else hiddenFeatures.value.splice(idx, 1);
  localStorage.setItem(
    'cevico_hidden_menu',
    JSON.stringify(hiddenFeatures.value)
  );
};

// ── Ordem dos itens do menu (Personalizar menu, por pessoa/navegador) ──
// Padrão admin: Relatórios logo abaixo do CRM (pedido 2026-07-15).
const DEFAULT_MENU_ORDER = [
  'Business',
  'Inicio',
  'CRM',
  'Reports',
  'Strategy',
  'Finance',
  'Goals',
  'Builder',
  'People',
  'Inbox',
  'Conversation',
  'Cevico Calls',
  'Captain',
  'Companies',
  'Campanha WhatsApp',
  'Forms',
  'Tasks',
  'Agenda',
  'Cevico Appointments',
  'Cevico Oftalmofacil',
  'Cevico Pages',
  'Academy',
  'Automations Hub',
  'Settings',
];
// Padrão do ATENDENTE (pedido 2026-07-17): Meu Painel | CRM | Conversas |
// Agenda | Metas | Respostas prontas — depois os extras/concedidos.
const AGENT_MENU_ORDER = [
  'Inicio',
  'CRM',
  'Conversation',
  'Cevico Calls',
  'Agenda',
  'Cevico Appointments',
  'Cevico Oftalmofacil',
  'Goals',
  'Builder',
  'Canned',
  'Tasks',
  'People',
  'Reports',
  'Campanha WhatsApp',
  'Cevico Pages',
  'Strategy',
  'Finance',
  'Academy',
  'Automations Hub',
  'Settings',
];
const baseMenuOrder = () =>
  isAdmin.value ? DEFAULT_MENU_ORDER : AGENT_MENU_ORDER;
const menuOrder = ref(
  JSON.parse(localStorage.getItem('cevico_menu_order') ?? 'null') || null
);
const orderIndex = name => {
  const saved = (menuOrder.value || baseMenuOrder()).indexOf(name);
  if (saved !== -1) return saved;
  const fallback = baseMenuOrder().indexOf(name);
  return fallback !== -1 ? fallback + 0.5 : 999; // item novo entra perto do padrão
};

// itens do modal Personalizar menu: TODOS os itens do papel (inclusive os
// ocultos, para poder reexibir), na ordem atual, com o olhinho (a ordem é das gavetas)
const orderedMenuEntries = computed(() =>
  menuItemsForRole.value
    .map(item => ({
      name: item.name,
      label: item.label,
      icon: item.icon,
      feature: FEATURE_BY_ITEM_NAME[item.name] || null,
    }))
    .sort((a, b) => orderIndex(a.name) - orderIndex(b.name))
);

// ── Ícones em gradiente: do Início (azul CEVICO) até Configurações
// (dourado), passando pelo roxo — cada item recebe a cor interpolada
// da sua posição no menu.
const GRADIENT_STOPS = ['#0F5FA6', '#7C3AED', '#D4A017'];

const hexToRgb = hex => [
  parseInt(hex.slice(1, 3), 16),
  parseInt(hex.slice(3, 5), 16),
  parseInt(hex.slice(5, 7), 16),
];

const gradientColorAt = ratio => {
  const segments = GRADIENT_STOPS.length - 1;
  const pos = Math.min(Math.max(ratio, 0), 1) * segments;
  const i = Math.min(Math.floor(pos), segments - 1);
  const localT = pos - i;
  const from = hexToRgb(GRADIENT_STOPS[i]);
  const to = hexToRgb(GRADIENT_STOPS[i + 1]);
  const mix = from.map((c, idx) => Math.round(c + (to[idx] - c) * localT));
  return `rgb(${mix[0]}, ${mix[1]}, ${mix[2]})`;
};

// Atendente vê: todos os itens do catálogo cujo nó é pelo menos VER (a árvore
// vem do servidor, já com papel/padrão aplicados). Item com filhos aparece se
// sobrar algum filho. Configurações vira "Meu perfil" — e, se a pessoa tiver
// algum filho CEVICO liberado (Integrações, Tabela de preços…), ele entra
// junto na gaveta.
const menuItemsForRole = computed(() => {
  // admin vê tudo — menos o que o RAMO da empresa não tem (nó fora de
  // `access.me`, ex.: Oftalmofácil e Agenda cirúrgica numa ótica)
  if (isAdmin.value) {
    if (!loaded.value) return menuItems.value;
    const gone = name => itemVisible(name) === false;
    return menuItems.value.flatMap(item => {
      if (gone(item.name)) return [];
      if (!item.children) return [item];
      const kids = item.children.filter(c => !gone(c.name));
      return kids.length ? [{ ...item, children: kids }] : [];
    });
  }
  const visible = name => itemVisible(name) === true;
  const meuPerfil = {
    name: 'Settings',
    label: 'Meu perfil',
    icon: 'i-lucide-circle-user-round',
    to: accountScopedRoute('profile_settings_index'),
  };
  const out = menuItems.value.flatMap(item => {
    if (item.name === 'Settings') {
      const kids = (item.children || []).filter(c => visible(c.name));
      if (!kids.length) return [meuPerfil];
      return [
        {
          ...item,
          children: [...kids, { ...meuPerfil, name: 'Settings Profile' }],
        },
      ];
    }
    if (item.children) {
      const kids = item.children.filter(c => visible(c.name));
      return kids.length ? [{ ...item, children: kids }] : [];
    }
    return visible(item.name) ? [item] : [];
  });
  if (!out.some(i => i.name === 'Settings')) out.push(meuPerfil);
  return out;
});

// ── 🗄️ GAVETAS DO MENU (pedido 20/09, "personal organizer"): cada gaveta
// responde a UMA pergunta e a ordem dentro dela segue a filosofia da casa —
// otimizar o funil etapa por etapa (atrair → captar → converter → atender →
// cirurgia → medir). Só uma gaveta fica aberta por vez (accordion) e a do
// item ativo abre sozinha. Entradas de uma gaveta:
//   'Nome'                     item de 1º nível (folha, ou subgrupo se tiver filhos)
//   'Pai > Filho'              puxa UM filho de um item com filhos, como folha
//   'Pai > *'                  o que sobrou dos filhos do Pai (nada se perde)
//   { rest: 'Pai', … }         o que sobrou, como subgrupo fechável
// Item que não couber em gaveta nenhuma cai em "Mais" — nunca desaparece.
const MENU_LAYOUT = [
  { solo: 'Business' }, // 👑 27/09: a mesa do dono, acima de tudo (só admin)
  { solo: 'Inicio' }, // como está meu dia?
  {
    name: 'group:atendimento', // quem eu atendo agora?
    // 23/09: laranja (o verde ficava repetido 3x com Conversas e Chamadas)
    color: '#ff9f0a',
    label: 'Atendimento',
    icon: 'i-lucide-headset',
    items: [
      'Conversation',
      'Cevico Calls',
      'Agenda',
      'Cevico Appointments',
      'Cevico Oftalmofacil',
      'Canned',
    ],
  },
  { solo: 'CRM' }, // em que ponto está cada paciente?
  { solo: 'Tasks' }, // avisa por notificação — fica à mão
  {
    name: 'group:automacoes', // o que trabalha sozinho por mim?
    color: '#5856d6',
    label: 'Automações',
    icon: 'i-lucide-workflow',
    items: [
      'Jornada do paciente',
      'Automations Hub > Automations Robos',
      'Campanha WhatsApp',
      'Automations Hub > Automations AI Agents',
      'Automations Hub > Automations AI Panel',
      'Automations Hub > Automations Flows',
      'Automations Hub > Automations Rules',
      'Automations Hub > Automations Programming',
      'Automations Hub > Automations Results',
      'Automations Hub > Automations Treatment',
      'Automations Hub > *',
    ],
  },
  {
    name: 'group:marketing', // como eu atraio e crio? (gaveta dos parceiros)
    color: '#ff9f0a',
    label: 'Marketing',
    icon: 'i-lucide-megaphone',
    items: [
      'Creatives Center', // anúncios: o topo do funil
      'Cevico Pages > Pages List', // onde o lead chega
      'Forms', // captação
      'Cevico Pages > Funnel Builder', // conversão
      'Cevico Pages > AB Center',
      'Cevico Pages > Content Planner', // conteúdo orgânico
      'Cevico Pages > Pages Analytics', // medir
      'Cevico Pages > Pages Results',
      'Cevico Pages > *', // SEO, vídeo com IA… entram aqui quando nascerem
    ],
  },
  {
    name: 'group:analises', // e os números? (na ordem do funil)
    color: '#0a84ff',
    label: 'Análises',
    icon: 'i-lucide-chart-line',
    items: [
      'Reports > Ads Report', // anúncio → lead
      'Reports > Google Dashboard',
      'Reports > CRM Dashboard', // lead → consulta → cirurgia
      'Reports > Campaigns Dashboard', // o que empurra as etapas
      'Reports > Agenda Dashboard', // consulta marcada → compareceu
      'Reports > Doctors Dashboard', // consulta → indicação → fechou
      'Reports > Agents Dashboard', // a equipe no processo
      'Reports > Calls Dashboard',
      'Reports > WhatsApp Health', // o canal está saudável?
      'Reports > WhatsApp Spend', // 💸 quanto a Meta cobra (item 303, só admin)
      'Reports > Acquisition Cost', // 💰 quanto custa cada paciente operado (item 318)
      'Reports > Traffic Funnel', // por último (pedido dele 20/09)
      {
        rest: 'Reports',
        name: 'Chatwoot Reports',
        label: 'Outros relatórios',
        icon: 'i-lucide-file-chart-column',
      },
    ],
  },
  {
    name: 'group:gestao', // para onde vai a clínica?
    color: '#64d2ff',
    label: 'Gestão',
    icon: 'i-lucide-compass',
    items: ['Strategy', 'Goals', 'Finance', 'People', 'Academy'],
  },
  {
    name: 'group:config', // como isso funciona por dentro? (um nível só)
    color: '#8e8e93',
    label: 'Configurações',
    icon: 'i-lucide-settings',
    items: [
      'Settings > Integrations Hub',
      'Settings > Settings Account Settings',
      'Settings > Settings Company', // 🏢 rodada 334: identidade da empresa
      'Settings > Settings Domain',
      'Settings > Settings Panels',
      'Builder', // construtor dos painéis por pessoa, ao lado de Painéis
      'Settings > Settings Prices',
      'Settings > Settings Agents',
      'Settings > Settings Access', // 🔐 rodada 334: acessos e papéis
      'Settings > Settings Teams',
      'Settings > Settings Custom Roles',
      'Settings > Settings Inboxes',
      'Settings > Settings Templates',
      'Settings > Settings Labels',
      'Settings > Settings Custom Attributes',
      'Settings > Settings Canned Responses',
      'Settings > Settings Macros',
      'Settings > Settings Agent Bots',
      'Settings > Conversation Workflow',
      'Settings > Settings Sla',
      'Settings > *', // auditoria, segurança, cobrança, distribuição…
      'Captain',
      'Companies',
      'Integrations Hub',
      'Settings', // atendente: "Meu perfil" (folha)
    ],
  },
];
// fora do menu: o "Calls" do Chatwoot (enterprise; o nosso é "Cevico Calls") e a
// "Caixa de entrada" (pedido 20/09 — o atendimento acontece pelas Conversas;
// a tela segue viva pela URL e em Configurações → Caixas)
const OMITTED_FROM_MENU = ['Calls', 'Inbox'];
// contadores dos itens que viram folha (folha não lê getterKeys)
const leafBadge = item => {
  const key = item.getterKeys && item.getterKeys.count;
  if (!key) return 0;
  const value = store.getters[key];
  return typeof value === 'number' ? value : 0;
};
// azulejos coloridos por item (como os ícones dos Ajustes do iPhone)
const TILE_COLORS = {
  Business: '#d4af37', // 👑 dourado da marca
  Conversation: '#34c759',
  'Cevico Calls': '#5856d6', // 23/09: índigo — a gaveta Atendimento alterna laranja/verde/índigo/vermelho/azul
  Inbox: '#007aff',
  Agenda: '#ff3b30',
  'Cevico Appointments': '#0a84ff',
  'Cevico Oftalmofacil': '#64d2ff',
  Tasks: '#ff9500',
  Canned: '#5ac8fa',
  CRM: '#af52de',
  'Jornada do paciente': '#ff2d55',
  'Campanha WhatsApp': '#25d366',
  Forms: '#ffcc00',
  'Automations Hub': '#5856d6',
  Reports: '#0a84ff',
  Goals: '#ff9f0a',
  Strategy: '#64d2ff',
  Finance: '#30d158',
  People: '#ff375f',
  Academy: '#bf5af2',
  'Cevico Pages': '#0a84ff',
  Builder: '#ff9f0a',
  Captain: '#5e5ce6',
  Companies: '#8e8e93',
  Settings: '#8e8e93',
  'Integrations Hub': '#64d2ff',
  Inicio: '#34c759',
  // Marketing e Análises (gavetas 20/09)
  'Creatives Center': '#ff9f0a',
  'Pages List': '#0a84ff',
  'Content Planner': '#34c759',
  'Pages Results': '#30d158',
  'Pages Analytics': '#5ac8fa',
  'Funnel Builder': '#ff3b30',
  'AB Center': '#af52de',
  'Traffic Funnel': '#ff9f0a',
  'Ads Report': '#0a84ff',
  'Google Dashboard': '#34c759',
  'CRM Dashboard': '#af52de',
  'Campaigns Dashboard': '#25d366',
  'Agenda Dashboard': '#ff3b30',
  'Doctors Dashboard': '#5ac8fa',
  'Agents Dashboard': '#ff2d55',
  'Calls Dashboard': '#30d158',
  'WhatsApp Health': '#64d2ff',
  'WhatsApp Spend': '#25d366',
  'Chatwoot Reports': '#8e8e93',
  // Configurações (pedido 20/09: cada linha com a sua cor, nada de azulejo cinza)
  'Settings Account Settings': '#0a84ff',
  'Settings Company': '#0a84ff', // 🏢 rodada 334
  'Settings Access': '#ff3b30', // 🔐 rodada 334
  'Settings Profile': '#8e8e93',
  'Settings Domain': '#30d158',
  'Settings Panels': '#af52de',
  'Settings Prices': '#34c759',
  'Settings Agents': '#ff9f0a',
  'Settings Teams': '#5856d6',
  'Settings Agent Assignment': '#ff2d55',
  'Settings Inboxes': '#007aff',
  'Settings Templates': '#25d366',
  'Settings Labels': '#ffcc00',
  'Settings Custom Attributes': '#64d2ff',
  'Settings Agent Bots': '#bf5af2',
  'Settings Macros': '#ff9500',
  'Settings Canned Responses': '#5ac8fa',
  'Settings Audit Logs': '#a2845e',
  'Settings Custom Roles': '#ff3b30',
  'Settings Sla': '#ff9f0a',
  'Conversation Workflow': '#5e5ce6',
  'Settings Security': '#34c759',
  'Settings Billing': '#30d158',
  // Automações
  'Automations Robos': '#5856d6',
  'Automations Flows': '#0a84ff',
  'Automations Rules': '#ff9f0a',
  'Automations AI Agents': '#af52de',
  'Automations AI Panel': '#30d158',
  'Automations Programming': '#ff3b30',
  'Automations Results': '#34c759',
  'Automations Treatment': '#64d2ff',
};
const tileColor = name => TILE_COLORS[name] || '#8e8e93';
// filhos de subgrupo (Configurações, Automações, Relatórios…): cada um com a
// sua cor — sem isso o azulejo herdava a cor do texto e saía cinza
const NESTED_CYCLE = [
  '#0a84ff',
  '#34c759',
  '#ff9f0a',
  '#af52de',
  '#ff3b30',
  '#5ac8fa',
  '#ff2d55',
  '#30d158',
  '#5856d6',
  '#ffcc00',
  '#64d2ff',
  '#bf5af2',
];
const colorChildren = children =>
  (children || []).map((c, i) => ({
    ...c,
    iconColor: TILE_COLORS[c.name] || NESTED_CYCLE[i % NESTED_CYCLE.length],
  }));
const toChild = item =>
  item.children
    ? {
        ...item,
        children: colorChildren(item.children),
        collapsible: true,
        iconColor: tileColor(item.name),
      }
    : {
        name: item.name,
        label: item.label,
        icon: item.icon,
        iconColor: tileColor(item.name),
        to: item.to,
        activeOn: item.activeOn || [],
        badgeCount: leafBadge(item),
      };
const groupedMenuItems = computed(() => {
  const items = visibleMenuItems.value.filter(
    i => !OMITTED_FROM_MENU.includes(i.name)
  );
  const findItem = name => items.find(i => i.name === name);
  const usedTop = new Set();
  const usedChild = new Map(); // pai → Set(filhos já colocados em alguma gaveta)
  const takeChild = (parentName, childName) => {
    if (!usedChild.has(parentName)) usedChild.set(parentName, new Set());
    usedChild.get(parentName).add(childName);
  };
  const remainingChildren = parent =>
    (parent.children || []).filter(
      c => !usedChild.get(parent.name)?.has(c.name)
    );
  const takeAll = parent => {
    const rest = remainingChildren(parent);
    rest.forEach(c => takeChild(parent.name, c.name));
    return rest;
  };
  const resolve = entry => {
    if (typeof entry === 'object') {
      // { rest: 'Pai' } → o que sobrou do Pai, como subgrupo fechável
      const parent = findItem(entry.rest);
      if (!parent || !parent.children) return [];
      usedTop.add(parent.name);
      const rest = takeAll(parent);
      return rest.length
        ? [
            toChild({
              name: entry.name,
              label: entry.label,
              icon: entry.icon,
              children: rest,
            }),
          ]
        : [];
    }
    const [parentName, childName] = entry.split(' > ');
    if (childName) {
      const parent = findItem(parentName);
      if (!parent || !parent.children) return [];
      usedTop.add(parent.name);
      if (childName === '*') return takeAll(parent).map(toChild);
      const child = parent.children.find(c => c.name === childName);
      if (!child || usedChild.get(parent.name)?.has(childName)) return [];
      takeChild(parent.name, childName);
      return [toChild(child)];
    }
    const item = findItem(entry);
    if (!item || usedTop.has(item.name)) return [];
    usedTop.add(item.name);
    if (!item.children) return [toChild(item)];
    const rest = takeAll(item);
    return rest.length ? [toChild({ ...item, children: rest })] : [];
  };
  const out = [];
  MENU_LAYOUT.forEach(g => {
    if (g.solo) {
      const item = findItem(g.solo);
      if (!item) return;
      usedTop.add(item.name);
      out.push({ ...item, iconColor: tileColor(item.name) });
      return;
    }
    const children = g.items.flatMap(resolve);
    if (!children.length) return;
    out.push({
      name: g.name,
      label: g.label,
      icon: g.icon,
      iconColor: g.color,
      children,
    });
  });
  // rede de segurança: item sem gaveta, ou filho que sobrou de um pai já
  // usado, cai em "Mais" — nada desaparece do menu
  const rest = items.filter(i => !usedTop.has(i.name)).map(toChild);
  items
    .filter(i => i.children && usedTop.has(i.name))
    .forEach(p => {
      const left = takeAll(p);
      if (left.length) rest.push(toChild({ ...p, children: left }));
    });
  if (rest.length)
    out.push({
      name: 'group:mais',
      label: 'Mais',
      icon: 'i-lucide-ellipsis',
      iconColor: '#8e8e93',
      children: rest,
    });
  return out;
});

const visibleMenuItems = computed(() => {
  const items = menuItemsForRole.value
    .filter(item => {
      const key = FEATURE_BY_ITEM_NAME[item.name];
      if (!key) return true;
      // Caixa de Entrada é visão de admin — atendimento acontece pelo CRM
      if (key === 'inbox' && !isAdmin.value) return false;
      return !hiddenFeatures.value.includes(key);
    })
    // ordem escolhida no Personalizar menu (padrão por papel)
    .sort((a, b) => orderIndex(a.name) - orderIndex(b.name));
  const denominator = Math.max(items.length - 1, 1);
  return items.map((item, index) => ({
    ...item,
    iconColor: gradientColorAt(index / denominator),
  }));
});

onMounted(() => {
  // carrega agent_permissions (e presets do CRM) para filtrar o menu
  store.dispatch('crm/fetchSettings').catch(() => {});
  // carrega tarefas para o aviso de prazo na sidebar (badge em Tarefas)
  store.dispatch('tasks/fetch').catch(() => {});
  // badge do Radar de Oportunidades no "Meu Painel" — atualiza a cada 5 min
  radarBadgeTimer = setInterval(
    () => {
      store.dispatch('crm/fetchSettings').catch(() => {});
    },
    5 * 60 * 1000
  );
});

let radarBadgeTimer = null;
onUnmounted(() => clearInterval(radarBadgeTimer));
// ──────────────────────────────────────────────────────────────────────────

// abas do ambiente Automações (uma por nó automacoes.*; rodada 334)
const automationChildren = computed(() =>
  [
    {
      name: 'Automations Robos',
      label: 'Robôs de follow-up',
      icon: 'i-lucide-bot',
      tab: 'robos',
    },
    // 🗺️ item 170: fluxograma de cada agente/automação com o estado ao vivo
    {
      name: 'Automations Flows',
      label: 'Fluxos',
      icon: 'i-lucide-git-branch',
      tab: 'fluxos',
    },
    {
      name: 'Automations Rules',
      label: 'Regras da caixa',
      icon: 'i-lucide-repeat',
      tab: 'regras',
    },
    {
      name: 'Automations AI Agents',
      label: 'Agentes de IA',
      icon: 'i-lucide-sparkles',
      tab: 'agentes',
    },
    // item 85: o que cada agente de IA está fazendo + custos
    {
      name: 'Automations AI Panel',
      label: 'Painel dos agentes',
      icon: 'i-lucide-activity',
      tab: 'painel_ia',
    },
    {
      name: 'Automations Programming',
      label: 'Modo Programação',
      icon: 'i-lucide-zap',
      tab: 'programacao',
    },
    {
      name: 'Automations Results',
      label: 'Resultados',
      icon: 'i-lucide-bar-chart-3',
      tab: 'resultados',
    },
    {
      name: 'Automations Treatment',
      label: 'Tratamento de dados',
      icon: 'i-lucide-database',
      tab: 'tratamento',
    },
  ]
    .filter(c => show(c.name))
    .map(c => ({
      name: c.name,
      label: c.label,
      icon: c.icon,
      to: accountScopedRoute('cevico_automations', {}, { tab: c.tab }),
    }))
);

const menuItems = computed(() => {
  return [
    // 👑 Painel do empresário (27/09): ambiente próprio acima do Meu Painel — só admin
    ...(show('Business')
      ? [
          {
            name: 'Business',
            label: 'Painel do empresário',
            icon: 'i-lucide-crown',
            to: accountScopedRoute('cevico_business'),
          },
        ]
      : []),
    // Meu Painel: boas-vindas + resumo do dia + avisos do Radar
    // (badge = pacientes quentes sem atendimento detectados pelo Radar)
    {
      name: 'Inicio',
      label: 'Meu Painel',
      icon: 'i-lucide-house',
      to: accountScopedRoute('inicio_home'),
      getterKeys: { count: 'crm/getRadarAlertCount' },
      countVariant: 'radar', // verde dopamine, igual ao badge — pulsando
    },
    // CRM em primeiro — é o hub de atendimento
    {
      name: 'CRM',
      label: t('SIDEBAR.CRM'),
      icon: 'i-lucide-rocket',
      to: accountScopedRoute('crm_board'),
    },
    {
      name: 'Inbox',
      label: t('SIDEBAR.INBOX'),
      icon: 'i-lucide-inbox',
      to: accountScopedRoute('inbox_view'),
      activeOn: ['inbox_view', 'inbox_view_conversation'],
      getterKeys: {
        count: 'notifications/getUnreadCount',
      },
    },
    {
      name: 'Conversation',
      label: t('SIDEBAR.CONVERSATIONS'),
      icon: 'i-lucide-message-circle',
      // CEVICO 18/07: menu de conversas ENXUTO — só o principal.
      // Caixas viraram pílulas no topo e estágio/etiqueta viraram filtros
      // DENTRO do Conversas; pastas/times/canais/etiquetas saíram do menu.
      badgeCount: allUnreadCount.value,
      activeOn: [
        'inbox_conversation',
        'conversation_through_unattended',
        'conversations_through_folders',
        'conversations_through_team',
        'conversation_through_inbox',
        'conversations_through_label',
      ],
      to: accountScopedRoute('home'),
    },
    {
      name: 'Captain',
      icon: 'i-woot-captain',
      label: t('SIDEBAR.CAPTAIN'),
      activeOn: ['captain_assistants_create_index'],
      children: [
        {
          name: 'Overview',
          label: t('SIDEBAR.CAPTAIN_OVERVIEW'),
          activeOn: ['captain_assistants_overview_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_overview_index',
          }),
        },
        {
          name: 'FAQs',
          label: t('SIDEBAR.CAPTAIN_RESPONSES'),
          activeOn: [
            'captain_assistants_responses_index',
            'captain_assistants_faq_suggestions',
          ],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_responses_index',
          }),
        },
        {
          name: 'Documents',
          label: t('SIDEBAR.CAPTAIN_DOCUMENTS'),
          activeOn: ['captain_assistants_documents_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_documents_index',
          }),
        },
        {
          name: 'Scenarios',
          label: t('SIDEBAR.CAPTAIN_SCENARIOS'),
          activeOn: ['captain_assistants_scenarios_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_scenarios_index',
          }),
        },
        {
          name: 'Playground',
          label: t('SIDEBAR.CAPTAIN_PLAYGROUND'),
          activeOn: ['captain_assistants_playground_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_playground_index',
          }),
        },
        {
          name: 'Inboxes',
          label: t('SIDEBAR.CAPTAIN_INBOXES'),
          activeOn: ['captain_assistants_inboxes_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_inboxes_index',
          }),
        },
        {
          name: 'Tools',
          label: t('SIDEBAR.CAPTAIN_TOOLS'),
          activeOn: ['captain_tools_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_tools_index',
          }),
        },
        {
          name: 'Settings',
          label: t('SIDEBAR.CAPTAIN_SETTINGS'),
          activeOn: [
            'captain_assistants_settings_index',
            'captain_assistants_settings_system_index',
            'captain_assistants_settings_audience_index',
            'captain_assistants_settings_schedule_index',
            'captain_assistants_guidelines_index',
            'captain_assistants_guardrails_index',
          ],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_settings_index',
          }),
        },
      ],
    },
    ...(isCallsAvailable.value
      ? [
          {
            name: 'Calls',
            label: t('SIDEBAR.CALLS'),
            icon: 'i-lucide-phone',
            to: accountScopedRoute('calls_dashboard_index'),
            activeOn: ['calls_dashboard_index'],
          },
        ]
      : []),
    {
      name: 'Companies',
      label: t('SIDEBAR.COMPANIES'),
      icon: 'i-lucide-building-2',
      children: [
        {
          name: 'All Companies',
          label: t('SIDEBAR.ALL_COMPANIES'),
          to: accountScopedRoute(
            'companies_dashboard_index',
            {},
            { page: 1, search: undefined }
          ),
          activeOn: ['companies_dashboard_index', 'companies_dashboard_show'],
        },
      ],
    },
    // 🎬 Central de Criativos: 1º item da gaveta Marketing (pedido 20/09)
    ...(show('Creatives Center')
      ? [
          {
            name: 'Creatives Center',
            label: 'Central de Criativos',
            icon: 'i-lucide-clapperboard',
            to: accountScopedRoute('creatives_reports'),
          },
        ]
      : []),
    {
      name: 'Reports',
      label: t('SIDEBAR.REPORTS'),
      icon: 'i-lucide-chart-spline',
      children: [
        // dashboards CEVICO — cada um com o seu nó em relatorios.* (rodada
        // 334): aparece para quem tem pelo menos VER naquele relatório
        ...[
          {
            name: 'CRM Dashboard',
            icon: 'i-lucide-kanban',
            label: 'Dashboard CRM',
            route: 'crm_dashboard_reports',
          },
          {
            name: 'Campaigns Dashboard',
            icon: 'i-lucide-send',
            label: 'Dashboard Campanhas',
            route: 'crm_campaigns_dashboard',
          },
          {
            name: 'Traffic Funnel',
            icon: 'i-lucide-filter',
            label: 'Funil de Tráfego',
            route: 'traffic_funnel_reports',
          },
          {
            name: 'Doctors Dashboard',
            icon: 'i-lucide-stethoscope',
            label: 'Dashboard dos Médicos',
            route: 'doctors_reports',
          },
          {
            name: 'Agents Dashboard',
            icon: 'i-lucide-headset',
            label: 'Dashboard dos Agentes',
            route: 'agents_dashboard_reports',
          },
          {
            name: 'Agenda Dashboard',
            icon: 'i-lucide-calendar-days',
            label: 'Dashboard da Agenda',
            route: 'agenda_dashboard_reports',
          },
          {
            name: 'Calls Dashboard',
            icon: 'i-lucide-phone',
            label: 'Dashboard de Ligações',
            route: 'calls_dashboard_reports',
          },
          {
            name: 'Ads Report',
            icon: 'i-lucide-megaphone',
            label: 'Anúncios (Meta)',
            route: 'ads_reports',
          },
          {
            name: 'Google Dashboard',
            icon: 'i-lucide-search',
            label: 'Google (Ads + GA4)',
            route: 'google_dashboard_reports',
          },
          {
            name: 'WhatsApp Health',
            icon: 'i-lucide-heart-pulse',
            label: 'Saúde do WhatsApp',
            route: 'whatsapp_health_reports',
          },
          {
            // 💸 item 303: dinheiro — nó só de admin
            name: 'WhatsApp Spend',
            icon: 'i-lucide-receipt',
            label: 'Gasto do WhatsApp',
            route: 'whatsapp_spend_reports',
          },
          {
            // 💰 item 318: CAC e retorno — nó financeiro.cac
            name: 'Acquisition Cost',
            icon: 'i-lucide-piggy-bank',
            label: 'Financeiro & CAC',
            route: 'acquisition_cost_reports',
          },
        ]
          .filter(r => show(r.name))
          .map(r => ({
            name: r.name,
            label: r.label,
            icon: r.icon,
            to: accountScopedRoute(r.route),
          })),
        // relatórios do core do Chatwoot — a API deles só aceita admin
        // (nó relatorios.core, marcado como admin no catálogo)
        ...(show('Report Overview')
          ? [
              {
                name: 'Label Dashboard',
                label: t('SIDEBAR.LABEL_DASHBOARD'),
                to: accountScopedRoute('label_dashboard'),
              },
              {
                name: 'Report Overview',
                label: t('SIDEBAR.REPORTS_OVERVIEW'),
                to: accountScopedRoute('account_overview_reports'),
              },
              {
                name: 'Report Conversation',
                label: t('SIDEBAR.REPORTS_CONVERSATION'),
                to: accountScopedRoute('conversation_reports'),
              },
              ...reportRoutes.value,
              {
                name: 'Reports CSAT',
                label: t('SIDEBAR.CSAT'),
                to: accountScopedRoute('csat_reports'),
              },
              {
                name: 'Reports SLA',
                label: t('SIDEBAR.REPORTS_SLA'),
                to: accountScopedRoute('sla_reports'),
              },
              {
                name: 'Reports Bot',
                label: t('SIDEBAR.REPORTS_BOT'),
                to: accountScopedRoute('bot_reports'),
              },
              {
                name: 'All Contacts',
                label: t('SIDEBAR.CONTACTS'),
                to: accountScopedRoute(
                  'contacts_dashboard_index',
                  {},
                  { page: 1, search: undefined }
                ),
                activeOn: ['contacts_dashboard_index', 'contacts_edit'],
              },
            ]
          : []),
      ],
    },
    // 📞 ambiente Chamadas (item 176): ao vivo para todo mundo + histórico
    {
      name: 'Cevico Calls',
      label: 'Chamadas',
      icon: 'i-lucide-phone-call',
      to: accountScopedRoute('crm_calls'),
    },
    {
      name: 'Campanha WhatsApp',
      label: 'Campanha WhatsApp',
      icon: 'i-lucide-megaphone',
      to: accountScopedRoute('crm_campaigns'),
    },
    // 🗺️ Mensagens da jornada (item 168) — rótulo no vocabulário da empresa
    {
      name: 'Jornada do paciente',
      label: jornadaLabel.value,
      icon: 'i-lucide-route',
      to: accountScopedRoute('crm_journey'),
    },
    // Formulários: gaveta Marketing — nó crm.formularios
    ...(show('Forms')
      ? [
          {
            name: 'Forms',
            label: 'Formulários',
            icon: 'i-lucide-clipboard-list',
            to: accountScopedRoute('crm_forms'),
          },
        ]
      : []),
    // Painel Estratégico — nó estrategia
    ...(show('Strategy')
      ? [
          {
            name: 'Strategy',
            label: 'Estratégia',
            icon: 'i-lucide-compass',
            to: accountScopedRoute('cevico_strategy'),
          },
        ]
      : []),
    // Gestão Financeira — nó financeiro (ou qualquer filho)
    ...(show('Finance')
      ? [
          {
            name: 'Finance',
            label: 'Financeiro',
            icon: 'i-lucide-wallet',
            to: accountScopedRoute('cevico_finance'),
          },
        ]
      : []),
    // Respostas prontas (mensagens rápidas do "/") — atalho do time;
    // admin já chega por Configurações
    ...(isAdmin.value
      ? []
      : [
          {
            name: 'Canned',
            label: 'Respostas prontas',
            icon: 'i-lucide-message-square-quote',
            to: accountScopedRoute('canned_list'),
          },
        ]),
    {
      name: 'Tasks',
      label: 'Tarefas',
      icon: 'i-lucide-list-checks',
      to: accountScopedRoute('tasks_board'),
      getterKeys: { count: 'tasks/getAlertCount' },
      countVariant: 'gold', // tarefa esperando você — dourado brilhante
    },
    {
      name: 'Agenda',
      label: 'Agenda',
      icon: 'i-lucide-calendar-days',
      to: accountScopedRoute('agenda_board'),
    },
    // 📅 ambiente Agendamentos (item 200): monitorar marcadas/remarcadas/canceladas
    {
      name: 'Cevico Appointments',
      label: 'Agendamentos',
      icon: 'i-lucide-calendar-check',
      to: accountScopedRoute('crm_appointments'),
    },
    // 🏥 ambiente Oftalmofácil (item 229): o hub de parceiros dentro do sistema
    {
      name: 'Cevico Oftalmofacil',
      label: 'Oftalmofácil',
      icon: 'i-lucide-hospital',
      to: accountScopedRoute('crm_oftalmofacil'),
    },
    {
      name: 'Cevico Pages',
      label: 'Conteúdos',
      icon: 'i-lucide-panels-top-left',
      children: [
        {
          name: 'Pages List',
          label: 'Páginas',
          icon: 'i-lucide-panels-top-left',
          to: accountScopedRoute('cevico_pages_home'),
        },
        {
          name: 'Content Planner',
          label: 'Planejamento',
          icon: 'i-lucide-kanban',
          to: accountScopedRoute('cevico_content_board'),
        },
        // Resultados (marketing.resultados) e funis/testes A/B
        // (marketing.funis) — cada um pelo seu nó (rodada 334)
        ...[
          {
            // 📈 origem (Google Ads/SEO/Meta) → leads → cirurgias
            name: 'Pages Results',
            label: 'Resultados de tráfego',
            icon: 'i-lucide-trending-up',
            to: accountScopedRoute('cevico_pages_results'),
          },
          {
            name: 'Pages Analytics',
            label: 'Análise de funis',
            icon: 'i-lucide-chart-line',
            to: accountScopedRoute('cevico_pages_analytics'),
          },
          {
            // 🌪 item 60: fontes de captação → páginas → WhatsApp
            name: 'Funnel Builder',
            label: 'Montador de Funis',
            icon: 'i-lucide-tornado',
            to: accountScopedRoute('cevico_funnel_builder'),
          },
          {
            name: 'AB Center',
            label: 'Testes A/B',
            icon: 'i-lucide-flask-conical',
            to: accountScopedRoute('cevico_ab_center'),
          },
        ].filter(c => show(c.name)),
      ],
    },
    // Pessoas: DISC, desenvolvimento e feedbacks (cada um vê o seu)
    {
      name: 'People',
      label: 'Pessoas',
      icon: 'i-lucide-heart-handshake',
      to: accountScopedRoute('cevico_people'),
    },
    // Painel de Metas: admin define, time acompanha
    {
      name: 'Goals',
      label: 'Metas',
      icon: 'i-lucide-target',
      to: accountScopedRoute('cevico_goals'),
    },
    {
      // 🧲 painel personalizado por pessoa (item 57)
      name: 'Builder',
      label: 'Construtor',
      icon: 'i-lucide-magnet',
      to: accountScopedRoute('cevico_builder'),
    },
    {
      name: 'Academy',
      label: academiaLabel.value,
      icon: 'i-lucide-graduation-cap',
      to: accountScopedRoute('academy_home'),
    },
    // Automações — cada aba pelo seu nó em automacoes.* (rodada 334); o
    // pai aparece se sobrar alguma aba
    ...(automationChildren.value.length
      ? [
          {
            name: 'Automations Hub',
            label: 'Automações',
            icon: 'i-lucide-workflow',
            children: automationChildren.value,
          },
        ]
      : []),
    {
      name: 'Settings',
      label: t('SIDEBAR.SETTINGS'),
      icon: 'i-lucide-settings',
      children: [
        // Integrações UNIFICADAS dentro de Configurações (item 78):
        // central CEVICO (Meta/Google/Claude/Sheets/n8n) + aplicativos nativos
        ...(show('Integrations Hub')
          ? [
              {
                name: 'Integrations Hub',
                label: 'Integrações',
                icon: 'i-lucide-plug',
                to: accountScopedRoute('crm_integrations'),
              },
            ]
          : []),
        {
          name: 'Settings Account Settings',
          label: t('SIDEBAR.ACCOUNT_SETTINGS'),
          icon: 'i-lucide-briefcase',
          to: accountScopedRoute('general_settings_index'),
        },
        // 🏢 rodada 334: quem é a empresa (nome, ramo, vocabulário, unidades)
        ...(show('Settings Company')
          ? [
              {
                name: 'Settings Company',
                label: 'Identidade da empresa',
                icon: 'i-lucide-building-2',
                to: accountScopedRoute('empresa_settings_index'),
              },
            ]
          : []),
        // Domínio, Painéis e Tabela de preços — cada um pelo seu nó em
        // configuracoes.* (rodada 334)
        ...[
          {
            // Domínio público das páginas/formulários
            name: 'Settings Domain',
            label: 'Domínio',
            icon: 'i-lucide-globe',
            route: 'dominio_settings_index',
          },
          {
            // Responsável por painel do Meu Painel (pedido 20/08)
            name: 'Settings Panels',
            label: 'Painéis',
            icon: 'i-lucide-layout-dashboard',
            route: 'paineis_settings_index',
          },
          {
            // Tabela de preços oficial (Espaço do Paciente + agentes IA)
            name: 'Settings Prices',
            label: 'Tabela de preços',
            icon: 'i-lucide-badge-dollar-sign',
            route: 'precos_settings_index',
          },
        ]
          .filter(c => show(c.name))
          .map(c => ({
            name: c.name,
            label: c.label,
            icon: c.icon,
            to: accountScopedRoute(c.route),
          })),
        // {
        //   name: 'Settings Captain',
        //   label: t('SIDEBAR.CAPTAIN_AI'),
        //   icon: 'i-woot-captain',
        //   to: accountScopedRoute('captain_settings_index'),
        // },
        {
          name: 'Settings Agents',
          label: t('SIDEBAR.AGENTS'),
          icon: 'i-lucide-square-user',
          to: accountScopedRoute('agent_list'),
        },
        // 🔐 rodada 334: quem vê e quem edita cada área (árvore + papéis)
        ...(show('Settings Access')
          ? [
              {
                name: 'Settings Access',
                label: 'Acessos e papéis',
                icon: 'i-lucide-shield-check',
                to: accountScopedRoute('acessos_settings_index'),
              },
            ]
          : []),
        {
          name: 'Settings Teams',
          label: t('SIDEBAR.TEAMS'),
          icon: 'i-lucide-users',
          activeOn: [
            'settings_teams_list',
            'settings_teams_new',
            'settings_teams_finish',
            'settings_teams_add_agents',
            'settings_teams_show',
            'settings_teams_edit',
            'settings_teams_edit_members',
            'settings_teams_edit_finish',
          ],
          to: accountScopedRoute('settings_teams_list'),
        },
        ...(hasAdvancedAssignment.value
          ? [
              {
                name: 'Settings Agent Assignment',
                label: t('SIDEBAR.AGENT_ASSIGNMENT'),
                icon: 'i-lucide-user-cog',
                activeOn: [
                  'assignment_policy_index',
                  'agent_assignment_policy_index',
                  'agent_assignment_policy_create',
                  'agent_assignment_policy_edit',
                  'agent_capacity_policy_index',
                  'agent_capacity_policy_create',
                  'agent_capacity_policy_edit',
                ],
                to: accountScopedRoute('assignment_policy_index'),
              },
            ]
          : []),
        {
          name: 'Settings Inboxes',
          label: t('SIDEBAR.INBOXES'),
          icon: 'i-lucide-inbox',
          activeOn: [
            'settings_inbox_list',
            'settings_inbox_show',
            'settings_inbox_new',
            'settings_inbox_finish',
            'settings_inboxes_page_channel',
            'settings_inboxes_add_agents',
          ],
          to: accountScopedRoute('settings_inbox_list'),
        },
        {
          name: 'Settings Templates',
          label: t('SIDEBAR.WHATSAPP_TEMPLATES'),
          icon: 'i-lucide-layout-template',
          to: accountScopedRoute('settings_templates'),
        },
        {
          name: 'Settings Labels',
          label: t('SIDEBAR.LABELS'),
          icon: 'i-lucide-tags',
          to: accountScopedRoute('labels_list'),
        },
        {
          name: 'Settings Custom Attributes',
          label: t('SIDEBAR.CUSTOM_ATTRIBUTES'),
          icon: 'i-lucide-code',
          to: accountScopedRoute('attributes_list'),
        },
        {
          name: 'Settings Agent Bots',
          label: t('SIDEBAR.AGENT_BOTS'),
          icon: 'i-lucide-bot',
          to: accountScopedRoute('agent_bots'),
        },
        {
          name: 'Settings Macros',
          label: t('SIDEBAR.MACROS'),
          icon: 'i-lucide-toy-brick',
          to: accountScopedRoute('macros_wrapper'),
        },
        {
          name: 'Settings Canned Responses',
          label: t('SIDEBAR.CANNED_RESPONSES'),
          icon: 'i-lucide-message-square-quote',
          to: accountScopedRoute('canned_list'),
        },
        {
          name: 'Settings Audit Logs',
          label: t('SIDEBAR.AUDIT_LOGS'),
          icon: 'i-lucide-scroll-text',
          to: accountScopedRoute('auditlogs_list'),
        },
        {
          name: 'Settings Custom Roles',
          label: t('SIDEBAR.CUSTOM_ROLES'),
          icon: 'i-lucide-shield-plus',
          to: accountScopedRoute('custom_roles_list'),
        },
        {
          name: 'Settings Sla',
          label: t('SIDEBAR.SLA'),
          icon: 'i-lucide-clock-alert',
          to: accountScopedRoute('sla_list'),
        },
        {
          name: 'Conversation Workflow',
          label: t('SIDEBAR.CONVERSATION_WORKFLOW'),
          icon: 'i-lucide-workflow',
          to: accountScopedRoute('conversation_workflow_index'),
        },
        {
          name: 'Settings Security',
          label: t('SIDEBAR.SECURITY'),
          icon: 'i-lucide-shield',
          to: accountScopedRoute('security_settings_index'),
        },
        {
          name: 'Settings Billing',
          label: t('SIDEBAR.BILLING'),
          icon: 'i-lucide-credit-card',
          to: accountScopedRoute('billing_settings_index'),
        },
      ],
    },
  ];
});
</script>

<template>
  <aside
    v-on-click-outside="[
      closeMobileSidebar,
      {
        ignore: [
          '#mobile-sidebar-launcher',
          '[data-popover-content]',
          '[data-popover-backdrop]',
        ],
      },
    ]"
    class="bg-n-background flex flex-col text-sm pb-px fixed top-0 ltr:left-0 rtl:right-0 h-full z-40 w-[min(80vw,320px)] md:w-auto md:relative md:flex-shrink-0 md:ltr:translate-x-0 md:rtl:translate-x-0 ltr:border-r rtl:border-l border-n-weak"
    :class="[
      {
        'shadow-lg md:shadow-none': isMobileSidebarOpen,
        'ltr:-translate-x-full rtl:translate-x-full': !isMobileSidebarOpen,
        'transition-transform duration-200 ease-out md:transition-[width]':
          !isResizing,
      },
    ]"
    :style="isMobile ? undefined : { width: `${sidebarWidth}px` }"
  >
    <section
      class="grid"
      :class="isEffectivelyCollapsed ? 'mt-3 mb-6 gap-4' : 'mt-1 mb-4 gap-2'"
    >
      <div
        class="flex gap-2 items-center min-w-0"
        :class="{
          'justify-center px-1': isEffectivelyCollapsed,
          'px-2': !isEffectivelyCollapsed,
        }"
      >
        <template v-if="isEffectivelyCollapsed">
          <SidebarAccountSwitcher
            is-collapsed
            @show-create-account-modal="emit('showCreateAccountModal')"
          />
        </template>
        <template v-else>
          <div class="grid flex-shrink-0 place-content-center size-6">
            <Logo class="size-4" />
          </div>
          <div class="flex-shrink-0 w-px h-3 bg-n-strong" />
          <SidebarAccountSwitcher
            class="flex-grow -mx-1 min-w-0"
            @show-create-account-modal="emit('showCreateAccountModal')"
          />
        </template>
      </div>
      <div
        class="flex gap-2"
        :class="isEffectivelyCollapsed ? 'flex-col items-center' : 'px-2'"
      >
        <RouterLink
          v-if="!isEffectivelyCollapsed"
          :to="{ name: 'search' }"
          class="flex gap-2 items-center px-2 py-1 w-full h-7 rounded-lg outline outline-1 outline-n-weak bg-n-button-color transition-all duration-100 ease-out"
        >
          <span class="flex-shrink-0 i-lucide-search size-4 text-n-slate-10" />
          <span class="flex-grow text-start text-n-slate-10">
            {{ t('COMBOBOX.SEARCH_PLACEHOLDER') }}
          </span>
          <span
            class="hidden tracking-wide pointer-events-none select-none text-n-slate-10"
          >
            {{ searchShortcut }}
          </span>
        </RouterLink>
        <RouterLink
          v-else
          :to="{ name: 'search' }"
          class="flex items-center justify-center size-8 rounded-lg outline outline-1 outline-n-weak bg-n-button-color transition-all duration-100 ease-out hover:bg-n-alpha-2 dark:hover:bg-n-slate-9/30"
          :title="t('COMBOBOX.SEARCH_PLACEHOLDER')"
        >
          <span class="i-lucide-search size-4 text-n-slate-11" />
        </RouterLink>
        <!-- CEVICO 199: o lápis abre a "Nova conversa" em 3 passos -->
        <Button
          icon="i-lucide-message-square-plus"
          color="slate"
          size="sm"
          title="Nova conversa"
          class="dark:hover:!bg-n-slate-9/30"
          :class="
            isEffectivelyCollapsed
              ? '!size-8 !outline-n-weak !text-n-slate-11'
              : '!h-7 !outline-n-weak !text-n-slate-11'
          "
          @click="openNovaConversa()"
        />
      </div>
    </section>
    <nav
      class="grid overflow-y-scroll flex-grow gap-2 pb-5 no-scrollbar min-w-0"
      :class="isEffectivelyCollapsed ? 'px-1' : 'px-2'"
    >
      <ul
        class="flex flex-col gap-1 m-0 list-none min-w-0"
        :class="{
          'items-center': isEffectivelyCollapsed,
          'cv-ios-nav': !isEffectivelyCollapsed,
        }"
      >
        <SidebarGroup
          v-for="item in groupedMenuItems"
          :key="item.name"
          v-bind="item"
        />
        <!-- Personalizar menu (só admin) -->
        <li v-if="isAdmin" class="list-none mt-1">
          <button
            class="flex items-center gap-2 w-full px-2 py-1.5 text-xs text-n-slate-9 hover:text-n-slate-11 rounded-lg hover:bg-n-alpha-1 transition-colors"
            :class="{ 'justify-center': isEffectivelyCollapsed }"
            title="Personalizar menu"
            @click="showCustomizeMenu = true"
          >
            <span class="i-lucide-eye-off text-sm flex-shrink-0" />
            <span v-if="!isEffectivelyCollapsed">Personalizar menu</span>
          </button>
        </li>
      </ul>
    </nav>

    <!-- Modal: personalizar menu -->
    <Teleport to="body">
      <div
        v-if="showCustomizeMenu"
        class="fixed inset-0 z-[70] flex items-center justify-center bg-black/60 p-4"
        @click.self="showCustomizeMenu = false"
      >
        <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-sm">
          <div
            class="flex items-center justify-between px-5 py-4 border-b border-n-weak"
          >
            <div>
              <h2 class="text-base font-semibold text-n-slate-12">
                Personalizar menu
              </h2>
              <p class="text-xs text-n-slate-10 mt-0.5">
                Oculte seções que você não usa. Dá para reativar quando quiser.
              </p>
            </div>
            <button
              class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl"
              @click="showCustomizeMenu = false"
            />
          </div>
          <div class="px-4 pt-3 pb-1 flex items-center justify-between">
            <p class="text-[11px] text-n-slate-10">
              A caixinha mostra/oculta o item. A ordem segue as gavetas do menu.
            </p>
          </div>
          <div class="p-4 pt-2 space-y-1 max-h-[60vh] overflow-y-auto">
            <div
              v-for="item in orderedMenuEntries"
              :key="item.name"
              class="flex items-center gap-2 px-3 py-2 rounded-lg hover:bg-n-alpha-1"
            >
              <span
                v-if="typeof item.icon === 'string'"
                :class="item.icon"
                class="text-sm text-n-slate-10 flex-shrink-0"
              />
              <span class="text-sm text-n-slate-12 flex-1 truncate">{{
                item.label
              }}</span>
              <span
                v-if="item.feature && hiddenFeatures.includes(item.feature)"
                class="text-[10px] text-n-slate-9"
                >oculto</span
              >
              <input
                v-if="item.feature"
                type="checkbox"
                class="rounded accent-n-brand"
                title="Mostrar/ocultar este item"
                :checked="!hiddenFeatures.includes(item.feature)"
                @change="toggleHiddenFeature(item.feature)"
              />
            </div>
          </div>
        </div>
      </div>
    </Teleport>
    <section
      class="flex relative flex-col flex-shrink-0 gap-1 justify-between items-center"
    >
      <div
        class="pointer-events-none absolute inset-x-0 -top-[1.938rem] h-8 bg-gradient-to-t from-n-background to-transparent"
      />
      <SidebarChangelogCard
        v-if="
          isOnChatwootCloud &&
          !isACustomBrandedInstance &&
          !isEffectivelyCollapsed
        "
      />
      <SidebarChangelogButton
        v-if="
          isOnChatwootCloud &&
          !isACustomBrandedInstance &&
          isEffectivelyCollapsed
        "
      />
      <div
        class="px-1 py-1.5 flex-shrink-0 flex w-full z-50 gap-2 items-center border-t border-n-weak shadow-[0px_-2px_4px_0px_rgba(27,28,29,0.02)]"
        :class="isEffectivelyCollapsed ? 'justify-center' : 'justify-between'"
      >
        <SidebarProfileMenu
          :is-collapsed="isEffectivelyCollapsed"
          @open-key-shortcut-modal="emit('openKeyShortcutModal')"
        />
      </div>
    </section>
    <!-- Resize Handle (desktop only) -->
    <div
      class="hidden md:block absolute top-0 h-full w-1 cursor-col-resize z-40 ltr:right-0 rtl:left-0 group"
      @mousedown="onResizeStart"
      @touchstart="onResizeStart"
      @dblclick="onResizeHandleDoubleClick"
    >
      <div
        class="absolute top-0 h-full w-px ltr:right-0 rtl:left-0 bg-transparent group-hover:bg-n-brand transition-colors"
        :class="{ 'bg-n-brand': isResizing }"
      />
    </div>
  </aside>
</template>
