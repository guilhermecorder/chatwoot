<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { relativeTime } from '../helpers';
import ContactAPI from 'dashboard/api/contacts';
import AccountActionsAPI from 'dashboard/api/accountActions';

const props = defineProps({
  contact: { type: Object, default: null },
  pipeline: { type: Object, required: true },
});

const emit = defineEmits(['close', 'updated', 'removed', 'openChat']);

const store = useStore();
const { t } = useI18n();
const router = useRouter();
const { accountId } = useAccount();

const agents = useMapGetter('agents/getAgents');
const accountLabels = useMapGetter('labels/getLabels');

const activeTab = ref('crm');
const isSaving = ref(false);
const isRemoving = ref(false);
const showRemoveConfirm = ref(false);

// History tab state
const historyLogs = ref([]);
const historyLoading = ref(false);
const historyError = ref(false);

// Label picker state
const labelSearch = ref('');
const showLabelPicker = ref(false);

const form = ref({
  stage_id: null,
  assignee_id: null,
  value: '',
  origin: '',
  procedure_of_interest: '',
  notes: '',
  labels: [],
});

onMounted(() => {
  if (!agents.value.length) store.dispatch('agents/get');
  if (!accountLabels.value.length) store.dispatch('labels/fetch');
});

watch(() => props.contact, (c) => {
  if (!c) return;
  activeTab.value = 'crm';
  showRemoveConfirm.value = false;
  labelSearch.value = '';
  showLabelPicker.value = false;
  historyLogs.value = [];
  historyError.value = false;
  form.value = {
    stage_id: c.stage_id,
    assignee_id: c.assignee?.id ?? null,
    value: c.value ?? '',
    origin: c.origin ?? '',
    procedure_of_interest: c.procedure_of_interest ?? '',
    notes: c.notes ?? '',
    labels: [...(c.labels ?? [])],
  };
}, { immediate: true });

watch(activeTab, async (tab) => {
  if (tab === 'history' && props.contact && !historyLogs.value.length) {
    await loadHistory();
  }
});

const loadHistory = async () => {
  if (!props.contact) return;
  historyLoading.value = true;
  historyError.value = false;
  try {
    historyLogs.value = await store.dispatch('crm/fetchContactHistory', {
      pipelineId: props.pipeline.id,
      contactId: props.contact.id,
    });
  } catch {
    historyError.value = true;
  } finally {
    historyLoading.value = false;
  }
};

// Tempo total no funil (soma dos durations)
const totalMinutes = computed(() =>
  historyLogs.value.reduce((sum, l) => sum + (l.duration_minutes ?? 0), 0)
);

const formatDuration = (minutes) => {
  if (!minutes || minutes <= 0) return null;
  if (minutes < 60) return `${minutes}min`;
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h < 24) return m > 0 ? `${h}h ${m}min` : `${h}h`;
  const d = Math.floor(h / 24);
  const rh = h % 24;
  return rh > 0 ? `${d}d ${rh}h` : `${d}d`;
};

const filteredAvailableLabels = computed(() =>
  accountLabels.value.filter(l =>
    l.title.toLowerCase().includes(labelSearch.value.toLowerCase()) &&
    !form.value.labels.includes(l.title)
  )
);

const addLabel = (title) => {
  if (!form.value.labels.includes(title)) form.value.labels.push(title);
  labelSearch.value = '';
  showLabelPicker.value = false;
};

const addLabelFromInput = () => {
  const input = labelSearch.value.trim().toLowerCase().replace(/\s+/g, '-');
  if (input && !form.value.labels.includes(input)) form.value.labels.push(input);
  labelSearch.value = '';
  showLabelPicker.value = false;
};

const removeLabel = (label) => {
  const idx = form.value.labels.indexOf(label);
  if (idx !== -1) form.value.labels.splice(idx, 1);
};

const onLabelBlur = () => {
  setTimeout(() => { showLabelPicker.value = false; }, 150);
};

const tabs = computed(() => [
  { key: 'crm',          label: t('CRM.MODAL.TAB_CRM') },
  { key: 'contact',      label: t('CRM.MODAL.TAB_CONTACT') },
  { key: 'conversation', label: t('CRM.MODAL.TAB_CONVERSATION') },
  { key: 'history',      label: t('CRM.MODAL.TAB_HISTORY') },
]);

const channelIcon = (channelType) => {
  const map = {
    'Channel::Whatsapp':    'i-lucide-message-circle',
    'Channel::WebWidget':   'i-lucide-globe',
    'Channel::Email':       'i-lucide-mail',
    'Channel::Sms':         'i-lucide-smartphone',
    'Channel::TwilioSms':   'i-lucide-smartphone',
    'Channel::Api':         'i-lucide-code',
    'Channel::TelegramBot': 'i-lucide-send',
    'Channel::FacebookPage':'i-lucide-message-square',
    'Channel::Instagram':   'i-lucide-instagram',
  };
  return map[channelType] ?? 'i-lucide-inbox';
};

const statusClass = (status) => {
  const map = {
    open:     'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
    resolved: 'bg-n-alpha-2 text-n-slate-10',
    pending:  'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400',
    snoozed:  'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
  };
  return map[status] ?? 'bg-n-alpha-2 text-n-slate-10';
};

const save = async () => {
  if (!props.contact) return;
  isSaving.value = true;
  try {
    const { labels, ...crmFields } = form.value;
    const previousLabels = props.contact.labels ?? [];

    // Salva campos CRM e etiquetas em paralelo
    await Promise.all([
      store.dispatch('crm/updateContact', {
        pipelineId: props.pipeline.id,
        id: props.contact.id,
        ...crmFields,
      }),
      store.dispatch('contactLabels/update', {
        contactId: props.contact.contact_id,
        labels,
      }),
    ]);

    // Calcula diff de etiquetas e dispara automações label_added/label_removed
    const added   = labels.filter(l => !previousLabels.includes(l));
    const removed = previousLabels.filter(l => !labels.includes(l));
    if (added.length || removed.length) {
      store.dispatch('crm/triggerLabelChange', {
        pipelineId: props.pipeline.id,
        contactId:  props.contact.id,
        added,
        removed,
      }).catch(() => {}); // não bloqueia o save se falhar
    }

    useAlert(t('CRM.SUCCESS.CONTACT_SAVED'));
    emit('updated');
  } catch {
    useAlert(t('CRM.ERROR.GENERIC'));
  } finally {
    isSaving.value = false;
  }
};

const removeContact = async () => {
  if (!props.contact) return;
  isRemoving.value = true;
  try {
    await store.dispatch('crm/removeContact', {
      pipelineId: props.pipeline.id,
      id: props.contact.id,
    });
    useAlert(t('CRM.SUCCESS.CONTACT_REMOVED'));
    emit('removed');
  } catch {
    useAlert(t('CRM.ERROR.GENERIC'));
  } finally {
    isRemoving.value = false;
  }
};

const openConversation = () => {
  if (!props.contact?.last_conversation_id) return;
  router.push({
    name: 'inbox_conversation',
    params: {
      account_id: accountId.value,
      conversation_id: props.contact.last_conversation_id,
    },
  });
  emit('close');
};

// ── Mesclar contato duplicado (ex: Instagram + WhatsApp) ──
const showMergeSection = ref(false);
const mergeSearch = ref('');
const mergeResults = ref([]);
const isMergeSearching = ref(false);
const mergeCandidate = ref(null);
const isMerging = ref(false);

let mergeTimer = null;
const onMergeSearchInput = () => {
  clearTimeout(mergeTimer);
  mergeCandidate.value = null;
  if (!mergeSearch.value.trim()) {
    mergeResults.value = [];
    return;
  }
  mergeTimer = setTimeout(async () => {
    isMergeSearching.value = true;
    try {
      const { data } = await ContactAPI.search(mergeSearch.value, 1);
      mergeResults.value = (data.payload ?? []).filter(
        c => c.id !== props.contact.contact_id
      );
    } finally {
      isMergeSearching.value = false;
    }
  }, 300);
};

// ── Detectar valor do orçamento na conversa ──
const isDetectingValue = ref(false);
const detectValue = async () => {
  if (!props.contact || isDetectingValue.value) return;
  isDetectingValue.value = true;
  try {
    const data = await store.dispatch('crm/detectCardValue', {
      pipelineId: props.pipeline.id,
      id: props.contact.id,
    });
    if (data.updated) {
      form.value.value = data.value;
      useAlert(t('CRM.VALUE_DETECT.FOUND', { value: Number(data.value).toLocaleString('pt-BR') }));
    } else {
      useAlert(t('CRM.VALUE_DETECT.NOT_FOUND'));
    }
  } catch {
    useAlert(t('CRM.ERROR.GENERIC'));
  } finally {
    isDetectingValue.value = false;
  }
};

const doMerge = async () => {
  if (!mergeCandidate.value || isMerging.value) return;
  isMerging.value = true;
  try {
    // o card atual é o contato principal; o selecionado é absorvido
    await AccountActionsAPI.merge(props.contact.contact_id, mergeCandidate.value.id);
    useAlert(t('CRM.MERGE.SUCCESS'));
    showMergeSection.value = false;
    mergeSearch.value = '';
    mergeResults.value = [];
    mergeCandidate.value = null;
    emit('updated');
  } catch {
    useAlert(t('CRM.ERROR.GENERIC'));
  } finally {
    isMerging.value = false;
  }
};
</script>

<template>
  <div
    v-if="contact"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
    @click.self="emit('close')"
  >
    <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-2xl max-h-[88vh] flex flex-col">

      <!-- Header -->
      <div class="flex items-start justify-between px-6 pt-5 pb-4 border-b border-n-weak flex-shrink-0">
        <div class="flex items-center gap-4 min-w-0">
          <!-- Avatar -->
          <div class="w-12 h-12 rounded-full bg-n-brand flex items-center justify-center text-white text-lg font-semibold flex-shrink-0 overflow-hidden">
            <img v-if="contact.avatar_url" :src="contact.avatar_url" class="w-12 h-12 object-cover" />
            <span v-else>{{ contact.name?.[0]?.toUpperCase() ?? '?' }}</span>
          </div>
          <!-- Info -->
          <div class="min-w-0">
            <h2 class="text-base font-semibold text-n-slate-12 truncate">{{ contact.name }}</h2>
            <div class="flex items-center gap-3 mt-0.5 flex-wrap">
              <span v-if="contact.phone_number" class="text-sm text-n-slate-10 flex items-center gap-1">
                <span class="i-lucide-phone text-xs" />{{ contact.phone_number }}
              </span>
              <span v-if="contact.email" class="text-sm text-n-slate-10 flex items-center gap-1">
                <span class="i-lucide-mail text-xs" />{{ contact.email }}
              </span>
            </div>
            <!-- Labels -->
            <div v-if="contact.labels?.length" class="flex flex-wrap gap-1 mt-1.5">
              <span
                v-for="label in contact.labels"
                :key="label"
                class="text-xs bg-n-alpha-2 text-n-slate-11 px-2 py-0.5 rounded-full"
              >
                {{ label }}
              </span>
            </div>
          </div>
        </div>
        <button
          class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl flex-shrink-0 ml-4"
          @click="emit('close')"
        />
      </div>

      <!-- Tabs -->
      <div class="flex border-b border-n-weak flex-shrink-0 px-6">
        <button
          v-for="tab in tabs"
          :key="tab.key"
          class="py-3 px-1 mr-6 text-sm font-medium border-b-2 transition-colors"
          :class="activeTab === tab.key
            ? 'border-n-brand text-n-brand'
            : 'border-transparent text-n-slate-10 hover:text-n-slate-12'"
          @click="activeTab = tab.key"
        >
          {{ tab.label }}
        </button>
      </div>

      <!-- Scrollable content -->
      <div class="flex-1 overflow-y-auto">

        <!-- ── Tab: CRM ── -->
        <div v-if="activeTab === 'crm'" class="p-6 space-y-4">
          <div class="grid grid-cols-2 gap-4">
            <!-- Stage -->
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">{{ $t('CRM.MODAL.STAGE') }}</label>
              <select
                v-model="form.stage_id"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              >
                <option v-for="s in pipeline.stages" :key="s.id" :value="s.id">{{ s.name }}</option>
              </select>
            </div>

            <!-- Assignee -->
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">{{ $t('CRM.MODAL.ASSIGNEE') }}</label>
              <select
                v-model="form.assignee_id"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              >
                <option :value="null">{{ $t('CRM.MODAL.NO_ASSIGNEE') }}</option>
                <option v-for="agent in agents" :key="agent.id" :value="agent.id">
                  {{ agent.name }}
                </option>
              </select>
            </div>

            <!-- Value -->
            <div>
              <div class="flex items-center justify-between mb-1">
                <label class="text-xs font-medium text-n-slate-11">{{ $t('CRM.MODAL.VALUE') }}</label>
                <button
                  class="text-[11px] text-n-brand hover:underline flex items-center gap-1 disabled:opacity-50"
                  :disabled="isDetectingValue"
                  :title="$t('CRM.VALUE_DETECT.HINT')"
                  @click="detectValue"
                >
                  <span :class="isDetectingValue ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-wand-2'" class="text-xs" />
                  {{ $t('CRM.VALUE_DETECT.BUTTON') }}
                </button>
              </div>
              <input
                v-model="form.value"
                type="number"
                step="0.01"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
                placeholder="0,00"
              />
            </div>

            <!-- Origin -->
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">{{ $t('CRM.MODAL.ORIGIN') }}</label>
              <input
                v-model="form.origin"
                type="text"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              />
            </div>
          </div>

          <!-- Procedure (full width) -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1">{{ $t('CRM.MODAL.PROCEDURE') }}</label>
            <input
              v-model="form.procedure_of_interest"
              type="text"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
            />
          </div>

          <!-- Notes (full width) -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1">{{ $t('CRM.MODAL.NOTES') }}</label>
            <textarea
              v-model="form.notes"
              rows="4"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 resize-none"
            />
          </div>

          <!-- Labels -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-2">{{ $t('CRM.MODAL.LABELS') }}</label>
            <!-- Current label chips -->
            <div class="flex flex-wrap gap-1.5 mb-2 min-h-[24px]">
              <span
                v-for="label in form.labels"
                :key="label"
                class="inline-flex items-center gap-1 text-xs bg-n-alpha-2 text-n-slate-11 px-2 py-0.5 rounded-full"
              >
                {{ label }}
                <button
                  class="i-lucide-x text-[10px] hover:text-red-500 ml-0.5 flex-shrink-0"
                  @click="removeLabel(label)"
                />
              </span>
            </div>
            <!-- Label search / add input -->
            <div class="relative">
              <input
                v-model="labelSearch"
                class="w-full border border-n-weak rounded-lg px-3 py-1.5 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
                placeholder="Adicionar etiqueta..."
                @focus="showLabelPicker = true"
                @blur="onLabelBlur"
                @keydown.enter.prevent="addLabelFromInput"
              />
              <div
                v-if="showLabelPicker && filteredAvailableLabels.length > 0"
                class="absolute top-full left-0 right-0 z-30 mt-1 bg-n-solid-1 border border-n-weak rounded-lg shadow-lg max-h-36 overflow-y-auto"
              >
                <button
                  v-for="lbl in filteredAvailableLabels"
                  :key="lbl.id"
                  class="w-full text-left px-3 py-1.5 text-sm hover:bg-n-alpha-1 text-n-slate-12 flex items-center gap-2"
                  @mousedown.prevent="addLabel(lbl.title)"
                >
                  <span
                    class="w-2.5 h-2.5 rounded-full flex-shrink-0"
                    :style="{ backgroundColor: lbl.color ?? '#6B7280' }"
                  />
                  {{ lbl.title }}
                </button>
              </div>
            </div>
          </div>

          <!-- Actions -->
          <div class="flex gap-2 pt-2">
            <button
              class="flex-1 bg-n-brand text-white rounded-lg py-2 text-sm font-medium hover:bg-n-brand/90 transition-colors disabled:opacity-50"
              :disabled="isSaving"
              @click="save"
            >
              {{ isSaving ? $t('CRM.MODAL.SAVING') : $t('CRM.MODAL.SAVE') }}
            </button>
          </div>

          <!-- Remove section -->
          <div class="border-t border-n-weak pt-3">
            <div v-if="!showRemoveConfirm">
              <button
                class="w-full py-2 text-sm text-red-500 hover:text-red-700 hover:bg-red-50 dark:hover:bg-red-900/20 rounded-lg transition-colors"
                @click="showRemoveConfirm = true"
              >
                {{ $t('CRM.MODAL.REMOVE') }}
              </button>
            </div>
            <div v-else class="flex items-center gap-2">
              <span class="text-xs text-n-slate-11 flex-1">{{ $t('CRM.MODAL.REMOVE') }}?</span>
              <button
                class="bg-red-500 text-white px-3 py-1.5 rounded-lg text-xs disabled:opacity-50"
                :disabled="isRemoving"
                @click="removeContact"
              >
                {{ $t('CRM.MODAL.REMOVE') }}
              </button>
              <button
                class="border border-n-weak px-3 py-1.5 rounded-lg text-xs text-n-slate-11"
                @click="showRemoveConfirm = false"
              >
                {{ $t('CRM.CANCEL') }}
              </button>
            </div>
          </div>
        </div>

        <!-- ── Tab: Contato ── -->
        <div v-else-if="activeTab === 'contact'" class="p-6 space-y-5">
          <!-- Info rows -->
          <div class="space-y-3">
            <div v-if="contact.phone_number" class="flex items-center gap-3">
              <span class="i-lucide-phone text-n-slate-10 text-base flex-shrink-0 w-5" />
              <div>
                <p class="text-xs text-n-slate-10">{{ $t('CRM.MODAL.CHANNEL') }}</p>
                <p class="text-sm text-n-slate-12">{{ contact.phone_number }}</p>
              </div>
            </div>

            <div v-if="contact.email" class="flex items-center gap-3">
              <span class="i-lucide-mail text-n-slate-10 text-base flex-shrink-0 w-5" />
              <div>
                <p class="text-xs text-n-slate-10">E-mail</p>
                <p class="text-sm text-n-slate-12">{{ contact.email }}</p>
              </div>
            </div>

            <div class="flex items-center gap-3">
              <span class="i-lucide-calendar text-n-slate-10 text-base flex-shrink-0 w-5" />
              <div>
                <p class="text-xs text-n-slate-10">{{ $t('CRM.MODAL.CONTACT_SINCE') }}</p>
                <p class="text-sm text-n-slate-12">
                  {{ contact.contact_created_at
                    ? new Date(contact.contact_created_at).toLocaleDateString('pt-BR')
                    : '—' }}
                </p>
              </div>
            </div>

            <div class="flex items-center gap-3">
              <span class="i-lucide-clock text-n-slate-10 text-base flex-shrink-0 w-5" />
              <div>
                <p class="text-xs text-n-slate-10">{{ $t('CRM.MODAL.LAST_ACTIVITY') }}</p>
                <p class="text-sm text-n-slate-12">
                  {{ relativeTime(contact.last_activity_at) ?? '—' }}
                </p>
              </div>
            </div>

            <div class="flex items-center gap-3">
              <span class="i-lucide-message-square text-n-slate-10 text-base flex-shrink-0 w-5" />
              <div>
                <p class="text-xs text-n-slate-10">{{ $t('CRM.MODAL.TAB_CONVERSATION') }}</p>
                <p class="text-sm text-n-slate-12">
                  {{ contact.conversations_count ?? 0 }} {{ $t('CRM.MODAL.CONVERSATIONS') }}
                </p>
              </div>
            </div>
          </div>

          <!-- Labels -->
          <div v-if="contact.labels?.length">
            <p class="text-xs font-medium text-n-slate-11 mb-2">{{ $t('CRM.MODAL.LABELS') }}</p>
            <div class="flex flex-wrap gap-1.5">
              <span
                v-for="label in contact.labels"
                :key="label"
                class="text-xs bg-n-alpha-2 text-n-slate-11 px-2.5 py-1 rounded-full"
              >
                {{ label }}
              </span>
            </div>
          </div>

          <!-- CRM snapshot (read-only) -->
          <div class="border-t border-n-weak pt-4 space-y-2">
            <div v-if="contact.value" class="flex items-center justify-between">
              <span class="text-xs text-n-slate-10">{{ $t('CRM.MODAL.VALUE') }}</span>
              <span class="text-sm font-medium text-green-600">
                R$ {{ Number(contact.value).toLocaleString('pt-BR', { maximumFractionDigits: 0 }) }}
              </span>
            </div>
            <div v-if="contact.origin" class="flex items-center justify-between">
              <span class="text-xs text-n-slate-10">{{ $t('CRM.MODAL.ORIGIN') }}</span>
              <span class="text-sm text-n-slate-12">{{ contact.origin }}</span>
            </div>
            <div v-if="contact.procedure_of_interest" class="flex items-center justify-between">
              <span class="text-xs text-n-slate-10">{{ $t('CRM.MODAL.PROCEDURE') }}</span>
              <span class="text-sm text-n-slate-12 text-right max-w-xs">{{ contact.procedure_of_interest }}</span>
            </div>
            <div v-if="contact.assignee" class="flex items-center justify-between">
              <span class="text-xs text-n-slate-10">{{ $t('CRM.MODAL.ASSIGNEE') }}</span>
              <span class="text-sm text-n-slate-12">{{ contact.assignee.name }}</span>
            </div>
          </div>

          <!-- Mesclar contato duplicado -->
          <div class="border-t border-n-weak pt-4">
            <button
              v-if="!showMergeSection"
              class="w-full flex items-center justify-center gap-2 border border-n-weak text-n-slate-11 rounded-xl py-2.5 text-sm font-medium hover:bg-n-alpha-1 transition-colors"
              @click="showMergeSection = true"
            >
              <span class="i-lucide-merge text-base" />
              {{ $t('CRM.MERGE.BUTTON') }}
            </button>

            <div v-else class="space-y-3">
              <div>
                <p class="text-sm font-medium text-n-slate-12 flex items-center gap-1.5">
                  <span class="i-lucide-merge text-base text-n-brand" />
                  {{ $t('CRM.MERGE.TITLE') }}
                </p>
                <p class="text-xs text-n-slate-10 mt-1">{{ $t('CRM.MERGE.HINT') }}</p>
              </div>

              <input
                v-model="mergeSearch"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
                :placeholder="$t('CRM.MERGE.SEARCH_PLACEHOLDER')"
                @input="onMergeSearchInput"
              />

              <div v-if="isMergeSearching" class="text-xs text-n-slate-10 py-1">{{ $t('CRM.MODAL.LOADING') }}</div>

              <div v-else-if="mergeResults.length" class="max-h-40 overflow-y-auto space-y-0.5">
                <button
                  v-for="c in mergeResults"
                  :key="c.id"
                  class="w-full flex items-center gap-2 px-2.5 py-1.5 rounded-lg text-left transition-colors"
                  :class="mergeCandidate?.id === c.id ? 'bg-n-brand/10 border border-n-brand' : 'hover:bg-n-alpha-1 border border-transparent'"
                  @click="mergeCandidate = c"
                >
                  <div class="w-6 h-6 rounded-full bg-n-slate-9 flex items-center justify-center text-white text-[10px] font-semibold flex-shrink-0 overflow-hidden">
                    <img v-if="c.avatar_url" :src="c.avatar_url" class="w-6 h-6 object-cover" />
                    <span v-else>{{ c.name?.[0]?.toUpperCase() ?? '?' }}</span>
                  </div>
                  <div class="flex-1 min-w-0">
                    <p class="text-xs font-medium text-n-slate-12 truncate">{{ c.name }}</p>
                    <p class="text-[11px] text-n-slate-10 truncate">{{ c.phone_number ?? c.email ?? '—' }}</p>
                  </div>
                </button>
              </div>

              <div v-if="mergeCandidate" class="bg-amber-500/10 border border-amber-500/30 rounded-lg p-2.5">
                <p class="text-xs text-amber-700 dark:text-amber-400">
                  {{ $t('CRM.MERGE.CONFIRM', { mergee: mergeCandidate.name, base: contact.name }) }}
                </p>
              </div>

              <div class="flex gap-2">
                <button
                  class="flex-1 bg-n-brand text-white rounded-lg py-2 text-sm font-medium disabled:opacity-50"
                  :disabled="!mergeCandidate || isMerging"
                  @click="doMerge"
                >
                  {{ isMerging ? $t('CRM.MODAL.SAVING') : $t('CRM.MERGE.APPLY') }}
                </button>
                <button
                  class="px-4 border border-n-weak rounded-lg py-2 text-sm text-n-slate-11"
                  @click="showMergeSection = false; mergeCandidate = null"
                >
                  {{ $t('CRM.CANCEL') }}
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- ── Tab: Conversa ── -->
        <div v-else-if="activeTab === 'conversation'" class="p-6">
          <!-- No conversation -->
          <div
            v-if="!contact.last_conversation"
            class="flex flex-col items-center justify-center py-12 text-n-slate-10"
          >
            <span class="i-lucide-message-square-off text-4xl mb-3" />
            <p class="text-sm text-center">{{ $t('CRM.MODAL.NO_CONVERSATION') }}</p>
          </div>

          <!-- Conversation preview -->
          <div v-else class="space-y-4">
            <!-- Status + Channel row -->
            <div class="flex items-center gap-3 flex-wrap">
              <span
                class="px-2.5 py-1 rounded-full text-xs font-medium"
                :class="statusClass(contact.last_conversation.status)"
              >
                {{ $t(`CRM.MODAL.STATUS.${contact.last_conversation.status}`) }}
              </span>

              <div class="flex items-center gap-1.5 text-sm text-n-slate-10">
                <span :class="channelIcon(contact.last_conversation.channel_type)" class="text-base" />
                {{ contact.last_conversation.inbox_name }}
              </div>
            </div>

            <!-- Last message preview -->
            <div class="bg-n-alpha-1 rounded-xl p-4">
              <p class="text-xs text-n-slate-10 mb-2">{{ $t('CRM.MODAL.LAST_MESSAGE') }}</p>
              <p v-if="contact.last_conversation.last_message" class="text-sm text-n-slate-12 leading-relaxed">
                {{ contact.last_conversation.last_message }}
              </p>
              <p v-else class="text-sm text-n-slate-10 italic">
                {{ $t('CRM.MODAL.NO_MESSAGES') }}
              </p>
              <p v-if="contact.last_conversation.last_message_at" class="text-xs text-n-slate-9 mt-2">
                {{ relativeTime(contact.last_conversation.last_message_at) }}
              </p>
            </div>

            <!-- Reply here (popup) + open conversation -->
            <button
              class="w-full flex items-center justify-center gap-2 bg-n-brand text-white rounded-xl py-3 text-sm font-medium hover:bg-n-brand/90 transition-colors"
              @click="emit('openChat', contact); emit('close')"
            >
              <span class="i-lucide-message-circle-more text-base" />
              {{ $t('CRM.CHAT.REPLY_HERE') }}
            </button>
            <button
              class="w-full flex items-center justify-center gap-2 border border-n-weak text-n-slate-11 rounded-xl py-2.5 text-sm font-medium hover:bg-n-alpha-1 transition-colors"
              @click="openConversation"
            >
              <span class="i-lucide-external-link text-base" />
              {{ $t('CRM.MODAL.OPEN_CONVERSATION') }}
            </button>

            <!-- Conversation details -->
            <div class="text-xs text-n-slate-9 text-center">
              #{{ contact.last_conversation.id }} •
              {{ contact.conversations_count }} {{ $t('CRM.MODAL.CONVERSATIONS') }}
            </div>
          </div>
        </div>

        <!-- ── Tab: Histórico ── -->
        <div v-else-if="activeTab === 'history'" class="p-6">

          <!-- Loading -->
          <div v-if="historyLoading" class="flex items-center justify-center py-12 text-n-slate-10">
            <span class="i-lucide-loader-2 text-2xl animate-spin mr-2" />
            <span class="text-sm">{{ $t('CRM.MODAL.LOADING') }}</span>
          </div>

          <!-- Error -->
          <div v-else-if="historyError" class="flex flex-col items-center justify-center py-12 text-n-slate-10">
            <span class="i-lucide-alert-circle text-3xl mb-2 text-red-400" />
            <p class="text-sm">{{ $t('CRM.ERROR.GENERIC') }}</p>
            <button
              class="mt-3 text-xs text-n-brand hover:underline"
              @click="loadHistory"
            >
              {{ $t('CRM.RETRY') }}
            </button>
          </div>

          <!-- Empty state -->
          <div
            v-else-if="!historyLogs.length"
            class="flex flex-col items-center justify-center py-12 text-n-slate-10"
          >
            <span class="i-lucide-clock-4 text-4xl mb-3" />
            <p class="text-sm text-center">{{ $t('CRM.MODAL.NO_HISTORY') }}</p>
          </div>

          <!-- Timeline -->
          <div v-else>
            <!-- Summary card -->
            <div class="bg-n-alpha-1 rounded-xl p-4 mb-6 flex items-center justify-between">
              <div>
                <p class="text-xs text-n-slate-10 mb-0.5">{{ $t('CRM.MODAL.HISTORY_TOTAL_TIME') }}</p>
                <p class="text-lg font-semibold text-n-slate-12">
                  {{ formatDuration(totalMinutes) ?? '—' }}
                </p>
              </div>
              <div class="text-right">
                <p class="text-xs text-n-slate-10 mb-0.5">{{ $t('CRM.MODAL.HISTORY_STAGES') }}</p>
                <p class="text-lg font-semibold text-n-slate-12">{{ historyLogs.length }}</p>
              </div>
            </div>

            <!-- Stage entries -->
            <div class="relative pl-6">
              <!-- Vertical line -->
              <div class="absolute left-2 top-2 bottom-2 w-0.5 bg-n-weak" />

              <div
                v-for="(log, idx) in historyLogs"
                :key="log.id"
                class="relative mb-5 last:mb-0"
              >
                <!-- Dot on timeline -->
                <div
                  class="absolute -left-4 top-1.5 w-3 h-3 rounded-full border-2 border-white dark:border-n-solid-1 shadow-sm flex-shrink-0"
                  :style="{ backgroundColor: log.stage_color || '#6B7280' }"
                />

                <!-- Card -->
                <div class="bg-n-solid-2 rounded-xl p-3.5 border border-n-weak hover:border-n-alpha-3 transition-colors">
                  <div class="flex items-start justify-between gap-2">
                    <!-- Stage name + pill -->
                    <div class="flex items-center gap-2 flex-wrap min-w-0">
                      <span
                        class="text-xs font-medium px-2 py-0.5 rounded-full text-white flex-shrink-0"
                        :style="{ backgroundColor: log.stage_color || '#6B7280' }"
                      >
                        {{ log.stage_name }}
                      </span>
                      <!-- Current stage indicator -->
                      <span
                        v-if="!log.left_at"
                        class="text-xs bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400 px-2 py-0.5 rounded-full"
                      >
                        {{ $t('CRM.MODAL.HISTORY_CURRENT') }}
                      </span>
                    </div>

                    <!-- Duration badge -->
                    <span
                      v-if="log.duration_minutes"
                      class="text-xs font-mono bg-n-alpha-2 text-n-slate-11 px-2 py-0.5 rounded-full flex-shrink-0"
                    >
                      {{ formatDuration(log.duration_minutes) }}
                    </span>
                    <span
                      v-else-if="!log.left_at"
                      class="text-xs bg-n-alpha-2 text-n-slate-11 px-2 py-0.5 rounded-full flex-shrink-0 animate-pulse"
                    >
                      {{ $t('CRM.MODAL.HISTORY_IN_PROGRESS') }}
                    </span>
                  </div>

                  <!-- Dates -->
                  <div class="mt-2 flex items-center gap-3 text-xs text-n-slate-10 flex-wrap">
                    <span class="flex items-center gap-1">
                      <span class="i-lucide-log-in text-[11px]" />
                      {{ new Date(log.entered_at).toLocaleString('pt-BR', { day:'2-digit', month:'2-digit', hour:'2-digit', minute:'2-digit' }) }}
                    </span>
                    <span v-if="log.left_at" class="flex items-center gap-1">
                      <span class="i-lucide-log-out text-[11px]" />
                      {{ new Date(log.left_at).toLocaleString('pt-BR', { day:'2-digit', month:'2-digit', hour:'2-digit', minute:'2-digit' }) }}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

      </div>
    </div>
  </div>
</template>
