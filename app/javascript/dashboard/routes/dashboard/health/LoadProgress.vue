<script setup>
// PROGRESSÃO DE CARGA POR TREINO (rodada 41) — pedido dele 29/09: "os
// gráficos mais interessantes são os de progressão de carga por treino;
// adicione esse tipo de informação em vários tipos de gráficos, pra gente
// entender qual o melhor pra analisar (radar, pizza, barras, linhas…);
// também um espacinho de notas pra anotar coisas importantes que fiz".
// Mesmo dado (ciclo + treino + métrica) em 8 visualizações, cada uma com
// estrela de favorito (guardada no navegador) — depois a gente mantém só
// as que ele escolher. Notas = registros kind=note (por pessoa).
import { ref, computed, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import RadarChart from './HubRadar.vue';
import {
  Chart as ChartJS, Tooltip, Legend, CategoryScale, LinearScale, PointElement,
  LineElement, Filler, BarElement, ArcElement, RadialLinearScale,
} from 'chart.js';
import { Line, Bar, Doughnut, PolarArea } from 'vue-chartjs';
import { applyChartTheme, watchChartTheme, isDarkMode } from './chartTheme';
import { ROYAL, ROYAL_CLARO, LARANJA, CINZA, GRAD_ROYAL, GRAD_LARANJA } from './palette';

const props = defineProps({
  workouts: { type: Array, default: () => [] },
  program: { type: Object, default: null },
  initialNotes: { type: Array, default: () => [] },
});

ChartJS.register(Tooltip, Legend, CategoryScale, LinearScale, PointElement, LineElement, Filler, BarElement, ArcElement, RadialLinearScale);
applyChartTheme();
watchChartTheme();

// uma cor por exercício (alegres, distinguíveis nos dois temas)
const SERIES = ['#4169E1', '#FF8A00', '#00C7BE', '#AF52DE', '#FF2D55', '#34C759', '#FFB300', '#32ADE6'];
const colorAt = i => SERIES[i % SERIES.length];
const alpha = (hex, a) => {
  const n = parseInt(hex.slice(1), 16);
  // eslint-disable-next-line no-bitwise
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${a})`;
};

const pad2 = n => String(n).padStart(2, '0');
const toISO = d => `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
const todayISO = toISO(new Date());
const fmtDay = iso => {
  const [, m, d] = String(iso).split('-');
  return `${d}/${m}`;
};
const fmtNum = v => {
  const n = Number(v) || 0;
  return String(Number.isInteger(n) ? n : n.toFixed(1)).replace('.', ',');
};
const e1rm = (load, reps) => (reps > 0 ? load * (1 + reps / 30) : load);
// rodada 42: NADA de reticências — o nome vai inteiro (pedido dele: "os
// indicadores precisam mostrar toda a informação"); eixos quebram em linhas
const shortName = name => String(name || '').trim();

// ── seleção: ciclo · treino · métrica ──────────────────────────────
const cycles = computed(() => props.program?.cycles || []);
const progRecs = computed(() =>
  props.workouts
    .filter(w => w.data?.program_id && (!props.program || w.data.program_id === props.program.id))
    .slice()
    .sort((a, b) => String(a.record_date).localeCompare(String(b.record_date)) || a.id - b.id)
);
const cycleOfRec = w => {
  if (w.data?.cycle_id) return w.data.cycle_id;
  const wk = Number(w.data?.week) || 0;
  return cycles.value.find(c => wk >= c.week_start && wk <= c.week_end)?.id || cycles.value[0]?.id;
};
const lastRec = computed(() => progRecs.value.at(-1) || null);
const selCycle = ref(null);
const selKey = ref(null);
const metric = ref('top');
watch(
  [lastRec, cycles],
  () => {
    if (!selCycle.value && cycles.value.length) selCycle.value = (lastRec.value && cycleOfRec(lastRec.value)) || cycles.value[0].id;
    if (!selKey.value) selKey.value = lastRec.value?.data?.session_key || 'A';
  },
  { immediate: true }
);
const cycle = computed(() => cycles.value.find(c => c.id === selCycle.value) || cycles.value[0] || null);
const sessionKeys = computed(() => (cycle.value?.sessions || []).map(s => s.key));
watch(sessionKeys, keys => {
  if (keys.length && !keys.includes(selKey.value)) selKey.value = keys[0];
});
const cycleLabel = c => `${String(c.name || '').replace('Treino ', 'Ciclo ')}${c.focus ? ` · ${String(c.focus).replace(/^Fase \d — /, '')}` : ''}`;
const recCount = (cId, key) => progRecs.value.filter(w => cycleOfRec(w) === cId && w.data?.session_key === key).length;

const METRICS = [
  { key: 'top', label: 'Carga máxima', unit: 'kg', hint: 'a série mais pesada de cada exercício' },
  { key: 'e1rm', label: 'Força estimada', unit: 'kg', hint: '1RM estimado (carga × repetições) — compara sessões com reps diferentes' },
  { key: 'vol', label: 'Volume', unit: 'kg', hint: 'soma de carga × repetições de todas as séries' },
];
const metricNow = computed(() => METRICS.find(m => m.key === metric.value) || METRICS[0]);

const valueOf = (ex, m) => {
  const sets = (ex?.sets || []).filter(s => Number(s.load) > 0 && Number(s.reps) > 0);
  if (!sets.length) return null;
  if (m === 'vol') return sets.reduce((s, x) => s + Number(x.load) * Number(x.reps), 0);
  if (m === 'e1rm') return Math.max(...sets.map(x => e1rm(Number(x.load), Number(x.reps))));
  return Math.max(...sets.map(x => Number(x.load)));
};

// sessões do treino escolhido, em ordem
const recs = computed(() =>
  progRecs.value.filter(w => cycleOfRec(w) === cycle.value?.id && w.data?.session_key === selKey.value)
);
const exNames = computed(() => {
  const presc = (cycle.value?.sessions || []).find(s => s.key === selKey.value)?.exercises || [];
  const names = presc.map(e => e.name);
  recs.value.forEach(w => (w.data?.exercises || []).forEach(e => {
    if (e.name && !names.includes(e.name)) names.push(e.name);
  }));
  return names;
});
const seriesOf = (name, m) =>
  recs.value.map(w => {
    const ex = (w.data?.exercises || []).find(e => e.name === name);
    const v = valueOf(ex, m);
    return v == null ? null : Math.round(v * 10) / 10;
  });
const rows = computed(() =>
  exNames.value
    .map((name, i) => {
      const s = seriesOf(name, metric.value);
      const vals = s.filter(v => v != null);
      if (!vals.length) return null;
      const first = vals[0];
      const last = vals.at(-1);
      const best = Math.max(...vals);
      return {
        name,
        short: shortName(name),
        color: colorAt(i),
        series: s,
        vol: seriesOf(name, 'vol'),
        first,
        last,
        best,
        gain: Math.round((last - first) * 10) / 10,
        pct: first > 0 ? Math.round(((last - first) / first) * 1000) / 10 : 0,
        n: vals.length,
      };
    })
    .filter(Boolean)
);
const labels = computed(() => recs.value.map(w => fmtDay(w.record_date)));
const hasData = computed(() => recs.value.length >= 1 && rows.value.length > 0);
const totals = computed(() => {
  const r = rows.value;
  if (!r.length) return null;
  const first = r.reduce((s, x) => s + x.first, 0);
  const last = r.reduce((s, x) => s + x.last, 0);
  const bestRow = [...r].sort((a, b) => b.pct - a.pct)[0];
  const worstRow = [...r].sort((a, b) => a.pct - b.pct)[0];
  return {
    sessions: recs.value.length,
    from: recs.value[0]?.record_date,
    to: recs.value.at(-1)?.record_date,
    pct: first > 0 ? Math.round(((last - first) / first) * 1000) / 10 : 0,
    gain: Math.round((last - first) * 10) / 10,
    bestRow,
    worstRow,
  };
});
const signed = v => `${v > 0 ? '+' : ''}${fmtNum(v)}`;

// ── notas (kind=note) ───────────────────────────────────────────────
const notes = ref([]);
watch(() => props.initialNotes, v => { notes.value = [...(v || [])]; }, { immediate: true });
const NOTE_TAGS = [
  { key: 'treino', label: 'Treino', ico: 'i-lucide-dumbbell', color: '#FF9500' },
  { key: 'dieta', label: 'Dieta', ico: 'i-lucide-utensils', color: '#00C7BE' },
  { key: 'sono', label: 'Sono', ico: 'i-lucide-bed', color: '#5856D6' },
  { key: 'corpo', label: 'Corpo', ico: 'i-lucide-ruler', color: '#AF52DE' },
  { key: 'rotina', label: 'Rotina', ico: 'i-lucide-calendar-range', color: '#32ADE6' },
  { key: 'outro', label: 'Outro', ico: 'i-lucide-sticky-note', color: '#8E8E93' },
];
const tagOf = key => NOTE_TAGS.find(t => t.key === key) || NOTE_TAGS.at(-1);
const noteForm = ref({ date: todayISO, tag: 'treino', text: '' });
const savingNote = ref(false);
const addNote = async () => {
  const text = noteForm.value.text.trim();
  if (!text) {
    useAlert('Escreva a nota antes de salvar.');
    return;
  }
  savingNote.value = true;
  try {
    const { data } = await CrmAPI.createHealthRecord({
      kind: 'note',
      record_date: noteForm.value.date || todayISO,
      data: { text, tag: noteForm.value.tag, session_key: noteForm.value.tag === 'treino' ? selKey.value : null },
    });
    notes.value = [data, ...notes.value];
    noteForm.value.text = '';
  } catch {
    useAlert('Não consegui salvar a nota.');
  } finally {
    savingNote.value = false;
  }
};
const removeNote = async n => {
  try {
    await CrmAPI.deleteHealthRecord(n.id);
    notes.value = notes.value.filter(x => x.id !== n.id);
  } catch {
    useAlert('Não consegui apagar a nota.');
  }
};
const MONTHS = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];
const notesByMonth = computed(() => {
  const sorted = [...notes.value].sort((a, b) => String(b.record_date).localeCompare(String(a.record_date)) || b.id - a.id);
  const groups = [];
  sorted.forEach(n => {
    const [y, m] = String(n.record_date).split('-');
    const key = `${y}-${m}`;
    let g = groups.find(x => x.key === key);
    if (!g) {
      g = { key, label: `${MONTHS[Number(m) - 1]} de ${y}`, items: [] };
      groups.push(g);
    }
    g.items.push(n);
  });
  return groups;
});
// notas que caem entre a sessão anterior (exclusivo) e esta (inclusivo)
const notesForIndex = i => {
  const to = recs.value[i]?.record_date;
  if (!to) return [];
  const from = i > 0 ? recs.value[i - 1].record_date : '0000-00-00';
  return notes.value.filter(n => n.record_date > from && n.record_date <= to);
};
const noteMarks = computed(() => recs.value.map((_, i) => notesForIndex(i).length));

// ── favoritos (no navegador) ───────────────────────────────────────
const FAV_KEY = 'hub_progress_favs';
const favs = ref([]);
try {
  favs.value = JSON.parse(localStorage.getItem(FAV_KEY) || '[]');
} catch {
  favs.value = [];
}
const toggleFav = key => {
  favs.value = favs.value.includes(key) ? favs.value.filter(k => k !== key) : [...favs.value, key];
  localStorage.setItem(FAV_KEY, JSON.stringify(favs.value));
};
const isFav = key => favs.value.includes(key);
const CHART_NAMES = { linhas: 'Linhas', barras: 'Barras', ganho: 'Ranking', radar: 'Radar', pizza: 'Pizza', area: 'Área', polar: 'Polar', tabela: 'Tabela' };

// ── gráficos ────────────────────────────────────────────────────────
const unit = computed(() => metricNow.value.unit);
const base = (extra = {}) => ({
  responsive: true,
  maintainAspectRatio: false,
  plugins: { legend: { position: 'bottom', labels: { boxWidth: 10, font: { size: 10 } } } },
  ...extra,
});
const kgTick = v => `${fmtNum(v)}`;
const wrapLabel = (label, max = 13) => {
  const words = String(label || '').split(' ');
  const lines = [];
  words.forEach(w => {
    if (lines.length && `${lines.at(-1)} ${w}`.length <= max) lines[lines.length - 1] = `${lines.at(-1)} ${w}`;
    else lines.push(w);
  });
  return lines;
};

// linhas em kg achatam os exercícios leves (terra 120 × abdômen 7) → modo
// '% desde o início' coloca todos na mesma régua
const lineMode = ref('pct');
const pctSeries = r => r.series.map(v => (v == null || !r.first ? null : Math.round(((v - r.first) / r.first) * 1000) / 10));
const lineChart = computed(() => ({
  labels: labels.value,
  datasets: [
    ...rows.value.map(r => ({
      label: r.short,
      data: lineMode.value === 'pct' ? pctSeries(r) : r.series,
      borderColor: r.color,
      backgroundColor: r.color,
      borderWidth: 2.5,
      pointRadius: 3,
      pointHoverRadius: 6,
      tension: 0.3,
      spanGaps: true,
    })),
  ],
}));
const lineOptions = computed(() =>
  base({
    interaction: { mode: 'index', intersect: false },
    plugins: {
      legend: { position: 'bottom', labels: { boxWidth: 10, font: { size: 10 } } },
      tooltip: {
        callbacks: {
          label: ctx => (lineMode.value === 'pct' ? ` ${ctx.dataset.label}: ${signed(ctx.parsed.y)}%  (${fmtNum(rows.value[ctx.datasetIndex]?.series[ctx.dataIndex])} ${unit.value})` : ` ${ctx.dataset.label}: ${fmtNum(ctx.parsed.y)} ${unit.value}`),
          footer: items => {
            const list = notesForIndex(items[0]?.dataIndex ?? -1);
            return list.length ? list.map(n => `nota: ${String(n.data?.text || '').slice(0, 70)}`) : [];
          },
        },
      },
    },
    scales: {
      y: { beginAtZero: false, ticks: { font: { size: 10 }, callback: v => (lineMode.value === 'pct' ? `${signed(v)}%` : kgTick(v)) }, title: { display: true, text: lineMode.value === 'pct' ? '% desde o início' : unit.value, font: { size: 10 } } },
      x: { ticks: { font: { size: 10 } } },
    },
  })
);

const barChart = computed(() => ({
  labels: rows.value.map(r => r.short),
  datasets: [
    { label: 'Início', data: rows.value.map(r => r.first), backgroundColor: alpha(ROYAL, 0.85), borderRadius: 6, maxBarThickness: 34 },
    { label: 'Agora', data: rows.value.map(r => r.last), backgroundColor: LARANJA, borderRadius: 6, maxBarThickness: 34 },
  ],
}));
const barOptions = computed(() =>
  base({
    plugins: {
      legend: { position: 'bottom', labels: { boxWidth: 10, font: { size: 10 } } },
      tooltip: { callbacks: { label: ctx => ` ${ctx.dataset.label}: ${fmtNum(ctx.parsed.y)} ${unit.value}` } },
    },
    scales: {
      y: { beginAtZero: true, ticks: { font: { size: 10 }, callback: kgTick } },
      // nome inteiro em até 3 linhas (nada de pular rótulo)
      x: { ticks: { font: { size: 9.5 }, autoSkip: false, callback(v) { return wrapLabel(this.getLabelForValue(v)); } } },
    },
  })
);

const ranked = computed(() => [...rows.value].sort((a, b) => b.pct - a.pct));
const gainChart = computed(() => ({
  labels: ranked.value.map(r => r.short),
  datasets: [
    {
      label: 'Ganho %',
      data: ranked.value.map(r => r.pct),
      backgroundColor: ranked.value.map(r => (r.pct > 0 ? LARANJA : r.pct < 0 ? '#E5484D' : CINZA)),
      borderRadius: 6,
      maxBarThickness: 26,
    },
  ],
}));
const gainOptions = computed(() =>
  base({
    indexAxis: 'y',
    plugins: {
      legend: { display: false },
      tooltip: { callbacks: { label: ctx => ` ${signed(ctx.parsed.x)}%  (${signed(ranked.value[ctx.dataIndex].gain)} ${unit.value})` } },
    },
    scales: {
      x: { ticks: { font: { size: 10 }, callback: v => `${v}%` } },
      y: { ticks: { font: { size: 9.5 }, autoSkip: false, callback(v) { return wrapLabel(this.getLabelForValue(v), 20); } } },
    },
  })
);

const radar = computed(() => ({
  axes: rows.value.map(r => ({ key: r.name, label: r.short })),
  datasets: [
    { label: 'Início', color: isDarkMode() ? ROYAL_CLARO : ROYAL, values: Object.fromEntries(rows.value.map(r => [r.name, r.best > 0 ? (r.first / r.best) * 100 : 0])) },
    { label: 'Agora', color: LARANJA, values: Object.fromEntries(rows.value.map(r => [r.name, r.best > 0 ? (r.last / r.best) * 100 : 0])) },
  ],
}));

const gainers = computed(() => rows.value.filter(r => r.gain > 0));
const pieChart = computed(() => ({
  labels: gainers.value.map(r => r.short),
  datasets: [
    {
      data: gainers.value.map(r => r.gain),
      backgroundColor: gainers.value.map(r => r.color),
      borderColor: isDarkMode() ? '#10131e' : '#fff',
      borderWidth: 3,
      hoverOffset: 8,
    },
  ],
}));
const pieOptions = computed(() =>
  base({
    cutout: '58%',
    plugins: {
      legend: { position: 'bottom', labels: { boxWidth: 10, font: { size: 10 } } },
      tooltip: {
        callbacks: {
          label: ctx => {
            const total = ctx.dataset.data.reduce((s, v) => s + v, 0) || 1;
            return ` ${ctx.label}: +${fmtNum(ctx.parsed)} ${unit.value} (${Math.round((ctx.parsed / total) * 100)}%)`;
          },
        },
      },
    },
  })
);
const pieTotal = computed(() => Math.round(gainers.value.reduce((s, r) => s + r.gain, 0) * 10) / 10);

const areaChart = computed(() => ({
  labels: labels.value,
  datasets: rows.value.map(r => ({
    label: r.short,
    data: r.vol.map(v => v ?? 0),
    borderColor: r.color,
    backgroundColor: alpha(r.color, 0.55),
    borderWidth: 1.5,
    pointRadius: 0,
    tension: 0.3,
    fill: true,
  })),
}));
const areaOptions = computed(() =>
  base({
    interaction: { mode: 'index', intersect: false },
    plugins: {
      legend: { position: 'bottom', labels: { boxWidth: 10, font: { size: 10 } } },
      tooltip: { callbacks: { label: ctx => ` ${ctx.dataset.label}: ${fmtNum(ctx.parsed.y)} kg` } },
    },
    scales: { y: { stacked: true, beginAtZero: true, ticks: { font: { size: 10 } } }, x: { ticks: { font: { size: 10 } } } },
  })
);

const polarChart = computed(() => ({
  labels: rows.value.map(r => r.short),
  datasets: [
    {
      data: rows.value.map(r => Math.max(r.pct, 0)),
      backgroundColor: rows.value.map(r => alpha(r.color, 0.7)),
      borderColor: rows.value.map(r => r.color),
      borderWidth: 1.5,
    },
  ],
}));
const polarOptions = computed(() =>
  base({
    plugins: {
      legend: { position: 'bottom', labels: { boxWidth: 10, font: { size: 10 } } },
      tooltip: { callbacks: { label: ctx => ` ${ctx.label}: +${fmtNum(ctx.parsed.r)}%` } },
    },
    scales: {
      r: {
        ticks: { display: false },
        grid: { color: isDarkMode() ? 'rgba(255,255,255,0.12)' : 'rgba(15,23,42,0.1)' },
        angleLines: { color: isDarkMode() ? 'rgba(255,255,255,0.12)' : 'rgba(15,23,42,0.1)' },
      },
    },
  })
);
</script>

<template>
  <div class="hub-lp">
    <!-- ═══ controles ═══ -->
    <div class="hub-block p-5 mb-8">
      <div class="hub-sec">
        <span class="hub-sec-ico"><span class="i-lucide-trending-up" /></span>
        <div class="hub-sec-text">
          <p class="hub-sec-title">Progressão de carga por treino</p>
          <p class="hub-sec-sub">o mesmo dado em 8 gráficos — marque com a estrela os que você achar melhores</p>
        </div>
      </div>

      <div v-if="!cycles.length" class="text-xs text-n-slate-10">Nenhum programa com ciclos configurado.</div>
      <div v-else class="hub-form">
        <div class="hub-form-row">
          <span class="hub-lp-l">Ciclo</span>
          <div class="hub-seg hub-lp-seg">
            <button v-for="c in cycles" :key="c.id" :class="{ 'is-on': cycle && cycle.id === c.id }" @click="selCycle = c.id">{{ cycleLabel(c) }}</button>
          </div>
        </div>
        <div class="hub-form-row">
          <span class="hub-lp-l">Treino</span>
          <div class="hub-seg hub-lp-seg">
            <button v-for="k in sessionKeys" :key="k" :class="{ 'is-on': selKey === k }" @click="selKey = k">
              Treino {{ k }}<span class="hub-lp-count">{{ recCount(cycle.id, k) }}</span>
            </button>
          </div>
        </div>
        <div class="hub-form-row">
          <span class="hub-lp-l">Métrica</span>
          <div>
            <div class="hub-seg hub-lp-seg">
              <button v-for="m in METRICS" :key="m.key" :class="{ 'is-on': metric === m.key }" @click="metric = m.key">{{ m.label }}</button>
            </div>
            <p class="text-[11px] text-n-slate-10 mt-1.5">{{ metricNow.hint }}</p>
          </div>
        </div>
      </div>

      <div v-if="hasData && totals" class="hub-grid-4 mt-5">
        <div class="hub-kpi hub-crystal t-royal">
          <span class="hub-kpi-l"><span class="i-lucide-calendar-check" />Sessões</span>
          <p class="hub-kpi-v is-royal">{{ totals.sessions }}</p>
          <p class="hub-kpi-s">{{ fmtDay(totals.from) }} → {{ fmtDay(totals.to) }}</p>
        </div>
        <div class="hub-kpi hub-crystal t-orange">
          <span class="hub-kpi-l"><span class="i-lucide-trending-up" />Ganho do treino</span>
          <p class="hub-kpi-v is-orange">{{ signed(totals.pct) }}%</p>
          <p class="hub-kpi-s">{{ signed(totals.gain) }} {{ unit }} somando os exercícios</p>
        </div>
        <div class="hub-kpi hub-crystal t-orange">
          <span class="hub-kpi-l"><span class="i-lucide-trophy" />Mais evoluiu</span>
          <p class="hub-kpi-v is-orange">{{ signed(totals.bestRow.pct) }}%</p>
          <p class="hub-kpi-s">{{ totals.bestRow.short }}</p>
        </div>
        <div class="hub-kpi hub-crystal t-royal">
          <span class="hub-kpi-l"><span class="i-lucide-hourglass" />Menos evoluiu</span>
          <p class="hub-kpi-v is-royal">{{ signed(totals.worstRow.pct) }}%</p>
          <p class="hub-kpi-s">{{ totals.worstRow.short }}</p>
        </div>
      </div>
      <p v-if="favs.length" class="text-[11px] text-n-slate-10 mt-4">
        <span class="i-lucide-star hub-ico-inline" /> Seus favoritos: <b class="text-n-slate-12">{{ favs.map(k => CHART_NAMES[k]).filter(Boolean).join(' · ') }}</b>
      </p>
    </div>

    <div v-if="cycles.length && !hasData" class="hub-block p-5 mb-8">
      <p class="text-sm text-n-slate-11">Ainda não há sessões registradas de <b>Treino {{ selKey }}</b> neste ciclo. Escolha outro treino ou ciclo acima.</p>
    </div>

    <template v-if="hasData">
      <!-- 1 · LINHAS -->
      <div class="hub-block p-5 mb-8">
        <div class="hub-lp-head">
          <div class="min-w-0 flex-1">
            <h2 class="hub-h2"><span class="hub-h-ico i-lucide-chart-line" />1 · Linhas<span class="hub-h-sub">sessão a sessão</span></h2>
            <p class="hub-lp-q">Responde: como cada exercício andou ao longo do tempo? Onde travou, onde disparou?</p>
          </div>
          <div class="hub-seg flex-shrink-0">
            <button :class="{ 'is-on': lineMode === 'pct' }" title="Todos os exercícios na mesma régua" @click="lineMode = 'pct'">% desde o início</button>
            <button :class="{ 'is-on': lineMode === 'abs' }" @click="lineMode = 'abs'">{{ unit }}</button>
          </div>
          <button class="hub-lp-star" :class="{ 'is-on': isFav('linhas') }" title="Marcar como favorito" @click="toggleFav('linhas')"><span class="i-lucide-star" /></button>
        </div>
        <div style="height: 320px"><Line :data="lineChart" :options="lineOptions" /></div>
        <div v-if="noteMarks.some(n => n)" class="hub-lp-marks" :style="{ gridTemplateColumns: `repeat(${labels.length}, minmax(0, 1fr))` }">
          <span v-for="(n, i) in noteMarks" :key="i" :title="n ? notesForIndex(i).map(x => x.data?.text).join(' · ') : ''"><i v-if="n" /></span>
        </div>
        <p v-if="noteMarks.some(n => n)" class="text-[11px] text-n-slate-10 mt-1"><span class="hub-lp-dot" /> sessões com nota sua no período (passe o mouse no ponto pra ler)</p>
      </div>

      <!-- NOTAS -->
      <div class="hub-block p-5 mb-8 hub-orange">
        <div class="hub-sec">
          <span class="hub-sec-ico"><span class="i-lucide-notebook-pen" /></span>
          <div class="hub-sec-text">
            <p class="hub-sec-title">Notas</p>
            <p class="hub-sec-sub">coisas importantes que você fez — aparecem junto dos pontos do gráfico de linhas</p>
          </div>
        </div>
        <div class="hub-lp-note-form">
          <input v-model="noteForm.date" type="date" class="hub-field" style="width: 9.5rem" />
          <div class="flex gap-1.5 flex-wrap">
            <button v-for="t in NOTE_TAGS" :key="t.key" class="hub-tag" :class="{ 'is-on': noteForm.tag === t.key }" @click="noteForm.tag = t.key">
              <span :class="t.ico" class="hub-ico" style="width: 13px; height: 13px" />{{ t.label }}
            </button>
          </div>
        </div>
        <textarea
          v-model="noteForm.text"
          rows="2"
          maxlength="2000"
          placeholder="ex.: subi o supino pra 82 kg · dormi 5 h na véspera · troquei a barra fixa por puxada · comecei creatina"
          class="hub-lp-note-text"
          @keydown.meta.enter="addNote"
          @keydown.ctrl.enter="addNote"
        />
        <div class="flex items-center gap-2 mt-2">
          <span class="text-[11px] text-n-slate-10">⌘ + Enter salva</span>
          <div class="flex-1" />
          <button class="h-9 px-4 rounded-xl text-xs font-bold text-white" :style="{ background: GRAD_LARANJA, opacity: savingNote ? 0.6 : 1 }" :disabled="savingNote" @click="addNote">Salvar nota</button>
        </div>

        <template v-if="notesByMonth.length">
          <div v-for="g in notesByMonth" :key="g.key" class="mt-5">
            <p class="hub-label">{{ g.label }} · {{ g.items.length }}</p>
            <div class="hub-list">
              <div v-for="n in g.items" :key="n.id" class="hub-row" style="align-items: flex-start">
                <span class="hub-lp-note-ico" :style="{ background: tagOf(n.data?.tag).color }"><span :class="tagOf(n.data?.tag).ico" /></span>
                <span class="min-w-0 flex-1">
                  <span class="block text-[11px] font-bold text-n-slate-10">{{ fmtDay(n.record_date) }} · {{ tagOf(n.data?.tag).label }}<template v-if="n.data?.session_key"> · Treino {{ n.data.session_key }}</template></span>
                  <span class="block text-[13px] text-n-slate-12 leading-snug whitespace-pre-line">{{ n.data?.text }}</span>
                </span>
                <button class="hub-lp-del" title="Apagar nota" @click="removeNote(n)"><span class="i-lucide-trash-2" /></button>
              </div>
            </div>
          </div>
        </template>
        <p v-else class="text-xs text-n-slate-10 mt-4">Nenhuma nota ainda. A primeira pode ser de hoje.</p>
      </div>

      <div class="hub-grid-2 mb-8" style="gap: 32px 24px">
        <!-- 2 · BARRAS -->
        <div class="hub-block p-5" style="margin: 0">
          <div class="hub-lp-head">
            <div class="min-w-0 flex-1">
              <h2 class="hub-h2"><span class="hub-h-ico i-lucide-chart-column" />2 · Barras<span class="hub-h-sub">início × agora</span></h2>
              <p class="hub-lp-q">Responde: quanto cada exercício saiu do ponto de partida?</p>
            </div>
            <button class="hub-lp-star" :class="{ 'is-on': isFav('barras') }" @click="toggleFav('barras')"><span class="i-lucide-star" /></button>
          </div>
          <div style="height: 340px"><Bar :data="barChart" :options="barOptions" /></div>
        </div>

        <!-- 3 · RANKING -->
        <div class="hub-block p-5" style="margin: 0">
          <div class="hub-lp-head">
            <div class="min-w-0 flex-1">
              <h2 class="hub-h2"><span class="hub-h-ico i-lucide-chart-bar" />3 · Ranking<span class="hub-h-sub">ganho em %</span></h2>
              <p class="hub-lp-q">Responde: qual exercício mais evoluiu e qual está parado?</p>
            </div>
            <button class="hub-lp-star" :class="{ 'is-on': isFav('ganho') }" @click="toggleFav('ganho')"><span class="i-lucide-star" /></button>
          </div>
          <div :style="{ height: `${Math.max(300, ranked.length * 64 + 50)}px` }"><Bar :data="gainChart" :options="gainOptions" /></div>
        </div>

        <!-- 4 · RADAR -->
        <div class="hub-block p-5" style="margin: 0">
          <div class="hub-lp-head">
            <div class="min-w-0 flex-1">
              <h2 class="hub-h2"><span class="hub-h-ico i-lucide-radar" />4 · Radar<span class="hub-h-sub">a teia do treino</span></h2>
              <p class="hub-lp-q">Responde: o treino cresceu por igual ou tem um lado puxando mais? (cada eixo vai de 0 ao seu recorde)</p>
            </div>
            <button class="hub-lp-star" :class="{ 'is-on': isFav('radar') }" @click="toggleFav('radar')"><span class="i-lucide-star" /></button>
          </div>
          <div class="flex justify-center"><RadarChart :axes="radar.axes" :datasets="radar.datasets" :size="300" :label-size="9.5" /></div>
        </div>

        <!-- 5 · PIZZA -->
        <div class="hub-block p-5" style="margin: 0">
          <div class="hub-lp-head">
            <div class="min-w-0 flex-1">
              <h2 class="hub-h2"><span class="hub-h-ico i-lucide-chart-pie" />5 · Pizza<span class="hub-h-sub">de onde veio o ganho</span></h2>
              <p class="hub-lp-q">Responde: do total que você ganhou, quanto veio de cada exercício?</p>
            </div>
            <button class="hub-lp-star" :class="{ 'is-on': isFav('pizza') }" @click="toggleFav('pizza')"><span class="i-lucide-star" /></button>
          </div>
          <div v-if="gainers.length" class="relative" style="height: 300px">
            <Doughnut :data="pieChart" :options="pieOptions" />
            <div class="hub-lp-center"><b>+{{ fmtNum(pieTotal) }}</b><span>{{ unit }} no total</span></div>
          </div>
          <p v-else class="text-xs text-n-slate-10">Ainda sem ganho positivo neste treino.</p>
        </div>

        <!-- 6 · ÁREA -->
        <div class="hub-block p-5" style="margin: 0">
          <div class="hub-lp-head">
            <div class="min-w-0 flex-1">
              <h2 class="hub-h2"><span class="hub-h-ico i-lucide-chart-area" />6 · Área<span class="hub-h-sub">volume empilhado</span></h2>
              <p class="hub-lp-q">Responde: o trabalho total da sessão está subindo? Qual exercício pesa mais nele? (sempre em volume)</p>
            </div>
            <button class="hub-lp-star" :class="{ 'is-on': isFav('area') }" @click="toggleFav('area')"><span class="i-lucide-star" /></button>
          </div>
          <div style="height: 300px"><Line :data="areaChart" :options="areaOptions" /></div>
        </div>

        <!-- 7 · POLAR -->
        <div class="hub-block p-5" style="margin: 0">
          <div class="hub-lp-head">
            <div class="min-w-0 flex-1">
              <h2 class="hub-h2"><span class="hub-h-ico i-lucide-target" />7 · Polar<span class="hub-h-sub">pétalas de ganho</span></h2>
              <p class="hub-lp-q">Responde: o mesmo do ranking, em formato de flor — pétala maior = exercício que mais cresceu.</p>
            </div>
            <button class="hub-lp-star" :class="{ 'is-on': isFav('polar') }" @click="toggleFav('polar')"><span class="i-lucide-star" /></button>
          </div>
          <div style="height: 300px"><PolarArea :data="polarChart" :options="polarOptions" /></div>
        </div>
      </div>

      <!-- 8 · TABELA -->
      <div class="hub-block p-5 mb-8">
        <div class="hub-lp-head">
          <div class="min-w-0 flex-1">
            <h2 class="hub-h2"><span class="hub-h-ico i-lucide-table-2" />8 · Tabela<span class="hub-h-sub">os números exatos</span></h2>
            <p class="hub-lp-q">Responde: qual era a carga, qual é hoje e qual foi o recorde — sem interpretação.</p>
          </div>
          <button class="hub-lp-star" :class="{ 'is-on': isFav('tabela') }" @click="toggleFav('tabela')"><span class="i-lucide-star" /></button>
        </div>
        <div class="hub-lp-table-wrap">
          <table class="hub-lp-table">
            <thead>
              <tr><th>Exercício</th><th>Início</th><th>Agora</th><th>Recorde</th><th>Ganho</th><th>%</th><th>Sessões</th></tr>
            </thead>
            <tbody>
              <tr v-for="r in rows" :key="r.name">
                <td><i :style="{ background: r.color }" />{{ r.name }}</td>
                <td>{{ fmtNum(r.first) }}</td>
                <td><b>{{ fmtNum(r.last) }}</b></td>
                <td>{{ fmtNum(r.best) }}</td>
                <td :class="r.gain > 0 ? 'is-up' : r.gain < 0 ? 'is-down' : ''">{{ signed(r.gain) }} {{ unit }}</td>
                <td :class="r.pct > 0 ? 'is-up' : r.pct < 0 ? 'is-down' : ''">{{ signed(r.pct) }}%</td>
                <td>{{ r.n }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped>
.hub-lp-l { font-size: 10.5px; font-weight: 800; letter-spacing: 0.08em; text-transform: uppercase; color: #64748b; padding-top: 9px; }
.dark .hub-lp-l { color: rgba(255, 255, 255, 0.62); }
.hub-lp-seg { flex-wrap: wrap; }
/* celular: rótulo em cima, seletor embaixo ocupando a linha; o texto do
   cabeçalho do gráfico fica com a linha inteira e os botões descem */
@media (max-width: 639px) {
  .hub-lp :deep(.hub-form-row), .hub-lp .hub-form-row { grid-template-columns: minmax(0, 1fr) !important; gap: 4px !important; }
  .hub-lp-l { padding-top: 0; }
  .hub-lp-seg { display: flex; width: 100%; }
  .hub-lp-seg > button { flex: 1 1 auto; justify-content: center; padding: 0 8px; }
  .hub-lp-head > .min-w-0 { flex: 1 1 calc(100% - 48px); order: 1; }
  .hub-lp-head > .hub-lp-star { order: 2; }
  .hub-lp-head > .hub-seg { order: 3; width: 100%; display: flex; }
  .hub-lp-head > .hub-seg > button { flex: 1; justify-content: center; }
}
.hub-lp :deep(.hub-kpi-s) { white-space: normal; overflow: visible; text-overflow: clip; }
.hub-lp-count { margin-left: 6px; font-size: 10px; font-weight: 800; padding: 1px 6px; border-radius: 9999px; background: rgba(255, 138, 0, 0.18); color: #b85c00; }
.dark .hub-lp-count { color: #ffc17a; }
.is-on > .hub-lp-count, .dark .is-on > .hub-lp-count { background: rgba(26, 14, 0, 0.18); color: #1a0e00; }

.hub-lp-head { display: flex; align-items: flex-start; gap: 12px; margin-bottom: 14px; flex-wrap: wrap; }
.hub-lp-q { font-size: 12px; line-height: 1.45; color: #64748b; margin: 4px 0 0; }
.dark .hub-lp-q { color: rgba(255, 255, 255, 0.66); }
.hub-lp-star {
  flex-shrink: 0;
  width: 36px;
  height: 36px;
  border-radius: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #94a3b8;
  border: 1px solid rgba(148, 163, 184, 0.4);
  transition: all 0.15s ease;
}
.hub-lp-star > span { width: 17px; height: 17px; }
.hub-lp-star:hover { color: #ff8a00; border-color: rgba(255, 138, 0, 0.6); }
.hub-lp-star.is-on { color: #1a0e00; background: linear-gradient(135deg, #ff6b1a, #ffb300); border-color: transparent; box-shadow: 0 6px 14px -6px rgba(255, 138, 0, 0.7); }

.hub-lp-marks { display: grid; padding: 0 8px 0 44px; margin-top: 2px; }
.hub-lp-marks > span { display: flex; justify-content: center; height: 8px; }
.hub-lp-marks i, .hub-lp-dot { display: inline-block; width: 7px; height: 7px; border-radius: 9999px; background: #ff8a00; }

.hub-lp-center { position: absolute; inset: 0 0 46px 0; display: flex; flex-direction: column; align-items: center; justify-content: center; pointer-events: none; }
.hub-lp-center b { font-size: 22px; font-weight: 800; color: #b85c00; line-height: 1; }
.dark .hub-lp-center b { color: #ffb25e; }
.hub-lp-center span { font-size: 10.5px; color: #64748b; margin-top: 3px; }
.dark .hub-lp-center span { color: rgba(255, 255, 255, 0.62); }

.hub-lp-note-form { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; margin-bottom: 10px; }
.hub-lp-note-text {
  display: block;
  width: 100%;
  border-radius: 14px;
  border: 1px solid rgba(255, 138, 0, 0.4);
  background: rgba(255, 255, 255, 0.9);
  padding: 12px 14px;
  font-size: 13.5px;
  line-height: 1.5;
  margin: 0 !important;
  resize: vertical;
  min-height: 64px;
}
.hub-lp-note-text:focus { outline: none; border-color: #ff8a00; box-shadow: 0 0 0 3px rgba(255, 138, 0, 0.18); }
.dark .hub-lp-note-text { background: rgba(255, 255, 255, 0.05); color: #fff; }
.hub-lp-note-ico { flex-shrink: 0; width: 28px; height: 28px; border-radius: 8px; display: grid; place-content: center; color: #fff; margin-top: 2px; }
.hub-lp-note-ico > span { width: 15px; height: 15px; }
.hub-lp-del { flex-shrink: 0; width: 30px; height: 30px; border-radius: 9px; display: grid; place-content: center; color: #94a3b8; }
.hub-lp-del:hover { color: #e5484d; background: rgba(229, 72, 77, 0.1); }
.hub-lp-del > span { width: 15px; height: 15px; }

.hub-lp-table-wrap { overflow-x: auto; border-radius: 14px; border: 1px solid rgba(65, 105, 225, 0.2); }
.hub-lp-table { width: 100%; border-collapse: collapse; font-size: 12.5px; min-width: 620px; margin: 0; }
.hub-lp-table th { text-align: right; font-size: 10.5px; font-weight: 800; letter-spacing: 0.07em; text-transform: uppercase; color: #64748b; padding: 10px 12px; background: rgba(65, 105, 225, 0.07); white-space: nowrap; }
.hub-lp-table th:first-child, .hub-lp-table td:first-child { text-align: left; }
.hub-lp-table td { text-align: right; padding: 11px 12px; border-top: 1px solid rgba(65, 105, 225, 0.12); color: #0f172a; white-space: nowrap; font-variant-numeric: tabular-nums; }
.hub-lp-table td:first-child { white-space: normal; font-weight: 600; }
.hub-lp-table td i { display: inline-block; width: 9px; height: 9px; border-radius: 3px; margin-right: 8px; vertical-align: 0; }
.hub-lp-table td.is-up { color: #b85c00; font-weight: 700; }
.hub-lp-table td.is-down { color: #e5484d; font-weight: 700; }
.dark .hub-lp-table th { color: rgba(255, 255, 255, 0.62); background: rgba(255, 255, 255, 0.05); }
.dark .hub-lp-table td { color: rgba(255, 255, 255, 0.9); border-top-color: rgba(255, 255, 255, 0.08); }
.dark .hub-lp-table td.is-up { color: #ffb25e; }
.dark .hub-lp-table-wrap { border-color: rgba(255, 255, 255, 0.12); }
</style>
