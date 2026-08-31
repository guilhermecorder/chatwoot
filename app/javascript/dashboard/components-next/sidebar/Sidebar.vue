<script setup>
import { h, ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useRouter } from 'vue-router';
import { provideSidebarContext, useSidebarResize } from './provider';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
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
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import { frase, segmentoId } from 'dashboard/helper/segmento';
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
const router = useRouter();
const store = useStore();
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

const getSortOptionsForSection = section =>
  getSidebarSortOptions(section, {
    hasUnreadCounts: hasConversationUnreadCounts.value,
  });

const getSortForSection = section =>
  resolveSidebarSort(section, getSidebarSectionSort.value(section), {
    hasUnreadCounts: hasConversationUnreadCounts.value,
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

// ── CEVICO: acessos por agente (modelo de CONCESSÃO, decisão 17/07) ──
// - Dia a dia: itens que o admin liga/desliga por pessoa (só menu; os
//   endpoints continuam abertos ao time). Padrão = DAY_MENU_DEFAULT.
// - Áreas administrativas: aparecem para o atendente SÓ com concessão em
//   agent_permissions['grants'] (a tranca de verdade é o backend).
const crmSettings = useMapGetter('crm/getSettings');

// chave do dia a dia → name do item do menu
const DAY_ITEM_BY_KEY = {
  crm: 'CRM',
  conversation: 'Conversation',
  agenda: 'Agenda',
  goals: 'Goals',
  canned: 'Canned',
  tasks: 'Tasks',
  people: 'People',
  academy: 'Academy',
};
// menu padrão do atendente (pedido do Guilherme 17/07):
// Meu Painel | CRM | Conversas | Agenda | Metas | Respostas prontas
const DAY_MENU_DEFAULT = ['crm', 'conversation', 'agenda', 'goals', 'canned'];

// name do item → capabilities que o liberam para atendente (qualquer uma)
const GRANT_BY_ITEM_NAME = {
  Reports: ['reports'],
  'Campanha WhatsApp': ['campaigns'],
  'Automations Hub': ['automations', 'data_tools'],
  'Integrations Hub': ['settings'],
  Finance: ['finance'],
  Strategy: ['strategy'],
};

// chaves usadas pelo "Personalizar menu" (ocultar por conta própria)
const FEATURE_BY_ITEM_NAME = {
  Inbox: 'inbox',
  Conversation: 'conversation',
  Captain: 'captain',
  Companies: 'companies',
  Reports: 'reports',
  CRM: 'crm',
  'Campanha WhatsApp': 'crm_campaigns',
  Tasks: 'tasks',
  Agenda: 'agenda',
  Academy: 'academy',
  Settings: 'settings',
  Goals: 'goals',
  People: 'people',
  Canned: 'canned',
};

const myGrants = computed(() => {
  const perms = crmSettings.value?.agent_permissions ?? {};
  return perms.grants?.[String(currentUserId.value)] ?? [];
});

// atendente COM a área concedida (admin sempre passa)
const canSee = capability =>
  isAdmin.value || myGrants.value.includes(capability);

// HUB: convidado SÓ da Saúde (não-admin com a área 'health' concedida)
// → o sistema dele é o mundo Saúde inteiro, sem Negócios
const healthOnly = computed(
  () =>
    segmentoId === 'saude' && !isAdmin.value && myGrants.value.includes('health')
);

// item 62: relatórios ESPECÍFICOS concedidos (lista vazia = todos)
const myReportKeys = computed(() => {
  const perms = crmSettings.value?.agent_permissions ?? {};
  return perms.report_keys?.[String(currentUserId.value)] ?? [];
});
const canSeeReport = key =>
  isAdmin.value ||
  myReportKeys.value.length === 0 ||
  myReportKeys.value.includes(key);

const myDayMenu = computed(() => {
  const perms = crmSettings.value?.agent_permissions ?? {};
  const configured = perms.menu?.[String(currentUserId.value)];
  if (configured) return configured;
  // legado (lista de bloqueio antiga): respeita subtraindo do padrão
  const legacyBlocked = perms[String(currentUserId.value)] ?? [];
  return DAY_MENU_DEFAULT.filter(key => !legacyBlocked.includes(key));
});

const hiddenFeatures = ref(
  JSON.parse(localStorage.getItem('cevico_hidden_menu') ?? '[]')
);

const showCustomizeMenu = ref(false);

const toggleHiddenFeature = key => {
  const idx = hiddenFeatures.value.indexOf(key);
  if (idx === -1) hiddenFeatures.value.push(key);
  else hiddenFeatures.value.splice(idx, 1);
  localStorage.setItem('cevico_hidden_menu', JSON.stringify(hiddenFeatures.value));
};

// ── Ordem dos itens do menu (Personalizar menu, por pessoa/navegador) ──
// Padrão admin: Relatórios logo abaixo do CRM (pedido 2026-07-15).
const DEFAULT_MENU_ORDER = [
  'Inicio', 'CRM', 'Reports', 'Strategy', 'Finance', 'Goals', 'Builder', 'People', 'Inbox', 'Conversation', 'Captain', 'Companies',
  'Campanha WhatsApp', 'Forms', 'Tasks', 'Agenda', 'Cevico Pages', 'Academy',
  'Automations Hub', 'Settings',
];
// Padrão do ATENDENTE (pedido 2026-07-17): Meu Painel | CRM | Conversas |
// Agenda | Metas | Respostas prontas — depois os extras/concedidos.
const AGENT_MENU_ORDER = [
  'Inicio', 'CRM', 'Conversation', 'Agenda', 'Goals', 'Builder', 'Canned',
  'Tasks', 'People', 'Reports', 'Campanha WhatsApp', 'Cevico Pages',
  'Strategy', 'Finance', 'Academy', 'Automations Hub',
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
const moveMenuItem = (name, dir) => {
  const names = orderedMenuEntries.value.map(i => i.name);
  const idx = names.indexOf(name);
  const to = idx + dir;
  if (idx === -1 || to < 0 || to >= names.length) return;
  [names[idx], names[to]] = [names[to], names[idx]];
  menuOrder.value = names;
  localStorage.setItem('cevico_menu_order', JSON.stringify(names));
};
const resetMenuOrder = () => {
  menuOrder.value = null; // volta ao padrão do papel (admin/atendente)
  localStorage.removeItem('cevico_menu_order');
};

// itens do modal Personalizar menu: TODOS os itens do papel (inclusive os
// ocultos, para poder reexibir), na ordem atual, com ↑/↓ e olhinho
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

// Atendente vê: Meu Painel + itens do dia a dia configurados pelo admin
// (padrão: CRM | Conversas | Agenda | Metas | Respostas prontas) +
// Conteúdos (rascunhos do time) + áreas CONCEDIDAS + Configurações (perfil)
const menuItemsForRole = computed(() => {
  if (isAdmin.value) return menuItems.value;
  const dayNames = myDayMenu.value
    .map(key => DAY_ITEM_BY_KEY[key])
    .filter(Boolean);
  const allow = ['Inicio', ...dayNames, 'Cevico Pages', 'Builder'];
  const granted = Object.entries(GRANT_BY_ITEM_NAME)
    .filter(([, capabilities]) =>
      capabilities.some(capability => myGrants.value.includes(capability))
    )
    .map(([name]) => name);
  return [
    ...menuItems.value.filter(
      i => allow.includes(i.name) || granted.includes(i.name)
    ),
    {
      name: 'Settings',
      label: 'Configurações',
      icon: 'i-lucide-bolt',
      to: accountScopedRoute('profile_settings_index'),
    },
  ];
});

// ── HUB (segmento saude): mundos isolados — desenho do Guilherme 25/08.
// hub_mode (localStorage) decide o menu inteiro: 'saude' = só o mundo da
// saúde; 'negocios' (ou nada) = o sistema normal, com o item HUB no topo
// pra voltar à porta de entrada. A tela /hub troca o modo e avisa por evento.
const hubMode = ref(localStorage.getItem('hub_mode') || '');
const onHubModeChange = e => {
  hubMode.value = e?.detail || localStorage.getItem('hub_mode') || '';
};

const hubItem = () => ({
  name: 'HubHome',
  label: 'HUB',
  icon: 'i-lucide-layout-grid',
  to: accountScopedRoute('hub_home'),
});

// boxe é recurso LIGÁVEL (Configurações → HUB): desligado, some pra todos
const boxingOn = computed(
  () => crmSettings.value?.health_features?.boxing === true
);

const hubMenuSaude = () => [
  hubItem(),
  { name: 'HealthPainel', label: 'Meu Painel', icon: 'i-lucide-gauge', to: accountScopedRoute('hub_health_painel') },
  { name: 'HealthTreino', label: 'Treino', icon: 'i-lucide-dumbbell', to: accountScopedRoute('hub_health') },
  ...(boxingOn.value
    ? [{ name: 'HealthBoxe', label: 'Boxe', icon: 'i-lucide-swords', to: accountScopedRoute('hub_health_boxe') }]
    : []),
  { name: 'HealthDieta', label: 'Dieta', icon: 'i-lucide-utensils', to: accountScopedRoute('hub_health_dieta') },
  { name: 'HealthCorpo', label: 'Corpo', icon: 'i-lucide-ruler', to: accountScopedRoute('hub_health_corpo') },
  { name: 'HealthDash', label: 'Dashboard', icon: 'i-lucide-area-chart', to: accountScopedRoute('hub_health_dash') },
];

const visibleMenuItems = computed(() => {
  // convidado só-Saúde: menu do mundo Saúde SEMPRE, sem item HUB
  if (healthOnly.value) {
    const items = hubMenuSaude().filter(i => i.name !== 'HubHome');
    const denominator = Math.max(items.length - 1, 1);
    return items.map((item, index) => ({
      ...item,
      iconColor: gradientColorAt(index / denominator),
    }));
  }
  // mundo 2 — Saúde: menu isolado, nada de negócios
  if (segmentoId === 'saude' && hubMode.value === 'saude') {
    const items = hubMenuSaude();
    const denominator = Math.max(items.length - 1, 1);
    return items.map((item, index) => ({
      ...item,
      iconColor: gradientColorAt(index / denominator),
    }));
  }
  let items = menuItemsForRole.value
    .filter(item => {
      const key = FEATURE_BY_ITEM_NAME[item.name];
      if (!key) return true;
      // Caixa de Entrada é visão de admin — atendimento acontece pelo CRM
      if (key === 'inbox' && !isAdmin.value) return false;
      return !hiddenFeatures.value.includes(key);
    })
    // ordem escolhida no Personalizar menu (padrão por papel)
    .sort((a, b) => orderIndex(a.name) - orderIndex(b.name));
  // mundo 1 — Negócios: Saúde mora no mundo 2 (não aparece aqui);
  // o HUB fica no topo pra transitar entre os mundos
  if (segmentoId === 'saude') {
    items = [hubItem(), ...items.filter(i => i.name !== 'Health')];
  }
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
  radarBadgeTimer = setInterval(() => {
    store.dispatch('crm/fetchSettings').catch(() => {});
  }, 5 * 60 * 1000);
  // HUB: a tela /hub avisa a troca de mundo por evento
  window.addEventListener('hub:mode', onHubModeChange);
  // primeira entrada sem mundo escolhido → porta de entrada do HUB
  if (
    segmentoId === 'saude' &&
    !localStorage.getItem('hub_mode') &&
    router.currentRoute.value.name !== 'hub_home'
  ) {
    router.push(accountScopedRoute('hub_home'));
  }
});

// convidado só-Saúde caindo fora do mundo Saúde → leva pro painel dele
watch(healthOnly, only => {
  if (!only) return;
  const name = String(router.currentRoute.value.name || '');
  if (!name.startsWith('hub_health')) {
    router.push(accountScopedRoute('hub_health_painel'));
  }
});

let radarBadgeTimer = null;
onUnmounted(() => {
  clearInterval(radarBadgeTimer);
  window.removeEventListener('hub:mode', onHubModeChange);
});
// ──────────────────────────────────────────────────────────────────────────

const menuItems = computed(() => {
  return [
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
          name: 'FAQs',
          label: t('SIDEBAR.CAPTAIN_RESPONSES'),
          activeOn: [
            'captain_assistants_responses_index',
            'captain_assistants_responses_pending',
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
            'captain_assistants_guidelines_index',
            'captain_assistants_guardrails_index',
          ],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_settings_index',
          }),
        },
      ],
    },
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
    {
      name: 'Reports',
      label: t('SIDEBAR.REPORTS'),
      icon: 'i-lucide-chart-spline',
      children: [
        // dashboards CEVICO — abrem para atendente com a concessão
        // "Relatórios"; item 62: o admin pode conceder relatórios
        // ESPECÍFICOS (report_keys — lista vazia = todos)
        ...[
          { name: 'CRM Dashboard', key: 'crm_dashboard', label: 'Dashboard CRM', route: 'crm_dashboard_reports' },
          ...(canSee('campaigns')
            ? [{ name: 'Campaigns Dashboard', key: 'campaigns_dashboard', label: 'Dashboard Campanhas', route: 'crm_campaigns_dashboard' }]
            : []),
          { name: 'Traffic Funnel', key: 'traffic_funnel', label: 'Funil de Tráfego', route: 'traffic_funnel_reports' },
          { name: 'Doctors Dashboard', key: 'doctors', label: frase('dashboard_profissionais', 'Dashboard dos Médicos'), route: 'doctors_reports' },
          { name: 'Agents Dashboard', key: 'agents_dashboard', label: 'Dashboard dos Agentes', route: 'agents_dashboard_reports' },
          { name: 'Agenda Dashboard', key: 'agenda_dashboard', label: 'Dashboard da Agenda', route: 'agenda_dashboard_reports' },
          { name: 'Ads Report', key: 'ads', label: 'Anúncios (Meta)', route: 'ads_reports' },
          { name: 'Google Dashboard', key: 'google', label: 'Google (Ads + GA4)', route: 'google_dashboard_reports' },
          { name: 'WhatsApp Health', key: 'whatsapp_health', label: 'Saúde do WhatsApp', route: 'whatsapp_health_reports' },
        ]
          .filter(r => canSeeReport(r.key))
          .map(r => ({ name: r.name, label: r.label, to: accountScopedRoute(r.route) })),
        // relatórios do core do Chatwoot — a API deles só aceita admin,
        // então nem aparecem para atendente concedido
        ...(isAdmin.value
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
    {
      name: 'Campanha WhatsApp',
      label: 'Campanha WhatsApp',
      icon: 'i-lucide-megaphone',
      to: accountScopedRoute('crm_campaigns'),
    },
    // Formulários (pré-operatório etc.) — visão de gestão, só admin
    ...(isAdmin.value
      ? [
          {
            name: 'Forms',
            label: 'Formulários',
            icon: 'i-lucide-clipboard-list',
            to: accountScopedRoute('crm_forms'),
          },
        ]
      : []),
    // Painel Estratégico — admin ou concessão "Estratégia"
    ...(canSee('strategy')
      ? [
          {
            name: 'Strategy',
            label: 'Estratégia',
            icon: 'i-lucide-compass',
            to: accountScopedRoute('cevico_strategy'),
          },
        ]
      : []),
    // Gestão Financeira — admin ou concessão "Financeiro"
    ...(canSee('finance')
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
          label: 'Planejamento de conteúdos',
          icon: 'i-lucide-kanban',
          to: accountScopedRoute('cevico_content_board'),
        },
        // Análise de funis + testes A/B (PÁGINAS PRO) — admin ou
        // concessão "Páginas" (decisão 17/07: rascunhos p/ todo o time,
        // análise por concessão)
        ...(canSee('pages')
          ? [
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
            ]
          : []),
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
      label: frase('academia', 'Academia CEVICO'),
      icon: 'i-lucide-graduation-cap',
      to: accountScopedRoute('academy_home'),
    },
    // Automações — admin ou concessões (cada aba pede a sua área:
    // robôs/resultados = Automações; tratamento = Tratamento de dados;
    // regras/agentes de IA/programação = só admin)
    ...(canSee('automations') || canSee('data_tools')
      ? [
          {
            name: 'Automations Hub',
            label: 'Automações',
            icon: 'i-lucide-workflow',
            children: [
              ...(canSee('automations')
                ? [
                    {
                      name: 'Automations Robos',
                      label: 'Robôs de follow-up',
                      icon: 'i-lucide-bot',
                      to: accountScopedRoute('cevico_automations', {}, { tab: 'robos' }),
                    },
                  ]
                : []),
              ...(isAdmin.value
                ? [
                    {
                      name: 'Automations Rules',
                      label: 'Regras da caixa de entrada',
                      icon: 'i-lucide-repeat',
                      to: accountScopedRoute('cevico_automations', {}, { tab: 'regras' }),
                    },
                    {
                      name: 'Automations AI Agents',
                      label: 'Agentes de IA',
                      icon: 'i-lucide-sparkles',
                      to: accountScopedRoute('cevico_automations', {}, { tab: 'agentes' }),
                    },
                    // item 85: o que cada agente de IA está fazendo + custos
                    {
                      name: 'Automations AI Panel',
                      label: 'Painel dos agentes',
                      icon: 'i-lucide-activity',
                      to: accountScopedRoute('cevico_automations', {}, { tab: 'painel_ia' }),
                    },
                    {
                      name: 'Automations Programming',
                      label: 'Modo Programação',
                      icon: 'i-lucide-zap',
                      to: accountScopedRoute('cevico_automations', {}, { tab: 'programacao' }),
                    },
                  ]
                : []),
              ...(canSee('automations')
                ? [
                    {
                      name: 'Automations Results',
                      label: 'Resultados',
                      icon: 'i-lucide-bar-chart-3',
                      to: accountScopedRoute('cevico_automations', {}, { tab: 'resultados' }),
                    },
                  ]
                : []),
              ...(canSee('data_tools')
                ? [
                    {
                      name: 'Automations Treatment',
                      label: 'Tratamento de dados',
                      icon: 'i-lucide-database',
                      to: accountScopedRoute('cevico_automations', {}, { tab: 'tratamento' }),
                    },
                  ]
                : []),
            ],
          },
        ]
      : []),
    {
      name: 'Settings',
      label: t('SIDEBAR.SETTINGS'),
      icon: 'i-lucide-bolt',
      children: [
        // Integrações UNIFICADAS dentro de Configurações (item 78):
        // central CEVICO (Meta/Google/Claude/Sheets/n8n) + aplicativos nativos
        ...(canSee('settings')
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
        // Domínio público das páginas/formulários (só admin)
        ...(isAdmin.value
          ? [
              {
                name: 'Settings Domain',
                label: 'Domínio',
                icon: 'i-lucide-globe',
                to: accountScopedRoute('dominio_settings_index'),
              },
              // Responsável por painel do Meu Painel (pedido 20/08)
              {
                name: 'Settings Panels',
                label: 'Painéis',
                icon: 'i-lucide-layout-dashboard',
                to: accountScopedRoute('paineis_settings_index'),
              },
              // Tabela de preços oficial (Espaço do Paciente + agentes IA)
              {
                name: 'Settings Prices',
                label: 'Tabela de preços',
                icon: 'i-lucide-badge-dollar-sign',
                to: accountScopedRoute('precos_settings_index'),
              },
              // Personalização (sistema coringa): profissionais/unidades/listas
              {
                name: 'Settings Segment',
                label: 'Personalização',
                icon: 'i-lucide-puzzle',
                to: accountScopedRoute('personalizacao_settings_index'),
              },
              // HUB (segmento saude): recursos ligáveis do sistema pessoal
              ...(segmentoId === 'saude'
                ? [
                    {
                      name: 'Settings Hub',
                      label: 'HUB',
                      icon: 'i-lucide-layout-grid',
                      to: accountScopedRoute('hub_settings_index'),
                    },
                  ]
                : []),
            ]
          : []),
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
          icon: 'i-lucide-briefcase',
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
    class="bg-n-background flex flex-col text-sm pb-px fixed top-0 ltr:left-0 rtl:right-0 h-full z-40 w-[200px] md:w-auto md:relative md:flex-shrink-0 md:ltr:translate-x-0 md:rtl:translate-x-0 ltr:border-r rtl:border-l border-n-weak"
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
        <ComposeConversation align="start">
          <template #trigger="{ isOpen }">
            <Button
              icon="i-lucide-pen-line"
              color="slate"
              size="sm"
              class="dark:hover:!bg-n-slate-9/30"
              :class="[
                isEffectivelyCollapsed
                  ? '!size-8 !outline-n-weak !text-n-slate-11'
                  : '!h-7 !outline-n-weak !text-n-slate-11',
                { '!bg-n-alpha-2 dark:!bg-n-slate-9/30': isOpen },
              ]"
            />
          </template>
        </ComposeConversation>
      </div>
    </section>
    <nav
      class="grid overflow-y-scroll flex-grow gap-2 pb-5 no-scrollbar min-w-0"
      :class="isEffectivelyCollapsed ? 'px-1' : 'px-2'"
    >
      <ul
        class="flex flex-col gap-1 m-0 list-none min-w-0"
        :class="{ 'items-center': isEffectivelyCollapsed }"
      >
        <SidebarGroup
          v-for="item in visibleMenuItems"
          :key="item.name"
          v-bind="item"
        />
        <!-- Personalizar menu (só admin; no mundo Saúde o menu é fixo) -->
        <li v-if="isAdmin && hubMode !== 'saude'" class="list-none mt-1">
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
          <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak">
            <div>
              <h2 class="text-base font-semibold text-n-slate-12">Personalizar menu</h2>
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
              Use as setas para mudar a ordem; a caixinha mostra/oculta o item.
            </p>
            <button
              class="text-[11px] font-medium text-n-brand hover:underline flex-shrink-0"
              @click="resetMenuOrder"
            >
              Restaurar ordem padrão
            </button>
          </div>
          <div class="p-4 pt-2 space-y-1 max-h-[60vh] overflow-y-auto">
            <div
              v-for="(item, idx) in orderedMenuEntries"
              :key="item.name"
              class="flex items-center gap-2 px-3 py-2 rounded-lg hover:bg-n-alpha-1"
            >
              <!-- reordenar -->
              <div class="flex flex-col -my-1">
                <button
                  class="i-lucide-chevron-up text-sm text-n-slate-9 hover:text-n-brand disabled:opacity-25"
                  :disabled="idx === 0"
                  title="Subir"
                  @click="moveMenuItem(item.name, -1)"
                />
                <button
                  class="i-lucide-chevron-down text-sm text-n-slate-9 hover:text-n-brand disabled:opacity-25"
                  :disabled="idx === orderedMenuEntries.length - 1"
                  title="Descer"
                  @click="moveMenuItem(item.name, 1)"
                />
              </div>
              <span v-if="typeof item.icon === 'string'" :class="item.icon" class="text-sm text-n-slate-10 flex-shrink-0" />
              <span class="text-sm text-n-slate-12 flex-1 truncate">{{ item.label }}</span>
              <span
                v-if="item.feature && hiddenFeatures.includes(item.feature)"
                class="text-[10px] text-n-slate-9"
              >oculto</span>
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
