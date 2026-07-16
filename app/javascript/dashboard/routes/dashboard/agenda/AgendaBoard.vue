<script setup>
// Agenda de CONSULTAS da clínica — visões Mês / Semana / Dia.
// Cada agendamento guarda: nome, telefone, problema (catarata, refrativa,
// exames...), dia, horário, médico e unidade. Criado à mão ou pelo Agente
// de Agendamento (IA) via ação de coluna do CRM.
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { frontendURL } from 'dashboard/helper/URLHelper';
import PatientSpaceIcon from 'dashboard/routes/dashboard/patient/PatientSpaceIcon.vue';
import {
  startOfMonth, endOfMonth, startOfWeek, endOfWeek,
  addDays, addWeeks, addMonths, isSameDay, isSameMonth, format,
} from 'date-fns';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';
import {
  DOCTORS, MODALITIES, resolveWindows, resolveBlocked, resolveBlockedDays,
  resolveSurgeryWindows, slotsFor as sharedSlotsFor, dateKey, blockKey, scanAgenda,
} from 'dashboard/helper/cevicoAgenda';
import { ALL_THEMES, resolveTheme } from 'dashboard/helper/cevicoThemes';

const store = useStore();
const { isAdmin } = useAdmin();
const route = useRoute();
const router = useRouter();

// Espaço do Paciente: consulta amarrada ao contato (Fase 0) abre a
// página única com toda a jornada do paciente
const openPatientSpace = task => {
  if (!task?.contact_id) return;
  router.push(frontendURL(`accounts/${route.params.accountId}/patient/${task.contact_id}`));
};

const agents = useMapGetter('agents/getAgents');
const currentUser = useMapGetter('getCurrentUser');
const allTasks = useMapGetter('tasks/getTasks');

const isLoading = ref(true);
const cursor = ref(new Date()); // data de referência da navegação
const viewMode = ref('month'); // 'month' | 'week' | 'day'
// filtro: 'clinic' (todas) | 'unit:x' | 'doctor:Nome' | 'me' | '<agentId>'
const view = ref('clinic');

// ── AGENDA PARALELA DE CIRURGIAS ──
// Mesmo calendário, outro trilho: task_type 'cirurgia'. Tema AZUL CLARO
// "vítreo" (referências do Guilherme), bem distinto do azul→roxo das
// consultas — as cores dos médicos não mudam.
const agendaMode = ref('consultas'); // 'consultas' | 'cirurgias'
const isSurgeryMode = computed(() => agendaMode.value === 'cirurgias');
const isSurgeryTask = t => t.task_type === 'cirurgia';
const modeFilter = list =>
  isSurgeryMode.value ? list.filter(isSurgeryTask) : list.filter(t => !isSurgeryTask(t));

const SURGERY_GRAD = 'linear-gradient(135deg, #0284C7 0%, #38BDF8 55%, #7DD3FC 100%)';
const SURGERY_COLOR = '#0284C7';

// ── TEMA DO AMBIENTE (Santorini, Flor del Mar...) — escolha do admin ──
const theme = computed(() => resolveTheme(crmSettings.value));
// trilho de cirurgias: a cor do tema "PUXANDO PARA O BRANCO" (diferença
// bem evidente vs consultas) — o texto usa a cor escura do tema
const surgeryGrad = computed(() => theme.value.surgeryGrad || SURGERY_GRAD);
const surgeryInk = computed(() => theme.value.surgeryText || '#FFFFFF');
const showThemeMenu = ref(false);
const isSavingTheme = ref(false);
const setTheme = async key => {
  if (isSavingTheme.value) return;
  isSavingTheme.value = true;
  try {
    await CrmAPI.updateTheme(key);
    await store.dispatch('crm/fetchSettings');
    showThemeMenu.value = false;
    useAlert(`Tema aplicado: ${ALL_THEMES.find(t => t.key === key)?.label}`);
  } catch {
    useAlert('Erro ao trocar o tema.');
  } finally {
    isSavingTheme.value = false;
  }
};

// ── JANELAS DA SALA CIRÚRGICA (clínica parceira + dia + horário + bloco) ──
// Equivalente às janelas dos médicos, mas do trilho de cirurgias. O campo
// unit da janela recebe a KEY do local — assim scanAgenda/ocupação funcionam.
const surgeryWindows = computed(() => resolveSurgeryWindows(crmSettings.value));
const surgeryWindowsForDay = day =>
  surgeryWindows.value.filter(w => w.dow === day.getDay());
const surgeryLocationLabel = key =>
  surgeryLocations.value.find(l => l.key === key)?.label || key || 'Local a definir';

const showSurgeryWindowsModal = ref(false);
const editSurgeryWindows = ref([]);
const isSavingSurgeryWindows = ref(false);
const openSurgeryWindowsModal = () => {
  editSurgeryWindows.value = surgeryWindows.value.map(w => ({ ...w }));
  showSurgeryWindowsModal.value = true;
};
const addSurgeryWindow = () => {
  editSurgeryWindows.value.push({
    dow: 1, location: surgeryLocations.value[0]?.key || '', start: '08:00', end: '12:00', block: 60,
  });
};
const removeSurgeryWindow = i => editSurgeryWindows.value.splice(i, 1);
const saveSurgeryWindows = async () => {
  if (isSavingSurgeryWindows.value) return;
  isSavingSurgeryWindows.value = true;
  try {
    const clean = editSurgeryWindows.value
      .filter(w => w.start && w.end && w.location)
      .map(w => ({ dow: Number(w.dow), location: w.location, start: w.start, end: w.end, block: Number(w.block) || 60 }));
    await CrmAPI.updateSurgeryWindows(clean);
    await store.dispatch('crm/fetchSettings');
    showSurgeryWindowsModal.value = false;
    useAlert('Janelas da sala cirúrgica salvas!');
  } catch {
    useAlert('Erro ao salvar as janelas.');
  } finally {
    isSavingSurgeryWindows.value = false;
  }
};

// ── Duração dos agendamentos (blocos proporcionais nas visões) ──
// CONFIGURÁVEL pelas janelas: o bloco da janela (médico ou sala cirúrgica)
// onde o horário cai define a duração. Sem janela: consulta 15 · cirurgia 60.
const taskDuration = task => {
  const d = new Date(task.due_at);
  const mins = d.getHours() * 60 + d.getMinutes();
  const list = isSurgeryTask(task) ? surgeryWindows.value : windows.value;
  const win = list.find(w => {
    if (w.dow !== d.getDay()) return false;
    if (task.unit && w.unit !== task.unit) return false;
    const [sh, sm] = w.start.split(':').map(Number);
    const [eh, em] = w.end.split(':').map(Number);
    return mins >= sh * 60 + sm && mins < eh * 60 + em;
  });
  if (win?.block) return Number(win.block);
  return isSurgeryTask(task) ? 60 : 15;
};

// Locais de cirurgia (clínicas parceiras — IOP etc.): editáveis pelo admin,
// salvos em agenda_config.surgery_locations; a cirurgia guarda o local em unit
const DEFAULT_SURGERY_LOCATIONS = [
  { key: 'iop', label: 'IOP' },              // geralmente PRK
  { key: 'ocular_surgery', label: 'Ocular Surgery' }, // geralmente Lasik
];
// cor de cada clínica: IOP azul claro · Ocular Surgery prateado
const LOCATION_COLORS = { iop: '#38BDF8', ocular_surgery: '#94A3B8' };
const LOCATION_FALLBACK = ['#38BDF8', '#94A3B8', '#0EA5E9', '#818CF8'];
const surgeryLocations = computed(() => {
  const list = crmSettings.value?.surgery_locations;
  const base = Array.isArray(list) && list.length ? list : DEFAULT_SURGERY_LOCATIONS;
  return base.map((l, i) => ({
    ...l,
    color: LOCATION_COLORS[l.key] || LOCATION_FALLBACK[i % LOCATION_FALLBACK.length],
  }));
});
const surgeryLocationOf = task =>
  surgeryLocations.value.find(l => l.key === task.unit) || null;

const showLocationsModal = ref(false);
const locationsDraft = ref([]);
const isSavingLocations = ref(false);
const openLocationsModal = () => {
  locationsDraft.value = surgeryLocations.value.map(l => ({ ...l }));
  showLocationsModal.value = true;
};
const addLocationRow = () => locationsDraft.value.push({ key: '', label: '' });
const removeLocationRow = i => locationsDraft.value.splice(i, 1);
const slugifyLocation = text =>
  text.toString().trim().toLowerCase().normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
const saveLocations = async () => {
  if (isSavingLocations.value) return;
  isSavingLocations.value = true;
  try {
    const list = locationsDraft.value
      .filter(l => l.label.trim())
      .map(l => ({ key: l.key || slugifyLocation(l.label), label: l.label.trim() }));
    await CrmAPI.updateSurgeryLocations(list);
    await store.dispatch('crm/fetchSettings');
    showLocationsModal.value = false;
    useAlert('Locais de cirurgia salvos');
  } catch {
    useAlert('Erro ao salvar os locais.');
  } finally {
    isSavingLocations.value = false;
  }
};

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

// janelas de um dia (respeitando o filtro de unidade/médico ativo);
// no trilho de cirurgias, as janelas são as da SALA CIRÚRGICA
const windowsForDay = day => {
  if (isSurgeryMode.value) return surgeryWindowsForDay(day);
  return windows.value
    .filter(w => w.dow === day.getDay())
    .filter(w => !activeUnit.value || w.unit === activeUnit.value)
    .filter(w => !activeDoctor.value || w.doctor === activeDoctor.value);
};

// consultas ocupando um bloco (pode haver ENCAIXE: 2+ no mesmo horário)
const tasksAtSlotAll = (day, win, slot) =>
  dayTasks(day).filter(t => {
    const d = new Date(t.due_at);
    const hm = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
    return hm === slot && (!t.unit || t.unit === win.unit);
  });
const taskAtSlot = (day, win, slot) => tasksAtSlotAll(day, win, slot)[0];

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
  if (view.value === 'clinic') return modeFilter(list.filter(isAppointment));
  if (activeUnit.value) return modeFilter(list.filter(x => x.unit === activeUnit.value));
  if (activeDoctor.value)
    return modeFilter(list.filter(x => isAppointment(x) && x.doctor === activeDoctor.value));
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

// ── Calendário interativo (popover do rótulo de navegação) ──
const showDatePicker = ref(false);
const pickerCursor = ref(new Date());
const toggleDatePicker = () => {
  pickerCursor.value = new Date(cursor.value);
  showDatePicker.value = !showDatePicker.value;
};
const pickerLabel = computed(() =>
  pickerCursor.value
    .toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' })
    .replace(/^./, c => c.toUpperCase())
);
const pickerWeeks = computed(() => {
  const start = startOfWeek(startOfMonth(pickerCursor.value), { weekStartsOn: 0 });
  const end = endOfWeek(endOfMonth(pickerCursor.value), { weekStartsOn: 0 });
  const days = [];
  let d = start;
  while (d <= end) {
    days.push(d);
    d = addDays(d, 1);
  }
  const out = [];
  for (let i = 0; i < days.length; i += 7) out.push(days.slice(i, i + 7));
  return out;
});
const pickDate = day => {
  cursor.value = new Date(day);
  showDatePicker.value = false;
};

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
const tasksOutsideHours = computed(() =>
  dayViewTasks.value.filter(t => {
    const h = new Date(t.due_at).getHours();
    return h < HOURS[0] || h > HOURS[HOURS.length - 1];
  })
);

// ── Blocos proporcionais ao tempo (visões semana e dia) ─────
// 15 min = 25% de uma hora: o bloco ocupa exatamente o espaço do seu
// tempo, deixando o espaço livre evidente para o próximo encaixe.
const WEEK_ROW_PX = 48; // altura de 1 hora na grade semanal
const DAY_ROW_PX = 88;  // altura de 1 hora na grade diária

// posição do bloco DENTRO da célula da hora (semana)
const weekBlockStyle = (task, idx) => {
  const d = new Date(task.due_at);
  const topPct = (d.getMinutes() / 60) * 100;
  const heightPct = Math.max((taskDuration(task) / 60) * 100, 28);
  return {
    top: `${topPct}%`,
    height: `${heightPct}%`,
    left: `${2 + idx * 12}%`,
    right: '2px',
    zIndex: 5 + idx,
  };
};

// posição do bloco na grade do DIA (a partir das 07:00)
const dayBlockStyle = (task, list) => {
  const d = new Date(task.due_at);
  const minutes = (d.getHours() - HOURS[0]) * 60 + d.getMinutes();
  // encaixes no mesmo horário deslocam pra direita
  const sameTime = list.filter(
    t => t.id !== task.id && new Date(t.due_at).getTime() === d.getTime()
  );
  const idx = sameTime.filter(t => t.id < task.id).length;
  return {
    top: `${(minutes / 60) * DAY_ROW_PX}px`,
    height: `${Math.max((taskDuration(task) / 60) * DAY_ROW_PX - 2, 20)}px`,
    left: `${56 + idx * 120}px`,
    right: '8px',
    zIndex: 5 + idx,
  };
};

// clique num espaço vazio da grade do dia → agenda naquele horário (15 em 15)
const onDayGridClick = evt => {
  if (isDayOff(cursor.value)) return;
  const rect = evt.currentTarget.getBoundingClientRect();
  const minutes = ((evt.clientY - rect.top) / DAY_ROW_PX) * 60;
  const total = Math.round(minutes / 15) * 15;
  const h = HOURS[0] + Math.floor(total / 60);
  const mm = total % 60;
  openCreateOnDay(cursor.value, { time: `${String(h).padStart(2, '0')}:${String(mm).padStart(2, '0')}` });
};
const gridTasks = computed(() =>
  dayViewTasks.value.filter(t => {
    const h = new Date(t.due_at).getHours();
    return h >= HOURS[0] && h <= HOURS[HOURS.length - 1];
  })
);

// ── Helpers de exibição ─────────────────────────────────────
const displayName = task => (task.title || '').replace(/^Consulta:\s*/i, '');
const chipTime = task =>
  new Date(task.due_at).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
const unitOf = task => {
  if (task.unit && UNITS[task.unit]) return UNITS[task.unit];
  if (isSurgeryTask(task)) {
    const loc = surgeryLocationOf(task);
    if (loc) return { label: loc.label, color: loc.color || SURGERY_COLOR };
  }
  return null;
};
const dotColor = task => unitOf(task)?.color || '#94A3B8';
const isOverdue = task => task.status !== 'done' && new Date(task.due_at) < new Date();
// modalidade da consulta (sem tipo = avaliação, caso das consultas antigas)
const modalityOf = task =>
  MODALITIES.find(m => m.key === (task.modality || 'avaliacao')) || MODALITIES[0];

// ── Ocupação da agenda (% preenchida — dia/semana/mês) ──────
// Segue a navegação do calendário e o filtro ativo (unidade/médico).
// Fórmula: blocos ocupados ÷ blocos das janelas (cadeados fora da conta).
const occWindows = computed(() => {
  if (isSurgeryMode.value) return surgeryWindows.value;
  return windows.value
    .filter(w => !activeUnit.value || w.unit === activeUnit.value)
    .filter(w => !activeDoctor.value || w.doctor === activeDoctor.value);
});
const occScan = (from, days) =>
  scanAgenda({
    windows: occWindows.value,
    tasks: isSurgeryMode.value ? visibleTasks.value : visibleTasks.value.filter(isAppointment),
    blockedSet: blockedSet.value,
    blockedDays: blockedDays.value,
    from,
    days,
    freeLimit: 0,
  });

// só faz sentido contra as janelas da clínica (não na agenda pessoal,
// nem no trilho de cirurgias — que não usa as janelas de avaliação)
const showOccupancy = computed(() => {
  if (isSurgeryMode.value) return surgeryWindows.value.length > 0;
  return view.value === 'clinic' || !!activeUnit.value || !!activeDoctor.value;
});
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

// barra SEGMENTADA por tipo de consulta (avaliação/retorno/exames) —
// mostra quanto da agenda está ocupada com cada modalidade
const occSegments = scan => {
  if (isSurgeryMode.value || !scan.total) return null;
  return MODALITIES
    .map(m => ({ ...m, count: scan.byModality?.[m.key] || 0 }))
    .filter(s => s.count > 0)
    .map(s => ({ ...s, pct: Math.round((s.count / scan.total) * 100) }));
};
const occCaption = scan => {
  if (!scan.total) return null;
  const parts = (occSegments(scan) || [])
    .map(s => `${s.label} ${s.pct}%`)
    .join(' · ');
  return parts || null;
};

// % de um dia específico (chip nas visões Mês/Semana)
const dayOccupancy = day => {
  if (isDayOff(day)) return null;
  if (!occWindows.value.some(w => w.dow === day.getDay())) return null;
  return occScan(day, 1);
};

// ocupação de UMA janela de médico (visão Dia)
// rótulos/cores da janela — médicos (consultas) OU sala cirúrgica (cirurgias)
const winColor = win =>
  win.doctor
    ? doctorColor(win.doctor)
    : surgeryLocations.value.find(l => l.key === win.unit)?.color || SURGERY_COLOR;
const winTitle = win => win.doctor || `Sala cirúrgica — ${surgeryLocationLabel(win.unit)}`;
const winUnitLabel = win => (win.doctor ? UNITS[win.unit]?.label : surgeryLocationLabel(win.unit));

const winOccupancy = (day, win) => {
  const slots = slotsFor(win).filter(s => !isBlocked(day, win, s));
  const filled = slots.filter(s => taskAtSlot(day, win, s)).length;
  const total = slots.length;
  return { filled, total, pct: total ? Math.round((filled / total) * 100) : 0 };
};

// ── KPIs no estilo do Dashboard CRM (seguem o trilho ativo) ──
const clinicTasks = computed(() =>
  modeFilter(allTasks.value.filter(x => isAppointment(x) && x.due_at && x.status !== 'done'))
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
  const keys = isSurgeryMode.value
    ? surgeryLocations.value.map(l => l.key)
    : Object.keys(UNITS);
  return Object.fromEntries(
    keys.map(key => [key, inCursorMonth.filter(x => x.unit === key).length])
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

onMounted(async () => {
  if (!agents.value.length) store.dispatch('agents/get');
  await store.dispatch('crm/fetchSettings').catch(() => {}); // janelas dos médicos
  fetchTasks();
  loadCrmStages(); // colunas do CRM p/ a conferência do dia
});

// ── Modal criar/editar consulta ─────────────────────────────
const showModal = ref(false);
const editingTask = ref(null);
const isSaving = ref(false);
const showDeleteConfirm = ref(false);

const emptyForm = (day, prefill = {}) => ({
  name: prefill.name || '',
  phone: prefill.phone || '',
  procedure: prefill.procedure || '',
  doctor: prefill.doctor || activeDoctor.value || '',
  modality: prefill.modality || 'avaliacao',
  date: format(day || cursor.value, 'yyyy-MM-dd'),
  time: prefill.time || '09:00',
  unit: prefill.unit ||
    (isSurgeryMode.value ? surgeryLocations.value[0]?.key : activeUnit.value || 'tatuape') || '',
  status: 'todo',
  canceled: false,
  description: prefill.description || '',
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

// mês: clicar no dia NAVEGA para a semana daquele dia (agendar é na
// semana ou no botão +, onde o horário já vem entendido)
const goToWeek = day => {
  cursor.value = new Date(day);
  viewMode.value = 'week';
};

// semana: a ALTURA do clique dentro da célula diz o horário — metade de
// cima = hora cheia, metade de baixo = meia hora
const openCreateAtPoint = (day, hour, evt) => {
  const cell = evt.currentTarget;
  const ratio = cell.clientHeight
    ? Math.min(0.99, Math.max(0, evt.offsetY / cell.clientHeight))
    : 0;
  const half = ratio >= 0.5 ? '30' : '00';
  openCreateOnDay(day, { time: `${String(hour).padStart(2, '0')}:${half}` });
};

// botão + flutuante: o caminho principal para agendar de qualquer visão
const openCreateFab = () => {
  const base = viewMode.value === 'month' ? new Date() : new Date(cursor.value);
  openCreateOnDay(base);
};

const openEdit = task => {
  const d = new Date(task.due_at);
  const pad = n => String(n).padStart(2, '0');
  editingTask.value = task;
  form.value = {
    name: displayName(task),
    phone: task.phone ?? '',
    procedure: task.procedure ?? '',
    doctor: task.doctor ?? '',
    modality: task.modality || 'avaliacao',
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
      modality: form.value.modality || 'avaliacao',
      due_at: dueAt.toISOString(),
      unit: form.value.unit,
      status: form.value.status,
      canceled: form.value.canceled,
      description: form.value.description,
      // trilho ativo define o tipo; editar preserva o tipo original
      task_type: editingTask.value?.task_type || (isSurgeryMode.value ? 'cirurgia' : 'consulta'),
      priority: 'medium',
    };
    if (editingTask.value) {
      await store.dispatch('tasks/update', { id: editingTask.value.id, ...payload });
      useAlert(isSurgeryTask(payload) ? 'Cirurgia atualizada' : 'Consulta atualizada');
    } else {
      await store.dispatch('tasks/create', payload);
      useAlert(isSurgeryMode.value ? 'Cirurgia agendada 🔪' : 'Consulta agendada');
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

// ── Conferência do dia: Compareceu / Faltou + Indicação de cirurgia ──
// Marcar reflete no CRM: o card do paciente move para a coluna configurada
// (modal "Janelas dos médicos" → Conferência do dia) e as automações da
// coluna de destino disparam (régua de conversão/reagendamento).
const PROCEDURES = [
  'Catarata', 'Refrativa PRK', 'Refrativa Lasik', 'Lente Fácica',
  'Lente de Foco Estendido', 'Trifocal', 'Anel de Ferrara', 'Pterígio',
  'Capsulotomia YAG', 'Outro',
];
const savingAttendanceId = ref(0);
const indicationPickerId = ref(0); // consulta com o seletor de procedimento aberto

const setAttendance = async (task, value) => {
  if (savingAttendanceId.value) return;
  savingAttendanceId.value = task.id;
  try {
    const next = task.attendance === value ? null : value; // re-clique desfaz
    const payload = {
      id: task.id,
      attendance: next,
      status: next === 'attended' ? 'done' : 'todo',
    };
    if (next !== 'attended') {
      payload.surgery_indication = null;
      payload.indicated_procedure = null;
      indicationPickerId.value = 0;
    }
    await store.dispatch('tasks/update', payload);
    if (next === 'attended') useAlert('✓ Compareceu — agora marque se houve indicação de cirurgia.');
    else if (next === 'missed') useAlert('✗ Falta registrada — card movido no CRM (se a coluna estiver configurada).');
  } catch {
    useAlert('Erro ao registrar a conferência.');
  } finally {
    savingAttendanceId.value = 0;
  }
};

const setIndication = async (task, value, procedure = null) => {
  if (savingAttendanceId.value) return;
  // indicada exige escolher o procedimento primeiro
  if (value === 'indicated' && !procedure) {
    indicationPickerId.value = indicationPickerId.value === task.id ? 0 : task.id;
    return;
  }
  savingAttendanceId.value = task.id;
  try {
    const next = task.surgery_indication === value && !procedure ? null : value;
    await store.dispatch('tasks/update', {
      id: task.id,
      surgery_indication: next,
      indicated_procedure: next === 'indicated' ? procedure : null,
    });
    indicationPickerId.value = 0;
    if (next === 'indicated') useAlert(`🎯 Cirurgia de ${procedure} indicada — card movido no CRM (se configurado).`);
  } catch {
    useAlert('Erro ao registrar a indicação.');
  } finally {
    savingAttendanceId.value = 0;
  }
};

// ── Cirurgia: "veio e NÃO fez" (pede o motivo) ──
const noSurgeryReasonId = ref(0);
const noSurgeryReason = ref('');
const toggleNoSurgery = task => {
  if (task.attendance === 'attended_not_done') {
    setAttendance(task, 'attended_not_done'); // re-clique desfaz
    return;
  }
  noSurgeryReasonId.value = noSurgeryReasonId.value === task.id ? 0 : task.id;
  noSurgeryReason.value = '';
};
const confirmNoSurgery = async task => {
  if (savingAttendanceId.value) return;
  savingAttendanceId.value = task.id;
  try {
    const reason = noSurgeryReason.value.trim();
    await store.dispatch('tasks/update', {
      id: task.id,
      attendance: 'attended_not_done',
      status: 'todo',
      description: reason
        ? `⚠️ Veio e não operou: ${reason}\n${task.description || ''}`
        : task.description,
    });
    noSurgeryReasonId.value = 0;
    useAlert('Registrado: o paciente veio, mas a cirurgia não aconteceu.');
  } catch {
    useAlert('Erro ao registrar.');
  } finally {
    savingAttendanceId.value = 0;
  }
};

// valor da cirurgia (só admin): vem do card do CRM + forma de pagamento da IA
const fmtBRL = v =>
  Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });

// da consulta com indicação → agendar a CIRURGIA (trilho azul, pré-preenchida)
const scheduleSurgeryFrom = task => {
  agendaMode.value = 'cirurgias';
  editingTask.value = null;
  form.value = emptyForm(new Date(), {
    name: displayName(task),
    phone: task.phone || '',
    procedure: task.indicated_procedure || task.procedure || '',
    unit: surgeryLocations.value[0]?.key || '', // local padrão (ex.: IOP)
    description: `Origem: consulta de ${format(new Date(task.due_at), 'dd/MM')} às ${chipTime(task)} — cirurgia indicada.`,
  });
  showDeleteConfirm.value = false;
  showModal.value = true;
};

// ── Conferência do dia → colunas do CRM (config, admin) ──
const allCrmStages = ref([]);
const attendanceStages = ref({
  attended_stage_id: '', missed_stage_id: '', indicated_stage_id: '',
  surgery_done_stage_id: '', surgery_missed_stage_id: '',
});
// responsáveis pela conferência + prazo (consultas = Elisangela,
// cirurgias = Gabriela — o admin escolhe); passou do prazo sem conferir →
// tarefa automática "Concluir a conferência do dia" pra pessoa certa
const attendanceOwners = ref({ consulta_user_id: '', cirurgia_user_id: '', deadline: '19:00' });
const isSavingAttendanceCfg = ref(false);

const loadCrmStages = async () => {
  try {
    await store.dispatch('crm/fetchPipelines');
    const pipelines = store.getters['crm/getPipelines'] || [];
    allCrmStages.value = pipelines.flatMap(p =>
      (p.stages || []).map(s => ({ id: s.id, name: s.name, pipeline: p.name }))
    );
    const own = crmSettings.value?.attendance_owners || {};
    attendanceOwners.value = {
      consulta_user_id: own.consulta_user_id || '',
      cirurgia_user_id: own.cirurgia_user_id || '',
      deadline: own.deadline || '19:00',
    };
    const cfg = crmSettings.value?.attendance_stages || {};
    attendanceStages.value = {
      attended_stage_id: cfg.attended_stage_id || '',
      missed_stage_id: cfg.missed_stage_id || '',
      indicated_stage_id: cfg.indicated_stage_id || '',
      surgery_done_stage_id: cfg.surgery_done_stage_id || '',
      surgery_missed_stage_id: cfg.surgery_missed_stage_id || '',
    };
  } catch {
    allCrmStages.value = [];
  }
};

const saveAttendanceStages = async () => {
  isSavingAttendanceCfg.value = true;
  try {
    await CrmAPI.updateAttendanceStages({
      attended_stage_id: attendanceStages.value.attended_stage_id || null,
      missed_stage_id: attendanceStages.value.missed_stage_id || null,
      indicated_stage_id: attendanceStages.value.indicated_stage_id || null,
      surgery_done_stage_id: attendanceStages.value.surgery_done_stage_id || null,
      surgery_missed_stage_id: attendanceStages.value.surgery_missed_stage_id || null,
    });
    await CrmAPI.updateAttendanceOwners({
      consulta_user_id: attendanceOwners.value.consulta_user_id || null,
      cirurgia_user_id: attendanceOwners.value.cirurgia_user_id || null,
      deadline: attendanceOwners.value.deadline || '19:00',
    });
    useAlert('Conferência do dia configurada!');
  } catch {
    useAlert('Erro ao salvar a configuração.');
  } finally {
    isSavingAttendanceCfg.value = false;
  }
};

// ── Imprimir a lista do dia (PDF pelo diálogo de impressão) ──
const printDayList = () => {
  const day = cursor.value;
  const list = [...dayViewTasks.value].sort((a, b) => new Date(a.due_at) - new Date(b.due_at));
  const title = `CEVICO — Consultas de ${day.toLocaleDateString('pt-BR', { weekday: 'long', day: '2-digit', month: '2-digit', year: 'numeric' })}`;
  const esc = s => String(s ?? '').replace(/</g, '&lt;');
  const rows = list.map(t => `
    <tr>
      <td class="time">${chipTime(t)}</td>
      <td><b>${esc(displayName(t))}</b></td>
      <td>${esc(t.phone || '')}</td>
      <td>${esc(t.procedure || '')}</td>
      <td>${esc(t.doctor || '')}</td>
      <td>${unitOf(t)?.label || ''}</td>
      <td class="obs">${esc((t.description || '').slice(0, 90))}</td>
      <td class="check">☐</td>
      <td class="check">☐</td>
      <td class="check">☐</td>
    </tr>`).join('');
  const html = `<!doctype html><html><head><meta charset="utf-8"><title>${title}</title>
    <style>
      @page { size: A4 portrait; margin: 10mm; }
      body { font-family: Arial, sans-serif; margin: 24px; color: #111; }
      h1 { font-size: 16px; margin: 0 0 2px; }
      p.sub { font-size: 11px; color: #555; margin: 0 0 14px; }
      table { width: 100%; border-collapse: collapse; font-size: 11px; }
      th, td { border: 1px solid #999; padding: 5px 6px; text-align: left; vertical-align: top; }
      th { background: #eee; font-size: 10px; text-transform: uppercase; }
      td.time { font-weight: bold; white-space: nowrap; }
      td.check { text-align: center; font-size: 14px; width: 52px; }
      td.obs { font-size: 10px; color: #444; }
      @media print { body { margin: 10mm; } }
    </style></head><body>
    <h1>${title}</h1>
    <p class="sub">${list.length} consulta(s) · Conferência do fim do dia: marque Compareceu, Faltou e Cirurgia indicada — depois registre no sistema (Agenda → visão Dia).</p>
    <table><thead><tr>
      <th>Hora</th><th>Paciente</th><th>Telefone</th><th>Problema</th><th>Médico</th><th>Unidade</th><th>Observações</th>
      <th>Compareceu</th><th>Faltou</th><th>Cirurgia indicada</th>
    </tr></thead><tbody>${rows}</tbody></table>
    <script>window.onload = () => window.print();<\/script>
    </body></html>`;
  const w = window.open('', '_blank');
  if (!w) { useAlert('O navegador bloqueou a janela — libere pop-ups para imprimir.'); return; }
  w.document.write(html);
  w.document.close();
};

// ── Visão semanal (grade horária) ──
const tasksAtDayHour = (day, hour) =>
  dayTasks(day).filter(t => new Date(t.due_at).getHours() === hour);

const dragTask = ref(null);
const dragOverDay = ref('');
const onDragStart = task => { dragTask.value = task; };

// soltar numa célula = reagendar para aquele dia + hora (minutos mantidos);
// abre o modal já preenchido para CONFIRMAR antes de salvar
const onDropCell = (day, hour) => {
  const task = dragTask.value;
  dragTask.value = null;
  dragOverDay.value = '';
  if (!task || isDayOff(day)) return;
  const original = new Date(task.due_at);
  const sameSpot = isSameDay(original, day) && original.getHours() === hour;
  if (sameSpot) return;
  openEdit(task);
  form.value.date = format(day, 'yyyy-MM-dd');
  form.value.time = `${String(hour).padStart(2, '0')}:${String(original.getMinutes()).padStart(2, '0')}`;
};
</script>

<template>
  <div class="bg-n-surface-1 flex flex-col h-full w-full">
    <!-- Top bar — visual alinhado ao Dashboard CRM (conteúdo centralizado) -->
    <div class="px-4 sm:px-6 pt-5 pb-4 border-b border-n-weak flex-shrink-0">
      <div class="max-w-[1440px] mx-auto">
      <div class="flex flex-col gap-3">
      <div class="flex items-center gap-3 flex-wrap">
        <!-- Título com a ação principal logo abaixo (verde contrastante) -->
        <div class="flex flex-col gap-2">
          <h1
            class="font-bold text-n-slate-12 flex items-center gap-2"
            :class="isSurgeryMode ? 'text-xl' : 'text-lg'"
          >
            <span
              class="w-8 h-8 rounded-lg flex items-center justify-center"
              :class="isSurgeryMode ? 'cevico-glass cevico-surgery-ink' : ''"
              :style="{ background: isSurgeryMode ? surgeryGrad : theme.primary, '--surg-text': surgeryInk }"
            >
              <span :class="isSurgeryMode ? 'i-lucide-slice' : 'i-lucide-calendar-days'" class="text-white text-base" />
            </span>
            <!-- título em destaque no trilho de cirurgias (a faixa saiu) -->
            <span
              v-if="isSurgeryMode"
              class="bg-clip-text text-transparent"
              :style="{ backgroundImage: theme.key === 'cevico' ? 'linear-gradient(135deg, #0369A1, #38BDF8)' : theme.primary }"
            >Agenda de Cirurgias</span>
            <template v-else>Agenda de Consultas</template>
          </h1>
          <button
            class="flex items-center justify-center gap-1.5 text-sm font-semibold px-3.5 py-2 rounded-lg text-white hover:opacity-90 transition-opacity shadow w-fit"
            :class="isSurgeryMode ? 'cevico-glass cevico-surgery-ink' : ''"
            :style="{ background: isSurgeryMode ? surgeryGrad : theme.action, '--surg-text': surgeryInk }"
            @click="openCreateOnDay(new Date())"
          >
            <span class="i-lucide-plus text-sm" />
            {{ isSurgeryMode ? 'Agendar cirurgia' : 'Nova consulta' }}
          </button>
        </div>

        <!-- Navegação -->
        <div class="flex items-center gap-1 sm:ml-auto">
          <button
            class="w-8 h-8 flex items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-alpha-1 i-lucide-chevron-left"
            @click="step(-1)"
          />
          <!-- calendário interativo: clica no período e escolhe a data -->
          <div class="relative">
            <button
              class="text-sm font-medium text-n-slate-12 min-w-[170px] text-center px-2 py-1 rounded-lg hover:bg-n-alpha-1 flex items-center justify-center gap-1.5"
              title="Clique para escolher a data num calendário"
              @click="toggleDatePicker"
            >
              {{ navLabel }}
              <span class="i-lucide-chevron-down text-xs text-n-slate-9" />
            </button>
            <div
              v-if="showDatePicker"
              class="absolute left-1/2 -translate-x-1/2 top-10 z-40 w-72 bg-n-solid-1 border border-n-weak rounded-3xl shadow-2xl p-4"
            >
              <div class="flex items-center justify-between mb-2">
                <button class="w-7 h-7 flex items-center justify-center rounded-full hover:bg-n-alpha-1 i-lucide-chevron-left text-n-slate-10" @click="pickerCursor = addMonths(pickerCursor, -1)" />
                <p class="text-sm font-bold text-n-slate-12">{{ pickerLabel }}</p>
                <button class="w-7 h-7 flex items-center justify-center rounded-full hover:bg-n-alpha-1 i-lucide-chevron-right text-n-slate-10" @click="pickerCursor = addMonths(pickerCursor, 1)" />
              </div>
              <div class="grid grid-cols-7 mb-1">
                <span v-for="wd in WEEKDAYS" :key="'p' + wd" class="text-center text-[10px] font-semibold text-n-slate-9">{{ wd.charAt(0) }}</span>
              </div>
              <div v-for="(week, wi) in pickerWeeks" :key="'pw' + wi" class="grid grid-cols-7">
                <button
                  v-for="day in week"
                  :key="'pd' + day.toISOString()"
                  class="h-8 w-8 mx-auto flex items-center justify-center rounded-full text-xs transition-colors"
                  :class="[
                    isSameMonth(day, pickerCursor) ? 'text-n-slate-12 hover:bg-n-alpha-2' : 'text-n-slate-8 hover:bg-n-alpha-1',
                    isSameDay(day, cursor) ? 'text-white font-bold' : '',
                  ]"
                  :style="isSameDay(day, cursor) ? { background: isSurgeryMode ? surgeryGrad : theme.pill, color: isSurgeryMode ? surgeryInk : '#fff' } : (isToday(day) ? { boxShadow: `inset 0 0 0 1.5px ${theme.ring}` } : {})"
                  @click="pickDate(day)"
                >
                  {{ day.getDate() }}
                </button>
              </div>
              <button
                class="w-full mt-2 text-xs font-medium py-1.5 rounded-xl text-white"
                :style="{ background: theme.primary }"
                @click="pickDate(new Date())"
              >
                Hoje
              </button>
            </div>
          </div>
          <button
            class="w-8 h-8 flex items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-alpha-1 i-lucide-chevron-right"
            @click="step(1)"
          />
          <button
            class="ml-1 text-xs font-medium px-2.5 py-1.5 rounded-lg text-white"
            :style="{ background: theme.primary }"
            @click="goToday"
          >
            Hoje
          </button>
        </div>
      </div>

      <!-- Linha 2: pré-definições SEMPRE alinhadas em linha (rola de lado se faltar espaço) -->
      <div class="flex items-center gap-2 overflow-x-auto pb-0.5" style="scrollbar-width: thin">
        <!-- Visões: Mês / Semana / Dia -->
        <div class="flex items-center bg-n-solid-2 border border-n-weak rounded-xl p-0.5 gap-0.5 flex-shrink-0">
          <button
            v-for="m in VIEW_MODES"
            :key="m.key"
            class="flex items-center gap-1.5 px-3 h-7 rounded-lg text-xs font-medium transition-colors"
            :class="viewMode === m.key ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
            :style="viewMode === m.key ? { background: theme.pill } : {}"
            @click="viewMode = m.key"
          >
            <span :class="m.icon" class="text-sm" />
            {{ m.label }}
          </button>
        </div>

        <!-- Trilho: Consultas | Cirurgias (agenda paralela, azul claro vítreo) -->
        <div
          class="flex items-center rounded-xl p-0.5 gap-0.5 border-2 transition-colors flex-shrink-0"
          :class="isSurgeryMode ? 'bg-sky-400/10' : 'bg-n-solid-2'"
          :style="{ borderColor: isSurgeryMode ? theme.ring : 'var(--n-weak, rgba(148,163,184,0.3))' }"
        >
          <button
            class="flex items-center gap-1.5 px-3 h-7 rounded-lg text-xs font-medium transition-colors"
            :class="!isSurgeryMode ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
            :style="!isSurgeryMode ? { background: theme.pill } : {}"
            @click="agendaMode = 'consultas'"
          >
            <span class="i-lucide-stethoscope text-sm" />
            Consultas
          </button>
          <button
            class="flex items-center gap-1.5 px-3 h-7 rounded-lg text-xs font-semibold transition-colors"
            :class="isSurgeryMode ? 'text-white cevico-glass cevico-surgery-ink' : 'text-n-slate-11 hover:bg-n-alpha-1'"
            :style="isSurgeryMode ? { background: surgeryGrad, '--surg-text': surgeryInk } : {}"
            @click="agendaMode = 'cirurgias'"
          >
            <span class="i-lucide-slice text-sm" />
            Cirurgias
          </button>
        </div>

        <div class="flex items-center gap-2 ml-auto flex-shrink-0">
          <!-- consultas = janelas dos médicos · cirurgias = janela da SALA CIRÚRGICA -->
          <button
            v-if="!isSurgeryMode"
            class="flex items-center gap-1.5 text-xs font-medium px-3 py-2 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 transition-colors whitespace-nowrap"
            title="Janelas de avaliação dos médicos"
            @click="showWindowsModal = true"
          >
            <span class="i-lucide-clock text-sm" />
            Janelas dos médicos
          </button>
          <button
            v-else
            class="flex items-center gap-1.5 text-xs font-medium px-3 py-2 rounded-lg border text-n-slate-11 hover:bg-n-alpha-1 transition-colors whitespace-nowrap"
            :style="{ borderColor: theme.ring + '60' }"
            title="Dias e horários em que a sala cirúrgica de cada clínica está disponível"
            @click="openSurgeryWindowsModal"
          >
            <span class="i-lucide-clock text-sm" />
            Janela da sala cirúrgica
          </button>
          <!-- 🎨 tema do ambiente (admin) -->
          <div v-if="isAdmin" class="relative">
            <button
              class="w-9 h-9 flex items-center justify-center rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
              title="Tema do ambiente (Santorini, Flor del Mar...)"
              @click="showThemeMenu = !showThemeMenu"
            >
              <span class="i-lucide-palette text-sm" />
            </button>
            <div
              v-if="showThemeMenu"
              class="absolute right-0 top-11 z-30 w-56 bg-n-solid-1 border border-n-weak rounded-xl shadow-2xl p-1.5 space-y-0.5"
            >
              <p class="text-[10px] font-semibold text-n-slate-9 uppercase px-2 pt-1">Tema dos ambientes</p>
              <button
                v-for="t in ALL_THEMES"
                :key="t.key"
                class="w-full flex items-center gap-2 px-2 py-1.5 rounded-lg text-left text-xs hover:bg-n-alpha-1 disabled:opacity-50"
                :disabled="isSavingTheme"
                @click="setTheme(t.key)"
              >
                <span class="w-5 h-5 rounded-full flex-shrink-0" :style="{ background: t.primary }" />
                <span class="flex-1">
                  <span class="font-semibold text-n-slate-12">{{ t.emoji }} {{ t.label }}</span>
                  <span class="block text-[10px] text-n-slate-9 leading-tight">{{ t.desc }}</span>
                </span>
                <span v-if="theme.key === t.key" class="i-lucide-check text-sm text-green-500" />
              </button>
            </div>
          </div>
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
        </div>
      </div>
      </div>

      </div>
    </div>

    <!-- Loading -->
    <div v-if="isLoading" class="flex justify-center items-center flex-1">
      <Spinner :size="32" class="text-n-brand" />
    </div>

    <!-- ÁREA ROLÁVEL: KPIs + ocupação + calendário (cabeçalho acima fica FIXO) -->
    <div v-else class="flex-1 min-h-0 overflow-y-auto" :style="isSurgeryMode ? { boxShadow: `inset 0 0 0 2px ${theme.key === 'cevico' ? 'rgba(56,189,248,0.3)' : theme.ring + '4D'}` } : {}">
      <div class="px-4 sm:px-6 pt-4 max-w-[1440px] mx-auto">
      <!-- KPIs no estilo do Dashboard -->
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <div class="rounded-xl px-4 py-3 text-white shadow" :class="isSurgeryMode ? 'cevico-glass cevico-surgery-ink' : ''" :style="{ background: isSurgeryMode ? surgeryGrad : theme.primary, '--surg-text': surgeryInk }">
          <p class="text-[11px] font-medium text-white/80">{{ isSurgeryMode ? 'Cirurgias hoje' : 'Consultas hoje' }}</p>
          <p class="text-xl font-bold leading-tight">{{ kpiToday }}</p>
        </div>
        <div
          class="rounded-xl px-4 py-3 shadow"
          :class="isSurgeryMode ? 'cevico-glass' : 'text-white'"
          :style="isSurgeryMode
            ? { background: theme.surgerySoft, color: theme.surgerySoftText }
            : { background: theme.pill }"
        >
          <p class="text-[11px] font-medium" :style="isSurgeryMode ? { color: theme.surgerySoftText, opacity: 0.85 } : { color: 'rgba(255,255,255,0.8)' }">Nesta semana</p>
          <p class="text-xl font-bold leading-tight">{{ kpiWeek }}</p>
        </div>
        <template v-if="!isSurgeryMode">
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
        </template>
        <!-- trilho de cirurgias: contagem por LOCAL (clínica parceira) -->
        <template v-else>
          <div
            v-for="loc in surgeryLocations.slice(0, 2)"
            :key="loc.key"
            class="rounded-xl px-4 py-3 text-left shadow border"
            :style="{ backgroundColor: loc.color + '14', borderColor: loc.color + '50' }"
          >
            <p class="text-[11px] font-medium flex items-center gap-1.5" :style="{ color: loc.color }">
              <span class="w-2 h-2 rounded-full" :style="{ backgroundColor: loc.color }" />
              {{ loc.label }} — no mês
            </p>
            <p class="text-xl font-bold leading-tight" :style="{ color: loc.color }">
              {{ kpiByUnitMonth[loc.key] || 0 }}
            </p>
          </div>
        </template>
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
          <span v-if="isSurgeryMode" class="text-[10px] text-n-slate-9 ml-auto hidden sm:block">
            🟢 com vagas · 🟡 enchendo · 🔴 quase cheia — cadeados fora da conta
          </span>
          <span v-else class="text-[10px] text-n-slate-9 ml-auto hidden sm:flex items-center gap-2.5">
            <span v-for="m in MODALITIES" :key="m.key" class="flex items-center gap-1">
              <span class="w-2 h-2 rounded-full" :style="{ background: m.color }" />{{ m.label }}
            </span>
            <span>— cadeados fora da conta</span>
          </span>
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div>
            <div class="flex items-center justify-between text-xs mb-1">
              <span class="text-n-slate-11">Dia <span class="text-n-slate-9">({{ occDayLabel }})</span></span>
              <span class="font-bold text-n-slate-12">{{ occDay.total ? occDay.pct + '%' : '—' }}</span>
            </div>
            <div class="h-2.5 bg-n-alpha-1 rounded-full overflow-hidden flex">
              <template v-if="occDay.total && occSegments(occDay)">
                <div
                  v-for="s in occSegments(occDay)"
                  :key="s.key"
                  class="h-full transition-all"
                  :style="{ width: Math.max(s.pct, 2) + '%', background: s.color }"
                  :title="`${s.label}: ${s.count} bloco(s)`"
                />
              </template>
              <div
                v-else-if="occDay.total"
                class="h-full rounded-full transition-all"
                :style="{ width: Math.max(occDay.pct, 3) + '%', background: occColor(occDay.pct) }"
              />
            </div>
            <p class="text-[10px] text-n-slate-9 mt-0.5">
              {{ occDay.total ? `${occDay.filled} de ${occDay.total} blocos ocupados` : 'sem janela neste dia' }}
              <template v-if="occCaption(occDay)"> · {{ occCaption(occDay) }}</template>
            </p>
          </div>
          <div>
            <div class="flex items-center justify-between text-xs mb-1">
              <span class="text-n-slate-11">Semana <span class="text-n-slate-9">({{ occWeekLabel }})</span></span>
              <span class="font-bold text-n-slate-12">{{ occWeek.total ? occWeek.pct + '%' : '—' }}</span>
            </div>
            <div class="h-2.5 bg-n-alpha-1 rounded-full overflow-hidden flex">
              <template v-if="occWeek.total && occSegments(occWeek)">
                <div
                  v-for="s in occSegments(occWeek)"
                  :key="s.key"
                  class="h-full transition-all"
                  :style="{ width: Math.max(s.pct, 2) + '%', background: s.color }"
                  :title="`${s.label}: ${s.count} bloco(s)`"
                />
              </template>
              <div
                v-else-if="occWeek.total"
                class="h-full rounded-full transition-all"
                :style="{ width: Math.max(occWeek.pct, 3) + '%', background: occColor(occWeek.pct) }"
              />
            </div>
            <p class="text-[10px] text-n-slate-9 mt-0.5">
              {{ occWeek.total ? `${occWeek.filled} de ${occWeek.total} blocos ocupados` : 'sem janelas na semana' }}
              <template v-if="occCaption(occWeek)"> · {{ occCaption(occWeek) }}</template>
            </p>
          </div>
          <div>
            <div class="flex items-center justify-between text-xs mb-1">
              <span class="text-n-slate-11">Mês <span class="text-n-slate-9">({{ occMonthLabel }})</span></span>
              <span class="font-bold text-n-slate-12">{{ occMonth.total ? occMonth.pct + '%' : '—' }}</span>
            </div>
            <div class="h-2.5 bg-n-alpha-1 rounded-full overflow-hidden flex">
              <template v-if="occMonth.total && occSegments(occMonth)">
                <div
                  v-for="s in occSegments(occMonth)"
                  :key="s.key"
                  class="h-full transition-all"
                  :style="{ width: Math.max(s.pct, 2) + '%', background: s.color }"
                  :title="`${s.label}: ${s.count} bloco(s)`"
                />
              </template>
              <div
                v-else-if="occMonth.total"
                class="h-full rounded-full transition-all"
                :style="{ width: Math.max(occMonth.pct, 3) + '%', background: occColor(occMonth.pct) }"
              />
            </div>
            <p class="text-[10px] text-n-slate-9 mt-0.5">
              {{ occMonth.total ? `${occMonth.filled} de ${occMonth.total} blocos ocupados` : 'sem janelas no mês' }}
              <template v-if="occCaption(occMonth)"> · {{ occCaption(occMonth) }}</template>
            </p>
          </div>
        </div>
      </div>
      </div>

    <!-- ══ VISÃO MENSAL ══ -->
    <div v-if="viewMode === 'month'" class="p-3 sm:p-5 max-w-[1440px] mx-auto w-full">
      <div class="grid grid-cols-7 gap-px mb-px">
        <div v-for="wd in WEEKDAYS" :key="wd" class="text-center text-xs font-medium text-n-slate-10 py-1.5">
          {{ wd }}
        </div>
      </div>
      <div class="grid gap-px">
        <div v-for="(week, wi) in weeks" :key="wi" class="grid grid-cols-7 gap-px">
          <div
            v-for="day in week"
            :key="day.toISOString()"
            class="border border-n-weak rounded-lg p-1.5 flex flex-col min-h-[104px] max-h-[160px] overflow-hidden cursor-pointer transition-colors hover:border-n-brand/50"
            :class="[
              inMonth(day) ? 'bg-n-solid-1' : 'bg-n-alpha-1 opacity-60',
              isDayOff(day) ? 'opacity-50' : '',
            ]"
            title="Abrir a semana deste dia"
            @click="goToWeek(day)"
          >
            <div class="flex items-center justify-between flex-shrink-0 mb-1">
              <span
                class="text-xs w-5 h-5 flex items-center justify-center rounded-full"
                :class="isToday(day) ? 'text-white font-semibold' : (inMonth(day) ? 'text-n-slate-11' : 'text-n-slate-9')"
                :style="isToday(day) ? { background: theme.primary } : {}"
              >
                {{ day.getDate() }}
              </span>
              <span v-if="isDayOff(day)" class="i-lucide-lock text-[10px]" :class="isDayBlocked(day) ? 'text-red-400' : 'text-n-slate-8'" :title="isDayBlocked(day) ? 'Dia fechado' : 'Sem agenda de avaliação'" />
              <span v-else class="flex items-center gap-0.5">
                <span
                  v-for="w in windowsForDay(day)"
                  :key="(w.doctor || w.unit) + w.start"
                  class="w-1.5 h-1.5 rounded-full"
                  :style="{ backgroundColor: winColor(w) }"
                  :title="`${winTitle(w)} — ${w.start}`"
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

    <!-- ══ VISÃO SEMANAL ══ grade horária estilo Google: horas à esquerda,
         célula vazia = 1 clique agenda, arrastar consulta = reagendar -->
    <div v-else-if="viewMode === 'week'" class="p-3 sm:p-5 max-w-[1440px] mx-auto w-full">
      <div class="overflow-x-auto">
      <div class="min-w-[760px] border border-n-weak rounded-xl overflow-hidden bg-n-solid-1">
        <!-- Cabeçalho: dias da semana -->
        <div class="grid bg-n-solid-2" style="grid-template-columns: 52px repeat(7, 1fr)">
          <div class="border-b border-n-weak" />
          <button
            v-for="day in weekDays"
            :key="'h' + day.toISOString()"
            class="flex flex-col items-center py-2 border-b border-l border-n-weak hover:bg-n-alpha-1"
            :class="isDayOff(day) ? 'opacity-50' : ''"
            title="Agendar neste dia"
            @click="!isDayOff(day) && openCreateOnDay(day)"
          >
            <span class="text-[10px] font-medium text-n-slate-10 uppercase">{{ WEEKDAYS[day.getDay()] }}</span>
            <span
              class="text-sm w-7 h-7 flex items-center justify-center rounded-full font-semibold"
              :class="isToday(day) ? 'text-white' : 'text-n-slate-12'"
              :style="isToday(day) ? { background: theme.primary } : {}"
            >
              {{ day.getDate() }}
            </span>
            <span v-if="isDayOff(day)" class="text-[9px] flex items-center gap-0.5" :class="isDayBlocked(day) ? 'text-red-400' : 'text-n-slate-9'">
              <span class="i-lucide-lock text-[9px]" /> {{ isDayBlocked(day) ? 'Fechado' : 'Bloqueado' }}
            </span>
            <span v-else class="flex items-center gap-0.5 flex-wrap justify-center px-0.5">
              <span
                v-for="w in windowsForDay(day)"
                :key="(w.doctor || w.unit) + w.start"
                class="text-[8px] px-1 py-px rounded-full font-semibold text-white"
                :style="{ backgroundColor: winColor(w) }"
                :title="`${winTitle(w)} — ${w.start} às ${w.end} (${winUnitLabel(w)})`"
              >
                {{ w.doctor ? DOCTORS.find(d => d.name === w.doctor)?.short : surgeryLocationLabel(w.unit) }}
              </span>
              <span
                v-if="showOccupancy && dayOccupancy(day)"
                class="text-[9px] font-bold"
                :style="{ color: occColor(dayOccupancy(day).pct) }"
              >{{ dayOccupancy(day).pct }}%</span>
            </span>
          </button>
        </div>

        <!-- Linhas de hora -->
        <div
          v-for="hour in HOURS"
          :key="hour"
          class="grid"
          style="grid-template-columns: 52px repeat(7, 1fr)"
        >
          <div class="text-right pr-2 pt-1 text-[11px] text-n-slate-9 font-medium border-t border-n-weak">
            {{ String(hour).padStart(2, '0') }}:00
          </div>
          <div
            v-for="day in weekDays"
            :key="day.toISOString() + hour"
            class="relative border-t border-l border-n-weak h-12 transition-colors"
            :class="[
              isDayOff(day) ? 'bg-n-alpha-1' : 'cursor-pointer hover:bg-n-alpha-1',
              dragOverDay === dateKey(day) && !isDayOff(day) ? 'bg-amber-400/10' : '',
            ]"
            :title="isDayOff(day) ? '' : 'Clique para agendar por volta das ' + String(hour).padStart(2, '0') + 'h (a altura do clique define a meia hora)'"
            @click="!isDayOff(day) && openCreateAtPoint(day, hour, $event)"
            @dragover.prevent="dragTask && !isDayOff(day) && (dragOverDay = dateKey(day))"
            @dragleave="dragOverDay === dateKey(day) && (dragOverDay = '')"
            @drop.prevent="onDropCell(day, hour)"
          >
            <!-- bloco PROPORCIONAL: 15 min = 25% da hora (o espaço livre fica evidente) -->
            <button
              v-for="(task, ti) in tasksAtDayHour(day, hour)"
              :key="task.id"
              draggable="true"
              class="absolute text-left rounded-md border px-1 leading-tight cursor-grab active:cursor-grabbing hover:opacity-90 overflow-hidden flex items-center gap-1"
              :class="task.attendance === 'missed' ? 'opacity-60' : ''"
              :style="{ ...weekBlockStyle(task, ti), borderColor: dotColor(task) + '80', backgroundColor: dotColor(task) + '22' }"
              :title="`${chipTime(task)} · ${displayName(task)} (${taskDuration(task)} min) · clique abre, arraste reagenda`"
              @dragstart="onDragStart(task)"
              @click.stop="openEdit(task)"
            >
              <span class="text-[9px] font-bold flex-shrink-0" :style="{ color: dotColor(task) }">{{ chipTime(task) }}</span>
              <span class="text-[9px] font-medium text-n-slate-12 truncate" :class="task.attendance === 'missed' ? 'line-through' : ''">
                {{ displayName(task) }}
              </span>
              <span v-if="task.attendance === 'attended'" class="text-[8px] text-green-600 flex-shrink-0">✓</span>
              <span v-else-if="task.attendance === 'missed'" class="text-[8px] text-red-500 flex-shrink-0">✗</span>
              <span v-else-if="task.attendance === 'attended_not_done'" class="text-[8px] flex-shrink-0">⚠️</span>
              <span v-if="task.surgery_indication === 'indicated'" class="text-[8px] flex-shrink-0">🎯</span>
            </button>
          </div>
        </div>
      </div>
      </div>
      <p class="text-[10px] text-n-slate-9 mt-2 text-center">
        Clique num espaço vazio para agendar naquele horário · arraste uma consulta para outro dia/hora para reagendar
      </p>
    </div>

    <!-- ══ VISÃO DIÁRIA ══ (largura pensada p/ tablet e notebook) -->
    <div v-else class="p-3 sm:p-5">
      <div class="max-w-4xl mx-auto">
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
        <div v-else-if="windowsForDay(cursor).length || dayViewTasks.length" class="flex items-center justify-end gap-2 mb-3 flex-wrap">
          <button
            v-if="dayViewTasks.length"
            class="flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-lg text-white hover:opacity-90 shadow"
            :style="{ background: theme.accent }"
            title="Abre a lista do dia pronta para imprimir ou salvar em PDF"
            @click="printDayList"
          >
            <span class="i-lucide-printer text-xs" />
            Imprimir lista (PDF)
          </button>
          <button
            v-if="isAdmin && windowsForDay(cursor).length"
            class="flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-10 hover:text-red-500 hover:bg-n-alpha-1 transition-colors"
            title="Fechar o dia inteiro (feriado, congresso, folga...)"
            @click="toggleBlockDay(cursor)"
          >
            <span class="i-lucide-lock text-xs" />
            Fechar este dia
          </button>
        </div>

        <!-- Janelas de avaliação do dia (só no trilho de consultas) -->
        <div v-for="win in (isDayBlocked(cursor) ? [] : windowsForDay(cursor))" :key="(win.doctor || win.unit) + win.start" class="rounded-2xl border-2 bg-n-solid-1 overflow-hidden mb-4" :style="{ borderColor: winColor(win) + '40' }">
          <div class="h-1 w-full" :style="{ background: winColor(win) }" />
          <div class="p-4">
            <div class="flex items-center gap-2 flex-wrap mb-3">
              <span class="w-7 h-7 rounded-lg flex items-center justify-center" :style="{ background: winColor(win) }">
                <span :class="win.doctor ? 'i-lucide-stethoscope' : 'i-lucide-slice'" class="text-white text-sm" />
              </span>
              <p class="text-sm font-bold text-n-slate-12">{{ winTitle(win) }}</p>
              <span class="text-[10px] px-2 py-0.5 rounded-full font-medium" :style="{ backgroundColor: winColor(win) + '1A', color: winColor(win) }">
                {{ winUnitLabel(win) }}
              </span>
              <span class="text-xs text-n-slate-10"><template v-if="win.turno">{{ win.turno }} · </template>{{ win.start }} às {{ win.end }} · blocos de {{ win.block }} min</span>
              <span
                class="text-[10px] px-2 py-0.5 rounded-full font-bold text-white ml-auto"
                :style="{ backgroundColor: occColor(winOccupancy(cursor, win).pct) }"
                :title="`${winOccupancy(cursor, win).filled} de ${winOccupancy(cursor, win).total} blocos ocupados`"
              >
                {{ winOccupancy(cursor, win).pct }}% ocupado
              </span>
            </div>
            <!-- 4 horários por linha: blocos grandes, agenda mais vertical -->
            <div class="grid grid-cols-4 gap-2">
              <template v-for="slot in slotsFor(win)" :key="slot">
                <!-- ocupado (com encaixe: "+" agenda outro paciente no mesmo horário) -->
                <span v-if="taskAtSlot(cursor, win, slot)" class="relative group min-w-0">
                  <button
                    class="w-full rounded-lg px-1.5 py-1.5 text-[11px] font-medium text-white text-left truncate hover:opacity-90"
                    :style="{ background: winColor(win) }"
                    :title="tasksAtSlotAll(cursor, win, slot).map(displayName).join(' + ')"
                    @click="openEdit(taskAtSlot(cursor, win, slot))"
                  >
                    {{ slot }} · {{ displayName(taskAtSlot(cursor, win, slot)) }}
                    <span v-if="tasksAtSlotAll(cursor, win, slot).length > 1" class="font-bold">
                      +{{ tasksAtSlotAll(cursor, win, slot).length - 1 }}
                    </span>
                  </button>
                  <button
                    class="absolute -top-1.5 -right-1.5 w-4 h-4 rounded-full bg-n-solid-3 border border-n-weak items-center justify-center hidden group-hover:flex hover:bg-n-alpha-2"
                    title="Encaixe: agendar OUTRO paciente neste mesmo horário"
                    @click.stop="openCreateSlot(cursor, win, slot)"
                  >
                    <span class="i-lucide-plus text-[9px] text-n-slate-10" />
                  </button>
                </span>
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
                    :style="{ borderColor: winColor(win) + '60' }"
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
            :class="isSurgeryMode ? 'cevico-surgery-ink' : ''"
            :style="{ background: isSurgeryMode ? surgeryGrad : theme.primary, '--surg-text': surgeryInk }"
            @click="openCreateOnDay(cursor)"
          >
            {{ isSurgeryMode ? '+ Agendar cirurgia' : '+ Agendar consulta' }}
          </button>
        </div>
        <template v-if="dayViewTasks.length">
          <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-2 mt-2">
            Linha do tempo do dia
            <span class="normal-case font-normal">— cada bloco ocupa o espaço do seu tempo (consulta 15 min · cirurgia 1h)</span>
          </p>
          <!-- grade PROPORCIONAL: 1h = altura fixa; o bloco mede o tempo dele -->
          <div
            class="relative rounded-xl border border-n-weak bg-n-solid-1 mb-4"
            :class="isDayOff(cursor) ? '' : 'cursor-pointer'"
            :style="{ height: HOURS.length * DAY_ROW_PX + 'px' }"
            title="Clique num espaço vazio para agendar naquele horário"
            @click.self="onDayGridClick"
          >
            <div
              v-for="(hour, hi) in HOURS"
              :key="'linha' + hour"
              class="absolute left-0 right-0 border-t border-n-weak pointer-events-none"
              :style="{ top: hi * DAY_ROW_PX + 'px' }"
            >
              <span class="absolute left-1.5 top-0.5 text-[10px] text-n-slate-9 font-medium">{{ String(hour).padStart(2, '0') }}:00</span>
            </div>
            <button
              v-for="task in gridTasks"
              :key="'bloco' + task.id"
              class="absolute rounded-lg border text-left px-2 py-0.5 overflow-hidden hover:opacity-90 leading-tight"
              :style="{ ...dayBlockStyle(task, gridTasks), borderColor: dotColor(task), backgroundColor: dotColor(task) + '22' }"
              :title="`${chipTime(task)} · ${displayName(task)} (${taskDuration(task)} min)`"
              @click.stop="openEdit(task)"
            >
              <span class="text-[10px] font-bold" :style="{ color: dotColor(task) }">{{ chipTime(task) }}</span>
              <span class="text-[10px] font-medium text-n-slate-12 ml-1">{{ displayName(task) }}</span>
              <span v-if="task.attendance === 'attended'" class="text-[9px] text-green-600">✓</span>
              <span v-else-if="task.attendance === 'missed'" class="text-[9px] text-red-500">✗</span>
              <span v-else-if="task.attendance === 'attended_not_done'" class="text-[9px]">⚠️</span>
            </button>
          </div>

          <!-- Conferência do dia: os cards completos com os botões -->
          <div class="flex items-center gap-2 mb-2 mt-1 flex-wrap">
            <p class="text-sm font-bold text-n-slate-12 flex items-center gap-1.5">
              <span class="w-6 h-6 rounded-lg flex items-center justify-center" :style="{ background: isSurgeryMode ? surgeryGrad : theme.primary }">
                <span class="i-lucide-clipboard-check text-white text-xs" :style="isSurgeryMode ? { color: surgeryInk } : {}" />
              </span>
              Conferência {{ isSurgeryMode ? 'das Cirurgias' : 'das Consultas' }} do dia
            </p>
            <span
              v-if="dayViewTasks.filter(t => !t.attendance).length"
              class="text-[10px] px-2 py-0.5 rounded-full font-bold bg-amber-500/15 text-amber-600"
            >
              {{ dayViewTasks.filter(t => !t.attendance).length }} pendente(s)
            </span>
            <span v-else class="text-[10px] px-2 py-0.5 rounded-full font-bold bg-green-500/15 text-green-600">
              tudo conferido ✓
            </span>
          </div>
          <div class="space-y-1.5">
              <div
                v-for="task in dayViewTasks"
                :key="task.id"
                class="w-full text-left rounded-xl border-2 px-3 py-2.5 transition-colors cursor-pointer"
                :class="task.attendance === 'missed' ? 'opacity-75' : ''"
                :style="{ borderColor: dotColor(task) + '60', backgroundColor: dotColor(task) + '10' }"
                @click="openEdit(task)"
              >
                <div class="flex items-center gap-2 flex-wrap">
                  <span class="text-xs font-bold" :style="{ color: dotColor(task) }">{{ chipTime(task) }}</span>
                  <span class="text-sm font-semibold text-n-slate-12" :class="task.attendance === 'missed' ? 'line-through' : ''">
                    {{ displayName(task) }}
                  </span>
                  <span v-if="unitOf(task)" class="text-[10px] px-2 py-0.5 rounded-full font-medium" :style="{ backgroundColor: dotColor(task) + '1A', color: dotColor(task) }">
                    {{ unitOf(task).label }}
                  </span>
                  <span v-if="task.attendance === 'attended'" class="text-[10px] px-2 py-0.5 rounded-full font-semibold bg-green-500/15 text-green-600">
                    {{ isSurgeryTask(task) ? '✓ Realizada' : '✓ Compareceu' }}
                  </span>
                  <span v-else-if="task.attendance === 'missed'" class="text-[10px] px-2 py-0.5 rounded-full font-semibold bg-red-500/15 text-red-600">
                    {{ isSurgeryTask(task) ? '✗ Não veio' : '✗ Faltou' }}
                  </span>
                  <span v-else-if="task.attendance === 'attended_not_done'" class="text-[10px] px-2 py-0.5 rounded-full font-semibold bg-amber-500/15 text-amber-600">
                    ⚠️ Veio e não fez
                  </span>
                  <!-- 💰 valor do card do CRM + forma de pagamento (SÓ ADMIN) -->
                  <span
                    v-if="isAdmin && isSurgeryTask(task) && task.crm_value"
                    class="text-[10px] px-2 py-0.5 rounded-full font-bold text-white ml-auto"
                    style="background: linear-gradient(135deg, #065F46, #10B981)"
                    :title="task.surgery_payment ? `Forma de pagamento: ${task.surgery_payment}` : 'Valor do card no CRM'"
                  >
                    💰 {{ fmtBRL(task.crm_value) }}<template v-if="task.surgery_payment"> · {{ task.surgery_payment }}</template>
                  </span>
                  <span v-if="task.surgery_indication === 'indicated'" class="text-[10px] px-2 py-0.5 rounded-full font-semibold text-white" style="background: linear-gradient(135deg, #B8860B, #D4A017)">
                    🎯 {{ task.indicated_procedure || 'Cirurgia indicada' }}
                  </span>
                  <span v-else-if="task.surgery_indication === 'not_indicated'" class="text-[10px] px-2 py-0.5 rounded-full font-medium bg-n-alpha-2 text-n-slate-10">
                    Sem indicação
                  </span>
                </div>
                <div class="flex items-center gap-3 mt-1 text-[11px] text-n-slate-10 flex-wrap">
                  <span
                    v-if="!isSurgeryTask(task)"
                    class="text-[10px] font-semibold px-1.5 py-px rounded-full text-white"
                    :style="{ background: modalityOf(task).color }"
                  >{{ modalityOf(task).label }}</span>
                  <span v-if="task.phone" class="flex items-center gap-1"><span class="i-lucide-phone text-[10px]" />{{ task.phone }}</span>
                  <span v-if="task.procedure" class="flex items-center gap-1"><span class="i-lucide-eye text-[10px]" />{{ task.procedure }}</span>
                  <span v-if="task.doctor" class="flex items-center gap-1"><span class="i-lucide-stethoscope text-[10px]" />{{ task.doctor }}</span>
                </div>

                <!-- Conferência do dia: compareceu/faltou → indicação de cirurgia -->
                <div class="flex items-center gap-1.5 mt-2 pt-2 border-t flex-wrap" :style="{ borderColor: dotColor(task) + '30' }" @click.stop>
                  <button
                    class="text-[11px] font-semibold px-2.5 py-1 rounded-lg border transition-colors disabled:opacity-50"
                    :class="task.attendance === 'attended'
                      ? 'bg-green-600 text-white border-green-600'
                      : 'text-green-600 border-green-500/40 hover:bg-green-500/10'"
                    :disabled="savingAttendanceId === task.id"
                    @click="setAttendance(task, 'attended')"
                  >
                    {{ isSurgeryTask(task) ? '✓ Realizada' : '✓ Compareceu' }}
                  </button>
                  <button
                    v-if="isSurgeryTask(task)"
                    class="text-[11px] font-semibold px-2.5 py-1 rounded-lg border transition-colors disabled:opacity-50"
                    :class="task.attendance === 'attended_not_done'
                      ? 'bg-amber-500 text-white border-amber-500'
                      : 'text-amber-600 border-amber-500/40 hover:bg-amber-500/10'"
                    :disabled="savingAttendanceId === task.id"
                    title="O paciente veio, mas a cirurgia não aconteceu — registre o motivo"
                    @click="toggleNoSurgery(task)"
                  >
                    ⚠️ Veio e não fez
                  </button>
                  <button
                    class="text-[11px] font-semibold px-2.5 py-1 rounded-lg border transition-colors disabled:opacity-50"
                    :class="task.attendance === 'missed'
                      ? 'bg-red-600 text-white border-red-600'
                      : 'text-red-500 border-red-500/40 hover:bg-red-500/10'"
                    :disabled="savingAttendanceId === task.id"
                    @click="setAttendance(task, 'missed')"
                  >
                    {{ isSurgeryTask(task) ? '✗ Não veio' : '✗ Faltou' }}
                  </button>
                  <!-- motivo de "veio e não fez" -->
                  <div v-if="noSurgeryReasonId === task.id" class="w-full flex items-center gap-1.5 mt-1.5">
                    <input
                      v-model="noSurgeryReason"
                      class="flex-1 border border-amber-500/40 rounded-lg px-2.5 py-1.5 text-xs bg-n-solid-2 text-n-slate-12 focus:outline-none"
                      placeholder="Qual foi o motivo? (pressão alta, desistiu, exame pendente...)"
                      @keyup.enter="confirmNoSurgery(task)"
                    />
                    <button
                      class="text-xs font-semibold px-3 py-1.5 rounded-lg bg-amber-500 text-white disabled:opacity-50"
                      :disabled="savingAttendanceId === task.id"
                      @click="confirmNoSurgery(task)"
                    >
                      Registrar
                    </button>
                  </div>

                  <template v-if="task.attendance === 'attended' && !isSurgeryTask(task)">
                    <span class="text-n-slate-8 text-[10px]">·</span>
                    <button
                      class="text-[11px] font-semibold px-2.5 py-1 rounded-lg border transition-colors disabled:opacity-50"
                      :class="task.surgery_indication === 'indicated'
                        ? 'text-white border-transparent'
                        : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
                      :style="task.surgery_indication === 'indicated' ? { background: 'linear-gradient(135deg, #B8860B, #D4A017)' } : {}"
                      :disabled="savingAttendanceId === task.id"
                      @click="setIndication(task, 'indicated')"
                    >
                      🎯 Cirurgia indicada
                    </button>
                    <button
                      class="text-[11px] font-medium px-2.5 py-1 rounded-lg border transition-colors disabled:opacity-50"
                      :class="task.surgery_indication === 'not_indicated'
                        ? 'bg-n-slate-11 text-white border-transparent'
                        : 'border-n-weak text-n-slate-10 hover:bg-n-alpha-1'"
                      :disabled="savingAttendanceId === task.id"
                      @click="setIndication(task, 'not_indicated')"
                    >
                      Sem indicação
                    </button>
                  </template>

                  <!-- Indicada → agendar a CIRURGIA no trilho dourado -->
                  <button
                    v-if="!isSurgeryTask(task) && task.surgery_indication === 'indicated'"
                    class="cevico-glass cevico-surgery-ink text-[11px] font-semibold px-2.5 py-1 rounded-lg text-white hover:opacity-90 shadow"
                    :style="{ background: surgeryGrad, '--surg-text': surgeryInk }"
                    title="Abre a Agenda de Cirurgias com os dados do paciente preenchidos"
                    @click="scheduleSurgeryFrom(task)"
                  >
                    📅 Agendar cirurgia
                  </button>
                </div>
                <!-- Escolha do procedimento indicado -->
                <div v-if="indicationPickerId === task.id" class="flex flex-wrap gap-1 mt-1.5" @click.stop>
                  <span class="text-[10px] text-n-slate-10 w-full">Qual procedimento foi indicado?</span>
                  <button
                    v-for="proc in PROCEDURES"
                    :key="proc"
                    class="text-[10px] font-medium px-2 py-1 rounded-lg border border-n-weak text-n-slate-11 hover:text-white hover:border-transparent transition-colors"
                    :disabled="savingAttendanceId === task.id"
                    @click="setIndication(task, 'indicated', proc)"
                    @mouseenter="$event.target.style.background = 'linear-gradient(135deg, #B8860B, #D4A017)'"
                    @mouseleave="$event.target.style.background = ''"
                  >
                    {{ proc }}
                  </button>
                </div>
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
    </div>

    <!-- Modal criar/editar consulta -->
    <div
      v-if="showModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      @click.self="showModal = false"
    >
      <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-md max-h-[90vh] flex flex-col overflow-hidden">
        <div class="h-1.5 w-full flex-shrink-0" :style="{ background: isSurgeryMode ? surgeryGrad : theme.primary }" />
        <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak flex-shrink-0">
          <h2 class="text-base font-semibold text-n-slate-12 flex items-center gap-2">
            <span :class="isSurgeryMode ? 'i-lucide-slice' : 'i-lucide-calendar-plus'" :style="isSurgeryMode ? { color: SURGERY_COLOR } : {}" class="text-n-brand" />
            <template v-if="isSurgeryMode">{{ editingTask ? 'Editar cirurgia' : 'Agendar cirurgia' }}</template>
            <template v-else>{{ editingTask ? 'Editar consulta' : 'Nova consulta' }}</template>
          </h2>
          <div class="flex items-center gap-1.5">
            <button
              v-if="editingTask?.contact_id"
              class="flex items-center gap-1.5 text-[11px] font-semibold text-n-slate-12 hover:text-n-brand"
              title="Abrir o Espaço do Paciente"
              @click="openPatientSpace(editingTask)"
            >
              <PatientSpaceIcon :size="18" />
              Espaço do Paciente
            </button>
            <button class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl" @click="showModal = false" />
          </div>
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
          <!-- Modalidade — só no trilho de consultas -->
          <div v-if="!isSurgeryMode">
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Tipo de consulta</label>
            <div class="flex gap-1.5">
              <button
                v-for="m in MODALITIES"
                :key="m.key"
                type="button"
                class="flex-1 text-xs font-medium px-2 py-1.5 rounded-lg border transition-colors"
                :class="form.modality === m.key ? 'text-white border-transparent' : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
                :style="form.modality === m.key ? { background: m.color } : {}"
                @click="form.modality = m.key"
              >
                {{ m.label }}
              </button>
            </div>
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
            <div v-if="!isSurgeryMode">
              <label class="text-xs font-medium text-n-slate-11 block mb-1">Unidade</label>
              <select
                v-model="form.unit"
                class="w-full border border-n-weak rounded-lg px-2 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              >
                <option v-for="(u, key) in UNITS" :key="key" :value="key">{{ u.label }}</option>
                <option value="">Agenda pessoal (sem unidade)</option>
              </select>
            </div>
            <div v-else>
              <label class="text-xs font-medium text-n-slate-11 mb-1 flex items-center justify-between">
                Local da cirurgia
                <button
                  v-if="isAdmin"
                  class="text-[10px] font-medium hover:underline"
                  :style="{ color: SURGERY_COLOR }"
                  @click="openLocationsModal"
                >
                  gerenciar
                </button>
              </label>
              <select
                v-model="form.unit"
                class="w-full border border-n-weak rounded-lg px-2 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              >
                <option v-for="loc in surgeryLocations" :key="loc.key" :value="loc.key">{{ loc.label }}</option>
                <option value="">A definir</option>
              </select>
            </div>
          </div>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Situação</label>
            <div class="flex items-center bg-n-solid-2 border border-n-weak rounded-xl p-0.5 gap-0.5 w-fit">
              <button
                class="px-3 h-7 rounded-lg text-xs font-medium transition-colors"
                :class="form.status === 'todo' ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
                :style="form.status === 'todo' ? { background: theme.pill } : {}"
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
              :class="isSurgeryMode ? 'cevico-glass cevico-surgery-ink' : ''"
              :style="{ background: isSurgeryMode ? surgeryGrad : theme.primary, '--surg-text': surgeryInk }"
              :disabled="!form.name.trim() || !form.date || isSaving"
              @click="save"
            >
              <template v-if="isSurgeryMode">{{ isSaving ? 'Salvando…' : (editingTask ? 'Salvar cirurgia' : 'Agendar cirurgia') }}</template>
              <template v-else>{{ isSaving ? 'Salvando…' : (editingTask ? 'Salvar consulta' : 'Agendar consulta') }}</template>
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
    <!-- Modal: janela da SALA CIRÚRGICA (clínica + dia + horário + bloco) -->
    <div
      v-if="showSurgeryWindowsModal"
      class="fixed inset-0 z-[55] flex items-center justify-center bg-black/60 p-4"
      @click.self="showSurgeryWindowsModal = false"
    >
      <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-lg max-h-[90vh] flex flex-col overflow-hidden">
        <div class="h-1.5 w-full flex-shrink-0" :style="{ background: surgeryGrad }" />
        <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak flex-shrink-0">
          <h2 class="text-base font-semibold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-clock" :style="{ color: SURGERY_COLOR }" />
            Janela da sala cirúrgica
          </h2>
          <button class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl" @click="showSurgeryWindowsModal = false" />
        </div>
        <div class="flex-1 overflow-y-auto p-5 space-y-3">
          <p class="text-xs text-n-slate-10">
            Dias e horários em que a sala cirúrgica de cada clínica parceira está disponível.
            A ocupação e os blocos livres do trilho de cirurgias vêm daqui.
            <button v-if="isAdmin" class="font-medium hover:underline" :style="{ color: SURGERY_COLOR }" @click="openLocationsModal">
              Gerenciar clínicas →
            </button>
          </p>
          <div v-if="!editSurgeryWindows.length" class="text-center py-6 text-n-slate-10 text-sm">
            Nenhuma janela ainda — adicione a primeira.
          </div>
          <div
            v-for="(w, i) in editSurgeryWindows"
            :key="i"
            class="grid grid-cols-2 sm:grid-cols-6 gap-2 items-center rounded-xl border border-n-weak bg-n-solid-2 p-2.5"
          >
            <select v-model="w.dow" :disabled="!isAdmin" class="border border-n-weak rounded-lg px-1.5 py-1.5 text-xs bg-n-solid-1 text-n-slate-12">
              <option v-for="(d, di) in WEEKDAY_FULL" :key="di" :value="di">{{ d }}</option>
            </select>
            <select v-model="w.location" :disabled="!isAdmin" class="border border-n-weak rounded-lg px-1.5 py-1.5 text-xs bg-n-solid-1 text-n-slate-12">
              <option v-for="loc in surgeryLocations" :key="loc.key" :value="loc.key">{{ loc.label }}</option>
            </select>
            <input v-model="w.start" type="time" :disabled="!isAdmin" class="border border-n-weak rounded-lg px-1.5 py-1 text-xs bg-n-solid-1 text-n-slate-12" />
            <input v-model="w.end" type="time" :disabled="!isAdmin" class="border border-n-weak rounded-lg px-1.5 py-1 text-xs bg-n-solid-1 text-n-slate-12" />
            <select v-model="w.block" :disabled="!isAdmin" class="border border-n-weak rounded-lg px-1.5 py-1.5 text-xs bg-n-solid-1 text-n-slate-12">
              <option :value="10">10 min</option>
              <option :value="15">15 min</option>
              <option :value="20">20 min</option>
              <option :value="30">30 min</option>
              <option :value="60">1 hora</option>
              <option :value="90">1h30</option>
              <option :value="120">2 horas</option>
            </select>
            <button v-if="isAdmin" class="text-n-slate-9 hover:text-red-500 i-lucide-trash-2 text-sm justify-self-center" @click="removeSurgeryWindow(i)" />
          </div>
          <button
            v-if="isAdmin"
            class="text-xs font-medium hover:underline flex items-center gap-1"
            :style="{ color: SURGERY_COLOR }"
            @click="addSurgeryWindow"
          >
            <span class="i-lucide-plus text-xs" />
            Adicionar janela
          </button>
        </div>
        <div v-if="isAdmin" class="px-5 py-4 border-t border-n-weak flex gap-2 flex-shrink-0">
          <button
            class="flex-1 text-white rounded-lg py-2 text-sm font-medium cevico-glass cevico-surgery-ink disabled:opacity-50"
            :style="{ background: surgeryGrad, '--surg-text': surgeryInk }"
            :disabled="isSavingSurgeryWindows"
            @click="saveSurgeryWindows"
          >
            {{ isSavingSurgeryWindows ? 'Salvando…' : 'Salvar janelas' }}
          </button>
          <button class="px-4 border border-n-weak rounded-lg py-2 text-sm text-n-slate-11" @click="showSurgeryWindowsModal = false">
            Cancelar
          </button>
        </div>
      </div>
    </div>

    <!-- Modal: locais de cirurgia (clínicas parceiras) -->
    <div
      v-if="showLocationsModal"
      class="fixed inset-0 z-[55] flex items-center justify-center bg-black/60 p-4"
      @click.self="showLocationsModal = false"
    >
      <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-sm flex flex-col overflow-hidden">
        <div class="h-1.5 w-full flex-shrink-0" :style="{ background: SURGERY_GRAD }" />
        <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak">
          <h2 class="text-base font-semibold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-map-pin" :style="{ color: SURGERY_COLOR }" />
            Locais de cirurgia
          </h2>
          <button class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl" @click="showLocationsModal = false" />
        </div>
        <div class="p-5 space-y-2">
          <p class="text-xs text-n-slate-10">
            Clínicas parceiras onde as cirurgias acontecem (ex.: IOP). Aparecem no campo
            "Local da cirurgia" ao agendar.
          </p>
          <div v-for="(loc, i) in locationsDraft" :key="i" class="flex items-center gap-2">
            <input
              v-model="loc.label"
              class="flex-1 border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none"
              placeholder="Nome da clínica (ex.: IOP)"
            />
            <button class="text-n-slate-9 hover:text-red-500 i-lucide-trash-2 text-sm" @click="removeLocationRow(i)" />
          </div>
          <button
            class="text-xs font-medium hover:underline flex items-center gap-1"
            :style="{ color: SURGERY_COLOR }"
            @click="addLocationRow"
          >
            <span class="i-lucide-plus text-xs" />
            Adicionar local
          </button>
        </div>
        <div class="px-5 py-4 border-t border-n-weak flex gap-2">
          <button
            class="flex-1 text-white rounded-lg py-2 text-sm font-medium cevico-glass cevico-surgery-ink disabled:opacity-50"
            :style="{ background: surgeryGrad, '--surg-text': surgeryInk }"
            :disabled="isSavingLocations"
            @click="saveLocations"
          >
            {{ isSavingLocations ? 'Salvando…' : 'Salvar locais' }}
          </button>
          <button class="px-4 border border-n-weak rounded-lg py-2 text-sm text-n-slate-11" @click="showLocationsModal = false">
            Cancelar
          </button>
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
        <div class="h-1.5 w-full flex-shrink-0" :style="{ background: theme.primary }" />
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

            <!-- Conferência do dia → colunas do CRM (admin) -->
            <div v-if="isAdmin" class="rounded-xl border-2 border-n-weak bg-n-solid-2 p-3.5 space-y-2.5">
              <p class="text-xs font-bold text-n-slate-12 flex items-center gap-1.5">
                <span class="i-lucide-list-checks text-sm" style="color: #B8860B" />
                Conferência do dia → CRM
              </p>
              <p class="text-[11px] text-n-slate-10 leading-relaxed">
                Ao marcar <b>Compareceu / Faltou / Cirurgia indicada</b> na lista do dia, o card do
                paciente move sozinho para a coluna escolhida — e as automações dessa coluna disparam
                (ex.: régua de reagendamento para quem faltou).
              </p>
              <!-- responsáveis + prazo: passou da hora sem conferir → tarefa automática -->
              <div class="rounded-xl border border-amber-500/30 bg-amber-500/5 p-2.5 space-y-2">
                <p class="text-[10px] font-semibold text-n-slate-11">
                  ⏰ Prazo da conferência — sem conferir até o horário, nasce a tarefa
                  "Concluir a conferência do dia" (badge na sidebar + aviso no Meu Painel da responsável)
                </p>
                <div class="grid grid-cols-1 sm:grid-cols-3 gap-2">
                  <div>
                    <label class="text-[10px] font-medium text-n-slate-10 block mb-0.5">Consultas — responsável</label>
                    <select v-model="attendanceOwners.consulta_user_id" class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12">
                      <option value="">Ninguém (desligado)</option>
                      <option v-for="agent in agents" :key="agent.id" :value="String(agent.id)">{{ agent.name }}</option>
                    </select>
                  </div>
                  <div>
                    <label class="text-[10px] font-medium text-n-slate-10 block mb-0.5">Cirurgias — responsável</label>
                    <select v-model="attendanceOwners.cirurgia_user_id" class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12">
                      <option value="">Ninguém (desligado)</option>
                      <option v-for="agent in agents" :key="agent.id" :value="String(agent.id)">{{ agent.name }}</option>
                    </select>
                  </div>
                  <div>
                    <label class="text-[10px] font-medium text-n-slate-10 block mb-0.5">Horário limite</label>
                    <input v-model="attendanceOwners.deadline" type="time" class="w-full border border-n-weak rounded-lg px-2 py-1 text-xs bg-n-solid-1 text-n-slate-12" />
                  </div>
                </div>
              </div>
              <div class="space-y-2">
                <div>
                  <label class="text-[10px] font-medium text-n-slate-10 block mb-0.5">✓ Compareceu → mover card para</label>
                  <select v-model="attendanceStages.attended_stage_id" class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12">
                    <option value="">Não mover</option>
                    <option v-for="s in allCrmStages" :key="s.id" :value="s.id">{{ s.name }} ({{ s.pipeline }})</option>
                  </select>
                </div>
                <div>
                  <label class="text-[10px] font-medium text-n-slate-10 block mb-0.5">✗ Faltou → mover card para</label>
                  <select v-model="attendanceStages.missed_stage_id" class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12">
                    <option value="">Não mover</option>
                    <option v-for="s in allCrmStages" :key="s.id" :value="s.id">{{ s.name }} ({{ s.pipeline }})</option>
                  </select>
                </div>
                <div>
                  <label class="text-[10px] font-medium text-n-slate-10 block mb-0.5">🎯 Cirurgia indicada → mover card para</label>
                  <select v-model="attendanceStages.indicated_stage_id" class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12">
                    <option value="">Não mover</option>
                    <option v-for="s in allCrmStages" :key="s.id" :value="s.id">{{ s.name }} ({{ s.pipeline }})</option>
                  </select>
                </div>
                <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide pt-1">Agenda de Cirurgias</p>
                <div>
                  <label class="text-[10px] font-medium text-n-slate-10 block mb-0.5">🔪 Cirurgia realizada → mover card para</label>
                  <select v-model="attendanceStages.surgery_done_stage_id" class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12">
                    <option value="">Não mover</option>
                    <option v-for="s in allCrmStages" :key="s.id" :value="s.id">{{ s.name }} ({{ s.pipeline }})</option>
                  </select>
                </div>
                <div>
                  <label class="text-[10px] font-medium text-n-slate-10 block mb-0.5">✗ Não veio à cirurgia → mover card para</label>
                  <select v-model="attendanceStages.surgery_missed_stage_id" class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12">
                    <option value="">Não mover</option>
                    <option v-for="s in allCrmStages" :key="s.id" :value="s.id">{{ s.name }} ({{ s.pipeline }})</option>
                  </select>
                </div>
              </div>
              <button
                class="w-full text-white rounded-lg py-2 text-xs font-semibold disabled:opacity-50"
                style="background: linear-gradient(135deg, #B8860B, #D4A017)"
                :disabled="isSavingAttendanceCfg"
                @click="saveAttendanceStages"
              >
                {{ isSavingAttendanceCfg ? 'Salvando…' : 'Salvar conferência do dia' }}
              </button>
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

    <!-- botão + flutuante: caminho principal para agendar consultas -->
    <button
      class="fixed bottom-6 right-6 z-30 w-14 h-14 rounded-full text-white shadow-xl flex items-center justify-center transition-transform hover:scale-110 active:scale-95"
      :style="{ background: theme.primary, boxShadow: '0 10px 26px rgba(0,0,0,.3)' }"
      title="Agendar consulta"
      @click="openCreateFab"
    >
      <span class="i-lucide-plus text-2xl" />
    </button>
  </div>
</template>

<style scoped>
/* tinta do trilho de cirurgias nos temas claros ("cor puxando pro branco"):
   força a cor escura do tema no texto e nos ícones dos elementos claros */
.cevico-surgery-ink,
.cevico-surgery-ink * {
  color: var(--surg-text, #fff) !important;
}

/* efeito "vidro" leve do trilho de cirurgias: brilho interno no topo +
   sombra suave azulada (só box-shadow — não pesa nada) */
.cevico-glass {
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.45),
    inset 0 -1px 0 rgba(2, 132, 199, 0.25),
    0 2px 8px rgba(56, 189, 248, 0.35);
}
</style>
