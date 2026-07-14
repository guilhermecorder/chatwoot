<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import draggable from 'vuedraggable';
import KanbanColumn from './components/KanbanColumn.vue';
import ContactModal from './components/ContactModal.vue';
import CrmIntegrationsModal from './components/CrmIntegrationsModal.vue';
import ConversationChatModal from './components/ConversationChatModal.vue';
import ColumnPresetsModal from './components/ColumnPresetsModal.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ContactAPI from 'dashboard/api/contacts';

const store = useStore();
const { isAdmin } = useAdmin();
const { t } = useI18n();

const pipelines = useMapGetter('crm/getPipelines');
const allContacts = useMapGetter('crm/getContacts');
const contactsMeta = useMapGetter('crm/getContactsMeta');
const uiFlags = useMapGetter('crm/getUIFlags');
const agents = useMapGetter('agents/getAgents');
const crmSettings = useMapGetter('crm/getSettings');

const selectedPipelineId = ref(null);
const selectedContact = ref(null);
const chatContact = ref(null); // popup de conversa oficial

// New pipeline form
const showNewPipelineForm = ref(false);
const newPipelineName = ref('');

// Rename pipeline
const isRenamingPipeline = ref(false);
const renamePipelineValue = ref('');

// Delete pipeline
const showDeletePipelineConfirm = ref(false);

// New stage form
const showNewStageForm = ref(false);
const newStageName = ref('');
const newStageColor = ref('#6B7280');

// Add contact modal
// Carga em DUAS FASES: primeiro os 15 cards mais recentes de cada coluna
// (abertura instantânea), depois a JANELA DE TRABALHO completa em background.
// A base inteira (9k+ cards) só entra sob demanda (busca / botão "Tudo") —
// carregar tudo sempre travava máquinas fracas (i3/celular).
const WINDOW_OPTIONS = [7, 15, 30];
const windowDays = ref(
  Number(localStorage.getItem('cevico_crm_window_days')) || 7
);
const contactsScope = ref('days');
const isLoadingAll = ref(false);
const isBackgroundLoading = ref(false);

// payload de escopo atual (janela de N dias ou base completa)
const scopePayload = () =>
  contactsScope.value === 'days'
    ? { scope: 'days', days: windowDays.value }
    : { scope: contactsScope.value };

const loadBoard = async pipelineId => {
  await store.dispatch('crm/fetchContacts', { pipelineId, scope: 'preview' });
  isBackgroundLoading.value = true;
  store
    .dispatch('crm/fetchContacts', { pipelineId, ...scopePayload(), silent: true })
    .catch(() => {})
    .finally(() => { isBackgroundLoading.value = false; });
};

const setWindowDays = async d => {
  windowDays.value = d;
  localStorage.setItem('cevico_crm_window_days', String(d));
  contactsScope.value = 'days';
  if (!selectedPipelineId.value) return;
  await store.dispatch('crm/fetchContacts', {
    pipelineId: selectedPipelineId.value,
    ...scopePayload(),
  });
};
const addContactStageId = ref(null);
const contactSearchQuery = ref('');
const contactSearchResults = ref([]);
const isSearching = ref(false);
const addContactTab = ref('search'); // 'search' | 'create'
const newContact = ref({ name: '', phone_number: '', email: '' });
const isCreatingContact = ref(false);

// ── Filters ──────────────────────────────────────────────
const showFilters = ref(false);
const showLabelsDropdown = ref(false);
const showStagesDropdown = ref(false);

// Estado inicial dos filtros — CRM abre no MÊS ATUAL (leve) por padrão.
const makeDefaultFilters = () => ({
  search: '',
  assigneeId: '',  // '' = all, 'none' = no assignee, number = agent id
  labels: [],      // array of label strings
  inboxName: '',
  stageIds: [],    // etapas selecionadas (multi)
  createdAt: '', // todo o período — a ordenação por última mensagem prioriza o que importa
  lastActivity: '',
  dateFrom: '',    // período do lead (data real do contato) — De
  dateTo: '',      // período do lead — Até
  awaitingOnly: false, // só pacientes sem resposta
});

const filters = ref(makeDefaultFilters());

// Painel expandido usa RASCUNHO — só refiltra ao clicar em "Aplicar"
// (com milhares de cards, refiltrar a cada clique pesa).
const panelDraft = ref(null);

const openFiltersPanel = () => {
  const f = filters.value;
  panelDraft.value = {
    assigneeId: f.assigneeId,
    labels: [...f.labels],
    stageIds: [...f.stageIds],
    createdAt: f.createdAt,
    lastActivity: f.lastActivity,
    dateFrom: f.dateFrom,
    dateTo: f.dateTo,
  };
  showFilters.value = true;
};

const applyFiltersPanel = () => {
  Object.assign(filters.value, {
    ...panelDraft.value,
    labels: [...panelDraft.value.labels],
    stageIds: [...panelDraft.value.stageIds],
  });
  showFilters.value = false;
  showLabelsDropdown.value = false;
  showStagesDropdown.value = false;
};

// Ordenação dos cards dentro das colunas
// 'lastMessage' (padrão) = não lidas no topo, depois última mensagem recente→antiga
// 'waiting' = aguardando há mais tempo | 'oldest'/'newest' = data de entrada
// '' = manual (posição)
const sortOrder = ref('lastMessage');

// Presets de visualização de colunas — pode selecionar VÁRIOS ao mesmo
// tempo (união das colunas); nenhum selecionado = todas as colunas.
const loadStoredPresets = () => {
  try {
    const multi = JSON.parse(localStorage.getItem('cevico_crm_column_presets') ?? 'null');
    if (Array.isArray(multi)) return multi;
  } catch { /* ignora valor corrompido */ }
  const legacy = localStorage.getItem('cevico_crm_column_preset');
  return legacy ? [legacy] : [];
};

const activePresetNames = ref(loadStoredPresets());
const showPresetsModal = ref(false);

const columnPresets = computed(() => crmSettings.value.column_presets ?? []);

const activePresets = computed(() =>
  columnPresets.value.filter(p => activePresetNames.value.includes(p.name))
);

const persistPresetSelection = () => {
  localStorage.setItem('cevico_crm_column_presets', JSON.stringify(activePresetNames.value));
};

const togglePreset = name => {
  const idx = activePresetNames.value.indexOf(name);
  if (idx === -1) activePresetNames.value.push(name);
  else activePresetNames.value.splice(idx, 1);
  persistPresetSelection();
};

const clearPresets = () => {
  activePresetNames.value = [];
  persistPresetSelection();
};

const visibleStageIdSet = computed(() => {
  if (!activePresets.value.length) return null; // null = todas
  const ids = new Set();
  activePresets.value.forEach(p => (p.stage_ids ?? []).forEach(id => ids.add(Number(id))));
  return ids;
});

const isStageVisible = stageId => {
  if (isEditMode.value || !visibleStageIdSet.value) return true;
  return visibleStageIdSet.value.has(Number(stageId));
};

const onPresetsSaved = () => {
  showPresetsModal.value = false;
  // remove seleções de presets renomeados/apagados
  const names = columnPresets.value.map(p => p.name);
  activePresetNames.value = activePresetNames.value.filter(n => names.includes(n));
  persistPresetSelection();
};

const datePresets = computed(() => [
  { value: '',         label: t('CRM.FILTER.ALL_PERIODS') },
  { value: 'today',    label: t('CRM.FILTER.TODAY') },
  { value: 'yesterday',label: t('CRM.FILTER.YESTERDAY') },
  { value: '7days',    label: t('CRM.FILTER.LAST_7_DAYS') },
  { value: '30days',   label: t('CRM.FILTER.LAST_30_DAYS') },
  { value: 'month',    label: t('CRM.FILTER.THIS_MONTH') },
  { value: 'year',     label: t('CRM.FILTER.THIS_YEAR') },
]);

const matchesDatePreset = (dateStr, preset) => {
  if (!preset || !dateStr) return !preset;
  const date = new Date(dateStr);
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  switch (preset) {
    case 'today':     return date >= today;
    case 'yesterday': { const d = new Date(today); d.setDate(d.getDate()-1); return date >= d && date < today; }
    case '7days':     { const d = new Date(today); d.setDate(d.getDate()-7); return date >= d; }
    case '30days':    { const d = new Date(today); d.setDate(d.getDate()-30); return date >= d; }
    case 'month':     return date >= new Date(today.getFullYear(), today.getMonth(), 1);
    case 'year':      return date >= new Date(today.getFullYear(), 0, 1);
    default:          return true;
  }
};

const filteredContacts = computed(() => {
  // Busca ativa IGNORA o filtro de período — quem busca um nome quer achar
  // o paciente mesmo que ele seja de outro mês (o padrão é "mês atual").
  const searching = !!filters.value.search;
  return allContacts.value.filter(c => {
    // Search: name, phone, labels, notes
    if (searching) {
      const q = filters.value.search.toLowerCase();
      const hit = (c.name?.toLowerCase().includes(q)) ||
                  (c.phone_number?.includes(q)) ||
                  (c.labels?.some(l => l.toLowerCase().includes(q))) ||
                  (c.notes?.toLowerCase().includes(q));
      if (!hit) return false;
    }
    // Assignee
    if (filters.value.assigneeId !== '') {
      if (filters.value.assigneeId === 'none') {
        if (c.assignee != null) return false;
      } else if (c.assignee?.id !== Number(filters.value.assigneeId)) {
        return false;
      }
    }
    // Labels: show contacts that have ANY of the selected labels
    if (filters.value.labels.length > 0) {
      const contactLabels = c.labels ?? [];
      if (!filters.value.labels.some(l => contactLabels.includes(l))) return false;
    }
    // Inbox
    if (filters.value.inboxName && c.last_conversation?.inbox_name !== filters.value.inboxName) {
      return false;
    }
    // Etapas (multi)
    if (filters.value.stageIds.length > 0 && !filters.value.stageIds.map(Number).includes(Number(c.stage_id))) {
      return false;
    }
    // Created at — usa a data real do lead (contato), não a de importação
    if (!searching && filters.value.createdAt && !matchesDatePreset(c.contact_created_at, filters.value.createdAt)) {
      return false;
    }
    // Período customizado De/Até (data real do lead)
    if (!searching && (filters.value.dateFrom || filters.value.dateTo)) {
      const d = c.contact_created_at ? new Date(c.contact_created_at) : null;
      if (!d) return false;
      if (filters.value.dateFrom && d < new Date(filters.value.dateFrom + 'T00:00:00')) return false;
      if (filters.value.dateTo && d > new Date(filters.value.dateTo + 'T23:59:59')) return false;
    }
    // Last activity
    if (filters.value.lastActivity) {
      if (filters.value.lastActivity === 'none') {
        const cutoff = new Date(); cutoff.setDate(cutoff.getDate() - 30);
        if (c.last_activity_at && new Date(c.last_activity_at) >= cutoff) return false;
      } else if (!matchesDatePreset(c.last_activity_at, filters.value.lastActivity)) {
        return false;
      }
    }
    // Sem resposta (paciente aguardando)
    if (filters.value.awaitingOnly && !c.last_conversation?.awaiting_reply) {
      return false;
    }
    return true;
  });
});

// Total de pacientes sem resposta (independente do toggle)
const awaitingCount = computed(() =>
  allContacts.value.filter(c => c.last_conversation?.awaiting_reply).length
);

const availableLabels = computed(() => {
  const set = new Set();
  allContacts.value.forEach(c => c.labels?.forEach(l => set.add(l)));
  return [...set].sort();
});

const availableInboxes = computed(() => {
  const set = new Set();
  allContacts.value.forEach(c => {
    if (c.last_conversation?.inbox_name) set.add(c.last_conversation.inbox_name);
  });
  return [...set].sort();
});

const totalContacts = computed(() => allContacts.value.length);
const filteredCount = computed(() => filteredContacts.value.length);

const activeFilterCount = computed(() => {
  let n = 0;
  if (filters.value.search)            n++;
  if (filters.value.assigneeId !== '') n++;
  if (filters.value.labels.length > 0) n++;
  if (filters.value.inboxName)         n++;
  if (filters.value.stageIds.length > 0) n++;
  if (filters.value.createdAt)         n++;
  if (filters.value.lastActivity)      n++;
  if (filters.value.dateFrom || filters.value.dateTo) n++;
  if (filters.value.awaitingOnly)      n++;
  return n;
});

const hasActiveFilters = computed(() => activeFilterCount.value > 0);

const allFilteredOut = computed(() =>
  hasActiveFilters.value && filteredCount.value === 0
);

const loadAllContacts = async () => {
  if (isLoadingAll.value) return;
  isLoadingAll.value = true;
  contactsScope.value = 'all';
  try {
    await store.dispatch('crm/fetchContacts', {
      pipelineId: selectedPipelineId.value,
      scope: 'all',
    });
  } finally {
    isLoadingAll.value = false;
  }
};

const clearFilters = () => {
  filters.value = { ...makeDefaultFilters(), createdAt: '' }; // limpar = ver tudo
  panelDraft.value = null;
  showFilters.value = false;
};

// Buscar precisa enxergar a base toda: se ela ainda não foi carregada,
// dispara o carregamento completo na primeira busca (o loadAllContacts
// já se protege contra chamadas duplicadas).
watch(() => filters.value.search, term => {
  if (
    term &&
    contactsMeta.value.scope !== 'all' &&
    contactsMeta.value.total > contactsMeta.value.shown
  ) {
    loadAllContacts();
  }
});

// ─────────────────────────────────────────────────────────

const selectedPipeline = computed(() =>
  pipelines.value.find(p => p.id === selectedPipelineId.value) ?? null
);

const sortCards = cards => {
  if (!sortOrder.value) return cards;
  const byLeadDate = c => (c.contact_created_at ? new Date(c.contact_created_at).getTime() : 0);
  const sorted = [...cards];
  if (sortOrder.value === 'lastMessage') {
    // não lidas no topo; dentro de cada grupo, última mensagem recente→antiga
    const hasUnread = c => ((c.last_conversation?.unread_count ?? 0) > 0 ? 1 : 0);
    const lastMsgAt = c => {
      const ts = c.last_conversation?.last_message_at || c.last_activity_at;
      return ts ? new Date(ts).getTime() : 0;
    };
    sorted.sort((a, b) => {
      const unreadDiff = hasUnread(b) - hasUnread(a);
      if (unreadDiff !== 0) return unreadDiff;
      return lastMsgAt(b) - lastMsgAt(a);
    });
  }
  if (sortOrder.value === 'oldest') sorted.sort((a, b) => byLeadDate(a) - byLeadDate(b));
  if (sortOrder.value === 'newest') sorted.sort((a, b) => byLeadDate(b) - byLeadDate(a));
  if (sortOrder.value === 'waiting') {
    // aguardando há mais tempo primeiro; quem não aguarda vai para o fim
    const waitKey = c => {
      const w = c.last_conversation?.awaiting_reply && c.last_conversation?.waiting_since;
      return w ? new Date(w).getTime() : Infinity;
    };
    sorted.sort((a, b) => waitKey(a) - waitKey(b));
  }
  return sorted;
};

const contactsByStage = computed(() => {
  const map = {};
  if (!selectedPipeline.value) return map;
  for (const stage of selectedPipeline.value.stages) {
    map[stage.id] = sortCards(filteredContacts.value.filter(c => c.stage_id === stage.id));
  }
  return map;
});

// IDs de contatos já adicionados ao pipeline atual (contact_id do Chatwoot)
const alreadyAddedContactIds = computed(() =>
  new Set(allContacts.value.map(c => c.contact_id))
);

const filteredSearchResults = computed(() =>
  contactSearchResults.value.filter(c => !alreadyAddedContactIds.value.has(c.id))
);

const alreadyInPipelineResults = computed(() =>
  contactSearchResults.value.filter(c => alreadyAddedContactIds.value.has(c.id))
);

// ── Edit mode & Programming mode ──────────────────────────
const isEditMode           = ref(false);
const isProgrammingMode    = ref(false);
const showIntegrationsModal = ref(false);
// ──────────────────────────────────────────────────────────

onMounted(async () => {
  if (!agents.value.length) store.dispatch('agents/get');
  store.dispatch('crm/fetchSettings'); // presets de colunas
  await store.dispatch('crm/fetchPipelines');
  if (pipelines.value.length) {
    selectedPipelineId.value = pipelines.value[0].id;
    await loadBoard(selectedPipelineId.value);
  }
  // ?programming=1 abre direto no Modo Programação (link do hub de Automações)
  if (new URLSearchParams(window.location.search).get('programming') === '1' && isAdmin.value) {
    isProgrammingMode.value = true;
  }
});

// ── Chat popup (conversa oficial) ─────────────────────────
const openChat = contact => {
  if (!contact) return;
  chatContact.value = contact;
  // abrir o popup marca a conversa como lida (se houver conversa)
  if (contact.last_conversation_id) {
    store.commit('crm/patchContactConversation', {
      id: contact.id,
      data: { unread_count: 0 },
    });
  }
};

const onChatReplied = () => {
  if (!chatContact.value) return;
  store.commit('crm/patchContactConversation', {
    id: chatContact.value.id,
    data: { unread_count: 0, awaiting_reply: false, waiting_since: null },
  });
};

const onChatResolved = ({ status }) => {
  if (!chatContact.value) return;
  // resolvida conta como respondida
  const data = status === 'resolved'
    ? { status, awaiting_reply: false, waiting_since: null }
    : { status };
  store.commit('crm/patchContactConversation', {
    id: chatContact.value.id,
    data,
  });
};

const selectPipeline = async (id) => {
  if (selectedPipelineId.value === id) return;
  selectedPipelineId.value = id;
  isRenamingPipeline.value = false;
  showDeletePipelineConfirm.value = false;
  isEditMode.value = false;
  isProgrammingMode.value = false;
  filters.value = makeDefaultFilters(); // volta ao padrão
  await loadBoard(id);
};

// Save normal é LEVE: o store já foi atualizado (updateContact + patch de
// etiquetas) — só fecha o modal, sem recarregar o board.
const onContactUpdated = () => {
  selectedContact.value = null;
};

// Merge de contatos muda vários cards → refetch completo.
const onContactMerged = async () => {
  selectedContact.value = null;
  if (selectedPipelineId.value) {
    await store.dispatch('crm/fetchContacts', { pipelineId: selectedPipelineId.value, ...scopePayload() });
  }
};

// --- Pipeline CRUD ---

const createPipeline = async () => {
  if (!newPipelineName.value.trim()) return;
  try {
    const p = await store.dispatch('crm/createPipeline', { name: newPipelineName.value });
    newPipelineName.value = '';
    showNewPipelineForm.value = false;
    selectedPipelineId.value = p.id;
    await store.dispatch('crm/fetchContacts', { pipelineId: p.id, ...scopePayload() });
    useAlert(t('CRM.SUCCESS.PIPELINE_CREATED'));
  } catch {
    useAlert(t('CRM.ERROR.GENERIC'));
  }
};

const startRenamePipeline = () => {
  renamePipelineValue.value = selectedPipeline.value.name;
  isRenamingPipeline.value = true;
  showDeletePipelineConfirm.value = false;
};

const saveRenamePipeline = async () => {
  if (!renamePipelineValue.value.trim()) return;
  try {
    await store.dispatch('crm/updatePipeline', {
      id: selectedPipelineId.value,
      name: renamePipelineValue.value,
    });
    isRenamingPipeline.value = false;
    useAlert(t('CRM.SUCCESS.PIPELINE_RENAMED'));
  } catch {
    useAlert(t('CRM.ERROR.GENERIC'));
  }
};

const deletePipeline = async () => {
  try {
    await store.dispatch('crm/deletePipeline', selectedPipelineId.value);
    showDeletePipelineConfirm.value = false;
    const remaining = pipelines.value;
    selectedPipelineId.value = remaining.length ? remaining[0].id : null;
    if (selectedPipelineId.value) {
      await store.dispatch('crm/fetchContacts', { pipelineId: selectedPipelineId.value, ...scopePayload() });
    }
    useAlert(t('CRM.SUCCESS.PIPELINE_DELETED'));
  } catch {
    useAlert(t('CRM.ERROR.GENERIC'));
  }
};

// --- Stage CRUD ---

const createStage = async () => {
  if (!newStageName.value.trim() || !selectedPipelineId.value) return;
  try {
    await store.dispatch('crm/createStage', {
      pipelineId: selectedPipelineId.value,
      name: newStageName.value,
      color: newStageColor.value,
    });
    newStageName.value = '';
    newStageColor.value = '#6B7280';
    showNewStageForm.value = false;
    useAlert(t('CRM.SUCCESS.STAGE_CREATED'));
  } catch {
    useAlert(t('CRM.ERROR.GENERIC'));
  }
};

const onColumnReorder = async () => {
  if (!selectedPipeline.value) return;
  const stageIds = selectedPipeline.value.stages.map(s => s.id);
  try {
    await store.dispatch('crm/reorderStages', {
      pipelineId: selectedPipelineId.value,
      stageIds,
    });
  } catch {
    useAlert(t('CRM.ERROR.GENERIC'));
  }
};

const onStageDrop = async ({ stageId, contacts }) => {
  // otimista: o card ASSENTA na coluna nova imediatamente; a API confirma em
  // background e, se falhar, o card volta para a coluna de origem.
  const moves = contacts
    .filter(c => c.stage_id !== stageId)
    .map(c => ({ id: c.id, from: c.stage_id }));

  moves.forEach(m =>
    store.commit('crm/patchContact', { id: m.id, data: { stage_id: stageId } })
  );

  moves.forEach(async m => {
    try {
      await store.dispatch('crm/moveContact', {
        pipelineId: selectedPipelineId.value,
        id: m.id,
        stageId,
      });
    } catch {
      store.commit('crm/patchContact', { id: m.id, data: { stage_id: m.from } });
      useAlert(t('CRM.ERROR.GENERIC'));
    }
  });
};

// --- Add contact modal ---

const openAddContact = (stageId) => {
  addContactStageId.value = stageId;
  contactSearchQuery.value = '';
  contactSearchResults.value = [];
  addContactTab.value = 'search';
  newContact.value = { name: '', phone_number: '', email: '' };
};

const closeAddContact = () => {
  addContactStageId.value = null;
  contactSearchQuery.value = '';
  contactSearchResults.value = [];
  newContact.value = { name: '', phone_number: '', email: '' };
};

let searchTimer = null;
const onSearchInput = () => {
  clearTimeout(searchTimer);
  if (!contactSearchQuery.value.trim()) {
    contactSearchResults.value = [];
    return;
  }
  searchTimer = setTimeout(async () => {
    isSearching.value = true;
    try {
      const { data } = await ContactAPI.search(contactSearchQuery.value, 1);
      contactSearchResults.value = data.payload ?? [];
    } finally {
      isSearching.value = false;
    }
  }, 300);
};

const addContactToStage = async (contact) => {
  try {
    await store.dispatch('crm/addContact', {
      pipelineId: selectedPipelineId.value,
      contact_id: contact.id,
      stage_id: addContactStageId.value,
    });
    useAlert(t('CRM.SUCCESS.CONTACT_ADDED'));
    closeAddContact();
  } catch {
    useAlert(t('CRM.ERROR.GENERIC'));
  }
};

const canCreateContact = computed(
  () => newContact.value.name.trim() && (newContact.value.phone_number.trim() || newContact.value.email.trim())
);

const createAndAddContact = async () => {
  if (!canCreateContact.value || isCreatingContact.value) return;
  isCreatingContact.value = true;
  try {
    const payload = { name: newContact.value.name.trim() };
    if (newContact.value.phone_number.trim()) payload.phone_number = newContact.value.phone_number.trim();
    if (newContact.value.email.trim()) payload.email = newContact.value.email.trim();

    const { data } = await ContactAPI.create(payload);
    const contact = data.payload?.contact ?? data.contact ?? data;
    await addContactToStage(contact);
  } catch (error) {
    const message = error?.response?.data?.message;
    useAlert(message || t('CRM.ERROR.GENERIC'));
  } finally {
    isCreatingContact.value = false;
  }
};
</script>

<template>
  <div class="bg-n-surface-1" style="display:flex;flex-direction:column;height:100%;width:100%;" @click="showLabelsDropdown = false; showStagesDropdown = false">
    <!-- Top bar -->
    <div class="flex items-center gap-3 px-6 py-4 border-b border-n-weak flex-shrink-0 flex-wrap">
      <h1 class="text-lg font-bold text-n-slate-12 flex items-center gap-2">
        <span class="w-8 h-8 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)">
          <span class="i-lucide-rocket text-white text-base" />
        </span>
        {{ $t('CRM.TITLE') }}
      </h1>

      <!-- Pipeline tabs -->
      <div class="flex items-center gap-2 ml-2 flex-wrap">
        <template v-for="p in pipelines" :key="p.id">
          <!-- Rename input (only for selected) -->
          <div v-if="isRenamingPipeline && selectedPipelineId === p.id" class="flex items-center gap-1">
            <input
              v-model="renamePipelineValue"
              class="border border-n-brand rounded-lg px-2 py-1 text-sm bg-n-solid-2 text-n-slate-12 w-36"
              @keyup.enter="saveRenamePipeline"
              @keyup.escape="isRenamingPipeline = false"
            />
            <button class="text-n-brand i-lucide-check text-base" @click="saveRenamePipeline" />
            <button class="text-n-slate-10 i-lucide-x text-base" @click="isRenamingPipeline = false" />
          </div>

          <!-- Normal tab -->
          <button
            v-else
            class="px-3 py-1.5 rounded-lg text-sm font-medium transition-colors"
            :class="selectedPipelineId === p.id
              ? 'text-white shadow'
              : 'text-n-slate-11 hover:bg-n-alpha-1'"
            :style="selectedPipelineId === p.id ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' } : {}"
            @click="selectPipeline(p.id)"
          >
            {{ p.name }}
          </button>
        </template>
      </div>

      <!-- Right actions — design novo: grupos de pílulas alinhados -->
      <div class="flex items-center gap-2 ml-auto justify-end flex-wrap">
        <!-- Renomear funil (excluir foi ocultado a pedido do Guilherme) -->
        <div
          v-if="isAdmin && selectedPipeline && !isRenamingPipeline"
          class="flex items-center bg-n-solid-2 border border-n-weak rounded-xl p-0.5 gap-0.5"
        >
          <button
            class="h-7 w-7 flex items-center justify-center rounded-lg text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1 transition-colors"
            :title="$t('CRM.RENAME_PIPELINE')"
            @click="startRenamePipeline"
          >
            <span class="i-lucide-pencil text-sm" />
          </button>
        </div>

        <!-- Ferramentas — grupo único de pílulas (só admin) -->
        <div
          v-if="isAdmin"
          class="flex items-center bg-n-solid-2 border border-n-weak rounded-xl p-0.5 gap-0.5 flex-wrap"
        >
          <button
            v-if="selectedPipeline && !isProgrammingMode"
            class="h-7 flex items-center gap-1.5 text-xs font-medium px-3 rounded-lg transition-colors whitespace-nowrap"
            :class="isEditMode
              ? 'bg-amber-500 text-white hover:bg-amber-600'
              : 'text-n-slate-11 hover:bg-n-alpha-1'"
            @click="isEditMode = !isEditMode"
          >
            <span :class="isEditMode ? 'i-lucide-x' : 'i-lucide-layout-template'" class="text-sm" />
            {{ isEditMode ? $t('CRM.EXIT_EDIT_MODE') : $t('CRM.EDIT_MODE') }}
          </button>

          <button
            v-if="selectedPipeline && !isProgrammingMode && !isEditMode"
            class="h-7 flex items-center gap-1.5 text-xs font-medium px-3 rounded-lg text-yellow-600 hover:bg-yellow-500/10 transition-colors whitespace-nowrap"
            @click="isProgrammingMode = true"
          >
            <span class="i-lucide-zap text-sm" />
            {{ $t('CRM.PROGRAMMING_MODE') }}
          </button>

          <button
            class="h-7 flex items-center gap-1.5 text-xs font-medium px-3 rounded-lg text-n-slate-11 hover:bg-n-alpha-1 transition-colors whitespace-nowrap"
            title="Integrações (n8n, Meta, Google, Claude)"
            @click="$router.push({ name: 'crm_integrations' })"
          >
            <span class="i-lucide-plug text-sm" />
            Integrações
          </button>

          <button
            class="h-7 flex items-center gap-1.5 text-xs font-medium px-3 rounded-lg text-n-slate-11 hover:bg-n-alpha-1 transition-colors whitespace-nowrap"
            title="Central de mensagens em massa (templates WhatsApp)"
            @click="$router.push({ name: 'crm_campaigns' })"
          >
            <span class="i-lucide-megaphone text-sm" />
            Mensagens em massa
          </button>

          <button
            class="h-7 flex items-center gap-1.5 text-xs font-medium px-3 rounded-lg text-n-slate-11 hover:bg-n-alpha-1 transition-colors whitespace-nowrap"
            @click="showNewPipelineForm = !showNewPipelineForm; showDeletePipelineConfirm = false"
          >
            <span class="i-lucide-plus text-sm" />
            {{ $t('CRM.NEW_PIPELINE') }}
          </button>
        </div>
      </div>
    </div>

    <!-- Janela de trabalho: aviso + seletor de período + carregar tudo -->
    <div
      v-if="['days', 'recent'].includes(contactsMeta.scope) && contactsMeta.total > contactsMeta.shown"
      class="flex items-center gap-2 px-6 py-1.5 text-xs text-n-slate-10 border-b border-n-weak flex-shrink-0 flex-wrap"
    >
      <span class="i-lucide-zap text-n-gold" />
      Leads ativos dos últimos {{ windowDays }} dias ({{ contactsMeta.shown }} de {{ contactsMeta.total }}) — leve e rápido. A busca enxerga a base toda.
      <span class="ml-1">Janela:</span>
      <button
        v-for="d in WINDOW_OPTIONS"
        :key="d"
        class="px-1.5 py-0.5 rounded border transition-colors"
        :class="windowDays === d && contactsScope === 'days'
          ? 'border-n-brand text-n-brand font-medium'
          : 'border-n-weak hover:bg-n-alpha-1'"
        @click="setWindowDays(d)"
      >
        {{ d }}d
      </button>
      <button
        class="px-1.5 py-0.5 rounded border border-n-weak hover:bg-n-alpha-1 disabled:opacity-50"
        :disabled="isLoadingAll"
        @click="loadAllContacts"
      >
        {{ isLoadingAll ? 'Carregando…' : 'Tudo' }}
      </button>
    </div>

    <!-- Edit mode banner -->
    <div
      v-if="isEditMode"
      class="flex items-center gap-3 px-6 py-2 bg-amber-50 dark:bg-amber-900/20 border-b border-amber-200 dark:border-amber-700 flex-shrink-0"
    >
      <span class="i-lucide-pencil-ruler text-amber-600 dark:text-amber-400 text-sm" />
      <span class="text-sm font-medium text-amber-700 dark:text-amber-300 flex-1">
        {{ $t('CRM.EDIT_MODE_ACTIVE') }}
      </span>
      <button
        class="flex items-center gap-1.5 text-sm px-3 py-1 rounded-lg bg-amber-600 text-white hover:bg-amber-700 transition-colors"
        @click="isEditMode = false"
      >
        <span class="i-lucide-x text-sm" />
        {{ $t('CRM.EXIT_EDIT_MODE') }}
      </button>
    </div>

    <!-- Programming mode banner -->
    <div
      v-if="isProgrammingMode"
      class="flex items-center gap-3 px-6 py-2 bg-yellow-50 dark:bg-yellow-900/20 border-b border-yellow-200 dark:border-yellow-700 flex-shrink-0"
    >
      <span class="i-lucide-zap text-yellow-600 dark:text-yellow-400 text-sm" />
      <span class="text-sm font-medium text-yellow-700 dark:text-yellow-300 flex-1">
        {{ $t('CRM.PROGRAMMING_MODE_ACTIVE') }}
      </span>
      <button
        class="flex items-center gap-1.5 text-sm px-3 py-1 rounded-lg bg-yellow-600 text-white hover:bg-yellow-700 transition-colors"
        @click="isProgrammingMode = false"
      >
        <span class="i-lucide-x text-sm" />
        {{ $t('CRM.EXIT_PROGRAMMING_MODE') }}
      </button>
    </div>

    <!-- Delete pipeline confirm bar -->
    <div
      v-if="showDeletePipelineConfirm"
      class="flex items-center gap-3 px-6 py-2.5 bg-red-50 dark:bg-red-900/20 border-b border-red-200 dark:border-red-800"
    >
      <span class="text-sm text-red-700 dark:text-red-300 flex-1">{{ $t('CRM.DELETE_PIPELINE_CONFIRM') }}</span>
      <button class="bg-red-500 text-white px-3 py-1 rounded-lg text-xs" @click="deletePipeline">
        {{ $t('CRM.DELETE_PIPELINE') }}
      </button>
      <button class="text-n-slate-10 px-3 py-1 text-xs" @click="showDeletePipelineConfirm = false">
        {{ $t('CRM.CANCEL') }}
      </button>
    </div>

    <!-- New pipeline form bar -->
    <div v-if="showNewPipelineForm" class="flex items-center gap-2 px-6 py-3 bg-n-alpha-1 border-b border-n-weak">
      <input
        v-model="newPipelineName"
        class="border border-n-weak rounded-lg px-3 py-1.5 text-sm bg-n-solid-2 text-n-slate-12 w-56"
        :placeholder="$t('CRM.PIPELINE_NAME')"
        @keyup.enter="createPipeline"
      />
      <button class="bg-n-brand text-white px-3 py-1.5 rounded-lg text-sm" @click="createPipeline">
        {{ $t('CRM.CREATE') }}
      </button>
      <button class="text-n-slate-10 px-3 py-1.5 text-sm" @click="showNewPipelineForm = false">
        {{ $t('CRM.CANCEL') }}
      </button>
    </div>

    <!-- Filter bar (only when a pipeline is selected) -->
    <div v-if="selectedPipeline && !uiFlags.isFetchingPipelines && !uiFlags.isFetchingContacts" class="flex-shrink-0">
      <!-- Main filter row -->
      <div class="flex items-center gap-2 px-4 py-2 border-b border-n-weak flex-wrap">
        <!-- Search input -->
        <div class="relative flex-none w-72">
          <span class="absolute left-3 top-1/2 -translate-y-1/2 i-lucide-search text-n-slate-9 text-base pointer-events-none" />
          <input
            v-model="filters.search"
            class="w-full pl-9 pr-3 py-2 text-sm bg-n-alpha-1 border border-n-weak rounded-lg text-n-slate-12 placeholder-n-slate-9 focus:outline-none focus:border-n-brand"
            :placeholder="$t('CRM.FILTER.SEARCH_PLACEHOLDER')"
          />
        </div>



        <!-- Sem resposta (paciente aguardando) -->
        <button
          class="flex items-center gap-1.5 px-3 py-1.5 text-sm rounded-lg border transition-colors whitespace-nowrap"
          :class="filters.awaitingOnly
            ? 'bg-amber-500/15 border-amber-500 text-amber-700 dark:text-amber-400 font-medium'
            : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
          @click="filters.awaitingOnly = !filters.awaitingOnly"
        >
          <span class="i-lucide-clock text-sm" />
          {{ $t('CRM.FILTER.AWAITING_REPLY') }}
          <span
            v-if="awaitingCount > 0"
            class="inline-flex items-center justify-center min-w-[16px] h-4 px-1 text-[10px] font-bold rounded-full"
            :class="filters.awaitingOnly ? 'bg-amber-500 text-white' : 'bg-n-alpha-2 text-n-slate-10'"
          >
            {{ awaitingCount }}
          </span>
        </button>

        <!-- Ordenação (compacto — a busca é quem manda no espaço) -->
        <select
          v-model="sortOrder"
          class="h-[34px] text-sm border border-n-weak rounded-lg px-2 bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand w-auto max-w-[210px] flex-shrink-0"
          :title="$t('CRM.FILTER.SORT')"
        >
          <option value="lastMessage">{{ $t('CRM.FILTER.SORT_LAST_MESSAGE') }}</option>
          <option value="waiting">{{ $t('CRM.FILTER.SORT_WAITING') }}</option>
          <option value="oldest">{{ $t('CRM.FILTER.SORT_OLDEST') }}</option>
          <option value="newest">{{ $t('CRM.FILTER.SORT_NEWEST') }}</option>
          <option value="">{{ $t('CRM.FILTER.SORT_DEFAULT') }}</option>
        </select>

        <!-- Caixa de entrada -->
        <select
          v-model="filters.inboxName"
          class="h-[34px] text-sm border border-n-weak rounded-lg px-2 bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand max-w-[170px]"
          :title="$t('CRM.MODAL.INBOX')"
        >
          <option value="">{{ $t('CRM.FILTER.ALL_INBOXES') }}</option>
          <option v-for="inbox in availableInboxes" :key="inbox" :value="inbox">{{ inbox }}</option>
        </select>

        <!-- Filters toggle button -->
        <button
          class="relative flex items-center gap-1.5 px-3 py-1.5 text-sm rounded-lg border transition-colors"
          :class="showFilters || activeFilterCount > 0
            ? 'bg-n-brand/10 border-n-brand text-n-brand'
            : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
          @click="showFilters ? (showFilters = false) : openFiltersPanel()"
        >
          <span class="i-lucide-sliders-horizontal text-sm" />
          {{ $t('CRM.FILTER.FILTERS') }}
          <span
            v-if="activeFilterCount > 0"
            class="inline-flex items-center justify-center w-4 h-4 text-[10px] font-bold bg-n-brand text-white rounded-full"
          >
            {{ activeFilterCount }}
          </span>
        </button>

        <!-- Visualizações pré-configuradas (colunas) -->
        <div class="flex items-center gap-1">
          <div class="flex items-center bg-n-solid-2 border border-n-weak rounded-xl p-0.5 gap-0.5 flex-wrap">
            <button
              class="h-7 flex items-center gap-1.5 px-3 rounded-lg text-xs font-medium transition-colors whitespace-nowrap"
              :class="activePresetNames.length === 0 ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
              :style="activePresetNames.length === 0 ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' } : {}"
              @click="clearPresets"
            >
              <span class="i-lucide-columns-3 text-sm" />
              Todas as colunas
            </button>
            <button
              v-for="p in columnPresets"
              :key="p.name"
              class="h-7 px-3 rounded-lg text-xs font-medium transition-colors whitespace-nowrap max-w-[160px] truncate"
              :class="activePresetNames.includes(p.name) ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
              :style="activePresetNames.includes(p.name) ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' } : {}"
              :title="`Mostrar só as colunas de ${p.name} (dá para combinar mais de uma)`"
              @click="togglePreset(p.name)"
            >
              {{ p.name }}
            </button>
            <button
              v-if="isAdmin"
              class="h-7 w-7 flex items-center justify-center rounded-lg text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1 transition-colors"
              :title="$t('CRM.PRESETS.MANAGE')"
              @click="showPresetsModal = true"
            >
              <span class="i-lucide-settings-2 text-sm" />
            </button>
          </div>
        </div>

        <!-- Clear filters button -->
        <button
          v-if="hasActiveFilters"
          class="flex items-center gap-1 text-xs text-red-500 hover:text-red-600 ml-1"
          @click="clearFilters"
        >
          <span class="i-lucide-x text-sm" />
          {{ $t('CRM.FILTER.CLEAR') }}
        </button>

        <!-- Counter (fim da linha) -->
        <span class="text-xs text-n-slate-9 whitespace-nowrap ml-auto">
          {{ $t('CRM.FILTER.SHOWING', { count: filteredCount, total: contactsMeta.total ?? totalContacts }) }}
          <template v-if="contactsMeta.with_conversations">
            · {{ $t('CRM.FILTER.WITH_CONVERSATION', { count: contactsMeta.with_conversations }) }}
          </template>
        </span>

        <!-- Completando em background -->
        <span
          v-if="isBackgroundLoading"
          class="flex items-center gap-1 text-xs text-n-slate-9 whitespace-nowrap"
        >
          <span class="i-lucide-loader-2 animate-spin text-xs" />
          {{ $t('CRM.FILTER.LOADING_REST') }}
        </span>

      </div>

      <!-- Expanded filter panel (rascunho — só filtra ao Aplicar) -->
      <div
        v-if="showFilters && panelDraft"
        class="px-4 py-3 bg-n-alpha-1 border-b border-n-weak"
      >
        <div class="flex items-start gap-3 flex-wrap">
          <!-- Assignee -->
          <div class="flex flex-col gap-1 min-w-[140px]">
            <label class="text-xs text-n-slate-9">{{ $t('CRM.MODAL.ASSIGNEE') }}</label>
            <select
              v-model="panelDraft.assigneeId"
              class="h-9 text-sm border border-n-weak rounded-lg px-2 bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
            >
              <option value="">{{ $t('CRM.FILTER.ALL_ASSIGNEES') }}</option>
              <option value="none">{{ $t('CRM.FILTER.NO_ASSIGNEE') }}</option>
              <option v-for="agent in agents" :key="agent.id" :value="agent.id">{{ agent.name }}</option>
            </select>
          </div>

          <!-- Labels multi-select -->
          <div class="flex flex-col gap-1 min-w-[140px] relative">
            <label class="text-xs text-n-slate-9">{{ $t('CRM.FILTER.ALL_LABELS') }}</label>
            <button
              class="h-9 w-full flex items-center justify-between text-sm border border-n-weak rounded-lg px-2 bg-n-solid-2 text-n-slate-12 focus:outline-none"
              :class="showLabelsDropdown ? 'border-n-brand' : ''"
              @click.stop="showLabelsDropdown = !showLabelsDropdown; showStagesDropdown = false"
            >
              <span class="truncate min-w-0 flex-1 text-left">
                {{ panelDraft.labels.length === 0 ? $t('CRM.FILTER.ALL_LABELS') : (panelDraft.labels.length === 1 ? panelDraft.labels[0] : `${panelDraft.labels.length} etiquetas`) }}
              </span>
              <span class="i-lucide-chevron-down text-xs ml-1 text-n-slate-9 flex-shrink-0" />
            </button>
            <div
              v-if="showLabelsDropdown"
              class="absolute top-full left-0 z-20 mt-1 bg-n-solid-1 border border-n-weak rounded-lg shadow-lg min-w-full max-h-48 overflow-y-auto"
              @click.stop
            >
              <div v-if="availableLabels.length === 0" class="px-3 py-2 text-xs text-n-slate-9">
                {{ $t('CRM.NO_CONTACTS_FOUND') }}
              </div>
              <label
                v-for="label in availableLabels"
                :key="label"
                class="flex items-center gap-2 px-3 py-1.5 text-sm cursor-pointer hover:bg-n-alpha-1 text-n-slate-12"
              >
                <input
                  v-model="panelDraft.labels"
                  type="checkbox"
                  :value="label"
                  class="rounded accent-n-brand"
                />
                {{ label }}
              </label>
            </div>
          </div>

          <!-- Etapas multi-select -->
          <div class="flex flex-col gap-1 min-w-[160px] relative">
            <label class="text-xs text-n-slate-9">{{ $t('CRM.MODAL.STAGE') }}</label>
            <button
              class="h-9 w-full flex items-center justify-between text-sm border border-n-weak rounded-lg px-2 bg-n-solid-2 text-n-slate-12 focus:outline-none"
              :class="showStagesDropdown ? 'border-n-brand' : ''"
              @click.stop="showStagesDropdown = !showStagesDropdown; showLabelsDropdown = false"
            >
              <span class="truncate min-w-0 flex-1 text-left">
                {{ panelDraft.stageIds.length === 0 ? $t('CRM.FILTER.ALL_STAGES') : `${panelDraft.stageIds.length} etapa(s)` }}
              </span>
              <span class="i-lucide-chevron-down text-xs ml-1 text-n-slate-9 flex-shrink-0" />
            </button>
            <div
              v-if="showStagesDropdown"
              class="absolute top-full left-0 z-20 mt-1 bg-n-solid-1 border border-n-weak rounded-lg shadow-lg min-w-full max-h-48 overflow-y-auto"
              @click.stop
            >
              <label
                v-for="stage in selectedPipeline.stages"
                :key="stage.id"
                class="flex items-center gap-2 px-3 py-1.5 text-sm cursor-pointer hover:bg-n-alpha-1 text-n-slate-12"
              >
                <input
                  v-model="panelDraft.stageIds"
                  type="checkbox"
                  :value="stage.id"
                  class="rounded accent-n-brand"
                />
                <span class="w-2 h-2 rounded-full flex-shrink-0" :style="{ backgroundColor: stage.color }" />
                {{ stage.name }}
              </label>
            </div>
          </div>

          <!-- Created at (entry in CRM) -->
          <div class="flex flex-col gap-1 min-w-[140px]">
            <label class="text-xs text-n-slate-9">{{ $t('CRM.FILTER.CREATED_AT') }}</label>
            <select
              v-model="panelDraft.createdAt"
              class="h-9 text-sm border border-n-weak rounded-lg px-2 bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
            >
              <option v-for="p in datePresets" :key="p.value" :value="p.value">{{ p.label }}</option>
            </select>
          </div>

          <!-- Last activity -->
          <div class="flex flex-col gap-1 min-w-[140px]">
            <label class="text-xs text-n-slate-9">{{ $t('CRM.FILTER.LAST_ACTIVITY') }}</label>
            <select
              v-model="panelDraft.lastActivity"
              class="h-9 text-sm border border-n-weak rounded-lg px-2 bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
            >
              <option v-for="p in datePresets" :key="p.value" :value="p.value">{{ p.label }}</option>
              <option value="none">{{ $t('CRM.FILTER.NO_INTERACTION') }}</option>
            </select>
          </div>

          <!-- Período do lead: De / Até (data real do contato) -->
          <div class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-9">Período do lead (De / Até)</label>
            <div class="flex items-center gap-1.5">
              <input
                v-model="panelDraft.dateFrom"
                type="date"
                class="h-9 text-sm border border-n-weak rounded-lg px-2 bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
              />
              <span class="text-xs text-n-slate-9">até</span>
              <input
                v-model="panelDraft.dateTo"
                type="date"
                class="h-9 text-sm border border-n-weak rounded-lg px-2 bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
              />
            </div>
          </div>
        </div>

        <!-- Aplicar / cancelar -->
        <div class="flex items-center gap-2 mt-3">
          <button
            class="flex items-center gap-1.5 text-sm px-4 py-1.5 rounded-lg bg-n-brand text-white hover:bg-n-brand/90 transition-colors"
            @click="applyFiltersPanel"
          >
            <span class="i-lucide-check text-sm" />
            {{ $t('CRM.FILTER.APPLY') }}
          </button>
          <button
            class="text-sm px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
            @click="showFilters = false"
          >
            {{ $t('CRM.CANCEL') }}
          </button>
        </div>
      </div>
    </div>

    <!-- Loading -->
    <div v-if="uiFlags.isFetchingPipelines || uiFlags.isFetchingContacts" class="flex justify-center items-center flex-1">
      <Spinner :size="32" class="text-n-brand" />
    </div>

    <!-- Empty state -->
    <div v-else-if="!selectedPipeline" class="flex flex-col items-center justify-center flex-1 text-n-slate-10">
      <span class="i-lucide-layout-kanban text-5xl mb-3" />
      <p class="text-sm">{{ $t('CRM.NO_PIPELINE') }}</p>
    </div>

    <!-- Kanban board -->
    <div
      v-else
      class="kanban-board-scroll snap-x snap-mandatory md:snap-none"
      style="flex:1;min-height:0;overflow-x:scroll;overflow-y:auto;padding:24px;scrollbar-width:thin;scrollbar-color:rgba(148,163,184,0.45) transparent;scroll-behavior:smooth;"
    >
      <!-- All-filtered-out empty state -->
      <div v-if="allFilteredOut" class="flex flex-col items-center justify-center h-full text-n-slate-9">
        <span class="i-lucide-search-x text-4xl mb-3" />
        <p class="text-sm">{{ $t('CRM.FILTER.EMPTY') }}</p>
        <button class="mt-3 text-sm text-n-brand hover:underline" @click="clearFilters">
          {{ $t('CRM.FILTER.CLEAR_FILTERS') }}
        </button>
      </div>

      <draggable
        v-else
        v-model="selectedPipeline.stages"
        item-key="id"
        :animation="150"
        handle=".column-drag-handle"
        style="display:flex;gap:16px;height:100%;min-width:max-content;"
        @end="onColumnReorder"
      >
        <template #item="{ element: stage }">
          <KanbanColumn
            :key="stage.id"
            :hidden="!isStageVisible(stage.id)"
            :stage="stage"
            :pipeline-id="selectedPipelineId"
            :contacts="contactsByStage[stage.id] ?? []"
            :edit-mode="isEditMode"
            :programming-mode="isProgrammingMode"
            :all-stages="selectedPipeline.stages"
            @card-click="selectedContact = $event"
            @stage-drop="onStageDrop"
            @add-contact="openAddContact"
            @open-chat="openChat"
          />
        </template>

        <template #footer>
          <!-- Add stage column — only in edit mode -->
          <div v-if="isEditMode" class="flex-shrink-0 w-64">
            <div v-if="!showNewStageForm">
              <button
                class="w-full border-2 border-dashed border-n-weak rounded-xl py-3 text-sm text-n-slate-10 hover:border-n-brand hover:text-n-brand transition-colors flex items-center justify-center gap-1"
                @click="showNewStageForm = true"
              >
                <span class="i-lucide-plus" />
                {{ $t('CRM.NEW_STAGE') }}
              </button>
            </div>
            <div v-else class="bg-n-alpha-1 rounded-xl p-3 space-y-2">
              <input
                v-model="newStageName"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
                :placeholder="$t('CRM.STAGE_NAME')"
                @keyup.enter="createStage"
              />
              <div class="flex items-center gap-2">
                <label class="text-xs text-n-slate-10">{{ $t('CRM.STAGE_COLOR') }}</label>
                <input v-model="newStageColor" type="color" class="w-8 h-8 rounded cursor-pointer border-0" />
              </div>
              <div class="flex gap-2">
                <button class="flex-1 bg-n-brand text-white rounded-lg py-1.5 text-xs" @click="createStage">
                  {{ $t('CRM.CREATE') }}
                </button>
                <button class="flex-1 border border-n-weak rounded-lg py-1.5 text-xs text-n-slate-11" @click="showNewStageForm = false">
                  {{ $t('CRM.CANCEL') }}
                </button>
              </div>
            </div>
          </div>
        </template>
      </draggable>
    </div>

    <!-- Contact detail modal -->
    <ContactModal
      :contact="selectedContact"
      :pipeline="selectedPipeline ?? { stages: [] }"
      @close="selectedContact = null"
      @updated="onContactUpdated"
      @merged="onContactMerged"
      @removed="selectedContact = null"
      @open-chat="openChat"
    />

    <!-- Chat popup (conversa oficial) -->
    <ConversationChatModal
      v-if="chatContact"
      :contact="chatContact"
      :pipeline-id="selectedPipelineId"
      :stages="selectedPipeline?.stages ?? []"
      @close="chatContact = null"
      @replied="onChatReplied"
      @resolved="onChatResolved"
      @conversation-started="chatContact = $event"
    />

    <!-- Column presets modal -->
    <ColumnPresetsModal
      v-if="showPresetsModal && selectedPipeline"
      :stages="selectedPipeline.stages"
      :presets="columnPresets"
      @close="showPresetsModal = false"
      @saved="onPresetsSaved"
    />

    <!-- Integrations modal -->
    <CrmIntegrationsModal
      v-if="showIntegrationsModal"
      @close="showIntegrationsModal = false"
    />

    <!-- Add contact modal -->
    <div
      v-if="addContactStageId !== null"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      @click.self="closeAddContact"
    >
      <div class="bg-n-solid-1 rounded-2xl shadow-xl w-full max-w-md mx-4">
        <div class="flex items-center justify-between p-4 border-b border-n-weak">
          <h2 class="text-base font-semibold text-n-slate-12">{{ $t('CRM.ADD_CONTACT') }}</h2>
          <button class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl" @click="closeAddContact" />
        </div>

        <!-- Tabs -->
        <div class="flex items-center gap-1 px-4 pt-3">
          <button
            class="px-3 py-1.5 text-xs font-medium rounded-lg transition-colors"
            :class="addContactTab === 'search' ? 'bg-n-brand text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
            @click="addContactTab = 'search'"
          >Buscar existente</button>
          <button
            class="px-3 py-1.5 text-xs font-medium rounded-lg transition-colors"
            :class="addContactTab === 'create' ? 'bg-n-brand text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
            @click="addContactTab = 'create'"
          >Criar novo contato</button>
        </div>

        <div v-if="addContactTab === 'create'" class="p-4 space-y-3">
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Nome</label>
            <input
              v-model="newContact.name"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              placeholder="Nome do contato"
            />
          </div>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Telefone</label>
            <input
              v-model="newContact.phone_number"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              placeholder="+55 11 99999-9999"
            />
          </div>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1">
              Email <span class="text-n-slate-9">(opcional se tiver telefone)</span>
            </label>
            <input
              v-model="newContact.email"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              placeholder="email@exemplo.com"
            />
          </div>
          <button
            class="w-full bg-n-brand text-white rounded-lg py-2 text-sm font-medium disabled:opacity-50"
            :disabled="!canCreateContact || isCreatingContact"
            @click="createAndAddContact"
          >{{ isCreatingContact ? 'Criando…' : 'Criar e adicionar ao funil' }}</button>
        </div>

        <div v-else class="p-4">
          <div class="relative">
            <span class="absolute left-3 top-1/2 -translate-y-1/2 i-lucide-search text-n-slate-10 text-sm" />
            <input
              v-model="contactSearchQuery"
              class="w-full border border-n-weak rounded-lg pl-8 pr-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              :placeholder="$t('CRM.SEARCH_CONTACT')"
              @input="onSearchInput"
            />
          </div>

          <div class="mt-3 max-h-72 overflow-y-auto space-y-0.5">
            <!-- Loading -->
            <div v-if="isSearching" class="flex justify-center py-4">
              <Spinner :size="20" class="text-n-brand" />
            </div>

            <!-- No results -->
            <div
              v-else-if="contactSearchQuery && contactSearchResults.length === 0"
              class="text-center py-4 text-sm text-n-slate-10"
            >
              {{ $t('CRM.NO_CONTACTS_FOUND') }}
            </div>

            <template v-else>
              <!-- Available contacts -->
              <button
                v-for="c in filteredSearchResults"
                :key="c.id"
                class="w-full flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-n-alpha-1 transition-colors text-left"
                @click="addContactToStage(c)"
              >
                <div class="w-8 h-8 rounded-full bg-n-brand flex items-center justify-center text-white text-xs font-semibold flex-shrink-0">
                  <img v-if="c.avatar_url" :src="c.avatar_url" class="w-8 h-8 rounded-full object-cover" />
                  <span v-else>{{ c.name?.[0]?.toUpperCase() ?? '?' }}</span>
                </div>
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-medium text-n-slate-12 truncate">{{ c.name }}</p>
                  <p class="text-xs text-n-slate-10 truncate">{{ c.phone_number ?? c.email }}</p>
                </div>
              </button>

              <!-- Already added contacts (greyed out) -->
              <div
                v-for="c in alreadyInPipelineResults"
                :key="'added-' + c.id"
                class="w-full flex items-center gap-3 px-3 py-2 rounded-lg opacity-40 cursor-not-allowed"
              >
                <div class="w-8 h-8 rounded-full bg-n-slate-9 flex items-center justify-center text-white text-xs font-semibold flex-shrink-0">
                  <img v-if="c.avatar_url" :src="c.avatar_url" class="w-8 h-8 rounded-full object-cover" />
                  <span v-else>{{ c.name?.[0]?.toUpperCase() ?? '?' }}</span>
                </div>
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-medium text-n-slate-11 truncate">{{ c.name }}</p>
                  <p class="text-xs text-n-slate-9 truncate">{{ $t('CRM.ALREADY_IN_PIPELINE') }}</p>
                </div>
              </div>
            </template>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
