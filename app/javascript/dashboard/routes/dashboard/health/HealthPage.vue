<script setup>
// SAÚDE (HUB, segmento saude) — o painel pessoal: treino, dieta e corpo.
// O treino roda em MODO PROGRAMA (Warrior Shredding): a prescrição mora em
// agenda_config['health']['programs'] (seed db/seeds/hub_warrior.rb) e cada
// execução vira um hub_health_record imutável. O motor de progressão
// (warrior.js) compara HOJE × ÚLTIMA SESSÃO e calcula a meta de cada
// exercício. Fichas avulsas (fora de programa) continuam existindo.
// Feito pra usar NO CELULAR dentro da academia: poucos toques por série.
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import MiniBars from 'dashboard/components-next/cevico/MiniBars.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';
import WheelInput from './WheelInput.vue';
import {
  METHOD_LABELS, METHOD_HINTS, SET_LABELS,
  activeProgram, weekOf, cycleForWeek, suggestedSessionKey,
  lastSessionRecord, lastExerciseSets, buildTodaySets,
  exerciseVerdict, targetHint, setTargets, sessionSummary, summaryPhrase, fmtSets,
} from './warrior';

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

// aba sincronizada com a rota (cada aba tem rota própria — o item certo
// acende no menu do modo Saúde e o link é compartilhável)
const route = useRoute();
const router = useRouter();
const tab = ref(route.meta?.healthTab || 'treino');
watch(
  () => route.meta?.healthTab,
  t => {
    if (t) tab.value = t;
  }
);

const TAB_ROUTES = {
  treino: 'hub_health',
  boxe: 'hub_health_boxe',
  dieta: 'hub_health_dieta',
  corpo: 'hub_health_corpo',
};
const goTab = key => {
  tab.value = key;
  const name = TAB_ROUTES[key];
  if (name && route.name !== name) router.push({ name, params: route.params });
};

// boxe é ligável em Configurações → HUB — desligado, a pílula some
const boxingOn = computed(() => config.value?.features?.boxing === true);
const TABS_ALL = [
  { key: 'treino', label: 'Treino', icon: 'i-lucide-dumbbell' },
  { key: 'boxe', label: 'Boxe', icon: 'i-lucide-swords' },
  { key: 'dieta', label: 'Dieta', icon: 'i-lucide-utensils' },
  { key: 'corpo', label: 'Corpo', icon: 'i-lucide-ruler' },
];
const TABS = computed(() =>
  TABS_ALL.filter(t => t.key !== 'boxe' || boxingOn.value)
);

// ordena registros do mais novo pro mais velho (entradas retroativas)
const sortRecs = arr => [...arr].sort((a, b) => (a.record_date < b.record_date ? 1 : -1));

// ── utilidades ──────────────────────────────────────────────────────
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
// aceita vírgula brasileira: "62,5" → 62.5
const toNum = v => Number(String(v ?? '').replace(',', '.')) || 0;

const plans = computed(() => config.value?.workout_plans || []);
const programs = computed(() => config.value?.programs || []);
const dietCfg = computed(() => {
  const d = config.value?.diet || {};
  return { targets: d.targets || {}, meals: d.meals || [], notes: d.notes || '' };
});

// ── KPIs do topo (musculação + boxe contam como treino) ─────────────
const allTraining = computed(() => [...workouts.value, ...boxings.value]);
const treinos7 = computed(
  () => allTraining.value.filter(w => w.record_date >= daysAgo(6)).length
);
const streak = computed(() => {
  const dates = new Set(allTraining.value.map(w => w.record_date));
  let count = 0;
  const cursor = new Date();
  // hoje ainda sem treino não quebra a sequência — começa de ontem
  if (!dates.has(toISO(cursor))) cursor.setDate(cursor.getDate() - 1);
  while (dates.has(toISO(cursor))) {
    count += 1;
    cursor.setDate(cursor.getDate() - 1);
  }
  return count;
});
const latestWeight = computed(() => {
  const rec = bodies.value.find(b => Number(b.data?.weight) > 0);
  return rec ? Number(rec.data.weight) : null;
});
const weightDelta30 = computed(() => {
  if (latestWeight.value === null) return null;
  const limit = daysAgo(30);
  const old = [...bodies.value]
    .filter(b => Number(b.data?.weight) > 0 && b.record_date <= limit)
    .sort((a, b) => (a.record_date < b.record_date ? 1 : -1))[0];
  if (!old) return null;
  return latestWeight.value - Number(old.data.weight);
});

// ═══ TREINO — MODO PROGRAMA (Warrior) ═══════════════════════════════
const program = computed(() => activeProgram(programs.value));
const programWeek = computed(() => weekOf(program.value, todayISO));
const programCycle = computed(() => cycleForWeek(program.value, programWeek.value));
const totalWeeks = computed(() => {
  const cycles = program.value?.cycles || [];
  return cycles.length ? Math.max(...cycles.map(c => c.week_end || 0)) : 0;
});
const nextKey = computed(() =>
  suggestedSessionKey(workouts.value, program.value, programCycle.value)
);

const savingConfig = ref(false);
const pushConfig = async next => {
  savingConfig.value = true;
  try {
    const { data: resp } = await CrmAPI.updateHealthConfig(next);
    config.value = resp.config || {};
    return true;
  } catch {
    useAlert('Não consegui salvar a configuração.');
    return false;
  } finally {
    savingConfig.value = false;
  }
};

const setActiveProgram = p => {
  const list = programs.value.map(x => ({ ...x, active: x.id === p.id }));
  pushConfig({ ...config.value, programs: list });
};

// ═══ EDITOR DE EXERCÍCIOS DA PRESCRIÇÃO (pedido 26/08) ══════════════
// Adicionar exercício num treino, substituir (renomear) e marcar a
// VARIAÇÃO como tag (ex.: halteres/barra/máquina). Mexe só na
// prescrição (config) — os registros já feitos ficam como estão.
const exEditor = ref(null);
const openExerciseEditor = sessionDef => {
  const prog = program.value;
  const cycle = programCycle.value;
  exEditor.value = {
    programId: prog.id,
    cycleId: cycle?.id,
    sessionKey: sessionDef.key,
    title: `Treino ${sessionDef.key} — ${cycle?.name || prog.name}`,
    rows: (sessionDef.exercises || []).map(e => ({ ...e, _del: false })),
  };
};
const addEditorExercise = () =>
  exEditor.value.rows.push({
    name: '',
    tag: '',
    method: 'sets',
    scheme: '3 × 8–12',
    rest: '',
    warmup: '',
    progression: '',
    progression_type: '',
    note: '',
    sets: [{ min: 8, max: 12 }, { min: 8, max: 12 }, { min: 8, max: 12 }],
    _del: false,
  });
const saveExerciseEditor = async () => {
  const ed = exEditor.value;
  if (!ed) return;
  const rows = ed.rows.filter(r => !r._del && r.name?.trim());
  const progs = programs.value.map(p => {
    if (p.id !== ed.programId) return p;
    return {
      ...p,
      cycles: (p.cycles || []).map(c =>
        c.id !== ed.cycleId
          ? c
          : {
              ...c,
              sessions: (c.sessions || []).map(s =>
                s.key !== ed.sessionKey
                  ? s
                  : { ...s, exercises: rows.map(({ _del, ...e }) => e) }
              ),
            }
      ),
    };
  });
  const ok = await pushConfig({ ...config.value, programs: progs });
  if (ok) {
    exEditor.value = null;
    useAlert('✏️ Treino atualizado.');
  } else {
    useAlert('Não consegui salvar a edição.');
  }
};

// sessão em andamento (programa OU ficha avulsa) — nada salvo até concluir
const session = ref(null);
const savingSession = ref(false);

const startProgramSession = sessionDef => {
  const prog = program.value;
  const cycle = programCycle.value;
  const lastRecord = lastSessionRecord(workouts.value, prog.id, sessionDef.key);
  const exercises = (sessionDef.exercises || []).map(p => {
    const last = lastExerciseSets(lastRecord, p.name);
    return {
      name: p.name,
      tag: p.tag,
      baseTag: p.tag || '',
      altTag: p.alt_tag || '',
      presc: p,
      method: p.method,
      scheme: p.scheme,
      rest: p.rest,
      warmup: p.warmup,
      progression: p.progression,
      note: p.note,
      last,
      hint: targetHint(p, last),
      targets: setTargets(p, last),
      sets: buildTodaySets(p, last),
    };
  });
  session.value = {
    mode: 'program',
    program_id: prog.id,
    cycle_id: cycle?.id,
    session_key: sessionDef.key,
    week: programWeek.value,
    plan_name: `Treino ${sessionDef.key} — ${cycle?.name || prog.name}`,
    date: todayISO,
    exercises,
    notes: '',
  };
};

// ═══ PLANILHA DAS SEMANAS (pedido 25/08): abas A | B | C | Bônus ═══
// A = ciclo 1 (sem 1–8) · B = ciclo 2 (9–16) · C = ciclo 3 (17–24) ·
// Bônus = bloco extra de 8 semanas. Linhas = exercícios; colunas = as
// semanas; lacuna = "60x6 54x7 48x8". Grava nos MESMOS registros do
// modo treino (1 registro por treino/semana — nada duplica).
const CYCLE_LETTERS = ['A', 'B', 'C'];
const gridTabs = computed(() => {
  const main = programs.value.find(p => p.id === 'warrior24');
  const bonus = programs.value.find(p => p.id === 'warrior_bonus');
  const tabs = (main?.cycles || []).map((c, i) => ({
    key: c.id,
    label: CYCLE_LETTERS[i] || c.name,
    sub: `sem ${c.week_start}–${c.week_end}`,
    programId: main.id,
    program: main,
    cycle: c,
  }));
  if (bonus?.cycles?.length) {
    tabs.push({
      key: 'bonus',
      label: 'Bônus',
      sub: '8 sem extra',
      programId: bonus.id,
      program: bonus,
      cycle: bonus.cycles[0],
    });
  }
  return tabs;
});
const gridCycleKey = ref('');
const gridTab = computed(
  () => gridTabs.value.find(t => t.key === gridCycleKey.value) || gridTabs.value[0] || null
);
const gridWeeks = computed(() => {
  const c = gridTab.value?.cycle;
  if (!c) return [];
  const start = c.week_start || 1;
  const end = c.week_end || start + 7;
  return Array.from({ length: end - start + 1 }, (_, i) => start + i);
});

const gridRecordFor = (sessionKey, week) =>
  workouts.value.find(
    w =>
      w.data?.program_id === gridTab.value?.programId &&
      w.data?.cycle_id === gridTab.value?.cycle?.id &&
      w.data?.session_key === sessionKey &&
      Number(w.data?.week) === Number(week)
  ) || null;

const cellText = (sessionKey, week, exName) => {
  const rec = gridRecordFor(sessionKey, week);
  const ex = (rec?.data?.exercises || []).find(e => e.name === exName);
  if (!ex?.sets?.length) return '';
  return ex.sets.map(s => `${String(s.load).replace('.', ',')}x${s.reps}`).join(' ');
};

// lacunas em edição (sessão|semana|exercício → texto digitado)
const gridDrafts = ref({});
const gridKey = (s, w, n) => `${s}|${w}|${n}`;

// "60x6 54x7 48x8" → séries; aceita vírgula (62,5x8), × e separador / ·
const parseCellSets = text =>
  String(text)
    .trim()
    .split(/[\s;/·|]+/)
    .filter(Boolean)
    .map(token => {
      const m = token.match(/^(\d+(?:[.,]\d+)?)[x×](\d+)$/i);
      return m ? { load: Number(m[1].replace(',', '.')), reps: Number(m[2]) } : null;
    })
    .filter(Boolean);

const WEEKDAY_OFFSET = { Segunda: 0, Terça: 1, Quarta: 2, Quinta: 3, Sexta: 4, Sábado: 5 };
// data planejada da célula: início do programa + semanas + dia da sessão
const plannedDate = (prog, week, weekday) => {
  if (!prog?.start_date) return todayISO;
  const d = new Date(`${prog.start_date}T00:00:00`);
  d.setDate(d.getDate() + (week - 1) * 7 + (WEEKDAY_OFFSET[weekday] || 0));
  return toISO(d);
};

const saveCell = async (sessionDef, week, exName) => {
  const key = gridKey(sessionDef.key, week, exName);
  const raw = gridDrafts.value[key];
  if (raw === undefined) return;
  const sets = parseCellSets(raw);
  const rec = gridRecordFor(sessionDef.key, week);
  try {
    if (rec) {
      const exercises = [...(rec.data.exercises || [])];
      const idx = exercises.findIndex(e => e.name === exName);
      if (sets.length) {
        if (idx >= 0) exercises[idx] = { ...exercises[idx], name: exName, sets, skipped: false };
        else exercises.push({ name: exName, sets });
      } else if (idx >= 0) {
        exercises.splice(idx, 1);
      }
      const { data: updated } = await CrmAPI.updateHealthRecord(rec.id, { ...rec.data, exercises });
      workouts.value = workouts.value.map(w => (w.id === updated.id ? updated : w));
    } else if (sets.length) {
      const tabInfo = gridTab.value;
      const { data: created } = await CrmAPI.createHealthRecord({
        kind: 'workout',
        record_date: plannedDate(tabInfo.program, week, sessionDef.weekday),
        data: {
          program_id: tabInfo.programId,
          cycle_id: tabInfo.cycle.id,
          session_key: sessionDef.key,
          week,
          plan_name: `Treino ${sessionDef.key} — ${tabInfo.cycle.name}`,
          exercises: [{ name: exName, sets }],
        },
      });
      workouts.value = [created, ...workouts.value];
    }
    delete gridDrafts.value[key];
  } catch {
    useAlert('Não consegui salvar a lacuna.');
  }
};

const startSession = plan => {
  const last = workouts.value.find(w => w.data?.plan_id === plan.id);
  const exercises = (plan.exercises || []).map(ex => {
    const prev = (last?.data?.exercises || []).find(e => e.name === ex.name);
    const sets = prev?.sets?.length
      ? prev.sets.map(s => ({
          load: '',
          reps: '',
          prev: { load: s.load, reps: s.reps },
          range: String(ex.reps || ''),
        }))
      : Array.from({ length: Math.max(1, ex.sets || 3) }, () => ({
          load: '',
          reps: '',
          prev: null,
          range: String(ex.reps || ''),
        }));
    return { name: ex.name, scheme: `${ex.sets || '?'}×${ex.reps || '?'}`, sets };
  });
  session.value = {
    mode: 'ficha',
    plan_id: plan.id,
    plan_name: plan.name,
    date: todayISO,
    exercises,
    notes: '',
  };
};

const addSet = ex => {
  const lastSet = ex.sets[ex.sets.length - 1] || {};
  ex.sets.push({
    load: '',
    reps: '',
    prev: null,
    range: lastSet.range || '',
    kind: lastSet.kind || '',
  });
};
const removeSet = (ex, i) => ex.sets.splice(i, 1);

// toque no chip cinza "última vez" → copia o valor pras caixinhas da série
const copyPrev = set => {
  if (!set.prev) return;
  set.load = String(set.prev.load ?? '').replace('.', ',');
  set.reps = String(set.prev.reps ?? '');
};
const fmtPrev = prev => `${String(prev.load ?? '').replace('.', ',')}×${prev.reps ?? ''}`;

// ═══ CHAVINHA DE VARIAÇÃO (rodada 13): halteres ⇄ barra etc. ════════
// A prescrição tem tag (variação A) e alt_tag (variação B, no editor ✎).
// Trocar a chavinha re-prefill as roletas com a última execução DAQUELA
// variação (carga de barra ≠ carga de halter) e recalcula meta/alvos.
// O registro salva a variação usada (out.tag) pra busca futura.
const normTag = t => String(t || '').trim().toLowerCase();
// última execução do exercício NESSA variação, em qualquer treino;
// registros antigos sem tag contam como a variação principal (base)
const lastSetsForTag = (name, tag, baseTag) => {
  const alvoNome = name.trim().toLowerCase();
  const alvoTag = normTag(tag);
  const ehBase = alvoTag === normTag(baseTag);
  for (const w of workouts.value) {
    const ex = (w.data?.exercises || []).find(e => {
      if (String(e.name || '').trim().toLowerCase() !== alvoNome) return false;
      const t = normTag(e.tag);
      return t === alvoTag || (ehBase && !t);
    });
    if (ex?.sets?.length) return ex.sets;
  }
  return null;
};
const switchVariation = (ex, tag) => {
  if (normTag(ex.tag) === normTag(tag)) return;
  ex.tag = tag;
  const last = lastSetsForTag(ex.name, tag, ex.baseTag);
  ex.last = last;
  ex.hint = last
    ? targetHint(ex.presc || { sets: [] }, last)
    : `Primeira vez com ${tag} — encontre a carga desta variação.`;
  ex.targets = setTargets(ex.presc || { sets: [] }, last);
  ex.sets = buildTodaySets(ex.presc || { sets: [] }, last);
};

// tocar num alvo do cartão de vidro → roletas da série vão pra meta
const applyTarget = (ex, i) => {
  const t = ex.targets?.[i];
  const set = ex.sets?.[i];
  if (!t || !set || t.load === null || t.load === undefined) return;
  set.load = String(t.load).replace('.', ',');
  if (Number.isFinite(Number(t.reps))) set.reps = String(t.reps);
};
const fmtTarget = t =>
  `${String(t.load ?? '').replace('.', ',')}×${t.reps}`;

// ═══ EXERCÍCIO EXTRA no treino de hoje (rodada 11): crucifixo,
// panturrilha etc. entram na MESMA sessão e salvam junto no histórico
// (flag extra: true no registro). Última execução vem do histórico
// inteiro (qualquer treino em que o nome apareceu) — o motor compara.
const extraOpen = ref(false);
const extraName = ref('');
const EXTRA_COMUNS = [
  'Crucifixo na máquina',
  'Panturrilha em pé',
  'Panturrilha sentado',
  'Elevação lateral com halteres',
  'Face pull',
  'Abdominal na polia',
];
const extraSuggestions = computed(() => {
  const names = new Set(EXTRA_COMUNS);
  programs.value.forEach(p =>
    (p.cycles || []).forEach(c =>
      (c.sessions || []).forEach(s =>
        (s.exercises || []).forEach(e => e.name && names.add(e.name))
      )
    )
  );
  workouts.value.forEach(w =>
    (w.data?.exercises || []).forEach(e => e.name && names.add(e.name))
  );
  const inSession = new Set(
    (session.value?.exercises || []).map(e => e.name.trim().toLowerCase())
  );
  return [...names]
    .filter(n => !inSession.has(n.trim().toLowerCase()))
    .sort((a, b) => a.localeCompare(b));
});
// última vez deste exercício em QUALQUER treino registrado
const lastAnySets = name => {
  const alvo = name.trim().toLowerCase();
  for (const w of workouts.value) {
    const ex = (w.data?.exercises || []).find(
      e => String(e.name || '').trim().toLowerCase() === alvo
    );
    if (ex?.sets?.length) return ex.sets;
  }
  return null;
};
const addExtraExercise = () => {
  const name = extraName.value.trim();
  if (!name || !session.value) return;
  if (
    session.value.exercises.some(
      e => e.name.trim().toLowerCase() === name.toLowerCase()
    )
  ) {
    useAlert('Esse exercício já está no treino de hoje.');
    return;
  }
  const last = lastAnySets(name);
  const sets = last
    ? last.map(s => ({
        load: String(s.load ?? '').replace('.', ','),
        reps: String(s.reps ?? ''),
        prev: { load: s.load, reps: s.reps },
        range: '',
      }))
    : Array.from({ length: 3 }, () => ({ load: '', reps: '', prev: null, range: '' }));
  session.value.exercises.push({
    name,
    extra: true,
    method: 'sets',
    scheme: `${sets.length} séries`,
    presc: { sets: [] },
    last,
    hint: last ? targetHint({ sets: [] }, last) : 'Exercício extra — primeira vez, encontre a carga.',
    targets: setTargets({ sets: [] }, last),
    sets,
  });
  extraName.value = '';
  extraOpen.value = false;
};
const removeExtraExercise = ex => {
  session.value.exercises = session.value.exercises.filter(e => e !== ex);
};

// a SEMANA do registro segue a DATA escolhida (registro retroativo cai
// na semana certa do programa, não na semana de hoje)
watch(
  () => session.value?.date,
  d => {
    if (!d || session.value?.mode !== 'program') return;
    const w = weekOf(program.value, d);
    if (w) session.value.week = w;
  }
);

const saveSession = async () => {
  if (!session.value) return;
  savingSession.value = true;
  try {
    const isProgram = session.value.mode === 'program';
    const exercises = session.value.exercises.map(ex => {
      const sets = ex.sets
        .filter(s => s.load !== '' || s.reps !== '')
        .map(s => {
          const set = { load: toNum(s.load), reps: Math.round(toNum(s.reps)) };
          if (s.kind) set.kind = s.kind;
          return set;
        });
      const out = { name: ex.name, sets, skipped: sets.length === 0 };
      if (ex.extra) out.extra = true;
      if (ex.tag) out.tag = ex.tag; // variação usada hoje (chavinha)
      if (ex.method) out.method = ex.method;
      if (isProgram && !out.skipped) out.verdict = exerciseVerdict(sets, ex.last);
      return out;
    })
      // extra adicionado mas deixado em branco não entra no registro
      .filter(e => !(e.extra && e.skipped));
    const data = {
      plan_name: session.value.plan_name,
      notes: session.value.notes,
      exercises,
    };
    if (isProgram) {
      data.program_id = session.value.program_id;
      data.cycle_id = session.value.cycle_id;
      data.session_key = session.value.session_key;
      data.week = session.value.week;
      data.summary = sessionSummary(exercises.map(e => ({ ...e, verdict: e.verdict })));
    } else {
      data.plan_id = session.value.plan_id;
    }
    // 1 registro por treino/semana: se a planilha (ou um treino anterior)
    // já criou o registro desta sessão nesta semana, atualiza em vez de duplicar
    const existing =
      isProgram && Number.isFinite(Number(session.value.week))
        ? workouts.value.find(
            w =>
              w.data?.program_id === session.value.program_id &&
              w.data?.session_key === session.value.session_key &&
              Number(w.data?.week) === Number(session.value.week)
          )
        : null;
    if (existing) {
      const { data: rec } = await CrmAPI.updateHealthRecord(existing.id, data, session.value.date);
      workouts.value = workouts.value.map(w => (w.id === rec.id ? rec : w));
    } else {
      const { data: rec } = await CrmAPI.createHealthRecord({
        kind: 'workout',
        record_date: session.value.date || todayISO,
        data,
      });
      workouts.value = sortRecs([rec, ...workouts.value]);
    }
    session.value = null;
    if (isProgram) {
      const done = exercises.filter(e => !e.skipped).length;
      useAlert(`💪 ${summaryPhrase(data.summary, done)}`);
    } else {
      useAlert('💪 Treino registrado!');
    }
  } catch {
    useAlert('Não consegui salvar o treino.');
  } finally {
    savingSession.value = false;
  }
};

// ═══ BOXE: sequências pra praticar + treino com tempo e rounds ═══
const boxingSeqs = computed(() => config.value?.boxing?.sequences || []);

const boxForm = ref({ date: todayISO, duration: '', rounds: '', seqs: [], notes: '' });
const savingBox = ref(false);
const toggleSeq = id => {
  const i = boxForm.value.seqs.indexOf(id);
  if (i >= 0) boxForm.value.seqs.splice(i, 1);
  else boxForm.value.seqs.push(id);
};
const saveBoxing = async () => {
  const duration = Math.round(toNum(boxForm.value.duration));
  if (!duration) {
    useAlert('Informe a duração do treino (minutos).');
    return;
  }
  savingBox.value = true;
  try {
    const { data: rec } = await CrmAPI.createHealthRecord({
      kind: 'boxing',
      record_date: boxForm.value.date || todayISO,
      data: {
        duration_min: duration,
        rounds: Math.round(toNum(boxForm.value.rounds)),
        sequences: [...boxForm.value.seqs],
        notes: boxForm.value.notes?.trim() || '',
      },
    });
    boxings.value = sortRecs([rec, ...boxings.value]);
    boxForm.value = { date: todayISO, duration: '', rounds: '', seqs: [], notes: '' };
    useAlert('🥊 Treino de boxe registrado!');
  } catch {
    useAlert('Não consegui salvar o treino de boxe.');
  } finally {
    savingBox.value = false;
  }
};

// editor de sequências (biblioteca de combos)
const seqForm = ref(null);
const openNewSeq = () => {
  seqForm.value = { id: '', name: '', steps: '', desc: '' };
};
const openEditSeq = s => {
  seqForm.value = { ...s };
};
const saveSeq = async () => {
  if (!seqForm.value.name?.trim() || !seqForm.value.steps?.trim()) {
    useAlert('Dê um nome e os passos da sequência (ex.: 1 · 2 · 3).');
    return;
  }
  const list = [...boxingSeqs.value];
  const idx = list.findIndex(s => s.id && s.id === seqForm.value.id);
  if (idx >= 0) list[idx] = { ...seqForm.value };
  else list.push({ ...seqForm.value });
  const ok = await pushConfig({ ...config.value, boxing: { sequences: list } });
  if (ok) {
    seqForm.value = null;
    useAlert('Sequência salva.');
  }
};
const deleteSeq = async () => {
  const list = boxingSeqs.value.filter(s => s.id !== seqForm.value.id);
  const ok = await pushConfig({ ...config.value, boxing: { sequences: list } });
  if (ok) {
    seqForm.value = null;
    useAlert('Sequência removida.');
  }
};
const seqName = id => boxingSeqs.value.find(s => s.id === id)?.name || id;
const boxMin7 = computed(() =>
  boxings.value
    .filter(b => b.record_date >= daysAgo(6))
    .reduce((s, b) => s + (Number(b.data?.duration_min) || 0), 0)
);

// fichas avulsas (fora de programa)
const planForm = ref(null); // null = fechado; {id?, name, exercises[]}
const showFichas = ref(false);

const openNewPlan = () => {
  planForm.value = { id: '', name: '', exercises: [{ name: '', sets: 3, reps: '10', load: '' }] };
};
const openEditPlan = plan => {
  planForm.value = JSON.parse(JSON.stringify(plan));
};
const addPlanExercise = () => planForm.value.exercises.push({ name: '', sets: 3, reps: '10', load: '' });
const removePlanExercise = i => planForm.value.exercises.splice(i, 1);

const savePlan = async () => {
  const form = planForm.value;
  if (!form?.name?.trim()) {
    useAlert('Dê um nome pra ficha (ex.: Cardio — Esteira).');
    return;
  }
  form.exercises = form.exercises.filter(ex => ex.name?.trim());
  const list = [...plans.value];
  const idx = list.findIndex(p => p.id && p.id === form.id);
  if (idx >= 0) list[idx] = form;
  else list.push(form);
  const ok = await pushConfig({ ...config.value, workout_plans: list });
  if (ok) {
    planForm.value = null;
    useAlert('Ficha salva.');
  }
};

const deletePlan = async () => {
  const list = plans.value.filter(p => p.id !== planForm.value.id);
  const ok = await pushConfig({ ...config.value, workout_plans: list });
  if (ok) {
    planForm.value = null;
    useAlert('Ficha removida.');
  }
};

// evolução por exercício (carga máxima da 1ª série efetiva por treino)
const evoExercise = ref('');
const exerciseOptions = computed(() => {
  const names = new Set();
  programs.value.forEach(p =>
    (p.cycles || []).forEach(c =>
      (c.sessions || []).forEach(s => (s.exercises || []).forEach(ex => ex.name && names.add(ex.name)))
    )
  );
  plans.value.forEach(p => (p.exercises || []).forEach(ex => ex.name && names.add(ex.name)));
  workouts.value.forEach(w => (w.data?.exercises || []).forEach(ex => ex.name && names.add(ex.name)));
  return [...names].sort();
});
const evoSeries = computed(() => {
  if (!evoExercise.value) return { values: [], labels: [] };
  const points = [...workouts.value]
    .reverse()
    .map(w => {
      const ex = (w.data?.exercises || []).find(e => e.name === evoExercise.value);
      if (!ex?.sets?.length) return null;
      const max = Math.max(...ex.sets.map(s => Number(s.load) || 0));
      return { date: w.record_date, max };
    })
    .filter(Boolean)
    .slice(-15);
  return {
    values: points.map(p => p.max),
    labels: points.map(p => fmtDay(p.date)),
  };
});

const workoutSummary = w => {
  const exs = w.data?.exercises || [];
  const names = exs.map(e => e.name).slice(0, 3).join(' · ');
  return exs.length > 3 ? `${names} +${exs.length - 3}` : names || '—';
};

const VERDICT_CHIPS = {
  progress: { label: '▲', color: '#059669', title: 'progrediu' },
  tie: { label: '▬', color: '#94A3B8', title: 'empatou' },
  regress: { label: '▼', color: '#DC2626', title: 'regrediu' },
};

// ═══ DIETA ══════════════════════════════════════════════════════════
// dia selecionado (dá pra voltar e registrar dias passados)
const dietDate = ref(todayISO);
const dietToday = computed(() => diets.value.find(d => d.record_date === dietDate.value));
const mealsDone = computed(() => dietToday.value?.data?.meals_done || []);
// horário REAL em que cada refeição foi marcada (dashboard usa isso)
const mealsDoneAt = computed(() => dietToday.value?.data?.meals_done_at || {});
const dietExtras = computed(() => dietToday.value?.data?.extras || []);
const savingDiet = ref(false);

const saveDietDay = async data => {
  savingDiet.value = true;
  try {
    const { data: rec } = await CrmAPI.createHealthRecord({
      kind: 'diet',
      record_date: dietDate.value || todayISO,
      data,
    });
    diets.value = sortRecs([rec, ...diets.value.filter(d => d.id !== rec.id)]);
  } catch {
    useAlert('Não consegui salvar o dia.');
  } finally {
    savingDiet.value = false;
  }
};

const toggleMeal = mealId => {
  const marcando = !mealsDone.value.includes(mealId);
  const done = marcando
    ? [...mealsDone.value, mealId]
    : mealsDone.value.filter(id => id !== mealId);
  const at = { ...mealsDoneAt.value };
  if (marcando && dietDate.value === todayISO) {
    // horário real só vale pro dia de HOJE; dia passado fica com o do plano
    const now = new Date();
    at[mealId] = `${pad2(now.getHours())}:${pad2(now.getMinutes())}`;
  } else if (!marcando) {
    delete at[mealId];
  }
  saveDietDay({ meals_done: done, meals_done_at: at, extras: dietExtras.value });
};

const extraForm = ref({ name: '', kcal: '', protein: '', carbs: '', fat: '' });
const addExtra = () => {
  if (!extraForm.value.name.trim()) return;
  const extra = {
    name: extraForm.value.name.trim(),
    kcal: toNum(extraForm.value.kcal),
    protein: toNum(extraForm.value.protein),
    carbs: toNum(extraForm.value.carbs),
    fat: toNum(extraForm.value.fat),
  };
  saveDietDay({
    meals_done: mealsDone.value,
    meals_done_at: mealsDoneAt.value,
    extras: [...dietExtras.value, extra],
  });
  extraForm.value = { name: '', kcal: '', protein: '', carbs: '', fat: '' };
};
const removeExtra = i => {
  const extras = dietExtras.value.filter((_, idx) => idx !== i);
  saveDietDay({ meals_done: mealsDone.value, meals_done_at: mealsDoneAt.value, extras });
};

const dayTotals = computed(() => {
  const totals = { kcal: 0, protein: 0, carbs: 0, fat: 0 };
  dietCfg.value.meals
    .filter(m => mealsDone.value.includes(m.id))
    .concat(dietExtras.value)
    .forEach(m => {
      totals.kcal += Number(m.kcal) || 0;
      totals.protein += Number(m.protein) || 0;
      totals.carbs += Number(m.carbs) || 0;
      totals.fat += Number(m.fat) || 0;
    });
  return totals;
});
const MACROS = [
  { key: 'kcal', label: 'Calorias', suffix: ' kcal', cor: OURO },
  { key: 'protein', label: 'Proteína', suffix: 'g', cor: VERDE },
  { key: 'carbs', label: 'Carbo', suffix: 'g', cor: AZUL },
  { key: 'fat', label: 'Gordura', suffix: 'g', cor: ROSA },
];
const macroPct = key => {
  const target = Number(dietCfg.value.targets?.[key]) || 0;
  if (!target) return 0;
  return Math.min(100, Math.round((dayTotals.value[key] / target) * 100));
};

// plano alimentar + metas (config)
const dietForm = ref(null);
const openDietEditor = () => {
  dietForm.value = JSON.parse(
    JSON.stringify({
      targets: { kcal: 0, protein: 0, carbs: 0, fat: 0, ...dietCfg.value.targets },
      notes: dietCfg.value.notes,
      meals: dietCfg.value.meals.length
        ? dietCfg.value.meals
        : [{ id: '', name: '', time: '', desc: '', kcal: 0, protein: 0, carbs: 0, fat: 0 }],
    })
  );
};
const addMeal = () =>
  dietForm.value.meals.push({ id: '', name: '', time: '', desc: '', kcal: 0, protein: 0, carbs: 0, fat: 0 });
const removeMeal = i => dietForm.value.meals.splice(i, 1);

// ═══ METAS CALCULADAS (rodada 14) ═══════════════════════════════════
// Passou as CALORIAS → o resto sai do método: proteína 1,8 g/kg do peso
// atual (cutting Warrior), gordura 25% das kcal, carbo com o que sobra;
// e as refeições recebem a divisão proporcional às kcal que já têm
// (sem kcal ainda = divisão igual). Tudo continua editável depois.
const pesoAtual = () =>
  Number(bodies.value.find(b => Number(b.data?.weight) > 0)?.data?.weight) || 0;
const autoTargets = kcal => {
  const k = Number(kcal) || 0;
  if (!k) return null;
  const peso = pesoAtual();
  const protein = peso ? Math.round(peso * 1.8) : Math.round((k * 0.3) / 4);
  const fat = Math.round((k * 0.25) / 9);
  const carbs = Math.max(0, Math.round((k - protein * 4 - fat * 9) / 4));
  return { protein, fat, carbs };
};
const splitMeals = () => {
  const f = dietForm.value;
  if (!f?.meals?.length) return;
  const k = Number(f.targets.kcal) || 0;
  if (!k) return;
  const kcals = f.meals.map(m => Number(m.kcal) || 0);
  const total = kcals.reduce((a, b) => a + b, 0);
  const shares = total
    ? kcals.map(v => v / total)
    : f.meals.map(() => 1 / f.meals.length);
  f.meals.forEach((m, i) => {
    m.kcal = Math.round((k * shares[i]) / 5) * 5;
    m.protein = Math.round(Number(f.targets.protein) * shares[i]);
    m.carbs = Math.round(Number(f.targets.carbs) * shares[i]);
    m.fat = Math.round(Number(f.targets.fat) * shares[i]);
  });
};
// digitou as kcal no editor → recalcula macros e refeições sozinho
watch(
  () => dietForm.value?.targets?.kcal,
  (kcal, old) => {
    if (!dietForm.value || old === undefined || String(kcal) === String(old)) return;
    const t = autoTargets(kcal);
    if (!t) return;
    dietForm.value.targets.protein = t.protein;
    dietForm.value.targets.carbs = t.carbs;
    dietForm.value.targets.fat = t.fat;
    splitMeals();
  }
);

// equivalência PRÁTICA da proteína da refeição em comida crua
// (frango cru ~23 g/100 g · patinho cru ~21 g/100 g · ovo ~6 g/un)
const mealEquiv = meal => {
  const p = Number(meal.protein) || 0;
  if (!p) return '';
  const frango = Math.round(p / 0.23 / 10) * 10;
  const carne = Math.round(p / 0.21 / 10) * 10;
  const ovos = Math.ceil(p / 6);
  return `≈ ${frango} g de frango cru · ${carne} g de patinho cru · ${ovos} ovos`;
};
const saveDietCfg = async () => {
  dietForm.value.meals = dietForm.value.meals.filter(m => m.name?.trim());
  const ok = await pushConfig({ ...config.value, diet: dietForm.value });
  if (ok) {
    dietForm.value = null;
    useAlert('Plano alimentar salvo.');
  }
};

const dietDayPct = d => {
  const total = dietCfg.value.meals.length || 1;
  const done = (d.data?.meals_done || []).length;
  return Math.round((done / total) * 100);
};

// ═══ CORPO ══════════════════════════════════════════════════════════
// Protocolo oficial do Guilherme (26/08): braço RELAXADO, coxa no meio
// entre virilha e joelho, cintura após expiração normal sem encolher,
// pescoço abaixo do pomo de Adão sem apertar.
const MEASURES = [
  // step/max alimentam a roleta (rodada 12): peso fino de 0,1 em 0,1 kg;
  // circunferências de 0,5 em 0,5 cm até 220 (teto fixo, sem infinito)
  { key: 'weight', label: 'Peso', suffix: ' kg', step: 0.1, max: 200 },
  { key: 'waist_navel', label: 'Cintura (umbigo)', suffix: ' cm', step: 0.1, max: 220 },
  { key: 'waist_narrow', label: 'Cintura estreita', suffix: ' cm', step: 0.1, max: 220 },
  { key: 'hips', label: 'Quadril', suffix: ' cm', step: 0.1, max: 220 },
  { key: 'chest', label: 'Peito/tórax', suffix: ' cm', step: 0.1, max: 220 },
  { key: 'arm_r', label: 'Braço D', suffix: ' cm', step: 0.1, max: 220 },
  { key: 'arm_l', label: 'Braço E', suffix: ' cm', step: 0.1, max: 220 },
  { key: 'thigh_r', label: 'Coxa D', suffix: ' cm', step: 0.1, max: 220 },
  { key: 'thigh_l', label: 'Coxa E', suffix: ' cm', step: 0.1, max: 220 },
  { key: 'neck', label: 'Pescoço', suffix: ' cm', step: 0.1, max: 220 },
  { key: 'shoulders', label: 'Ombros (escapular)', suffix: ' cm', step: 0.1, max: 220 },
];
const bodyForm = ref({
  date: todayISO,
  notes: '',
  ...Object.fromEntries(MEASURES.map(m => [m.key, ''])),
});
const savingBody = ref(false);

// última medição de cada medida (chip embaixo da roleta — tocar posiciona
// a roleta no valor da última vez, aí é só o ajuste fino)
const lastBodyValue = key => {
  const rec = bodies.value.find(b => b.data?.[key] !== undefined && b.data?.[key] !== null && b.data?.[key] !== '');
  return rec ? rec.data[key] : null;
};
const copyLastBody = key => {
  const v = lastBodyValue(key);
  if (v !== null) bodyForm.value[key] = String(v).replace('.', ',');
};

const saveBody = async () => {
  const data = {};
  MEASURES.forEach(m => {
    const v = toNum(bodyForm.value[m.key]);
    if (v > 0) data[m.key] = v;
  });
  if (bodyForm.value.notes?.trim()) data.notes = bodyForm.value.notes.trim();
  if (!Object.keys(data).length) {
    useAlert('Preencha ao menos uma medida.');
    return;
  }
  savingBody.value = true;
  try {
    const { data: rec } = await CrmAPI.createHealthRecord({
      kind: 'body',
      record_date: bodyForm.value.date || todayISO,
      data,
    });
    bodies.value = sortRecs([rec, ...bodies.value.filter(b => b.id !== rec.id)]);
    useAlert('📏 Medidas registradas.');
  } catch {
    useAlert('Não consegui salvar as medidas.');
  } finally {
    savingBody.value = false;
  }
};

const weightSeries = computed(() => {
  const points = [...bodies.value]
    .filter(b => Number(b.data?.weight) > 0)
    .sort((a, b) => (a.record_date > b.record_date ? 1 : -1))
    .slice(-20);
  return {
    values: points.map(p => Number(p.data.weight)),
    labels: points.map(p => fmtDay(p.record_date)),
  };
});

// última medida de cada campo + variação contra a anterior
const currentMeasures = computed(() =>
  MEASURES.map(m => {
    const withValue = bodies.value.filter(b => Number(b.data?.[m.key]) > 0);
    if (!withValue.length) return { ...m, value: null, delta: null };
    const value = Number(withValue[0].data[m.key]);
    const prev = withValue[1] ? Number(withValue[1].data[m.key]) : null;
    return { ...m, value, delta: prev === null ? null : value - prev };
  })
);

const deleteRecord = async record => {
  try {
    await CrmAPI.deleteHealthRecord(record.id);
    if (record.kind === 'workout') workouts.value = workouts.value.filter(w => w.id !== record.id);
    if (record.kind === 'boxing') boxings.value = boxings.value.filter(b => b.id !== record.id);
    if (record.kind === 'diet') diets.value = diets.value.filter(d => d.id !== record.id);
    if (record.kind === 'body') bodies.value = bodies.value.filter(b => b.id !== record.id);
    useAlert('Registro removido.');
  } catch {
    useAlert('Não consegui remover.');
  }
};

// ── carga inicial ───────────────────────────────────────────────────
onMounted(async () => {
  try {
    const { data: payload } = await CrmAPI.getHealth();
    config.value = payload.config || {};
    workouts.value = payload.workouts || [];
    boxings.value = payload.boxings || [];
    diets.value = payload.diets || [];
    bodies.value = payload.bodies || [];
    const latest = bodies.value[0]?.data || {};
    MEASURES.forEach(m => {
      if (latest[m.key]) bodyForm.value[m.key] = latest[m.key];
    });
  } catch {
    useAlert('Não consegui carregar o painel de saúde.');
  } finally {
    isLoading.value = false;
  }
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1" :class="{ 'hub-snap': session }">
    <div class="max-w-5xl mx-auto w-full p-4 sm:p-8">
      <!-- Header -->
      <div class="flex items-center gap-3 flex-wrap mb-5">
        <span
          class="w-9 h-9 rounded-xl flex items-center justify-center"
          :style="{ background: `linear-gradient(135deg, ${VERDE_ESCURO}, ${VERDE})` }"
        >
          <span class="i-lucide-heart-pulse text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-lg font-bold text-n-slate-12">Saúde</h1>
          <p class="text-xs text-n-slate-10">treino · dieta · corpo — seu painel pessoal</p>
        </div>
      </div>

      <div v-if="isLoading" class="flex justify-center py-16"><Spinner /></div>

      <template v-else>
        <!-- KPIs -->
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5">
          <DashKpi label="Treinos (7 dias)" :value="treinos7" sub="últimos 7 dias" :from="VERDE_ESCURO" :to="VERDE" />
          <DashKpi
            label="Sequência"
            :value="streak"
            :sub="streak === 1 ? 'dia seguido' : 'dias seguidos'"
            :from="'#92400E'"
            :to="OURO"
          />
          <DashKpi
            label="Peso atual"
            :value="latestWeight === null ? '—' : `${fmtNum(latestWeight)} kg`"
            sub="última medição"
            :from="'#0B4A82'"
            :to="AZUL"
          />
          <DashKpi
            label="Variação (30d)"
            :value="weightDelta30 === null ? '—' : `${weightDelta30 > 0 ? '+' : ''}${fmtNum(weightDelta30)} kg`"
            sub="peso vs 30 dias atrás"
            :from="'#5B21B6'"
            :to="ROXO"
          />
        </div>

        <!-- Pílulas de aba -->
        <div class="flex gap-2 mb-5 flex-wrap">
          <button
            v-for="t in TABS"
            :key="t.key"
            class="h-9 px-4 rounded-full text-xs font-bold flex items-center gap-1.5 border"
            :class="tab === t.key ? 'text-white border-transparent' : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
            :style="tab === t.key ? { background: `linear-gradient(135deg, ${VERDE_ESCURO}, ${VERDE})` } : {}"
            @click="goTab(t.key)"
          >
            <span :class="t.icon" /> {{ t.label }}
          </button>
        </div>

        <!-- ═══ TREINO ═══ -->
        <template v-if="tab === 'treino'">
          <!-- Programa ativo (Warrior) -->
          <div v-if="program && !session" class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <div class="flex items-center justify-between flex-wrap gap-2 mb-1">
              <h2 class="text-sm font-bold text-n-slate-12">🏋️ {{ program.name }}</h2>
              <div v-if="programs.length > 1" class="flex gap-1.5">
                <button
                  v-for="p in programs"
                  :key="p.id"
                  class="h-7 px-2.5 rounded-full text-[11px] font-medium border"
                  :class="p.active ? 'text-white border-transparent' : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
                  :style="p.active ? { background: VERDE } : {}"
                  @click="setActiveProgram(p)"
                >
                  {{ p.id === 'warrior24' ? '24 semanas' : 'Rotina Bônus' }}
                </button>
              </div>
            </div>
            <p class="text-xs text-n-slate-10 mb-3">
              <template v-if="programWeek">
                Semana <b>{{ Math.min(programWeek, totalWeeks) }}</b> de {{ totalWeeks }} ·
              </template>
              {{ programCycle?.name }} — {{ programCycle?.focus }}
              <template v-if="program.note"> · {{ program.note }}</template>
            </p>
            <div class="flex gap-2 flex-wrap">
              <div
                v-for="s in programCycle?.sessions || []"
                :key="s.key"
                class="flex items-center gap-1"
              >
                <button
                  class="h-11 px-4 rounded-xl text-xs font-bold flex items-center gap-2 border"
                  :class="s.key === nextKey ? 'text-white border-transparent' : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
                  :style="s.key === nextKey ? { background: `linear-gradient(135deg, ${VERDE_ESCURO}, ${VERDE})` } : {}"
                  @click="startProgramSession(s)"
                >
                  <span class="i-lucide-play" />
                  Treino {{ s.key }}
                  <span class="font-normal opacity-80">· {{ s.weekday }}</span>
                  <span v-if="s.key === nextKey" class="text-[10px] font-normal opacity-90">▶ próximo</span>
                </button>
                <button
                  class="h-11 w-8 rounded-xl text-sm text-n-slate-10 border border-n-weak hover:bg-n-alpha-1"
                  title="Editar exercícios deste treino (adicionar, substituir, variação)"
                  @click="openExerciseEditor(s)"
                >
                  ✎
                </button>
              </div>
            </div>
          </div>

          <!-- Editor de exercícios da prescrição -->
          <div v-if="exEditor" class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <div class="flex items-center justify-between gap-2 flex-wrap mb-1">
              <span class="text-sm font-bold" :style="{ color: VERDE }">✎ {{ exEditor.title }}</span>
              <button
                class="h-8 px-3 rounded-lg text-xs text-n-slate-11 border border-n-weak hover:bg-n-alpha-1"
                @click="exEditor = null"
              >
                Cancelar
              </button>
            </div>
            <p class="text-[11px] text-n-slate-10 mb-3">
              <b>Variação</b> = o jeito que você faz (halteres, barra, máquina…). Preenchendo
              <b>A e B</b>, o treino ganha uma <b>chavinha A ⇄ B</b> — cada variação guarda as
              próprias cargas. <b>Renomear</b> vale como substituição: o exercício novo começa
              histórico do zero.
            </p>
            <div class="flex flex-col gap-2 mb-3">
              <div
                v-for="(row, i) in exEditor.rows"
                :key="i"
                class="flex items-center gap-1.5 flex-wrap rounded-xl border border-n-weak p-2"
                :class="row._del ? 'opacity-40' : ''"
              >
                <input
                  v-model="row.name"
                  type="text"
                  placeholder="Nome do exercício"
                  class="h-9 flex-1 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                  style="min-width: 11rem; margin-bottom: 0"
                />
                <input
                  v-model="row.tag"
                  type="text"
                  placeholder="variação A (ex.: halteres)"
                  class="h-9 rounded-lg border border-dashed border-n-weak bg-n-solid-2 px-2 text-[11px] text-n-slate-11"
                  style="width: 9rem; margin-bottom: 0"
                />
                <input
                  v-model="row.alt_tag"
                  type="text"
                  placeholder="variação B (ex.: barra)"
                  title="Preenchendo as duas variações, o treino ganha a chavinha A ⇄ B"
                  class="h-9 rounded-lg border border-dashed border-n-weak bg-n-solid-2 px-2 text-[11px] text-n-slate-11"
                  style="width: 9rem; margin-bottom: 0"
                />
                <span class="text-[10px] text-n-slate-10">{{ row.scheme }}</span>
                <button
                  class="h-9 w-8 rounded-lg text-n-slate-10 hover:bg-n-alpha-1"
                  :title="row._del ? 'Desfazer remoção' : 'Remover deste treino'"
                  @click="row._del = !row._del"
                >
                  {{ row._del ? '↩' : '🗑' }}
                </button>
              </div>
            </div>
            <div class="flex gap-2 flex-wrap">
              <button
                class="h-9 px-3 rounded-lg text-xs font-medium text-n-slate-11 border border-n-weak hover:bg-n-alpha-1"
                @click="addEditorExercise"
              >
                + adicionar exercício
              </button>
              <button
                class="h-9 px-4 rounded-lg text-xs font-bold text-white disabled:opacity-60"
                :style="{ background: `linear-gradient(135deg, ${VERDE_ESCURO}, ${VERDE})` }"
                :disabled="savingConfig"
                @click="saveExerciseEditor"
              >
                {{ savingConfig ? 'Salvando…' : '✓ Salvar treino' }}
              </button>
            </div>
          </div>

          <!-- Sessão em andamento -->
          <div v-if="session" class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <div class="flex items-center justify-between gap-2 flex-wrap mb-2">
              <span class="text-sm font-bold" :style="{ color: VERDE }">{{ session.plan_name }}</span>
              <button
                class="h-8 px-3 rounded-lg text-xs text-n-slate-11 border border-n-weak hover:bg-n-alpha-1"
                @click="session = null"
              >
                Cancelar
              </button>
            </div>

            <!-- Data em destaque: registro retroativo muda a semana junto -->
            <div class="flex items-center gap-2 flex-wrap mb-3 rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2">
              <span class="text-[11px] font-medium text-n-slate-11">📅 Data do treino</span>
              <input
                v-model="session.date"
                type="date"
                class="h-9 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-xs text-n-slate-12"
                style="width: 9.5rem; margin-bottom: 0"
              />
              <span
                v-if="session.mode === 'program' && session.week"
                class="px-2 py-0.5 rounded-full text-[10px] font-bold text-white"
                :style="{ background: VERDE }"
              >
                Semana {{ session.week }}
              </span>
              <span class="text-[10px] text-n-slate-10">treinou outro dia? troque a data</span>
            </div>

            <p class="text-[11px] text-n-slate-10 mb-3">
              <b>Role as roletas</b> até o valor de hoje: <b>carga (kg) × repetições</b> — elas
              já vêm na última execução. O chip cinza ao lado é o da <b>última vez</b>;
              tocar nele traz a roleta de volta pra esse valor.
            </p>

            <!-- 1 exercício ≈ 1 tela no celular (pedido 30/08): o card
                 ocupa ~80% do viewport e o scroll "trava" nele — a tela
                 fica parada no exercício durante o treino -->
            <div v-for="ex in session.exercises" :key="ex.name" class="hub-ex-card mb-5 rounded-2xl border border-n-weak p-4 sm:p-5">
              <div class="flex items-start justify-between gap-2 mb-1">
                <h3 class="text-lg font-extrabold leading-snug text-n-slate-12">
                  {{ ex.name }}
                  <span
                    v-if="ex.extra"
                    class="ml-1 px-1.5 py-0.5 rounded-full text-[10px] font-bold border border-dashed align-middle"
                    :style="{ color: OURO, borderColor: OURO }"
                  >
                    extra
                  </span>
                </h3>
                <button
                  v-if="ex.extra"
                  class="w-6 h-6 rounded-lg text-n-slate-10 hover:bg-n-alpha-1 shrink-0"
                  title="Tirar este exercício extra do treino de hoje"
                  @click="removeExtraExercise(ex)"
                >
                  ✕
                </button>
              </div>
              <div class="flex items-center gap-2 flex-wrap mb-2">
                <!-- chavinha de variação (halteres ⇄ barra): troca o
                     equipamento de HOJE e re-prefill com a última
                     execução daquela variação -->
                <span v-if="ex.altTag" class="hub-switch">
                  <button
                    v-for="t in [ex.baseTag, ex.altTag]"
                    :key="t"
                    class="hub-switch-opt"
                    :class="{ 'is-on': normTag(ex.tag) === normTag(t) }"
                    :style="normTag(ex.tag) === normTag(t) ? { background: VERDE } : {}"
                    @click="switchVariation(ex, t)"
                  >
                    {{ t }}
                  </button>
                </span>
                <span
                  v-else-if="ex.tag"
                  class="px-2 py-0.5 rounded-full text-[10px] font-medium border border-dashed border-n-weak text-n-slate-10"
                >
                  {{ ex.tag }}
                </span>
                <span
                  v-if="ex.method"
                  class="px-1.5 py-0.5 rounded text-[10px] font-bold text-white"
                  :style="{ background: ex.method === 'rest_pause' ? ROXO : ex.method === 'pyramid' ? OURO : AZUL }"
                  :title="METHOD_HINTS[ex.method]"
                >
                  {{ METHOD_LABELS[ex.method] || ex.method }}
                </span>
                <span class="text-[11px] text-n-slate-10">{{ ex.scheme }}</span>
              </div>
              <p v-if="ex.rest || ex.warmup" class="text-[11px] text-n-slate-10 mb-2.5">
                <template v-if="ex.rest">⏱ descanso {{ ex.rest }}</template>
                <template v-if="ex.rest && ex.warmup"> · </template>
                <template v-if="ex.warmup">🔥 aquecimento: {{ ex.warmup }}</template>
              </p>
              <!-- cartão de vidro: a meta de hoje + alvo POR SÉRIE
                   (tocar num alvo posiciona as roletas da série) -->
              <div
                v-if="ex.hint || ex.targets?.length"
                class="hub-glass rounded-xl px-3 py-3 mb-4"
                :class="{ 'hub-glass-gold': ex.hint?.startsWith('🎯') }"
              >
                <p
                  v-if="ex.hint"
                  class="text-xs font-medium"
                  :class="ex.targets?.length ? 'mb-2' : ''"
                  :style="{ color: ex.hint.startsWith('🎯') ? OURO : VERDE }"
                >
                  {{ ex.hint }}
                </p>
                <div v-if="ex.targets?.length" class="flex gap-1.5 flex-wrap">
                  <button
                    v-for="(t, ti) in ex.targets"
                    :key="ti"
                    class="hub-target-chip"
                    :disabled="t.load === null || t.load === undefined"
                    :title="t.load != null ? 'Toque pra levar as roletas da série até a meta' : 'Faixa da prescrição'"
                    @click="applyTarget(ex, ti)"
                  >
                    <span class="opacity-60">{{ t.label }}</span>
                    <b>{{ t.load != null ? fmtTarget(t) : t.reps }}</b>
                  </button>
                </div>
              </div>

              <!-- série: rótulo + chip à esquerda, roletas GRANDES
                   ancoradas à direita (pedido 30/08) -->
              <div class="flex flex-col gap-3">
                <div v-for="(set, i) in ex.sets" :key="i" class="flex items-center justify-between gap-2">
                  <div class="flex flex-col items-start gap-1 min-w-0">
                    <span class="flex items-center gap-1.5 text-xs font-bold text-n-slate-11">
                      {{ SET_LABELS(ex.method, i) }}
                      <button
                        class="w-4 h-4 rounded text-[10px] text-n-slate-10 hover:bg-n-alpha-1 opacity-60"
                        title="Remover série"
                        @click="removeSet(ex, i)"
                      >
                        ✕
                      </button>
                    </span>
                    <button
                      v-if="set.prev"
                      class="h-8 px-2 rounded-lg text-[11px] text-n-slate-10 bg-n-alpha-1 hover:bg-n-alpha-2 border border-dashed border-n-weak whitespace-nowrap"
                      title="Foi isso na última vez — toque pra voltar a roleta pra esse valor"
                      @click="copyPrev(set)"
                    >
                      {{ fmtPrev(set.prev) }}⤵
                    </button>
                    <span v-else class="text-[10px] text-n-slate-10">1ª vez</span>
                  </div>
                  <div class="flex items-center gap-2 shrink-0">
                    <WheelInput
                      v-model="set.load"
                      :step="0.5"
                      :max="200"
                      decimal
                      :placeholder="set.prev ? String(set.prev.load).replace('.', ',') : 'kg'"
                      style="width: 5rem"
                    />
                    <span class="text-base text-n-slate-10">×</span>
                    <WheelInput
                      v-model="set.reps"
                      :step="1"
                      :max="30"
                      :placeholder="set.prev ? String(set.prev.reps) : set.range || 'reps'"
                      style="width: 3.6rem"
                    />
                  </div>
                </div>
              </div>
              <button
                class="mt-4 h-9 px-3.5 rounded-xl text-xs font-medium text-n-slate-11 border border-n-weak hover:bg-n-alpha-1"
                @click="addSet(ex)"
              >
                + série
              </button>
            </div>

            <!-- Exercício extra do dia (rodada 11): entra na sessão e salva
                 junto no histórico, marcado como "extra" -->
            <div class="mb-3">
              <button
                v-if="!extraOpen"
                class="w-full h-9 rounded-xl text-xs font-medium text-n-slate-11 border border-dashed border-n-weak hover:bg-n-alpha-1"
                @click="extraOpen = true"
              >
                ➕ Adicionar exercício extra no treino de hoje
              </button>
              <div
                v-else
                class="rounded-xl border border-dashed border-n-weak p-3 flex items-center gap-2 flex-wrap"
              >
                <input
                  v-model="extraName"
                  type="text"
                  list="hub-extra-exercicios"
                  placeholder="Ex.: Crucifixo na máquina, Panturrilha em pé…"
                  class="flex-1 h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                  style="min-width: 12rem; margin-bottom: 0"
                  @keyup.enter="addExtraExercise"
                />
                <datalist id="hub-extra-exercicios">
                  <option v-for="n in extraSuggestions" :key="n" :value="n" />
                </datalist>
                <button
                  class="h-9 px-3 rounded-lg text-xs font-bold text-white disabled:opacity-60"
                  :style="{ background: `linear-gradient(135deg, ${VERDE_ESCURO}, ${VERDE})` }"
                  :disabled="!extraName.trim()"
                  @click="addExtraExercise"
                >
                  Adicionar
                </button>
                <button
                  class="h-9 px-2 rounded-lg text-xs text-n-slate-10 border border-n-weak hover:bg-n-alpha-1"
                  @click="extraOpen = false; extraName = ''"
                >
                  ✕
                </button>
              </div>
            </div>

            <input
              v-model="session.notes"
              type="text"
              placeholder="Observações (ex.: dor no ombro, treino rápido…)"
              class="block w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
              style="margin-bottom: 12px"
            />
            <button
              class="w-full h-11 rounded-xl text-sm font-bold text-white disabled:opacity-60"
              :style="{ background: `linear-gradient(135deg, ${VERDE_ESCURO}, ${VERDE})` }"
              :disabled="savingSession"
              @click="saveSession"
            >
              {{ savingSession ? 'Salvando…' : '✓ Concluir treino' }}
            </button>
          </div>

          <!-- Planilha das semanas: A | B | C | Bônus -->
          <div v-if="gridTabs.length && !session" class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <div class="flex items-center justify-between flex-wrap gap-2 mb-2">
              <h2 class="text-sm font-bold text-n-slate-12">📋 Planilha das semanas</h2>
              <div class="flex gap-1.5 flex-wrap">
                <button
                  v-for="t in gridTabs"
                  :key="t.key"
                  class="h-9 px-3 rounded-lg text-xs font-bold border"
                  :class="gridTab?.key === t.key ? 'text-white border-transparent' : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
                  :style="gridTab?.key === t.key ? { background: `linear-gradient(135deg, ${VERDE_ESCURO}, ${VERDE})` } : {}"
                  @click="gridCycleKey = t.key"
                >
                  {{ t.label }} <span class="font-normal opacity-75 text-[10px]">{{ t.sub }}</span>
                </button>
              </div>
            </div>
            <p class="text-[11px] text-n-slate-10 mb-3">
              Preencha a semana com carga×reps de cada série, separadas por espaço — ex.:
              <b>60x6 54x7 48x8</b> (vírgula vale: 62,5x8). Salva sozinho ao sair da lacuna.
            </p>
            <div class="overflow-x-auto">
              <table class="border-collapse" style="min-width: 100%">
                <thead>
                  <tr>
                    <th
                      class="sticky left-0 z-10 bg-n-solid-1 text-left text-[11px] font-bold text-n-slate-11 px-2 py-1.5 border-b border-n-weak"
                      style="min-width: 13rem"
                    >
                      Exercício
                    </th>
                    <th
                      v-for="w in gridWeeks"
                      :key="w"
                      class="text-center text-[11px] font-bold px-1 py-1.5 border-b border-n-weak"
                      :class="gridTab?.programId === 'warrior24' && w === programWeek ? '' : 'text-n-slate-11'"
                      :style="gridTab?.programId === 'warrior24' && w === programWeek ? { color: VERDE } : {}"
                    >
                      S{{ w }}
                      <span v-if="gridTab?.programId === 'warrior24' && w === programWeek">•</span>
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <template v-for="s in gridTab?.cycle?.sessions || []" :key="s.key">
                    <tr>
                      <td
                        :colspan="gridWeeks.length + 1"
                        class="text-[11px] font-bold text-n-slate-12 px-2 pt-3 pb-1"
                      >
                        🏋️ Treino {{ s.key }} <span class="font-normal text-n-slate-10">· {{ s.weekday }}</span>
                      </td>
                    </tr>
                    <tr v-for="ex in s.exercises" :key="`${s.key}-${ex.name}`" class="border-b border-n-weak/60">
                      <td class="sticky left-0 z-10 bg-n-solid-1 px-2 py-1.5" style="min-width: 13rem">
                        <p class="text-[11px] font-medium text-n-slate-12 leading-tight">
                          {{ ex.name }}
                          <span v-if="ex.tag" class="text-[9px] font-normal text-n-slate-10">· {{ ex.tag }}</span>
                        </p>
                        <p class="text-[10px] text-n-slate-10">{{ ex.scheme }}</p>
                      </td>
                      <td v-for="w in gridWeeks" :key="w" class="px-0.5 py-1">
                        <input
                          type="text"
                          :value="gridDrafts[gridKey(s.key, w, ex.name)] !== undefined ? gridDrafts[gridKey(s.key, w, ex.name)] : cellText(s.key, w, ex.name)"
                          placeholder="—"
                          class="h-8 rounded-md border border-n-weak bg-n-solid-2 px-1.5 text-[11px] text-n-slate-12 text-center"
                          style="width: 7.5rem; margin-bottom: 0"
                          @input="gridDrafts[gridKey(s.key, w, ex.name)] = $event.target.value"
                          @blur="saveCell(s, w, ex.name)"
                          @keyup.enter="$event.target.blur()"
                        />
                      </td>
                    </tr>
                  </template>
                </tbody>
              </table>
            </div>
          </div>

          <!-- Evolução -->
          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <div class="flex items-center justify-between mb-3 flex-wrap gap-2">
              <h2 class="text-sm font-bold text-n-slate-12">📈 Evolução de carga</h2>
              <select
                v-model="evoExercise"
                class="h-9 rounded-lg border border-n-weak px-2 text-xs text-n-slate-12"
                style="width: 16rem; margin-bottom: 0; border: 1px solid rgba(148, 163, 184, 0.35); background-color: transparent"
              >
                <option value="">Escolha o exercício…</option>
                <option v-for="name in exerciseOptions" :key="name" :value="name">{{ name }}</option>
              </select>
            </div>
            <MiniBars
              v-if="evoSeries.values.length"
              :values="evoSeries.values"
              :labels="evoSeries.labels"
              :color="VERDE"
              :height="110"
              :format="v => `${fmtNum(v)} kg`"
            />
            <p v-else class="text-xs text-n-slate-10">
              Escolha um exercício com treinos registrados pra ver a carga máxima por sessão.
            </p>
          </div>

          <!-- Histórico -->
          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-3">🗓 Últimos treinos</h2>
            <p v-if="!workouts.length" class="text-xs text-n-slate-10">Nenhum treino registrado ainda.</p>
            <div
              v-for="w in workouts.slice(0, 8)"
              :key="w.id"
              class="flex items-center gap-3 py-2 border-b border-n-weak last:border-0"
            >
              <span
                class="w-8 h-8 rounded-lg flex items-center justify-center text-white text-[10px] font-bold shrink-0"
                :style="{ background: `linear-gradient(135deg, ${VERDE_ESCURO}, ${VERDE})` }"
              >
                {{ fmtDay(w.record_date) }}
              </span>
              <div class="flex-1 min-w-0">
                <p class="text-xs font-bold text-n-slate-12 truncate">
                  {{ w.data?.plan_name || 'Treino' }}
                  <span v-if="w.data?.week" class="font-normal text-n-slate-10">· sem. {{ w.data.week }}</span>
                </p>
                <p class="text-[11px] text-n-slate-10 truncate">{{ workoutSummary(w) }}</p>
              </div>
              <span v-if="w.data?.summary" class="flex items-center gap-1 shrink-0 text-[11px] font-bold">
                <span
                  v-for="(chip, verdictKey) in VERDICT_CHIPS"
                  :key="verdictKey"
                  v-show="w.data.summary[verdictKey]"
                  :style="{ color: chip.color }"
                  :title="chip.title"
                >
                  {{ chip.label }}{{ w.data.summary[verdictKey] }}
                </span>
              </span>
              <button
                class="w-7 h-7 rounded-lg text-n-slate-10 hover:bg-n-alpha-1 shrink-0"
                title="Remover"
                @click="deleteRecord(w)"
              >
                ✕
              </button>
            </div>
          </div>

          <!-- Fichas avulsas (fora do programa) -->
          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4">
            <div class="flex items-center justify-between">
              <button class="text-sm font-bold text-n-slate-12" @click="showFichas = !showFichas">
                {{ showFichas ? '▾' : '▸' }} 📝 Fichas avulsas
              </button>
              <button
                v-if="showFichas"
                class="h-8 px-3 rounded-lg text-xs font-medium text-n-slate-11 border border-n-weak hover:bg-n-alpha-1"
                @click="openNewPlan"
              >
                + Nova ficha
              </button>
            </div>
            <template v-if="showFichas">
              <p class="text-[11px] text-n-slate-10 mt-1 mb-3">
                Treinos fora do programa (cardio, mobilidade, treino de viagem…).
              </p>
              <div v-if="!session" class="flex gap-2 flex-wrap mb-2">
                <button
                  v-for="plan in plans"
                  :key="plan.id"
                  class="h-9 px-3 rounded-xl text-xs font-bold text-white flex items-center gap-2"
                  :style="{ background: `linear-gradient(135deg, #475569, #64748B)` }"
                  @click="startSession(plan)"
                >
                  <span class="i-lucide-play" /> {{ plan.name }}
                </button>
              </div>
              <div v-if="plans.length && !planForm" class="flex gap-2 flex-wrap">
                <button
                  v-for="plan in plans"
                  :key="plan.id"
                  class="h-7 px-2.5 rounded-lg text-[11px] font-medium text-n-slate-11 border border-n-weak hover:bg-n-alpha-1"
                  @click="openEditPlan(plan)"
                >
                  ✏️ {{ plan.name }}
                </button>
              </div>

              <!-- Editor de ficha avulsa -->
              <div v-if="planForm" class="mt-3 rounded-xl border border-n-weak p-3">
                <h3 class="text-xs font-bold text-n-slate-12 mb-2">
                  {{ planForm.id ? '✏️ Editar ficha' : '📝 Nova ficha' }}
                </h3>
                <input
                  v-model="planForm.name"
                  type="text"
                  placeholder="Nome da ficha (ex.: Cardio — Esteira)"
                  class="block w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                  style="margin-bottom: 10px"
                />
                <div v-for="(ex, i) in planForm.exercises" :key="i" class="flex items-center gap-2 mb-2 flex-wrap">
                  <input
                    v-model="ex.name"
                    type="text"
                    placeholder="Exercício"
                    class="h-9 flex-1 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                    style="min-width: 10rem; margin-bottom: 0"
                  />
                  <input
                    v-model="ex.sets"
                    type="text"
                    inputmode="numeric"
                    title="Séries"
                    class="h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 text-center"
                    style="width: 3.5rem; margin-bottom: 0"
                  />
                  <span class="text-[11px] text-n-slate-10">×</span>
                  <input
                    v-model="ex.reps"
                    type="text"
                    title="Repetições"
                    class="h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 text-center"
                    style="width: 4rem; margin-bottom: 0"
                  />
                  <input
                    v-model="ex.load"
                    type="text"
                    inputmode="decimal"
                    title="Carga inicial (kg)"
                    placeholder="kg"
                    class="h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 text-right"
                    style="width: 4.5rem; margin-bottom: 0"
                  />
                  <button class="w-7 h-7 rounded-lg text-n-slate-10 hover:bg-n-alpha-1" @click="removePlanExercise(i)">
                    ✕
                  </button>
                </div>
                <div class="flex items-center gap-2 mt-3 flex-wrap">
                  <button
                    class="h-8 px-3 rounded-lg text-xs font-medium text-n-slate-11 border border-n-weak hover:bg-n-alpha-1"
                    @click="addPlanExercise"
                  >
                    + exercício
                  </button>
                  <div class="flex-1" />
                  <button
                    v-if="planForm.id"
                    class="h-9 px-3 rounded-lg text-xs font-medium border border-n-weak hover:bg-n-alpha-1"
                    style="color: #dc2626"
                    @click="deletePlan"
                  >
                    Excluir ficha
                  </button>
                  <button
                    class="h-9 px-3 rounded-lg text-xs font-medium text-n-slate-11 border border-n-weak hover:bg-n-alpha-1"
                    @click="planForm = null"
                  >
                    Cancelar
                  </button>
                  <button
                    class="h-9 px-4 rounded-lg text-xs font-bold text-white disabled:opacity-60"
                    :style="{ background: `linear-gradient(135deg, ${VERDE_ESCURO}, ${VERDE})` }"
                    :disabled="savingConfig"
                    @click="savePlan"
                  >
                    {{ savingConfig ? 'Salvando…' : 'Salvar ficha' }}
                  </button>
                </div>
              </div>
            </template>
          </div>
        </template>

        <!-- ═══ BOXE ═══ -->
        <template v-if="tab === 'boxe'">
          <!-- Registrar treino de boxe -->
          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">🥊 Registrar treino de boxe</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">{{ boxMin7 }} min nos últimos 7 dias</p>
            <div class="flex items-end gap-2.5 flex-wrap mb-3">
              <label class="block">
                <span class="text-[11px] font-medium text-n-slate-11">Data</span>
                <input
                  v-model="boxForm.date"
                  type="date"
                  class="mt-1 block h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                  style="width: 10rem; margin-bottom: 0"
                />
              </label>
              <label class="block">
                <span class="text-[11px] font-medium text-n-slate-11">Duração (min)</span>
                <WheelInput
                  v-model="boxForm.duration"
                  :step="5"
                  :max="180"
                  placeholder="min"
                  class="mt-1"
                  style="width: 5.4rem"
                />
              </label>
              <label class="block">
                <span class="text-[11px] font-medium text-n-slate-11">Rounds</span>
                <WheelInput
                  v-model="boxForm.rounds"
                  :step="1"
                  :max="30"
                  placeholder="nº"
                  class="mt-1"
                  style="width: 4.2rem"
                />
              </label>
              <label class="block flex-1" style="min-width: 12rem">
                <span class="text-[11px] font-medium text-n-slate-11">Observações</span>
                <input
                  v-model="boxForm.notes"
                  type="text"
                  placeholder="Ex.: saco pesado + sombra"
                  class="mt-1 block w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                  style="margin-bottom: 0"
                />
              </label>
            </div>
            <p class="text-[11px] font-medium text-n-slate-11 mb-1.5">Sequências praticadas (toque pra marcar)</p>
            <div class="flex gap-1.5 flex-wrap mb-3">
              <button
                v-for="s in boxingSeqs"
                :key="s.id"
                class="h-9 px-3 rounded-lg text-[11px] font-bold border"
                :class="boxForm.seqs.includes(s.id) ? 'text-white border-transparent' : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
                :style="boxForm.seqs.includes(s.id) ? { background: ROXO } : {}"
                @click="toggleSeq(s.id)"
              >
                {{ s.name }} <span class="font-normal opacity-75">{{ s.steps }}</span>
              </button>
            </div>
            <button
              class="h-10 px-6 rounded-xl text-xs font-bold text-white disabled:opacity-60"
              :style="{ background: `linear-gradient(135deg, #5B21B6, ${ROXO})` }"
              :disabled="savingBox"
              @click="saveBoxing"
            >
              {{ savingBox ? 'Salvando…' : '✓ Salvar treino de boxe' }}
            </button>
          </div>

          <!-- Repertório de sequências -->
          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <div class="flex items-center justify-between mb-1">
              <h2 class="text-sm font-bold text-n-slate-12">🌀 Sequências — repertório</h2>
              <button
                class="h-8 px-3 rounded-lg text-xs font-medium text-n-slate-11 border border-n-weak hover:bg-n-alpha-1"
                @click="openNewSeq"
              >
                + Nova sequência
              </button>
            </div>
            <p class="text-[11px] text-n-slate-10 mb-3">
              1 jab · 2 direto · 3 hook esq · 4 hook dir · 5 uppercut esq · 6 uppercut dir
            </p>

            <!-- Editor -->
            <div v-if="seqForm" class="rounded-xl border border-n-weak p-3 mb-3">
              <div class="flex items-center gap-2 flex-wrap mb-2">
                <input
                  v-model="seqForm.name"
                  type="text"
                  placeholder="Nome (ex.: Clássica)"
                  class="h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                  style="width: 12rem; margin-bottom: 0"
                />
                <input
                  v-model="seqForm.steps"
                  type="text"
                  placeholder="Passos (ex.: 1 · 2 · 3)"
                  class="h-9 flex-1 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                  style="min-width: 10rem; margin-bottom: 0"
                />
              </div>
              <input
                v-model="seqForm.desc"
                type="text"
                placeholder="Descrição (ex.: Jab · direto · hook esquerdo)"
                class="block w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                style="margin-bottom: 10px"
              />
              <div class="flex items-center gap-2 flex-wrap">
                <div class="flex-1" />
                <button
                  v-if="seqForm.id"
                  class="h-9 px-3 rounded-lg text-xs font-medium border border-n-weak hover:bg-n-alpha-1"
                  style="color: #dc2626"
                  @click="deleteSeq"
                >
                  Excluir
                </button>
                <button
                  class="h-9 px-3 rounded-lg text-xs font-medium text-n-slate-11 border border-n-weak hover:bg-n-alpha-1"
                  @click="seqForm = null"
                >
                  Cancelar
                </button>
                <button
                  class="h-9 px-4 rounded-lg text-xs font-bold text-white disabled:opacity-60"
                  :style="{ background: `linear-gradient(135deg, #5B21B6, ${ROXO})` }"
                  :disabled="savingConfig"
                  @click="saveSeq"
                >
                  {{ savingConfig ? 'Salvando…' : 'Salvar sequência' }}
                </button>
              </div>
            </div>

            <!-- Cards das sequências (grandes, pra praticar lendo) -->
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
              <div
                v-for="s in boxingSeqs"
                :key="s.id"
                class="rounded-xl border border-n-weak p-3 flex items-start gap-2"
              >
                <div class="flex-1 min-w-0">
                  <p class="text-[11px] font-bold text-n-slate-11">{{ s.name }}</p>
                  <p class="text-xl font-black tracking-wide" :style="{ color: ROXO }">{{ s.steps }}</p>
                  <p v-if="s.desc" class="text-[11px] text-n-slate-10">{{ s.desc }}</p>
                </div>
                <button
                  class="w-7 h-7 rounded-lg text-n-slate-10 hover:bg-n-alpha-1 shrink-0"
                  title="Editar"
                  @click="openEditSeq(s)"
                >
                  ✏️
                </button>
              </div>
            </div>
          </div>

          <!-- Histórico do boxe -->
          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-3">🗓 Últimos treinos de boxe</h2>
            <p v-if="!boxings.length" class="text-xs text-n-slate-10">Nenhum treino de boxe registrado ainda.</p>
            <div
              v-for="b in boxings.slice(0, 8)"
              :key="b.id"
              class="flex items-center gap-3 py-2 border-b border-n-weak last:border-0"
            >
              <span
                class="w-8 h-8 rounded-lg flex items-center justify-center text-white text-[10px] font-bold shrink-0"
                :style="{ background: `linear-gradient(135deg, #5B21B6, ${ROXO})` }"
              >
                {{ fmtDay(b.record_date) }}
              </span>
              <div class="flex-1 min-w-0">
                <p class="text-xs font-bold text-n-slate-12">
                  {{ b.data?.duration_min || 0 }} min
                  <span v-if="b.data?.rounds" class="font-normal text-n-slate-10">· {{ b.data.rounds }} rounds</span>
                </p>
                <p class="text-[11px] text-n-slate-10 truncate">
                  {{ (b.data?.sequences || []).map(seqName).join(' · ') || b.data?.notes || '—' }}
                </p>
              </div>
              <button
                class="w-7 h-7 rounded-lg text-n-slate-10 hover:bg-n-alpha-1 shrink-0"
                title="Remover"
                @click="deleteRecord(b)"
              >
                ✕
              </button>
            </div>
          </div>
        </template>

        <!-- ═══ DIETA ═══ -->
        <template v-if="tab === 'dieta'">
          <!-- Dia de hoje -->
          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <div class="flex items-center justify-between gap-2 flex-wrap mb-1">
              <span class="flex items-center gap-2">
                <h2 class="text-sm font-bold text-n-slate-12">
                  🍽 {{ dietDate === todayISO ? 'Hoje' : fmtDay(dietDate) }}
                </h2>
                <input
                  v-model="dietDate"
                  type="date"
                  title="Escolha o dia (dá pra registrar dias passados)"
                  class="h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[11px] text-n-slate-12"
                  style="width: 8.5rem; margin-bottom: 0"
                />
              </span>
              <button
                class="h-8 px-3 rounded-lg text-xs font-medium text-n-slate-11 border border-n-weak hover:bg-n-alpha-1"
                @click="openDietEditor"
              >
                ✏️ Plano & metas
              </button>
            </div>
            <p v-if="dietCfg.notes" class="text-[11px] text-n-slate-10 mb-3">{{ dietCfg.notes }}</p>
            <p v-if="!dietCfg.meals.length" class="text-xs text-n-slate-10">
              Monte seu plano alimentar em "Plano & metas" — as refeições viram um checklist diário.
            </p>

            <!-- barras de macros -->
            <div v-if="dietCfg.meals.length" class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
              <div v-for="m in MACROS" :key="m.key" class="rounded-xl border border-n-weak p-2.5">
                <div class="flex items-baseline justify-between">
                  <span class="text-[11px] font-medium text-n-slate-11">{{ m.label }}</span>
                  <span class="text-[11px] text-n-slate-10">
                    {{ fmtNum(dayTotals[m.key]) }}/{{ fmtNum(dietCfg.targets?.[m.key] || 0) }}{{ m.suffix }}
                  </span>
                </div>
                <div class="mt-1.5 h-2 rounded-full bg-n-alpha-1 overflow-hidden">
                  <div
                    class="h-full rounded-full transition-all"
                    :style="{ width: `${macroPct(m.key)}%`, background: m.cor }"
                  />
                </div>
              </div>
            </div>

            <!-- checklist de refeições -->
            <div v-for="meal in dietCfg.meals" :key="meal.id" class="mb-1.5">
              <button
                class="w-full flex items-center gap-3 rounded-xl border p-2.5 text-left transition-colors"
                :class="mealsDone.includes(meal.id) ? 'border-transparent' : 'border-n-weak hover:bg-n-alpha-1'"
                :style="mealsDone.includes(meal.id) ? { background: 'rgba(16, 185, 129, 0.12)' } : {}"
                :disabled="savingDiet"
                @click="toggleMeal(meal.id)"
              >
                <span
                  class="w-6 h-6 rounded-full flex items-center justify-center text-white text-xs shrink-0"
                  :style="{ background: mealsDone.includes(meal.id) ? VERDE : 'rgba(148,163,184,0.4)' }"
                >
                  {{ mealsDone.includes(meal.id) ? '✓' : '' }}
                </span>
                <div class="flex-1 min-w-0">
                  <p class="text-xs font-bold text-n-slate-12">
                    {{ meal.name }} <span v-if="meal.time" class="font-normal text-n-slate-10">· {{ meal.time }}</span>
                  </p>
                  <p v-if="meal.desc" class="text-[11px] text-n-slate-10 truncate">{{ meal.desc }}</p>
                  <p v-if="mealEquiv(meal)" class="text-[10px]" :style="{ color: VERDE }">
                    🍗 {{ mealEquiv(meal) }}
                  </p>
                </div>
                <span class="text-[11px] text-n-slate-10 shrink-0 text-right">
                  {{ meal.kcal }} kcal
                  <span v-if="meal.protein" class="block text-[10px]">P {{ meal.protein }} g</span>
                </span>
              </button>
            </div>

            <!-- extras do dia -->
            <div v-if="dietCfg.meals.length" class="mt-3">
              <p class="text-[11px] font-medium text-n-slate-11 mb-1.5">Fora do plano (extras)</p>
              <div
                v-for="(extra, i) in dietExtras"
                :key="i"
                class="flex items-center gap-2 text-[11px] text-n-slate-11 py-1"
              >
                <span class="flex-1">{{ extra.name }}</span>
                <span class="text-n-slate-10">{{ extra.kcal }} kcal</span>
                <button class="w-6 h-6 rounded text-n-slate-10 hover:bg-n-alpha-1" @click="removeExtra(i)">✕</button>
              </div>
              <div class="flex items-center gap-2 flex-wrap mt-1">
                <input
                  v-model="extraForm.name"
                  type="text"
                  placeholder="O que comeu fora do plano?"
                  class="h-9 flex-1 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                  style="min-width: 10rem; margin-bottom: 0"
                  @keyup.enter="addExtra"
                />
                <WheelInput
                  v-model="extraForm.kcal"
                  :step="10"
                  :max="2000"
                  placeholder="kcal"
                  style="width: 5rem"
                />
                <button
                  class="h-9 px-3 rounded-lg text-xs font-bold text-white"
                  :style="{ background: `linear-gradient(135deg, ${VERDE_ESCURO}, ${VERDE})` }"
                  @click="addExtra"
                >
                  Adicionar
                </button>
              </div>
            </div>
          </div>

          <!-- Editor do plano alimentar -->
          <div v-if="dietForm" class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">🎯 Metas do dia</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">
              É só passar as <b>calorias</b>: proteína (1,8 g/kg do seu peso), carbo e
              gordura são calculados na hora e divididos entre as refeições — ajuste
              depois o que quiser.
            </p>
            <div class="flex items-end gap-2.5 flex-wrap mb-4">
              <label v-for="m in MACROS" :key="m.key" class="block">
                <span class="text-[11px] font-medium text-n-slate-11">{{ m.label }}{{ m.suffix }}</span>
                <input
                  v-model="dietForm.targets[m.key]"
                  type="text"
                  inputmode="numeric"
                  class="mt-1 block h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 text-right"
                  style="width: 6rem; margin-bottom: 0"
                />
              </label>
            </div>
            <label class="block mb-4">
              <span class="text-[11px] font-medium text-n-slate-11">Notas do método (aparece na aba Dieta)</span>
              <input
                v-model="dietForm.notes"
                type="text"
                class="mt-1 block w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                style="margin-bottom: 0"
              />
            </label>
            <h2 class="text-sm font-bold text-n-slate-12 mb-2">🍱 Refeições do plano</h2>
            <div v-for="(meal, i) in dietForm.meals" :key="i" class="rounded-xl border border-n-weak p-2.5 mb-2">
              <div class="flex items-center gap-2 flex-wrap mb-1.5">
                <input
                  v-model="meal.name"
                  type="text"
                  placeholder="Refeição (ex.: Café da manhã)"
                  class="h-9 flex-1 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                  style="min-width: 9rem; margin-bottom: 0"
                />
                <input
                  v-model="meal.time"
                  type="text"
                  placeholder="07:30"
                  class="h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 text-center"
                  style="width: 4.5rem; margin-bottom: 0"
                />
                <button class="w-7 h-7 rounded-lg text-n-slate-10 hover:bg-n-alpha-1" @click="removeMeal(i)">✕</button>
              </div>
              <input
                v-model="meal.desc"
                type="text"
                placeholder="O que tem nela (ex.: 3 ovos + aveia + banana)"
                class="block w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                style="margin-bottom: 6px"
              />
              <div class="flex items-center gap-2 flex-wrap">
                <label v-for="m in MACROS" :key="m.key" class="flex items-center gap-1">
                  <span class="text-[10px] text-n-slate-10">{{ m.label }}</span>
                  <input
                    v-model="meal[m.key]"
                    type="text"
                    inputmode="numeric"
                    class="h-8 rounded-lg border border-n-weak bg-n-solid-2 px-1.5 text-[11px] text-n-slate-12 text-right"
                    style="width: 3.8rem; margin-bottom: 0"
                  />
                </label>
              </div>
            </div>
            <div class="flex items-center gap-2 flex-wrap mt-3">
              <button
                class="h-8 px-3 rounded-lg text-xs font-medium text-n-slate-11 border border-n-weak hover:bg-n-alpha-1"
                @click="addMeal"
              >
                + refeição
              </button>
              <div class="flex-1" />
              <button
                class="h-9 px-3 rounded-lg text-xs font-medium text-n-slate-11 border border-n-weak hover:bg-n-alpha-1"
                @click="dietForm = null"
              >
                Cancelar
              </button>
              <button
                class="h-9 px-4 rounded-lg text-xs font-bold text-white disabled:opacity-60"
                :style="{ background: `linear-gradient(135deg, ${VERDE_ESCURO}, ${VERDE})` }"
                :disabled="savingConfig"
                @click="saveDietCfg"
              >
                {{ savingConfig ? 'Salvando…' : 'Salvar plano' }}
              </button>
            </div>
          </div>

          <!-- Histórico da dieta -->
          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-3">🗓 Últimos dias</h2>
            <p v-if="!diets.length" class="text-xs text-n-slate-10">Nenhum dia registrado ainda.</p>
            <div
              v-for="d in diets.slice(0, 7)"
              :key="d.id"
              class="flex items-center gap-3 py-2 border-b border-n-weak last:border-0"
            >
              <span class="text-[11px] font-bold text-n-slate-11" style="width: 3rem">{{ fmtDay(d.record_date) }}</span>
              <div class="flex-1 h-2 rounded-full bg-n-alpha-1 overflow-hidden">
                <div class="h-full rounded-full" :style="{ width: `${dietDayPct(d)}%`, background: VERDE }" />
              </div>
              <span class="text-[11px] text-n-slate-10" style="width: 8rem; text-align: right">
                {{ (d.data?.meals_done || []).length }}/{{ dietCfg.meals.length }} refeições · {{ dietDayPct(d) }}%
              </span>
            </div>
          </div>
        </template>

        <!-- ═══ CORPO ═══ -->
        <template v-if="tab === 'corpo'">
          <!-- Registrar medidas: data em destaque + GRADE uniforme
               (rodada 15 — cada célula: rótulo · roleta · chip da última) -->
          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 sm:p-5 mb-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">📏 Registrar medidas</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">
              Protocolo: braço RELAXADO · coxa no meio virilha–joelho · cintura após expiração normal, sem encolher · pescoço abaixo do pomo de Adão, sem apertar. Sempre do mesmo jeito.
            </p>

            <div class="flex items-center gap-2 flex-wrap mb-4 rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5">
              <span class="text-[11px] font-medium text-n-slate-11">📅 Data da medição</span>
              <input
                v-model="bodyForm.date"
                type="date"
                class="h-9 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-xs text-n-slate-12"
                style="width: 9.5rem; margin-bottom: 0"
              />
              <span class="text-[10px] text-n-slate-10">mediu outro dia? troque a data</span>
            </div>

            <div class="hub-measure-grid mb-4">
              <div v-for="m in MEASURES" :key="m.key" class="flex flex-col gap-1.5">
                <span class="hub-measure-label text-n-slate-11">
                  <span>{{ m.label }}<span class="opacity-60 font-normal">{{ m.suffix }}</span></span>
                </span>
                <WheelInput
                  v-model="bodyForm[m.key]"
                  :step="m.step"
                  :max="m.max"
                  decimal
                  :placeholder="m.suffix.trim()"
                  style="width: 100%"
                />
                <button
                  v-if="lastBodyValue(m.key) !== null"
                  class="h-6 rounded-lg text-[10px] text-n-slate-10 bg-n-alpha-1 hover:bg-n-alpha-2 border border-dashed border-n-weak whitespace-nowrap"
                  title="Última medição — toque pra posicionar a roleta"
                  @click="copyLastBody(m.key)"
                >
                  {{ String(lastBodyValue(m.key)).replace('.', ',') }}⤵
                </button>
                <span v-else class="h-6 text-[10px] text-n-slate-10 text-center leading-6">1ª vez</span>
              </div>
            </div>

            <div class="flex items-end gap-2.5 flex-wrap">
              <label class="block flex-1" style="min-width: 12rem">
                <span class="text-[11px] font-medium text-n-slate-11">Observações</span>
                <input
                  v-model="bodyForm.notes"
                  type="text"
                  placeholder="Ex.: medido em jejum"
                  class="mt-1 block w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                  style="margin-bottom: 0"
                />
              </label>
              <button
                class="h-10 px-6 rounded-xl text-sm font-bold text-white disabled:opacity-60 w-full sm:w-auto"
                :style="{ background: `linear-gradient(135deg, ${VERDE_ESCURO}, ${VERDE})` }"
                :disabled="savingBody"
                @click="saveBody"
              >
                {{ savingBody ? 'Salvando…' : '✓ Salvar medidas' }}
              </button>
            </div>
          </div>

          <!-- Gráfico do peso -->
          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-3">⚖️ Peso ao longo do tempo</h2>
            <MiniBars
              v-if="weightSeries.values.length > 1"
              :values="weightSeries.values"
              :labels="weightSeries.labels"
              :color="AZUL"
              :height="110"
              :format="v => `${fmtNum(v)} kg`"
            />
            <p v-else class="text-xs text-n-slate-10">Registre o peso em pelo menos 2 dias pra ver a curva.</p>
          </div>

          <!-- Medidas atuais -->
          <div class="grid grid-cols-2 lg:grid-cols-3 gap-3 mb-4">
            <div v-for="m in currentMeasures" :key="m.key" class="rounded-xl border border-n-weak bg-n-solid-1 p-3">
              <p class="text-[11px] font-medium text-n-slate-11">{{ m.label }}</p>
              <p class="text-lg font-bold text-n-slate-12">
                {{ m.value === null ? '—' : `${fmtNum(m.value)}${m.suffix}` }}
              </p>
              <p v-if="m.delta !== null && m.delta !== 0" class="text-[11px]" :style="{ color: m.delta > 0 ? OURO : VERDE }">
                {{ m.delta > 0 ? '▲' : '▼' }} {{ fmtNum(Math.abs(m.delta)) }} desde a última
              </p>
            </div>
          </div>

          <!-- Histórico do corpo -->
          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-3">🗓 Últimas medições</h2>
            <p v-if="!bodies.length" class="text-xs text-n-slate-10">Nenhuma medição registrada ainda.</p>
            <div
              v-for="b in bodies.slice(0, 10)"
              :key="b.id"
              class="flex items-center gap-3 py-2 border-b border-n-weak last:border-0"
            >
              <span class="text-[11px] font-bold text-n-slate-11" style="width: 3rem">{{ fmtDay(b.record_date) }}</span>
              <p class="flex-1 text-[11px] text-n-slate-10 truncate">
                <template v-for="m in MEASURES" :key="m.key">
                  <span v-if="b.data?.[m.key]" class="mr-2">
                    {{ m.label }} {{ fmtNum(b.data[m.key]) }}{{ m.suffix }}
                  </span>
                </template>
              </p>
              <button
                class="w-7 h-7 rounded-lg text-n-slate-10 hover:bg-n-alpha-1 shrink-0"
                title="Remover"
                @click="deleteRecord(b)"
              >
                ✕
              </button>
            </div>
          </div>
        </template>
      </template>
    </div>
  </div>
</template>

<style scoped>
/* Cartão de vidro da meta (rodada 13): translúcido c/ blur, borda fina
   e brilho interno — verde no dia a dia, ouro quando a meta foi batida */
.hub-glass {
  background: linear-gradient(
    135deg,
    rgba(16, 185, 129, 0.1),
    rgba(16, 185, 129, 0.03) 45%,
    rgba(255, 255, 255, 0.04)
  );
  -webkit-backdrop-filter: blur(14px) saturate(1.5);
  backdrop-filter: blur(14px) saturate(1.5);
  border: 1px solid rgba(16, 185, 129, 0.22);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.08),
    0 6px 18px -12px rgba(16, 185, 129, 0.45);
}
.hub-glass-gold {
  background: linear-gradient(
    135deg,
    rgba(212, 160, 23, 0.12),
    rgba(212, 160, 23, 0.03) 45%,
    rgba(255, 255, 255, 0.04)
  );
  border-color: rgba(212, 160, 23, 0.28);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.08),
    0 6px 18px -12px rgba(212, 160, 23, 0.5);
}
/* alvo por série dentro do vidro — tocável, leva as roletas até a meta */
.hub-target-chip {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  height: 1.75rem;
  padding: 0 0.55rem;
  border-radius: 9999px;
  font-size: 11px;
  color: var(--slate-12, inherit);
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid rgba(255, 255, 255, 0.12);
  -webkit-backdrop-filter: blur(8px);
  backdrop-filter: blur(8px);
  transition: transform 0.12s ease, background 0.12s ease;
}
.hub-target-chip:not(:disabled):active {
  transform: scale(0.94);
}
.hub-target-chip:not(:disabled):hover {
  background: rgba(255, 255, 255, 0.12);
}
.hub-target-chip:disabled {
  opacity: 0.75;
}
/* chavinha de variação — segmentada estilo iOS */
.hub-switch {
  display: inline-flex;
  align-items: center;
  gap: 2px;
  padding: 2px;
  border-radius: 9999px;
  background: rgba(127, 127, 127, 0.14);
  border: 1px solid rgba(127, 127, 127, 0.18);
}
.hub-switch-opt {
  height: 1.6rem;
  padding: 0 0.7rem;
  border-radius: 9999px;
  font-size: 11px;
  font-weight: 600;
  color: inherit;
  opacity: 0.65;
  transition: all 0.15s ease;
}
.hub-switch-opt.is-on {
  color: #fff;
  opacity: 1;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.25);
}
/* aba Corpo: grade uniforme de medidas — colunas iguais, rótulo com
   altura reservada (2 linhas) pra TODAS as roletas ficarem alinhadas */
.hub-measure-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(5.8rem, 1fr));
  gap: 0.75rem;
}
.hub-measure-label {
  font-size: 11px;
  font-weight: 600;
  line-height: 1.15;
  text-align: center;
  min-height: 2.3em;
  display: flex;
  align-items: flex-end;
  justify-content: center;
}
/* modo treino no celular: cada exercício vira "uma tela" (~80% do
   viewport) e o scroll assenta no começo do card — a tela fica parada
   no exercício durante o treino */
.hub-snap {
  scroll-snap-type: y proximity;
}
@media (max-width: 640px) {
  .hub-ex-card {
    min-height: 78vh;
    scroll-snap-align: start;
    scroll-margin-top: 0.5rem;
  }
}
</style>
