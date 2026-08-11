<script setup>
// 📈 VISUALIZAÇÃO PRO MAX (item 129) — estúdio de análise do Dashboard CRM.
// Séries diárias do backend (pro_series) + agregação local em dia/semana/mês,
// 4 estilos (linha, área, barras, candles) e o HISTÓRICO DE AÇÕES DA EMPRESA
// desenhado por cima da linha do tempo — para ver o que cada ação gerou.
// Candles sem lib nova: barras flutuantes [min,max] do chart.js (corpo+pavio).
import { ref, computed, watch, onMounted } from 'vue';
import {
  Chart as ChartJS,
  Title, Tooltip, Legend,
  BarElement, CategoryScale, LinearScale,
  PointElement, LineElement, Filler,
} from 'chart.js';
import { Bar, Line } from 'vue-chartjs';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';

ChartJS.register(
  Title, Tooltip, Legend,
  BarElement, CategoryScale, LinearScale,
  PointElement, LineElement, Filler,
);

const props = defineProps({
  pipelineId: { type: Number, required: true },
  initialFrom: { type: String, default: '' },
  initialTo: { type: String, default: '' },
  // atalho de foco (129B): '' = padrão · 'timeline' = conversas por caixa ·
  // 'revenue' = faturamento por caixa de entrada
  focus: { type: String, default: '' },
});
const emit = defineEmits(['close']);

const { isAdmin } = useAdmin();

// ── estado ────────────────────────────────────────────────────────────
const isLoading = ref(false);
const payload = ref(null); // { dates, labels, series, actions }
const period = ref({
  preset: props.initialFrom ? 'custom' : 'month',
  from: props.initialFrom || '',
  to: props.initialTo || '',
});
const granularity = ref('week'); // day | week | month
const chartStyle = ref('area'); // line | area | bars | candles
const selectedKeys = ref([]); // variáveis ligadas
const showActions = ref(true);

const GRANULARITIES = [
  { key: 'day', label: 'Dia' },
  { key: 'week', label: 'Semana' },
  { key: 'month', label: 'Mês' },
];
const STYLES = [
  { key: 'line', label: 'Linha', icon: 'i-lucide-chart-line' },
  { key: 'area', label: 'Área', icon: 'i-lucide-chart-area' },
  { key: 'bars', label: 'Barras', icon: 'i-lucide-chart-column' },
  { key: 'candles', label: 'Candles', icon: 'i-lucide-chart-candlestick' },
];
const ACTION_META = {
  campanha: { emoji: '📣', label: 'Campanha', color: '#DB2777' },
  pagina: { emoji: '🌐', label: 'Página', color: '#1D4ED8' },
  sistema: { emoji: '⚙️', label: 'Sistema', color: '#7C3AED' },
  whatsapp: { emoji: '💬', label: 'WhatsApp', color: '#059669' },
  outro: { emoji: '📌', label: 'Outro', color: '#B8860B' },
};

// ── carga ─────────────────────────────────────────────────────────────
const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await CrmAPI.getProSeries(props.pipelineId, {
      from: period.value.from,
      to: period.value.to,
    });
    payload.value = data;
    if (!selectedKeys.value.length) {
      if (props.focus === 'timeline') {
        const perInbox = data.series.filter(s => s.group === 'inbox_conv').map(s => s.key);
        selectedKeys.value = ['new_conversations', ...perInbox];
      } else if (props.focus === 'revenue') {
        const perInbox = data.series.filter(s => s.group === 'inbox_rev').map(s => s.key);
        selectedKeys.value = perInbox.length ? perInbox : ['revenue'];
      } else {
        selectedKeys.value = data.series.filter(s => s.default_on).map(s => s.key);
      }
    }
  } catch {
    useAlert('Não consegui carregar as séries do período.');
  } finally {
    isLoading.value = false;
  }
};
onMounted(load);
watch(() => [period.value.from, period.value.to], load);

const toggleKey = key => {
  const idx = selectedKeys.value.indexOf(key);
  if (idx === -1) selectedKeys.value.push(key);
  else if (selectedKeys.value.length > 1) selectedKeys.value.splice(idx, 1);
};

// ── agregação dia → semana/mês ────────────────────────────────────────
// cada balde = { label, dayIdxs: [índices dos dias dentro dele] }
const buckets = computed(() => {
  if (!payload.value) return [];
  const out = [];
  const seen = {};
  payload.value.dates.forEach((iso, i) => {
    let key;
    let label;
    const d = new Date(`${iso}T12:00:00`);
    if (granularity.value === 'day') {
      key = iso;
      label = payload.value.labels[i];
    } else if (granularity.value === 'month') {
      key = iso.slice(0, 7);
      label = d.toLocaleDateString('pt-BR', { month: 'short', year: '2-digit' });
    } else {
      // semana ISO: recua até segunda-feira
      const monday = new Date(d);
      monday.setDate(d.getDate() - ((d.getDay() + 6) % 7));
      key = monday.toISOString().slice(0, 10);
      label = `sem ${monday.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })}`;
    }
    if (seen[key] === undefined) {
      seen[key] = out.length;
      out.push({ key, label, dayIdxs: [] });
    }
    out[seen[key]].dayIdxs.push(i);
  });
  return out;
});

const activeSeries = computed(() =>
  (payload.value?.series ?? []).filter(s => selectedKeys.value.includes(s.key))
);

const sumBucket = (values, idxs) => idxs.reduce((acc, i) => acc + (values[i] || 0), 0);

// candle olha UMA variável (a primeira ligada) — OHLC dos DIAS dentro do balde
const candleSeries = computed(() => activeSeries.value[0] ?? null);
const candleData = computed(() => {
  const serie = candleSeries.value;
  if (!serie) return [];
  return buckets.value.map(b => {
    const days = b.dayIdxs.map(i => serie.values[i] || 0);
    return {
      open: days[0] ?? 0,
      close: days[days.length - 1] ?? 0,
      high: Math.max(...days, 0),
      low: Math.min(...days),
    };
  });
});

// ── ações da empresa: em qual balde cada uma cai ──────────────────────
const actionsInChart = computed(() => {
  if (!payload.value || !showActions.value) return [];
  return payload.value.actions
    .map((a, n) => {
      const bIdx = buckets.value.findIndex(b =>
        b.dayIdxs.some(i => payload.value.dates[i] === a.date)
      );
      return bIdx === -1 ? null : { ...a, bucketIndex: bIdx, n: n + 1 };
    })
    .filter(Boolean);
});

// plugin inline: linhas verticais tracejadas + medalhinha numerada no topo
const actionsPlugin = {
  id: 'cevicoCompanyActions',
  afterDatasetsDraw(chart, _args, opts) {
    const items = opts?.items ?? [];
    if (!items.length) return;
    const { ctx, chartArea, scales } = chart;
    if (!chartArea || !scales.x) return;
    items.forEach(item => {
      const x = scales.x.getPixelForValue(item.bucketIndex);
      if (Number.isNaN(x)) return;
      const color = ACTION_META[item.category]?.color ?? '#B8860B';
      ctx.save();
      ctx.setLineDash([4, 4]);
      ctx.strokeStyle = `${color}AA`;
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.moveTo(x, chartArea.top + 14);
      ctx.lineTo(x, chartArea.bottom);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(x, chartArea.top + 8, 8, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#fff';
      ctx.font = 'bold 9px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(String(item.n), x, chartArea.top + 8.5);
      ctx.restore();
    });
  },
};

// ── gráfico ───────────────────────────────────────────────────────────
const hexAlpha = (hex, alpha) => `${hex}${alpha}`;

const baseOptions = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  interaction: { mode: 'index', intersect: false },
  plugins: {
    legend: { display: false },
    tooltip: {
      callbacks: {
        label: ctx => {
          const serie = activeSeries.value[ctx.datasetIndex];
          const v = Array.isArray(ctx.raw) ? ctx.raw[1] : ctx.raw;
          const fmt = serie?.unit === 'brl'
            ? `R$ ${Number(v).toLocaleString('pt-BR', { maximumFractionDigits: 0 })}`
            : Number(v).toLocaleString('pt-BR');
          return `${serie?.label ?? ctx.dataset.label}: ${fmt}`;
        },
      },
    },
    cevicoCompanyActions: { items: actionsInChart.value },
  },
  scales: {
    x: { grid: { display: false }, ticks: { maxRotation: 45, autoSkip: true, maxTicksLimit: 24 } },
    y: { beginAtZero: chartStyle.value !== 'candles', grid: { color: 'rgba(148,163,184,0.15)' } },
  },
}));

const lineChart = computed(() => {
  if (!payload.value) return null;
  const labels = buckets.value.map(b => b.label);
  const area = chartStyle.value === 'area';
  return {
    data: {
      labels,
      datasets: activeSeries.value.map(s => ({
        label: s.label,
        data: buckets.value.map(b => sumBucket(s.values, b.dayIdxs)),
        borderColor: s.color,
        backgroundColor: area ? hexAlpha(s.color, '33') : s.color,
        fill: area,
        tension: 0.35,
        pointRadius: buckets.value.length > 40 ? 0 : 2.5,
        borderWidth: 2.5,
      })),
    },
    options: baseOptions.value,
  };
});

const barsChart = computed(() => {
  if (!payload.value) return null;
  return {
    data: {
      labels: buckets.value.map(b => b.label),
      datasets: activeSeries.value.map(s => ({
        label: s.label,
        data: buckets.value.map(b => sumBucket(s.values, b.dayIdxs)),
        backgroundColor: hexAlpha(s.color, 'CC'),
        borderRadius: 6,
        maxBarThickness: 34,
      })),
    },
    options: baseOptions.value,
  };
});

const candlesChart = computed(() => {
  if (!payload.value || !candleSeries.value) return null;
  const up = '#10B981';
  const down = '#F43F5E';
  const colorOf = c => (c.close >= c.open ? up : down);
  return {
    data: {
      labels: buckets.value.map(b => b.label),
      datasets: [
        {
          // pavio (low → high) — barra fininha atrás
          label: 'amplitude',
          data: candleData.value.map(c => [c.low, c.high]),
          backgroundColor: candleData.value.map(c => hexAlpha(colorOf(c), '99')),
          barPercentage: 0.16,
          categoryPercentage: 1,
          grouped: false,
          borderRadius: 2,
        },
        {
          // corpo (open → close)
          label: candleSeries.value.label,
          data: candleData.value.map(c => [Math.min(c.open, c.close), Math.max(c.open, c.close, Math.min(c.open, c.close) + 0.01)]),
          backgroundColor: candleData.value.map(colorOf),
          barPercentage: 0.55,
          categoryPercentage: 1,
          grouped: false,
          borderRadius: 3,
        },
      ],
    },
    options: {
      ...baseOptions.value,
      plugins: {
        ...baseOptions.value.plugins,
        tooltip: {
          callbacks: {
            label: ctx => {
              const c = candleData.value[ctx.dataIndex];
              if (!c || ctx.datasetIndex === 0) return null;
              return [
                `abriu: ${c.open.toLocaleString('pt-BR')}`,
                `fechou: ${c.close.toLocaleString('pt-BR')}`,
                `máx: ${c.high.toLocaleString('pt-BR')} · mín: ${c.low.toLocaleString('pt-BR')}`,
              ];
            },
          },
        },
      },
    },
  };
});

const isBarStyle = computed(() => ['bars', 'candles'].includes(chartStyle.value));
const chartPayload = computed(() => {
  if (chartStyle.value === 'candles') return candlesChart.value;
  if (chartStyle.value === 'bars') return barsChart.value;
  return lineChart.value;
});

// ── CRUD das ações da empresa (admin) ─────────────────────────────────
const showActionForm = ref(false);
const isSavingActions = ref(false);
const actionDraft = ref({ date: '', title: '', category: 'campanha', notes: '' });

// fonte da verdade: a lista COMPLETA vem do settings (o pro_series só
// devolve as ações do período visível)
const fetchAllActions = async () => {
  const { data } = await CrmAPI.getSettings();
  return data.company_actions ?? [];
};

const saveAction = async () => {
  if (!actionDraft.value.date || !actionDraft.value.title.trim()) return;
  isSavingActions.value = true;
  try {
    const current = await fetchAllActions();
    const next = [...current, { ...actionDraft.value, title: actionDraft.value.title.trim() }];
    await CrmAPI.updateCompanyActions(next);
    actionDraft.value = { date: '', title: '', category: 'campanha', notes: '' };
    showActionForm.value = false;
    await load();
    useAlert('Ação registrada na linha do tempo! 📌');
  } catch {
    useAlert('Não consegui salvar a ação.');
  } finally {
    isSavingActions.value = false;
  }
};

const removeAction = async action => {
  isSavingActions.value = true;
  try {
    const current = await fetchAllActions();
    await CrmAPI.updateCompanyActions(current.filter(a => a.id !== action.id));
    await load();
  } catch {
    useAlert('Não consegui remover a ação.');
  } finally {
    isSavingActions.value = false;
  }
};
</script>

<template>
  <div class="fixed inset-0 z-50 flex items-center justify-center p-3 md:p-6" style="background: rgba(2, 6, 23, 0.72)" @click.self="emit('close')">
    <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-[1200px] h-[94vh] flex flex-col overflow-hidden border border-n-weak">
      <!-- Cabeçalho -->
      <div class="flex items-center justify-between px-5 py-3.5 border-b border-n-weak flex-shrink-0">
        <h2 class="text-sm font-bold text-n-slate-12 flex items-center gap-2">
          <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)">
            <span class="i-lucide-sparkles text-white text-sm" />
          </span>
          Visualização PRO MAX
          <span class="text-[11px] font-normal text-n-slate-10 hidden md:inline">análise por período · estilos de gráfico · ações da empresa na linha do tempo</span>
        </h2>
        <button class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-lg" @click="emit('close')" />
      </div>

      <!-- Controles -->
      <div class="px-5 py-3 border-b border-n-weak flex items-center gap-2 flex-wrap flex-shrink-0">
        <PeriodRuler v-model="period" />

        <!-- granularidade -->
        <div class="flex items-center h-[34px] bg-n-solid-2 border border-n-weak rounded-xl px-0.5 gap-0.5">
          <button
            v-for="g in GRANULARITIES"
            :key="g.key"
            class="h-7 px-2.5 rounded-lg text-xs font-medium transition-colors"
            :class="granularity === g.key ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
            :style="granularity === g.key ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' } : {}"
            @click="granularity = g.key"
          >
            {{ g.label }}
          </button>
        </div>

        <!-- estilo -->
        <div class="flex items-center h-[34px] bg-n-solid-2 border border-n-weak rounded-xl px-0.5 gap-0.5">
          <button
            v-for="s in STYLES"
            :key="s.key"
            class="h-7 px-2.5 rounded-lg text-xs font-medium transition-colors flex items-center gap-1"
            :class="chartStyle === s.key ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
            :style="chartStyle === s.key ? { background: 'linear-gradient(135deg, #B8860B, #D4A017)' } : {}"
            @click="chartStyle = s.key"
          >
            <span :class="s.icon" class="text-sm" />
            {{ s.label }}
          </button>
        </div>

        <label class="flex items-center gap-1.5 text-xs text-n-slate-11 cursor-pointer ml-auto">
          <input v-model="showActions" type="checkbox" class="rounded accent-n-brand" />
          📌 Ações da empresa
        </label>
      </div>

      <!-- Variáveis -->
      <div class="px-5 py-2.5 border-b border-n-weak flex items-center gap-1.5 flex-wrap flex-shrink-0 max-h-24 overflow-y-auto">
        <button
          v-for="s in payload?.series ?? []"
          :key="s.key"
          class="flex items-center gap-1.5 text-[11px] px-2.5 py-1 rounded-full border transition-colors"
          :class="selectedKeys.includes(s.key)
            ? 'font-semibold text-n-slate-12 bg-n-alpha-1'
            : 'text-n-slate-9 border-n-weak hover:bg-n-alpha-1'"
          :style="selectedKeys.includes(s.key) ? { borderColor: s.color } : {}"
          @click="toggleKey(s.key)"
        >
          <span class="w-2 h-2 rounded-full" :style="{ background: s.color }" />
          {{ s.label }}
        </button>
        <span v-if="chartStyle === 'candles'" class="text-[10px] text-n-slate-9 ml-1">
          candles usam a 1ª variável ligada ({{ candleSeries?.label }}) — o balde abre no 1º dia e fecha no último
        </span>
      </div>

      <!-- Gráfico -->
      <div class="flex-1 min-h-0 px-5 py-4">
        <div v-if="isLoading" class="h-full flex items-center justify-center"><Spinner /></div>
        <template v-else-if="chartPayload">
          <Bar
            v-if="isBarStyle"
            :data="chartPayload.data"
            :options="chartPayload.options"
            :plugins="[actionsPlugin]"
            class="!h-full"
          />
          <Line
            v-else
            :data="chartPayload.data"
            :options="chartPayload.options"
            :plugins="[actionsPlugin]"
            class="!h-full"
          />
        </template>
        <div v-else class="h-full flex items-center justify-center text-sm text-n-slate-9">Sem dados no período</div>
      </div>

      <!-- Ações da empresa: legenda + gestão -->
      <div class="border-t border-n-weak px-5 py-3 flex-shrink-0 max-h-44 overflow-y-auto">
        <div class="flex items-center justify-between mb-2">
          <p class="text-xs font-semibold text-n-slate-12">📌 Ações da empresa no período</p>
          <button
            v-if="isAdmin"
            class="text-xs text-n-brand hover:underline flex items-center gap-1"
            @click="showActionForm = !showActionForm"
          >
            <span class="i-lucide-plus text-xs" /> Registrar ação
          </button>
        </div>

        <!-- form de nova ação -->
        <div v-if="showActionForm" class="flex items-center gap-2 flex-wrap mb-2.5 bg-n-alpha-1 rounded-xl p-2.5">
          <input v-model="actionDraft.date" type="date" class="h-8 text-xs border border-n-weak rounded-lg px-2 bg-n-solid-2 text-n-slate-12" />
          <input
            v-model="actionDraft.title"
            class="h-8 text-xs border border-n-weak rounded-lg px-2.5 bg-n-solid-2 text-n-slate-12 flex-1 min-w-[180px]"
            placeholder='Ex.: "LP nova da catarata no ar", "Campanha refrativa 2x verba"'
            @keyup.enter="saveAction"
          />
          <select v-model="actionDraft.category" class="h-8 text-xs border border-n-weak rounded-lg px-2 bg-n-solid-2 text-n-slate-12">
            <option v-for="(meta, key) in ACTION_META" :key="key" :value="key">{{ meta.emoji }} {{ meta.label }}</option>
          </select>
          <button
            class="h-8 px-3 rounded-lg text-xs font-bold text-white disabled:opacity-50"
            style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)"
            :disabled="isSavingActions || !actionDraft.date || !actionDraft.title.trim()"
            @click="saveAction"
          >
            Salvar
          </button>
        </div>

        <div v-if="actionsInChart.length" class="flex flex-wrap gap-1.5">
          <span
            v-for="a in actionsInChart"
            :key="a.id"
            class="inline-flex items-center gap-1.5 text-[11px] px-2 py-1 rounded-full border border-n-weak text-n-slate-11 group"
            :title="a.notes || a.title"
          >
            <span
              class="w-4 h-4 rounded-full text-white text-[9px] font-bold flex items-center justify-center"
              :style="{ background: ACTION_META[a.category]?.color ?? '#B8860B' }"
            >{{ a.n }}</span>
            {{ ACTION_META[a.category]?.emoji }} {{ new Date(a.date + 'T12:00:00').toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' }) }}
            · {{ a.title }}
            <button
              v-if="isAdmin"
              class="i-lucide-x text-[10px] text-n-slate-9 hover:text-red-500 opacity-0 group-hover:opacity-100 transition-opacity"
              :disabled="isSavingActions"
              @click="removeAction(a)"
            />
          </span>
        </div>
        <p v-else class="text-[11px] text-n-slate-9">
          Nenhuma ação registrada no período. Registre "subimos LP nova", "campanha X no ar", "sistema atualizado" — e veja na linha do tempo o que cada ação gerou.
        </p>
      </div>
    </div>
  </div>
</template>
