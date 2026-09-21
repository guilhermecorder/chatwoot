<script setup>
// SAÚDE (HUB, segmento saude) — o painel pessoal: treino, dieta e corpo.
// O treino roda em MODO PROGRAMA (Warrior Shredding): a prescrição mora em
// agenda_config['health']['programs'] (seed db/seeds/hub_warrior.rb) e cada
// execução vira um hub_health_record imutável. O motor de progressão
// (warrior.js) compara HOJE × ÚLTIMA SESSÃO e calcula a meta de cada
// exercício. Fichas avulsas (fora de programa) continuam existindo.
// Feito pra usar NO CELULAR dentro da academia: poucos toques por série.
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import MiniBars from 'dashboard/components-next/cevico/MiniBars.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';
import { useHealthAccess } from './useHealthAccess';
import WheelInput from './WheelInput.vue';
import ProgramWizard from './ProgramWizard.vue';
import HubCelebration from './HubCelebration.vue';
import SeqPicker from './SeqPicker.vue';
import RadarChart from './HubRadar.vue';
import {
  METHOD_LABELS, METHOD_HINTS, SET_LABELS,
  activeProgram, weekOf, cycleForWeek, suggestedSessionKey,
  resolvePrograms, mainProgramOf, goalOf, goalProgress, programWeeks,
  workoutCelebration, bodyCelebration, MEASURE_DEFS,
  CARDIO_TYPES, cardioType, CARDIO_DURATIONS, CARDIO_INTENSITIES,
  SEQ_CATEGORIES, seqCategory, SEQ_LIBRARY,
  FIGHT_INTENTS, fightIntent, blankFightPlan, fightPlanToWorkout,
  axesFrom, workoutStyleValues, workoutTypeValues, WORKOUT_TYPE_AXES, planIntentValues, planStyleValues,
  ATHLETE_AXES, ATHLETE_ROLES, athleteRole, ATHLETE_STANCES, blankAthlete, athleteDataset, athleteHighlights, initialsOf,
  lastSessionRecord, lastExerciseSets, buildTodaySets,
  exerciseVerdict, targetHint, setTargets, sessionSummary, summaryPhrase, fmtSets,
  equipmentOf, nameWithoutEquipment, EXTRA_METHODS, extraMethod,
  learnEquiv, factorOf, convertLoad, fixedFactor,
} from './warrior';
// paleta azul royal + laranja (rodada 16) — a mesma do Meu Painel
import {
  ROYAL, ROYAL_CLARO,
  LARANJA, LARANJA_VIVO, LARANJA_CLARO,
  VERMELHO, VERDE_OK, CINZA,
  GRAD_ROYAL, GRAD_NOITE, GRAD_LARANJA,
} from './palette';

// MODO DE ENTRADA no treino (rodada 16): roletas (padrão) ou digitar —
// preferência guardada no aparelho
const INPUT_MODE_KEY = 'hub_input_mode';
const inputMode = ref('wheel');
try {
  if (localStorage.getItem(INPUT_MODE_KEY) === 'type') inputMode.value = 'type';
} catch {
  /* sem localStorage: fica nas roletas */
}
const setInputMode = m => {
  inputMode.value = m;
  try {
    localStorage.setItem(INPUT_MODE_KEY, m);
  } catch {
    /* ignora */
  }
};

const isLoading = ref(true);
const config = ref({});
// ficha da pessoa (modo de programa, alvos) + programas PESSOAIS (rodada 25)
const profile = ref({});
const personalPrograms = ref([]);
const workouts = ref([]);
const boxings = ref([]);
const cardios = ref([]); // rodada 26
const fightPlans = ref([]); // rodada 26
const athletes = ref([]); // rodada 29: mapeador de atletas
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
  cardio: 'hub_health_cardio',
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
  { key: 'cardio', label: 'Cardio', icon: 'i-lucide-heart-pulse' },
  { key: 'boxe', label: 'Boxe', icon: 'i-lucide-swords' },
  { key: 'dieta', label: 'Dieta', icon: 'i-lucide-utensils' },
  { key: 'corpo', label: 'Corpo', icon: 'i-lucide-ruler' },
];
// rodada 34: abas = módulos liberados pra mim (boxe também precisa do recurso ligado)
const { allowed: moduleAllowed } = useHealthAccess();
const TABS = computed(() =>
  TABS_ALL.filter(t => moduleAllowed(t.key) && (t.key !== 'boxe' || boxingOn.value))
);

// ═══ RODADA 27: BOTÕES DE VISUALIZAÇÃO por aba (pedido dele 19/09:
// "mais controle e mais limpeza" — cada aba mostra UMA coisa por vez)
const TREINO_VIEWS = [
  { key: 'treinar', label: 'Treinar', ico: 'i-lucide-play' },
  { key: 'planilha', label: 'Planilha', ico: 'i-lucide-table' },
  { key: 'historico', label: 'Histórico', ico: 'i-lucide-history' },
];
const CARDIO_VIEWS = [
  { key: 'registrar', label: 'Registrar', ico: 'i-lucide-plus-circle' },
  { key: 'historico', label: 'Histórico', ico: 'i-lucide-history' },
];
const BOX_VIEWS = [
  { key: 'treinar', label: 'Treinar', ico: 'i-lucide-play' },
  { key: 'planos', label: 'Planos', ico: 'i-lucide-medal' },
  { key: 'atletas', label: 'Atletas', ico: 'i-lucide-users' },
  { key: 'repertorio', label: 'Repertório', ico: 'i-lucide-list-ordered' },
  { key: 'historico', label: 'Histórico', ico: 'i-lucide-history' },
];
const treinoView = ref('treinar');
const cardioView = ref('registrar');
const boxView = ref('treinar');
// histórico agrupado por mês (lista estilo iOS)
const MONTHS_PT = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];
const MONTHS_ABBR = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
const dayOf = iso => String(iso).slice(8, 10);
const monOf = iso => MONTHS_ABBR[Number(String(iso).slice(5, 7)) - 1] || '';
const groupByMonth = list => {
  const out = [];
  (list || []).forEach(r => {
    const key = String(r.record_date).slice(0, 7);
    let g = out.find(x => x.key === key);
    if (!g) {
      g = { key, label: `${MONTHS_PT[Number(key.slice(5, 7)) - 1]} ${key.slice(0, 4)}`, items: [] };
      out.push(g);
    }
    g.items.push(r);
  });
  return out;
};

// ordena registros do mais novo pro mais velho (entradas retroativas);
// mesma data → o id maior primeiro (rodada 25: dois treinos no mesmo dia
// faziam o "próximo" apontar pro treino errado — o comparador empatava)
const sortRecs = arr =>
  [...arr].sort((a, b) => {
    if (a.record_date === b.record_date) return (Number(b.id) || 0) - (Number(a.id) || 0);
    return a.record_date < b.record_date ? 1 : -1;
  });

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
// Warrior (config, compartilhado) OU o programa pessoal ativo — mesma forma
const programs = computed(() => resolvePrograms(config.value, profile.value, personalPrograms.value));
const mainProgram = computed(() => mainProgramOf(programs.value));
const warriorPrograms = computed(() => config.value?.programs || []);
const programMode = computed(() => profile.value?.program_mode || 'warrior');
const dietCfg = computed(() => {
  const d = config.value?.diet || {};
  return { targets: d.targets || {}, meals: d.meals || [], notes: d.notes || '' };
});

// (rodada 20: a fileira de KPIs do topo saiu — "enxugar": a tela de
// treino é pra treinar; os indicadores moram no Meu Painel e em Análises)
const currentTabLabel = computed(
  () => TABS_ALL.find(t => t.key === tab.value)?.label || 'Saúde'
);

// ═══ TREINO — MODO PROGRAMA (Warrior) ═══════════════════════════════
const program = computed(() => activeProgram(programs.value));
// rodada 23: o treino DO DIA (dia da semana da prescrição = hoje)
const WEEKDAYS_PT = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];
const todayWeekday = WEEKDAYS_PT[new Date().getDay()];
const isTodaySession = sx =>
  (sx.weekday || '').toLowerCase().startsWith(todayWeekday.slice(0, 4).toLowerCase());
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
  const list = warriorPrograms.value.map(x => ({ ...x, active: x.id === p.id }));
  pushConfig({ ...config.value, programs: list });
};

// ═══ PROGRAMAS PESSOAIS (rodada 25): Warrior × "crie seu próprio treino" ═══
// A ficha (kind=profile) guarda o modo: 'warrior' = prescrição compartilhada
// exatamente como está; 'custom' = o programa pessoal ativo (kind=program).
const savingProfile = ref(false);
const saveProfile = async patch => {
  savingProfile.value = true;
  try {
    const { data: rec } = await CrmAPI.createHealthRecord({
      kind: 'profile',
      data: { ...profile.value, ...patch },
    });
    profile.value = rec.data || {};
    return true;
  } catch {
    useAlert('Não consegui salvar a escolha do programa.');
    return false;
  } finally {
    savingProfile.value = false;
  }
};
const activePersonal = computed(() =>
  personalPrograms.value.filter(r => r.data?.status === 'active')
);
const finishedPersonal = computed(() =>
  personalPrograms.value.filter(r => r.data?.status !== 'active')
);
const chooseWarrior = () => saveProfile({ program_mode: 'warrior' });
const choosePersonal = rec => saveProfile({ program_mode: 'custom', active_program_id: rec.id });

const historyOpen = ref(false);
const wizard = ref(null); // { record: null | registro em edição }
const savingWizard = ref(false);
const openWizard = (rec = null) => {
  wizard.value = { record: rec };
  historyOpen.value = false;
};
const saveWizard = async data => {
  savingWizard.value = true;
  try {
    let rec;
    if (wizard.value?.record) {
      const { data: updated } = await CrmAPI.updateHealthRecord(wizard.value.record.id, data, data.start_date);
      rec = updated;
      personalPrograms.value = personalPrograms.value.map(r => (r.id === rec.id ? rec : r));
      useAlert('✏️ Treino atualizado.');
    } else {
      const { data: created } = await CrmAPI.createHealthRecord({
        kind: 'program',
        record_date: data.start_date,
        data,
      });
      rec = created;
      personalPrograms.value = [rec, ...personalPrograms.value];
      useAlert(`🚀 "${rec.data?.name}" começou. Bom jogo!`);
    }
    await choosePersonal(rec);
    wizard.value = null;
  } catch {
    useAlert('Não consegui salvar o treino.');
  } finally {
    savingWizard.value = false;
  }
};
// objetivo do programa pessoal ativo: quanto já entregou
const goalNow = computed(() =>
  program.value?.custom
    ? goalProgress({ program: program.value, workouts: workouts.value, bodies: bodies.value, todayISO })
    : null
);
const finishProgram = async rec => {
  const prog = programs.value.find(p => p.record_id === rec.id);
  const g = prog
    ? goalProgress({ program: prog, workouts: workouts.value, bodies: bodies.value, todayISO })
    : null;
  const result = g && !g.none ? `${g.icon} ${g.label}: ${g.value} — ${g.ok ? 'sucesso' : 'abaixo do esperado'} (${g.detail})` : 'sem dados suficientes pra avaliar';
  try {
    const { data: updated } = await CrmAPI.updateHealthRecord(rec.id, {
      ...rec.data,
      status: 'finished',
      finished_at: todayISO,
      result,
    });
    personalPrograms.value = personalPrograms.value.map(r => (r.id === updated.id ? updated : r));
    if (Number(profile.value.active_program_id) === Number(rec.id)) {
      const other = activePersonal.value.find(r => r.id !== rec.id);
      if (other) await choosePersonal(other);
      else await saveProfile({ program_mode: warriorPrograms.value.length ? 'warrior' : 'custom', active_program_id: null });
    }
    useAlert(`🏁 "${rec.data?.name}" encerrado e guardado no histórico.`);
  } catch {
    useAlert('Não consegui encerrar o programa.');
  }
};
const deleteProgram = async rec => {
  try {
    await CrmAPI.deleteHealthRecord(rec.id);
    personalPrograms.value = personalPrograms.value.filter(r => r.id !== rec.id);
    if (Number(profile.value.active_program_id) === Number(rec.id)) {
      await saveProfile({ program_mode: warriorPrograms.value.length ? 'warrior' : 'custom', active_program_id: null });
    }
    useAlert('Programa removido.');
  } catch {
    useAlert('Não consegui remover.');
  }
};
// histórico dos programas pessoais: nome, período, treinos feitos, resultado
const programHistory = computed(() =>
  personalPrograms.value.map(rec => {
    const pid = `custom_${rec.id}`;
    const done = workouts.value.filter(
      w => w.data?.program_id === pid && (w.data?.exercises || []).some(e => e.sets?.length)
    ).length;
    const d = rec.data || {};
    const goal = goalOf(d.goal);
    const prog = programs.value.find(p => p.record_id === rec.id);
    const live = prog && d.status === 'active'
      ? goalProgress({ program: prog, workouts: workouts.value, bodies: bodies.value, todayISO })
      : null;
    return {
      rec,
      name: d.name || 'Meu treino',
      period: `${fmtDay(d.start_date || rec.record_date)}${d.finished_at ? ` → ${fmtDay(d.finished_at)}` : ''}`,
      weeks: Number(d.weeks) || 0,
      split: (d.sessions || []).map(x => x.key).join(''),
      done,
      goal,
      status: d.status || 'active',
      result: d.result || '',
      live,
      isActive: Number(profile.value.active_program_id) === Number(rec.id) && programMode.value === 'custom',
    };
  })
);
// nomes conhecidos pro autocompletar do assistente
const knownExerciseNames = computed(() => {
  const names = new Set();
  [...warriorPrograms.value, ...programs.value].forEach(p =>
    (p.cycles || []).forEach(c =>
      (c.sessions || []).forEach(sx => (sx.exercises || []).forEach(e => e.name && names.add(e.name)))
    )
  );
  workouts.value.forEach(w => (w.data?.exercises || []).forEach(e => e.name && names.add(e.name)));
  return [...names].sort((a, b) => a.localeCompare(b));
});

// ═══ CELEBRAÇÕES (rodada 25): semana fechada + medição registrada ═══
// (valem pro Warrior e pro programa pessoal). Cada celebração tem uma
// chave; guardada no aparelho pra não repetir se editar o mesmo registro.
const celebration = ref(null);
const CELE_KEY = 'hub_celebrated';
const alreadyCelebrated = key => {
  try {
    return (JSON.parse(localStorage.getItem(CELE_KEY) || '[]') || []).includes(key);
  } catch {
    return false;
  }
};
const markCelebrated = key => {
  try {
    const list = JSON.parse(localStorage.getItem(CELE_KEY) || '[]') || [];
    localStorage.setItem(CELE_KEY, JSON.stringify([...list, key].slice(-60)));
  } catch {
    /* ignora */
  }
};
const celebrate = data => {
  if (!data || alreadyCelebrated(data.key)) return;
  markCelebrated(data.key);
  celebration.value = data;
};
const sessionsPerWeek = computed(
  () => Number(profile.value?.weekly_sessions) || (programCycle.value?.sessions || []).length || 3
);

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
    // campo único "barra | halteres | máquina": vazio = automático pelo
    // nome · 1 opção = sem chavinha · 2+ = chavinha com essas opções
    rows: (sessionDef.exercises || []).map(e => ({
      ...e,
      // "barra | halteres ×2 | máquina ×0,85" — o ×n é o fator do PESO COMUM
      _variants: equipmentOf(e)
        .options.map(o => {
          const f = fixedFactor(e, o);
          return f && f !== 1 ? `${o} ×${String(f).replace('.', ',')}` : o;
        })
        .join(' | '),
      _del: false,
    })),
  };
};
// "barra | halteres ×2 | máquina x0,85" → { variants: [...], equiv: { máquina: 0.85 } }
const parseVariants = text => {
  const variants = [];
  const equiv = {};
  String(text || '')
    .split(/[|,;/]+/)
    .map(v => v.trim())
    .filter(Boolean)
    .forEach(v => {
      const m = v.match(/^(.*?)\s*[×x]\s*([\d.,]+)$/i);
      const name = (m ? m[1] : v).trim();
      if (!name) return;
      variants.push(name);
      if (m) {
        const f = Number(m[2].replace(',', '.'));
        if (f > 0) equiv[name.toLowerCase()] = f;
      }
    });
  return { variants, equiv };
};
const addEditorExercise = () =>
  exEditor.value.rows.push({
    name: '',
    tag: '',
    _variants: '',
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
  const cleanRows = rows.map(({ _del, _variants, ...e }) => {
    const { variants, equiv } = parseVariants(_variants);
    return { ...e, variants, equiv, tag: variants[0] || '', alt_tag: '' };
  });
  // programa PESSOAL: a prescrição mora no registro kind=program
  const personal = program.value?.custom ? personalPrograms.value.find(r => r.id === program.value.record_id) : null;
  if (personal) {
    try {
      const sessions = (personal.data.sessions || []).map(sx =>
        sx.key === ed.sessionKey ? { ...sx, exercises: cleanRows } : sx
      );
      const { data: updated } = await CrmAPI.updateHealthRecord(personal.id, { ...personal.data, sessions });
      personalPrograms.value = personalPrograms.value.map(r => (r.id === updated.id ? updated : r));
      exEditor.value = null;
      useAlert('✏️ Treino atualizado.');
    } catch {
      useAlert('Não consegui salvar a edição.');
    }
    return;
  }
  const progs = warriorPrograms.value.map(p => {
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
                  : {
                      ...s,
                      exercises: rows.map(({ _del, _variants, ...e }) => {
                        const { variants, equiv } = parseVariants(_variants);
                        return { ...e, variants, equiv, tag: variants[0] || '', alt_tag: '' };
                      }),
                    }
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

// (normTag/lastSetsForTag moram aqui em cima porque a sessão nasce já
// na variação da última vez — rodada 16)
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
// sessão em andamento (programa OU ficha avulsa) — nada salvo até concluir
const session = ref(null);
const savingSession = ref(false);

const startProgramSession = sessionDef => {
  const prog = program.value;
  const cycle = programCycle.value;
  const lastRecord = lastSessionRecord(workouts.value, prog.id, sessionDef.key);
  const exercises = (sessionDef.exercises || []).map(p => {
    const eq = equipmentOf(p);
    // a chavinha nasce na variação usada da ÚLTIMA vez (se ainda existir)
    const lastEntry = (lastRecord?.data?.exercises || []).find(e => e.name === p.name);
    const startTag =
      lastEntry?.tag && eq.options.some(o => normTag(o) === normTag(lastEntry.tag))
        ? eq.options.find(o => normTag(o) === normTag(lastEntry.tag))
        : eq.base;
    const last = eq.options.length > 1
      ? lastSetsForTag(p.name, startTag, eq.base)
      : lastExerciseSets(lastRecord, p.name);
    return {
      name: p.name,
      displayName: eq.options.length > 1 ? nameWithoutEquipment(p.name) : p.name,
      tag: startTag,
      baseTag: eq.base,
      options: eq.options,
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
  const main = mainProgram.value;
  const bonus = programs.value.find(p => p.id === 'warrior_bonus');
  const tabs = (main?.cycles || []).map((c, i) => ({
    key: c.id,
    label: main.custom ? 'Semanas' : CYCLE_LETTERS[i] || c.name,
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

// ═══ CHAVINHA DE EQUIPAMENTO (rodada 13 → N opções na 16) ═══════════
// As opções vêm de equipmentOf (lista `variants` da prescrição ou, sem
// lista, sugeridas pelo nome: barra | halteres | máquina…). Trocar a
// chavinha re-prefill as roletas com a última execução DAQUELA variação
// (carga de barra ≠ carga de halter) e recalcula meta/alvos. O registro
// salva a variação usada (out.tag) pra busca futura.
// execuções do exercício em QUALQUER variação (tag, e-1RM, data) — base do
// peso comum: fator de cada variação aprendido pelo histórico
const e1rmOf = (load, reps) => (reps > 0 ? load * (1 + reps / 30) : load);
const execsOfName = name => {
  const alvo = name.trim().toLowerCase();
  const out = [];
  workouts.value.forEach(w => {
    (w.data?.exercises || []).forEach(e => {
      if (String(e.name || '').trim().toLowerCase() !== alvo || !e.sets?.length) return;
      out.push({
        tag: e.tag || '',
        date: w.record_date,
        sets: e.sets,
        e1: Math.max(...e.sets.map(s => e1rmOf(toNum(s.load), toNum(s.reps)))),
      });
    });
  });
  return out; // mais novo primeiro
};
const equivOf = ex => learnEquiv(ex.presc || {}, ex.baseTag, execsOfName(ex.name));
const fmtF = f => `×${String(Math.round(f * 100) / 100).replace('.', ',')}`;
// nota do peso comum no card da sessão ("halteres 30 ≈ 60 kg comum · máquina ×0,86")
const commonNote = ex => {
  if (!ex.options || ex.options.length < 2) return '';
  const equiv = equivOf(ex);
  const baseF = factorOf(equiv, ex.baseTag, ex.baseTag, ex.presc) || 1;
  const rel = t => factorOf(equiv, t, ex.baseTag, ex.presc) / baseF; // escala da variação principal
  const f = rel(ex.tag);
  const top = Math.max(0, ...(ex.sets || []).map(s => toNum(s.load)));
  const parts = [];
  if (top && f !== 1) {
    parts.push(`${ex.tag} ${String(top).replace('.', ',')} ≈ ${String(Math.round(top * f * 10) / 10).replace('.', ',')} kg na escala de ${ex.baseTag}`);
  }
  ex.options.forEach(o => {
    const fo = Math.round(rel(o) * 100) / 100;
    if (fo !== 1) parts.push(`${o} ${fmtF(fo)}`);
  });
  return parts.join(' · ');
};
const switchVariation = (ex, tag) => {
  if (normTag(ex.tag) === normTag(tag)) return;
  ex.tag = tag;
  const last = lastSetsForTag(ex.name, tag, ex.baseTag);
  ex.last = last;
  const presc = ex.presc || { sets: [] };
  if (last) {
    ex.hint = targetHint(presc, last);
    ex.targets = setTargets(presc, last);
    ex.sets = buildTodaySets(presc, last);
    return;
  }
  // 1ª vez nesta variação: ESTIMA pelo peso comum a partir da execução
  // mais recente em outra variação (halteres 30 ×2 → máquina ≈ 60/fator)
  const other = execsOfName(ex.name)[0];
  if (!other) {
    ex.hint = `Primeira vez com ${tag} — encontre a carga desta variação.`;
    ex.targets = setTargets(presc, null);
    ex.sets = buildTodaySets(presc, null);
    return;
  }
  const equiv = equivOf(ex);
  const fFrom = factorOf(equiv, other.tag, ex.baseTag, ex.presc);
  const fTo = factorOf(equiv, tag, ex.baseTag, ex.presc);
  const est = other.sets.map(s => ({ load: convertLoad(toNum(s.load), fFrom, fTo), reps: toNum(s.reps) }));
  ex.hint = `Primeira vez com ${tag} — estimado pelo peso comum: ${other.tag || ex.baseTag} ${fmtSets(other.sets)} ≈ ${fmtSets(est)}. Ajuste e a variação passa a ter o próprio histórico.`;
  ex.targets = setTargets(presc, null);
  ex.sets = buildTodaySets(presc, est).map(st => ({ ...st, prev: null, estimated: true }));
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
// técnica do extra (rodada 16): o exercício nasce pré-configurado
// (séries/faixas/descanso) e o motor calcula meta e alvos como no programa
const extraMethodKey = ref('sets');
const extraPreset = computed(() => extraMethod(extraMethodKey.value));
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
// nome "normalizado" (rodada 20): sem acento, minúsculo, sem preposição
// nem equipamento no fim — "Crucifixo maquina" acha "Crucifixo na máquina"
// (feedback dele 18/09: o extra não puxava as informações anteriores;
// no iPhone a lista de sugestões não aparece e ele digita de outro jeito)
const normName = s =>
  String(s || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\b(na|no|nas|nos|em|com|de|do|da|a|o)\b/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
// versão "solta": também sem o equipamento no fim, com ou sem preposição
// ("rosca martelo halteres" = "Rosca martelo com halteres" = "Rosca martelo")
const EQUIP_TAIL = /\s+(barra|halter|halteres|maquina|corda|polia|cabo|smith|reta|w)$/;
const normLoose = s => {
  let out = normName(nameWithoutEquipment(s));
  for (let i = 0; i < 2 && EQUIP_TAIL.test(out); i += 1) out = out.replace(EQUIP_TAIL, '');
  return out;
};
// última vez deste exercício em QUALQUER treino registrado (séries +
// técnica + data): igual primeiro; senão igual sem o equipamento
const lastAnyEntry = name => {
  const alvo = normName(name);
  if (!alvo) return null;
  const alvoLoose = normLoose(name);
  let loose = null;
  for (const w of workouts.value) {
    for (const e of w.data?.exercises || []) {
      if (!e.sets?.length) continue;
      const n = normName(e.name);
      if (n === alvo) return { ...e, date: w.record_date };
      if (!loose && normLoose(e.name) === alvoLoose) loose = { ...e, date: w.record_date };
    }
  }
  return loose;
};
// prévia ao vivo no seletor: o que foi feito da última vez com esse nome
const extraPreview = computed(() =>
  extraName.value.trim() ? lastAnyEntry(extraName.value) : null
);
// extras recentes (1 toque adiciona com a técnica da última vez)
const recentExtras = computed(() => {
  const seen = new Map();
  workouts.value.forEach(w =>
    (w.data?.exercises || []).forEach(e => {
      if (!e.extra || !e.name || !e.sets?.length) return;
      const k = normName(e.name);
      if (!seen.has(k)) seen.set(k, { name: e.name, date: w.record_date, sets: e.sets, method: e.method || 'sets' });
    })
  );
  const inSession = new Set((session.value?.exercises || []).map(e => normName(e.name)));
  return [...seen.values()].filter(x => !inSession.has(normName(x.name))).slice(0, 8);
});
// escolheu um exercício já feito → a técnica da última vez vem selecionada
watch(extraName, name => {
  const entry = name?.trim() ? lastAnyEntry(name) : null;
  if (entry?.method && EXTRA_METHODS.some(m => m.key === entry.method)) {
    extraMethodKey.value = entry.method;
  }
});
const addExtraExercise = () => {
  const name = extraName.value.trim();
  if (!name || !session.value) return;
  if (session.value.exercises.some(e => normName(e.name) === normName(name))) {
    useAlert('Esse exercício já está no treino de hoje.');
    return;
  }
  const preset = extraPreset.value;
  const presc = { name, ...JSON.parse(JSON.stringify(preset.presc)) };
  const entry = lastAnyEntry(name);
  // PUXA a última execução SEMPRE: as caixinhas nascem com as cargas da
  // última vez (chip cinza por série) mesmo que a técnica tenha mudado.
  // O veredito HOJE × última só vale na MESMA técnica (rest-pause não se
  // compara com séries retas) — aí entra como referência no hint.
  const sameMethod = entry && (entry.method || 'sets') === presc.method;
  const comparable = sameMethod ? entry.sets : null;
  let hint;
  if (comparable) hint = targetHint(presc, comparable);
  else if (entry) {
    hint = `Última vez ${fmtDay(entry.date)} em ${
      METHOD_LABELS[entry.method || 'sets']
    }: ${fmtSets(entry.sets)}. Técnica nova (${preset.label}) — ajuste a carga nas faixas.`;
  } else hint = `Extra em ${preset.label} — primeira vez, encontre a carga nas faixas.`;
  session.value.exercises.push({
    name: entry?.name || name,
    extra: true,
    method: presc.method,
    scheme: presc.scheme,
    rest: presc.rest,
    presc,
    last: comparable,
    lastDate: entry?.date || null,
    hint,
    targets: setTargets(presc, comparable),
    sets: buildTodaySets(presc, entry?.sets || null),
  });
  extraName.value = '';
  extraOpen.value = false;
};
// chip de extra recente: 1 toque = entra no treino com a técnica da última vez
const pickExtra = x => {
  extraName.value = x.name;
  if (EXTRA_METHODS.some(m => m.key === x.method)) extraMethodKey.value = x.method;
  addExtraExercise();
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
    const savedDate = session.value.date || todayISO;
    session.value = null;
    if (isProgram) {
      const done = exercises.filter(e => !e.skipped).length;
      useAlert(`💪 ${summaryPhrase(data.summary, done)}`);
      // rodada 25: fechou o último treino planejado da semana → celebra
      celebrate(
        workoutCelebration({
          program: program.value,
          workouts: workouts.value,
          dateISO: savedDate,
          sessionsPerWeek: sessionsPerWeek.value,
        })
      );
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
  seqForm.value = { id: '', name: '', steps: '', desc: '', category: '', when: '' };
};
// rodada 26: etiqueta "quando usar" — filtro por categoria + biblioteca pronta
const seqFilter = ref('');
const filteredSeqs = computed(() =>
  seqFilter.value ? boxingSeqs.value.filter(sq => sq.category === seqFilter.value) : boxingSeqs.value
);
const seqCatMeta = key => seqCategory(key);
const seqCount = key => boxingSeqs.value.filter(sq => sq.category === key).length;
const importSeqLibrary = async () => {
  const have = new Set(boxingSeqs.value.map(sq => String(sq.name || '').trim().toLowerCase()));
  const fresh = SEQ_LIBRARY.filter(sq => !have.has(sq.name.toLowerCase()));
  if (!fresh.length) {
    useAlert('A biblioteca inteira já está no seu repertório.');
    return;
  }
  const stamp = Date.now().toString(36);
  const list = [...boxingSeqs.value, ...fresh.map((sq, i) => ({ ...sq, id: `lb${stamp}${i}` }))];
  const ok = await pushConfig({ ...config.value, boxing: { ...(config.value?.boxing || {}), sequences: list } });
  if (ok) useAlert(`📚 ${fresh.length} sequências entraram no repertório.`);
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
  const ok = await pushConfig({ ...config.value, boxing: { ...(config.value?.boxing || {}), sequences: list } });
  if (ok) {
    seqForm.value = null;
    useAlert('Sequência salva.');
  }
};
const deleteSeq = async () => {
  const list = boxingSeqs.value.filter(s => s.id !== seqForm.value.id);
  const ok = await pushConfig({ ...config.value, boxing: { ...(config.value?.boxing || {}), sequences: list } });
  if (ok) {
    seqForm.value = null;
    useAlert('Sequência removida.');
  }
};
const seqName = id => boxingSeqs.value.find(s => s.id === id)?.name || id;
const seqSteps = id => boxingSeqs.value.find(s => s.id === id)?.steps || '';
const boxMin7 = computed(() =>
  boxings.value
    .filter(b => b.record_date >= daysAgo(6))
    .reduce((s, b) => s + (Number(b.data?.duration_min) || 0), 0)
);

// ═══ BOXE PRÉ-PROGRAMADO (rodada 20) ════════════════════════════════
// Pedido dele 18/09: "pré-programar treinos de boxe, 60 minutos por
// exemplo, estruturados com aquecimento, sequências praticadas,
// footwork etc." Cada treino = blocos em ordem, cada bloco com minutos
// (ou rounds × segundos + descanso) e as sequências do repertório que
// entram nele. A sessão guiada roda um cronômetro bloco a bloco
// (round/descanso com apito) e, ao concluir, vira 1 registro de boxe.
const BLOCK_TYPES = {
  aquecimento: { label: 'Aquecimento', icon: '🔥', ico: 'i-lucide-flame' },
  sombra: { label: 'Sombra', icon: '👤', ico: 'i-lucide-user' },
  tecnica: { label: 'Técnica', icon: '🎯', ico: 'i-lucide-crosshair' },
  sequencias: { label: 'Sequências', icon: '🌀', ico: 'i-lucide-list-ordered' },
  footwork: { label: 'Footwork', icon: '👟', ico: 'i-lucide-footprints' },
  defesa: { label: 'Defesa', icon: '🛡', ico: 'i-lucide-shield' },
  saco: { label: 'Saco pesado', icon: '🥊', ico: 'i-lucide-circle-dot' },
  condicionamento: { label: 'Condicionamento', icon: '⚡', ico: 'i-lucide-zap' },
  alongamento: { label: 'Volta à calma', icon: '🧘', ico: 'i-lucide-leaf' },
  round: { label: 'Round', icon: '🔔', ico: 'i-lucide-bell' },
};
const blockMeta = type => BLOCK_TYPES[type] || { label: type || 'Bloco', icon: '▫️', ico: 'i-lucide-square' };
// estatísticas do histórico de boxe (rodada 27)
const boxStats = computed(() => ({
  n: boxings.value.length,
  min: boxings.value.reduce((a, b) => a + (Number(b.data?.duration_min) || 0), 0),
  rounds: boxings.value.reduce((a, b) => a + (Number(b.data?.rounds) || 0), 0),
}));
const blk = (type, title, minutes, rounds, roundSec, restSec, seqs, desc) => ({
  type, title, minutes, rounds, round_sec: roundSec, rest_sec: restSec, seqs, desc,
});
// treinos de fábrica (aparecem enquanto ele não salvar os dele; os ids
// das sequências são os do repertório seedado)
const DEFAULT_BOX_WORKOUTS = [
  {
    id: 'bx60',
    name: 'Fundamentos — 60 min',
    desc: 'Treino completo: base na sombra, sequências, footwork, saco e condicionamento.',
    blocks: [
      blk('aquecimento', 'Corda + mobilidade', 10, 0, 0, 0, [], '5 min de corda · 5 min de mobilidade (ombros, quadril, tornozelos)'),
      blk('sombra', 'Sombra técnica', 9, 3, 180, 60, ['b1', 'b2'], 'Base, guarda e jab-direto; atenção na volta da mão'),
      blk('sequencias', 'Sequências', 12, 4, 180, 60, ['b3', 'b4', 'b6'], 'Cada sequência 10× lenta, 10× rápida — troca a cada round'),
      blk('footwork', 'Footwork', 9, 3, 180, 60, [], 'Passo lateral · pivô · entra-sai com jab'),
      blk('saco', 'Saco pesado', 12, 4, 180, 60, ['b3', 'b7', 'b8'], 'Potência nas sequências; último round livre'),
      blk('condicionamento', 'Condicionamento', 5, 5, 40, 20, [], 'Burpee · corrida no lugar · prancha · agachamento · polichinelo'),
      blk('alongamento', 'Volta à calma', 3, 0, 0, 0, [], 'Respiração + alongamento de ombros e punhos'),
    ],
  },
  {
    id: 'bx45',
    name: 'Sequências e footwork — 45 min',
    desc: 'Técnica pura: combinações do repertório e deslocamento, sem saco.',
    blocks: [
      blk('aquecimento', 'Corda', 8, 0, 0, 0, [], 'Corda com variações (pé alternado, duplo)'),
      blk('sombra', 'Sombra', 6, 2, 180, 60, ['b1'], 'Jab e direto com deslocamento'),
      blk('sequencias', 'Sequências', 16, 4, 180, 60, ['b2', 'b3', 'b4', 'b5'], 'Uma sequência por round; últimos 30 s em velocidade'),
      blk('footwork', 'Footwork + esquiva', 12, 4, 150, 30, ['b5'], 'Esquiva e resposta; pivô pra sair da linha'),
      blk('alongamento', 'Volta à calma', 3, 0, 0, 0, [], 'Respiração e alongamento'),
    ],
  },
  {
    id: 'bx30',
    name: 'Rápido — 30 min',
    desc: 'Pra dia corrido: aquece, bate no saco e condiciona.',
    blocks: [
      blk('aquecimento', 'Corda', 5, 0, 0, 0, [], 'Corda leve'),
      blk('saco', 'Saco pesado', 15, 5, 150, 30, ['b1', 'b3', 'b7'], 'Rounds de 2:30; sequência diferente a cada round'),
      blk('condicionamento', 'Condicionamento', 8, 8, 30, 30, [], 'Tabata: burpee · sprint · prancha · polichinelo'),
      blk('alongamento', 'Volta à calma', 2, 0, 0, 0, [], 'Respiração'),
    ],
  },
];
const boxWorkouts = computed(() => {
  const saved = config.value?.boxing?.workouts;
  return saved?.length ? saved : DEFAULT_BOX_WORKOUTS;
});
const blockMinutes = b => {
  const m = Number(b.minutes) || 0;
  if (m) return m;
  const r = Number(b.rounds) || 0;
  // rest_after (rodada 26): descanso depois do último round também conta
  const rests = Math.max(0, r - 1) + (b.rest_after ? 1 : 0);
  return r ? Math.round(((r * (Number(b.round_sec) || 0) + rests * (Number(b.rest_sec) || 0)) / 60) * 10) / 10 : 0;
};
const workoutMinutes = w => Math.round((w.blocks || []).reduce((s, b) => s + blockMinutes(b), 0));
const workoutRounds = w => (w.blocks || []).reduce((s, b) => s + (Number(b.rounds) || 0), 0);
const workoutSeqIds = w => [...new Set((w.blocks || []).flatMap(b => b.seqs || []))];
const fmtClock = sec => {
  const s = Math.max(0, Math.round(sec));
  return `${Math.floor(s / 60)}:${pad2(s % 60)}`;
};

// apito de round (AudioContext nasce no toque do ▶ — regra do iOS)
let audioCtx = null;
const beep = (freq = 880, ms = 160, times = 1) => {
  try {
    audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
    for (let i = 0; i < times; i += 1) {
      const o = audioCtx.createOscillator();
      const g = audioCtx.createGain();
      o.type = 'sine';
      o.frequency.value = freq;
      g.gain.value = 0.25;
      o.connect(g);
      g.connect(audioCtx.destination);
      const t0 = audioCtx.currentTime + i * ((ms + 90) / 1000);
      o.start(t0);
      o.stop(t0 + ms / 1000);
    }
  } catch {
    /* sem áudio: segue em silêncio */
  }
};
let wakeLock = null;
const keepAwake = async () => {
  try {
    wakeLock = await navigator.wakeLock?.request('screen');
  } catch {
    wakeLock = null;
  }
};
const releaseAwake = () => {
  try {
    wakeLock?.release();
  } catch {
    /* ignora */
  }
  wakeLock = null;
};

// sessão guiada: { workout, blockIdx, phase (round|rest|free), round,
// remaining, running, elapsed, done[], date, notes }
const boxSession = ref(null);
let boxTimer = null;
const phaseFor = (block, round) => {
  const rounds = Number(block.rounds) || 0;
  if (rounds && Number(block.round_sec)) return { phase: 'round', round, remaining: Number(block.round_sec) };
  return { phase: 'free', round: 0, remaining: Math.round((Number(block.minutes) || 0) * 60) };
};
const enterBlock = idx => {
  const s = boxSession.value;
  if (!s) return;
  const block = s.workout.blocks[idx];
  if (!block) return;
  s.blockIdx = idx;
  Object.assign(s, phaseFor(block, 1));
};
const startBoxWorkout = w => {
  boxSession.value = {
    workout: JSON.parse(JSON.stringify(w)),
    blockIdx: 0,
    phase: 'free',
    round: 0,
    remaining: 0,
    running: false,
    elapsed: 0,
    done: (w.blocks || []).map(() => false),
    date: todayISO,
    notes: '',
  };
  enterBlock(0);
  window.scrollTo({ top: 0, behavior: 'smooth' });
};
const boxBlock = computed(() => boxSession.value?.workout.blocks[boxSession.value.blockIdx] || null);
const boxIsLast = computed(
  () => !!boxSession.value && boxSession.value.blockIdx >= boxSession.value.workout.blocks.length - 1
);
const stopBoxTimer = () => {
  clearInterval(boxTimer);
  boxTimer = null;
  if (boxSession.value) boxSession.value.running = false;
  releaseAwake();
};
const nextBoxBlock = () => {
  const s = boxSession.value;
  if (!s) return;
  s.done[s.blockIdx] = true;
  if (boxIsLast.value) {
    stopBoxTimer();
    beep(660, 220, 3);
    return;
  }
  enterBlock(s.blockIdx + 1);
  beep(990, 140, 2);
};
const prevBoxBlock = () => {
  const s = boxSession.value;
  if (!s || s.blockIdx === 0) return;
  enterBlock(s.blockIdx - 1);
};
const tickBox = () => {
  const s = boxSession.value;
  if (!s || !s.running) return;
  s.elapsed += 1;
  if (s.remaining > 0) {
    s.remaining -= 1;
    if (s.remaining === 3 || s.remaining === 2 || s.remaining === 1) beep(720, 90);
    if (s.remaining > 0) return;
  }
  // acabou o tempo desta fase
  const block = boxBlock.value;
  const rounds = Number(block?.rounds) || 0;
  if (s.phase === 'round') {
    if (s.round >= rounds) {
      // rodada 26: bloco = 1 round (professor/plano de luta) → descansa
      // antes do próximo bloco, como entre rounds de uma luta
      if (block.rest_after && Number(block.rest_sec) > 0 && !boxIsLast.value) {
        s.phase = 'rest_after';
        s.remaining = Number(block.rest_sec);
        beep(520, 260);
        return;
      }
      nextBoxBlock();
      return;
    }
    if (Number(block.rest_sec) > 0) {
      s.phase = 'rest';
      s.remaining = Number(block.rest_sec);
      beep(520, 260);
      return;
    }
    s.round += 1;
    s.remaining = Number(block.round_sec);
    beep(990, 140, 2);
    return;
  }
  if (s.phase === 'rest_after') {
    nextBoxBlock();
    return;
  }
  if (s.phase === 'rest') {
    s.round += 1;
    s.phase = 'round';
    s.remaining = Number(block.round_sec);
    beep(990, 140, 2);
    return;
  }
  nextBoxBlock();
};
const toggleBoxTimer = () => {
  const s = boxSession.value;
  if (!s) return;
  if (s.running) {
    stopBoxTimer();
    return;
  }
  beep(880, 60); // destrava o áudio no gesto
  s.running = true;
  keepAwake();
  boxTimer = setInterval(tickBox, 1000);
};
const cancelBoxSession = () => {
  stopBoxTimer();
  boxSession.value = null;
};
const boxPct = computed(() => {
  const s = boxSession.value;
  const b = boxBlock.value;
  if (!s || !b) return 0;
  const total = s.phase.startsWith('rest') ? Number(b.rest_sec) : s.phase === 'round' ? Number(b.round_sec) : (Number(b.minutes) || 0) * 60;
  return total ? Math.round(((total - s.remaining) / total) * 100) : 0;
});
// salva o treino guiado (ou "já fiz" direto do card) como registro de boxe
const saveBoxWorkout = async (w, { elapsedSec = 0, done = null, date = todayISO, notes = '' } = {}) => {
  const blocks = (w.blocks || []).map((b, i) => ({
    type: b.type,
    title: b.title,
    minutes: blockMinutes(b),
    done: done ? done[i] !== false : true,
  }));
  const doneBlocks = (w.blocks || []).filter((b, i) => blocks[i].done);
  const planned = workoutMinutes(w);
  const duration = elapsedSec >= 60 ? Math.round(elapsedSec / 60) : planned;
  savingBox.value = true;
  try {
    const { data: rec } = await CrmAPI.createHealthRecord({
      kind: 'boxing',
      record_date: date || todayISO,
      data: {
        duration_min: duration,
        planned_min: planned,
        rounds: doneBlocks.reduce((s, b) => s + (Number(b.rounds) || 0), 0),
        sequences: [...new Set(doneBlocks.flatMap(b => b.seqs || []))],
        workout_id: w.id,
        workout_name: w.name,
        blocks,
        notes: notes?.trim() || '',
      },
    });
    boxings.value = sortRecs([rec, ...boxings.value]);
    useAlert(`🥊 ${w.name} registrado — ${duration} min.`);
    return true;
  } catch {
    useAlert('Não consegui salvar o treino de boxe.');
    return false;
  } finally {
    savingBox.value = false;
  }
};
const finishBoxSession = async () => {
  const s = boxSession.value;
  if (!s) return;
  stopBoxTimer();
  const done = s.done.map((d, i) => d || i <= s.blockIdx);
  const ok = await saveBoxWorkout(s.workout, { elapsedSec: s.elapsed, done, date: s.date, notes: s.notes });
  if (ok) boxSession.value = null;
};
const logBoxWorkoutNow = w => saveBoxWorkout(w);
onUnmounted(stopBoxTimer);

// editor de treinos programados (blocos)
const boxWkForm = ref(null);
const openNewBoxWorkout = () => {
  wkOpen.value = 0;
  boxWkForm.value = {
    id: '',
    name: '',
    desc: '',
    blocks: [
      blk('aquecimento', 'Aquecimento', 10, 0, 0, 0, [], ''),
      blk('sequencias', 'Sequências', 12, 4, 180, 60, [], ''),
      blk('alongamento', 'Volta à calma', 3, 0, 0, 0, [], ''),
    ],
  };
};
const openEditBoxWorkout = w => {
  wkOpen.value = 0;
  boxWkForm.value = JSON.parse(JSON.stringify(w));
};
const addBoxBlock = () => {
  boxWkForm.value.blocks.push(blk('sequencias', '', 0, 3, 180, 60, [], ''));
  wkOpen.value = boxWkForm.value.blocks.length - 1;
};
const removeBoxBlock = i => boxWkForm.value.blocks.splice(i, 1);
const moveBoxBlock = (i, dir) => {
  const list = boxWkForm.value.blocks;
  const j = i + dir;
  if (j < 0 || j >= list.length) return;
  [list[i], list[j]] = [list[j], list[i]];
};
const toggleBlockSeq = (b, id) => {
  const i = (b.seqs || []).indexOf(id);
  if (i >= 0) b.seqs.splice(i, 1);
  else (b.seqs = b.seqs || []).push(id);
};
const saveBoxWorkoutCfg = async () => {
  const f = boxWkForm.value;
  if (!f?.name?.trim()) {
    useAlert('Dê um nome pro treino (ex.: Fundamentos — 60 min).');
    return;
  }
  f.blocks = f.blocks.filter(b => b.title?.trim() || blockMinutes(b) > 0);
  const list = [...boxWorkouts.value];
  const idx = list.findIndex(w => w.id && w.id === f.id);
  if (idx >= 0) list[idx] = f;
  else list.push({ ...f, id: f.id || `bx${Date.now().toString(36)}` });
  const ok = await pushConfig({ ...config.value, boxing: { ...(config.value?.boxing || {}), sequences: boxingSeqs.value, workouts: list } });
  if (ok) {
    boxWkForm.value = null;
    useAlert('🥊 Treino programado salvo.');
  }
};
const deleteBoxWorkoutCfg = async () => {
  const list = boxWorkouts.value.filter(w => w.id !== boxWkForm.value.id);
  const ok = await pushConfig({ ...config.value, boxing: { ...(config.value?.boxing || {}), sequences: boxingSeqs.value, workouts: list } });
  if (ok) {
    boxWkForm.value = null;
    useAlert('Treino removido.');
  }
};
const showManualBox = ref(false);

// ═══ RODADA 28: editor de blocos com OPÇÕES PRÉ-SELECIONÁVEIS + "outro",
// no padrão do plano de luta (acordeão, rótulo à esquerda, campo à direita)
const MIN_PRESETS = [3, 5, 8, 10, 12, 15];
const ROUND_SEC_PRESETS = [60, 90, 120, 150, 180];
const REST_PRESETS = [15, 30, 45, 60, 90];
const wkOpen = ref(0);
const blockMode = b => (Number(b.rounds) > 0 ? 'rounds' : 'min');
const setBlockMode = (b, mode) => {
  if (mode === 'min') {
    b.rounds = 0;
    b.round_sec = 0;
    b.rest_sec = 0;
    if (!Number(b.minutes)) b.minutes = 10;
  } else {
    b.minutes = 0;
    if (!Number(b.rounds)) b.rounds = 3;
    if (!Number(b.round_sec)) b.round_sec = 180;
    if (!Number(b.rest_sec)) b.rest_sec = 60;
  }
};
const blockDurationText = b =>
  blockMode(b) === 'min'
    ? 'tempo corrido'
    : `${b.rounds} × ${fmtClock(Number(b.round_sec) || 0)} · descanso ${b.rest_sec || 0} s`;

// ═══ RODADA 26 · PROFESSOR: montar o treino POR ROUNDS ═══════════════
// "deixar o professor ir lá e criar o treino, considerando o tempo em
// rounds": nº de rounds × segundos + descanso, e o que fazer em cada
// round (foco + sequências + observação). Gera os blocos (1 por round,
// descanso antes do próximo) e abre no editor normal pra ajustar.
const roundsForm = ref(null);
const roundsOpen = ref(0); // acordeão: 1 round aberto por vez (rodada 27)
const copyRoundToAll = i => {
  const src = roundsForm.value.items[i];
  roundsForm.value.items.forEach((it, j) => {
    if (j === i) return;
    it.type = src.type;
    it.seqs = [...src.seqs];
    it.desc = src.desc;
  });
  useAlert('Aplicado aos outros rounds.');
};
const openRoundsBuilder = () => {
  roundsOpen.value = 0;
  roundsForm.value = {
    name: '',
    rounds: 6,
    round_sec: 180,
    rest_sec: 60,
    warmup: 10,
    cooldown: 3,
    items: Array.from({ length: 6 }, (_, i) => ({ type: i === 0 ? 'sombra' : 'sequencias', title: '', seqs: [], desc: '' })),
  };
  boxWkForm.value = null;
};
const setRoundsCount = n => {
  const f = roundsForm.value;
  const count = Math.max(1, Math.min(20, n));
  while (f.items.length < count) f.items.push({ type: 'sequencias', title: '', seqs: [], desc: '' });
  f.items.length = count;
  f.rounds = count;
};
const toggleRoundSeq = (item, id) => {
  const i = item.seqs.indexOf(id);
  if (i >= 0) item.seqs.splice(i, 1);
  else item.seqs.push(id);
};
const roundsTotalMin = computed(() => {
  const f = roundsForm.value;
  if (!f) return 0;
  const core = (f.rounds * f.round_sec + Math.max(0, f.rounds - 1) * f.rest_sec) / 60;
  return Math.round(core + (Number(f.warmup) || 0) + (Number(f.cooldown) || 0));
});
const generateFromRounds = () => {
  const f = roundsForm.value;
  if (!f) return;
  const blocks = [];
  if (Number(f.warmup) > 0) blocks.push(blk('aquecimento', 'Aquecimento', Number(f.warmup), 0, 0, 0, [], 'Corda · mobilidade · sombra leve'));
  f.items.forEach((it, i) => {
    blocks.push({
      ...blk(it.type || 'round', it.title || `Round ${i + 1}`, 0, 1, Number(f.round_sec) || 180, Number(f.rest_sec) || 60, [...it.seqs], it.desc || ''),
      rest_after: i < f.items.length - 1,
    });
  });
  if (Number(f.cooldown) > 0) blocks.push(blk('alongamento', 'Volta à calma', Number(f.cooldown), 0, 0, 0, [], 'Respiração · alongamento'));
  boxWkForm.value = {
    id: '',
    name: f.name.trim() || `Treino do professor — ${f.rounds} rounds`,
    desc: `${f.rounds} rounds × ${Math.round(f.round_sec / 60)} min · descanso ${f.rest_sec} s`,
    blocks,
  };
  roundsForm.value = null;
  useAlert('Blocos gerados — revise e salve.');
};

// ═══ RODADA 26 · PLANO DE LUTA ═══════════════════════════════════════
// "escolher o volume de rounds e planejar a intenção, sequências etc. em
// cada um; salvar com nome (por atleta ou por luta)". Registro
// kind=fight_plan por pessoa; ▶ Treinar vira sessão guiada round a round.
const fpForm = ref(null);
const fpOpen = ref(0); // acordeão dos rounds do plano (rodada 27)
const savingFp = ref(false);
const openNewFightPlan = () => {
  fpForm.value = { id: null, ...blankFightPlan(3) };
  fpOpen.value = 0;
};
const openEditFightPlan = rec => {
  const d = JSON.parse(JSON.stringify(rec.data || {}));
  fpForm.value = { id: rec.id, ...blankFightPlan(Number(d.rounds) || 3), ...d };
  setFpRounds(Number(d.rounds) || 3);
};
const setFpRounds = n => {
  const f = fpForm.value;
  const count = Math.max(1, Math.min(15, n));
  while (f.plan.length < count) f.plan.push({ intent: '', seqs: [], notes: '' });
  f.plan.length = count;
  f.rounds = count;
};
const toggleFpSeq = (r, id) => {
  const i = r.seqs.indexOf(id);
  if (i >= 0) r.seqs.splice(i, 1);
  else r.seqs.push(id);
};
const saveFightPlan = async () => {
  const f = fpForm.value;
  if (!f?.name?.trim()) {
    useAlert('Dê um nome ao plano (ex.: Luta de outubro · João).');
    return;
  }
  savingFp.value = true;
  try {
    const { id, ...raw } = f;
    const data = { ...raw, round_sec: Number(raw.round_sec) || 180, rest_sec: Number(raw.rest_sec) || 0 };
    let rec;
    if (id) {
      ({ data: rec } = await CrmAPI.updateHealthRecord(id, data));
      fightPlans.value = fightPlans.value.map(x => (x.id === rec.id ? rec : x));
    } else {
      ({ data: rec } = await CrmAPI.createHealthRecord({ kind: 'fight_plan', record_date: todayISO, data }));
      fightPlans.value = [rec, ...fightPlans.value];
    }
    fpForm.value = null;
    useAlert(`🥇 Plano "${rec.data?.name}" salvo.`);
  } catch {
    useAlert('Não consegui salvar o plano de luta.');
  } finally {
    savingFp.value = false;
  }
};
const deleteFightPlan = async rec => {
  try {
    await CrmAPI.deleteHealthRecord(rec.id);
    fightPlans.value = fightPlans.value.filter(x => x.id !== rec.id);
    fpForm.value = null;
    useAlert('Plano removido.');
  } catch {
    useAlert('Não consegui remover.');
  }
};
const trainFightPlan = rec => {
  startBoxWorkout(fightPlanToWorkout(rec));
};
const fpSummary = rec => {
  const d = rec.data || {};
  const who = [d.athlete, d.opponent].filter(Boolean).join(' × ');
  return `${d.rounds} × ${Math.round((Number(d.round_sec) || 0) / 60)} min · descanso ${d.rest_sec} s${who ? ` · ${who}` : ''}`;
};

// ═══ RODADA 26 · CARDIO ══════════════════════════════════════════════
// Pré-configurado: tipo (caminhada, corrida, bike, boxe…) + tempo em
// toques, intensidade e distância opcional. 1 registro por sessão.
const cardioForm = ref({ date: todayISO, type: 'caminhada', minutes: 30, km: '', intensity: 'moderado', notes: '' });
const savingCardio = ref(false);
const saveCardio = async () => {
  const minutes = Math.round(toNum(cardioForm.value.minutes));
  if (!minutes) {
    useAlert('Quanto tempo? Toque num dos tempos ou digite os minutos.');
    return;
  }
  savingCardio.value = true;
  try {
    const data = {
      type: cardioForm.value.type,
      minutes,
      intensity: cardioForm.value.intensity,
      notes: cardioForm.value.notes?.trim() || '',
    };
    const km = toNum(cardioForm.value.km);
    if (km > 0) data.km = km;
    const { data: rec } = await CrmAPI.createHealthRecord({
      kind: 'cardio',
      record_date: cardioForm.value.date || todayISO,
      data,
    });
    cardios.value = sortRecs([rec, ...cardios.value]);
    cardioForm.value = { ...cardioForm.value, km: '', notes: '' };
    useAlert(`${cardioType(data.type).icon} ${cardioType(data.type).label} · ${minutes} min registrado!`);
  } catch {
    useAlert('Não consegui salvar o cardio.');
  } finally {
    savingCardio.value = false;
  }
};
const cardioStats = computed(() => ({
  n: cardios.value.length,
  min: cardios.value.reduce((a, c) => a + (Number(c.data?.minutes) || 0), 0),
  km: Math.round(cardios.value.reduce((a, c) => a + (Number(c.data?.km) || 0), 0) * 10) / 10,
}));
const cardioWeekMin = computed(() =>
  cardios.value.filter(c => c.record_date >= daysAgo(6)).reduce((a, c) => a + (Number(c.data?.minutes) || 0), 0)
);
const cardioWeekCount = computed(() => cardios.value.filter(c => c.record_date >= daysAgo(6)).length);
// ═══ RODADA 29: RADAR (teia) nos treinos e planos + MAPEADOR DE ATLETAS ═══
const seqAxes = axesFrom(SEQ_CATEGORIES);
const typeAxes = axesFrom(WORKOUT_TYPE_AXES);
const intentAxes = axesFrom(FIGHT_INTENTS);
const athleteAxes = axesFrom(ATHLETE_AXES);
// treino: prefere o perfil por ETIQUETA (o que ele treina: ataque, esquiva…);
// sem sequências etiquetadas, mostra o perfil por tipo de bloco
const workoutRadar = w => {
  const style = workoutStyleValues(w, boxingSeqs.value);
  if (style) return { axes: seqAxes, datasets: [{ label: 'estilo do treino', color: ROYAL, values: style }] };
  const type = workoutTypeValues(w);
  return type ? { axes: typeAxes, datasets: [{ label: 'perfil do treino', color: ROYAL, values: type }] } : null;
};
const planRadar = fp => {
  const intents = planIntentValues(fp);
  const style = planStyleValues(fp, boxingSeqs.value);
  if (intents) return { axes: intentAxes, datasets: [{ label: 'intenção por round', color: LARANJA, values: intents }] };
  return style ? { axes: seqAxes, datasets: [{ label: 'sequências', color: LARANJA, values: style }] } : null;
};

const athForm = ref(null);
const savingAth = ref(false);
const athFilter = ref('');
const athCompare = ref([]); // até 2 ids
const athletesShown = computed(() =>
  (athFilter.value ? athletes.value.filter(a => a.data?.role === athFilter.value) : athletes.value).slice().sort((a, b) =>
    String(a.data?.name || '').localeCompare(String(b.data?.name || ''))
  )
);
const athCount = role => athletes.value.filter(a => a.data?.role === role).length;
const openNewAthlete = (role = 'aluno') => {
  athForm.value = { id: null, ...blankAthlete(role) };
  window.scrollTo({ top: 0, behavior: 'smooth' });
};
const openEditAthlete = a => {
  athForm.value = { id: a.id, ...blankAthlete(), ...JSON.parse(JSON.stringify(a.data || {})) };
  window.scrollTo({ top: 0, behavior: 'smooth' });
};
const athFormDataset = computed(() => (athForm.value ? [athleteDataset(athForm.value)] : []));
const saveAthlete = async () => {
  const f = athForm.value;
  if (!f?.name?.trim()) {
    useAlert('Dê um nome ao atleta.');
    return;
  }
  savingAth.value = true;
  try {
    const { id, ...data } = f;
    let rec;
    if (id) {
      ({ data: rec } = await CrmAPI.updateHealthRecord(id, data));
      athletes.value = athletes.value.map(x => (x.id === rec.id ? rec : x));
    } else {
      ({ data: rec } = await CrmAPI.createHealthRecord({ kind: 'athlete', record_date: todayISO, data }));
      athletes.value = [rec, ...athletes.value];
    }
    athForm.value = null;
    useAlert(`${rec.data?.name} mapeado.`);
  } catch {
    useAlert('Não consegui salvar o atleta.');
  } finally {
    savingAth.value = false;
  }
};
const deleteAthlete = async id => {
  try {
    await CrmAPI.deleteHealthRecord(id);
    athletes.value = athletes.value.filter(x => x.id !== id);
    athCompare.value = athCompare.value.filter(x => x !== id);
    athForm.value = null;
    useAlert('Atleta removido.');
  } catch {
    useAlert('Não consegui remover.');
  }
};
const toggleCompare = id => {
  const i = athCompare.value.indexOf(id);
  if (i >= 0) athCompare.value.splice(i, 1);
  else athCompare.value = [...athCompare.value.slice(-1), id];
};
const compareDatasets = computed(() =>
  athCompare.value
    .map(id => athletes.value.find(a => a.id === id))
    .filter(Boolean)
    .map((a, i) => athleteDataset(a, i))
);
// "plano contra ele / plano pra ele": abre o plano de luta já preenchido
const planForAthlete = a => {
  openNewFightPlan();
  if (a.data?.role === 'aluno') fpForm.value.athlete = a.data.name;
  else fpForm.value.opponent = a.data.name;
  fpForm.value.name = a.data?.role === 'aluno' ? `Plano · ${a.data.name}` : `Contra ${a.data.name}`;
  boxView.value = 'planos';
  window.scrollTo({ top: 0, behavior: 'smooth' });
};
const cardioByType = computed(() => {
  const acc = {};
  cardios.value
    .filter(c => c.record_date >= daysAgo(29))
    .forEach(c => {
      const k = c.data?.type || 'outro';
      acc[k] = acc[k] || { min: 0, n: 0, km: 0 };
      acc[k].min += Number(c.data?.minutes) || 0;
      acc[k].n += 1;
      acc[k].km += Number(c.data?.km) || 0;
    });
  const max = Math.max(1, ...Object.values(acc).map(v => v.min));
  return Object.entries(acc)
    .map(([k, v]) => ({ key: k, ...cardioType(k), ...v, pct: Math.round((v.min / max) * 100) }))
    .sort((a, b) => b.min - a.min);
});

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
  progress: { label: '▲', color: VERDE_OK, title: 'progrediu' },
  tie: { label: '▬', color: CINZA, title: 'empatou' },
  regress: { label: '▼', color: VERMELHO, title: 'regrediu' },
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
  { key: 'kcal', label: 'Calorias', suffix: ' kcal', cor: LARANJA },
  { key: 'protein', label: 'Proteína', suffix: 'g', cor: ROYAL },
  { key: 'carbs', label: 'Carbo', suffix: 'g', cor: ROYAL_CLARO },
  { key: 'fat', label: 'Gordura', suffix: 'g', cor: LARANJA_CLARO },
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
// lista única em warrior.js (rodada 25); step/max alimentam a roleta
// (rodada 12): peso de 0,1 em 0,1 kg; circunferências até 220 cm
const MEASURES = MEASURE_DEFS.map(m => ({
  key: m.key,
  label: m.label,
  suffix: ` ${m.unit}`,
  step: 0.1,
  max: m.key === 'weight' ? 200 : 220,
}));
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
    // rodada 25: anima o que andou na direção certa
    celebrate(bodyCelebration({ bodies: bodies.value, record: rec }));
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
    if (record.kind === 'program') personalPrograms.value = personalPrograms.value.filter(r => r.id !== record.id);
    if (record.kind === 'cardio') cardios.value = cardios.value.filter(c => c.id !== record.id);
    if (record.kind === 'fight_plan') fightPlans.value = fightPlans.value.filter(f => f.id !== record.id);
    if (record.kind === 'athlete') athletes.value = athletes.value.filter(a => a.id !== record.id);
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
    profile.value = payload.profile || {};
    personalPrograms.value = payload.programs || [];
    workouts.value = payload.workouts || [];
    boxings.value = payload.boxings || [];
    cardios.value = payload.cardios || [];
    fightPlans.value = payload.fight_plans || [];
    athletes.value = payload.athletes || [];
    diets.value = payload.diets || [];
    bodies.value = payload.bodies || [];
    const latest = bodies.value[0]?.data || {};
    MEASURES.forEach(m => {
      if (latest[m.key]) bodyForm.value[m.key] = latest[m.key];
    });
    // rodada 20: veio do botão "▶ Treino X de hoje" do painel → a sessão
    // já abre pronta (2 toques do painel até a 1ª série)
    const startKey = String(route.query?.start || '');
    if (startKey && program.value) {
      const def = (programCycle.value?.sessions || []).find(x => x.key === startKey);
      if (def) startProgramSession(def);
      router.replace({ name: route.name, params: route.params });
    }
  } catch {
    useAlert('Não consegui carregar o painel de saúde.');
  } finally {
    isLoading.value = false;
  }
});
</script>

<template>
  <div class="hub-page flex flex-col h-full w-full overflow-y-auto bg-n-surface-1" :class="{ 'hub-snap': session }">
    <div class="max-w-5xl mx-auto w-full p-4 pb-20 sm:p-8 md:pb-8">
      <!-- Header (rodada 20: título = a aba atual; sem fileira de KPIs) -->
      <div class="flex items-center gap-3 flex-wrap mb-4">
        <span
          class="w-9 h-9 rounded-xl flex items-center justify-center"
          :style="{ background: GRAD_NOITE }"
        >
          <span class="i-lucide-heart-pulse text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="hub-h1">{{ currentTabLabel }}</h1>
          <p class="text-xs text-n-slate-10">Saúde · seu painel pessoal</p>
        </div>
      </div>

      <div v-if="isLoading" class="flex justify-center py-16"><Spinner /></div>

      <template v-else>
        <!-- Pílulas de aba (no celular a barra de abas do rodapé faz isso) -->
        <div class="hidden md:block mb-5">
          <div class="hub-seg">
            <button v-for="t in TABS" :key="t.key" :class="{ 'is-on': tab === t.key }" @click="goTab(t.key)">
              <span :class="t.icon" />{{ t.label }}
            </button>
          </div>
        </div>

        <!-- ═══ TREINO ═══ -->
        <template v-if="tab === 'treino'">
          <!-- rodada 25: ESCOLHA DO PROGRAMA — Warrior (como está) ×
               meu treino (criado/importado, com histórico próprio) -->
          <div v-if="!session && !wizard" class="flex items-center gap-1.5 flex-wrap mb-3">
            <button
              v-if="warriorPrograms.length"
              class="h-9 px-3 rounded-full text-xs font-bold border transition"
              :class="programMode === 'warrior' ? 'text-white border-transparent' : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
              :style="programMode === 'warrior' ? { background: GRAD_NOITE } : {}"
              :disabled="savingProfile"
              @click="chooseWarrior"
            >
              🛡 Warrior
            </button>
            <button
              v-for="rec in activePersonal"
              :key="rec.id"
              class="h-9 px-3 rounded-full text-xs font-bold border transition"
              :class="programMode === 'custom' && Number(profile.active_program_id) === rec.id ? 'text-white border-transparent' : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
              :style="programMode === 'custom' && Number(profile.active_program_id) === rec.id ? { background: GRAD_LARANJA } : {}"
              :disabled="savingProfile"
              @click="choosePersonal(rec)"
            >
              ✨ {{ rec.data?.name }}
            </button>
            <button
              class="h-9 px-3 rounded-full text-xs font-bold border border-dashed border-n-weak hover:bg-n-alpha-1"
              :style="{ color: LARANJA_VIVO }"
              @click="openWizard()"
            >
              + Criar / importar treino
            </button>
            <button
              v-if="personalPrograms.length"
              class="h-9 px-3 rounded-full text-xs font-medium text-n-slate-11 border border-n-weak hover:bg-n-alpha-1 ml-auto"
              @click="historyOpen = !historyOpen"
            >
              📜 Histórico ({{ personalPrograms.length }})
            </button>
          </div>

          <!-- rodada 27: visualizações da aba Treino -->
          <div v-if="!session && !wizard && program" class="hub-seg hub-seg-full mb-4">
            <button v-for="v in TREINO_VIEWS" :key="v.key" :class="{ 'is-on': treinoView === v.key }" @click="treinoView = v.key">
              <span :class="v.ico" />{{ v.label }}
            </button>
          </div>

          <ProgramWizard
            v-if="wizard"
            :initial="wizard.record?.data || null"
            :known-exercises="knownExerciseNames"
            :saving="savingWizard"
            @save="saveWizard"
            @cancel="wizard = null"
          />

          <!-- histórico dos programas pessoais (pra vida toda) -->
          <div v-if="historyOpen && !session && !wizard" class="hub-block p-5 mb-8">
            <h2 class="hub-h2 mb-1"><span class="hub-h-ico i-lucide-scroll-text" />Meus programas</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">Cada bloco que você fez, com o resultado no parâmetro que você escolheu.</p>
            <div class="flex flex-col gap-2">
              <div
                v-for="h in programHistory"
                :key="h.rec.id"
                class="rounded-xl border p-3 flex items-start gap-3 flex-wrap"
                :class="h.isActive ? '' : 'border-n-weak'"
                :style="h.isActive ? { borderColor: LARANJA, background: 'rgba(255,138,0,0.06)' } : {}"
              >
                <span class="w-10 h-10 rounded-xl flex items-center justify-center text-xl shrink-0" :style="{ background: h.status === 'active' ? GRAD_LARANJA : GRAD_NOITE }">{{ h.goal.icon }}</span>
                <div class="flex-1 min-w-0">
                  <p class="hub-h2">
                    {{ h.name }}
                    <span v-if="h.isActive" class="ml-1 px-2 py-0.5 rounded-full text-[10px] text-white" :style="{ background: LARANJA }">ativo</span>
                    <span v-else-if="h.status === 'finished'" class="ml-1 px-2 py-0.5 rounded-full text-[10px] bg-n-alpha-2 text-n-slate-11">encerrado</span>
                  </p>
                  <p class="text-[11px] text-n-slate-10">
                    {{ h.split }} · {{ h.weeks }} semanas · {{ h.period }} · <b>{{ h.done }}</b> treinos feitos · objetivo {{ h.goal.label }}
                  </p>
                  <p v-if="h.result" class="text-[11px] mt-1" :style="{ color: ROYAL }">🏁 {{ h.result }}</p>
                  <p v-else-if="h.live && !h.live.none" class="text-[11px] mt-1" :style="{ color: h.live.ok ? ROYAL : LARANJA_VIVO }">
                    {{ h.live.icon }} {{ h.live.value }} · {{ h.live.detail }}
                  </p>
                </div>
                <div class="flex gap-1.5 flex-wrap">
                  <button v-if="h.status === 'active' && !h.isActive" class="h-8 px-2.5 rounded-lg text-[11px] font-bold text-white" :style="{ background: ROYAL }" @click="choosePersonal(h.rec)">▶ Usar</button>
                  <button v-if="h.status === 'active'" class="h-8 px-2.5 rounded-lg text-[11px] border border-n-weak hover:bg-n-alpha-1" @click="openWizard(h.rec)">✎</button>
                  <button v-if="h.status === 'active'" class="h-8 px-2.5 rounded-lg text-[11px] border border-n-weak hover:bg-n-alpha-1" title="Encerrar e guardar o resultado" @click="finishProgram(h.rec)">🏁</button>
                  <button v-if="h.status !== 'active' && !h.done" class="h-8 px-2.5 rounded-lg text-[11px] text-n-slate-10 hover:bg-n-alpha-1" title="Remover (só sem treinos feitos)" @click="deleteProgram(h.rec)">🗑</button>
                </div>
              </div>
            </div>
          </div>

          <!-- sem programa (modo pessoal sem nenhum ativo) -->
          <div v-if="!program && !session && !wizard" class="hub-block p-5 mb-8 text-center">
            <p class="text-2xl mb-1">✨</p>
            <p class="hub-h2 mb-1">Nenhum programa ativo</p>
            <p class="text-[11px] text-n-slate-10 mb-3">Monte o seu (ABC, ABCD…) ou cole um treino pronto — leva 2 minutos.</p>
            <button class="h-10 px-5 rounded-xl text-xs font-bold text-white" :style="{ background: GRAD_LARANJA }" @click="openWizard()">+ Criar / importar treino</button>
          </div>

          <!-- Programa ativo (Warrior ou pessoal) -->
          <div v-if="program && !session && !wizard && treinoView === 'treinar'" class="hub-block p-5 mb-8">
            <div class="flex items-center justify-between flex-wrap gap-2 mb-1">
              <h2 class="hub-h2"><span class="hub-h-ico i-lucide-dumbbell" />{{ program.name }}</h2>
              <div v-if="programs.length > 1" class="flex gap-1.5">
                <button
                  v-for="p in programs"
                  :key="p.id"
                  class="h-7 px-2.5 rounded-full text-[11px] font-medium border"
                  :class="p.active ? 'text-white border-transparent' : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
                  :style="p.active ? { background: ROYAL } : {}"
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
            <!-- rodada 25: objetivo do programa pessoal = parâmetro de sucesso -->
            <div v-if="program.custom && goalNow" class="rounded-xl p-3 mb-3 flex items-center gap-3 flex-wrap" :style="{ background: 'rgba(65,105,225,0.08)', border: '1px solid rgba(65,105,225,0.25)' }">
              <span class="text-2xl">{{ goalNow.icon }}</span>
              <div class="flex-1 min-w-0" style="min-width: 10rem">
                <p class="text-[11px] text-n-slate-10">Objetivo: <b>{{ goalNow.label }}</b> · semana {{ goalNow.week }} de {{ goalNow.weeks }}</p>
                <p class="text-lg font-extrabold leading-tight" :style="{ color: goalNow.none ? CINZA : goalNow.ok ? ROYAL : LARANJA_VIVO }">{{ goalNow.value }}</p>
                <p class="text-[10px] text-n-slate-10">{{ goalNow.detail }}</p>
                <div class="h-1.5 rounded-full bg-n-alpha-2 mt-1.5 overflow-hidden">
                  <div class="h-full rounded-full" :style="{ width: `${Math.round(goalNow.pct * 100)}%`, background: GRAD_LARANJA }" />
                </div>
              </div>
              <div class="flex gap-1.5">
                <button class="h-8 px-2.5 rounded-lg text-[11px] border border-n-weak hover:bg-n-alpha-1" @click="openWizard(personalPrograms.find(r => r.id === program.record_id))">✎ editar</button>
                <button class="h-8 px-2.5 rounded-lg text-[11px] border border-n-weak hover:bg-n-alpha-1" title="Encerrar e guardar no histórico" @click="finishProgram(personalPrograms.find(r => r.id === program.record_id))">🏁 encerrar</button>
              </div>
            </div>
            <!-- rodada 23: todos os treinos são cartões de vidro; o da vez
                 (do dia ou o próximo) vem em laranja sólido pulsando -->
            <div class="grid gap-3" style="grid-template-columns: repeat(auto-fit, minmax(150px, 1fr))">
              <div
                v-for="s in programCycle?.sessions || []"
                :key="s.key"
                class="hub-block hub-block-hover hub-session-card p-4 flex flex-col gap-2"
                :class="s.key === nextKey ? 'hub-orange hub-block-solid hub-block-today is-next' : ''"
                role="button"
                @click="startProgramSession(s)"
              >
                <div class="flex items-start justify-between gap-2">
                  <span
                    class="w-10 h-10 rounded-xl flex items-center justify-center text-xl font-black shrink-0"
                    :style="s.key === nextKey ? { background: '#fff', color: LARANJA_VIVO } : { background: GRAD_NOITE, color: '#fff' }"
                  >
                    {{ s.key }}
                  </span>
                  <span
                    v-if="s.key === nextKey"
                    class="px-2 py-0.5 rounded-full text-[10px] font-bold"
                    style="background: rgba(255, 255, 255, 0.24)"
                  >
                    {{ isTodaySession(s) ? 'HOJE' : '▶ próximo' }}
                  </span>
                  <button
                    v-else
                    class="w-7 h-7 rounded-lg text-n-slate-10 hover:bg-n-alpha-1"
                    title="Editar exercícios deste treino"
                    @click.stop="openExerciseEditor(s)"
                  >
                    ✎
                  </button>
                </div>
                <div>
                  <p class="text-sm font-extrabold leading-tight">Treino {{ s.key }}<span v-if="s.label" class="font-semibold opacity-80"> · {{ s.label }}</span></p>
                  <p class="text-[11px]" :class="s.key === nextKey ? 'opacity-90' : 'text-n-slate-10'">
                    {{ s.weekday }} · {{ (s.exercises || []).length }} exercícios
                  </p>
                </div>
                <p class="text-[11px] font-bold" :style="s.key === nextKey ? {} : { color: ROYAL }">
                  {{ s.key === nextKey ? '▶ Começar agora' : '▶ Fazer este' }}
                </p>
                <button
                  v-if="s.key === nextKey"
                  class="self-start text-[10px] underline opacity-90"
                  @click.stop="openExerciseEditor(s)"
                >
                  ✎ editar exercícios
                </button>
              </div>
            </div>
          </div>

          <!-- Editor de exercícios da prescrição -->
          <div v-if="exEditor" class="hub-block p-5 mb-8">
            <div class="flex items-center justify-between gap-2 flex-wrap mb-1">
              <span class="text-sm font-bold" :style="{ color: ROYAL }">✎ {{ exEditor.title }}</span>
              <button
                class="h-8 px-3 rounded-lg text-xs text-n-slate-11 border border-n-weak hover:bg-n-alpha-1"
                @click="exEditor = null"
              >
                Cancelar
              </button>
            </div>
            <p class="text-[11px] text-n-slate-10 mb-3">
              <b>Chavinha</b> = as opções de equipamento do exercício, separadas por <b>|</b>
              (ex.: <b>barra | halteres | máquina</b>) — a 1ª é a principal e cada uma guarda as
              próprias cargas. Vazio = opções automáticas pelo nome; só 1 opção = sem chavinha.
              <b>Peso comum</b>: escreva o fator com ×, ex. <b>halteres ×2</b> (cada lado vira total) ou
              <b>máquina ×0,85</b>; sem fator, a máquina é calibrada sozinha pela sua força.
              <b>Renomear</b> vale como substituição: o exercício novo começa histórico do zero.
            </p>
            <div class="flex flex-col gap-2 mb-3">
              <div
                v-for="(row, i) in exEditor.rows"
                :key="i"
                class="flex items-center gap-1.5 flex-wrap hub-crystal rounded-xl p-3"
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
                  v-model="row._variants"
                  type="text"
                  placeholder="chavinha: barra | halteres ×2 | máquina ×0,85"
                  title="Opções da chavinha separadas por | — vazio = automático pelo nome; 1 opção = sem chavinha. ×n = fator do peso comum (halteres ×2; sem fator a máquina é calibrada pelo histórico)"
                  class="h-9 rounded-lg border border-dashed border-n-weak bg-n-solid-2 px-2 text-[11px] text-n-slate-11"
                  style="width: 15rem; margin-bottom: 0"
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
                :style="{ background: GRAD_ROYAL }"
                :disabled="savingConfig"
                @click="saveExerciseEditor"
              >
                {{ savingConfig ? 'Salvando…' : '✓ Salvar treino' }}
              </button>
            </div>
          </div>

          <!-- Sessão em andamento -->
          <div v-if="session" class="hub-block p-5 mb-8">
            <div class="flex items-center justify-between gap-2 flex-wrap mb-2">
              <span class="text-sm font-bold" :style="{ color: ROYAL }">{{ session.plan_name }}</span>
              <button
                class="h-8 px-3 rounded-lg text-xs text-n-slate-11 border border-n-weak hover:bg-n-alpha-1"
                @click="session = null"
              >
                Cancelar
              </button>
            </div>

            <!-- Data em destaque: registro retroativo muda a semana junto -->
            <div class="flex items-center gap-2 flex-wrap mb-3 hub-crystal rounded-xl px-4 py-3">
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
                :style="{ background: ROYAL }"
              >
                Semana {{ session.week }}
              </span>
              <span class="text-[10px] text-n-slate-10">treinou outro dia? troque a data</span>
            </div>

            <!-- modo de entrada (rodada 16): roletas ou digitar -->
            <div class="flex items-center justify-between gap-2 flex-wrap mb-3">
              <p class="text-[11px] text-n-slate-10 flex-1" style="min-width: 12rem">
                <template v-if="inputMode === 'wheel'">
                  <b>Role as roletas</b> até o valor de hoje: <b>carga (kg) × reps</b> — já vêm na
                  última execução. O chip cinza é o da <b>última vez</b>; tocar nele traz a roleta de volta.
                </template>
                <template v-else>
                  <b>Digite</b> carga (kg) × reps de cada série — as caixinhas já vêm com a última
                  execução. O chip cinza é o da <b>última vez</b>; tocar nele recoloca o valor.
                </template>
              </p>
              <span class="hub-switch shrink-0" title="Como você prefere lançar as séries">
                <button
                  class="hub-switch-opt"
                  :class="{ 'is-on': inputMode === 'wheel' }"
                  :style="inputMode === 'wheel' ? { background: ROYAL } : {}"
                  @click="setInputMode('wheel')"
                >
                  🎡 Roletas
                </button>
                <button
                  class="hub-switch-opt"
                  :class="{ 'is-on': inputMode === 'type' }"
                  :style="inputMode === 'type' ? { background: ROYAL } : {}"
                  @click="setInputMode('type')"
                >
                  ⌨️ Digitar
                </button>
              </span>
            </div>

            <!-- 1 exercício ≈ 1 tela no celular (pedido 30/08): o card
                 ocupa ~80% do viewport e o scroll "trava" nele — a tela
                 fica parada no exercício durante o treino -->
            <div v-for="ex in session.exercises" :key="ex.name" class="hub-ex-card mb-5 hub-crystal rounded-2xl p-5 sm:p-6">
              <div class="flex items-start justify-between gap-2 mb-1">
                <h3 class="text-lg font-extrabold leading-snug text-n-slate-12">
                  {{ ex.displayName || ex.name }}
                  <span
                    v-if="ex.extra"
                    class="ml-1 px-1.5 py-0.5 rounded-full text-[10px] font-bold border border-dashed align-middle"
                    :style="{ color: LARANJA, borderColor: LARANJA }"
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
                <span v-if="ex.options?.length > 1" class="hub-switch">
                  <button
                    v-for="t in ex.options"
                    :key="t"
                    class="hub-switch-opt"
                    :class="{ 'is-on': normTag(ex.tag) === normTag(t) }"
                    :style="normTag(ex.tag) === normTag(t) ? { background: ROYAL } : {}"
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
                  :style="{ background: ex.method === 'rest_pause' ? LARANJA_VIVO : ex.method === 'pyramid' ? LARANJA : ROYAL }"
                  :title="METHOD_HINTS[ex.method]"
                >
                  {{ METHOD_LABELS[ex.method] || ex.method }}
                </span>
                <span class="text-[11px] text-n-slate-10">{{ ex.scheme }}</span>
              </div>
              <p v-if="ex.options?.length > 1 && commonNote(ex)" class="text-[10px] mb-2" :style="{ color: ROYAL }" title="Peso comum: todas as variações na mesma escala (halteres ×2 = cada lado vira total)">
                ⚖ {{ commonNote(ex) }}
              </p>
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
                  :style="{ color: ex.hint.startsWith('🎯') ? LARANJA : ROYAL }"
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
                  <div v-if="inputMode === 'wheel'" class="flex items-center gap-2 shrink-0">
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
                  <div v-else class="flex items-center gap-2 shrink-0">
                    <input
                      v-model="set.load"
                      type="text"
                      inputmode="decimal"
                      :placeholder="set.prev ? String(set.prev.load).replace('.', ',') : 'kg'"
                      class="hub-type-input"
                      style="width: 5rem"
                    />
                    <span class="text-base text-n-slate-10">×</span>
                    <input
                      v-model="set.reps"
                      type="text"
                      inputmode="numeric"
                      :placeholder="set.prev ? String(set.prev.reps) : set.range || 'reps'"
                      class="hub-type-input"
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
              <div v-else class="rounded-xl border border-dashed border-n-weak p-3">
                <!-- extras recentes: 1 toque adiciona com as cargas e a técnica da última vez -->
                <div v-if="recentExtras.length" class="mb-2.5">
                  <p class="text-[11px] font-medium text-n-slate-11 mb-1.5">Seus extras recentes — toque pra adicionar</p>
                  <div class="flex gap-1.5 flex-wrap">
                    <button
                      v-for="x in recentExtras"
                      :key="x.name"
                      class="hub-extra-chip"
                      :title="`Última vez ${fmtDay(x.date)} · ${METHOD_LABELS[x.method]} · ${fmtSets(x.sets)}`"
                      @click="pickExtra(x)"
                    >
                      <b>{{ x.name }}</b>
                      <span class="opacity-70">{{ fmtSets(x.sets) }}</span>
                    </button>
                  </div>
                </div>
                <div class="flex items-center gap-2 flex-wrap mb-1.5">
                  <input
                    v-model="extraName"
                    type="text"
                    list="hub-extra-exercicios"
                    placeholder="Ou digite: Crucifixo na máquina, Panturrilha em pé…"
                    class="flex-1 h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                    style="min-width: 12rem; margin-bottom: 0"
                    @keyup.enter="addExtraExercise"
                  />
                  <datalist id="hub-extra-exercicios">
                    <option v-for="n in extraSuggestions" :key="n" :value="n" />
                  </datalist>
                  <button
                    class="h-9 px-2 rounded-lg text-xs text-n-slate-10 border border-n-weak hover:bg-n-alpha-1"
                    @click="extraOpen = false; extraName = ''"
                  >
                    ✕
                  </button>
                </div>
                <!-- prévia: o que foi feito da última vez com esse nome -->
                <p v-if="extraPreview" class="text-[11px] mb-2" :style="{ color: ROYAL }">
                  ↩ Última vez {{ fmtDay(extraPreview.date) }} · {{ METHOD_LABELS[extraPreview.method || 'sets'] }} ·
                  <b>{{ fmtSets(extraPreview.sets) }}</b> — as caixinhas já vêm assim.
                </p>
                <p v-else-if="extraName.trim()" class="text-[11px] text-n-slate-10 mb-2">
                  Primeira vez com esse nome — vai nascer nas faixas da técnica.
                </p>
                <!-- técnica (rodada 16): o extra já nasce pré-configurado -->
                <p class="text-[11px] font-medium text-n-slate-11 mb-1.5">Técnica</p>
                <div class="flex items-center gap-2 flex-wrap">
                  <span class="hub-switch">
                    <button
                      v-for="m in EXTRA_METHODS"
                      :key="m.key"
                      class="hub-switch-opt"
                      :class="{ 'is-on': extraMethodKey === m.key }"
                      :style="extraMethodKey === m.key ? { background: m.key === 'rest_pause' ? LARANJA_VIVO : m.key === 'pyramid' ? LARANJA : ROYAL } : {}"
                      :title="m.desc"
                      @click="extraMethodKey = m.key"
                    >
                      {{ m.label }}
                    </button>
                  </span>
                  <span class="text-[11px] text-n-slate-10">{{ extraPreset.desc }}</span>
                  <div class="flex-1" />
                  <button
                    class="h-9 px-4 rounded-lg text-xs font-bold text-white disabled:opacity-60"
                    :style="{ background: GRAD_LARANJA }"
                    :disabled="!extraName.trim()"
                    @click="addExtraExercise"
                  >
                    Adicionar
                  </button>
                </div>
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
              class="w-full h-11 rounded-xl text-sm font-bold text-white disabled:opacity-60 shadow-lg"
              :style="{ background: GRAD_LARANJA }"
              :disabled="savingSession"
              @click="saveSession"
            >
              {{ savingSession ? 'Salvando…' : '✓ Concluir treino' }}
            </button>
          </div>

          <!-- Planilha das semanas: A | B | C | Bônus -->
          <div v-if="gridTabs.length && !session && !wizard && treinoView === 'planilha'" class="hub-block p-5 mb-8">
            <div class="flex items-center justify-between flex-wrap gap-2 mb-2">
              <h2 class="hub-h2"><span class="hub-h-ico i-lucide-table" />Planilha das semanas</h2>
              <div class="flex gap-1.5 flex-wrap">
                <button
                  v-for="t in gridTabs"
                  :key="t.key"
                  class="h-9 px-3 rounded-lg text-xs font-bold border"
                  :class="gridTab?.key === t.key ? 'text-white border-transparent' : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
                  :style="gridTab?.key === t.key ? { background: GRAD_ROYAL } : {}"
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
                      :class="gridTab?.programId === mainProgram?.id && w === programWeek ? '' : 'text-n-slate-11'"
                      :style="gridTab?.programId === mainProgram?.id && w === programWeek ? { color: ROYAL } : {}"
                    >
                      S{{ w }}
                      <span v-if="gridTab?.programId === mainProgram?.id && w === programWeek">•</span>
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
          <div v-if="!session && !wizard && treinoView === 'historico'" class="hub-block p-5 mb-8">
            <div class="flex items-center justify-between mb-3 flex-wrap gap-2">
              <h2 class="hub-h2"><span class="hub-h-ico i-lucide-trending-up" />Evolução de carga</h2>
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
              :color="ROYAL"
              :height="110"
              :format="v => `${fmtNum(v)} kg`"
            />
            <p v-else class="text-xs text-n-slate-10">
              Escolha um exercício com treinos registrados pra ver a carga máxima por sessão.
            </p>
          </div>

          <!-- Histórico (rodada 27: seção própria, lista agrupada por mês) -->
          <div v-if="!session && !wizard && treinoView === 'historico'" class="hub-block p-5 mb-8">
            <div class="hub-sec">
              <span class="hub-sec-ico"><span class="i-lucide-history" /></span>
              <div class="hub-sec-text">
                <h2 class="hub-sec-title">Histórico de treinos</h2>
                <p class="hub-sec-sub">{{ workouts.length }} treinos registrados · toque no ✕ pra remover</p>
              </div>
            </div>
            <p v-if="!workouts.length" class="text-xs text-n-slate-10">Nenhum treino registrado ainda.</p>
            <div v-else class="hub-list">
              <template v-for="g in groupByMonth(workouts.slice(0, 80))" :key="g.key">
                <div class="hub-month">{{ g.label }}</div>
                <div v-for="w in g.items" :key="w.id" class="hub-row">
                  <span class="hub-row-date"><b>{{ dayOf(w.record_date) }}</b><small>{{ monOf(w.record_date) }}</small></span>
                  <div class="flex-1 min-w-0">
                    <p class="text-xs font-bold text-n-slate-12 truncate">
                      {{ w.data?.plan_name || 'Treino' }}<span v-if="w.data?.week" class="font-normal text-n-slate-10"> · semana {{ w.data.week }}</span>
                    </p>
                    <p class="text-[11px] text-n-slate-10 truncate">{{ (w.data?.exercises || []).filter(e => !e.skipped).map(e => e.name).join(' · ') || '—' }}</p>
                  </div>
                  <span v-if="w.data?.summary" class="text-[11px] font-bold whitespace-nowrap hidden sm:inline">
                    <span :style="{ color: ROYAL }">▲{{ w.data.summary.progress || 0 }}</span>
                    <span class="text-n-slate-10 mx-1">▬{{ w.data.summary.tie || 0 }}</span>
                    <span :style="{ color: LARANJA_VIVO }">▼{{ w.data.summary.regress || 0 }}</span>
                  </span>
                  <button class="w-8 h-8 rounded-lg text-n-slate-10 hover:bg-n-alpha-1 shrink-0 flex items-center justify-center" title="Remover" @click="deleteRecord(w)">
                    <span class="i-lucide-x" style="width: 14px; height: 14px" />
                  </button>
                </div>
              </template>
            </div>
          </div>

          <!-- Fichas avulsas (fora do programa) -->
          <div v-if="!session && !wizard && treinoView === 'treinar'" class="hub-block p-5">
            <div class="flex items-center justify-between">
              <button class="hub-h2" @click="showFichas = !showFichas">
                {{ showFichas ? '▾' : '▸' }} Fichas avulsas
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
              <div v-if="planForm" class="mt-3 hub-crystal rounded-xl p-4">
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
                    :style="{ background: GRAD_ROYAL }"
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
        <!-- ═══ CARDIO (rodada 26 · reorganizado na 27) ═══ -->
        <template v-if="tab === 'cardio'">
          <div class="hub-seg hub-seg-full mb-4">
            <button v-for="v in CARDIO_VIEWS" :key="v.key" :class="{ 'is-on': cardioView === v.key }" @click="cardioView = v.key">
              <span :class="v.ico" />{{ v.label }}
            </button>
          </div>

          <div v-if="cardioView === 'registrar'" class="hub-block p-5 mb-8">
            <div class="hub-sec">
              <span class="hub-sec-ico"><span class="i-lucide-heart-pulse" /></span>
              <div class="hub-sec-text">
                <h2 class="hub-sec-title">Registrar cardio</h2>
                <p class="hub-sec-sub">tipo, tempo, intensidade — pronto. {{ cardioWeekMin }} min em {{ cardioWeekCount }} sessões nos últimos 7 dias</p>
              </div>
            </div>
            <p class="hub-label">Tipo</p>
            <div class="hub-grid-4 mb-4">
              <button
                v-for="t in CARDIO_TYPES"
                :key="t.key"
                class="hub-cardio-type"
                :class="{ 'is-on': cardioForm.type === t.key }"
                @click="cardioForm.type = t.key"
              >
                <span :class="t.ico" class="hub-cardio-ico" />
                <span>{{ t.label }}</span>
              </button>
            </div>
            <div class="hub-grid-2 mb-4">
              <div>
                <p class="hub-label">Tempo</p>
                <div class="flex items-center gap-1.5 flex-wrap">
                  <button
                    v-for="m in CARDIO_DURATIONS"
                    :key="m"
                    class="hub-tag"
                    :class="{ 'is-on': Number(cardioForm.minutes) === m }"
                    @click="cardioForm.minutes = m"
                  >
                    {{ m }} min
                  </button>
                  <input v-model="cardioForm.minutes" type="text" inputmode="numeric" placeholder="outro" class="hub-field" style="width: 5rem" />
                </div>
              </div>
              <div>
                <p class="hub-label">Intensidade</p>
                <div class="flex items-center gap-1.5 flex-wrap">
                  <button
                    v-for="i in CARDIO_INTENSITIES"
                    :key="i.key"
                    class="hub-tag"
                    :class="{ 'is-on': cardioForm.intensity === i.key }"
                    :title="i.hint"
                    @click="cardioForm.intensity = i.key"
                  >
                    {{ i.label }}
                  </button>
                </div>
              </div>
            </div>
            <div class="hub-grid-3 mb-4">
              <label class="block">
                <span class="hub-label" style="margin-bottom: 6px">Data</span>
                <input v-model="cardioForm.date" type="date" class="hub-field hub-field-w" />
              </label>
              <label class="block">
                <span class="hub-label" style="margin-bottom: 6px">Distância (km)</span>
                <input v-model="cardioForm.km" type="text" inputmode="decimal" placeholder="opcional, ex.: 5,2" class="hub-field hub-field-w" />
              </label>
              <label class="block">
                <span class="hub-label" style="margin-bottom: 6px">Observações</span>
                <input v-model="cardioForm.notes" type="text" placeholder="ex.: esteira inclinada 8%" class="hub-field hub-field-w" />
              </label>
            </div>
            <button
              class="h-12 rounded-xl text-sm font-bold text-white disabled:opacity-60 w-full sm:w-auto sm:px-8"
              :style="{ background: GRAD_LARANJA }"
              :disabled="savingCardio"
              @click="saveCardio"
            >
              {{ savingCardio ? 'Salvando…' : `Salvar ${cardioType(cardioForm.type).label} · ${cardioForm.minutes || 0} min` }}
            </button>
          </div>

          <template v-if="cardioView === 'historico'">
            <div class="hub-block p-5 mb-8">
              <div class="hub-sec">
                <span class="hub-sec-ico"><span class="i-lucide-history" /></span>
                <div class="hub-sec-text">
                  <h2 class="hub-sec-title">Histórico de cardio</h2>
                  <p class="hub-sec-sub">tudo que você registrou, mês a mês</p>
                </div>
              </div>
              <div class="hub-grid-3 mb-4">
                <div class="hub-stat"><b>{{ cardioStats.n }}</b><span>sessões</span></div>
                <div class="hub-stat"><b>{{ cardioStats.min }}</b><span>minutos</span></div>
                <div class="hub-stat"><b>{{ String(cardioStats.km).replace('.', ',') }}</b><span>km</span></div>
              </div>
              <template v-if="cardioByType.length">
                <p class="hub-label">Últimos 30 dias por tipo</p>
                <div class="flex flex-col gap-2 mb-4">
                  <div v-for="t in cardioByType" :key="t.key" class="flex items-center gap-3">
                    <span class="hub-sec-ico" style="width: 30px; height: 30px"><span :class="t.ico" style="width: 15px; height: 15px" /></span>
                    <div class="flex-1 min-w-0">
                      <div class="flex items-center justify-between text-[11px]">
                        <b class="text-n-slate-12">{{ t.label }}</b>
                        <span class="text-n-slate-10">{{ t.min }} min · {{ t.n }}×<template v-if="t.km"> · {{ String(Math.round(t.km * 10) / 10).replace('.', ',') }} km</template></span>
                      </div>
                      <div class="h-1.5 rounded-full bg-n-alpha-2 overflow-hidden mt-1">
                        <div class="h-full rounded-full" :style="{ width: `${t.pct}%`, background: GRAD_ROYAL }" />
                      </div>
                    </div>
                  </div>
                </div>
              </template>
              <p v-if="!cardios.length" class="text-xs text-n-slate-10">Nenhum cardio registrado ainda.</p>
              <div v-else class="hub-list">
                <template v-for="g in groupByMonth(cardios.slice(0, 80))" :key="g.key">
                  <div class="hub-month">{{ g.label }}</div>
                  <div v-for="c in g.items" :key="c.id" class="hub-row">
                    <span class="hub-row-date"><b>{{ dayOf(c.record_date) }}</b><small>{{ monOf(c.record_date) }}</small></span>
                    <span class="hub-sec-ico" style="width: 30px; height: 30px"><span :class="cardioType(c.data?.type).ico" style="width: 15px; height: 15px" /></span>
                    <div class="flex-1 min-w-0">
                      <p class="text-xs font-bold text-n-slate-12 truncate">
                        {{ cardioType(c.data?.type).label }} · {{ c.data?.minutes || 0 }} min
                        <span v-if="c.data?.km" class="font-normal text-n-slate-10">· {{ String(c.data.km).replace('.', ',') }} km</span>
                      </p>
                      <p class="text-[11px] text-n-slate-10 truncate">{{ [c.data?.intensity, c.data?.notes].filter(Boolean).join(' · ') || '—' }}</p>
                    </div>
                    <button class="w-8 h-8 rounded-lg text-n-slate-10 hover:bg-n-alpha-1 shrink-0 flex items-center justify-center" title="Remover" @click="deleteRecord(c)">
                      <span class="i-lucide-x" style="width: 14px; height: 14px" />
                    </button>
                  </div>
                </template>
              </div>
            </div>
          </template>
        </template>

        <template v-if="tab === 'boxe'">
          <!-- SESSÃO GUIADA (rodada 20): cronômetro bloco a bloco -->
          <div v-if="boxSession" class="rounded-2xl overflow-hidden mb-4 text-white" :style="{ background: GRAD_NOITE }">
            <div class="p-4 sm:p-5">
              <div class="flex items-center justify-between gap-2 flex-wrap mb-3">
                <div class="min-w-0">
                  <p class="text-[11px] opacity-80">{{ boxSession.workout.name }}</p>
                  <p class="text-xs opacity-80">
                    bloco {{ boxSession.blockIdx + 1 }} de {{ boxSession.workout.blocks.length }} ·
                    {{ fmtClock(boxSession.elapsed) }} de treino
                  </p>
                </div>
                <button class="h-8 px-3 rounded-lg text-xs border border-white/25 hover:bg-white/10" @click="cancelBoxSession">
                  Cancelar
                </button>
              </div>
              <!-- trilha dos blocos -->
              <div class="flex gap-1 mb-4">
                <button
                  v-for="(b, i) in boxSession.workout.blocks"
                  :key="i"
                  class="h-1.5 flex-1 rounded-full transition-all"
                  :style="{ background: i < boxSession.blockIdx || boxSession.done[i] ? LARANJA : i === boxSession.blockIdx ? '#fff' : 'rgba(255,255,255,0.22)' }"
                  :title="b.title || blockMeta(b.type).label"
                  @click="enterBlock(i)"
                />
              </div>
              <!-- bloco atual -->
              <div v-if="boxBlock" class="text-center mb-4">
                <p class="text-[11px] uppercase tracking-wide opacity-80 flex items-center justify-center gap-1.5">
                  <span :class="blockMeta(boxBlock.type).ico" style="width: 13px; height: 13px" />{{ blockMeta(boxBlock.type).label }}
                </p>
                <p class="text-xl font-extrabold leading-tight">{{ boxBlock.title || blockMeta(boxBlock.type).label }}</p>
                <p v-if="boxBlock.desc" class="text-xs opacity-85 mt-1">{{ boxBlock.desc }}</p>
                <p class="text-[11px] mt-1" :style="{ color: LARANJA_CLARO }">
                  <template v-if="boxSession.phase === 'round'">Round {{ boxSession.round }} de {{ boxBlock.rounds }}</template>
                  <template v-else-if="boxSession.phase === 'rest'">Descanso · próximo: round {{ boxSession.round + 1 }} de {{ boxBlock.rounds }}</template>
                  <template v-else-if="boxSession.phase === 'rest_after'">Descanso · próximo: {{ boxSession.workout.blocks[boxSession.blockIdx + 1]?.title || 'próximo bloco' }}</template>
                  <template v-else>{{ blockMinutes(boxBlock) }} min corridos</template>
                </p>
              </div>
              <!-- cronômetro grande -->
              <div class="relative mx-auto mb-4 hub-box-clock" :class="{ 'is-rest': boxSession.phase.startsWith('rest') }">
                <svg viewBox="0 0 120 120" class="absolute inset-0 w-full h-full -rotate-90">
                  <circle cx="60" cy="60" r="54" fill="none" stroke="rgba(255,255,255,0.14)" stroke-width="6" />
                  <circle
                    cx="60"
                    cy="60"
                    r="54"
                    fill="none"
                    :stroke="boxSession.phase.startsWith('rest') ? ROYAL_CLARO : LARANJA"
                    stroke-width="6"
                    stroke-linecap="round"
                    :stroke-dasharray="`${(boxPct / 100) * 339.3} 339.3`"
                    style="transition: stroke-dasharray 0.9s linear"
                  />
                </svg>
                <div class="absolute inset-0 flex flex-col items-center justify-center">
                  <span class="text-5xl font-black tabular-nums leading-none">{{ fmtClock(boxSession.remaining) }}</span>
                  <span class="text-[10px] uppercase tracking-wider opacity-75 mt-1">
                    {{ boxSession.phase.startsWith('rest') ? 'descanso' : boxSession.running ? 'em andamento' : 'pausado' }}
                  </span>
                </div>
              </div>
              <!-- sequências do bloco, grandes pra ler batendo -->
              <div v-if="boxBlock?.seqs?.length" class="grid gap-2 mb-4" style="grid-template-columns: repeat(auto-fit, minmax(150px, 1fr))">
                <div v-for="id in boxBlock.seqs" :key="id" class="rounded-xl px-3 py-2 bg-white/10 border border-white/15">
                  <p class="text-[10px] opacity-80">{{ seqName(id) }}</p>
                  <p class="text-lg font-black tracking-wide" :style="{ color: LARANJA_CLARO }">{{ seqSteps(id) }}</p>
                </div>
              </div>
              <!-- controles -->
              <div class="flex items-center justify-center gap-2 flex-wrap">
                <button class="hub-box-btn" :disabled="boxSession.blockIdx === 0" title="Bloco anterior" @click="prevBoxBlock">‹</button>
                <button
                  class="h-14 px-8 rounded-2xl text-base font-extrabold shadow-lg"
                  :style="{ background: boxSession.running ? 'rgba(255,255,255,0.16)' : GRAD_LARANJA, color: '#fff' }"
                  @click="toggleBoxTimer"
                >
                  {{ boxSession.running ? '⏸ Pausar' : boxSession.elapsed ? '▶ Continuar' : '▶ Começar' }}
                </button>
                <button class="hub-box-btn" :title="boxIsLast ? 'Último bloco' : 'Próximo bloco'" @click="nextBoxBlock">›</button>
              </div>
              <div class="flex items-center gap-2 flex-wrap mt-4">
                <input
                  v-model="boxSession.date"
                  type="date"
                  class="h-9 rounded-lg border border-white/25 bg-white/10 px-2 text-xs text-white"
                  style="width: 9.5rem; margin-bottom: 0"
                />
                <input
                  v-model="boxSession.notes"
                  type="text"
                  placeholder="Observações"
                  class="h-9 flex-1 rounded-lg border border-white/25 bg-white/10 px-2 text-xs text-white placeholder-white/60"
                  style="min-width: 10rem; margin-bottom: 0"
                />
                <button
                  class="h-11 px-5 rounded-xl text-sm font-bold text-white disabled:opacity-60 w-full sm:w-auto"
                  :style="{ background: GRAD_LARANJA }"
                  :disabled="savingBox"
                  @click="finishBoxSession"
                >
                  {{ savingBox ? 'Salvando…' : '✓ Concluir treino' }}
                </button>
              </div>
            </div>
          </div>

          <!-- rodada 27: visualizações da aba Boxe -->
          <div v-if="!boxSession" class="hub-seg hub-seg-full hub-seg-5 mb-4">
            <button v-for="v in BOX_VIEWS" :key="v.key" :class="{ 'is-on': boxView === v.key }" @click="boxView = v.key">
              <span :class="v.ico" /><span class="lbl">{{ v.label }}</span>
            </button>
          </div>

          <!-- TREINOS PRÉ-PROGRAMADOS -->
          <div v-if="!boxSession && boxView === 'treinar'" class="hub-block p-5 mb-8">
            <div class="hub-sec">
              <span class="hub-sec-ico"><span class="i-lucide-swords" /></span>
              <div class="hub-sec-text">
                <h2 class="hub-sec-title">Treinos programados</h2>
                <p class="hub-sec-sub">blocos com cronômetro · {{ boxMin7 }} min nos últimos 7 dias</p>
              </div>
              <div class="hub-sec-actions">
                <button
                  class="h-8 px-3 rounded-lg text-xs font-bold text-white"
                  :style="{ background: GRAD_NOITE }"
                  title="O professor monta o treino em rounds: quantos, quanto tempo, o que fazer em cada um"
                  @click="openRoundsBuilder"
                >
                  <span class="i-lucide-graduation-cap hub-ico" style="width: 14px; height: 14px" /> Montar por rounds
                </button>
                <button
                  class="h-8 px-3 rounded-lg text-xs font-medium text-n-slate-11 border border-n-weak hover:bg-n-alpha-1"
                  @click="openNewBoxWorkout"
                >
                  + Novo treino
                </button>
              </div>
            </div>

            <!-- rodada 27: construtor do PROFESSOR por rounds — acordeão + seletor -->
            <div v-if="roundsForm" class="rounded-2xl p-4 mb-3 text-white" :style="{ background: GRAD_NOITE }">
              <div class="hub-sec">
                <span class="hub-sec-ico" style="background: rgba(255, 255, 255, 0.14); color: #fff"><span class="i-lucide-graduation-cap" /></span>
                <div class="hub-sec-text">
                  <h3 class="hub-sec-title">Treino do professor</h3>
                  <p class="hub-sec-sub">monte round a round · total ≈ {{ roundsTotalMin }} min</p>
                </div>
                <div class="hub-sec-actions">
                  <button class="h-8 px-3 rounded-lg text-xs border border-white/25 hover:bg-white/10" @click="roundsForm = null">Cancelar</button>
                </div>
              </div>
              <input
                v-model="roundsForm.name"
                type="text"
                placeholder="Nome do treino (ex.: Sparring técnico — 6 rounds)"
                class="hub-field hub-field-w hub-field-dark mb-3"
              />
              <div class="hub-grid-4 mb-3">
                <div class="hub-pro-ctl">
                  <em>Rounds</em>
                  <div class="flex items-center gap-2">
                    <button class="hub-pro-bump" @click="setRoundsCount(roundsForm.rounds - 1)">−</button>
                    <b>{{ roundsForm.rounds }}</b>
                    <button class="hub-pro-bump" @click="setRoundsCount(roundsForm.rounds + 1)">+</button>
                  </div>
                </div>
                <div class="hub-pro-ctl">
                  <em>Tempo do round</em>
                  <div class="flex gap-1">
                    <button v-for="sec in [120, 150, 180]" :key="sec" class="hub-pro-pill" :class="{ 'is-on': roundsForm.round_sec === sec }" @click="roundsForm.round_sec = sec">{{ fmtClock(sec) }}</button>
                  </div>
                </div>
                <div class="hub-pro-ctl">
                  <em>Descanso</em>
                  <div class="flex gap-1">
                    <button v-for="sec in [30, 45, 60, 90]" :key="sec" class="hub-pro-pill" :class="{ 'is-on': roundsForm.rest_sec === sec }" @click="roundsForm.rest_sec = sec">{{ sec }}s</button>
                  </div>
                </div>
                <div class="hub-pro-ctl">
                  <em>Aquecer · volta à calma</em>
                  <div class="flex items-center gap-1">
                    <input v-model="roundsForm.warmup" type="text" inputmode="numeric" class="hub-rounds-num" />
                    <span class="text-[10px] opacity-70">min</span>
                    <input v-model="roundsForm.cooldown" type="text" inputmode="numeric" class="hub-rounds-num ml-1" />
                    <span class="text-[10px] opacity-70">min</span>
                  </div>
                </div>
              </div>
              <div class="flex flex-col gap-2">
                <div v-for="(it, i) in roundsForm.items" :key="i" class="hub-acc hub-acc-dark" :class="{ 'is-open': roundsOpen === i }">
                  <button class="hub-acc-head" @click="roundsOpen = roundsOpen === i ? -1 : i">
                    <span class="hub-acc-n" :style="{ background: LARANJA, color: '#1a0e00' }">{{ i + 1 }}</span>
                    <span class="flex-1 min-w-0">
                      <span class="block text-xs font-bold truncate">{{ it.title || blockMeta(it.type).label }}</span>
                      <span class="block text-[10px] opacity-75 truncate">
                        {{ blockMeta(it.type).label }} · {{ it.seqs.length }} sequência{{ it.seqs.length === 1 ? '' : 's' }}<template v-if="it.desc"> · {{ it.desc }}</template>
                      </span>
                    </span>
                    <span :class="roundsOpen === i ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'" class="hub-ico opacity-70" />
                  </button>
                  <div v-if="roundsOpen === i" class="hub-acc-body pt-3">
                    <div class="hub-grid-2 mb-2">
                      <select v-model="it.type" class="hub-field hub-field-w hub-field-dark">
                        <option v-for="(m, k) in BLOCK_TYPES" :key="k" :value="k" style="color: #111">{{ m.label }}</option>
                      </select>
                      <input v-model="it.title" type="text" placeholder="Foco do round (ex.: jab e distância)" class="hub-field hub-field-w hub-field-dark" />
                    </div>
                    <input v-model="it.desc" type="text" placeholder="Instrução do professor pra este round" class="hub-field hub-field-w hub-field-dark mb-2" />
                    <SeqPicker v-model="it.seqs" :seqs="boxingSeqs" dark />
                    <div class="flex justify-end mt-2">
                      <button class="text-[11px] underline opacity-80 hover:opacity-100" @click="copyRoundToAll(i)">aplicar este round aos demais</button>
                    </div>
                  </div>
                </div>
              </div>
              <div class="flex justify-end mt-3">
                <button class="h-10 px-5 rounded-xl text-xs font-bold" :style="{ background: GRAD_LARANJA, color: '#fff' }" @click="generateFromRounds">
                  Gerar treino ({{ roundsTotalMin }} min) →
                </button>
              </div>
            </div>

            <!-- editor do treino programado (rodada 28: padrão do plano de luta) -->
            <div v-if="boxWkForm" class="rounded-2xl border p-3 sm:p-4 mb-3" :style="{ borderColor: ROYAL, background: 'rgba(65,105,225,0.04)' }">
              <div class="hub-sec">
                <span class="hub-sec-ico"><span class="i-lucide-pencil-line" /></span>
                <div class="hub-sec-text">
                  <h3 class="hub-sec-title">{{ boxWkForm.id ? 'Editar treino' : 'Novo treino' }}</h3>
                  <p class="hub-sec-sub">{{ boxWkForm.blocks.length }} blocos · ≈ {{ workoutMinutes(boxWkForm) }} min</p>
                </div>
                <div class="hub-sec-actions">
                  <button class="h-8 px-3 rounded-lg text-xs text-n-slate-11 border border-n-weak hover:bg-n-alpha-1" @click="boxWkForm = null">Cancelar</button>
                </div>
              </div>
              <div class="hub-form mb-4">
                <div class="hub-form-row">
                  <label>Nome</label>
                  <input v-model="boxWkForm.name" type="text" placeholder="ex.: Fundamentos — 60 min" class="hub-field hub-field-w font-bold" />
                </div>
                <div class="hub-form-row">
                  <label>Descrição</label>
                  <input v-model="boxWkForm.desc" type="text" placeholder="uma linha sobre o treino" class="hub-field hub-field-w" />
                </div>
              </div>
              <p class="hub-label">Blocos</p>
              <div class="flex flex-col gap-2">
                <div v-for="(b, i) in boxWkForm.blocks" :key="i" class="hub-acc" :class="{ 'is-open': wkOpen === i }">
                  <button class="hub-acc-head" @click="wkOpen = wkOpen === i ? -1 : i">
                    <span class="hub-acc-n">{{ i + 1 }}</span>
                    <span class="flex-1 min-w-0">
                      <span class="flex items-center gap-1.5 hub-h2 truncate">
                        <span :class="blockMeta(b.type).ico" style="width: 14px; height: 14px; flex-shrink: 0" />{{ b.title || blockMeta(b.type).label }}
                      </span>
                      <span class="block text-[11px] text-n-slate-10 truncate">
                        ≈ {{ blockMinutes(b) }} min · {{ blockDurationText(b) }} · {{ (b.seqs || []).length }} sequência{{ (b.seqs || []).length === 1 ? '' : 's' }}
                      </span>
                    </span>
                    <span :class="wkOpen === i ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'" class="hub-ico text-n-slate-10" />
                  </button>
                  <div v-if="wkOpen === i" class="hub-acc-body pt-3">
                    <div class="hub-form">
                      <div class="hub-form-row">
                        <label>Tipo</label>
                        <div class="flex gap-1.5 flex-wrap">
                          <button v-for="(m, k) in BLOCK_TYPES" :key="k" class="hub-tag" :class="{ 'is-on': b.type === k }" @click="b.type = k">
                            <span :class="m.ico" />{{ m.label }}
                          </button>
                        </div>
                      </div>
                      <div class="hub-form-row">
                        <label>Nome</label>
                        <input v-model="b.title" type="text" :placeholder="blockMeta(b.type).label" class="hub-field hub-field-w" />
                      </div>
                      <div class="hub-form-row">
                        <label>Formato</label>
                        <div class="hub-seg">
                          <button :class="{ 'is-on': blockMode(b) === 'min' }" @click="setBlockMode(b, 'min')"><span class="i-lucide-timer" />Tempo corrido</button>
                          <button :class="{ 'is-on': blockMode(b) === 'rounds' }" @click="setBlockMode(b, 'rounds')"><span class="i-lucide-bell" />Rounds</button>
                        </div>
                      </div>
                      <template v-if="blockMode(b) === 'min'">
                        <div class="hub-form-row">
                          <label>Minutos</label>
                          <div class="flex gap-1.5 flex-wrap items-center">
                            <button v-for="m in MIN_PRESETS" :key="m" class="hub-tag" :class="{ 'is-on': Number(b.minutes) === m }" @click="b.minutes = m">{{ m }} min</button>
                            <input v-model="b.minutes" type="text" inputmode="decimal" placeholder="outro" class="hub-field hub-other" title="Outro valor" />
                          </div>
                        </div>
                      </template>
                      <template v-else>
                        <div class="hub-form-row">
                          <label>Rounds</label>
                          <div class="flex items-center gap-2">
                            <button class="hub-bump" @click="b.rounds = Math.max(1, Number(b.rounds) - 1)">−</button>
                            <b class="text-base font-black w-7 text-center text-n-slate-12">{{ b.rounds }}</b>
                            <button class="hub-bump" @click="b.rounds = Math.min(30, Number(b.rounds) + 1)">+</button>
                          </div>
                        </div>
                        <div class="hub-form-row">
                          <label>Round</label>
                          <div class="flex gap-1.5 flex-wrap items-center">
                            <button v-for="sec in ROUND_SEC_PRESETS" :key="sec" class="hub-tag" :class="{ 'is-on': Number(b.round_sec) === sec }" @click="b.round_sec = sec">{{ fmtClock(sec) }}</button>
                            <input v-model="b.round_sec" type="text" inputmode="numeric" placeholder="seg" class="hub-field hub-other" title="Outro valor, em segundos" />
                          </div>
                        </div>
                        <div class="hub-form-row">
                          <label>Descanso</label>
                          <div class="flex gap-1.5 flex-wrap items-center">
                            <button v-for="sec in REST_PRESETS" :key="sec" class="hub-tag" :class="{ 'is-on': Number(b.rest_sec) === sec }" @click="b.rest_sec = sec">{{ sec }} s</button>
                            <input v-model="b.rest_sec" type="text" inputmode="numeric" placeholder="seg" class="hub-field hub-other" title="Outro valor, em segundos" />
                          </div>
                        </div>
                      </template>
                      <div class="hub-form-row">
                        <label>O que fazer</label>
                        <input v-model="b.desc" type="text" placeholder="instrução deste bloco" class="hub-field hub-field-w" />
                      </div>
                      <div class="hub-form-row" style="align-items: start">
                        <label style="padding-top: 8px">Sequências</label>
                        <SeqPicker v-model="b.seqs" :seqs="boxingSeqs" />
                      </div>
                    </div>
                    <div class="flex items-center gap-1.5 justify-end mt-3">
                      <button class="hub-tag" :disabled="i === 0" @click="moveBoxBlock(i, -1)"><span class="i-lucide-arrow-up" />subir</button>
                      <button class="hub-tag" :disabled="i === boxWkForm.blocks.length - 1" @click="moveBoxBlock(i, 1)"><span class="i-lucide-arrow-down" />descer</button>
                      <button class="hub-tag" style="color: #dc2626" @click="removeBoxBlock(i)"><span class="i-lucide-trash-2" />remover</button>
                    </div>
                  </div>
                </div>
              </div>
              <div class="flex items-center gap-2 flex-wrap mt-3">
                <button class="hub-tag" @click="addBoxBlock"><span class="i-lucide-plus" />bloco</button>
                <div class="flex-1" />
                <button v-if="boxWkForm.id" class="h-9 px-3 rounded-lg text-xs font-medium border border-n-weak hover:bg-n-alpha-1" style="color: #dc2626" @click="deleteBoxWorkoutCfg">Excluir</button>
                <button class="h-10 px-5 rounded-xl text-xs font-bold text-white disabled:opacity-60" :style="{ background: GRAD_LARANJA }" :disabled="savingConfig" @click="saveBoxWorkoutCfg">
                  {{ savingConfig ? 'Salvando…' : 'Salvar treino' }}
                </button>
              </div>
            </div>

            <!-- cards dos treinos -->
            <div class="grid gap-2.5" style="grid-template-columns: repeat(auto-fill, minmax(260px, 1fr))">
              <div v-for="w in boxWorkouts" :key="w.id" class="hub-crystal rounded-2xl p-4 flex flex-col gap-2">
                <div class="flex items-start gap-2">
                  <span
                    class="w-11 h-11 rounded-xl flex flex-col items-center justify-center text-white shrink-0 leading-none"
                    :style="{ background: GRAD_NOITE }"
                  >
                    <span class="text-base font-black">{{ workoutMinutes(w) }}</span>
                    <span class="text-[8px] opacity-80">min</span>
                  </span>
                  <div class="flex-1 min-w-0">
                    <p class="hub-h2 leading-tight">{{ w.name }}</p>
                    <p class="text-[11px] text-n-slate-10">
                      {{ (w.blocks || []).length }} blocos · {{ workoutRounds(w) }} rounds · {{ workoutSeqIds(w).length }} sequências
                    </p>
                  </div>
                  <button class="w-7 h-7 rounded-lg text-n-slate-10 hover:bg-n-alpha-1 shrink-0" title="Editar" @click="openEditBoxWorkout(w)">✏️</button>
                </div>
                <div class="flex gap-1 flex-wrap">
                  <span
                    v-for="(b, i) in w.blocks"
                    :key="i"
                    class="inline-flex items-center gap-1 h-6 px-1.5 rounded-md text-[10px] border border-n-weak bg-n-solid-2 text-n-slate-11"
                    :title="b.desc"
                  >
                    <span :class="blockMeta(b.type).ico" style="width: 11px; height: 11px" />{{ b.title || blockMeta(b.type).label }}
                    <b class="text-n-slate-10">{{ blockMinutes(b) }}'</b>
                  </span>
                </div>
                <!-- rodada 29: teia do treino (o que ele trabalha) -->
                <div v-if="workoutRadar(w)" class="hub-radar-sm">
                  <RadarChart :axes="workoutRadar(w).axes" :datasets="workoutRadar(w).datasets" :size="220" />
                </div>
                <div class="flex gap-2 mt-auto">
                  <button
                    class="h-10 flex-1 rounded-xl text-xs font-bold text-white shadow"
                    :style="{ background: GRAD_LARANJA }"
                    @click="startBoxWorkout(w)"
                  >
                    ▶ Iniciar
                  </button>
                  <button
                    class="h-10 px-3 rounded-xl text-xs font-medium text-n-slate-11 border border-n-weak hover:bg-n-alpha-1 disabled:opacity-60"
                    :disabled="savingBox"
                    title="Registrar este treino como feito hoje, sem cronômetro"
                    @click="logBoxWorkoutNow(w)"
                  >
                    ✓ Já fiz
                  </button>
                </div>
              </div>
            </div>
          </div>

          <!-- rodada 26: PLANO DE LUTA -->
          <div v-if="!boxSession && boxView === 'planos'" class="hub-block p-5 mb-8">
            <div class="hub-sec">
              <span class="hub-sec-ico"><span class="i-lucide-medal" /></span>
              <div class="hub-sec-text">
                <h2 class="hub-sec-title">Planos de luta</h2>
                <p class="hub-sec-sub">intenção e sequências de cada round · por atleta ou por luta · Treinar roda no cronômetro</p>
              </div>
              <div class="hub-sec-actions">
                <button class="h-8 px-3 rounded-lg text-xs font-bold text-white" :style="{ background: GRAD_LARANJA }" @click="openNewFightPlan">+ Novo plano</button>
              </div>
            </div>

            <div v-if="fpForm" class="rounded-2xl border p-3 mb-3" :style="{ borderColor: LARANJA, background: 'rgba(255,138,0,0.05)' }">
              <div class="hub-form mb-4">
                <div class="hub-form-row">
                  <label>Nome</label>
                  <input v-model="fpForm.name" type="text" placeholder="ex.: Luta de outubro · João" class="hub-field hub-field-w font-bold" />
                </div>
                <div class="hub-form-row">
                  <label>Atleta</label>
                  <input v-model="fpForm.athlete" type="text" placeholder="quem vai lutar" class="hub-field hub-field-w" />
                </div>
                <div class="hub-form-row">
                  <label>Adversário</label>
                  <input v-model="fpForm.opponent" type="text" placeholder="adversário ou nome da luta" class="hub-field hub-field-w" />
                </div>
                <div class="hub-form-row">
                  <label>Rounds</label>
                  <div class="flex items-center gap-2">
                    <button class="hub-bump" @click="setFpRounds(fpForm.rounds - 1)">−</button>
                    <b class="text-base font-black w-7 text-center text-n-slate-12">{{ fpForm.rounds }}</b>
                    <button class="hub-bump" @click="setFpRounds(fpForm.rounds + 1)">+</button>
                  </div>
                </div>
                <div class="hub-form-row">
                  <label>Round</label>
                  <div class="flex gap-1.5 flex-wrap items-center">
                    <button v-for="sec in ROUND_SEC_PRESETS" :key="sec" class="hub-tag" :class="{ 'is-on': Number(fpForm.round_sec) === sec }" @click="fpForm.round_sec = sec">{{ fmtClock(sec) }}</button>
                    <input v-model="fpForm.round_sec" type="text" inputmode="numeric" placeholder="seg" class="hub-field hub-other" title="Outro valor, em segundos" />
                  </div>
                </div>
                <div class="hub-form-row">
                  <label>Descanso</label>
                  <div class="flex gap-1.5 flex-wrap items-center">
                    <button v-for="sec in REST_PRESETS" :key="sec" class="hub-tag" :class="{ 'is-on': Number(fpForm.rest_sec) === sec }" @click="fpForm.rest_sec = sec">{{ sec }} s</button>
                    <input v-model="fpForm.rest_sec" type="text" inputmode="numeric" placeholder="seg" class="hub-field hub-other" title="Outro valor, em segundos" />
                  </div>
                </div>
              </div>
              <p class="hub-label">Rounds</p>
              <div class="flex flex-col gap-2">
                <div v-for="(r, i) in fpForm.plan" :key="i" class="hub-acc" :class="{ 'is-open': fpOpen === i }">
                  <button class="hub-acc-head" @click="fpOpen = fpOpen === i ? -1 : i">
                    <span class="hub-acc-n">{{ i + 1 }}</span>
                    <span class="flex-1 min-w-0">
                      <span class="block text-xs font-bold text-n-slate-12 truncate">Round {{ i + 1 }}<template v-if="fightIntent(r.intent)"> · {{ fightIntent(r.intent).label }}</template></span>
                      <span class="block text-[10px] text-n-slate-10 truncate">{{ r.seqs.length }} sequência{{ r.seqs.length === 1 ? '' : 's' }}<template v-if="r.notes"> · {{ r.notes }}</template></span>
                    </span>
                    <span :class="fpOpen === i ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'" class="hub-ico text-n-slate-10" />
                  </button>
                  <div v-if="fpOpen === i" class="hub-acc-body pt-3">
                    <p class="hub-label">Intenção</p>
                    <div class="flex gap-1.5 flex-wrap mb-3">
                      <button
                        v-for="it in FIGHT_INTENTS"
                        :key="it.key"
                        class="hub-tag"
                        :class="{ 'is-on': r.intent === it.key }"
                        :title="it.hint"
                        @click="r.intent = r.intent === it.key ? '' : it.key"
                      >
                        <span :class="it.ico" />{{ it.label }}
                      </button>
                    </div>
                    <p class="hub-label">Sequências</p>
                    <SeqPicker v-model="r.seqs" :seqs="boxingSeqs" class="mb-3" />
                    <input v-model="r.notes" type="text" placeholder="Observações do round (o que evitar, o que provocar…)" class="hub-field hub-field-w" />
                  </div>
                </div>
              </div>
              <div class="hub-form mt-3 mb-3">
                <div class="hub-form-row">
                  <label>Estratégia</label>
                  <input v-model="fpForm.note" type="text" placeholder="linha geral da luta (opcional)" class="hub-field hub-field-w" />
                </div>
              </div>
              <div class="flex items-center gap-2 flex-wrap">
                <div class="flex-1" />
                <button v-if="fpForm.id" class="h-9 px-3 rounded-lg text-xs font-medium border border-n-weak hover:bg-n-alpha-1" style="color: #dc2626" @click="deleteFightPlan({ id: fpForm.id })">Excluir</button>
                <button class="h-9 px-3 rounded-lg text-xs font-medium text-n-slate-11 border border-n-weak hover:bg-n-alpha-1" @click="fpForm = null">Cancelar</button>
                <button class="h-10 px-5 rounded-xl text-xs font-bold text-white disabled:opacity-60" :style="{ background: GRAD_LARANJA }" :disabled="savingFp" @click="saveFightPlan">
                  {{ savingFp ? 'Salvando…' : 'Salvar plano' }}
                </button>
              </div>
            </div>

            <p v-if="!fightPlans.length && !fpForm" class="text-xs text-n-slate-10">Nenhum plano ainda — monte o primeiro.</p>
            <div class="grid gap-2.5" style="grid-template-columns: repeat(auto-fill, minmax(260px, 1fr))">
              <div v-for="fp in fightPlans" :key="fp.id" class="hub-crystal rounded-2xl p-4 flex flex-col gap-2">
                <div class="flex items-start gap-2">
                  <span class="w-11 h-11 rounded-xl flex flex-col items-center justify-center text-white shrink-0 leading-none" :style="{ background: GRAD_LARANJA }">
                    <span class="text-base font-black">{{ fp.data?.rounds }}</span>
                    <span class="text-[8px] opacity-90">rounds</span>
                  </span>
                  <div class="flex-1 min-w-0">
                    <p class="hub-h2 leading-tight">{{ fp.data?.name }}</p>
                    <p class="text-[11px] text-n-slate-10">{{ fpSummary(fp) }}</p>
                  </div>
                  <button class="w-7 h-7 rounded-lg text-n-slate-10 hover:bg-n-alpha-1 shrink-0" title="Editar" @click="openEditFightPlan(fp)">✏️</button>
                </div>
                <div class="flex gap-1 flex-wrap">
                  <span v-for="(r, i) in fp.data?.plan || []" :key="i" class="inline-flex items-center gap-1 h-6 px-1.5 rounded-md text-[10px] border border-n-weak bg-n-solid-2 text-n-slate-11" :title="(r.seqs || []).map(seqName).join(' · ')">
                    <span v-if="fightIntent(r.intent)" :class="fightIntent(r.intent).ico" style="width: 11px; height: 11px" />R{{ i + 1 }} {{ fightIntent(r.intent)?.label || 'livre' }}
                    <b v-if="(r.seqs || []).length" class="text-n-slate-10">{{ (r.seqs || []).length }}</b>
                  </span>
                </div>
                <div v-if="planRadar(fp)" class="hub-radar-sm">
                  <RadarChart :axes="planRadar(fp).axes" :datasets="planRadar(fp).datasets" :size="220" />
                </div>
                <button class="h-10 rounded-xl text-xs font-bold text-white shadow mt-auto" :style="{ background: GRAD_NOITE }" @click="trainFightPlan(fp)">▶ Treinar este plano</button>
              </div>
            </div>
          </div>

          <!-- Registrar manualmente (dobrável) -->
          <div v-if="!boxSession && boxView === 'treinar'" class="hub-block p-5 mb-8">
            <button class="w-full text-left hub-h2" @click="showManualBox = !showManualBox">
              {{ showManualBox ? '▾' : '▸' }} Registrar treino livre
            </button>
            <template v-if="showManualBox">
            <p class="text-[11px] text-n-slate-10 mt-1 mb-3">Treinou fora dos programados? Anote duração, rounds e sequências.</p>
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
                :style="boxForm.seqs.includes(s.id) ? { background: ROYAL } : {}"
                @click="toggleSeq(s.id)"
              >
                {{ s.name }} <span class="font-normal opacity-75">{{ s.steps }}</span>
              </button>
            </div>
            <button
              class="h-10 px-6 rounded-xl text-xs font-bold text-white disabled:opacity-60"
              :style="{ background: GRAD_NOITE }"
              :disabled="savingBox"
              @click="saveBoxing"
            >
              {{ savingBox ? 'Salvando…' : '✓ Salvar treino de boxe' }}
            </button>
            </template>
          </div>

          <!-- rodada 29: MAPEADOR DE ATLETAS -->
          <template v-if="!boxSession && boxView === 'atletas'">
            <div class="hub-block p-5 mb-8">
              <div class="hub-sec">
                <span class="hub-sec-ico"><span class="i-lucide-users" /></span>
                <div class="hub-sec-text">
                  <h2 class="hub-sec-title">Mapeador de atletas</h2>
                  <p class="hub-sec-sub">catalogue alunos, adversários e referências — a teia mostra o que cada um usa e faz</p>
                </div>
                <div class="hub-sec-actions">
                  <button v-for="r in ATHLETE_ROLES" :key="r.key" class="hub-tag" :style="{ color: r.color }" @click="openNewAthlete(r.key)"><span class="i-lucide-plus" />{{ r.label }}</button>
                </div>
              </div>

              <!-- formulário do atleta -->
              <div v-if="athForm" class="rounded-2xl border p-3 sm:p-4 mb-4" :style="{ borderColor: athleteRole(athForm.role).color, background: 'rgba(65,105,225,0.04)' }">
                <div class="hub-sec">
                  <span class="hub-sec-ico" :style="{ background: athleteRole(athForm.role).color, color: '#fff' }"><span :class="athleteRole(athForm.role).ico" /></span>
                  <div class="hub-sec-text">
                    <h3 class="hub-sec-title">{{ athForm.id ? 'Editar atleta' : 'Novo atleta' }}</h3>
                    <p class="hub-sec-sub">{{ athleteRole(athForm.role).label }} · perfil técnico de 0 a 10 em cada eixo</p>
                  </div>
                  <div class="hub-sec-actions">
                    <button class="h-8 px-3 rounded-lg text-xs text-n-slate-11 border border-n-weak hover:bg-n-alpha-1" @click="athForm = null">Cancelar</button>
                  </div>
                </div>
                <div class="hub-grid-2" style="gap: 16px">
                  <div class="hub-form">
                    <div class="hub-form-row"><label>Nome</label><input v-model="athForm.name" type="text" placeholder="nome do atleta" class="hub-field hub-field-w font-bold" /></div>
                    <div class="hub-form-row">
                      <label>Papel</label>
                      <div class="flex gap-1.5 flex-wrap">
                        <button v-for="r in ATHLETE_ROLES" :key="r.key" class="hub-tag" :class="{ 'is-on': athForm.role === r.key }" @click="athForm.role = r.key"><span :class="r.ico" />{{ r.label }}</button>
                      </div>
                    </div>
                    <div class="hub-form-row">
                      <label>Guarda</label>
                      <div class="flex gap-1.5 flex-wrap">
                        <button v-for="st in ATHLETE_STANCES" :key="st.key" class="hub-tag" :class="{ 'is-on': athForm.stance === st.key }" @click="athForm.stance = st.key">{{ st.label }}</button>
                      </div>
                    </div>
                    <div class="hub-form-row"><label>Categoria</label><input v-model="athForm.weight" type="text" placeholder="ex.: até 75 kg · médio" class="hub-field hub-field-w" /></div>
                    <div class="hub-form-row"><label>Equipe</label><input v-model="athForm.team" type="text" placeholder="academia / equipe" class="hub-field hub-field-w" /></div>
                    <div class="hub-form-row"><label>Vídeo</label><input v-model="athForm.link" type="text" placeholder="link de uma luta pra estudar" class="hub-field hub-field-w" /></div>
                    <div class="hub-form-row"><label>Fortes</label><input v-model="athForm.strengths" type="text" placeholder="o que ele faz muito bem" class="hub-field hub-field-w" /></div>
                    <div class="hub-form-row"><label>Fracos</label><input v-model="athForm.weaknesses" type="text" placeholder="onde ele sofre" class="hub-field hub-field-w" /></div>
                    <div class="hub-form-row" style="align-items: start"><label style="padding-top: 8px">Notas</label><textarea v-model="athForm.notes" rows="3" placeholder="como ele luta, padrões, hábitos" class="hub-field hub-field-w" style="height: auto; padding: 8px 10px; resize: vertical" /></div>
                    <div class="hub-form-row" style="align-items: start"><label style="padding-top: 8px">O que usa</label><SeqPicker v-model="athForm.seqs" :seqs="boxingSeqs" /></div>
                  </div>
                  <div>
                    <p class="hub-label">Perfil técnico</p>
                    <div class="hub-radar-form">
                      <RadarChart :axes="athleteAxes" :datasets="athFormDataset" :size="240" />
                    </div>
                    <div class="flex flex-col gap-1.5 mt-2">
                      <div v-for="ax in ATHLETE_AXES" :key="ax.key" class="hub-slider" :title="ax.hint">
                        <label>{{ ax.label }}</label>
                        <input v-model.number="athForm.radar[ax.key]" type="range" min="0" max="10" step="1" />
                        <b>{{ athForm.radar[ax.key] }}</b>
                      </div>
                    </div>
                  </div>
                </div>
                <div class="flex items-center gap-2 flex-wrap mt-4">
                  <button v-if="athForm.id" class="h-9 px-3 rounded-lg text-xs font-medium border border-n-weak hover:bg-n-alpha-1" style="color: #dc2626" @click="deleteAthlete(athForm.id)">Excluir</button>
                  <div class="flex-1" />
                  <button class="h-10 px-5 rounded-xl text-xs font-bold text-white disabled:opacity-60" :style="{ background: GRAD_LARANJA }" :disabled="savingAth" @click="saveAthlete">
                    {{ savingAth ? 'Salvando…' : 'Salvar atleta' }}
                  </button>
                </div>
              </div>

              <!-- comparação lado a lado -->
              <div v-if="compareDatasets.length === 2" class="hub-crystal rounded-2xl p-4 mb-4" :style="{ background: 'rgba(65,105,225,0.04)' }">
                <div class="hub-sec" style="margin-bottom: 4px">
                  <span class="hub-sec-ico"><span class="i-lucide-git-compare" /></span>
                  <div class="hub-sec-text"><h3 class="hub-sec-title">Comparação</h3><p class="hub-sec-sub">{{ compareDatasets[0].label }} × {{ compareDatasets[1].label }}</p></div>
                  <div class="hub-sec-actions"><button class="hub-tag" @click="athCompare = []"><span class="i-lucide-x" />limpar</button></div>
                </div>
                <RadarChart :axes="athleteAxes" :datasets="compareDatasets" :size="300" />
              </div>

              <div class="flex gap-1.5 flex-wrap mb-3">
                <button class="hub-tag" :class="{ 'is-on': !athFilter }" @click="athFilter = ''">todos <small>{{ athletes.length }}</small></button>
                <button v-for="r in ATHLETE_ROLES" :key="r.key" class="hub-tag" :class="{ 'is-on': athFilter === r.key }" @click="athFilter = athFilter === r.key ? '' : r.key"><span :class="r.ico" />{{ r.label }}s <small>{{ athCount(r.key) }}</small></button>
                <span v-if="athCompare.length === 1" class="text-[11px] text-n-slate-10 self-center ml-1">escolha o 2º pra comparar</span>
              </div>
              <p v-if="!athletesShown.length && !athForm" class="text-xs text-n-slate-10">Nenhum atleta mapeado ainda — comece pelo botão acima.</p>
              <div class="grid gap-3" style="grid-template-columns: repeat(auto-fill, minmax(250px, 1fr))">
                <div v-for="a in athletesShown" :key="a.id" class="rounded-2xl border p-3 flex flex-col gap-2" :class="athCompare.includes(a.id) ? '' : 'border-n-weak'" :style="athCompare.includes(a.id) ? { borderColor: LARANJA, background: 'rgba(255,138,0,0.05)' } : {}">
                  <div class="flex items-start gap-2">
                    <span class="w-11 h-11 rounded-xl flex items-center justify-center text-white text-sm font-black shrink-0" :style="{ background: athleteRole(a.data?.role).color }">{{ initialsOf(a.data?.name) }}</span>
                    <div class="flex-1 min-w-0">
                      <p class="hub-h2 leading-tight truncate">{{ a.data?.name }}</p>
                      <p class="text-[11px] text-n-slate-10 truncate">
                        <span class="hub-tag is-soft" style="height: 18px; padding: 0 5px; font-size: 9.5px"><span :class="athleteRole(a.data?.role).ico" />{{ athleteRole(a.data?.role).label }}</span>
                        {{ [ATHLETE_STANCES.find(x => x.key === a.data?.stance)?.label, a.data?.weight, a.data?.team].filter(Boolean).join(' · ') }}
                      </p>
                    </div>
                    <button class="w-8 h-8 rounded-lg text-n-slate-10 hover:bg-n-alpha-1 shrink-0 flex items-center justify-center" title="Editar" @click="openEditAthlete(a)"><span class="i-lucide-pencil-line" style="width: 14px; height: 14px" /></button>
                  </div>
                  <div class="hub-radar-sm"><RadarChart :axes="athleteAxes" :datasets="[athleteDataset(a)]" :size="220" /></div>
                  <p class="text-[11px] text-n-slate-11">
                    <b :style="{ color: ROYAL }">Forte:</b> {{ athleteHighlights(a).top.map(x => x.label).join(' · ') }}
                    <span class="mx-1 text-n-slate-10">·</span>
                    <b :style="{ color: LARANJA_VIVO }">Fraco:</b> {{ athleteHighlights(a).low.map(x => x.label).join(' · ') }}
                  </p>
                  <p v-if="a.data?.strengths || a.data?.weaknesses" class="text-[11px] text-n-slate-10 truncate" :title="`${a.data?.strengths || ''} / ${a.data?.weaknesses || ''}`">{{ [a.data?.strengths, a.data?.weaknesses].filter(Boolean).join(' / ') }}</p>
                  <div v-if="(a.data?.seqs || []).length" class="flex gap-1 flex-wrap">
                    <span v-for="id in a.data.seqs.slice(0, 6)" :key="id" class="hub-tag is-soft" :title="seqSteps(id)">{{ seqName(id) }}</span>
                    <span v-if="a.data.seqs.length > 6" class="hub-tag is-soft">+{{ a.data.seqs.length - 6 }}</span>
                  </div>
                  <div class="flex gap-1.5 mt-auto">
                    <button class="hub-tag" :class="{ 'is-on': athCompare.includes(a.id) }" @click="toggleCompare(a.id)"><span class="i-lucide-git-compare" />comparar</button>
                    <a v-if="a.data?.link" :href="a.data.link" target="_blank" rel="noopener" class="hub-tag"><span class="i-lucide-play" />vídeo</a>
                    <button class="hub-tag ml-auto" :style="{ color: athleteRole(a.data?.role).color }" @click="planForAthlete(a)"><span class="i-lucide-medal" />{{ a.data?.role === 'aluno' ? 'plano pra ele' : 'plano contra' }}</button>
                  </div>
                </div>
              </div>
            </div>
          </template>

          <!-- Repertório de sequências -->
          <div v-if="!boxSession && boxView === 'repertorio'" class="hub-block p-5 mb-8">
            <div class="hub-sec">
              <span class="hub-sec-ico"><span class="i-lucide-list-ordered" /></span>
              <div class="hub-sec-text">
                <h2 class="hub-sec-title">Repertório de sequências</h2>
                <p class="hub-sec-sub">1 jab · 2 direto · 3 hook esq · 4 hook dir · 5 upper esq · 6 upper dir · b = no corpo</p>
              </div>
              <div class="hub-sec-actions">
                <button
                  class="h-8 px-3 rounded-lg text-xs font-medium border border-dashed border-n-weak hover:bg-n-alpha-1"
                  :style="{ color: LARANJA_VIVO }"
                  title="Traz 25 sequências prontas com etiqueta e 'quando usar' (não repete as suas)"
                  @click="importSeqLibrary"
                >
                  <span class="i-lucide-library hub-ico" style="width: 14px; height: 14px" /> Importar biblioteca
                </button>
                <button
                  class="h-8 px-3 rounded-lg text-xs font-medium text-n-slate-11 border border-n-weak hover:bg-n-alpha-1"
                  @click="openNewSeq"
                >
                  + Nova sequência
                </button>
              </div>
            </div>
            <!-- etiquetas "quando usar" (rodada 26 · tags de linha na 27) -->
            <div class="flex gap-1.5 flex-wrap mb-3">
              <button class="hub-tag" :class="{ 'is-on': !seqFilter }" @click="seqFilter = ''">todas <small>{{ boxingSeqs.length }}</small></button>
              <button
                v-for="c in SEQ_CATEGORIES"
                :key="c.key"
                class="hub-tag"
                :class="{ 'is-on': seqFilter === c.key }"
                :title="c.hint"
                @click="seqFilter = seqFilter === c.key ? '' : c.key"
              >
                <span :class="c.ico" />{{ c.label }} <small>{{ seqCount(c.key) }}</small>
              </button>
            </div>

            <!-- Editor -->
            <div v-if="seqForm" class="hub-crystal rounded-xl p-4 mb-3">
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
                style="margin-bottom: 8px"
              />
              <div class="flex items-center gap-2 flex-wrap" style="margin-bottom: 10px">
                <select v-model="seqForm.category" class="h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12" style="width: 12rem; margin-bottom: 0">
                  <option value="">Etiqueta (quando usar)…</option>
                  <option v-for="c in SEQ_CATEGORIES" :key="c.key" :value="c.key">{{ c.label }}</option>
                </select>
                <input
                  v-model="seqForm.when"
                  type="text"
                  placeholder="Quando usar (ex.: ele solta o jab: esquiva pra fora e direto)"
                  class="h-9 flex-1 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                  style="min-width: 12rem; margin-bottom: 0"
                />
              </div>
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
                  :style="{ background: GRAD_NOITE }"
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
                v-for="s in filteredSeqs"
                :key="s.id"
                class="hub-crystal rounded-xl p-4 flex items-start gap-2"
              >
                <div class="flex-1 min-w-0">
                  <p class="text-[11px] font-bold text-n-slate-11 flex items-center gap-1.5 flex-wrap">
                    {{ s.name }}
                    <span v-if="seqCatMeta(s.category)" class="hub-tag is-soft"><span :class="seqCatMeta(s.category).ico" />{{ seqCatMeta(s.category).label }}</span>
                  </p>
                  <p class="text-xl font-black tracking-wide" :style="{ color: ROYAL }">{{ s.steps }}</p>
                  <p v-if="s.desc" class="text-[11px] text-n-slate-10">{{ s.desc }}</p>
                  <p v-if="s.when" class="text-[11px] mt-0.5" :style="{ color: LARANJA_VIVO }"><b>Quando usar:</b> {{ s.when }}</p>
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

          <!-- Histórico do boxe (rodada 27: seção própria, lista agrupada por mês) -->
          <div v-if="!boxSession && boxView === 'historico'" class="hub-block p-5 mb-8">
            <div class="hub-sec">
              <span class="hub-sec-ico"><span class="i-lucide-history" /></span>
              <div class="hub-sec-text">
                <h2 class="hub-sec-title">Histórico de boxe</h2>
                <p class="hub-sec-sub">cada sessão registrada, mês a mês</p>
              </div>
            </div>
            <div class="hub-grid-3 mb-4">
              <div class="hub-stat"><b>{{ boxStats.n }}</b><span>sessões</span></div>
              <div class="hub-stat"><b>{{ boxStats.min }}</b><span>minutos</span></div>
              <div class="hub-stat"><b>{{ boxStats.rounds }}</b><span>rounds</span></div>
            </div>
            <p v-if="!boxings.length" class="text-xs text-n-slate-10">Nenhum treino de boxe registrado ainda.</p>
            <div v-else class="hub-list">
              <template v-for="g in groupByMonth(boxings.slice(0, 80))" :key="g.key">
                <div class="hub-month">{{ g.label }}</div>
                <div v-for="b in g.items" :key="b.id" class="hub-row">
                  <span class="hub-row-date"><b>{{ dayOf(b.record_date) }}</b><small>{{ monOf(b.record_date) }}</small></span>
                  <div class="flex-1 min-w-0">
                    <p class="text-xs font-bold text-n-slate-12 truncate">
                      {{ b.data?.duration_min || 0 }} min
                      <span v-if="b.data?.rounds" class="font-normal text-n-slate-10">· {{ b.data.rounds }} rounds</span>
                      <span v-if="b.data?.workout_name" class="font-normal" :style="{ color: ROYAL }">· {{ b.data.workout_name }}</span>
                    </p>
                    <p class="text-[11px] text-n-slate-10 truncate">{{ (b.data?.sequences || []).map(seqName).join(' · ') || b.data?.notes || '—' }}</p>
                  </div>
                  <button class="w-8 h-8 rounded-lg text-n-slate-10 hover:bg-n-alpha-1 shrink-0 flex items-center justify-center" title="Remover" @click="deleteRecord(b)">
                    <span class="i-lucide-x" style="width: 14px; height: 14px" />
                  </button>
                </div>
              </template>
            </div>
          </div>
        </template>

        <!-- ═══ DIETA ═══ -->
        <template v-if="tab === 'dieta'">
          <!-- Dia de hoje -->
          <div class="hub-block p-5 mb-8">
            <div class="flex items-center justify-between gap-2 flex-wrap mb-1">
              <span class="flex items-center gap-2">
                <h2 class="hub-h2"><span class="hub-h-ico i-lucide-utensils-crossed" />{{ dietDate === todayISO ? 'Hoje' : fmtDay(dietDate) }}
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
                <span class="i-lucide-pencil hub-ico" style="width: 13px; height: 13px" /> Plano & metas
              </button>
            </div>
            <p v-if="dietCfg.notes" class="text-[11px] text-n-slate-10 mb-3">{{ dietCfg.notes }}</p>
            <p v-if="!dietCfg.meals.length" class="text-xs text-n-slate-10">
              Monte seu plano alimentar em "Plano & metas" — as refeições viram um checklist diário.
            </p>

            <!-- barras de macros -->
            <div v-if="dietCfg.meals.length" class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
              <div v-for="m in MACROS" :key="m.key" class="hub-crystal rounded-xl p-4">
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
                :style="mealsDone.includes(meal.id) ? { background: 'rgba(65, 105, 225, 0.12)' } : {}"
                :disabled="savingDiet"
                @click="toggleMeal(meal.id)"
              >
                <span
                  class="w-6 h-6 rounded-full flex items-center justify-center text-white text-xs shrink-0"
                  :style="{ background: mealsDone.includes(meal.id) ? ROYAL : 'rgba(148,163,184,0.4)' }"
                >
                  {{ mealsDone.includes(meal.id) ? '✓' : '' }}
                </span>
                <div class="flex-1 min-w-0">
                  <p class="text-xs font-bold text-n-slate-12">
                    {{ meal.name }} <span v-if="meal.time" class="font-normal text-n-slate-10">· {{ meal.time }}</span>
                  </p>
                  <p v-if="meal.desc" class="text-[11px] text-n-slate-10 truncate">{{ meal.desc }}</p>
                  <p v-if="mealEquiv(meal)" class="text-[10px]" :style="{ color: ROYAL }">
                    <span class="i-lucide-drumstick hub-ico-inline" style="color: inherit" />{{ mealEquiv(meal) }}
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
                  :style="{ background: GRAD_ROYAL }"
                  @click="addExtra"
                >
                  Adicionar
                </button>
              </div>
            </div>
          </div>

          <!-- Editor do plano alimentar -->
          <div v-if="dietForm" class="hub-block p-5 mb-8">
            <h2 class="hub-h2 mb-1"><span class="hub-h-ico i-lucide-target" />Metas do dia</h2>
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
            <h2 class="hub-h2 mb-2"><span class="hub-h-ico i-lucide-utensils" />Refeições do plano</h2>
            <div v-for="(meal, i) in dietForm.meals" :key="i" class="hub-crystal rounded-xl p-4 mb-2">
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
                :style="{ background: GRAD_ROYAL }"
                :disabled="savingConfig"
                @click="saveDietCfg"
              >
                {{ savingConfig ? 'Salvando…' : 'Salvar plano' }}
              </button>
            </div>
          </div>

          <!-- Histórico da dieta -->
          <div class="hub-block p-5">
            <h2 class="hub-h2 mb-3"><span class="hub-h-ico i-lucide-calendar-days" />Últimos dias</h2>
            <p v-if="!diets.length" class="text-xs text-n-slate-10">Nenhum dia registrado ainda.</p>
            <div
              v-for="d in diets.slice(0, 7)"
              :key="d.id"
              class="flex items-center gap-3 py-2 border-b border-n-weak last:border-0"
            >
              <span class="text-[11px] font-bold text-n-slate-11" style="width: 3rem">{{ fmtDay(d.record_date) }}</span>
              <div class="flex-1 h-2 rounded-full bg-n-alpha-1 overflow-hidden">
                <div class="h-full rounded-full" :style="{ width: `${dietDayPct(d)}%`, background: ROYAL }" />
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
          <div class="hub-block p-5 sm:p-6 mb-8">
            <h2 class="hub-h2 mb-1"><span class="hub-h-ico i-lucide-ruler" />Registrar medidas</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">
              Protocolo: braço RELAXADO · antebraço na parte mais grossa, punho solto · coxa no meio virilha–joelho · panturrilha em pé, na parte mais grossa · cintura após expiração normal, sem encolher · pescoço abaixo do pomo de Adão, sem apertar. Sempre do mesmo jeito.
            </p>

            <div class="flex items-center gap-2 flex-wrap mb-4 hub-crystal rounded-xl px-4 py-3">
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
                :style="{ background: GRAD_ROYAL }"
                :disabled="savingBody"
                @click="saveBody"
              >
                {{ savingBody ? 'Salvando…' : '✓ Salvar medidas' }}
              </button>
            </div>
          </div>

          <!-- Gráfico do peso -->
          <div class="hub-block p-5 mb-8">
            <h2 class="hub-h2 mb-3"><span class="hub-h-ico i-lucide-scale" />Peso ao longo do tempo</h2>
            <MiniBars
              v-if="weightSeries.values.length > 1"
              :values="weightSeries.values"
              :labels="weightSeries.labels"
              :color="ROYAL"
              :height="110"
              :format="v => `${fmtNum(v)} kg`"
            />
            <p v-else class="text-xs text-n-slate-10">Registre o peso em pelo menos 2 dias pra ver a curva.</p>
          </div>

          <!-- Medidas atuais -->
          <div class="grid grid-cols-2 lg:grid-cols-3 gap-3 mb-4">
            <div v-for="m in currentMeasures" :key="m.key" class="hub-crystal rounded-xl p-4">
              <p class="text-[11px] font-medium text-n-slate-11">{{ m.label }}</p>
              <p class="text-lg font-bold text-n-slate-12">
                {{ m.value === null ? '—' : `${fmtNum(m.value)}${m.suffix}` }}
              </p>
              <p v-if="m.delta !== null && m.delta !== 0" class="text-[11px]" :style="{ color: m.delta > 0 ? LARANJA : ROYAL }">
                {{ m.delta > 0 ? '▲' : '▼' }} {{ fmtNum(Math.abs(m.delta)) }} desde a última
              </p>
            </div>
          </div>

          <!-- Histórico do corpo -->
          <div class="hub-block p-5">
            <h2 class="hub-h2 mb-3"><span class="hub-h-ico i-lucide-calendar-days" />Últimas medições</h2>
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
    <HubCelebration :data="celebration" @close="celebration = null" />
  </div>
</template>

<style scoped>
/* rodada 26: TODOS os treinos com moldura; o da vez segue laranja */
.hub-session-card:not(.is-next) {
  border: 1.5px solid rgba(65, 105, 225, 0.42) !important;
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.9),
    0 10px 24px -14px rgba(39, 64, 139, 0.45) !important;
}
:global(.dark) .hub-session-card:not(.is-next) {
  border-color: rgba(143, 169, 245, 0.55) !important;
}
/* rodada 29: teias pequenas nos cartões + sliders do perfil técnico */
.hub-radar-sm { margin: 2px 0 0; }
.hub-radar-sm :deep(svg) { max-width: 320px !important; }
.hub-radar-form :deep(svg) { max-width: 360px !important; }
.hub-slider { display: grid; grid-template-columns: 5.6rem 1fr 1.6rem; align-items: center; gap: 8px; font-size: 11px; }
.hub-slider label { font-weight: 700; color: #334155; }
.hub-slider b { text-align: right; color: #27408b; font-size: 12px; }
.hub-slider input[type='range'] { width: 100%; accent-color: #4169e1; margin: 0; height: 22px; }
:global(.dark) .hub-slider label { color: #fff; }
:global(.dark) .hub-slider b { color: #fff; }
/* rodada 27: tipo de cardio (grade fixa), estatísticas, campos escuros, controles do professor */
.hub-cardio-type {
  height: 64px;
  border-radius: 16px;
  border: 1px solid rgba(65, 105, 225, 0.22);
  background: rgba(255, 255, 255, 0.85);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 4px;
  font-size: 11px;
  font-weight: 700;
  color: #334155;
  transition: all 0.15s ease;
}
.hub-cardio-type .hub-cardio-ico { width: 20px; height: 20px; color: #4169e1; }
.hub-cardio-type.is-on { background: linear-gradient(135deg, #27408b, #4169e1); color: #fff; border-color: transparent; box-shadow: 0 8px 20px rgba(65, 105, 225, 0.35); }
.hub-cardio-type.is-on .hub-cardio-ico { color: #fff; }
:global(.dark) .hub-cardio-type { background: rgba(255, 255, 255, 0.06); color: #fff; }
.hub-stat {
  border-radius: 14px;
  padding: 10px 12px;
  background: rgba(65, 105, 225, 0.08);
  border: 1px solid rgba(65, 105, 225, 0.18);
  display: flex;
  flex-direction: column;
  line-height: 1.1;
}
.hub-stat b { font-size: 20px; font-weight: 900; color: #27408b; }
.hub-stat span { font-size: 10px; text-transform: uppercase; letter-spacing: 0.08em; color: #64748b; margin-top: 3px; }
:global(.dark) .hub-stat b { color: #fff; }
.hub-field-dark { background: rgba(255, 255, 255, 0.1) !important; border-color: rgba(255, 255, 255, 0.25) !important; color: #fff !important; }
.hub-field-dark::placeholder { color: rgba(255, 255, 255, 0.6); }
.hub-acc-dark { background: rgba(255, 255, 255, 0.08) !important; border-color: rgba(255, 255, 255, 0.18) !important; }
.hub-acc-dark.is-open { border-color: rgba(255, 178, 94, 0.6) !important; }
.hub-acc-dark .hub-acc-body { border-top-color: rgba(255, 255, 255, 0.14); }
.hub-pro-ctl { border-radius: 12px; padding: 8px 10px; background: rgba(255, 255, 255, 0.08); display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.hub-pro-ctl > div { flex-wrap: wrap; }
.hub-pro-ctl em { font-style: normal; font-size: 10px; text-transform: uppercase; letter-spacing: 0.08em; opacity: 0.75; }
.hub-pro-ctl b { min-width: 22px; text-align: center; font-size: 15px; }
.hub-pro-bump { width: 28px; height: 28px; border-radius: 8px; font-weight: 900; border: 1px solid rgba(255, 255, 255, 0.3); }
.hub-pro-pill { height: 28px; padding: 0 9px; border-radius: 8px; font-size: 11px; font-weight: 700; border: 1px solid rgba(255, 255, 255, 0.25); }
.hub-pro-pill.is-on { background: #ff8a00; color: #1a0e00; border-color: transparent; }
/* controles do construtor por rounds / plano de luta */
.hub-rounds-ctl {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  height: 36px;
  padding: 0 8px;
  border-radius: 10px;
  background: rgba(255, 255, 255, 0.1);
  font-size: 12px;
}
.hub-rounds-ctl.is-light {
  background: rgba(65, 105, 225, 0.08);
}
.hub-rounds-ctl em {
  font-style: normal;
  font-size: 10px;
  opacity: 0.75;
  margin-right: 2px;
}
.hub-rounds-ctl > button {
  width: 26px;
  height: 26px;
  border-radius: 8px;
  font-weight: 900;
  border: 1px solid rgba(148, 163, 184, 0.45);
}
.hub-rounds-ctl b {
  min-width: 20px;
  text-align: center;
  font-size: 14px;
}
.hub-rounds-pill {
  width: auto !important;
  padding: 0 8px;
  font-size: 11px;
  font-weight: 700 !important;
}
.hub-rounds-pill.is-on {
  background: #ff8a00;
  color: #1a0e00;
  border-color: transparent !important;
}
.hub-rounds-num {
  width: 3rem !important;
  height: 26px;
  border-radius: 8px;
  border: 1px solid rgba(148, 163, 184, 0.45);
  background: rgba(255, 255, 255, 0.12);
  color: inherit;
  text-align: center;
  font-size: 12px;
  margin-bottom: 0 !important;
}
/* Cartão de vidro da meta (rodada 13): translúcido c/ blur, borda fina
   e brilho interno — royal no dia a dia, LARANJA quando a meta foi batida */
.hub-glass {
  background: linear-gradient(
    135deg,
    rgba(65, 105, 225, 0.12),
    rgba(65, 105, 225, 0.04) 45%,
    rgba(255, 255, 255, 0.04)
  );
  -webkit-backdrop-filter: blur(14px) saturate(1.5);
  backdrop-filter: blur(14px) saturate(1.5);
  border: 1px solid rgba(65, 105, 225, 0.26);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.08),
    0 6px 18px -12px rgba(65, 105, 225, 0.5);
}
.hub-glass-gold {
  background: linear-gradient(
    135deg,
    rgba(255, 138, 0, 0.14),
    rgba(255, 138, 0, 0.04) 45%,
    rgba(255, 255, 255, 0.04)
  );
  border-color: rgba(255, 138, 0, 0.32);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.08),
    0 6px 18px -12px rgba(255, 138, 0, 0.55);
}
/* extra recente (rodada 20): chip tocável com o nome e a última execução */
.hub-extra-chip {
  display: inline-flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 1px;
  padding: 0.35rem 0.65rem;
  border-radius: 0.75rem;
  font-size: 11px;
  line-height: 1.2;
  border: 1px solid rgba(65, 105, 225, 0.3);
  background: rgba(65, 105, 225, 0.08);
  transition: transform 0.12s ease, background 0.12s ease;
}
.hub-extra-chip:active {
  transform: scale(0.96);
}
.hub-extra-chip:hover {
  background: rgba(65, 105, 225, 0.16);
}
/* boxe guiado (rodada 20): relógio redondo + botões de bloco */
.hub-box-clock {
  width: 13.5rem;
  height: 13.5rem;
}
.hub-box-btn {
  width: 3rem;
  height: 3rem;
  border-radius: 9999px;
  background: rgba(255, 255, 255, 0.14);
  color: #fff;
  font-size: 24px;
  line-height: 1;
}
.hub-box-btn:disabled {
  opacity: 0.3;
}
.hub-box-btn:not(:disabled):active {
  transform: scale(0.92);
}
.hub-mini-input {
  width: 3.4rem;
  height: 2rem;
  margin-bottom: 0;
  border-radius: 0.5rem;
  border: 1px solid rgba(148, 163, 184, 0.35);
  background: transparent;
  text-align: center;
  font-size: 11px;
}
/* modo "digitar" (rodada 16): caixinha grande no lugar da roleta */
.hub-type-input {
  height: 3rem;
  margin-bottom: 0;
  border-radius: 0.75rem;
  border: 1px solid rgba(65, 105, 225, 0.35);
  background: transparent;
  text-align: center;
  font-size: 19px;
  font-weight: 700;
}
.hub-type-input:focus {
  outline: none;
  border-color: #4169e1;
  box-shadow: 0 0 0 3px rgba(65, 105, 225, 0.18);
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
