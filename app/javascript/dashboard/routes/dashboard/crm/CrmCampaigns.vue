<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ChipPicker from './components/ChipPicker.vue';
import { relativeTime } from './helpers';

const store = useStore();
const router = useRouter();

const activeTab = ref('campaigns'); // campaigns | automations
const campaigns = ref([]);
const automations = ref([]);
const isLoading = ref(false);
const showComposer = ref(false);
const showAutomationComposer = ref(false);
const deleteConfirmId = ref(null);
const deleteAutoConfirmId = ref(null);

// ── Formulário de campanha ────────────────────────────────────────────
const form = ref({
  name: '',
  inbox_id: null,
  apply_label: '',
});
const scheduledAt = ref(''); // vazio = publica agora; preenchido = agenda
const includeLabelIds = ref([]);
const excludeLabelIds = ref([]);
const includeStageIds = ref([]);
const excludeStageIds = ref([]);
const conversionStageIds = ref([]);
const conversionLabelIds = ref([]);
const periodField = ref(''); // '' | contact_created | label_applied
const periodFrom = ref('');
const periodTo = ref('');
const audiencePreview = ref(null);
const isPreviewLoading = ref(false);
const isSubmitting = ref(false);

// ── Formulário de automação (régua) ───────────────────────────────────
const aForm = ref({
  name: '',
  inbox_id: null,
  trigger_label: '',
  trigger_stage_id: null,
  delay_days: 7,
  required_labels: [],
  exclude_labels: [],
});

// ── Template compartilhado entre os dois composers ────────────────────
const templates = ref([]);
const selectedTemplateName = ref('');
const varValues = ref({});
const isLoadingTemplates = ref(false);

// ── Painel de resultados ──────────────────────────────────────────────
const resultsCampaign = ref(null);
const results = ref(null);
const isResultsLoading = ref(false);

// ── Dados de apoio ────────────────────────────────────────────────────
const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabels');
const pipelines = useMapGetter('crm/getPipelines');

const whatsappInboxes = computed(() =>
  inboxes.value.filter(i => i.channel_type === 'Channel::Whatsapp')
);

const allStages = computed(() =>
  pipelines.value.flatMap(p =>
    (p.stages ?? []).map(s => ({ ...s, pipeline_name: p.name }))
  )
);

// Opções para os seletores de chips
const labelOptions = computed(() =>
  labels.value.map(l => ({ id: l.id, label: l.title, color: l.color }))
);
const labelTitleOptions = computed(() =>
  labels.value.map(l => ({ id: l.title, label: l.title, color: l.color }))
);
const stageOptions = computed(() =>
  allStages.value.map(s => ({
    id: s.id,
    label: `${s.pipeline_name} › ${s.name}`,
    color: s.color,
  }))
);

const selectedTemplate = computed(
  () => templates.value.find(t => t.name === selectedTemplateName.value) ?? null
);

const bodyText = computed(() => {
  const body = selectedTemplate.value?.components?.find(c => c.type === 'BODY');
  return body?.text ?? '';
});

const variableTokens = computed(() => {
  const tokens = new Set();
  const re = /\{\{\s*(\d+)\s*\}\}/g;
  let m = re.exec(bodyText.value);
  while (m !== null) {
    tokens.add(m[1]);
    m = re.exec(bodyText.value);
  }
  return [...tokens];
});

const renderedPreview = computed(() =>
  bodyText.value.replace(/\{\{\s*(\d+)\s*\}\}/g, (full, token) =>
    varValues.value[token]?.trim() ? varValues.value[token] : full
  )
);

const templateReady = computed(
  () =>
    selectedTemplate.value &&
    variableTokens.value.every(t => varValues.value[t]?.trim())
);

const hasAudience = computed(
  () => includeLabelIds.value.length > 0 || includeStageIds.value.length > 0
);

const canSubmit = computed(
  () =>
    form.value.name.trim() &&
    form.value.inbox_id &&
    templateReady.value &&
    hasAudience.value
);

const canSubmitAutomation = computed(
  () =>
    aForm.value.name.trim() &&
    aForm.value.inbox_id &&
    (aForm.value.trigger_label || aForm.value.trigger_stage_id) &&
    aForm.value.delay_days >= 0 &&
    templateReady.value
);

// qualquer mudança no público invalida a prévia calculada
watch(
  [includeLabelIds, excludeLabelIds, includeStageIds, excludeStageIds, periodField, periodFrom, periodTo],
  () => {
    audiencePreview.value = null;
  }
);

// Chaves literais não podem aparecer dentro de interpolação no template
const wrapToken = t => '{{' + t + '}}';
const TOKEN_HINT = wrapToken('contact.name');

// ── Carga ─────────────────────────────────────────────────────────────
let refreshTimer = null;

const loadCampaigns = async () => {
  try {
    campaigns.value = await store.dispatch('crm/fetchCampaigns');
  } catch {
    // silencioso no polling
  }
};

const loadAutomations = async () => {
  try {
    automations.value = await store.dispatch('crm/fetchMessageAutomations');
  } catch {
    // silencioso
  }
};

onMounted(async () => {
  isLoading.value = true;
  await Promise.all([
    loadCampaigns(),
    loadAutomations(),
    store.dispatch('crm/fetchPipelines'),
    store.dispatch('labels/get'),
    store.dispatch('inboxes/get'),
  ]);
  isLoading.value = false;
  refreshTimer = setInterval(() => {
    if (campaigns.value.some(c => c.status === 'processing')) loadCampaigns();
  }, 5000);
});

onUnmounted(() => clearInterval(refreshTimer));

// ── Templates ─────────────────────────────────────────────────────────
const loadTemplates = async inboxId => {
  if (!inboxId) return;
  isLoadingTemplates.value = true;
  selectedTemplateName.value = '';
  varValues.value = {};
  try {
    templates.value = await store.dispatch('crm/fetchWhatsappTemplates', inboxId);
  } catch {
    templates.value = [];
    useAlert('Erro ao carregar templates do WhatsApp');
  } finally {
    isLoadingTemplates.value = false;
  }
};

const isSyncingTemplates = ref(false);

// A Meta demora alguns segundos para o Chatwoot puxar o template novo —
// dispara a sincronização e espera antes de recarregar a lista
const syncTemplates = async inboxId => {
  if (!inboxId || isSyncingTemplates.value) return;
  isSyncingTemplates.value = true;
  try {
    await store.dispatch('inboxes/syncTemplates', inboxId);
    useAlert('Sincronizando com a Meta… aguarde alguns segundos');
    await new Promise(resolve => setTimeout(resolve, 5000));
    await loadTemplates(inboxId);
  } catch {
    useAlert('Erro ao sincronizar templates');
  } finally {
    isSyncingTemplates.value = false;
  }
};

const buildTemplateParams = () => ({
  name: selectedTemplate.value.name,
  namespace: selectedTemplate.value.namespace ?? '',
  language: selectedTemplate.value.language,
  category: selectedTemplate.value.category,
  processed_params: { body: { ...varValues.value } },
});

// ── Composer de campanha ──────────────────────────────────────────────
const openComposer = () => {
  form.value = { name: '', inbox_id: whatsappInboxes.value[0]?.id ?? null, apply_label: '' };
  scheduledAt.value = '';
  templates.value = [];
  selectedTemplateName.value = '';
  varValues.value = {};
  includeLabelIds.value = [];
  excludeLabelIds.value = [];
  includeStageIds.value = [];
  excludeStageIds.value = [];
  conversionStageIds.value = [];
  conversionLabelIds.value = [];
  periodField.value = '';
  periodFrom.value = '';
  periodTo.value = '';
  audiencePreview.value = null;
  showComposer.value = true;
  if (form.value.inbox_id) loadTemplates(form.value.inbox_id);
};

const audiencePayload = () => ({
  include_label_ids: includeLabelIds.value,
  include_stage_ids: includeStageIds.value,
  exclude_label_ids: excludeLabelIds.value,
  exclude_stage_ids: excludeStageIds.value,
  period_field: periodField.value,
  period_from: periodFrom.value,
  period_to: periodTo.value,
});

const previewAudience = async () => {
  isPreviewLoading.value = true;
  try {
    audiencePreview.value = await store.dispatch('crm/previewAudience', audiencePayload());
  } catch {
    useAlert('Erro ao calcular o público');
  } finally {
    isPreviewLoading.value = false;
  }
};

const submit = async mode => {
  // mode: 'create' (salva sem enviar) | 'publish' (agenda se tiver data, senão envia agora)
  if (mode === 'publish' && !canSubmit.value) return;
  isSubmitting.value = true;
  try {
    const created = await store.dispatch('crm/createCampaign', {
      name: form.value.name,
      inbox_id: form.value.inbox_id,
      apply_label: form.value.apply_label,
      message_preview: bodyText.value,
      conversion_stage_ids: conversionStageIds.value,
      conversion_label_ids: conversionLabelIds.value,
      audience: audiencePayload(),
      template_params: buildTemplateParams(),
    });
    if (mode === 'publish' && scheduledAt.value) {
      await store.dispatch('crm/scheduleCampaign', {
        id: created.id,
        scheduledAt: scheduledAt.value,
      });
      useAlert(`Campanha agendada para ${formatDateTime(scheduledAt.value)}!`);
    } else if (mode === 'publish') {
      await store.dispatch('crm/sendCampaign', created.id);
      useAlert('Campanha publicada! Acompanhe o progresso na lista.');
    } else {
      useAlert('Campanha criada. Publique quando quiser.');
    }
    showComposer.value = false;
    await loadCampaigns();
  } catch {
    useAlert('Erro ao criar a campanha');
  } finally {
    isSubmitting.value = false;
  }
};

// ── Composer de automação ─────────────────────────────────────────────
const openAutomationComposer = () => {
  aForm.value = {
    name: '',
    inbox_id: whatsappInboxes.value[0]?.id ?? null,
    trigger_label: '',
    trigger_stage_id: null,
    delay_days: 7,
    required_labels: [],
    exclude_labels: [],
  };
  templates.value = [];
  selectedTemplateName.value = '';
  varValues.value = {};
  showAutomationComposer.value = true;
  if (aForm.value.inbox_id) loadTemplates(aForm.value.inbox_id);
};

const submitAutomation = async () => {
  if (!canSubmitAutomation.value) return;
  isSubmitting.value = true;
  try {
    await store.dispatch('crm/createMessageAutomation', {
      ...aForm.value,
      message_preview: bodyText.value,
      template_params: buildTemplateParams(),
      active: true,
    });
    useAlert('Automação criada! Ela roda a cada 5 minutos.');
    showAutomationComposer.value = false;
    await loadAutomations();
  } catch {
    useAlert('Erro ao criar a automação');
  } finally {
    isSubmitting.value = false;
  }
};

const toggleAutomationActive = async a => {
  try {
    await store.dispatch('crm/updateMessageAutomation', {
      id: a.id,
      active: !a.active,
    });
    await loadAutomations();
  } catch {
    useAlert('Erro ao atualizar a automação');
  }
};

const removeAutomation = async a => {
  try {
    await store.dispatch('crm/deleteMessageAutomation', a.id);
    deleteAutoConfirmId.value = null;
    await loadAutomations();
  } catch {
    useAlert('Erro ao excluir a automação');
  }
};

// ── Resultados ────────────────────────────────────────────────────────
const openResults = async c => {
  if (c.status === 'draft' || c.status === 'scheduled') return;
  resultsCampaign.value = c;
  results.value = null;
  isResultsLoading.value = true;
  try {
    results.value = await store.dispatch('crm/fetchCampaignResults', c.id);
  } catch {
    useAlert('Erro ao carregar resultados');
    resultsCampaign.value = null;
  } finally {
    isResultsLoading.value = false;
  }
};

const formatCurrency = v =>
  'R$ ' + Number(v || 0).toLocaleString('pt-BR', { maximumFractionDigits: 0 });

const formatDateTime = v =>
  v ? new Date(v).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' }) : '';

// ── Ações da lista ────────────────────────────────────────────────────
const sendDraft = async c => {
  try {
    await store.dispatch('crm/sendCampaign', c.id);
    useAlert('Campanha enviada!');
    await loadCampaigns();
  } catch {
    useAlert('Erro ao enviar a campanha');
  }
};

const removeCampaign = async c => {
  try {
    await store.dispatch('crm/deleteCampaign', c.id);
    deleteConfirmId.value = null;
    await loadCampaigns();
  } catch {
    useAlert('Erro ao excluir a campanha');
  }
};

const STATUS_META = {
  draft:      { label: 'Rascunho',   cls: 'bg-n-alpha-2 text-n-slate-11' },
  scheduled:  { label: 'Agendada',   cls: 'bg-purple-500/15 text-purple-600' },
  processing: { label: 'Enviando…',  cls: 'bg-blue-500/15 text-blue-600' },
  completed:  { label: 'Concluída',  cls: 'bg-green-500/15 text-green-600' },
  failed:     { label: 'Falhou',     cls: 'bg-red-500/15 text-red-600' },
};

const statsLine = c => {
  const s = c.stats ?? {};
  if (c.status === 'draft' || c.status === 'scheduled') return '';
  const parts = [`${s.sent ?? 0}/${s.total ?? 0} enviadas`];
  if (s.skipped) parts.push(`${s.skipped} puladas`);
  if (s.failed) parts.push(`${s.failed} falhas`);
  return parts.join(' · ');
};
</script>

<template>
  <div class="flex flex-col h-full w-full bg-n-solid-1 overflow-hidden">

    <!-- Header -->
    <div class="flex items-center gap-3 px-6 py-4 border-b border-n-weak flex-shrink-0 flex-wrap">
      <button
        class="flex items-center gap-1 text-sm text-n-slate-11 hover:text-n-slate-12"
        @click="router.push({ name: 'crm_board' })"
      >
        <span class="i-lucide-arrow-left" />
        CRM
      </button>
      <span class="text-n-slate-8">/</span>
      <h1 class="text-base font-semibold text-n-slate-12 flex items-center gap-2">
        <span class="i-lucide-megaphone text-n-brand" />
        Campanha WhatsApp
      </h1>

      <!-- Abas -->
      <div class="flex items-center gap-1 bg-n-solid-2 border border-n-weak rounded-xl p-1 ml-4">
        <button
          class="px-3 py-1.5 text-xs font-medium rounded-lg transition-colors"
          :class="activeTab === 'campaigns' ? 'bg-n-brand text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          @click="activeTab = 'campaigns'"
        >Campanhas</button>
        <button
          class="px-3 py-1.5 text-xs font-medium rounded-lg transition-colors"
          :class="activeTab === 'automations' ? 'bg-n-brand text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          @click="activeTab = 'automations'"
        >Automações</button>
      </div>

      <div class="flex-1" />
      <button
        v-if="activeTab === 'campaigns'"
        class="flex items-center gap-1.5 text-sm px-4 py-2 rounded-lg bg-n-brand text-white hover:opacity-90 transition-opacity"
        @click="openComposer"
      >
        <span class="i-lucide-plus" />
        Nova campanha
      </button>
      <button
        v-else
        class="flex items-center gap-1.5 text-sm px-4 py-2 rounded-lg bg-n-brand text-white hover:opacity-90 transition-opacity"
        @click="openAutomationComposer"
      >
        <span class="i-lucide-plus" />
        Nova automação
      </button>
    </div>

    <!-- Corpo -->
    <div class="flex-1 overflow-y-auto p-6">
      <div v-if="isLoading" class="flex justify-center py-16"><Spinner /></div>

      <!-- ══ ABA CAMPANHAS: grid de cards ══ -->
      <template v-else-if="activeTab === 'campaigns'">
        <div v-if="!campaigns.length" class="flex flex-col items-center justify-center py-20 text-n-slate-9">
          <span class="i-lucide-megaphone text-5xl mb-4" />
          <p class="text-sm">Nenhuma campanha ainda.</p>
          <p class="text-xs mt-1">Crie a primeira para disparar mensagens modelo do WhatsApp em massa.</p>
        </div>

        <div v-else class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          <div
            v-for="c in campaigns"
            :key="c.id"
            class="bg-n-solid-2 border border-n-weak rounded-xl p-4 flex flex-col gap-2 transition-all"
            :class="(c.status === 'completed' || c.status === 'processing') ? 'cursor-pointer hover:border-n-brand hover:shadow-sm' : ''"
            @click="openResults(c)"
          >
            <div class="flex items-center gap-2 flex-wrap">
              <span class="text-sm font-semibold text-n-slate-12 flex-1 min-w-0 truncate">{{ c.name }}</span>
              <span class="text-xs px-2 py-0.5 rounded-full flex-shrink-0" :class="STATUS_META[c.status]?.cls">
                {{ STATUS_META[c.status]?.label ?? c.status }}
              </span>
            </div>

            <p class="text-xs text-n-slate-10">
              {{ c.inbox_name }} · <span class="font-mono">{{ c.template_params?.name }}</span>
            </p>

            <p v-if="c.status === 'scheduled' && c.scheduled_at" class="text-xs text-purple-600 flex items-center gap-1">
              <span class="i-lucide-clock" /> Envia em {{ formatDateTime(c.scheduled_at) }}
            </p>
            <p v-if="statsLine(c)" class="text-xs text-n-slate-11">{{ statsLine(c) }}</p>
            <p v-if="c.stats?.error" class="text-xs text-red-500 truncate">{{ c.stats.error }}</p>

            <div class="flex items-center gap-2 mt-auto pt-2" @click.stop>
              <span
                v-if="c.status === 'completed' || c.status === 'processing'"
                class="text-xs text-green-600 flex items-center gap-1"
              >
                <span class="i-lucide-trending-up" /> Ver resultados
              </span>
              <button
                v-if="c.status === 'draft' || c.status === 'scheduled'"
                class="text-xs px-3 py-1.5 rounded-lg bg-n-brand text-white hover:opacity-90"
                @click="sendDraft(c)"
              >Enviar agora</button>

              <div class="flex-1" />
              <template v-if="c.status !== 'processing'">
                <button
                  v-if="deleteConfirmId !== c.id"
                  class="text-n-slate-10 hover:text-red-500 i-lucide-trash-2 text-sm"
                  @click="deleteConfirmId = c.id"
                />
                <button
                  v-else
                  class="text-xs px-2 py-1 rounded bg-red-500 text-white"
                  @click="removeCampaign(c)"
                >Confirmar</button>
              </template>
              <Spinner v-else :size="14" />
            </div>
          </div>
        </div>
      </template>

      <!-- ══ ABA AUTOMAÇÕES: réguas de mensagens ══ -->
      <template v-else>
        <div v-if="!automations.length" class="flex flex-col items-center justify-center py-20 text-n-slate-9">
          <span class="i-lucide-timer text-5xl mb-4" />
          <p class="text-sm">Nenhuma automação ainda.</p>
          <p class="text-xs mt-1 max-w-md text-center">
            Ex: quem recebeu a etiqueta "encerrou-contato" há 7 dias recebe automaticamente
            uma mensagem de marketing. Crie uma régua para 7, 30 e 60 dias.
          </p>
        </div>

        <div v-else class="space-y-3 max-w-3xl">
          <div
            v-for="a in automations"
            :key="a.id"
            class="bg-n-solid-2 border border-n-weak rounded-xl p-4 flex items-center gap-4"
          >
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2 flex-wrap">
                <span class="text-sm font-semibold text-n-slate-12">{{ a.name }}</span>
                <span
                  class="text-xs px-2 py-0.5 rounded-full"
                  :class="a.active ? 'bg-green-500/15 text-green-600' : 'bg-n-alpha-2 text-n-slate-10'"
                >{{ a.active ? 'Ativa' : 'Pausada' }}</span>
              </div>
              <p class="text-xs text-n-slate-10 mt-1">
                <template v-if="a.trigger_label">Etiqueta <span class="font-mono">{{ a.trigger_label }}</span></template>
                <template v-if="a.trigger_label && a.trigger_stage_name"> + </template>
                <template v-if="a.trigger_stage_name">Coluna <span class="font-mono">{{ a.trigger_stage_name }}</span></template>
                há <b>{{ a.delay_days }} dias</b> → template
                <span class="font-mono">{{ a.template_params?.name }}</span> ({{ a.inbox_name }})
              </p>
              <p v-if="a.required_labels?.length" class="text-xs text-n-slate-10 mt-0.5">
                Exige também: {{ a.required_labels.join(', ') }}
              </p>
              <p class="text-xs text-n-slate-11 mt-1">
                {{ a.stats?.sent ?? 0 }} enviadas
                <template v-if="a.stats?.last_run_at"> · última execução {{ relativeTime(a.stats.last_run_at) }}</template>
                · marcador: <span class="font-mono">{{ a.marker_label }}</span>
              </p>
            </div>

            <div class="flex items-center gap-2 flex-shrink-0">
              <button
                class="text-xs px-3 py-1.5 rounded-lg border transition-colors"
                :class="a.active
                  ? 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
                  : 'border-green-500/60 text-green-600 hover:bg-green-500/10'"
                @click="toggleAutomationActive(a)"
              >{{ a.active ? 'Pausar' : 'Ativar' }}</button>
              <button
                v-if="deleteAutoConfirmId !== a.id"
                class="text-n-slate-10 hover:text-red-500 i-lucide-trash-2"
                @click="deleteAutoConfirmId = a.id"
              />
              <button
                v-else
                class="text-xs px-2 py-1 rounded bg-red-500 text-white"
                @click="removeAutomation(a)"
              >Confirmar</button>
            </div>
          </div>
        </div>
      </template>
    </div>

    <!-- ── Composer de campanha ─────────────────────────────────── -->
    <div
      v-if="showComposer"
      class="fixed inset-0 z-40 bg-black/50 flex items-start justify-center overflow-y-auto py-8"
      @click.self="showComposer = false"
    >
      <div class="bg-n-solid-1 rounded-2xl w-full max-w-2xl mx-4 shadow-xl border border-n-weak">
        <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak">
          <h2 class="text-sm font-semibold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-megaphone text-n-brand" />
            Nova campanha
          </h2>
          <button class="i-lucide-x text-n-slate-10 hover:text-n-slate-12" @click="showComposer = false" />
        </div>

        <div class="p-5 space-y-5">
          <!-- Nome + quando publicar -->
          <div class="flex flex-wrap gap-3">
            <div class="flex-1 min-w-48">
              <label class="text-xs font-medium text-n-slate-11 block mb-1">Nome da campanha</label>
              <input
                v-model="form.name"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
                placeholder="Ex: Reativação consultas julho"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">
                Publicar em <span class="text-n-slate-9">(vazio = agora)</span>
              </label>
              <input
                v-model="scheduledAt"
                type="datetime-local"
                class="border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              />
            </div>
          </div>

          <!-- Inbox -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Caixa de entrada (WhatsApp oficial)</label>
            <select
              v-model="form.inbox_id"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              @change="loadTemplates(form.inbox_id)"
            >
              <option v-for="i in whatsappInboxes" :key="i.id" :value="i.id">{{ i.name }}</option>
            </select>
            <p v-if="!whatsappInboxes.length" class="text-xs text-red-500 mt-1">
              Nenhuma caixa WhatsApp API oficial encontrada.
            </p>
          </div>

          <!-- Template -->
          <div>
            <div class="flex items-center justify-between mb-1">
              <label class="text-xs font-medium text-n-slate-11 flex items-center gap-1">
                Mensagem modelo (aprovada pelo Meta)
                <Spinner v-if="isLoadingTemplates" :size="12" class="ml-1" />
              </label>
              <button
                type="button"
                class="text-xs text-n-brand hover:underline flex items-center gap-1 disabled:opacity-50 disabled:no-underline"
                :disabled="!form.inbox_id || isSyncingTemplates"
                @click="syncTemplates(form.inbox_id)"
              >
                <span class="i-lucide-refresh-cw text-xs" :class="isSyncingTemplates ? 'animate-spin' : ''" />
                {{ isSyncingTemplates ? 'Sincronizando…' : 'Buscar novos templates' }}
              </button>
            </div>
            <select
              v-model="selectedTemplateName"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
            >
              <option value="" disabled>Selecione um template…</option>
              <option v-for="t in templates" :key="`${t.name}-${t.language}`" :value="t.name">
                {{ t.name }} ({{ t.language }})
              </option>
            </select>

            <div v-if="selectedTemplate" class="mt-3 space-y-3">
              <div class="bg-n-alpha-1 border border-n-weak rounded-lg p-3">
                <p class="text-xs text-n-slate-10 mb-1">Prévia da mensagem</p>
                <p class="text-sm text-n-slate-12 whitespace-pre-wrap">{{ renderedPreview }}</p>
              </div>
              <div v-for="token in variableTokens" :key="token">
                <label class="text-xs font-medium text-n-slate-11 block mb-1">
                  Variável {{ wrapToken(token) }}
                </label>
                <input
                  v-model="varValues[token]"
                  class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
                  :placeholder="'Valor fixo ou ' + TOKEN_HINT + ' para personalizar'"
                />
              </div>
              <p v-if="variableTokens.length" class="text-xs text-n-slate-9">
                Dica: use <span class="font-mono">{{ TOKEN_HINT }}</span> para inserir o nome do lead automaticamente.
              </p>
            </div>
          </div>

          <!-- Público: incluir -->
          <div class="bg-n-alpha-1 border border-n-weak rounded-xl p-4 space-y-3">
            <p class="text-xs font-semibold text-n-slate-11 flex items-center gap-1">
              <span class="i-lucide-users text-n-brand" /> Público — quem VAI receber
            </p>
            <div>
              <p class="text-xs text-n-slate-10 mb-1.5">Etiquetas:</p>
              <ChipPicker
                v-model="includeLabelIds"
                :options="labelOptions"
                placeholder="Etiqueta"
                accent="brand"
              />
            </div>
            <div>
              <p class="text-xs text-n-slate-10 mb-1.5">Colunas do CRM:</p>
              <ChipPicker
                v-model="includeStageIds"
                :options="stageOptions"
                placeholder="Coluna"
                accent="brand"
              />
            </div>
          </div>

          <!-- Período -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-2">
              Período <span class="text-n-slate-9">(opcional — acione a base em blocos: janeiro, fevereiro…)</span>
            </label>
            <div class="flex flex-wrap items-center gap-2">
              <select
                v-model="periodField"
                class="border border-n-weak rounded-lg px-2 py-2 text-xs bg-n-solid-2 text-n-slate-12"
                @change="audiencePreview = null"
              >
                <option value="">Sem filtro de período</option>
                <option value="contact_created">Lead chegou entre…</option>
                <option value="label_applied">Etiqueta aplicada entre…</option>
              </select>
              <template v-if="periodField">
                <input
                  v-model="periodFrom"
                  type="date"
                  class="border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-2 text-n-slate-12"
                  @change="audiencePreview = null"
                />
                <span class="text-xs text-n-slate-10">até</span>
                <input
                  v-model="periodTo"
                  type="date"
                  class="border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-2 text-n-slate-12"
                  @change="audiencePreview = null"
                />
              </template>
            </div>
            <p v-if="periodField === 'label_applied'" class="text-xs text-n-slate-9 mt-1">
              Considera a data em que as etiquetas do público foram aplicadas ao lead.
            </p>
          </div>

          <!-- Público: excluir -->
          <div class="bg-n-alpha-1 border border-n-weak rounded-xl p-4 space-y-3">
            <p class="text-xs font-semibold text-n-slate-11 flex items-center gap-1">
              <span class="i-lucide-user-x text-red-500" /> Exclusões — quem NÃO deve receber
              <span class="text-n-slate-9 font-normal">(opcional)</span>
            </p>
            <div>
              <p class="text-xs text-n-slate-10 mb-1.5">Etiquetas:</p>
              <ChipPicker
                v-model="excludeLabelIds"
                :options="labelOptions"
                placeholder="Etiqueta"
                accent="red"
              />
            </div>
            <div>
              <p class="text-xs text-n-slate-10 mb-1.5">Colunas do CRM:</p>
              <ChipPicker
                v-model="excludeStageIds"
                :options="stageOptions"
                placeholder="Coluna"
                accent="red"
              />
            </div>

            <div class="flex items-center gap-3 pt-1">
              <button
                class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center gap-1"
                :disabled="!hasAudience || isPreviewLoading"
                @click="previewAudience"
              >
                <span class="i-lucide-users" />
                {{ isPreviewLoading ? 'Calculando…' : 'Calcular público' }}
              </button>
              <span v-if="audiencePreview" class="text-sm text-n-slate-12 font-medium">
                {{ audiencePreview.count }} contato(s) com telefone
              </span>
            </div>
          </div>

          <!-- Etiqueta pós-envio -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1">
              Etiqueta aplicada a quem receber <span class="text-n-slate-9">(opcional)</span>
            </label>
            <input
              v-model="form.apply_label"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              placeholder="Ex: campanha-julho-2026"
            />
          </div>

          <!-- Conversões -->
          <div class="bg-n-alpha-1 border border-n-weak rounded-xl p-4 space-y-3">
            <p class="text-xs font-semibold text-n-slate-11 flex items-center gap-1">
              <span class="i-lucide-trending-up text-green-600" /> O que conta como CONVERSÃO
              <span class="text-n-slate-9 font-normal">(para o painel de resultados)</span>
            </p>
            <div>
              <p class="text-xs text-n-slate-10 mb-1.5">Colunas do CRM (ex: Cirurgia Realizada):</p>
              <ChipPicker
                v-model="conversionStageIds"
                :options="stageOptions"
                placeholder="Coluna"
                accent="green"
              />
            </div>
            <div>
              <p class="text-xs text-n-slate-10 mb-1.5">Etiquetas (ex: consulta-agendada):</p>
              <ChipPicker
                v-model="conversionLabelIds"
                :options="labelOptions"
                placeholder="Etiqueta"
                accent="green"
              />
            </div>
          </div>
        </div>

        <!-- Footer -->
        <div class="flex items-center justify-end gap-2 px-5 py-4 border-t border-n-weak">
          <button
            class="text-sm px-4 py-2 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
            @click="showComposer = false"
          >Cancelar</button>
          <button
            class="text-sm px-4 py-2 rounded-lg border border-n-brand text-n-brand hover:bg-n-brand/10 disabled:opacity-50"
            :disabled="isSubmitting || !form.name.trim() || !form.inbox_id || !templateReady"
            @click="submit('create')"
          >Criar</button>
          <button
            class="text-sm px-4 py-2 rounded-lg text-white hover:opacity-90 disabled:opacity-50 flex items-center gap-1.5"
            :class="scheduledAt ? 'bg-purple-600' : 'bg-n-brand'"
            :disabled="!canSubmit || isSubmitting"
            @click="submit('publish')"
          >
            <span :class="scheduledAt ? 'i-lucide-clock' : 'i-lucide-send'" />
            <template v-if="isSubmitting">Publicando…</template>
            <template v-else-if="scheduledAt">Publicar em {{ formatDateTime(scheduledAt) }}</template>
            <template v-else>Publicar agora</template>
          </button>
        </div>
      </div>
    </div>

    <!-- ── Composer de automação (régua) ─────────────────────────── -->
    <div
      v-if="showAutomationComposer"
      class="fixed inset-0 z-40 bg-black/50 flex items-start justify-center overflow-y-auto py-8"
      @click.self="showAutomationComposer = false"
    >
      <div class="bg-n-solid-1 rounded-2xl w-full max-w-2xl mx-4 shadow-xl border border-n-weak">
        <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak">
          <h2 class="text-sm font-semibold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-timer text-n-brand" />
            Nova automação de mensagem
          </h2>
          <button class="i-lucide-x text-n-slate-10 hover:text-n-slate-12" @click="showAutomationComposer = false" />
        </div>

        <div class="p-5 space-y-5">
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Nome</label>
            <input
              v-model="aForm.name"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              placeholder="Ex: Reativação 7 dias após encerrar contato"
            />
          </div>

          <!-- Gatilho -->
          <div class="bg-n-alpha-1 border border-n-weak rounded-xl p-4 space-y-3">
            <p class="text-xs font-semibold text-n-slate-11 flex items-center gap-1">
              <span class="i-lucide-zap text-yellow-500" /> Gatilho
            </p>
            <div class="flex flex-wrap items-center gap-2 text-sm text-n-slate-12">
              <span>Quando o lead tiver a etiqueta</span>
              <select
                v-model="aForm.trigger_label"
                class="border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-2 text-n-slate-12"
              >
                <option value="">(nenhuma)</option>
                <option v-for="l in labels" :key="l.id" :value="l.title">{{ l.title }}</option>
              </select>
              <span>e/ou estiver na coluna</span>
              <select
                v-model="aForm.trigger_stage_id"
                class="border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-2 text-n-slate-12"
              >
                <option :value="null">(nenhuma)</option>
                <option v-for="s in allStages" :key="s.id" :value="s.id">
                  {{ s.pipeline_name }} › {{ s.name }}
                </option>
              </select>
              <span>há</span>
              <input
                v-model.number="aForm.delay_days"
                type="number"
                min="0"
                class="w-20 border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-2 text-n-slate-12"
              />
              <span>dias → envia a mensagem</span>
            </div>
            <p v-if="!aForm.trigger_label && !aForm.trigger_stage_id" class="text-xs text-amber-600">
              Escolha pelo menos um gatilho: etiqueta ou coluna.
            </p>

            <div>
              <p class="text-xs text-n-slate-10 mb-1.5">E que TAMBÉM tenha estas etiquetas (opcional):</p>
              <ChipPicker
                v-model="aForm.required_labels"
                :options="labelTitleOptions"
                placeholder="Etiqueta"
                accent="brand"
              />
            </div>

            <div>
              <p class="text-xs text-n-slate-10 mb-1.5">E que NÃO tenha estas (opcional):</p>
              <ChipPicker
                v-model="aForm.exclude_labels"
                :options="labelTitleOptions"
                placeholder="Etiqueta"
                accent="red"
              />
            </div>

            <p class="text-xs text-n-slate-9">
              Cada lead recebe esta automação apenas uma vez (controlado por etiqueta marcadora automática).
            </p>
          </div>

          <!-- Inbox -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Caixa de entrada (WhatsApp oficial)</label>
            <select
              v-model="aForm.inbox_id"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              @change="loadTemplates(aForm.inbox_id)"
            >
              <option v-for="i in whatsappInboxes" :key="i.id" :value="i.id">{{ i.name }}</option>
            </select>
          </div>

          <!-- Template -->
          <div>
            <div class="flex items-center justify-between mb-1">
              <label class="text-xs font-medium text-n-slate-11 flex items-center gap-1">
                Mensagem modelo (aprovada pelo Meta)
                <Spinner v-if="isLoadingTemplates" :size="12" class="ml-1" />
              </label>
              <button
                type="button"
                class="text-xs text-n-brand hover:underline flex items-center gap-1 disabled:opacity-50 disabled:no-underline"
                :disabled="!aForm.inbox_id || isSyncingTemplates"
                @click="syncTemplates(aForm.inbox_id)"
              >
                <span class="i-lucide-refresh-cw text-xs" :class="isSyncingTemplates ? 'animate-spin' : ''" />
                {{ isSyncingTemplates ? 'Sincronizando…' : 'Buscar novos templates' }}
              </button>
            </div>
            <select
              v-model="selectedTemplateName"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
            >
              <option value="" disabled>Selecione um template…</option>
              <option v-for="t in templates" :key="`${t.name}-${t.language}`" :value="t.name">
                {{ t.name }} ({{ t.language }})
              </option>
            </select>

            <div v-if="selectedTemplate" class="mt-3 space-y-3">
              <div class="bg-n-alpha-1 border border-n-weak rounded-lg p-3">
                <p class="text-xs text-n-slate-10 mb-1">Prévia da mensagem</p>
                <p class="text-sm text-n-slate-12 whitespace-pre-wrap">{{ renderedPreview }}</p>
              </div>
              <div v-for="token in variableTokens" :key="token">
                <label class="text-xs font-medium text-n-slate-11 block mb-1">
                  Variável {{ wrapToken(token) }}
                </label>
                <input
                  v-model="varValues[token]"
                  class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
                  :placeholder="'Valor fixo ou ' + TOKEN_HINT + ' para personalizar'"
                />
              </div>
            </div>
          </div>
        </div>

        <div class="flex items-center justify-end gap-2 px-5 py-4 border-t border-n-weak">
          <button
            class="text-sm px-4 py-2 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
            @click="showAutomationComposer = false"
          >Cancelar</button>
          <button
            class="text-sm px-4 py-2 rounded-lg bg-n-brand text-white hover:opacity-90 disabled:opacity-50 flex items-center gap-1.5"
            :disabled="!canSubmitAutomation || isSubmitting"
            @click="submitAutomation"
          >
            <span class="i-lucide-timer" />
            {{ isSubmitting ? 'Criando…' : 'Criar automação' }}
          </button>
        </div>
      </div>
    </div>

    <!-- ── Painel de Resultados ──────────────────────────────────── -->
    <div
      v-if="resultsCampaign"
      class="fixed inset-0 z-40 bg-black/50 flex items-start justify-center overflow-y-auto py-8"
      @click.self="resultsCampaign = null"
    >
      <div class="bg-n-solid-1 rounded-2xl w-full max-w-2xl mx-4 shadow-xl border border-n-weak">
        <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak">
          <h2 class="text-sm font-semibold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-trending-up text-green-600" />
            Resultados — {{ resultsCampaign.name }}
          </h2>
          <button class="i-lucide-x text-n-slate-10 hover:text-n-slate-12" @click="resultsCampaign = null" />
        </div>

        <div v-if="isResultsLoading" class="flex justify-center py-16"><Spinner /></div>

        <div v-else-if="results" class="p-5 space-y-5">
          <!-- KPIs -->
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <div class="bg-n-alpha-1 border border-n-weak rounded-xl p-3">
              <p class="text-xs text-n-slate-10">Receberam</p>
              <p class="text-xl font-bold text-n-slate-12">{{ results.recipients }}</p>
            </div>
            <div class="bg-n-alpha-1 border border-n-weak rounded-xl p-3">
              <p class="text-xs text-n-slate-10">Responderam</p>
              <p class="text-xl font-bold text-blue-600">{{ results.replies?.count ?? 0 }}</p>
            </div>
            <div class="bg-n-alpha-1 border border-n-weak rounded-xl p-3">
              <p class="text-xs text-n-slate-10">Conversões</p>
              <p class="text-xl font-bold text-green-600">{{ results.conversions.count + (results.label_conversions?.count ?? 0) }}</p>
            </div>
            <div class="bg-n-alpha-1 border border-n-weak rounded-xl p-3">
              <p class="text-xs text-n-slate-10">Valor total</p>
              <p class="text-xl font-bold text-green-600">{{ formatCurrency(results.conversions.total_value) }}</p>
            </div>
          </div>

          <!-- Respostas -->
          <div v-if="results.replies?.items?.length">
            <p class="text-xs font-medium text-n-slate-11 mb-2">
              Respostas recebidas ({{ results.replies.count }})
            </p>
            <div class="space-y-1.5 max-h-64 overflow-y-auto">
              <div
                v-for="r in results.replies.items"
                :key="r.contact_id"
                class="bg-n-alpha-1 rounded-lg px-3 py-2"
              >
                <div class="flex items-center justify-between">
                  <p class="text-sm font-medium text-n-slate-12">{{ r.name }}</p>
                  <span class="text-xs text-n-slate-9">{{ relativeTime(r.replied_at) }}</span>
                </div>
                <p class="text-xs text-n-slate-11 mt-0.5 italic">"{{ r.reply }}"</p>
              </div>
            </div>
          </div>

          <!-- Conversões por etiqueta (ex: agendou consulta) -->
          <div v-if="results.label_conversions?.count">
            <p class="text-xs font-medium text-n-slate-11 mb-2">
              Converteram por etiqueta ({{ results.label_conversions.labels.join(', ') }}) — {{ results.label_conversions.count }}
            </p>
            <div class="space-y-1.5 max-h-48 overflow-y-auto">
              <div
                v-for="c in results.label_conversions.items"
                :key="c.contact_id"
                class="flex items-center justify-between bg-n-alpha-1 rounded-lg px-3 py-2"
              >
                <p class="text-sm text-n-slate-12">{{ c.name }}</p>
                <span class="text-xs text-green-600">{{ c.labels.join(', ') }}</span>
              </div>
            </div>
          </div>

          <p v-if="!resultsCampaign.conversion_stage_ids?.length && !resultsCampaign.conversion_label_ids?.length" class="text-xs text-amber-600 bg-amber-500/10 border border-amber-500/30 rounded-lg p-3">
            Esta campanha não tem conversões definidas — selecione colunas ou etiquetas
            de conversão ao criar as próximas campanhas.
          </p>

          <!-- Por procedimento -->
          <div v-if="results.by_procedure.length">
            <p class="text-xs font-medium text-n-slate-11 mb-2">Procedimentos fechados</p>
            <div class="border border-n-weak rounded-xl overflow-hidden">
              <div
                v-for="p in results.by_procedure"
                :key="p.procedure"
                class="flex items-center justify-between px-4 py-2.5 border-b border-n-weak last:border-b-0 bg-n-solid-2"
              >
                <span class="text-sm text-n-slate-12">{{ p.procedure }}</span>
                <span class="text-xs text-n-slate-10">{{ p.count }}x</span>
                <span class="text-sm font-semibold text-green-600">{{ formatCurrency(p.total_value) }}</span>
              </div>
            </div>
          </div>

          <!-- Contatos convertidos via CRM -->
          <div v-if="results.converted_contacts.length">
            <p class="text-xs font-medium text-n-slate-11 mb-2">Quem converteu no CRM</p>
            <div class="space-y-1.5 max-h-64 overflow-y-auto">
              <div
                v-for="c in results.converted_contacts"
                :key="c.contact_id"
                class="flex items-center justify-between bg-n-alpha-1 rounded-lg px-3 py-2"
              >
                <div class="min-w-0">
                  <p class="text-sm text-n-slate-12 truncate">{{ c.name }}</p>
                  <p class="text-xs text-n-slate-10">{{ c.procedure || 'Procedimento não informado' }}</p>
                </div>
                <div class="text-right flex-shrink-0 ml-3">
                  <p class="text-sm font-semibold text-green-600">{{ c.value ? formatCurrency(c.value) : '—' }}</p>
                  <span
                    class="text-[10px] px-1.5 py-0.5 rounded-full"
                    :style="{ backgroundColor: (c.stage_color || '#6B7280') + '22', color: c.stage_color || '#6B7280' }"
                  >{{ c.stage_name }}</span>
                </div>
              </div>
            </div>
          </div>

          <p class="text-xs text-n-slate-9">
            Conversões cruzam quem recebeu a campanha com os cards do CRM e as etiquetas
            de conversão. Em breve: dados em tempo real do Oftalmofácil.
          </p>
        </div>
      </div>
    </div>
  </div>
</template>
