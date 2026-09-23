<script setup>
// 📅 AMBIENTE AGENDAMENTOS (item 200, 22/09): "um ambiente em que os
// agendamentos são registrados; o trabalho das meninas será de monitoramento".
// Uma tela, no kit "iMac G3 + vidro":
//   1. RESUMO do período: marcadas, remarcadas, canceladas e robô × equipe.
//   2. REGISTROS: cada consulta marcada, remarcada ou cancelada (pelo robô ou
//      pela equipe), agrupada por dia, com caixa da conversa, etiquetas do
//      paciente, coluna do CRM, quem marcou, e os atalhos: abrir a conversa,
//      abrir o Espaço do Paciente, ligar e ver na Agenda.
//   3. AJUSTES (só admin): o que acontece sozinho quando uma consulta é
//      confirmada na conversa (etiquetas + coluna do CRM).
// Dados: GET crm/appointments/feed (tasks do tipo 'consulta', a mesma Agenda).
// Atualiza sozinho a cada 60 s enquanto a tela está aberta.
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { frontendURL } from 'dashboard/helper/URLHelper';
import CrmAPI from 'dashboard/api/crm';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import CevicoCallButton from 'dashboard/components-next/cevico/calls/CevicoCallButton.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { inboxSolidFor } from 'dashboard/helper/cevicoInboxColors';
import { formatPhoneBR } from 'dashboard/helper/cevicoCallsFormat';

const router = useRouter();
const store = useStore();
const accountId = useMapGetter('getCurrentAccountId');
const crmSettings = useMapGetter('crm/getSettings');
const inboxes = useMapGetter('inboxes/getInboxes');

const pal = useCevicoPalette({
  scope: 'crm:agendamentos',
  blocks: [
    { id: 'resumo', label: 'Resumo', icon: 'i-lucide-gauge' },
    { id: 'lista', label: 'Registros', icon: 'i-lucide-list' },
  ],
});
const { cvVars, blockVars, blockFamily } = pal;

// ── cores FIXAS do tipo (não seguem a paleta: verde = marcou, âmbar =
//    remarcou, vermelho = cancelou, em qualquer tela) ──
const KIND_META = {
  agendada: {
    label: 'Marcada',
    verb: 'marcou às',
    color: '#059669',
    light: '#34d399',
    tone: 'cv-green',
    icon: 'i-lucide-calendar-plus',
  },
  reagendada: {
    label: 'Remarcada',
    verb: 'remarcou às',
    color: '#D97706',
    light: '#fbbf24',
    tone: 'cv-amber',
    icon: 'i-lucide-refresh-cw',
  },
  cancelada: {
    label: 'Cancelada',
    verb: 'cancelou às',
    color: '#DC2626',
    light: '#f87171',
    tone: 'cv-red',
    icon: 'i-lucide-calendar-x',
  },
};
const kindMeta = row => KIND_META[row.kind] || KIND_META.agendada;
const kindLabel = row => {
  const meta = kindMeta(row);
  if (row.kind === 'reagendada' && Number(row.rescheduled_count) > 1) {
    return `${meta.label} ×${row.rescheduled_count}`;
  }
  return meta.label;
};
const kindBarStyle = row => ({ background: kindMeta(row).color });

// ── período + filtros ──
const period = ref({ preset: 'last7', from: '', to: '' });
const MODES = [
  { key: 'registradas', label: 'Registradas no período' },
  { key: 'consultas', label: 'Consultas do período' },
];
const mode = ref('registradas');
const KINDS = [
  { key: '', label: 'Todas', tone: 'cv-blue', countKey: 'total' },
  {
    key: 'agendada',
    label: 'Marcadas',
    tone: 'cv-green',
    countKey: 'agendada',
  },
  {
    key: 'reagendada',
    label: 'Remarcadas',
    tone: 'cv-amber',
    countKey: 'reagendada',
  },
  {
    key: 'cancelada',
    label: 'Canceladas',
    tone: 'cv-red',
    countKey: 'cancelada',
  },
];
const kind = ref('');
const SOURCES = [
  { key: 'ia', label: 'Robô', icon: 'i-lucide-bot', countKey: 'ia' },
  { key: 'equipe', label: 'Equipe', icon: 'i-lucide-user', countKey: 'equipe' },
];
const source = ref('');
const UNITS = [
  { key: '', label: 'Todas as unidades' },
  { key: 'paulista', label: 'Av. Paulista' },
  { key: 'tatuape', label: 'Tatuapé' },
];
const unit = ref('');
const inboxId = ref('');
const q = ref('');
const inboxOptions = computed(() =>
  (inboxes.value || []).map(i => ({ id: i.id, name: i.name }))
);
const hasFilters = computed(
  () =>
    Boolean(kind.value || source.value || unit.value || inboxId.value) ||
    String(q.value || '').trim().length > 0
);
const clearFilters = () => {
  kind.value = '';
  source.value = '';
  unit.value = '';
  inboxId.value = '';
  q.value = '';
};

// tipo e origem filtram AQUI (na tela): o backend já devolve o período
// inteiro e assim as contagens dos chips continuam certas com o filtro ligado
const feedParams = () => {
  const p = period.value || {};
  const params = { preset: p.preset, mode: mode.value };
  if (p.preset === 'custom') Object.assign(params, { from: p.from, to: p.to });
  if (unit.value) params.unit = unit.value;
  if (inboxId.value) params.inbox_id = inboxId.value;
  const term = String(q.value || '').trim();
  if (term.length >= 2) params.q = term;
  return params;
};

// ── formulário dos AJUSTES (só admin): etiquetas + coluna do CRM ao
//    confirmar; fica aqui em cima porque o carregamento o preenche ──
const showSettings = ref(false);
const isSaving = ref(false);
const form = ref({
  labels_enabled: true,
  labels: { created: '', rescheduled: '', canceled: '' },
  stage_id: '',
  cancel_stage_id: '',
});
const syncForm = cfg => {
  if (!cfg) return;
  form.value = {
    labels_enabled: cfg.labels_enabled !== false,
    labels: {
      created: cfg.labels?.created || '',
      rescheduled: cfg.labels?.rescheduled || '',
      canceled: cfg.labels?.canceled || '',
    },
    stage_id: cfg.stage_id ? String(cfg.stage_id) : '',
    cancel_stage_id: cfg.cancel_stage_id ? String(cfg.cancel_stage_id) : '',
  };
};

// ── carregar ──
const feed = ref(null);
const isLoading = ref(true);
const isRefreshing = ref(false);
const loadError = ref('');
let fetchSeq = 0;
const fetchFeed = async ({ quiet = false } = {}) => {
  fetchSeq += 1;
  const seq = fetchSeq;
  if (quiet) isRefreshing.value = true;
  else isLoading.value = true;
  loadError.value = '';
  try {
    const { data } = await CrmAPI.appointmentsFeed(feedParams());
    if (seq !== fetchSeq) return; // chegou uma busca mais nova
    feed.value = data;
    if (!showSettings.value) syncForm(data.booking);
  } catch (error) {
    if (seq !== fetchSeq) return;
    loadError.value =
      error?.response?.data?.error ||
      'Não consegui carregar os agendamentos agora.';
  } finally {
    if (seq === fetchSeq) {
      isLoading.value = false;
      isRefreshing.value = false;
    }
  }
};

// carregando de novo com dados na tela (troca de modo, busca, minuto)
const busy = computed(() => isLoading.value || isRefreshing.value);
const rows = computed(() => feed.value?.rows || []);
const counts = computed(() => feed.value?.counts || {});
const booking = computed(() => feed.value?.booking || null);
const iaShare = computed(() => {
  const ia = Number(counts.value.ia || 0);
  const equipe = Number(counts.value.equipe || 0);
  if (!ia && !equipe) return 0;
  return Math.round((ia / (ia + equipe)) * 100);
});
const kpiGrad = i => blockFamily('resumo')[i % blockFamily('resumo').length];

// ── datas em pt-BR ──
const pad = n => String(n).padStart(2, '0');
const dateKey = ts => {
  const d = new Date(ts);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};
const WEEKDAYS = [
  'domingo',
  'segunda',
  'terça',
  'quarta',
  'quinta',
  'sexta',
  'sábado',
];
const WEEKDAYS_SHORT = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
const dayLabel = key => {
  const now = new Date();
  if (key === dateKey(now)) return 'Hoje';
  const y = new Date(now);
  y.setDate(y.getDate() - 1);
  if (key === dateKey(y)) return 'Ontem';
  const d = new Date(`${key}T12:00:00`);
  return `${WEEKDAYS[d.getDay()]}, ${pad(d.getDate())}/${pad(d.getMonth() + 1)}`;
};
const timeOf = ts => {
  if (!ts) return '';
  return new Date(ts).toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  });
};
// "seg 28/09 às 14:30 · Av. Paulista · Dr. Fulano · Avaliação"
const whenOf = row => {
  const parts = [];
  if (row.due_at) {
    const d = new Date(row.due_at);
    parts.push(
      `${WEEKDAYS_SHORT[d.getDay()]} ${pad(d.getDate())}/${pad(d.getMonth() + 1)} às ${timeOf(d)}`
    );
  } else {
    parts.push('sem data');
  }
  if (row.unit_label) parts.push(row.unit_label);
  if (row.doctor) parts.push(row.doctor);
  if (row.procedure) parts.push(row.procedure);
  return parts.join(' · ');
};
const phoneOf = row => formatPhoneBR(row.phone || row.contact?.phone || '');
// relógio à direita da linha: no modo registradas é a hora em que marcou/
// remarcou/cancelou; no modo consultas é a hora da consulta
const rowClock = row => {
  const ts = mode.value === 'consultas' ? row.due_at : row.event_at;
  return timeOf(ts) || '--:--';
};
const rowClockCaption = row =>
  mode.value === 'consultas' ? 'consulta' : kindMeta(row).verb;

// ── lista: filtro local + ordem + grupos por dia ──
const groupField = computed(() =>
  mode.value === 'consultas' ? 'due_at' : 'event_at'
);
const visibleRows = computed(() => {
  let list = rows.value;
  if (kind.value) list = list.filter(r => r.kind === kind.value);
  if (source.value) list = list.filter(r => r.source === source.value);
  const field = groupField.value;
  // registradas: o mais recente primeiro; consultas: na ordem do dia
  const dir = mode.value === 'consultas' ? 1 : -1;
  return [...list].sort(
    (a, b) =>
      (new Date(a[field] || 0).getTime() - new Date(b[field] || 0).getTime()) *
      dir
  );
});
const groups = computed(() => {
  const field = groupField.value;
  const map = new Map();
  visibleRows.value.forEach(r => {
    const key = r[field] ? dateKey(r[field]) : 'sem-data';
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(r);
  });
  return [...map.entries()].map(([key, list]) => ({
    key,
    label: key === 'sem-data' ? 'Sem data' : dayLabel(key),
    rows: list,
  }));
});

// etiquetas do paciente ∪ etiquetas da conversa, sem repetir
const MAX_LABELS = 6;
const labelsOf = row => {
  const all = new Set([
    ...(row.contact?.labels || []),
    ...(row.conversation?.labels || []),
  ]);
  return [...all];
};
const shownLabels = row => labelsOf(row).slice(0, MAX_LABELS);
const hiddenLabelCount = row => Math.max(0, labelsOf(row).length - MAX_LABELS);
const inboxChipStyle = row => ({
  background: inboxSolidFor(inboxes.value, row.conversation?.inbox_id),
  color: '#fff',
  borderColor: 'transparent',
});
const stageDotStyle = row => ({
  background: row.card?.stage_color || '#94a3b8',
});

// ── ações da linha ──
const callsOn = computed(() => Boolean(crmSettings.value?.calls?.enabled));
const openConversation = row => {
  if (!row.conversation?.display_id) return;
  router.push(
    frontendURL(
      `accounts/${accountId.value}/conversations/${row.conversation.display_id}`
    )
  );
};
const patientUrl = row =>
  frontendURL(`accounts/${accountId.value}/patient/${row.contact.id}`);
const agendaUrl = row =>
  frontendURL(`accounts/${accountId.value}/agenda`, {
    date: dateKey(row.due_at),
  });

// ── ajustes (só admin): abrir, mostrar a coluna efetiva e salvar ──
const toggleSettings = () => {
  if (!showSettings.value) syncForm(booking.value);
  showSettings.value = !showSettings.value;
};
const stageName = id => {
  const st = (booking.value?.stages || []).find(s => s.id === Number(id));
  return st ? `${st.name} (${st.pipeline})` : '';
};
const effectiveStageLabel = computed(() => {
  const name = stageName(booking.value?.effective_stage_id);
  return name ? `hoje o card vai para ${name}` : 'hoje o card não é movido';
});
const saveBooking = async () => {
  if (isSaving.value) return;
  isSaving.value = true;
  try {
    await CrmAPI.updateAgendaBooking({
      labels_enabled: form.value.labels_enabled,
      labels: { ...form.value.labels },
      stage_id: form.value.stage_id || null,
      cancel_stage_id: form.value.cancel_stage_id || null,
    });
    useAlert('Ajustes salvos.');
    showSettings.value = false;
    await fetchFeed({ quiet: true });
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui salvar os ajustes.');
  } finally {
    isSaving.value = false;
  }
};

// ── reações: filtros do backend refazem a busca; busca com pausa de 300 ms;
//    atualização silenciosa a cada 60 s ──
let searchTimer = null;
let refreshTimer = null;
watch([mode, unit, inboxId], () => fetchFeed());
watch(period, () => fetchFeed(), { deep: true });
watch(q, () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => fetchFeed({ quiet: true }), 300);
});

onMounted(() => {
  fetchFeed();
  if (!crmSettings.value) store.dispatch('crm/fetchSettings').catch(() => {});
  if (!(inboxes.value || []).length)
    store.dispatch('inboxes/get').catch(() => {});
  refreshTimer = setInterval(() => fetchFeed({ quiet: true }), 60000);
});
onBeforeUnmount(() => {
  clearInterval(refreshTimer);
  clearTimeout(searchTimer);
});
</script>

<template>
  <div
    class="cv-page flex flex-col h-full w-full overflow-y-auto bg-n-surface-1"
    :style="cvVars"
  >
    <div class="max-w-6xl mx-auto w-full p-4 sm:p-8">
      <CevicoHero
        :pal="pal"
        title="Agendamentos"
        subtitle="cada consulta marcada, remarcada ou cancelada, quem marcou e por qual caixa; abra a conversa, o Espaço do Paciente ou ligue daqui"
        icon="i-lucide-calendar-check"
      >
        <template #chips>
          <span v-if="feed" class="cv-glass-chip">
            <span class="i-lucide-calendar-check text-xs" />
            {{ counts.total || 0 }} no período
          </span>
          <span v-if="feed && busy" class="cv-glass-chip">
            <span class="i-lucide-loader-2 text-xs animate-spin" />
            atualizando
          </span>
        </template>
        <div class="flex items-center gap-2 flex-wrap">
          <PeriodRuler v-model="period" glass />
        </div>
      </CevicoHero>

      <SkeletonScreen v-if="isLoading && !feed" variant="dashboard" />

      <template v-else>
        <!-- erro -->
        <div
          v-if="loadError"
          class="cv-block cv-strip cv-red px-4 py-3.5 mb-8 flex items-center gap-3 flex-wrap"
        >
          <span class="cv-icon cv-icon-sm">
            <span class="i-lucide-triangle-alert text-xs" />
          </span>
          <p class="text-xs text-n-slate-11 flex-1 min-w-0">{{ loadError }}</p>
          <button class="cv-btn cv-btn-sm" @click="fetchFeed()">
            Tentar de novo
          </button>
        </div>

        <!-- ═══════════ RESUMO ═══════════ -->
        <section class="cv-block p-6 sm:p-9 mb-10" :style="blockVars('resumo')">
          <h2
            class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12 mb-1 flex items-center gap-2.5"
          >
            <div class="cv-icon">
              <span class="i-lucide-gauge text-base" />
            </div>
            Resumo
          </h2>
          <p class="text-xs text-n-slate-10 mb-6">
            {{
              mode === 'consultas'
                ? 'consultas cuja data cai no período escolhido'
                : 'o que aconteceu no período: marcações, remarcações e cancelamentos'
            }}
          </p>
          <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 sm:gap-4">
            <DashKpi
              label="Marcadas"
              :value="Number(counts.agendada || 0)"
              sub="consultas novas"
              :from="KIND_META.agendada.color"
              :to="KIND_META.agendada.light"
              glass
              compact
            />
            <DashKpi
              label="Remarcadas"
              :value="Number(counts.reagendada || 0)"
              sub="mudaram de dia ou hora"
              :from="KIND_META.reagendada.color"
              :to="KIND_META.reagendada.light"
              glass
              compact
            />
            <DashKpi
              label="Canceladas"
              :value="Number(counts.cancelada || 0)"
              sub="desmarcadas no período"
              :from="KIND_META.cancelada.color"
              :to="KIND_META.cancelada.light"
              glass
              compact
            />
            <DashKpi
              label="Pelo robô × pela equipe"
              :value="`${Number(counts.ia || 0)} × ${Number(counts.equipe || 0)}`"
              :sub="`${iaShare}% registrados pelo robô`"
              :grad="kpiGrad(1)"
              glass
              compact
            />
          </div>
        </section>

        <!-- ═══════════ REGISTROS ═══════════ -->
        <section class="cv-block p-6 sm:p-9 mb-10" :style="blockVars('lista')">
          <div class="flex items-center gap-2 flex-wrap mb-1">
            <h2
              class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12 flex items-center gap-2.5"
            >
              <div class="cv-icon">
                <span class="i-lucide-list text-base" />
              </div>
              Registros
              <span class="cv-chip">{{ visibleRows.length }}</span>
            </h2>
            <button
              v-if="booking?.can_edit"
              class="cv-btn cv-btn-ghost cv-btn-sm ml-auto"
              :class="showSettings ? 'cv-blue' : ''"
              title="O que acontece sozinho quando uma consulta é confirmada"
              @click="toggleSettings"
            >
              <span class="i-lucide-settings-2 text-xs" /> Ajustes
            </button>
          </div>
          <p class="text-xs text-n-slate-10 mb-5">
            agrupados por dia; cada linha mostra a caixa da conversa, as
            etiquetas do paciente, a coluna do CRM e quem marcou
          </p>

          <!-- AJUSTES (só admin) -->
          <div v-if="showSettings && booking" class="cv-pop p-4 sm:p-6 mb-6">
            <p class="text-sm font-semibold text-n-slate-12 mb-1">
              Ao confirmar uma consulta
            </p>
            <p class="text-xs text-n-slate-10 mb-4">
              Quando o robô ou a equipe confirma uma consulta na conversa, o
              sistema registra na Agenda, etiqueta o paciente e move o card
              sozinho.
            </p>

            <label class="flex items-center gap-2.5 mb-4 cursor-pointer">
              <button
                class="cv-switch"
                :class="form.labels_enabled ? 'cv-switch-on' : ''"
                role="switch"
                :aria-checked="form.labels_enabled"
                @click.prevent="form.labels_enabled = !form.labels_enabled"
              />
              <span class="text-sm text-n-slate-12">
                Etiquetar o paciente automaticamente
              </span>
            </label>

            <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-4">
              <label class="flex flex-col gap-1">
                <span class="cv-label">Etiqueta ao marcar</span>
                <input
                  v-model="form.labels.created"
                  type="text"
                  class="cv-input w-full"
                  placeholder="ex.: consulta_marcada"
                  :disabled="!form.labels_enabled"
                />
              </label>
              <label class="flex flex-col gap-1">
                <span class="cv-label">Etiqueta ao remarcar</span>
                <input
                  v-model="form.labels.rescheduled"
                  type="text"
                  class="cv-input w-full"
                  placeholder="ex.: consulta_remarcada"
                  :disabled="!form.labels_enabled"
                />
              </label>
              <label class="flex flex-col gap-1">
                <span class="cv-label">Etiqueta ao cancelar</span>
                <input
                  v-model="form.labels.canceled"
                  type="text"
                  class="cv-input w-full"
                  placeholder="ex.: consulta_cancelada"
                  :disabled="!form.labels_enabled"
                />
              </label>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-4">
              <label class="flex flex-col gap-1">
                <span class="cv-label">
                  Ao marcar ou remarcar, mover o card para
                </span>
                <select v-model="form.stage_id" class="cv-input w-full">
                  <option value="">
                    usar a coluna do Atendente de Agendamento
                  </option>
                  <option
                    v-for="st in booking.stages"
                    :key="st.id"
                    :value="String(st.id)"
                  >
                    {{ st.pipeline }} · {{ st.name }}
                  </option>
                </select>
                <span class="text-[11px] text-n-slate-9">
                  {{ effectiveStageLabel }}
                </span>
              </label>
              <label class="flex flex-col gap-1">
                <span class="cv-label">Ao cancelar, mover o card para</span>
                <select v-model="form.cancel_stage_id" class="cv-input w-full">
                  <option value="">não mover</option>
                  <option
                    v-for="st in booking.stages"
                    :key="st.id"
                    :value="String(st.id)"
                  >
                    {{ st.pipeline }} · {{ st.name }}
                  </option>
                </select>
              </label>
            </div>

            <div class="flex items-center justify-end gap-2">
              <button
                class="cv-btn cv-btn-ghost cv-btn-sm"
                :disabled="isSaving"
                @click="showSettings = false"
              >
                Cancelar
              </button>
              <button
                class="cv-btn cv-btn-sm cv-blue"
                :disabled="isSaving"
                @click="saveBooking"
              >
                <span
                  :class="
                    isSaving
                      ? 'i-lucide-loader-2 animate-spin'
                      : 'i-lucide-check'
                  "
                  class="text-xs"
                />
                {{ isSaving ? 'Salvando…' : 'Salvar' }}
              </button>
            </div>
          </div>

          <!-- filtros -->
          <div class="flex items-center gap-2 flex-wrap mb-3">
            <div
              class="cv-seg cv-seg-sm inline-flex items-center gap-0.5 max-w-full overflow-x-auto"
            >
              <button
                v-for="m in MODES"
                :key="m.key"
                class="cv-seg-item"
                :class="mode === m.key ? 'cv-seg-on' : ''"
                @click="mode = m.key"
              >
                {{ m.label }}
              </button>
            </div>
            <div class="flex items-center gap-1.5 flex-wrap">
              <button
                v-for="k in KINDS"
                :key="k.key"
                class="cv-chip"
                :class="[k.tone, kind === k.key ? 'cv-chip-on' : '']"
                @click="kind = k.key"
              >
                {{ k.label }}
                <span class="opacity-80 tabular-nums">{{
                  counts[k.countKey] || 0
                }}</span>
              </button>
            </div>
            <div class="flex items-center gap-1.5 flex-wrap">
              <button
                v-for="s in SOURCES"
                :key="s.key"
                class="cv-chip cv-blue"
                :class="source === s.key ? 'cv-chip-on' : ''"
                :title="
                  s.key === 'ia'
                    ? 'Só o que o robô marcou, remarcou ou cancelou'
                    : 'Só o que a equipe marcou, remarcou ou cancelou'
                "
                @click="source = source === s.key ? '' : s.key"
              >
                <span :class="s.icon" class="text-xs" />
                {{ s.label }}
                <span class="opacity-80 tabular-nums">{{
                  counts[s.countKey] || 0
                }}</span>
              </button>
            </div>
          </div>
          <div class="flex items-center gap-2 flex-wrap mb-6">
            <select v-model="unit" class="cv-input text-xs !w-auto">
              <option v-for="u in UNITS" :key="u.key" :value="u.key">
                {{ u.label }}
              </option>
            </select>
            <select
              v-if="inboxOptions.length > 1"
              v-model="inboxId"
              class="cv-input text-xs !w-auto"
            >
              <option value="">Qualquer caixa</option>
              <option
                v-for="i in inboxOptions"
                :key="i.id"
                :value="String(i.id)"
              >
                {{ i.name }}
              </option>
            </select>
            <input
              v-model="q"
              type="search"
              placeholder="Buscar por nome ou telefone…"
              class="cv-input text-xs w-full sm:!w-auto sm:min-w-[14rem]"
            />
            <button
              v-if="hasFilters"
              class="cv-btn cv-btn-ghost cv-btn-sm"
              @click="clearFilters"
            >
              Limpar
            </button>
            <button
              class="cv-btn cv-btn-sm sm:ml-auto"
              :disabled="busy"
              title="Buscar de novo agora (a tela também atualiza sozinha a cada minuto)"
              @click="fetchFeed({ quiet: true })"
            >
              <span
                :class="
                  busy
                    ? 'i-lucide-loader-2 animate-spin'
                    : 'i-lucide-refresh-cw'
                "
                class="text-xs"
              />
              Atualizar
            </button>
          </div>

          <!-- vazio -->
          <div
            v-if="!visibleRows.length"
            class="cv-sub p-8 sm:p-10 text-center"
          >
            <span class="cv-icon cv-icon-xl mx-auto mb-3">
              <span class="i-lucide-calendar-off text-lg" />
            </span>
            <p class="text-sm font-semibold text-n-slate-12">
              Nenhum agendamento neste período.
            </p>
            <p class="text-xs text-n-slate-9 mt-1">
              {{
                hasFilters
                  ? 'experimente limpar os filtros ou mudar o período'
                  : 'quando o robô ou a equipe confirmar uma consulta, ela aparece aqui'
              }}
            </p>
          </div>

          <!-- LISTA agrupada por dia -->
          <div v-else class="space-y-7">
            <div v-for="g in groups" :key="g.key">
              <h3
                class="text-sm font-bold text-n-slate-12 mb-2.5 flex items-center gap-2"
              >
                <span class="i-lucide-calendar-days text-sm" />
                {{ g.label }}
                <span class="cv-chip">{{ g.rows.length }}</span>
              </h3>
              <div class="space-y-2.5">
                <div
                  v-for="row in g.rows"
                  :key="row.id"
                  class="cv-row p-3 sm:p-4 flex flex-col sm:flex-row sm:items-center gap-3 sm:gap-4"
                >
                  <div class="flex gap-3 flex-1 min-w-0">
                    <!-- fio na cor do tipo -->
                    <span
                      class="w-1 self-stretch rounded-full flex-shrink-0"
                      :style="kindBarStyle(row)"
                    />
                    <Avatar
                      :name="row.name"
                      :src="row.contact?.thumbnail || ''"
                      :size="44"
                      rounded-full
                      gradient
                    />
                    <div class="min-w-0 flex-1">
                      <div class="flex items-center gap-2 flex-wrap">
                        <span class="cv-chip" :class="kindMeta(row).tone">
                          <span :class="kindMeta(row).icon" class="text-xs" />
                          {{ kindLabel(row) }}
                        </span>
                        <p
                          class="text-sm font-semibold text-n-slate-12 break-words"
                        >
                          {{ row.name }}
                        </p>
                        <span
                          v-if="phoneOf(row)"
                          class="text-xs text-n-slate-10 tabular-nums whitespace-nowrap"
                        >
                          {{ phoneOf(row) }}
                        </span>
                      </div>
                      <p
                        class="text-xs text-n-slate-10 mt-1.5 flex items-start gap-1.5"
                      >
                        <span
                          class="i-lucide-clock text-xs flex-shrink-0 mt-0.5"
                        />
                        <span class="break-words">{{ whenOf(row) }}</span>
                      </p>
                      <div class="flex items-center gap-1.5 flex-wrap mt-2">
                        <span
                          v-if="row.conversation"
                          class="cv-chip"
                          :style="inboxChipStyle(row)"
                          title="Caixa de entrada da conversa"
                        >
                          <span class="i-lucide-inbox text-xs" />
                          {{ row.conversation.inbox_name || 'Caixa' }}
                        </span>
                        <span
                          v-if="row.card?.stage"
                          class="cv-chip"
                          :title="`Coluna do CRM · ${row.card.pipeline || ''}`"
                        >
                          <span
                            class="w-1.5 h-1.5 rounded-full flex-shrink-0"
                            :style="stageDotStyle(row)"
                          />
                          {{ row.card.stage }}
                        </span>
                        <span
                          class="cv-chip"
                          :class="row.source === 'ia' ? 'cv-blue' : ''"
                          :title="
                            row.source === 'ia'
                              ? 'Registrado pelo robô'
                              : 'Registrado pela equipe'
                          "
                        >
                          <span
                            :class="
                              row.source === 'ia'
                                ? 'i-lucide-bot'
                                : 'i-lucide-user'
                            "
                            class="text-xs"
                          />
                          {{ row.source === 'ia' ? 'Robô' : 'Equipe' }}
                          <template v-if="row.assignee?.name">
                            · com {{ row.assignee.name }}
                          </template>
                        </span>
                        <span
                          v-for="lb in shownLabels(row)"
                          :key="lb"
                          class="cv-chip"
                          title="Etiqueta do paciente"
                        >
                          <span class="i-lucide-tag text-[10px]" />
                          {{ lb }}
                        </span>
                        <span
                          v-if="hiddenLabelCount(row)"
                          class="cv-chip"
                          :title="labelsOf(row).slice(MAX_LABELS).join(', ')"
                        >
                          +{{ hiddenLabelCount(row) }}
                        </span>
                      </div>
                    </div>
                  </div>

                  <!-- no celular fica embaixo do conteúdo; no desktop, à direita -->
                  <div
                    class="flex flex-col gap-2 sm:items-end flex-shrink-0 pl-4 sm:pl-0"
                  >
                    <!-- hora do acontecimento (registradas) / da consulta (consultas) -->
                    <div
                      class="flex items-baseline gap-1.5 sm:block sm:text-right"
                    >
                      <p
                        class="text-base font-bold tabular-nums text-n-slate-12 leading-none"
                      >
                        {{ rowClock(row) }}
                      </p>
                      <p class="text-[10px] text-n-slate-9 sm:mt-1">
                        {{ rowClockCaption(row) }}
                      </p>
                    </div>

                    <!-- ações redondas com rótulo (as mesmas do painel do paciente) -->
                    <div
                      class="cv-chat cv-side-actions !justify-start sm:!justify-end"
                    >
                      <button
                        class="cv-side-action cv-side-action-main"
                        :disabled="!row.conversation"
                        :title="
                          row.conversation ? 'Abrir a conversa' : 'sem conversa'
                        "
                        @click="openConversation(row)"
                      >
                        <span class="cv-side-action-btn">
                          <span class="i-lucide-message-circle" />
                        </span>
                        <span>Conversa</span>
                      </button>
                      <router-link
                        v-if="row.contact?.id"
                        class="cv-side-action"
                        :to="patientUrl(row)"
                        title="Abrir o Espaço do Paciente"
                      >
                        <span class="cv-side-action-btn">
                          <span class="i-lucide-user-round" />
                        </span>
                        <span>Paciente</span>
                      </router-link>
                      <button
                        v-else
                        class="cv-side-action"
                        disabled
                        title="sem cadastro"
                      >
                        <span class="cv-side-action-btn">
                          <span class="i-lucide-user-round" />
                        </span>
                        <span>Paciente</span>
                      </button>
                      <div
                        v-if="callsOn && row.contact?.id && row.phone"
                        class="cv-side-action"
                        title="Ligar"
                      >
                        <CevicoCallButton
                          :contact-id="row.contact.id"
                          :inbox-id="row.conversation?.inbox_id"
                          :phone="row.phone"
                          :ghost="false"
                          faded
                        />
                        <span>Ligar</span>
                      </div>
                      <router-link
                        v-if="row.due_at"
                        class="cv-side-action"
                        :to="agendaUrl(row)"
                        title="Ver o dia na Agenda"
                      >
                        <span class="cv-side-action-btn">
                          <span class="i-lucide-calendar-days" />
                        </span>
                        <span>Agenda</span>
                      </router-link>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>
      </template>
    </div>
  </div>
</template>
