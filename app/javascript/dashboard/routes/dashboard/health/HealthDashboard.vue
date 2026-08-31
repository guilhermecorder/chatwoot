<script setup>
// DASHBOARD DA SAÚDE (HUB) — os resultados virando gráfico (pedido 25/08):
// TREINO: volume por semana (por treino A/B/C e total), acumulado das 24
// semanas e evolução por exercício — linha e área.
// DIETA: calorias e proteína dia a dia contra a meta + quais refeições
// foram feitas em cada dia e o HORÁRIO real em que foram marcadas.
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';
import {
  Chart as ChartJS,
  Tooltip,
  Legend,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Filler,
} from 'chart.js';
import { Line } from 'vue-chartjs';
import { exerciseVerdict } from './warrior';

ChartJS.register(Tooltip, Legend, CategoryScale, LinearScale, PointElement, LineElement, Filler);

const VERDE = '#10B981';
const VERDE_ESCURO = '#065F46';
const OURO = '#D4A017';
const AZUL = '#0F5FA6';
const ROXO = '#7C3AED';
const ROSA = '#EC4899';

const isLoading = ref(true);
const config = ref({});
const workouts = ref([]);
const boxings = ref([]);
const diets = ref([]);
const bodies = ref([]);
const dashTab = ref('visao');

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
const daysAgo = n => {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return toISO(d);
};
// 1RM estimado (Epley): a força REAL, comparável entre reps diferentes
const e1rm = (load, reps) => (reps > 0 ? load * (1 + reps / 30) : load);
// tendência linear (mínimos quadrados) → variação por dia
const fitSlopePerDay = pts => {
  // pts = [{ x: dias desde o início, y }]
  if (pts.length < 2) return null;
  const n = pts.length;
  const sx = pts.reduce((s, p) => s + p.x, 0);
  const sy = pts.reduce((s, p) => s + p.y, 0);
  const sxx = pts.reduce((s, p) => s + p.x * p.x, 0);
  const sxy = pts.reduce((s, p) => s + p.x * p.y, 0);
  const den = n * sxx - sx * sx;
  if (!den) return null;
  return (n * sxy - sx * sy) / den;
};
const dayIndex = iso => Math.floor(new Date(`${iso}T00:00:00`).getTime() / 86400000);
// volume em kg → "12,4 t" quando passa de 1000
const fmtVol = v => (v >= 1000 ? `${(v / 1000).toFixed(1).replace('.', ',')} t` : `${Math.round(v)} kg`);

const programs = computed(() => config.value?.programs || []);
const mainProgram = computed(() => programs.value.find(p => p.id === 'warrior24') || null);
const dietCfg = computed(() => {
  const d = config.value?.diet || {};
  return { targets: d.targets || {}, meals: d.meals || [] };
});

// ═══ TREINO ═════════════════════════════════════════════════════════
const recVolume = rec =>
  (rec.data?.exercises || []).reduce(
    (sum, ex) =>
      sum + (ex.sets || []).reduce((s, set) => s + (Number(set.load) || 0) * (Number(set.reps) || 0), 0),
    0
  );

const progRecords = computed(() =>
  workouts.value.filter(w => w.data?.program_id && recVolume(w) > 0)
);
const mainRecords = computed(() =>
  progRecords.value.filter(w => w.data?.program_id === 'warrior24' && Number(w.data?.week) >= 1)
);

const totalWeeks = computed(() => {
  const cycles = mainProgram.value?.cycles || [];
  return cycles.length ? Math.max(...cycles.map(c => c.week_end || 0)) : 24;
});
const currentWeek = computed(() => {
  if (!mainProgram.value?.start_date) return null;
  const diff = Math.floor(
    (new Date(`${todayISO}T00:00:00`) - new Date(`${mainProgram.value.start_date}T00:00:00`)) / 86400000
  );
  return diff < 0 ? 1 : Math.min(Math.floor(diff / 7) + 1, totalWeeks.value);
});

// volume semana a semana, quebrado por treino A/B/C
const weeklyVolumes = computed(() => {
  const weeks = Array.from({ length: totalWeeks.value }, (_, i) => ({
    week: i + 1,
    total: 0,
    A: 0,
    B: 0,
    C: 0,
  }));
  mainRecords.value.forEach(w => {
    const idx = Number(w.data.week) - 1;
    if (idx < 0 || idx >= weeks.length) return;
    const vol = recVolume(w);
    weeks[idx].total += vol;
    const key = w.data.session_key;
    if (key && weeks[idx][key] !== undefined) weeks[idx][key] += vol;
  });
  return weeks;
});

const weekLabels = computed(() => weeklyVolumes.value.map(w => `S${w.week}`));

const lineBase = (label, color, data, { area = false, dashed = false, axis = 'y' } = {}) => ({
  label,
  data,
  borderColor: color,
  backgroundColor: area ? `${color}33` : color,
  fill: area,
  tension: 0.35,
  borderWidth: 2,
  pointRadius: 2,
  borderDash: dashed ? [6, 4] : undefined,
  yAxisID: axis,
});

const chartOptions = (extra = {}) => ({
  responsive: true,
  maintainAspectRatio: false,
  plugins: { legend: { position: 'bottom', labels: { boxWidth: 10, font: { size: 10 } } } },
  scales: { y: { beginAtZero: true, ticks: { font: { size: 10 } } }, x: { ticks: { font: { size: 10 } } } },
  ...extra,
});

const volumeChart = computed(() => ({
  labels: weekLabels.value,
  datasets: [
    lineBase('Total', VERDE, weeklyVolumes.value.map(w => w.total), { area: true }),
    lineBase('Treino A', AZUL, weeklyVolumes.value.map(w => w.A)),
    lineBase('Treino B', ROXO, weeklyVolumes.value.map(w => w.B)),
    lineBase('Treino C', ROSA, weeklyVolumes.value.map(w => w.C)),
  ],
}));

const cumulativeChart = computed(() => {
  let acc = 0;
  const data = weeklyVolumes.value.map(w => {
    acc += w.total;
    return acc;
  });
  return {
    labels: weekLabels.value,
    datasets: [lineBase('Volume acumulado', OURO, data, { area: true })],
  };
});

// evolução por exercício (todos os programas, inclusive Bônus)
const exOptions = computed(() => {
  const names = new Set();
  programs.value.forEach(p =>
    (p.cycles || []).forEach(c =>
      (c.sessions || []).forEach(s => (s.exercises || []).forEach(ex => ex.name && names.add(ex.name)))
    )
  );
  workouts.value.forEach(w => (w.data?.exercises || []).forEach(ex => ex.name && names.add(ex.name)));
  return [...names].sort();
});
const exSelected = ref('');
const exChart = computed(() => {
  if (!exSelected.value) return null;
  const hist = exHistory.value[exSelected.value] || [];
  const points = [...workouts.value]
    .filter(w => (w.data?.exercises || []).some(e => e.name === exSelected.value && e.sets?.length))
    .sort((a, b) => (a.record_date > b.record_date ? 1 : -1))
    .map(w => {
      const ex = w.data.exercises.find(e => e.name === exSelected.value);
      const top = Math.max(...ex.sets.map(s => Number(s.load) || 0));
      const vol = ex.sets.reduce((s, set) => s + (Number(set.load) || 0) * (Number(set.reps) || 0), 0);
      const label = w.data.week ? `S${w.data.week}` : fmtDay(w.record_date);
      return { label, top, vol };
    });
  if (!points.length) return null;
  return {
    labels: points.map(p => p.label),
    datasets: [
      lineBase('Carga máxima (kg)', VERDE, points.map(p => p.top)),
      lineBase('e-1RM (força estimada)', OURO, hist.map(p => p.e1), { dashed: true }),
      lineBase('Volume (kg)', AZUL, points.map(p => p.vol), { area: true, axis: 'y1' }),
    ],
  };
});
const exChartOptions = chartOptions({
  scales: {
    y: { beginAtZero: true, ticks: { font: { size: 10 } }, title: { display: true, text: 'carga (kg)', font: { size: 10 } } },
    y1: { beginAtZero: true, position: 'right', grid: { drawOnChartArea: false }, ticks: { font: { size: 10 } }, title: { display: true, text: 'volume (kg)', font: { size: 10 } } },
    x: { ticks: { font: { size: 10 } } },
  },
});

const totalVolume = computed(() => progRecords.value.reduce((s, w) => s + recVolume(w), 0));

// ── histórico POR EXERCÍCIO: carga máxima + e-1RM por sessão ───────
const exHistory = computed(() => {
  const map = {};
  [...workouts.value]
    .sort((a, b) => (a.record_date > b.record_date ? 1 : -1))
    .forEach(w =>
      (w.data?.exercises || []).forEach(ex => {
        if (!ex.sets?.length) return;
        const top = Math.max(...ex.sets.map(s => Number(s.load) || 0));
        if (top <= 0) return;
        const best = Math.max(...ex.sets.map(s => e1rm(Number(s.load) || 0, Number(s.reps) || 0)));
        if (!map[ex.name]) map[ex.name] = [];
        map[ex.name].push({
          date: w.record_date,
          label: w.data.week ? `S${w.data.week}` : fmtDay(w.record_date),
          top,
          e1: Math.round(best * 10) / 10,
        });
      })
    );
  return map;
});
const exSeriesAll = exHistory;
const exercisesWithData = computed(() => Object.keys(exHistory.value).sort());

// ── recordes pessoais (melhor carga e melhor e-1RM, com data) ──────
const personalRecords = computed(() =>
  Object.entries(exHistory.value)
    .map(([name, pts]) => {
      let bestLoad = { v: 0, date: null };
      let bestE1 = { v: 0, date: null };
      pts.forEach(p => {
        if (p.top > bestLoad.v) bestLoad = { v: p.top, date: p.date };
        if (p.e1 > bestE1.v) bestE1 = { v: p.e1, date: p.date };
      });
      return { name, bestLoad, bestE1, recent: bestE1.date >= daysAgo(7) };
    })
    .sort((a, b) => b.bestE1.v - a.bestE1.v)
);
const recentPRs = computed(() => personalRecords.value.filter(r => r.recent));
const miniChart = name => {
  const pts = exSeriesAll.value[name] || [];
  return {
    labels: pts.map(p => p.label),
    datasets: [lineBase('kg', VERDE, pts.map(p => p.top), { area: true })],
  };
};
const miniOptions = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: { legend: { display: false } },
  scales: { y: { display: false }, x: { display: false } },
};
const lastTop = name => {
  const pts = exSeriesAll.value[name] || [];
  return pts.length ? pts[pts.length - 1].top : 0;
};

// ── placar de progressão POR SEMANA (calculado dos dados brutos:
// cada treino comparado ao MESMO treino da ocorrência anterior) ─────
const weeklyVerdicts = computed(() => {
  const weeks = Array.from({ length: totalWeeks.value }, (_, i) => ({
    week: i + 1,
    progress: 0,
    tie: 0,
    regress: 0,
  }));
  const recs = [...mainRecords.value].sort((a, b) => Number(a.data.week) - Number(b.data.week));
  recs.forEach(rec => {
    const w = Number(rec.data.week);
    if (w < 1 || w > weeks.length) return;
    const prev = recs
      .filter(r => r.data.session_key === rec.data.session_key && Number(r.data.week) < w)
      .sort((a, b) => Number(b.data.week) - Number(a.data.week))[0];
    if (!prev) return;
    (rec.data.exercises || []).forEach(ex => {
      if (!ex.sets?.length) return;
      const last = (prev.data.exercises || []).find(e => e.name === ex.name)?.sets;
      if (!last?.length) return;
      const verdict = exerciseVerdict(ex.sets, last);
      if (weeks[w - 1][verdict] !== undefined) weeks[w - 1][verdict] += 1;
    });
  });
  return weeks;
});
const totalProgress = computed(() => weeklyVerdicts.value.reduce((s, w) => s + w.progress, 0));
const verdictChart = computed(() => ({
  labels: weekLabels.value,
  datasets: [
    lineBase('▲ progressões', '#059669', weeklyVerdicts.value.map(w => w.progress), { area: true }),
    lineBase('▬ empates', '#94A3B8', weeklyVerdicts.value.map(w => w.tie)),
    lineBase('▼ regressões', '#DC2626', weeklyVerdicts.value.map(w => w.regress)),
  ],
}));

// ── séries e repetições por semana ─────────────────────────────────
const weeklySetsReps = computed(() => {
  const weeks = Array.from({ length: totalWeeks.value }, () => ({ sets: 0, reps: 0 }));
  mainRecords.value.forEach(w => {
    const idx = Number(w.data.week) - 1;
    if (idx < 0 || idx >= weeks.length) return;
    (w.data.exercises || []).forEach(ex =>
      (ex.sets || []).forEach(s => {
        weeks[idx].sets += 1;
        weeks[idx].reps += Number(s.reps) || 0;
      })
    );
  });
  return weeks;
});
const setsRepsChart = computed(() => ({
  labels: weekLabels.value,
  datasets: [
    lineBase('Séries', ROXO, weeklySetsReps.value.map(w => w.sets)),
    lineBase('Repetições', ROSA, weeklySetsReps.value.map(w => w.reps), { area: true, axis: 'y1' }),
  ],
}));
const setsRepsOptions = chartOptions({
  scales: {
    y: { beginAtZero: true, ticks: { font: { size: 10 } }, title: { display: true, text: 'séries', font: { size: 10 } } },
    y1: { beginAtZero: true, position: 'right', grid: { drawOnChartArea: false }, ticks: { font: { size: 10 } }, title: { display: true, text: 'reps', font: { size: 10 } } },
    x: { ticks: { font: { size: 10 } } },
  },
});

// ═══ BOXE ═══════════════════════════════════════════════════════════
const BOX_DAYS = 30;
const boxTotalMin = computed(() => boxings.value.reduce((s, b) => s + (Number(b.data?.duration_min) || 0), 0));
const boxTotalRounds = computed(() => boxings.value.reduce((s, b) => s + (Number(b.data?.rounds) || 0), 0));
const fmtHours = min => (min >= 60 ? `${(min / 60).toFixed(1).replace('.', ',')} h` : `${Math.round(min)} min`);

const boxTimeline = computed(() => {
  const days = [];
  for (let i = BOX_DAYS - 1; i >= 0; i -= 1) {
    const d = new Date();
    d.setDate(d.getDate() - i);
    const iso = toISO(d);
    const recs = boxings.value.filter(b => b.record_date === iso);
    days.push({
      iso,
      min: recs.reduce((s, b) => s + (Number(b.data?.duration_min) || 0), 0),
      rounds: recs.reduce((s, b) => s + (Number(b.data?.rounds) || 0), 0),
    });
  }
  return days;
});
const boxChart = computed(() => ({
  labels: boxTimeline.value.map(d => fmtDay(d.iso)),
  datasets: [
    lineBase('Minutos', ROXO, boxTimeline.value.map(d => d.min), { area: true }),
    lineBase('Rounds', OURO, boxTimeline.value.map(d => d.rounds), { axis: 'y1' }),
  ],
}));
const boxChartOptions = chartOptions({
  scales: {
    y: { beginAtZero: true, ticks: { font: { size: 10 } }, title: { display: true, text: 'minutos', font: { size: 10 } } },
    y1: { beginAtZero: true, position: 'right', grid: { drawOnChartArea: false }, ticks: { font: { size: 10 } }, title: { display: true, text: 'rounds', font: { size: 10 } } },
    x: { ticks: { font: { size: 10 } } },
  },
});
const boxCumChart = computed(() => {
  let acc = 0;
  const data = boxTimeline.value.map(d => {
    acc += d.min;
    return Math.round((acc / 60) * 10) / 10;
  });
  return {
    labels: boxTimeline.value.map(d => fmtDay(d.iso)),
    datasets: [lineBase('Horas acumuladas (30d)', ROXO, data, { area: true })],
  };
});
// ═══ VISÃO GERAL: transformação, projeções, constância, insights ═══

// buckets de 12 semanas-calendário (segunda a domingo) até hoje
const calendarWeeks = computed(() => {
  const weeks = [];
  const today = new Date(`${todayISO}T00:00:00`);
  const monday = new Date(today);
  monday.setDate(monday.getDate() - ((monday.getDay() + 6) % 7)); // segunda desta semana
  for (let i = 11; i >= 0; i -= 1) {
    const start = new Date(monday);
    start.setDate(start.getDate() - i * 7);
    const end = new Date(start);
    end.setDate(end.getDate() + 6);
    weeks.push({ start: toISO(start), end: toISO(end) });
  }
  return weeks;
});
const inWindow = (iso, w) => iso >= w.start && iso <= w.end;
const avgOrNull = arr => (arr.length ? arr.reduce((s, v) => s + v, 0) / arr.length : null);

// e-1RM médio de um treino (média dos melhores e-1RM de cada exercício)
const recStrength = rec => {
  const vals = (rec.data?.exercises || [])
    .filter(ex => ex.sets?.length)
    .map(ex => Math.max(...ex.sets.map(s => e1rm(Number(s.load) || 0, Number(s.reps) || 0))));
  return vals.length ? vals.reduce((s, v) => s + v, 0) / vals.length : null;
};

const transformationChart = computed(() => {
  const rows = calendarWeeks.value.map(w => {
    const pesos = bodies.value.filter(b => inWindow(b.record_date, w) && Number(b.data?.weight) > 0).map(b => Number(b.data.weight));
    const forcas = workouts.value.filter(r => inWindow(r.record_date, w)).map(recStrength).filter(v => v !== null);
    const kcals = diets.value.filter(d => inWindow(d.record_date, w)).map(d => dayTotalsFor(d).kcal);
    return {
      label: fmtDay(w.start),
      peso: avgOrNull(pesos),
      forca: avgOrNull(forcas),
      kcal: avgOrNull(kcals),
    };
  });
  return {
    labels: rows.map(r => r.label),
    datasets: [
      lineBase('Peso (kg)', AZUL, rows.map(r => (r.peso === null ? null : Math.round(r.peso * 10) / 10))),
      lineBase('Força e-1RM média (kg)', VERDE, rows.map(r => (r.forca === null ? null : Math.round(r.forca * 10) / 10)), { axis: 'y1' }),
      lineBase('Calorias médias/dia', OURO, rows.map(r => (r.kcal === null ? null : Math.round(r.kcal))), { dashed: true, axis: 'y2' }),
    ],
  };
});
const transformationOptions = chartOptions({
  spanGaps: true,
  scales: {
    y: { ticks: { font: { size: 10 } }, title: { display: true, text: 'peso (kg)', font: { size: 10 } } },
    y1: { position: 'right', grid: { drawOnChartArea: false }, ticks: { font: { size: 10 } }, title: { display: true, text: 'força (kg)', font: { size: 10 } } },
    y2: { display: false },
    x: { ticks: { font: { size: 10 } } },
  },
});

// projeções: tendência dos últimos 30 dias → ritmo por mês
const trend30 = pts => {
  const base = pts.filter(p => p.date >= daysAgo(30));
  if (base.length < 2 || dayIndex(base[base.length - 1].date) - dayIndex(base[0].date) < 5) return null;
  const x0 = dayIndex(base[0].date);
  const slope = fitSlopePerDay(base.map(p => ({ x: dayIndex(p.date) - x0, y: p.v })));
  return slope === null ? null : slope * 30;
};
const pesoTrend = computed(() =>
  trend30(
    [...bodies.value]
      .filter(b => Number(b.data?.weight) > 0)
      .sort((a, b) => (a.record_date > b.record_date ? 1 : -1))
      .map(b => ({ date: b.record_date, v: Number(b.data.weight) }))
  )
);
const forcaTrend = computed(() =>
  trend30(
    [...workouts.value]
      .sort((a, b) => (a.record_date > b.record_date ? 1 : -1))
      .map(r => ({ date: r.record_date, v: recStrength(r) }))
      .filter(p => p.v !== null)
  )
);
const latestWeight = computed(() => {
  const rec = [...bodies.value].sort((a, b) => (a.record_date < b.record_date ? 1 : -1)).find(b => Number(b.data?.weight) > 0);
  return rec ? Number(rec.data.weight) : null;
});
const sinal = v => `${v > 0 ? '+' : '−'}${fmtNum(Math.abs(v))}`;

// ── mapa de constância (heatmap, últimas 24 semanas) ───────────────
const trainedByDate = computed(() => {
  const map = {};
  workouts.value.forEach(w => {
    map[w.record_date] = { ...(map[w.record_date] || {}), musc: true };
  });
  boxings.value.forEach(b => {
    map[b.record_date] = { ...(map[b.record_date] || {}), boxe: true };
  });
  return map;
});
const heatmap = computed(() => {
  const today = new Date(`${todayISO}T00:00:00`);
  const monday = new Date(today);
  monday.setDate(monday.getDate() - ((monday.getDay() + 6) % 7));
  const cols = [];
  for (let wk = 23; wk >= 0; wk -= 1) {
    const col = [];
    for (let dow = 0; dow < 7; dow += 1) {
      const d = new Date(monday);
      d.setDate(d.getDate() - wk * 7 + dow);
      const iso = toISO(d);
      const info = trainedByDate.value[iso];
      let tone = 'vazio';
      if (iso > todayISO) tone = 'futuro';
      else if (info?.musc && info?.boxe) tone = 'ambos';
      else if (info?.musc) tone = 'musc';
      else if (info?.boxe) tone = 'boxe';
      col.push({ iso, tone, hoje: iso === todayISO });
    }
    cols.push(col);
  }
  return cols;
});
const HEAT_COLORS = {
  musc: VERDE,
  boxe: ROXO,
  ambos: `linear-gradient(135deg, ${VERDE} 50%, ${ROXO} 50%)`,
  vazio: 'rgba(148, 163, 184, 0.18)',
  futuro: 'transparent',
};

// ── aderência ao plano (3 sessões/semana do programa) ──────────────
const adherenceChart = computed(() => {
  const upto = Math.min(currentWeek.value || 0, totalWeeks.value);
  if (!upto) return null;
  const labels = [];
  const data = [];
  for (let w = 1; w <= upto; w += 1) {
    labels.push(`S${w}`);
    const done = new Set(
      mainRecords.value.filter(r => Number(r.data.week) === w).map(r => r.data.session_key)
    ).size;
    data.push(Math.round((done / 3) * 100));
  }
  return { labels, datasets: [lineBase('% das 3 sessões feitas', VERDE, data, { area: true })] };
});
const adherenceOptions = chartOptions({
  scales: { y: { beginAtZero: true, max: 100, ticks: { font: { size: 10 } } }, x: { ticks: { font: { size: 10 } } } },
});

// ── balanço muscular (volume por grupo, mapeado pelo nome) ─────────
const MUSCLE_GROUPS = [
  { label: 'Empurrar (peito)', match: /supino|crucifixo(?! inverso)|paralelas/i, cor: AZUL },
  { label: 'Ombros', match: /desenvolvimento|elevação lateral|remada alta/i, cor: OURO },
  { label: 'Puxar (costas)', match: /barra fixa|remada baixa|crucifixo inverso/i, cor: VERDE },
  { label: 'Braços', match: /rosca|tríceps/i, cor: ROXO },
  { label: 'Pernas', match: /agachamento|terra|extensora|afundo|hip thrust|pélvica|panturrilha/i, cor: ROSA },
  { label: 'Core', match: /joelhos|abdominal|prancha/i, cor: '#64748B' },
];
const muscleBalance = computed(() => {
  const totals = MUSCLE_GROUPS.map(g => ({ ...g, vol: 0 }));
  let outros = 0;
  workouts.value.forEach(w =>
    (w.data?.exercises || []).forEach(ex => {
      const vol = (ex.sets || []).reduce((s, set) => s + (Number(set.load) || 0) * (Number(set.reps) || 0), 0);
      if (!vol) return;
      const grupo = totals.find(g => g.match.test(ex.name));
      if (grupo) grupo.vol += vol;
      else outros += vol;
    })
  );
  if (outros > 0) totals.push({ label: 'Outros', cor: '#94A3B8', vol: outros });
  const max = Math.max(1, ...totals.map(t => t.vol));
  const sum = totals.reduce((s, t) => s + t.vol, 0) || 1;
  return totals
    .filter(t => t.vol > 0)
    .map(t => ({ ...t, pct: Math.round((t.vol / sum) * 100), bar: (t.vol / max) * 100 }))
    .sort((a, b) => b.vol - a.vol);
});

// ── insights automáticos (regras sobre o que já foi calculado) ─────
const insights = computed(() => {
  const list = [];
  // recordes da semana
  if (recentPRs.value.length) {
    list.push({
      icon: '🏅',
      tone: VERDE,
      text: `Recorde pessoal esta semana: ${recentPRs.value.slice(0, 2).map(r => r.name).join(' e ')}${recentPRs.value.length > 2 ? ` (+${recentPRs.value.length - 2})` : ''}.`,
    });
  }
  // estagnação: 3 sessões seguidas sem superar o melhor e-1RM anterior
  const estagnado = Object.entries(exHistory.value).find(([, pts]) => {
    if (pts.length < 4) return false;
    const antes = Math.max(...pts.slice(0, -3).map(p => p.e1));
    return pts.slice(-3).every(p => p.e1 <= antes);
  });
  if (estagnado) {
    list.push({
      icon: '🧊',
      tone: OURO,
      text: `${estagnado[0]} está estagnado há 3 sessões — o Warrior sugere reduzir ~10% a carga e reconstruir.`,
    });
  }
  // peso: tendência de 30 dias
  if (pesoTrend.value !== null) {
    if (pesoTrend.value < -0.1) {
      list.push({ icon: '📉', tone: VERDE, text: `Peso caindo ${fmtNum(Math.abs(pesoTrend.value))} kg/mês no ritmo atual — cutting funcionando.` });
    } else if (pesoTrend.value > 0.3) {
      list.push({ icon: '⚠️', tone: OURO, text: `Peso subindo ${fmtNum(pesoTrend.value)} kg/mês — confira as calorias contra a meta.` });
    }
  }
  // proteína baixa na semana
  const dias7 = diets.value.filter(d => d.record_date >= daysAgo(6));
  const alvoProt = Number(dietCfg.value.targets?.protein) || 0;
  if (alvoProt && dias7.length >= 3) {
    const abaixo = dias7.filter(d => dayTotalsFor(d).protein < alvoProt * 0.8).length;
    if (abaixo >= 3) {
      list.push({ icon: '🥩', tone: OURO, text: `Proteína abaixo de 80% da meta em ${abaixo} dos últimos ${dias7.length} dias registrados.` });
    }
  }
  // sessão planejada faltando nesta semana do programa
  if (currentWeek.value) {
    const feitas = new Set(
      mainRecords.value.filter(r => Number(r.data.week) === currentWeek.value).map(r => r.data.session_key)
    );
    const dow = (new Date(`${todayISO}T00:00:00`).getDay() + 6) % 7; // 0=segunda
    const esperadas = [dow >= 0 && 'A', dow >= 2 && 'B', dow >= 4 && 'C'].filter(Boolean);
    const faltando = esperadas.filter(k => !feitas.has(k));
    if (faltando.length) {
      list.push({ icon: '⏰', tone: OURO, text: `Semana ${currentWeek.value}: falta o Treino ${faltando.join(' e o ')} previsto até aqui.` });
    } else if (esperadas.length) {
      list.push({ icon: '✅', tone: VERDE, text: `Semana ${currentWeek.value} em dia: ${esperadas.length} de 3 sessões previstas até hoje, todas feitas.` });
    }
  }
  // melhor semana de volume
  const vols = weeklyVolumes.value.filter(w => w.total > 0);
  if (vols.length >= 2) {
    const ultima = vols[vols.length - 1];
    if (ultima.total === Math.max(...vols.map(w => w.total))) {
      list.push({ icon: '🔥', tone: VERDE, text: `S${ultima.week} é a sua melhor semana de volume até agora (${fmtVol(ultima.total)}).` });
    }
  }
  if (!list.length) {
    list.push({ icon: '🏁', tone: AZUL, text: 'Registre treinos, peso e dieta — os insights nascem sozinhos daqui.' });
  }
  return list.slice(0, 6);
});

// sequência mais praticada (30d)
const boxTopSeqs = computed(() => {
  const seqs = config.value?.boxing?.sequences || [];
  const count = {};
  boxings.value.forEach(b => (b.data?.sequences || []).forEach(id => { count[id] = (count[id] || 0) + 1; }));
  return Object.entries(count)
    .map(([id, n]) => ({ name: seqs.find(s => s.id === id)?.name || id, n }))
    .sort((a, b) => b.n - a.n)
    .slice(0, 5);
});

// ═══ DIETA ══════════════════════════════════════════════════════════
const DIET_DAYS = 21;
const dietByDate = computed(() => {
  const map = {};
  diets.value.forEach(d => {
    map[d.record_date] = d;
  });
  return map;
});
const dietTimeline = computed(() => {
  const days = [];
  for (let i = DIET_DAYS - 1; i >= 0; i -= 1) {
    const d = new Date();
    d.setDate(d.getDate() - i);
    const iso = toISO(d);
    days.push({ iso, rec: dietByDate.value[iso] || null });
  }
  return days;
});

const dayTotalsFor = rec => {
  const totals = { kcal: 0, protein: 0 };
  if (!rec) return totals;
  const done = rec.data?.meals_done || [];
  dietCfg.value.meals
    .filter(m => done.includes(m.id))
    .concat(rec.data?.extras || [])
    .forEach(m => {
      totals.kcal += Number(m.kcal) || 0;
      totals.protein += Number(m.protein) || 0;
    });
  return totals;
};

const dietLabels = computed(() => dietTimeline.value.map(d => fmtDay(d.iso)));
const kcalChart = computed(() => ({
  labels: dietLabels.value,
  datasets: [
    lineBase('Calorias', VERDE, dietTimeline.value.map(d => dayTotalsFor(d.rec).kcal), { area: true }),
    lineBase('Meta', OURO, dietTimeline.value.map(() => Number(dietCfg.value.targets?.kcal) || 0), { dashed: true }),
  ],
}));
const proteinChart = computed(() => ({
  labels: dietLabels.value,
  datasets: [
    lineBase('Proteína (g)', AZUL, dietTimeline.value.map(d => dayTotalsFor(d.rec).protein), { area: true }),
    lineBase('Meta', OURO, dietTimeline.value.map(() => Number(dietCfg.value.targets?.protein) || 0), { dashed: true }),
  ],
}));

const last7 = computed(() => dietTimeline.value.slice(-7));
const avg7 = key => {
  const withData = last7.value.filter(d => d.rec);
  if (!withData.length) return 0;
  return Math.round(withData.reduce((s, d) => s + dayTotalsFor(d.rec)[key], 0) / withData.length);
};
const adherence7 = computed(() => {
  const total = dietCfg.value.meals.length;
  const withData = last7.value.filter(d => d.rec);
  if (!total || !withData.length) return 0;
  const pct = withData.reduce((s, d) => s + (d.rec.data?.meals_done || []).length / total, 0) / withData.length;
  return Math.round(pct * 100);
});

// refeições × dias (com o horário REAL marcado; sem horário = o do plano)
const mealDays = computed(() => [...dietTimeline.value].reverse().slice(0, 14));
const mealCell = (day, meal) => {
  if (!day.rec) return null;
  const done = (day.rec.data?.meals_done || []).includes(meal.id);
  if (!done) return { done: false };
  const at = day.rec.data?.meals_done_at?.[meal.id];
  return { done: true, at: at || meal.time || '', real: Boolean(at) };
};

onMounted(async () => {
  try {
    const { data: payload } = await CrmAPI.getHealth();
    config.value = payload.config || {};
    workouts.value = payload.workouts || [];
    boxings.value = payload.boxings || [];
    diets.value = payload.diets || [];
    bodies.value = payload.bodies || [];
    if (exOptions.value.includes('Supino inclinado com barra')) {
      exSelected.value = 'Supino inclinado com barra';
    }
  } catch {
    useAlert('Não consegui carregar o dashboard.');
  } finally {
    isLoading.value = false;
  }
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-5xl mx-auto w-full p-4 sm:p-8">
      <!-- Header -->
      <div class="flex items-center gap-3 flex-wrap mb-5">
        <span
          class="w-9 h-9 rounded-xl flex items-center justify-center"
          :style="{ background: `linear-gradient(135deg, ${VERDE_ESCURO}, ${VERDE})` }"
        >
          <span class="i-lucide-area-chart text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-lg font-bold text-n-slate-12">Dashboard</h1>
          <p class="text-xs text-n-slate-10">seus resultados — semana a semana e acumulado</p>
        </div>
        <div class="flex gap-2">
          <button
            v-for="t in [{ key: 'visao', label: '🎯 Visão geral' }, { key: 'treino', label: '🏋️ Treino' }, ...(config?.features?.boxing === true ? [{ key: 'boxe', label: '🥊 Boxe' }] : []), { key: 'dieta', label: '🍽 Dieta' }]"
            :key="t.key"
            class="h-9 px-4 rounded-full text-xs font-bold border"
            :class="dashTab === t.key ? 'text-white border-transparent' : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
            :style="dashTab === t.key ? { background: `linear-gradient(135deg, ${VERDE_ESCURO}, ${VERDE})` } : {}"
            @click="dashTab = t.key"
          >
            {{ t.label }}
          </button>
        </div>
      </div>

      <div v-if="isLoading" class="flex justify-center py-16"><Spinner /></div>

      <template v-else>
        <!-- ═══ VISÃO GERAL ═══ -->
        <template v-if="dashTab === 'visao'">
          <!-- Insights automáticos -->
          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-2">🧠 Insights</h2>
            <div
              v-for="(ins, i) in insights"
              :key="i"
              class="flex items-start gap-2.5 py-1.5 border-b border-n-weak/60 last:border-0"
            >
              <span class="text-base leading-none mt-0.5">{{ ins.icon }}</span>
              <p class="flex-1 text-xs text-n-slate-12">{{ ins.text }}</p>
            </div>
          </div>

          <!-- Transformação -->
          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">🦋 A Transformação</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">
              o objetivo do Warrior num gráfico só: peso caindo (azul) enquanto a força sobe (verde) — calorias na linha pontilhada
            </p>
            <div style="height: 260px">
              <Line :data="transformationChart" :options="transformationOptions" />
            </div>
            <!-- Projeções -->
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 mt-3">
              <div class="rounded-xl border border-n-weak p-2.5">
                <p class="text-[11px] font-medium text-n-slate-11">⚖️ Peso — ritmo (30d)</p>
                <p class="text-sm font-bold" :style="{ color: pesoTrend !== null && pesoTrend < 0 ? VERDE : OURO }">
                  {{ pesoTrend === null ? 'registre mais dias' : `${sinal(pesoTrend)} kg/mês` }}
                </p>
                <p v-if="pesoTrend !== null && latestWeight !== null" class="text-[11px] text-n-slate-10">
                  em 30 dias: ~{{ fmtNum(latestWeight + pesoTrend) }} kg
                </p>
              </div>
              <div class="rounded-xl border border-n-weak p-2.5">
                <p class="text-[11px] font-medium text-n-slate-11">💪 Força e-1RM — ritmo (30d)</p>
                <p class="text-sm font-bold" :style="{ color: forcaTrend !== null && forcaTrend > 0 ? VERDE : OURO }">
                  {{ forcaTrend === null ? 'registre mais treinos' : `${sinal(forcaTrend)} kg/mês` }}
                </p>
                <p class="text-[11px] text-n-slate-10">média dos exercícios do programa</p>
              </div>
              <div class="rounded-xl border border-n-weak p-2.5">
                <p class="text-[11px] font-medium text-n-slate-11">🏅 Recordes na semana</p>
                <p class="text-sm font-bold" :style="{ color: recentPRs.length ? VERDE : undefined }">
                  {{ recentPRs.length || '—' }}
                </p>
                <p class="text-[11px] text-n-slate-10 truncate">
                  {{ recentPRs.slice(0, 2).map(r => r.name).join(' · ') || 'supere um e-1RM pra marcar' }}
                </p>
              </div>
            </div>
          </div>

          <!-- Mapa de constância -->
          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">🟩 Mapa de constância</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">
              últimas 24 semanas — <span :style="{ color: VERDE }">■</span> musculação ·
              <span :style="{ color: ROXO }">■</span> boxe · meio a meio = os dois no dia
            </p>
            <div class="overflow-x-auto">
              <div class="flex gap-[3px]" style="min-width: 640px">
                <div v-for="(col, ci) in heatmap" :key="ci" class="flex flex-col gap-[3px]">
                  <div
                    v-for="cell in col"
                    :key="cell.iso"
                    class="rounded-[3px]"
                    :style="{
                      width: '14px',
                      height: '14px',
                      background: HEAT_COLORS[cell.tone],
                      outline: cell.hoje ? `2px solid ${VERDE}` : 'none',
                    }"
                    :title="`${fmtDay(cell.iso)}${cell.tone === 'ambos' ? ' · musculação + boxe' : cell.tone === 'musc' ? ' · musculação' : cell.tone === 'boxe' ? ' · boxe' : ''}`"
                  />
                </div>
              </div>
            </div>
          </div>

          <!-- Aderência ao plano -->
          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">📅 Aderência ao plano</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">das 3 sessões previstas por semana (seg · qua · sex), quantas saíram</p>
            <div v-if="adherenceChart" style="height: 200px">
              <Line :data="adherenceChart" :options="adherenceOptions" />
            </div>
            <p v-else class="text-xs text-n-slate-10">O programa ainda não começou a contar semanas.</p>
          </div>
        </template>

        <!-- ═══ TREINO ═══ -->
        <template v-if="dashTab === 'treino'">
          <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5">
            <DashKpi label="Treinos feitos" :value="progRecords.length" sub="registros com séries" :from="VERDE_ESCURO" :to="VERDE" />
            <DashKpi label="Volume total" :value="fmtVol(totalVolume)" sub="Σ carga × reps" :from="'#92400E'" :to="OURO" />
            <DashKpi label="Progressões" :value="totalProgress" sub="exercícios superados" :from="'#0B4A82'" :to="AZUL" />
            <DashKpi
              label="Semana atual"
              :value="currentWeek === null ? '—' : `${currentWeek}/${totalWeeks}`"
              sub="do programa de 24"
              :from="'#5B21B6'"
              :to="ROXO"
            />
          </div>

          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">📊 Volume por semana</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">quanto peso você moveu em cada semana, por treino</p>
            <div style="height: 260px">
              <Line :data="volumeChart" :options="chartOptions()" />
            </div>
          </div>

          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <div class="flex items-center justify-between flex-wrap gap-2 mb-1">
              <h2 class="text-sm font-bold text-n-slate-12">📈 Evolução por exercício</h2>
              <select
                v-model="exSelected"
                class="h-9 rounded-lg border border-n-weak px-2 text-xs text-n-slate-12"
                style="width: 16rem; margin-bottom: 0; border: 1px solid rgba(148, 163, 184, 0.35); background-color: transparent"
              >
                <option value="">Escolha o exercício…</option>
                <option v-for="name in exOptions" :key="name" :value="name">{{ name }}</option>
              </select>
            </div>
            <p class="text-[11px] text-n-slate-10 mb-3">carga máxima (linha) e volume da sessão (área) — sessão a sessão</p>
            <div v-if="exChart" style="height: 260px">
              <Line :data="exChart" :options="exChartOptions" />
            </div>
            <p v-else class="text-xs text-n-slate-10">Escolha um exercício com registros pra ver a evolução.</p>
          </div>

          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">📶 Placar de progressão por semana</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">
              cada treino comparado ao MESMO treino da vez anterior — exercícios que subiram, empataram ou caíram
            </p>
            <div style="height: 220px">
              <Line :data="verdictChart" :options="chartOptions()" />
            </div>
          </div>

          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">🔁 Séries e repetições por semana</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">o trabalho total da semana em séries (linha) e repetições (área)</p>
            <div style="height: 220px">
              <Line :data="setsRepsChart" :options="setsRepsOptions" />
            </div>
          </div>

          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">🗂 Carga por exercício — histórico completo</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">
              a carga máxima de cada exercício, sessão a sessão — um gráfico por exercício registrado
            </p>
            <p v-if="!exercisesWithData.length" class="text-xs text-n-slate-10">
              Registre treinos (planilha ou modo treino) e cada exercício ganha seu gráfico aqui.
            </p>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
              <div v-for="name in exercisesWithData" :key="name" class="rounded-xl border border-n-weak p-2.5">
                <div class="flex items-baseline justify-between gap-2 mb-1">
                  <p class="text-[11px] font-bold text-n-slate-12 truncate">{{ name }}</p>
                  <p class="text-[11px] font-bold shrink-0" :style="{ color: VERDE }">{{ fmtNum(lastTop(name)) }} kg</p>
                </div>
                <div style="height: 70px">
                  <Line :data="miniChart(name)" :options="miniOptions" />
                </div>
              </div>
            </div>
          </div>

          <!-- Recordes pessoais -->
          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">🏅 Recordes pessoais</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">
              sua melhor marca em cada exercício — carga máxima e e-1RM (força estimada pela fórmula de Epley)
            </p>
            <p v-if="!personalRecords.length" class="text-xs text-n-slate-10">
              Os recordes nascem do primeiro treino registrado.
            </p>
            <div class="overflow-x-auto">
              <table v-if="personalRecords.length" class="border-collapse" style="min-width: 100%">
                <thead>
                  <tr>
                    <th class="text-left text-[11px] font-bold text-n-slate-11 px-2 py-1.5 border-b border-n-weak">Exercício</th>
                    <th class="text-right text-[11px] font-bold text-n-slate-11 px-2 py-1.5 border-b border-n-weak">Carga máx</th>
                    <th class="text-right text-[11px] font-bold text-n-slate-11 px-2 py-1.5 border-b border-n-weak">e-1RM</th>
                    <th class="text-right text-[11px] font-bold text-n-slate-11 px-2 py-1.5 border-b border-n-weak">Quando</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="r in personalRecords" :key="r.name" class="border-b border-n-weak/60 last:border-0">
                    <td class="px-2 py-1.5 text-[11px] font-medium text-n-slate-12">
                      {{ r.name }} <span v-if="r.recent" title="recorde recente">🏅</span>
                    </td>
                    <td class="px-2 py-1.5 text-[11px] text-right text-n-slate-11">{{ fmtNum(r.bestLoad.v) }} kg</td>
                    <td class="px-2 py-1.5 text-[11px] text-right font-bold" :style="{ color: VERDE }">
                      {{ fmtNum(r.bestE1.v) }} kg
                    </td>
                    <td class="px-2 py-1.5 text-[11px] text-right text-n-slate-10">{{ fmtDay(r.bestE1.date) }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <!-- Balanço muscular -->
          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">⚖️ Balanço muscular</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">como o volume se divide entre os grupos — algum ficando pra trás?</p>
            <p v-if="!muscleBalance.length" class="text-xs text-n-slate-10">Registre treinos pra ver a divisão.</p>
            <div v-for="g in muscleBalance" :key="g.label" class="flex items-center gap-3 py-1.5">
              <span class="text-xs font-medium text-n-slate-12" style="width: 9.5rem">{{ g.label }}</span>
              <div class="flex-1 h-2.5 rounded-full bg-n-alpha-1 overflow-hidden">
                <div class="h-full rounded-full" :style="{ width: `${g.bar}%`, background: g.cor }" />
              </div>
              <span class="text-[11px] text-n-slate-10" style="width: 6.5rem; text-align: right">
                {{ fmtVol(g.vol) }} · {{ g.pct }}%
              </span>
            </div>
          </div>

          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">🏔 Acumulado do programa</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">todo o volume somado, semana após semana — a montanha subindo</p>
            <div style="height: 220px">
              <Line :data="cumulativeChart" :options="chartOptions()" />
            </div>
          </div>
        </template>

        <!-- ═══ BOXE ═══ -->
        <template v-if="dashTab === 'boxe'">
          <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5">
            <DashKpi label="Sessões" :value="boxings.length" sub="treinos de boxe" :from="'#5B21B6'" :to="ROXO" />
            <DashKpi label="Tempo total" :value="fmtHours(boxTotalMin)" sub="acumulado" :from="'#92400E'" :to="OURO" />
            <DashKpi
              label="Média por sessão"
              :value="boxings.length ? `${Math.round(boxTotalMin / boxings.length)} min` : '—'"
              sub="duração média"
              :from="VERDE_ESCURO"
              :to="VERDE"
            />
            <DashKpi label="Rounds" :value="boxTotalRounds" sub="no total" :from="'#0B4A82'" :to="AZUL" />
          </div>

          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">⏱ Tempo de treino por dia</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">últimos 30 dias — minutos (área) e rounds (linha)</p>
            <div style="height: 240px">
              <Line :data="boxChart" :options="boxChartOptions" />
            </div>
          </div>

          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">🏔 Horas acumuladas</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">o tempo de luta somando, dia após dia (30 dias)</p>
            <div style="height: 200px">
              <Line :data="boxCumChart" :options="chartOptions()" />
            </div>
          </div>

          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-3">🌀 Sequências mais praticadas</h2>
            <p v-if="!boxTopSeqs.length" class="text-xs text-n-slate-10">
              Registre treinos de boxe marcando as sequências praticadas — o ranking nasce aqui.
            </p>
            <div v-for="(s, i) in boxTopSeqs" :key="s.name" class="flex items-center gap-3 py-1.5">
              <span class="text-[11px] font-bold text-n-slate-10" style="width: 1.2rem">{{ i + 1 }}º</span>
              <span class="flex-1 text-xs font-medium text-n-slate-12">{{ s.name }}</span>
              <div class="flex-1 h-2 rounded-full bg-n-alpha-1 overflow-hidden">
                <div
                  class="h-full rounded-full"
                  :style="{ width: `${(s.n / boxTopSeqs[0].n) * 100}%`, background: ROXO }"
                />
              </div>
              <span class="text-[11px] text-n-slate-10" style="width: 3.5rem; text-align: right">{{ s.n }}×</span>
            </div>
          </div>
        </template>

        <!-- ═══ DIETA ═══ -->
        <template v-if="dashTab === 'dieta'">
          <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5">
            <DashKpi label="Calorias (média 7d)" :value="avg7('kcal')" sub="kcal por dia" :from="'#92400E'" :to="OURO" />
            <DashKpi label="Proteína (média 7d)" :value="`${avg7('protein')} g`" sub="por dia" :from="VERDE_ESCURO" :to="VERDE" />
            <DashKpi label="Aderência (7d)" :value="`${adherence7}%`" sub="refeições do plano feitas" :from="'#0B4A82'" :to="AZUL" />
            <DashKpi label="Dias registrados" :value="diets.length" sub="no total" :from="'#5B21B6'" :to="ROXO" />
          </div>

          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">🔥 Calorias por dia</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">últimos {{ dietLabels.length }} dias contra a meta ({{ fmtNum(dietCfg.targets?.kcal || 0) }} kcal)</p>
            <div style="height: 240px">
              <Line :data="kcalChart" :options="chartOptions()" />
            </div>
          </div>

          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">🥩 Proteína por dia</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">últimos {{ dietLabels.length }} dias contra a meta ({{ fmtNum(dietCfg.targets?.protein || 0) }} g)</p>
            <div style="height: 240px">
              <Line :data="proteinChart" :options="chartOptions()" />
            </div>
          </div>

          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">🍽 Refeições feitas — dia a dia</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">
              ✓ com o horário REAL em que você marcou (horário em cinza = o previsto no plano)
            </p>
            <div class="overflow-x-auto">
              <table class="border-collapse" style="min-width: 100%">
                <thead>
                  <tr>
                    <th class="text-left text-[11px] font-bold text-n-slate-11 px-2 py-1.5 border-b border-n-weak">Dia</th>
                    <th
                      v-for="meal in dietCfg.meals"
                      :key="meal.id"
                      class="text-center text-[11px] font-bold text-n-slate-11 px-2 py-1.5 border-b border-n-weak"
                      style="min-width: 7rem"
                    >
                      {{ meal.name.split('—')[0].trim() }}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="day in mealDays" :key="day.iso" class="border-b border-n-weak/60">
                    <td class="px-2 py-1.5 text-[11px] font-bold text-n-slate-11">
                      {{ fmtDay(day.iso) }}
                      <span v-if="day.iso === todayISO" class="font-normal" :style="{ color: VERDE }">hoje</span>
                    </td>
                    <td v-for="meal in dietCfg.meals" :key="meal.id" class="px-2 py-1.5 text-center">
                      <template v-if="mealCell(day, meal)?.done">
                        <span class="text-[11px] font-bold" :style="{ color: VERDE }">✓</span>
                        <span
                          class="text-[10px] ml-1"
                          :class="mealCell(day, meal).real ? 'text-n-slate-11 font-medium' : 'text-n-slate-9'"
                        >
                          {{ mealCell(day, meal).at }}
                        </span>
                      </template>
                      <span v-else-if="day.rec" class="text-[11px] text-n-slate-8">—</span>
                      <span v-else class="text-[11px] text-n-slate-7">·</span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </template>
      </template>
    </div>
  </div>
</template>
