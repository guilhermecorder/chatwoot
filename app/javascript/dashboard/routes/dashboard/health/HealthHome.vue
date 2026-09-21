<script setup>
// MEU PAINEL DA SAÚDE — rodada 20 (18/09): "as coisas mais importantes
// no início, e nos ater a elas". Ordem: HERO (treino da vez) → RESULTADO
// (peso × alvo, cintura, força) → CENTÍMETROS (balanço + gráfico de todos
// os cm ganhos/perdidos ao longo do tempo + gráficos por ÁREA do corpo)
// → CARGAS por exercício → FORÇA → METAS do próximo treino (dobrável).
// Saíram: elogio, fileira de KPIs de vaidade, caixinhas de consistência
// (moram em Análises) e o card de dieta (1 toque na barra de abas).
// Mantém: ciclo de 24 semanas, carrosséis A|B|C, paleta royal + laranja.
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';
import { useHealthAccess } from './useHealthAccess';
import WheelInput from './WheelInput.vue';
import RadarChart from './HubRadar.vue';
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
import { applyChartTheme, watchChartTheme } from './chartTheme';
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
  learnEquiv,
  factorOf,
  resolvePrograms,
  programWeeks,
  goalProgress,
} from './warrior';
// rodada 23: paleta SÓ azul + laranja em tons (pedido dele) — sem verde/
// vermelho no painel: "na direção certa" = azul, "contra" = laranja vivo
import {
  ROYAL, ROYAL_CLARO,
  LARANJA, LARANJA_VIVO, LARANJA_CLARO,
  CINZA, GRAD_NOITE, GRAD_LARANJA,
} from './palette';
const VERDICT_COLORS = { progress: ROYAL, tie: CINZA, regress: LARANJA_VIVO };

ChartJS.register(Tooltip, Legend, CategoryScale, LinearScale, PointElement, LineElement, Filler);
applyChartTheme();
watchChartTheme();

const router = useRouter();
const accountScopedRoute = name => ({
  name,
  params: { accountId: router.currentRoute.value.params.accountId },
});
const go = name => router.push(accountScopedRoute(name));
// "▶ Treino X de hoje" → a tela de treino já abre com a sessão pronta
const goStart = key =>
  router.push({ ...accountScopedRoute('hub_health'), query: { start: key } });
const scrollToId = id => {
  const el = document.getElementById(id);
  if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
};

const isLoading = ref(true);
const config = ref({});
const profile = ref({});
const programRecords = ref([]); // programas pessoais (rodada 25)
const cardios = ref([]); // rodada 26
const workouts = ref([]);
const boxings = ref([]);
const diets = ref([]);
const bodies = ref([]);

const todayISO = new Date().toISOString().slice(0, 10);
const num = v => Number(String(v ?? '').replace(',', '.')) || 0;
const fmt1 = v => String(Math.round(v * 10) / 10).replace('.', ',');
const fmtKg = v => `${fmt1(v)} kg`;
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
    programRecords.value = data.programs || [];
    cardios.value = data.cardios || [];
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

const { allowed: moduleAllowed } = useHealthAccess();
const boxingOn = computed(() => config.value.features?.boxing === true && moduleAllowed('boxe'));

// ── programa, SEMANA e CICLO ─────────────────────────────────────────
// Warrior (24 semanas, config) OU o programa pessoal ativo (rodada 25:
// N semanas do registro kind=program) — mesma forma, mesmo painel
const programs = computed(() => resolvePrograms(config.value, profile.value, programRecords.value));
const program = computed(() => activeProgram(programs.value));
const cycleLen = computed(() => programWeeks(program.value) || 24);
// objetivo do programa pessoal (parâmetro de sucesso escolhido por ele)
const goalNow = computed(() =>
  program.value?.custom
    ? goalProgress({ program: program.value, workouts: workouts.value, bodies: bodies.value, todayISO })
    : null
);
const programWeek = computed(() => weekOf(program.value, todayISO));
const cycleNumber = computed(() =>
  programWeek.value ? Math.floor((programWeek.value - 1) / cycleLen.value) + 1 : 1
);
const weekInCycle = computed(() =>
  programWeek.value ? ((programWeek.value - 1) % cycleLen.value) + 1 : 1
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

// ── ALVOS (registro 'profile' da pessoa) ────────────────────────────
const weeklyGoal = computed(() => Number(profile.value.weekly_sessions) || 3);
const weightGoal = computed(
  () => Number(profile.value.targets?.weight) || Number(profile.value.weight_goal) || 0
);

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
const weekBoxings = computed(() => boxings.value.filter(b => inThisWeek(b.record_date)));
// rodada 26: minutos de cardio na semana (caminhada, corrida, bike…)
const weekCardioMin = computed(() =>
  cardios.value.filter(c => inThisWeek(c.record_date)).reduce((a, c) => a + (Number(c.data?.minutes) || 0), 0)
);
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
        // PESO COMUM (rodada 21): cada execução ganha `common` = carga máx ×
        // fator da variação (halteres ×2, máquina calibrada pelo histórico)
        // — o Δ, a curva e o número grande não pulam quando troca o
        // equipamento
        const rawExecs = executionsOf(p.name);
        // escala do peso comum = a da variação PRINCIPAL do exercício (um
        // supino com halteres continua mostrando o número do halter; a
        // máquina/barra é que entram convertidas pra essa escala)
        const equiv = learnEquiv(p, eq.base, rawExecs);
        const baseF = factorOf(equiv, eq.base, eq.base, p) || 1;
        const relF = tag => Math.round((factorOf(equiv, tag, eq.base, p) / baseF) * 1000) / 1000;
        const execs = rawExecs.map(x => ({
          ...x,
          factor: relF(x.tag),
          common: Math.round(x.top * relF(x.tag) * 10) / 10,
        }));
        const tagsSeen = [...new Set(execs.map(x => lowerName(x.tag) || lowerName(eq.base)))];
        const mixed = tagsSeen.length > 1;
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
          .map(x => x.common);
        // última carga de cada variação (pra linha "halteres 30 ≈ máquina 70")
        const perTag = tagsSeen.map(t => {
          const x = execs.find(e => (lowerName(e.tag) || lowerName(eq.base)) === t);
          return { tag: t, top: x.top, factor: x.factor };
        });
        return {
          name: eq.options.length > 1 ? nameWithoutEquipment(p.name) : p.name,
          tag: last?.tag || '',
          method: p.method,
          last,
          mixed,
          perTag,
          count: execs.length,
          deltaCycle: last && first && last !== first ? Math.round((last.common - first.common) * 10) / 10 : null,
          pctCycle:
            last && first && last !== first && first.common
              ? Math.round(((last.common - first.common) / first.common) * 1000) / 10
              : null,
          firstE1: first?.e1 ?? null,
          deltaPrev: last && prev ? Math.round((last.common - prev.common) * 10) / 10 : null,
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

// cards de carga (rodada 22): frente leve — nome, carga, Δ ciclo, curva;
// tocar abre séries/data, veredito, e-1RM e peso comum
const openCards = ref(new Set());
const toggleCard = name => {
  const next = new Set(openCards.value);
  if (next.has(name)) next.delete(name);
  else next.add(name);
  openCards.value = next;
};

// ── CORPO: circunferência abdominal em destaque + peso ──────────────
const seriesOf = key =>
  bodies.value
    .filter(b => Number(b.data?.[key]) > 0)
    .map(b => ({ date: b.record_date, v: Number(b.data[key]) }))
    .sort((a, b) => (a.date > b.date ? 1 : -1));
const weighins = computed(() => seriesOf('weight'));
const currentWeight = computed(() => weighins.value.at(-1)?.v || 0);
const firstWeight = computed(() => weighins.value[0]?.v || 0);

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

const MEASURE_VIEW = [
  { key: 'waist_narrow', label: 'C. estreita', down: true },
  { key: 'hips', label: 'Quadril', down: true },
  { key: 'chest', label: 'Peito', down: false },
  { key: 'arm_r', label: 'Braço D', down: false },
  { key: 'arm_l', label: 'Braço E', down: false },
  { key: 'thigh_r', label: 'Coxa D', down: false },
  { key: 'thigh_l', label: 'Coxa E', down: false },
  { key: 'forearm_r', label: 'Antebraço D', down: false },
  { key: 'forearm_l', label: 'Antebraço E', down: false },
  { key: 'calf_r', label: 'Panturrilha D', down: false },
  { key: 'calf_l', label: 'Panturrilha E', down: false },
  { key: 'neck', label: 'Pescoço', down: true },
  { key: 'shoulders', label: 'Ombros', down: false },
];

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
  const absWeek = (cycleNumber.value - 1) * cycleLen.value + (cy.week_start || 1);
  return shiftISO(prog.start_date, (absWeek - 1) * 7);
});
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
    exercises: exercises.length,
  };
};
const strength = computed(() => strengthFor(null));

// ── FORÇA GERAL E POR TREINO (rodada 23): força total semana a semana
// (carry-forward: cada exercício vale o último e-1RM conhecido até a
// semana) × força relativa ao peso — chavinha Geral | A | B | C
const strengthChartFor = exercises => {
  const cy = programCycle.value;
  const prog = program.value;
  if (!cy || !prog?.start_date) return null;
  const wStart = cy.week_start || 1;
  const wEnd = Math.min(weekInCycle.value, cy.week_end || cycleLen.value);
  const labels = [];
  const total = [];
  const rel = [];
  for (let w = wStart; w <= wEnd; w += 1) {
    const absWeek = (cycleNumber.value - 1) * cycleLen.value + w;
    let sum = 0;
    let any = false;
    exercises.forEach(e => {
      const known = (e.execs || []).find(x => x.week && x.week <= absWeek);
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
        label: 'Força relativa (× peso)',
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
const forcaKey = ref('geral');
const forcaOptions = computed(() => [
  { key: 'geral', label: 'Geral' },
  ...loadProgress.value.map(g => ({ key: g.key, label: `Treino ${g.key}` })),
]);
const forcaView = computed(() => {
  const key = forcaKey.value === 'geral' ? null : forcaKey.value;
  const groups = key ? loadProgress.value.filter(g => g.key === key) : loadProgress.value;
  return { m: strengthFor(key), chart: strengthChartFor(groups.flatMap(g => g.exercises)) };
});
// ── BALANÇO DE CENTÍMETROS (rodada 17): quanto o corpo mudou, no total ──
// "perdidos onde importa" = cintura/cintura estreita/quadril/pescoço
// (queda é vitória) · "ganhos onde importa" = peito/braços/antebraços/coxas/panturrilhas/ombros
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

// rodada 31b: medidas em GRUPOS por região (pedido dele: "organizar em
// grupos: cintura umbigo | cintura estreita | quadril / peito | ombros | pescoço")
const CM_GROUPS = [
  { key: 'tronco', label: 'Tronco', tone: 't-orange', keys: { waist_navel: 'Cintura umbigo', waist_narrow: 'Cintura estreita', hips: 'Quadril' } },
  { key: 'superior', label: 'Peito · ombros · pescoço', tone: 't-royal', keys: { chest: 'Peito', shoulders: 'Ombros', neck: 'Pescoço' } },
  { key: 'bracos', label: 'Braços', tone: 't-sky', keys: { arm_r: 'Braço D', arm_l: 'Braço E', forearm_r: 'Antebraço D', forearm_l: 'Antebraço E' } },
  { key: 'pernas', label: 'Pernas', tone: 't-amber', keys: { thigh_r: 'Coxa D', thigh_l: 'Coxa E', calf_r: 'Panturrilha D', calf_l: 'Panturrilha E' } },
];
const cmGroups = computed(() =>
  CM_GROUPS.map(g => ({
    ...g,
    rows: Object.entries(g.keys)
      .map(([k, short]) => {
        const r = cmBalance.value.rows.find(x => x.key === k);
        return r ? { ...r, short } : null;
      })
      .filter(Boolean),
  })).filter(g => g.rows.length)
);

// ── ATUAL → ALVO (rodada 23): "meus dados atuais e desejados" no topo.
// Alvos por medida moram no registro 'profile' (targets: { key: valor });
// braço, antebraço, coxa e panturrilha = média D/E. Barra = quanto do caminho (1ª medição → alvo)
// já foi percorrido.
const TARGET_DEFS = [
  { key: 'weight', label: 'Peso', unit: 'kg', down: true, max: 200 },
  { key: 'waist_navel', label: 'Cintura (umbigo)', unit: 'cm', down: true, max: 220 },
  { key: 'waist_narrow', label: 'Cintura estreita', unit: 'cm', down: true, max: 220 },
  { key: 'hips', label: 'Quadril', unit: 'cm', down: true, max: 220 },
  { key: 'chest', label: 'Peito', unit: 'cm', down: false, max: 220 },
  { key: 'arm', label: 'Braço (média)', unit: 'cm', down: false, max: 220, avg: ['arm_r', 'arm_l'] },
  { key: 'thigh', label: 'Coxa (média)', unit: 'cm', down: false, max: 220, avg: ['thigh_r', 'thigh_l'] },
  { key: 'forearm', label: 'Antebraço (média)', unit: 'cm', down: false, max: 220, avg: ['forearm_r', 'forearm_l'] },
  { key: 'calf', label: 'Panturrilha (média)', unit: 'cm', down: false, max: 220, avg: ['calf_r', 'calf_l'] },
  { key: 'shoulders', label: 'Ombros', unit: 'cm', down: false, max: 220 },
  { key: 'neck', label: 'Pescoço', unit: 'cm', down: true, max: 220 },
];
const valueAt = (def, which) => {
  const vals = (def.avg || [def.key])
    .map(k => {
      const sr = seriesOf(k);
      if (!sr.length) return null;
      return which === 'last' ? sr.at(-1).v : sr[0].v;
    })
    .filter(v => v !== null);
  if (!vals.length) return null;
  return round1(vals.reduce((a, b) => a + b, 0) / vals.length);
};
const targets = computed(() => ({
  ...(profile.value.targets || {}),
  weight: weightGoal.value,
}));
const goalRows = computed(() =>
  TARGET_DEFS.map(d => {
    const now = valueAt(d, 'last');
    const first = valueAt(d, 'first');
    const target = Number(targets.value[d.key]) || 0;
    if (now === null && !target) return null;
    const remaining = target && now !== null ? round1(d.down ? now - target : target - now) : null;
    let pct = null;
    if (target && now !== null && first !== null) {
      const total = d.down ? first - target : target - first;
      const done = d.down ? first - now : now - first;
      if (total > 0) pct = Math.max(0, Math.min(100, Math.round((done / total) * 100)));
      else if (remaining <= 0) pct = 100;
    }
    return { ...d, now, first, target, remaining, pct, hit: remaining !== null && remaining <= 0 };
  }).filter(Boolean)
);
// rodada 31b: "muitos indicadores" → só os 3 mais importantes (quem tem alvo
// primeiro, na ordem peso > cintura > …) + força total, cada um num tom
const GOAL_TONES = ['t-royal', 't-orange', 't-sky'];
const keyGoals = computed(() => {
  const withTarget = goalRows.value.filter(r => r.target && r.now !== null);
  const rest = goalRows.value.filter(r => !withTarget.includes(r) && r.now !== null);
  return [...withTarget, ...rest].slice(0, 3).map((r, i) => ({ ...r, tone: GOAL_TONES[i] }));
});
const editingTargets = ref(false);
const targetsDraft = ref({});
const openTargets = () => {
  targetsDraft.value = Object.fromEntries(
    TARGET_DEFS.map(d => [d.key, targets.value[d.key] ? String(targets.value[d.key]).replace('.', ',') : ''])
  );
  editingTargets.value = true;
};
const saveTargets = async () => {
  const t = {};
  TARGET_DEFS.forEach(d => {
    const v = num(targetsDraft.value[d.key]);
    if (v > 0) t[d.key] = v;
  });
  try {
    const { data: rec } = await CrmAPI.createHealthRecord({
      kind: 'profile',
      data: { ...profile.value, targets: t, weight_goal: t.weight || 0 },
    });
    profile.value = rec.data || {};
    editingTargets.value = false;
    useAlert('🎯 Alvos salvos.');
  } catch {
    useAlert('Não consegui salvar os alvos.');
  }
};

// ═══ RODADA 30: TEIAS DO PROGRESSO no painel (pedido dele 19/09: "deixar
// mais interessante a visualização de progresso; pode ter mais de uma") ═══
const shortName = n => {
  // sem reticências: o HubRadar quebra em 2 linhas e calcula a folga
  return String(n || '').replace(/\s+(com|na|no|em)\s+.*$/i, '').trim();
};
const radarAxes = list => list.map(x => ({ key: x.key, label: x.label }));
// rodada 31: no celular as 3 teias deslizam (1 card de tela inteira por vez);
// as bolinhas acompanham o scroll
const progressRail = ref(null);
const progressSlide = ref(0);
const onProgressScroll = () => {
  const el = progressRail.value;
  const first = el?.firstElementChild;
  if (!el || !first) return;
  const pitch = first.offsetWidth + 12;
  progressSlide.value = Math.max(0, Math.min(2, Math.round(el.scrollLeft / pitch)));
};
// 1) FORÇA por exercício: início do ciclo × agora (e-1RM), até 8 exercícios
const strengthRadar = computed(() => {
  const ex = loadProgress.value
    .flatMap(g => g.exercises)
    .filter(e => e.last && e.e1)
    .sort((a, b) => b.e1 - a.e1)
    .slice(0, 8);
  if (ex.length < 3) return null;
  const max = Math.max(1, ...ex.map(e => Math.max(e.e1, e.firstE1 || 0)));
  const axes = radarAxes(ex.map(e => ({ key: e.name, label: shortName(e.name) })));
  const pc = v => Math.round((v / max) * 100);
  return {
    axes,
    datasets: [
      { label: 'início do ciclo', color: '#94A3B8', values: Object.fromEntries(ex.map(e => [e.name, pc(e.firstE1 ?? e.e1)])) },
      { label: 'agora', color: ROYAL, values: Object.fromEntries(ex.map(e => [e.name, pc(e.e1)])) },
    ],
    up: ex.filter(e => e.firstE1 !== null && e.e1 > e.firstE1).length,
    n: ex.length,
  };
});
// 2) MEDIDAS × OBJETIVO: % do caminho até o alvo em cada medida (alvo = borda)
const targetRadar = computed(() => {
  const rows = goalRows.value.filter(r => r.pct !== null);
  if (rows.length < 3) return null;
  const axes = radarAxes(rows.map(r => ({ key: r.key, label: r.label.replace(/ \(.*\)/, '') })));
  return {
    axes,
    datasets: [
      { label: 'onde quero (alvo)', color: LARANJA, values: Object.fromEntries(rows.map(r => [r.key, 100])) },
      { label: 'onde estou', color: ROYAL, values: Object.fromEntries(rows.map(r => [r.key, r.pct])) },
    ],
    avg: Math.round(rows.reduce((a, r) => a + r.pct, 0) / rows.length),
    hit: rows.filter(r => r.hit).length,
  };
});
// 3) SEMANA: constância em cada frente (0–100)
const weekRadar = computed(() => {
  const bodyThisWeek = bodies.value.some(b => inThisWeek(b.record_date));
  const vs = weekScore.value;
  const comparable = vs.progress + vs.tie + vs.regress;
  const items = [
    { key: 'treinos', label: 'Treinos', v: Math.min(100, Math.round((weekWorkouts.value.length / Math.max(1, weeklyGoal.value)) * 100)) },
    { key: 'cardio', label: 'Cardio', v: Math.min(100, Math.round((weekCardioMin.value / 150) * 100)) },
    ...(boxingOn.value ? [{ key: 'boxe', label: 'Boxe', v: Math.min(100, weekBoxings.value.length * 50) }] : []),
    { key: 'medidas', label: 'Medição', v: bodyThisWeek ? 100 : 0 },
    { key: 'cargas', label: 'Cargas ▲', v: comparable ? Math.round((vs.progress / comparable) * 100) : 0 },
  ];
  return {
    axes: radarAxes(items),
    datasets: [{ label: 'esta semana', color: LARANJA_VIVO, values: Object.fromEntries(items.map(i => [i.key, i.v])) }],
    score: Math.round(items.reduce((a, i) => a + i.v, 0) / items.length),
  };
});

// eixo duplo (esq. laranja/direita azul) usado nos gráficos de relação
const dualChartOpts = {
  responsive: true,
  maintainAspectRatio: false,
  interaction: { mode: 'index', intersect: false },
  plugins: { legend: { display: true, labels: { boxWidth: 10, font: { size: 10 } } } },
  scales: {
    x: { ticks: { font: { size: 9 } }, grid: { display: false } },
    y: { position: 'left', ticks: { font: { size: 9 } }, grid: { color: 'rgba(127,127,127,0.12)' } },
    y1: { position: 'right', ticks: { font: { size: 9 } }, grid: { drawOnChartArea: false } },
  },
};

// ── CENTÍMETROS TOTAIS × PESO (rodada 23): a soma de TODAS as
// circunferências (cada medida vale o último valor conhecido) contra o
// peso, medição a medição — o gráfico que ele pediu "logo no início"
const CM_ALL = [{ key: 'waist_navel', label: 'Cintura (umbigo)', down: true }, ...MEASURE_VIEW];
const cmTotalChart = computed(() => {
  const keys = CM_ALL.map(m => m.key).filter(k => seriesOf(k).length);
  if (keys.length < 3) return null;
  const series = Object.fromEntries(keys.map(k => [k, seriesOf(k)]));
  const dates = [...new Set(keys.flatMap(k => series[k].map(pt => pt.date)))].sort();
  if (dates.length < 2) return null;
  const totals = dates.map(d =>
    round1(
      keys.reduce((a, k) => {
        const sr = series[k];
        const at = sr.filter(pt => pt.date <= d).at(-1) || sr[0];
        return a + at.v;
      }, 0)
    )
  );
  const pesos = dates.map(d => weighins.value.filter(pt => pt.date <= d).at(-1)?.v ?? null);
  return {
    first: totals[0],
    last: totals.at(-1),
    pesoFirst: pesos.find(v => v !== null) ?? null,
    pesoLast: [...pesos].reverse().find(v => v !== null) ?? null,
    chart: {
      labels: dates.map(fmtDay),
      datasets: [
        {
          label: 'Centímetros totais (Σ medidas)',
          data: totals,
          borderColor: LARANJA,
          backgroundColor: 'rgba(255,138,0,0.14)',
          fill: true,
          tension: 0.3,
          pointRadius: 3,
          borderWidth: 2,
          yAxisID: 'y',
        },
        {
          label: 'Peso (kg)',
          data: pesos,
          borderColor: ROYAL,
          backgroundColor: 'transparent',
          fill: false,
          tension: 0.3,
          pointRadius: 3,
          borderWidth: 2,
          spanGaps: true,
          yAxisID: 'y1',
        },
      ],
    },
  };
});

// ── GRÁFICO DE TODOS OS CENTÍMETROS (rodada 20): a cada medição, Σ do Δ
// desde a 1ª medição — onde quer perder (laranja, cair é vitória), onde
// quer ganhar (royal, subir é vitória) e o saldo. Cada medida vale o
// último valor conhecido até a data (carry-forward); entram só as que
// têm ≥ 2 registros, igual ao balanço.
const CM_KEYS = [{ key: 'waist_navel', label: 'Cintura (umbigo)', down: true }, ...MEASURE_VIEW];
const cmTimeline = computed(() => {
  const series = {};
  CM_KEYS.forEach(m => {
    const s = seriesOf(m.key);
    if (s.length >= 2) series[m.key] = s;
  });
  const keys = Object.keys(series);
  if (!keys.length) return null;
  const dates = [...new Set(keys.flatMap(k => series[k].map(p => p.date)))].sort();
  if (dates.length < 2) return null;
  // rodada 23 (pedido dele): "centímetros onde eu quero e onde eu não
  // quero" — Δ desde a 1ª medição, somado por grupo: laranja = onde quer
  // PERDER (cair é vitória), azul = onde quer GANHAR (subir é vitória)
  const rows = dates.map(d => {
    let lose = 0;
    let gain = 0;
    CM_KEYS.forEach(m => {
      const sr = series[m.key];
      if (!sr) return;
      const at = sr.filter(pt => pt.date <= d).at(-1);
      if (!at) return;
      const dlt = at.v - sr[0].v;
      if (m.down) lose += dlt;
      else gain += dlt;
    });
    return { date: d, lose: round1(lose), gain: round1(gain) };
  });
  return {
    rows,
    chart: {
      labels: rows.map(r => fmtDay(r.date)),
      datasets: [
        {
          label: 'Onde quero perder (Δ cm)',
          data: rows.map(r => r.lose),
          borderColor: LARANJA,
          backgroundColor: 'rgba(255,138,0,0.14)',
          fill: true,
          tension: 0.3,
          pointRadius: 3,
          borderWidth: 2,
        },
        {
          label: 'Regiões de desenvolvimento muscular (Δ cm)',
          data: rows.map(r => r.gain),
          borderColor: ROYAL,
          backgroundColor: 'rgba(65,105,225,0.12)',
          fill: true,
          tension: 0.3,
          pointRadius: 3,
          borderWidth: 2,
        },
      ],
    },
  };
});
const cmChartOpts = {
  responsive: true,
  maintainAspectRatio: false,
  interaction: { mode: 'index', intersect: false },
  plugins: { legend: { display: true, labels: { boxWidth: 10, font: { size: 10 } } } },
  scales: {
    x: { ticks: { font: { size: 9 } }, grid: { display: false } },
    y: { ticks: { font: { size: 9 }, callback: v => `${v > 0 ? '+' : ''}${v}` }, grid: { color: 'rgba(127,127,127,0.12)' } },
  },
};

// ── ÁREAS DO CORPO (rodada 20): "gráficos separados de áreas do corpo" —
// uma chavinha escolhe a área e o gráfico mostra a(s) medida(s) dela
// (braços e coxas = D e E; abdômen = umbigo e estreita) com Δ desde o
// início e vs última, na cor da direção certa.
const BODY_AREAS = [
  { key: 'abdomen', label: 'Abdômen', icon: '📐', down: true, unit: 'cm', keys: [{ key: 'waist_navel', label: 'Umbigo' }, { key: 'waist_narrow', label: 'Estreita' }] },
  { key: 'quadril', label: 'Quadril', icon: '🍑', down: true, unit: 'cm', keys: [{ key: 'hips', label: 'Quadril' }] },
  { key: 'peito', label: 'Peito', icon: '🫁', down: false, unit: 'cm', keys: [{ key: 'chest', label: 'Peito' }] },
  { key: 'bracos', label: 'Braços', icon: '💪', down: false, unit: 'cm', keys: [{ key: 'arm_r', label: 'Direito' }, { key: 'arm_l', label: 'Esquerdo' }] },
  { key: 'coxas', label: 'Coxas', icon: '🦵', down: false, unit: 'cm', keys: [{ key: 'thigh_r', label: 'Direita' }, { key: 'thigh_l', label: 'Esquerda' }] },
  { key: 'antebracos', label: 'Antebraços', icon: '🦾', down: false, unit: 'cm', keys: [{ key: 'forearm_r', label: 'Direito' }, { key: 'forearm_l', label: 'Esquerdo' }] },
  { key: 'panturrilhas', label: 'Panturrilhas', icon: '🦿', down: false, unit: 'cm', keys: [{ key: 'calf_r', label: 'Direita' }, { key: 'calf_l', label: 'Esquerda' }] },
  { key: 'ombros', label: 'Ombros', icon: '🏔', down: false, unit: 'cm', keys: [{ key: 'shoulders', label: 'Ombros' }] },
  { key: 'pescoco', label: 'Pescoço', icon: '🧣', down: true, unit: 'cm', keys: [{ key: 'neck', label: 'Pescoço' }] },
  { key: 'peso', label: 'Peso', icon: '⚖️', down: true, unit: 'kg', keys: [{ key: 'weight', label: 'Peso' }] },
];
const areaKey = ref('abdomen');
const areaView = computed(() => {
  const a = BODY_AREAS.find(x => x.key === areaKey.value) || BODY_AREAS[0];
  const lines = a.keys
    .map(k => ({ ...k, s: seriesOf(k.key) }))
    .filter(l => l.s.length);
  if (!lines.length) return { ...a, lines: [], chart: null };
  const dates = [...new Set(lines.flatMap(l => l.s.map(p => p.date)))].sort().slice(-30);
  const main = a.down ? LARANJA : ROYAL;
  const alt = a.down ? LARANJA_CLARO : ROYAL_CLARO;
  const stats = lines.map(l => {
    const first = l.s[0].v;
    const last = l.s.at(-1).v;
    const prev = l.s.at(-2)?.v ?? null;
    const dStart = round1(last - first);
    const dPrev = prev === null ? null : round1(last - prev);
    return {
      key: l.key,
      label: l.label,
      now: last,
      dStart,
      dPrev,
      good: a.down ? dStart <= 0 : dStart >= 0,
      firstDate: l.s[0].date,
      lastDate: l.s.at(-1).date,
      n: l.s.length,
    };
  });
  const datasets = lines.map((l, i) => ({
    label: `${l.label} (${a.unit})`,
    data: dates.map(d => l.s.find(p => p.date === d)?.v ?? null),
    borderColor: i === 0 ? main : alt,
    backgroundColor: i === 0 ? (a.down ? 'rgba(255,138,0,0.12)' : 'rgba(65,105,225,0.12)') : 'transparent',
    fill: i === 0,
    tension: 0.35,
    pointRadius: 3,
    borderWidth: 2,
    spanGaps: true,
  }));
  if (a.key === 'peso' && weightGoal.value > 0) {
    datasets.push({
      label: 'Peso-alvo',
      data: dates.map(() => weightGoal.value),
      borderColor: ROYAL_CLARO,
      borderDash: [6, 5],
      borderWidth: 1.5,
      pointRadius: 0,
      fill: false,
    });
  }
  return { ...a, lines: stats, chart: { labels: dates.map(fmtDay), datasets } };
});
const areaChartOpts = {
  responsive: true,
  maintainAspectRatio: false,
  interaction: { mode: 'index', intersect: false },
  plugins: { legend: { display: true, labels: { boxWidth: 10, font: { size: 10 } } } },
  scales: {
    x: { ticks: { font: { size: 9 } }, grid: { display: false } },
    y: { ticks: { font: { size: 9 } }, grid: { color: 'rgba(127,127,127,0.12)' } },
  },
};

// ── RESULTADO (rodada 20): os 3 números que definem "deu certo" ─────

// ── METAS do próximo treino: dobrável (rodada 20), lembra no aparelho ──
const METAS_KEY = 'hub_painel_metas';
const metasOpen = ref(false);
try {
  metasOpen.value = localStorage.getItem(METAS_KEY) === '1';
} catch {
  /* fica fechado */
}
const toggleMetas = () => {
  metasOpen.value = !metasOpen.value;
  try {
    localStorage.setItem(METAS_KEY, metasOpen.value ? '1' : '0');
  } catch {
    /* ignora */
  }
};

// (dieta saiu do painel na rodada 20 — 1 toque na barra de abas)
</script>

<template>
  <div class="hub-page flex-1 overflow-auto p-4 pb-20 sm:p-6 md:pb-6">
    <div class="max-w-5xl mx-auto">
      <div v-if="isLoading" class="flex justify-center py-16"><Spinner /></div>
      <template v-else>
        <!-- 1. HERO: treino da vez + semana -->
        <div class="hub-block hub-block-solid p-5 mb-8 text-white">
          <div class="flex items-center justify-between flex-wrap gap-3">
            <div class="min-w-0">
              <div class="flex items-center gap-2 flex-wrap mb-1">
                <h1 class="text-lg font-bold text-white" style="color: #fff">Meu Painel</h1>
                <span class="px-2 py-0.5 rounded-full text-[10px] font-bold" :style="{ background: LARANJA, color: '#1a0e00' }">
                  Ciclo {{ cycleNumber }}
                </span>
                <span
                  v-if="weekComplete"
                  class="px-2 py-0.5 rounded-full text-[10px] font-bold"
                  :style="{ background: 'rgba(255,255,255,0.14)', color: LARANJA_CLARO }"
                  :title="praise"
                >
                  <span class="i-lucide-trophy hub-ico" /> semana completa
                </span>
              </div>
              <!-- rodada 26: "treino atual · semana atual" pra se situar -->
              <p v-if="program" class="text-[12px] font-bold mb-1 flex items-center gap-1.5 flex-wrap">
                <span class="px-2 py-0.5 rounded-lg inline-flex items-center gap-1" style="background: rgba(255, 255, 255, 0.16)"><span class="i-lucide-map-pin hub-ico" style="width: 13px; height: 13px" />{{ program.name }}</span>
                <span class="px-2 py-0.5 rounded-lg" :style="{ background: LARANJA, color: '#1a0e00' }">Semana {{ weekInCycle }} de {{ cycleLen }}</span>
                <span v-if="upcomingSession" class="opacity-90 font-semibold">próximo: Treino {{ upcomingSession.key }}<template v-if="upcomingSession.weekday"> · {{ upcomingSession.weekday }}</template></span>
              </p>
              <p class="text-xs opacity-85">
                <template v-if="program && programWeek">
                  Semana <b>{{ weekInCycle }} de {{ cycleLen }}</b> · {{ programCycle?.name }}
                  <template v-if="programCycle?.focus"> — {{ programCycle.focus }}</template>
                </template>
                <template v-else>Suas cargas, seu progresso, sua transformação.</template>
              </p>
              <p v-if="goalNow" class="text-[11px] mt-1 opacity-95">
                <span :class="goalNow.ico" class="hub-ico" style="width: 13px; height: 13px" /> Objetivo {{ goalNow.label }}: <b :style="{ color: goalNow.none ? '#fff' : goalNow.ok ? ROYAL_CLARO : LARANJA_CLARO }">{{ goalNow.value }}</b>
                <span class="opacity-80"> · {{ goalNow.detail }}</span>
              </p>
              <p class="text-[11px] mt-1 opacity-90">
                Semana: <b>{{ weekSessions }} de {{ weeklyGoal }}</b> sessões ·
                <span :style="{ color: ROYAL_CLARO }">▲{{ weekScore.progress }}</span>
                <span class="opacity-70 mx-1">▬{{ weekScore.tie }}</span>
                <span :style="{ color: LARANJA_CLARO }">▼{{ weekScore.regress }}</span>
                <span v-if="weekCardioMin" class="opacity-90"> · {{ weekCardioMin }} min de cardio</span>
              </p>
            </div>
            <button
              v-if="upcomingSession"
              class="h-12 px-5 rounded-xl text-sm font-bold text-white shadow-lg w-full sm:w-auto"
              :style="{ background: GRAD_LARANJA }"
              @click="goStart(upcomingSession.key)"
            >
              ▶ Treino {{ upcomingSession.key }}
              {{ todaysSession && !workoutDoneToday ? 'de hoje' : workoutDoneToday ? '· próximo' : '' }}
              <span class="block text-[10px] font-normal opacity-85">abre com as metas prontas</span>
            </button>
          </div>
        </div>

        <!-- 2. ATUAL → ALVO: onde estou e onde quero chegar -->
        <div class="hub-block p-5 mb-8">
          <div class="flex items-center justify-between gap-2 mb-3">
            <h2 class="hub-h"><span class="hub-h-ico i-lucide-target" />Onde estou → onde quero chegar</h2>
            <button class="hub-chip" @click="editingTargets ? (editingTargets = false) : openTargets()">
              {{ editingTargets ? '✕ fechar' : '✎ alvos' }}
            </button>
          </div>
          <div v-if="editingTargets" class="rounded-xl border border-dashed border-n-weak p-3 mb-3">
            <p class="text-[11px] text-n-slate-10 mb-2">Role até o valor que você quer chegar em cada medida (vazio = sem alvo).</p>
            <div class="grid gap-3 mb-3" style="grid-template-columns: repeat(auto-fill, minmax(7.2rem, 1fr))">
              <div v-for="d in TARGET_DEFS" :key="d.key" class="flex flex-col gap-1">
                <span class="text-[10px] font-semibold text-n-slate-11 text-center leading-tight" style="min-height: 2.2em; display: flex; align-items: flex-end; justify-content: center">
                  {{ d.label }}&nbsp;<span class="opacity-60">{{ d.unit }}</span>
                </span>
                <WheelInput v-model="targetsDraft[d.key]" :step="0.5" :max="d.max" decimal :placeholder="d.unit" style="width: 100%" />
              </div>
            </div>
            <button class="h-10 px-5 rounded-xl text-xs font-bold text-white w-full sm:w-auto" :style="{ background: GRAD_LARANJA }" @click="saveTargets">
              ✓ Salvar alvos
            </button>
          </div>
          <!-- rodada 31b: só os 3 alvos mais importantes + força total, cada um num tom -->
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <div v-for="r in keyGoals" :key="r.key" class="hub-goal hub-crystal" :class="r.tone">
              <p class="hub-goal-l">{{ r.label.replace(/ \(.*\)/, '') }}</p>
              <p class="hub-goal-v">
                {{ r.now === null ? '—' : fmt1(r.now) }}
                <span v-if="r.target" class="hub-goal-t">→ {{ fmt1(r.target) }}</span>
                <span class="hub-goal-u">{{ r.unit }}</span>
              </p>
              <div v-if="r.pct !== null" class="hub-goal-bar"><i :style="{ width: `${Math.max(r.pct, 3)}%` }" /></div>
              <p class="hub-goal-s">
                <template v-if="r.hit">alvo batido</template>
                <template v-else-if="r.remaining !== null">
                  faltam <b>{{ fmt1(r.remaining) }} {{ r.unit }}</b><template v-if="r.pct !== null"> · {{ r.pct }}%</template><template v-if="r.key === 'weight' && goalEta"> · ≈ {{ goalEta.label }}</template>
                </template>
                <template v-else-if="r.first !== null && r.now !== null && r.first !== r.now">{{ signed(r.now - r.first) }} {{ r.unit }} desde o início</template>
                <template v-else>defina o alvo em ✎</template>
              </p>
            </div>
            <button class="hub-goal hub-crystal t-amber text-left" title="Ver a força por treino" @click="scrollToId('hub-forca')">
              <p class="hub-goal-l">Força total</p>
              <p class="hub-goal-v">
                {{ strength.n ? strength.now : '—' }}
                <span class="hub-goal-u">kg</span>
              </p>
              <p class="hub-goal-s">
                <template v-if="strength.rel !== null"><b>{{ String(strength.rel).replace('.', ',') }}×</b> peso</template>
                <template v-if="strength.n && strength.delta"><template v-if="strength.rel !== null"> · </template>{{ signed(strength.delta) }} kg no ciclo ({{ signed(strength.pct) }}%)</template>
                <template v-else-if="strength.rel === null">registre treinos</template>
              </p>
            </button>
          </div>
        </div>

        <!-- 2b. PROGRESSO — 3 teias (rodada 30; rodada 31: título PROGRESSO,
             cards de vidro transparente, no celular cada teia é um card de
             tela inteira que desliza pro lado com bolinhas) -->
        <div class="hub-block hub-progress p-5 mb-8">
          <div class="hub-sec">
            <span class="hub-sec-ico"><span class="i-lucide-orbit" /></span>
            <div class="hub-sec-text">
              <h2 class="hub-sec-title hub-progress-title">Progresso</h2>
              <p class="hub-sec-sub">força por exercício, medidas rumo ao alvo e a constância da semana — de uma olhada</p>
            </div>
          </div>
          <div ref="progressRail" class="hub-progress-rail" @scroll.passive="onProgressScroll">
            <div class="hub-progress-card hub-crystal">
              <p class="hub-label">Força · início × agora</p>
              <template v-if="strengthRadar">
                <div class="hub-progress-web"><RadarChart :axes="strengthRadar.axes" :datasets="strengthRadar.datasets" :size="300" :label-size="11" :ex-ratio="0.1" :pad-ratio="0.16" /></div>
                <p class="hub-progress-cap"><b class="hub-num-royal">{{ strengthRadar.up }}</b> de {{ strengthRadar.n }} exercícios acima do início do ciclo</p>
              </template>
              <p v-else class="hub-progress-empty">Registre 3 exercícios com carga pra teia aparecer.</p>
            </div>
            <div class="hub-progress-card hub-crystal">
              <p class="hub-label">Medidas · rumo ao alvo</p>
              <template v-if="targetRadar">
                <div class="hub-progress-web"><RadarChart :axes="targetRadar.axes" :datasets="targetRadar.datasets" :size="300" :label-size="11" :ex-ratio="0.1" :pad-ratio="0.16" /></div>
                <p class="hub-progress-cap"><b class="hub-num-royal">{{ targetRadar.avg }}%</b> do caminho, em média · <b class="hub-num-orange">{{ targetRadar.hit }}</b> alvo{{ targetRadar.hit === 1 ? '' : 's' }} batido{{ targetRadar.hit === 1 ? '' : 's' }}</p>
              </template>
              <p v-else class="hub-progress-empty">Defina pelo menos 3 alvos em "alvos" pra teia aparecer.</p>
            </div>
            <div class="hub-progress-card hub-crystal">
              <p class="hub-label">Semana · constância</p>
              <div class="hub-progress-web"><RadarChart :axes="weekRadar.axes" :datasets="weekRadar.datasets" :size="300" :label-size="11" :ex-ratio="0.1" :pad-ratio="0.16" /></div>
              <p class="hub-progress-cap"><b class="hub-num-orange">{{ weekRadar.score }}%</b> da semana ideal (treinos, cardio, medição, cargas subindo)</p>
            </div>
          </div>
          <div class="hub-progress-dots" aria-hidden="true">
            <i v-for="i in 3" :key="i" :class="{ 'is-on': progressSlide === i - 1 }" />
          </div>
        </div>

        <!-- 3. CENTÍMETROS TOTAIS × PESO -->
        <div class="hub-block hub-orange p-5 mb-8">
          <div class="flex items-center justify-between gap-2 flex-wrap mb-1">
            <h2 class="hub-h"><span class="hub-h-ico i-lucide-ruler" />Centímetros totais × peso</h2>
            <p v-if="cmTotalChart" class="text-[11px] text-n-slate-10">
              <b :style="{ color: LARANJA }">{{ fmt1(cmTotalChart.last) }} cm</b> ({{ signed(cmTotalChart.last - cmTotalChart.first) }})
              <template v-if="cmTotalChart.pesoLast !== null">
                · <b :style="{ color: ROYAL }">{{ fmtKg(cmTotalChart.pesoLast) }}</b><template v-if="cmTotalChart.pesoFirst !== null"> ({{ signed(cmTotalChart.pesoLast - cmTotalChart.pesoFirst) }})</template>
              </template>
            </p>
          </div>
          <p class="text-[10px] text-n-slate-10 mb-2">Soma de todas as circunferências (laranja) contra o peso (azul), medição a medição.</p>
          <div v-if="cmTotalChart" class="hub-chart" style="height: 190px">
            <Line :data="cmTotalChart.chart" :options="dualChartOpts" />
          </div>
          <p v-else class="text-[11px] text-n-slate-10">Registre as medidas na aba Corpo (2 medições) pra curva aparecer.</p>
        </div>

        <!-- 4. CENTÍMETROS: onde quero perder × onde quero ganhar + áreas -->
        <h2 id="hub-corpo" class="hub-h mb-4" style="scroll-margin-top: 0.75rem"><span class="hub-h-ico i-lucide-ruler" />Centímetros
          <span v-if="cmBalance.since" class="hub-h-sub">desde {{ fmtDay(cmBalance.since) }}</span>
        </h2>
        <div class="hub-block p-5 mb-8">
          <template v-if="cmBalance.rows.length">
            <div class="grid grid-cols-2 sm:grid-cols-3 gap-3 mb-3">
              <div class="hub-goal hub-crystal t-orange">
                <p class="hub-goal-l">Onde quero perder</p>
                <p class="hub-goal-v">{{ signed(cmBalance.lostStart) }}<span class="hub-goal-u">cm</span></p>
                <p class="hub-goal-s">cintura · quadril · pescoço · <b>{{ signed(cmBalance.lostPrev) }}</b> vs última</p>
              </div>
              <div class="hub-goal hub-crystal t-royal">
                <p class="hub-goal-l">Ganho muscular</p>
                <p class="hub-goal-v">{{ signed(cmBalance.gainStart) }}<span class="hub-goal-u">cm</span></p>
                <p class="hub-goal-s">peito · braços · coxas · ombros · <b>{{ signed(cmBalance.gainPrev) }}</b> vs última</p>
              </div>
              <div class="hub-goal hub-crystal t-sky">
                <p class="hub-goal-l">Saldo total</p>
                <p class="hub-goal-v">{{ signed(cmBalance.netStart) }}<span class="hub-goal-u">cm</span></p>
                <p class="hub-goal-s">{{ fmt1(cmBalance.movedStart) }} cm movidos · <b>{{ signed(cmBalance.netPrev) }}</b> vs última</p>
              </div>
            </div>
            <!-- rodada 31b: medidas agrupadas por região (tronco / peito-ombros-pescoço / braços / pernas) -->
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-6">
              <div v-for="g in cmGroups" :key="g.key" class="hub-group hub-crystal" :class="g.tone">
                <p class="hub-group-l">{{ g.label }}</p>
                <div class="hub-group-row" :class="g.rows.length >= 4 ? 'cols-4' : 'cols-3'">
                  <div v-for="r in g.rows" :key="r.key" class="hub-cell" :title="`${fmt1(r.first)} → ${fmt1(r.last)} cm`">
                    <span class="hub-cell-l">{{ r.short }}</span>
                    <b class="hub-cell-v" :class="r.dStart === 0 ? '' : r.good ? 'hub-num-royal' : 'hub-num-orange'">{{ signed(r.dStart) }}</b>
                  </div>
                </div>
              </div>
            </div>
            <p class="hub-sub"><span class="i-lucide-trending-down hub-sub-ico" />Onde quero perder × ganho muscular</p>
            <p class="text-[11px] text-n-slate-10 mb-3">
              Quanto cada grupo mudou desde a 1ª medição. Laranja bom é caindo (cintura, quadril, pescoço); azul bom é subindo (peito, braços, antebraços, coxas, panturrilhas, ombros).
            </p>
            <div v-if="cmTimeline" style="height: 190px" class="mb-4">
              <Line :data="cmTimeline.chart" :options="cmChartOpts" />
            </div>
            <p v-else class="text-[11px] text-n-slate-10 mb-4">A curva aparece a partir da 2ª medição.</p>
          </template>
          <p v-else class="text-[11px] text-n-slate-10 mb-4">
            Registre as medidas na aba Corpo (2 medições) pro balanço e as curvas aparecerem.
          </p>

          <p class="hub-sub mb-3"><span class="i-lucide-person-standing hub-sub-ico" />Áreas do corpo</p>
          <div class="hub-scroll-row mb-3">
            <span class="hub-seg">
              <button
                v-for="a in BODY_AREAS"
                :key="a.key"
                class="hub-seg-opt"
                :class="{ 'is-on': areaKey === a.key }"
                :style="areaKey === a.key ? { background: a.down ? LARANJA : ROYAL } : {}"
                @click="areaKey = a.key"
              >
                {{ a.label }}
              </button>
            </span>
          </div>
          <div v-if="areaView.lines.length" class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-3">
            <div v-for="(l, li) in areaView.lines" :key="l.key" class="hub-goal hub-crystal" :class="['t-royal', 't-orange', 't-sky', 't-amber'][li % 4]">
              <p class="hub-goal-l">{{ areaView.lines.length > 1 ? l.label : areaView.label }}</p>
              <p class="hub-goal-v">{{ fmt1(l.now) }}<span class="hub-goal-u">{{ areaView.unit }}</span></p>
              <p class="hub-goal-s">
                <b :class="l.dStart === 0 ? '' : l.good ? 'hub-num-royal' : 'hub-num-orange'">{{ signed(l.dStart) }} {{ areaView.unit }}</b> desde {{ fmtDay(l.firstDate) }}<template v-if="l.dPrev !== null"> · {{ signed(l.dPrev) }} vs última</template>
              </p>
            </div>
          </div>
          <div v-if="areaView.chart" class="hub-chart" style="height: 180px">
            <Line :data="areaView.chart" :options="areaChartOpts" />
          </div>
          <p v-else class="text-[11px] text-n-slate-10">Sem medições de {{ areaView.label.toLowerCase() }} ainda.</p>
        </div>

        <!-- 4. PROGRESSO DAS CARGAS: todos os exercícios do ciclo -->
        <div class="flex items-center justify-between gap-2 flex-wrap mb-2">
          <h2 class="hub-h"><span class="hub-h-ico i-lucide-dumbbell" />Progresso das cargas</h2>
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
        <div class="hub-block p-5 mb-8">
          <p class="text-[11px] text-n-slate-10 mb-3">
            Carga de cada exercício e quanto subiu neste ciclo. Toque num exercício pra ver o detalhe; deslize pro lado pros outros treinos.
          </p>
          <div ref="carousel" class="hub-carousel" @scroll.passive="onCarouselScroll">
            <div v-for="(s, i) in loadProgress" :key="s.key" class="hub-slide">
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
                  <button class="hub-arrow" :disabled="i === 0" title="Treino anterior" @click="goSlide(i - 1)">‹</button>
                  <span class="text-[10px] opacity-80">{{ i + 1 }}/{{ loadProgress.length }}</span>
                  <button class="hub-arrow" :disabled="i === loadProgress.length - 1" title="Próximo treino" @click="goSlide(i + 1)">›</button>
                </div>
              </div>
              <!-- fazer este treino agora (pedido 18/09) -->
              <button
                class="w-full h-11 rounded-xl text-sm font-bold text-white shadow mb-3"
                :style="{ background: GRAD_LARANJA }"
                @click="goStart(s.key)"
              >
                ▶ Fazer Treino {{ s.key }}
                <span v-if="upcomingSession && upcomingSession.key === s.key" class="text-[10px] font-normal opacity-90">· é o da vez</span>
              </button>
              <div class="grid gap-2" style="grid-template-columns: repeat(auto-fill, minmax(260px, 1fr))">
                <button
                  v-for="e in s.exercises"
                  :key="e.name"
                  class="hub-crystal t-royal rounded-xl p-2.5 text-left transition-colors"
                  :class="{ 'is-open': openCards.has(e.name) }"
                  @click="toggleCard(e.name)"
                >
                  <div class="flex items-center gap-3">
                    <div class="flex-1 min-w-0">
                      <p class="text-xs font-bold text-n-slate-12 truncate">
                        {{ e.name }}
                        <span v-if="e.tag" class="font-normal text-n-slate-10">· {{ e.tag }}</span>
                        <span v-if="e.pr" class="i-lucide-medal hub-ico-inline" title="Recorde de força estimada" />
                      </p>
                      <p v-if="e.last" class="text-[11px] mt-0.5">
                        <span
                          v-if="e.deltaCycle !== null"
                          class="font-bold"
                          :style="{ color: e.deltaCycle > 0 ? ROYAL : e.deltaCycle < 0 ? LARANJA_VIVO : CINZA }"
                        >
                          {{ signed(e.deltaCycle) }} kg no ciclo<template v-if="e.pctCycle !== null"> ({{ signed(e.pctCycle) }}%)</template>
                        </span>
                        <span v-else class="text-n-slate-10">1ª execução do ciclo</span>
                      </p>
                      <p v-else class="text-[11px] text-n-slate-10">ainda não feito</p>
                    </div>
                    <div class="shrink-0 text-right">
                      <p class="text-lg font-extrabold leading-none" :style="{ color: e.last ? ROYAL : CINZA }">
                        {{ e.last ? fmt1(e.last.common) : '—' }}<span class="text-[10px] font-medium text-n-slate-10"> kg</span>
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
                  <!-- detalhe (toque) -->
                  <div v-if="openCards.has(e.name) && e.last" class="hub-card-detail mt-2 pt-2 border-t border-n-weak/60 text-n-slate-10 flex flex-col gap-0.5">
                    <p>Última {{ fmtDay(e.last.date) }}: {{ fmtSets(e.last.sets) }}</p>
                    <p>
                      <span v-if="e.verdict" :style="{ color: VERDICT_COLORS[e.verdict] || LARANJA }">{{ VERDICT_LABEL[e.verdict] }}</span>
                      <span v-if="e.deltaPrev !== null"> · {{ signed(e.deltaPrev) }} kg vs anterior</span>
                      <span v-if="e.e1"> · força estimada {{ fmt1(e.e1) }} kg</span>
                      <span> · {{ e.count }} {{ e.count === 1 ? 'execução' : 'execuções' }}</span>
                    </p>
                    <p v-if="e.mixed" :style="{ color: ROYAL }">
                      peso comum ·
                      <template v-for="(t, ti) in e.perTag" :key="t.tag">
                        <template v-if="ti > 0"> ≈ </template>{{ t.tag }} {{ fmt1(t.top) }}<template v-if="t.factor !== 1"> (×{{ String(t.factor).replace('.', ',') }})</template>
                      </template>
                    </p>
                    <p v-if="e.last.common !== e.last.top">registrado em {{ e.last.tag || 'outra variação' }}: {{ fmt1(e.last.top) }} kg</p>
                  </div>
                </button>
              </div>
            </div>
          </div>
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

        <!-- 6. FORÇA: geral e por treino -->
        <div id="hub-forca" class="flex items-center justify-between gap-2 flex-wrap mb-2" style="scroll-margin-top: 0.75rem">
          <h2 class="hub-h"><span class="hub-h-ico i-lucide-trending-up" />Força nos treinos</h2>
          <span v-if="forcaOptions.length > 1" class="hub-seg">
            <button
              v-for="o in forcaOptions"
              :key="o.key"
              class="hub-seg-opt"
              :class="{ 'is-on': forcaKey === o.key }"
              :style="forcaKey === o.key ? { background: o.key === 'geral' ? LARANJA : ROYAL } : {}"
              @click="forcaKey = o.key"
            >
              {{ o.label }}
            </button>
          </span>
        </div>
        <div class="hub-block p-5 mb-8">
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-3 mb-3">
            <div class="hub-goal hub-crystal t-royal">
              <p class="hub-goal-l">Força total</p>
              <p class="hub-goal-v">{{ forcaView.m.n ? forcaView.m.now : '—' }}<span class="hub-goal-u">kg</span></p>
              <p class="hub-goal-s">
                <template v-if="forcaView.m.n && forcaView.m.delta"><b>{{ signed(forcaView.m.delta) }} kg</b> no ciclo ({{ signed(forcaView.m.pct) }}%)</template>
                <template v-else-if="forcaView.m.n">partiu de {{ forcaView.m.start }} kg</template>
                <template v-else>registre treinos</template>
              </p>
            </div>
            <div class="hub-goal hub-crystal t-orange">
              <p class="hub-goal-l">Força relativa</p>
              <p class="hub-goal-v">{{ forcaView.m.rel !== null ? `${String(forcaView.m.rel).replace('.', ',')}×` : '—' }}<span class="hub-goal-u">peso</span></p>
              <p class="hub-goal-s">
                <template v-if="forcaView.m.relDelta !== null && forcaView.m.relDelta !== 0"><b>{{ signed(forcaView.m.relDelta) }}×</b> peso no ciclo</template>
                <template v-else>força por kg de corpo</template>
              </p>
            </div>
            <div class="hub-goal hub-crystal t-sky">
              <p class="hub-goal-l">Exercícios subindo</p>
              <p class="hub-goal-v">{{ forcaView.m.rate === null ? '—' : forcaView.m.rate }}<span v-if="forcaView.m.rate !== null" class="hub-goal-u">%</span></p>
              <p class="hub-goal-s">
                <template v-if="forcaView.m.comparable">▲{{ forcaView.m.verdicts.progress }} ▬{{ forcaView.m.verdicts.tie }} ▼{{ forcaView.m.verdicts.regress }} no ciclo</template>
                <template v-else>superados ÷ comparáveis</template>
              </p>
            </div>
          </div>
          <div v-if="forcaView.chart" class="hub-chart" style="height: 180px">
            <Line :data="forcaView.chart" :options="dualChartOpts" />
          </div>
          <p v-else class="text-[11px] text-n-slate-10">A curva da força aparece a partir da 2ª semana com treinos registrados.</p>
        </div>

        <!-- 6. METAS DO PRÓXIMO TREINO (dobrável) -->
        <div class="hub-block mb-8">
          <button class="w-full flex items-center justify-between gap-2 px-4 py-3 text-left" @click="toggleMetas">
            <span class="hub-h">
              <span class="hub-h-ico i-lucide-target" />Metas do Treino {{ metasSession?.key || '' }}
              <span v-if="metasSession?.weekday" class="hub-h-sub">· {{ metasSession.weekday }} · {{ upcomingPlan.length }} exercícios</span>
              <span
                v-if="metasSession && upcomingSession && metasSession.key === upcomingSession.key"
                class="ml-1 px-1.5 py-0.5 rounded-full text-[9px] font-bold normal-case"
                :style="{ background: LARANJA, color: '#1a0e00' }"
              >
                da vez
              </span>
            </span>
            <span class="text-n-slate-10 text-sm">{{ metasOpen ? '▾' : '▸' }}</span>
          </button>
          <div v-if="metasOpen" class="px-4 pb-4">
            <div v-if="cycleSessions.length > 1" class="mb-3">
              <span class="hub-seg">
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
            <p v-if="!upcomingPlan.length" class="text-[11px] text-n-slate-10">
              Sem programa ativo — escolha o Warrior ou crie o seu na aba Treino.
            </p>
            <div v-for="ex in upcomingPlan" :key="ex.name" class="py-2.5 border-b border-n-weak/60 last:border-0 last:pb-0 first:pt-0">
              <div class="flex items-center gap-2 flex-wrap mb-1">
                <p class="text-sm font-bold text-n-slate-12">{{ ex.name }}</p>
                <span v-if="ex.tag" class="px-1.5 py-0.5 rounded-full text-[10px] font-medium border border-dashed border-n-weak text-n-slate-10">
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
                <span v-for="(t, ti) in ex.targets" :key="ti" class="hub-target" :class="{ 'is-gold': ex.hint.startsWith('🎯') }">
                  <span class="opacity-60">{{ t.label }}</span>
                  <b>{{ t.load != null ? fmtTarget(t) : t.reps }}</b>
                </span>
                <span class="text-[11px] font-medium" :style="{ color: ex.hint.startsWith('🎯') ? LARANJA : ROYAL }">
                  {{ ex.hint }}
                </span>
              </div>
            </div>
            <button
              v-if="metasSession"
              class="mt-3 h-10 px-4 rounded-xl text-xs font-bold text-white"
              :style="{ background: GRAD_LARANJA }"
              @click="goStart(metasSession.key)"
            >
              ▶ Começar Treino {{ metasSession.key }}
            </button>
          </div>
        </div>

        <div class="flex justify-end mb-8">
          <button class="text-[11px] underline" :style="{ color: ROYAL_CLARO }" @click="go('hub_health_dash')">
            ver Análises completas →
          </button>
        </div>
      </template>
    </div>
  </div>
</template>

<style scoped>
/* detalhe do card de carga (rodada 22): o <p> global do app impõe 14px */
.hub-card-detail,
.hub-card-detail p {
  font-size: 11px;
  line-height: 1.35;
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
  white-space: nowrap;
  transition: all 0.15s ease;
}
.hub-seg-opt.is-on {
  color: #fff;
  opacity: 1;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.25);
}
/* fileira que rola pro lado no celular (áreas do corpo) */
.hub-scroll-row {
  overflow-x: auto;
  scrollbar-width: none;
  -webkit-overflow-scrolling: touch;
  margin: 0 -0.25rem;
  padding: 0 0.25rem;
}
.hub-scroll-row::-webkit-scrollbar {
  display: none;
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
