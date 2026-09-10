<script setup>
// MEU PAINEL DA SAÚDE — rodada 16: 95% TREINO. Pedido dele 10/09: o painel
// focado no treino, nas cargas e na visualização do progresso; dieta e
// calorias só como referência; indicadores de peso e medidas com a
// CIRCUNFERÊNCIA ABDOMINAL em destaque (o indicador do momento).
// Mantém da rodada 14: ciclo de 24 semanas, caixinhas de consistência,
// elogio da semana completa, projeções de peso, paleta royal + laranja.
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
  Legend,
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
  setTargets,
  targetHint,
  equipmentOf,
  nameWithoutEquipment,
  fmtSets,
  METHOD_LABELS,
} from './warrior';
import {
  ROYAL, ROYAL_PROFUNDO, ROYAL_NOITE, ROYAL_CLARO,
  LARANJA, LARANJA_VIVO, LARANJA_CLARO, LARANJA_ESCURO,
  VERMELHO, VERDE_OK, CINZA, GRAD_NOITE, GRAD_LARANJA, GRAD_ROYAL,
  VERDICT_COLORS,
} from './palette';

ChartJS.register(Tooltip, Legend, CategoryScale, LinearScale, PointElement, LineElement, Filler);

const router = useRouter();
const accountScopedRoute = name => ({
  name,
  params: { accountId: router.currentRoute.value.params.accountId },
});
const go = name => router.push(accountScopedRoute(name));

const isLoading = ref(true);
const config = ref({});
const profile = ref({});
const workouts = ref([]);
const boxings = ref([]);
const diets = ref([]);
const bodies = ref([]);

const todayISO = new Date().toISOString().slice(0, 10);
const num = v => Number(String(v ?? '').replace(',', '.')) || 0;
const fmt1 = v => String(Math.round(v * 10) / 10).replace('.', ',');
const fmtKg = v => `${fmt1(v)} kg`;
const fmtCm = v => `${fmt1(v)} cm`;
const fmtDay = iso => `${String(iso).slice(8, 10)}/${String(iso).slice(5, 7)}`;
const signed = v => `${v > 0 ? '+' : v < 0 ? '−' : ''}${fmt1(Math.abs(v))}`;
const shiftISO = (iso, days) => {
  const d = new Date(`${iso}T00:00:00`);
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
};
// 1RM estimado (Epley) — força comparável entre reps diferentes
const e1rm = (load, reps) => (reps > 0 ? load * (1 + reps / 30) : load);

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

const boxingOn = computed(() => config.value.features?.boxing === true);

// ── programa, SEMANA e CICLO de 24 semanas ──────────────────────────
const CYCLE_LEN = 24;
const program = computed(() => activeProgram(config.value.programs));
const programWeek = computed(() => weekOf(program.value, todayISO));
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

const mondayISO = computed(() => {
  const d = new Date(`${todayISO}T00:00:00`);
  const dow = (d.getDay() + 6) % 7;
  d.setDate(d.getDate() - dow);
  return d.toISOString().slice(0, 10);
});
const inThisWeek = iso => iso >= mondayISO.value && iso <= todayISO;
const lastMondayISO = computed(() => shiftISO(mondayISO.value, -7));
const inLastWeek = iso => iso >= lastMondayISO.value && iso < mondayISO.value;

// ── ALVOS (registro 'profile' da pessoa) ────────────────────────────
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

// ── HOJE / SEMANA ───────────────────────────────────────────────────
const WEEKDAYS_PT = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];
const todayWeekday = WEEKDAYS_PT[new Date().getDay()];
const todaysSession = computed(() =>
  (programCycle.value?.sessions || []).find(s =>
    (s.weekday || '').toLowerCase().startsWith(todayWeekday.slice(0, 4).toLowerCase())
  )
);
const workoutDoneToday = computed(() => workouts.value.some(w => w.record_date === todayISO));
// o treino "da vez": o de hoje se ainda não foi feito, senão o próximo
const upcomingSession = computed(() => {
  const sessions = programCycle.value?.sessions || [];
  if (todaysSession.value && !workoutDoneToday.value) return todaysSession.value;
  return sessions.find(s => s.key === nextKey.value) || sessions[0] || null;
});

const weekWorkouts = computed(() => workouts.value.filter(w => inThisWeek(w.record_date)));
const lastWeekWorkouts = computed(() => workouts.value.filter(w => inLastWeek(w.record_date)));
const weekBoxings = computed(() => boxings.value.filter(b => inThisWeek(b.record_date)));
const weekSessions = computed(
  () => weekWorkouts.value.length + (boxingOn.value ? weekBoxings.value.length : 0)
);
const weekComplete = computed(() => weekWorkouts.value.length >= weeklyGoal.value);
const PRAISES = [
  'Os 3 treinos da semana feitos. Consistência é o que constrói — orgulho! 🔥',
  'Semana fechada! Quem aparece TODA semana é imbatível. 👑',
  'Mais uma semana completa no bolso. O corpo agradece, o futuro também. 💪',
  'Semana 100%. Isso não é sorte — é disciplina. ⚡',
];
const praise = computed(() => PRAISES[(programWeek.value || 0) % PRAISES.length]);

// ── EXECUÇÕES por exercício (o dado central das cargas) ─────────────
// workouts vêm do mais novo pro mais velho; cada execução = { date,
// sets, top (carga máx), e1 (melhor e-1RM), vol, tag, verdict, cycle_id }
const lowerName = s => String(s || '').trim().toLowerCase();
const executionsOf = name => {
  const alvo = lowerName(name);
  const out = [];
  workouts.value.forEach(w => {
    (w.data?.exercises || []).forEach(e => {
      if (lowerName(e.name) !== alvo || !e.sets?.length) return;
      const sets = e.sets.map(s => ({ load: num(s.load), reps: num(s.reps) }));
      out.push({
        date: w.record_date,
        sets,
        top: Math.max(...sets.map(s => s.load)),
        e1: Math.max(...sets.map(s => e1rm(s.load, s.reps))),
        vol: sets.reduce((a, s) => a + s.load * s.reps, 0),
        tag: e.tag || '',
        method: e.method || '',
        verdict: e.verdict || '',
        cycle_id: w.data?.cycle_id,
        session_key: w.data?.session_key,
        week: Number(w.data?.week) || null,
      });
    });
  });
  return out; // mais novo primeiro
};

const volumeOf = list =>
  list.reduce(
    (a, w) =>
      a +
      (w.data?.exercises || []).reduce(
        (b, e) => b + (e.sets || []).reduce((c, s) => c + num(s.load) * num(s.reps), 0),
        0
      ),
    0
  );
const fmtVol = v => (v >= 1000 ? `${fmt1(v / 1000)} t` : `${Math.round(v)} kg`);
const weekVolume = computed(() => volumeOf(weekWorkouts.value));
const lastWeekVolume = computed(() => volumeOf(lastWeekWorkouts.value));

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

// ── METAS: chavinha A | B | C (rodada 18) — nasce no treino da vez ──
const metasKey = ref('');
const cycleSessions = computed(() => programCycle.value?.sessions || []);
const metasSession = computed(
  () =>
    cycleSessions.value.find(x => x.key === metasKey.value) || upcomingSession.value
);
const upcomingPlan = computed(() => {
  const s = metasSession.value;
  if (!s) return [];
  return (s.exercises || []).map(p => {
    const eq = equipmentOf(p);
    const execs = executionsOf(p.name);
    // última execução na variação principal (registro antigo sem tag = base)
    const last =
      execs.find(x => !x.tag || lowerName(x.tag) === lowerName(eq.base)) || execs[0] || null;
    const lastSets = last?.sets || null;
    return {
      name: eq.options.length > 1 ? nameWithoutEquipment(p.name) : p.name,
      tag: last?.tag || eq.base,
      method: p.method,
      hint: targetHint(p, lastSets),
      targets: setTargets(p, lastSets),
      last: lastSets,
      lastDate: last?.date,
    };
  });
});
const fmtTarget = t => `${String(t.load ?? '').replace('.', ',')}×${t.reps}`;

// ── PROGRESSO DAS CARGAS: cada exercício do ciclo atual ─────────────
const sparkPoints = values => {
  if (values.length < 2) return '';
  const min = Math.min(...values);
  const max = Math.max(...values);
  const span = max - min || 1;
  const W = 84;
  const H = 26;
  return values
    .map((v, i) => {
      const x = (i / (values.length - 1)) * (W - 4) + 2;
      const y = H - 3 - ((v - min) / span) * (H - 6);
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(' ');
};

const loadProgress = computed(() => {
  const cy = programCycle.value;
  if (!cy) return [];
  const seen = new Set();
  return (cy.sessions || []).map(s => ({
    key: s.key,
    weekday: s.weekday,
    exercises: (s.exercises || [])
      .filter(p => {
        const k = lowerName(p.name);
        if (seen.has(k)) return false;
        seen.add(k);
        return true;
      })
      .map(p => {
        const eq = equipmentOf(p);
        const execs = executionsOf(p.name);
        const last = execs[0] || null;
        const prev = execs[1] || null;
        // primeira execução DESTE ciclo (Δ no ciclo); senão a mais antiga
        const inCycle = execs.filter(x => x.cycle_id === cy.id);
        const first = inCycle.length ? inCycle[inCycle.length - 1] : execs[execs.length - 1];
        const bestBefore = execs.slice(1).reduce((m, x) => Math.max(m, x.e1), 0);
        let verdict = last?.verdict || '';
        if (!verdict && last) verdict = prev ? exerciseVerdict(last.sets, prev.sets) : 'first';
        const spark = execs
          .slice(0, 10)
          .reverse()
          .map(x => x.top);
        return {
          name: eq.options.length > 1 ? nameWithoutEquipment(p.name) : p.name,
          tag: last?.tag || '',
          method: p.method,
          last,
          count: execs.length,
          deltaCycle: last && first && last !== first ? last.top - first.top : null,
          pctCycle:
            last && first && last !== first && first.top
              ? Math.round(((last.top - first.top) / first.top) * 1000) / 10
              : null,
          firstE1: first?.e1 ?? null,
          deltaPrev: last && prev ? last.top - prev.top : null,
          verdict,
          pr: Boolean(last && execs.length > 1 && last.e1 > bestBefore + 0.01),
          e1: last ? Math.round(last.e1 * 10) / 10 : null,
          spark: sparkPoints(spark),
          sparkUp: spark.length > 1 ? spark[spark.length - 1] >= spark[0] : true,
          execs,
        };
      }),
  }));
});

// resumo do ciclo: progressões, recordes, sessões feitas
const cycleRecords = computed(() =>
  workouts.value.filter(w => w.data?.cycle_id === programCycle.value?.id)
);
// vereditos do ciclo: usa o salvo no registro; se não tiver (planilha/
// simulação), calcula contra a execução anterior do mesmo exercício
const verdictsFor = exercises => {
  const acc = { progress: 0, tie: 0, regress: 0 };
  const cyId = programCycle.value?.id;
  exercises.forEach(e => {
    (e.execs || []).forEach((x, i) => {
      if (x.cycle_id !== cyId) return;
      const prev = e.execs[i + 1];
      const v = x.verdict || (prev ? exerciseVerdict(x.sets, prev.sets) : 'first');
      if (acc[v] !== undefined) acc[v] += 1;
    });
  });
  return acc;
};
const cycleVerdicts = computed(() =>
  verdictsFor(loadProgress.value.flatMap(s => s.exercises))
);
const cycleProgressions = computed(() => cycleVerdicts.value.progress);
const cyclePRs = computed(() =>
  loadProgress.value.reduce((a, s) => a + s.exercises.filter(e => e.pr).length, 0)
);
const VERDICT_LABEL = { progress: '▲ progrediu', tie: '▬ empatou', regress: '▼ regrediu', first: '🏁 1ª vez' };

// ── CARROSSEL do progresso (rodada 18): 1 slide por treino A/B/C, desliza
// com o dedo (scroll-snap) e tem chavinha + setas; o slide ativo segue
// o scroll
// (um "carrossel" por bloco: el + índice + ir + acompanhar o scroll)
const useCarousel = countOf => {
  const el = ref(null);
  const idx = ref(0);
  const go = i => {
    if (!el.value) return;
    const n = countOf();
    const target = Math.max(0, Math.min(n - 1, i));
    el.value.scrollTo({ left: target * el.value.clientWidth, behavior: 'smooth' });
    idx.value = target;
  };
  // só atualiza quando a rolagem ASSENTA (no meio do deslize suave o
  // scrollLeft passa por valores intermediários e a pílula piscaria)
  let timer = null;
  const onScroll = () => {
    clearTimeout(timer);
    timer = setTimeout(() => {
      if (!el.value || !el.value.clientWidth) return;
      idx.value = Math.round(el.value.scrollLeft / el.value.clientWidth);
    }, 120);
  };
  return { el, idx, go, onScroll };
};
const { el: carousel, idx: slideIdx, go: goSlide, onScroll: onCarouselScroll } = useCarousel(
  () => loadProgress.value.length
);
const SESSION_HINT = {
  A: 'empurrar + braços',
  B: 'pernas + core',
  C: 'puxar + ombros',
};

// ── CAIXINHAS DE CONSISTÊNCIA (rodada 14) ───────────────────────────
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
const adherencePct = computed(() => {
  const t = consistencyTotals.value;
  const total = t.done + t.moved + t.missed;
  return total ? Math.round(((t.done + t.moved) / total) * 100) : null;
});
const CELL_COLORS = {
  done: VERDE_OK,
  moved: LARANJA,
  missed: VERMELHO,
  future: 'rgba(127,127,127,0.18)',
};

// ── CORPO: circunferência abdominal em destaque + peso ──────────────
const seriesOf = key =>
  bodies.value
    .filter(b => Number(b.data?.[key]) > 0)
    .map(b => ({ date: b.record_date, v: Number(b.data[key]) }))
    .sort((a, b) => (a.date > b.date ? 1 : -1));
const weighins = computed(() => seriesOf('weight'));
const waists = computed(() => seriesOf('waist_navel'));
const currentWeight = computed(() => weighins.value.at(-1)?.v || 0);
const firstWeight = computed(() => weighins.value[0]?.v || 0);
const waistNow = computed(() => waists.value.at(-1) || null);
const waistPrev = computed(() => waists.value.at(-2) || null);
const waistFirst = computed(() => waists.value[0] || null);
const waistSpark = computed(() => sparkPoints(waists.value.slice(-12).map(p => p.v)));

const slopeOf = (series, days = 30) => {
  const cut = shiftISO(todayISO, -days);
  const pts = series.filter(p => p.date >= cut);
  if (pts.length < 3) return null;
  const x0 = new Date(`${cut}T00:00:00`);
  const xs = pts.map(p => (new Date(`${p.date}T00:00:00`) - x0) / 86400000);
  const ys = pts.map(p => p.v);
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
  return (cov / varx) * days;
};
const slope30 = computed(() => slopeOf(weighins.value));
const waistSlope30 = computed(() => slopeOf(waists.value));
const projection30 = computed(() =>
  slope30.value === null ? null : currentWeight.value + slope30.value
);
const gapToGoal = computed(() =>
  weightGoal.value > 0 && currentWeight.value > 0 ? currentWeight.value - weightGoal.value : null
);
const goalEta = computed(() => {
  if (gapToGoal.value === null || gapToGoal.value <= 0) return null;
  if (slope30.value === null || slope30.value >= -0.1) return null;
  const days = Math.round((gapToGoal.value / Math.abs(slope30.value)) * 30);
  if (days > 400) return null;
  return { days, label: fmtDay(shiftISO(todayISO, days)) };
});
const weightThisWeek = computed(() =>
  bodies.value.some(b => inThisWeek(b.record_date) && Number(b.data?.weight) > 0)
);

const MEASURE_VIEW = [
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

// ── PROGRESSO DE FORÇA (rodada 17): jeitos de MEDIR a evolução das cargas
// além do Δ kg por exercício:
//   força total    = Σ do melhor e-1RM (última execução) dos exercícios do
//                    ciclo — um número só pra toda a força, comparável
//                    com o mesmo Σ na 1ª execução do ciclo;
//   força relativa = força total ÷ peso corporal (kg por kg) — no cutting
//                    o peso cai e a força sobe: este é o índice que prova;
//   taxa de progressão = % de exercícios ▲ entre os comparáveis do ciclo;
//   tonelagem      = Σ carga×reps do ciclo + média por semana.
const weightAt = iso => {
  const before = weighins.value.filter(p => p.date <= iso);
  return (before.at(-1) || weighins.value[0])?.v || 0;
};
const cycleStartISO = computed(() => {
  const prog = program.value;
  const cy = programCycle.value;
  if (!prog?.start_date || !cy) return null;
  const absWeek = (cycleNumber.value - 1) * CYCLE_LEN + (cy.week_start || 1);
  return shiftISO(prog.start_date, (absWeek - 1) * 7);
});
// força total semana a semana (carry-forward: cada exercício vale o
// último e-1RM conhecido até aquela semana) + força relativa ao peso
const strengthChartFor = exercises => {
  const cy = programCycle.value;
  const prog = program.value;
  if (!cy || !prog?.start_date) return null;
  const names = exercises.map(e => e.name);
  const execsByName = {};
  exercises.forEach(e => {
    execsByName[e.name] = e.execs || [];
  });
  const wStart = cy.week_start || 1;
  const wEnd = Math.min(weekInCycle.value, cy.week_end || CYCLE_LEN);
  const labels = [];
  const total = [];
  const rel = [];
  for (let w = wStart; w <= wEnd; w += 1) {
    const absWeek = (cycleNumber.value - 1) * CYCLE_LEN + w;
    let sum = 0;
    let any = false;
    names.forEach(name => {
      const known = (execsByName[name] || []).find(x => x.week && x.week <= absWeek);
      if (known) {
        sum += known.e1;
        any = true;
      }
    });
    if (!any) continue;
    labels.push(`S${w}`);
    total.push(Math.round(sum));
    const peso = weightAt(shiftISO(prog.start_date, absWeek * 7 - 1));
    rel.push(peso ? Math.round((sum / peso) * 100) / 100 : null);
  }
  if (labels.length < 2) return null;
  return {
    labels,
    datasets: [
      {
        label: 'Força total (Σ e-1RM, kg)',
        data: total,
        borderColor: ROYAL,
        backgroundColor: 'rgba(65,105,225,0.14)',
        fill: true,
        tension: 0.3,
        pointRadius: 2,
        borderWidth: 2,
        yAxisID: 'y',
      },
      {
        label: 'Força relativa (× peso corporal)',
        data: rel,
        borderColor: LARANJA,
        borderDash: [6, 4],
        fill: false,
        tension: 0.3,
        pointRadius: 2,
        borderWidth: 2,
        spanGaps: true,
        yAxisID: 'y1',
      },
    ],
  };
};

// métricas de um conjunto de exercícios (sessionKey null = GERAL, A+B+C)
const strengthFor = sessionKey => {
  const groups = sessionKey
    ? loadProgress.value.filter(g => g.key === sessionKey)
    : loadProgress.value;
  const exercises = groups.flatMap(g => g.exercises);
  const recs = sessionKey
    ? cycleRecords.value.filter(w => w.data?.session_key === sessionKey)
    : cycleRecords.value;
  let now = 0;
  let start = 0;
  let n = 0;
  exercises.forEach(e => {
    if (!e.last) return;
    now += e.last.e1;
    start += e.firstE1 ?? e.last.e1;
    n += 1;
  });
  const pesoNow = currentWeight.value || 0;
  const pesoStart = cycleStartISO.value ? weightAt(cycleStartISO.value) : firstWeight.value;
  const rel = pesoNow ? now / pesoNow : null;
  const relStart = pesoStart ? start / pesoStart : null;
  const verdicts = verdictsFor(exercises);
  const comparable = verdicts.progress + verdicts.tie + verdicts.regress;
  const tonnage = volumeOf(recs);
  const cy = programCycle.value;
  const weeksElapsed = cy ? Math.max(1, weekInCycle.value - (cy.week_start || 1) + 1) : 1;
  return {
    n,
    now: Math.round(now),
    start: Math.round(start),
    delta: Math.round(now - start),
    pct: start ? Math.round(((now - start) / start) * 1000) / 10 : null,
    rel: rel === null ? null : Math.round(rel * 100) / 100,
    relStart: relStart === null ? null : Math.round(relStart * 100) / 100,
    relDelta: rel !== null && relStart !== null ? Math.round((rel - relStart) * 100) / 100 : null,
    rate: comparable ? Math.round((verdicts.progress / comparable) * 100) : null,
    verdicts,
    comparable,
    tonnage,
    tonnagePerWeek: tonnage / weeksElapsed,
    chart: strengthChartFor(exercises),
    exercises: exercises.length,
  };
};
const strength = computed(() => strengthFor(null));
// slides do carrossel de força: Geral + um por treino
const strengthSlides = computed(() => [
  {
    key: 'geral',
    letter: 'Σ',
    title: 'Geral',
    sub: 'A + B + C · todos os exercícios do ciclo',
    m: strength.value,
  },
  ...loadProgress.value.map(g => ({
    key: g.key,
    letter: g.key,
    title: `Treino ${g.key}`,
    sub: `${g.weekday} · ${g.exercises.length} exercícios${SESSION_HINT[g.key] ? ` · ${SESSION_HINT[g.key]}` : ''}`,
    m: strengthFor(g.key),
  })),
]);

const {
  el: forceCarousel,
  idx: forceIdx,
  go: goForce,
  onScroll: onForceScroll,
} = useCarousel(() => strengthSlides.value.length);

// ── BALANÇO DE CENTÍMETROS (rodada 17): quanto o corpo mudou, no total ──
// "perdidos onde importa" = cintura/cintura estreita/quadril/pescoço
// (queda é vitória) · "ganhos onde importa" = peito/braços/coxas/ombros
// (subida é vitória) · saldo = soma de tudo com sinal.
const round1 = v => Math.round(v * 10) / 10;
const cmBalance = computed(() => {
  const all = [{ key: 'waist_navel', label: 'Cintura (umbigo)', down: true }, ...MEASURE_VIEW];
  const rows = all
    .map(m => {
      const s = seriesOf(m.key);
      if (s.length < 2) return null;
      const first = s[0].v;
      const last = s.at(-1).v;
      const prev = s.at(-2).v;
      return {
        ...m,
        first,
        last,
        dStart: round1(last - first),
        dPrev: round1(last - prev),
        firstDate: s[0].date,
        good: m.down ? last - first < 0 : last - first > 0,
      };
    })
    .filter(Boolean)
    .sort((a, b) => Math.abs(b.dStart) - Math.abs(a.dStart));
  const sum = (list, f) => round1(list.reduce((a, r) => a + f(r), 0));
  const lose = rows.filter(r => r.down);
  const gain = rows.filter(r => !r.down);
  return {
    rows,
    lostStart: sum(lose, r => r.dStart),
    lostPrev: sum(lose, r => r.dPrev),
    gainStart: sum(gain, r => r.dStart),
    gainPrev: sum(gain, r => r.dPrev),
    netStart: sum(rows, r => r.dStart),
    netPrev: sum(rows, r => r.dPrev),
    movedStart: sum(rows, r => Math.abs(r.dStart)),
    since: rows.length ? rows.reduce((a, r) => (r.firstDate < a ? r.firstDate : a), rows[0].firstDate) : null,
  };
});

// gráfico: cintura (laranja, eixo esq.) × peso (royal, eixo dir.)
const bodyChart = computed(() => {
  const dates = [...new Set([...waists.value, ...weighins.value].map(p => p.date))]
    .sort()
    .slice(-30);
  const at = (series, d) => series.find(p => p.date === d)?.v ?? null;
  const data = {
    labels: dates.map(fmtDay),
    datasets: [
      {
        label: 'Cintura (cm)',
        data: dates.map(d => at(waists.value, d)),
        borderColor: LARANJA,
        backgroundColor: 'rgba(255,138,0,0.12)',
        fill: true,
        tension: 0.35,
        pointRadius: 2,
        borderWidth: 2,
        spanGaps: true,
        yAxisID: 'y',
      },
      {
        label: 'Peso (kg)',
        data: dates.map(d => at(weighins.value, d)),
        borderColor: ROYAL,
        backgroundColor: 'transparent',
        fill: false,
        tension: 0.35,
        pointRadius: 2,
        borderWidth: 2,
        spanGaps: true,
        yAxisID: 'y1',
      },
    ],
  };
  if (weightGoal.value > 0) {
    data.datasets.push({
      label: 'Peso-alvo',
      data: dates.map(() => weightGoal.value),
      borderColor: ROYAL_CLARO,
      borderDash: [6, 5],
      borderWidth: 1.5,
      pointRadius: 0,
      fill: false,
      yAxisID: 'y1',
    });
  }
  return data;
});
const bodyChartOpts = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: { legend: { display: true, labels: { boxWidth: 10, font: { size: 10 } } } },
  scales: {
    x: { ticks: { font: { size: 9 } }, grid: { display: false } },
    y: { position: 'left', ticks: { font: { size: 9 } } },
    y1: { position: 'right', ticks: { font: { size: 9 } }, grid: { drawOnChartArea: false } },
  },
};

// ── DIETA: só referência ────────────────────────────────────────────
const dietToday = computed(() => diets.value.find(d => d.record_date === todayISO));
const mealsTotal = computed(() => (config.value.diet?.meals || []).length);
const mealsDoneToday = computed(() => (dietToday.value?.data?.meals_done || []).length);
const kcalOfDay = d => {
  const meals = config.value.diet?.meals || [];
  const done = d.data?.meals_done || [];
  const base = meals.filter(m => done.includes(m.id)).reduce((s, m) => s + (Number(m.kcal) || 0), 0);
  const extra = (d.data?.extras || []).reduce((s, e) => s + (Number(e.kcal) || 0), 0);
  return base + extra;
};
const weekKcalAvg = computed(() => {
  const days = diets.value.filter(d => inThisWeek(d.record_date));
  if (!days.length) return 0;
  return Math.round(days.reduce((sum, d) => sum + kcalOfDay(d), 0) / days.length);
});
const kcalDelta = computed(() => {
  const meta = Number(dietTargets.value.kcal) || 0;
  if (!meta || !weekKcalAvg.value) return null;
  return weekKcalAvg.value - meta;
});
</script>

<template>
  <div class="flex-1 overflow-auto p-4 sm:p-6">
    <div class="max-w-5xl mx-auto">
      <div v-if="isLoading" class="flex justify-center py-16"><Spinner /></div>
      <template v-else>
        <!-- HERO: ciclo + treino da vez + placar da semana -->
        <div class="rounded-2xl p-5 mb-4 text-white" :style="{ background: GRAD_NOITE }">
          <div class="flex items-center justify-between flex-wrap gap-3">
            <div>
              <div class="flex items-center gap-2 flex-wrap mb-1">
                <h1 class="text-lg font-bold text-white" style="color: #fff">Meu Painel · Treino</h1>
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
                <template v-else>Suas cargas, seu progresso, sua transformação.</template>
              </p>
              <p class="text-[11px] mt-1" :style="{ color: ROYAL_CLARO }">
                <template v-if="cyclesDone === 0">🚀 Primeiro ciclo — é aqui que a base é construída.</template>
                <template v-else>
                  🏅 {{ cyclesDone }} {{ cyclesDone === 1 ? 'ciclo completo' : 'ciclos completos' }} de 24 semanas.
                </template>
              </p>
            </div>
            <div class="flex flex-col items-end gap-2">
              <button
                v-if="upcomingSession"
                class="h-11 px-5 rounded-xl text-sm font-bold text-white shadow-lg"
                :style="{ background: GRAD_LARANJA }"
                @click="go('hub_health')"
              >
                ▶ Treino {{ upcomingSession.key }}
                {{ todaysSession && !workoutDoneToday ? 'de hoje' : workoutDoneToday ? '· próximo' : '' }}
              </button>
              <p class="text-[11px] opacity-90">
                Semana: <b>{{ weekSessions }} de {{ weeklyGoal }}</b> sessões ·
                <span :style="{ color: '#7EE2A8' }">▲{{ weekScore.progress }}</span>
                <span class="opacity-70 mx-1">▬{{ weekScore.tie }}</span>
                <span :style="{ color: '#FF9C9C' }">▼{{ weekScore.regress }}</span>
              </p>
            </div>
          </div>
        </div>

        <!-- ELOGIO: semana completa -->
        <div v-if="weekComplete" class="hub-praise rounded-2xl px-4 py-3 mb-4 flex items-center gap-3">
          <span class="text-2xl">🏆</span>
          <div>
            <p class="text-sm font-bold" :style="{ color: LARANJA_CLARO }">Semana completa!</p>
            <p class="text-xs text-n-slate-11">{{ praise }}</p>
          </div>
        </div>

        <!-- KPIs do treino -->
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5">
          <DashKpi
            label="Volume da semana"
            :value="fmtVol(weekVolume)"
            :sub="lastWeekVolume ? `semana passada ${fmtVol(lastWeekVolume)}` : 'Σ carga × reps'"
            :from="ROYAL_NOITE"
            :to="ROYAL"
          />
          <DashKpi
            label="Progressões no ciclo"
            :value="cycleProgressions"
            sub="exercícios superados"
            :from="LARANJA_ESCURO"
            :to="LARANJA"
          />
          <DashKpi
            label="Recordes"
            :value="cyclePRs"
            sub="exercícios no melhor e-1RM"
            :from="ROYAL_PROFUNDO"
            :to="ROYAL_CLARO"
          />
          <DashKpi
            label="Aderência do ciclo"
            :value="adherencePct === null ? '—' : `${adherencePct}%`"
            :sub="`${consistencyTotals.done + consistencyTotals.moved} treinos feitos`"
            :from="LARANJA_VIVO"
            :to="LARANJA_CLARO"
          />
        </div>

        <!-- PRÓXIMO TREINO: metas por exercício -->
        <div class="flex items-center justify-between gap-2 flex-wrap mb-2">
          <h2 class="text-xs font-bold text-n-slate-11 uppercase tracking-wide">
            🎯 Metas do Treino {{ metasSession?.key || '' }}
            <span v-if="metasSession?.weekday" class="font-normal normal-case text-n-slate-10">· {{ metasSession.weekday }}</span>
            <span
              v-if="metasSession && upcomingSession && metasSession.key === upcomingSession.key"
              class="ml-1 px-1.5 py-0.5 rounded-full text-[9px] font-bold normal-case"
              :style="{ background: LARANJA, color: '#1a0e00' }"
            >
              da vez
            </span>
          </h2>
          <span v-if="cycleSessions.length > 1" class="hub-seg">
            <button
              v-for="sx in cycleSessions"
              :key="sx.key"
              class="hub-seg-opt"
              :class="{ 'is-on': metasSession?.key === sx.key }"
              :style="metasSession?.key === sx.key ? { background: ROYAL } : {}"
              :title="`Treino ${sx.key} · ${sx.weekday}`"
              @click="metasKey = sx.key"
            >
              Treino {{ sx.key }}
            </button>
          </span>
        </div>
        <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-5">
          <p v-if="!upcomingPlan.length" class="text-[11px] text-n-slate-10">
            Sem programa ativo — configure o Warrior na aba Treino.
          </p>
          <div v-for="ex in upcomingPlan" :key="ex.name" class="py-2.5 border-b border-n-weak/60 last:border-0 last:pb-0 first:pt-0">
            <div class="flex items-center gap-2 flex-wrap mb-1">
              <p class="text-sm font-bold text-n-slate-12">{{ ex.name }}</p>
              <span
                v-if="ex.tag"
                class="px-1.5 py-0.5 rounded-full text-[10px] font-medium border border-dashed border-n-weak text-n-slate-10"
              >
                {{ ex.tag }}
              </span>
              <span
                v-if="ex.method"
                class="px-1.5 py-0.5 rounded text-[10px] font-bold text-white"
                :style="{ background: ex.method === 'rest_pause' ? LARANJA_VIVO : ex.method === 'pyramid' ? LARANJA : ROYAL }"
              >
                {{ METHOD_LABELS[ex.method] || ex.method }}
              </span>
              <span v-if="ex.last" class="text-[11px] text-n-slate-10">
                última {{ ex.lastDate ? fmtDay(ex.lastDate) : '' }}: {{ fmtSets(ex.last) }}
              </span>
            </div>
            <div class="flex gap-1.5 flex-wrap items-center">
              <span
                v-for="(t, ti) in ex.targets"
                :key="ti"
                class="hub-target"
                :class="{ 'is-gold': ex.hint.startsWith('🎯') }"
              >
                <span class="opacity-60">{{ t.label }}</span>
                <b>{{ t.load != null ? fmtTarget(t) : t.reps }}</b>
              </span>
              <span
                class="text-[11px] font-medium"
                :style="{ color: ex.hint.startsWith('🎯') ? LARANJA : ROYAL }"
              >
                {{ ex.hint }}
              </span>
            </div>
          </div>
        </div>

        <!-- PROGRESSO DAS CARGAS: todos os exercícios do ciclo -->
        <div class="flex items-center justify-between gap-2 flex-wrap mb-2">
          <h2 class="text-xs font-bold text-n-slate-11 uppercase tracking-wide">🏋️ Progresso das cargas</h2>
          <span v-if="loadProgress.length > 1" class="hub-seg">
            <button
              v-for="(s, i) in loadProgress"
              :key="s.key"
              class="hub-seg-opt"
              :class="{ 'is-on': slideIdx === i }"
              :style="slideIdx === i ? { background: ROYAL } : {}"
              @click="goSlide(i)"
            >
              Treino {{ s.key }}
            </button>
          </span>
        </div>
        <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-5">
          <p class="text-[11px] text-n-slate-10 mb-3">
            Carga máxima de cada exercício, execução a execução. <b>Δ ciclo</b> = quanto subiu
            desde a 1ª vez neste ciclo · 🏅 = melhor força estimada (e-1RM) de todos os tempos.
            <span class="opacity-80">Deslize pro lado pra ver os outros treinos.</span>
          </p>
          <!-- carrossel: 1 slide por treino -->
          <div ref="carousel" class="hub-carousel" @scroll.passive="onCarouselScroll">
            <div v-for="(s, i) in loadProgress" :key="s.key" class="hub-slide">
              <!-- cabeçalho grande do treino -->
              <div class="flex items-center gap-3 rounded-2xl px-4 py-3 mb-3 text-white" :style="{ background: GRAD_NOITE }">
                <span
                  class="w-11 h-11 rounded-xl flex items-center justify-center text-2xl font-black shrink-0"
                  :style="{ background: LARANJA, color: '#1a0e00' }"
                >
                  {{ s.key }}
                </span>
                <div class="flex-1 min-w-0">
                  <p class="text-base font-extrabold leading-tight">Treino {{ s.key }}</p>
                  <p class="text-[11px] opacity-85">
                    {{ s.weekday }} · {{ s.exercises.length }} exercícios
                    <template v-if="SESSION_HINT[s.key]"> · {{ SESSION_HINT[s.key] }}</template>
                  </p>
                </div>
                <div class="flex items-center gap-1 shrink-0">
                  <button
                    class="hub-arrow"
                    :disabled="i === 0"
                    title="Treino anterior"
                    @click="goSlide(i - 1)"
                  >
                    ‹
                  </button>
                  <span class="text-[10px] opacity-80">{{ i + 1 }}/{{ loadProgress.length }}</span>
                  <button
                    class="hub-arrow"
                    :disabled="i === loadProgress.length - 1"
                    title="Próximo treino"
                    @click="goSlide(i + 1)"
                  >
                    ›
                  </button>
                </div>
              </div>
              <div class="grid gap-2" style="grid-template-columns: repeat(auto-fill, minmax(260px, 1fr))">
              <div
                v-for="e in s.exercises"
                :key="e.name"
                class="rounded-xl border border-n-weak p-2.5 flex items-center gap-3"
              >
                <div class="flex-1 min-w-0">
                  <p class="text-xs font-bold text-n-slate-12 truncate">
                    {{ e.name }}
                    <span v-if="e.tag" class="font-normal text-n-slate-10">· {{ e.tag }}</span>
                    <span v-if="e.pr" title="Recorde de força estimada (e-1RM)">🏅</span>
                  </p>
                  <p v-if="e.last" class="text-[11px] text-n-slate-10 truncate">
                    {{ fmtSets(e.last.sets) }}
                    <span class="opacity-70">· {{ fmtDay(e.last.date) }}</span>
                  </p>
                  <p v-else class="text-[11px] text-n-slate-10">ainda não feito</p>
                  <p v-if="e.last" class="text-[11px] flex items-center gap-2 flex-wrap mt-0.5">
                    <span
                      v-if="e.deltaCycle !== null"
                      class="font-bold"
                      :style="{ color: e.deltaCycle > 0 ? VERDE_OK : e.deltaCycle < 0 ? VERMELHO : CINZA }"
                    >
                      Δ ciclo {{ signed(e.deltaCycle) }} kg<template v-if="e.pctCycle !== null"> ({{ signed(e.pctCycle) }}%)</template>
                    </span>
                    <span v-if="e.verdict" :style="{ color: VERDICT_COLORS[e.verdict] || LARANJA }">
                      {{ VERDICT_LABEL[e.verdict] }}
                    </span>
                    <span v-if="e.e1" class="text-n-slate-10">e-1RM {{ fmt1(e.e1) }}</span>
                  </p>
                </div>
                <div class="shrink-0 text-right">
                  <p class="text-lg font-extrabold leading-none" :style="{ color: e.last ? ROYAL : CINZA }">
                    {{ e.last ? fmt1(e.last.top) : '—' }}<span class="text-[10px] font-medium text-n-slate-10"> kg</span>
                  </p>
                  <svg v-if="e.spark" viewBox="0 0 84 26" class="hub-spark mt-1">
                    <polyline
                      :points="e.spark"
                      fill="none"
                      :stroke="e.sparkUp ? ROYAL : LARANJA"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    />
                  </svg>
                  <p v-else class="text-[9px] text-n-slate-10 mt-1">{{ e.count }} {{ e.count === 1 ? 'execução' : 'execuções' }}</p>
                </div>
              </div>
            </div>
            </div>
          </div>
          <!-- bolinhas do carrossel -->
          <div v-if="loadProgress.length > 1" class="flex justify-center gap-1.5 mt-3">
            <button
              v-for="(s, i) in loadProgress"
              :key="s.key"
              class="w-2 h-2 rounded-full transition-all"
              :style="{ background: slideIdx === i ? ROYAL : 'rgba(127,127,127,0.3)', transform: slideIdx === i ? 'scale(1.35)' : 'none' }"
              :title="`Treino ${s.key}`"
              @click="goSlide(i)"
            />
          </div>
        </div>

        <!-- PROGRESSO DE FORÇA: carrossel Geral | A | B | C -->
        <div class="flex items-center justify-between gap-2 flex-wrap mb-2">
          <h2 class="text-xs font-bold text-n-slate-11 uppercase tracking-wide">📈 Progresso de força</h2>
          <span v-if="strengthSlides.length > 1" class="hub-seg">
            <button
              v-for="(sl, i) in strengthSlides"
              :key="sl.key"
              class="hub-seg-opt"
              :class="{ 'is-on': forceIdx === i }"
              :style="forceIdx === i ? { background: sl.key === 'geral' ? LARANJA : ROYAL } : {}"
              @click="goForce(i)"
            >
              {{ sl.key === 'geral' ? 'Geral' : `Treino ${sl.key}` }}
            </button>
          </span>
        </div>
        <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-5">
          <p class="text-[11px] text-n-slate-10 mb-3">
            <b>Força total</b> = soma da força estimada (e-1RM) dos exercícios, um número só.
            <b>Força relativa</b> = essa força dividida pelo seu peso: no cutting, é o que prova que
            você emagreceu ficando mais forte. <span class="opacity-80">Deslize pro lado: geral e cada treino.</span>
          </p>
          <div ref="forceCarousel" class="hub-carousel" @scroll.passive="onForceScroll">
            <div v-for="(sl, i) in strengthSlides" :key="sl.key" class="hub-slide">
              <div
                class="flex items-center gap-3 rounded-2xl px-4 py-3 mb-3 text-white"
                :style="{ background: sl.key === 'geral' ? GRAD_LARANJA : GRAD_NOITE }"
              >
                <span
                  class="w-11 h-11 rounded-xl flex items-center justify-center text-2xl font-black shrink-0"
                  :style="sl.key === 'geral' ? { background: '#fff', color: LARANJA_VIVO } : { background: LARANJA, color: '#1a0e00' }"
                >
                  {{ sl.letter }}
                </span>
                <div class="flex-1 min-w-0">
                  <p class="text-base font-extrabold leading-tight">{{ sl.title }}</p>
                  <p class="text-[11px] opacity-85">{{ sl.sub }}</p>
                </div>
                <div class="flex items-center gap-1 shrink-0">
                  <button class="hub-arrow" :disabled="i === 0" title="Anterior" @click="goForce(i - 1)">‹</button>
                  <span class="text-[10px] opacity-80">{{ i + 1 }}/{{ strengthSlides.length }}</span>
                  <button class="hub-arrow" :disabled="i === strengthSlides.length - 1" title="Próximo" @click="goForce(i + 1)">›</button>
                </div>
              </div>
              <div class="grid gap-3 mb-3" style="grid-template-columns: repeat(auto-fit, minmax(150px, 1fr))">
                <div class="rounded-2xl p-3 text-white" :style="{ background: GRAD_ROYAL }">
                  <p class="text-[11px] opacity-90">Força total (Σ e-1RM)</p>
                  <p class="text-xl font-bold">{{ sl.m.n ? `${sl.m.now} kg` : '—' }}</p>
                  <p class="text-[10px] opacity-90">
                    <template v-if="sl.m.n && sl.m.delta">
                      {{ signed(sl.m.delta) }} kg no ciclo<template v-if="sl.m.pct !== null"> ({{ signed(sl.m.pct) }}%)</template>
                    </template>
                    <template v-else-if="sl.m.n">partiu de {{ sl.m.start }} kg</template>
                    <template v-else>registre treinos</template>
                  </p>
                </div>
                <div class="rounded-2xl p-3 text-white" :style="{ background: GRAD_LARANJA }">
                  <p class="text-[11px] opacity-90">Força relativa</p>
                  <p class="text-xl font-bold">{{ sl.m.rel !== null ? `${String(sl.m.rel).replace('.', ',')}×` : '—' }}</p>
                  <p class="text-[10px] opacity-90">
                    <template v-if="sl.m.relDelta !== null && sl.m.relDelta !== 0">
                      {{ signed(sl.m.relDelta) }} × peso desde o início do ciclo
                    </template>
                    <template v-else>força por kg de peso corporal</template>
                  </p>
                </div>
                <div class="rounded-2xl p-3 border border-n-weak bg-n-solid-1">
                  <p class="text-[11px] text-n-slate-10">Taxa de progressão</p>
                  <p class="text-xl font-bold" :style="{ color: sl.m.rate === null ? undefined : sl.m.rate >= 50 ? VERDE_OK : LARANJA }">
                    {{ sl.m.rate === null ? '—' : `${sl.m.rate}%` }}
                  </p>
                  <p class="text-[10px] text-n-slate-10">
                    <template v-if="sl.m.comparable">
                      ▲{{ sl.m.verdicts.progress }} ▬{{ sl.m.verdicts.tie }} ▼{{ sl.m.verdicts.regress }} no ciclo
                    </template>
                    <template v-else>exercícios superados ÷ comparáveis</template>
                  </p>
                </div>
                <div class="rounded-2xl p-3 border border-n-weak bg-n-solid-1">
                  <p class="text-[11px] text-n-slate-10">Tonelagem do ciclo</p>
                  <p class="text-xl font-bold" :style="{ color: ROYAL }">{{ fmtVol(sl.m.tonnage) }}</p>
                  <p class="text-[10px] text-n-slate-10">≈ {{ fmtVol(sl.m.tonnagePerWeek) }} por semana</p>
                </div>
              </div>
              <div v-if="sl.m.chart" style="height: 170px">
                <Line :data="sl.m.chart" :options="bodyChartOpts" />
              </div>
              <p v-else class="text-[11px] text-n-slate-10">
                A curva da força aparece a partir da 2ª semana com treinos registrados.
              </p>
            </div>
          </div>
          <div v-if="strengthSlides.length > 1" class="flex justify-center gap-1.5 mt-3">
            <button
              v-for="(sl, i) in strengthSlides"
              :key="sl.key"
              class="w-2 h-2 rounded-full transition-all"
              :style="{ background: forceIdx === i ? (sl.key === 'geral' ? LARANJA : ROYAL) : 'rgba(127,127,127,0.3)', transform: forceIdx === i ? 'scale(1.35)' : 'none' }"
              :title="sl.title"
              @click="goForce(i)"
            />
          </div>
        </div>

        <!-- CONSISTÊNCIA: caixinhas do ciclo -->
        <h2 class="text-xs font-bold text-n-slate-11 uppercase tracking-wide mb-2">📦 Consistência do ciclo</h2>
        <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-5">
          <div class="flex items-center justify-between flex-wrap gap-2 mb-3">
            <p class="text-[11px] text-n-slate-10">Cada coluna é uma semana; cada caixinha, um treino planejado.</p>
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
                  :title="`S${w.n} · Treino ${c.key} · ${fmtDay(c.plannedISO)} — ${
                    { done: 'feito no dia', moved: 'reagendado (feito noutro dia)', missed: 'não foi', future: 'a fazer' }[c.state]
                  }`"
                />
                <span class="text-[8px]" :class="w.current ? 'font-bold' : 'text-n-slate-10'" :style="w.current ? { color: ROYAL } : {}">
                  {{ w.n }}
                </span>
              </div>
            </div>
          </div>
        </div>

        <!-- CORPO: circunferência abdominal em destaque + peso -->
        <h2 class="text-xs font-bold text-n-slate-11 uppercase tracking-wide mb-2">📏 Corpo — indicadores</h2>
        <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-5">
          <div class="grid gap-3 mb-3" style="grid-template-columns: repeat(auto-fit, minmax(160px, 1fr))">
            <!-- destaque: cintura no umbigo -->
            <div class="rounded-2xl p-3 text-white sm:col-span-2 flex items-center gap-3" :style="{ background: GRAD_LARANJA }">
              <div class="flex-1 min-w-0">
                <p class="text-[11px] opacity-90">Circunferência abdominal (umbigo)</p>
                <p class="text-2xl font-extrabold leading-tight">
                  {{ waistNow ? fmtCm(waistNow.v) : '—' }}
                </p>
                <p class="text-[11px] opacity-90">
                  <template v-if="waistPrev">
                    {{ signed(waistNow.v - waistPrev.v) }} cm vs anterior
                  </template>
                  <template v-if="waistFirst && waistFirst !== waistNow">
                    · {{ signed(waistNow.v - waistFirst.v) }} cm desde o início ({{ fmtDay(waistFirst.date) }})
                  </template>
                  <template v-if="waistSlope30 !== null"> · ritmo {{ signed(waistSlope30) }} cm/mês</template>
                  <template v-if="!waistPrev && !waistNow">registre na aba Corpo — é o indicador do momento</template>
                </p>
              </div>
              <svg v-if="waistSpark" viewBox="0 0 84 26" class="hub-spark shrink-0" style="width: 84px">
                <polyline :points="waistSpark" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
            </div>
            <div class="rounded-2xl p-3 text-white" :style="{ background: GRAD_ROYAL }">
              <p class="text-[11px] opacity-90">Peso atual</p>
              <p class="text-xl font-bold">{{ currentWeight ? fmtKg(currentWeight) : '—' }}</p>
              <p class="text-[10px] opacity-85">
                <template v-if="weighins.length > 1">{{ signed(currentWeight - firstWeight) }} kg desde o início</template>
                <template v-else-if="!weightThisWeek">pesagem da semana pendente</template>
                <template v-else>pesagem da semana ✓</template>
              </p>
            </div>
            <div class="rounded-2xl p-3" :style="{ background: 'rgba(65,105,225,0.10)', border: '1px solid rgba(65,105,225,0.35)' }">
              <p class="text-[11px] text-n-slate-10">Peso-alvo</p>
              <template v-if="!editingGoal">
                <p class="text-xl font-bold" :style="{ color: ROYAL }">{{ weightGoal > 0 ? fmtKg(weightGoal) : '—' }}</p>
                <p class="text-[10px] text-n-slate-10">
                  <template v-if="gapToGoal !== null && gapToGoal <= 0">🎉 alvo batido!</template>
                  <template v-else-if="gapToGoal !== null">faltam {{ fmtKg(gapToGoal) }}</template>
                  <button class="underline ml-1" @click="editingGoal = true; goalDraft = weightGoal || ''">
                    {{ weightGoal > 0 ? 'ajustar' : 'definir' }}
                  </button>
                </p>
              </template>
              <div v-else class="flex items-center gap-1.5">
                <WheelInput v-model="goalDraft" :step="0.5" :max="200" decimal placeholder="kg" style="width: 5rem" />
                <button class="h-8 px-2 rounded-lg text-[11px] font-bold text-white" :style="{ background: ROYAL }" @click="saveGoal">✓</button>
              </div>
            </div>
          </div>

          <div class="grid gap-3 mb-3" style="grid-template-columns: repeat(auto-fit, minmax(140px, 1fr))">
            <DashKpi
              label="Ritmo (30d)"
              :value="slope30 === null ? '—' : `${slope30 > 0 ? '+' : '−'}${fmt1(Math.abs(slope30))} kg/mês`"
              hint="tendência das pesagens"
            />
            <DashKpi label="Peso em 30 dias" :value="projection30 === null ? '—' : `~${fmtKg(projection30)}`" hint="se o ritmo continuar" />
            <DashKpi
              label="Chegada ao alvo"
              :value="gapToGoal !== null && gapToGoal <= 0 ? '🎉 batido!' : goalEta ? `≈ ${goalEta.label}` : '—'"
              :hint="goalEta ? `~${goalEta.days} dias no ritmo atual` : 'precisa de ritmo de queda'"
              :value-color="LARANJA"
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
          <!-- balanço de centímetros (rodada 17) -->
          <div v-if="cmBalance.rows.length" class="rounded-xl border border-n-weak p-3 mb-3">
            <p class="text-[11px] font-bold text-n-slate-11 mb-2">
              📐 Balanço de centímetros
              <span class="font-normal text-n-slate-10">desde {{ cmBalance.since ? fmtDay(cmBalance.since) : 'o início' }}</span>
            </p>
            <div class="grid gap-2 mb-2" style="grid-template-columns: repeat(auto-fit, minmax(140px, 1fr))">
              <div class="rounded-xl p-2.5" :style="{ background: 'rgba(255,138,0,0.10)', border: '1px solid rgba(255,138,0,0.35)' }">
                <p class="text-[10px] text-n-slate-10">Onde quer perder</p>
                <p class="text-lg font-extrabold leading-tight" :style="{ color: cmBalance.lostStart <= 0 ? LARANJA : VERMELHO }">
                  {{ signed(cmBalance.lostStart) }} cm
                </p>
                <p class="text-[10px] text-n-slate-10">cintura · quadril · pescoço · {{ signed(cmBalance.lostPrev) }} vs última</p>
              </div>
              <div class="rounded-xl p-2.5" :style="{ background: 'rgba(65,105,225,0.10)', border: '1px solid rgba(65,105,225,0.35)' }">
                <p class="text-[10px] text-n-slate-10">Onde quer ganhar</p>
                <p class="text-lg font-extrabold leading-tight" :style="{ color: cmBalance.gainStart >= 0 ? ROYAL : LARANJA }">
                  {{ signed(cmBalance.gainStart) }} cm
                </p>
                <p class="text-[10px] text-n-slate-10">peito · braços · coxas · ombros · {{ signed(cmBalance.gainPrev) }} vs última</p>
              </div>
              <div class="rounded-xl p-2.5 border border-n-weak">
                <p class="text-[10px] text-n-slate-10">Saldo total</p>
                <p class="text-lg font-extrabold leading-tight text-n-slate-12">{{ signed(cmBalance.netStart) }} cm</p>
                <p class="text-[10px] text-n-slate-10">{{ fmt1(cmBalance.movedStart) }} cm movidos no total · {{ signed(cmBalance.netPrev) }} vs última</p>
              </div>
            </div>
            <div class="flex gap-1.5 flex-wrap">
              <span
                v-for="r in cmBalance.rows"
                :key="r.key"
                class="inline-flex items-center gap-1 h-6 px-2 rounded-full text-[10px] border border-n-weak bg-n-solid-2"
                :title="`${r.label}: ${fmt1(r.first)} → ${fmt1(r.last)} cm`"
              >
                <span class="text-n-slate-10">{{ r.label }}</span>
                <b :style="{ color: r.dStart === 0 ? CINZA : r.good ? VERDE_OK : LARANJA }">{{ signed(r.dStart) }}</b>
              </span>
            </div>
          </div>
          <div v-if="weighins.length > 1 || waists.length > 1" style="height: 170px">
            <Line :data="bodyChart" :options="bodyChartOpts" />
          </div>
          <p v-else class="text-[11px] text-n-slate-10">
            Registre peso e cintura na aba Corpo pra curva aparecer aqui.
          </p>
        </div>

        <!-- DIETA: só referência -->
        <h2 class="text-xs font-bold text-n-slate-11 uppercase tracking-wide mb-2">🍽 Dieta (referência)</h2>
        <button
          class="w-full rounded-2xl border border-n-weak bg-n-solid-1 p-3 mb-5 text-left hover:bg-n-alpha-1 flex items-center gap-3 flex-wrap"
          @click="go('hub_health_dieta')"
        >
          <span class="text-[11px] text-n-slate-11">
            Meta <b :style="{ color: LARANJA }">{{ dietTargets.kcal || '—' }} kcal</b>
            · proteína <b :style="{ color: ROYAL }">{{ dietTargets.protein ? `${dietTargets.protein} g` : '—' }}</b>
          </span>
          <span class="text-[11px] text-n-slate-10">
            hoje {{ mealsDoneToday }} de {{ mealsTotal || '—' }} refeições
          </span>
          <span v-if="kcalDelta !== null" class="text-[11px] text-n-slate-10">
            · média da semana {{ weekKcalAvg }} kcal
            <b :style="{ color: kcalDelta <= 0 ? VERDE_OK : VERMELHO }">({{ kcalDelta > 0 ? '+' : '' }}{{ kcalDelta }})</b>
          </span>
          <span class="ml-auto text-[11px]" :style="{ color: ROYAL_CLARO }">abrir →</span>
        </button>

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
  background: linear-gradient(135deg, rgba(255, 138, 0, 0.14), rgba(255, 107, 26, 0.05) 55%, rgba(255, 255, 255, 0.03));
  -webkit-backdrop-filter: blur(12px) saturate(1.4);
  backdrop-filter: blur(12px) saturate(1.4);
  border: 1px solid rgba(255, 138, 0, 0.3);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.08),
    0 8px 22px -14px rgba(255, 138, 0, 0.55);
}
/* alvo por série do próximo treino (mesma cara do vidro da sessão) */
.hub-target {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  height: 1.6rem;
  padding: 0 0.55rem;
  border-radius: 9999px;
  font-size: 11px;
  background: rgba(65, 105, 225, 0.1);
  border: 1px solid rgba(65, 105, 225, 0.28);
}
.hub-target.is-gold {
  background: rgba(255, 138, 0, 0.12);
  border-color: rgba(255, 138, 0, 0.35);
}
.hub-spark {
  width: 84px;
  height: 26px;
  display: block;
}
/* chavinha segmentada (A | B | C) — mesma cara da do treino */
.hub-seg {
  display: inline-flex;
  align-items: center;
  gap: 2px;
  padding: 2px;
  border-radius: 9999px;
  background: rgba(127, 127, 127, 0.14);
  border: 1px solid rgba(127, 127, 127, 0.18);
}
.hub-seg-opt {
  height: 1.6rem;
  padding: 0 0.7rem;
  border-radius: 9999px;
  font-size: 11px;
  font-weight: 600;
  color: inherit;
  opacity: 0.65;
  transition: all 0.15s ease;
}
.hub-seg-opt.is-on {
  color: #fff;
  opacity: 1;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.25);
}
/* carrossel dos treinos: desliza com o dedo, ímã em cada slide */
.hub-carousel {
  display: flex;
  overflow-x: auto;
  scroll-snap-type: x mandatory;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: none;
  gap: 0;
  margin: 0 -0.25rem;
}
.hub-carousel::-webkit-scrollbar {
  display: none;
}
.hub-slide {
  flex: 0 0 100%;
  min-width: 100%;
  scroll-snap-align: start;
  scroll-snap-stop: always;
  padding: 0 0.25rem;
  box-sizing: border-box;
}
.hub-arrow {
  width: 1.75rem;
  height: 1.75rem;
  border-radius: 9999px;
  background: rgba(255, 255, 255, 0.14);
  color: #fff;
  font-size: 18px;
  line-height: 1;
  transition: background 0.12s ease, transform 0.12s ease;
}
.hub-arrow:not(:disabled):hover {
  background: rgba(255, 255, 255, 0.26);
}
.hub-arrow:not(:disabled):active {
  transform: scale(0.92);
}
.hub-arrow:disabled {
  opacity: 0.3;
}
</style>
