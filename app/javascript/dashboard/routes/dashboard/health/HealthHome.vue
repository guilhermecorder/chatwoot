<script setup>
// MEU PAINEL DA SAÚDE — rodada 14: o ESSENCIAL do usuário num painel só,
// vestido com a paleta do HUB pessoal (azul royal + laranja brilhante):
// ciclo de 24 semanas (quantos já fez, em qual está), caixinhas de
// consistência (verde = no dia · laranja = reagendado · vermelho = não
// foi), elogio na semana completa, alvos, projeções, medidas e a curva
// da transformação. Boxe só aparece se o admin liberar (Config → HUB).
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';
import WheelInput from './WheelInput.vue';
import {
  Chart as ChartJS,
  Tooltip,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Filler,
} from 'chart.js';
import { Line } from 'vue-chartjs';
import {
  activeProgram,
  weekOf,
  cycleForWeek,
  suggestedSessionKey,
  exerciseVerdict,
} from './warrior';

ChartJS.register(Tooltip, CategoryScale, LinearScale, PointElement, LineElement, Filler);

// ── paleta do painel (pedido 30/08): azul royal + laranja brilhante ──
const ROYAL = '#4169E1'; // azul royal
const ROYAL_PROFUNDO = '#27408B'; // subtom escuro
const ROYAL_NOITE = '#111C3F'; // quase-preto azulado (fundos)
const ROYAL_CLARO = '#8FA9F5'; // subtom claro
const LARANJA = '#FF8A00'; // laranja brilhante
const LARANJA_VIVO = '#FF6B1A'; // subtom quente
const LARANJA_CLARO = '#FFB25E'; // subtom suave
const VERMELHO = '#E5484D';
const VERDE_OK = '#30A46C'; // só nas caixinhas feitas no dia

const router = useRouter();
const accountScopedRoute = name => ({
  name,
  params: { accountId: router.currentRoute.value.params.accountId },
});

const isLoading = ref(true);
const config = ref({});
const profile = ref({});
const workouts = ref([]);
const boxings = ref([]);
const diets = ref([]);
const bodies = ref([]);

const todayISO = new Date().toISOString().slice(0, 10);
const num = v => Number(String(v ?? '').replace(',', '.')) || 0;
const fmtKg = v => `${String(Math.round(v * 10) / 10).replace('.', ',')} kg`;
const fmt1 = v => String(Math.round(v * 10) / 10).replace('.', ',');

const fetchAll = async () => {
  isLoading.value = true;
  try {
    const { data } = await CrmAPI.getHealth();
    config.value = data.config || {};
    profile.value = data.profile || {};
    workouts.value = data.workouts || [];
    boxings.value = data.boxings || [];
    diets.value = data.diets || [];
    bodies.value = data.bodies || [];
  } catch {
    useAlert('Não consegui carregar o painel de saúde.');
  } finally {
    isLoading.value = false;
  }
};
onMounted(fetchAll);

// boxe é ligável em Configurações → HUB (desligado = omitido de tudo)
const boxingOn = computed(() => config.value.features?.boxing === true);

// ── programa, SEMANA e CICLO de 24 semanas ──────────────────────────
const CYCLE_LEN = 24;
const program = computed(() => activeProgram(config.value.programs));
const programWeek = computed(() => weekOf(program.value, todayISO));
// semana 25 em diante = novo ciclo do MESMO programa (a conta continua)
const cycleNumber = computed(() =>
  programWeek.value ? Math.floor((programWeek.value - 1) / CYCLE_LEN) + 1 : 1
);
const cyclesDone = computed(() => cycleNumber.value - 1);
const weekInCycle = computed(() =>
  programWeek.value ? ((programWeek.value - 1) % CYCLE_LEN) + 1 : 1
);
const programCycle = computed(() => cycleForWeek(program.value, weekInCycle.value));
const nextKey = computed(() =>
  suggestedSessionKey(workouts.value, program.value, programCycle.value)
);

// segunda-feira da semana atual (semana-calendário seg→dom)
const mondayISO = computed(() => {
  const d = new Date(`${todayISO}T00:00:00`);
  const dow = (d.getDay() + 6) % 7;
  d.setDate(d.getDate() - dow);
  return d.toISOString().slice(0, 10);
});
const inThisWeek = iso => iso >= mondayISO.value && iso <= todayISO;

// ── ALVOS (por pessoa, registro 'profile') ──────────────────────────
const dietTargets = computed(() => config.value.diet?.targets || {});
const weeklyGoal = computed(() => Number(profile.value.weekly_sessions) || 3);
const weightGoal = computed(() => Number(profile.value.weight_goal) || 0);

const editingGoal = ref(false);
const goalDraft = ref('');
const saveGoal = async () => {
  const v = num(goalDraft.value);
  try {
    const { data: rec } = await CrmAPI.createHealthRecord({
      kind: 'profile',
      data: { ...profile.value, weight_goal: v },
    });
    profile.value = rec.data || {};
    editingGoal.value = false;
    useAlert('🎯 Peso-alvo salvo.');
  } catch {
    useAlert('Não consegui salvar o alvo.');
  }
};

// ── HOJE ────────────────────────────────────────────────────────────
const WEEKDAYS_PT = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];
const todayWeekday = WEEKDAYS_PT[new Date().getDay()];
const todaysSession = computed(() =>
  (programCycle.value?.sessions || []).find(s =>
    (s.weekday || '').toLowerCase().startsWith(todayWeekday.slice(0, 4).toLowerCase())
  )
);
const workoutDoneToday = computed(() =>
  workouts.value.some(w => w.record_date === todayISO)
);
const boxingDoneToday = computed(() =>
  boxings.value.some(b => b.record_date === todayISO)
);
const dietToday = computed(() => diets.value.find(d => d.record_date === todayISO));
const mealsTotal = computed(() => (config.value.diet?.meals || []).length);
const mealsDoneToday = computed(
  () => (dietToday.value?.data?.meals_done || []).length
);
const weightThisWeek = computed(() =>
  bodies.value.some(b => inThisWeek(b.record_date) && Number(b.data?.weight) > 0)
);

// ── SEMANA ──────────────────────────────────────────────────────────
const weekWorkouts = computed(() =>
  workouts.value.filter(w => inThisWeek(w.record_date))
);
const weekBoxings = computed(() =>
  boxings.value.filter(b => inThisWeek(b.record_date))
);
const weekSessions = computed(
  () => weekWorkouts.value.length + (boxingOn.value ? weekBoxings.value.length : 0)
);
const weekComplete = computed(() => weekWorkouts.value.length >= weeklyGoal.value);
// elogio da semana completa — frase estável dentro da mesma semana
const PRAISES = [
  'Os 3 treinos da semana feitos. Consistência é o que constrói — orgulho! 🔥',
  'Semana fechada! Quem aparece TODA semana é imbatível. 👑',
  'Mais uma semana completa no bolso. O corpo agradece, o futuro também. 💪',
  'Semana 100%. Isso não é sorte — é disciplina. ⚡',
];
const praise = computed(() => PRAISES[(programWeek.value || 0) % PRAISES.length]);

const weekScore = computed(() => {
  const acc = { progress: 0, tie: 0, regress: 0 };
  weekWorkouts.value.forEach(w => {
    const prev = workouts.value.find(
      o =>
        o.record_date < w.record_date &&
        o.data?.program_id === w.data?.program_id &&
        o.data?.session_key === w.data?.session_key
    );
    (w.data?.exercises || []).forEach(ex => {
      const last = (prev?.data?.exercises || []).find(e => e.name === ex.name);
      if (!last?.sets?.length) return;
      const v = exerciseVerdict(ex.sets || [], last.sets);
      if (acc[v] !== undefined) acc[v] += 1;
    });
  });
  return acc;
});

const kcalOfDay = d => {
  const meals = config.value.diet?.meals || [];
  const done = d.data?.meals_done || [];
  const base = meals
    .filter(m => done.includes(m.id))
    .reduce((s, m) => s + (Number(m.kcal) || 0), 0);
  const extra = (d.data?.extras || []).reduce((s, e) => s + (Number(e.kcal) || 0), 0);
  return base + extra;
};
const weekKcalAvg = computed(() => {
  const days = diets.value.filter(d => inThisWeek(d.record_date));
  if (!days.length) return 0;
  const total = days.reduce((sum, d) => sum + kcalOfDay(d), 0);
  return Math.round(total / days.length);
});

// ── CAIXINHAS DE CONSISTÊNCIA (pedido 30/08) ────────────────────────
// Ciclo atual, semana a semana × sessão planejada (A/B/C):
//   verde = feito no dia planejado · laranja = feito noutro dia da
//   semana (REAGENDADO) · vermelho = passou e não foi · vazio = a fazer.
const WEEKDAY_OFFSET = {
  Segunda: 0, Terça: 1, Quarta: 2, Quinta: 3, Sexta: 4, Sábado: 5, Domingo: 6,
};
const consistency = computed(() => {
  const prog = program.value;
  if (!prog?.start_date) return [];
  const startWeekAbs = (cycleNumber.value - 1) * CYCLE_LEN + 1;
  const weeks = [];
  for (let w = 1; w <= CYCLE_LEN; w += 1) {
    const absWeek = startWeekAbs + w - 1;
    const cy = cycleForWeek(prog, w);
    const cells = (cy?.sessions || []).map(s => {
      const d = new Date(`${prog.start_date}T00:00:00`);
      d.setDate(d.getDate() + (absWeek - 1) * 7 + (WEEKDAY_OFFSET[s.weekday] ?? 0));
      const plannedISO = d.toISOString().slice(0, 10);
      const rec = workouts.value.find(
        x =>
          x.data?.program_id === prog.id &&
          x.data?.session_key === s.key &&
          Number(x.data?.week) === absWeek
      );
      let state = 'future';
      if (rec) state = rec.record_date === plannedISO ? 'done' : 'moved';
      else if (plannedISO < todayISO) state = 'missed';
      return { key: s.key, state, plannedISO };
    });
    weeks.push({ n: w, absWeek, cells, current: absWeek === programWeek.value });
  }
  return weeks;
});
const consistencyTotals = computed(() => {
  const t = { done: 0, moved: 0, missed: 0 };
  consistency.value.forEach(w =>
    w.cells.forEach(c => {
      if (t[c.state] !== undefined) t[c.state] += 1;
    })
  );
  return t;
});
const CELL_COLORS = {
  done: VERDE_OK,
  moved: LARANJA,
  missed: VERMELHO,
  future: 'rgba(127,127,127,0.18)',
};

// ── TRANSFORMAÇÃO + PROJEÇÕES ───────────────────────────────────────
const weighins = computed(() =>
  bodies.value
    .filter(b => Number(b.data?.weight) > 0)
    .map(b => ({ date: b.record_date, w: Number(b.data.weight) }))
    .sort((a, b) => (a.date > b.date ? 1 : -1))
);
const currentWeight = computed(() => weighins.value.at(-1)?.w || 0);
const firstWeight = computed(() => weighins.value[0]?.w || 0);
const deltaTotal = computed(() => currentWeight.value - firstWeight.value);
const deltaLabel = computed(() => {
  if (weighins.value.length < 2) return '—';
  return `${deltaTotal.value < 0 ? '−' : '+'}${fmtKg(Math.abs(deltaTotal.value))}`;
});

const slope30 = computed(() => {
  const cut = new Date(`${todayISO}T00:00:00`);
  cut.setDate(cut.getDate() - 30);
  const cutISO = cut.toISOString().slice(0, 10);
  const pts = weighins.value.filter(p => p.date >= cutISO);
  if (pts.length < 3) return null;
  const xs = pts.map(p => (new Date(`${p.date}T00:00:00`) - cut) / 86400000);
  const ys = pts.map(p => p.w);
  const n = xs.length;
  const mx = xs.reduce((a, b) => a + b, 0) / n;
  const my = ys.reduce((a, b) => a + b, 0) / n;
  let cov = 0;
  let varx = 0;
  xs.forEach((x, i) => {
    cov += (x - mx) * (ys[i] - my);
    varx += (x - mx) ** 2;
  });
  if (!varx) return null;
  return (cov / varx) * 30;
});
const projection30 = computed(() =>
  slope30.value === null ? null : currentWeight.value + slope30.value
);
const gapToGoal = computed(() =>
  weightGoal.value > 0 && currentWeight.value > 0
    ? currentWeight.value - weightGoal.value
    : null
);
// projeção: DATA estimada de chegada ao alvo no ritmo atual
const goalEta = computed(() => {
  if (gapToGoal.value === null || gapToGoal.value <= 0) return null;
  if (slope30.value === null || slope30.value >= -0.1) return null;
  const days = Math.round((gapToGoal.value / Math.abs(slope30.value)) * 30);
  if (days > 400) return null;
  const d = new Date(`${todayISO}T00:00:00`);
  d.setDate(d.getDate() + days);
  return { days, label: `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}` };
});
// projeção: kcal média da semana vs meta
const kcalDelta = computed(() => {
  const meta = Number(dietTargets.value.kcal) || 0;
  if (!meta || !weekKcalAvg.value) return null;
  return weekKcalAvg.value - meta;
});

// ── MEDIDAS: última medição + variação ──────────────────────────────
const MEASURE_VIEW = [
  { key: 'waist_navel', label: 'Cintura', down: true },
  { key: 'waist_narrow', label: 'C. estreita', down: true },
  { key: 'hips', label: 'Quadril', down: true },
  { key: 'chest', label: 'Peito', down: false },
  { key: 'arm_r', label: 'Braço D', down: false },
  { key: 'arm_l', label: 'Braço E', down: false },
  { key: 'thigh_r', label: 'Coxa D', down: false },
  { key: 'thigh_l', label: 'Coxa E', down: false },
  { key: 'neck', label: 'Pescoço', down: true },
  { key: 'shoulders', label: 'Ombros', down: false },
];
const measures = computed(() =>
  MEASURE_VIEW.map(m => {
    const withVal = bodies.value.filter(b => Number(b.data?.[m.key]) > 0);
    if (!withVal.length) return null;
    const value = Number(withVal[0].data[m.key]);
    const prev = withVal[1] ? Number(withVal[1].data[m.key]) : null;
    const delta = prev === null ? null : Math.round((value - prev) * 10) / 10;
    return { ...m, value, delta };
  }).filter(Boolean)
);

const weightChart = computed(() => {
  const pts = weighins.value.slice(-24);
  const data = {
    labels: pts.map(p => p.date.slice(8, 10) + '/' + p.date.slice(5, 7)),
    datasets: [
      {
        data: pts.map(p => p.w),
        borderColor: ROYAL,
        backgroundColor: 'rgba(65,105,225,0.14)',
        fill: true,
        tension: 0.35,
        pointRadius: 2,
        borderWidth: 2,
      },
    ],
  };
  if (weightGoal.value > 0) {
    data.datasets.push({
      data: pts.map(() => weightGoal.value),
      borderColor: LARANJA,
      borderDash: [6, 5],
      borderWidth: 1.5,
      pointRadius: 0,
      fill: false,
    });
  }
  return data;
});
const chartOpts = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: { legend: { display: false } },
  scales: {
    x: { ticks: { font: { size: 9 } }, grid: { display: false } },
    y: { ticks: { font: { size: 9 } } },
  },
};

const go = name => router.push(accountScopedRoute(name));
</script>

<template>
  <div class="flex-1 overflow-auto p-6">
    <div class="max-w-5xl mx-auto">
      <div v-if="isLoading" class="flex justify-center py-16"><Spinner /></div>
      <template v-else>
        <!-- HERO: ciclo de 24 semanas + treino de hoje -->
        <div
          class="rounded-2xl p-5 mb-4 text-white"
          :style="{ background: `linear-gradient(135deg, ${ROYAL_NOITE}, ${ROYAL_PROFUNDO} 65%, ${ROYAL})` }"
        >
          <div class="flex items-center justify-between flex-wrap gap-3">
            <div>
              <div class="flex items-center gap-2 flex-wrap mb-1">
                <h1 class="text-lg font-bold">Meu Painel · Saúde</h1>
                <span
                  class="px-2 py-0.5 rounded-full text-[10px] font-bold"
                  :style="{ background: LARANJA, color: '#1a0e00' }"
                >
                  Ciclo {{ cycleNumber }}
                </span>
              </div>
              <p class="text-xs opacity-85">
                <template v-if="program && programWeek">
                  Semana <b>{{ weekInCycle }} de {{ CYCLE_LEN }}</b> · {{ programCycle?.name }}
                  <template v-if="programCycle?.focus"> — {{ programCycle.focus }}</template>
                </template>
                <template v-else>Seu dia, seus alvos e sua transformação.</template>
              </p>
              <p class="text-[11px] mt-1" :style="{ color: ROYAL_CLARO }">
                <template v-if="cyclesDone === 0">
                  🚀 Primeiro ciclo — é aqui que a base é construída.
                </template>
                <template v-else>
                  🏅 {{ cyclesDone }} {{ cyclesDone === 1 ? 'ciclo completo' : 'ciclos completos' }} de
                  24 semanas — poucos chegam aí.
                </template>
              </p>
            </div>
            <button
              v-if="todaysSession || nextKey"
              class="h-11 px-5 rounded-xl text-sm font-bold text-white shadow-lg"
              :style="{ background: `linear-gradient(135deg, ${LARANJA_VIVO}, ${LARANJA})` }"
              @click="go('hub_health')"
            >
              ▶ Treino {{ todaysSession?.key || nextKey }} de hoje
            </button>
          </div>
        </div>

        <!-- ELOGIO: semana completa -->
        <div
          v-if="weekComplete"
          class="hub-praise rounded-2xl px-4 py-3 mb-4 flex items-center gap-3"
        >
          <span class="text-2xl">🏆</span>
          <div>
            <p class="text-sm font-bold" :style="{ color: LARANJA_CLARO }">Semana completa!</p>
            <p class="text-xs text-n-slate-11">{{ praise }}</p>
          </div>
        </div>

        <!-- CONSISTÊNCIA: caixinhas do ciclo -->
        <h2 class="text-xs font-bold text-n-slate-11 uppercase tracking-wide mb-2">
          📦 Consistência do ciclo
        </h2>
        <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-5">
          <div class="flex items-center justify-between flex-wrap gap-2 mb-3">
            <p class="text-[11px] text-n-slate-10">
              Cada coluna é uma semana; cada caixinha, um treino planejado.
            </p>
            <p class="text-[11px] font-medium">
              <span :style="{ color: VERDE_OK }">■ no dia ({{ consistencyTotals.done }})</span>
              <span class="mx-1.5" :style="{ color: LARANJA }">■ reagendado ({{ consistencyTotals.moved }})</span>
              <span :style="{ color: VERMELHO }">■ não foi ({{ consistencyTotals.missed }})</span>
            </p>
          </div>
          <div class="overflow-x-auto pb-1">
            <div class="flex gap-1" style="min-width: max-content">
              <div v-for="w in consistency" :key="w.n" class="flex flex-col items-center gap-1">
                <div
                  v-for="c in w.cells"
                  :key="c.key"
                  class="rounded-[4px]"
                  :style="{
                    width: '14px',
                    height: '14px',
                    background: CELL_COLORS[c.state],
                    outline: w.current ? `1.5px solid ${ROYAL}` : 'none',
                  }"
                  :title="`S${w.n} · Treino ${c.key} · ${c.plannedISO.slice(8, 10)}/${c.plannedISO.slice(5, 7)} — ${
                    { done: 'feito no dia', moved: 'reagendado (feito noutro dia)', missed: 'não foi', future: 'a fazer' }[c.state]
                  }`"
                />
                <span
                  class="text-[8px]"
                  :class="w.current ? 'font-bold' : 'text-n-slate-10'"
                  :style="w.current ? { color: ROYAL } : {}"
                >
                  {{ w.n }}
                </span>
              </div>
            </div>
          </div>
        </div>

        <!-- ALVOS -->
        <h2 class="text-xs font-bold text-n-slate-11 uppercase tracking-wide mb-2">🎯 Alvos</h2>
        <div class="grid gap-3 mb-5" style="grid-template-columns: repeat(auto-fit, minmax(150px, 1fr))">
          <div class="rounded-2xl p-3 text-white" :style="{ background: `linear-gradient(135deg, ${ROYAL_PROFUNDO}, ${ROYAL})` }">
            <p class="text-[11px] opacity-90">Peso-alvo</p>
            <template v-if="!editingGoal">
              <p class="text-xl font-bold">
                {{ weightGoal > 0 ? fmtKg(weightGoal) : '—' }}
              </p>
              <button class="text-[10px] underline opacity-80" @click="editingGoal = true; goalDraft = weightGoal || ''">
                {{ weightGoal > 0 ? 'ajustar' : 'definir alvo' }}
              </button>
            </template>
            <template v-else>
              <div class="flex items-center gap-1.5">
                <WheelInput
                  v-model="goalDraft"
                  :step="0.5"
                  :max="200"
                  decimal
                  placeholder="kg"
                  style="width: 5rem"
                />
                <button class="h-8 px-2 rounded-lg text-[11px] font-bold bg-white/20" @click="saveGoal">✓</button>
              </div>
            </template>
          </div>
          <div class="rounded-2xl p-3" :style="{ background: 'rgba(255,138,0,0.10)', border: `1px solid rgba(255,138,0,0.35)` }">
            <p class="text-[11px] text-n-slate-10">Calorias/dia</p>
            <p class="text-xl font-bold" :style="{ color: LARANJA }">{{ dietTargets.kcal || '—' }}</p>
            <p class="text-[10px] text-n-slate-10">meta do plano</p>
          </div>
          <div class="rounded-2xl p-3" :style="{ background: 'rgba(65,105,225,0.10)', border: `1px solid rgba(65,105,225,0.35)` }">
            <p class="text-[11px] text-n-slate-10">Proteína/dia</p>
            <p class="text-xl font-bold" :style="{ color: ROYAL_CLARO }">{{ dietTargets.protein ? `${dietTargets.protein} g` : '—' }}</p>
            <p class="text-[10px] text-n-slate-10">meta do plano</p>
          </div>
          <div class="rounded-2xl p-3 border border-n-weak bg-n-solid-1">
            <p class="text-[11px] text-n-slate-10">Sessões/semana</p>
            <p class="text-xl font-bold" :style="{ color: weekComplete ? VERDE_OK : undefined }">
              {{ weekSessions }} de {{ weeklyGoal }}
            </p>
            <p class="text-[10px] text-n-slate-10">{{ boxingOn ? 'musculação + boxe' : 'musculação' }}</p>
          </div>
        </div>

        <!-- HOJE -->
        <h2 class="text-xs font-bold text-n-slate-11 uppercase tracking-wide mb-2">✅ Hoje ({{ todayWeekday }})</h2>
        <div class="grid gap-3 mb-5" style="grid-template-columns: repeat(auto-fit, minmax(170px, 1fr))">
          <button class="rounded-2xl border border-n-weak bg-n-solid-1 p-3 text-left hover:bg-n-alpha-1" @click="go('hub_health')">
            <p class="text-[11px] text-n-slate-10">Treino do dia</p>
            <p class="text-sm font-bold" :style="{ color: workoutDoneToday ? VERDE_OK : undefined }">
              <template v-if="workoutDoneToday">✓ feito</template>
              <template v-else-if="todaysSession">Treino {{ todaysSession.key }} — bora? →</template>
              <template v-else>descanso (próximo: {{ nextKey || '—' }})</template>
            </p>
          </button>
          <button class="rounded-2xl border border-n-weak bg-n-solid-1 p-3 text-left hover:bg-n-alpha-1" @click="go('hub_health_dieta')">
            <p class="text-[11px] text-n-slate-10">Refeições marcadas</p>
            <p class="text-sm font-bold" :style="{ color: mealsTotal && mealsDoneToday >= mealsTotal ? VERDE_OK : undefined }">
              {{ mealsDoneToday }} de {{ mealsTotal || '—' }} →
            </p>
          </button>
          <button
            v-if="boxingOn"
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-3 text-left hover:bg-n-alpha-1"
            @click="go('hub_health_boxe')"
          >
            <p class="text-[11px] text-n-slate-10">Boxe</p>
            <p class="text-sm font-bold" :style="{ color: boxingDoneToday ? ROYAL : undefined }">
              {{ boxingDoneToday ? '✓ treinou hoje' : 'registrar →' }}
            </p>
          </button>
          <button class="rounded-2xl border border-n-weak bg-n-solid-1 p-3 text-left hover:bg-n-alpha-1" @click="go('hub_health_corpo')">
            <p class="text-[11px] text-n-slate-10">Pesagem da semana</p>
            <p class="text-sm font-bold" :style="{ color: weightThisWeek ? VERDE_OK : undefined }">
              {{ weightThisWeek ? '✓ registrada' : 'registrar →' }}
            </p>
          </button>
        </div>

        <!-- SEMANA + PROJEÇÕES -->
        <h2 class="text-xs font-bold text-n-slate-11 uppercase tracking-wide mb-2">🔭 Projeções</h2>
        <div class="grid gap-3 mb-5" style="grid-template-columns: repeat(auto-fit, minmax(150px, 1fr))">
          <DashKpi
            label="Ritmo (30d)"
            :value="slope30 === null ? '—' : `${slope30 > 0 ? '+' : '−'}${fmt1(Math.abs(slope30))} kg/mês`"
            hint="tendência das pesagens"
          />
          <DashKpi
            label="Peso em 30 dias"
            :value="projection30 === null ? '—' : `~${fmtKg(projection30)}`"
            hint="se o ritmo continuar"
          />
          <div class="rounded-2xl p-3" :style="{ background: 'rgba(255,138,0,0.10)', border: '1px solid rgba(255,138,0,0.35)' }">
            <p class="text-[11px] text-n-slate-10">Chegada ao alvo</p>
            <p class="text-xl font-bold" :style="{ color: LARANJA }">
              <template v-if="gapToGoal !== null && gapToGoal <= 0">🎉 batido!</template>
              <template v-else-if="goalEta">≈ {{ goalEta.label }}</template>
              <template v-else>—</template>
            </p>
            <p class="text-[10px] text-n-slate-10">
              {{ goalEta ? `~${goalEta.days} dias no ritmo atual` : 'precisa de ritmo de queda' }}
            </p>
          </div>
          <div class="rounded-2xl p-3 border border-n-weak bg-n-solid-1">
            <p class="text-[11px] text-n-slate-10">Kcal média × meta</p>
            <p class="text-xl font-bold" :style="{ color: kcalDelta === null ? undefined : kcalDelta <= 0 ? VERDE_OK : VERMELHO }">
              <template v-if="kcalDelta === null">—</template>
              <template v-else>{{ kcalDelta > 0 ? '+' : '' }}{{ kcalDelta }}</template>
            </p>
            <p class="text-[10px] text-n-slate-10">{{ weekKcalAvg ? `média ${weekKcalAvg} esta semana` : 'marque as refeições' }}</p>
          </div>
          <div class="rounded-2xl p-3 border border-n-weak bg-n-solid-1">
            <p class="text-[11px] text-n-slate-10">Placar da semana</p>
            <p class="text-sm font-bold mt-1">
              <span :style="{ color: VERDE_OK }">▲{{ weekScore.progress }}</span>
              <span class="text-n-slate-10 mx-1">▬{{ weekScore.tie }}</span>
              <span :style="{ color: VERMELHO }">▼{{ weekScore.regress }}</span>
            </p>
            <p class="text-[10px] text-n-slate-10">exercícios vs treino anterior</p>
          </div>
        </div>

        <!-- MEDIDAS E PESO -->
        <h2 class="text-xs font-bold text-n-slate-11 uppercase tracking-wide mb-2">📏 Medidas e peso</h2>
        <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-5">
          <div class="grid gap-3 mb-3" style="grid-template-columns: repeat(auto-fit, minmax(140px, 1fr))">
            <DashKpi label="Peso atual" :value="currentWeight ? fmtKg(currentWeight) : '—'" hint="última pesagem" />
            <DashKpi
              label="Desde o início"
              :value="deltaLabel"
              :hint="firstWeight ? `partiu de ${fmtKg(firstWeight)}` : ''"
            />
            <DashKpi
              label="Falta pro alvo"
              :value="gapToGoal === null ? '—' : gapToGoal <= 0 ? '🎉 alvo batido!' : fmtKg(gapToGoal)"
              :hint="weightGoal ? `alvo ${fmtKg(weightGoal)}` : 'defina o peso-alvo'"
            />
          </div>
          <div v-if="measures.length" class="flex gap-1.5 flex-wrap mb-3">
            <span
              v-for="m in measures"
              :key="m.key"
              class="inline-flex items-center gap-1 h-7 px-2 rounded-full text-[11px] border border-n-weak bg-n-solid-2"
            >
              <span class="text-n-slate-10">{{ m.label }}</span>
              <b class="text-n-slate-12">{{ fmt1(m.value) }}</b>
              <span
                v-if="m.delta !== null && m.delta !== 0"
                class="font-bold"
                :style="{ color: (m.down ? m.delta < 0 : m.delta > 0) ? VERDE_OK : LARANJA }"
              >
                {{ m.delta > 0 ? '▲' : '▼' }}{{ fmt1(Math.abs(m.delta)) }}
              </span>
            </span>
          </div>
          <div v-if="weighins.length > 1" style="height: 160px">
            <Line :data="weightChart" :options="chartOpts" />
          </div>
          <p v-else class="text-[11px] text-n-slate-10">
            Registre seu peso na aba Corpo pra curva da transformação aparecer aqui.
          </p>
        </div>

        <div class="flex justify-end mb-8">
          <button class="text-[11px] underline" :style="{ color: ROYAL_CLARO }" @click="go('hub_health_dash')">
            ver o Dashboard completo →
          </button>
        </div>
      </template>
    </div>
  </div>
</template>

<style scoped>
/* elogio da semana completa — vidro quente laranja */
.hub-praise {
  background: linear-gradient(
    135deg,
    rgba(255, 138, 0, 0.14),
    rgba(255, 107, 26, 0.05) 55%,
    rgba(255, 255, 255, 0.03)
  );
  -webkit-backdrop-filter: blur(12px) saturate(1.4);
  backdrop-filter: blur(12px) saturate(1.4);
  border: 1px solid rgba(255, 138, 0, 0.3);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.08),
    0 8px 22px -14px rgba(255, 138, 0, 0.55);
}
</style>
