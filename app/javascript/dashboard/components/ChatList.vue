<script setup>
import { ref, unref, provide, computed, watch, onMounted } from 'vue';
import { onClickOutside } from '@vueuse/core';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import {
  useMapGetter,
  useFunctionGetter,
} from 'dashboard/composables/store.js';

import ChatListHeader from './ChatListHeader.vue';
import ConversationList from './ConversationList.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ConversationFilter from 'next/filter/ConversationFilter.vue';
import SaveCustomView from 'next/filter/SaveCustomView.vue';
import DeleteCustomViews from 'dashboard/routes/dashboard/customviews/DeleteCustomViews.vue';
import ConversationBulkActions from './widgets/conversation/conversationBulkActions/Index.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import ConversationResolveAttributesModal from 'dashboard/components-next/ConversationWorkflow/ConversationResolveAttributesModal.vue';

import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAlert } from 'dashboard/composables';
import { useBulkActions } from 'dashboard/composables/chatlist/useBulkActions';
import { useFilter } from 'shared/composables/useFilter';
import { useTrack } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import {
  useCamelCase,
  useSnakeCase,
} from 'dashboard/composables/useTransformKeys';
import { useEmitter } from 'dashboard/composables/emitter';
import { useConversationRequiredAttributes } from 'dashboard/composables/useConversationRequiredAttributes';

import { emitter } from 'shared/helpers/mitt';

import wootConstants from 'dashboard/constants/globals';
import advancedFilterOptions from './widgets/conversation/advancedFilterItems';
import filterQueryGenerator from '../helper/filterQueryGenerator.js';
import {
  inboxGradientFor,
  inboxSolidFor,
} from '../helper/cevicoInboxColors.js';
import languages from 'dashboard/components/widgets/conversation/advancedFilterItems/languages';
import countries from 'shared/constants/countries';
import { generateValuesForEditCustomViews } from 'dashboard/helper/customViewsHelper';
import { conversationListPageURL } from '../helper/URLHelper';
import {
  isOnMentionsView,
  isOnParticipatingView,
  isOnUnattendedView,
} from '../store/modules/conversations/helpers/actionHelpers';
import {
  getUserPermissions,
  filterItemsByPermission,
} from 'dashboard/helper/permissionsHelper.js';
import { matchesFilters } from '../store/modules/conversations/helpers/filterHelpers';
import { CONVERSATION_EVENTS } from '../helper/AnalyticsHelper/events';
import { ASSIGNEE_TYPE_TAB_PERMISSIONS } from 'dashboard/constants/permissions.js';

const props = defineProps({
  conversationInbox: { type: [String, Number], default: 0 },
  teamId: { type: [String, Number], default: 0 },
  label: { type: String, default: '' },
  conversationType: { type: String, default: '' },
  foldersId: { type: [String, Number], default: 0 },
  showConversationList: { default: true, type: Boolean },
  isOnExpandedLayout: { default: false, type: Boolean },
});

const emit = defineEmits(['conversationLoad']);
const { uiSettings, updateUISettings } = useUISettings();
const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const store = useStore();

// ── CEVICO: pílulas de caixa de entrada no topo (estilo presets do Meu
// Painel). Só nas visões "puras" (Conversas/caixa) — não em times/etiquetas/
// menções/pastas. Aceita MAIS DE UMA caixa ao mesmo tempo: 1 caixa usa a
// rota nativa; 2+ ficam na visão geral com filtro local. A escolha fica
// salva no navegador e é pré-selecionada ao abrir Conversas.
const INBOX_PILLS_KEY = 'cevico_conversas_inboxes';
const pillInboxes = computed(() => store.getters['inboxes/getInboxes'] || []);
// cor própria por caixa (pedido 16/07) — dourado fica só no "Todas"
const pillGradient = ib => inboxGradientFor(pillInboxes.value, ib.id);
const pillDot = ib => inboxSolidFor(pillInboxes.value, ib.id);
const showInboxPills = computed(
  () =>
    !props.teamId && !props.label && !props.conversationType && !props.foldersId
);
const routeInboxId = computed(() => Number(props.conversationInbox) || 0);

const loadSavedInboxPills = () => {
  try {
    const raw = JSON.parse(localStorage.getItem(INBOX_PILLS_KEY) || '[]');
    return Array.isArray(raw) ? raw.map(Number).filter(Boolean) : [];
  } catch {
    return [];
  }
};
const multiInboxIds = ref(loadSavedInboxPills());

// caixas "acesas": a seleção múltipla, ou a caixa da rota (vinda da sidebar)
const activeInboxSet = computed(() => {
  if (multiInboxIds.value.length) return new Set(multiInboxIds.value);
  return routeInboxId.value ? new Set([routeInboxId.value]) : new Set();
});

const goHomeIfNeeded = () => {
  if (route.name !== 'home') {
    router.push({ name: 'home', params: { accountId: route.params.accountId } });
  }
};

const selectInboxPill = id => {
  if (!id) {
    // "Todas": limpa a seleção
    multiInboxIds.value = [];
  } else {
    const base = multiInboxIds.value.length
      ? [...multiInboxIds.value]
      : (routeInboxId.value ? [routeInboxId.value] : []);
    const idx = base.indexOf(id);
    if (idx >= 0) base.splice(idx, 1);
    else base.push(id);
    multiInboxIds.value = base;
  }
  localStorage.setItem(INBOX_PILLS_KEY, JSON.stringify(multiInboxIds.value));

  if (multiInboxIds.value.length === 1) {
    // 1 caixa = rota nativa (mais leve, carrega tudo daquela caixa)
    const only = multiInboxIds.value[0];
    if (routeInboxId.value !== only) {
      router.push({
        name: 'inbox_dashboard',
        params: { accountId: route.params.accountId, inbox_id: only },
      });
    }
  } else {
    // 0 ou 2+ caixas = visão geral (o filtro local faz o resto)
    goHomeIfNeeded();
  }
};

// pré-seleção: abrir "Conversas" volta para a última escolha
onMounted(() => {
  if (route.name !== 'home' || !showInboxPills.value) return;
  const saved = multiInboxIds.value;
  if (saved.length !== 1) return; // 0 = todas; 2+ = filtro local já aplica
  const applySaved = () => {
    // caixa pode ter sido apagada — só aplica se ainda existe
    if (pillInboxes.value.some(i => i.id === saved[0])) {
      router.replace({
        name: 'inbox_dashboard',
        params: { accountId: route.params.accountId, inbox_id: saved[0] },
      });
    }
  };
  if (pillInboxes.value.length) applySaved();
  else {
    const stop = watch(pillInboxes, list => {
      if (!list.length) return;
      applySaved();
      stop();
    });
  }
});

const resolveAttributesModalRef = ref(null);

// CEVICO 18/07: abas Minhas/Não atribuídas/Todos REMOVIDAS — a lista é
// sempre "todas" (as pílulas de caixa + filtros da jornada organizam)
const activeAssigneeTab = ref(wootConstants.ASSIGNEE_TYPE.ALL);

// ── CEVICO 18/07: filtros da JORNADA no topo do Conversas ──
// estágio do CRM (coluna da jornada) + etiqueta, no lugar das abas
const journeyStageId = ref(null);
const journeyLabel = ref(null);
const crmPipelines = computed(() => store.getters['crm/getPipelines'] || []);
const journeyStages = computed(() =>
  crmPipelines.value.flatMap(p => p.stages || [])
);
const journeyLabels = computed(
  () => store.getters['labels/getLabels'] || []
);
// pílula recolhida mostra o nome/cor do que foi escolhido (pedido 20/07)
const selectedJourneyStage = computed(
  () => journeyStages.value.find(s => s.id === journeyStageId.value) || null
);
const selectedJourneyLabel = computed(
  () => journeyLabels.value.find(l => l.title === journeyLabel.value) || null
);
// item 102 (20/07): JANELINHA selecionável no lugar da nuvem de chips —
// tela limpa; aperta "Colunas CRM" ou "Etiquetas", escolhe, ela se fecha
const filterPanel = ref(null); // null | 'stage' | 'label'
const journeyFilterWrap = ref(null);
const toggleFilterPanel = kind => {
  filterPanel.value = filterPanel.value === kind ? null : kind;
};
const pickJourneyStage = s => {
  journeyStageId.value = s.id;
  filterPanel.value = null;
};
const pickJourneyLabel = l => {
  journeyLabel.value = l.title;
  filterPanel.value = null;
};
onClickOutside(journeyFilterWrap, () => {
  filterPanel.value = null;
});
onMounted(() => {
  if (!crmPipelines.value.length) store.dispatch('crm/fetchPipelines');
  if (!journeyLabels.value.length) store.dispatch('labels/get');
});
// CEVICO: padrão é TODAS as conversas à disposição do time —
// o filtro de status serve para organizar, nunca para esconder
const activeStatus = ref(wootConstants.STATUS_TYPE.ALL);
const activeSortBy = ref(wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC);
const showAdvancedFilters = ref(false);
// chatsOnView is to store the chats that are currently visible on the screen,
// which mirrors the conversationList.
const chatsOnView = ref([]);
const foldersQuery = ref({});
const showAddFoldersModal = ref(false);
const showDeleteFoldersModal = ref(false);
const appliedFilter = ref([]);
const advancedFilterTypes = ref(
  advancedFilterOptions.map(filter => ({
    ...filter,
    attributeName: t(`FILTER.ATTRIBUTES.${filter.attributeI18nKey}`),
  }))
);

const currentUser = useMapGetter('getCurrentUser');
const chatLists = useMapGetter('getFilteredConversations');
const mineChatsList = useMapGetter('getMineChats');
const allChatList = useMapGetter('getAllStatusChats');
const unAssignedChatsList = useMapGetter('getUnAssignedChats');
const participatingChatsList = useMapGetter('getParticipatingChats');
const chatListLoading = useMapGetter('getChatListLoadingStatus');
const activeInbox = useMapGetter('getSelectedInbox');
const conversationStats = useMapGetter('conversationStats/getStats');
const appliedFilters = useMapGetter('getAppliedConversationFiltersV2');
const folders = useMapGetter('customViews/getConversationCustomViews');
const agentList = useMapGetter('agents/getAgents');
const teamsList = useMapGetter('teams/getTeams');
const inboxesList = useMapGetter('inboxes/getInboxes');
const campaigns = useMapGetter('campaigns/getAllCampaigns');
const labels = useMapGetter('labels/getLabels');
const currentAccountId = useMapGetter('getCurrentAccountId');
// We can't useFunctionGetter here since it needs to be called on setup?
const getTeamFn = useMapGetter('teams/getTeam');
const getConversationById = useMapGetter('getConversationById');

const {
  selectedConversations,
  selectedInboxes,
  selectConversation,
  deSelectConversation,
  selectAllConversations,
  resetBulkActions,
  isConversationSelected,
  onAssignAgent,
  onAssignLabels,
  onRemoveLabels,
} = useBulkActions();

const {
  initializeStatusAndAssigneeFilterToModal,
  initializeInboxTeamAndLabelFilterToModal,
} = useFilter({
  filteri18nKey: 'FILTER',
  attributeModel: 'conversation_attribute',
});

const { checkMissingAttributes } = useConversationRequiredAttributes();

// computed

const hasAppliedFilters = computed(() => {
  return appliedFilters.value.length !== 0;
});

const activeFolder = computed(() => {
  if (props.foldersId) {
    const activeView = folders.value.filter(
      view => view.id === Number(props.foldersId)
    );
    const [firstValue] = activeView;
    return firstValue;
  }
  return undefined;
});

const getContact = useMapGetter('contacts/getContact');
const folderContactId = useMapGetter('customViews/getActiveFolderContactId');

const activeFolderName = computed(() => {
  return activeFolder.value?.name;
});

const hasActiveFolders = computed(() => {
  return Boolean(activeFolder.value && props.foldersId !== 0);
});

const hasAppliedFiltersOrActiveFolders = computed(() => {
  return hasAppliedFilters.value || hasActiveFolders.value;
});

const currentUserDetails = computed(() => {
  const { id, name } = currentUser.value;
  return { id, name };
});

const userPermissions = computed(() => {
  return getUserPermissions(currentUser.value, currentAccountId.value);
});

const assigneeTabItems = computed(() => {
  return filterItemsByPermission(
    ASSIGNEE_TYPE_TAB_PERMISSIONS,
    userPermissions.value,
    item => item.permissions
  ).map(({ key, count: countKey }) => ({
    key,
    name: t(`CHAT_LIST.ASSIGNEE_TYPE_TABS.${key}`),
    count: conversationStats.value[countKey] || 0,
  }));
});

const showAssigneeInConversationCard = computed(() => {
  return (
    hasAppliedFiltersOrActiveFolders.value ||
    activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.ALL
  );
});

const currentPageFilterKey = computed(() => {
  return hasAppliedFiltersOrActiveFolders.value
    ? 'appliedFilters'
    : activeAssigneeTab.value;
});

const inbox = useFunctionGetter('inboxes/getInbox', activeInbox);
const currentPage = useFunctionGetter(
  'conversationPage/getCurrentPageFilter',
  activeAssigneeTab
);
const currentFiltersPage = useFunctionGetter(
  'conversationPage/getCurrentPageFilter',
  currentPageFilterKey
);
const hasCurrentPageEndReached = useFunctionGetter(
  'conversationPage/getHasEndReached',
  currentPageFilterKey
);

const conversationCustomAttributes = useFunctionGetter(
  'attributes/getAttributesByModel',
  'conversation_attribute'
);

const activeAssigneeTabCount = computed(() => {
  const count = assigneeTabItems.value.find(
    item => item.key === activeAssigneeTab.value
  ).count;
  return count;
});

const conversationListPagination = computed(() => {
  const conversationsPerPage = 25;
  const hasChatsOnView =
    chatsOnView.value &&
    Array.isArray(chatsOnView.value) &&
    !chatsOnView.value.length;
  const isNoFiltersOrFoldersAndChatListNotEmpty =
    !hasAppliedFiltersOrActiveFolders.value && hasChatsOnView;
  const isUnderPerPage =
    chatsOnView.value.length < conversationsPerPage &&
    activeAssigneeTabCount.value < conversationsPerPage &&
    activeAssigneeTabCount.value > chatsOnView.value.length;

  if (isNoFiltersOrFoldersAndChatListNotEmpty && isUnderPerPage) {
    return 1;
  }

  return currentPage.value + 1;
});

const conversationFilters = computed(() => {
  const journeyLabels_ = journeyLabel.value ? [journeyLabel.value] : undefined;
  return {
    inboxId: props.conversationInbox ? props.conversationInbox : undefined,
    assigneeType: activeAssigneeTab.value,
    status: activeStatus.value,
    sortBy: activeSortBy.value,
    page: conversationListPagination.value,
    labels: props.label ? [props.label] : journeyLabels_,
    teamId: props.teamId || undefined,
    conversationType: props.conversationType || undefined,
    crmStageId: journeyStageId.value || undefined,
  };
});

// trocar estágio/etiqueta da jornada = recarregar a lista do zero
watch([journeyStageId, journeyLabel], () => resetAndFetchData());

const activeTeam = computed(() => {
  if (props.teamId) {
    return getTeamFn.value(props.teamId);
  }
  return {};
});

const pageTitle = computed(() => {
  if (hasAppliedFilters.value) {
    return t('CHAT_LIST.TAB_HEADING');
  }
  if (inbox.value.name) {
    return inbox.value.name;
  }
  if (activeTeam.value.name) {
    return activeTeam.value.name;
  }
  if (props.label) {
    return `#${props.label}`;
  }
  if (props.conversationType === wootConstants.CONVERSATION_TYPE.MENTION) {
    return t('CHAT_LIST.MENTION_HEADING');
  }
  if (
    props.conversationType === wootConstants.CONVERSATION_TYPE.PARTICIPATING
  ) {
    return t('CONVERSATION_PARTICIPANTS.SIDEBAR_MENU_TITLE');
  }
  if (props.conversationType === wootConstants.CONVERSATION_TYPE.UNATTENDED) {
    return t('CHAT_LIST.UNATTENDED_HEADING');
  }
  if (hasActiveFolders.value) {
    return activeFolder.value.name;
  }
  return t('CHAT_LIST.TAB_HEADING');
});

function filterByAssigneeTab(conversations) {
  if (activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.ME) {
    return conversations.filter(
      c => c.meta?.assignee?.id === currentUser.value?.id
    );
  }
  if (activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.UNASSIGNED) {
    return conversations.filter(c => !c.meta?.assignee);
  }
  return [...conversations];
}

function sortByUnreadStatus(conversations) {
  // Não lidas no topo; dentro de cada grupo, da conversa mais RECENTE
  // para a mais antiga (recência manda, não a quantidade de não lidas).
  return [...conversations].sort((a, b) => {
    const aUnread = (a.unread_count || 0) > 0 ? 1 : 0;
    const bUnread = (b.unread_count || 0) > 0 ? 1 : 0;
    if (bUnread !== aUnread) return bUnread - aUnread;

    return (b.last_activity_at || 0) - (a.last_activity_at || 0);
  });
}

const conversationList = computed(() => {
  let localConversationList = [];

  if (!hasAppliedFiltersOrActiveFolders.value) {
    const filters = conversationFilters.value;
    if (
      props.conversationType === wootConstants.CONVERSATION_TYPE.PARTICIPATING
    ) {
      localConversationList = filterByAssigneeTab(
        participatingChatsList.value(filters)
      );
    } else if (activeAssigneeTab.value === 'me') {
      localConversationList = [...mineChatsList.value(filters)];
    } else if (activeAssigneeTab.value === 'unassigned') {
      localConversationList = [...unAssignedChatsList.value(filters)];
    } else {
      localConversationList = [...allChatList.value(filters)];
    }
  } else {
    localConversationList = [...chatLists.value];
  }

  if (activeFolder.value) {
    const { payload } = activeFolder.value.query;
    localConversationList = localConversationList.filter(conversation => {
      return matchesFilters(conversation, payload);
    });
  }

  if (
    !hasAppliedFiltersOrActiveFolders.value &&
    activeSortBy.value === wootConstants.SORT_BY_TYPE.UNREAD
  ) {
    localConversationList = sortByUnreadStatus(localConversationList);
  }

  // CEVICO: 2+ caixas escolhidas nas pílulas = filtra a lista aqui mesmo
  // (1 caixa usa a rota nativa; a combinação de caixas o core não tem)
  if (showInboxPills.value && multiInboxIds.value.length > 1) {
    const wanted = new Set(multiInboxIds.value);
    localConversationList = localConversationList.filter(c =>
      wanted.has(c.inbox_id)
    );
  }

  return localConversationList;
});

const showEndOfListMessage = computed(() => {
  return !!(
    conversationList.value.length &&
    hasCurrentPageEndReached.value &&
    !chatListLoading.value
  );
});

const allConversationsSelected = computed(() => {
  return (
    conversationList.value.length === selectedConversations.value.length &&
    conversationList.value.every(el =>
      selectedConversations.value.includes(el.id)
    )
  );
});

const uniqueInboxes = computed(() => {
  return [...new Set(selectedInboxes.value)];
});

// ---------------------- Methods -----------------------
function setFiltersFromUISettings() {
  const { conversations_filter_by: filterBy = {} } = uiSettings.value;
  const { status, order_by: orderBy } = filterBy;
  activeStatus.value = status || wootConstants.STATUS_TYPE.ALL;
  activeSortBy.value = Object.values(wootConstants.SORT_BY_TYPE).includes(
    orderBy
  )
    ? orderBy
    : wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC;
}

function emitConversationLoaded() {
  emit('conversationLoad');
}

function fetchFilteredConversations(payload) {
  payload = useSnakeCase(payload);
  let page = currentFiltersPage.value + 1;
  store
    .dispatch('fetchFilteredConversations', {
      queryData: filterQueryGenerator(payload),
      page,
    })
    .then(emitConversationLoaded);

  showAdvancedFilters.value = false;
}

function fetchSavedFilteredConversations(payload) {
  payload = useSnakeCase(payload);
  let page = currentFiltersPage.value + 1;
  store
    .dispatch('fetchFilteredConversations', {
      queryData: payload,
      page,
    })
    .then(emitConversationLoaded);
}

function onApplyFilter(payload) {
  payload = useSnakeCase(payload);
  resetBulkActions();
  foldersQuery.value = filterQueryGenerator(payload);
  store.dispatch('conversationPage/reset');
  store.dispatch('emptyAllConversations');
  fetchFilteredConversations(payload);
}

function closeAdvanceFiltersModal() {
  showAdvancedFilters.value = false;
  appliedFilter.value = [];
}

function onUpdateSavedFilter(payload, folderName) {
  const transformedPayload = useSnakeCase(payload);
  const payloadData = {
    ...unref(activeFolder),
    name: unref(folderName),
    query: filterQueryGenerator(transformedPayload),
  };
  store.dispatch('customViews/update', payloadData);
  closeAdvanceFiltersModal();
}

function onClickOpenAddFoldersModal() {
  showAddFoldersModal.value = true;
}

function onCloseAddFoldersModal() {
  showAddFoldersModal.value = false;
}

function onClickOpenDeleteFoldersModal() {
  showDeleteFoldersModal.value = true;
}

function onCloseDeleteFoldersModal() {
  showDeleteFoldersModal.value = false;
}

function setParamsForEditFolderModal() {
  // Here we are setting the params for edit folder modal to show the existing values.

  // For agent, team, inboxes,and campaigns we get only the id's from the query.
  // So we are mapping the id's to the actual values.

  // For labels we get the name of the label from the query.
  // If we delete the label from the label list then we will not be able to show the label name.

  // For custom attributes we get only attribute key.
  // So we are mapping it to find the input type of the attribute to show in the edit folder modal.
  return {
    agents: agentList.value,
    teams: teamsList.value,
    inboxes: inboxesList.value,
    labels: labels.value,
    campaigns: campaigns.value,
    contacts: [getContact.value(folderContactId.value)],
    languages: languages,
    countries: countries,
    priority: [
      { id: 'low', name: t('CONVERSATION.PRIORITY.OPTIONS.LOW') },
      { id: 'medium', name: t('CONVERSATION.PRIORITY.OPTIONS.MEDIUM') },
      { id: 'high', name: t('CONVERSATION.PRIORITY.OPTIONS.HIGH') },
      { id: 'urgent', name: t('CONVERSATION.PRIORITY.OPTIONS.URGENT') },
    ],
    filterTypes: advancedFilterTypes.value,
    allCustomAttributes: conversationCustomAttributes.value,
  };
}

function initializeExistingFilterToModal() {
  const statusFilter = initializeStatusAndAssigneeFilterToModal(
    activeStatus.value,
    currentUserDetails.value,
    activeAssigneeTab.value
  );
  // TODO: Remove the usage of useCamelCase after migrating useFilter to camelcase
  if (statusFilter) {
    appliedFilter.value = [...appliedFilter.value, useCamelCase(statusFilter)];
  }

  // TODO: Remove the usage of useCamelCase after migrating useFilter to camelcase
  const otherFilters = initializeInboxTeamAndLabelFilterToModal(
    props.conversationInbox,
    inbox.value,
    props.teamId,
    activeTeam.value,
    props.label
  ).map(useCamelCase);

  appliedFilter.value = [...appliedFilter.value, ...otherFilters];
}

function initializeFolderToFilterModal(newActiveFolder) {
  // Here we are setting the params for edit folder modal.
  //  To show the existing values. when we click on edit folder button.

  // Here we get the query from the active folder.
  // And we are mapping the query to the actual values.
  // To show in the edit folder modal by the help of generateValuesForEditCustomViews helper.
  const query = unref(newActiveFolder)?.query?.payload;
  if (!Array.isArray(query)) return;

  const newFilters = query.map(filter => {
    const transformed = useCamelCase(filter);
    const values = Array.isArray(transformed.values)
      ? generateValuesForEditCustomViews(
          useSnakeCase(filter),
          setParamsForEditFolderModal()
        )
      : [];

    return {
      attributeKey: transformed.attributeKey,
      attributeModel: transformed.attributeModel,
      customAttributeType: transformed.customAttributeType,
      filterOperator: transformed.filterOperator,
      queryOperator: transformed.queryOperator ?? 'and',
      values,
    };
  });

  appliedFilter.value = [...appliedFilter.value, ...newFilters];
}

function initalizeAppliedFiltersToModal() {
  appliedFilter.value = [...appliedFilters.value];
}

function onToggleAdvanceFiltersModal() {
  if (showAdvancedFilters.value === true) {
    closeAdvanceFiltersModal();
    return;
  }

  if (!hasAppliedFilters.value && !hasActiveFolders.value) {
    initializeExistingFilterToModal();
  }
  if (hasActiveFolders.value) {
    initializeFolderToFilterModal(activeFolder.value);
  }
  if (hasAppliedFilters.value) {
    initalizeAppliedFiltersToModal();
  }

  showAdvancedFilters.value = true;
}

function fetchConversations() {
  store.dispatch('updateChatListFilters', conversationFilters.value);
  store.dispatch('fetchAllConversations').then(emitConversationLoaded);
}

function resetAndFetchData() {
  appliedFilter.value = [];
  resetBulkActions();
  store.dispatch('conversationPage/reset');
  store.dispatch('emptyAllConversations');
  store.dispatch('clearConversationFilters');
  if (hasActiveFolders.value) {
    const payload = activeFolder.value.query;
    fetchSavedFilteredConversations(payload);
  }
  if (props.foldersId) {
    return;
  }
  fetchConversations();
}

function loadMoreConversations() {
  if (hasCurrentPageEndReached.value || chatListLoading.value) {
    return;
  }

  if (!hasAppliedFiltersOrActiveFolders.value) {
    fetchConversations();
  } else if (hasActiveFolders.value) {
    const payload = activeFolder.value.query;
    fetchSavedFilteredConversations(payload);
  } else if (hasAppliedFilters.value) {
    fetchFilteredConversations(appliedFilters.value);
  }
}

function updateAssigneeTab(selectedTab) {
  if (activeAssigneeTab.value !== selectedTab) {
    resetBulkActions();
    emitter.emit('clearSearchInput');
    activeAssigneeTab.value = selectedTab;
    if (!currentPage.value) {
      fetchConversations();
    }
  }
}

function onBasicFilterChange(value, type) {
  if (type === 'status') {
    activeStatus.value = value;
  } else {
    activeSortBy.value = value;
  }
  resetAndFetchData();
}

// Toggle "não lidas no topo" — usa o sort nativo 'unread'
const isUnreadFirst = computed(
  () => activeSortBy.value === wootConstants.SORT_BY_TYPE.UNREAD
);

// CEVICO 19/07: ordenação visível da lista ("da mais recente para a mais
// antiga" e o inverso) — escolher uma ordem sai do modo 'não lidas'.
// Faz o MESMO trio do filtro nativo: refetch + sort do getter da lista
// (setChatSortFilter) + persistência no uiSettings.
const journeyOrder = computed({
  get() {
    return activeSortBy.value === wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_ASC
      ? wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_ASC
      : wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC;
  },
  set(value) {
    store.dispatch('setChatSortFilter', value);
    updateUISettings({
      conversations_filter_by: {
        status: activeStatus.value,
        order_by: value,
      },
    });
    onBasicFilterChange(value, 'sort');
  },
});
function toggleUnreadFirst() {
  const next = isUnreadFirst.value
    ? wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC
    : wootConstants.SORT_BY_TYPE.UNREAD;
  onBasicFilterChange(next, 'sort');
}

function openLastSavedItemInFolder() {
  const lastItemOfFolder = folders.value[folders.value.length - 1];
  const lastItemId = lastItemOfFolder.id;
  router.push({
    name: 'folder_conversations',
    params: { id: lastItemId },
  });
}

function openLastItemAfterDeleteInFolder() {
  if (folders.value.length > 0) {
    openLastSavedItemInFolder();
  } else {
    router.push({ name: 'home' });
    fetchConversations();
  }
}

function redirectToConversationList() {
  const {
    params: { accountId, inbox_id: inboxId, label, teamId },
    name,
  } = route;

  let conversationType = '';
  if (isOnMentionsView({ route: { name } })) {
    conversationType = wootConstants.CONVERSATION_TYPE.MENTION;
  } else if (isOnParticipatingView({ route: { name } })) {
    conversationType = wootConstants.CONVERSATION_TYPE.PARTICIPATING;
  } else if (isOnUnattendedView({ route: { name } })) {
    conversationType = wootConstants.CONVERSATION_TYPE.UNATTENDED;
  }
  router.push(
    conversationListPageURL({
      accountId,
      conversationType: conversationType,
      customViewId: props.foldersId,
      inboxId,
      label,
      teamId,
    })
  );
}

async function assignPriority(priority, conversationId = null) {
  store.dispatch('setCurrentChatPriority', {
    priority,
    conversationId,
  });
  store.dispatch('assignPriority', { conversationId, priority }).then(() => {
    useTrack(CONVERSATION_EVENTS.CHANGE_PRIORITY, {
      newValue: priority,
      from: 'Context menu',
    });
    useAlert(
      t('CONVERSATION.PRIORITY.CHANGE_PRIORITY.SUCCESSFUL', {
        priority,
        conversationId,
      })
    );
  });
}

async function markAsUnread(conversationId) {
  try {
    await store.dispatch('markMessagesUnread', {
      id: conversationId,
    });
    redirectToConversationList();
  } catch (error) {
    // Ignore error
  }
}
async function markAsRead(conversationId) {
  try {
    await store.dispatch('markMessagesRead', {
      id: conversationId,
    });
  } catch (error) {
    // Ignore error
  }
}

async function onAssignTeam(team, conversationId = null) {
  try {
    await store.dispatch('assignTeam', {
      conversationId,
      teamId: team.id,
    });
    useAlert(
      t('CONVERSATION.CARD_CONTEXT_MENU.API.TEAM_ASSIGNMENT.SUCCESFUL', {
        team: team.name,
        conversationId,
      })
    );
  } catch (error) {
    useAlert(t('CONVERSATION.CARD_CONTEXT_MENU.API.TEAM_ASSIGNMENT.FAILED'));
  }
}

function toggleConversationStatus(
  conversationId,
  status,
  snoozedUntil,
  customAttributes = null
) {
  const payload = {
    conversationId,
    status,
    snoozedUntil,
  };

  if (customAttributes) {
    payload.customAttributes = customAttributes;
  }

  store.dispatch('toggleStatus', payload).then(() => {
    useAlert(t('CONVERSATION.CHANGE_STATUS'));
  });
}

function handleResolveConversation(conversationId, status, snoozedUntil) {
  if (status !== wootConstants.STATUS_TYPE.RESOLVED) {
    toggleConversationStatus(conversationId, status, snoozedUntil);
    return;
  }

  // Check for required attributes before resolving
  const conversation = getConversationById.value(conversationId);
  const currentCustomAttributes = conversation?.custom_attributes || {};
  const { hasMissing, missing } = checkMissingAttributes(
    currentCustomAttributes
  );

  if (hasMissing) {
    // Pass conversation context through the modal's API
    const conversationContext = {
      id: conversationId,
      snoozedUntil,
    };
    resolveAttributesModalRef.value?.open(
      missing,
      currentCustomAttributes,
      conversationContext
    );
  } else {
    toggleConversationStatus(conversationId, status, snoozedUntil);
  }
}

function handleResolveWithAttributes({ attributes, context }) {
  if (context) {
    const existingConversation = getConversationById.value(context.id);
    const currentCustomAttributes =
      existingConversation?.custom_attributes || {};
    const mergedAttributes = { ...currentCustomAttributes, ...attributes };

    toggleConversationStatus(
      context.id,
      wootConstants.STATUS_TYPE.RESOLVED,
      context.snoozedUntil,
      mergedAttributes
    );
  }
}

function allSelectedConversationsStatus(status) {
  if (!selectedConversations.value.length) return false;
  return selectedConversations.value.every(item => {
    return getConversationById.value(item)?.status === status;
  });
}

function toggleSelectAll(check) {
  selectAllConversations(check, conversationList);
}

useEmitter('fetch_conversation_stats', () => {
  if (hasAppliedFiltersOrActiveFolders.value) return;
  store.dispatch('conversationStats/get', conversationFilters.value);
});

onMounted(() => {
  store.dispatch('setChatListFilters', conversationFilters.value);
  setFiltersFromUISettings();
  store.dispatch('setChatStatusFilter', activeStatus.value);
  store.dispatch('setChatSortFilter', activeSortBy.value);
  resetAndFetchData();
  if (hasActiveFolders.value) {
    store.dispatch('campaigns/get');
  }
});

const deleteConversationDialogRef = ref(null);
const selectedConversationId = ref(null);

async function deleteConversation() {
  try {
    await store.dispatch('deleteConversation', selectedConversationId.value);
    redirectToConversationList();
    selectedConversationId.value = null;
    deleteConversationDialogRef.value.close();
    useAlert(t('CONVERSATION.SUCCESS_DELETE_CONVERSATION'));
  } catch (error) {
    useAlert(t('CONVERSATION.FAIL_DELETE_CONVERSATION'));
  }
}

const handleDelete = conversationId => {
  selectedConversationId.value = conversationId;
  deleteConversationDialogRef.value.open();
};

provide('selectConversation', selectConversation);
provide('deSelectConversation', deSelectConversation);
provide('assignAgent', onAssignAgent);
provide('assignTeam', onAssignTeam);
provide('assignLabels', onAssignLabels);
provide('removeLabels', onRemoveLabels);
provide('updateConversationStatus', handleResolveConversation);
provide('markAsUnread', markAsUnread);
provide('markAsRead', markAsRead);
provide('assignPriority', assignPriority);
provide('isConversationSelected', isConversationSelected);
provide('deleteConversation', handleDelete);

watch(activeTeam, () => resetAndFetchData());

watch(
  computed(() => props.conversationInbox),
  () => resetAndFetchData()
);
watch(
  computed(() => props.label),
  () => resetAndFetchData()
);
watch(
  computed(() => props.conversationType),
  () => resetAndFetchData()
);

watch(activeFolder, (newVal, oldVal) => {
  if (newVal !== oldVal) {
    store.dispatch('customViews/setActiveConversationFolder', newVal || null);
  }
  resetAndFetchData();
});

watch(chatLists, () => {
  chatsOnView.value = conversationList.value;
});

watch(conversationFilters, (newVal, oldVal) => {
  if (newVal !== oldVal) {
    store.dispatch('updateChatListFilters', newVal);
  }
});
</script>

<template>
  <div
    class="flex flex-col flex-shrink-0 conversations-list-wrap bg-n-surface-1 relative"
    :class="[
      { hidden: !showConversationList },
      isOnExpandedLayout ? 'basis-full' : 'w-[340px] 2xl:w-[412px]',
    ]"
  >
    <slot />
    <ChatListHeader
      :page-title="pageTitle"
      :has-applied-filters="hasAppliedFilters"
      :has-active-folders="hasActiveFolders"
      :active-status="activeStatus"
      :is-on-expanded-layout="isOnExpandedLayout"
      :conversation-stats="conversationStats"
      :is-list-loading="chatListLoading && !conversationList.length"
      @add-folders="onClickOpenAddFoldersModal"
      @delete-folders="onClickOpenDeleteFoldersModal"
      @filters-modal="onToggleAdvanceFiltersModal"
      @reset-filters="resetAndFetchData"
      @basic-filter-change="onBasicFilterChange"
    />

    <!-- CEVICO: escolha das caixas de entrada (aceita várias; salva no navegador).
         Enquadramento (pedido 19/07): mesma calha horizontal do cabeçalho (px-3) -->
    <div
      v-if="showInboxPills && pillInboxes.length"
      class="cevico-no-scrollbar flex items-center bg-n-solid-2 border border-n-weak rounded-xl p-0.5 gap-0.5 mx-3 mb-1.5 overflow-x-auto flex-shrink-0"
    >
      <button
        class="px-3 h-7 rounded-lg text-xs font-medium whitespace-nowrap transition-colors flex-shrink-0"
        :class="activeInboxSet.size === 0 ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
        :style="activeInboxSet.size === 0 ? { background: 'linear-gradient(135deg, #B8860B, #D4A017)' } : {}"
        @click="selectInboxPill(0)"
      >
        Todas
      </button>
      <button
        v-for="ib in pillInboxes"
        :key="ib.id"
        class="px-3 h-7 rounded-lg text-xs font-medium whitespace-nowrap transition-colors flex-shrink-0 flex items-center gap-1.5"
        :class="activeInboxSet.has(ib.id) ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
        :style="activeInboxSet.has(ib.id) ? { background: pillGradient(ib) } : {}"
        :title="activeInboxSet.has(ib.id) ? 'Clique para tirar esta caixa da seleção' : 'Clique para somar esta caixa à seleção'"
        @click="selectInboxPill(ib.id)"
      >
        <span
          v-if="!activeInboxSet.has(ib.id)"
          class="w-1.5 h-1.5 rounded-full flex-shrink-0"
          :style="{ background: pillDot(ib) }"
        />
        {{ ib.name }}
      </button>
    </div>

    <TeleportWithDirection
      v-if="showAddFoldersModal"
      to="#saveFilterTeleportTarget"
    >
      <SaveCustomView
        v-model="appliedFilter"
        :custom-views-query="foldersQuery"
        :open-last-saved-item="openLastSavedItemInFolder"
        @close="onCloseAddFoldersModal"
      />
    </TeleportWithDirection>

    <DeleteCustomViews
      v-if="showDeleteFoldersModal"
      v-model:show="showDeleteFoldersModal"
      :active-custom-view="activeFolder"
      :custom-views-id="foldersId"
      :open-last-item-after-delete="openLastItemAfterDeleteInFolder"
      @close="onCloseDeleteFoldersModal"
    />

    <!-- CEVICO item 102 (20/07): filtros da jornada em JANELINHA — tela
         limpa. Dois botões (Colunas CRM | Etiquetas); apertou, abre a
         janelinha com as opções; escolheu, fecha e sobra a pílula colorida -->
    <div
      v-if="!hasAppliedFiltersOrActiveFolders"
      ref="journeyFilterWrap"
      class="mx-3 mt-1.5 mb-0.5 space-y-1 relative"
    >
      <div class="flex items-center gap-1.5 flex-wrap">
        <!-- Colunas CRM: gatilho ou pílula do selecionado -->
        <button
          v-if="!journeyStageId"
          class="inline-flex items-center gap-1 px-2 h-6 rounded-lg border text-[11px] font-medium transition-colors"
          :class="filterPanel === 'stage'
            ? 'border-n-brand bg-n-brand/10 text-n-brand'
            : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
          @click="toggleFilterPanel('stage')"
        >
          <span class="i-lucide-columns-3 text-[11px]" />
          Colunas CRM
          <span class="i-lucide-chevron-down text-[10px]" />
        </button>
        <button
          v-else
          class="inline-flex items-center gap-1.5 px-2.5 h-6 rounded-full text-[11px] font-semibold text-white transition-transform hover:scale-[1.02]"
          :style="{ background: selectedJourneyStage?.color || '#2563EB' }"
          title="Clique para limpar"
          @click="journeyStageId = null"
        >
          {{ selectedJourneyStage?.name || 'Coluna' }}
          <span class="i-lucide-x text-[10px]" />
        </button>

        <!-- Etiquetas: gatilho ou pílula do selecionado -->
        <button
          v-if="!journeyLabel"
          class="inline-flex items-center gap-1 px-2 h-6 rounded-lg border text-[11px] font-medium transition-colors"
          :class="filterPanel === 'label'
            ? 'border-n-brand bg-n-brand/10 text-n-brand'
            : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
          @click="toggleFilterPanel('label')"
        >
          <span class="i-lucide-tag text-[11px]" />
          Etiquetas
          <span class="i-lucide-chevron-down text-[10px]" />
        </button>
        <button
          v-else
          class="inline-flex items-center gap-1.5 px-2.5 h-6 rounded-full text-[11px] font-semibold text-white transition-transform hover:scale-[1.02]"
          :style="{ background: selectedJourneyLabel?.color || '#2563EB' }"
          title="Clique para limpar"
          @click="journeyLabel = null"
        >
          {{ journeyLabel }}
          <span class="i-lucide-x text-[10px]" />
        </button>
      </div>

      <!-- a JANELINHA (abre por cima da lista, fecha ao escolher/clicar fora) -->
      <div
        v-if="filterPanel"
        class="absolute z-30 left-0 right-0 top-7 bg-n-solid-1 border border-n-weak rounded-xl shadow-xl p-2.5"
      >
        <div class="flex items-center gap-1 mb-2">
          <button
            class="px-2.5 h-6 rounded-lg text-[11px] font-semibold transition-colors"
            :class="filterPanel === 'stage' ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
            :style="filterPanel === 'stage' ? 'background: linear-gradient(135deg, #152C61, #3B82F6)' : ''"
            @click="filterPanel = 'stage'"
          >
            Colunas CRM
          </button>
          <button
            class="px-2.5 h-6 rounded-lg text-[11px] font-semibold transition-colors"
            :class="filterPanel === 'label' ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
            :style="filterPanel === 'label' ? 'background: linear-gradient(135deg, #B8860B, #D4AF37)' : ''"
            @click="filterPanel = 'label'"
          >
            Etiquetas
          </button>
          <button
            class="ml-auto w-6 h-6 rounded-lg flex items-center justify-center text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1"
            @click="filterPanel = null"
          >
            <span class="i-lucide-x text-xs" />
          </button>
        </div>
        <div class="flex flex-wrap gap-1 max-h-44 overflow-y-auto" style="scrollbar-width: thin;">
          <template v-if="filterPanel === 'stage'">
            <button
              v-for="s in journeyStages"
              :key="s.id"
              class="inline-flex items-center gap-1 px-2 h-6 rounded-full border border-n-weak text-[11px] text-n-slate-11 hover:bg-n-alpha-1 hover:border-n-brand/50 transition-colors whitespace-nowrap"
              @click="pickJourneyStage(s)"
            >
              <span class="w-1.5 h-1.5 rounded-full flex-shrink-0" :style="{ background: s.color || '#94A3B8' }" />
              {{ s.name }}
            </button>
          </template>
          <template v-else>
            <button
              v-for="lb in journeyLabels"
              :key="lb.id"
              class="inline-flex items-center gap-1 px-2 h-6 rounded-full border border-n-weak text-[11px] text-n-slate-11 hover:bg-n-alpha-1 hover:border-n-brand/50 transition-colors whitespace-nowrap"
              @click="pickJourneyLabel(lb)"
            >
              <span class="w-1.5 h-1.5 rounded-full flex-shrink-0" :style="{ background: lb.color || '#94A3B8' }" />
              {{ lb.title }}
            </button>
          </template>
        </div>
      </div>

      <!-- Não lidas no topo + ordenação (2 opções sempre à vista) -->
      <div class="flex items-center gap-1.5 flex-wrap">
        <button
          class="flex items-center gap-2 px-2 py-1 rounded-lg text-xs transition-colors flex-shrink-0"
          :class="isUnreadFirst
            ? 'bg-n-brand/10 text-n-brand'
            : 'text-n-slate-11 hover:bg-n-alpha-1'"
          @click="toggleUnreadFirst"
        >
          <span
            class="w-3.5 h-3.5 rounded border flex items-center justify-center flex-shrink-0"
            :class="isUnreadFirst ? 'bg-n-brand border-n-brand' : 'border-n-slate-8'"
          >
            <span v-if="isUnreadFirst" class="i-lucide-check text-white text-[10px]" />
          </span>
          {{ $t('CHAT_LIST.UNREAD_FIRST') }}
        </button>
        <div class="flex items-center gap-1 ml-auto">
          <button
            class="inline-flex items-center gap-1 px-2 h-6 rounded-full text-[10px] font-medium border transition-colors"
            :class="journeyOrder === 'last_activity_at_desc'
              ? 'border-n-brand bg-n-brand/10 text-n-brand font-bold'
              : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
            title="Da mais recente para a mais antiga"
            @click="journeyOrder = 'last_activity_at_desc'"
          >
            <span class="i-lucide-arrow-down text-[10px]" /> Recentes primeiro
          </button>
          <button
            class="inline-flex items-center gap-1 px-2 h-6 rounded-full text-[10px] font-medium border transition-colors"
            :class="journeyOrder === 'last_activity_at_asc'
              ? 'border-n-brand bg-n-brand/10 text-n-brand font-bold'
              : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
            title="Da mais antiga para a mais recente"
            @click="journeyOrder = 'last_activity_at_asc'"
          >
            <span class="i-lucide-arrow-up text-[10px]" /> Antigas primeiro
          </button>
        </div>
      </div>
    </div>

    <p
      v-if="!chatListLoading && !conversationList.length"
      class="flex overflow-auto justify-center items-center p-4"
    >
      {{ $t('CHAT_LIST.LIST.404') }}
    </p>
    <ConversationBulkActions
      :conversations="selectedConversations"
      :all-conversations-selected="allConversationsSelected"
      :selected-inboxes="uniqueInboxes"
      :show-open-action="allSelectedConversationsStatus('open')"
      :show-resolved-action="allSelectedConversationsStatus('resolved')"
      :show-snoozed-action="allSelectedConversationsStatus('snoozed')"
      :class="isOnExpandedLayout && 'sm:!w-[24rem] !w-full'"
      @select-all-conversations="toggleSelectAll"
    />
    <ConversationList
      :conversation-list="conversationList"
      :is-loading="chatListLoading"
      :show-end-of-list-message="showEndOfListMessage"
      :label="label"
      :team-id="teamId"
      :folders-id="foldersId"
      :conversation-type="conversationType"
      :show-assignee="showAssigneeInConversationCard"
      :is-on-expanded-layout="isOnExpandedLayout"
      @load-more="loadMoreConversations"
    />
    <Dialog
      ref="deleteConversationDialogRef"
      type="alert"
      :title="
        $t('CONVERSATION.DELETE_CONVERSATION.TITLE', {
          conversationId: selectedConversationId,
        })
      "
      :description="$t('CONVERSATION.DELETE_CONVERSATION.DESCRIPTION')"
      :confirm-button-label="$t('CONVERSATION.DELETE_CONVERSATION.CONFIRM')"
      @confirm="deleteConversation"
      @close="selectedConversationId = null"
    />
    <TeleportWithDirection
      v-if="showAdvancedFilters"
      to="#conversationFilterTeleportTarget"
    >
      <ConversationFilter
        v-model="appliedFilter"
        :folder-name="activeFolderName"
        :is-folder-view="hasActiveFolders"
        @apply-filter="onApplyFilter"
        @update-folder="onUpdateSavedFilter"
        @close="closeAdvanceFiltersModal"
      />
    </TeleportWithDirection>
    <ConversationResolveAttributesModal
      ref="resolveAttributesModalRef"
      @submit="handleResolveWithAttributes"
    />
  </div>
</template>

<style scoped>
/* pílulas de caixa: desliza no dedo/scroll SEM barra de rolagem aparente
   (pedido 20/07 — mobile clean) */
.cevico-no-scrollbar {
  scrollbar-width: none;
  -ms-overflow-style: none;
}
.cevico-no-scrollbar::-webkit-scrollbar {
  display: none;
}
</style>
