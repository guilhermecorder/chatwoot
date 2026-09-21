<script setup>
// CONSTRUTOR DE ROTINA (rodada 26) — pedido dele 19/09: "um novo ambiente
// de rotina pra otimizar e visualizar melhor os dias, semanas, meses e
// anos; construir rotinas campeãs de acordo com os objetivos de vida".
// DIA = blocos de horário por dia da semana (linha do tempo colorida por
// área da vida) · SEMANA = as 7 linhas lado a lado + onde vai o tempo ·
// MÊS = foco e metas de cada mês (com os programas de treino que passam
// por ele) · ANO = onde quero chegar em cada área + metas do ano.
// Tudo num registro kind=routine por pessoa (salva sozinho ao mexer).
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';
import {
  ROUTINE_CATS, routineCat, LIFE_AREAS, WEEKDAYS,
  ROUTINE_PRESET_WEEKDAY, ROUTINE_PRESET_WEEKEND, ROUTINE_PRESETS,
  timeToMin, dayMinutesByCat, customToProgram, programWeeks,
  resolvePrograms, mainProgramOf, weekOf, cycleForWeek,
} from './warrior';
import { ROYAL, LARANJA, LARANJA_VIVO, GRAD_ROYAL, GRAD_NOITE, GRAD_LARANJA } from './palette';

const route = useRoute();
const router = useRouter();
const isLoading = ref(true);
const config = ref({});
const profile = ref({});
const programRecords = ref([]);
const routine = ref({ days: {}, months: {}, years: {} });
const loaded = ref(false);
const savedAt = ref('');
const saving = ref(false);

const boxingOn = computed(() => config.value?.features?.boxing === true);
const todayISO = new Date().toISOString().slice(0, 10);
const todayWeekday = WEEKDAYS[(new Date().getDay() + 6) % 7];
const nowYear = new Date().getFullYear();
const nowMonthKey = todayISO.slice(0, 7);

const VIEWS = [
  { key: 'dia', ico: 'i-lucide-sunrise', label: 'Dia' },
  { key: 'semana', ico: 'i-lucide-calendar', label: 'Semana' },
  { key: 'mes', ico: 'i-lucide-calendar-days', label: 'Mês' },
  { key: 'ano', ico: 'i-lucide-trophy', label: 'Ano' },
];
const view = ref('dia');
const selDay = ref(todayWeekday);
const year = ref(nowYear);

const clone = v => JSON.parse(JSON.stringify(v));
const fmtH = min => `${Math.floor(min / 60)}h${min % 60 ? String(min % 60).padStart(2, '0') : ''}`;
const textOn = color => (['#8FA9F5', '#FFB25E', '#94A3B8', '#FF8A00'].includes(color) ? '#111827' : '#fff');

// ── carga + salvamento automático ──────────────────────────────────
onMounted(async () => {
  try {
    const { data } = await CrmAPI.getHealth();
    config.value = data.config || {};
    profile.value = data.profile || {};
    programRecords.value = data.programs || [];
    const r = data.routine || {};
    routine.value = { days: r.days || {}, months: r.months || {}, years: r.years || {} };
  } catch {
    useAlert('Não consegui carregar a rotina.');
  } finally {
    isLoading.value = false;
    setTimeout(() => {
      loaded.value = true;
    }, 0);
  }
});
let saveTimer = null;
const saveRoutine = async () => {
  saving.value = true;
  try {
    await CrmAPI.createHealthRecord({ kind: 'routine', data: routine.value });
    savedAt.value = new Date().toTimeString().slice(0, 5);
  } catch {
    useAlert('Não consegui salvar a rotina.');
  } finally {
    saving.value = false;
  }
};
watch(
  routine,
  () => {
    if (!loaded.value) return;
    clearTimeout(saveTimer);
    saveTimer = setTimeout(saveRoutine, 700);
  },
  { deep: true }
);

// ── DIA: blocos de horário ─────────────────────────────────────────
const blocksOf = day => routine.value.days[day] || [];
const sortBlocks = list => [...list].sort((a, b) => timeToMin(a.start) - timeToMin(b.start));
const dayBlocks = computed(() => sortBlocks(blocksOf(selDay.value)));
const PX_H = 26; // pixels por hora na linha do dia
const HOURS = Array.from({ length: 13 }, (_, i) => i * 2);
// segmentos desenháveis (bloco que passa da meia-noite vira 2 pedaços)
const segmentsOf = (blocks, px) =>
  blocks.flatMap(b => {
    const s = timeToMin(b.start);
    let e = timeToMin(b.end);
    if (e <= s) e += 1440;
    const cat = routineCat(b.cat);
    const seg = (from, to) => ({
      id: `${b.id}-${from}`,
      block: b,
      top: (from / 60) * px,
      height: Math.max(6, ((to - from) / 60) * px - 2),
      color: cat.color,
      text: textOn(cat.color),
      icon: cat.icon,
    });
    if (e <= 1440) return [seg(s, e)];
    return [seg(s, 1440), seg(0, e - 1440)];
  });
const daySegments = computed(() => segmentsOf(dayBlocks.value, PX_H));
const dayByCat = computed(() => {
  const acc = dayMinutesByCat(dayBlocks.value);
  return ROUTINE_CATS.map(c => ({ ...c, min: acc[c.key] || 0 })).filter(c => c.min > 0);
});

const blockForm = ref(null);
const openNewBlock = () => {
  const last = dayBlocks.value.at(-1);
  blockForm.value = { id: '', start: last?.end || '06:00', end: '', title: '', cat: 'saude', note: '' };
};
const openEditBlock = b => {
  blockForm.value = clone(b);
};
const saveBlock = () => {
  const f = blockForm.value;
  if (!f.title.trim() || !f.start || !f.end) {
    useAlert('Preencha início, fim e o nome do bloco.');
    return;
  }
  const list = [...blocksOf(selDay.value)];
  if (f.id) {
    const i = list.findIndex(b => b.id === f.id);
    if (i >= 0) list[i] = { ...f, title: f.title.trim() };
  } else {
    list.push({ ...f, id: `b${Date.now().toString(36)}`, title: f.title.trim() });
  }
  routine.value.days[selDay.value] = sortBlocks(list);
  blockForm.value = null;
};
const removeBlock = b => {
  routine.value.days[selDay.value] = blocksOf(selDay.value).filter(x => x.id !== b.id);
  blockForm.value = null;
};
const presetsOpen = ref(false);
// rodada 33: ESCOPO do modelo — só este dia, seg–sex, sáb–dom ou a semana
// toda (seg–sex com o modelo escolhido + sáb–dom com o de fim de semana)
const PRESET_SCOPES = [
  { key: 'dia', label: 'só este dia' },
  { key: 'uteis', label: 'seg–sex' },
  { key: 'fds', label: 'sáb–dom' },
  { key: 'semana', label: 'semana toda' },
];
const presetScope = ref('dia');
const stamp = day => `${Date.now().toString(36)}_${day.slice(0, 3)}`;
const presetBlocks = kind => {
  const found = ROUTINE_PRESETS.find(p => p.key === kind);
  return found ? found.blocks : kind === 'fds' ? ROUTINE_PRESET_WEEKEND : ROUTINE_PRESET_WEEKDAY;
};
const applyPreset = kind => {
  presetsOpen.value = false;
  const scope = presetScope.value;
  const days = scope === 'dia' ? [selDay.value] : scope === 'uteis' ? WEEKDAYS.slice(0, 5) : scope === 'fds' ? WEEKDAYS.slice(5) : WEEKDAYS;
  days.forEach(day => {
    const weekend = WEEKDAYS.indexOf(day) >= 5;
    const src = scope === 'semana' && weekend && kind !== 'fds' ? presetBlocks('fds') : presetBlocks(kind);
    routine.value.days[day] = clone(src).map(b => ({ ...b, id: `${b.id}_${stamp(day)}` }));
  });
  if (days.length > 1) useAlert(`Modelo aplicado em ${days.length} dias.`);
};
// rodada 33: DESLOCAR O RELÓGIO do dia inteiro (±30 min) — "a rotina tem
// que ser ajustável": todos os blocos andam juntos, a meia-noite dá a volta
const pad2 = n => String(n).padStart(2, '0');
const minToTime = m => `${pad2(Math.floor(m / 60))}:${pad2(m % 60)}`;
const shiftDay = delta => {
  const sh = t => minToTime((timeToMin(t) + delta + 1440) % 1440);
  routine.value.days[selDay.value] = sortBlocks(blocksOf(selDay.value).map(b => ({ ...b, start: sh(b.start), end: sh(b.end) })));
};
// rodada 33: o bloco "Treino" mostra o TREINO REAL do dia (programa ativo:
// sessão daquele dia da semana, semana atual do programa, nº de exercícios)
const mainProgram = computed(() => mainProgramOf(resolvePrograms(config.value, profile.value, programRecords.value)));
const curWeek = computed(() => weekOf(mainProgram.value, todayISO));
const curCycle = computed(() => cycleForWeek(mainProgram.value, curWeek.value));
const sessionFor = day =>
  (curCycle.value?.sessions || []).find(s => (s.weekday || '').toLowerCase().startsWith(day.slice(0, 4).toLowerCase())) || null;
const isTrainingBlock = b => b.cat === 'saude' && /treino/i.test(b.title || '') && !/cardio|boxe/i.test(b.title || '');
const trainingFor = day => {
  const p = mainProgram.value;
  if (!p) return null;
  const s = sessionFor(day);
  const weeks = programWeeks(p) || 0;
  if (!s) return { rest: true, name: p.name, week: curWeek.value, weeks };
  return { rest: false, key: s.key, label: s.label || '', n: (s.exercises || []).length, name: p.name, week: curWeek.value, weeks };
};
const dayTraining = computed(() => trainingFor(selDay.value));
const goTrain = key => {
  router.push({ name: 'hub_health', params: { accountId: route.params.accountId }, query: { start: key } });
};
const copyDayTo = day => {
  if (day === selDay.value) return;
  routine.value.days[day] = clone(blocksOf(selDay.value)).map(b => ({ ...b, id: `${b.id}_${day.slice(0, 3)}` }));
  useAlert(`Copiado pra ${day}.`);
};
const copyToWeekdays = () => {
  WEEKDAYS.slice(0, 5).forEach(d => copyDayTo(d));
};

// ── SEMANA ─────────────────────────────────────────────────────────
const PX_W = 13;
const weekColumns = computed(() =>
  WEEKDAYS.map(d => ({ day: d, segments: segmentsOf(sortBlocks(blocksOf(d)), PX_W), n: blocksOf(d).length }))
);
const weekByCat = computed(() => {
  const acc = {};
  WEEKDAYS.forEach(d => {
    const m = dayMinutesByCat(blocksOf(d));
    Object.entries(m).forEach(([k, v]) => {
      acc[k] = (acc[k] || 0) + v;
    });
  });
  const total = Object.values(acc).reduce((a, b) => a + b, 0) || 1;
  return ROUTINE_CATS.map(c => ({ ...c, min: acc[c.key] || 0, pct: Math.round(((acc[c.key] || 0) / total) * 100) })).filter(c => c.min > 0);
});
const goDay = d => {
  selDay.value = d;
  view.value = 'dia';
};

// ── programas de treino que passam pelos meses (pra se situar) ──────
const allPrograms = computed(() => [
  ...(config.value?.programs || []).filter(p => p.start_date),
  ...programRecords.value.filter(r => r.data?.status === 'active').map(customToProgram),
]);
const programSpans = computed(() =>
  allPrograms.value.map(p => {
    const weeks = programWeeks(p) || 12;
    const start = new Date(`${p.start_date}T00:00:00`);
    const end = new Date(start);
    end.setDate(end.getDate() + weeks * 7 - 1);
    return { name: p.name, custom: !!p.custom, start, end, weeks };
  })
);
const programsInMonth = key => {
  const [y, m] = key.split('-').map(Number);
  const first = new Date(y, m - 1, 1);
  const last = new Date(y, m, 0);
  return programSpans.value.filter(p => p.start <= last && p.end >= first);
};

// ── MÊS ────────────────────────────────────────────────────────────
const MONTHS_PT = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
const monthKeys = computed(() => MONTHS_PT.map((_, i) => `${year.value}-${String(i + 1).padStart(2, '0')}`));
const monthOf = key => {
  if (!routine.value.months[key]) routine.value.months[key] = { focus: '', goals: [] };
  return routine.value.months[key];
};
const monthLabel = key => `${MONTHS_PT[Number(key.slice(5, 7)) - 1]} ${key.slice(0, 4)}`;
const goalDraft = ref({});
const addGoal = target => {
  const text = (goalDraft.value[target.key] || '').trim();
  if (!text) return;
  target.list.push({ text, done: false });
  goalDraft.value[target.key] = '';
};
const monthProgress = m => {
  const n = (m.goals || []).length;
  return n ? Math.round(((m.goals || []).filter(g => g.done).length / n) * 100) : null;
};

// ── ANO ────────────────────────────────────────────────────────────
const yearOf = y => {
  if (!routine.value.years[y]) routine.value.years[y] = { areas: {}, goals: [] };
  const yr = routine.value.years[y];
  if (!yr.areas) yr.areas = {};
  if (!yr.goals) yr.goals = [];
  return yr;
};
const yearData = computed(() => yearOf(String(year.value)));
const areaDefs = computed(() => LIFE_AREAS.map(k => routineCat(k)));
const yearDone = computed(() => {
  const g = yearData.value.goals || [];
  return g.length ? Math.round((g.filter(x => x.done).length / g.length) * 100) : null;
});
</script>

<template>
  <div class="hub-page flex-1 overflow-auto p-4 pb-20 sm:p-6 md:pb-6">
    <div class="max-w-5xl mx-auto">
      <div class="flex items-center gap-3 flex-wrap mb-4">
        <span class="w-9 h-9 rounded-xl flex items-center justify-center" :style="{ background: GRAD_NOITE }">
          <span class="i-lucide-calendar-range text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="hub-h1">Rotina</h1>
          <p class="text-[11px] text-n-slate-10">construtor de dias, semanas, meses e anos — rotinas campeãs pros seus objetivos de vida</p>
        </div>
        <span class="text-[10px] text-n-slate-10">{{ saving ? 'salvando…' : savedAt ? `salvo ✓ ${savedAt}` : '' }}</span>
      </div>

      <div v-if="isLoading" class="flex justify-center py-16"><Spinner /></div>
      <template v-else>
        <!-- pílulas Dia · Semana · Mês · Ano -->
        <div class="hub-seg hub-seg-full mb-4">
          <button v-for="v in VIEWS" :key="v.key" :class="{ 'is-on': view === v.key }" @click="view = v.key">
            <span :class="v.ico" />{{ v.label }}
          </button>
        </div>

        <!-- ═══ DIA ═══ -->
        <template v-if="view === 'dia'">
          <div class="hub-block p-5 mb-8">
            <div class="flex items-center gap-1.5 flex-wrap mb-3">
              <button
                v-for="d in WEEKDAYS"
                :key="d"
                class="h-9 px-3 rounded-full text-xs font-bold border relative"
                :class="selDay === d ? 'text-white border-transparent' : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
                :style="selDay === d ? { background: d === todayWeekday ? GRAD_LARANJA : GRAD_NOITE } : {}"
                @click="selDay = d"
              >
                {{ d.slice(0, 3) }}
                <span v-if="blocksOf(d).length" class="ml-1 text-[9px] opacity-80">{{ blocksOf(d).length }}</span>
                <span v-if="d === todayWeekday && selDay !== d" class="absolute -top-1 -right-1 w-2 h-2 rounded-full" :style="{ background: LARANJA }" />
              </button>
              <div class="flex-1" />
              <span v-if="dayBlocks.length" class="hub-clock" title="Desloca todos os blocos deste dia">
                <button class="hub-clock-btn" title="Tudo 30 min mais cedo" @click="shiftDay(-30)"><span class="i-lucide-chevron-left" /></button>
                <span class="hub-clock-l"><span class="i-lucide-clock" />30 min</span>
                <button class="hub-clock-btn" title="Tudo 30 min mais tarde" @click="shiftDay(30)"><span class="i-lucide-chevron-right" /></button>
              </span>
              <button class="h-9 px-3 rounded-xl text-xs font-bold border border-n-weak text-n-slate-11 hover:bg-n-alpha-1" :class="{ 'is-on': presetsOpen }" @click="presetsOpen = !presetsOpen"><span class="i-lucide-layout-template hub-ico" style="width: 14px; height: 14px" /> Modelos</button>
              <button class="h-9 px-3 rounded-xl text-xs font-bold text-white" :style="{ background: GRAD_LARANJA }" @click="openNewBlock">+ bloco</button>
            </div>

            <!-- editor do bloco -->
            <div v-if="blockForm" class="rounded-xl border border-dashed p-3 mb-3" :style="{ borderColor: LARANJA }">
              <div class="flex items-end gap-2 flex-wrap mb-2">
                <label class="block">
                  <span class="text-[11px] font-medium text-n-slate-11">Início</span>
                  <input v-model="blockForm.start" type="time" class="mt-1 block h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12" style="width: 7rem; margin-bottom: 0" />
                </label>
                <label class="block">
                  <span class="text-[11px] font-medium text-n-slate-11">Fim</span>
                  <input v-model="blockForm.end" type="time" class="mt-1 block h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12" style="width: 7rem; margin-bottom: 0" />
                </label>
                <label class="block flex-1" style="min-width: 12rem">
                  <span class="text-[11px] font-medium text-n-slate-11">O que</span>
                  <input v-model="blockForm.title" type="text" placeholder="ex.: Treino · Trabalho foco · Família" class="mt-1 block w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12" style="margin-bottom: 0" />
                </label>
              </div>
              <div class="flex gap-1.5 flex-wrap mb-2">
                <button
                  v-for="c in ROUTINE_CATS"
                  :key="c.key"
                  class="h-8 px-2.5 rounded-lg text-[11px] font-bold border"
                  :class="blockForm.cat === c.key ? 'border-transparent' : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
                  :style="blockForm.cat === c.key ? { background: c.color, color: textOn(c.color) } : {}"
                  @click="blockForm.cat = c.key"
                >
                  <span :class="c.ico" class="hub-ico" style="width: 13px; height: 13px" /> {{ c.label }}
                </button>
              </div>
              <input v-model="blockForm.note" type="text" placeholder="Detalhe (opcional): regra, intenção, lembrete" class="block w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12" style="margin-bottom: 8px" />
              <div class="flex gap-2 flex-wrap">
                <div class="flex-1" />
                <button v-if="blockForm.id" class="h-9 px-3 rounded-lg text-xs border border-n-weak hover:bg-n-alpha-1" style="color: #dc2626" @click="removeBlock(blockForm)">Excluir</button>
                <button class="h-9 px-3 rounded-lg text-xs text-n-slate-11 border border-n-weak hover:bg-n-alpha-1" @click="blockForm = null">Cancelar</button>
                <button class="h-9 px-4 rounded-lg text-xs font-bold text-white" :style="{ background: GRAD_ROYAL }" @click="saveBlock">Salvar bloco</button>
              </div>
            </div>

            <!-- dia vazio: rotina campeã de partida -->
            <div v-if="(!dayBlocks.length || presetsOpen) && !blockForm" class="hub-crystal rounded-2xl p-5 text-center mb-6">
              <span class="hub-sec-ico mx-auto mb-2"><span class="i-lucide-sunrise" /></span>
              <p class="hub-h2 justify-center">{{ dayBlocks.length ? `Modelos pra ${selDay}` : `${selDay} ainda sem rotina` }}</p>
              <p class="text-[11px] text-n-slate-10 mb-4">{{ dayBlocks.length ? "Aplicar um modelo substitui os blocos deste dia — depois é só ajustar." : "Comece por um modelo campeão e ajuste — ou monte bloco a bloco." }}</p>
              <div class="hub-seg hub-seg-wrap mb-4">
                <button v-for="sc in PRESET_SCOPES" :key="sc.key" class="hub-seg-opt" :class="{ 'is-on': presetScope === sc.key }" :style="presetScope === sc.key ? { background: ROYAL } : {}" @click="presetScope = sc.key">{{ sc.label }}</button>
              </div>
              <div class="hub-preset-grid">
                <!-- rodada 32: rotinas pré-definidas por relógio (acorda cedo/tarde × dorme cedo/tarde) + fim de semana -->
                <button
                  v-for="p in ROUTINE_PRESETS"
                  :key="p.key"
                  class="hub-preset hub-crystal t-royal"
                  :title="`Aplica em ${selDay}: ${p.sub}`"
                  @click="applyPreset(p.key)"
                >
                  <span class="hub-preset-ico" :class="p.ico" />
                  <span class="hub-preset-l">{{ p.label }}</span>
                  <span class="hub-preset-t"><b>{{ p.wake }}</b> acorda · <b>{{ p.sleep }}</b> dorme</span>
                  <span class="hub-preset-s">{{ p.sub }}</span>
                </button>
                <button class="hub-preset hub-crystal t-orange" title="Sábado e domingo" @click="applyPreset('fds')">
                  <span class="hub-preset-ico i-lucide-tent" />
                  <span class="hub-preset-l">Fim de semana</span>
                  <span class="hub-preset-t"><b>07:00</b> acorda · <b>22:00</b> dorme</span>
                  <span class="hub-preset-s">ar livre, família, projeto pessoal, revisão da semana</span>
                </button>
              </div>
            </div>

            <div v-else class="hub-rt-day">
              <!-- linha do tempo -->
              <div class="relative hub-crystal rounded-2xl overflow-hidden" :style="{ height: `${24 * PX_H + 8}px` }">
                <div v-for="h in HOURS" :key="h" class="absolute left-0 right-0 border-t border-n-weak/60 text-[9px] text-n-slate-10 pl-1" :style="{ top: `${(h / 1) * PX_H + 4}px` }">{{ String(h).padStart(2, '0') }}h</div>
                <div
                  v-for="sg in daySegments"
                  :key="sg.id"
                  class="absolute left-8 right-1 rounded-md px-1.5 overflow-hidden cursor-pointer hub-rt-seg"
                  :style="{ top: `${sg.top + 4}px`, height: `${sg.height}px`, background: sg.color, color: sg.text }"
                  :title="`${sg.block.start}–${sg.block.end} ${sg.block.title}`"
                  @click="openEditBlock(sg.block)"
                >
                  <span class="text-[10px] font-bold leading-tight">{{ sg.block.title }}</span>
                </div>
              </div>
              <!-- lista + resumo -->
              <div>
                <div v-for="b in dayBlocks" :key="b.id" class="hub-rt-row" @click="openEditBlock(b)">
                  <span class="hub-rt-bar" :style="{ background: routineCat(b.cat).color }" />
                  <span class="hub-rt-time">{{ b.start }}–{{ b.end }}</span>
                  <span class="hub-rt-main">
                    <span class="hub-rt-title">{{ b.title }}</span>
                    <!-- rodada 33: o bloco "Treino" puxa o treino real do dia -->
                    <template v-if="isTrainingBlock(b) && dayTraining">
                      <span v-if="!dayTraining.rest" class="hub-rt-train" title="Abrir este treino" @click.stop="goTrain(dayTraining.key)">
                        <span class="i-lucide-dumbbell hub-rt-train-i" />
                        <span class="hub-rt-train-t"><b>Treino {{ dayTraining.key }}</b><template v-if="dayTraining.label"> · {{ dayTraining.label }}</template> · semana {{ dayTraining.week }} de {{ dayTraining.weeks }} · {{ dayTraining.n }} exercícios</span>
                        <span class="i-lucide-play hub-rt-go" />
                      </span>
                      <span v-else class="hub-rt-train is-rest"><span class="i-lucide-bed hub-rt-train-i" /><span class="hub-rt-train-t">sem treino programado neste dia · {{ dayTraining.name }}</span></span>
                    </template>
                    <span v-else-if="b.note" class="hub-rt-note">{{ b.note }}</span>
                  </span>
                </div>
                <div class="mt-3">
                  <p class="text-[10px] font-bold text-n-slate-11 uppercase tracking-wide mb-1">Onde vai o dia</p>
                  <div class="flex gap-1 h-3 rounded-full overflow-hidden bg-n-alpha-2 mb-1">
                    <div v-for="c in dayByCat" :key="c.key" :style="{ width: `${(c.min / 1440) * 100}%`, background: c.color }" :title="`${c.label} ${fmtH(c.min)}`" />
                  </div>
                  <div class="flex gap-2 flex-wrap">
                    <span v-for="c in dayByCat" :key="c.key" class="text-[10px] text-n-slate-11"><span class="inline-block w-2 h-2 rounded-sm mr-1" :style="{ background: c.color }" />{{ c.label }} <b>{{ fmtH(c.min) }}</b></span>
                  </div>
                </div>
                <div class="mt-3 flex items-center gap-1 flex-wrap">
                  <span class="text-[10px] text-n-slate-10 mr-1">copiar este dia pra:</span>
                  <button v-for="d in WEEKDAYS.filter(x => x !== selDay)" :key="d" class="h-6 px-2 rounded-md text-[10px] border border-n-weak hover:bg-n-alpha-1 text-n-slate-11" @click="copyDayTo(d)">{{ d.slice(0, 3) }}</button>
                  <button class="h-6 px-2 rounded-md text-[10px] font-bold text-white" :style="{ background: ROYAL }" @click="copyToWeekdays">Seg–Sex</button>
                  <button class="h-6 px-2 rounded-md text-[10px] border border-n-weak hover:bg-n-alpha-1" style="color: #dc2626" @click="routine.days[selDay] = []">limpar</button>
                </div>
              </div>
            </div>
          </div>
        </template>

        <!-- ═══ SEMANA ═══ -->
        <template v-if="view === 'semana'">
          <div class="hub-block p-5 mb-8">
            <h2 class="hub-h2 mb-1"><span class="hub-h-ico i-lucide-calendar" />A semana inteira</h2>
            <p class="text-[11px] text-n-slate-10 mb-3">Cada coluna é um dia (toque pra editar). Cores = áreas da vida.</p>
            <div class="grid gap-1.5" style="grid-template-columns: repeat(7, minmax(0, 1fr))">
              <div v-for="c in weekColumns" :key="c.day" class="min-w-0 cursor-pointer" @click="goDay(c.day)">
                <p class="text-[10px] font-bold text-center mb-1 rounded-md py-0.5" :style="c.day === todayWeekday ? { background: LARANJA, color: '#1a0e00' } : { color: '#64748b' }">{{ c.day.slice(0, 3) }}</p>
                <div class="relative rounded-lg border border-n-weak bg-n-solid-1 overflow-hidden" :style="{ height: `${24 * PX_W + 4}px` }">
                  <div v-for="h in [6, 12, 18]" :key="h" class="absolute left-0 right-0 border-t border-n-weak/50" :style="{ top: `${h * PX_W + 2}px` }" />
                  <div v-for="sg in c.segments" :key="sg.id" class="absolute left-0.5 right-0.5 rounded-sm overflow-hidden" :style="{ top: `${sg.top + 2}px`, height: `${sg.height}px`, background: sg.color }" :title="`${sg.block.start}–${sg.block.end} ${sg.block.title}`" />
                  <p v-if="!c.n" class="absolute inset-0 flex items-center justify-center text-[9px] text-n-slate-10">vazio</p>
                </div>
              </div>
            </div>
          </div>
          <div class="hub-block p-5 mb-8">
            <h2 class="hub-h2 mb-1"><span class="hub-h-ico i-lucide-hourglass" />Onde vai o seu tempo na semana</h2>
            <p v-if="!weekByCat.length" class="text-[11px] text-n-slate-10">Monte pelo menos um dia pra ver a distribuição.</p>
            <div v-for="c in weekByCat" :key="c.key" class="flex items-center gap-2 mb-1.5">
              <span class="w-6 h-6 rounded-md flex items-center justify-center" :style="{ background: c.color, color: textOn(c.color) }"><span :class="c.ico" style="width: 13px; height: 13px" /></span>
              <span class="text-[11px] font-bold text-n-slate-12 w-28 truncate">{{ c.label }}</span>
              <div class="flex-1 h-2.5 rounded-full bg-n-alpha-2 overflow-hidden">
                <div class="h-full rounded-full" :style="{ width: `${c.pct}%`, background: c.color }" />
              </div>
              <span class="text-[11px] text-n-slate-10 w-24 text-right">{{ fmtH(c.min) }} · {{ c.pct }}%</span>
            </div>
          </div>
        </template>

        <!-- ═══ MÊS ═══ -->
        <template v-if="view === 'mes'">
          <div class="flex items-center gap-2 mb-3">
            <button class="h-8 w-8 rounded-lg border border-n-weak hover:bg-n-alpha-1" @click="year -= 1">‹</button>
            <span class="text-sm font-black" :style="{ color: ROYAL }">{{ year }}</span>
            <button class="h-8 w-8 rounded-lg border border-n-weak hover:bg-n-alpha-1" @click="year += 1">›</button>
            <span class="text-[11px] text-n-slate-10">foco e metas de cada mês · programas de treino que passam por ele</span>
          </div>
          <div class="grid gap-3" style="grid-template-columns: repeat(auto-fill, minmax(230px, 1fr))">
            <div
              v-for="key in monthKeys"
              :key="key"
              class="hub-block p-4"
              :class="key === nowMonthKey ? 'hub-orange hub-block-solid' : ''"
            >
              <div class="flex items-center justify-between mb-1">
                <p class="text-sm font-black">{{ monthLabel(key) }}</p>
                <span v-if="monthProgress(monthOf(key)) !== null" class="text-[10px] font-bold px-1.5 py-0.5 rounded-md" :style="key === nowMonthKey ? { background: 'rgba(255,255,255,0.22)' } : { background: 'rgba(65,105,225,0.12)', color: ROYAL }">{{ monthProgress(monthOf(key)) }}%</span>
              </div>
              <div v-if="programsInMonth(key).length" class="flex gap-1 flex-wrap mb-1.5">
                <span v-for="p in programsInMonth(key)" :key="p.name" class="text-[9px] px-1.5 py-0.5 rounded-md" :style="key === nowMonthKey ? { background: 'rgba(255,255,255,0.22)' } : { background: 'rgba(65,105,225,0.1)', color: ROYAL }">{{ p.name }}</span>
              </div>
              <input v-model="monthOf(key).focus" type="text" placeholder="Foco do mês" class="block w-full h-8 rounded-lg border px-2 text-xs mb-1.5" :class="key === nowMonthKey ? 'border-white/30 bg-white/15 text-white placeholder-white/70' : 'border-n-weak bg-n-solid-2 text-n-slate-12'" style="margin-bottom: 6px" />
              <div v-for="(g, i) in monthOf(key).goals" :key="i" class="flex items-center gap-1.5 text-[11px] py-0.5">
                <input v-model="g.done" type="checkbox" class="m-0" />
                <span class="flex-1 min-w-0 truncate" :class="g.done ? 'line-through opacity-60' : ''">{{ g.text }}</span>
                <button class="opacity-60 hover:opacity-100 text-[10px]" @click="monthOf(key).goals.splice(i, 1)">✕</button>
              </div>
              <div class="flex gap-1 mt-1">
                <input v-model="goalDraft[key]" type="text" placeholder="+ meta do mês" class="flex-1 h-7 rounded-lg border px-2 text-[11px]" :class="key === nowMonthKey ? 'border-white/30 bg-white/15 text-white placeholder-white/70' : 'border-n-weak bg-n-solid-2 text-n-slate-12'" style="margin-bottom: 0; min-width: 0" @keyup.enter="addGoal({ key, list: monthOf(key).goals })" />
                <button class="h-7 px-2 rounded-lg text-[11px] font-bold" :style="key === nowMonthKey ? { background: '#fff', color: LARANJA_VIVO } : { background: ROYAL, color: '#fff' }" @click="addGoal({ key, list: monthOf(key).goals })">+</button>
              </div>
            </div>
          </div>
        </template>

        <!-- ═══ ANO ═══ -->
        <template v-if="view === 'ano'">
          <div class="flex items-center gap-2 mb-3">
            <button class="h-8 w-8 rounded-lg border border-n-weak hover:bg-n-alpha-1" @click="year -= 1">‹</button>
            <span class="text-sm font-black" :style="{ color: ROYAL }">{{ year }}</span>
            <button class="h-8 w-8 rounded-lg border border-n-weak hover:bg-n-alpha-1" @click="year += 1">›</button>
            <span v-if="yearDone !== null" class="text-[11px] font-bold px-2 py-0.5 rounded-md" :style="{ background: 'rgba(65,105,225,0.12)', color: ROYAL }">{{ yearDone }}% das metas</span>
          </div>
          <div class="hub-block hub-block-solid p-5 mb-8 text-white">
            <p class="text-sm font-black mb-0.5 flex items-center gap-2"><span class="i-lucide-trophy" style="width: 16px; height: 16px" />Onde quero chegar em {{ year }}</p>
            <p class="text-[11px] opacity-85 mb-3">Uma frase por área da vida. É daqui que nascem as metas do mês e os blocos do dia.</p>
            <div class="grid gap-2" style="grid-template-columns: repeat(auto-fill, minmax(220px, 1fr))">
              <div v-for="a in areaDefs" :key="a.key" class="rounded-xl p-2.5" style="background: rgba(255, 255, 255, 0.12); border: 1px solid rgba(255, 255, 255, 0.2)">
                <p class="text-[11px] font-bold mb-1 flex items-center gap-1.5"><span :class="a.ico" style="width: 13px; height: 13px" />{{ a.label }}</p>
                <textarea v-model="yearData.areas[a.key]" rows="2" :placeholder="`${a.label}: onde quero estar em dezembro`" class="block w-full rounded-lg border border-white/25 bg-white/10 px-2 py-1 text-xs text-white placeholder-white/60" style="margin-bottom: 0; resize: vertical" />
              </div>
            </div>
          </div>
          <div class="hub-block p-5 mb-8">
            <h2 class="hub-h2 mb-1"><span class="hub-h-ico i-lucide-target" />Metas do ano</h2>
            <p class="text-[11px] text-n-slate-10 mb-2">Poucas e claras. Marque quando bater.</p>
            <div v-for="(g, i) in yearData.goals" :key="i" class="flex items-center gap-2 text-xs py-1.5 border-b border-n-weak/60 last:border-0">
              <input v-model="g.done" type="checkbox" class="m-0" />
              <span class="flex-1" :class="g.done ? 'line-through opacity-60' : 'text-n-slate-12 font-semibold'">{{ g.text }}</span>
              <button class="text-n-slate-10 hover:text-n-slate-12 text-[11px]" @click="yearData.goals.splice(i, 1)">✕</button>
            </div>
            <div class="flex gap-1.5 mt-2">
              <input v-model="goalDraft[`y${year}`]" type="text" placeholder="+ meta do ano (ex.: 80 kg com 12% de gordura · faturar X · lutar em maio)" class="flex-1 h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12" style="margin-bottom: 0" @keyup.enter="addGoal({ key: `y${year}`, list: yearData.goals })" />
              <button class="h-9 px-4 rounded-lg text-xs font-bold text-white" :style="{ background: GRAD_LARANJA }" @click="addGoal({ key: `y${year}`, list: yearData.goals })">Adicionar</button>
            </div>
          </div>
          <div class="hub-block p-5">
            <h2 class="hub-h2 mb-2"><span class="hub-h-ico i-lucide-calendar-days" />Linha do ano</h2>
            <div class="grid gap-1" style="grid-template-columns: repeat(12, minmax(0, 1fr))">
              <div v-for="key in monthKeys" :key="key" class="rounded-lg border p-1 min-h-[3.4rem]" :style="key === nowMonthKey ? { borderColor: LARANJA, background: 'rgba(255,138,0,0.08)' } : { borderColor: 'rgba(148,163,184,0.35)' }">
                <p class="text-[9px] font-bold text-center" :style="{ color: key === nowMonthKey ? LARANJA_VIVO : '#64748b' }">{{ MONTHS_PT[Number(key.slice(5, 7)) - 1] }}</p>
                <p v-if="monthOf(key).focus" class="text-[8px] text-center text-n-slate-11 truncate" :title="monthOf(key).focus">{{ monthOf(key).focus }}</p>
                <div v-for="p in programsInMonth(key)" :key="p.name" class="h-1.5 rounded-full mt-1" :style="{ background: p.custom ? LARANJA : ROYAL }" :title="p.name" />
              </div>
            </div>
            <div class="flex gap-3 mt-2 text-[10px] text-n-slate-10">
              <span><span class="inline-block w-3 h-1.5 rounded-full align-middle mr-1" :style="{ background: ROYAL }" />Warrior</span>
              <span><span class="inline-block w-3 h-1.5 rounded-full align-middle mr-1" :style="{ background: LARANJA }" />meu programa</span>
            </div>
          </div>
        </template>
      </template>
    </div>
  </div>
</template>

<style scoped>
/* rodada 27: no celular a lista vem primeiro e a linha do tempo embaixo (nada espremido) */
.hub-rt-day {
  display: grid;
  gap: 16px;
  grid-template-columns: minmax(0, 1fr);
}
.hub-rt-day > :first-child {
  order: 2;
}
@media (min-width: 640px) {
  .hub-rt-day {
    grid-template-columns: minmax(0, 1fr) minmax(0, 1.4fr);
  }
  .hub-rt-day > :first-child {
    order: 0;
  }
}
.hub-rt-seg {
  transition: transform 0.12s ease, box-shadow 0.12s ease;
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.35);
}
.hub-rt-seg:hover {
  transform: scale(1.01);
  box-shadow: 0 6px 16px rgba(17, 28, 63, 0.35);
  z-index: 2;
}
</style>
