<script setup>
// 🍎📅 AGENDA no design Apple (item 210, 23/09) — Consultas | Teleconsultas |
// Exames | Cirurgias, cada tipo no seu trilho e na sua cor, visões Mês /
// Semana / Dia (abre na SEMANA). Cada agendamento guarda: nome, telefone,
// problema/exame, dia, horário, médico e unidade (ou local da cirurgia, ou
// "online" na teleconsulta). Criado à mão aqui ou pelo Atendente de
// Agendamento (IA). Peças: kit "iMac G3 + vidro" + _cevico-agenda.scss.
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import AgendaTimeColumn from 'dashboard/components-next/cevico/agenda/AgendaTimeColumn.vue';
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
import CrmAPI from 'dashboard/api/crm';
import {
  DOCTORS, MODALITIES, KINDS, KIND_BY_KEY, ONLINE_UNIT,
  kindFor, kindOf, kindVars, hexToRgbSpaced,
  resolveWindows, resolveBlocked, resolveBlockedDays,
  resolveSurgeryWindows, slotsFor as sharedSlotsFor, dateKey, blockKey, scanAgenda,
} from 'dashboard/helper/cevicoAgenda';

const store = useStore();
const { isAdmin } = useAdmin();
const route = useRoute();
const router = useRouter();

// Espaço do Paciente: consulta amarrada ao contato abre a página única
const openPatientSpace = task => {
  if (!task?.contact_id) return;
  router.push(frontendURL(`accounts/${route.params.accountId}/patient/${task.contact_id}`));
};

const agents = useMapGetter('agents/getAgents');
const currentUser = useMapGetter('getCurrentUser');
const allTasks = useMapGetter('tasks/getTasks');
const crmSettings = useMapGetter('crm/getSettings');

const isLoading = ref(true);
const cursor = ref(new Date()); // data de referência da navegação
const viewMode = ref('week'); // 'month' | 'week' | 'day' — padrão SEMANA
// filtro: 'clinic' (todas) | 'unit:x' | 'doctor:Nome' | 'me' | '<agentId>'
const view = ref('clinic');

// ── OS 4 TRILHOS: consultas | teleconsultas | exames | cirurgias ──
const kind = ref('consultas');
const k = computed(() => kindFor(kind.value)); // o tipo ativo (cor, nome, ícone)
const pageVars = computed(() => kindVars(k.value));
const isSurgeryMode = computed(() => kind.value === 'cirurgias');
const isTele = computed(() => kind.value === 'teleconsultas');
const isPhysical = computed(() => kind.value === 'consultas' || kind.value === 'exames');
const isSurgeryTask = t => t.task_type === 'cirurgia';
const kindVarsOf = key => {
  const kk = KIND_BY_KEY[key];
  return {
    '--k-grad': kk.grad,
    '--k-deep': kk.deep,
    '--k-rgb': hexToRgbSpaced(kk.color),
    '--k-deep-rgb': hexToRgbSpaced(kk.deep),
  };
};
// "Nova consulta" / "Agendar cirurgia" / "Novo exame"…
const newLabel = computed(() =>
  isSurgeryMode.value ? 'Agendar cirurgia' : `${k.value.article === 'o' ? 'Novo' : 'Nova'} ${k.value.noun}`
);
const cap = s => s.charAt(0).toUpperCase() + s.slice(1);

// ── JANELAS DA SALA CIRÚRGICA (clínica parceira + dia + horário + bloco) ──
const surgeryWindows = computed(() => resolveSurgeryWindows(crmSettings.value));
const surgeryWindowsForDay = day => surgeryWindows.value.filter(w => w.dow === day.getDay());
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
// O bloco da janela (médico ou sala) onde o horário cai define a duração.
// Sem janela: consulta 15 · teleconsulta 20 · exame 30 · cirurgia 60.
const DEFAULT_DURATION = { consultas: 15, teleconsultas: 20, exames: 30, cirurgias: 60 };
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
  if (win?.block && kindOf(task) !== 'exames') return Number(win.block);
  return DEFAULT_DURATION[kindOf(task)] || 15;
};

// Locais de cirurgia (clínicas parceiras — IOP etc.)
const DEFAULT_SURGERY_LOCATIONS = [
  { key: 'iop', label: 'IOP' },
  { key: 'ocular_surgery', label: 'Ocular Surgery' },
];
const LOCATION_COLORS = { iop: '#0EA5E9', ocular_surgery: '#64748B' };
const LOCATION_FALLBACK = ['#0EA5E9', '#64748B', '#0284C7', '#818CF8'];
const surgeryLocations = computed(() => {
  const list = crmSettings.value?.surgery_locations;
  const base = Array.isArray(list) && list.length ? list : DEFAULT_SURGERY_LOCATIONS;
  return base.map((l, i) => ({
    ...l,
    color: LOCATION_COLORS[l.key] || LOCATION_FALLBACK[i % LOCATION_FALLBACK.length],
  }));
});
const surgeryLocationOf = task => surgeryLocations.value.find(l => l.key === task.unit) || null;

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
    .replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
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
const WEEKDAY_FULL = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];
const VIEW_MODES = [
  { key: 'month', label: 'Mês', icon: 'i-lucide-calendar' },
  { key: 'week', label: 'Semana', icon: 'i-lucide-calendar-range' },
  { key: 'day', label: 'Dia', icon: 'i-lucide-calendar-check' },
];

// Unidades da clínica (+ "online" da teleconsulta)
const UNITS = {
  tatuape:  { label: 'Tatuapé',      color: '#2563EB' },
  paulista: { label: 'Av. Paulista', color: '#EA580C' },
};
const ONLINE = { label: 'Online', color: '#7C3AED' };

const PROBLEMAS = [
  'Catarata', 'Refrativa', 'Ceratocone', 'Lentes Fácicas',
  'Consulta geral', 'Pós-operatório', 'Plástica ocular', 'Retorno de exames',
];
const EXAMES = [
  'Pentacam', 'Topografia', 'OCT', 'Biometria', 'Paquimetria', 'Campo visual',
  'Retinografia', 'Microscopia especular', 'Mapeamento de retina', 'Aberrometria',
];
const PROCEDURES = [
  'Catarata', 'Refrativa PRK', 'Refrativa Lasik', 'Lente Fácica',
  'Lente de Foco Estendido', 'Trifocal', 'Anel de Ferrara', 'Pterígio',
  'Capsulotomia YAG', 'Outro',
];
const procedureOptions = computed(() => {
  if (form.value.kind === 'exames') return EXAMES;
  if (form.value.kind === 'cirurgias') return PROCEDURES;
  return PROBLEMAS;
});
const procedureLabel = computed(() => {
  if (form.value.kind === 'exames') return 'Exame';
  if (form.value.kind === 'cirurgias') return 'Procedimento';
  return 'Problema';
});

// ── Médicos e janelas de avaliação da clínica ───────────────
const doctorColor = name => DOCTORS.find(d => d.name === name)?.color || '#64748B';
const doctorShort = name => DOCTORS.find(d => d.name === name)?.short || name;
const windows = computed(() => resolveWindows(crmSettings.value));

// horários fechados com o cadeado ({date, time, unit})
const blockedList = computed(() => resolveBlocked(crmSettings.value));
const blockedSet = computed(() => new Set(blockedList.value.map(b => blockKey(b.date, b.time, b.unit))));
const isBlocked = (day, win, slot) => blockedSet.value.has(blockKey(dateKey(day), slot, win.unit));

const isSavingBlock = ref(false);
const toggleBlock = async (day, win, slot) => {
  if (isSavingBlock.value) return;
  isSavingBlock.value = true;
  try {
    const key = { date: dateKey(day), time: slot, unit: win.unit };
    const exists = blockedList.value.some(b => b.date === key.date && b.time === key.time && b.unit === key.unit);
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
const blockedDays = computed(() => new Set(resolveBlockedDays(crmSettings.value)));
const isDayBlocked = day => blockedDays.value.has(dateKey(day));
// teleconsulta pode acontecer em qualquer dia útil, mesmo sem janela
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

// janelas de um dia no trilho ativo: consultas/exames = médicos (com o
// filtro de unidade/médico); cirurgias = sala cirúrgica; teleconsultas = nenhuma
const windowsForDay = day => {
  if (isSurgeryMode.value) return surgeryWindowsForDay(day);
  if (isTele.value) return [];
  return windows.value
    .filter(w => w.dow === day.getDay())
    .filter(w => !activeUnit.value || w.unit === activeUnit.value)
    .filter(w => !activeDoctor.value || w.doctor === activeDoctor.value);
};
const toMin = hm => {
  const [h, m] = hm.split(':').map(Number);
  return h * 60 + m;
};
// faixas para a coluna de horas (semana/dia)
const bandsForDay = day =>
  windowsForDay(day).map(w => ({
    key: (w.doctor || w.unit) + w.start,
    startMin: toMin(w.start),
    endMin: toMin(w.end),
    block: Number(w.block) || 15,
    color: winColor(w),
    label: w.doctor ? doctorShort(w.doctor) : surgeryLocationLabel(w.unit),
    title: `${winTitle(w)} · ${w.start}–${w.end} (${winUnitLabel(w)}) · blocos de ${w.block} min`,
    unit: w.unit,
    doctor: w.doctor || '',
  }));

// agendamentos ocupando um bloco (pode haver ENCAIXE: 2+ no mesmo horário)
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

// ── Edição das janelas (admin) ──
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

// ── FECHAR/reabrir a agenda de um médico (item 76) ──
const closedDoctors = computed(() => crmSettings.value?.agenda_closed_doctors || []);
const isDoctorClosed = name => closedDoctors.value.includes(name);
const togglingDoctor = ref('');
const toggleDoctorClosed = async name => {
  const wasClosed = isDoctorClosed(name);
  togglingDoctor.value = name;
  try {
    const next = wasClosed ? closedDoctors.value.filter(x => x !== name) : [...closedDoctors.value, name];
    await CrmAPI.updateClosedDoctors(next);
    await store.dispatch('crm/fetchSettings');
    useAlert(wasClosed ? `Agenda de ${name} reaberta!` : `Agenda de ${name} fechada — as janelas somem até reabrir.`);
  } catch {
    useAlert('Não consegui atualizar a agenda do médico.');
  } finally {
    togglingDoctor.value = '';
  }
};

// ── etiquetas + resposta de formulário na lista do dia (item 76) ──
const dayDetails = ref({});
const formAnswersTask = ref(null);
const loadDayDetails = async () => {
  const ids = dayViewTasks.value.filter(t => t.contact_id).map(t => t.id);
  if (!ids.length) {
    dayDetails.value = {};
    return;
  }
  try {
    const { data } = await CrmAPI.getAgendaDayDetails(ids);
    dayDetails.value = Object.fromEntries(data.map(d => [d.task_id, d]));
  } catch {
    dayDetails.value = {};
  }
};
watch([viewMode, cursor, kind, allTasks], () => {
  if (viewMode.value === 'day') loadDayDetails();
});
const detailOf = task => dayDetails.value[task.id] || null;
const openFormAnswers = task => {
  const detail = detailOf(task);
  if (detail?.form_response) formAnswersTask.value = { name: displayName(task), detail };
};

// ── Filtro ──
const activeUnit = computed(() => (view.value.startsWith('unit:') ? view.value.slice(5) : null));
const activeDoctor = computed(() => (view.value.startsWith('doctor:') ? view.value.slice(7) : null));
const isPersonalView = computed(() => view.value === 'me' || /^\d+$/.test(view.value));
const isAppointment = t => t.task_type === 'consulta' || t.task_type === 'cirurgia' || t.unit;

// tudo o que está no calendário (canceladas ficam fora; continuam no banco)
const liveTasks = computed(() => allTasks.value.filter(x => x.due_at && !x.canceled_at));
const inKind = t => kindOf(t) === kind.value;

const visibleTasks = computed(() => {
  const list = liveTasks.value;
  if (view.value === 'clinic') return list.filter(isAppointment).filter(inKind);
  if (activeUnit.value) return list.filter(x => x.unit === activeUnit.value).filter(inKind);
  if (activeDoctor.value) return list.filter(x => isAppointment(x) && x.doctor === activeDoctor.value).filter(inKind);
  if (view.value === 'me') return list.filter(x => !x.unit && x.assignee?.id === currentUser.value.id);
  return list.filter(x => !x.unit && x.assignee?.id === Number(view.value));
});

const tasksByDay = computed(() => {
  const map = {};
  visibleTasks.value.forEach(task => {
    const key = format(new Date(task.due_at), 'yyyy-MM-dd');
    (map[key] ||= []).push(task);
  });
  Object.values(map).forEach(arr => arr.sort((a, b) => new Date(a.due_at) - new Date(b.due_at)));
  return map;
});
const dayTasks = day => tasksByDay.value[format(day, 'yyyy-MM-dd')] || [];
const isToday = day => isSameDay(day, new Date());
const inMonth = day => isSameMonth(day, cursor.value);

// ── intervalo visível (mês/semana/dia) → contagem por tipo no seletor ──
const rangeStart = computed(() => {
  if (viewMode.value === 'month') return startOfWeek(startOfMonth(cursor.value), { weekStartsOn: 0 });
  if (viewMode.value === 'week') return startOfWeek(cursor.value, { weekStartsOn: 0 });
  const d = new Date(cursor.value); d.setHours(0, 0, 0, 0); return d;
});
const rangeEnd = computed(() => {
  if (viewMode.value === 'month') return addDays(endOfWeek(endOfMonth(cursor.value), { weekStartsOn: 0 }), 1);
  if (viewMode.value === 'week') return addDays(startOfWeek(cursor.value, { weekStartsOn: 0 }), 7);
  return addDays(rangeStart.value, 1);
});
const kindCounts = computed(() => {
  const out = { consultas: 0, teleconsultas: 0, exames: 0, cirurgias: 0 };
  const s = rangeStart.value.getTime();
  const e = rangeEnd.value.getTime();
  liveTasks.value.filter(isAppointment).forEach(t => {
    const ts = new Date(t.due_at).getTime();
    if (ts >= s && ts < e) out[kindOf(t)] += 1;
  });
  return out;
});
const rangeNoun = computed(() =>
  ({ month: 'no mês', week: 'na semana', day: 'no dia' })[viewMode.value]
);

// ── Calendário interativo (popover do rótulo do período) ──
const showDatePicker = ref(false);
const pickerCursor = ref(new Date());
const toggleDatePicker = () => {
  pickerCursor.value = new Date(cursor.value);
  showDatePicker.value = !showDatePicker.value;
};
const pickerLabel = computed(() =>
  cap(pickerCursor.value.toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' }))
);
const pickerWeeks = computed(() => {
  const start = startOfWeek(startOfMonth(pickerCursor.value), { weekStartsOn: 0 });
  const end = endOfWeek(endOfMonth(pickerCursor.value), { weekStartsOn: 0 });
  const days = [];
  let d = start;
  while (d <= end) { days.push(d); d = addDays(d, 1); }
  const out = [];
  for (let i = 0; i < days.length; i += 7) out.push(days.slice(i, i + 7));
  return out;
});
const pickDate = day => {
  cursor.value = new Date(day);
  showDatePicker.value = false;
};

// ── Navegação ──
const step = dir => {
  if (viewMode.value === 'month') cursor.value = addMonths(cursor.value, dir);
  else if (viewMode.value === 'week') cursor.value = addWeeks(cursor.value, dir);
  else cursor.value = addDays(cursor.value, dir);
};
const goToday = () => { cursor.value = new Date(); };
const stepLabel = computed(() => ({ month: 'mês', week: 'semana', day: 'dia' })[viewMode.value]);

const navLabel = computed(() => {
  if (viewMode.value === 'month') {
    return cap(cursor.value.toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' }));
  }
  if (viewMode.value === 'week') {
    const start = startOfWeek(cursor.value, { weekStartsOn: 0 });
    const end = endOfWeek(cursor.value, { weekStartsOn: 0 });
    const sameMonth = start.getMonth() === end.getMonth();
    const a = start.toLocaleDateString('pt-BR', { day: 'numeric', month: sameMonth ? undefined : 'short' });
    const b = end.toLocaleDateString('pt-BR', { day: 'numeric', month: 'long', year: 'numeric' });
    return `${a} – ${cap(b)}`.replace(' de ', ' de ');
  }
  return cap(cursor.value.toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' }));
});
const navSub = computed(() => {
  if (viewMode.value === 'week') {
    const start = startOfWeek(cursor.value, { weekStartsOn: 0 });
    return `semana ${format(start, 'dd/MM')} – ${format(endOfWeek(cursor.value, { weekStartsOn: 0 }), 'dd/MM')}`;
  }
  if (viewMode.value === 'day') return format(cursor.value, 'dd/MM/yyyy');
  return '';
});

// grade mensal (6 semanas, domingo primeiro)
const weeks = computed(() => {
  const start = startOfWeek(startOfMonth(cursor.value), { weekStartsOn: 0 });
  const end = endOfWeek(endOfMonth(cursor.value), { weekStartsOn: 0 });
  const days = [];
  let d = start;
  while (d <= end) { days.push(d); d = addDays(d, 1); }
  const result = [];
  for (let i = 0; i < days.length; i += 7) result.push(days.slice(i, i + 7));
  return result;
});
const MONTH_MAX = 4;

// dias da semana da visão semanal — "esconder sáb/dom" (item 76)
const hideWeekend = ref(localStorage.getItem('cevico_agenda_hide_weekend') !== '0');
const toggleWeekend = () => {
  hideWeekend.value = !hideWeekend.value;
  localStorage.setItem('cevico_agenda_hide_weekend', hideWeekend.value ? '1' : '0');
};
const weekDays = computed(() => {
  const start = startOfWeek(cursor.value, { weekStartsOn: 0 });
  const days = Array.from({ length: 7 }, (_, i) => addDays(start, i));
  return hideWeekend.value ? days.filter(d => d.getDay() !== 0 && d.getDay() !== 6) : days;
});
const weekGridCols = computed(() => `56px repeat(${weekDays.value.length}, minmax(0, 1fr))`);

// ── grade de horas: o expediente (08–18) esticado até cobrir TUDO o que
//    está marcado no intervalo (nada fica escondido) ──
const WEEK_ROW_PX = 64;
const DAY_ROW_PX = 96;
const hourSpan = (tasks, baseStart, baseEnd) => {
  let start = baseStart;
  let end = baseEnd;
  tasks.forEach(t => {
    const d = new Date(t.due_at);
    const h = d.getHours();
    const endH = Math.ceil((h * 60 + d.getMinutes() + taskDuration(t)) / 60);
    if (h < start) start = h;
    if (endH > end) end = endH;
  });
  return { start: Math.max(6, start), end: Math.min(23, Math.max(end, start + 1)) };
};
const weekTasks = computed(() => weekDays.value.flatMap(d => dayTasks(d)));
const weekSpan = computed(() => hourSpan(weekTasks.value, 8, 18));
const weekHours = computed(() =>
  Array.from({ length: weekSpan.value.end - weekSpan.value.start }, (_, i) => weekSpan.value.start + i)
);
const dayViewTasks = computed(() => dayTasks(cursor.value));
const daySpan = computed(() => hourSpan(dayViewTasks.value, 7, 20));
const dayHours = computed(() =>
  Array.from({ length: daySpan.value.end - daySpan.value.start }, (_, i) => daySpan.value.start + i)
);

// linha de AGORA (atualiza a cada minuto)
const nowMinutes = ref(new Date().getHours() * 60 + new Date().getMinutes());
let nowTimer = null;

// ── Helpers de exibição ──
const displayName = task => (task.title || '').replace(/^(Consulta|Teleconsulta|Exame|Cirurgia):\s*/i, '');
const chipTime = task =>
  new Date(task.due_at).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
const unitOf = task => {
  if (task.unit === ONLINE_UNIT) return ONLINE;
  if (task.unit && UNITS[task.unit]) return UNITS[task.unit];
  if (isSurgeryTask(task)) {
    const loc = surgeryLocationOf(task);
    if (loc) return { label: loc.label, color: loc.color };
  }
  return null;
};
// cor do balão: unidade (Tatuapé/Paulista), local da cirurgia, ou a cor do tipo
const accentOf = task => unitOf(task)?.color || KIND_BY_KEY[kindOf(task)]?.color || '#2563EB';
const evVars = task => ({ '--ev': accentOf(task), '--ev-rgb': hexToRgbSpaced(accentOf(task)) });
const modalityOf = task =>
  MODALITIES.find(m => m.key === (task.modality || 'avaliacao')) || MODALITIES[0];
const kindLabelOf = task => KIND_BY_KEY[kindOf(task)]?.noun || 'consulta';

// ── Ocupação da agenda (% preenchida — dia/semana/mês) ──
// Consultas e exames dividem os MESMOS blocos dos médicos (a ocupação soma
// os dois — é o que o Atendente enxerga ao oferecer horários); cirurgias
// contra a sala cirúrgica; teleconsulta não ocupa bloco físico.
const occWindows = computed(() => {
  if (isSurgeryMode.value) return surgeryWindows.value;
  return windows.value
    .filter(w => !activeUnit.value || w.unit === activeUnit.value)
    .filter(w => !activeDoctor.value || w.doctor === activeDoctor.value);
});
const occTasks = computed(() => {
  const base = liveTasks.value.filter(isAppointment);
  if (isSurgeryMode.value) return base.filter(isSurgeryTask);
  return base
    .filter(t => !isSurgeryTask(t) && t.unit !== ONLINE_UNIT)
    .filter(t => !activeUnit.value || t.unit === activeUnit.value)
    .filter(t => !activeDoctor.value || t.doctor === activeDoctor.value);
});
const occScan = (from, days) =>
  scanAgenda({
    windows: occWindows.value,
    tasks: occTasks.value,
    blockedSet: blockedSet.value,
    blockedDays: blockedDays.value,
    from,
    days,
    freeLimit: 0,
  });
const showOccupancy = computed(() => {
  if (isTele.value || isPersonalView.value) return false;
  return occWindows.value.length > 0;
});
const showOccDetail = ref(false);
const occDay = computed(() => occScan(cursor.value, 1));
const occWeek = computed(() => occScan(startOfWeek(cursor.value, { weekStartsOn: 0 }), 7));
const occMonth = computed(() => occScan(startOfMonth(cursor.value), endOfMonth(cursor.value).getDate()));
const occCurrent = computed(() =>
  ({ month: occMonth.value, week: occWeek.value, day: occDay.value })[viewMode.value]
);
const occRows = computed(() => [
  { key: 'day', label: 'Dia', sub: format(cursor.value, 'dd/MM'), scan: occDay.value },
  { key: 'week', label: 'Semana', sub: `${format(startOfWeek(cursor.value, { weekStartsOn: 0 }), 'dd/MM')}–${format(endOfWeek(cursor.value, { weekStartsOn: 0 }), 'dd/MM')}`, scan: occWeek.value },
  { key: 'month', label: 'Mês', sub: cap(cursor.value.toLocaleDateString('pt-BR', { month: 'long' })), scan: occMonth.value },
]);
const occColor = pct => {
  if (pct >= 80) return '#EF4444';
  if (pct >= 50) return '#D4A017';
  return '#22C55E';
};
const OCC_MODALITIES = MODALITIES.filter(m => m.key !== 'teleconsulta');
const occSegments = scan => {
  if (isSurgeryMode.value || !scan.total) return null;
  return OCC_MODALITIES
    .map(m => ({ ...m, count: scan.byModality?.[m.key] || 0 }))
    .filter(s => s.count > 0)
    .map(s => ({ ...s, pct: Math.round((s.count / scan.total) * 100) }));
};
const occCaption = scan => {
  if (!scan.total) return null;
  const parts = (occSegments(scan) || []).map(s => `${s.label} ${s.pct}%`).join(' · ');
  return parts || null;
};
const dayOccupancy = day => {
  if (isDayOff(day) || !showOccupancy.value) return null;
  if (!occWindows.value.some(w => w.dow === day.getDay())) return null;
  return occScan(day, 1);
};

// rótulos/cores da janela — médicos (consultas) OU sala cirúrgica (cirurgias)
const winColor = win =>
  win.doctor ? doctorColor(win.doctor) : surgeryLocations.value.find(l => l.key === win.unit)?.color || k.value.color;
const winTitle = win => win.doctor || `Sala cirúrgica — ${surgeryLocationLabel(win.unit)}`;
const winUnitLabel = win => (win.doctor ? UNITS[win.unit]?.label : surgeryLocationLabel(win.unit));
const winVars = win => ({ '--w': winColor(win), '--w-rgb': hexToRgbSpaced(winColor(win)), '--w-deep': winColor(win) });
const winOccupancy = (day, win) => {
  const slots = slotsFor(win).filter(s => !isBlocked(day, win, s));
  const filled = slots.filter(s => taskAtSlot(day, win, s)).length;
  const total = slots.length;
  return { filled, total, pct: total ? Math.round((filled / total) * 100) : 0 };
};

// ── KPIs do trilho ativo ──
const clinicTasks = computed(() =>
  liveTasks.value.filter(x => isAppointment(x) && x.status !== 'done').filter(inKind)
);
const kpiToday = computed(() => clinicTasks.value.filter(x => isSameDay(new Date(x.due_at), new Date())).length);
const kpiWeek = computed(() => {
  const start = startOfWeek(new Date(), { weekStartsOn: 0 });
  const end = endOfWeek(new Date(), { weekStartsOn: 0 });
  return clinicTasks.value.filter(x => { const d = new Date(x.due_at); return d >= start && d <= end; }).length;
});
const kpiPlaces = computed(() => {
  const inCursorMonth = clinicTasks.value.filter(x => isSameMonth(new Date(x.due_at), cursor.value));
  if (isTele.value) return [{ key: ONLINE_UNIT, label: 'Online — no mês', color: ONLINE.color, n: inCursorMonth.length }];
  const places = isSurgeryMode.value
    ? surgeryLocations.value.slice(0, 2).map(l => ({ key: l.key, label: l.label, color: l.color }))
    : Object.entries(UNITS).map(([key, u]) => ({ key, label: u.label, color: u.color }));
  return places.map(p => ({ ...p, label: `${p.label} — no mês`, n: inCursorMonth.filter(x => x.unit === p.key).length }));
});

// ── Fetch ──
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
  // deep-links: ?date=AAAA-MM-DD abre o DIA; ?kind=exames abre o trilho;
  // ?view=month|week|day escolhe a visão
  if (route.query.date) {
    const d = new Date(`${route.query.date}T12:00:00`);
    if (!Number.isNaN(d.getTime())) {
      cursor.value = d;
      viewMode.value = 'day';
    }
  }
  if (route.query.kind && KIND_BY_KEY[route.query.kind]) kind.value = route.query.kind;
  if (['month', 'week', 'day'].includes(route.query.view)) viewMode.value = route.query.view;
  if (!agents.value.length) store.dispatch('agents/get');
  await store.dispatch('crm/fetchSettings').catch(() => {});
  fetchTasks();
  loadCrmStages();
  nowTimer = setInterval(() => {
    const n = new Date();
    nowMinutes.value = n.getHours() * 60 + n.getMinutes();
  }, 60000);
});
onBeforeUnmount(() => clearInterval(nowTimer));

// ── Modal criar/editar ──
const showModal = ref(false);
const editingTask = ref(null);
const isSaving = ref(false);
const showDeleteConfirm = ref(false);

const defaultModality = key => ({ consultas: 'avaliacao', teleconsultas: 'teleconsulta', exames: 'exames', cirurgias: '' })[key] || 'avaliacao';
const defaultUnit = key => {
  if (key === 'teleconsultas') return ONLINE_UNIT;
  if (key === 'cirurgias') return surgeryLocations.value[0]?.key || '';
  return activeUnit.value || 'tatuape';
};
const emptyForm = (day, prefill = {}) => {
  const key = prefill.kind || kind.value;
  return {
    kind: key,
    name: prefill.name || '',
    phone: prefill.phone || '',
    procedure: prefill.procedure || '',
    doctor: prefill.doctor || activeDoctor.value || '',
    modality: prefill.modality || defaultModality(key),
    date: format(day || cursor.value, 'yyyy-MM-dd'),
    time: prefill.time || '09:00',
    unit: prefill.unit ?? defaultUnit(key),
    status: 'todo',
    canceled: false,
    description: prefill.description || '',
  };
};
const form = ref(emptyForm());
const formKind = computed(() => kindFor(form.value.kind));
const formVars = computed(() => kindVars(formKind.value));
// trocar o tipo no modal (só ao criar): modalidade e unidade acompanham
const setFormKind = key => {
  if (editingTask.value || form.value.kind === key) return;
  form.value.kind = key;
  form.value.modality = defaultModality(key);
  form.value.unit = defaultUnit(key);
  if (key !== 'consultas' && key !== 'teleconsultas') form.value.procedure = '';
};
const consultaModalities = MODALITIES.filter(m => m.key === 'avaliacao' || m.key === 'retorno');

const openCreateOnDay = (day, prefill = {}) => {
  editingTask.value = null;
  form.value = emptyForm(day, prefill);
  showDeleteConfirm.value = false;
  showModal.value = true;
};
// clique num bloco livre da janela → pré-preenchido com unidade e médico
const openCreateSlot = (day, win, slot) =>
  openCreateOnDay(day, { time: slot, unit: win.unit, doctor: win.doctor });
// clique na coluna de horas (semana/dia)
const onColumnCreate = ({ day, minutes, band }) => {
  const time = `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;
  openCreateOnDay(day, { time, unit: band?.unit, doctor: band?.doctor });
};
// mês: clicar no dia NAVEGA para a semana daquele dia
const goToWeek = day => {
  cursor.value = new Date(day);
  viewMode.value = 'week';
};
const goToDay = day => {
  cursor.value = new Date(day);
  viewMode.value = 'day';
};
const openCreateFab = () => {
  const base = viewMode.value === 'month' ? new Date() : new Date(cursor.value);
  openCreateOnDay(base);
};

const openEdit = task => {
  const d = new Date(task.due_at);
  const pad = n => String(n).padStart(2, '0');
  editingTask.value = task;
  form.value = {
    kind: kindOf(task),
    name: displayName(task),
    phone: task.phone ?? '',
    procedure: task.procedure ?? '',
    doctor: task.doctor ?? '',
    modality: task.modality || (task.task_type === 'cirurgia' ? '' : 'avaliacao'),
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
    const fk = form.value.kind;
    const dueAt = new Date(`${form.value.date}T${form.value.time || '09:00'}`);
    const payload = {
      title: form.value.name.trim(),
      phone: form.value.phone.trim(),
      procedure: form.value.procedure.trim(),
      doctor: form.value.doctor.trim(),
      modality: fk === 'cirurgias' ? null : (form.value.modality || defaultModality(fk)),
      due_at: dueAt.toISOString(),
      unit: fk === 'teleconsultas' ? ONLINE_UNIT : form.value.unit,
      status: form.value.status,
      canceled: form.value.canceled,
      description: form.value.description,
      task_type: fk === 'cirurgias' ? 'cirurgia' : 'consulta',
      priority: 'medium',
    };
    const noun = kindFor(fk).noun;
    if (editingTask.value) {
      await store.dispatch('tasks/update', { id: editingTask.value.id, ...payload });
      useAlert(`${cap(noun)} atualizad${kindFor(fk).article}`);
    } else {
      await store.dispatch('tasks/create', payload);
      useAlert(`${cap(noun)} agendad${kindFor(fk).article} ${fk === 'cirurgias' ? '🔪' : '✓'}`);
      if (fk !== kind.value) kind.value = fk; // mostra onde ficou
    }
    showModal.value = false;
  } catch {
    useAlert('Erro ao salvar o agendamento.');
  } finally {
    isSaving.value = false;
  }
};

const removeTask = async () => {
  if (!editingTask.value) return;
  try {
    await store.dispatch('tasks/remove', editingTask.value.id);
    showModal.value = false;
    useAlert('Agendamento removido');
  } catch {
    useAlert('Erro ao remover.');
  }
};

// ── Conferência do dia: Compareceu / Faltou + Indicação de cirurgia ──
const savingAttendanceId = ref(0);
const indicationPickerId = ref(0);

const setAttendance = async (task, value) => {
  if (savingAttendanceId.value) return;
  savingAttendanceId.value = task.id;
  try {
    const next = task.attendance === value ? null : value; // re-clique desfaz
    const payload = { id: task.id, attendance: next, status: next === 'attended' ? 'done' : 'todo' };
    if (next !== 'attended') {
      payload.surgery_indication = null;
      payload.indicated_procedure = null;
      indicationPickerId.value = 0;
    }
    await store.dispatch('tasks/update', payload);
    if (next === 'attended') useAlert(isSurgeryTask(task) ? '✓ Realizada.' : '✓ Compareceu — agora marque se houve indicação de cirurgia.');
    else if (next === 'missed') useAlert('✗ Falta registrada — card movido no CRM (se a coluna estiver configurada).');
  } catch {
    useAlert('Erro ao registrar a conferência.');
  } finally {
    savingAttendanceId.value = 0;
  }
};

const setIndication = async (task, value, procedure = null) => {
  if (savingAttendanceId.value) return;
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
    setAttendance(task, 'attended_not_done');
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
      description: reason ? `⚠️ Veio e não operou: ${reason}\n${task.description || ''}` : task.description,
    });
    noSurgeryReasonId.value = 0;
    useAlert('Registrado: o paciente veio, mas a cirurgia não aconteceu.');
  } catch {
    useAlert('Erro ao registrar.');
  } finally {
    savingAttendanceId.value = 0;
  }
};

const fmtBRL = v =>
  Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });

// da consulta com indicação → agendar a CIRURGIA (trilho azul, pré-preenchida)
const scheduleSurgeryFrom = task => {
  kind.value = 'cirurgias';
  editingTask.value = null;
  form.value = emptyForm(new Date(), {
    kind: 'cirurgias',
    name: displayName(task),
    phone: task.phone || '',
    procedure: task.indicated_procedure || task.procedure || '',
    unit: surgeryLocations.value[0]?.key || '',
    description: `Origem: consulta de ${format(new Date(task.due_at), 'dd/MM')} às ${chipTime(task)} — cirurgia indicada.`,
  });
  showDeleteConfirm.value = false;
  showModal.value = true;
};
// do exame/teleconsulta/consulta → marcar um RETORNO presencial
const scheduleFollowUpFrom = task => {
  kind.value = 'consultas';
  editingTask.value = null;
  form.value = emptyForm(addDays(new Date(task.due_at), 7), {
    kind: 'consultas',
    name: displayName(task),
    phone: task.phone || '',
    doctor: task.doctor || '',
    modality: 'retorno',
    unit: task.unit && UNITS[task.unit] ? task.unit : 'tatuape',
    description: `Origem: ${kindLabelOf(task)} de ${format(new Date(task.due_at), 'dd/MM')} às ${chipTime(task)}.`,
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
const attendanceOwners = ref({ consulta_user_id: '', cirurgia_user_id: '', deadline: '19:00' });
const isSavingAttendanceCfg = ref(false);

const loadCrmStages = async () => {
  try {
    await store.dispatch('crm/fetchPipelines');
    const pipelines = store.getters['crm/getPipelines'] || [];
    allCrmStages.value = pipelines.flatMap(p => (p.stages || []).map(s => ({ id: s.id, name: s.name, pipeline: p.name })));
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
  const title = `CEVICO — ${cap(k.value.plural)} de ${day.toLocaleDateString('pt-BR', { weekday: 'long', day: '2-digit', month: '2-digit', year: 'numeric' })}`;
  const esc = s => String(s ?? '').replace(/</g, '&lt;');
  const procHeader = { cirurgias: 'Procedimento', exames: 'Exame' }[kind.value] || 'Problema';
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
      body { font-family: -apple-system, Inter, Arial, sans-serif; margin: 24px; color: #111; }
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
    <p class="sub">${list.length} ${k.value.noun}(s) · Conferência do fim do dia: marque Compareceu, Faltou e Cirurgia indicada — depois registre no sistema (Agenda → visão Dia).</p>
    <table><thead><tr>
      <th>Hora</th><th>Paciente</th><th>Telefone</th><th>${procHeader}</th><th>Médico</th><th>${isSurgeryMode.value ? 'Local' : 'Unidade'}</th><th>Observações</th>
      <th>Compareceu</th><th>Faltou</th><th>Cirurgia indicada</th>
    </tr></thead><tbody>${rows}</tbody></table>
    <script>window.onload = () => window.print();<\/script>
    </body></html>`;
  const w = window.open('', '_blank');
  if (!w) { useAlert('O navegador bloqueou a janela — libere pop-ups para imprimir.'); return; }
  w.document.write(html);
  w.document.close();
};

// ── arrastar-e-soltar (semana/dia): soltar = reagendar, confirmando no modal ──
const dragTask = ref(null);
const dragOverDay = ref('');
const onDragStart = task => { dragTask.value = task; };
const onDragOver = day => { if (dragTask.value) dragOverDay.value = dateKey(day); };
const onDragLeave = day => { if (dragOverDay.value === dateKey(day)) dragOverDay.value = ''; };
const onColumnDrop = ({ day, minutes }) => {
  const task = dragTask.value;
  dragTask.value = null;
  dragOverDay.value = '';
  if (!task || isDayOff(day)) return;
  const original = new Date(task.due_at);
  const hh = Math.floor(minutes / 60);
  const mm = minutes % 60;
  if (isSameDay(original, day) && original.getHours() === hh && original.getMinutes() === mm) return;
  openEdit(task);
  form.value.date = format(day, 'yyyy-MM-dd');
  form.value.time = `${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
};

// contagem de pendentes da conferência
const pendingCount = computed(() => dayViewTasks.value.filter(t => !t.attendance).length);
</script>

<template>
  <div class="cv-page cv-agenda flex flex-col h-full w-full bg-n-surface-1" :style="pageVars">
    <!-- ══ CABEÇALHO grudado (vidro): período · navegação · visões · tipos ══ -->
    <div class="cv-ag-top flex-shrink-0">
      <div class="max-w-[1440px] mx-auto px-4 sm:px-6 pt-3 pb-3 flex flex-col gap-2.5">
        <!-- linha 1: período grande à esquerda, visões + ação à direita -->
        <div class="flex items-center gap-2 flex-wrap">
          <div class="cv-icon cv-icon-lg hidden sm:inline-flex" :title="`Agenda de ${k.plural}`">
            <span :class="k.icon" class="text-lg" />
          </div>
          <div class="relative">
            <button class="cv-ag-period" title="Clique para escolher a data num calendário" @click="toggleDatePicker">
              <span class="truncate max-w-[60vw] sm:max-w-none">{{ navLabel }}</span>
              <span class="i-lucide-chevron-down text-xs opacity-60" />
            </button>
            <!-- calendário interativo. O véu invisível que fecha ao clicar fora
                 vai para o body: o cabeçalho tem backdrop-filter, e um fixed
                 dentro dele só cobriria o próprio cabeçalho. z-10 fica abaixo
                 do cabeçalho (z-20), então o calendário continua clicável. -->
            <Teleport to="body">
              <div v-if="showDatePicker" class="fixed inset-0 z-10" @click="showDatePicker = false" />
            </Teleport>
            <div v-if="showDatePicker" class="cv-pop cv-ag-pop absolute left-0 top-10 z-40 w-72 p-4">
              <div class="flex items-center justify-between mb-2">
                <button class="cv-ag-nav !w-7 !h-7" @click="pickerCursor = addMonths(pickerCursor, -1)"><span class="i-lucide-chevron-left text-sm" /></button>
                <p class="text-sm font-bold text-n-slate-12">{{ pickerLabel }}</p>
                <button class="cv-ag-nav !w-7 !h-7" @click="pickerCursor = addMonths(pickerCursor, 1)"><span class="i-lucide-chevron-right text-sm" /></button>
              </div>
              <div class="grid grid-cols-7 mb-1">
                <span v-for="wd in WEEKDAYS" :key="'p' + wd" class="text-center text-[10px] font-semibold text-n-slate-9">{{ wd.charAt(0) }}</span>
              </div>
              <div v-for="(week, wi) in pickerWeeks" :key="'pw' + wi" class="grid grid-cols-7">
                <button
                  v-for="day in week"
                  :key="'pd' + day.toISOString()"
                  class="cv-ag-daynum mx-auto !w-8 !h-8 text-xs hover:bg-n-alpha-2"
                  :class="[
                    isSameMonth(day, pickerCursor) ? '' : 'cv-ag-daynum-muted',
                    isSameDay(day, cursor) ? 'cv-ag-daynum-today' : '',
                  ]"
                  :style="!isSameDay(day, cursor) && isToday(day) ? { boxShadow: 'inset 0 0 0 1.5px var(--cv)' } : {}"
                  @click="pickDate(day)"
                >
                  {{ day.getDate() }}
                </button>
              </div>
              <button class="cv-btn cv-btn-sm w-full mt-2" @click="pickDate(new Date())">Hoje</button>
            </div>
          </div>
          <p v-if="navSub" class="text-[11px] text-n-slate-9 hidden md:block">{{ navSub }}</p>

          <div class="flex items-center gap-1.5 ml-auto">
            <button class="cv-ag-nav" :title="`${cap(stepLabel)} anterior`" @click="step(-1)"><span class="i-lucide-chevron-left text-base" /></button>
            <button class="cv-btn cv-btn-ghost cv-btn-sm" title="Voltar para hoje" @click="goToday">Hoje</button>
            <button class="cv-ag-nav" :title="`${cap(stepLabel)} seguinte`" @click="step(1)"><span class="i-lucide-chevron-right text-base" /></button>
          </div>

          <div class="cv-seg cv-seg-sm">
            <button
              v-for="m in VIEW_MODES"
              :key="m.key"
              class="cv-seg-item"
              :class="viewMode === m.key ? 'cv-seg-on' : ''"
              @click="viewMode = m.key"
            >
              <span :class="m.icon" class="text-sm" />
              <span class="hidden sm:inline">{{ m.label }}</span>
            </button>
          </div>

          <button class="cv-btn" @click="openCreateOnDay(viewMode === 'month' ? new Date() : cursor)">
            <span class="i-lucide-plus text-sm" />
            <span class="hidden sm:inline">{{ newLabel }}</span>
            <span class="sm:hidden">{{ cap(k.noun) }}</span>
          </button>
        </div>

        <!-- linha 2: os 4 TIPOS (cada um acende na sua cor) + filtros -->
        <div class="flex items-center gap-2 flex-wrap">
          <div class="cv-seg overflow-x-auto" style="scrollbar-width: none">
            <button
              v-for="kk in KINDS"
              :key="kk.key"
              class="cv-ag-kind"
              :class="kind === kk.key ? 'cv-ag-kind-on' : ''"
              :style="kindVarsOf(kk.key)"
              :title="`${kk.label} — ${kk.hint}`"
              @click="kind = kk.key"
            >
              <span class="cv-ag-kind-dot" />
              <span :class="kk.icon" class="text-sm hidden sm:inline" />
              {{ kk.label }}
              <span class="cv-ag-kind-n" :title="`${kindCounts[kk.key]} ${rangeNoun}`">{{ kindCounts[kk.key] }}</span>
            </button>
          </div>

          <div class="flex items-center gap-1.5 ml-auto flex-wrap">
            <button
              v-if="viewMode === 'week'"
              class="cv-btn cv-btn-ghost cv-btn-sm"
              :title="hideWeekend ? 'Mostrar sábado e domingo' : 'Esconder sábado e domingo'"
              @click="toggleWeekend"
            >
              <span :class="hideWeekend ? 'i-lucide-eye-off' : 'i-lucide-eye'" class="text-xs" />
              <span class="hidden md:inline">sáb/dom</span>
            </button>
            <button
              v-if="viewMode === 'day' && dayViewTasks.length"
              class="cv-btn cv-btn-ghost cv-btn-sm"
              title="Abre a lista do dia pronta para imprimir ou salvar em PDF"
              @click="printDayList"
            >
              <span class="i-lucide-printer text-xs" />
              <span class="hidden md:inline">Imprimir</span>
            </button>
            <button
              v-if="isPhysical"
              class="cv-btn cv-btn-ghost cv-btn-sm"
              title="Janelas de avaliação dos médicos"
              @click="showWindowsModal = true"
            >
              <span class="i-lucide-clock text-xs" />
              <span class="hidden md:inline">Janelas dos médicos</span>
            </button>
            <button
              v-else-if="isSurgeryMode"
              class="cv-btn cv-btn-ghost cv-btn-sm"
              title="Dias e horários em que a sala cirúrgica de cada clínica está disponível"
              @click="openSurgeryWindowsModal"
            >
              <span class="i-lucide-clock text-xs" />
              <span class="hidden md:inline">Sala cirúrgica</span>
            </button>
            <select v-model="view" class="cv-input !h-8 text-xs !w-auto max-w-[180px]">
              <option value="clinic">{{ isSurgeryMode ? 'Todos os locais' : 'Toda a clínica' }}</option>
              <optgroup v-if="!isSurgeryMode && !isTele" label="Unidades">
                <option v-for="(u, key) in UNITS" :key="key" :value="`unit:${key}`">{{ u.label }}</option>
              </optgroup>
              <optgroup v-if="!isSurgeryMode" label="Médicos">
                <option v-for="d in DOCTORS" :key="d.name" :value="`doctor:${d.name}`">{{ d.name }}</option>
              </optgroup>
              <option value="me">Minha agenda pessoal</option>
              <optgroup v-if="isAdmin" label="Pessoas">
                <option v-for="agent in agents" :key="agent.id" :value="String(agent.id)">{{ agent.name }}</option>
              </optgroup>
            </select>
          </div>
        </div>

        <!-- linha 3: atalhos em linha — um médico só / um local só -->
        <div v-if="!isPersonalView" class="flex items-center gap-1.5 flex-wrap">
          <button
            class="cv-chip"
            :class="view === 'clinic' ? 'cv-chip-on' : ''"
            @click="view = 'clinic'"
          >
            {{ isSurgeryMode ? 'Todos os locais' : 'Toda a clínica' }}
          </button>
          <template v-if="!isSurgeryMode">
            <button
              v-for="d in DOCTORS"
              :key="'quick' + d.name"
              class="cv-chip"
              :class="view === `doctor:${d.name}` ? 'cv-chip-on' : ''"
              :style="view === `doctor:${d.name}` ? { '--cv-grad': d.color, '--cv-deep-rgb': hexToRgbSpaced(d.color) } : {}"
              @click="view = `doctor:${d.name}`"
            >
              <span class="w-2 h-2 rounded-full" :style="{ background: view === `doctor:${d.name}` ? '#fff' : d.color }" />
              {{ d.short }}
              <span v-if="isDoctorClosed(d.name)" class="text-[9px]" title="agenda fechada">⏸</span>
            </button>
            <template v-if="!isTele">
              <span class="w-px h-4 bg-n-weak mx-0.5" />
              <button
                v-for="(u, key) in UNITS"
                :key="'qu' + key"
                class="cv-chip"
                :class="view === `unit:${key}` ? 'cv-chip-on' : ''"
                :style="view === `unit:${key}` ? { '--cv-grad': u.color, '--cv-deep-rgb': hexToRgbSpaced(u.color) } : {}"
                @click="view = view === `unit:${key}` ? 'clinic' : `unit:${key}`"
              >
                <span class="w-2 h-2 rounded-full" :style="{ background: view === `unit:${key}` ? '#fff' : u.color }" />
                {{ u.label }}
              </button>
            </template>
          </template>
          <template v-else>
            <button
              v-for="loc in surgeryLocations"
              :key="'quickloc' + loc.key"
              class="cv-chip"
              :class="view === `unit:${loc.key}` ? 'cv-chip-on' : ''"
              :style="view === `unit:${loc.key}` ? { '--cv-grad': loc.color, '--cv-deep-rgb': hexToRgbSpaced(loc.color) } : {}"
              @click="view = `unit:${loc.key}`"
            >
              <span class="w-2 h-2 rounded-full" :style="{ background: view === `unit:${loc.key}` ? '#fff' : loc.color }" />
              {{ loc.label }}
            </button>
            <button v-if="isAdmin" class="cv-chip" title="Gerenciar clínicas parceiras" @click="openLocationsModal">
              <span class="i-lucide-map-pin text-[10px]" /> locais
            </button>
          </template>
          <span class="text-[11px] text-n-slate-9 ml-auto hidden lg:inline">{{ k.hint }}</span>
        </div>
      </div>
    </div>

    <!-- 📖 respostas do formulário do paciente -->
    <div v-if="formAnswersTask" class="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" @click.self="formAnswersTask = null">
      <div class="cv-modal cv-ag-pop w-full max-w-lg max-h-[85vh] flex flex-col">
        <div class="cv-modal-head flex items-center gap-3" style="--cv-hero: linear-gradient(135deg, #5B21B6, #7C3AED)">
          <span class="i-lucide-book-open-check text-xl" />
          <div class="flex-1 min-w-0">
            <h2 class="text-sm font-bold truncate">{{ formAnswersTask.name }}</h2>
            <p class="text-[11px] opacity-85">
              {{ formAnswersTask.detail.form_response.form }}
              · respondido em {{ new Date(formAnswersTask.detail.form_response.answered_at).toLocaleDateString('pt-BR') }}
            </p>
          </div>
          <button class="cv-glass-btn cv-iconbtn" @click="formAnswersTask = null"><span class="i-lucide-x" /></button>
        </div>
        <div class="flex-1 overflow-y-auto p-5 space-y-2.5">
          <div v-for="(ans, ai) in formAnswersTask.detail.form_response.answers" :key="ai" class="cv-sub px-3.5 py-2.5">
            <p class="text-[11px] font-semibold text-n-slate-10 mb-0.5">{{ ans.label }}</p>
            <p class="text-sm text-n-slate-12">{{ Array.isArray(ans.value) ? ans.value.join(', ') : (ans.value || '—') }}</p>
          </div>
        </div>
      </div>
    </div>

    <SkeletonScreen v-if="isLoading" variant="calendar" />

    <!-- ══ ÁREA ROLÁVEL ══ -->
    <div v-else class="flex-1 min-h-0 overflow-y-auto">
      <div class="px-4 sm:px-6 pt-4 pb-24 max-w-[1440px] mx-auto">
        <!-- resumo do trilho: 4 vidros pequenos -->
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-2.5 mb-3">
          <div class="cv-stat px-4 py-3 flex items-center gap-3">
            <span class="cv-icon cv-icon-sm"><span :class="k.icon" class="text-xs" /></span>
            <div class="min-w-0">
              <p class="text-[11px] font-semibold text-n-slate-10 truncate">{{ cap(k.plural) }} hoje</p>
              <p class="text-xl font-bold leading-tight text-n-slate-12 tabular-nums">{{ kpiToday }}</p>
            </div>
          </div>
          <div class="cv-stat px-4 py-3 flex items-center gap-3">
            <span class="cv-icon cv-icon-sm"><span class="i-lucide-calendar-range text-xs" /></span>
            <div class="min-w-0">
              <p class="text-[11px] font-semibold text-n-slate-10 truncate">Nesta semana</p>
              <p class="text-xl font-bold leading-tight text-n-slate-12 tabular-nums">{{ kpiWeek }}</p>
            </div>
          </div>
          <button
            v-for="p in kpiPlaces"
            :key="p.key"
            class="cv-stat px-4 py-3 flex items-center gap-3 text-left transition-transform hover:-translate-y-px"
            :class="view === `unit:${p.key}` ? 'cv-sub-on' : ''"
            :disabled="isTele"
            :title="isTele ? '' : 'Ver só este lugar'"
            @click="!isTele && (view = view === `unit:${p.key}` ? 'clinic' : `unit:${p.key}`)"
          >
            <span class="cv-icon cv-icon-sm" :style="{ background: p.color }"><span class="i-lucide-map-pin text-xs" /></span>
            <div class="min-w-0">
              <p class="text-[11px] font-semibold text-n-slate-10 truncate">{{ p.label }}</p>
              <p class="text-xl font-bold leading-tight tabular-nums" :style="{ color: p.color }">{{ p.n }}</p>
            </div>
          </button>
        </div>

        <!-- Ocupação: uma linha fina; abre para ver dia/semana/mês por tipo -->
        <div v-if="showOccupancy" class="cv-sub px-4 py-2.5 mb-3">
          <button class="w-full flex items-center gap-2.5 text-left" @click="showOccDetail = !showOccDetail">
            <span class="i-lucide-gauge text-sm text-n-slate-10" />
            <p class="text-xs font-semibold text-n-slate-12 whitespace-nowrap">Ocupação</p>
            <span class="cv-chip">{{ activeDoctor ? doctorShort(activeDoctor) : activeUnit ? (UNITS[activeUnit]?.label || surgeryLocationLabel(activeUnit)) : (isSurgeryMode ? 'todos os locais' : 'toda a clínica') }}</span>
            <div class="cv-track cv-track-sm flex-1 min-w-[80px] flex">
              <template v-if="occCurrent.total && occSegments(occCurrent)">
                <div v-for="s in occSegments(occCurrent)" :key="s.key" class="h-full" :style="{ width: Math.max(s.pct, 2) + '%', background: s.color }" :title="`${s.label}: ${s.count} bloco(s)`" />
              </template>
              <div v-else-if="occCurrent.total" class="cv-fill" :style="{ width: Math.max(occCurrent.pct, 3) + '%', background: occColor(occCurrent.pct) }" />
            </div>
            <span class="text-xs font-bold text-n-slate-12 tabular-nums w-10 text-right">{{ occCurrent.total ? occCurrent.pct + '%' : '—' }}</span>
            <span class="text-[10px] text-n-slate-9 hidden sm:inline">{{ rangeNoun }}</span>
            <span :class="showOccDetail ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'" class="text-xs text-n-slate-9" />
          </button>
          <div v-if="showOccDetail" class="grid grid-cols-1 sm:grid-cols-3 gap-3 mt-3 pt-3 border-t border-n-weak">
            <div v-for="row in occRows" :key="row.key">
              <div class="flex items-center justify-between text-xs mb-1">
                <span class="text-n-slate-11">{{ row.label }} <span class="text-n-slate-9">({{ row.sub }})</span></span>
                <span class="font-bold text-n-slate-12 tabular-nums">{{ row.scan.total ? row.scan.pct + '%' : '—' }}</span>
              </div>
              <div class="cv-track cv-track-sm flex">
                <template v-if="row.scan.total && occSegments(row.scan)">
                  <div v-for="s in occSegments(row.scan)" :key="s.key" class="h-full" :style="{ width: Math.max(s.pct, 2) + '%', background: s.color }" :title="`${s.label}: ${s.count} bloco(s)`" />
                </template>
                <div v-else-if="row.scan.total" class="cv-fill" :style="{ width: Math.max(row.scan.pct, 3) + '%', background: occColor(row.scan.pct) }" />
              </div>
              <p class="text-[10px] text-n-slate-9 mt-0.5">
                {{ row.scan.total ? `${row.scan.filled} de ${row.scan.total} blocos` : 'sem janela' }}
                <template v-if="occCaption(row.scan)"> · {{ occCaption(row.scan) }}</template>
              </p>
            </div>
            <p v-if="!isSurgeryMode" class="sm:col-span-3 text-[10px] text-n-slate-9 flex items-center gap-2.5 flex-wrap">
              <span v-for="m in OCC_MODALITIES" :key="m.key" class="flex items-center gap-1"><span class="w-2 h-2 rounded-full" :style="{ background: m.color }" />{{ m.label }}</span>
              <span>· consultas e exames dividem os mesmos blocos dos médicos · cadeados fora da conta</span>
            </p>
          </div>
        </div>

        <!-- ══ MÊS ══ -->
        <div v-if="viewMode === 'month'">
          <div class="cv-ag-month">
            <div v-for="wd in WEEKDAYS" :key="wd" class="cv-ag-month-head">{{ wd }}</div>
            <template v-for="(week, wi) in weeks" :key="wi">
              <div
                v-for="day in week"
                :key="day.toISOString()"
                class="cv-ag-cell"
                :class="{
                  'cv-ag-cell-out': !inMonth(day),
                  'cv-ag-cell-off': isDayOff(day),
                  'cv-ag-cell-today': isToday(day),
                }"
                role="button"
                title="Abrir a semana deste dia"
                @click="goToWeek(day)"
              >
                <div class="flex items-center justify-between">
                  <span class="cv-ag-daynum !w-6 !h-6 text-xs" :class="[isToday(day) ? 'cv-ag-daynum-today' : '', !inMonth(day) ? 'cv-ag-daynum-muted' : '']">{{ day.getDate() }}</span>
                  <span v-if="isDayOff(day)" class="i-lucide-lock text-[10px]" :class="isDayBlocked(day) ? 'text-red-400' : 'text-n-slate-8'" :title="isDayBlocked(day) ? 'Dia fechado' : 'Fim de semana'" />
                  <span v-else class="flex items-center gap-0.5">
                    <span v-for="w in windowsForDay(day)" :key="(w.doctor || w.unit) + w.start" class="w-1.5 h-1.5 rounded-full" :style="{ backgroundColor: winColor(w) }" :title="`${winTitle(w)} — ${w.start}`" />
                    <span v-if="dayOccupancy(day)" class="text-[9px] font-bold ml-0.5 tabular-nums" :style="{ color: occColor(dayOccupancy(day).pct) }" :title="`${dayOccupancy(day).filled} de ${dayOccupancy(day).total} blocos ocupados`">{{ dayOccupancy(day).pct }}%</span>
                  </span>
                </div>
                <div class="flex flex-col gap-[3px] min-h-0">
                  <button
                    v-for="task in dayTasks(day).slice(0, MONTH_MAX)"
                    :key="task.id"
                    type="button"
                    class="cv-ag-ev"
                    :class="{ 'cv-ag-ev-done': task.status === 'done' && task.attendance !== 'missed', 'cv-ag-ev-missed': task.attendance === 'missed' }"
                    :style="evVars(task)"
                    :title="`${chipTime(task)} · ${displayName(task)}${unitOf(task) ? ' · ' + unitOf(task).label : ''}`"
                    @click.stop="openEdit(task)"
                  >
                    <span class="cv-ag-ev-time">{{ chipTime(task) }}</span>
                    <span class="cv-ag-ev-name">{{ displayName(task) }}</span>
                  </button>
                  <button
                    v-if="dayTasks(day).length > MONTH_MAX"
                    type="button"
                    class="cv-ag-more text-left"
                    title="Ver o dia inteiro"
                    @click.stop="goToDay(day)"
                  >
                    +{{ dayTasks(day).length - MONTH_MAX }} mais
                  </button>
                </div>
              </div>
            </template>
          </div>
          <p class="text-[10px] text-n-slate-9 mt-2 text-center">clique num dia para abrir a semana · o número de cada tipo está no seletor acima</p>
        </div>

        <!-- ══ SEMANA ══ -->
        <div v-else-if="viewMode === 'week'" class="overflow-x-auto">
          <div class="cv-ag-grid min-w-[720px]">
            <div class="cv-ag-grid-head" :style="{ gridTemplateColumns: weekGridCols }">
              <div />
              <button
                v-for="day in weekDays"
                :key="'h' + day.toISOString()"
                type="button"
                class="cv-ag-dayhead"
                :class="{ 'cv-ag-dayhead-today': isToday(day), 'cv-ag-dayhead-off': isDayOff(day) }"
                :title="isDayOff(day) ? (isDayBlocked(day) ? 'Dia fechado' : 'Fim de semana') : 'Abrir o dia'"
                @click="goToDay(day)"
              >
                <span class="cv-ag-dayhead-wd">{{ WEEKDAYS[day.getDay()] }}</span>
                <span class="cv-ag-daynum cv-ag-daynum-lg" :class="isToday(day) ? 'cv-ag-daynum-today' : ''">{{ day.getDate() }}</span>
                <span v-if="isDayOff(day)" class="text-[9px] text-n-slate-9 flex items-center gap-0.5"><span class="i-lucide-lock text-[9px]" />{{ isDayBlocked(day) ? 'fechado' : 'sem agenda' }}</span>
                <span v-else class="flex items-center gap-1 flex-wrap justify-center min-h-[16px]">
                  <span v-for="w in windowsForDay(day)" :key="(w.doctor || w.unit) + w.start" class="cv-ag-win" :style="{ '--w': winColor(w) }" :title="`${winTitle(w)} — ${w.start} às ${w.end} (${winUnitLabel(w)})`">
                    {{ w.doctor ? doctorShort(w.doctor) : surgeryLocationLabel(w.unit) }}
                  </span>
                  <span v-if="dayOccupancy(day)" class="text-[9px] font-bold tabular-nums" :style="{ color: occColor(dayOccupancy(day).pct) }">{{ dayOccupancy(day).pct }}%</span>
                  <span v-else-if="dayTasks(day).length" class="text-[9px] font-semibold text-n-slate-9">{{ dayTasks(day).length }}</span>
                </span>
              </button>
            </div>
            <div class="cv-ag-grid-body" :style="{ gridTemplateColumns: weekGridCols }">
              <div class="cv-ag-gutter" :style="{ height: weekHours.length * WEEK_ROW_PX + 'px' }">
                <span v-for="(h, hi) in weekHours" :key="h" class="cv-ag-hour" :style="{ top: hi * WEEK_ROW_PX + 'px' }">{{ hi === 0 ? '' : String(h).padStart(2, '0') + ':00' }}</span>
              </div>
              <AgendaTimeColumn
                v-for="day in weekDays"
                :key="'c' + day.toISOString()"
                :day="day"
                :tasks="dayTasks(day)"
                :bands="bandsForDay(day)"
                :start-hour="weekSpan.start"
                :end-hour="weekSpan.end"
                :hour-px="WEEK_ROW_PX"
                :day-off="isDayOff(day)"
                :today="isToday(day)"
                :now-minutes="nowMinutes"
                :drop-active="dragOverDay === dateKey(day)"
                :duration-of="taskDuration"
                :accent-of="accentOf"
                :name-of="displayName"
                compact
                @create="onColumnCreate"
                @open="openEdit"
                @dragstart="onDragStart"
                @dragover="onDragOver"
                @dragleave="onDragLeave"
                @drop="onColumnDrop"
              />
            </div>
          </div>
          <p class="text-[10px] text-n-slate-9 mt-2 text-center">
            clique num espaço vazio para agendar naquele horário · arraste um balão para reagendar · faixas coloridas = horário em que cada médico atende
          </p>
        </div>

        <!-- ══ DIA ══ -->
        <div v-else>
          <!-- avisos do dia -->
          <div v-if="isWeekend(cursor)" class="cv-sub flex items-center gap-2 px-4 py-3 mb-4 text-sm text-n-slate-10">
            <span class="i-lucide-lock text-base" />
            {{ WEEKDAY_FULL[cursor.getDay()] }} — sem agenda em nenhuma unidade.
          </div>
          <div v-else-if="isDayBlocked(cursor)" class="cv-block cv-strip cv-red flex items-center gap-2 px-4 py-3 mb-4 text-sm text-n-slate-11 flex-wrap">
            <span class="i-lucide-lock text-base text-red-500" />
            <b>Dia fechado</b> — sem agenda nesta data.
            <button v-if="isAdmin" class="cv-btn cv-btn-ghost cv-btn-sm ml-auto" @click="toggleBlockDay(cursor)">Reabrir dia</button>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-12 gap-4">
            <!-- linha do tempo do dia -->
            <div class="lg:col-span-5">
              <div class="cv-ag-grid">
                <div class="cv-ag-grid-head" style="grid-template-columns: 56px minmax(0, 1fr)">
                  <div />
                  <div class="cv-ag-dayhead !items-start px-3 !py-2.5" :class="isToday(cursor) ? 'cv-ag-dayhead-today' : ''">
                    <span class="cv-ag-dayhead-wd">{{ WEEKDAY_FULL[cursor.getDay()] }}</span>
                    <span class="flex items-center gap-2">
                      <span class="cv-ag-daynum cv-ag-daynum-lg" :class="isToday(cursor) ? 'cv-ag-daynum-today' : ''">{{ cursor.getDate() }}</span>
                      <span class="text-sm font-semibold text-n-slate-12">{{ dayViewTasks.length }} {{ dayViewTasks.length === 1 ? k.noun : k.plural }}</span>
                    </span>
                  </div>
                </div>
                <div class="cv-ag-grid-body" style="grid-template-columns: 56px minmax(0, 1fr)">
                  <div class="cv-ag-gutter" :style="{ height: dayHours.length * DAY_ROW_PX + 'px' }">
                    <span v-for="(h, hi) in dayHours" :key="h" class="cv-ag-hour" :style="{ top: hi * DAY_ROW_PX + 'px' }">{{ hi === 0 ? '' : String(h).padStart(2, '0') + ':00' }}</span>
                  </div>
                  <AgendaTimeColumn
                    :day="cursor"
                    :tasks="dayViewTasks"
                    :bands="bandsForDay(cursor)"
                    :start-hour="daySpan.start"
                    :end-hour="daySpan.end"
                    :hour-px="DAY_ROW_PX"
                    :day-off="isDayOff(cursor)"
                    :today="isToday(cursor)"
                    :now-minutes="nowMinutes"
                    :drop-active="dragOverDay === dateKey(cursor)"
                    :duration-of="taskDuration"
                    :accent-of="accentOf"
                    :name-of="displayName"
                    @create="onColumnCreate"
                    @open="openEdit"
                    @dragstart="onDragStart"
                    @dragover="onDragOver"
                    @dragleave="onDragLeave"
                    @drop="onColumnDrop"
                  />
                </div>
              </div>
              <p class="text-[10px] text-n-slate-9 mt-2 text-center">cada balão ocupa o espaço do seu tempo · clique no vazio para agendar</p>
            </div>

            <div class="lg:col-span-7 space-y-4">
              <!-- janelas do dia: blocos de horário (livre / ocupado / cadeado) -->
              <div v-if="!isDayBlocked(cursor) && windowsForDay(cursor).length" class="space-y-3">
                <div v-for="win in windowsForDay(cursor)" :key="(win.doctor || win.unit) + win.start" class="cv-sub p-4" :style="winVars(win)">
                  <div class="flex items-center gap-2 flex-wrap mb-3">
                    <span class="cv-icon cv-icon-sm" :style="{ background: winColor(win) }">
                      <span :class="win.doctor ? 'i-lucide-stethoscope' : 'i-lucide-slice'" class="text-xs" />
                    </span>
                    <p class="text-sm font-bold text-n-slate-12">{{ winTitle(win) }}</p>
                    <span class="cv-chip" :style="{ '--cv-rgb': hexToRgbSpaced(winColor(win)), '--cv-deep': winColor(win) }">{{ winUnitLabel(win) }}</span>
                    <span class="text-xs text-n-slate-10"><template v-if="win.turno">{{ win.turno }} · </template>{{ win.start }}–{{ win.end }} · {{ win.block }} min</span>
                    <span class="text-[10px] px-2 py-0.5 rounded-full font-bold text-white ml-auto" :style="{ backgroundColor: occColor(winOccupancy(cursor, win).pct) }" :title="`${winOccupancy(cursor, win).filled} de ${winOccupancy(cursor, win).total} blocos ocupados`">
                      {{ winOccupancy(cursor, win).pct }}%
                    </span>
                    <button v-if="isAdmin" class="cv-btn cv-btn-ghost cv-btn-sm cv-btn-danger" title="Fechar o dia inteiro (feriado, congresso, folga...)" @click="toggleBlockDay(cursor)">
                      <span class="i-lucide-lock text-[10px]" /> fechar dia
                    </button>
                  </div>
                  <div class="grid grid-cols-3 sm:grid-cols-4 xl:grid-cols-5 gap-2">
                    <template v-for="slot in slotsFor(win)" :key="slot">
                      <span v-if="taskAtSlot(cursor, win, slot)" class="relative group min-w-0">
                        <button class="cv-ag-slot cv-ag-slot-taken truncate" :title="tasksAtSlotAll(cursor, win, slot).map(displayName).join(' + ')" @click="openEdit(taskAtSlot(cursor, win, slot))">
                          <span class="tabular-nums opacity-90">{{ slot }}</span>
                          <span class="truncate">{{ displayName(taskAtSlot(cursor, win, slot)) }}</span>
                          <span v-if="tasksAtSlotAll(cursor, win, slot).length > 1" class="font-extrabold">+{{ tasksAtSlotAll(cursor, win, slot).length - 1 }}</span>
                        </button>
                        <button class="cv-ag-corner" title="Encaixe: agendar OUTRO paciente neste mesmo horário" @click.stop="openCreateSlot(cursor, win, slot)"><span class="i-lucide-plus" /></button>
                      </span>
                      <button v-else-if="isBlocked(cursor, win, slot)" class="cv-ag-slot cv-ag-slot-locked" :title="isAdmin ? 'Horário fechado — clique para reabrir' : 'Horário fechado'" @click="isAdmin && toggleBlock(cursor, win, slot)">
                        <span class="i-lucide-lock text-[10px]" /> {{ slot }}
                      </button>
                      <span v-else class="relative group">
                        <button class="cv-ag-slot cv-ag-slot-free tabular-nums" title="Bloco livre — clique para agendar" @click="openCreateSlot(cursor, win, slot)">{{ slot }}</button>
                        <button v-if="isAdmin" class="cv-ag-corner" title="Fechar este horário 🔒" @click.stop="toggleBlock(cursor, win, slot)"><span class="i-lucide-lock" /></button>
                      </span>
                    </template>
                  </div>
                </div>
              </div>

              <!-- vazio -->
              <div v-if="!dayViewTasks.length && !windowsForDay(cursor).length && !isDayOff(cursor)" class="cv-sub text-center py-14 text-n-slate-10">
                <span class="cv-icon cv-icon-xl mx-auto mb-3 block"><span :class="k.icon" class="text-xl" /></span>
                <p class="text-sm">Nenhum{{ k.article === 'a' ? 'a' : '' }} {{ k.noun }} neste dia.</p>
                <button class="cv-btn mt-3" @click="openCreateOnDay(cursor)"><span class="i-lucide-plus text-sm" /> {{ newLabel }}</button>
              </div>

              <!-- Conferência do dia -->
              <template v-if="dayViewTasks.length">
                <div class="flex items-center gap-2 flex-wrap">
                  <span class="cv-icon cv-icon-sm"><span class="i-lucide-clipboard-check text-xs" /></span>
                  <p class="text-sm font-bold text-n-slate-12">Conferência d{{ k.article }}s {{ k.plural }} do dia</p>
                  <span v-if="pendingCount" class="cv-chip cv-amber">{{ pendingCount }} pendente(s)</span>
                  <span v-else class="cv-chip cv-green">tudo conferido ✓</span>
                </div>
                <div class="space-y-2.5">
                  <div
                    v-for="task in dayViewTasks"
                    :key="task.id"
                    class="cv-ag-card"
                    :class="task.attendance === 'missed' ? 'opacity-75' : ''"
                    :style="evVars(task)"
                    @click="openEdit(task)"
                  >
                    <div class="flex items-center gap-2 flex-wrap">
                      <span class="text-sm font-extrabold tabular-nums" :style="{ color: accentOf(task) }">{{ chipTime(task) }}</span>
                      <span class="text-sm font-semibold text-n-slate-12" :class="task.attendance === 'missed' ? 'line-through' : ''">{{ displayName(task) }}</span>
                      <span v-if="unitOf(task)" class="cv-chip" :style="{ '--cv-rgb': hexToRgbSpaced(accentOf(task)), '--cv-deep': accentOf(task) }">{{ unitOf(task).label }}</span>
                      <span v-if="!isSurgeryTask(task) && !isTele" class="cv-chip" :style="{ '--cv-rgb': hexToRgbSpaced(modalityOf(task).color), '--cv-deep': modalityOf(task).color }">{{ modalityOf(task).label }}</span>
                      <span v-if="task.attendance === 'attended'" class="cv-chip cv-green">{{ isSurgeryTask(task) ? '✓ Realizada' : '✓ Compareceu' }}</span>
                      <span v-else-if="task.attendance === 'missed'" class="cv-chip cv-red">{{ isSurgeryTask(task) ? '✗ Não veio' : '✗ Faltou' }}</span>
                      <span v-else-if="task.attendance === 'attended_not_done'" class="cv-chip cv-amber">⚠️ Veio e não fez</span>
                      <span v-if="isAdmin && isSurgeryTask(task) && task.crm_value" class="cv-chip cv-green ml-auto" :title="task.surgery_payment ? `Forma de pagamento: ${task.surgery_payment}` : 'Valor do card no CRM'">
                        💰 {{ fmtBRL(task.crm_value) }}<template v-if="task.surgery_payment"> · {{ task.surgery_payment }}</template>
                      </span>
                      <span v-if="task.surgery_indication === 'indicated'" class="cv-chip cv-gold cv-chip-on">🎯 {{ task.indicated_procedure || 'Cirurgia indicada' }}</span>
                      <span v-else-if="task.surgery_indication === 'not_indicated'" class="cv-chip cv-slate">Sem indicação</span>
                    </div>
                    <div class="flex items-center gap-3 mt-1.5 text-[11px] text-n-slate-10 flex-wrap">
                      <span v-if="task.phone" class="flex items-center gap-1"><span class="i-lucide-phone text-[10px]" />{{ task.phone }}</span>
                      <span v-if="task.procedure" class="flex items-center gap-1"><span class="i-lucide-eye text-[10px]" />{{ task.procedure }}</span>
                      <span v-if="task.doctor" class="flex items-center gap-1"><span class="i-lucide-stethoscope text-[10px]" />{{ task.doctor }}</span>
                      <button v-if="task.contact_id" class="flex items-center gap-1 hover:underline" :style="{ color: accentOf(task) }" @click.stop="openPatientSpace(task)">
                        <PatientSpaceIcon :size="12" /> Espaço do Paciente
                      </button>
                    </div>

                    <div v-if="detailOf(task) && (detailOf(task).labels.length || detailOf(task).form_response)" class="flex items-center gap-1.5 mt-1.5 flex-wrap">
                      <span v-for="lbl in detailOf(task).labels" :key="task.id + lbl" class="cv-chip" :style="{ '--cv-rgb': hexToRgbSpaced(accentOf(task)), '--cv-deep': accentOf(task) }">🏷 {{ lbl }}</span>
                      <button v-if="detailOf(task).form_response" class="cv-btn cv-btn-sm" style="--cv-grad: linear-gradient(135deg, #5B21B6, #7C3AED); --cv-deep-rgb: 91 33 182" title="Respostas que o paciente deu no formulário — leia antes da consulta" @click.stop="openFormAnswers(task)">
                        📖 Ler respostas do formulário
                      </button>
                    </div>

                    <!-- conferência: compareceu / faltou → indicação -->
                    <div class="flex items-center gap-1.5 mt-2.5 pt-2.5 border-t border-n-weak flex-wrap" @click.stop>
                      <button class="cv-ag-act" style="--a: #059669" :class="task.attendance === 'attended' ? 'cv-ag-act-on' : ''" :disabled="savingAttendanceId === task.id" @click="setAttendance(task, 'attended')">
                        {{ isSurgeryTask(task) ? '✓ Realizada' : '✓ Compareceu' }}
                      </button>
                      <button v-if="isSurgeryTask(task)" class="cv-ag-act" style="--a: #D97706" :class="task.attendance === 'attended_not_done' ? 'cv-ag-act-on' : ''" :disabled="savingAttendanceId === task.id" title="O paciente veio, mas a cirurgia não aconteceu — registre o motivo" @click="toggleNoSurgery(task)">
                        ⚠️ Veio e não fez
                      </button>
                      <button class="cv-ag-act" style="--a: #DC2626" :class="task.attendance === 'missed' ? 'cv-ag-act-on' : ''" :disabled="savingAttendanceId === task.id" @click="setAttendance(task, 'missed')">
                        {{ isSurgeryTask(task) ? '✗ Não veio' : '✗ Faltou' }}
                      </button>
                      <div v-if="noSurgeryReasonId === task.id" class="w-full flex items-center gap-1.5 mt-1">
                        <input v-model="noSurgeryReason" class="cv-input flex-1 !h-8 text-xs" placeholder="Qual foi o motivo? (pressão alta, desistiu, exame pendente...)" @keyup.enter="confirmNoSurgery(task)" />
                        <button class="cv-btn cv-btn-sm cv-amber" :disabled="savingAttendanceId === task.id" @click="confirmNoSurgery(task)">Registrar</button>
                      </div>

                      <template v-if="task.attendance === 'attended' && !isSurgeryTask(task)">
                        <span class="text-n-slate-8 text-[10px]">·</span>
                        <button class="cv-ag-act" style="--a: #B8860B" :class="task.surgery_indication === 'indicated' ? 'cv-ag-act-on' : ''" :disabled="savingAttendanceId === task.id" @click="setIndication(task, 'indicated')">🎯 Cirurgia indicada</button>
                        <button class="cv-ag-act" style="--a: #64748B" :class="task.surgery_indication === 'not_indicated' ? 'cv-ag-act-on' : ''" :disabled="savingAttendanceId === task.id" @click="setIndication(task, 'not_indicated')">Sem indicação</button>
                        <button v-if="kind !== 'consultas' || task.modality === 'exames'" class="cv-ag-act" style="--a: #2563EB" title="Marcar um retorno presencial a partir deste atendimento" @click="scheduleFollowUpFrom(task)">📅 Marcar retorno</button>
                      </template>
                      <button v-if="!isSurgeryTask(task) && task.surgery_indication === 'indicated'" class="cv-btn cv-btn-sm" style="--cv-grad: linear-gradient(135deg, #0369A1, #38BDF8); --cv-deep-rgb: 7 89 133" title="Abre a Agenda de Cirurgias com os dados do paciente preenchidos" @click="scheduleSurgeryFrom(task)">
                        🔪 Agendar cirurgia
                      </button>
                    </div>
                    <div v-if="indicationPickerId === task.id" class="flex flex-wrap gap-1 mt-1.5" @click.stop>
                      <span class="text-[10px] text-n-slate-10 w-full">Qual procedimento foi indicado?</span>
                      <button v-for="proc in PROCEDURES" :key="proc" class="cv-chip cv-gold" :disabled="savingAttendanceId === task.id" @click="setIndication(task, 'indicated', proc)">{{ proc }}</button>
                    </div>
                  </div>
                </div>
              </template>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- ══ Modal criar/editar (a concha veste a cor do TIPO escolhido) ══ -->
    <div v-if="showModal" class="fixed inset-0 z-50 flex items-center justify-center bg-black/55 p-4" @click.self="showModal = false">
      <div class="cv-modal cv-ag-pop w-full max-w-md max-h-[92vh] flex flex-col" :style="formVars">
        <div class="cv-modal-head flex items-center gap-3">
          <span class="cv-glass w-9 h-9 flex items-center justify-center flex-shrink-0"><span :class="formKind.icon" class="text-base" /></span>
          <div class="flex-1 min-w-0">
            <h2 class="text-base font-bold leading-tight">
              {{ editingTask ? `Editar ${formKind.noun}` : (formKind.key === 'cirurgias' ? 'Agendar cirurgia' : `${formKind.article === 'o' ? 'Novo' : 'Nova'} ${formKind.noun}`) }}
            </h2>
            <p class="text-[11px] opacity-85 truncate">{{ formKind.hint }}</p>
          </div>
          <button v-if="editingTask?.contact_id" class="cv-glass-btn" title="Abrir o Espaço do Paciente" @click="openPatientSpace(editingTask)">
            <PatientSpaceIcon :size="16" /> <span class="hidden sm:inline">Paciente</span>
          </button>
          <button class="cv-glass-btn cv-iconbtn" @click="showModal = false"><span class="i-lucide-x" /></button>
        </div>

        <div class="flex-1 overflow-y-auto p-5 space-y-4">
          <!-- o TIPO (só ao criar) -->
          <div v-if="!editingTask">
            <span class="cv-label block mb-1.5">Tipo</span>
            <div class="cv-seg cv-seg-sm w-full !flex">
              <button
                v-for="kk in KINDS"
                :key="'fk' + kk.key"
                type="button"
                class="cv-ag-kind flex-1 justify-center !h-7 !px-2 text-[11px]"
                :class="form.kind === kk.key ? 'cv-ag-kind-on' : ''"
                :style="kindVarsOf(kk.key)"
                @click="setFormKind(kk.key)"
              >
                <span :class="kk.icon" class="text-xs" />
                <span class="hidden sm:inline">{{ kk.label.replace(/s$/, '') }}</span>
              </button>
            </div>
          </div>

          <div>
            <span class="cv-label block mb-1">Nome do paciente *</span>
            <input v-model="form.name" class="cv-input w-full" placeholder="Nome completo" />
          </div>

          <div v-if="form.kind === 'consultas'">
            <span class="cv-label block mb-1.5">Tipo de consulta</span>
            <div class="cv-seg cv-seg-sm">
              <button v-for="m in consultaModalities" :key="m.key" type="button" class="cv-seg-item" :class="form.modality === m.key ? 'cv-seg-on' : ''" @click="form.modality = m.key">{{ m.label }}</button>
            </div>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <span class="cv-label block mb-1">Telefone</span>
              <input v-model="form.phone" class="cv-input w-full" placeholder="(11) 98888-7777" />
            </div>
            <div>
              <span class="cv-label block mb-1">{{ procedureLabel }}</span>
              <input v-model="form.procedure" list="agenda-procedimentos" class="cv-input w-full" :placeholder="form.kind === 'exames' ? 'Pentacam, OCT…' : form.kind === 'cirurgias' ? 'Catarata, PRK…' : 'Catarata, refrativa…'" />
              <datalist id="agenda-procedimentos">
                <option v-for="p in procedureOptions" :key="p" :value="p" />
              </datalist>
            </div>
            <div>
              <span class="cv-label block mb-1">Dia *</span>
              <input v-model="form.date" type="date" class="cv-input w-full" />
            </div>
            <div>
              <span class="cv-label block mb-1">Horário</span>
              <input v-model="form.time" type="time" class="cv-input w-full" />
            </div>
            <div>
              <span class="cv-label block mb-1">Médico</span>
              <select v-model="form.doctor" class="cv-input w-full">
                <option value="">A definir</option>
                <option v-for="d in DOCTORS" :key="d.name" :value="d.name">{{ d.name }}</option>
              </select>
            </div>
            <div v-if="form.kind === 'teleconsultas'">
              <span class="cv-label block mb-1">Onde</span>
              <div class="cv-input w-full flex items-center gap-2 text-sm text-n-slate-11"><span class="i-lucide-video text-sm" /> Online (vídeo)</div>
            </div>
            <div v-else-if="form.kind !== 'cirurgias'">
              <span class="cv-label block mb-1">Unidade</span>
              <select v-model="form.unit" class="cv-input w-full">
                <option v-for="(u, key) in UNITS" :key="key" :value="key">{{ u.label }}</option>
                <option value="">Agenda pessoal (sem unidade)</option>
              </select>
            </div>
            <div v-else>
              <span class="cv-label mb-1 flex items-center justify-between">
                Local da cirurgia
                <button v-if="isAdmin" type="button" class="normal-case tracking-normal font-semibold hover:underline" style="color: var(--cv)" @click="openLocationsModal">gerenciar</button>
              </span>
              <select v-model="form.unit" class="cv-input w-full">
                <option v-for="loc in surgeryLocations" :key="loc.key" :value="loc.key">{{ loc.label }}</option>
                <option value="">A definir</option>
              </select>
            </div>
          </div>

          <div>
            <span class="cv-label block mb-1.5">Situação</span>
            <div class="cv-seg cv-seg-sm">
              <button type="button" class="cv-seg-item" :class="form.status === 'todo' && !form.canceled ? 'cv-seg-on' : ''" @click="form.status = 'todo'; form.canceled = false">Agendada</button>
              <button type="button" class="cv-seg-item" :class="form.status === 'done' && !form.canceled ? 'cv-seg-on' : ''" style="--cv-grad: linear-gradient(135deg, #047857, #10B981); --cv-deep-rgb: 6 95 70" @click="form.status = 'done'; form.canceled = false">Concluída</button>
              <button v-if="editingTask" type="button" class="cv-seg-item" :class="form.canceled ? 'cv-seg-on' : ''" style="--cv-grad: linear-gradient(135deg, #991B1B, #EF4444); --cv-deep-rgb: 153 27 27" @click="form.canceled = !form.canceled">Cancelada</button>
            </div>
            <p v-if="form.canceled" class="text-[10px] text-red-500 mt-1">Sai do calendário e conta no indicador de canceladas.</p>
          </div>

          <div>
            <span class="cv-label block mb-1">Observações</span>
            <textarea v-model="form.description" rows="2" class="cv-input w-full resize-none" placeholder="Convênio, pedido especial, retorno..." />
          </div>
        </div>

        <div class="cv-modal-foot space-y-2">
          <div class="flex gap-2">
            <button class="cv-btn cv-btn-lg flex-1" :disabled="!form.name.trim() || !form.date || isSaving" @click="save">
              <span :class="isSaving ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-check'" class="text-sm" />
              {{ isSaving ? 'Salvando…' : (editingTask ? `Salvar ${formKind.noun}` : `Agendar ${formKind.noun}`) }}
            </button>
            <button class="cv-btn cv-btn-ghost cv-btn-lg" @click="showModal = false">Cancelar</button>
          </div>
          <div v-if="editingTask">
            <button v-if="!showDeleteConfirm" class="w-full py-1 text-xs text-red-500 hover:text-red-600" @click="showDeleteConfirm = true">Excluir {{ formKind.noun }}</button>
            <div v-else class="flex items-center gap-2">
              <span class="text-xs text-n-slate-11 flex-1">Excluir este agendamento?</span>
              <button class="cv-btn cv-btn-sm cv-red" @click="removeTask">Excluir</button>
              <button class="cv-btn cv-btn-ghost cv-btn-sm" @click="showDeleteConfirm = false">Cancelar</button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Modal: janela da SALA CIRÚRGICA -->
    <div v-if="showSurgeryWindowsModal" class="fixed inset-0 z-[55] flex items-center justify-center bg-black/55 p-4" @click.self="showSurgeryWindowsModal = false">
      <div class="cv-modal cv-ag-pop w-full max-w-lg max-h-[90vh] flex flex-col" :style="kindVars('cirurgias')">
        <div class="cv-modal-head flex items-center gap-3">
          <span class="i-lucide-clock text-xl" />
          <div class="flex-1">
            <h2 class="text-base font-bold">Janela da sala cirúrgica</h2>
            <p class="text-[11px] opacity-85">dias e horários em que a sala de cada clínica parceira está disponível</p>
          </div>
          <button class="cv-glass-btn cv-iconbtn" @click="showSurgeryWindowsModal = false"><span class="i-lucide-x" /></button>
        </div>
        <div class="flex-1 overflow-y-auto p-5 space-y-3">
          <p class="text-xs text-n-slate-10">
            A ocupação e os blocos livres do trilho de cirurgias vêm daqui.
            <button v-if="isAdmin" class="font-semibold hover:underline" style="color: var(--cv)" @click="openLocationsModal">Gerenciar clínicas →</button>
          </p>
          <div v-if="!editSurgeryWindows.length" class="cv-sub text-center py-6 text-n-slate-10 text-sm">Nenhuma janela ainda — adicione a primeira.</div>
          <div v-for="(w, i) in editSurgeryWindows" :key="i" class="cv-sub grid grid-cols-2 sm:grid-cols-6 gap-2 items-center p-2.5">
            <select v-model="w.dow" :disabled="!isAdmin" class="cv-input !h-8 text-xs">
              <option v-for="(d, di) in WEEKDAY_FULL" :key="di" :value="di">{{ d }}</option>
            </select>
            <select v-model="w.location" :disabled="!isAdmin" class="cv-input !h-8 text-xs">
              <option v-for="loc in surgeryLocations" :key="loc.key" :value="loc.key">{{ loc.label }}</option>
            </select>
            <input v-model="w.start" type="time" :disabled="!isAdmin" class="cv-input !h-8 text-xs" />
            <input v-model="w.end" type="time" :disabled="!isAdmin" class="cv-input !h-8 text-xs" />
            <select v-model="w.block" :disabled="!isAdmin" class="cv-input !h-8 text-xs">
              <option :value="10">10 min</option><option :value="15">15 min</option><option :value="20">20 min</option>
              <option :value="30">30 min</option><option :value="60">1 hora</option><option :value="90">1h30</option><option :value="120">2 horas</option>
            </select>
            <button v-if="isAdmin" class="text-n-slate-9 hover:text-red-500 i-lucide-trash-2 text-sm justify-self-center" @click="removeSurgeryWindow(i)" />
          </div>
          <button v-if="isAdmin" class="cv-btn cv-btn-ghost cv-btn-sm" @click="addSurgeryWindow"><span class="i-lucide-plus text-xs" /> Adicionar janela</button>
        </div>
        <div v-if="isAdmin" class="cv-modal-foot flex gap-2">
          <button class="cv-btn flex-1" :disabled="isSavingSurgeryWindows" @click="saveSurgeryWindows">{{ isSavingSurgeryWindows ? 'Salvando…' : 'Salvar janelas' }}</button>
          <button class="cv-btn cv-btn-ghost" @click="showSurgeryWindowsModal = false">Cancelar</button>
        </div>
      </div>
    </div>

    <!-- Modal: locais de cirurgia -->
    <div v-if="showLocationsModal" class="fixed inset-0 z-[56] flex items-center justify-center bg-black/55 p-4" @click.self="showLocationsModal = false">
      <div class="cv-modal cv-ag-pop w-full max-w-sm flex flex-col" :style="kindVars('cirurgias')">
        <div class="cv-modal-head flex items-center gap-3">
          <span class="i-lucide-map-pin text-xl" />
          <h2 class="text-base font-bold flex-1">Locais de cirurgia</h2>
          <button class="cv-glass-btn cv-iconbtn" @click="showLocationsModal = false"><span class="i-lucide-x" /></button>
        </div>
        <div class="p-5 space-y-2">
          <p class="text-xs text-n-slate-10">Clínicas parceiras onde as cirurgias acontecem (ex.: IOP). Aparecem no campo "Local da cirurgia" ao agendar.</p>
          <div v-for="(loc, i) in locationsDraft" :key="i" class="flex items-center gap-2">
            <input v-model="loc.label" class="cv-input flex-1" placeholder="Nome da clínica (ex.: IOP)" />
            <button class="text-n-slate-9 hover:text-red-500 i-lucide-trash-2 text-sm" @click="removeLocationRow(i)" />
          </div>
          <button class="cv-btn cv-btn-ghost cv-btn-sm" @click="addLocationRow"><span class="i-lucide-plus text-xs" /> Adicionar local</button>
        </div>
        <div class="cv-modal-foot flex gap-2">
          <button class="cv-btn flex-1" :disabled="isSavingLocations" @click="saveLocations">{{ isSavingLocations ? 'Salvando…' : 'Salvar locais' }}</button>
          <button class="cv-btn cv-btn-ghost" @click="showLocationsModal = false">Cancelar</button>
        </div>
      </div>
    </div>

    <!-- Modal: janelas de avaliação dos médicos + conferência → CRM -->
    <div v-if="showWindowsModal" class="fixed inset-0 z-50 flex items-center justify-center bg-black/55 p-4" @click.self="showWindowsModal = false; isEditingWindows = false">
      <div class="cv-modal cv-ag-pop w-full max-w-lg max-h-[90vh] flex flex-col">
        <div class="cv-modal-head flex items-center gap-3">
          <span class="i-lucide-clock text-xl" />
          <div class="flex-1">
            <h2 class="text-base font-bold">Janelas de avaliação dos médicos</h2>
            <p class="text-[11px] opacity-85">quando cada médico atende, em qual unidade e de quanto em quanto tempo</p>
          </div>
          <button v-if="isAdmin && !isEditingWindows" class="cv-glass-btn" @click="startEditWindows"><span class="i-lucide-pencil text-xs" /> Editar</button>
          <button class="cv-glass-btn cv-iconbtn" @click="showWindowsModal = false; isEditingWindows = false"><span class="i-lucide-x" /></button>
        </div>
        <div class="flex-1 overflow-y-auto p-5 space-y-4">
          <!-- médicos + FECHAR/reabrir a agenda -->
          <div class="space-y-1.5">
            <div v-for="d in DOCTORS" :key="d.name" class="cv-sub flex items-center gap-2 flex-wrap px-3 py-2" :class="isDoctorClosed(d.name) ? 'opacity-70' : ''">
              <span class="w-2.5 h-2.5 rounded-full flex-shrink-0" :style="{ backgroundColor: d.color }" />
              <span class="text-xs font-semibold text-n-slate-12" :class="isDoctorClosed(d.name) ? 'line-through' : ''">{{ d.name }}</span>
              <span v-if="isDoctorClosed(d.name)" class="cv-chip cv-red">agenda fechada</span>
              <button v-if="isAdmin" class="cv-btn cv-btn-ghost cv-btn-sm ml-auto" :class="isDoctorClosed(d.name) ? 'cv-green' : 'cv-btn-danger'" :disabled="togglingDoctor === d.name" @click="toggleDoctorClosed(d.name)">
                {{ isDoctorClosed(d.name) ? '▶️ Reabrir agenda' : '⏸ Fechar agenda' }}
              </button>
            </div>
            <p v-if="isAdmin" class="text-[10px] text-n-slate-9">fechar tira o médico de toda a agenda na hora; para abrir em dias/horários personalizados, use o <b>Editar</b>.</p>
          </div>

          <template v-if="!isEditingWindows">
            <div v-for="dow in [1, 2, 3, 4, 5]" :key="dow">
              <p class="cv-label mb-1.5">{{ WEEKDAY_FULL[dow] }}</p>
              <div class="space-y-1.5">
                <div v-for="w in windowsByDow[dow] || []" :key="w.doctor + w.start" class="cv-row flex items-center gap-2 px-3 py-2 flex-wrap" :style="{ '--cv-rgb': hexToRgbSpaced(doctorColor(w.doctor)) }">
                  <span class="w-2 h-2 rounded-full flex-shrink-0" :style="{ backgroundColor: doctorColor(w.doctor) }" />
                  <span class="text-sm font-medium text-n-slate-12">{{ w.doctor }}</span>
                  <span class="cv-chip" :style="{ '--cv-rgb': hexToRgbSpaced(UNITS[w.unit]?.color || '#64748B'), '--cv-deep': UNITS[w.unit]?.color }">{{ UNITS[w.unit]?.label || w.unit }}</span>
                  <span class="text-xs text-n-slate-10 ml-auto">{{ w.turno }} · {{ w.start }}–{{ w.end }} · {{ w.block }} min</span>
                </div>
                <p v-if="!(windowsByDow[dow] || []).length" class="text-xs text-n-slate-9 pl-1">— sem janela</p>
              </div>
            </div>
            <div class="cv-sub flex items-center gap-2 px-3 py-2 text-xs text-n-slate-10">
              <span class="i-lucide-lock text-sm" /> Sábado e domingo: bloqueados — não existe agenda em nenhuma unidade.
            </div>

            <!-- Conferência do dia → colunas do CRM (admin) -->
            <div v-if="isAdmin" class="cv-sub p-3.5 space-y-2.5 cv-gold">
              <p class="text-xs font-bold text-n-slate-12 flex items-center gap-1.5">
                <span class="i-lucide-list-checks text-sm" style="color: #B8860B" /> Conferência do dia → CRM
              </p>
              <p class="text-[11px] text-n-slate-10 leading-relaxed">
                Ao marcar <b>Compareceu / Faltou / Cirurgia indicada</b> na lista do dia, o card do paciente move sozinho para a coluna escolhida — e as automações dessa coluna disparam.
              </p>
              <div class="cv-row cv-amber p-2.5 space-y-2">
                <p class="text-[10px] font-semibold text-n-slate-11">⏰ Prazo da conferência — sem conferir até o horário, nasce a tarefa "Concluir a conferência do dia" para a responsável</p>
                <div class="grid grid-cols-1 sm:grid-cols-3 gap-2">
                  <div>
                    <span class="cv-label block mb-0.5">Consultas — responsável</span>
                    <select v-model="attendanceOwners.consulta_user_id" class="cv-input w-full !h-8 text-xs">
                      <option value="">Ninguém (desligado)</option>
                      <option v-for="agent in agents" :key="agent.id" :value="String(agent.id)">{{ agent.name }}</option>
                    </select>
                  </div>
                  <div>
                    <span class="cv-label block mb-0.5">Cirurgias — responsável</span>
                    <select v-model="attendanceOwners.cirurgia_user_id" class="cv-input w-full !h-8 text-xs">
                      <option value="">Ninguém (desligado)</option>
                      <option v-for="agent in agents" :key="agent.id" :value="String(agent.id)">{{ agent.name }}</option>
                    </select>
                  </div>
                  <div>
                    <span class="cv-label block mb-0.5">Horário limite</span>
                    <input v-model="attendanceOwners.deadline" type="time" class="cv-input w-full !h-8 text-xs" />
                  </div>
                </div>
              </div>
              <div class="space-y-2">
                <div v-for="opt in [
                  { key: 'attended_stage_id', label: '✓ Compareceu → mover card para' },
                  { key: 'missed_stage_id', label: '✗ Faltou → mover card para' },
                  { key: 'indicated_stage_id', label: '🎯 Cirurgia indicada → mover card para' },
                  { key: 'surgery_done_stage_id', label: '🔪 Cirurgia realizada → mover card para' },
                  { key: 'surgery_missed_stage_id', label: '✗ Não veio à cirurgia → mover card para' },
                ]" :key="opt.key">
                  <span class="cv-label block mb-0.5">{{ opt.label }}</span>
                  <select v-model="attendanceStages[opt.key]" class="cv-input w-full !h-8 text-xs">
                    <option value="">Não mover</option>
                    <option v-for="s in allCrmStages" :key="s.id" :value="s.id">{{ s.name }} ({{ s.pipeline }})</option>
                  </select>
                </div>
              </div>
              <button class="cv-btn w-full" :disabled="isSavingAttendanceCfg" @click="saveAttendanceStages">{{ isSavingAttendanceCfg ? 'Salvando…' : 'Salvar conferência do dia' }}</button>
            </div>
          </template>

          <!-- edição (admin) -->
          <template v-else>
            <div v-for="(w, i) in editWindows" :key="i" class="cv-sub p-3 space-y-2">
              <div class="flex items-center gap-2 flex-wrap">
                <select v-model.number="w.dow" class="cv-input !h-8 text-xs !w-auto">
                  <option v-for="d in [1, 2, 3, 4, 5]" :key="d" :value="d">{{ WEEKDAY_FULL[d] }}</option>
                </select>
                <select v-model="w.doctor" class="cv-input !h-8 text-xs !w-auto">
                  <option v-for="d in DOCTORS" :key="d.name" :value="d.name">{{ d.name }}</option>
                </select>
                <select v-model="w.unit" class="cv-input !h-8 text-xs !w-auto">
                  <option v-for="(u, key) in UNITS" :key="key" :value="key">{{ u.label }}</option>
                </select>
                <button class="ml-auto text-n-slate-9 hover:text-red-500 i-lucide-trash-2 text-sm" title="Remover janela" @click="removeWindow(i)" />
              </div>
              <div class="flex items-center gap-2 flex-wrap text-xs text-n-slate-11">
                <select v-model="w.turno" class="cv-input !h-8 text-xs !w-auto"><option value="Manhã">Manhã</option><option value="Tarde">Tarde</option></select>
                das <input v-model="w.start" type="time" class="cv-input !h-8 text-xs !w-auto" />
                às <input v-model="w.end" type="time" class="cv-input !h-8 text-xs !w-auto" />
                <span class="text-n-slate-9">(fim exclusivo)</span> · blocos de
                <select v-model.number="w.block" class="cv-input !h-8 text-xs !w-auto">
                  <option :value="5">5 min</option><option :value="10">10 min</option><option :value="15">15 min</option><option :value="20">20 min</option><option :value="30">30 min</option>
                </select>
              </div>
            </div>
            <button class="cv-tile-add w-full py-2 text-xs" @click="addWindow">+ Adicionar janela</button>
            <div class="flex gap-2">
              <button class="cv-btn flex-1" :disabled="isSavingWindows" @click="saveWindows">{{ isSavingWindows ? 'Salvando…' : 'Salvar janelas' }}</button>
              <button class="cv-btn cv-btn-ghost" @click="isEditingWindows = false">Cancelar</button>
            </div>
          </template>
        </div>
      </div>
    </div>

    <!-- botão + flutuante -->
    <button class="cv-ag-fab" :title="newLabel" @click="openCreateFab">
      <span class="i-lucide-plus text-2xl" />
    </button>
  </div>
</template>
