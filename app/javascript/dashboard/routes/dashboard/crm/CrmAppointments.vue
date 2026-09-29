<script setup>
// 📅 AMBIENTE AGENDAMENTOS (item 200, 22/09): "um ambiente em que os
// agendamentos são registrados; o trabalho das meninas será de monitoramento".
// Uma tela, no kit "iMac G3 + vidro":
//   1. RESUMO do período: marcadas, remarcadas, canceladas e robô × equipe.
//   2. REGISTROS: cada consulta marcada, remarcada ou cancelada (pelo robô ou
//      pela equipe), agrupada por dia, com caixa da conversa, etiquetas do
//      paciente, coluna do CRM, quem marcou, e os atalhos: abrir a conversa,
//      abrir o Espaço do Paciente, ligar e ver na Agenda.
//   3. AJUSTES (só admin): o que acontece sozinho quando uma consulta é
//      confirmada na conversa (etiquetas + coluna do CRM).
// Dados: GET crm/appointments/feed (tasks do tipo 'consulta', a mesma Agenda).
// Atualiza sozinho a cada 60 s enquanto a tela está aberta.
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { frontendURL } from 'dashboard/helper/URLHelper';
import CrmAPI from 'dashboard/api/crm';
import TasksAPI from 'dashboard/api/tasks';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import AreaChart from 'dashboard/components-next/cevico/AreaChart.vue';
import BridgeFlow from 'dashboard/components-next/cevico/BridgeFlow.vue';
import { bucketize } from 'dashboard/helper/cevicoBuckets';
import PatientListPopup from 'dashboard/components-next/cevico/PatientListPopup.vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import CevicoCallButton from 'dashboard/components-next/cevico/calls/CevicoCallButton.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { inboxSolidFor } from 'dashboard/helper/cevicoInboxColors';
import { formatPhoneBR } from 'dashboard/helper/cevicoCallsFormat';
import {
  KINDS as AGENDA_KINDS,
  kindFor,
  kindVars,
  hexToRgbSpaced,
} from 'dashboard/helper/cevicoAgenda';

const router = useRouter();
const store = useStore();
const accountId = useMapGetter('getCurrentAccountId');
const crmSettings = useMapGetter('crm/getSettings');
const inboxes = useMapGetter('inboxes/getInboxes');

const pal = useCevicoPalette({
  scope: 'crm:agendamentos',
  blocks: [
    { id: 'resumo', label: 'Resumo', icon: 'i-lucide-gauge' },
    { id: 'lista', label: 'Registros', icon: 'i-lucide-list' },
  ],
});
const { cvVars } = pal;

// ── cores FIXAS do tipo (não seguem a paleta: verde = marcou, âmbar =
//    remarcou, vermelho = cancelou, em qualquer tela) ──
const KIND_META = {
  agendada: {
    label: 'Marcada',
    verb: 'marcou às',
    color: '#059669',
    light: '#34d399',
    tone: 'cv-green',
    icon: 'i-lucide-calendar-plus',
  },
  reagendada: {
    label: 'Remarcada',
    verb: 'remarcou às',
    color: '#D97706',
    light: '#fbbf24',
    tone: 'cv-amber',
    icon: 'i-lucide-refresh-cw',
  },
  cancelada: {
    label: 'Cancelada',
    verb: 'cancelou às',
    color: '#DC2626',
    light: '#f87171',
    tone: 'cv-red',
    icon: 'i-lucide-calendar-x',
  },
  // 📅 item 217 (23/09): o que conta como o quê
  confirmada: {
    label: 'Confirmada',
    verb: 'confirmou às',
    color: '#2563eb',
    light: '#60a5fa',
    tone: 'cv-blue',
    icon: 'i-lucide-calendar-check',
  },
  nao_confirmou: {
    label: 'Não confirmou',
    verb: 'respondeu NÃO às',
    color: '#db2777',
    light: '#f472b6',
    tone: 'cv-pink',
    icon: 'i-lucide-message-circle-x',
  },
  lancada: {
    label: 'Lançada',
    verb: 'lançou às',
    color: '#64748b',
    light: '#94a3b8',
    tone: 'cv-slate',
    icon: 'i-lucide-clipboard-list',
  },
};
const kindMeta = row => KIND_META[row.kind] || KIND_META.agendada;
const kindLabel = row => {
  const meta = kindMeta(row);
  if (row.kind === 'reagendada' && Number(row.rescheduled_count) > 1) {
    return `${meta.label} ×${row.rescheduled_count}`;
  }
  return meta.label;
};
const kindBarStyle = row => ({ background: kindMeta(row).color });

// ── período + filtros ──
const period = ref({ preset: 'last7', from: '', to: '' });
// 📅 item 210 (23/09): seletor Consultas | Teleconsultas | Exames | Cirurgias
// (os mesmos 4 trilhos da Agenda, cada um na sua cor): tudo o que é marcado
// passa por este ambiente; as meninas acompanham cada tipo no seu lugar
const track = ref('consultas');
const trackKind = computed(() => kindFor(track.value));
const kindVarsOf = key => {
  const kk = kindFor(key);
  return {
    '--k-grad': kk.grad,
    '--k-deep': kk.deep,
    '--k-rgb': hexToRgbSpaced(kk.color),
    '--k-deep-rgb': hexToRgbSpaced(kk.deep),
  };
};
// 🎨 pedido 23/09: a COR do ambiente inteiro segue o tipo escolhido (como na
// Agenda) — a pessoa não confunde consulta com cirurgia; a paleta da página
// (Strawberry etc.) fica só de base
const pageStyle = computed(() => ({
  ...cvVars.value,
  ...kindVars(trackKind.value),
}));
const trackStyle = computed(() => kindVars(trackKind.value));
const noun = computed(() => trackKind.value.noun);
const nounPlural = computed(() => trackKind.value.plural);
const cap = s => s.charAt(0).toUpperCase() + s.slice(1);
// item 238: nomes que se explicam ("Registradas no período" confundia)
const MODES = computed(() => [
  {
    key: 'registradas',
    label: 'Marcações do período',
    hint: `o que foi marcado, remarcado, confirmado ou cancelado nestes dias — não importa para quando é a ${noun.value}`,
  },
  {
    key: 'consultas',
    label: 'Agenda do período',
    hint: `as ${nounPlural.value} com DATA nestes dias — não importa quando foram marcadas`,
  },
]);
const modeHint = computed(
  () => MODES.value.find(m => m.key === mode.value)?.hint || ''
);
const mode = ref('registradas');
const KINDS = [
  { key: '', label: 'Todas', tone: 'cv-blue', countKey: 'total' },
  {
    key: 'agendada',
    label: 'Marcadas',
    tone: 'cv-green',
    countKey: 'agendada',
  },
  {
    key: 'reagendada',
    label: 'Remarcadas',
    tone: 'cv-amber',
    countKey: 'reagendada',
  },
  {
    key: 'confirmada',
    label: 'Confirmadas',
    tone: 'cv-blue',
    countKey: 'confirmada',
  },
  {
    key: 'nao_confirmou',
    label: 'Não confirmou',
    tone: 'cv-pink',
    countKey: 'nao_confirmou',
  },
  {
    key: 'cancelada',
    label: 'Canceladas',
    tone: 'cv-red',
    countKey: 'cancelada',
  },
  {
    key: 'lancada',
    label: 'Lançadas',
    tone: 'cv-slate',
    countKey: 'lancada',
  },
];
const kind = ref('');
// 📅 item 217: o admin corrige o tipo de uma consulta ali mesmo — "Nova
// (agendamento)" ↔ "Já estava marcada (lançada)". A lista recarrega.
const isTogglingKind = ref(null);
const canEditKind = computed(() => booking.value?.can_edit === true);
const toggleBookingKind = async row => {
  if (isTogglingKind.value) return;
  isTogglingKind.value = row.task_id;
  const next = row.booking_kind === 'registro' ? 'agendamento' : 'registro';
  try {
    await TasksAPI.update(row.task_id, { booking_kind: next });
    useAlert(
      next === 'registro'
        ? 'Marcada como "já estava marcada": sai de Consultas agendadas.'
        : 'Marcada como consulta nova: conta em Consultas agendadas.'
    );
    await fetchFeed({ quiet: true });
  } catch {
    useAlert('Não deu para mudar o tipo desta consulta.');
  } finally {
    isTogglingKind.value = null;
  }
};
const SOURCES = [
  { key: 'ia', label: 'Robô', icon: 'i-lucide-bot', countKey: 'ia' },
  { key: 'equipe', label: 'Equipe', icon: 'i-lucide-user', countKey: 'equipe' },
];
const source = ref('');
const UNITS = [
  { key: 'paulista', label: 'Av. Paulista', color: '#EA580C' },
  { key: 'tatuape', label: 'Tatuapé', color: '#2563EB' },
];
// teleconsulta é online (sem unidade física): o filtro de unidade some
const showUnitFilter = computed(
  () => track.value === 'consultas' || track.value === 'exames'
);
// 📊 item 235: unidades e caixas MÚLTIPLAS (chips que ligam/desligam)
const units = ref([]);
const inboxIds = ref([]);
const q = ref('');
const byInbox = ref([]); // empilhamento por caixa, vem do servidor
const byOrigin = ref([]); // 27/09: das marcadas, a caixa por onde o paciente CHEGOU
const originItems = computed(() =>
  (byOrigin.value || []).map((b, i) => ({
    key: `o${b.inbox_id || 'none'}`,
    label: b.name || 'sem conversa',
    value: b.count,
    color: b.inbox_id ? inboxSolidFor(inboxes.value, b.inbox_id) : '#94a3b8',
    hint: `${b.count} marcada(s) de pacientes que chegaram por ${b.name || 'fora do sistema'}`,
    i,
  }))
);
const originTotal = computed(() =>
  (byOrigin.value || []).reduce((s, b) => s + (b.count || 0), 0)
);
const inboxOptions = computed(() =>
  (inboxes.value || []).map(i => ({ id: i.id, name: i.name }))
);
const toggleIn = (list, value) => {
  const i = list.value.indexOf(value);
  if (i >= 0) list.value.splice(i, 1);
  else list.value.push(value);
};
const toggleUnit = key => toggleIn(units, key);
const toggleInbox = id => toggleIn(inboxIds, Number(id));
const inboxCount = id =>
  (byInbox.value || []).find(b => Number(b.inbox_id) === Number(id))?.count ||
  0;
const stackTotal = computed(() =>
  (byInbox.value || []).reduce((s, b) => s + (b.count || 0), 0)
);
const INBOX_STACK_COLORS = [
  '#2563EB',
  '#EA580C',
  '#059669',
  '#7C3AED',
  '#DB2777',
  '#0D9488',
  '#D4A017',
  '#64748B',
];
const stackItems = computed(() =>
  (byInbox.value || []).map((b, i) => ({
    label: b.name,
    value: b.count,
    color: INBOX_STACK_COLORS[i % INBOX_STACK_COLORS.length],
  }))
);
// ── item 246: QUANDO o lead chegou em relação à marcação (coorte) ──
const COHORTS = [
  {
    key: 'mesmo_dia',
    label: 'no mesmo dia',
    short: 'chegou no dia',
    color: '#059669',
  },
  {
    key: 'semana',
    label: 'até 7 dias antes',
    short: 'chegou na semana',
    color: '#2563EB',
  },
  {
    key: 'mes',
    label: '8 a 30 dias antes',
    short: 'chegou no mês',
    color: '#D97706',
  },
  {
    key: 'antes',
    label: 'há mais de 30 dias',
    short: 'lead antigo',
    color: '#7C3AED',
  },
  {
    key: 'sem_cadastro',
    label: 'sem cadastro ligado',
    short: 'sem cadastro',
    color: '#94A3B8',
  },
];
const COHORT_BY_KEY = Object.fromEntries(COHORTS.map(c => [c.key, c]));
const cohort = ref('');
const cohortItems = computed(() => {
  const c = counts.value?.cohorts || {};
  return COHORTS.map(x => ({
    label: x.label,
    value: c[x.key] || 0,
    color: x.color,
  })).filter(x => x.value > 0);
});
const cohortTotal = computed(() =>
  cohortItems.value.reduce((a, b) => a + b.value, 0)
);
// "chegou há 5 dias" / "chegou no dia" (a partir do cadastro do contato)
const cohortChip = row => {
  const meta = COHORT_BY_KEY[row.lead_cohort];
  if (!meta) return null;
  if (!row.lead_arrived_at || row.lead_cohort === 'mesmo_dia')
    return { ...meta, text: meta.short };
  const days = Math.max(
    1,
    Math.round(
      (new Date(row.event_at || row.due_at || Date.now()) -
        new Date(row.lead_arrived_at)) /
        86400000
    )
  );
  const text =
    days > 60
      ? `lead há ${Math.round(days / 30)} meses`
      : `chegou há ${days} dia${days === 1 ? '' : 's'}`;
  return { ...meta, text };
};
// ── item 246: visualização em LISTA ou em CARDS (lembrada por pessoa) ──
const VIEW_KEY = 'cevico_appts_view';
const readView = () => {
  try {
    return localStorage.getItem(VIEW_KEY) === 'cards' ? 'cards' : 'lista';
  } catch {
    return 'lista';
  }
};
const listView = ref(readView());
watch(listView, v => {
  try {
    localStorage.setItem(VIEW_KEY, v);
  } catch {
    // sem armazenamento: vale só nesta visita
  }
});
const showGlossary = ref(false);

const hasFilters = computed(
  () =>
    Boolean(
      kind.value ||
        source.value ||
        cohort.value ||
        units.value.length ||
        inboxIds.value.length
    ) || String(q.value || '').trim().length > 0
);
const clearFilters = () => {
  kind.value = '';
  source.value = '';
  cohort.value = '';
  units.value = [];
  inboxIds.value = [];
  q.value = '';
};

// tipo e origem filtram AQUI (na tela): o backend já devolve o período
// inteiro e assim as contagens dos chips continuam certas com o filtro ligado
const feedParams = () => {
  const p = period.value || {};
  const params = { preset: p.preset, mode: mode.value, track: track.value };
  if (p.preset === 'custom') Object.assign(params, { from: p.from, to: p.to });
  if (units.value.length) params.units = [...units.value];
  if (inboxIds.value.length) params.inbox_ids = [...inboxIds.value];
  const term = String(q.value || '').trim();
  if (term.length >= 2) params.q = term;
  return params;
};

// ── formulário dos AJUSTES (só admin): etiquetas + coluna do CRM ao
//    confirmar; fica aqui em cima porque o carregamento o preenche ──
const showSettings = ref(false);
const isSaving = ref(false);
const form = ref({
  labels_enabled: true,
  labels: { created: '', rescheduled: '', canceled: '' },
  stage_id: '',
  cancel_stage_id: '',
  budget_stage_id: '', // 💰 item 236
});
const syncForm = cfg => {
  if (!cfg) return;
  form.value = {
    labels_enabled: cfg.labels_enabled !== false,
    labels: {
      created: cfg.labels?.created || '',
      rescheduled: cfg.labels?.rescheduled || '',
      canceled: cfg.labels?.canceled || '',
    },
    stage_id: cfg.stage_id ? String(cfg.stage_id) : '',
    cancel_stage_id: cfg.cancel_stage_id ? String(cfg.cancel_stage_id) : '',
    budget_stage_id: cfg.budget_stage_id ? String(cfg.budget_stage_id) : '',
  };
};

// ── carregar ──
const feed = ref(null);
const isLoading = ref(true);
const isRefreshing = ref(false);
const loadError = ref('');
let fetchSeq = 0;
// ── item 277: quem ENTROU na coluna "Agendamento de Consulta" (a regra dele) ──
const stageEntries = ref(null);
const fetchStageEntries = async () => {
  const p = period.value || {};
  const params = { preset: p.preset };
  if (p.preset === 'custom') Object.assign(params, { from: p.from, to: p.to });
  try {
    const { data } = await CrmAPI.appointmentsStageEntries(params);
    stageEntries.value = data;
  } catch {
    stageEntries.value = stageEntries.value || null;
  }
};
const entryPerson = r => ({
  id: r.contact_id,
  contact_id: r.contact_id,
  name: r.name,
  phone: r.phone,
  origin: r.origin,
  when: r.entered_at,
  meta: [
    r.stage_now ? `hoje em ${r.stage_now}` : null,
    r.consult
      ? `${r.consult.source === 'ia' ? 'robô' : 'equipe'} · ${r.consult.unit || ''}`
      : 'sem consulta na Agenda',
  ]
    .filter(Boolean)
    .join(' · '),
  conversation_id: r.conversation_id,
});
const openEntries = (title, subtitle, filter) => {
  const rows = (stageEntries.value?.rows || []).filter(filter);
  listPopup.value = {
    title,
    subtitle,
    people: rows.map(entryPerson),
    grad: 'linear-gradient(135deg, #6d28d9, #a78bfa)',
    icon: 'i-lucide-columns-3',
  };
};

const fetchFeed = async ({ quiet = false } = {}) => {
  fetchStageEntries();
  fetchSeq += 1;
  const seq = fetchSeq;
  if (quiet) isRefreshing.value = true;
  else isLoading.value = true;
  loadError.value = '';
  try {
    const { data } = await CrmAPI.appointmentsFeed(feedParams());
    if (seq !== fetchSeq) return; // chegou uma busca mais nova
    feed.value = data;
    byInbox.value = data.by_inbox || []; // item 235: empilhamento por caixa
    byOrigin.value = data.by_origin || [];
    if (!showSettings.value) syncForm(data.booking);
  } catch (error) {
    if (seq !== fetchSeq) return;
    loadError.value =
      error?.response?.data?.error ||
      'Não consegui carregar os agendamentos agora.';
  } finally {
    if (seq === fetchSeq) {
      isLoading.value = false;
      isRefreshing.value = false;
    }
  }
};

// carregando de novo com dados na tela (troca de modo, busca, minuto)
const busy = computed(() => isLoading.value || isRefreshing.value);
const rows = computed(() => feed.value?.rows || []);
const counts = computed(() => feed.value?.counts || {});
const booking = computed(() => feed.value?.booking || null);
// ── item 271 (28/09): QUEM são os pacientes das marcadas + a LISTA por trás
// de cada card ("não tenho informações claras sobre eles — e preciso ter") ──
const PATIENT_KINDS = [
  {
    key: 'novo',
    label: 'leads novos',
    one: 'lead novo',
    color: '#1d4ed8',
    hint: 'chegaram há até 30 dias',
  },
  {
    key: 'lead_antigo',
    label: 'leads antigos',
    one: 'lead antigo',
    color: '#0891b2',
    hint: 'chegaram há mais de 30 dias e nunca tinham consultado — ainda é aquisição',
  },
  {
    key: 'retorno',
    label: 'retornos',
    one: 'retorno',
    color: '#7c3aed',
    hint: 'já tinham consultado antes',
  },
  {
    key: 'cirurgia',
    label: 'pacientes de cirurgia',
    one: 'paciente de cirurgia',
    color: '#be123c',
    hint: 'já tinham cirurgia (Agenda ou Oftalmofácil)',
  },
  {
    key: 'sem_cadastro',
    label: 'sem cadastro',
    color: '#64748b',
    hint: 'consulta sem paciente ligado',
  },
];
const kindCounts = computed(() => counts.value?.kinds || {});
const listPopup = ref(null);
const personOf = r => ({
  id: r.task_id,
  task_id: r.task_id,
  contact_id: r.contact?.id,
  name: r.name,
  phone: r.phone,
  origin: r.origin_inbox?.name,
  when: r.event_at,
  meta: [
    r.unit_label,
    r.source === 'ia'
      ? 'pelo Atendente de IA'
      : r.creator?.name
        ? `por ${r.creator.name}`
        : null,
  ]
    .filter(Boolean)
    .join(' · '),
  conversation_id: r.conversation?.display_id,
});
const openList = (title, subtitle, list, grad, icon = 'i-lucide-users') => {
  listPopup.value = { title, subtitle, people: list.map(personOf), grad, icon };
};
const gradOf = k =>
  `linear-gradient(135deg, ${KIND_META[k].color}, ${KIND_META[k].light})`;
const openKindList = k =>
  openList(
    `${KIND_META[k].label}s no período`,
    KIND_META[k].label.toLowerCase(),
    rows.value.filter(r => r.kind === k),
    gradOf(k),
    KIND_META[k].icon
  );
const openSourceList = src =>
  openList(
    src === 'ia' ? 'Marcadas pelo Atendente de IA' : 'Marcadas pela equipe',
    'das marcadas no período',
    rows.value.filter(r => r.kind === 'agendada' && r.source === src),
    src === 'ia'
      ? 'linear-gradient(135deg, #7c3aed, #a78bfa)'
      : 'linear-gradient(135deg, #0f766e, #2dd4bf)',
    src === 'ia' ? 'i-lucide-bot' : 'i-lucide-users'
  );
const openPatientKind = pk =>
  openList(
    `Marcadas · ${pk.label}`,
    pk.hint,
    rows.value.filter(r => r.kind === 'agendada' && r.patient_kind === pk.key),
    `linear-gradient(135deg, ${pk.color}, ${pk.color}99)`,
    'i-lucide-user-round'
  );
const openOriginList = o => {
  const ids = new Set(o.task_ids || []);
  openList(
    `Marcadas que chegaram por ${o.name || 'fora do sistema'}`,
    'caixa da primeira conversa do paciente',
    rows.value.filter(r => r.kind === 'agendada' && ids.has(r.task_id)),
    `linear-gradient(135deg, ${o.inbox_id ? inboxSolidFor(inboxes.value, o.inbox_id) : '#94a3b8'}, #0f172a)`,
    'i-lucide-inbox'
  );
};
const marcadasKindsText = computed(() =>
  PATIENT_KINDS.filter(k => kindCounts.value[k.key])
    .map(
      k =>
        `${kindCounts.value[k.key]} ${kindCounts.value[k.key] === 1 ? k.one || k.label : k.label}`
    )
    .join(' · ')
);

// item 267: quantas das marcadas são de LEAD NOVO (chegou há até 30 dias) × da BASE
const marcadasSub = computed(() => {
  const c = counts.value?.cohorts || {};
  const novos = (c.mesmo_dia || 0) + (c.semana || 0) + (c.mes || 0);
  const base = (c.antes || 0) + (c.sem_cadastro || 0);
  if (!novos && !base) return `${nounPlural.value} novas`;
  // item 271: a "base" aberta (leads antigos · retornos · cirurgia · sem cadastro)
  return (
    marcadasKindsText.value ||
    `${novos} de leads novos · ${base} de pacientes da base`
  );
});
const iaShare = computed(() => {
  const ia = Number(counts.value.ia || 0);
  const equipe = Number(counts.value.equipe || 0);
  if (!ia && !equipe) return 0;
  return Math.round((ia / (ia + equipe)) * 100);
});
const kpiGrad = () => trackKind.value.grad2;

// ── item 285 (29/09): gráficos de ÁREA no lugar das barras em linha ──
// cada bloco mostra COMO o número se formou ao longo do período, uma área
// por fatia (caixa, tipo de paciente, tempo de chegada)
const marcadas = computed(() => rows.value.filter(r => r.kind === 'agendada'));
const areaOf = (items, since, until, at, key, meta) => {
  if (!items.length || !since || !until) return { labels: [], series: [] };
  const out = bucketize(items, since, until, at, key);
  return {
    labels: out.labels,
    granularity: out.granularity,
    series: Object.entries(out.series).map(([k, values]) => ({
      key: k,
      values,
      ...meta(k),
    })),
  };
};
const granText = g => {
  if (g === 'hour') return 'hora a hora';
  if (g === 'week') return 'semana a semana';
  return 'dia a dia';
};
const originMeta = list => k => {
  const o = (list || []).find(b => String(b.inbox_id || 'none') === k) || {};
  return {
    label: o.name || 'sem conversa',
    color: o.inbox_id ? inboxSolidFor(inboxes.value, o.inbox_id) : '#94a3b8',
    ref: o,
  };
};
const entriesArea = computed(() =>
  areaOf(
    stageEntries.value?.rows || [],
    stageEntries.value?.since,
    stageEntries.value?.until,
    r => r.entered_at,
    r => String(r.origin_id || 'none'),
    originMeta(stageEntries.value?.by_origin)
  )
);
const originArea = computed(() =>
  areaOf(
    marcadas.value,
    feed.value?.since,
    feed.value?.until,
    r => r.event_at,
    r => String(r.origin_inbox?.id || 'none'),
    originMeta(byOrigin.value)
  )
);
const kindArea = computed(() =>
  areaOf(
    marcadas.value,
    feed.value?.since,
    feed.value?.until,
    r => r.event_at,
    r => r.patient_kind || 'sem_cadastro',
    k => {
      const pk = PATIENT_KINDS.find(x => x.key === k) || {};
      return { label: pk.label || k, color: pk.color, hint: pk.hint, ref: pk };
    }
  )
);
const cohortArea = computed(() =>
  areaOf(
    marcadas.value,
    feed.value?.since,
    feed.value?.until,
    r => r.event_at,
    r => r.lead_cohort || 'sem_cadastro',
    k => ({
      label: COHORT_BY_KEY[k]?.label || k,
      color: COHORT_BY_KEY[k]?.color,
    })
  )
);
const stackArea = computed(() =>
  areaOf(
    rows.value,
    feed.value?.since,
    feed.value?.until,
    r => r.event_at,
    r => String(r.conversation?.inbox_id || 'none'),
    k => {
      const i = (byInbox.value || []).findIndex(
        b => String(b.inbox_id || 'none') === k
      );
      return {
        label: byInbox.value[i]?.name || 'sem conversa',
        color: INBOX_STACK_COLORS[Math.max(0, i) % INBOX_STACK_COLORS.length],
      };
    }
  )
);

// ── item 285: a PONTE "entraram na coluna × marcadas na Agenda" ──
// de onde veio cada número, como se ramifica e onde os pacientes estão hoje
const bridge = computed(() =>
  track.value === 'consultas' ? stageEntries.value?.bridge || null : null
);
const bridgeSides = computed(() => {
  const b = bridge.value;
  if (!b) return [];
  return [
    {
      key: 'column',
      title: `Entraram em ${b.stage?.name || 'Agendamento de Consulta'}`,
      total: b.column_total,
      unit: b.column_total === 1 ? 'paciente' : 'pacientes',
      caption: 'o card chegou na coluna do CRM',
      color: b.stage?.color || '#6d28d9',
      branches: b.column,
    },
    {
      key: 'agenda',
      title: 'Marcadas na Agenda',
      total: b.agenda_total,
      unit: b.agenda_total === 1 ? 'consulta nova' : 'consultas novas',
      caption:
        b.agenda_patients !== b.agenda_total
          ? `de ${b.agenda_patients} pacientes`
          : 'criadas no período',
      color: '#2563eb',
      branches: b.agenda,
    },
  ];
});
const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;
// a diferença em uma frase, do jeito que se fala
const bridgeSentence = computed(() => {
  const b = bridge.value;
  if (!b) return '';
  const others = (b.agenda || []).filter(x => x.key !== 'both');
  const rest = others.reduce((a, x) => a + x.count, 0);
  const parts = others.map(x => `${x.count} ${x.label}`);
  const head = `${plural(b.column_total, 'paciente entrou', 'pacientes entraram')} na coluna e ${plural(b.agenda_total, 'consulta foi marcada', 'consultas foram marcadas')} na Agenda. ${plural(b.both_patients, 'paciente está', 'pacientes estão')} nos dois números.`;
  if (!rest) return head;
  return `${head} As outras ${rest} marcadas são de quem não passou pela coluna neste período: ${parts.join(' · ')}.`;
});
const shortDay = ts =>
  ts
    ? new Date(ts).toLocaleDateString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
      })
    : '';
const bridgePerson = p => ({
  id: p.id,
  task_id: p.task_id,
  contact_id: p.contact_id,
  name: p.name || 'Paciente',
  phone: p.phone,
  when: p.when,
  meta: [
    p.stage_now ? `hoje em ${p.stage_now}` : 'sem card no CRM',
    p.pipeline ? `funil ${p.pipeline}` : null,
    p.passed_at ? `passou pela coluna em ${shortDay(p.passed_at)}` : null,
    p.due_at ? `consulta em ${shortDay(p.due_at)}` : null,
    p.source === 'ia' ? 'marcada pelo Atendente de IA' : null,
  ]
    .filter(Boolean)
    .join(' · '),
});
const openBridge = ({ side, branch }) => {
  listPopup.value = {
    title: `${side.title} · ${branch.label}`,
    subtitle: branch.hint,
    people: (branch.people || []).map(bridgePerson),
    grad: `linear-gradient(135deg, ${branch.color}, #0f172a)`,
    icon: 'i-lucide-git-fork',
  };
};

// ── datas em pt-BR ──
const pad = n => String(n).padStart(2, '0');
const dateKey = ts => {
  const d = new Date(ts);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};
const WEEKDAYS = [
  'domingo',
  'segunda',
  'terça',
  'quarta',
  'quinta',
  'sexta',
  'sábado',
];
const WEEKDAYS_SHORT = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
const dayLabel = key => {
  const now = new Date();
  if (key === dateKey(now)) return 'Hoje';
  const y = new Date(now);
  y.setDate(y.getDate() - 1);
  if (key === dateKey(y)) return 'Ontem';
  const d = new Date(`${key}T12:00:00`);
  return `${WEEKDAYS[d.getDay()]}, ${pad(d.getDate())}/${pad(d.getMonth() + 1)}`;
};
const timeOf = ts => {
  if (!ts) return '';
  return new Date(ts).toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  });
};
// "seg 28/09 às 14:30 · Av. Paulista · Dr. Fulano · Avaliação"
const whenOf = row => {
  const parts = [];
  if (row.due_at) {
    const d = new Date(row.due_at);
    parts.push(
      `${WEEKDAYS_SHORT[d.getDay()]} ${pad(d.getDate())}/${pad(d.getMonth() + 1)} às ${timeOf(d)}`
    );
  } else {
    parts.push('sem data');
  }
  if (row.unit_label) parts.push(row.unit_label);
  if (row.doctor) parts.push(row.doctor);
  if (row.procedure) parts.push(row.procedure);
  return parts.join(' · ');
};
const phoneOf = row => formatPhoneBR(row.phone || row.contact?.phone || '');
// relógio à direita da linha: no modo registradas é a hora em que marcou/
// remarcou/cancelou; no modo consultas é a hora da consulta
const rowClock = row => {
  const ts = mode.value === 'consultas' ? row.due_at : row.event_at;
  return timeOf(ts) || '--:--';
};
const rowClockCaption = row =>
  mode.value === 'consultas' ? noun.value : kindMeta(row).verb;

// ── lista: filtro local + ordem + grupos por dia ──
const groupField = computed(() =>
  mode.value === 'consultas' ? 'due_at' : 'event_at'
);
const visibleRows = computed(() => {
  let list = rows.value;
  if (kind.value) list = list.filter(r => r.kind === kind.value);
  if (source.value) list = list.filter(r => r.source === source.value);
  if (cohort.value) list = list.filter(r => r.lead_cohort === cohort.value);
  const field = groupField.value;
  // registradas: o mais recente primeiro; consultas: na ordem do dia
  const dir = mode.value === 'consultas' ? 1 : -1;
  return [...list].sort(
    (a, b) =>
      (new Date(a[field] || 0).getTime() - new Date(b[field] || 0).getTime()) *
      dir
  );
});
const groups = computed(() => {
  const field = groupField.value;
  const map = new Map();
  visibleRows.value.forEach(r => {
    const key = r[field] ? dateKey(r[field]) : 'sem-data';
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(r);
  });
  return [...map.entries()].map(([key, list]) => ({
    key,
    label: key === 'sem-data' ? 'Sem data' : dayLabel(key),
    rows: list,
  }));
});

// etiquetas do paciente ∪ etiquetas da conversa, sem repetir
const MAX_LABELS = 6;
const labelsOf = row => {
  const all = new Set([
    ...(row.contact?.labels || []),
    ...(row.conversation?.labels || []),
  ]);
  return [...all];
};
const shownLabels = row => labelsOf(row).slice(0, MAX_LABELS);
const hiddenLabelCount = row => Math.max(0, labelsOf(row).length - MAX_LABELS);
const inboxChipStyle = row => ({
  background: inboxSolidFor(inboxes.value, row.conversation?.inbox_id),
  color: '#fff',
  borderColor: 'transparent',
});
const stageDotStyle = row => ({
  background: row.card?.stage_color || '#94a3b8',
});

// ── ações da linha ──
const callsOn = computed(() => Boolean(crmSettings.value?.calls?.enabled));
const openConversation = row => {
  if (!row.conversation?.display_id) return;
  router.push(
    frontendURL(
      `accounts/${accountId.value}/conversations/${row.conversation.display_id}`
    )
  );
};
const patientUrl = row =>
  frontendURL(`accounts/${accountId.value}/patient/${row.contact.id}`);
// abre a Agenda no DIA e no TRILHO da linha (consultas/teleconsultas/exames/cirurgias)
const agendaUrl = row =>
  frontendURL(`accounts/${accountId.value}/agenda`, {
    date: dateKey(row.due_at),
    kind: row.track || track.value,
  });

// ── ajustes (só admin): abrir, mostrar a coluna efetiva e salvar ──
const toggleSettings = () => {
  if (!showSettings.value) syncForm(booking.value);
  showSettings.value = !showSettings.value;
};
const stageName = id => {
  const st = (booking.value?.stages || []).find(s => s.id === Number(id));
  return st ? `${st.name} (${st.pipeline})` : '';
};
const effectiveStageLabel = computed(() => {
  const name = stageName(booking.value?.effective_stage_id);
  return name ? `hoje o card vai para ${name}` : 'hoje o card não é movido';
});
const saveBooking = async () => {
  if (isSaving.value) return;
  isSaving.value = true;
  try {
    await CrmAPI.updateAgendaBooking({
      labels_enabled: form.value.labels_enabled,
      labels: { ...form.value.labels },
      stage_id: form.value.stage_id || null,
      cancel_stage_id: form.value.cancel_stage_id || null,
      budget_stage_id: form.value.budget_stage_id || null, // 💰 item 236
    });
    useAlert('Ajustes salvos.');
    showSettings.value = false;
    await fetchFeed({ quiet: true });
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui salvar os ajustes.');
  } finally {
    isSaving.value = false;
  }
};

// ── reações: filtros do backend refazem a busca; busca com pausa de 300 ms;
//    atualização silenciosa a cada 60 s ──
let searchTimer = null;
let refreshTimer = null;
watch(track, () => {
  if (!showUnitFilter.value) units.value = [];
});
watch([mode, track], () => fetchFeed());
watch([units, inboxIds], () => fetchFeed(), { deep: true }); // item 235
watch(period, () => fetchFeed(), { deep: true });
watch(q, () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => fetchFeed({ quiet: true }), 300);
});

onMounted(() => {
  fetchFeed();
  if (!crmSettings.value) store.dispatch('crm/fetchSettings').catch(() => {});
  if (!(inboxes.value || []).length)
    store.dispatch('inboxes/get').catch(() => {});
  refreshTimer = setInterval(() => fetchFeed({ quiet: true }), 60000);
});
onBeforeUnmount(() => {
  clearInterval(refreshTimer);
  clearTimeout(searchTimer);
});
</script>

<template>
  <div
    class="cv-page flex flex-col h-full w-full overflow-y-auto bg-n-surface-1"
    :style="pageStyle"
  >
    <div class="max-w-6xl mx-auto w-full p-4 sm:p-8">
      <CevicoHero
        :pal="pal"
        title="Agendamentos"
        :subtitle="`${cap(nounPlural)} marcadas, remarcadas, confirmadas, canceladas ou lançadas, quem marcou e por qual caixa; abra a conversa, o Espaço do Paciente ou ligue daqui`"
        :icon="trackKind.icon"
        :hero-bg="trackKind.hero"
        :palette="false"
      >
        <template #chips>
          <span v-if="feed" class="cv-glass-chip">
            <span class="i-lucide-calendar-check text-xs" />
            {{ counts.total || 0 }} no período
          </span>
          <span v-if="feed && busy" class="cv-glass-chip">
            <span class="i-lucide-loader-2 text-xs animate-spin" />
            atualizando
          </span>
        </template>
        <!-- 📅 o que MUDA a agenda, em destaque no banner: Consultas |
             Teleconsultas | Exames | Cirurgias (a cor do ambiente acompanha) -->
        <div class="w-full flex flex-col gap-2.5">
          <div
            class="cv-ag-kindbar"
            role="tablist"
            aria-label="Tipo de agendamento"
          >
            <button
              v-for="kk in AGENDA_KINDS"
              :key="kk.key"
              class="cv-ag-kind cv-ag-kind-hero"
              :class="track === kk.key ? 'cv-ag-kind-on' : ''"
              :style="kindVarsOf(kk.key)"
              role="tab"
              :aria-selected="track === kk.key"
              :title="`${kk.label} — ${kk.hint}`"
              @click="track = kk.key"
            >
              <span :class="kk.icon" class="text-sm" />
              {{ kk.label }}
            </button>
          </div>
          <div class="flex items-center gap-2 flex-wrap">
            <PeriodRuler v-model="period" glass />
          </div>
        </div>
      </CevicoHero>

      <SkeletonScreen v-if="isLoading && !feed" variant="dashboard" />

      <template v-else>
        <!-- erro -->
        <div
          v-if="loadError"
          class="cv-block cv-strip cv-red px-4 py-3.5 mb-8 flex items-center gap-3 flex-wrap"
        >
          <span class="cv-icon cv-icon-sm">
            <span class="i-lucide-triangle-alert text-xs" />
          </span>
          <p class="text-xs text-n-slate-11 flex-1 min-w-0">{{ loadError }}</p>
          <button class="cv-btn cv-btn-sm" @click="fetchFeed()">
            Tentar de novo
          </button>
        </div>

        <!-- ═══════════ RESUMO ═══════════ -->
        <section class="cv-block p-6 sm:p-9 mb-10" :style="trackStyle">
          <h2
            class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12 mb-1 flex items-center gap-2.5"
          >
            <div class="cv-icon">
              <span class="i-lucide-gauge text-base" />
            </div>
            Resumo
          </h2>
          <p class="text-xs text-n-slate-10 mb-6">
            {{
              mode === 'consultas'
                ? `${nounPlural} cuja data cai no período escolhido`
                : `o que aconteceu no período com as ${nounPlural}: marcações, remarcações, confirmações, cancelamentos e lançamentos (consulta que já estava marcada fora do sistema)`
            }}
          </p>
          <!-- item 277: o NÚMERO dele — entrou na coluna "Agendamento de Consulta" -->
          <div
            v-if="stageEntries"
            class="cv-ag-block p-5 sm:p-6 mb-6"
            :style="{ '--cv': stageEntries.stage?.color || '#6d28d9' }"
          >
            <div class="flex items-start gap-4 flex-wrap">
              <button
                class="text-left flex-shrink-0 cursor-pointer transition-transform hover:-translate-y-0.5"
                title="ver a lista: quem são, de onde vieram, como foi"
                @click="
                  openEntries(
                    `Entraram em ${stageEntries.stage?.name || 'Agendamento de Consulta'}`,
                    'um por paciente · clique para abrir a conversa',
                    () => true
                  )
                "
              >
                <p class="cv-ag-block-title">
                  Entraram em
                  {{ stageEntries.stage?.name || 'Agendamento de Consulta' }}
                </p>
                <p
                  class="text-5xl font-bold tabular-nums tracking-tight text-n-slate-12 leading-none mt-1"
                >
                  {{ stageEntries.total }}
                </p>
                <p class="cv-ag-block-sub mt-1">
                  pacientes cujo card CHEGOU nessa coluna do CRM no período (a
                  regra oficial de agendamento)
                  <template v-if="stageEntries.passages > stageEntries.total">
                    · {{ stageEntries.passages }} passagens
                  </template>
                  · clique para ver os nomes
                </p>
              </button>
              <div class="flex-1 min-w-[16rem]">
                <p class="text-[11px] font-bold text-n-slate-11 mb-1.5">
                  de quais caixas vieram (primeira conversa) ·
                  {{ granText(entriesArea.granularity) }}
                </p>
                <AreaChart
                  v-if="entriesArea.series.length"
                  :series="entriesArea.series"
                  :labels="entriesArea.labels"
                  :height="150"
                  :legend="false"
                  unit="entraram na coluna"
                />
                <p v-else class="text-[11px] text-n-slate-9">
                  ninguém no período
                </p>
                <div class="flex items-center gap-1.5 flex-wrap mt-2">
                  <button
                    v-for="o in stageEntries.by_origin"
                    :key="'eo' + (o.inbox_id || 'none')"
                    class="cv-chip"
                    :title="`ver quem chegou por ${o.name || 'fora do sistema'}`"
                    @click="
                      openEntries(
                        `Chegaram por ${o.name || 'fora do sistema'}`,
                        'e entraram em Agendamento de Consulta no período',
                        r => (r.origin_id || null) === (o.inbox_id || null)
                      )
                    "
                  >
                    <span
                      class="w-2 h-2 rounded-full"
                      :style="{
                        background: o.inbox_id
                          ? inboxSolidFor(inboxes, o.inbox_id)
                          : '#94a3b8',
                      }"
                    />
                    {{ o.name || 'sem conversa' }}
                    <b class="tabular-nums">{{ o.count }}</b>
                  </button>
                </div>
                <p class="text-[11px] font-bold text-n-slate-11 mt-4 mb-1.5">
                  como foi depois
                </p>
                <div class="flex items-center gap-1.5 flex-wrap">
                  <button
                    v-for="oc in stageEntries.by_outcome"
                    :key="'oc' + oc.key"
                    class="cv-chip"
                    :class="
                      oc.key === 'attended'
                        ? 'cv-green'
                        : oc.key === 'missed' || oc.key === 'canceled'
                          ? 'cv-red'
                          : oc.key === 'no_consult' || oc.key === 'past_unknown'
                            ? 'cv-amber'
                            : ''
                    "
                    :title="`ver quem: ${oc.label}`"
                    @click="
                      openEntries(
                        `Entraram em Agendamento · ${oc.label}`,
                        'no período',
                        r => r.outcome === oc.key
                      )
                    "
                  >
                    {{ oc.label }} <b class="tabular-nums">{{ oc.count }}</b>
                  </button>
                  <span
                    v-if="stageEntries.by_source"
                    class="cv-chip ml-auto"
                    title="das consultas ligadas a essas entradas, quem marcou"
                  >
                    <span class="i-lucide-bot text-xs" /> robô
                    <b class="tabular-nums">{{ stageEntries.by_source.ia }}</b>
                    × equipe
                    <b class="tabular-nums">{{
                      stageEntries.by_source.equipe
                    }}</b>
                  </span>
                </div>
              </div>
            </div>
          </div>

          <!-- item 285: a PONTE entre os dois números (coluna do CRM × Agenda) -->
          <div v-if="bridge" class="cv-ag-block p-5 sm:p-6 mb-6">
            <p class="cv-ag-block-title flex items-center gap-2">
              <span class="i-lucide-git-fork text-base" />
              Por que
              {{ plural(bridge.column_total, 'entrou', 'entraram') }}
              na coluna e
              {{ plural(bridge.agenda_total, 'foi marcada', 'foram marcadas') }}
            </p>
            <p class="cv-ag-block-sub mb-5">
              são duas réguas: a <b>coluna do CRM</b> conta o paciente cujo card
              chegou em {{ bridge.stage?.name }}; a <b>Agenda</b> conta cada
              consulta nova criada. {{ bridgeSentence }} Clique em um ramo para
              ver os nomes.
            </p>
            <BridgeFlow :sides="bridgeSides" @pick="openBridge" />
          </div>

          <p class="text-[11px] text-n-slate-10 mb-3">
            abaixo, o que a <b>Agenda</b> registrou (consultas marcadas,
            remarcadas, confirmadas…)
          </p>
          <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 sm:gap-4">
            <div
              class="cursor-pointer transition-transform hover:-translate-y-0.5"
              title="ver a lista de pacientes"
              @click="openKindList('agendada')"
            >
              <DashKpi
                label="Marcadas"
                :value="Number(counts.agendada || 0)"
                :sub="marcadasSub"
                :from="KIND_META.agendada.color"
                :to="KIND_META.agendada.light"
                glass
                compact
              />
            </div>
            <div
              class="cursor-pointer transition-transform hover:-translate-y-0.5"
              title="ver a lista de pacientes"
              @click="openKindList('reagendada')"
            >
              <DashKpi
                label="Remarcadas"
                :value="Number(counts.reagendada || 0)"
                sub="mudaram de dia ou hora"
                :from="KIND_META.reagendada.color"
                :to="KIND_META.reagendada.light"
                glass
                compact
              />
            </div>
            <div
              class="cursor-pointer transition-transform hover:-translate-y-0.5"
              title="ver a lista de pacientes"
              @click="openKindList('confirmada')"
            >
              <DashKpi
                label="Confirmadas"
                :value="Number(counts.confirmada || 0)"
                sub="responderam SIM ao lembrete"
                :from="KIND_META.confirmada.color"
                :to="KIND_META.confirmada.light"
                glass
                compact
              />
            </div>
            <div
              class="cursor-pointer transition-transform hover:-translate-y-0.5"
              title="ver a lista de pacientes"
              @click="openKindList('nao_confirmou')"
            >
              <DashKpi
                label="Não confirmou"
                :value="Number(counts.nao_confirmou || 0)"
                sub="responderam NÃO — ligar"
                :from="KIND_META.nao_confirmou.color"
                :to="KIND_META.nao_confirmou.light"
                glass
                compact
              />
            </div>
            <div
              class="cursor-pointer transition-transform hover:-translate-y-0.5"
              title="ver a lista de pacientes"
              @click="openKindList('cancelada')"
            >
              <DashKpi
                label="Canceladas"
                :value="Number(counts.cancelada || 0)"
                sub="desmarcadas no período"
                :from="KIND_META.cancelada.color"
                :to="KIND_META.cancelada.light"
                glass
                compact
              />
            </div>
            <div
              class="cursor-pointer transition-transform hover:-translate-y-0.5"
              title="ver a lista de pacientes"
              @click="openKindList('lancada')"
            >
              <DashKpi
                label="Lançadas"
                :value="Number(counts.lancada || 0)"
                sub="já estavam marcadas fora do sistema"
                :from="KIND_META.lancada.color"
                :to="KIND_META.lancada.light"
                glass
                compact
              />
            </div>
            <div
              class="cursor-pointer transition-transform hover:-translate-y-0.5"
              title="ver quem o Atendente de IA marcou e quem a equipe marcou"
              @click="
                openSourceList(
                  Number(counts.ia || 0) >= Number(counts.equipe || 0)
                    ? 'ia'
                    : 'equipe'
                )
              "
            >
              <DashKpi
                label="Marcadas pelo Atendente de IA × pela equipe"
                :value="`${Number(counts.ia || 0)} × ${Number(counts.equipe || 0)}`"
                :sub="`das ${Number(counts.agendada || 0)} marcadas, ${iaShare}% foram pelo Atendente de IA`"
                :grad="kpiGrad()"
                glass
                compact
              />
            </div>
          </div>

          <!-- item 271: QUEM SÃO os pacientes das marcadas — cada chip abre a lista -->
          <div class="cv-ag-divider" />
          <div class="cv-ag-block p-5 sm:p-6">
            <p class="cv-ag-block-title">Quem são os pacientes das marcadas</p>
            <p class="cv-ag-block-sub mb-4">
              das <b>{{ Number(counts.agendada || 0) }} marcadas</b>, quem é
              cada paciente: lead novo (até 30 dias), lead antigo (chegou há
              mais tempo e nunca tinha consultado — ainda é aquisição), retorno
              (já consultou), paciente de cirurgia ou sem cadastro ·
              {{ granText(kindArea.granularity) }} · clique para ver os nomes
            </p>
            <AreaChart
              v-if="kindArea.series.length"
              class="mb-4"
              :series="kindArea.series"
              :labels="kindArea.labels"
              :legend="false"
              unit="marcadas"
            />
            <div class="flex items-center gap-2 flex-wrap">
              <button
                v-for="pk in PATIENT_KINDS"
                :key="'pk' + pk.key"
                class="cv-chip"
                :class="kindCounts[pk.key] ? '' : 'opacity-50'"
                :title="pk.hint"
                :disabled="!kindCounts[pk.key]"
                @click="openPatientKind(pk)"
              >
                <span
                  class="w-2 h-2 rounded-full"
                  :style="{ background: pk.color }"
                />
                {{ pk.label }}
                <span class="opacity-80 tabular-nums">{{
                  kindCounts[pk.key] || 0
                }}</span>
                <span
v-if="counts.agendada" class="opacity-60 tabular-nums"
                  >·
                  {{
                    Math.round(
                      ((kindCounts[pk.key] || 0) / counts.agendada) * 100
                    )
                  }}%</span
                >
              </button>
            </div>
          </div>

          <!-- 27/09: DE QUAIS CAIXAS VIERAM as marcadas (caixa de origem do paciente) -->
          <div class="cv-ag-divider" />
          <div class="cv-ag-block p-5 sm:p-6">
            <p class="cv-ag-block-title">De quais caixas vieram as marcações</p>
            <p class="cv-ag-block-sub mb-4">
              das <b>{{ Number(counts.agendada || 0) }} marcadas</b>, a caixa
              por onde o paciente <b>chegou</b> (a primeira conversa dele:
              Google, Instagram…), não a da conversa mais recente — por isso a
              caixa de confirmação não rouba o crédito
            </p>
            <AreaChart
              v-if="originTotal && originArea.series.length"
              :series="originArea.series"
              :labels="originArea.labels"
              :legend="false"
              unit="marcadas"
            />
            <p v-else class="text-[11px] text-n-slate-9">
              nenhuma marcação no período
            </p>
            <div
              v-if="originTotal"
              class="flex items-center gap-2 flex-wrap mt-4"
            >
              <button
                v-for="o in originItems"
                :key="o.key"
                class="cv-chip"
                :title="o.hint + ' · clique para ver os nomes'"
                @click="openOriginList(byOrigin[o.i])"
              >
                <span
                  class="w-2 h-2 rounded-full"
                  :style="{ background: o.color }"
                />
                {{ o.label }}
                <span class="opacity-80 tabular-nums">{{ o.value }}</span>
                <span class="opacity-60 tabular-nums"
                  >· {{ Math.round((o.value / originTotal) * 100) }}%</span
                >
              </button>
            </div>
          </div>

          <!-- item 246: ENTENDER as marcações — quando o lead chegou + o que conta -->
          <div class="cv-ag-divider" />
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-5">
            <div class="cv-ag-block p-5 sm:p-6">
              <p class="cv-ag-block-title">Quando esses leads chegaram</p>
              <p class="cv-ag-block-sub mb-4">
                das <b>{{ Number(counts.agendada || 0) }} marcadas</b>, quantos
                dias entre o paciente chegar (cadastro) e a {{ noun }} ser
                marcada · clique para filtrar a lista
              </p>
              <AreaChart
                v-if="cohortTotal && cohortArea.series.length"
                :series="cohortArea.series"
                :labels="cohortArea.labels"
                :height="170"
                :legend="false"
                :active="cohort"
                unit="marcadas"
              />
              <p v-else class="text-[11px] text-n-slate-9">
                nenhuma marcação no período
              </p>
              <div class="flex items-center gap-1.5 flex-wrap mt-2.5">
                <button
                  v-for="c in COHORTS.filter(
                    x => (counts.cohorts || {})[x.key]
                  )"
                  :key="'coh' + c.key"
                  class="cv-chip"
                  :class="cohort === c.key ? 'cv-chip-on' : ''"
                  @click="cohort = cohort === c.key ? '' : c.key"
                >
                  <span
                    class="w-2 h-2 rounded-full"
                    :style="{ background: c.color }"
                  />
                  {{ c.label }}
                  <span class="opacity-80 tabular-nums">{{
                    counts.cohorts[c.key]
                  }}</span>
                </button>
              </div>
            </div>
            <div class="cv-ag-block p-5 sm:p-6">
              <div class="flex items-center gap-2">
                <p class="cv-ag-block-title flex-1">
                  O que cada número quer dizer
                </p>
                <button
                  class="cv-btn cv-btn-ghost cv-btn-sm"
                  @click="showGlossary = !showGlossary"
                >
                  {{ showGlossary ? 'recolher' : 'ver tudo' }}
                </button>
              </div>
              <ul
                class="mt-2 space-y-1.5 text-[11.5px] text-n-slate-11 leading-snug"
              >
                <li>
                  <b>Marcada</b> = {{ noun }} NOVA criada no período, pelo robô
                  ou pela equipe — o lead pode ter chegado hoje ou há meses
                  (veja ao lado).
                </li>
                <li>
                  <b>Não é marcada:</b> lançada (já estava marcada fora do
                  sistema), remarcação, confirmação — cada uma tem o seu cartão.
                </li>
                <template v-if="showGlossary">
                  <li>
                    <b>Caixa de entrada</b> = a da conversa de onde a
                    {{ noun }} saiu (ou a conversa mais recente do paciente).
                  </li>
                  <li>
                    <b>Meu Painel · Marcadas na Agenda</b> = estas mesmas
                    marcadas, sem exame, tele, cancelada e parceiro do
                    Oftalmofácil.
                  </li>
                  <li>
                    <b>Meu Painel · Entrou em Agendamento</b> = pessoas cujo
                    card MUDOU para a coluna "Agendamento de Consulta" no
                    período (é a taxa oficial). Difere das marcadas: quem já
                    estava na coluna, ou foi marcado sem card, não entra.
                  </li>
                  <li>
                    <b>% de agendamento</b> = entradas nessa coluna ÷ leads,
                    sempre dos últimos 30 dias (taxa madura).
                  </li>
                  <li>
                    <b>Chegaram e agendaram</b> = lead que chegou no período E
                    já foi marcado no mesmo período (a coorte "no mesmo
                    dia/semana" ao lado).
                  </li>
                  <li>
                    <b>Cuidado com fórmulas que misturam</b> "entrou em
                    Agendamento hoje" ÷ "leads de hoje": os agendados de hoje
                    vieram de vários dias; os leads de hoje ainda vão agendar.
                  </li>
                </template>
              </ul>
            </div>
          </div>
        </section>

        <!-- ═══════════ REGISTROS ═══════════ -->
        <section class="cv-block p-6 sm:p-9 mb-10" :style="trackStyle">
          <div class="flex items-center gap-2 flex-wrap mb-1">
            <h2
              class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12 flex items-center gap-2.5"
            >
              <div class="cv-icon">
                <span class="i-lucide-list text-base" />
              </div>
              Registros
              <span class="cv-chip">{{ visibleRows.length }}</span>
            </h2>
            <button
              v-if="booking?.can_edit"
              class="cv-btn cv-btn-ghost cv-btn-sm ml-auto"
              :class="showSettings ? 'cv-blue' : ''"
              title="O que acontece sozinho quando uma consulta é confirmada"
              @click="toggleSettings"
            >
              <span class="i-lucide-settings-2 text-xs" /> Ajustes
            </button>
          </div>
          <p class="text-xs text-n-slate-10 mb-5">
            agrupados por dia; cada linha mostra a caixa da conversa, as
            etiquetas do paciente, a coluna do CRM e quem marcou
          </p>

          <!-- AJUSTES (só admin) -->
          <div v-if="showSettings && booking" class="cv-pop p-4 sm:p-6 mb-6">
            <p class="text-sm font-semibold text-n-slate-12 mb-1">
              Ao confirmar uma consulta
            </p>
            <p class="text-xs text-n-slate-10 mb-4">
              Quando o robô ou a equipe confirma uma consulta na conversa, o
              sistema registra na Agenda, etiqueta o paciente e move o card
              sozinho.
            </p>

            <label class="flex items-center gap-2.5 mb-4 cursor-pointer">
              <button
                class="cv-switch"
                :class="form.labels_enabled ? 'cv-switch-on' : ''"
                role="switch"
                :aria-checked="form.labels_enabled"
                @click.prevent="form.labels_enabled = !form.labels_enabled"
              />
              <span class="text-sm text-n-slate-12">
                Etiquetar o paciente automaticamente
              </span>
            </label>

            <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-4">
              <label class="flex flex-col gap-1">
                <span class="cv-label">Etiqueta ao marcar</span>
                <input
                  v-model="form.labels.created"
                  type="text"
                  class="cv-input w-full"
                  placeholder="ex.: consulta_marcada"
                  :disabled="!form.labels_enabled"
                />
              </label>
              <label class="flex flex-col gap-1">
                <span class="cv-label">Etiqueta ao remarcar</span>
                <input
                  v-model="form.labels.rescheduled"
                  type="text"
                  class="cv-input w-full"
                  placeholder="ex.: consulta_remarcada"
                  :disabled="!form.labels_enabled"
                />
              </label>
              <label class="flex flex-col gap-1">
                <span class="cv-label">Etiqueta ao cancelar</span>
                <input
                  v-model="form.labels.canceled"
                  type="text"
                  class="cv-input w-full"
                  placeholder="ex.: consulta_cancelada"
                  :disabled="!form.labels_enabled"
                />
              </label>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-4">
              <label class="flex flex-col gap-1">
                <span class="cv-label">
                  Ao marcar ou remarcar, mover o card para
                </span>
                <select v-model="form.stage_id" class="cv-input w-full">
                  <option value="">
                    usar a coluna do Atendente de Agendamento
                  </option>
                  <option
                    v-for="st in booking.stages"
                    :key="st.id"
                    :value="String(st.id)"
                  >
                    {{ st.pipeline }} · {{ st.name }}
                  </option>
                </select>
                <span class="text-[11px] text-n-slate-9">
                  {{ effectiveStageLabel }}
                </span>
              </label>
              <label class="flex flex-col gap-1">
                <span class="cv-label">Ao cancelar, mover o card para</span>
                <select v-model="form.cancel_stage_id" class="cv-input w-full">
                  <option value="">não mover</option>
                  <option
                    v-for="st in booking.stages"
                    :key="st.id"
                    :value="String(st.id)"
                  >
                    {{ st.pipeline }} · {{ st.name }}
                  </option>
                </select>
              </label>
              <label class="flex flex-col gap-1 sm:col-span-2">
                <span class="cv-label">
                  💰 Quando a clínica manda um valor (R$), mover o card para
                </span>
                <select v-model="form.budget_stage_id" class="cv-input w-full">
                  <option value="">
                    a coluna do 1º funil com "orçamento" no nome
                  </option>
                  <option
                    v-for="st in booking.stages"
                    :key="'b' + st.id"
                    :value="String(st.id)"
                  >
                    {{ st.pipeline }} · {{ st.name }}
                  </option>
                </select>
                <span class="text-[11px] text-n-slate-9">
                  Robô ou equipe: qualquer mensagem enviada com "R$ 1.234" ou
                  "1.234 reais" leva o card pra frente até essa coluna (nunca
                  volta). É o que faz a taxa de agendamento contar a passagem
                  certa.
                </span>
              </label>
            </div>

            <div class="flex items-center justify-end gap-2">
              <button
                class="cv-btn cv-btn-ghost cv-btn-sm"
                :disabled="isSaving"
                @click="showSettings = false"
              >
                Cancelar
              </button>
              <button
                class="cv-btn cv-btn-sm cv-blue"
                :disabled="isSaving"
                @click="saveBooking"
              >
                <span
                  :class="
                    isSaving
                      ? 'i-lucide-loader-2 animate-spin'
                      : 'i-lucide-check'
                  "
                  class="text-xs"
                />
                {{ isSaving ? 'Salvando…' : 'Salvar' }}
              </button>
            </div>
          </div>

          <!-- item 246: filtros em BLOCOS (regra das telas): ① Ver · ② Situação · ③ Onde -->
          <section
            class="cv-ag-block p-4 mb-3 flex items-center gap-3 flex-wrap"
          >
            <p class="cv-ag-block-title">Ver</p>
            <div class="cv-seg cv-seg-sm inline-flex items-center gap-0.5">
              <button
                v-for="m in MODES"
                :key="m.key"
                class="cv-seg-item"
                :class="mode === m.key ? 'cv-seg-on' : ''"
                :title="m.hint"
                @click="mode = m.key"
              >
                {{ m.label }}
              </button>
            </div>
            <div
              class="cv-seg cv-seg-sm inline-flex items-center gap-0.5"
              title="Como mostrar os registros"
            >
              <button
                class="cv-seg-item"
                :class="listView === 'lista' ? 'cv-seg-on' : ''"
                @click="listView = 'lista'"
              >
                <span class="i-lucide-list text-sm" /> Lista
              </button>
              <button
                class="cv-seg-item"
                :class="listView === 'cards' ? 'cv-seg-on' : ''"
                @click="listView = 'cards'"
              >
                <span class="i-lucide-layout-grid text-sm" /> Cards
              </button>
            </div>
            <input
              v-model="q"
              type="search"
              placeholder="Buscar por nome ou telefone…"
              class="cv-input !h-8 text-xs w-full sm:!w-auto sm:min-w-[14rem] sm:ml-auto"
            />
            <button
              v-if="hasFilters"
              class="cv-btn cv-btn-ghost cv-btn-sm"
              @click="clearFilters"
            >
              <span class="i-lucide-x text-xs" /> Limpar
            </button>
            <button
              class="cv-btn cv-btn-sm"
              :disabled="busy"
              title="Buscar de novo agora (a tela também atualiza sozinha a cada minuto)"
              @click="fetchFeed({ quiet: true })"
            >
              <span
                :class="
                  busy
                    ? 'i-lucide-loader-2 animate-spin'
                    : 'i-lucide-refresh-cw'
                "
                class="text-xs"
              />
              Atualizar
            </button>
            <p class="basis-full text-[11px] text-n-slate-10 -mt-1">
              {{ modeHint }}
            </p>
          </section>

          <div class="grid grid-cols-1 xl:grid-cols-2 gap-5 mb-8">
            <!-- 28/09 (item 266): mais RESPIRO entre as linhas e entre as pílulas -->
            <section
              class="cv-ag-block p-6 sm:p-7 flex flex-col gap-6 cv-ag-filters"
            >
              <p class="cv-ag-block-title !mb-0">Situação</p>
              <div class="flex items-start gap-3">
                <span class="cv-ag-row-label">Registro</span>
                <div class="flex items-center gap-1.5 flex-wrap min-w-0">
                  <button
                    v-for="k in KINDS"
                    :key="k.key"
                    class="cv-chip"
                    :class="[k.tone, kind === k.key ? 'cv-chip-on' : '']"
                    @click="kind = k.key"
                  >
                    {{ k.label }}
                    <span class="opacity-80 tabular-nums">{{
                      counts[k.countKey] || 0
                    }}</span>
                  </button>
                </div>
              </div>
              <div class="flex items-start gap-3">
                <span class="cv-ag-row-label">Quem marcou</span>
                <div class="flex items-center gap-1.5 flex-wrap min-w-0">
                  <button
                    v-for="sr in SOURCES"
                    :key="sr.key"
                    class="cv-chip cv-blue"
                    :class="source === sr.key ? 'cv-chip-on' : ''"
                    :title="
                      sr.key === 'ia'
                        ? 'Só o que o robô marcou, remarcou ou cancelou'
                        : 'Só o que a equipe marcou, remarcou ou cancelou'
                    "
                    @click="source = source === sr.key ? '' : sr.key"
                  >
                    <span :class="sr.icon" class="text-xs" />
                    {{ sr.label }}
                    <span class="opacity-80 tabular-nums">{{
                      counts[sr.countKey] || 0
                    }}</span>
                  </button>
                </div>
              </div>
              <div class="flex items-start gap-3">
                <span class="cv-ag-row-label">Lead chegou</span>
                <div class="flex items-center gap-1.5 flex-wrap min-w-0">
                  <button
                    v-for="c in COHORTS"
                    :key="'fc' + c.key"
                    class="cv-chip"
                    :class="cohort === c.key ? 'cv-chip-on' : ''"
                    :title="`Marcadas cujo paciente chegou ${c.label} da marcação`"
                    @click="cohort = cohort === c.key ? '' : c.key"
                  >
                    <span
                      class="w-2 h-2 rounded-full"
                      :style="{ background: c.color }"
                    />
                    {{ c.label }}
                    <span class="opacity-80 tabular-nums">{{
                      (counts.cohorts || {})[c.key] || 0
                    }}</span>
                  </button>
                </div>
              </div>
            </section>

            <section
              class="cv-ag-block p-6 sm:p-7 flex flex-col gap-6 cv-ag-filters"
            >
              <p class="cv-ag-block-title !mb-0">Onde</p>
              <!-- 📊 item 235: unidades e caixas MÚLTIPLAS (ligue quantas quiser) -->
              <div v-if="showUnitFilter" class="flex items-start gap-3">
                <span class="cv-ag-row-label">Unidade</span>
                <div
                  class="flex items-center gap-1.5 flex-wrap min-w-0"
                  title="Unidades: ligue uma ou as duas"
                >
                  <button
                    v-for="u in UNITS"
                    :key="u.key"
                    class="cv-chip"
                    :class="units.includes(u.key) ? 'cv-chip-on' : ''"
                    @click="toggleUnit(u.key)"
                  >
                    <span
                      class="w-2 h-2 rounded-full flex-shrink-0"
                      :style="{ background: u.color }"
                    />
                    {{ u.label }}
                  </button>
                </div>
              </div>
              <div
                v-if="inboxOptions.length > 1"
                class="flex items-start gap-3"
              >
                <span class="cv-ag-row-label">Caixa</span>
                <div
                  class="flex items-center gap-1.5 flex-wrap min-w-0"
                  title="Caixas de entrada: ligue quantas quiser (o número é quanto cada uma trouxe no período)"
                >
                  <button
                    v-for="i in inboxOptions"
                    :key="i.id"
                    class="cv-chip"
                    :class="inboxIds.includes(Number(i.id)) ? 'cv-chip-on' : ''"
                    @click="toggleInbox(i.id)"
                  >
                    <span
                      class="w-2 h-2 rounded-full flex-shrink-0"
                      :style="{ background: inboxSolidFor(inboxes, i.id) }"
                    />
                    {{ i.name }}
                    <span class="opacity-80 tabular-nums">{{
                      inboxCount(i.id)
                    }}</span>
                  </button>
                </div>
              </div>
              <!-- 📊 item 235: de onde vêm os registros (fatia de cada caixa, antes do filtro de caixa) -->
              <div v-if="stackItems.length > 1" class="flex items-start gap-3">
                <span class="cv-ag-row-label">De onde</span>
                <div class="min-w-0 flex-1 pt-1.5">
                  <AreaChart
                    :series="stackArea.series"
                    :labels="stackArea.labels"
                    :height="130"
                    unit="registros"
                  />
                  <p class="text-[10px] text-n-slate-9 mt-1">
                    {{ stackTotal }} registros no período, por caixa de entrada
                  </p>
                </div>
              </div>
            </section>
          </div>

          <!-- vazio -->
          <div
            v-if="!visibleRows.length"
            class="cv-sub p-8 sm:p-10 text-center"
          >
            <span class="cv-icon cv-icon-xl mx-auto mb-3">
              <span class="i-lucide-calendar-off text-lg" />
            </span>
            <p class="text-sm font-semibold text-n-slate-12">
              Nenhum agendamento neste período.
            </p>
            <p class="text-xs text-n-slate-9 mt-1">
              {{
                hasFilters
                  ? 'experimente limpar os filtros ou mudar o período'
                  : `quando o robô ou a equipe confirmar ${noun === 'exame' ? 'um' : 'uma'} ${noun}, aparece aqui`
              }}
            </p>
          </div>

          <!-- item 246: CARDS agrupados por dia — cada registro em blocos (quem ·
               consulta · de onde · situação), leitura de relance -->
          <div v-else-if="listView === 'cards'" class="space-y-7">
            <div v-for="g in groups" :key="'cg' + g.key">
              <h3
                class="text-sm font-bold text-n-slate-12 mb-2.5 flex items-center gap-2"
              >
                <span class="i-lucide-calendar-days text-sm" />
                {{ g.label }}
                <span class="cv-chip">{{ g.rows.length }}</span>
              </h3>
              <div
                class="grid grid-cols-1 md:grid-cols-2 2xl:grid-cols-3 gap-3"
              >
                <div
                  v-for="row in g.rows"
                  :key="'c' + row.id"
                  class="cv-ag-block p-4 flex flex-col gap-3"
                  :style="{ borderTop: `3px solid ${kindMeta(row).color}` }"
                >
                  <!-- quem + quando aconteceu -->
                  <div class="flex items-start gap-3">
                    <Avatar
                      :name="row.name"
                      :src="row.contact?.thumbnail || ''"
                      :size="40"
                      rounded-full
                      gradient
                    />
                    <div class="min-w-0 flex-1">
                      <p class="text-sm font-bold text-n-slate-12 truncate">
                        {{ row.name }}
                      </p>
                      <p class="text-[11px] text-n-slate-10 tabular-nums">
                        {{ phoneOf(row) || 'sem telefone' }}
                      </p>
                    </div>
                    <div class="text-right shrink-0">
                      <p
                        class="text-base font-bold tabular-nums text-n-slate-12 leading-none"
                      >
                        {{ rowClock(row) }}
                      </p>
                      <p class="text-[10px] text-n-slate-9 mt-1">
                        {{ rowClockCaption(row) }}
                      </p>
                    </div>
                  </div>
                  <!-- situação -->
                  <div class="flex items-center gap-1.5 flex-wrap">
                    <span
class="cv-chip" :class="kindMeta(row).tone"
                      ><span :class="kindMeta(row).icon" class="text-xs" />
                      {{ kindLabel(row) }}</span
                    >
                    <span
                      class="cv-chip"
                      :class="row.source === 'ia' ? 'cv-blue' : ''"
                    >
                      <span
                        :class="
                          row.source === 'ia' ? 'i-lucide-bot' : 'i-lucide-user'
                        "
                        class="text-xs"
                      />
                      {{ row.source === 'ia' ? 'Robô' : 'Equipe'
                      }}<template v-if="row.assignee?.name">
                        · {{ row.assignee.name }}</template
                      >
                    </span>
                  </div>
                  <!-- blocos: consulta · de onde -->
                  <div class="grid grid-cols-2 gap-2">
                    <div class="cv-stat !p-2.5">
                      <p class="cv-ag-row-label !w-auto !pt-0 mb-1">
                        {{ cap(noun) }}
                      </p>
                      <p class="text-[11.5px] text-n-slate-12 leading-snug">
                        {{ whenOf(row) }}
                      </p>
                    </div>
                    <div class="cv-stat !p-2.5">
                      <p class="cv-ag-row-label !w-auto !pt-0 mb-1">De onde</p>
                      <p
                        class="text-[11.5px] text-n-slate-12 leading-snug truncate"
                      >
                        <span class="i-lucide-inbox text-[10px]" />
                        {{ row.conversation?.inbox_name || 'sem conversa' }}
                      </p>
                      <p
                        v-if="cohortChip(row)"
                        class="text-[11px] font-semibold mt-0.5"
                        :style="{ color: cohortChip(row).color }"
                      >
                        {{ cohortChip(row).text }}
                      </p>
                      <p
                        v-if="row.card?.stage"
                        class="text-[11px] text-n-slate-10 mt-0.5 truncate"
                        :title="row.card.pipeline"
                      >
                        <span
                          class="inline-block w-1.5 h-1.5 rounded-full align-middle"
                          :style="stageDotStyle(row)"
                        />
                        {{ row.card.stage }}
                      </p>
                    </div>
                  </div>
                  <!-- ações -->
                  <div
                    class="flex items-center gap-1.5 mt-auto pt-1 border-t border-n-weak"
                  >
                    <button
                      class="cv-btn cv-btn-ghost cv-btn-sm"
                      :disabled="!row.conversation"
                      @click="openConversation(row)"
                    >
                      <span class="i-lucide-message-circle text-xs" /> Conversa
                    </button>
                    <router-link
                      v-if="row.contact?.id"
                      class="cv-btn cv-btn-ghost cv-btn-sm"
                      :to="patientUrl(row)"
                    >
                      <span class="i-lucide-user-round text-xs" /> Paciente
                    </router-link>
                    <router-link
                      v-if="row.due_at"
                      class="cv-btn cv-btn-ghost cv-btn-sm ml-auto"
                      :to="agendaUrl(row)"
                    >
                      <span class="i-lucide-calendar-days text-xs" /> Agenda
                    </router-link>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- LISTA agrupada por dia -->
          <div v-else class="space-y-7">
            <div v-for="g in groups" :key="g.key">
              <h3
                class="text-sm font-bold text-n-slate-12 mb-2.5 flex items-center gap-2"
              >
                <span class="i-lucide-calendar-days text-sm" />
                {{ g.label }}
                <span class="cv-chip">{{ g.rows.length }}</span>
              </h3>
              <div class="space-y-2.5">
                <div
                  v-for="row in g.rows"
                  :key="row.id"
                  class="cv-row p-3 sm:p-4 flex flex-col sm:flex-row sm:items-center gap-3 sm:gap-4"
                >
                  <div class="flex gap-3 flex-1 min-w-0">
                    <!-- fio na cor do tipo -->
                    <span
                      class="w-1 self-stretch rounded-full flex-shrink-0"
                      :style="kindBarStyle(row)"
                    />
                    <Avatar
                      :name="row.name"
                      :src="row.contact?.thumbnail || ''"
                      :size="44"
                      rounded-full
                      gradient
                    />
                    <div class="min-w-0 flex-1">
                      <div class="flex items-center gap-2 flex-wrap">
                        <span class="cv-chip" :class="kindMeta(row).tone">
                          <span :class="kindMeta(row).icon" class="text-xs" />
                          {{ kindLabel(row) }}
                        </span>
                        <p
                          class="text-sm font-semibold text-n-slate-12 break-words"
                        >
                          {{ row.name }}
                        </p>
                        <span
                          v-if="phoneOf(row)"
                          class="text-xs text-n-slate-10 tabular-nums whitespace-nowrap"
                        >
                          {{ phoneOf(row) }}
                        </span>
                      </div>
                      <p
                        class="text-xs text-n-slate-10 mt-1.5 flex items-start gap-1.5"
                      >
                        <span
                          class="i-lucide-clock text-xs flex-shrink-0 mt-0.5"
                        />
                        <span class="break-words">{{ whenOf(row) }}</span>
                      </p>
                      <div class="flex items-center gap-1.5 flex-wrap mt-2">
                        <span
                          v-if="row.conversation"
                          class="cv-chip"
                          :style="inboxChipStyle(row)"
                          title="Caixa de entrada da conversa"
                        >
                          <span class="i-lucide-inbox text-xs" />
                          {{ row.conversation.inbox_name || 'Caixa' }}
                        </span>
                        <span
                          v-if="row.card?.stage"
                          class="cv-chip"
                          :title="`Coluna do CRM · ${row.card.pipeline || ''}`"
                        >
                          <span
                            class="w-1.5 h-1.5 rounded-full flex-shrink-0"
                            :style="stageDotStyle(row)"
                          />
                          {{ row.card.stage }}
                        </span>
                        <span
                          class="cv-chip"
                          :class="row.source === 'ia' ? 'cv-blue' : ''"
                          :title="
                            row.source === 'ia'
                              ? 'Registrado pelo robô'
                              : 'Registrado pela equipe'
                          "
                        >
                          <span
                            :class="
                              row.source === 'ia'
                                ? 'i-lucide-bot'
                                : 'i-lucide-user'
                            "
                            class="text-xs"
                          />
                          {{ row.source === 'ia' ? 'Robô' : 'Equipe' }}
                          <template v-if="row.assignee?.name">
                            · com {{ row.assignee.name }}
                          </template>
                        </span>
                        <!-- item 246: quando o lead chegou (em relação à marcação) -->
                        <span
                          v-if="cohortChip(row)"
                          class="cv-chip"
                          :style="{
                            '--cv-rgb': hexToRgbSpaced(cohortChip(row).color),
                            '--cv-deep': cohortChip(row).color,
                          }"
                          :title="
                            row.lead_arrived_at
                              ? `Paciente chegou em ${new Date(row.lead_arrived_at).toLocaleDateString('pt-BR')}`
                              : 'sem cadastro ligado'
                          "
                        >
                          <span class="i-lucide-user-plus text-[10px]" />
                          {{ cohortChip(row).text }}
                        </span>
                        <!-- 📅 item 217: o admin corrige "nova" ↔ "já estava marcada" -->
                        <button
                          v-if="
                            canEditKind &&
                            (row.kind === 'agendada' || row.kind === 'lancada')
                          "
                          class="cv-chip"
                          :class="
                            row.booking_kind === 'registro'
                              ? 'cv-slate'
                              : 'cv-green'
                          "
                          :disabled="isTogglingKind === row.task_id"
                          :title="
                            row.booking_kind === 'registro'
                              ? 'Está como já marcada fora do sistema (fora dos números). Clique para contar como consulta nova.'
                              : 'Está contando como consulta nova. Clique se ela já estava marcada fora do sistema (só foi lançada).'
                          "
                          @click="toggleBookingKind(row)"
                        >
                          <span class="i-lucide-arrow-left-right text-[10px]" />
                          {{
                            row.booking_kind === 'registro'
                              ? 'contar como nova'
                              : 'já estava marcada'
                          }}
                        </button>
                        <span
                          v-for="lb in shownLabels(row)"
                          :key="lb"
                          class="cv-chip"
                          title="Etiqueta do paciente"
                        >
                          <span class="i-lucide-tag text-[10px]" />
                          {{ lb }}
                        </span>
                        <span
                          v-if="hiddenLabelCount(row)"
                          class="cv-chip"
                          :title="labelsOf(row).slice(MAX_LABELS).join(', ')"
                        >
                          +{{ hiddenLabelCount(row) }}
                        </span>
                      </div>
                    </div>
                  </div>

                  <!-- no celular fica embaixo do conteúdo; no desktop, à direita -->
                  <div
                    class="flex flex-col gap-2 sm:items-end flex-shrink-0 pl-4 sm:pl-0"
                  >
                    <!-- hora do acontecimento (registradas) / da consulta (consultas) -->
                    <div
                      class="flex items-baseline gap-1.5 sm:block sm:text-right"
                    >
                      <p
                        class="text-base font-bold tabular-nums text-n-slate-12 leading-none"
                      >
                        {{ rowClock(row) }}
                      </p>
                      <p class="text-[10px] text-n-slate-9 sm:mt-1">
                        {{ rowClockCaption(row) }}
                      </p>
                    </div>

                    <!-- ações redondas com rótulo (as mesmas do painel do paciente) -->
                    <div
                      class="cv-chat cv-side-actions !justify-start sm:!justify-end"
                    >
                      <button
                        class="cv-side-action cv-side-action-main"
                        :disabled="!row.conversation"
                        :title="
                          row.conversation ? 'Abrir a conversa' : 'sem conversa'
                        "
                        @click="openConversation(row)"
                      >
                        <span class="cv-side-action-btn">
                          <span class="i-lucide-message-circle" />
                        </span>
                        <span>Conversa</span>
                      </button>
                      <router-link
                        v-if="row.contact?.id"
                        class="cv-side-action"
                        :to="patientUrl(row)"
                        title="Abrir o Espaço do Paciente"
                      >
                        <span class="cv-side-action-btn">
                          <span class="i-lucide-user-round" />
                        </span>
                        <span>Paciente</span>
                      </router-link>
                      <button
                        v-else
                        class="cv-side-action"
                        disabled
                        title="sem cadastro"
                      >
                        <span class="cv-side-action-btn">
                          <span class="i-lucide-user-round" />
                        </span>
                        <span>Paciente</span>
                      </button>
                      <div
                        v-if="callsOn && row.contact?.id && row.phone"
                        class="cv-side-action"
                        title="Ligar"
                      >
                        <CevicoCallButton
                          :contact-id="row.contact.id"
                          :inbox-id="row.conversation?.inbox_id"
                          :phone="row.phone"
                          :ghost="false"
                          faded
                        />
                        <span>Ligar</span>
                      </div>
                      <router-link
                        v-if="row.due_at"
                        class="cv-side-action"
                        :to="agendaUrl(row)"
                        title="Ver o dia na Agenda"
                      >
                        <span class="cv-side-action-btn">
                          <span class="i-lucide-calendar-days" />
                        </span>
                        <span>Agenda</span>
                      </router-link>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>
      </template>
    </div>
  </div>
  <PatientListPopup
    v-if="listPopup"
    :title="listPopup.title"
    :subtitle="listPopup.subtitle"
    :people="listPopup.people"
    :grad="listPopup.grad"
    :icon="listPopup.icon"
    :account-id="accountId"
    @close="listPopup = null"
  />
</template>
