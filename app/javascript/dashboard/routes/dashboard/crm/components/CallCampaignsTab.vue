<script setup>
// 🤖📞 Aba "Ligações" das Campanhas (item 169): campanhas em que a
// assistente virtual LIGA para um público (etiquetas / colunas do CRM /
// período), dentro do horário configurado em Integrações → Agente de
// Ligação. Lista + formulário + detalhe com a tabela de contatos. Fala
// direto com CevicoCallCampaignsAPI (crm/call_campaigns) — sem módulo Vuex,
// porque só esta aba usa esses dados.
import { ref, computed, watch, onMounted, onUnmounted } from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ChipPicker from './ChipPicker.vue';
import CevicoCallCampaignsAPI from 'dashboard/api/cevicoCallCampaigns';
import {
  formatTalkTime,
  formatPhoneBR,
  shortDateTime,
} from 'dashboard/helper/cevicoCallsFormat';

const props = defineProps({
  labelOptions: { type: Array, default: () => [] },
  stageOptions: { type: Array, default: () => [] },
  voiceEnabled: { type: Boolean, default: false },
  permissionTemplateSet: { type: Boolean, default: false },
});

const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');

const GRADIENT = 'linear-gradient(135deg, #7C3AED, #DB2777)';
const PER_PAGE = 50;

const STATUS_META = {
  draft: { label: 'Rascunho', cls: 'bg-n-alpha-2 text-n-slate-11' },
  scheduled: { label: 'Agendada', cls: 'bg-n-gold-soft text-n-gold' },
  processing: { label: 'Ligando…', cls: 'bg-purple-500/15 text-purple-700' },
  paused: { label: 'Pausada', cls: 'bg-amber-500/15 text-amber-700' },
  completed: { label: 'Concluída', cls: 'bg-green-500/15 text-green-600' },
  failed: { label: 'Falhou', cls: 'bg-red-500/15 text-red-600' },
};
const CONTACT_STATUS = {
  queued: { label: 'Na fila', cls: 'bg-n-alpha-2 text-n-slate-11' },
  calling: { label: 'Ligando…', cls: 'bg-purple-500/15 text-purple-700' },
  done: { label: 'Concluída', cls: 'bg-green-500/15 text-green-600' },
  failed: { label: 'Falhou', cls: 'bg-red-500/15 text-red-600' },
  skipped: { label: 'Pulado', cls: 'bg-amber-500/15 text-amber-700' },
  no_permission: {
    label: 'Sem permissão',
    cls: 'bg-amber-500/15 text-amber-700',
  },
};
// espelho de Crm::Call::OUTCOME_LABELS — só entra quando o backend manda a
// chave crua em vez do rótulo pronto
const OUTCOME_LABELS = {
  agendou: 'Agendou consulta',
  remarcou: 'Remarcou',
  cancelou: 'Cancelou',
  quer_whatsapp: 'Prefere WhatsApp',
  sem_interesse: 'Sem interesse',
  recado: 'Deixou recado',
  transferido: 'Transferida',
  nao_atendeu: 'Não atendeu',
  outro: 'Outro',
};
const outcomeLabel = key => OUTCOME_LABELS[key] || key;

const needsSetup = computed(
  () => !props.voiceEnabled || !props.permissionTemplateSet
);
const goToVoiceSettings = () =>
  router.push({ name: 'crm_integrations_voice_agent' });

// ── lista ──
const campaigns = ref([]);
const isLoading = ref(false);
const deleteConfirmId = ref(null);
const busyId = ref(null);

const load = async (silent = false) => {
  try {
    const { data } = await CevicoCallCampaignsAPI.list();
    campaigns.value = Array.isArray(data?.call_campaigns)
      ? data.call_campaigns
      : [];
  } catch {
    if (!silent) useAlert('Erro ao carregar as campanhas de ligação');
  }
};

// ── detalhe (contatos paginados) ──
const detail = ref(null);
const detailContacts = ref([]);
const detailMeta = ref({ total: 0, page: 1 });
const isDetailLoading = ref(false);

const openDetail = async (c, page = 1) => {
  detail.value = c;
  isDetailLoading.value = true;
  try {
    const { data } = await CevicoCallCampaignsAPI.show(c.id, { page });
    // a resposta é a campanha + contacts + meta — separa o que é da campanha
    const { contacts, meta, ...campaign } = data || {};
    detail.value = { ...c, ...campaign };
    detailContacts.value = Array.isArray(contacts) ? contacts : [];
    detailMeta.value = {
      total: Number(meta?.total ?? detailContacts.value.length),
      page: Number(meta?.page ?? page),
    };
  } catch {
    useAlert('Erro ao abrir a campanha');
    detail.value = null;
  } finally {
    isDetailLoading.value = false;
  }
};
const refreshDetail = () => {
  if (detail.value) openDetail(detail.value, detailMeta.value.page);
};
const closeDetail = () => {
  detail.value = null;
  detailContacts.value = [];
};
const totalPages = computed(() =>
  Math.max(1, Math.ceil(detailMeta.value.total / PER_PAGE))
);

// ── polling: enquanto alguma campanha está discando ──
let timer = null;
onMounted(async () => {
  isLoading.value = true;
  await load();
  isLoading.value = false;
  timer = setInterval(() => {
    const live = campaigns.value.some(c => c.status === 'processing');
    if (live) load(true);
    if (
      detail.value &&
      ['processing', 'scheduled'].includes(detail.value.status)
    ) {
      refreshDetail();
    }
  }, 5000);
});
onUnmounted(() => clearInterval(timer));

// ── formulário ──
const showComposer = ref(false);
const isSubmitting = ref(false);
const blankForm = () => ({
  name: '',
  objective: '',
  first_message: '',
  apply_label: '',
  hours: { start: '08:00', end: '19:00' },
  daily_cap: 50,
  concurrency: 2,
});
const form = ref(blankForm());
const scheduledAt = ref(''); // vazio = "Começar agora" ou rascunho
const includeLabelIds = ref([]);
const excludeLabelIds = ref([]);
const includeStageIds = ref([]);
const excludeStageIds = ref([]);
const periodField = ref(''); // '' | contact_created | label_applied
const periodFrom = ref('');
const periodTo = ref('');
const audiencePreview = ref(null);
const isPreviewLoading = ref(false);

const openComposer = () => {
  form.value = blankForm();
  scheduledAt.value = '';
  includeLabelIds.value = [];
  excludeLabelIds.value = [];
  includeStageIds.value = [];
  excludeStageIds.value = [];
  periodField.value = '';
  periodFrom.value = '';
  periodTo.value = '';
  audiencePreview.value = null;
  showComposer.value = true;
};

// mesmas chaves da Campanha WhatsApp (Crm::Campaign#resolve_audience)
const audiencePayload = () => ({
  include_label_ids: includeLabelIds.value,
  include_stage_ids: includeStageIds.value,
  exclude_label_ids: excludeLabelIds.value,
  exclude_stage_ids: excludeStageIds.value,
  period_field: periodField.value,
  period_from: periodFrom.value,
  period_to: periodTo.value,
});
const hasAudience = computed(
  () => includeLabelIds.value.length > 0 || includeStageIds.value.length > 0
);
const canSubmit = computed(
  () => Boolean(form.value.name.trim()) && hasAudience.value
);
// qualquer mudança no público invalida a prévia calculada
watch(
  [
    includeLabelIds,
    excludeLabelIds,
    includeStageIds,
    excludeStageIds,
    periodField,
    periodFrom,
    periodTo,
  ],
  () => {
    audiencePreview.value = null;
  }
);

const previewAudience = async () => {
  if (!hasAudience.value || isPreviewLoading.value) return;
  isPreviewLoading.value = true;
  try {
    const { data } =
      await CevicoCallCampaignsAPI.previewAudience(audiencePayload());
    audiencePreview.value = data || { count: 0, sample: [] };
  } catch {
    useAlert('Erro ao calcular o público');
  } finally {
    isPreviewLoading.value = false;
  }
};

const buildPayload = () => ({
  name: form.value.name.trim(),
  objective: form.value.objective.trim(),
  first_message: form.value.first_message.trim(),
  audience: audiencePayload(),
  hours: { ...form.value.hours },
  daily_cap: Math.max(1, Number(form.value.daily_cap || 50)),
  concurrency: Math.max(1, Number(form.value.concurrency || 1)),
  apply_label: form.value.apply_label.trim(),
  scheduled_at: scheduledAt.value || null,
});

const formatDateTime = v =>
  v
    ? new Date(v).toLocaleString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        year: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '';

// mode: 'draft' (só salva) | 'now' (salva e começa) | 'schedule' (salva com data)
const submit = async mode => {
  if (!canSubmit.value || isSubmitting.value) return;
  if (mode === 'schedule' && !scheduledAt.value) {
    useAlert('Escolha a data e a hora para agendar.');
    return;
  }
  isSubmitting.value = true;
  try {
    const payload = buildPayload();
    if (mode !== 'schedule') payload.scheduled_at = null;
    const { data } = await CevicoCallCampaignsAPI.create(payload);
    const created = data?.call_campaign || data;
    if (mode === 'now' && created?.id) {
      await CevicoCallCampaignsAPI.start(created.id);
      useAlert('Campanha começou! A assistente liga dentro do horário.');
    } else if (mode === 'schedule') {
      useAlert(`Campanha agendada para ${formatDateTime(scheduledAt.value)}.`);
    } else {
      useAlert('Rascunho salvo.');
    }
    showComposer.value = false;
    await load();
  } catch (error) {
    useAlert(
      error?.response?.data?.error || 'Erro ao criar a campanha de ligações'
    );
  } finally {
    isSubmitting.value = false;
  }
};

// ── ações da lista/detalhe ──
const runAction = async (c, action, successMessage) => {
  if (busyId.value) return;
  busyId.value = c.id;
  try {
    await CevicoCallCampaignsAPI[action](c.id);
    if (successMessage) useAlert(successMessage);
    await load(true);
    if (detail.value?.id === c.id) refreshDetail();
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui fazer isso agora.');
  } finally {
    busyId.value = null;
  }
};
const startCampaign = c =>
  runAction(
    c,
    'start',
    'Campanha começou! A assistente liga dentro do horário.'
  );
const pauseCampaign = c => runAction(c, 'pause', 'Campanha pausada.');
const resumeCampaign = c => runAction(c, 'resume', 'Campanha retomada.');
const removeCampaign = async c => {
  try {
    await CevicoCallCampaignsAPI.destroy(c.id);
    deleteConfirmId.value = null;
    if (detail.value?.id === c.id) closeDetail();
    await load();
  } catch {
    useAlert('Erro ao excluir a campanha');
  }
};
const canStart = c => ['draft', 'scheduled'].includes(c.status);
const canPause = c => c.status === 'processing';
const canResume = c => c.status === 'paused';
const canDelete = c => c.status !== 'processing';

// ── progresso / resultados ──
const progressOf = c => c.progress || c.stats || {};
const totalOf = c => Number(progressOf(c).total || 0);
const pct = (c, key) => {
  const total = totalOf(c);
  if (!total) return 0;
  return Math.min(100, (Number(progressOf(c)[key] || 0) / total) * 100);
};
const progressLine = c => {
  const p = progressOf(c);
  if (!totalOf(c)) return c.status === 'draft' ? '' : 'sem contatos ainda';
  const parts = [`${p.done || 0}/${p.total} ligadas`];
  if (p.calling) parts.push(`${p.calling} em ligação`);
  if (p.queued) parts.push(`${p.queued} na fila`);
  if (p.failed) parts.push(`${p.failed} falhas`);
  if (p.no_permission) parts.push(`${p.no_permission} sem permissão`);
  if (p.skipped) parts.push(`${p.skipped} pulados`);
  return parts.join(' · ');
};
const outcomeChips = c =>
  Object.entries(c.outcomes || {})
    .map(([key, count]) => ({ key, label: outcomeLabel(key), count }))
    .filter(o => Number(o.count) > 0)
    .sort((a, b) => Number(b.count) - Number(a.count));

const openConversation = row => {
  if (!row?.conversation_id) return;
  router.push(
    `/app/accounts/${accountId.value}/conversations/${row.conversation_id}`
  );
};
const audienceSummary = c => {
  const a = c.audience || {};
  const parts = [];
  const names = (ids, options) =>
    (ids || [])
      .map(id => options.find(o => o.id === id)?.label)
      .filter(Boolean);
  const labels = names(a.include_label_ids, props.labelOptions);
  const stages = names(a.include_stage_ids, props.stageOptions);
  if (labels.length) parts.push(`etiquetas: ${labels.join(', ')}`);
  if (stages.length) parts.push(`colunas: ${stages.join(', ')}`);
  return parts.join(' · ');
};

const inputClass =
  'w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand';
</script>

<template>
  <div class="space-y-4">
    <!-- Aviso fixo: assistente desligada ou sem modelo de permissão -->
    <div
      v-if="needsSetup"
      class="sticky top-0 z-10 flex items-center gap-3 px-4 py-3 rounded-xl border bg-amber-500/10 border-amber-400/30 text-amber-800 dark:text-amber-200"
    >
      <span class="i-lucide-alert-triangle text-base flex-shrink-0" />
      <p class="text-xs flex-1 min-w-0">
        <template v-if="!voiceEnabled">
          A assistente virtual está <strong>desligada</strong> — as campanhas
          ficam paradas até ligar.
        </template>
        <template v-else>
          Falta o <strong>modelo de permissão para ligar</strong> — sem ele a
          Meta não deixa a assistente discar.
        </template>
      </p>
      <button
        class="text-xs font-bold px-3 py-1.5 rounded-lg text-white flex-shrink-0 hover:opacity-90"
        :style="{ background: GRADIENT }"
        @click="goToVoiceSettings"
      >
        Configurar a assistente →
      </button>
    </div>

    <!-- Cabeçalho da aba -->
    <div class="flex items-center gap-3 flex-wrap">
      <div>
        <h2
          class="text-sm font-semibold text-n-slate-12 flex items-center gap-2"
        >
          <span class="i-lucide-phone-call" style="color: #7c3aed" />
          Campanhas de ligação
        </h2>
        <p class="text-xs text-n-slate-10">
          A assistente virtual liga para um público, dentro do horário, e
          registra o resultado de cada conversa.
        </p>
      </div>
      <div class="flex-1" />
      <button
        class="flex items-center gap-1.5 text-sm font-bold px-4 py-2 rounded-xl text-white hover:opacity-90 transition-opacity shadow-sm"
        :style="{ background: GRADIENT }"
        @click="openComposer"
      >
        <span class="i-lucide-plus" />
        Nova campanha de ligações
      </button>
    </div>

    <div v-if="isLoading" class="flex justify-center py-16">
      <Spinner :size="28" class="text-n-brand" />
    </div>

    <div
      v-else-if="!campaigns.length"
      class="flex flex-col items-center justify-center py-20 text-n-slate-9"
    >
      <span class="i-lucide-phone-call text-5xl mb-4" />
      <p class="text-sm">Nenhuma campanha de ligação ainda.</p>
      <p class="text-xs mt-1">
        Crie a primeira: escolha o público e a assistente liga para cada
        paciente.
      </p>
    </div>

    <div v-else class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
      <div
        v-for="c in campaigns"
        :key="c.id"
        class="bg-n-solid-2 border border-n-weak rounded-xl p-4 flex flex-col gap-2 transition-all cursor-pointer hover:border-n-brand hover:shadow-sm"
        @click="openDetail(c)"
      >
        <div class="flex items-center gap-2 flex-wrap">
          <span
            class="text-sm font-semibold text-n-slate-12 flex-1 min-w-0 truncate"
          >
            {{ c.name }}
          </span>
          <span
            class="text-xs px-2 py-0.5 rounded-full flex-shrink-0"
            :class="STATUS_META[c.status]?.cls"
          >
            {{ STATUS_META[c.status]?.label ?? c.status }}
          </span>
        </div>

        <p v-if="c.objective" class="text-xs text-n-slate-10 line-clamp-2">
          {{ c.objective }}
        </p>
        <p
          v-if="audienceSummary(c)"
          class="text-[11px] text-n-slate-9 truncate"
        >
          {{ audienceSummary(c) }}
        </p>

        <p
          v-if="c.status === 'scheduled' && c.scheduled_at"
          class="text-xs text-n-gold flex items-center gap-1"
        >
          <span class="i-lucide-clock" /> Começa em
          {{ formatDateTime(c.scheduled_at) }}
        </p>

        <!-- barra de progresso -->
        <div v-if="totalOf(c)" class="space-y-1">
          <div class="h-2 rounded-full bg-n-alpha-2 overflow-hidden flex">
            <div
              class="h-full bg-green-500"
              :style="{ width: `${pct(c, 'done')}%` }"
            />
            <div
              class="h-full bg-red-400"
              :style="{ width: `${pct(c, 'failed')}%` }"
            />
            <div
              class="h-full bg-amber-400"
              :style="{
                width: `${pct(c, 'skipped') + pct(c, 'no_permission')}%`,
              }"
            />
            <div
              class="h-full bg-purple-400 animate-pulse"
              :style="{ width: `${pct(c, 'calling')}%` }"
            />
          </div>
          <p class="text-xs text-n-slate-11">{{ progressLine(c) }}</p>
        </div>
        <p v-else-if="progressLine(c)" class="text-xs text-n-slate-11">
          {{ progressLine(c) }}
        </p>

        <!-- resultados por tipo -->
        <div v-if="outcomeChips(c).length" class="flex flex-wrap gap-1">
          <span
            v-for="o in outcomeChips(c)"
            :key="o.key"
            class="text-[10px] px-2 py-0.5 rounded-full bg-purple-500/10 text-purple-700 border border-purple-500/20"
          >
            {{ o.label }} · {{ o.count }}
          </span>
        </div>
        <p v-if="c.stats?.error" class="text-xs text-red-500 truncate">
          {{ c.stats.error }}
        </p>

        <div class="flex items-center gap-2 mt-auto pt-2" @click.stop>
          <button
            v-if="canStart(c)"
            class="text-xs px-3 py-1.5 rounded-lg text-white hover:opacity-90 disabled:opacity-50"
            :style="{ background: GRADIENT }"
            :disabled="busyId === c.id || needsSetup"
            :title="needsSetup ? 'Configure a assistente antes' : ''"
            @click="startCampaign(c)"
          >
            Começar agora
          </button>
          <button
            v-else-if="canPause(c)"
            class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-amber-700 hover:bg-amber-500/10 disabled:opacity-50"
            :disabled="busyId === c.id"
            @click="pauseCampaign(c)"
          >
            Pausar
          </button>
          <button
            v-else-if="canResume(c)"
            class="text-xs px-3 py-1.5 rounded-lg bg-n-brand text-white hover:opacity-90 disabled:opacity-50"
            :disabled="busyId === c.id || needsSetup"
            @click="resumeCampaign(c)"
          >
            Retomar
          </button>
          <span
            v-if="c.status === 'completed'"
            class="text-xs text-green-600 flex items-center gap-1"
          >
            <span class="i-lucide-check" /> Ver contatos
          </span>

          <div class="flex-1" />
          <template v-if="canDelete(c)">
            <button
              v-if="deleteConfirmId !== c.id"
              class="text-n-slate-10 hover:text-red-500 i-lucide-trash-2 text-sm"
              @click="deleteConfirmId = c.id"
            />
            <button
              v-else
              class="text-xs px-2 py-1 rounded bg-red-500 text-white"
              @click="removeCampaign(c)"
            >
              Confirmar
            </button>
          </template>
          <Spinner v-else :size="14" />
        </div>
      </div>
    </div>

    <!-- ── Composer ───────────────────────────────────────────── -->
    <div
      v-if="showComposer"
      class="fixed inset-0 z-40 bg-black/50 flex items-start justify-center overflow-y-auto py-8"
      @click.self="showComposer = false"
    >
      <div
        class="bg-n-solid-1 rounded-2xl w-full max-w-2xl mx-4 shadow-xl border border-n-weak"
      >
        <div
          class="flex items-center justify-between px-5 py-4 border-b border-n-weak"
        >
          <h2
            class="text-sm font-semibold text-n-slate-12 flex items-center gap-2"
          >
            <span class="i-lucide-phone-call" style="color: #7c3aed" />
            Nova campanha de ligações
          </h2>
          <button
            class="i-lucide-x text-n-slate-10 hover:text-n-slate-12"
            @click="showComposer = false"
          />
        </div>

        <div class="p-5 space-y-5">
          <!-- passo 1: a LIGAÇÃO -->
          <p
            class="text-xs font-semibold text-n-slate-11 flex items-center gap-1.5 -mb-2"
          >
            <span
              class="w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold text-white flex-shrink-0"
              :style="{ background: GRADIENT }"
            >
              1
            </span>
            <span class="i-lucide-bot" style="color: #7c3aed" /> A ligação
            <span class="text-n-slate-9 font-normal">
              (o que a assistente vai fazer)
            </span>
          </p>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Nome da campanha <span class="text-red-500">*</span>
            </label>
            <input
              v-model="form.name"
              :class="inputClass"
              placeholder="Ex.: Reativar pacientes de catarata — setembro"
            />
          </div>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Objetivo da ligação
            </label>
            <textarea
              v-model="form.objective"
              rows="3"
              :class="inputClass"
              placeholder="Ex.: Convidar para a avaliação gratuita de cirurgia refrativa e já deixar a consulta marcada."
            />
            <p class="text-xs text-n-slate-9 mt-1">
              Entra no script da assistente como o motivo da ligação. Ela conduz
              a conversa a partir daqui.
            </p>
          </div>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Primeira frase
              <span class="text-n-slate-9 font-normal">(opcional)</span>
            </label>
            <textarea
              v-model="form.first_message"
              rows="2"
              :class="inputClass"
              placeholder="Vazio = ela se apresenta como assistente virtual da CEVICO, chama pelo nome e explica o motivo"
            />
          </div>

          <!-- passo 2: o PÚBLICO -->
          <p
            class="text-xs font-semibold text-n-slate-11 flex items-center gap-1.5 -mb-2 pt-2"
          >
            <span
              class="w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold text-white flex-shrink-0"
              :style="{ background: GRADIENT }"
            >
              2
            </span>
            <span class="i-lucide-users" style="color: #7c3aed" /> O público
            <span class="text-n-slate-9 font-normal">
              (para quem ela liga, quem fica de fora)
            </span>
          </p>

          <div
            class="bg-n-alpha-1 border border-n-weak rounded-xl p-4 space-y-3"
          >
            <p
              class="text-xs font-semibold text-n-slate-11 flex items-center gap-1"
            >
              <span class="i-lucide-users text-n-brand" /> Público — quem VAI
              receber a ligação
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

          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-2">
              Período
              <span class="text-n-slate-9">
                (opcional — acione a base em blocos)
              </span>
            </label>
            <div class="flex flex-wrap items-center gap-2">
              <select
                v-model="periodField"
                class="border border-n-weak rounded-lg px-2 py-2 text-xs bg-n-solid-2 text-n-slate-12"
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
                />
                <span class="text-xs text-n-slate-10">até</span>
                <input
                  v-model="periodTo"
                  type="date"
                  class="border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-2 text-n-slate-12"
                />
              </template>
            </div>
          </div>

          <div
            class="bg-n-alpha-1 border border-n-weak rounded-xl p-4 space-y-3"
          >
            <p
              class="text-xs font-semibold text-n-slate-11 flex items-center gap-1"
            >
              <span class="i-lucide-user-x text-red-500" /> Exclusões — quem NÃO
              deve receber
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
                class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center gap-1 disabled:opacity-50"
                :disabled="!hasAudience || isPreviewLoading"
                @click="previewAudience"
              >
                <span class="i-lucide-users" />
                {{ isPreviewLoading ? 'Calculando…' : 'Prever público' }}
              </button>
              <p v-if="audiencePreview" class="text-xs text-n-slate-11">
                <strong class="text-n-slate-12">
                  {{ audiencePreview.count }}
                </strong>
                paciente(s) com telefone
                <template
                  v-if="
                    Array.isArray(audiencePreview.sample) &&
                    audiencePreview.sample.length
                  "
                >
                  — ex.:
                  {{
                    audiencePreview.sample
                      .slice(0, 3)
                      .map(s => s.name || s.phone_number || s)
                      .join(', ')
                  }}
                </template>
              </p>
            </div>
          </div>

          <!-- passo 3: o RITMO -->
          <p
            class="text-xs font-semibold text-n-slate-11 flex items-center gap-1.5 -mb-2 pt-2"
          >
            <span
              class="w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold text-white flex-shrink-0"
              :style="{ background: GRADIENT }"
            >
              3
            </span>
            <span class="i-lucide-gauge" style="color: #7c3aed" /> O ritmo
            <span class="text-n-slate-9 font-normal">
              (horário, quantas por dia, ao mesmo tempo)
            </span>
          </p>
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
                Horário
              </label>
              <div class="flex items-center gap-1.5">
                <input
                  v-model="form.hours.start"
                  type="time"
                  :class="inputClass"
                />
                <span class="text-xs text-n-slate-9">–</span>
                <input
                  v-model="form.hours.end"
                  type="time"
                  :class="inputClass"
                />
              </div>
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
                Teto por dia
              </label>
              <input
                v-model.number="form.daily_cap"
                type="number"
                min="1"
                :class="inputClass"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
                Ligações ao mesmo tempo
              </label>
              <input
                v-model.number="form.concurrency"
                type="number"
                min="1"
                max="10"
                :class="inputClass"
              />
            </div>
          </div>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Etiqueta aplicada depois da ligação
              <span class="text-n-slate-9 font-normal">(opcional)</span>
            </label>
            <input
              v-model="form.apply_label"
              :class="inputClass"
              placeholder="Ex: ligacao-setembro-2026"
            />
          </div>

          <!-- passo 4: QUANDO -->
          <p
            class="text-xs font-semibold text-n-slate-11 flex items-center gap-1.5 -mb-2 pt-2"
          >
            <span
              class="w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold text-white flex-shrink-0"
              :style="{ background: GRADIENT }"
            >
              4
            </span>
            <span class="i-lucide-calendar-clock" style="color: #7c3aed" />
            Quando começar
          </p>
          <div class="flex flex-wrap items-center gap-2">
            <input
              v-model="scheduledAt"
              type="datetime-local"
              class="border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-2 text-n-slate-12"
            />
            <span class="text-xs text-n-slate-9">
              Vazio = "Começar agora". Com data, a campanha entra na fila e
              começa sozinha.
            </span>
          </div>
        </div>

        <div
          class="flex items-center gap-2 px-5 py-4 border-t border-n-weak flex-wrap"
        >
          <p v-if="!hasAudience" class="text-xs text-n-slate-9">
            Escolha pelo menos uma etiqueta ou coluna no público.
          </p>
          <div class="flex-1" />
          <button
            class="text-sm px-4 py-2 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50"
            :disabled="!canSubmit || isSubmitting"
            @click="submit('draft')"
          >
            Salvar rascunho
          </button>
          <button
            v-if="scheduledAt"
            class="text-sm font-bold px-4 py-2 rounded-lg text-white hover:opacity-90 disabled:opacity-50"
            :style="{ background: GRADIENT }"
            :disabled="!canSubmit || isSubmitting"
            @click="submit('schedule')"
          >
            {{
              isSubmitting
                ? 'Salvando…'
                : `Agendar para ${formatDateTime(scheduledAt)}`
            }}
          </button>
          <button
            v-else
            class="text-sm font-bold px-4 py-2 rounded-lg text-white hover:opacity-90 disabled:opacity-50 flex items-center gap-1.5"
            :style="{ background: GRADIENT }"
            :disabled="!canSubmit || isSubmitting || needsSetup"
            :title="needsSetup ? 'Configure a assistente antes' : ''"
            @click="submit('now')"
          >
            <span class="i-lucide-phone-outgoing" />
            {{ isSubmitting ? 'Começando…' : 'Começar agora' }}
          </button>
        </div>
      </div>
    </div>

    <!-- ── Detalhe ────────────────────────────────────────────── -->
    <div
      v-if="detail"
      class="fixed inset-0 z-40 bg-black/50 flex items-start justify-center overflow-y-auto py-8"
      @click.self="closeDetail"
    >
      <div
        class="bg-n-solid-1 rounded-2xl w-full max-w-3xl mx-4 shadow-xl border border-n-weak"
      >
        <div
          class="flex items-center gap-3 px-5 py-4 border-b border-n-weak flex-wrap"
        >
          <h2
            class="text-sm font-semibold text-n-slate-12 flex items-center gap-2 flex-1 min-w-0"
          >
            <span class="i-lucide-phone-call" style="color: #7c3aed" />
            <span class="truncate">{{ detail.name }}</span>
            <span
              class="text-xs px-2 py-0.5 rounded-full flex-shrink-0 font-normal"
              :class="STATUS_META[detail.status]?.cls"
            >
              {{ STATUS_META[detail.status]?.label ?? detail.status }}
            </span>
          </h2>
          <button
            v-if="canStart(detail)"
            class="text-xs px-3 py-1.5 rounded-lg text-white hover:opacity-90 disabled:opacity-50"
            :style="{ background: GRADIENT }"
            :disabled="busyId === detail.id || needsSetup"
            @click="startCampaign(detail)"
          >
            Começar agora
          </button>
          <button
            v-else-if="canPause(detail)"
            class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-amber-700 hover:bg-amber-500/10 disabled:opacity-50"
            :disabled="busyId === detail.id"
            @click="pauseCampaign(detail)"
          >
            Pausar
          </button>
          <button
            v-else-if="canResume(detail)"
            class="text-xs px-3 py-1.5 rounded-lg bg-n-brand text-white hover:opacity-90 disabled:opacity-50"
            :disabled="busyId === detail.id || needsSetup"
            @click="resumeCampaign(detail)"
          >
            Retomar
          </button>
          <button
            class="text-xs px-2.5 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:text-n-brand flex items-center gap-1 disabled:opacity-50"
            :disabled="isDetailLoading"
            @click="refreshDetail"
          >
            <span
              :class="
                isDetailLoading
                  ? 'i-lucide-loader-2 animate-spin'
                  : 'i-lucide-refresh-cw'
              "
              class="text-xs"
            />
            Atualizar
          </button>
          <button
            class="i-lucide-x text-n-slate-10 hover:text-n-slate-12"
            @click="closeDetail"
          />
        </div>

        <div class="p-5 space-y-4">
          <p v-if="detail.objective" class="text-xs text-n-slate-11">
            <span class="text-n-slate-9">Objetivo:</span> {{ detail.objective }}
          </p>
          <p class="text-[11px] text-n-slate-9 flex flex-wrap gap-x-3">
            <span v-if="audienceSummary(detail)">
              {{ audienceSummary(detail) }}
            </span>
            <span v-if="detail.hours?.start">
              horário {{ detail.hours.start }}–{{ detail.hours.end }}
            </span>
            <span v-if="detail.daily_cap">
              teto {{ detail.daily_cap }}/dia
            </span>
            <span v-if="detail.concurrency">
              {{ detail.concurrency }} ao mesmo tempo
            </span>
            <span v-if="detail.started_at">
              começou {{ formatDateTime(detail.started_at) }}
            </span>
            <span v-if="detail.finished_at">
              terminou {{ formatDateTime(detail.finished_at) }}
            </span>
          </p>

          <!-- progresso -->
          <div v-if="totalOf(detail)" class="space-y-1">
            <div class="h-2.5 rounded-full bg-n-alpha-2 overflow-hidden flex">
              <div
                class="h-full bg-green-500"
                :style="{ width: `${pct(detail, 'done')}%` }"
              />
              <div
                class="h-full bg-red-400"
                :style="{ width: `${pct(detail, 'failed')}%` }"
              />
              <div
                class="h-full bg-amber-400"
                :style="{
                  width: `${pct(detail, 'skipped') + pct(detail, 'no_permission')}%`,
                }"
              />
              <div
                class="h-full bg-purple-400 animate-pulse"
                :style="{ width: `${pct(detail, 'calling')}%` }"
              />
            </div>
            <p class="text-xs text-n-slate-11">{{ progressLine(detail) }}</p>
          </div>
          <p v-else class="text-xs text-n-slate-9">
            {{
              detail.status === 'draft'
                ? 'Ainda não começou — os contatos entram na fila no "Começar agora".'
                : 'Nenhum contato na fila.'
            }}
          </p>

          <div v-if="outcomeChips(detail).length" class="flex flex-wrap gap-1">
            <span
              v-for="o in outcomeChips(detail)"
              :key="o.key"
              class="text-[11px] px-2 py-0.5 rounded-full bg-purple-500/10 text-purple-700 border border-purple-500/20"
            >
              {{ o.label }} · {{ o.count }}
            </span>
          </div>

          <!-- tabela de contatos -->
          <div class="border border-n-weak rounded-xl overflow-hidden">
            <table class="w-full text-xs">
              <thead class="bg-n-alpha-1 text-n-slate-10">
                <tr>
                  <th class="text-left font-medium px-3 py-2">Paciente</th>
                  <th class="text-left font-medium px-3 py-2">Situação</th>
                  <th class="text-left font-medium px-3 py-2">Resultado</th>
                  <th class="text-left font-medium px-3 py-2">Duração</th>
                  <th class="text-left font-medium px-3 py-2">Quando</th>
                  <th class="px-3 py-2" />
                </tr>
              </thead>
              <tbody>
                <tr v-if="isDetailLoading && !detailContacts.length">
                  <td colspan="6" class="px-3 py-6 text-center text-n-slate-9">
                    Carregando contatos…
                  </td>
                </tr>
                <tr v-else-if="!detailContacts.length">
                  <td colspan="6" class="px-3 py-6 text-center text-n-slate-9">
                    Nenhum contato nesta campanha ainda.
                  </td>
                </tr>
                <tr
                  v-for="row in detailContacts"
                  :key="row.id"
                  class="border-t border-n-weak"
                >
                  <td class="px-3 py-2">
                    <p
                      class="text-n-slate-12 font-medium truncate max-w-[14rem]"
                    >
                      {{ row.contact?.name || 'Paciente' }}
                    </p>
                    <p class="text-n-slate-9">
                      {{ formatPhoneBR(row.contact?.phone_number) }}
                    </p>
                  </td>
                  <td class="px-3 py-2">
                    <span
                      class="px-2 py-0.5 rounded-full whitespace-nowrap"
                      :class="CONTACT_STATUS[row.status]?.cls"
                    >
                      {{ CONTACT_STATUS[row.status]?.label ?? row.status }}
                    </span>
                    <p
                      v-if="row.error"
                      class="text-red-500 mt-0.5 truncate max-w-[12rem]"
                      :title="row.error"
                    >
                      {{ row.error }}
                    </p>
                  </td>
                  <td class="px-3 py-2 text-n-slate-11">
                    {{ row.outcome_label || outcomeLabel(row.outcome) || '—' }}
                  </td>
                  <td class="px-3 py-2 text-n-slate-11 whitespace-nowrap">
                    {{
                      Number(row.duration) ? formatTalkTime(row.duration) : '—'
                    }}
                  </td>
                  <td class="px-3 py-2 text-n-slate-11 whitespace-nowrap">
                    {{ row.called_at ? shortDateTime(row.called_at) : '—' }}
                  </td>
                  <td class="px-3 py-2 text-right">
                    <button
                      v-if="row.conversation_id"
                      class="text-n-brand hover:underline whitespace-nowrap"
                      @click="openConversation(row)"
                    >
                      Conversa →
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <!-- paginação -->
          <div
            v-if="totalPages > 1"
            class="flex items-center justify-between text-xs text-n-slate-10"
          >
            <span>
              {{ detailMeta.total }} contato(s) · página
              {{ detailMeta.page }} de {{ totalPages }}
            </span>
            <div class="flex items-center gap-1">
              <button
                class="px-2.5 py-1 rounded-lg border border-n-weak disabled:opacity-40 hover:bg-n-alpha-1"
                :disabled="detailMeta.page <= 1 || isDetailLoading"
                @click="openDetail(detail, detailMeta.page - 1)"
              >
                ← Anterior
              </button>
              <button
                class="px-2.5 py-1 rounded-lg border border-n-weak disabled:opacity-40 hover:bg-n-alpha-1"
                :disabled="detailMeta.page >= totalPages || isDetailLoading"
                @click="openDetail(detail, detailMeta.page + 1)"
              >
                Próxima →
              </button>
            </div>
          </div>

          <div class="flex items-center gap-2 pt-1">
            <div class="flex-1" />
            <template v-if="canDelete(detail)">
              <button
                v-if="deleteConfirmId !== detail.id"
                class="text-xs text-n-slate-10 hover:text-red-500 flex items-center gap-1"
                @click="deleteConfirmId = detail.id"
              >
                <span class="i-lucide-trash-2" /> Excluir campanha
              </button>
              <button
                v-else
                class="text-xs px-2 py-1 rounded bg-red-500 text-white"
                @click="removeCampaign(detail)"
              >
                Confirmar exclusão
              </button>
            </template>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
