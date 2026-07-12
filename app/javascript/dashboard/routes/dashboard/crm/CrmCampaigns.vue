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

const activeTab = ref('campaigns'); // campaigns | automations | panel
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

// KPIs agregados do painel
const panelStats = computed(() => {
  const sentByCampaigns = campaigns.value.reduce((sum, c) => sum + (c.stats?.sent ?? 0), 0);
  const sentByAutomations = automations.value.reduce((sum, a) => sum + (a.stats?.sent ?? 0), 0);
  return {
    totalSent: sentByCampaigns + sentByAutomations,
    completedCampaigns: campaigns.value.filter(c => c.status === 'completed').length,
    scheduledCampaigns: campaigns.value.filter(c => c.status === 'scheduled').length,
    activeAutomations: automations.value.filter(a => a.active).length,
  };
});

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

// ── Tratamento de dados: etiqueta retroativa por conteúdo ─────────────
const retro = ref({
  term: '',
  labelChoice: '',
  newLabel: '',
  target_stage_id: '',
  period_from: '',
  period_to: '',
  apply_to_contact: true,
});

const retroLabel = computed(() =>
  retro.value.labelChoice === '__nova__'
    ? retro.value.newLabel.trim()
    : retro.value.labelChoice
);
const retroPreview = ref(null);
const isRetroLoading = ref(false);
const isRetroApplying = ref(false);
const showRetroPanel = ref(false);

const retroPayload = () => ({
  term: retro.value.term.trim(),
  label: retroLabel.value,
  target_stage_id: retro.value.target_stage_id || undefined,
  period_from: retro.value.period_from,
  period_to: retro.value.period_to,
  apply_to_contact: retro.value.apply_to_contact,
});

// precisa de pelo menos uma ação: etiqueta ou coluna
const retroHasAction = computed(
  () => !!retroLabel.value || !!retro.value.target_stage_id
);

const previewRetro = async () => {
  if (!retro.value.term.trim()) return;
  isRetroLoading.value = true;
  retroPreview.value = null;
  try {
    retroPreview.value = await store.dispatch('crm/previewRetroLabel', retroPayload());
  } catch {
    useAlert('Erro ao calcular as conversas');
  } finally {
    isRetroLoading.value = false;
  }
};

const applyRetro = async () => {
  if (!retro.value.term.trim() || !retroHasAction.value) return;
  isRetroApplying.value = true;
  try {
    await store.dispatch('crm/applyRetroLabel', retroPayload());
    useAlert(
      'Processando em segundo plano — em alguns minutos as conversas estarão organizadas.'
    );
    retroPreview.value = null;
    retro.value.term = '';
    retro.value.labelChoice = '';
    retro.value.newLabel = '';
    retro.value.target_stage_id = '';
  } catch {
    useAlert('Erro ao aplicar');
  } finally {
    isRetroApplying.value = false;
  }
};

// ── Preencher valores pelo orçamento ──────────────────────────────────
const showValuePanel = ref(false);
const valueOnlyEmpty = ref(true);
const isValueRunning = ref(false);

const runBulkValues = async () => {
  if (isValueRunning.value || !pipelines.value.length) return;
  isValueRunning.value = true;
  try {
    await Promise.all(
      pipelines.value.map(p =>
        store.dispatch('crm/detectValuesBulk', { pipelineId: p.id, onlyEmpty: valueOnlyEmpty.value })
      )
    );
    useAlert('Processando em segundo plano — os valores aparecem em instantes.');
    showValuePanel.value = false;
  } catch {
    useAlert('Erro ao iniciar o preenchimento de valores');
  } finally {
    isValueRunning.value = false;
  }
};

// ── Substituir etiquetas ──────────────────────────────────────────────
const showReplacePanel = ref(false);
const replaceFrom = ref('');
const replaceTo = ref('');
const replacePreview = ref(null);
const isReplaceLoading = ref(false);
const isReplaceApplying = ref(false);
const showReplaceConfirm = ref(false);

const replaceLabelOptions = computed(() => (labels.value || []).map(l => l.title));

const previewReplace = async () => {
  if (!replaceFrom.value || !replaceTo.value || replaceFrom.value === replaceTo.value) return;
  isReplaceLoading.value = true;
  replacePreview.value = null;
  showReplaceConfirm.value = false;
  try {
    replacePreview.value = await store.dispatch('crm/previewLabelReplace', {
      from: replaceFrom.value,
      to: replaceTo.value,
    });
  } catch {
    useAlert('Erro ao calcular a substituição');
  } finally {
    isReplaceLoading.value = false;
  }
};

const applyReplace = async () => {
  isReplaceApplying.value = true;
  try {
    await store.dispatch('crm/applyLabelReplace', { from: replaceFrom.value, to: replaceTo.value });
    useAlert('Substituição em andamento — as etiquetas serão trocadas em segundo plano.');
    replacePreview.value = null;
    showReplaceConfirm.value = false;
    replaceFrom.value = '';
    replaceTo.value = '';
  } catch {
    useAlert('Erro ao iniciar a substituição');
  } finally {
    isReplaceApplying.value = false;
  }
};

// ── Remover etiqueta em massa ─────────────────────────────────────────
const showRemovePanel = ref(false);
const removeLabel = ref('');
const removeStageId = ref('');
const removePreview = ref(null);
const isRemoveLoading = ref(false);
const isRemoveApplying = ref(false);
const showRemoveConfirm = ref(false);

const previewRemove = async () => {
  if (!removeLabel.value) return;
  isRemoveLoading.value = true;
  removePreview.value = null;
  showRemoveConfirm.value = false;
  try {
    removePreview.value = await store.dispatch('crm/previewLabelRemove', {
      label: removeLabel.value,
      stage_id: removeStageId.value || undefined,
    });
  } catch {
    useAlert('Erro ao calcular');
  } finally {
    isRemoveLoading.value = false;
  }
};

const applyRemove = async () => {
  isRemoveApplying.value = true;
  try {
    await store.dispatch('crm/applyLabelRemove', {
      label: removeLabel.value,
      stage_id: removeStageId.value || undefined,
    });
    useAlert('Remoção em andamento — as etiquetas serão removidas em segundo plano.');
    removePreview.value = null;
    showRemoveConfirm.value = false;
    removeLabel.value = '';
    removeStageId.value = '';
  } catch {
    useAlert('Erro ao iniciar a remoção');
  } finally {
    isRemoveApplying.value = false;
  }
};

// ── Unificação de contatos duplicados ─────────────────────────────────
const showUnifyPanel = ref(false);
const unifyPreview = ref(null);
const isUnifyLoading = ref(false);
const isUnifyApplying = ref(false);
const showUnifyConfirm = ref(false);

const previewUnify = async () => {
  isUnifyLoading.value = true;
  unifyPreview.value = null;
  showUnifyConfirm.value = false;
  try {
    unifyPreview.value = await store.dispatch('crm/previewContactUnification');
  } catch {
    useAlert('Erro ao calcular os duplicados');
  } finally {
    isUnifyLoading.value = false;
  }
};

const applyUnify = async () => {
  isUnifyApplying.value = true;
  try {
    await store.dispatch('crm/applyContactUnification');
    useAlert('Unificação em andamento — os contatos serão mesclados em segundo plano.');
    unifyPreview.value = null;
    showUnifyConfirm.value = false;
  } catch {
    useAlert('Erro ao iniciar a unificação');
  } finally {
    isUnifyApplying.value = false;
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
  scheduled:  { label: 'Agendada',   cls: 'bg-n-gold-soft text-n-gold' },
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
        <button
          class="px-3 py-1.5 text-xs font-medium rounded-lg transition-colors"
          :class="activeTab === 'panel' ? 'bg-n-brand text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          @click="activeTab = 'panel'"
        >Painel</button>
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
        v-else-if="activeTab === 'automations'"
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

            <p v-if="c.status === 'scheduled' && c.scheduled_at" class="text-xs text-n-gold flex items-center gap-1">
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
      <template v-else-if="activeTab === 'automations'">
        <!-- Tratamento de dados: etiqueta retroativa -->
        <div class="max-w-3xl mb-5 bg-n-solid-2 border border-n-weak rounded-xl overflow-hidden">
          <button
            class="w-full flex items-center gap-3 p-4 text-left hover:bg-n-alpha-1 transition-colors"
            @click="showRetroPanel = !showRetroPanel"
          >
            <span class="i-lucide-database text-xl text-n-gold flex-shrink-0" />
            <div class="flex-1 min-w-0">
              <p class="text-sm font-semibold text-n-slate-12">Tratamento de dados — etiquetar conversas antigas</p>
              <p class="text-xs text-n-slate-10">
                Aplica uma etiqueta em todas as conversas que contêm um texto. Ex: "3900" → orçamento-refrativa
              </p>
            </div>
            <span
              class="text-n-slate-10 flex-shrink-0"
              :class="showRetroPanel ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
            />
          </button>

          <div v-if="showRetroPanel" class="px-4 pb-4 space-y-3 border-t border-n-weak pt-4">
            <div class="flex flex-wrap gap-3">
              <div class="flex-1 min-w-48">
                <label class="text-xs font-medium text-n-slate-11 block mb-1">A conversa contém o texto</label>
                <input
                  v-model="retro.term"
                  class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
                  placeholder='Ex: 3900  ou  orçamento, orcamento, valor'
                  @input="retroPreview = null"
                />
                <p class="text-[11px] text-n-slate-9 mt-1">
                  Ignora acentos e maiúsculas. Separe alternativas por vírgula; use
                  "aspas" para uma frase exata ser tratada como uma peça só.
                </p>
              </div>
              <div class="flex-1 min-w-48">
                <label class="text-xs font-medium text-n-slate-11 block mb-1">
                  Recebe a etiqueta <span class="text-n-slate-9">(opcional)</span>
                </label>
                <select
                  v-model="retro.labelChoice"
                  class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
                >
                  <option value="">Sem etiqueta</option>
                  <option v-for="l in labels" :key="l.id" :value="l.title">{{ l.title }}</option>
                  <option value="__nova__">➕ Criar nova etiqueta…</option>
                </select>
                <input
                  v-if="retro.labelChoice === '__nova__'"
                  v-model="retro.newLabel"
                  class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 mt-2"
                  placeholder="nome-da-nova-etiqueta"
                />
              </div>
              <div class="flex-1 min-w-48">
                <label class="text-xs font-medium text-n-slate-11 block mb-1">
                  E move para a coluna do CRM <span class="text-n-slate-9">(opcional)</span>
                </label>
                <select
                  v-model="retro.target_stage_id"
                  class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
                >
                  <option value="">Não mover</option>
                  <option v-for="s in allStages" :key="s.id" :value="s.id">
                    {{ s.pipeline_name }} › {{ s.name }}
                  </option>
                </select>
              </div>
            </div>
            <p class="text-xs text-n-slate-9 -mt-1">
              Escolha uma etiqueta, uma coluna, ou as duas. Ex: conversa contém "orçamento" →
              coluna "Envio de Orçamento".
            </p>

            <div class="flex flex-wrap items-center gap-3">
              <label class="text-xs text-n-slate-10">Período (opcional):</label>
              <input
                v-model="retro.period_from"
                type="date"
                class="border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12"
                @change="retroPreview = null"
              />
              <span class="text-xs text-n-slate-10">até</span>
              <input
                v-model="retro.period_to"
                type="date"
                class="border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12"
                @change="retroPreview = null"
              />
              <label class="flex items-center gap-1.5 text-xs text-n-slate-11 ml-2 cursor-pointer">
                <input v-model="retro.apply_to_contact" type="checkbox" class="rounded" />
                Etiquetar também o contato (para usar em campanhas)
              </label>
            </div>

            <div class="flex flex-wrap items-center gap-3 pt-1">
              <button
                class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center gap-1 disabled:opacity-50"
                :disabled="!retro.term.trim() || isRetroLoading"
                @click="previewRetro"
              >
                <span class="i-lucide-search" />
                {{ isRetroLoading ? 'Buscando…' : 'Calcular conversas' }}
              </button>

              <span v-if="retroPreview" class="text-sm text-n-slate-12">
                <b>{{ retroPreview.conversations }}</b> conversa(s) ·
                <b>{{ retroPreview.contacts }}</b> contato(s)
                <span v-if="retroPreview.sample?.length" class="text-xs text-n-slate-9">
                  (ex: {{ retroPreview.sample.map(s => s.contact_name).filter(Boolean).slice(0, 3).join(', ') }})
                </span>
              </span>

              <div class="flex-1" />
              <button
                class="text-xs px-4 py-2 rounded-lg bg-n-brand text-white hover:opacity-90 flex items-center gap-1.5 disabled:opacity-50"
                :disabled="!retro.term.trim() || !retroHasAction || !retroPreview || isRetroApplying"
                @click="applyRetro"
              >
                <span class="i-lucide-wand-2" />
                {{ isRetroApplying ? 'Aplicando…' : 'Aplicar' }}
              </button>
            </div>
            <p v-if="retroPreview && !retroHasAction" class="text-xs text-amber-600">
              Escolha uma etiqueta e/ou uma coluna para aplicar.
            </p>
          </div>
        </div>

        <!-- Tratamento de dados: substituir etiquetas -->
        <div class="max-w-3xl mb-5 bg-n-solid-2 border border-n-weak rounded-xl overflow-hidden">
          <button
            class="w-full flex items-center gap-3 p-4 text-left hover:bg-n-alpha-1 transition-colors"
            @click="showReplacePanel = !showReplacePanel"
          >
            <span class="i-lucide-replace text-xl text-n-brand flex-shrink-0" />
            <div class="flex-1 min-w-0">
              <p class="text-sm font-semibold text-n-slate-12">Tratamento de dados — substituir etiquetas</p>
              <p class="text-xs text-n-slate-10">
                Troca uma etiqueta por outra em todo mundo. Ex.: "refrativa" → "orçamento-refrativa".
              </p>
            </div>
            <span
              class="text-n-slate-10 flex-shrink-0"
              :class="showReplacePanel ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
            />
          </button>

          <div v-if="showReplacePanel" class="px-4 pb-4 space-y-3 border-t border-n-weak pt-4">
            <div class="flex flex-wrap items-end gap-3">
              <div class="flex-1 min-w-40">
                <label class="text-xs font-medium text-n-slate-11 block mb-1">Etiqueta atual (será removida)</label>
                <input
                  v-model="replaceFrom"
                  list="replace-from-list"
                  class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
                  placeholder="ex: refrativa"
                  @input="replacePreview = null"
                />
                <datalist id="replace-from-list">
                  <option v-for="l in replaceLabelOptions" :key="l" :value="l" />
                </datalist>
              </div>
              <span class="i-lucide-arrow-right text-n-slate-9 pb-2.5" />
              <div class="flex-1 min-w-40">
                <label class="text-xs font-medium text-n-slate-11 block mb-1">Nova etiqueta (será adicionada)</label>
                <input
                  v-model="replaceTo"
                  list="replace-to-list"
                  class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
                  placeholder="ex: orçamento-refrativa"
                  @input="replacePreview = null"
                />
                <datalist id="replace-to-list">
                  <option v-for="l in replaceLabelOptions" :key="l" :value="l" />
                </datalist>
              </div>
            </div>

            <div class="flex flex-wrap items-center gap-3">
              <button
                class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center gap-1 disabled:opacity-50"
                :disabled="!replaceFrom || !replaceTo || replaceFrom === replaceTo || isReplaceLoading"
                @click="previewReplace"
              >
                <span class="i-lucide-search" />
                {{ isReplaceLoading ? 'Calculando…' : 'Calcular' }}
              </button>
              <span v-if="replacePreview" class="text-sm text-n-slate-12">
                <b>{{ replacePreview.contacts }}</b> contato(s) ·
                <b>{{ replacePreview.conversations }}</b> conversa(s)
              </span>
            </div>

            <div v-if="replacePreview && (replacePreview.contacts > 0 || replacePreview.conversations > 0)" class="flex items-center gap-3">
              <template v-if="!showReplaceConfirm">
                <button
                  class="text-xs px-4 py-2 rounded-lg bg-n-brand text-white hover:opacity-90 flex items-center gap-1.5"
                  @click="showReplaceConfirm = true"
                >
                  <span class="i-lucide-replace" />
                  Substituir etiqueta
                </button>
              </template>
              <template v-else>
                <span class="text-xs text-amber-600 font-medium">Confirma trocar "{{ replaceFrom }}" por "{{ replaceTo }}"?</span>
                <button
                  class="text-xs px-3 py-1.5 rounded-lg bg-amber-600 text-white disabled:opacity-50"
                  :disabled="isReplaceApplying"
                  @click="applyReplace"
                >{{ isReplaceApplying ? 'Iniciando…' : 'Sim, substituir' }}</button>
                <button class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11" @click="showReplaceConfirm = false">Cancelar</button>
              </template>
            </div>
            <p v-if="replacePreview && replacePreview.contacts === 0 && replacePreview.conversations === 0" class="text-xs text-n-slate-9">
              Ninguém com a etiqueta "{{ replaceFrom }}".
            </p>
          </div>
        </div>

        <!-- Tratamento de dados: remover etiqueta em massa -->
        <div class="max-w-3xl mb-5 bg-n-solid-2 border border-n-weak rounded-xl overflow-hidden">
          <button
            class="w-full flex items-center gap-3 p-4 text-left hover:bg-n-alpha-1 transition-colors"
            @click="showRemovePanel = !showRemovePanel"
          >
            <span class="i-lucide-tag-off text-xl text-red-500 flex-shrink-0" />
            <div class="flex-1 min-w-0">
              <p class="text-sm font-semibold text-n-slate-12">Tratamento de dados — remover etiqueta em massa</p>
              <p class="text-xs text-n-slate-10">
                Remove uma etiqueta de todo mundo que a tem — opcionalmente só de quem está numa coluna do CRM.
              </p>
            </div>
            <span
              class="text-n-slate-10 flex-shrink-0"
              :class="showRemovePanel ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
            />
          </button>

          <div v-if="showRemovePanel" class="px-4 pb-4 space-y-3 border-t border-n-weak pt-4">
            <div class="flex flex-wrap items-end gap-3">
              <div class="flex-1 min-w-40">
                <label class="text-xs font-medium text-n-slate-11 block mb-1">Etiqueta a remover</label>
                <select
                  v-model="removeLabel"
                  class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
                  @change="removePreview = null"
                >
                  <option value="">Escolha a etiqueta…</option>
                  <option v-for="l in labels" :key="l.id" :value="l.title">{{ l.title }}</option>
                </select>
              </div>
              <div class="flex-1 min-w-40">
                <label class="text-xs font-medium text-n-slate-11 block mb-1">
                  Só de quem está na coluna <span class="text-n-slate-9">(opcional)</span>
                </label>
                <select
                  v-model="removeStageId"
                  class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
                  @change="removePreview = null"
                >
                  <option value="">Todas as pessoas</option>
                  <option v-for="s in allStages" :key="s.id" :value="s.id">
                    {{ s.pipeline_name }} › {{ s.name }}
                  </option>
                </select>
              </div>
            </div>

            <div class="flex flex-wrap items-center gap-3">
              <button
                class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center gap-1 disabled:opacity-50"
                :disabled="!removeLabel || isRemoveLoading"
                @click="previewRemove"
              >
                <span class="i-lucide-search" />
                {{ isRemoveLoading ? 'Calculando…' : 'Calcular' }}
              </button>
              <span v-if="removePreview" class="text-sm text-n-slate-12">
                <b>{{ removePreview.contacts }}</b> contato(s) perderão a etiqueta
                <span v-if="removePreview.sample?.length" class="text-xs text-n-slate-9">
                  (ex: {{ removePreview.sample.map(s => s.name).filter(Boolean).slice(0, 3).join(', ') }})
                </span>
              </span>
            </div>

            <div v-if="removePreview && removePreview.contacts > 0" class="flex items-center gap-3">
              <template v-if="!showRemoveConfirm">
                <button
                  class="text-xs px-4 py-2 rounded-lg bg-red-500 text-white hover:opacity-90 flex items-center gap-1.5"
                  @click="showRemoveConfirm = true"
                >
                  <span class="i-lucide-tag-off" />
                  Remover etiqueta
                </button>
              </template>
              <template v-else>
                <span class="text-xs text-amber-600 font-medium">Confirma remover "{{ removeLabel }}" de {{ removePreview.contacts }} contato(s)?</span>
                <button
                  class="text-xs px-3 py-1.5 rounded-lg bg-red-600 text-white disabled:opacity-50"
                  :disabled="isRemoveApplying"
                  @click="applyRemove"
                >{{ isRemoveApplying ? 'Iniciando…' : 'Sim, remover' }}</button>
                <button class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11" @click="showRemoveConfirm = false">Cancelar</button>
              </template>
            </div>
            <p v-if="removePreview && removePreview.contacts === 0" class="text-xs text-n-slate-9">
              Ninguém encontrado com esse critério.
            </p>
          </div>
        </div>

        <!-- Tratamento de dados: preencher valores pelo orçamento -->
        <div class="max-w-3xl mb-5 bg-n-solid-2 border border-n-weak rounded-xl overflow-hidden">
          <button
            class="w-full flex items-center gap-3 p-4 text-left hover:bg-n-alpha-1 transition-colors"
            @click="showValuePanel = !showValuePanel"
          >
            <span class="i-lucide-badge-dollar-sign text-xl text-green-600 flex-shrink-0" />
            <div class="flex-1 min-w-0">
              <p class="text-sm font-semibold text-n-slate-12">Tratamento de dados — preencher valores pelo orçamento</p>
              <p class="text-xs text-n-slate-10">
                Varre as conversas de cada card procurando o maior R$ mencionado e preenche o valor.
              </p>
            </div>
            <span
              class="text-n-slate-10 flex-shrink-0"
              :class="showValuePanel ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
            />
          </button>

          <div v-if="showValuePanel" class="px-4 pb-4 space-y-3 border-t border-n-weak pt-4">
            <label class="flex items-center gap-2 text-xs text-n-slate-11 cursor-pointer">
              <input v-model="valueOnlyEmpty" type="checkbox" class="rounded accent-n-brand" />
              Só cards sem valor (recomendado)
            </label>
            <button
              class="text-xs px-4 py-2 rounded-lg bg-n-brand text-white hover:opacity-90 flex items-center gap-1.5 disabled:opacity-50"
              :disabled="isValueRunning"
              @click="runBulkValues"
            >
              <span :class="isValueRunning ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-wand-2'" />
              Preencher valores
            </button>
          </div>
        </div>

        <!-- Unificação de contatos duplicados -->
        <div class="max-w-3xl mb-5 bg-n-solid-2 border border-n-weak rounded-xl overflow-hidden">
          <button
            class="w-full flex items-center gap-3 p-4 text-left hover:bg-n-alpha-1 transition-colors"
            @click="showUnifyPanel = !showUnifyPanel"
          >
            <span class="i-lucide-merge text-xl text-n-brand flex-shrink-0" />
            <div class="flex-1 min-w-0">
              <p class="text-sm font-semibold text-n-slate-12">Unificar contatos duplicados</p>
              <p class="text-xs text-n-slate-10">
                Mescla contatos com o mesmo telefone ou e-mail (ex: chamou pelo Instagram e pelo WhatsApp).
                Conversas, etiquetas e notas são preservadas no contato unificado.
              </p>
            </div>
            <span
              class="text-n-slate-10 flex-shrink-0"
              :class="showUnifyPanel ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
            />
          </button>

          <div v-if="showUnifyPanel" class="px-4 pb-4 space-y-3 border-t border-n-weak pt-4">
            <div class="flex flex-wrap items-center gap-3">
              <button
                class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center gap-1 disabled:opacity-50"
                :disabled="isUnifyLoading"
                @click="previewUnify"
              >
                <span class="i-lucide-search" />
                {{ isUnifyLoading ? 'Calculando…' : 'Calcular duplicados' }}
              </button>

              <span v-if="unifyPreview" class="text-sm text-n-slate-12">
                <b>{{ unifyPreview.groups }}</b> grupo(s) de duplicados ·
                <b>{{ unifyPreview.contacts_to_merge }}</b> contato(s) serão mesclados
              </span>
            </div>

            <!-- Exemplos -->
            <div v-if="unifyPreview?.examples?.length" class="bg-n-alpha-1 rounded-lg p-3 space-y-1 max-h-48 overflow-y-auto">
              <p class="text-[11px] text-n-slate-9 mb-1">Exemplos do que será unificado:</p>
              <div
                v-for="(ex, i) in unifyPreview.examples"
                :key="i"
                class="text-xs text-n-slate-11 flex items-center gap-2"
              >
                <span class="i-lucide-users text-[11px] text-n-slate-9 flex-shrink-0" />
                <span class="truncate">
                  {{ ex.names.join(' + ') }}
                  <span class="text-n-slate-9">({{ ex.phone_number || ex.email }} · {{ ex.duplicates }} contatos → 1)</span>
                </span>
              </div>
            </div>

            <div v-if="unifyPreview && unifyPreview.contacts_to_merge > 0" class="flex items-center gap-3">
              <template v-if="!showUnifyConfirm">
                <button
                  class="text-xs px-4 py-2 rounded-lg bg-n-brand text-white hover:opacity-90 flex items-center gap-1.5"
                  @click="showUnifyConfirm = true"
                >
                  <span class="i-lucide-merge" />
                  Unificar contatos
                </button>
              </template>
              <template v-else>
                <span class="text-xs text-amber-600 font-medium">
                  ⚠ A mesclagem não pode ser desfeita. Confirma?
                </span>
                <button
                  class="text-xs px-3 py-1.5 rounded-lg bg-amber-600 text-white disabled:opacity-50"
                  :disabled="isUnifyApplying"
                  @click="applyUnify"
                >
                  {{ isUnifyApplying ? 'Iniciando…' : 'Sim, unificar' }}
                </button>
                <button
                  class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11"
                  @click="showUnifyConfirm = false"
                >
                  Cancelar
                </button>
              </template>
            </div>

            <p v-if="unifyPreview && unifyPreview.contacts_to_merge === 0" class="text-xs text-green-600">
              ✓ Nenhum duplicado por telefone/e-mail encontrado.
            </p>
            <p class="text-[11px] text-n-slate-9">
              Contatos sem telefone (ex: só Instagram) não são unificados automaticamente —
              use o botão "Mesclar" no card do CRM para esses casos.
            </p>
          </div>
        </div>

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

      <!-- ══ ABA PAINEL: saúde dos números + visão geral ══ -->
      <template v-else>
        <!-- KPIs gerais -->
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 max-w-4xl mb-6">
          <div class="bg-n-solid-2 border border-n-weak rounded-xl p-4">
            <p class="text-xs text-n-slate-10">Mensagens enviadas</p>
            <p class="text-2xl font-bold text-n-slate-12">{{ panelStats.totalSent }}</p>
            <p class="text-xs text-n-slate-9 mt-0.5">campanhas + automações</p>
          </div>
          <div class="bg-n-solid-2 border border-n-weak rounded-xl p-4">
            <p class="text-xs text-n-slate-10">Campanhas concluídas</p>
            <p class="text-2xl font-bold text-green-600">{{ panelStats.completedCampaigns }}</p>
          </div>
          <div class="bg-n-solid-2 border border-n-weak rounded-xl p-4">
            <p class="text-xs text-n-slate-10">Campanhas agendadas</p>
            <p class="text-2xl font-bold text-n-gold">{{ panelStats.scheduledCampaigns }}</p>
          </div>
          <div class="bg-n-solid-2 border border-n-weak rounded-xl p-4">
            <p class="text-xs text-n-slate-10">Automações ativas</p>
            <p class="text-2xl font-bold text-n-brand">{{ panelStats.activeAutomations }}</p>
          </div>
        </div>

        <!-- Saúde dos números agora vive em Relatórios -->
        <button
          class="w-full max-w-4xl bg-n-solid-2 border border-n-weak rounded-xl p-4 flex items-center gap-3 hover:border-n-brand transition-colors text-left"
          @click="router.push({ name: 'whatsapp_health_reports' })"
        >
          <span class="i-lucide-activity text-2xl text-n-brand flex-shrink-0" />
          <div class="flex-1 min-w-0">
            <p class="text-sm font-semibold text-n-slate-12">Saúde dos números WhatsApp</p>
            <p class="text-xs text-n-slate-10">
              Qualidade, limites de envio e webhook de cada número — em Relatórios › Saúde do WhatsApp
            </p>
          </div>
          <span class="i-lucide-arrow-right text-n-slate-10 flex-shrink-0" />
        </button>
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
            :class="scheduledAt ? 'bg-n-gold' : 'bg-n-brand'"
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
