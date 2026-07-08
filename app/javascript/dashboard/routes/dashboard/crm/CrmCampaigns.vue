<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { relativeTime } from './helpers';

const store = useStore();
const router = useRouter();

const campaigns = ref([]);
const isLoading = ref(false);
const showComposer = ref(false);
const deleteConfirmId = ref(null);

// ── Formulário ────────────────────────────────────────────────────────
const form = ref({
  name: '',
  inbox_id: null,
  apply_label: '',
});
const templates = ref([]);
const selectedTemplateName = ref('');
const varValues = ref({});
const includeLabelIds = ref([]);
const excludeLabelIds = ref([]);
const includeStageIds = ref([]);
const excludeStageIds = ref([]);
const conversionStageIds = ref([]);

// ── Painel de resultados ──────────────────────────────────────────────
const resultsCampaign = ref(null);
const results = ref(null);
const isResultsLoading = ref(false);
const audiencePreview = ref(null);
const isPreviewLoading = ref(false);
const isSubmitting = ref(false);
const isLoadingTemplates = ref(false);

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

const selectedTemplate = computed(() =>
  templates.value.find(t => t.name === selectedTemplateName.value) ?? null
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

const hasAudience = computed(
  () => includeLabelIds.value.length > 0 || includeStageIds.value.length > 0
);

const canSubmit = computed(
  () =>
    form.value.name.trim() &&
    form.value.inbox_id &&
    selectedTemplate.value &&
    hasAudience.value &&
    variableTokens.value.every(t => varValues.value[t]?.trim())
);

// ── Carga ─────────────────────────────────────────────────────────────
let refreshTimer = null;

const loadCampaigns = async () => {
  try {
    campaigns.value = await store.dispatch('crm/fetchCampaigns');
  } catch {
    // silencioso no polling
  }
};

onMounted(async () => {
  isLoading.value = true;
  await Promise.all([
    loadCampaigns(),
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

// ── Ações do composer ─────────────────────────────────────────────────
const openComposer = () => {
  form.value = { name: '', inbox_id: whatsappInboxes.value[0]?.id ?? null, apply_label: '' };
  templates.value = [];
  selectedTemplateName.value = '';
  varValues.value = {};
  includeLabelIds.value = [];
  excludeLabelIds.value = [];
  includeStageIds.value = [];
  excludeStageIds.value = [];
  conversionStageIds.value = [];
  audiencePreview.value = null;
  showComposer.value = true;
  if (form.value.inbox_id) loadTemplates();
};

const loadTemplates = async () => {
  if (!form.value.inbox_id) return;
  isLoadingTemplates.value = true;
  selectedTemplateName.value = '';
  varValues.value = {};
  try {
    templates.value = await store.dispatch('crm/fetchWhatsappTemplates', form.value.inbox_id);
  } catch {
    templates.value = [];
    useAlert('Erro ao carregar templates do WhatsApp');
  } finally {
    isLoadingTemplates.value = false;
  }
};

const toggle = (list, id) => {
  const idx = list.indexOf(id);
  if (idx === -1) list.push(id);
  else list.splice(idx, 1);
  audiencePreview.value = null;
};

const audiencePayload = () => ({
  include_label_ids: includeLabelIds.value,
  include_stage_ids: includeStageIds.value,
  exclude_label_ids: excludeLabelIds.value,
  exclude_stage_ids: excludeStageIds.value,
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

const buildPayload = () => ({
  name: form.value.name,
  inbox_id: form.value.inbox_id,
  apply_label: form.value.apply_label,
  message_preview: bodyText.value,
  conversion_stage_ids: conversionStageIds.value,
  audience: audiencePayload(),
  template_params: {
    name: selectedTemplate.value.name,
    namespace: selectedTemplate.value.namespace ?? '',
    language: selectedTemplate.value.language,
    category: selectedTemplate.value.category,
    processed_params: { body: { ...varValues.value } },
  },
});

const submit = async (sendNow) => {
  if (!canSubmit.value) return;
  isSubmitting.value = true;
  try {
    const created = await store.dispatch('crm/createCampaign', buildPayload());
    if (sendNow) await store.dispatch('crm/sendCampaign', created.id);
    useAlert(sendNow ? 'Campanha enviada! Acompanhe o progresso na lista.' : 'Rascunho salvo.');
    showComposer.value = false;
    await loadCampaigns();
  } catch {
    useAlert('Erro ao criar a campanha');
  } finally {
    isSubmitting.value = false;
  }
};

// ── Painel de resultados ──────────────────────────────────────────────
const openResults = async (c) => {
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

const formatCurrency = (v) =>
  'R$ ' + Number(v || 0).toLocaleString('pt-BR', { maximumFractionDigits: 0 });

// ── Ações da lista ────────────────────────────────────────────────────
const sendDraft = async (c) => {
  try {
    await store.dispatch('crm/sendCampaign', c.id);
    useAlert('Campanha enviada!');
    await loadCampaigns();
  } catch {
    useAlert('Erro ao enviar a campanha');
  }
};

const removeCampaign = async (c) => {
  try {
    await store.dispatch('crm/deleteCampaign', c.id);
    deleteConfirmId.value = null;
    await loadCampaigns();
  } catch {
    useAlert('Erro ao excluir a campanha');
  }
};

const STATUS_META = {
  draft:      { label: 'Rascunho',    cls: 'bg-n-alpha-2 text-n-slate-11' },
  processing: { label: 'Enviando…',   cls: 'bg-blue-500/15 text-blue-600' },
  completed:  { label: 'Concluída',   cls: 'bg-green-500/15 text-green-600' },
  failed:     { label: 'Falhou',      cls: 'bg-red-500/15 text-red-600' },
};

const statsLine = (c) => {
  const s = c.stats ?? {};
  if (c.status === 'draft') return '';
  const parts = [`${s.sent ?? 0}/${s.total ?? 0} enviadas`];
  if (s.skipped) parts.push(`${s.skipped} puladas`);
  if (s.failed) parts.push(`${s.failed} falhas`);
  return parts.join(' · ');
};
</script>

<template>
  <div class="flex flex-col h-full w-full bg-n-solid-1 overflow-hidden">

    <!-- Header -->
    <div class="flex items-center gap-3 px-6 py-4 border-b border-n-weak flex-shrink-0">
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
        Mensagens em Massa
      </h1>
      <div class="flex-1" />
      <button
        class="flex items-center gap-1.5 text-sm px-4 py-2 rounded-lg bg-n-brand text-white hover:opacity-90 transition-opacity"
        @click="openComposer"
      >
        <span class="i-lucide-plus" />
        Nova campanha
      </button>
    </div>

    <!-- Lista -->
    <div class="flex-1 overflow-y-auto p-6">
      <div v-if="isLoading" class="flex justify-center py-16"><Spinner /></div>

      <div v-else-if="!campaigns.length" class="flex flex-col items-center justify-center py-20 text-n-slate-9">
        <span class="i-lucide-megaphone text-5xl mb-4" />
        <p class="text-sm">Nenhuma campanha ainda.</p>
        <p class="text-xs mt-1">Crie a primeira para disparar mensagens modelo do WhatsApp em massa.</p>
      </div>

      <div v-else class="space-y-3 max-w-3xl">
        <div
          v-for="c in campaigns"
          :key="c.id"
          class="bg-n-solid-2 border border-n-weak rounded-xl p-4 flex items-center gap-4"
        >
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 flex-wrap">
              <span class="text-sm font-semibold text-n-slate-12">{{ c.name }}</span>
              <span
                class="text-xs px-2 py-0.5 rounded-full"
                :class="STATUS_META[c.status]?.cls"
              >{{ STATUS_META[c.status]?.label ?? c.status }}</span>
            </div>
            <p class="text-xs text-n-slate-10 mt-1">
              {{ c.inbox_name }} · template <span class="font-mono">{{ c.template_params?.name }}</span>
              <template v-if="c.apply_label"> · etiqueta <span class="font-mono">{{ c.apply_label }}</span></template>
            </p>
            <p v-if="statsLine(c)" class="text-xs text-n-slate-11 mt-1">{{ statsLine(c) }}</p>
            <p v-if="c.stats?.error" class="text-xs text-red-500 mt-1 truncate">{{ c.stats.error }}</p>
            <p class="text-xs text-n-slate-9 mt-1">criada {{ relativeTime(c.created_at) }}</p>
          </div>

          <div class="flex items-center gap-2 flex-shrink-0">
            <button
              v-if="c.status === 'draft'"
              class="text-xs px-3 py-1.5 rounded-lg bg-n-brand text-white hover:opacity-90"
              @click="sendDraft(c)"
            >Enviar agora</button>

            <button
              v-if="c.status === 'completed' || c.status === 'processing'"
              class="text-xs px-3 py-1.5 rounded-lg border border-green-500/60 text-green-600 hover:bg-green-500/10 flex items-center gap-1"
              @click="openResults(c)"
            >
              <span class="i-lucide-trending-up" />
              Resultados
            </button>

            <template v-if="c.status !== 'processing'">
              <button
                v-if="deleteConfirmId !== c.id"
                class="text-n-slate-10 hover:text-red-500 i-lucide-trash-2"
                @click="deleteConfirmId = c.id"
              />
              <button
                v-else
                class="text-xs px-2 py-1 rounded bg-red-500 text-white"
                @click="removeCampaign(c)"
              >Confirmar</button>
            </template>
            <Spinner v-else :size="16" />
          </div>
        </div>
      </div>
    </div>

    <!-- ── Composer ──────────────────────────────────────────────── -->
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
          <!-- Nome -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Nome da campanha</label>
            <input
              v-model="form.name"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              placeholder="Ex: Reativação consultas julho"
            />
          </div>

          <!-- Inbox -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Caixa de entrada (WhatsApp oficial)</label>
            <select
              v-model="form.inbox_id"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              @change="loadTemplates"
            >
              <option v-for="i in whatsappInboxes" :key="i.id" :value="i.id">{{ i.name }}</option>
            </select>
            <p v-if="!whatsappInboxes.length" class="text-xs text-red-500 mt-1">
              Nenhuma caixa WhatsApp API oficial encontrada.
            </p>
          </div>

          <!-- Template -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1">
              Mensagem modelo (aprovada pelo Meta)
              <Spinner v-if="isLoadingTemplates" :size="12" class="ml-1" />
            </label>
            <select
              v-model="selectedTemplateName"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
            >
              <option value="" disabled>Selecione um template…</option>
              <option v-for="t in templates" :key="`${t.name}-${t.language}`" :value="t.name">
                {{ t.name }} ({{ t.language }})
              </option>
            </select>

            <!-- Preview + variáveis -->
            <div v-if="selectedTemplate" class="mt-3 space-y-3">
              <div class="bg-n-alpha-1 border border-n-weak rounded-lg p-3">
                <p class="text-xs text-n-slate-10 mb-1">Prévia da mensagem</p>
                <p class="text-sm text-n-slate-12 whitespace-pre-wrap">{{ renderedPreview }}</p>
              </div>
              <div v-for="token in variableTokens" :key="token">
                <label class="text-xs font-medium text-n-slate-11 block mb-1">
                  Variável {{ '{{' + token + '}}' }}
                </label>
                <input
                  v-model="varValues[token]"
                  class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
                  :placeholder="'Valor fixo ou {{contact.name}} para personalizar'"
                />
              </div>
              <p v-if="variableTokens.length" class="text-xs text-n-slate-9">
                Dica: use <span class="font-mono">{{ '{{contact.name}}' }}</span> para inserir o nome do lead automaticamente.
              </p>
            </div>
          </div>

          <!-- Público: incluir -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-2">
              Público — quem VAI receber <span class="text-n-slate-9">(etiquetas e/ou colunas do CRM)</span>
            </label>
            <div class="flex flex-wrap gap-1.5 mb-2">
              <button
                v-for="l in labels"
                :key="`il-${l.id}`"
                class="text-xs px-2.5 py-1 rounded-full border transition-colors flex items-center gap-1"
                :class="includeLabelIds.includes(l.id)
                  ? 'bg-n-brand/10 border-n-brand text-n-brand'
                  : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
                @click="toggle(includeLabelIds, l.id)"
              >
                <span class="w-2 h-2 rounded-full" :style="{ backgroundColor: l.color }" />
                {{ l.title }}
              </button>
            </div>
            <div class="flex flex-wrap gap-1.5">
              <button
                v-for="s in allStages"
                :key="`is-${s.id}`"
                class="text-xs px-2.5 py-1 rounded-full border transition-colors flex items-center gap-1"
                :class="includeStageIds.includes(s.id)
                  ? 'bg-n-brand/10 border-n-brand text-n-brand'
                  : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
                @click="toggle(includeStageIds, s.id)"
              >
                <span class="w-2 h-2 rounded-full" :style="{ backgroundColor: s.color }" />
                {{ s.pipeline_name }} › {{ s.name }}
              </button>
            </div>
          </div>

          <!-- Público: excluir -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-2">
              Exclusões — quem NÃO deve receber <span class="text-n-slate-9">(opcional)</span>
            </label>
            <div class="flex flex-wrap gap-1.5 mb-2">
              <button
                v-for="l in labels"
                :key="`el-${l.id}`"
                class="text-xs px-2.5 py-1 rounded-full border transition-colors flex items-center gap-1"
                :class="excludeLabelIds.includes(l.id)
                  ? 'bg-red-500/10 border-red-500 text-red-600'
                  : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
                @click="toggle(excludeLabelIds, l.id)"
              >
                <span class="w-2 h-2 rounded-full" :style="{ backgroundColor: l.color }" />
                {{ l.title }}
              </button>
            </div>
            <div class="flex flex-wrap gap-1.5">
              <button
                v-for="s in allStages"
                :key="`es-${s.id}`"
                class="text-xs px-2.5 py-1 rounded-full border transition-colors flex items-center gap-1"
                :class="excludeStageIds.includes(s.id)
                  ? 'bg-red-500/10 border-red-500 text-red-600'
                  : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
                @click="toggle(excludeStageIds, s.id)"
              >
                <span class="w-2 h-2 rounded-full" :style="{ backgroundColor: s.color }" />
                {{ s.pipeline_name }} › {{ s.name }}
              </button>
            </div>

            <!-- Preview do público -->
            <div class="mt-3 flex items-center gap-3">
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

          <!-- Colunas de conversão -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-2">
              Colunas que contam como CONVERSÃO
              <span class="text-n-slate-9">(para o painel de resultados — ex: Cirurgia Realizada)</span>
            </label>
            <div class="flex flex-wrap gap-1.5">
              <button
                v-for="s in allStages"
                :key="`cs-${s.id}`"
                class="text-xs px-2.5 py-1 rounded-full border transition-colors flex items-center gap-1"
                :class="conversionStageIds.includes(s.id)
                  ? 'bg-green-500/10 border-green-500 text-green-600'
                  : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
                @click="toggle(conversionStageIds, s.id)"
              >
                <span class="w-2 h-2 rounded-full" :style="{ backgroundColor: s.color }" />
                {{ s.pipeline_name }} › {{ s.name }}
              </button>
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
            :disabled="!canSubmit || isSubmitting"
            @click="submit(false)"
          >Salvar rascunho</button>
          <button
            class="text-sm px-4 py-2 rounded-lg bg-n-brand text-white hover:opacity-90 disabled:opacity-50 flex items-center gap-1.5"
            :disabled="!canSubmit || isSubmitting"
            @click="submit(true)"
          >
            <span class="i-lucide-send" />
            {{ isSubmitting ? 'Enviando…' : 'Criar e enviar' }}
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
              <p class="text-xs text-n-slate-10">Conversões</p>
              <p class="text-xl font-bold text-green-600">{{ results.conversions.count }}</p>
            </div>
            <div class="bg-n-alpha-1 border border-n-weak rounded-xl p-3">
              <p class="text-xs text-n-slate-10">Taxa</p>
              <p class="text-xl font-bold text-n-slate-12">{{ results.conversions.rate }}%</p>
            </div>
            <div class="bg-n-alpha-1 border border-n-weak rounded-xl p-3">
              <p class="text-xs text-n-slate-10">Valor total</p>
              <p class="text-xl font-bold text-green-600">{{ formatCurrency(results.conversions.total_value) }}</p>
            </div>
          </div>

          <p v-if="!resultsCampaign.conversion_stage_ids?.length" class="text-xs text-amber-600 bg-amber-500/10 border border-amber-500/30 rounded-lg p-3">
            Esta campanha não tem colunas de conversão definidas — as conversões aparecem zeradas.
            Nas próximas campanhas, selecione as colunas (ex: Cirurgia Realizada) ao criar.
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

          <!-- Contatos convertidos -->
          <div v-if="results.converted_contacts.length">
            <p class="text-xs font-medium text-n-slate-11 mb-2">Quem converteu</p>
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
            As conversões são calculadas cruzando quem recebeu a campanha com os cards
            que chegaram nas colunas de conversão do CRM. Em breve: dados em tempo real do Oftalmofácil.
          </p>
        </div>
      </div>
    </div>
  </div>
</template>
