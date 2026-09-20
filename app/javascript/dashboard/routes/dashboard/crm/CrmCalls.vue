<script setup>
// 📞 AMBIENTE CHAMADAS (item 176) — uma tela, no kit "iMac G3 + vidro":
//   1. AGORA (ao vivo, para todo mundo): tocando / em atendimento com
//      cronômetro, quem está na linha; perdidas de hoje sem retorno com
//      "Retornar" e "Marcar como retornada".
//   2. INDICADORES do período (PeriodRuler) comparados com o anterior:
//      KPIs, por dia (MiniBars), por hora (faixa de calor), por atendente,
//      por caixa, assistente virtual.
//   3. HISTÓRICO com 4 visualizações (Lista · Tabela · Por atendente ·
//      Linha do tempo), filtros, busca, detalhe e CSV.
// Dados: GET crm/calls/overview (+ GET crm/calls com filtros). Ao vivo:
// o store cevicoCalls sobe `liveTick` a cada evento cevico_call.* do cable.
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import HBars from 'dashboard/components-next/cevico/HBars.vue';
import MiniBars from 'dashboard/components-next/cevico/MiniBars.vue';
import ShareBar from 'dashboard/components-next/cevico/ShareBar.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { hexFromGrad } from 'dashboard/helper/cevicoPalettes';
import { useCevicoCallsStore } from 'dashboard/stores/cevicoCalls';
import CevicoCallsAPI from 'dashboard/api/cevicoCalls';
import CallLine from './components/calls/CallLine.vue';
import CallDetailModal from './components/calls/CallDetailModal.vue';
import {
  callIcon,
  formatTalkTime,
  formatClock,
  formatPhoneBR,
  shortDateTime,
  initialsOf,
  STATUS_LABELS,
  END_REASON_LABELS,
} from 'dashboard/helper/cevicoCallsFormat';

const router = useRouter();
const store = useStore();
const callsStore = useCevicoCallsStore();
const accountId = useMapGetter('getCurrentAccountId');
const crmSettings = useMapGetter('crm/getSettings');
const agents = useMapGetter('agents/getAgents');
const inboxes = useMapGetter('inboxes/getInboxes');

const pal = useCevicoPalette({
  scope: 'crm:chamadas',
  blocks: [
    { id: 'agora', label: 'Agora (ao vivo)', icon: 'i-lucide-radio' },
    { id: 'kpis', label: 'Indicadores', icon: 'i-lucide-gauge' },
    { id: 'dias', label: 'Por dia', icon: 'i-lucide-calendar-range' },
    { id: 'horas', label: 'Por hora', icon: 'i-lucide-clock' },
    { id: 'atendentes', label: 'Por atendente', icon: 'i-lucide-headset' },
    { id: 'historico', label: 'Histórico', icon: 'i-lucide-history' },
  ],
});
const { cvVars, blockVars, blockFamily } = pal;

// ── período + visão geral ──
const period = ref({ preset: 'today', from: '', to: '' });
const periodParams = () => {
  const p = period.value || {};
  const params = { preset: p.preset };
  if (p.preset === 'custom') {
    Object.assign(params, {
      from: p.from,
      to: p.to,
      since: p.from,
      until: p.to,
    });
  }
  return params;
};
const overview = ref(null);
const isLoading = ref(true);
const loadError = ref('');
// estado compartilhado entre as três partes da tela
const live = ref([]); // tocando / em atendimento agora
const history = ref([]); // página(s) carregada(s) do histórico
const historyTotal = ref(0);
const historyPage = ref(1);
const isLoadingHistory = ref(false);
const detail = ref(null); // chamada aberta no modal
const fetchOverview = async ({ quiet = false } = {}) => {
  if (!quiet) isLoading.value = true;
  loadError.value = '';
  try {
    const { data } = await CevicoCallsAPI.overview(periodParams());
    overview.value = data;
    live.value = data.live || [];
  } catch (error) {
    if (!quiet) overview.value = null;
    loadError.value =
      error?.response?.data?.error ||
      'Não consegui carregar as chamadas agora.';
  } finally {
    isLoading.value = false;
  }
};

const callsEnabled = computed(
  () => crmSettings.value?.calls?.enabled !== false
);
const canCall = computed(() => callsEnabled.value && !callsStore.active);

// ── AGORA: ao vivo ──
const now = ref(Date.now());
let ticker = null;
const liveSorted = computed(() =>
  [...live.value].sort((a, b) => {
    if (a.status !== b.status) return a.status === 'ringing' ? -1 : 1;
    return new Date(a.started_at) - new Date(b.started_at);
  })
);
const elapsed = c => {
  const from = c.answered_at || c.started_at;
  if (!from) return '00:00';
  return formatClock((now.value - new Date(from).getTime()) / 1000);
};
const liveName = c => c.contact?.name || c.display_name || 'Paciente';
const livePhone = c => formatPhoneBR(c.contact?.phone_number || c.wa_id || '');
const liveWho = c => {
  if (c.handled_by === 'ai') return 'assistente virtual';
  return c.user?.name || '';
};
const ringsForMe = c => callsStore.ringing.includes(c.id);
const isMine = c => callsStore.active === c.id;

const refreshLive = async () => {
  try {
    const { data } = await CevicoCallsAPI.live();
    live.value = data.calls || [];
  } catch {
    // a próxima batida do cable tenta de novo
  }
};
let liveTimer = null;
let softTimer = null;

// ── AGORA: perdidas de hoje sem retorno ──
const missedPending = computed(() => overview.value?.missed_pending || []);
const busyId = ref(null);
const permissionAsk = ref(null); // { call, message }
const returnCall = async c => {
  if (!c.contact?.id) {
    useAlert('Esta ligação não tem um paciente vinculado para retornar.');
    return;
  }
  busyId.value = c.id;
  const result = await callsStore.startOutbound(c.contact.id, c.inbox_id);
  busyId.value = null;
  if (result?.permission) {
    permissionAsk.value = { call: c, message: result.error };
  }
};
const askPermission = async () => {
  const c = permissionAsk.value?.call;
  if (!c) return;
  busyId.value = c.id;
  try {
    await CevicoCallsAPI.requestPermission(c.contact.id, c.inbox_id);
    useAlert('Pedido de permissão enviado ao paciente pelo WhatsApp.');
    permissionAsk.value = null;
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui pedir a permissão.');
  } finally {
    busyId.value = null;
  }
};
const replaceEverywhere = call => {
  live.value = live.value.map(x => (x.id === call.id ? call : x));
  history.value = history.value.map(x => (x.id === call.id ? call : x));
  if (overview.value) {
    overview.value = {
      ...overview.value,
      missed_pending: (overview.value.missed_pending || []).filter(
        x => x.id !== call.id || !call.returned_at
      ),
      recent: (overview.value.recent || []).map(x =>
        x.id === call.id ? call : x
      ),
    };
  }
  if (detail.value?.id === call.id) detail.value = call;
};
const markReturned = async c => {
  busyId.value = c.id;
  try {
    const { data } = await CevicoCallsAPI.markReturned(c.id);
    replaceEverywhere(data);
    useAlert('Marcada como retornada.');
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui marcar agora.');
  } finally {
    busyId.value = null;
  }
};

// ── INDICADORES ──
const kpis = computed(() => overview.value?.kpis || {});
const prev = computed(() => overview.value?.previous || {});
const kpiGrad = i => blockFamily('kpis')[i % blockFamily('kpis').length];
// "▲ 12% vs anterior" · "▼ 3%" · "= igual" · "sem base"
const delta = (key, { lowerIsBetter = false } = {}) => {
  const cur = Number(kpis.value[key] || 0);
  const before = Number(prev.value[key] || 0);
  if (!before && !cur) return 'sem ligações nos dois períodos';
  if (!before) return `${cur} agora · 0 no período anterior`;
  const pct = Math.round(((cur - before) / before) * 100);
  if (pct === 0) return 'igual ao período anterior';
  const up = pct > 0;
  const good = lowerIsBetter ? !up : up;
  return `${up ? '▲' : '▼'} ${Math.abs(pct)}% vs anterior ${good ? '👍' : ''}`.trim();
};
const deltaPoints = key => {
  const cur = Number(kpis.value[key] || 0);
  const before = Number(prev.value[key] || 0);
  if (!Number(prev.value.received || 0)) return 'sem base no período anterior';
  const diff = Math.round(cur - before);
  if (diff === 0) return 'igual ao período anterior';
  return `${diff > 0 ? '▲' : '▼'} ${Math.abs(diff)} pontos vs anterior`;
};
const hasAi = computed(
  () =>
    Number(kpis.value.ai_answered || 0) + Number(kpis.value.ai_outbound || 0) >
    0
);

// por dia (MiniBars): recebidas; rótulos curtos; período anterior não entra
// (dias diferentes) — a comparação fica nos KPIs
const WEEKDAYS = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
const byDay = computed(() => overview.value?.by_day || []);
// o MiniBars pinta SVG: precisa de um hex, não do degradê da família
const dayColor = computed(
  () =>
    hexFromGrad(blockFamily('dias')[1] || blockFamily('dias')[0]) || '#0F5FA6'
);
const dayLabels = computed(() =>
  byDay.value.map(d => {
    const dt = new Date(`${d.date}T12:00:00`);
    if (byDay.value.length <= 14) {
      return `${WEEKDAYS[dt.getDay()]} ${String(dt.getDate()).padStart(2, '0')}`;
    }
    return `${String(dt.getDate()).padStart(2, '0')}/${String(dt.getMonth() + 1).padStart(2, '0')}`;
  })
);
const dayReceived = computed(() =>
  byDay.value.map(d => Number(d.received || 0))
);
const dayAnswered = computed(() =>
  byDay.value.map(d => Number(d.answered || 0))
);
const dayOutbound = computed(() =>
  byDay.value.map(d => Number(d.outbound || 0))
);
const hasOutboundDays = computed(() => dayOutbound.value.some(v => v > 0));
const bestDay = computed(() => {
  const max = Math.max(0, ...dayReceived.value);
  if (!max) return null;
  const i = dayReceived.value.indexOf(max);
  return { label: dayLabels.value[i], value: max };
});

// por hora (faixa de calor 24 colunas)
const hours = computed(() => {
  const list = Array.isArray(overview.value?.by_hour)
    ? overview.value.by_hour
    : [];
  return Array.from({ length: 24 }, (_x, h) => Number(list[h] || 0));
});
const hourMax = computed(() => Math.max(1, ...hours.value));
const hourAlpha = v => (v ? 0.14 + 0.78 * (v / hourMax.value) : 0.05);
const peakHour = computed(() => {
  const max = Math.max(...hours.value);
  return max ? hours.value.indexOf(max) : null;
});

// por atendente / por caixa / motivos / IA
const agentRows = computed(() =>
  (overview.value?.by_agent || []).map(a => ({
    key: a.user_id,
    label: a.name || 'Sem nome',
    sub: `${formatTalkTime(a.total_talk_seconds)} em ligação · média ${formatTalkTime(a.avg_talk_seconds)}`,
    values: [
      Number(a.answered || 0) - Number(a.outbound || 0),
      Number(a.outbound || 0),
    ],
  }))
);
const agentSeries = computed(() => [
  { label: 'atendidas', color: blockFamily('atendentes')[1] },
  {
    label: 'feitas',
    color: blockFamily('atendentes')[3] || blockFamily('atendentes')[0],
  },
]);
const inboxRows = computed(() =>
  (overview.value?.by_inbox || []).map(i => ({
    key: i.inbox_id,
    label: i.name,
    values: [Number(i.inbound || 0), Number(i.outbound || 0)],
  }))
);
const inboxSeries = computed(() => [
  { label: 'recebidas', color: blockFamily('kpis')[1] },
  { label: 'feitas', color: blockFamily('kpis')[3] || blockFamily('kpis')[0] },
]);
const reasonItems = computed(() =>
  (overview.value?.by_reason || []).map(r => ({
    label: END_REASON_LABELS[r.reason] || r.reason || 'Sem motivo',
    value: Number(r.count || 0),
  }))
);
const outcomeItems = computed(() =>
  (overview.value?.by_outcome || []).map(o => ({
    label: o.label || o.outcome || 'Sem resultado',
    value: Number(o.count || 0),
  }))
);

// ── HISTÓRICO ──
const VIEWS = [
  { key: 'list', label: 'Lista', icon: 'i-lucide-list' },
  { key: 'table', label: 'Tabela', icon: 'i-lucide-table' },
  { key: 'agents', label: 'Por atendente', icon: 'i-lucide-headset' },
  {
    key: 'timeline',
    label: 'Linha do tempo',
    icon: 'i-lucide-git-commit-vertical',
  },
];
const view = ref(localStorage.getItem('cevico_calls_view') || 'list');
watch(view, v => localStorage.setItem('cevico_calls_view', v));

const DIRECTIONS = [
  { key: '', label: 'Todas' },
  { key: 'inbound', label: 'Recebidas' },
  { key: 'outbound', label: 'Feitas' },
];
const STATUS_OPTIONS = [
  { key: '', label: 'Qualquer situação' },
  { key: 'completed', label: 'Atendidas' },
  { key: 'not_answered', label: 'Não atendidas (todas)' },
  { key: 'missed', label: 'Perdidas' },
  { key: 'rejected', label: 'Recusadas' },
  { key: 'failed', label: 'Com falha' },
  { key: 'canceled', label: 'Canceladas' },
];
const filters = ref({
  direction: '',
  status: '',
  user_id: '',
  inbox_id: '',
  handled_by: '',
  q: '',
});
const hasFilters = computed(() =>
  Object.values(filters.value).some(v => String(v || '').length)
);
const clearFilters = () => {
  filters.value = {
    direction: '',
    status: '',
    user_id: '',
    inbox_id: '',
    handled_by: '',
    q: '',
  };
};
const historyParams = () => {
  const f = filters.value;
  const params = { ...periodParams(), limit: 50 };
  Object.entries(f).forEach(([k, v]) => {
    if (String(v || '').length) params[k] = v;
  });
  if (params.q && params.q.length < 2) delete params.q;
  return params;
};
const hasMore = computed(() => history.value.length < historyTotal.value);
const fetchHistory = async ({ reset = false, quiet = false } = {}) => {
  if (reset) historyPage.value = 1;
  if (!quiet) isLoadingHistory.value = true;
  try {
    const { data } = await CevicoCallsAPI.list({
      ...historyParams(),
      page: historyPage.value,
    });
    history.value =
      reset || historyPage.value === 1
        ? data.calls
        : [...history.value, ...data.calls];
    historyTotal.value = data.meta?.total || 0;
  } catch {
    if (!quiet) useAlert('Não consegui carregar o histórico.');
  } finally {
    isLoadingHistory.value = false;
  }
};
const loadMore = () => {
  historyPage.value += 1;
  fetchHistory();
};
let searchTimer = null;
watch(
  () => ({ ...filters.value, q: undefined }),
  () => fetchHistory({ reset: true }),
  { deep: true }
);
watch(
  () => filters.value.q,
  () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => fetchHistory({ reset: true }), 350);
  }
);
watch(
  period,
  () => {
    fetchOverview();
    fetchHistory({ reset: true });
  },
  { deep: true }
);

const multiInbox = computed(() => (overview.value?.by_inbox || []).length > 1);
const agentOptions = computed(() =>
  (agents.value || []).map(a => ({
    id: a.id,
    name: a.available_name || a.name,
  }))
);
const inboxOptions = computed(() =>
  (inboxes.value || []).map(i => ({ id: i.id, name: i.name }))
);

// Por atendente (visão): totais do período + clique filtra a lista
const pickAgent = row => {
  filters.value.user_id = String(row.key);
  view.value = 'list';
};

// Linha do tempo: dia → hora → chamadas
const timelineDays = computed(() => {
  const days = new Map();
  history.value.forEach(c => {
    const d = new Date(c.started_at);
    const dayKey = d.toLocaleDateString('pt-BR', {
      weekday: 'long',
      day: '2-digit',
      month: '2-digit',
    });
    const hourKey = `${String(d.getHours()).padStart(2, '0')}h`;
    if (!days.has(dayKey)) days.set(dayKey, new Map());
    const hoursMap = days.get(dayKey);
    if (!hoursMap.has(hourKey)) hoursMap.set(hourKey, []);
    hoursMap.get(hourKey).push(c);
  });
  return [...days.entries()].map(([day, hoursMap]) => ({
    day: day.charAt(0).toUpperCase() + day.slice(1),
    hours: [...hoursMap.entries()].map(([hour, calls]) => ({ hour, calls })),
  }));
});

// CSV
const isExporting = ref(false);
const exportCsv = async () => {
  isExporting.value = true;
  try {
    const { data } = await CevicoCallsAPI.exportCsv(historyParams());
    const url = URL.createObjectURL(
      new Blob([data], { type: 'text/csv;charset=utf-8' })
    );
    const a = document.createElement('a');
    a.href = url;
    a.download = `chamadas-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  } catch {
    useAlert('Não consegui gerar o CSV.');
  } finally {
    isExporting.value = false;
  }
};

// ── detalhe / navegação ──
const playing = ref(null);
// abre com o que já temos e completa com o detalhe (linha do tempo/transcrição)
const openDetail = async c => {
  detail.value = c;
  try {
    const { data } = await CevicoCallsAPI.show(c.id);
    if (detail.value?.id === c.id) detail.value = { ...c, ...data };
  } catch {
    // fica com o resumo da lista
  }
};
const openConversation = c => {
  if (!c.conversation_id) return;
  router.push(
    `/app/accounts/${accountId.value}/conversations/${c.conversation_id}`
  );
};
const openContact = c => {
  if (!c.contact?.id) return;
  router.push(`/app/accounts/${accountId.value}/contacts/${c.contact.id}`);
};
const transcribe = async c => {
  try {
    const { data } = await CevicoCallsAPI.transcribe(c.id);
    replaceEverywhere(data);
    useAlert('Transcrição pedida — o resumo aparece em alguns minutos.');
  } catch (error) {
    useAlert(
      error?.response?.data?.error || 'Não consegui pedir a transcrição.'
    );
  }
};
const togglePlay = c => {
  playing.value = playing.value === c.id ? null : c.id;
};

const statusChip = status => {
  if (['completed', 'accepted'].includes(status)) return 'cv-green';
  if (status === 'missed') return 'cv-red';
  if (['rejected', 'failed', 'canceled'].includes(status)) return 'cv-amber';
  return '';
};
const rowName = c => c.contact?.name || c.display_name || 'Paciente';
const rowPhone = c => formatPhoneBR(c.contact?.phone_number || c.wa_id || '');

// cada evento cevico_call.* do cable: faixa "Agora" na hora, números e
// histórico de leve logo depois (uma chamada terminou → KPIs mudam)
watch(
  () => callsStore.liveTick,
  () => {
    clearTimeout(liveTimer);
    liveTimer = setTimeout(refreshLive, 400);
    // números/histórico mudam quando uma chamada termina: recarrega de leve
    clearTimeout(softTimer);
    softTimer = setTimeout(() => {
      fetchOverview({ quiet: true });
      fetchHistory({ reset: true, quiet: true });
    }, 2500);
  }
);

onMounted(() => {
  fetchOverview();
  fetchHistory({ reset: true });
  if (!crmSettings.value) store.dispatch('crm/fetchSettings').catch(() => {});
  if (!(agents.value || []).length)
    store.dispatch('agents/get').catch(() => {});
  ticker = setInterval(() => {
    now.value = Date.now();
  }, 1000);
});
onBeforeUnmount(() => {
  clearInterval(ticker);
  clearTimeout(liveTimer);
  clearTimeout(softTimer);
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
        title="Chamadas"
        subtitle="ligações de WhatsApp da clínica — o que está acontecendo agora, os números do período e o histórico completo"
        icon="i-lucide-phone-call"
      >
        <template #chips>
          <span v-if="liveSorted.length" class="cv-glass-chip">
            <span
              class="w-1.5 h-1.5 rounded-full bg-emerald-300 animate-pulse"
            />
            {{ liveSorted.length }} na linha agora
          </span>
        </template>
      </CevicoHero>

      <!-- módulo desligado -->
      <div
        v-if="!callsEnabled"
        class="cv-block cv-strip px-4 py-3.5 mb-8 flex items-center gap-3 flex-wrap"
        :style="blockVars('agora')"
      >
        <span class="cv-icon cv-icon-sm"
          ><span class="i-lucide-info text-xs"
        /></span>
        <p class="text-xs text-n-slate-11 flex-1 min-w-0">
          As ligações pelo WhatsApp ainda não estão ativadas nesta conta — o
          histórico continua aqui, mas ninguém recebe ou faz chamadas.
        </p>
        <router-link
          :to="`/app/accounts/${accountId}/settings/integrations/calls`"
          class="cv-btn cv-btn-sm"
        >
          Ativar em Integrações →
        </router-link>
      </div>

      <!-- ═══════════ AGORA ═══════════ -->
      <section class="cv-block p-6 sm:p-9 mb-10" :style="blockVars('agora')">
        <h2
          class="text-xl sm:text-2xl font-bold text-n-slate-12 mb-1 flex items-center gap-2.5"
        >
          <span class="cv-icon"><span class="i-lucide-radio text-base" /></span>
          Agora
          <span v-if="liveSorted.length" class="cv-chip cv-green ml-1">
            <span
              class="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse mr-1"
            />
            ao vivo
          </span>
        </h2>
        <p class="text-xs text-n-slate-10 mb-5">
          todo mundo vê as chamadas em andamento — quem está na linha, com quem
          e há quanto tempo
        </p>

        <div v-if="!liveSorted.length" class="cv-sub p-5 text-center mb-6">
          <p class="text-sm text-n-slate-11">Nenhuma chamada em andamento.</p>
          <p class="text-[11px] text-n-slate-9 mt-1">
            quando o telefone tocar, aparece aqui na hora — em todas as telas
          </p>
        </div>
        <div v-else class="grid grid-cols-1 md:grid-cols-2 gap-3 mb-6">
          <div
            v-for="c in liveSorted"
            :key="c.id"
            class="cv-sub p-4 flex items-center gap-3"
            :class="c.status === 'ringing' ? 'cv-btn-pulse' : ''"
          >
            <img
              v-if="c.contact?.thumbnail"
              :src="c.contact.thumbnail"
              alt=""
              class="w-11 h-11 rounded-full object-cover flex-shrink-0"
            />
            <span
              v-else
              class="w-11 h-11 rounded-full flex items-center justify-center text-xs font-bold text-white flex-shrink-0"
              style="background: var(--cv-grad-2)"
            >
              {{ initialsOf(liveName(c)) }}
            </span>
            <div class="min-w-0 flex-1">
              <p
                class="text-sm font-semibold text-n-slate-12 truncate flex items-center gap-1.5"
              >
                <span
                  :class="[callIcon(c).icon, callIcon(c).tone]"
                  class="text-sm"
                />
                {{ liveName(c) }}
              </p>
              <p class="text-[11px] text-n-slate-10 truncate">
                {{ livePhone(c) }}
                <template v-if="c.status === 'ringing'">
                  ·
                  {{
                    c.direction === 'outbound'
                      ? 'chamando o paciente…'
                      : 'tocando…'
                  }}
                </template>
                <template v-else-if="liveWho(c)">
                  · com {{ liveWho(c) }}</template
                >
                <template v-else> · em atendimento</template>
              </p>
            </div>
            <div class="text-right flex-shrink-0">
              <p
                class="text-lg font-bold tabular-nums text-n-slate-12 leading-none"
              >
                {{ elapsed(c) }}
              </p>
              <p class="text-[10px] text-n-slate-9 mt-1">
                {{ c.status === 'ringing' ? 'tocando' : 'na linha' }}
              </p>
            </div>
            <div class="flex items-center gap-1 flex-shrink-0">
              <template v-if="ringsForMe(c)">
                <button
                  class="cv-btn cv-btn-sm"
                  :disabled="callsStore.isBusy"
                  @click="callsStore.accept(c.id)"
                >
                  <span class="i-lucide-phone text-xs" /> Atender
                </button>
                <button
                  class="cv-btn cv-btn-danger cv-iconbtn"
                  title="Recusar"
                  @click="callsStore.reject(c.id)"
                >
                  <span class="i-lucide-phone-off text-xs" />
                </button>
              </template>
              <template v-else-if="isMine(c)">
                <button
                  class="cv-btn cv-btn-ghost cv-iconbtn"
                  :title="callsStore.isMuted ? 'Ativar microfone' : 'Silenciar'"
                  @click="callsStore.toggleMute()"
                >
                  <span
                    :class="
                      callsStore.isMuted ? 'i-lucide-mic-off' : 'i-lucide-mic'
                    "
                    class="text-xs"
                  />
                </button>
                <button
                  class="cv-btn cv-btn-danger cv-iconbtn"
                  title="Desligar"
                  :disabled="callsStore.isBusy"
                  @click="callsStore.hangup(c.id)"
                >
                  <span class="i-lucide-phone-off text-xs" />
                </button>
              </template>
              <button
                v-if="c.conversation_id"
                class="cv-btn cv-btn-ghost cv-iconbtn"
                title="Abrir a conversa"
                @click="openConversation(c)"
              >
                <span class="i-lucide-message-circle text-xs" />
              </button>
            </div>
          </div>
        </div>

        <!-- perdidas de hoje sem retorno -->
        <div class="flex items-center gap-2 mb-2">
          <h3 class="text-sm font-bold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-phone-missed text-red-500 text-sm" />
            Perdidas de hoje sem retorno
          </h3>
          <span class="cv-chip" :class="missedPending.length ? 'cv-red' : ''">
            {{ missedPending.length }}
          </span>
        </div>
        <p v-if="!missedPending.length" class="text-xs text-n-slate-9">
          Tudo retornado — nenhuma ligação perdida esperando.
        </p>
        <div v-else class="space-y-1.5">
          <div
            v-for="c in missedPending"
            :key="c.id"
            class="cv-row px-3 py-2 flex items-center gap-3 flex-wrap"
          >
            <span
              class="w-8 h-8 rounded-full flex items-center justify-center text-[11px] font-bold text-white flex-shrink-0"
              style="background: linear-gradient(135deg, #991b1b, #f87171)"
            >
              {{ initialsOf(rowName(c)) }}
            </span>
            <div class="min-w-0 flex-1 cursor-pointer" @click="openDetail(c)">
              <p class="text-sm font-semibold text-n-slate-12 truncate">
                {{ rowName(c) }}
                <span class="text-n-slate-9 font-normal text-xs">{{
                  rowPhone(c)
                }}</span>
              </p>
              <p class="text-[11px] text-n-slate-10">
                {{ shortDateTime(c.started_at) }} ·
                {{ END_REASON_LABELS[c.end_reason] || 'ninguém atendeu' }}
              </p>
            </div>
            <div class="flex items-center gap-1 flex-shrink-0">
              <button
                v-if="canCall && c.contact?.id"
                class="cv-btn cv-btn-sm"
                :disabled="busyId === c.id || callsStore.isBusy"
                @click="returnCall(c)"
              >
                <span class="i-lucide-phone-outgoing text-xs" /> Retornar
              </button>
              <button
                class="cv-btn cv-btn-ghost cv-btn-sm"
                title="Já retornei por fora (ligação ou mensagem)"
                :disabled="busyId === c.id"
                @click="markReturned(c)"
              >
                <span class="i-lucide-check text-xs" /> Retornada
              </button>
              <button
                v-if="c.conversation_id"
                class="cv-btn cv-btn-ghost cv-iconbtn"
                title="Abrir a conversa"
                @click="openConversation(c)"
              >
                <span class="i-lucide-message-circle text-xs" />
              </button>
            </div>
          </div>
        </div>

        <!-- permissão da Meta para ligar -->
        <div
          v-if="permissionAsk"
          class="cv-strip px-4 py-3 mt-4 flex items-center gap-3 flex-wrap"
        >
          <span class="cv-icon cv-icon-sm"
            ><span class="i-lucide-shield-question text-xs"
          /></span>
          <p class="text-xs text-n-slate-11 flex-1 min-w-0">
            {{
              permissionAsk.message ||
              'A Meta exige a permissão do paciente antes de ligarmos.'
            }}
          </p>
          <button
            class="cv-btn cv-btn-sm"
            :disabled="busyId === permissionAsk.call.id"
            @click="askPermission"
          >
            Pedir permissão pelo WhatsApp
          </button>
          <button
            class="cv-btn cv-btn-ghost cv-btn-sm"
            @click="permissionAsk = null"
          >
            Fechar
          </button>
        </div>
      </section>

      <!-- ═══════════ INDICADORES ═══════════ -->
      <div class="flex items-center gap-3 flex-wrap mb-5">
        <h2
          class="text-xl sm:text-2xl font-bold text-n-slate-12 flex items-center gap-2.5"
        >
          <span class="cv-icon"><span class="i-lucide-gauge text-base" /></span>
          Indicadores
        </h2>
        <PeriodRuler v-model="period" glass class="ml-auto" />
      </div>

      <div v-if="isLoading" class="flex justify-center py-16">
        <Spinner :size="32" class="text-n-brand" />
      </div>
      <div
        v-else-if="loadError"
        class="cv-block p-6 text-center mb-10"
        :style="blockVars('kpis')"
      >
        <p class="text-sm text-n-slate-11">{{ loadError }}</p>
        <button class="cv-btn cv-btn-sm mt-3" @click="fetchOverview()">
          Tentar de novo
        </button>
      </div>
      <template v-else-if="overview">
        <div
          class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-6"
          :style="blockVars('kpis')"
        >
          <DashKpi
            glass
            label="Recebidas"
            :value="Number(kpis.received || 0)"
            :sub="delta('received')"
            :grad="kpiGrad(0)"
          />
          <DashKpi
            glass
            label="Atendidas"
            :value="Number(kpis.answered || 0)"
            :sub="delta('answered')"
            :grad="kpiGrad(1)"
          />
          <DashKpi
            glass
            label="Perdidas"
            :value="Number(kpis.missed || 0)"
            :sub="delta('missed', { lowerIsBetter: true })"
            :grad="kpiGrad(2)"
          />
          <DashKpi
            glass
            label="Taxa de atendimento"
            :value="`${Math.round(Number(kpis.answer_rate || 0))}%`"
            :sub="deltaPoints('answer_rate')"
            :grad="kpiGrad(3)"
          />
          <DashKpi
            glass
            compact
            label="Feitas pela clínica"
            :value="Number(kpis.outbound || 0)"
            :sub="`${kpis.outbound_answered || 0} atendida(s) pelo paciente`"
          />
          <DashKpi
            glass
            compact
            label="Espera média"
            :value="formatTalkTime(kpis.avg_wait_seconds)"
            :sub="delta('avg_wait_seconds', { lowerIsBetter: true })"
          />
          <DashKpi
            glass
            compact
            label="Conversa média"
            :value="formatTalkTime(kpis.avg_talk_seconds)"
            :sub="delta('avg_talk_seconds')"
          />
          <DashKpi
            glass
            compact
            label="Tempo total"
            :value="formatTalkTime(kpis.total_talk_seconds)"
            sub="em ligação no período"
          />
          <template v-if="hasAi">
            <DashKpi
              glass
              compact
              label="Atendidas pela IA"
              :value="Number(kpis.ai_answered || 0)"
              sub="a assistente virtual atendeu"
              :grad="kpiGrad(4)"
            />
            <DashKpi
              glass
              compact
              label="Feitas pela IA"
              :value="Number(kpis.ai_outbound || 0)"
              sub="campanhas de ligação"
              :grad="kpiGrad(5)"
            />
          </template>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
          <!-- por dia -->
          <div class="cv-block p-6 sm:p-9" :style="blockVars('dias')">
            <h3
              class="text-base font-bold text-n-slate-12 mb-1 flex items-center gap-2"
            >
              <span class="cv-icon"
                ><span class="i-lucide-calendar-range text-base"
              /></span>
              Por dia
              <span v-if="bestDay" class="cv-chip ml-auto">
                pico {{ bestDay.label }} · {{ bestDay.value }}
              </span>
            </h3>
            <p class="text-[11px] text-n-slate-10 mb-3">
              recebidas por dia · linha tracejada = atendidas
            </p>
            <MiniBars
              :values="dayReceived"
              :labels="dayLabels"
              :prev-values="dayAnswered"
              :color="dayColor"
              :height="120"
            />
            <template v-if="hasOutboundDays">
              <p class="text-[11px] text-n-slate-10 mt-4 mb-1">
                feitas pela clínica por dia
              </p>
              <MiniBars
                :values="dayOutbound"
                :labels="dayLabels"
                :color="dayColor"
                :height="56"
              />
            </template>
          </div>

          <!-- por hora -->
          <div class="cv-block p-6 sm:p-9" :style="blockVars('horas')">
            <h3
              class="text-base font-bold text-n-slate-12 mb-1 flex items-center gap-2"
            >
              <span class="cv-icon"
                ><span class="i-lucide-clock text-base"
              /></span>
              Por hora do dia
              <span v-if="peakHour !== null" class="cv-chip ml-auto">
                pico às {{ peakHour }}h
              </span>
            </h3>
            <p class="text-[11px] text-n-slate-10 mb-3">
              recebidas por hora — quanto mais escuro, mais chamadas
            </p>
            <div
              class="grid gap-1"
              style="grid-template-columns: repeat(24, minmax(0, 1fr))"
            >
              <div
                v-for="(v, h) in hours"
                :key="h"
                class="h-10 rounded-md transition-colors"
                :style="{ background: `rgb(var(--cv-rgb) / ${hourAlpha(v)})` }"
                :title="`${h}h · ${v} chamada(s)`"
              />
            </div>
            <div
              class="grid gap-1 mt-1"
              style="grid-template-columns: repeat(24, minmax(0, 1fr))"
            >
              <span
                v-for="h in 24"
                :key="'l' + h"
                class="text-[9px] text-n-slate-9 text-center"
              >
                {{ (h - 1) % 3 === 0 ? `${h - 1}h` : '' }}
              </span>
            </div>
            <div class="mt-5">
              <p class="cv-label mb-2">Como terminaram</p>
              <ShareBar :items="reasonItems" :family="blockFamily('horas')" />
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-10">
          <div class="cv-block p-6 sm:p-9" :style="blockVars('atendentes')">
            <h3
              class="text-base font-bold text-n-slate-12 mb-4 flex items-center gap-2"
            >
              <span class="cv-icon"
                ><span class="i-lucide-headset text-base"
              /></span>
              Por atendente
            </h3>
            <HBars
              :rows="agentRows"
              :series="agentSeries"
              empty-text="Nenhuma chamada atendida no período."
            />
          </div>
          <div class="cv-block p-6 sm:p-9" :style="blockVars('atendentes')">
            <template v-if="multiInbox">
              <h3
                class="text-base font-bold text-n-slate-12 mb-4 flex items-center gap-2"
              >
                <span class="cv-icon"
                  ><span class="i-lucide-inbox text-base"
                /></span>
                Por caixa
              </h3>
              <HBars
                :rows="inboxRows"
                :series="inboxSeries"
                empty-text="Nenhuma chamada no período."
              />
            </template>
            <template v-else-if="hasAi">
              <h3
                class="text-base font-bold text-n-slate-12 mb-4 flex items-center gap-2"
              >
                <span class="cv-icon"
                  ><span class="i-lucide-bot text-base"
                /></span>
                Resultados da assistente virtual
              </h3>
              <p
                v-if="!outcomeItems.length"
                class="text-xs text-n-slate-9 py-3"
              >
                Sem resultados no período.
              </p>
              <ShareBar
                v-else
                :items="outcomeItems"
                :family="blockFamily('atendentes')"
              />
            </template>
            <template v-else>
              <h3
                class="text-base font-bold text-n-slate-12 mb-4 flex items-center gap-2"
              >
                <span class="cv-icon"
                  ><span class="i-lucide-lightbulb text-base"
                /></span>
                Leitura rápida
              </h3>
              <ul class="text-sm text-n-slate-11 space-y-2 leading-relaxed">
                <li v-if="Number(kpis.received)">
                  De cada 10 ligações recebidas,
                  <b>{{ Math.round(Number(kpis.answer_rate || 0) / 10) }}</b>
                  foram atendidas.
                </li>
                <li v-if="peakHour !== null">
                  O horário com mais chamadas é <b>{{ peakHour }}h</b> — vale
                  ter alguém na linha.
                </li>
                <li v-if="Number(kpis.avg_wait_seconds)">
                  O paciente espera em média
                  <b>{{ formatTalkTime(kpis.avg_wait_seconds) }}</b> até alguém
                  atender.
                </li>
                <li v-if="!Number(kpis.received)">
                  Ainda sem ligações recebidas neste período.
                </li>
              </ul>
            </template>
          </div>
        </div>
      </template>

      <!-- ═══════════ HISTÓRICO ═══════════ -->
      <section
        class="cv-block p-6 sm:p-9 mb-10"
        :style="blockVars('historico')"
      >
        <div class="flex items-center gap-3 flex-wrap mb-4">
          <h2
            class="text-xl sm:text-2xl font-bold text-n-slate-12 flex items-center gap-2.5"
          >
            <span class="cv-icon"
              ><span class="i-lucide-history text-base"
            /></span>
            Histórico
            <span class="cv-chip">{{ historyTotal }}</span>
          </h2>
          <div
            class="cv-seg inline-flex items-center gap-0.5 ml-auto overflow-x-auto"
          >
            <button
              v-for="v in VIEWS"
              :key="v.key"
              class="cv-seg-item flex items-center gap-1.5"
              :class="view === v.key ? 'cv-seg-on' : ''"
              @click="view = v.key"
            >
              <span :class="v.icon" class="text-xs" />
              <span class="hidden sm:inline">{{ v.label }}</span>
            </button>
          </div>
        </div>

        <!-- filtros -->
        <div class="flex items-center gap-2 flex-wrap mb-4">
          <div class="cv-seg cv-seg-sm inline-flex items-center gap-0.5">
            <button
              v-for="d in DIRECTIONS"
              :key="d.key"
              class="cv-seg-item"
              :class="filters.direction === d.key ? 'cv-seg-on' : ''"
              @click="filters.direction = d.key"
            >
              {{ d.label }}
            </button>
          </div>
          <select v-model="filters.status" class="cv-input text-xs !w-auto">
            <option v-for="s in STATUS_OPTIONS" :key="s.key" :value="s.key">
              {{ s.label }}
            </option>
          </select>
          <select v-model="filters.user_id" class="cv-input text-xs !w-auto">
            <option value="">Qualquer atendente</option>
            <option v-for="a in agentOptions" :key="a.id" :value="String(a.id)">
              {{ a.name }}
            </option>
          </select>
          <select
            v-if="multiInbox || inboxOptions.length > 1"
            v-model="filters.inbox_id"
            class="cv-input text-xs !w-auto"
          >
            <option value="">Qualquer caixa</option>
            <option v-for="i in inboxOptions" :key="i.id" :value="String(i.id)">
              {{ i.name }}
            </option>
          </select>
          <button
            class="cv-chip cursor-pointer"
            :class="filters.handled_by === 'ai' ? 'cv-green' : ''"
            title="Só as ligações da assistente virtual"
            @click="
              filters.handled_by = filters.handled_by === 'ai' ? '' : 'ai'
            "
          >
            🤖 IA
          </button>
          <input
            v-model="filters.q"
            type="search"
            placeholder="Buscar paciente ou telefone…"
            class="cv-input text-xs !w-auto min-w-[13rem]"
          />
          <button
            v-if="hasFilters"
            class="cv-btn cv-btn-ghost cv-btn-sm"
            @click="clearFilters"
          >
            Limpar
          </button>
          <button
            class="cv-btn cv-btn-ghost cv-btn-sm ml-auto"
            :disabled="isExporting"
            title="Baixar o histórico filtrado"
            @click="exportCsv"
          >
            <span class="i-lucide-download text-xs" /> CSV
          </button>
        </div>

        <div
          v-if="isLoadingHistory && !history.length"
          class="flex justify-center py-10"
        >
          <Spinner :size="28" class="text-n-brand" />
        </div>
        <p
          v-else-if="!history.length"
          class="text-xs text-n-slate-9 py-6 text-center"
        >
          Nenhuma chamada com esses filtros no período.
        </p>

        <!-- LISTA -->
        <div v-else-if="view === 'list'" class="space-y-1.5">
          <template v-for="c in history" :key="c.id">
            <CallLine
              :call="c"
              @open="openDetail"
              @conversation="openConversation"
              @play="togglePlay"
            />
            <audio
              v-if="playing === c.id && c.recording_url"
              controls
              autoplay
              :src="c.recording_url"
              class="w-full h-8 px-3"
            />
          </template>
        </div>

        <!-- TABELA -->
        <div v-else-if="view === 'table'" class="cv-sub overflow-x-auto">
          <table class="w-full text-xs">
            <thead>
              <tr
                class="text-left text-[10px] uppercase tracking-wide text-n-slate-9"
              >
                <th class="px-3 py-2">Quando</th>
                <th class="px-3 py-2">Paciente</th>
                <th class="px-3 py-2 hidden md:table-cell">Direção</th>
                <th class="px-3 py-2">Situação</th>
                <th class="px-3 py-2 hidden sm:table-cell">Atendente</th>
                <th class="px-3 py-2 hidden lg:table-cell">Espera</th>
                <th class="px-3 py-2 hidden sm:table-cell">Conversa</th>
                <th class="px-3 py-2 hidden lg:table-cell">Caixa</th>
                <th class="px-3 py-2" />
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="c in history"
                :key="c.id"
                class="border-t border-n-weak hover:bg-n-alpha-1 cursor-pointer"
                @click="openDetail(c)"
              >
                <td
                  class="px-3 py-2 whitespace-nowrap tabular-nums text-n-slate-11"
                >
                  {{ shortDateTime(c.started_at) }}
                </td>
                <td class="px-3 py-2 min-w-0">
                  <p
                    class="font-semibold text-n-slate-12 truncate max-w-[12rem]"
                  >
                    {{ rowName(c) }}
                  </p>
                  <p class="text-[10px] text-n-slate-9">{{ rowPhone(c) }}</p>
                </td>
                <td class="px-3 py-2 hidden md:table-cell">
                  <span
                    :class="[callIcon(c).icon, callIcon(c).tone]"
                    class="text-sm align-middle"
                  />
                  {{ c.direction === 'outbound' ? 'feita' : 'recebida' }}
                </td>
                <td class="px-3 py-2">
                  <span class="cv-chip" :class="statusChip(c.status)">{{
                    STATUS_LABELS[c.status] || c.status
                  }}</span>
                  <span
                    v-if="c.returned_at"
                    class="cv-chip ml-1 !hidden md:!inline-flex"
                    >retornada</span
                  >
                </td>
                <td class="px-3 py-2 hidden sm:table-cell text-n-slate-11">
                  {{ c.handled_by === 'ai' ? '🤖 IA' : c.user?.name || '—' }}
                </td>
                <td
                  class="px-3 py-2 hidden lg:table-cell tabular-nums text-n-slate-11"
                >
                  {{
                    c.wait_seconds != null
                      ? formatTalkTime(c.wait_seconds)
                      : '—'
                  }}
                </td>
                <td
                  class="px-3 py-2 hidden sm:table-cell tabular-nums text-n-slate-11"
                >
                  {{ Number(c.duration) ? formatTalkTime(c.duration) : '—' }}
                </td>
                <td
                  class="px-3 py-2 hidden lg:table-cell text-n-slate-10 truncate max-w-[10rem]"
                >
                  {{ c.inbox_name || '' }}
                </td>
                <td class="px-3 py-2 text-right whitespace-nowrap">
                  <button
                    v-if="c.recording_url"
                    class="cv-btn cv-btn-ghost cv-iconbtn"
                    title="Ouvir"
                    @click.stop="togglePlay(c)"
                  >
                    <span class="i-lucide-play text-xs" />
                  </button>
                  <button
                    v-if="c.conversation_id"
                    class="cv-btn cv-btn-ghost cv-iconbtn"
                    title="Conversa"
                    @click.stop="openConversation(c)"
                  >
                    <span class="i-lucide-message-circle text-xs" />
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
          <audio
            v-if="playing && history.find(x => x.id === playing)?.recording_url"
            controls
            autoplay
            :src="history.find(x => x.id === playing).recording_url"
            class="w-full h-8 px-3 py-2"
          />
        </div>

        <!-- POR ATENDENTE -->
        <div v-else-if="view === 'agents'">
          <p
            v-if="!agentRows.length"
            class="text-xs text-n-slate-9 py-6 text-center"
          >
            Ninguém atendeu chamadas neste período.
          </p>
          <div
            v-else
            class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3"
          >
            <button
              v-for="a in overview?.by_agent || []"
              :key="a.user_id"
              class="cv-sub cv-sub-hover p-4 text-left"
              :class="filters.user_id === String(a.user_id) ? 'cv-sub-on' : ''"
              @click="pickAgent({ key: a.user_id })"
            >
              <p
                class="text-sm font-bold text-n-slate-12 flex items-center gap-2"
              >
                <span
                  class="w-7 h-7 rounded-full flex items-center justify-center text-[10px] font-bold text-white"
                  style="background: var(--cv-grad-2)"
                >
                  {{ initialsOf(a.name) }}
                </span>
                {{ a.name }}
              </p>
              <div class="grid grid-cols-3 gap-1.5 mt-3">
                <div class="cv-stat text-center">
                  <p class="text-sm font-bold text-n-slate-12">
                    {{ a.answered }}
                  </p>
                  <p class="cv-label">atendidas</p>
                </div>
                <div class="cv-stat text-center">
                  <p class="text-sm font-bold text-n-slate-12">
                    {{ formatTalkTime(a.avg_talk_seconds) }}
                  </p>
                  <p class="cv-label">média</p>
                </div>
                <div class="cv-stat text-center">
                  <p class="text-sm font-bold text-n-slate-12">
                    {{ formatTalkTime(a.total_talk_seconds) }}
                  </p>
                  <p class="cv-label">total</p>
                </div>
              </div>
              <p class="text-[10px] text-n-slate-9 mt-2">
                clique para ver só as chamadas dessa pessoa
              </p>
            </button>
          </div>
        </div>

        <!-- LINHA DO TEMPO -->
        <div v-else-if="view === 'timeline'" class="space-y-6">
          <div v-for="day in timelineDays" :key="day.day">
            <p class="text-sm font-bold text-n-slate-12 mb-2">{{ day.day }}</p>
            <div v-for="h in day.hours" :key="h.hour" class="flex gap-3 mb-2">
              <div class="w-10 flex-shrink-0 text-right">
                <span
                  class="text-[11px] font-semibold tabular-nums"
                  style="color: var(--cv)"
                  >{{ h.hour }}</span
                >
              </div>
              <div
                class="flex-1 min-w-0 border-l-2 pl-3 space-y-1"
                style="border-color: rgb(var(--cv-rgb) / 0.35)"
              >
                <CallLine
                  v-for="c in h.calls"
                  :key="c.id"
                  :call="c"
                  when="time"
                  compact
                  @open="openDetail"
                  @conversation="openConversation"
                  @play="togglePlay"
                />
              </div>
            </div>
          </div>
        </div>

        <div
          v-if="hasMore && view !== 'agents'"
          class="flex justify-center mt-4"
        >
          <button
            class="cv-btn cv-btn-ghost cv-btn-sm"
            :disabled="isLoadingHistory"
            @click="loadMore"
          >
            {{
              isLoadingHistory
                ? 'Carregando…'
                : `Carregar mais (${historyTotal - history.length} restantes)`
            }}
          </button>
        </div>
      </section>
    </div>

    <CallDetailModal
      v-if="detail"
      :call="detail"
      :cv-vars="cvVars"
      :can-call="canCall"
      :is-busy="busyId === detail.id || callsStore.isBusy"
      @close="detail = null"
      @conversation="openConversation"
      @contact="openContact"
      @return="returnCall"
      @mark-returned="markReturned"
      @transcribe="transcribe"
    />
  </div>
</template>
