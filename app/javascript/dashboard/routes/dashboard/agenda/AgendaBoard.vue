<script setup>
// Agenda de CONSULTAS da clínica — visões Mês / Semana / Dia.
// Cada agendamento guarda: nome, telefone, problema (catarata, refrativa,
// exames...), dia, horário, médico e unidade. Criado à mão ou pelo Agente
// de Agendamento (IA) via ação de coluna do CRM.
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import {
  startOfMonth, endOfMonth, startOfWeek, endOfWeek,
  addDays, addWeeks, addMonths, isSameDay, isSameMonth, format,
} from 'date-fns';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';
import {
  DOCTORS, resolveWindows, resolveBlocked, resolveBlockedDays,
  slotsFor as sharedSlotsFor, dateKey, blockKey, scanAgenda,
} from 'dashboard/helper/cevicoAgenda';

const store = useStore();
const { isAdmin } = useAdmin();

const agents = useMapGetter('agents/getAgents');
const currentUser = useMapGetter('getCurrentUser');
const allTasks = useMapGetter('tasks/getTasks');

const isLoading = ref(true);
const cursor = ref(new Date()); // data de referência da navegação
const viewMode = ref('month'); // 'month' | 'week' | 'day'
// filtro: 'clinic' (todas) | 'unit:x' | 'doctor:Nome' | 'me' | '<agentId>'
const view = ref('clinic');

const WEEKDAYS = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
const VIEW_MODES = [
  { key: 'month', label: 'Mês', icon: 'i-lucide-calendar' },
  { key: 'week', label: 'Semana', icon: 'i-lucide-calendar-range' },
  { key: 'day', label: 'Dia', icon: 'i-lucide-calendar-check' },
];

// Unidades da clínica (agendas paralelas compartilhadas)
const UNITS = {
  tatuape:  { label: 'Tatuapé',      color: '#2563EB' },
  paulista: { label: 'Av. Paulista', color: '#EA580C' },
};

const PROBLEMAS = [
  'Catarata', 'Refrativa', 'Ceratocone', 'Lentes Fácicas',
  'Exames', 'Consulta geral', 'Pós-operatório', 'Plástica ocular',
];

const HOURS = Array.from({ length: 14 }, (_, i) => i + 7); // 07h às 20h

// ── Médicos e janelas de avaliação da clínica ───────────────
// (DOCTORS/DEFAULT_WINDOWS/slotsFor vivem em helper/cevicoAgenda.js,
// compartilhados com os indicadores do Meu Painel)
const doctorColor = name =>
  DOCTORS.find(d => d.name === name)?.color || '#64748B';

const WEEKDAY_FULL = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];

const crmSettings = useMapGetter('crm/getSettings');
const windows = computed(() => resolveWindows(crmSettings.value));

// horários fechados com o cadeado ({date, time, unit})
const blockedList = computed(() => resolveBlocked(crmSettings.value));
const blockedSet = computed(
  () => new Set(blockedList.value.map(b => blockKey(b.date, b.time, b.unit)))
);
const isBlocked = (day, win, slot) =>
  blockedSet.value.has(blockKey(dateKey(day), slot, win.unit));

const isSavingBlock = ref(false);
const toggleBlock = async (day, win, slot) => {
  if (isSavingBlock.value) return;
  isSavingBlock.value = true;
  try {
    const key = { date: dateKey(day), time: slot, unit: win.unit };
    const exists = blockedList.value.some(
      b => b.date === key.date && b.time === key.time && b.unit === key.unit
    );
    const next = exists
      ? blockedList.value.filter(b => !(b.date === key.date && b.time === key.time && b.unit === key.unit))
      : [...blockedList.value, { ...key, doctor: win.doctor }];
    await CrmAPI.updateAgendaBlocked(next);
    await store.dispatch('crm/fetchSettings');
    useAlert(exists ? 'Horário reaberto' : 'Horário fechado 🔒');
  } catch {
    useAlert('Erro ao atualizar o horário.');
  } finally {
    isSavingBlock.value = false;
  }
};

const isWeekend = day => day.getDay() === 0 || day.getDay() === 6;

// dias inteiros fechados (feriado, congresso...)
const blockedDays = computed(() => new Set(resolveBlockedDays(crmSettings.value)));
const isDayBlocked = day => blockedDays.value.has(dateKey(day));
const isDayOff = day => isWeekend(day) || isDayBlocked(day);

const toggleBlockDay = async day => {
  if (isSavingBlock.value) return;
  isSavingBlock.value = true;
  try {
    const key = dateKey(day);
    const list = resolveBlockedDays(crmSettings.value);
    const next = list.includes(key) ? list.filter(d => d !== key) : [...list, key];
    await CrmAPI.updateAgendaBlockedDays(next);
    await store.dispatch('crm/fetchSettings');
    useAlert(list.includes(key) ? 'Dia reaberto' : 'Dia fechado 🔒');
  } catch {
    useAlert('Erro ao atualizar o dia.');
  } finally {
    isSavingBlock.value = false;
  }
};

const slotsFor = sharedSlotsFor;

// janelas de um dia (respeitando o filtro de unidade/médico ativo)
const windowsForDay = day =>
  windows.value
    .filter(w => w.dow === day.getDay())
    .filter(w => !activeUnit.value || w.unit === activeUnit.value)
    .filter(w => !activeDoctor.value || w.doctor === activeDoctor.value);

// consulta ocupando um bloco: mesmo dia, mesma hora:minuto e mesma unidade
const taskAtSlot = (day, win, slot) =>
  dayTasks(day).find(t => {
    const d = new Date(t.due_at);
    const hm = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
    return hm === slot && (!t.unit || t.unit === win.unit);
  });

const showWindowsModal = ref(false);
const windowsByDow = computed(() => {
  const map = {};
  windows.value.forEach(w => { (map[w.dow] ||= []).push(w); });
  return map;
});

// ── Edição das janelas (admin) ──────────────────────────────
const isEditingWindows = ref(false);
const editWindows = ref([]);
const isSavingWindows = ref(false);

const startEditWindows = () => {
  editWindows.value = windows.value.map(w => ({ ...w }));
  isEditingWindows.value = true;
};

const addWindow = () => {
  editWindows.value.push({
    dow: 1, unit: 'paulista', doctor: DOCTORS[0].name,
    turno: 'Manhã', start: '08:00', end: '11:00', block: 15,
  });
};

const removeWindow = i => editWindows.value.splice(i, 1);

const saveWindows = async () => {
  isSavingWindows.value = true;
  try {
    const clean = editWindows.value
      .filter(w => w.start && w.end && w.doctor)
      .map(w => ({ ...w, dow: Number(w.dow), block: Number(w.block) }));
    await CrmAPI.updateAgendaWindows(clean);
    await store.dispatch('crm/fetchSettings');
    isEditingWindows.value = false;
    useAlert('Janelas dos médicos salvas!');
  } catch {
    useAlert('Erro ao salvar as janelas.');
  } finally {
    isSavingWindows.value = false;
  }
};

// ── Filtro de consultas ─────────────────────────────────────
const activeUnit = computed(() =>
  view.value.startsWith('unit:') ? view.value.slice(5) : null
);
// agenda de UM médico: só as janelas e consultas dele
const activeDoctor = computed(() =>
  view.value.startsWith('doctor:') ? view.value.slice(7) : null
);

const isAppointment = t => t.task_type === 'consulta' || t.unit;

const visibleTasks = computed(() => {
  // canceladas ficam fora do calendário (continuam no banco p/ indicadores)
  const list = allTasks.value.filter(x => x.due_at && !x.canceled_at);
  if (view.value === 'clinic') return list.filter(isAppointment);
  if (activeUnit.value) return list.filter(x => x.unit === activeUnit.value);
  if (activeDoctor.value)
    return list.filter(x => isAppointment(x) && x.doctor === activeDoctor.value);
  if (view.value === 'me')
    return list.filter(x => !x.unit && x.assignee?.id === currentUser.value.id);
  return list.filter(x => !x.unit && x.assignee?.id === Number(view.value));
});

const tasksByDay = computed(() => {
  const map = {};
  visibleTasks.value.forEach(task => {
    const key = format(new Date(task.due_at), 'yyyy-MM-dd');
    (map[key] ||= []).push(task);
  });
  Object.values(map).forEach(arr =>
    arr.sort((a, b) => new Date(a.due_at) - new Date(b.due_at))
  );
  return map;
});

const dayTasks = day => tasksByDay.value[format(day, 'yyyy-MM-dd')] || [];
const isToday = day => isSameDay(day, new Date());
const inMonth = day => isSameMonth(day, cursor.value);

// ── Navegação (muda conforme a visão) ───────────────────────
const step = dir => {
  if (viewMode.value === 'month') cursor.value = addMonths(cursor.value, dir);
  else if (viewMode.value === 'week') cursor.value = addWeeks(cursor.value, dir);
  else cursor.value = addDays(cursor.value, dir);
};
const goToday = () => { cursor.value = new Date(); };

const capitalize = s => s.charAt(0).toUpperCase() + s.slice(1);

const navLabel = computed(() => {
  if (viewMode.value === 'month') {
    return capitalize(cursor.value.toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' }));
  }
  if (viewMode.value === 'week') {
    const start = startOfWeek(cursor.value, { weekStartsOn: 0 });
    const end = endOfWeek(cursor.value, { weekStartsOn: 0 });
    return `${start.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })} — ${end.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })}`;
  }
  return capitalize(cursor.value.toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' }));
});

// grade mensal (6 semanas, domingo primeiro)
const weeks = computed(() => {
  const start = startOfWeek(startOfMonth(cursor.value), { weekStartsOn: 0 });
  const end = endOfWeek(endOfMonth(cursor.value), { weekStartsOn: 0 });
  const days = [];
  let d = start;
  while (d <= end) {
    days.push(d);
    d = addDays(d, 1);
  }
  const result = [];
  for (let i = 0; i < days.length; i += 7) result.push(days.slice(i, i + 7));
  return result;
});

// dias da semana da visão semanal
const weekDays = computed(() => {
  const start = startOfWeek(cursor.value, { weekStartsOn: 0 });
  return Array.from({ length: 7 }, (_, i) => addDays(start, i));
});

// visão diária: consultas agrupadas por hora
const dayViewTasks = computed(() => dayTasks(cursor.value));
const tasksAtHour = hour =>
  dayViewTasks.value.filter(t => new Date(t.due_at).getHours() === hour);
const tasksOutsideHours = computed(() =>
  dayViewTasks.value.filter(t => {
    const h = new Date(t.due_at).getHours();
    return h < HOURS[0] || h > HOURS[HOURS.length - 1];
  })
);

// ── Helpers de exibição ─────────────────────────────────────
const displayName = task => (task.title || '').replace(/^Consulta:\s*/i, '');
const chipTime = task =>
  new Date(task.due_at).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
const unitOf = task => (task.unit && UNITS[task.unit] ? UNITS[task.unit] : null);
const dotColor = task => unitOf(task)?.color || '#94A3B8';
const isOverdue = task => task.status !== 'done' && new Date(task.due_at) < new Date();

// ── Ocupação da agenda (% preenchida — dia/semana/mês) ──────
// Segue a navegação do calendário e o filtro ativo (unidade/médico).
// Fórmula: blocos ocupados ÷ blocos das janelas (cadeados fora da conta).
const occWindows = computed(() =>
  windows.value
    .filter(w => !activeUnit.value || w.unit === activeUnit.value)
    .filter(w => !activeDoctor.value || w.doctor === activeDoctor.value)
);
const occScan = (from, days) =>
  scanAgenda({
    windows: occWindows.value,
    tasks: visibleTasks.value.filter(isAppointment),
    blockedSet: blockedSet.value,
    blockedDays: blockedDays.value,
    from,
    days,
    freeLimit: 0,
  });

// só faz sentido contra as janelas da clínica (não na agenda pessoal)
const showOccupancy = computed(
  () => view.value === 'clinic' || !!activeUnit.value || !!activeDoctor.value
);
const occDay = computed(() => occScan(cursor.value, 1));
const occWeek = computed(() => occScan(startOfWeek(cursor.value, { weekStartsOn: 0 }), 7));
const occMonth = computed(() =>
  occScan(startOfMonth(cursor.value), endOfMonth(cursor.value).getDate())
);

const occDayLabel = computed(() =>
  cursor.value.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })
);
const occWeekLabel = computed(() => {
  const s = startOfWeek(cursor.value, { weekStartsOn: 0 });
  const e = endOfWeek(cursor.value, { weekStartsOn: 0 });
  const fmt = d => d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
  return `${fmt(s)}–${fmt(e)}`;
});
const occMonthLabel = computed(() =>
  capitalize(cursor.value.toLocaleDateString('pt-BR', { month: 'long' }))
);

// verde = com vagas · dourado = enchendo · vermelho = quase cheia
const occColor = pct => {
  if (pct >= 80) return '#EF4444';
  if (pct >= 50) return '#D4A017';
  return '#22C55E';
};

// % de um dia específico (chip nas visões Mês/Semana)
const dayOccupancy = day => {
  if (isDayOff(day)) return null;
  if (!occWindows.value.some(w => w.dow === day.getDay())) return null;
  return occScan(day, 1);
};

// ocupação de UMA janela de médico (visão Dia)
const winOccupancy = (day, win) => {
  const slots = slotsFor(win).filter(s => !isBlocked(day, win, s));
  const filled = slots.filter(s => taskAtSlot(day, win, s)).length;
  const total = slots.length;
  return { filled, total, pct: total ? Math.round((filled / total) * 100) : 0 };
};

// ── KPIs no estilo do Dashboard CRM ────────────────────────
const clinicTasks = computed(() =>
  allTasks.value.filter(x => isAppointment(x) && x.due_at && x.status !== 'done')
);
const kpiToday = computed(() =>
  clinicTasks.value.filter(x => isSameDay(new Date(x.due_at), new Date())).length
);
const kpiWeek = computed(() => {
  const start = startOfWeek(new Date(), { weekStartsOn: 0 });
  const end = endOfWeek(new Date(), { weekStartsOn: 0 });
  return clinicTasks.value.filter(x => {
    const d = new Date(x.due_at);
    return d >= start && d <= end;
  }).length;
});
const kpiByUnitMonth = computed(() => {
  const inCursorMonth = clinicTasks.value.filter(x =>
    isSameMonth(new Date(x.due_at), cursor.value)
  );
  return Object.fromEntries(
    Object.keys(UNITS).map(key => [key, inCursorMonth.filter(x => x.unit === key).length])
  );
});

// ── Fetch ──────────────────────────────────────────────────
const fetchTasks = async () => {
  isLoading.value = true;
  try {
    await store.dispatch('tasks/fetch');
  } catch {
    useAlert('Erro ao carregar a agenda.');
  } finally {
    isLoading.value = false;
  }
};

onMounted(() => {
  if (!agents.value.length) store.dispatch('agents/get');
  store.dispatch('crm/fetchSettings').catch(() => {}); // janelas dos médicos
  fetchTasks();
});

// ── Modal criar/editar consulta ─────────────────────────────
const showModal = ref(false);
const editingTask = ref(null);
const isSaving = ref(false);
const showDeleteConfirm = ref(false);

const emptyForm = (day, prefill = {}) => ({
  name: '',
  phone: '',
  procedure: '',
  doctor: prefill.doctor || activeDoctor.value || '',
  date: format(day || cursor.value, 'yyyy-MM-dd'),
  time: prefill.time || '09:00',
  unit: prefill.unit || activeUnit.value || 'tatuape',
  status: 'todo',
  canceled: false,
  description: '',
});

const form = ref(emptyForm());

const openCreateOnDay = (day, prefill = {}) => {
  editingTask.value = null;
  form.value = emptyForm(day, prefill);
  showDeleteConfirm.value = false;
  showModal.value = true;
};

// clique num bloco livre da janela → consulta pré-preenchida
const openCreateSlot = (day, win, slot) =>
  openCreateOnDay(day, { time: slot, unit: win.unit, doctor: win.doctor });

const openEdit = task => {
  const d = new Date(task.due_at);
  const pad = n => String(n).padStart(2, '0');
  editingTask.value = task;
  form.value = {
    name: displayName(task),
    phone: task.phone ?? '',
    procedure: task.procedure ?? '',
    doctor: task.doctor ?? '',
    date: `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`,
    time: `${pad(d.getHours())}:${pad(d.getMinutes())}`,
    unit: task.unit ?? '',
    status: task.status === 'done' ? 'done' : 'todo',
    canceled: !!task.canceled_at,
    description: task.description ?? '',
  };
  showDeleteConfirm.value = false;
  showModal.value = true;
};

const save = async () => {
  if (!form.value.name.trim() || !form.value.date || isSaving.value) return;
  isSaving.value = true;
  try {
    const dueAt = new Date(`${form.value.date}T${form.value.time || '09:00'}`);
    const payload = {
      title: form.value.name.trim(),
      phone: form.value.phone.trim(),
      procedure: form.value.procedure.trim(),
      doctor: form.value.doctor.trim(),
      due_at: dueAt.toISOString(),
      unit: form.value.unit,
      status: form.value.status,
      canceled: form.value.canceled,
      description: form.value.description,
      task_type: 'consulta',
      priority: 'medium',
    };
    if (editingTask.value) {
      await store.dispatch('tasks/update', { id: editingTask.value.id, ...payload });
      useAlert('Consulta atualizada');
    } else {
      await store.dispatch('tasks/create', payload);
      useAlert('Consulta agendada');
    }
    showModal.value = false;
  } catch {
    useAlert('Erro ao salvar a consulta.');
  } finally {
    isSaving.value = false;
  }
};

const removeTask = async () => {
  if (!editingTask.value) return;
  try {
    await store.dispatch('tasks/remove', editingTask.value.id);
    showModal.value = false;
    useAlert('Consulta removida');
  } catch {
    useAlert('Erro ao remover a consulta.');
  }
};
</script>

<template>
  <div class="bg-n-surface-1 flex flex-col h-full w-full">
    <!-- Top bar — visual alinhado ao Dashboard CRM -->
    <div class="px-6 pt-5 pb-4 border-b border-n-weak flex-shrink-0">
      <div class="flex items-center gap-3 flex-wrap">
        <h1 class="text-lg font-bold text-n-slate-12 flex items-center gap-2">
          <span class="w-8 h-8 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)">
            <span class="i-lucide-calendar-days text-white text-base" />
          </span>
          Agenda de Consultas
        </h1>

        <!-- Navegação -->
        <div class="flex items-center gap-1 ml-2">
          <button
            class="w-8 h-8 flex items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-alpha-1 i-lucide-chevron-left"
            @click="step(-1)"
          />
          <span class="text-sm font-medium text-n-slate-12 min-w-[170px] text-center">{{ navLabel }}</span>
          <button
            class="w-8 h-8 flex items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-alpha-1 i-lucide-chevron-right"
            @click="step(1)"
          />
          <button
            class="ml-1 text-xs font-medium px-2.5 py-1.5 rounded-lg text-white"
            style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)"
            @click="goToday"
          >
            Hoje
          </button>
        </div>

        <!-- Visões: Mês / Semana / Dia -->
        <div class="flex items-center bg-n-solid-2 border border-n-weak rounded-xl p-0.5 gap-0.5">
          <button
            v-for="m in VIEW_MODES"
            :key="m.key"
            class="flex items-center gap-1.5 px-3 h-7 rounded-lg text-xs font-medium transition-colors"
            :class="viewMode === m.key ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
            :style="viewMode === m.key ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' } : {}"
            @click="viewMode = m.key"
          >
            <span :class="m.icon" class="text-sm" />
            {{ m.label }}
          </button>
        </div>

        <div class="flex items-center gap-2 ml-auto flex-wrap">
          <button
            class="flex items-center gap-1.5 text-xs font-medium px-3 py-2 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 transition-colors"
            title="Janelas de avaliação dos médicos"
            @click="showWindowsModal = true"
          >
            <span class="i-lucide-clock text-sm" />
            Janelas dos médicos
          </button>
          <select
            v-model="view"
            class="h-9 text-sm border border-n-weak rounded-lg px-2 bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
          >
            <option value="clinic">Todas as consultas</option>
            <optgroup label="Unidades">
              <option v-for="(u, key) in UNITS" :key="key" :value="`unit:${key}`">{{ u.label }}</option>
            </optgroup>
            <optgroup label="Médicos">
              <option v-for="d in DOCTORS" :key="d.name" :value="`doctor:${d.name}`">{{ d.name }}</option>
            </optgroup>
            <option value="me">Minha agenda pessoal</option>
            <optgroup v-if="isAdmin" label="Pessoas">
              <option v-for="agent in agents" :key="agent.id" :value="String(agent.id)">{{ agent.name }}</option>
            </optgroup>
          </select>
          <button
            class="flex items-center gap-1.5 text-sm px-3 py-2 rounded-lg text-white hover:opacity-90 transition-opacity"
            style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)"
            @click="openCreateOnDay(new Date())"
          >
            <span class="i-lucide-plus text-sm" />
            Nova consulta
          </button>
        </div>
      </div>

      <!-- KPIs no estilo do Dashboard -->
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mt-4">
        <div class="rounded-xl px-4 py-3 text-white shadow" style="background: linear-gradient(135deg, #0F5FA6, #0B4A82)">
          <p class="text-[11px] font-medium text-white/80">Consultas hoje</p>
          <p class="text-xl font-bold leading-tight">{{ kpiToday }}</p>
        </div>
        <div class="rounded-xl px-4 py-3 text-white shadow" style="background: linear-gradient(135deg, #5B21B6, #7C3AED)">
          <p class="text-[11px] font-medium text-white/80">Nesta semana</p>
          <p class="text-xl font-bold leading-tight">{{ kpiWeek }}</p>
        </div>
        <button
          v-for="(u, key) in UNITS"
          :key="key"
          class="rounded-xl px-4 py-3 text-left shadow border transition-colors"
          :style="view === `unit:${key}`
            ? { background: u.color, borderColor: u.color, color: 'white' }
            : { backgroundColor: u.color + '14', borderColor: u.color + '40' }"
          @click="view = view === `unit:${key}` ? 'clinic' : `unit:${key}`"
        >
          <p class="text-[11px] font-medium flex items-center gap-1.5" :style="view === `unit:${key}` ? {} : { color: u.color }">
            <span class="w-2 h-2 rounded-full" :style="{ backgroundColor: view === `unit:${key}` ? 'white' : u.color }" />
            {{ u.label }} — no mês
          </p>
          <p class="text-xl font-bold leading-tight" :style="view === `unit:${key}` ? {} : { color: u.color }">
            {{ kpiByUnitMonth[key] || 0 }}
          </p>
        </button>
      </div>

      <!-- Ocupação da agenda (% preenchida no dia/semana/mês navegados) -->
      <div v-if="showOccupancy" class="mt-3 rounded-xl border border-n-weak bg-n-solid-2 px-4 py-3">
        <div class="flex items-center gap-2 mb-2.5 flex-wrap">
          <span class="i-lucide-gauge text-sm text-n-slate-10" />
          <p class="text-xs font-semibold text-n-slate-12">Ocupação da agenda</p>
          <span
            v-if="activeDoctor"
            class="text-[10px] px-2 py-0.5 rounded-full font-semibold text-white"
            :style="{ backgroundColor: doctorColor(activeDoctor) }"
          >{{ activeDoctor }}</span>
          <span
            v-else-if="activeUnit"
            class="text-[10px] px-2 py-0.5 rounded-full font-semibold text-white"
            :style="{ backgroundColor: UNITS[activeUnit].color }"
          >{{ UNITS[activeUnit].label }}</span>
          <span v-else class="text-[10px] px-2 py-0.5 rounded-full font-medium bg-n-alpha-2 text-n-slate-11">Toda a clínica</span>
          <span class="text-[10px] text-n-slate-9 ml-auto hidden sm:block">
            🟢 com vagas · 🟡 enchendo · 🔴 quase cheia — cadeados fora da conta
          </span>
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div>
            <div class="flex items-center justify-between text-xs mb-1">
              <span class="text-n-slate-11">Dia <span class="text-n-slate-9">({{ occDayLabel }})</span></span>
              <span class="font-bold text-n-slate-12">{{ occDay.total ? occDay.pct + '%' : '—' }}</span>
            </div>
            <div class="h-2.5 bg-n-alpha-1 rounded-full overflow-hidden">
              <div
                v-if="occDay.total"
                class="h-full rounded-full transition-all"
                :style="{ width: Math.max(occDay.pct, 3) + '%', background: occColor(occDay.pct) }"
              />
            </div>
            <p class="text-[10px] text-n-slate-9 mt-0.5">
              {{ occDay.total ? `${occDay.filled} de ${occDay.total} blocos ocupados` : 'sem janela neste dia' }}
            </p>
          </div>
          <div>
            <div class="flex items-center justify-between text-xs mb-1">
              <span class="text-n-slate-11">Semana <span class="text-n-slate-9">({{ occWeekLabel }})</span></span>
              <span class="font-bold text-n-slate-12">{{ occWeek.total ? occWeek.pct + '%' : '—' }}</span>
            </div>
            <div class="h-2.5 bg-n-alpha-1 rounded-full overflow-hidden">
              <div
                v-if="occWeek.total"
                class="h-full rounded-full transition-all"
                :style="{ width: Math.max(occWeek.pct, 3) + '%', background: occColor(occWeek.pct) }"
              />
            </div>
            <p class="text-[10px] text-n-slate-9 mt-0.5">
              {{ occWeek.total ? `${occWeek.filled} de ${occWeek.total} blocos ocupados` : 'sem janelas na semana' }}
            </p>
          </div>
          <div>
            <div class="flex items-center justify-between text-xs mb-1">
              <span class="text-n-slate-11">Mês <span class="text-n-slate-9">({{ occMonthLabel }})</span></span>
              <span class="font-bold text-n-slate-12">{{ occMonth.total ? occMonth.pct + '%' : '—' }}</span>
            </div>
            <div class="h-2.5 bg-n-alpha-1 rounded-full overflow-hidden">
              <div
                v-if="occMonth.total"
                class="h-full rounded-full transition-all"
                :style="{ width: Math.max(occMonth.pct, 3) + '%', background: occColor(occMonth.pct) }"
              />
            </div>
            <p class="text-[10px] text-n-slate-9 mt-0.5">
              {{ occMonth.total ? `${occMonth.filled} de ${occMonth.total} blocos ocupados` : 'sem janelas no mês' }}
            </p>
          </div>
        </div>
      </div>
    </div>

    <!-- Loading -->
    <div v-if="isLoading" class="flex justify-center items-center flex-1">
      <Spinner :size="32" class="text-n-brand" />
    </div>

    <!-- ══ VISÃO MENSAL ══ -->
    <div v-else-if="viewMode === 'month'" class="flex-1 min-h-0 flex flex-col p-4">
      <div class="grid grid-cols-7 gap-px mb-px">
        <div v-for="wd in WEEKDAYS" :key="wd" class="text-center text-xs font-medium text-n-slate-10 py-1.5">
          {{ wd }}
        </div>
      </div>
      <div class="flex-1 grid grid-rows-6 gap-px min-h-0">
        <div v-for="(week, wi) in weeks" :key="wi" class="grid grid-cols-7 gap-px min-h-0">
          <div
            v-for="day in week"
            :key="day.toISOString()"
            class="border border-n-weak rounded-lg p-1.5 flex flex-col min-h-0 overflow-hidden cursor-pointer transition-colors hover:border-n-brand/50"
            :class="[
              inMonth(day) ? 'bg-n-solid-1' : 'bg-n-alpha-1 opacity-60',
              isDayOff(day) ? 'opacity-50' : '',
            ]"
            @click="openCreateOnDay(day)"
          >
            <div class="flex items-center justify-between flex-shrink-0 mb-1">
              <span
                class="text-xs w-5 h-5 flex items-center justify-center rounded-full"
                :class="isToday(day) ? 'text-white font-semibold' : (inMonth(day) ? 'text-n-slate-11' : 'text-n-slate-9')"
                :style="isToday(day) ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' } : {}"
              >
                {{ day.getDate() }}
              </span>
              <span v-if="isDayOff(day)" class="i-lucide-lock text-[10px]" :class="isDayBlocked(day) ? 'text-red-400' : 'text-n-slate-8'" :title="isDayBlocked(day) ? 'Dia fechado' : 'Sem agenda de avaliação'" />
              <span v-else class="flex items-center gap-0.5">
                <span
                  v-for="w in windowsForDay(day)"
                  :key="w.doctor + w.start"
                  class="w-1.5 h-1.5 rounded-full"
                  :style="{ backgroundColor: doctorColor(w.doctor) }"
                  :title="`${w.doctor} — ${w.start}`"
                />
                <span
                  v-if="showOccupancy && dayOccupancy(day)"
                  class="text-[9px] font-bold ml-0.5"
                  :style="{ color: occColor(dayOccupancy(day).pct) }"
                  :title="`${dayOccupancy(day).filled} de ${dayOccupancy(day).total} blocos ocupados`"
                >{{ dayOccupancy(day).pct }}%</span>
              </span>
            </div>
            <div class="flex-1 overflow-y-auto space-y-0.5 min-h-0" style="scrollbar-width:thin;">
              <button
                v-for="task in dayTasks(day)"
                :key="task.id"
                class="w-full flex items-center gap-1 px-1.5 py-0.5 rounded text-left text-[11px] leading-tight transition-colors"
                :class="task.status === 'done'
                  ? 'bg-green-500/10 text-green-700 dark:text-green-400 line-through'
                  : (isOverdue(task) ? 'bg-red-500/10 text-red-600' : 'bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3')"
                @click.stop="openEdit(task)"
              >
                <span class="w-1.5 h-1.5 rounded-full flex-shrink-0" :style="{ backgroundColor: dotColor(task) }" />
                <span class="text-[10px] text-n-slate-9 flex-shrink-0">{{ chipTime(task) }}</span>
                <span class="truncate">{{ displayName(task) }}</span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- ══ VISÃO SEMANAL ══ -->
    <div v-else-if="viewMode === 'week'" class="flex-1 min-h-0 overflow-y-auto p-4">
      <div class="grid grid-cols-7 gap-2 min-h-full">
        <div
          v-for="day in weekDays"
          :key="day.toISOString()"
          class="border border-n-weak rounded-xl flex flex-col min-h-[300px]"
          :class="[isDayOff(day) ? 'bg-n-alpha-1 opacity-60' : 'bg-n-solid-1', { 'ring-2 ring-n-brand/40': isToday(day) }]"
        >
          <!-- Cabeçalho do dia -->
          <button
            class="flex flex-col items-center py-2 border-b border-n-weak hover:bg-n-alpha-1 rounded-t-xl"
            title="Agendar neste dia"
            @click="openCreateOnDay(day)"
          >
            <span class="text-[10px] font-medium text-n-slate-10 uppercase">{{ WEEKDAYS[day.getDay()] }}</span>
            <span
              class="text-sm w-7 h-7 flex items-center justify-center rounded-full font-semibold mt-0.5"
              :class="isToday(day) ? 'text-white' : 'text-n-slate-12'"
              :style="isToday(day) ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' } : {}"
            >
              {{ day.getDate() }}
            </span>
            <!-- Médicos do dia / bloqueado -->
            <span v-if="isDayOff(day)" class="text-[9px] mt-1 flex items-center gap-0.5" :class="isDayBlocked(day) ? 'text-red-400' : 'text-n-slate-9'">
              <span class="i-lucide-lock text-[9px]" /> {{ isDayBlocked(day) ? 'Fechado' : 'Bloqueado' }}
            </span>
            <span v-else-if="windowsForDay(day).length" class="flex flex-col items-center gap-0.5 mt-1 px-1">
              <span class="flex flex-wrap justify-center gap-0.5">
                <span
                  v-for="w in windowsForDay(day)"
                  :key="w.doctor + w.start"
                  class="text-[8px] px-1 py-px rounded-full font-semibold text-white"
                  :style="{ backgroundColor: doctorColor(w.doctor) }"
                  :title="`${w.doctor} — ${w.start} às ${w.end} (${UNITS[w.unit].label})`"
                >
                  {{ DOCTORS.find(d => d.name === w.doctor)?.short }}
                </span>
              </span>
              <span
                v-if="showOccupancy && dayOccupancy(day)"
                class="text-[9px] font-bold"
                :style="{ color: occColor(dayOccupancy(day).pct) }"
                :title="`${dayOccupancy(day).filled} de ${dayOccupancy(day).total} blocos ocupados`"
              >{{ dayOccupancy(day).pct }}% ocupado</span>
            </span>
          </button>
          <!-- Consultas -->
          <div class="flex-1 p-1.5 space-y-1.5 overflow-y-auto" style="scrollbar-width: thin;">
            <button
              v-for="task in dayTasks(day)"
              :key="task.id"
              class="w-full text-left rounded-lg border px-2 py-1.5 transition-colors hover:border-n-brand/60"
              :class="task.status === 'done' ? 'opacity-60' : ''"
              :style="{ borderColor: dotColor(task) + '50', backgroundColor: dotColor(task) + '0D' }"
              @click="openEdit(task)"
            >
              <p class="text-[10px] font-bold" :style="{ color: dotColor(task) }">{{ chipTime(task) }}</p>
              <p class="text-[11px] font-medium text-n-slate-12 leading-tight truncate" :class="task.status === 'done' ? 'line-through' : ''">
                {{ displayName(task) }}
              </p>
              <p v-if="task.procedure" class="text-[10px] text-n-slate-10 truncate">{{ task.procedure }}</p>
            </button>
            <p v-if="!dayTasks(day).length" class="text-center text-[10px] text-n-slate-8 pt-4">—</p>
          </div>
        </div>
      </div>
    </div>

    <!-- ══ VISÃO DIÁRIA ══ -->
    <div v-else class="flex-1 min-h-0 overflow-y-auto p-4">
      <div class="max-w-3xl mx-auto">
        <!-- Fim de semana / dia fechado -->
        <div
          v-if="isWeekend(cursor)"
          class="flex items-center gap-2 rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3 mb-4 text-sm text-n-slate-10"
        >
          <span class="i-lucide-lock text-base" />
          {{ WEEKDAY_FULL[cursor.getDay()] }} — sem agenda de avaliação em nenhuma unidade.
        </div>
        <div
          v-else-if="isDayBlocked(cursor)"
          class="flex items-center gap-2 rounded-xl border-2 border-red-500/30 bg-red-500/5 px-4 py-3 mb-4 text-sm text-n-slate-11 flex-wrap"
        >
          <span class="i-lucide-lock text-base text-red-500" />
          <b>Dia fechado</b> — sem agenda de avaliação nesta data.
          <button
            v-if="isAdmin"
            class="ml-auto text-xs font-medium px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
            @click="toggleBlockDay(cursor)"
          >
            Reabrir dia
          </button>
        </div>
        <div v-else-if="isAdmin && windowsForDay(cursor).length" class="flex justify-end mb-3">
          <button
            class="flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-10 hover:text-red-500 hover:bg-n-alpha-1 transition-colors"
            title="Fechar o dia inteiro (feriado, congresso, folga...)"
            @click="toggleBlockDay(cursor)"
          >
            <span class="i-lucide-lock text-xs" />
            Fechar este dia
          </button>
        </div>

        <!-- Janelas de avaliação do dia (blocos livres/ocupados) -->
        <div v-for="win in (isDayBlocked(cursor) ? [] : windowsForDay(cursor))" :key="win.doctor + win.start" class="rounded-2xl border-2 bg-n-solid-1 overflow-hidden mb-4" :style="{ borderColor: doctorColor(win.doctor) + '40' }">
          <div class="h-1 w-full" :style="{ background: doctorColor(win.doctor) }" />
          <div class="p-4">
            <div class="flex items-center gap-2 flex-wrap mb-3">
              <span class="w-7 h-7 rounded-lg flex items-center justify-center" :style="{ background: doctorColor(win.doctor) }">
                <span class="i-lucide-stethoscope text-white text-sm" />
              </span>
              <p class="text-sm font-bold text-n-slate-12">{{ win.doctor }}</p>
              <span class="text-[10px] px-2 py-0.5 rounded-full font-medium" :style="{ backgroundColor: UNITS[win.unit].color + '1A', color: UNITS[win.unit].color }">
                {{ UNITS[win.unit].label }}
              </span>
              <span class="text-xs text-n-slate-10">{{ win.turno }} · {{ win.start }} às {{ win.end }} · blocos de {{ win.block }} min</span>
              <span
                class="text-[10px] px-2 py-0.5 rounded-full font-bold text-white ml-auto"
                :style="{ backgroundColor: occColor(winOccupancy(cursor, win).pct) }"
                :title="`${winOccupancy(cursor, win).filled} de ${winOccupancy(cursor, win).total} blocos ocupados`"
              >
                {{ winOccupancy(cursor, win).pct }}% ocupado
              </span>
            </div>
            <div class="grid grid-cols-4 sm:grid-cols-6 gap-1.5">
              <template v-for="slot in slotsFor(win)" :key="slot">
                <!-- ocupado -->
                <button
                  v-if="taskAtSlot(cursor, win, slot)"
                  class="rounded-lg px-1.5 py-1.5 text-[11px] font-medium text-white text-left truncate hover:opacity-90"
                  :style="{ background: doctorColor(win.doctor) }"
                  :title="displayName(taskAtSlot(cursor, win, slot))"
                  @click="openEdit(taskAtSlot(cursor, win, slot))"
                >
                  {{ slot }} · {{ displayName(taskAtSlot(cursor, win, slot)) }}
                </button>
                <!-- fechado com o cadeado -->
                <button
                  v-else-if="isBlocked(cursor, win, slot)"
                  class="rounded-lg px-1.5 py-1.5 text-[11px] bg-n-alpha-2 text-n-slate-9 flex items-center justify-center gap-1"
                  :title="isAdmin ? 'Horário fechado — clique para reabrir' : 'Horário fechado'"
                  @click="isAdmin && toggleBlock(cursor, win, slot)"
                >
                  <span class="i-lucide-lock text-[10px]" />
                  {{ slot }}
                </button>
                <!-- livre (com mini-cadeado para fechar) -->
                <span v-else class="relative group">
                  <button
                    class="w-full rounded-lg px-1.5 py-1.5 text-[11px] border border-dashed text-n-slate-10 hover:text-n-slate-12 transition-colors"
                    :style="{ borderColor: doctorColor(win.doctor) + '60' }"
                    title="Bloco livre — clique para agendar"
                    @click="openCreateSlot(cursor, win, slot)"
                  >
                    {{ slot }}
                  </button>
                  <button
                    v-if="isAdmin"
                    class="absolute -top-1.5 -right-1.5 w-4 h-4 rounded-full bg-n-solid-3 border border-n-weak items-center justify-center hidden group-hover:flex hover:bg-n-alpha-2"
                    title="Fechar este horário 🔒"
                    @click.stop="toggleBlock(cursor, win, slot)"
                  >
                    <span class="i-lucide-lock text-[9px] text-n-slate-10" />
                  </button>
                </span>
              </template>
            </div>
          </div>
        </div>

        <div v-if="!dayViewTasks.length && !windowsForDay(cursor).length && !isWeekend(cursor)" class="text-center py-16 text-n-slate-10">
          <span class="i-lucide-calendar text-4xl mb-2 block mx-auto" />
          <p class="text-sm">Nenhuma consulta neste dia.</p>
          <button
            class="mt-3 text-sm px-3 py-2 rounded-lg text-white"
            style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)"
            @click="openCreateOnDay(cursor)"
          >
            + Agendar consulta
          </button>
        </div>
        <template v-if="dayViewTasks.length">
          <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-2 mt-2">Linha do tempo do dia</p>
          <div v-for="hour in HOURS" :key="hour" class="flex gap-3 min-h-[44px]">
            <!-- Coluna da hora -->
            <div class="w-12 flex-shrink-0 text-right pt-1">
              <span class="text-[11px] text-n-slate-9 font-medium">{{ String(hour).padStart(2, '0') }}:00</span>
            </div>
            <!-- Linha -->
            <div class="flex-1 border-t border-n-weak pt-1 pb-2 space-y-1.5">
              <button
                v-for="task in tasksAtHour(hour)"
                :key="task.id"
                class="w-full text-left rounded-xl border-2 px-3 py-2.5 transition-colors hover:opacity-90"
                :class="task.status === 'done' ? 'opacity-60' : ''"
                :style="{ borderColor: dotColor(task) + '60', backgroundColor: dotColor(task) + '10' }"
                @click="openEdit(task)"
              >
                <div class="flex items-center gap-2 flex-wrap">
                  <span class="text-xs font-bold" :style="{ color: dotColor(task) }">{{ chipTime(task) }}</span>
                  <span class="text-sm font-semibold text-n-slate-12" :class="task.status === 'done' ? 'line-through' : ''">
                    {{ displayName(task) }}
                  </span>
                  <span v-if="unitOf(task)" class="text-[10px] px-2 py-0.5 rounded-full font-medium" :style="{ backgroundColor: dotColor(task) + '1A', color: dotColor(task) }">
                    {{ unitOf(task).label }}
                  </span>
                  <span v-if="task.status === 'done'" class="text-[10px] px-2 py-0.5 rounded-full font-medium bg-green-500/15 text-green-600">
                    Concluída
                  </span>
                </div>
                <div class="flex items-center gap-3 mt-1 text-[11px] text-n-slate-10 flex-wrap">
                  <span v-if="task.phone" class="flex items-center gap-1"><span class="i-lucide-phone text-[10px]" />{{ task.phone }}</span>
                  <span v-if="task.procedure" class="flex items-center gap-1"><span class="i-lucide-eye text-[10px]" />{{ task.procedure }}</span>
                  <span v-if="task.doctor" class="flex items-center gap-1"><span class="i-lucide-stethoscope text-[10px]" />{{ task.doctor }}</span>
                </div>
              </button>
            </div>
          </div>
          <!-- Fora do horário 07–20h -->
          <div v-if="tasksOutsideHours.length" class="mt-3 pl-[60px] space-y-1.5">
            <p class="text-[10px] text-n-slate-9 uppercase font-semibold">Outros horários</p>
            <button
              v-for="task in tasksOutsideHours"
              :key="task.id"
              class="w-full text-left rounded-xl border px-3 py-2 text-sm text-n-slate-12"
              :style="{ borderColor: dotColor(task) + '50' }"
              @click="openEdit(task)"
            >
              {{ chipTime(task) }} — {{ displayName(task) }}
            </button>
          </div>
        </template>
      </div>
    </div>

    <!-- Modal criar/editar consulta -->
    <div
      v-if="showModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      @click.self="showModal = false"
    >
      <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-md max-h-[90vh] flex flex-col overflow-hidden">
        <div class="h-1.5 w-full flex-shrink-0" style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)" />
        <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak flex-shrink-0">
          <h2 class="text-base font-semibold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-calendar-plus text-n-brand" />
            {{ editingTask ? 'Editar consulta' : 'Nova consulta' }}
          </h2>
          <button class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl" @click="showModal = false" />
        </div>

        <div class="flex-1 overflow-y-auto p-5 space-y-3.5">
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Nome do paciente *</label>
            <input
              v-model="form.name"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
              placeholder="Maria Silva"
            />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">Telefone</label>
              <input
                v-model="form.phone"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
                placeholder="(11) 98888-7777"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">Problema</label>
              <input
                v-model="form.procedure"
                list="agenda-problemas"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
                placeholder="Catarata, refrativa..."
              />
              <datalist id="agenda-problemas">
                <option v-for="p in PROBLEMAS" :key="p" :value="p" />
              </datalist>
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">Dia *</label>
              <input
                v-model="form.date"
                type="date"
                class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-sm bg-n-solid-2 text-n-slate-12"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">Horário</label>
              <input
                v-model="form.time"
                type="time"
                class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-sm bg-n-solid-2 text-n-slate-12"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">Médico</label>
              <select
                v-model="form.doctor"
                class="w-full border border-n-weak rounded-lg px-2 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              >
                <option value="">A definir</option>
                <option v-for="d in DOCTORS" :key="d.name" :value="d.name">{{ d.name }}</option>
              </select>
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">Unidade</label>
              <select
                v-model="form.unit"
                class="w-full border border-n-weak rounded-lg px-2 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              >
                <option v-for="(u, key) in UNITS" :key="key" :value="key">{{ u.label }}</option>
                <option value="">Agenda pessoal (sem unidade)</option>
              </select>
            </div>
          </div>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Situação</label>
            <div class="flex items-center bg-n-solid-2 border border-n-weak rounded-xl p-0.5 gap-0.5 w-fit">
              <button
                class="px-3 h-7 rounded-lg text-xs font-medium transition-colors"
                :class="form.status === 'todo' ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
                :style="form.status === 'todo' ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' } : {}"
                @click="form.status = 'todo'"
              >
                Agendada
              </button>
              <button
                class="px-3 h-7 rounded-lg text-xs font-medium transition-colors"
                :class="form.status === 'done' ? 'bg-green-600 text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
                @click="form.status = 'done'"
              >
                Concluída
              </button>
              <button
                v-if="editingTask"
                class="px-3 h-7 rounded-lg text-xs font-medium transition-colors"
                :class="form.canceled ? 'bg-red-600 text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
                @click="form.canceled = !form.canceled"
              >
                Cancelada
              </button>
            </div>
            <p v-if="form.canceled" class="text-[10px] text-red-500 mt-1">
              A consulta sai do calendário e conta no indicador de canceladas do Meu Painel.
            </p>
          </div>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Observações</label>
            <textarea
              v-model="form.description"
              rows="2"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 resize-none focus:outline-none focus:border-n-brand"
              placeholder="Convênio, pedido especial, retorno..."
            />
          </div>
        </div>

        <div class="px-5 py-4 border-t border-n-weak flex-shrink-0 space-y-2">
          <div class="flex gap-2">
            <button
              class="flex-1 text-white rounded-lg py-2 text-sm font-medium disabled:opacity-50"
              style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)"
              :disabled="!form.name.trim() || !form.date || isSaving"
              @click="save"
            >
              {{ isSaving ? 'Salvando…' : (editingTask ? 'Salvar consulta' : 'Agendar consulta') }}
            </button>
            <button
              class="px-4 border border-n-weak rounded-lg py-2 text-sm text-n-slate-11"
              @click="showModal = false"
            >
              Cancelar
            </button>
          </div>
          <div v-if="editingTask">
            <button
              v-if="!showDeleteConfirm"
              class="w-full py-1.5 text-xs text-red-500 hover:text-red-600"
              @click="showDeleteConfirm = true"
            >
              Excluir consulta
            </button>
            <div v-else class="flex items-center gap-2">
              <span class="text-xs text-n-slate-11 flex-1">Excluir este agendamento?</span>
              <button class="bg-red-500 text-white px-3 py-1 rounded-lg text-xs" @click="removeTask">
                Excluir
              </button>
              <button class="border border-n-weak px-3 py-1 rounded-lg text-xs text-n-slate-11" @click="showDeleteConfirm = false">
                Cancelar
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    <!-- Modal: janelas de avaliação dos médicos -->
    <div
      v-if="showWindowsModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      @click.self="showWindowsModal = false"
    >
      <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-lg max-h-[90vh] flex flex-col overflow-hidden">
        <div class="h-1.5 w-full flex-shrink-0" style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)" />
        <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak flex-shrink-0">
          <h2 class="text-base font-semibold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-clock text-n-brand" />
            Janelas de avaliação dos médicos
          </h2>
          <div class="flex items-center gap-2">
            <button
              v-if="isAdmin && !isEditingWindows"
              class="flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
              @click="startEditWindows"
            >
              <span class="i-lucide-pencil text-xs" />
              Editar
            </button>
            <button class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl" @click="showWindowsModal = false; isEditingWindows = false" />
          </div>
        </div>
        <div class="flex-1 overflow-y-auto p-5 space-y-4">
          <!-- Legenda dos médicos -->
          <div class="flex items-center gap-3 flex-wrap">
            <span v-for="d in DOCTORS" :key="d.name" class="flex items-center gap-1.5 text-xs text-n-slate-11">
              <span class="w-2.5 h-2.5 rounded-full" :style="{ backgroundColor: d.color }" />
              {{ d.name }}
            </span>
          </div>

          <!-- ═ Visualização ═ -->
          <template v-if="!isEditingWindows">
            <div v-for="dow in [1, 2, 3, 4, 5]" :key="dow">
              <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1.5">{{ WEEKDAY_FULL[dow] }}</p>
              <div class="space-y-1.5">
                <div
                  v-for="w in windowsByDow[dow] || []"
                  :key="w.doctor + w.start"
                  class="flex items-center gap-2 rounded-xl border px-3 py-2 flex-wrap"
                  :style="{ borderColor: doctorColor(w.doctor) + '40', backgroundColor: doctorColor(w.doctor) + '0A' }"
                >
                  <span class="w-2 h-2 rounded-full flex-shrink-0" :style="{ backgroundColor: doctorColor(w.doctor) }" />
                  <span class="text-sm font-medium text-n-slate-12">{{ w.doctor }}</span>
                  <span class="text-[10px] px-2 py-0.5 rounded-full font-medium" :style="{ backgroundColor: UNITS[w.unit].color + '1A', color: UNITS[w.unit].color }">
                    {{ UNITS[w.unit].label }}
                  </span>
                  <span class="text-xs text-n-slate-10 ml-auto">{{ w.turno }} · {{ w.start }}–{{ w.end }} · {{ w.block }} min</span>
                </div>
                <p v-if="!(windowsByDow[dow] || []).length" class="text-xs text-n-slate-9 pl-1">— sem janela</p>
              </div>
            </div>

            <div class="flex items-center gap-2 rounded-xl border border-n-weak bg-n-alpha-1 px-3 py-2 text-xs text-n-slate-10">
              <span class="i-lucide-lock text-sm" />
              Sábado e domingo: bloqueados — não existe agenda em nenhuma unidade.
            </div>
          </template>

          <!-- ═ Edição (admin) ═ -->
          <template v-else>
            <div
              v-for="(w, i) in editWindows"
              :key="i"
              class="rounded-xl border border-n-weak bg-n-solid-2 p-3 space-y-2"
            >
              <div class="flex items-center gap-2 flex-wrap">
                <select v-model.number="w.dow" class="border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12">
                  <option v-for="d in [1, 2, 3, 4, 5]" :key="d" :value="d">{{ WEEKDAY_FULL[d] }}</option>
                </select>
                <select v-model="w.doctor" class="border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12">
                  <option v-for="d in DOCTORS" :key="d.name" :value="d.name">{{ d.name }}</option>
                </select>
                <select v-model="w.unit" class="border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12">
                  <option v-for="(u, key) in UNITS" :key="key" :value="key">{{ u.label }}</option>
                </select>
                <button class="ml-auto text-n-slate-9 hover:text-red-500 i-lucide-trash-2 text-sm" title="Remover janela" @click="removeWindow(i)" />
              </div>
              <div class="flex items-center gap-2 flex-wrap text-xs text-n-slate-11">
                <select v-model="w.turno" class="border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12">
                  <option value="Manhã">Manhã</option>
                  <option value="Tarde">Tarde</option>
                </select>
                das
                <input v-model="w.start" type="time" class="border border-n-weak rounded-lg px-2 py-1 text-xs bg-n-solid-1 text-n-slate-12" />
                às
                <input v-model="w.end" type="time" class="border border-n-weak rounded-lg px-2 py-1 text-xs bg-n-solid-1 text-n-slate-12" />
                <span class="text-n-slate-9">(fim exclusivo)</span>
                · blocos de
                <select v-model.number="w.block" class="border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12">
                  <option :value="10">10 min</option>
                  <option :value="15">15 min</option>
                  <option :value="20">20 min</option>
                  <option :value="30">30 min</option>
                </select>
              </div>
            </div>

            <button
              class="w-full py-2 rounded-xl border border-dashed border-n-weak text-xs text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1"
              @click="addWindow"
            >
              + Adicionar janela
            </button>

            <div class="flex gap-2">
              <button
                class="flex-1 text-white rounded-lg py-2 text-sm font-medium disabled:opacity-50"
                style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)"
                :disabled="isSavingWindows"
                @click="saveWindows"
              >
                {{ isSavingWindows ? 'Salvando…' : 'Salvar janelas' }}
              </button>
              <button
                class="px-4 border border-n-weak rounded-lg py-2 text-sm text-n-slate-11"
                @click="isEditingWindows = false"
              >
                Cancelar
              </button>
            </div>
          </template>
        </div>
      </div>
    </div>

  </div>
</template>
