<script setup>
// 🗂️ CONFIGURAÇÕES DA AGENDA (item 307, 01/10 — pedido dele: "deixar mais
// fácil e evidente abrir e fechar agendas… um ambiente em que podemos ajustar
// tudo o que pode mudar, sem eu precisar te pedir"). Um lugar só, em 4 partes:
//   1. Abrir e fechar  — médicos, dias e horários fechados
//   2. Faixas de horário — quando cada médico atende e PARA QUÊ serve cada
//      faixa (ex.: quarta 13h–14h = só pós-operatório)
//   3. Regras para a IA — texto da clínica que entra no prompt dos agentes +
//      a prova do que a IA está recebendo agora
//   4. Conferência do dia — o bloco que já existia (vem pelo slot)
// Sempre que uma mudança deixa paciente marcado fora da regra, a faixa
// "Precisa reagendar" lista cada um com o botão Reagendar.
import { ref, computed, watch, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import CrmAPI from 'dashboard/api/crm';
import {
  DOCTORS, TYPE_BY_KEY, RESERVABLE, AI_MODALITY,
  resolveAllWindows, resolveClosedDoctors, resolveBlocked, resolveBlockedDays,
  reservedFor, windowAccepts, windowAt, sameBlock, dateKey, patientNameOf, hexToRgbSpaced,
} from 'dashboard/helper/cevicoAgenda';

const props = defineProps({
  units: { type: Object, required: true }, // { tatuape: { label, color }, … }
  initialTab: { type: String, default: 'abrir' },
});
const emit = defineEmits(['close', 'reschedule', 'openExamWindows', 'openSurgeryWindows']);

const store = useStore();
const { isAdmin } = useAdmin();
const settings = useMapGetter('crm/getSettings');
const allTasks = useMapGetter('tasks/getTasks');

const TABS = [
  { key: 'abrir', label: 'Abrir e fechar', icon: 'i-lucide-lock-open' },
  { key: 'faixas', label: 'Faixas de horário', icon: 'i-lucide-clock' },
  { key: 'ia', label: 'Regras para a IA', icon: 'i-lucide-sparkles' },
  { key: 'conferencia', label: 'Conferência do dia', icon: 'i-lucide-list-checks' },
];
const tab = ref(props.initialTab);

const WEEKDAY_FULL = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];
const WEEKDAY_SHORT = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
const unitLabel = key => props.units[key]?.label || key;
const doctorColor = name => DOCTORS.find(d => d.name === name)?.color || '#64748B';
const doctorShort = name => DOCTORS.find(d => d.name === name)?.short || name;
const typeLabel = key => TYPE_BY_KEY[key]?.label || key;
const typeVars = key => {
  const t = TYPE_BY_KEY[key] || {};
  return {
    '--cv': t.color, '--cv-deep': t.deep, '--cv-grad': t.grad,
    '--cv-rgb': hexToRgbSpaced(t.color || '#64748B'), '--cv-deep-rgb': hexToRgbSpaced(t.deep || '#334155'),
  };
};
const reservedLabel = win => reservedFor(win).map(typeLabel).join(' + ');
const fmtDay = d =>
  d.toLocaleDateString('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit' }).replace('.', '');
const fmtHm = d => d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
const parseKey = key => new Date(`${key}T12:00:00`);
const todayKey = () => dateKey(new Date());

const refresh = () => store.dispatch('crm/fetchSettings');
const busy = ref('');

// ── 1. ABRIR E FECHAR ────────────────────────────────────────────────
const savedWindows = computed(() => resolveAllWindows(settings.value));
const closedDoctors = computed(() => resolveClosedDoctors(settings.value));
const isDoctorClosed = name => closedDoctors.value.includes(name);
const doctorSummary = name =>
  savedWindows.value
    .filter(w => w.doctor === name)
    .sort((a, b) => a.dow - b.dow || a.start.localeCompare(b.start))
    .map(w => `${WEEKDAY_SHORT[w.dow]} ${w.start}–${w.end} ${unitLabel(w.unit)}`)
    .join(' · ') || 'sem faixa de atendimento';

const toggleDoctor = async name => {
  const wasClosed = isDoctorClosed(name);
  busy.value = `doc:${name}`;
  try {
    const next = wasClosed ? closedDoctors.value.filter(x => x !== name) : [...closedDoctors.value, name];
    await CrmAPI.updateClosedDoctors(next);
    await refresh();
    useAlert(wasClosed ? `Agenda de ${name} reaberta!` : `Agenda de ${name} fechada — some da grade e a IA para de oferecer.`);
  } catch {
    useAlert('Não consegui atualizar a agenda do médico.');
  } finally {
    busy.value = '';
  }
};

// dias fechados (inteiro, uma unidade ou um médico) — de hoje em diante
const blockedDays = computed(() => resolveBlockedDays(settings.value));
const dayOf = b => (typeof b === 'string' ? b : b.date);
const closeScopeLabel = b => {
  if (typeof b === 'string') return 'Dia inteiro';
  return b.unit ? `Só ${unitLabel(b.unit)}` : `Só ${doctorShort(b.doctor)}`;
};
const futureClosings = computed(() =>
  blockedDays.value
    .filter(b => dayOf(b) >= todayKey())
    .sort((a, b) => dayOf(a).localeCompare(dayOf(b)))
);
const closeScopes = computed(() => [
  { key: 'all', label: 'Dia inteiro (clínica toda)' },
  ...Object.keys(props.units).map(u => ({ key: `u:${u}`, label: `Só ${unitLabel(u)}` })),
  ...DOCTORS.map(d => ({ key: `d:${d.name}`, label: `Só ${d.name}` })),
]);
const newClose = ref({ date: '', scope: 'all' });
const saveBlockedDays = async (next, message) => {
  busy.value = 'days';
  try {
    await CrmAPI.updateAgendaBlockedDays(next);
    await refresh();
    useAlert(message);
  } catch {
    useAlert('Não consegui salvar o fechamento.');
  } finally {
    busy.value = '';
  }
};
const addClosing = async () => {
  const { date, scope } = newClose.value;
  if (!date) return;
  let key = date;
  if (scope.startsWith('u:')) key = { date, unit: scope.slice(2) };
  if (scope.startsWith('d:')) key = { date, doctor: scope.slice(2) };
  if (blockedDays.value.some(b => sameBlock(b, key))) {
    useAlert('Esse fechamento já existe.');
    return;
  }
  await saveBlockedDays([...blockedDays.value, key], `${closeScopeLabel(key)} fechado em ${fmtDay(parseKey(date))} 🔒`);
  newClose.value = { date: '', scope: 'all' };
};
const reopenDay = b =>
  saveBlockedDays(blockedDays.value.filter(x => !sameBlock(x, b)), `${fmtDay(parseKey(dayOf(b)))} reaberto ✓`);

// horários fechados com o cadeado — de hoje em diante
const lockedSlots = computed(() =>
  resolveBlocked(settings.value)
    .filter(b => b.date >= todayKey())
    .sort((a, b) => `${a.date}${a.time}`.localeCompare(`${b.date}${b.time}`))
);
const reopenSlot = async slot => {
  busy.value = 'slots';
  try {
    const next = resolveBlocked(settings.value).filter(
      b => !(b.date === slot.date && b.time === slot.time && b.unit === slot.unit)
    );
    await CrmAPI.updateAgendaBlocked(next);
    await refresh();
    useAlert('Horário reaberto ✓');
  } catch {
    useAlert('Não consegui reabrir o horário.');
  } finally {
    busy.value = '';
  }
};

// ── PRECISA REAGENDAR: quem já está marcado e ficou fora da regra ─────
const conflicts = computed(() => {
  const now = new Date();
  const closed = closedDoctors.value;
  const openWins = savedWindows.value.filter(w => !closed.includes(w.doctor));
  const whole = new Set(blockedDays.value.filter(b => typeof b === 'string'));
  const parts = blockedDays.value.filter(b => b && typeof b === 'object');
  return (allTasks.value || [])
    .filter(
      t =>
        t.task_type === 'consulta' && t.due_at && !t.canceled_at && t.status !== 'done' &&
        !t.source && t.unit && props.units[t.unit] && !['exames', 'teleconsulta'].includes(t.modality) &&
        new Date(t.due_at) > now
    )
    .map(t => {
      const at = new Date(t.due_at);
      const key = dateKey(at);
      let reason = '';
      if (whole.has(key)) reason = 'o dia foi fechado';
      else if (parts.some(b => b.date === key && ((b.unit && b.unit === t.unit) || (b.doctor && b.doctor === t.doctor)))) {
        reason = 'a unidade ou o médico está fechado neste dia';
      } else if (t.doctor && closed.includes(t.doctor)) reason = `a agenda de ${doctorShort(t.doctor)} está fechada`;
      else {
        const spot = { dow: at.getDay(), unit: t.unit, minutes: at.getHours() * 60 + at.getMinutes() };
        const win = windowAt(openWins, { ...spot, doctor: t.doctor }) || windowAt(openWins, spot);
        if (win && !windowAccepts(win, t.modality || AI_MODALITY)) reason = `faixa reservada para ${reservedLabel(win)}`;
      }
      return reason ? { task: t, at, reason } : null;
    })
    .filter(Boolean)
    .sort((a, b) => a.at - b.at);
});
const showConflicts = ref(true);

// ── 2. FAIXAS DE HORÁRIO ─────────────────────────────────────────────
let uid = 0;
const nextUid = () => {
  uid += 1;
  return uid;
};
const cloneWindows = list => list.map(w => ({ ...w, only: [...reservedFor(w)], uid: nextUid() }));
const cleanWindows = list =>
  list
    .filter(w => w.start && w.end && w.doctor)
    .map(w => {
      const only = reservedFor(w);
      const base = {
        dow: Number(w.dow), unit: w.unit, doctor: w.doctor,
        turno: w.start < '12:00' ? 'Manhã' : 'Tarde',
        start: w.start, end: w.end, block: Number(w.block) || 15,
      };
      // os 3 tipos marcados = aceita tudo = sem reserva
      return only.length && only.length < RESERVABLE.length ? { ...base, only } : base;
    });
const draft = ref(cloneWindows(savedWindows.value));
const isDirty = computed(
  () => JSON.stringify(cleanWindows(draft.value)) !== JSON.stringify(cleanWindows(savedWindows.value))
);
watch(savedWindows, list => {
  if (!isDirty.value) draft.value = cloneWindows(list);
});
const resetDraft = () => {
  draft.value = cloneWindows(savedWindows.value);
};
const byDow = dow =>
  draft.value.filter(w => Number(w.dow) === dow).sort((a, b) => a.start.localeCompare(b.start));
const addWindow = dow => {
  draft.value.push({ dow, unit: 'paulista', doctor: DOCTORS[0].name, start: '08:00', end: '11:00', block: 15, only: [], uid: nextUid() });
};
const removeWindow = w => {
  draft.value = draft.value.filter(x => x.uid !== w.uid);
};
const toggleOnly = (w, key) => {
  w.only = w.only.includes(key) ? w.only.filter(k => k !== key) : [...w.only, key];
};
const acceptsAll = w => !reservedFor(w).length || reservedFor(w).length === RESERVABLE.length;
const aiOffers = w => acceptsAll(w) || windowAccepts(w, AI_MODALITY);
// dividir uma faixa em duas num horário (13h–17h → 13h–14h + 14h–17h)
const splitting = ref(null);
const splitTime = ref('');
const startSplit = w => {
  splitting.value = w.uid;
  splitTime.value = '';
};
const confirmSplit = w => {
  const at = splitTime.value;
  if (!at || at <= w.start || at >= w.end) {
    useAlert(`Escolha um horário entre ${w.start} e ${w.end}.`);
    return;
  }
  draft.value.push({ ...w, start: at, only: [], uid: nextUid() });
  w.end = at;
  splitting.value = null;
};
const rowError = w => {
  if (!w.start || !w.end) return 'informe início e fim';
  if (w.start >= w.end) return 'o fim precisa ser depois do início';
  const clash = draft.value.find(
    x => x.uid !== w.uid && Number(x.dow) === Number(w.dow) && x.doctor === w.doctor && x.start < w.end && x.end > w.start
  );
  return clash ? `sobrepõe a faixa ${clash.start}–${clash.end} do mesmo médico` : '';
};
const hasErrors = computed(() => draft.value.some(w => rowError(w)));

// ── 3. REGRAS PARA A IA ──────────────────────────────────────────────
const aiRules = ref(settings.value?.agenda_ai_rules || '');
const rulesDirty = computed(() => aiRules.value.trim() !== (settings.value?.agenda_ai_rules || '').trim());
const preview = ref(null);
const previewError = ref('');
const loadPreview = async () => {
  previewError.value = '';
  try {
    const { data } = await CrmAPI.getAgendaAiPreview();
    preview.value = data;
  } catch {
    previewError.value = 'Só quem tem acesso às configurações vê o que a IA recebe.';
  }
};
const saveRules = async () => {
  busy.value = 'rules';
  try {
    await CrmAPI.updateAgendaAiRules(aiRules.value);
    await refresh();
    await loadPreview();
    useAlert('Regras salvas — a IA já responde com elas na próxima mensagem.');
  } catch {
    useAlert('Não consegui salvar as regras.');
  } finally {
    busy.value = '';
  }
};

const saveWindows = async () => {
  if (hasErrors.value) {
    useAlert('Há faixa com horário inválido — confira os avisos em vermelho.');
    return;
  }
  busy.value = 'windows';
  try {
    await CrmAPI.updateAgendaWindows(cleanWindows(draft.value));
    await refresh();
    draft.value = cloneWindows(savedWindows.value);
    loadPreview();
    useAlert('Faixas de horário salvas!');
  } catch {
    useAlert('Erro ao salvar as faixas.');
  } finally {
    busy.value = '';
  }
};

const tryClose = () => {
  // eslint-disable-next-line no-alert
  if ((isDirty.value || rulesDirty.value) && !window.confirm('Há mudanças sem salvar. Fechar mesmo assim?')) return;
  emit('close');
};

onMounted(loadPreview);
</script>

<template>
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/55 p-3 sm:p-4" @click.self="tryClose">
    <div class="cv-modal cv-ag-pop w-full max-w-3xl max-h-[92vh] flex flex-col">
      <div class="cv-modal-head flex items-center gap-3">
        <span class="i-lucide-settings-2 text-xl" />
        <div class="flex-1 min-w-0">
          <h2 class="text-base font-bold">Configurações da agenda</h2>
          <p class="text-[11px] opacity-85">abrir e fechar, para que serve cada faixa de horário e o que a IA oferece — tudo num lugar só</p>
        </div>
        <button class="cv-glass-btn cv-iconbtn" title="Fechar" @click="tryClose"><span class="i-lucide-x" /></button>
      </div>

      <div class="px-4 sm:px-5 pt-4">
        <div class="cv-seg cv-seg-sm grid grid-cols-2 sm:grid-cols-4 gap-1 w-full">
          <button v-for="t in TABS" :key="t.key" class="cv-seg-item justify-center" :class="tab === t.key ? 'cv-seg-on' : ''" @click="tab = t.key">
            <span :class="t.icon" class="text-xs" /> {{ t.label }}
          </button>
        </div>
      </div>

      <div class="flex-1 overflow-y-auto p-4 sm:p-5 space-y-4">
        <!-- PRECISA REAGENDAR: aparece em qualquer aba enquanto houver paciente fora da regra -->
        <div v-if="conflicts.length" class="cv-sub cv-amber p-3.5">
          <button class="w-full flex items-center gap-2 text-left" @click="showConflicts = !showConflicts">
            <span class="i-lucide-calendar-clock text-base" style="color: #b45309" />
            <span class="text-sm font-bold text-n-slate-12 flex-1">Precisa reagendar · {{ conflicts.length }}</span>
            <span class="text-[11px] text-n-slate-10">paciente já marcado que ficou fora da regra</span>
            <span :class="showConflicts ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'" class="text-sm text-n-slate-10" />
          </button>
          <div v-if="showConflicts" class="mt-2.5 space-y-1.5">
            <div v-for="c in conflicts" :key="c.task.id" class="cv-row flex items-center gap-2 flex-wrap px-3 py-2">
              <span class="text-xs font-semibold text-n-slate-12 tabular-nums">{{ fmtDay(c.at) }} · {{ fmtHm(c.at) }}</span>
              <span class="text-xs text-n-slate-12 truncate flex-1 min-w-[120px]">{{ patientNameOf(c.task) }}</span>
              <span class="cv-chip" :style="typeVars(c.task.modality || 'avaliacao')">{{ typeLabel(c.task.modality || 'avaliacao') }}</span>
              <span class="text-[11px] text-n-slate-10 w-full sm:w-auto">{{ c.reason }}</span>
              <button class="cv-btn cv-btn-sm" @click="emit('reschedule', c.task)"><span class="i-lucide-calendar-clock text-xs" /> Reagendar</button>
            </div>
          </div>
        </div>

        <!-- 1. ABRIR E FECHAR -->
        <template v-if="tab === 'abrir'">
          <section class="space-y-2">
            <p class="cv-ag-block-title">Médicos</p>
            <p class="text-[11px] text-n-slate-10">Fechar tira o médico da grade inteira na hora, e a IA para de oferecer os horários dele. Reabrir devolve tudo como estava.</p>
            <div v-for="d in DOCTORS" :key="d.name" class="cv-sub flex items-center gap-3 flex-wrap px-3.5 py-3">
              <span class="w-3 h-3 rounded-full flex-shrink-0" :style="{ backgroundColor: d.color }" />
              <div class="flex-1 min-w-[180px]">
                <p class="text-sm font-semibold text-n-slate-12 flex items-center gap-2 flex-wrap">
                  {{ d.name }}
                  <span class="cv-chip" :class="isDoctorClosed(d.name) ? 'cv-red' : 'cv-green'">{{ isDoctorClosed(d.name) ? 'agenda fechada' : 'agenda aberta' }}</span>
                </p>
                <p class="text-[11px] text-n-slate-10 mt-0.5">{{ doctorSummary(d.name) }}</p>
              </div>
              <button v-if="isAdmin" class="cv-btn" :class="isDoctorClosed(d.name) ? '' : 'cv-btn-ghost cv-btn-danger'" :disabled="busy === `doc:${d.name}`" @click="toggleDoctor(d.name)">
                <span :class="isDoctorClosed(d.name) ? 'i-lucide-lock-open' : 'i-lucide-lock'" class="text-sm" />
                {{ isDoctorClosed(d.name) ? 'Reabrir agenda' : 'Fechar agenda' }}
              </button>
            </div>
          </section>

          <section class="space-y-2">
            <p class="cv-ag-block-title">Dias fechados</p>
            <p class="text-[11px] text-n-slate-10">Feriado, congresso, folga: o dia some da grade e a IA não oferece. Pode ser a clínica toda, só uma unidade ou só um médico.</p>
            <div class="cv-sub flex items-end gap-2 flex-wrap p-3">
              <label class="flex-1 min-w-[130px]">
                <span class="cv-label block mb-0.5">Dia</span>
                <input v-model="newClose.date" type="date" :min="todayKey()" class="cv-input w-full !h-9 text-xs" />
              </label>
              <label class="flex-1 min-w-[170px]">
                <span class="cv-label block mb-0.5">O que fecha</span>
                <select v-model="newClose.scope" class="cv-input w-full !h-9 text-xs">
                  <option v-for="s in closeScopes" :key="s.key" :value="s.key">{{ s.label }}</option>
                </select>
              </label>
              <button class="cv-btn" :disabled="!newClose.date || busy === 'days'" @click="addClosing"><span class="i-lucide-lock text-sm" /> Fechar</button>
            </div>
            <div v-for="(b, i) in futureClosings" :key="i" class="cv-row flex items-center gap-2 flex-wrap px-3 py-2">
              <span class="i-lucide-calendar-off text-sm text-n-slate-10" />
              <span class="text-xs font-semibold text-n-slate-12">{{ fmtDay(parseKey(dayOf(b))) }}</span>
              <span class="cv-chip cv-red">{{ closeScopeLabel(b) }}</span>
              <button class="cv-btn cv-btn-ghost cv-btn-sm ml-auto" :disabled="busy === 'days'" @click="reopenDay(b)"><span class="i-lucide-lock-open text-xs" /> Reabrir</button>
            </div>
            <p v-if="!futureClosings.length" class="text-xs text-n-slate-9 pl-1">Nenhum dia fechado daqui para frente.</p>
          </section>

          <section class="space-y-2">
            <p class="cv-ag-block-title">Horários com cadeado</p>
            <p class="text-[11px] text-n-slate-10">Um horário só (almoço, atraso do médico). Para fechar, use o cadeado no canto do horário, na visão Dia.</p>
            <div v-for="(s, i) in lockedSlots" :key="i" class="cv-row flex items-center gap-2 flex-wrap px-3 py-2">
              <span class="i-lucide-lock text-sm text-n-slate-10" />
              <span class="text-xs font-semibold text-n-slate-12 tabular-nums">{{ fmtDay(parseKey(s.date)) }} · {{ s.time }}</span>
              <span class="cv-chip cv-slate">{{ unitLabel(s.unit) }}</span>
              <span v-if="s.doctor" class="text-[11px] text-n-slate-10">{{ doctorShort(s.doctor) }}</span>
              <button v-if="isAdmin" class="cv-btn cv-btn-ghost cv-btn-sm ml-auto" :disabled="busy === 'slots'" @click="reopenSlot(s)"><span class="i-lucide-lock-open text-xs" /> Reabrir</button>
            </div>
            <p v-if="!lockedSlots.length" class="text-xs text-n-slate-9 pl-1">Nenhum horário fechado daqui para frente.</p>
          </section>
        </template>

        <!-- 2. FAIXAS DE HORÁRIO -->
        <template v-else-if="tab === 'faixas'">
          <p class="text-[11px] text-n-slate-10 leading-relaxed">
            Cada faixa diz quando o médico atende e <b>para que ela serve</b>. Faixa "Tudo" aceita qualquer atendimento.
            Faixa reservada (ex.: só Pós-operatório) fica marcada na grade, a equipe é avisada ao marcar outro tipo ali e
            <b>a IA só oferece consulta nova nas faixas que aceitam Avaliação</b>.
          </p>
          <section v-for="dow in [1, 2, 3, 4, 5]" :key="dow" class="space-y-1.5">
            <div class="flex items-center gap-2">
              <p class="cv-ag-block-title flex-1">{{ WEEKDAY_FULL[dow] }}</p>
              <button v-if="isAdmin" class="cv-btn cv-btn-ghost cv-btn-sm" @click="addWindow(dow)"><span class="i-lucide-plus text-xs" /> Faixa</button>
            </div>
            <div v-for="w in byDow(dow)" :key="w.uid" class="cv-sub p-3 space-y-2" :style="{ '--cv-rgb': hexToRgbSpaced(doctorColor(w.doctor)) }">
              <div class="flex items-center gap-2 flex-wrap">
                <span class="w-2.5 h-2.5 rounded-full flex-shrink-0" :style="{ backgroundColor: doctorColor(w.doctor) }" />
                <template v-if="isAdmin">
                  <select v-model="w.doctor" class="cv-input !h-8 text-xs !w-auto">
                    <option v-for="d in DOCTORS" :key="d.name" :value="d.name">{{ d.name }}</option>
                  </select>
                  <select v-model="w.unit" class="cv-input !h-8 text-xs !w-auto">
                    <option v-for="(u, key) in units" :key="key" :value="key">{{ u.label }}</option>
                  </select>
                  <span class="text-xs text-n-slate-10">das</span>
                  <input v-model="w.start" type="time" class="cv-input !h-8 text-xs !w-auto" />
                  <span class="text-xs text-n-slate-10">às</span>
                  <input v-model="w.end" type="time" class="cv-input !h-8 text-xs !w-auto" />
                  <select v-model.number="w.block" class="cv-input !h-8 text-xs !w-auto" title="De quanto em quanto tempo entra um paciente">
                    <option v-for="b in [5, 10, 15, 20, 30]" :key="b" :value="b">a cada {{ b }} min</option>
                  </select>
                  <button class="cv-btn cv-btn-ghost cv-btn-sm ml-auto" title="Dividir esta faixa em duas num horário" @click="startSplit(w)"><span class="i-lucide-scissors text-xs" /> Dividir</button>
                  <button class="text-n-slate-9 hover:text-red-500 i-lucide-trash-2 text-sm" title="Remover faixa" @click="removeWindow(w)" />
                </template>
                <template v-else>
                  <span class="text-sm font-medium text-n-slate-12">{{ w.doctor }}</span>
                  <span class="cv-chip cv-slate">{{ unitLabel(w.unit) }}</span>
                  <span class="text-xs text-n-slate-10 ml-auto">{{ w.start }}–{{ w.end }} · a cada {{ w.block }} min</span>
                </template>
              </div>
              <div v-if="splitting === w.uid" class="cv-row flex items-center gap-2 flex-wrap px-3 py-2">
                <span class="text-xs text-n-slate-11">Dividir às</span>
                <input v-model="splitTime" type="time" :min="w.start" :max="w.end" class="cv-input !h-8 text-xs !w-auto" />
                <span class="text-[11px] text-n-slate-10">vira {{ w.start }}–{{ splitTime || '…' }} e {{ splitTime || '…' }}–{{ w.end }}</span>
                <button class="cv-btn cv-btn-sm ml-auto" @click="confirmSplit(w)">Dividir</button>
                <button class="cv-btn cv-btn-ghost cv-btn-sm" @click="splitting = null">Cancelar</button>
              </div>
              <div class="flex items-center gap-1.5 flex-wrap">
                <span class="cv-label">Serve para</span>
                <button class="cv-chip cv-chip-lg" :class="acceptsAll(w) ? 'cv-chip-on' : ''" :disabled="!isAdmin" @click="w.only = []">Tudo</button>
                <button
                  v-for="key in RESERVABLE"
                  :key="key"
                  class="cv-chip cv-chip-lg"
                  :class="!acceptsAll(w) && w.only.includes(key) ? 'cv-chip-on' : ''"
                  :style="typeVars(key)"
                  :disabled="!isAdmin"
                  @click="toggleOnly(w, key)"
                >
                  só {{ typeLabel(key) }}
                </button>
                <span class="text-[11px] ml-auto flex items-center gap-1" :style="{ color: aiOffers(w) ? '#047857' : '#b45309' }">
                  <span :class="aiOffers(w) ? 'i-lucide-sparkles' : 'i-lucide-ban'" class="text-xs" />
                  {{ aiOffers(w) ? 'a IA oferece consulta nova aqui' : 'a IA não oferece — só a equipe marca' }}
                </span>
              </div>
              <p v-if="rowError(w)" class="text-[11px] font-semibold" style="color: #dc2626">⚠ {{ rowError(w) }}</p>
            </div>
            <p v-if="!byDow(dow).length" class="text-xs text-n-slate-9 pl-1">— sem atendimento</p>
          </section>
          <div class="cv-sub flex items-center gap-2 px-3 py-2 text-xs text-n-slate-10">
            <span class="i-lucide-lock text-sm" /> Sábado e domingo: sem agenda em nenhuma unidade.
          </div>
          <div class="cv-sub flex items-center gap-2 flex-wrap px-3 py-2.5">
            <span class="text-xs text-n-slate-11 flex-1 min-w-[160px]">Exames e sala cirúrgica têm faixas próprias:</span>
            <button class="cv-btn cv-btn-ghost cv-btn-sm" @click="emit('openExamWindows')"><span class="i-lucide-scan-eye text-xs" /> Janela de exames</button>
            <button class="cv-btn cv-btn-ghost cv-btn-sm" @click="emit('openSurgeryWindows')"><span class="i-lucide-slice text-xs" /> Sala cirúrgica</button>
          </div>
        </template>

        <!-- 3. REGRAS PARA A IA -->
        <template v-else-if="tab === 'ia'">
          <section class="space-y-2">
            <p class="cv-ag-block-title">O que a IA segue sozinha</p>
            <p class="text-[11px] text-n-slate-10 leading-relaxed">
              Os horários que ela oferece saem direto desta agenda: só faixa aberta, que aceita consulta nova, sem paciente marcado
              e sem cadeado. Fechou um médico, um dia ou reservou uma faixa — ela para de oferecer na mensagem seguinte, sem mexer no roteiro.
            </p>
          </section>
          <section class="space-y-2">
            <p class="cv-ag-block-title">Regras da clínica</p>
            <p class="text-[11px] text-n-slate-10">Escreva aqui o que a IA precisa saber sobre a agenda e que não cabe nas faixas. Este texto entra num bloco próprio do roteiro dos atendentes, só sobre agenda.</p>
            <textarea
              v-model="aiRules"
              rows="5"
              maxlength="2000"
              :disabled="!isAdmin"
              class="cv-input w-full text-xs !h-auto py-2 leading-relaxed"
              placeholder="Ex.: Retorno de pós-operatório é sempre às quartas, das 13h às 14h, com o Dr. Henrique — quem marca é a equipe. Não ofereça encaixe para o mesmo dia."
            />
            <div class="flex items-center gap-2">
              <span class="text-[10px] text-n-slate-9 flex-1">{{ aiRules.length }}/2000</span>
              <button v-if="isAdmin" class="cv-btn" :disabled="!rulesDirty || busy === 'rules'" @click="saveRules">{{ busy === 'rules' ? 'Salvando…' : 'Salvar regras' }}</button>
            </div>
          </section>
          <section class="space-y-2">
            <div class="flex items-center gap-2">
              <p class="cv-ag-block-title flex-1">O que a IA recebe agora</p>
              <button class="cv-btn cv-btn-ghost cv-btn-sm" @click="loadPreview"><span class="i-lucide-refresh-cw text-xs" /> Atualizar</button>
            </div>
            <p v-if="previewError" class="text-xs text-n-slate-9">{{ previewError }}</p>
            <template v-else-if="preview">
              <div class="cv-sub p-3">
                <p class="cv-label mb-1">Regras da agenda</p>
                <pre class="text-[11px] text-n-slate-12 whitespace-pre-wrap font-sans leading-relaxed">{{ preview.rules || 'Nenhuma regra — a IA segue só os horários livres abaixo.' }}</pre>
              </div>
              <div class="cv-sub p-3">
                <p class="cv-label mb-1">Horários que ela pode oferecer (próximas 2 semanas, até 3 por faixa)</p>
                <pre class="text-[11px] text-n-slate-12 whitespace-pre-wrap font-sans leading-relaxed">{{ preview.slots }}</pre>
              </div>
            </template>
            <p v-else class="text-xs text-n-slate-9">Carregando…</p>
          </section>
        </template>

        <!-- 4. CONFERÊNCIA DO DIA (bloco que já existia) -->
        <template v-else>
          <slot name="conferencia" />
        </template>
      </div>

      <!-- barra de salvar das faixas -->
      <div v-if="tab === 'faixas' && isAdmin" class="px-4 sm:px-5 py-3 border-t border-n-weak flex items-center gap-2">
        <span class="text-[11px] flex-1" :class="isDirty ? 'text-n-slate-12 font-semibold' : 'text-n-slate-9'">{{ isDirty ? 'Mudanças ainda não salvas' : 'Tudo salvo' }}</span>
        <button class="cv-btn cv-btn-ghost" :disabled="!isDirty" @click="resetDraft">Desfazer</button>
        <button class="cv-btn" :disabled="!isDirty || busy === 'windows'" @click="saveWindows">{{ busy === 'windows' ? 'Salvando…' : 'Salvar faixas' }}</button>
      </div>
    </div>
  </div>
</template>
