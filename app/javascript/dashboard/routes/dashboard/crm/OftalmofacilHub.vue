<script setup>
// 🏥 item 229 (24/09): ambiente "Oftalmofácil" DENTRO do sistema — o hub de
// parceiros espelhado (só leitura, a cada 15 min) no design da casa, NAVEGÁVEL
// como um sistema: Visão geral · Agenda · Itens · Parceiros · Clínicas ·
// Pacientes. Tabelas de verdade, calendário da semana, ficha por item e um
// tutorial de primeiro uso com balões (pedido dele, 24/09 noite).
import { ref, computed, watch, onMounted, onBeforeUnmount, nextTick } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store.js';
import { frontendURL } from 'dashboard/helper/URLHelper';
import CrmAPI from 'dashboard/api/crm';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import HBars from 'dashboard/components-next/cevico/HBars.vue';
import ShareBar from 'dashboard/components-next/cevico/ShareBar.vue';
import AgendaTimeColumn from 'dashboard/components-next/cevico/agenda/AgendaTimeColumn.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';

const route = useRoute();
const router = useRouter();
const currentUser = useMapGetter('getCurrentUser');
const accountId = computed(() => route.params.accountId);
const isAdmin = computed(() => currentUser.value?.role === 'administrator' || currentUser.value?.accounts?.some(a => Number(a.id) === Number(accountId.value) && a.role === 'administrator'));

const pal = useCevicoPalette({
  scope: 'crm:oftalmofacil',
  blocks: [
    { id: 'agenda', label: 'Volume de agendamentos', icon: 'i-lucide-calendar-check' },
    { id: 'parceiros', label: 'Parceiros', icon: 'i-lucide-handshake' },
    { id: 'meses', label: 'Meses', icon: 'i-lucide-bar-chart-3' },
    { id: 'lista', label: 'Registros', icon: 'i-lucide-list' },
  ],
});
const { cvVars, blockVars } = pal;
const HERO = 'linear-gradient(135deg, #0B3D3A 0%, #0F766E 55%, #2DD4BF 100%)';
const NAV_VARS = { '--k-deep': '#0F766E', '--k-grad': 'linear-gradient(135deg, #0F766E, #2DD4BF)' };

// ── áreas do ambiente (navegação própria, como um sistema) ──
// "Registros" = a planilha de tudo que aconteceu; fica por último, à direita (pedido dele)
const VIEWS = [
  { key: 'overview', label: 'Visão geral', icon: 'i-lucide-gauge', hint: 'volume de agendamentos, resumo e próximos dias' },
  { key: 'agenda', label: 'Agenda', icon: 'i-lucide-calendar-days', hint: 'mês, semana e dia do hub' },
  { key: 'partners', label: 'Parceiros', icon: 'i-lucide-handshake', hint: 'quem indica e quanto' },
  { key: 'clinics', label: 'Clínicas', icon: 'i-lucide-building-2', hint: 'onde acontece e o de-para de local' },
  { key: 'patients', label: 'Pacientes', icon: 'i-lucide-users', hint: 'pessoas do hub e o cadastro aqui' },
  { key: 'items', label: 'Registros', icon: 'i-lucide-table', hint: 'a planilha de tudo que aconteceu, com filtros e busca', right: true },
];
const view = ref(VIEWS.some(v => v.key === route.query.view) ? route.query.view : 'overview');
watch(view, v => { router.replace({ query: { ...route.query, view: v } }).catch(() => {}); });
const period = ref({ preset: 'month', from: '', to: '' });

// ── dados ──
const overview = ref(null);
const isLoading = ref(false);
const loadError = ref('');
const items = ref(null);
const isLoadingItems = ref(false);
const blankFilters = () => ({ side: '', status: '', agenda: '', partner: '', clinic: '', type: '', q: '', unmatched: false, usePeriod: true });
const filters = ref(blankFilters());
const page = ref(1);
const patients = ref(null);
const isLoadingPatients = ref(false);
const patientFilters = ref({ q: '', side: '', usePeriod: false });
const patientsPage = ref(1);
const week = ref(null); // itens da semana da Agenda
const isLoadingWeek = ref(false);
const detail = ref(null);

const STATUS = [
  { key: 'agendada', label: 'Agendada', tone: 'cv-blue', dot: '#3B82F6' },
  { key: 'aguardando_pagamento', label: 'Aguard. pagamento', tone: 'cv-amber', dot: '#F59E0B' },
  { key: 'realizada', label: 'Realizada', tone: 'cv-green', dot: '#10B981' },
  { key: 'cancelada', label: 'Cancelada', tone: 'cv-red', dot: '#EF4444' },
  { key: 'ausente', label: 'Não compareceu', tone: 'cv-pink', dot: '#EC4899' },
];
const statusMeta = k => STATUS.find(s => s.key === k) || { key: k, label: k || 'Outro', tone: 'cv-slate', dot: '#94a3b8' };
const UNIT_LABEL = { paulista: 'Av. Paulista', tatuape: 'Tatuapé', online: 'Online', iop: 'IOP', ocular_surgery: 'Ocular Surgery' };
const unitLabel = key => UNIT_LABEL[key] || key || '';
const pad = n => String(n).padStart(2, '0');
const dateKey = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const fmtDate = d => (d ? new Date(`${d}T12:00:00`).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' }) : '');
const fmtDateLong = d => (d ? new Date(`${d}T12:00:00`).toLocaleDateString('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit' }) : '');
const fmtMonth = m => { const [y, mo] = String(m).split('-'); return new Date(Number(y), Number(mo) - 1, 1).toLocaleDateString('pt-BR', { month: 'short', year: '2-digit' }); };
const fmtBRL = v => Number(v || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });
const fmtWhen = iso => (iso ? new Date(iso).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' }) : '—');
const pct = (a, b) => (b ? Math.round((a / b) * 100) : 0);

let seq = 0;
const fetchOverview = async () => {
  const mine = ++seq;
  isLoading.value = true;
  loadError.value = '';
  try {
    const { data } = await CrmAPI.oftalmofacilOverview({ from: period.value.from, to: period.value.to });
    if (mine === seq) overview.value = data;
  } catch (e) {
    loadError.value = e?.response?.data?.error || 'Não consegui ler o espelho do Oftalmofácil.';
  } finally {
    if (mine === seq) isLoading.value = false;
  }
};
let seqItems = 0;
const fetchItems = async () => {
  const mine = ++seqItems;
  isLoadingItems.value = true;
  try {
    const f = filters.value;
    const params = { page: page.value, per: 50 };
    ['side', 'status', 'agenda', 'partner', 'clinic', 'type', 'q'].forEach(k => { if (f[k]) params[k] = f[k]; });
    if (f.unmatched) params.unmatched = 'true';
    if (f.usePeriod) { params.from = period.value.from; params.to = period.value.to; }
    const { data } = await CrmAPI.oftalmofacilItems(params);
    if (mine === seqItems) items.value = data;
  } catch (e) {
    loadError.value = e?.response?.data?.error || 'Não consegui listar os itens.';
  } finally {
    if (mine === seqItems) isLoadingItems.value = false;
  }
};
let seqPat = 0;
const fetchPatients = async () => {
  const mine = ++seqPat;
  isLoadingPatients.value = true;
  try {
    const f = patientFilters.value;
    const params = { page: patientsPage.value, per: 50 };
    if (f.q) params.q = f.q;
    if (f.side) params.side = f.side;
    if (f.usePeriod) { params.from = period.value.from; params.to = period.value.to; }
    const { data } = await CrmAPI.oftalmofacilPatients(params);
    if (mine === seqPat) patients.value = data;
  } catch (e) {
    loadError.value = e?.response?.data?.error || 'Não consegui listar os pacientes.';
  } finally {
    if (mine === seqPat) isLoadingPatients.value = false;
  }
};

// ── Agenda da semana ──
const startOfWeek = d => { const x = new Date(d); x.setHours(0, 0, 0, 0); x.setDate(x.getDate() - ((x.getDay() + 6) % 7)); return x; };
const weekStart = ref(startOfWeek(new Date()));
const weekDays = computed(() => Array.from({ length: 7 }, (_, i) => { const d = new Date(weekStart.value); d.setDate(d.getDate() + i); return d; }));
const todayKey = dateKey(new Date());
let seqWeek = 0;
const fetchWeek = async () => {
  const mine = ++seqWeek;
  isLoadingWeek.value = true;
  try {
    const end = new Date(weekStart.value); end.setDate(end.getDate() + 6);
    const { data } = await CrmAPI.oftalmofacilItems({ from: dateKey(weekStart.value), to: dateKey(end), per: 200 });
    if (mine === seqWeek) week.value = data;
  } catch (e) {
    loadError.value = e?.response?.data?.error || 'Não consegui ler a semana.';
  } finally {
    if (mine === seqWeek) isLoadingWeek.value = false;
  }
};
const weekByDay = computed(() => {
  const map = {};
  (week.value?.rows || []).forEach(r => { (map[r.surgery_date] ||= []).push(r); });
  Object.values(map).forEach(list => list.sort((a, b) => String(a.surgery_hour || '99').localeCompare(String(b.surgery_hour || '99'))));
  return map;
});
const shiftWeek = n => { const d = new Date(weekStart.value); d.setDate(d.getDate() + n * 7); weekStart.value = d; };
const weekLabel = computed(() => { const a = weekDays.value[0]; const b = weekDays.value[6]; return `${a.toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' })} – ${b.toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' })}`; });

// ── Agenda do MÊS (pedido dele): grade de semanas, cada dia com os itens ──
const calMode = ref('month');
const monthStart = ref(new Date(new Date().getFullYear(), new Date().getMonth(), 1));
const month = ref(null);
const isLoadingMonth = ref(false);
const monthGridStart = computed(() => startOfWeek(monthStart.value));
const monthCells = computed(() => {
  const cells = [];
  const d = new Date(monthGridStart.value);
  for (let i = 0; i < 42; i += 1) { cells.push(new Date(d)); d.setDate(d.getDate() + 1); }
  // corta a 6ª semana se ela já for toda do mês seguinte
  const last = cells[35];
  return last.getMonth() !== monthStart.value.getMonth() ? cells.slice(0, 35) : cells;
});
let seqMonth = 0;
const fetchMonth = async () => {
  const mine = ++seqMonth;
  isLoadingMonth.value = true;
  try {
    const cells = monthCells.value;
    const { data } = await CrmAPI.oftalmofacilItems({ from: dateKey(cells[0]), to: dateKey(cells[cells.length - 1]), per: 500 });
    if (mine === seqMonth) month.value = data;
  } catch (e) {
    loadError.value = e?.response?.data?.error || 'Não consegui ler o mês.';
  } finally {
    if (mine === seqMonth) isLoadingMonth.value = false;
  }
};
const monthByDay = computed(() => {
  const map = {};
  (month.value?.rows || []).forEach(r => { (map[r.surgery_date] ||= []).push(r); });
  Object.values(map).forEach(list => list.sort((a, b) => String(a.surgery_hour || '99').localeCompare(String(b.surgery_hour || '99'))));
  return map;
});
const shiftMonth = n => { monthStart.value = new Date(monthStart.value.getFullYear(), monthStart.value.getMonth() + n, 1); };
const monthLabel = computed(() => monthStart.value.toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' }));
const monthTotals = computed(() => {
  const rows = (month.value?.rows || []).filter(r => new Date(`${r.surgery_date}T12:00:00`).getMonth() === monthStart.value.getMonth());
  const by = k => rows.filter(r => r.status_kind === k).length;
  return { total: rows.length, realizada: by('realizada'), agendada: by('agendada') + by('aguardando_pagamento'), cancelada: by('cancelada') + by('ausente') };
});
// ── DIA e SEMANA no formato da nossa Agenda (coluna de horas + balões) ──
const dayCursor = ref(new Date());
const HOURS = Array.from({ length: 14 }, (_, i) => 7 + i); // 07h … 20h
const WEEK_PX = 48;
const DAY_PX = 80;
const toTask = r => ({ id: r.id, due_at: `${r.surgery_date}T${r.surgery_hour || '08:00'}:00`, title: r.patient_name, _row: r, _nohour: !r.surgery_hour });
const tasksOfDay = d => (weekByDay.value[dateKey(d)] || []).map(toTask);
const accentOfTask = t => statusMeta(t._row.status_kind).dot;
const nameOfTask = t => `${t._row.own ? '⭐ ' : ''}${t._row.patient_name || '(sem nome)'}${t._nohour ? ' · sem hora' : ''}`;
const durationOfTask = () => 30;
const openTask = t => openDetail(t._row);
const openDay = d => { dayCursor.value = new Date(d); calMode.value = 'day'; };
const shiftDay = n => { const d = new Date(dayCursor.value); d.setDate(d.getDate() + n); dayCursor.value = d; };
const dayLabel = computed(() => dayCursor.value.toLocaleDateString('pt-BR', { weekday: 'long', day: '2-digit', month: 'long' }));
const dayRows = computed(() => weekByDay.value[dateKey(dayCursor.value)] || []);
watch(dayCursor, d => { const ws = startOfWeek(d); if (dateKey(ws) !== dateKey(weekStart.value)) weekStart.value = ws; });
const dayCellMax = 3;

// ── item 243: navegação no jeito do Google Agenda — [Hoje] [‹] [›] + título
// do período (clique = calendário para pular de data) + busca de paciente
// que leva ao dia dele. Uma barra só para Mês · Semana · Dia. ──
const cap1 = t => (t ? t.charAt(0).toUpperCase() + t.slice(1) : t);
const calTitle = computed(() => {
  if (calMode.value === 'month') return cap1(monthLabel.value);
  if (calMode.value === 'day')
    return cap1(dayCursor.value.toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }));
  const a = weekDays.value[0];
  const b = weekDays.value[6];
  const sameMonth = a.getMonth() === b.getMonth();
  const left = sameMonth ? a.getDate() : a.toLocaleDateString('pt-BR', { day: 'numeric', month: 'short' });
  return `${left} – ${b.toLocaleDateString('pt-BR', { day: 'numeric', month: 'long', year: 'numeric' })}`;
});
const calLoading = computed(() => (calMode.value === 'month' ? isLoadingMonth.value : isLoadingWeek.value));
const calStep = n => {
  if (calMode.value === 'month') shiftMonth(n);
  else if (calMode.value === 'week') shiftWeek(n);
  else shiftDay(n);
};
const jumpTo = d => {
  const x = new Date(d);
  dayCursor.value = x;
  weekStart.value = startOfWeek(x);
  const ms = new Date(x.getFullYear(), x.getMonth(), 1);
  if (dateKey(ms) !== dateKey(monthStart.value)) monthStart.value = ms;
};
const calToday = () => jumpTo(new Date());
// calendário do título (pular para qualquer data)
const showCalPicker = ref(false);
const pickerCursor = ref(new Date(new Date().getFullYear(), new Date().getMonth(), 1));
const pickerShift = n => { pickerCursor.value = new Date(pickerCursor.value.getFullYear(), pickerCursor.value.getMonth() + n, 1); };
const pickerLabel = computed(() => cap1(pickerCursor.value.toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' })));
const pickerDays = computed(() => {
  const start = startOfWeek(pickerCursor.value);
  return Array.from({ length: 42 }, (_, i) => { const d = new Date(start); d.setDate(d.getDate() + i); return d; });
});
const pickDay = d => { jumpTo(d); showCalPicker.value = false; };
// item 244: o mini mês fica SEMPRE aberto no bloco "Calendário" e segue a data
watch([calMode, dayCursor, monthStart], () => {
  const base = calMode.value === 'month' ? monthStart.value : dayCursor.value;
  pickerCursor.value = new Date(base.getFullYear(), base.getMonth(), 1);
}, { immediate: true });
const pickerInView = d => {
  if (calMode.value === 'day') return dateKey(d) === dateKey(dayCursor.value);
  if (calMode.value === 'week') { const a = weekStart.value; const b = new Date(a); b.setDate(b.getDate() + 6); return d >= a && d <= new Date(b.getFullYear(), b.getMonth(), b.getDate(), 23, 59); }
  return false;
};
const pickerWeeksRows = computed(() => {
  const days = pickerDays.value;
  const rows = [];
  for (let i = 0; i < days.length; i += 7) rows.push(days.slice(i, i + 7));
  return rows[5] && rows[5][0].getMonth() !== pickerCursor.value.getMonth() ? rows.slice(0, 5) : rows;
});
const calModeTitle = computed(() => ({ month: 'Mês', week: 'Semana', day: 'Dia' })[calMode.value]);
// 🔎 encontrar paciente na agenda do hub (nome, telefone ou CPF) → abre o dia dele
const calQuery = ref('');
const calHits = ref([]);
const calSearching = ref(false);
let calQTimer = null;
watch(calQuery, q => {
  clearTimeout(calQTimer);
  if (String(q || '').trim().length < 2) { calHits.value = []; return; }
  calQTimer = setTimeout(async () => {
    calSearching.value = true;
    try {
      const { data } = await CrmAPI.oftalmofacilItems({ q: q.trim(), per: 8 });
      calHits.value = data?.rows || [];
    } catch { calHits.value = []; } finally { calSearching.value = false; }
  }, 300);
});
const goToHit = r => {
  jumpTo(new Date(`${r.surgery_date}T12:00:00`));
  calMode.value = 'day';
  calQuery.value = '';
  calHits.value = [];
};

// ── sanfona nos itens (pedido dele: expandir na linha, não popup) ──
const expandedId = ref(null);
const rowDetails = ref({});
const toggleRow = async row => {
  if (expandedId.value === row.id) { expandedId.value = null; return; }
  expandedId.value = row.id;
  if (!rowDetails.value[row.id]) {
    try {
      const { data } = await CrmAPI.oftalmofacilItem(row.id);
      rowDetails.value = { ...rowDetails.value, [row.id]: data };
    } catch { rowDetails.value = { ...rowDetails.value, [row.id]: row }; }
  }
};
const rowDetail = row => rowDetails.value[row.id] || row;

// ── representatividade (visão geral, clínicas, parceiros) ──
const procRows = computed(() => (overview.value?.procedures || []).slice(0, 8).map(x => ({ label: x.name, values: [x.total, x.realizada], hint: `${x.total} itens · ${x.realizada} realizados` })));
const clinicShare = computed(() => (overview.value?.clinics || []).map(c => ({ label: c.name, value: c.total })));
const partnerShare = computed(() => (overview.value?.partners || []).map(p => ({ label: p.own ? `⭐ ${p.name}` : p.name, value: p.total })));
const typeShare = computed(() => (overview.value?.types || []).map(t => ({ label: t.name, value: t.total })));
const grandTotal = computed(() => Number(overview.value?.totals?.total || 0));
const share = n => (grandTotal.value ? Math.round((n / grandTotal.value) * 100) : 0);
const rate = (a, b) => (b ? Math.round((a / b) * 100) : 0);
const miniRows = list => (list || []).map(x => ({ label: x.name, values: [x.total] }));
// muitos parceiros/clínicas (pedido dele): cartões só dos 7 mais representativos; o resto pela busca
const TOP_CARDS = 7;
const partnerQuery = ref('');
const clinicQuery = ref('');
const norm = v => String(v || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
const partnerCards = computed(() => {
  const all = overview.value?.partners || [];
  const q = norm(partnerQuery.value.trim());
  return q ? all.filter(p => norm(p.name).includes(q)) : all.slice(0, TOP_CARDS);
});
const clinicCards = computed(() => {
  const all = overview.value?.clinics || [];
  const q = norm(clinicQuery.value.trim());
  return q ? all.filter(c => norm(c.name).includes(q)) : all.slice(0, TOP_CARDS);
});

const openDetail = async row => {
  detail.value = { ...row };
  try {
    const { data } = await CrmAPI.oftalmofacilItem(row.id);
    detail.value = data;
  } catch {
    detail.value = row;
  }
};
const goItems = (patch = {}) => { filters.value = { ...blankFilters(), ...patch }; page.value = 1; view.value = 'items'; };
const goPatients = (patch = {}) => { patientFilters.value = { q: '', side: '', usePeriod: false, ...patch }; patientsPage.value = 1; view.value = 'patients'; };
const totalPages = computed(() => (items.value ? Math.max(1, Math.ceil(items.value.total / items.value.per)) : 1));
const patientPages = computed(() => (patients.value ? Math.max(1, Math.ceil(patients.value.total / patients.value.per)) : 1));

let qTimer = null;
watch(period, () => { fetchOverview(); if (view.value === 'items' && filters.value.usePeriod) fetchItems(); if (view.value === 'patients' && patientFilters.value.usePeriod) fetchPatients(); }, { deep: true });
watch(view, v => {
  if (v === 'items' && !items.value) fetchItems();
  if (v === 'patients' && !patients.value) fetchPatients();
  if (v === 'agenda') { if (calMode.value === 'month' && !month.value) fetchMonth(); if (!week.value) fetchWeek(); }
});
watch(() => [filters.value.side, filters.value.status, filters.value.agenda, filters.value.partner, filters.value.clinic, filters.value.type, filters.value.unmatched, filters.value.usePeriod], () => { page.value = 1; fetchItems(); });
watch(() => filters.value.q, () => { clearTimeout(qTimer); qTimer = setTimeout(() => { page.value = 1; fetchItems(); }, 300); });
watch(page, fetchItems);
watch(() => [patientFilters.value.side, patientFilters.value.usePeriod], () => { patientsPage.value = 1; fetchPatients(); });
watch(() => patientFilters.value.q, () => { clearTimeout(qTimer); qTimer = setTimeout(() => { patientsPage.value = 1; fetchPatients(); }, 300); });
watch(patientsPage, fetchPatients);
watch(weekStart, fetchWeek);
watch(monthStart, fetchMonth);
watch(calMode, m => { if (m === 'month' && !month.value) fetchMonth(); if (m !== 'month' && !week.value) fetchWeek(); });

// links
const patientUrl = row => (row.contact?.id ? frontendURL(`accounts/${accountId.value}/patient/${row.contact.id}`) : null);
const agendaUrl = row => frontendURL(`accounts/${accountId.value}/agenda`, { date: row.surgery_date, kind: row.task?.task_type === 'consulta' ? ((row.procedure_type || '').toLowerCase().includes('exam') ? 'exames' : 'consultas') : 'cirurgias' });
const integrationsUrl = computed(() => frontendURL(`accounts/${accountId.value}/crm/integrations`));
const agendaStateOf = row => {
  if (!row.task) return { label: 'fora da Agenda', tone: 'cv-slate', icon: 'i-lucide-calendar-x' };
  if (row.task.canceled) return { label: 'cancelada', tone: 'cv-red', icon: 'i-lucide-calendar-off' };
  if (row.task.attendance === 'attended') return { label: 'realizada', tone: 'cv-green', icon: 'i-lucide-calendar-check' };
  if (row.task.attendance === 'missed') return { label: 'faltou', tone: 'cv-pink', icon: 'i-lucide-calendar-x' };
  if (!row.task.unit) return { label: 'na Agenda · sem local', tone: 'cv-amber', icon: 'i-lucide-map-pin-off' };
  return { label: `na Agenda · ${unitLabel(row.task.unit)}`, tone: 'cv-green', icon: 'i-lucide-calendar-check' };
};
const partnerOptions = computed(() => (overview.value?.partners || []).map(p => p.name));
const clinicOptions = computed(() => (overview.value?.clinics || []).map(c => c.name).filter(n => n && !n.startsWith('(')));
const typeOptions = computed(() => (overview.value?.types || []).map(t => t.name).filter(n => n && !n.startsWith('(')));
const monthMax = computed(() => Math.max(1, ...(overview.value?.months || []).map(m => m.total)));
const health = computed(() => overview.value?.agenda || {});

// 🔎 item 249: CONFERÊNCIA DO DIA — cada item do hub para a data × nossa Agenda
const nextBusinessDay = () => {
  const d = new Date();
  d.setDate(d.getDate() + 1);
  while (d.getDay() === 0 || d.getDay() === 6) d.setDate(d.getDate() + 1);
  return dateKey(d);
};
const dayCheckDate = ref(nextBusinessDay());
const dayCheck = ref(null);
const dayCheckLoading = ref(false);
const dayCheckFixing = ref(false);
const dayCheckMsg = ref('');
const dayCheckHub = ref(true);
const fetchDayCheck = async () => {
  dayCheckLoading.value = true;
  dayCheckMsg.value = '';
  try {
    const { data } = await CrmAPI.oftalmofacilDayCheck({ date: dayCheckDate.value, hub: dayCheckHub.value ? 1 : 0 });
    dayCheck.value = data;
  } catch (e) {
    dayCheckMsg.value = 'Não consegui conferir o dia. Tente de novo.';
  } finally {
    dayCheckLoading.value = false;
  }
};
const reconcileDay = async () => {
  dayCheckFixing.value = true;
  dayCheckMsg.value = '';
  try {
    const { data } = await CrmAPI.oftalmofacilReconcileDay(dayCheckDate.value);
    dayCheck.value = data;
    const errs = (data.errors || []).length;
    dayCheckMsg.value = `${data.fixed || 0} item(ns) reprocessado(s) · ${data.tasks_created || 0} agendamento(s) criado(s) · ${data.tasks_updated || 0} atualizado(s)${errs ? ` · ${errs} aviso(s)` : ''}`;
  } catch (e) {
    dayCheckMsg.value = e?.response?.data?.error || 'Não consegui trazer os agendamentos. Tente de novo.';
  } finally {
    dayCheckFixing.value = false;
  }
};
const dayCheckProblems = computed(() => (dayCheck.value?.rows || []).filter(r => !['ok', 'cancelada'].includes(r.situation)));
const dayCheckOk = computed(() => (dayCheck.value?.rows || []).filter(r => r.situation === 'ok'));
const dayCheckTone = s => (s === 'ok' ? 'cv-green' : s === 'cancelada' ? 'cv-slate' : ['sem_agendamento', 'nao_lido', 'hora_errada'].includes(s) ? 'cv-amber' : 'cv-rose');
const dayCheckLabel = computed(() => {
  if (!dayCheck.value) return '';
  const d = new Date(`${dayCheck.value.date}T12:00:00`);
  return `${dayCheck.value.weekday}, ${d.toLocaleDateString('pt-BR')}`;
});
const pageStyle = computed(() => cvVars.value);
const upcomingRows = computed(() => (week.value?.rows || []).filter(r => r.surgery_date >= todayKey && r.status_kind !== 'cancelada').slice(0, 8));

// ── 🎓 tutorial de primeiro uso (balões guiados) ──
const TOUR_KEY = 'cevico_of_tour_done';
const TOUR = [
  { target: 'nav', view: 'overview', title: 'As áreas do ambiente', text: 'Aqui você navega como no Oftalmofácil, só que organizado: Visão geral, Agenda, Parceiros, Clínicas, Pacientes e, à direita, os Registros (a planilha de tudo que aconteceu). Tudo é só leitura do espelho.' },
  { target: 'period', view: 'overview', title: 'O período', text: 'A régua filtra pela data do procedimento. Vale para a Visão geral, os Itens (quando "no período" estiver ligado), Parceiros e Clínicas.' },
  { target: 'health', view: 'overview', title: 'Volume de agendamentos', text: 'O mais importante: o que está marcado no hub de hoje em diante e o que ainda falta do nosso lado (sem balão, sem local, sem paciente casado). Cada número abre a lista já filtrada.' },
  { target: 'next', view: 'overview', title: 'Próximos dias', text: 'Os próximos itens do hub, prontos para conferir. Clique num nome para abrir a ficha completa.' },
  { target: 'nav', view: 'agenda', title: 'Agenda do hub', text: 'O mês inteiro numa grade; clique num dia para abrir a semana dele. Cada cartão mostra hora, paciente e status, e o ✓ diz que já está na nossa Agenda.' },
  { target: 'filters', view: 'items', title: 'Registros', text: 'A planilha de tudo que aconteceu. Filtre por lado (CEVICO ou parceiros), status, se já está na nossa Agenda, e busque por nome, telefone ou CPF. Clique numa linha para abrir a sanfona com os detalhes; a ficha completa fica no botão de expandir.' },
  { target: 'nav', view: 'partners', title: 'Parceiros', text: 'Os 7 parceiros mais representativos em cartões, com fatia, resultados e os procedimentos de cada um. Os outros você acha pela busca. A CEVICO aparece com estrela.' },
  { target: 'config', view: 'overview', title: 'Configurar', text: 'Conexão, parceiros, funil de destino, de-para de clínicas e a Agenda unificada ficam em Integrações. Você pode rever este tutorial a qualquer hora pelo botão "Tutorial".' },
];
const tourStep = ref(null); // null = fechado
const tourBox = ref(null); // retângulo do alvo
const tourCurrent = computed(() => (tourStep.value === null ? null : TOUR[tourStep.value]));
const placeTour = async () => {
  await nextTick();
  const step = tourCurrent.value;
  if (!step) return;
  const el = document.querySelector(`[data-tour="${step.target}"]`);
  if (!el) { tourBox.value = null; return; }
  el.scrollIntoView({ block: 'center', behavior: 'smooth' });
  setTimeout(() => {
    const r = el.getBoundingClientRect();
    tourBox.value = { top: r.top - 8, left: r.left - 8, width: r.width + 16, height: r.height + 16 };
  }, 350);
};
const tourGo = async n => {
  if (n < 0 || n >= TOUR.length) { tourEnd(); return; }
  tourStep.value = n;
  if (view.value !== TOUR[n].view) view.value = TOUR[n].view;
  placeTour();
};
const tourStart = () => tourGo(0);
const tourEnd = () => { tourStep.value = null; tourBox.value = null; try { localStorage.setItem(TOUR_KEY, '1'); } catch (e) { /* sem storage */ } };
const tourPopStyle = computed(() => {
  const b = tourBox.value;
  if (!b) return { top: '50%', left: '50%', transform: 'translate(-50%, -50%)' };
  const below = b.top + b.height + 16;
  const fits = below + 220 < window.innerHeight;
  const left = Math.min(Math.max(16, b.left), window.innerWidth - 376);
  return fits ? { top: `${below}px`, left: `${left}px` } : { top: `${Math.max(16, b.top - 236)}px`, left: `${left}px` };
});
const onResize = () => { if (tourStep.value !== null) placeTour(); };

onMounted(async () => {
  await fetchOverview();
  fetchWeek();
  window.addEventListener('resize', onResize);
  let done = '1';
  try { done = localStorage.getItem(TOUR_KEY); } catch (e) { /* sem storage */ }
  if (!done) setTimeout(tourStart, 800);
});
onBeforeUnmount(() => window.removeEventListener('resize', onResize));
</script>

<template>
  <div class="cv-page flex flex-col h-full w-full overflow-y-auto bg-n-surface-1" :style="pageStyle">
    <div class="max-w-6xl mx-auto w-full p-4 sm:p-8">
      <CevicoHero
        :pal="pal"
        title="Oftalmofácil"
        subtitle="O hub de parceiros dentro do nosso sistema: cirurgias, exames e consultas indicados por clínicas e médicos parceiros, com o estado de cada item na nossa Agenda e no CRM. Só leitura, espelhado a cada 15 minutos."
        icon="i-lucide-hospital"
        :hero-bg="HERO"
      >
        <template #chips>
          <span v-if="overview" class="cv-glass-chip"><span class="i-lucide-database text-xs" /> {{ overview.sync?.mirror_count || 0 }} itens espelhados</span>
          <span v-if="overview?.sync?.last_run_at" class="cv-glass-chip" :title="`cursor: ${overview.sync.last_sync_at || '—'}`"><span class="i-lucide-refresh-cw text-xs" /> sincronizado {{ fmtWhen(overview.sync.last_run_at) }}</span>
          <span v-if="overview && !overview.sync?.partners_enabled" class="cv-glass-chip" title="Só o fornecedor da CEVICO está sendo lido"><span class="i-lucide-triangle-alert text-xs" /> parceiros desligados</span>
          <span v-if="overview && !overview.sync?.agenda_enabled" class="cv-glass-chip" title="Os itens ainda não viram agendamentos"><span class="i-lucide-calendar-off text-xs" /> Agenda desligada</span>
        </template>
        <template #actions>
          <button class="cv-glass-btn" title="Rever o tutorial de primeiro uso" @click="tourStart"><span class="i-lucide-graduation-cap text-sm" /> <span class="hidden sm:inline">Tutorial</span></button>
          <router-link v-if="isAdmin" class="cv-glass-btn" :to="integrationsUrl" data-tour="config" title="Conexão, parceiros, funil e de-para de clínicas"><span class="i-lucide-settings-2 text-sm" /> <span class="hidden sm:inline">Configurar</span></router-link>
        </template>
        <div class="w-full flex flex-col gap-2.5">
          <div class="cv-ag-kindbar" role="tablist" data-tour="nav" aria-label="Áreas do ambiente Oftalmofácil">
            <button v-for="v in VIEWS" :key="v.key" class="cv-ag-kind cv-ag-kind-hero" :class="[view === v.key ? 'cv-ag-kind-on' : '', v.right ? 'ml-auto' : '']" :style="NAV_VARS" role="tab" :aria-selected="view === v.key" :title="v.hint" @click="view = v.key">
              <span :class="v.icon" class="text-sm" /> {{ v.label }}
            </button>
          </div>
          <div class="flex items-center gap-2 flex-wrap" data-tour="period">
            <PeriodRuler v-model="period" glass />
            <span class="text-[11px] text-white/80 hidden sm:inline">período pela data do procedimento</span>
          </div>
        </div>
      </CevicoHero>

      <SkeletonScreen v-if="isLoading && !overview" variant="dashboard" />

      <template v-else>
        <div v-if="loadError" class="cv-block cv-strip cv-red px-4 py-3.5 mb-8 flex items-center gap-3 flex-wrap">
          <span class="cv-icon cv-icon-sm"><span class="i-lucide-triangle-alert text-xs" /></span>
          <p class="text-xs text-n-slate-11 flex-1 min-w-0">{{ loadError }}</p>
          <button class="cv-btn cv-btn-sm" @click="fetchOverview">Tentar de novo</button>
        </div>

        <!-- ═══════════ VISÃO GERAL ═══════════ -->
        <template v-if="view === 'overview' && overview">
          <section class="cv-block p-6 sm:p-9 mb-8" :style="blockVars('agenda')" data-tour="health">
            <div class="flex items-start gap-3 mb-1">
              <span class="cv-ag-num">1</span>
              <div>
                <h2 class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12">Volume de agendamentos</h2>
                <p class="text-xs text-n-slate-10">marcado no hub de hoje em diante × como está do nosso lado · clique num número para ver a lista</p>
              </div>
            </div>
            <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 sm:gap-4 mt-6">
              <button class="text-left" @click="goItems({ status: 'agendada', usePeriod: false })"><DashKpi label="Marcados no hub" :value="Number(health.upcoming || 0)" sub="de hoje em diante" grad="linear-gradient(135deg, #0F766E, #2DD4BF)" glass compact /></button>
              <button class="text-left" @click="goItems({ agenda: 'with', status: 'agendada', usePeriod: false })"><DashKpi label="Já na nossa Agenda" :value="Number(health.with_task || 0)" :sub="`${pct(health.with_task, health.upcoming)}% dos marcados`" grad="linear-gradient(135deg, #047857, #10B981)" glass compact /></button>
              <button class="text-left" @click="goItems({ agenda: 'without', status: 'agendada', usePeriod: false })"><DashKpi label="Faltando na Agenda" :value="Number(health.without_task || 0)" sub="ligue a Agenda ou recarregue" :grad="health.without_task ? 'linear-gradient(135deg, #B45309, #F59E0B)' : ''" glass compact /></button>
              <button class="text-left" @click="goItems({ unmatched: true, status: 'agendada', usePeriod: false })"><DashKpi label="Sem paciente casado" :value="Number(health.unmatched_contacts || 0)" sub="telefone/CPF/nome não bateu" :grad="health.unmatched_contacts ? 'linear-gradient(135deg, #9F1239, #F43F5E)' : ''" glass compact /></button>
            </div>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-3 mt-4">
              <div class="cv-sub p-4"><p class="cv-label mb-1">Agendamentos sem local</p><p class="text-2xl font-bold text-n-slate-12">{{ health.task_without_unit || 0 }}</p><p class="text-[11px] text-n-slate-10">a clínica do hub ainda não tem de-para para um local nosso</p></div>
              <div class="cv-sub p-4">
                <p class="cv-label mb-1">Clínicas sem de-para</p>
                <div v-if="health.clinics_unmapped?.length" class="flex flex-wrap gap-1 mt-1"><span v-for="c in health.clinics_unmapped" :key="c" class="cv-chip cv-amber">{{ c }}</span></div>
                <p v-else class="text-sm font-semibold text-emerald-700 mt-1">todas mapeadas ✓</p>
                <router-link v-if="isAdmin" class="text-[11px] font-semibold hover:underline mt-2 inline-block" style="color: var(--cv)" :to="integrationsUrl">mapear em Integrações →</router-link>
              </div>
              <div class="cv-sub p-4"><p class="cv-label mb-1">"Agendada" com data passada</p><p class="text-2xl font-bold text-n-slate-12">{{ health.past_still_scheduled || 0 }}</p><p class="text-[11px] text-n-slate-10">há mais de 7 dias sem o hub atualizar o status</p></div>
            </div>
          </section>

          <!-- 🔎 item 249 · conferência do dia: hub × Agenda, item por item, com o motivo -->
          <section class="cv-block p-6 sm:p-9 mb-8" :style="blockVars('agenda')" data-tour="daycheck">
            <div class="flex items-start gap-3 mb-1 flex-wrap">
              <span class="cv-ag-num">✓</span>
              <div class="flex-1 min-w-[220px]">
                <h2 class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12">Conferência do dia</h2>
                <p class="text-xs text-n-slate-10">cada cirurgia, exame ou consulta marcada no hub para o dia × o que está na nossa Agenda, com o motivo quando falta</p>
              </div>
              <div class="flex items-center gap-2 flex-wrap">
                <input v-model="dayCheckDate" type="date" class="cv-input text-sm" style="margin-bottom: 0; width: 160px" />
                <label class="flex items-center gap-1.5 text-[11px] text-n-slate-11 cursor-pointer" title="Também pergunta ao banco do hub (só leitura): acha item que o sistema nunca leu">
                  <input v-model="dayCheckHub" type="checkbox" style="margin: 0" /> perguntar ao hub
                </label>
                <button class="cv-btn cv-btn-sm" :disabled="dayCheckLoading" @click="fetchDayCheck">{{ dayCheckLoading ? 'Conferindo…' : 'Conferir' }}</button>
                <button v-if="isAdmin && dayCheck && dayCheck.summary?.corrigiveis" class="cv-btn cv-btn-sm" style="background: linear-gradient(135deg, #B8860B, #F5D061); color: #1a1a1a; border-color: transparent" :disabled="dayCheckFixing" title="Reprocessa só o que falta neste dia — nada muda no hub" @click="reconcileDay">{{ dayCheckFixing ? 'Trazendo…' : `Trazer ${dayCheck.summary.corrigiveis} para a Agenda` }}</button>
              </div>
            </div>
            <p v-if="dayCheckMsg" class="text-xs font-semibold mt-2" style="color: var(--cv)">{{ dayCheckMsg }}</p>
            <template v-if="dayCheck">
              <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 sm:gap-4 mt-5">
                <DashKpi label="No hub para o dia" :value="Number(dayCheck.summary?.total || 0)" :sub="dayCheckLabel" grad="linear-gradient(135deg, #0F766E, #2DD4BF)" glass compact />
                <DashKpi label="Na Agenda, certinho" :value="dayCheckOk.length" sub="dia certo e com local" grad="linear-gradient(135deg, #047857, #10B981)" glass compact />
                <DashKpi label="Com problema" :value="Number(dayCheck.summary?.problemas || 0)" sub="falta, hora errada, sem local…" :grad="dayCheck.summary?.problemas ? 'linear-gradient(135deg, #B45309, #F59E0B)' : ''" glass compact />
                <DashKpi label="Corrigíveis agora" :value="Number(dayCheck.summary?.corrigiveis || 0)" :sub="dayCheck.hub?.checked ? 'hub consultado ✓' : dayCheck.hub?.error || 'só pelo espelho'" :grad="dayCheck.summary?.corrigiveis ? 'linear-gradient(135deg, #B8860B, #F5D061)' : ''" glass compact />
              </div>
              <div v-if="dayCheck.hub?.incomplete" class="cv-sub p-3 mt-3 text-xs text-n-slate-11">⚠️ O banco do hub tem <b>{{ dayCheck.hub.raw_total }}</b> itens neste dia, mas <b>{{ dayCheck.hub.incomplete }}</b> não têm o agendamento-pai completo lá (sem paciente/fornecedor ligado) e não dá para trazer. Peça para o Oftalmofácil completar o cadastro desses itens.</div>
              <div v-if="!dayCheck.config?.agenda_enabled" class="cv-sub p-3 mt-3 text-xs text-n-slate-11">⚠️ A <b>Agenda unificada está desligada</b> no card do Oftalmofácil (Integrações): nada do hub vira agendamento até ligar.</div>
              <div v-if="dayCheck.config?.error_count" class="cv-sub p-3 mt-3 text-xs text-n-slate-11">⚠️ O último sync terminou com {{ dayCheck.config.error_count }} erro(s): <span v-for="e in dayCheck.config.last_errors" :key="e" class="cv-chip cv-rose ml-1">{{ e }}</span></div>
              <div v-if="dayCheckProblems.length" class="mt-4 overflow-x-auto">
                <table class="cv-of-table cv-of-table-fit">
                  <thead><tr><th class="text-left">Hora</th><th class="text-left">Paciente</th><th class="text-left">Clínica → local</th><th class="text-left">Tipo</th><th class="text-left">Hub diz</th><th class="text-left">Situação</th></tr></thead>
                  <tbody>
                    <tr v-for="r in dayCheckProblems" :key="r.token">
                      <td class="font-mono">{{ r.hour || '—' }}</td>
                      <td><b>{{ r.patient }}</b><span v-if="r.phone_tail" class="text-n-slate-9"> · …{{ r.phone_tail }}</span><span v-if="!r.own" class="cv-chip cv-slate ml-1">{{ r.provider }}</span></td>
                      <td>{{ r.clinic || '—' }} <span class="text-n-slate-9">→ {{ r.unit_label || 'sem local' }}</span></td>
                      <td>{{ r.kind }}<span v-if="r.procedure" class="text-n-slate-9"> · {{ r.procedure }}</span></td>
                      <td>{{ r.status_label }}</td>
                      <td><span class="cv-chip" :class="dayCheckTone(r.situation)">{{ r.situation_label }}</span><p v-if="r.reason" class="text-[11px] text-n-slate-10 mt-0.5">{{ r.reason }}</p></td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <p v-else class="text-sm font-semibold text-emerald-700 mt-4">Tudo o que o hub tem para {{ dayCheckLabel }} está na nossa Agenda ✓</p>
              <div v-if="dayCheck.strays?.length" class="cv-sub p-3 mt-3 text-xs text-n-slate-11">
                <p class="font-semibold mb-1">Na nossa Agenda neste dia, mas o hub marca outra data:</p>
                <p v-for="t in dayCheck.strays" :key="t.task_id">• {{ t.title }} — hub: {{ t.hub_date || 'sem item' }} {{ t.hub_status ? `(${t.hub_status})` : '' }}</p>
              </div>
              <details v-if="dayCheckOk.length" class="mt-3">
                <summary class="text-xs font-semibold text-n-slate-11 cursor-pointer">Ver os {{ dayCheckOk.length }} que estão certinhos</summary>
                <p v-for="r in dayCheckOk" :key="r.token" class="text-xs text-n-slate-11 mt-1">✓ {{ r.hour || '—' }} · {{ r.patient }} · {{ r.kind }} · {{ r.unit_label }}</p>
              </details>
              <p class="text-[11px] text-n-slate-10 mt-4"><b>O que cada situação quer dizer:</b> <i>Falta na Agenda</i> = o hub tem e a Agenda não (o botão traz). <i>Hub tem, sistema nunca leu</i> = o sync incremental pulou o item (o botão traz). <i>Em outro dia/hora</i> = está na Agenda, mas no horário errado (o botão corrige). <i>Sem local</i> = a clínica do hub não tem de-para para um local nosso — some nas abas por unidade; mapeie em Integrações. <i>Cancelada na nossa Agenda</i> = a equipe cancelou aqui; o botão não mexe.</p>
            </template>
            <p v-else class="text-xs text-n-slate-10 mt-4">Escolha o dia e clique em Conferir. Segunda-feira já vem selecionada quando é fim de semana.</p>
          </section>

          <!-- 2 · representatividade: o que e quem pesa mais no volume -->
          <section class="cv-block p-6 sm:p-9 mb-8" :style="blockVars('parceiros')">
            <div class="flex items-start gap-3 mb-1">
              <span class="cv-ag-num">2</span>
              <div><h2 class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12">Representatividade</h2><p class="text-xs text-n-slate-10">quais procedimentos, clínicas e parceiros pesam mais no volume do período ({{ grandTotal }} itens)</p></div>
            </div>
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
              <div class="cv-sub p-5">
                <p class="text-sm font-bold text-n-slate-12 mb-0.5">Procedimentos mais indicados</p>
                <p class="text-[11px] text-n-slate-10 mb-3">itens no período × quantos já foram realizados</p>
                <HBars :rows="procRows" :series="[{ label: 'Itens', color: 'var(--cv-grad)' }, { label: 'Realizados', color: 'linear-gradient(135deg, #047857, #10B981)' }]" :label-width="14" />
              </div>
              <div class="space-y-4">
                <div class="cv-sub p-5">
                  <p class="text-sm font-bold text-n-slate-12 mb-0.5">Clínicas por volume</p>
                  <p class="text-[11px] text-n-slate-10 mb-3">onde os procedimentos acontecem</p>
                  <ShareBar :items="clinicShare" :max="5" />
                </div>
                <div class="cv-sub p-5">
                  <p class="text-sm font-bold text-n-slate-12 mb-0.5">Parceiros por volume</p>
                  <p class="text-[11px] text-n-slate-10 mb-3">quem indica · ⭐ = a CEVICO</p>
                  <ShareBar :items="partnerShare" :max="5" />
                </div>
                <div class="cv-sub p-5">
                  <p class="text-sm font-bold text-n-slate-12 mb-0.5">Tipos</p>
                  <ShareBar :items="typeShare" :max="4" :height="10" />
                </div>
              </div>
            </div>
          </section>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
            <section class="cv-block p-6 sm:p-8" :style="blockVars('agenda')" data-tour="next">
              <div class="flex items-start gap-3 mb-4">
                <span class="cv-ag-num">3</span>
                <div class="flex-1"><h2 class="text-lg font-bold tracking-tight text-n-slate-12">Próximos dias</h2><p class="text-xs text-n-slate-10">os próximos itens do hub nesta semana</p></div>
                <button class="cv-btn cv-btn-ghost cv-btn-sm" @click="view = 'agenda'">Agenda da semana ›</button>
              </div>
              <div v-if="!upcomingRows.length" class="cv-sub p-6 text-center text-sm text-n-slate-10">Nada marcado no hub nesta semana.</div>
              <div v-else class="space-y-1.5">
                <button v-for="r in upcomingRows" :key="r.id" class="cv-row w-full text-left px-3 py-2 flex items-center gap-3" @click="openDetail(r)">
                  <span class="w-1.5 h-8 rounded-full flex-shrink-0" :style="{ background: statusMeta(r.status_kind).dot }" />
                  <span class="w-20 text-xs font-bold text-n-slate-11 tabular-nums capitalize">{{ fmtDateLong(r.surgery_date) }}<br><span class="font-normal text-n-slate-10">{{ r.surgery_hour || '—' }}</span></span>
                  <span class="flex-1 min-w-0"><span class="text-sm font-semibold text-n-slate-12 block truncate">{{ r.patient_name }}</span><span class="text-[11px] text-n-slate-10 block truncate">{{ r.procedure_name || r.procedure_type }} · {{ r.own ? '⭐ CEVICO' : r.provider_name }}</span></span>
                  <span class="cv-chip" :class="agendaStateOf(r).tone"><span :class="agendaStateOf(r).icon" class="text-xs" /></span>
                </button>
              </div>
            </section>
            <section class="cv-block p-6 sm:p-8" :style="blockVars('parceiros')">
              <div class="flex items-start gap-3 mb-4">
                <span class="cv-ag-num">4</span>
                <div class="flex-1"><h2 class="text-lg font-bold tracking-tight text-n-slate-12">No período</h2><p class="text-xs text-n-slate-10">resumo e os maiores parceiros</p></div>
                <button class="cv-btn cv-btn-ghost cv-btn-sm" @click="view = 'partners'">Parceiros ›</button>
              </div>
              <div class="grid grid-cols-2 gap-2 mb-4">
                <DashKpi label="Itens" :value="Number(overview.totals?.total || 0)" grad="linear-gradient(135deg, #0F766E, #2DD4BF)" glass compact />
                <DashKpi label="Realizados" :value="Number(overview.totals?.realizada || 0)" grad="linear-gradient(135deg, #047857, #10B981)" glass compact />
                <DashKpi label="Agendados" :value="Number((overview.totals?.agendada || 0) + (overview.totals?.aguardando_pagamento || 0))" grad="linear-gradient(135deg, #1D4ED8, #3B82F6)" glass compact />
                <DashKpi label="Cancelados + faltas" :value="Number((overview.totals?.cancelada || 0) + (overview.totals?.ausente || 0))" grad="linear-gradient(135deg, #991B1B, #EF4444)" glass compact />
              </div>
              <div class="space-y-1.5">
                <button v-for="p in overview.partners.slice(0, 5)" :key="p.name" class="cv-row w-full text-left px-3 py-2 flex items-center gap-3" @click="goItems({ partner: p.name })">
                  <span :class="p.own ? 'i-lucide-star text-amber-500' : 'i-lucide-handshake text-n-slate-10'" class="text-sm flex-shrink-0" />
                  <span class="flex-1 text-sm font-semibold text-n-slate-12 truncate">{{ p.name || '(sem fornecedor)' }}</span>
                  <span class="text-xs text-n-slate-10 tabular-nums">{{ p.realizada }} realizados · {{ p.total }} itens</span>
                </button>
              </div>
            </section>
          </div>

          <section class="cv-block p-6 sm:p-9 mb-8" :style="blockVars('meses')">
            <div class="flex items-start gap-3 mb-1">
              <span class="cv-ag-num">5</span>
              <div><h2 class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12">Por mês</h2><p class="text-xs text-n-slate-10">cada item assentado no mês da data do procedimento</p></div>
            </div>
            <div v-if="!overview.months?.length" class="cv-sub p-6 text-center text-sm text-n-slate-10 mt-6">Sem itens no período.</div>
            <div v-else class="space-y-2 mt-6">
              <div v-for="m in overview.months" :key="m.month" class="flex items-center gap-3">
                <span class="w-16 text-xs font-bold text-n-slate-11 capitalize">{{ fmtMonth(m.month) }}</span>
                <div class="flex-1 h-5 rounded-full bg-n-alpha-2 overflow-hidden relative">
                  <div class="absolute inset-y-0 left-0 rounded-full" :style="{ width: `${Math.round((m.total / monthMax) * 100)}%`, background: 'rgb(var(--cv-rgb) / 0.35)' }" />
                  <div class="absolute inset-y-0 left-0 rounded-full" :style="{ width: `${Math.round((m.realizada / monthMax) * 100)}%`, background: 'var(--cv-grad)' }" />
                </div>
                <span class="w-32 text-[11px] text-n-slate-10 tabular-nums text-right">{{ m.realizada }} realizados · {{ m.total }} no total</span>
              </div>
            </div>
          </section>
        </template>

        <!-- ═══════════ AGENDA (mês · semana) ═══════════ -->
        <section v-if="view === 'agenda'" class="cv-block p-4 sm:p-6 mb-8" :style="blockVars('agenda')">
          <!-- item 244: cabeçalho em BLOCOS (igual à Agenda geral): ① Calendário com o
               mini mês sempre aberto + Hoje + Mês/Semana/Dia · ② período em título
               grande + ‹ › · ③ encontrar paciente -->
          <div class="grid grid-cols-1 lg:grid-cols-[272px_minmax(0,1fr)] gap-3 mb-4">
            <section class="cv-ag-block flex flex-col p-3.5">
              <div class="flex items-center gap-2 mb-2">
                <p class="cv-ag-block-title flex-1">Calendário</p>
                <button class="cv-btn cv-btn-ghost cv-btn-sm" title="Voltar para hoje" @click="calToday">Hoje</button>
              </div>
              <div class="flex items-center justify-between mb-1">
                <button class="cv-ag-nav !w-7 !h-7" title="Mês anterior" @click="pickerShift(-1)"><span class="i-lucide-chevron-left text-sm" /></button>
                <p class="text-sm font-bold text-n-slate-12">{{ pickerLabel }}</p>
                <button class="cv-ag-nav !w-7 !h-7" title="Mês seguinte" @click="pickerShift(1)"><span class="i-lucide-chevron-right text-sm" /></button>
              </div>
              <div class="grid grid-cols-7 mb-0.5">
                <span v-for="(wd, wi) in ['S', 'T', 'Q', 'Q', 'S', 'S', 'D']" :key="'pw' + wi" class="text-center text-[10px] font-semibold text-n-slate-9">{{ wd }}</span>
              </div>
              <div v-for="(row, ri) in pickerWeeksRows" :key="'pr' + ri" class="cv-ag-mini-week grid grid-cols-7" :class="calMode === 'week' && pickerInView(row[3]) ? 'cv-ag-mini-week-on' : ''">
                <button
                  v-for="d in row"
                  :key="'pk' + dateKey(d)"
                  class="cv-ag-daynum mx-auto !w-8 !h-8 text-xs hover:bg-n-alpha-2"
                  :class="[d.getMonth() === pickerCursor.getMonth() ? '' : 'cv-ag-daynum-muted', calMode === 'day' && pickerInView(d) ? 'cv-ag-daynum-today' : '']"
                  :style="dateKey(d) === todayKey && !(calMode === 'day' && pickerInView(d)) ? { boxShadow: 'inset 0 0 0 1.5px var(--cv)' } : {}"
                  @click="pickDay(d)"
                >
                  {{ d.getDate() }}
                </button>
              </div>
              <div class="cv-seg cv-seg-sm grid grid-cols-3 mt-auto pt-2">
                <button type="button" class="cv-seg-item justify-center" :class="calMode === 'month' ? 'cv-seg-on' : ''" @click="calMode = 'month'"><span class="i-lucide-calendar text-sm" /> Mês</button>
                <button type="button" class="cv-seg-item justify-center" :class="calMode === 'week' ? 'cv-seg-on' : ''" @click="calMode = 'week'"><span class="i-lucide-calendar-range text-sm" /> Semana</button>
                <button type="button" class="cv-seg-item justify-center" :class="calMode === 'day' ? 'cv-seg-on' : ''" @click="calMode = 'day'"><span class="i-lucide-calendar-check text-sm" /> Dia</button>
              </div>
            </section>

            <div class="flex flex-col gap-3 min-w-0">
              <section class="cv-ag-block p-4 flex items-center gap-3 flex-wrap">
                <span class="cv-icon cv-icon-lg hidden sm:inline-flex"><span class="i-lucide-hospital text-lg" /></span>
                <div class="min-w-0 flex-1">
                  <p class="cv-ag-block-title">{{ calModeTitle }} <span class="cv-ag-block-sub">· agenda do hub</span></p>
                  <h2 class="text-2xl font-bold tracking-tight text-n-slate-12 truncate">{{ calTitle }}</h2>
                </div>
                <span v-if="calLoading" class="i-lucide-loader-2 animate-spin text-sm text-n-slate-9" />
                <div class="flex items-center gap-1.5 ml-auto">
                  <button class="cv-ag-nav" title="Anterior" @click="calStep(-1)"><span class="i-lucide-chevron-left text-base" /></button>
                  <button class="cv-ag-nav" title="Seguinte" @click="calStep(1)"><span class="i-lucide-chevron-right text-base" /></button>
                </div>
              </section>
              <!-- bug 26/09: o bloco tem backdrop-filter (contexto de empilhamento próprio) e a lista
                   de resultados ficava POR BAIXO dos "Itens do dia"; com a busca aberta o bloco sobe -->
              <section class="cv-ag-block p-4 flex flex-col gap-2.5 flex-1" :class="calQuery.trim().length >= 2 ? 'relative z-30' : ''">
                <p class="cv-ag-block-title">Encontrar</p>
                <div class="flex items-start gap-3 flex-wrap">
                  <span class="cv-ag-row-label">Paciente</span>
              <!-- encontrar paciente -->
              <div class="relative w-full sm:w-72">
                <span class="i-lucide-search absolute left-2.5 top-1/2 -translate-y-1/2 text-xs text-n-slate-9" />
                <input v-model="calQuery" class="cv-input w-full !h-8 !pl-7 text-xs" placeholder="Encontrar paciente na agenda…" />
                <div v-if="calQuery.trim().length >= 2" class="cv-pop cv-ag-pop absolute right-0 top-10 z-40 w-[22rem] max-w-[90vw] p-1.5">
                  <p v-if="calSearching" class="text-[11px] text-n-slate-10 px-2 py-1.5">procurando…</p>
                  <p v-else-if="!calHits.length" class="text-[11px] text-n-slate-10 px-2 py-1.5">ninguém com "{{ calQuery }}" no hub</p>
                  <button v-for="h in calHits" :key="'hit' + h.id" class="w-full text-left rounded-lg px-2 py-1.5 hover:bg-n-alpha-2 flex items-center gap-2" @click="goToHit(h)">
                    <span class="w-1.5 h-8 rounded-full shrink-0" :style="{ background: statusMeta(h.status_kind).dot }" />
                    <span class="min-w-0 flex-1">
                      <span class="block text-xs font-semibold text-n-slate-12 truncate">{{ h.patient_name }}</span>
                      <span class="block text-[10px] text-n-slate-10 truncate capitalize">{{ fmtDateLong(h.surgery_date) }} · {{ h.surgery_hour || 'sem hora' }} · {{ h.procedure_name || h.procedure_type }}</span>
                    </span>
                    <span class="i-lucide-arrow-right text-xs text-n-slate-9" />
                  </button>
                </div>
              </div>
                </div>
                <div class="flex items-start gap-3 flex-wrap">
                  <span class="cv-ag-row-label">Status</span>
                  <div class="flex items-center gap-3 flex-wrap pt-2 text-[11px] text-n-slate-10">
                    <span v-for="st in STATUS" :key="'lg' + st.key" class="flex items-center gap-1"><span class="w-2 h-2 rounded-full" :style="{ background: st.dot }" /> {{ st.label }}</span>
                    <span class="flex items-center gap-1"><span class="i-lucide-check text-[11px]" /> = já está na nossa Agenda</span>
                  </div>
                </div>
              </section>
            </div>
          </div>

          <!-- MÊS -->
          <template v-if="calMode === 'month'">
            <div class="grid grid-cols-2 sm:grid-cols-4 gap-2 mb-4">
              <DashKpi label="Itens no mês" :value="Number(monthTotals.total)" grad="linear-gradient(135deg, #0F766E, #2DD4BF)" glass compact />
              <DashKpi label="Agendados" :value="Number(monthTotals.agendada)" grad="linear-gradient(135deg, #1D4ED8, #3B82F6)" glass compact />
              <DashKpi label="Realizados" :value="Number(monthTotals.realizada)" grad="linear-gradient(135deg, #047857, #10B981)" glass compact />
              <DashKpi label="Cancelados + faltas" :value="Number(monthTotals.cancelada)" grad="linear-gradient(135deg, #991B1B, #EF4444)" glass compact />
            </div>
            <div class="cv-of-month-head">
              <span v-for="d in weekDays" :key="'mh' + dateKey(d)">{{ d.toLocaleDateString('pt-BR', { weekday: 'short' }) }}</span>
            </div>
            <div class="cv-of-month">
              <div v-for="d in monthCells" :key="'mc' + dateKey(d)" class="cv-of-mcell" :class="{ 'cv-of-mcell-out': d.getMonth() !== monthStart.getMonth(), 'cv-of-mcell-today': dateKey(d) === todayKey }" @click="openDay(d)">
                <div class="flex items-center justify-between mb-1">
                  <span class="cv-of-mnum">{{ d.getDate() }}</span>
                  <span v-if="(monthByDay[dateKey(d)] || []).length" class="cv-of-mcount">{{ monthByDay[dateKey(d)].length }}</span>
                </div>
                <button v-for="r in (monthByDay[dateKey(d)] || []).slice(0, dayCellMax)" :key="r.id" class="cv-of-mchip" :class="`cv-of-ev-${r.status_kind}`" :title="`${r.surgery_hour || ''} ${r.patient_name} · ${r.procedure_name || ''} · ${r.provider_name}`" @click.stop="openDetail(r)">
                  <span class="cv-of-mchip-time">{{ r.surgery_hour || '' }}</span> {{ r.patient_name }}
                </button>
                <span v-if="(monthByDay[dateKey(d)] || []).length > dayCellMax" class="text-[10px] font-bold text-n-slate-10 block px-1">+ {{ monthByDay[dateKey(d)].length - dayCellMax }} mais</span>
              </div>
            </div>
          </template>

          <!-- SEMANA: 7 colunas de horário, como a nossa Agenda -->
          <div v-else-if="calMode === 'week'" class="cv-ag-grid">
            <div class="cv-ag-grid-head" style="grid-template-columns: 48px repeat(7, minmax(0, 1fr))">
              <div />
              <button v-for="d in weekDays" :key="'wh' + dateKey(d)" class="cv-ag-dayhead" :class="dateKey(d) === todayKey ? 'cv-ag-dayhead-today' : ''" @click="openDay(d)">
                <span class="cv-ag-dayhead-wd">{{ d.toLocaleDateString('pt-BR', { weekday: 'short' }) }}</span>
                <span class="flex items-center gap-1.5">
                  <span class="cv-ag-daynum" :class="dateKey(d) === todayKey ? 'cv-ag-daynum-today' : ''">{{ d.getDate() }}</span>
                  <span v-if="(weekByDay[dateKey(d)] || []).length" class="text-[10px] font-bold text-n-slate-10">{{ weekByDay[dateKey(d)].length }}</span>
                </span>
              </button>
            </div>
            <div class="cv-ag-grid-body" style="grid-template-columns: 48px repeat(7, minmax(0, 1fr))">
              <div class="cv-ag-gutter" :style="{ height: HOURS.length * WEEK_PX + 'px' }">
                <span v-for="(h, hi) in HOURS" :key="h" class="cv-ag-hour" :style="{ top: hi * WEEK_PX + 'px' }">{{ hi === 0 ? '' : String(h).padStart(2, '0') + ':00' }}</span>
              </div>
              <AgendaTimeColumn v-for="d in weekDays" :key="'wc' + dateKey(d)" :day="d" :tasks="tasksOfDay(d)" :start-hour="HOURS[0]" :end-hour="HOURS[HOURS.length - 1] + 1" :hour-px="WEEK_PX" :today="dateKey(d) === todayKey" :duration-of="durationOfTask" :accent-of="accentOfTask" :name-of="nameOfTask" compact @open="openTask" />
            </div>
          </div>

          <!-- DIA: coluna de horas + lista do dia (como a visão Dia da Agenda) -->
          <div v-else class="flex flex-col lg:flex-row gap-4 items-start">
            <div class="w-full lg:w-[42%] flex-shrink-0">
              <div class="cv-ag-grid">
                <div class="cv-ag-grid-head" style="grid-template-columns: 56px minmax(0, 1fr)">
                  <div />
                  <div class="cv-ag-dayhead !items-start px-3 !py-2.5" :class="dateKey(dayCursor) === todayKey ? 'cv-ag-dayhead-today' : ''">
                    <span class="cv-ag-dayhead-wd">{{ dayCursor.toLocaleDateString('pt-BR', { weekday: 'long' }) }}</span>
                    <span class="flex items-center gap-2">
                      <span class="cv-ag-daynum cv-ag-daynum-lg" :class="dateKey(dayCursor) === todayKey ? 'cv-ag-daynum-today' : ''">{{ dayCursor.getDate() }}</span>
                      <span class="text-sm font-semibold text-n-slate-12">{{ dayRows.length }} {{ dayRows.length === 1 ? 'item' : 'itens' }}</span>
                    </span>
                  </div>
                </div>
                <div class="cv-ag-grid-body" style="grid-template-columns: 56px minmax(0, 1fr)">
                  <div class="cv-ag-gutter" :style="{ height: HOURS.length * DAY_PX + 'px' }">
                    <span v-for="(h, hi) in HOURS" :key="h" class="cv-ag-hour" :style="{ top: hi * DAY_PX + 'px' }">{{ hi === 0 ? '' : String(h).padStart(2, '0') + ':00' }}</span>
                  </div>
                  <AgendaTimeColumn :day="dayCursor" :tasks="tasksOfDay(dayCursor)" :start-hour="HOURS[0]" :end-hour="HOURS[HOURS.length - 1] + 1" :hour-px="DAY_PX" :today="dateKey(dayCursor) === todayKey" :duration-of="durationOfTask" :accent-of="accentOfTask" :name-of="nameOfTask" @open="openTask" />
                </div>
              </div>
              <p class="text-[10px] text-n-slate-9 mt-2 text-center">item sem hora no hub entra às 08:00 com o aviso "sem hora"</p>
            </div>
            <div class="flex-1 min-w-0 w-full space-y-2.5">
              <div class="flex items-center gap-2"><span class="cv-icon cv-icon-sm"><span class="i-lucide-list text-xs" /></span><p class="text-sm font-bold text-n-slate-12">Itens do dia</p><span class="cv-chip cv-chip-on">{{ dayRows.length }}</span></div>
              <div v-if="!dayRows.length" class="cv-sub p-8 text-center text-sm text-n-slate-10">Nada marcado no hub neste dia.</div>
              <!-- item 243: cartão em GRADE — hora | quem e o quê | selos alinhados à direita -->
              <div v-for="r in dayRows" :key="'dr' + r.id" class="cv-ag-card cv-ag-card-grid" :style="{ '--cv': statusMeta(r.status_kind).dot }" @click="openDetail(r)">
                <span class="cv-ag-card-time" :style="{ color: statusMeta(r.status_kind).dot }">{{ r.surgery_hour || '—' }}</span>
                <div class="min-w-0">
                  <p class="text-sm font-semibold text-n-slate-12 truncate">{{ r.own ? '⭐ ' : '' }}{{ r.patient_name }}</p>
                  <p v-if="r.procedure_name" class="cv-ag-card-proc"><span class="i-lucide-eye text-[11px] opacity-60" /> {{ r.procedure_name }}<span v-if="r.eye" class="font-normal text-n-slate-10"> · {{ r.eye }}</span></p>
                  <div class="cv-ag-card-meta">
                    <span v-if="r.patient_phone"><span class="i-lucide-phone text-[10px]" />{{ r.patient_phone }}</span>
                    <span v-if="r.clinic_name"><span class="i-lucide-map-pin text-[10px]" />{{ r.clinic_name }}<template v-if="r.unit"> → {{ unitLabel(r.unit) }}</template></span>
                    <span v-if="r.doctor || r.doctor_crm"><span class="i-lucide-stethoscope text-[10px]" />{{ r.doctor || `CRM ${r.doctor_crm}` }}</span>
                    <router-link v-if="patientUrl(r)" class="hover:underline font-semibold" style="color: var(--cv)" :to="patientUrl(r)" @click.stop><span class="i-lucide-user-round text-[10px]" /> Paciente</router-link>
                  </div>
                </div>
                <div class="cv-ag-card-pills">
                  <span class="cv-chip" :class="statusMeta(r.status_kind).tone">{{ r.status_kind_label }}</span>
                  <span class="cv-chip" :class="r.own ? 'cv-gold' : ''" :title="r.provider_name"><span :class="r.own ? 'i-lucide-star' : 'i-lucide-handshake'" class="text-xs shrink-0" /> <span class="truncate">{{ r.provider_name }}</span></span>
                  <span class="cv-chip" :class="agendaStateOf(r).tone"><span :class="agendaStateOf(r).icon" class="text-xs shrink-0" /> <span class="truncate">{{ agendaStateOf(r).label }}</span></span>
                </div>
              </div>
            </div>
          </div>

        </section>

        <!-- ═══════════ ITENS (tabela) ═══════════ -->
        <section v-if="view === 'items'" class="cv-block p-4 sm:p-6 mb-8" :style="blockVars('lista')">
          <div class="flex items-center gap-3 mb-3">
            <div class="flex-1 min-w-0"><h2 class="text-xl font-bold tracking-tight text-n-slate-12">Registros</h2><p class="text-xs text-n-slate-10">a planilha de tudo que aconteceu no hub · cada linha é um registro lá; a coluna Situação mostra como está aqui</p></div>
            <span v-if="items" class="cv-chip cv-chip-on">{{ items.total }}</span>
          </div>
          <div class="flex flex-col gap-2 mb-3" data-tour="filters">
            <div class="flex items-center gap-1.5 flex-wrap">
              <button v-for="o in [['', 'Todos'], ['own', '⭐ CEVICO'], ['partners', 'Parceiros']]" :key="'side' + o[0]" class="cv-chip" :class="filters.side === o[0] ? 'cv-chip-on' : ''" @click="filters.side = o[0]">{{ o[1] }}</button>
              <span class="w-px h-4 bg-n-weak mx-1" />
              <button v-for="s in STATUS" :key="s.key" class="cv-chip" :class="[s.tone, filters.status === s.key ? 'cv-chip-on' : '']" @click="filters.status = filters.status === s.key ? '' : s.key">{{ s.label }}</button>
              <span class="w-px h-4 bg-n-weak mx-1" />
              <button v-for="o in [['with', 'Na Agenda'], ['without', 'Fora da Agenda']]" :key="'ag' + o[0]" class="cv-chip" :class="filters.agenda === o[0] ? 'cv-chip-on' : ''" @click="filters.agenda = filters.agenda === o[0] ? '' : o[0]">{{ o[1] }}</button>
              <button class="cv-chip cv-red" :class="filters.unmatched ? 'cv-chip-on' : ''" @click="filters.unmatched = !filters.unmatched">Sem paciente</button>
              <button class="cv-chip" :class="filters.usePeriod ? 'cv-chip-on' : ''" title="Limitar ao período da régua" @click="filters.usePeriod = !filters.usePeriod"><span class="i-lucide-calendar-range text-xs" /> {{ filters.usePeriod ? 'no período' : 'todas as datas' }}</button>
              <button v-if="filters.side || filters.status || filters.agenda || filters.partner || filters.clinic || filters.type || filters.q || filters.unmatched" class="cv-chip cv-slate ml-auto" @click="filters = blankFilters()"><span class="i-lucide-x text-xs" /> limpar</button>
            </div>
            <div class="grid grid-cols-1 sm:grid-cols-4 gap-2">
              <input v-model="filters.q" class="cv-input w-full" placeholder="🔎 nome, telefone ou CPF" />
              <select v-model="filters.partner" class="cv-input w-full"><option value="">Todos os parceiros</option><option v-for="p in partnerOptions" :key="p" :value="p">{{ p }}</option></select>
              <select v-model="filters.clinic" class="cv-input w-full"><option value="">Todas as clínicas</option><option v-for="c in clinicOptions" :key="c" :value="c">{{ c }}</option></select>
              <select v-model="filters.type" class="cv-input w-full"><option value="">Todos os tipos</option><option v-for="t in typeOptions" :key="t" :value="t">{{ t }}</option></select>
            </div>
          </div>
          <SkeletonScreen v-if="isLoadingItems && !items" variant="dashboard" />
          <div v-else-if="items && !items.rows.length" class="cv-sub p-8 text-center text-n-slate-10"><span class="cv-icon cv-icon-xl mx-auto mb-3 block"><span class="i-lucide-search-x text-xl" /></span><p class="text-sm">Nada com esses filtros.</p></div>
          <div v-else-if="items" class="cv-of-tablewrap" :class="isLoadingItems ? 'opacity-60' : ''">
            <table class="cv-of-table cv-of-table-fit">
              <thead>
                <tr>
                  <th style="width: 12%">Quando</th>
                  <th class="cv-of-sep" style="width: 20%">Paciente</th>
                  <th class="cv-of-sep" style="width: 20%">De onde</th>
                  <th class="cv-of-sep" style="width: 22%">O quê</th>
                  <th class="cv-of-sep">Situação</th>
                  <th class="cv-of-sep" style="width: 36px" />
                </tr>
              </thead>
              <tbody>
                <template v-for="row in items.rows" :key="row.id">
                  <tr :class="expandedId === row.id ? 'cv-of-row-open' : ''" @click="toggleRow(row)">
                    <td>
                      <span class="cv-of-main tabular-nums capitalize">{{ fmtDateLong(row.surgery_date) }}</span>
                      <span class="cv-of-sub tabular-nums">{{ row.surgery_hour || 'sem hora' }}</span>
                    </td>
                    <td class="cv-of-sep">
                      <span class="cv-of-main">{{ row.patient_name || '(sem nome)' }}<span v-if="!row.contact" class="cv-of-dot cv-of-dot-red" title="sem paciente casado" /></span>
                      <span class="cv-of-sub tabular-nums">{{ row.patient_phone || 'sem telefone' }}</span>
                    </td>
                    <td class="cv-of-sep">
                      <span class="cv-of-main"><span v-if="row.own" title="a CEVICO no hub">⭐ </span>{{ row.provider_name || '—' }}</span>
                      <span class="cv-of-sub" :class="row.unit ? '' : (row.clinic_name ? 'text-amber-700' : '')"><span class="i-lucide-map-pin text-[10px]" /> {{ row.clinic_name || '—' }}<template v-if="row.unit"> → {{ unitLabel(row.unit) }}</template><template v-else-if="row.clinic_name"> · sem local</template></span>
                    </td>
                    <td class="cv-of-sep">
                      <span class="cv-of-main">{{ row.procedure_name || row.procedure_type || '—' }}<span v-if="row.eye" class="font-normal text-n-slate-10"> · {{ row.eye }}</span></span>
                      <span class="cv-of-sub"><span class="i-lucide-stethoscope text-[10px]" /> {{ row.doctor || (row.doctor_crm ? `CRM ${row.doctor_crm}` : 'médico a definir') }}</span>
                    </td>
                    <td class="cv-of-sep">
                      <span class="flex items-center gap-1 flex-wrap">
                        <span class="cv-chip" :class="statusMeta(row.status_kind).tone">{{ row.status_kind_label }}</span>
                        <span v-if="isAdmin && Number(row.amount) > 0" class="text-xs font-semibold text-n-slate-11 tabular-nums">{{ fmtBRL(row.amount) }}</span>
                      </span>
                      <span class="flex items-center gap-1 flex-wrap mt-1">
                        <span class="cv-chip" :class="agendaStateOf(row).tone"><span :class="agendaStateOf(row).icon" class="text-xs" /> {{ agendaStateOf(row).label }}</span>
                        <span v-if="row.card" class="cv-chip" :title="row.card.pipeline"><span class="w-1.5 h-1.5 rounded-full" :style="{ background: row.card.stage_color || '#94a3b8' }" /> {{ row.card.stage }}</span>
                      </span>
                    </td>
                    <td class="cv-of-sep text-right"><span class="cv-of-ico" :class="expandedId === row.id ? 'rotate-180' : ''"><span class="i-lucide-chevron-down" /></span></td>
                  </tr>
                  <!-- sanfona: detalhes na própria tabela; a ficha completa fica no botão de expandir -->
                  <tr v-if="expandedId === row.id" class="cv-of-expand" @click.stop>
                    <td colspan="6">
                      <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
                        <div class="cv-sub p-3">
                          <p class="cv-label mb-1.5">Paciente</p>
                          <dl class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs">
                            <dt class="text-n-slate-10">E-mail</dt><dd class="text-n-slate-12 font-semibold truncate">{{ rowDetail(row).patient_email || '—' }}</dd>
                            <template v-if="isAdmin"><dt class="text-n-slate-10">CPF</dt><dd class="text-n-slate-12 font-semibold tabular-nums">{{ rowDetail(row).patient_cpf || '—' }}</dd></template>
                            <dt class="text-n-slate-10">Casou por</dt><dd class="text-n-slate-12 font-semibold">{{ { phone: 'telefone', cpf: 'CPF', name: 'nome', created: 'criado pelo sync' }[rowDetail(row).match_via] || rowDetail(row).match_via || '—' }}</dd>
                            <dt class="text-n-slate-10">Aqui</dt><dd><router-link v-if="patientUrl(row)" class="font-semibold hover:underline" style="color: var(--cv)" :to="patientUrl(row)">{{ row.contact.name }} →</router-link><span v-else class="text-red-600 font-semibold">sem paciente casado</span></dd>
                          </dl>
                        </div>
                        <div class="cv-sub p-3">
                          <p class="cv-label mb-1.5">Procedimento</p>
                          <dl class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs">
                            <dt class="text-n-slate-10">Tipo</dt><dd class="text-n-slate-12 font-semibold">{{ row.procedure_type || '—' }}</dd>
                            <dt class="text-n-slate-10">Status lá</dt><dd class="text-n-slate-12 font-semibold">{{ row.status_label || row.status_kind_label }}</dd>
                            <dt class="text-n-slate-10">Marcado em</dt><dd class="text-n-slate-12 font-semibold">{{ fmtWhen(row.of_created_at) }}</dd>
                            <dt class="text-n-slate-10">Alterado em</dt><dd class="text-n-slate-12 font-semibold">{{ fmtWhen(row.of_modified_at) }}</dd>
                            <template v-if="isAdmin && Number(row.paid_amount) > 0"><dt class="text-n-slate-10">Pago</dt><dd class="text-n-slate-12 font-semibold">{{ fmtBRL(row.paid_amount) }}</dd></template>
                          </dl>
                        </div>
                        <div class="cv-sub p-3 flex flex-col">
                          <p class="cv-label mb-1.5">Do nosso lado</p>
                          <div class="flex items-center gap-1.5 flex-wrap">
                            <span class="cv-chip" :class="agendaStateOf(row).tone"><span :class="agendaStateOf(row).icon" class="text-xs" /> {{ agendaStateOf(row).label }}</span>
                            <span v-if="row.task?.doctor" class="cv-chip cv-slate">{{ row.task.doctor }}</span>
                            <span v-if="row.card" class="cv-chip">{{ row.card.stage }} · {{ row.card.pipeline }}</span>
                            <span v-else class="cv-chip cv-slate">sem card no CRM</span>
                          </div>
                          <div class="flex items-center gap-1.5 flex-wrap mt-auto pt-3">
                            <router-link v-if="patientUrl(row)" class="cv-btn cv-btn-ghost cv-btn-sm" :to="patientUrl(row)"><span class="i-lucide-user-round text-xs" /> Paciente</router-link>
                            <router-link class="cv-btn cv-btn-ghost cv-btn-sm" :to="agendaUrl(row)"><span class="i-lucide-calendar-days text-xs" /> Agenda</router-link>
                            <button class="cv-btn cv-btn-sm ml-auto" title="Ficha completa" @click="openDetail(row)"><span class="i-lucide-maximize-2 text-xs" /> Expandir</button>
                          </div>
                        </div>
                      </div>
                    </td>
                  </tr>
                </template>
              </tbody>
            </table>
          </div>
          <div v-if="items && totalPages > 1" class="flex items-center justify-end gap-2 mt-3">
            <span class="text-xs text-n-slate-10">página {{ page }} de {{ totalPages }}</span>
            <button class="cv-btn cv-btn-ghost cv-btn-sm" :disabled="page <= 1" @click="page -= 1">‹ Anterior</button>
            <button class="cv-btn cv-btn-sm" :disabled="page >= totalPages" @click="page += 1">Próxima ›</button>
          </div>
        </section>

        <!-- ═══════════ PARCEIROS (indicadores) ═══════════ -->
        <section v-if="view === 'partners' && overview" class="cv-block p-4 sm:p-6 mb-8" :style="blockVars('parceiros')">
          <div class="mb-4"><h2 class="text-xl font-bold tracking-tight text-n-slate-12">Parceiros</h2><p class="text-xs text-n-slate-10">quem indica e quanto pesa no período · ⭐ = a própria CEVICO ({{ overview.sync?.own_provider }}) · clique em "ver itens" para a lista</p></div>
          <div v-if="!overview.partners?.length" class="cv-sub p-8 text-center text-sm text-n-slate-10">Nenhum item no período. Se os parceiros estiverem desligados, ligue em Integrações e recarregue tudo.</div>
          <template v-else>
            <div class="cv-sub p-5 mb-4">
              <p class="text-sm font-bold text-n-slate-12 mb-0.5">Fatia de cada parceiro</p>
              <p class="text-[11px] text-n-slate-10 mb-3">{{ grandTotal }} itens no período · {{ overview.partners.length }} parceiro(s)</p>
              <ShareBar :items="partnerShare" :max="6" />
            </div>
            <div class="flex items-center gap-2 flex-wrap mb-3">
              <input v-model="partnerQuery" class="cv-input w-72" placeholder="🔎 buscar parceiro pelo nome" />
              <span class="text-[11px] text-n-slate-10">{{ partnerQuery ? `${partnerCards.length} encontrado(s)` : `os ${Math.min(TOP_CARDS, overview.partners.length)} mais representativos · os outros pela busca` }}</span>
            </div>
            <div v-if="!partnerCards.length" class="cv-sub p-6 text-center text-sm text-n-slate-10">Nenhum parceiro com esse nome no período.</div>
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
              <div v-for="p in partnerCards" :key="p.name" class="cv-of-card">
                <div class="flex items-center gap-2 mb-3">
                  <span class="cv-icon cv-icon-sm" :style="p.own ? { background: 'linear-gradient(135deg, #B45309, #F59E0B)' } : {}"><span :class="p.own ? 'i-lucide-star' : 'i-lucide-handshake'" class="text-xs" /></span>
                  <div class="min-w-0 flex-1"><p class="text-sm font-bold text-n-slate-12 truncate">{{ p.name || '(sem fornecedor)' }}</p><p class="text-[11px] text-n-slate-10">{{ p.own ? 'a CEVICO no hub' : 'parceiro de aquisição' }} · {{ share(p.total) }}% do volume</p></div>
                  <button class="cv-btn cv-btn-ghost cv-btn-sm" @click="goItems({ partner: p.name })">ver itens ›</button>
                </div>
                <div class="grid grid-cols-4 gap-2 mb-3">
                  <div class="cv-of-stat"><b>{{ p.total }}</b><span>itens</span></div>
                  <div class="cv-of-stat"><b class="text-emerald-700">{{ rate(p.realizada, p.total) }}%</b><span>realizados</span></div>
                  <div class="cv-of-stat"><b class="text-red-600">{{ rate(p.cancelada + p.ausente, p.total) }}%</b><span>cancel. + faltas</span></div>
                  <div class="cv-of-stat"><b>{{ p.with_task }}/{{ p.total }}</b><span>na Agenda</span></div>
                </div>
                <p class="cv-label mb-1.5">Procedimentos deste parceiro</p>
                <HBars :rows="miniRows(p.top_procedures)" :series="[{ label: 'Itens', color: 'var(--cv-grad)' }]" :label-width="12" empty-text="sem procedimento informado" />
                <p v-if="isAdmin && p.amount != null" class="text-[11px] text-n-slate-10 mt-3 text-right">realizado <b class="text-n-slate-12">{{ fmtBRL(p.amount_done) }}</b> · faturável {{ fmtBRL(p.amount) }}</p>
              </div>
            </div>
          </template>
        </section>

        <!-- ═══════════ CLÍNICAS (indicadores) ═══════════ -->
        <section v-if="view === 'clinics' && overview" class="cv-block p-4 sm:p-6 mb-8" :style="blockVars('parceiros')">
          <div class="flex items-start gap-3 mb-4">
            <div class="flex-1"><h2 class="text-xl font-bold tracking-tight text-n-slate-12">Clínicas</h2><p class="text-xs text-n-slate-10">onde os procedimentos acontecem e quais pesam mais · o de-para diz em que local da nossa Agenda o item entra</p></div>
            <router-link v-if="isAdmin" class="cv-btn cv-btn-sm" :to="integrationsUrl"><span class="i-lucide-settings-2 text-xs" /> Mapear clínicas</router-link>
          </div>
          <div class="cv-sub p-5 mb-4">
            <p class="text-sm font-bold text-n-slate-12 mb-0.5">Fatia de cada clínica</p>
            <p class="text-[11px] text-n-slate-10 mb-3">{{ grandTotal }} itens no período · {{ overview.clinics.length }} clínica(s)</p>
            <ShareBar :items="clinicShare" :max="6" />
          </div>
          <div class="flex items-center gap-2 flex-wrap mb-3">
            <input v-model="clinicQuery" class="cv-input w-72" placeholder="🔎 buscar clínica pelo nome" />
            <span class="text-[11px] text-n-slate-10">{{ clinicQuery ? `${clinicCards.length} encontrada(s)` : `as ${Math.min(TOP_CARDS, overview.clinics.length)} mais representativas · as outras pela busca` }}</span>
          </div>
          <div v-if="!clinicCards.length" class="cv-sub p-6 text-center text-sm text-n-slate-10">Nenhuma clínica com esse nome no período.</div>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <div v-for="c in clinicCards" :key="c.name" class="cv-of-card">
              <div class="flex items-center gap-2 mb-3">
                <span class="cv-icon cv-icon-sm"><span class="i-lucide-building-2 text-xs" /></span>
                <div class="min-w-0 flex-1">
                  <p class="text-sm font-bold text-n-slate-12 truncate">{{ c.name }}</p>
                  <p class="text-[11px] text-n-slate-10">{{ share(c.total) }}% do volume ·
                    <span v-if="c.unit" class="text-emerald-700 font-semibold">→ {{ unitLabel(c.unit) }}</span>
                    <span v-else-if="!c.name.startsWith('(')" class="text-amber-700 font-semibold">sem de-para de local</span>
                  </p>
                </div>
                <button class="cv-btn cv-btn-ghost cv-btn-sm" @click="goItems({ clinic: c.name.startsWith('(') ? '' : c.name })">ver itens ›</button>
              </div>
              <div class="grid grid-cols-4 gap-2 mb-3">
                <div class="cv-of-stat"><b>{{ c.total }}</b><span>itens</span></div>
                <div class="cv-of-stat"><b class="text-blue-700">{{ c.agendada }}</b><span>agendados</span></div>
                <div class="cv-of-stat"><b class="text-emerald-700">{{ rate(c.realizada, c.total) }}%</b><span>realizados</span></div>
                <div class="cv-of-stat"><b class="text-red-600">{{ rate(c.cancelada + c.ausente, c.total) }}%</b><span>cancel. + faltas</span></div>
              </div>
              <p class="cv-label mb-1.5">Procedimentos nesta clínica</p>
              <HBars :rows="miniRows(c.top_procedures)" :series="[{ label: 'Itens', color: 'var(--cv-grad)' }]" :label-width="12" empty-text="sem procedimento informado" />
            </div>
          </div>
          <div class="cv-sub p-4 mt-4"><p class="cv-label mb-2">Tipos de procedimento no período</p><div class="flex flex-wrap gap-1"><button v-for="t in overview.types" :key="t.name" class="cv-chip" @click="goItems({ type: t.name.startsWith('(') ? '' : t.name })">{{ t.name }} · {{ t.total }}</button></div><p class="text-[11px] text-n-slate-10 mt-2">"Exame" vai para o trilho Exames, "Consulta" para Consultas, o resto para Cirurgias.</p></div>
        </section>

        <!-- ═══════════ PACIENTES (tabela) ═══════════ -->
        <section v-if="view === 'patients'" class="cv-block p-4 sm:p-6 mb-8" :style="blockVars('lista')">
          <div class="flex items-center gap-3 mb-3">
            <div class="flex-1 min-w-0"><h2 class="text-xl font-bold tracking-tight text-n-slate-12">Pacientes do hub</h2><p class="text-xs text-n-slate-10">cada pessoa uma vez, com quantos itens tem e se já existe no nosso cadastro</p></div>
            <span v-if="patients" class="cv-chip cv-chip-on">{{ patients.total }}</span>
          </div>
          <div class="flex items-center gap-2 flex-wrap mb-3">
            <input v-model="patientFilters.q" class="cv-input w-64" placeholder="🔎 nome, telefone ou CPF" />
            <button v-for="o in [['', 'Todos'], ['own', '⭐ CEVICO'], ['partners', 'Parceiros']]" :key="'pside' + o[0]" class="cv-chip" :class="patientFilters.side === o[0] ? 'cv-chip-on' : ''" @click="patientFilters.side = o[0]">{{ o[1] }}</button>
            <button class="cv-chip" :class="patientFilters.usePeriod ? 'cv-chip-on' : ''" @click="patientFilters.usePeriod = !patientFilters.usePeriod"><span class="i-lucide-calendar-range text-xs" /> {{ patientFilters.usePeriod ? 'no período' : 'todas as datas' }}</button>
          </div>
          <SkeletonScreen v-if="isLoadingPatients && !patients" variant="dashboard" />
          <div v-else-if="patients && !patients.rows.length" class="cv-sub p-8 text-center text-sm text-n-slate-10">Nenhum paciente com esses filtros.</div>
          <div v-else-if="patients" class="cv-of-tablewrap" :class="isLoadingPatients ? 'opacity-60' : ''">
            <table class="cv-of-table">
              <thead><tr><th>Paciente</th><th>Telefone</th><th>Parceiro(s)</th><th class="text-right">Itens</th><th>Primeiro</th><th>Último</th><th>Próximo</th><th>No nosso cadastro</th><th /></tr></thead>
              <tbody>
                <tr v-for="r in patients.rows" :key="`${r.patient_name}-${r.patient_phone}-${r.contact?.id}`" @click="goItems({ q: r.patient_phone || r.patient_name, usePeriod: false })">
                  <td class="font-semibold text-n-slate-12">{{ r.patient_name || '(sem nome)' }}</td>
                  <td class="tabular-nums whitespace-nowrap">{{ r.patient_phone || '—' }}</td>
                  <td><span v-if="r.own">⭐ </span>{{ r.providers.join(' · ') || '—' }}</td>
                  <td class="text-right font-bold tabular-nums">{{ r.total }}</td>
                  <td class="tabular-nums whitespace-nowrap">{{ fmtDate(r.first_date) || '—' }}</td>
                  <td class="tabular-nums whitespace-nowrap">{{ fmtDate(r.last_date) || '—' }}</td>
                  <td><span v-if="r.has_upcoming" class="cv-chip cv-blue">tem marcado</span><span v-else class="text-n-slate-9">—</span></td>
                  <td><router-link v-if="r.contact" class="cv-chip cv-green" :to="patientUrl(r)" @click.stop><span class="i-lucide-user-round text-xs" /> {{ r.contact.name }}</router-link><span v-else class="cv-chip cv-red"><span class="i-lucide-user-x text-xs" /> não casou</span></td>
                  <td class="text-right"><span class="text-xs text-n-slate-10">ver itens ›</span></td>
                </tr>
              </tbody>
            </table>
          </div>
          <div v-if="patients && patientPages > 1" class="flex items-center justify-end gap-2 mt-3">
            <span class="text-xs text-n-slate-10">página {{ patientsPage }} de {{ patientPages }}</span>
            <button class="cv-btn cv-btn-ghost cv-btn-sm" :disabled="patientsPage <= 1" @click="patientsPage -= 1">‹ Anterior</button>
            <button class="cv-btn cv-btn-sm" :disabled="patientsPage >= patientPages" @click="patientsPage += 1">Próxima ›</button>
          </div>
        </section>
      </template>
    </div>

    <!-- ficha do item -->
    <div v-if="detail" class="fixed inset-0 z-50 flex items-center justify-center bg-black/55 p-4" @click.self="detail = null">
      <div class="cv-modal cv-ag-pop w-full max-w-lg max-h-[92vh] flex flex-col" :style="pageStyle">
        <div class="cv-modal-head flex items-center gap-3">
          <span class="cv-glass w-9 h-9 flex items-center justify-center flex-shrink-0"><span class="i-lucide-hospital text-base" /></span>
          <div class="flex-1 min-w-0">
            <p class="text-[11px] font-bold uppercase tracking-wider opacity-85">{{ detail.procedure_type || 'Item' }} · {{ detail.status_kind_label }}</p>
            <h2 class="text-base font-bold leading-tight truncate">{{ detail.patient_name || '(sem nome)' }}</h2>
            <p class="text-[11px] opacity-90 truncate capitalize">{{ fmtDateLong(detail.surgery_date) }} · {{ detail.surgery_hour || 'sem hora' }} · {{ detail.own ? '⭐ CEVICO' : detail.provider_name }}</p>
          </div>
          <button class="cv-glass-btn cv-iconbtn" @click="detail = null"><span class="i-lucide-x" /></button>
        </div>
        <div class="flex-1 overflow-y-auto p-5 space-y-4 cv-ag-form">
          <section class="cv-ag-sec">
            <header class="cv-ag-sec-head"><span class="cv-ag-num">1</span><div><h3>Paciente</h3><p>como está lá e como casou aqui</p></div></header>
            <dl class="grid grid-cols-2 gap-x-4 gap-y-1.5 text-xs">
              <dt class="text-n-slate-10">Telefone</dt><dd class="text-n-slate-12 font-semibold tabular-nums">{{ detail.patient_phone || '—' }}</dd>
              <dt class="text-n-slate-10">E-mail</dt><dd class="text-n-slate-12 font-semibold truncate">{{ detail.patient_email || '—' }}</dd>
              <template v-if="isAdmin"><dt class="text-n-slate-10">CPF</dt><dd class="text-n-slate-12 font-semibold tabular-nums">{{ detail.patient_cpf || '—' }}</dd></template>
              <dt class="text-n-slate-10">Casou por</dt><dd class="text-n-slate-12 font-semibold">{{ { phone: 'telefone', cpf: 'CPF', name: 'nome', created: 'criado pelo sync' }[detail.match_via] || detail.match_via || '—' }}</dd>
              <dt class="text-n-slate-10">No sistema</dt><dd><router-link v-if="patientUrl(detail)" class="font-semibold hover:underline" style="color: var(--cv)" :to="patientUrl(detail)">{{ detail.contact.name }} →</router-link><span v-else class="text-red-600 font-semibold">sem paciente casado</span></dd>
            </dl>
          </section>
          <section class="cv-ag-sec">
            <header class="cv-ag-sec-head"><span class="cv-ag-num">2</span><div><h3>Procedimento</h3><p>o que foi indicado e onde</p></div></header>
            <dl class="grid grid-cols-2 gap-x-4 gap-y-1.5 text-xs">
              <dt class="text-n-slate-10">Procedimento</dt><dd class="text-n-slate-12 font-semibold">{{ detail.procedure_name || '—' }}<span v-if="detail.eye"> · {{ detail.eye }}</span></dd>
              <dt class="text-n-slate-10">Tipo</dt><dd class="text-n-slate-12 font-semibold">{{ detail.procedure_type || '—' }}</dd>
              <dt class="text-n-slate-10">Clínica</dt><dd class="text-n-slate-12 font-semibold">{{ detail.clinic_name || '—' }}<span v-if="detail.unit" class="text-n-slate-10"> → {{ unitLabel(detail.unit) }}</span><span v-else-if="detail.clinic_name" class="text-amber-600"> · sem de-para</span></dd>
              <dt class="text-n-slate-10">Médico</dt><dd class="text-n-slate-12 font-semibold">{{ detail.doctor || (detail.doctor_crm ? `CRM ${detail.doctor_crm}` : '—') }}</dd>
              <dt class="text-n-slate-10">Status lá</dt><dd class="text-n-slate-12 font-semibold">{{ detail.status_label || detail.status_kind_label }}</dd>
              <template v-if="isAdmin"><dt class="text-n-slate-10">Valor</dt><dd class="text-n-slate-12 font-semibold">{{ fmtBRL(detail.amount) }}<span v-if="Number(detail.paid_amount) > 0" class="text-n-slate-10"> · pago {{ fmtBRL(detail.paid_amount) }}</span></dd></template>
              <dt class="text-n-slate-10">Marcado lá em</dt><dd class="text-n-slate-12 font-semibold">{{ fmtWhen(detail.of_created_at) }}</dd>
              <dt class="text-n-slate-10">Última alteração lá</dt><dd class="text-n-slate-12 font-semibold">{{ fmtWhen(detail.of_modified_at) }}</dd>
            </dl>
          </section>
          <section class="cv-ag-sec">
            <header class="cv-ag-sec-head"><span class="cv-ag-num">3</span><div><h3>Do nosso lado</h3><p>Agenda e CRM</p></div></header>
            <div class="flex items-center gap-1.5 flex-wrap">
              <span class="cv-chip" :class="agendaStateOf(detail).tone"><span :class="agendaStateOf(detail).icon" class="text-xs" /> {{ agendaStateOf(detail).label }}</span>
              <span v-if="detail.task?.doctor" class="cv-chip cv-slate"><span class="i-lucide-stethoscope text-xs" /> {{ detail.task.doctor }}</span>
              <span v-if="detail.card" class="cv-chip"><span class="w-1.5 h-1.5 rounded-full" :style="{ background: detail.card.stage_color || '#94a3b8' }" /> {{ detail.card.stage }} · {{ detail.card.pipeline }}</span>
              <span v-else class="cv-chip cv-slate">sem card no CRM</span>
              <span v-if="detail.applied_action" class="cv-chip cv-slate" :title="`última ação do sync: ${detail.applied_action}`">sync: {{ detail.applied_action }}</span>
            </div>
          </section>
          <details v-if="isAdmin && detail.raw" class="cv-sub p-3">
            <summary class="text-xs font-bold text-n-slate-11 cursor-pointer">Registro bruto do hub (admin)</summary>
            <pre class="text-[10px] text-n-slate-11 whitespace-pre-wrap break-all mt-2">{{ JSON.stringify(detail.raw, null, 1) }}</pre>
          </details>
        </div>
        <div class="cv-modal-foot flex items-center gap-2">
          <button class="cv-btn cv-btn-ghost cv-btn-lg mr-auto" @click="detail = null">Fechar</button>
          <router-link v-if="patientUrl(detail)" class="cv-btn cv-btn-ghost cv-btn-lg" :to="patientUrl(detail)"><span class="i-lucide-user-round text-sm" /> Paciente</router-link>
          <router-link class="cv-btn cv-btn-lg" :to="agendaUrl(detail)"><span class="i-lucide-calendar-days text-sm" /> Abrir na Agenda</router-link>
        </div>
      </div>
    </div>

    <!-- 🎓 tutorial de primeiro uso: holofote no alvo + balão -->
    <div v-if="tourCurrent" class="cv-of-tour" @click.self="tourEnd">
      <div v-if="tourBox" class="cv-of-tour-spot" :style="{ top: `${tourBox.top}px`, left: `${tourBox.left}px`, width: `${tourBox.width}px`, height: `${tourBox.height}px` }" />
      <div class="cv-of-tour-pop cv-ag-pop" :style="tourPopStyle">
        <div class="flex items-center gap-2 mb-1.5">
          <span class="cv-ag-num">{{ tourStep + 1 }}</span>
          <p class="text-sm font-bold text-n-slate-12 flex-1">{{ tourCurrent.title }}</p>
          <span class="text-[10px] text-n-slate-10 tabular-nums">{{ tourStep + 1 }}/{{ TOUR.length }}</span>
        </div>
        <p class="text-xs text-n-slate-11 leading-relaxed">{{ tourCurrent.text }}</p>
        <div class="flex items-center gap-2 mt-3">
          <button class="text-xs text-n-slate-10 hover:underline mr-auto" @click="tourEnd">Pular</button>
          <button v-if="tourStep > 0" class="cv-btn cv-btn-ghost cv-btn-sm" @click="tourGo(tourStep - 1)">‹ Anterior</button>
          <button class="cv-btn cv-btn-sm" @click="tourGo(tourStep + 1)">{{ tourStep + 1 === TOUR.length ? 'Concluir ✓' : 'Próximo ›' }}</button>
        </div>
      </div>
    </div>
  </div>
</template>
