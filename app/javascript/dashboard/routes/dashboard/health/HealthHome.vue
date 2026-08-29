<script setup>
// MEU PAINEL DA SAÚDE (pedido 26/08): a porta de entrada do mundo Saúde,
// remodelada pro dia a dia — ALVOS (peso-meta, kcal/proteína, sessões),
// EXECUÇÕES (o que já foi feito hoje e na semana) e OBJETIVO (a
// transformação: ritmo do peso + projeção). Reusa o kit (DashKpi,
// chart.js) e os MESMOS dados do GET /health — nada de fonte nova.
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';
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

const VERDE = '#10B981';
const VERDE_ESCURO = '#065F46';
const OURO = '#D4A017';
const AZUL = '#0F5FA6';
const ROXO = '#7C3AED';

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

// ── programa e semana ────────────────────────────────────────────────
const program = computed(() => activeProgram(config.value.programs));
const programWeek = computed(() => weekOf(program.value, todayISO));
const programCycle = computed(() => cycleForWeek(program.value, programWeek.value));
const nextKey = computed(() =>
  suggestedSessionKey(workouts.value, program.value, programCycle.value)
);

// segunda-feira da semana atual (semana-calendário seg→dom)
const mondayISO = computed(() => {
  const d = new Date(`${todayISO}T00:00:00`);
  const dow = (d.getDay() + 6) % 7; // 0 = segunda
  d.setDate(d.getDate() - dow);
  return d.toISOString().slice(0, 10);
});
const inThisWeek = iso => iso >= mondayISO.value && iso <= todayISO;

// ── ALVOS (por PESSOA: ficam no registro 'profile' de cada usuário) ──
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

// ── EXECUÇÕES: hoje ──────────────────────────────────────────────────
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

// ── EXECUÇÕES: semana ────────────────────────────────────────────────
const weekWorkouts = computed(() =>
  workouts.value.filter(w => inThisWeek(w.record_date))
);
const weekBoxings = computed(() =>
  boxings.value.filter(b => inThisWeek(b.record_date))
);
// placar CALCULADO dos dados brutos (vale pra planilha e pro runner):
// cada exercício da semana vs a ocorrência anterior do MESMO treino
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
// kcal do dia = refeições marcadas (kcal do plano) + extras registrados
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

// ── OBJETIVO: transformação ──────────────────────────────────────────
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

// ritmo kg/mês por mínimos quadrados dos últimos 30 dias
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
  return (cov / varx) * 30; // kg / 30 dias
});
const projection30 = computed(() =>
  slope30.value === null ? null : currentWeight.value + slope30.value
);
const gapToGoal = computed(() =>
  weightGoal.value > 0 && currentWeight.value > 0
    ? currentWeight.value - weightGoal.value
    : null
);

const weightChart = computed(() => {
  const pts = weighins.value.slice(-24);
  return {
    labels: pts.map(p => p.date.slice(8, 10) + '/' + p.date.slice(5, 7)),
    datasets: [
      {
        data: pts.map(p => p.w),
        borderColor: AZUL,
        backgroundColor: 'rgba(15,95,166,0.12)',
        fill: true,
        tension: 0.35,
        pointRadius: 2,
        borderWidth: 2,
      },
    ],
  };
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
        <!-- Hero: onde eu estou no programa -->
        <div
          class="rounded-2xl p-5 mb-4 text-white"
          :style="{ background: `linear-gradient(135deg, #0B1220, ${VERDE_ESCURO})` }"
        >
          <div class="flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 class="text-lg font-bold">Meu Painel · Saúde</h1>
              <p class="text-xs opacity-80">
                <template v-if="program && programWeek">
                  Semana <b>{{ programWeek }}</b> · {{ programCycle?.name }}
                  <template v-if="programCycle?.focus"> — {{ programCycle.focus }}</template>
                </template>
                <template v-else>Seu dia, seus alvos e sua transformação.</template>
              </p>
            </div>
            <button
              v-if="todaysSession || nextKey"
              class="h-11 px-4 rounded-xl text-sm font-bold text-white border border-white/25 hover:bg-white/10"
              @click="go('hub_health')"
            >
              ▶ Treino {{ todaysSession?.key || nextKey }} de hoje
            </button>
          </div>
        </div>

        <!-- ALVOS -->
        <h2 class="text-xs font-bold text-n-slate-11 uppercase tracking-wide mb-2">🎯 Alvos</h2>
        <div class="grid gap-3 mb-5" style="grid-template-columns: repeat(auto-fit, minmax(150px, 1fr))">
          <div class="rounded-2xl p-3 text-white" :style="{ background: `linear-gradient(135deg, ${AZUL}, #38BDF8)` }">
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
              <input
                v-model="goalDraft"
                type="text"
                inputmode="decimal"
                class="h-8 w-20 rounded-lg px-2 text-xs text-n-slate-12"
                placeholder="ex.: 81,5"
              />
              <button class="ml-1 h-8 px-2 rounded-lg text-[11px] font-bold bg-white/20" @click="saveGoal">✓</button>
            </template>
          </div>
          <DashKpi label="Calorias/dia" :value="dietTargets.kcal ? `${dietTargets.kcal}` : '—'" hint="meta do plano" />
          <DashKpi label="Proteína/dia" :value="dietTargets.protein ? `${dietTargets.protein} g` : '—'" hint="meta do plano" />
          <DashKpi label="Sessões/semana" :value="`${weekWorkouts.length + weekBoxings.length} de ${weeklyGoal}`" hint="musculação + boxe" />
        </div>

        <!-- EXECUÇÕES DE HOJE -->
        <h2 class="text-xs font-bold text-n-slate-11 uppercase tracking-wide mb-2">✅ Hoje ({{ todayWeekday }})</h2>
        <div class="grid gap-3 mb-5" style="grid-template-columns: repeat(auto-fit, minmax(180px, 1fr))">
          <button class="rounded-2xl border border-n-weak bg-n-solid-1 p-3 text-left hover:bg-n-alpha-1" @click="go('hub_health')">
            <p class="text-[11px] text-n-slate-10">Treino do dia</p>
            <p class="text-sm font-bold" :style="{ color: workoutDoneToday ? VERDE : undefined }">
              <template v-if="workoutDoneToday">✓ feito</template>
              <template v-else-if="todaysSession">Treino {{ todaysSession.key }} — bora? →</template>
              <template v-else>descanso (próximo: {{ nextKey || '—' }})</template>
            </p>
          </button>
          <button class="rounded-2xl border border-n-weak bg-n-solid-1 p-3 text-left hover:bg-n-alpha-1" @click="go('hub_health_dieta')">
            <p class="text-[11px] text-n-slate-10">Refeições marcadas</p>
            <p class="text-sm font-bold" :style="{ color: mealsTotal && mealsDoneToday >= mealsTotal ? VERDE : undefined }">
              {{ mealsDoneToday }} de {{ mealsTotal || '—' }} →
            </p>
          </button>
          <button class="rounded-2xl border border-n-weak bg-n-solid-1 p-3 text-left hover:bg-n-alpha-1" @click="go('hub_health_boxe')">
            <p class="text-[11px] text-n-slate-10">Boxe</p>
            <p class="text-sm font-bold" :style="{ color: boxingDoneToday ? ROXO : undefined }">
              {{ boxingDoneToday ? '✓ treinou hoje' : 'registrar →' }}
            </p>
          </button>
          <button class="rounded-2xl border border-n-weak bg-n-solid-1 p-3 text-left hover:bg-n-alpha-1" @click="go('hub_health_corpo')">
            <p class="text-[11px] text-n-slate-10">Pesagem da semana</p>
            <p class="text-sm font-bold" :style="{ color: weightThisWeek ? VERDE : undefined }">
              {{ weightThisWeek ? '✓ registrada' : 'registrar →' }}
            </p>
          </button>
        </div>

        <!-- SEMANA -->
        <h2 class="text-xs font-bold text-n-slate-11 uppercase tracking-wide mb-2">📶 Minha semana</h2>
        <div class="grid gap-3 mb-5" style="grid-template-columns: repeat(auto-fit, minmax(150px, 1fr))">
          <DashKpi label="Sessões feitas" :value="`${weekWorkouts.length + weekBoxings.length}/${weeklyGoal}`" hint="desde segunda" />
          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-3">
            <p class="text-[11px] text-n-slate-10">Placar da semana</p>
            <p class="text-sm font-bold">
              <span :style="{ color: VERDE }">▲{{ weekScore.progress }}</span>
              <span class="text-n-slate-10 mx-1">▬{{ weekScore.tie }}</span>
              <span :style="{ color: '#DC2626' }">▼{{ weekScore.regress }}</span>
            </p>
            <p class="text-[10px] text-n-slate-10">exercícios vs treino anterior</p>
          </div>
          <DashKpi label="Kcal média" :value="weekKcalAvg ? `${weekKcalAvg}` : '—'" :hint="dietTargets.kcal ? `meta ${dietTargets.kcal}` : 'sem meta'" />
        </div>

        <!-- OBJETIVO / TRANSFORMAÇÃO -->
        <h2 class="text-xs font-bold text-n-slate-11 uppercase tracking-wide mb-2">🦋 Minha transformação</h2>
        <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-6">
          <div class="grid gap-3 mb-3" style="grid-template-columns: repeat(auto-fit, minmax(140px, 1fr))">
            <DashKpi label="Peso atual" :value="currentWeight ? fmtKg(currentWeight) : '—'" hint="última pesagem" />
            <DashKpi
              label="Desde o início"
              :value="deltaLabel"
              :hint="firstWeight ? `partiu de ${fmtKg(firstWeight)}` : ''"
            />
            <DashKpi
              label="Ritmo (30d)"
              :value="slope30 === null ? '—' : `${slope30 > 0 ? '+' : '−'}${fmtKg(Math.abs(slope30)).replace(' kg', '')} kg/mês`"
              hint="mínimos quadrados"
            />
            <DashKpi
              label="Falta pro alvo"
              :value="gapToGoal === null ? '—' : gapToGoal <= 0 ? '🎉 alvo batido!' : fmtKg(gapToGoal)"
              :hint="projection30 !== null ? `em 30d: ~${fmtKg(projection30)}` : 'registre pesagens'"
            />
          </div>
          <div v-if="weighins.length > 1" style="height: 160px">
            <Line :data="weightChart" :options="chartOpts" />
          </div>
          <p v-else class="text-[11px] text-n-slate-10">
            Registre seu peso na aba Corpo pra curva da transformação aparecer aqui.
          </p>
        </div>

        <div class="flex justify-end mb-8">
          <button class="text-[11px] text-n-slate-10 underline" @click="go('hub_health_dash')">
            ver o Dashboard completo →
          </button>
        </div>
      </template>
    </div>
  </div>
</template>
