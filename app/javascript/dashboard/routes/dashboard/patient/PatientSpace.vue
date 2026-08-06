<script setup>
// ESPAÇO DO PACIENTE (Central do Paciente) — edição "dopamine color":
// o ambiente inteiro se veste com a cor do paciente (sexo + idade),
// a jornada do funil vira uma pilha de estágios com tempos e etiquetas,
// e o Espaço do Médico é o protagonista (tudo-à-vista + anotações).
import { ref, computed, onMounted, watch } from 'vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { DOCTORS as SEGMENT_DOCTORS, MODALITIES, UNIT_LABELS as SEGMENT_UNIT_LABELS } from 'dashboard/helper/cevicoAgenda';
import { termo, termoCap, frase } from 'dashboard/helper/segmento';
import PatientSpaceIcon from './PatientSpaceIcon.vue';

const route = useRoute();
const router = useRouter();
const store = useStore();

const isLoading = ref(true);
const data = ref(null);
const showDetailed = ref(false);
const expandedForms = ref(new Set());

const contactId = computed(() => route.params.contactId);
const accountId = computed(() => route.params.accountId);
const currentRole = useMapGetter('getCurrentRole');
const currentUser = useMapGetter('getCurrentUser');
const isAdmin = computed(() => currentRole.value === 'administrator');

// ── Dados do paciente ──────────────────────────────────────────────
const fetchPatient = async () => {
  isLoading.value = true;
  try {
    const { data: payload } = await CrmAPI.getPatient(contactId.value);
    data.value = payload;
  } catch {
    data.value = null;
  } finally {
    isLoading.value = false;
  }
};

const identity = computed(() => data.value?.identity || {});
const indicators = computed(() => data.value?.indicators || {});
const timeline = computed(() => data.value?.timeline || []);
const labelEvents = computed(() => data.value?.label_events || []);
const automations = computed(() => data.value?.automations || {});
const updates = computed(() => data.value?.updates || {});

// ── DOPAMINE THEME: a cor do ambiente segue o paciente ─────────────
// Homem = azul (jovem → azul céu; maduro → azul profundo; 60+ → céu
// noturno estrelado). Mulher = rosa (jovem → rosa claro; madura → rosa
// intenso; 60+ → roxo). Sem sexo/idade no contato = azul CEVICO neutro.
const STAR_FIELD = [
  'radial-gradient(1.5px 1.5px at 12% 25%, rgba(255,255,255,0.95) 50%, transparent 51%)',
  'radial-gradient(1px 1px at 28% 65%, rgba(255,255,255,0.8) 50%, transparent 51%)',
  'radial-gradient(2px 2px at 42% 18%, rgba(255,255,255,0.9) 50%, transparent 51%)',
  'radial-gradient(1px 1px at 55% 72%, rgba(255,255,255,0.7) 50%, transparent 51%)',
  'radial-gradient(1.5px 1.5px at 67% 32%, rgba(255,255,255,0.95) 50%, transparent 51%)',
  'radial-gradient(1px 1px at 78% 58%, rgba(255,255,255,0.75) 50%, transparent 51%)',
  'radial-gradient(2px 2px at 88% 22%, rgba(255,255,255,0.85) 50%, transparent 51%)',
  'radial-gradient(1px 1px at 94% 70%, rgba(255,255,255,0.8) 50%, transparent 51%)',
  'radial-gradient(1px 1px at 20% 85%, rgba(255,255,255,0.6) 50%, transparent 51%)',
  'radial-gradient(1.5px 1.5px at 60% 88%, rgba(255,255,255,0.7) 50%, transparent 51%)',
].join(', ');

const THEMES = {
  blueYoung: {
    light: true, // fundo claro → letras escuras (contraste)
    grad: 'linear-gradient(135deg, #0EA5E9 0%, #38BDF8 45%, #7DD3FC 100%)',
    accent: '#0284C7',
    accentGrad: 'linear-gradient(135deg, #0EA5E9, #38BDF8)',
    stars: false,
  },
  blueAdult: {
    grad: 'linear-gradient(135deg, #075985 0%, #0284C7 50%, #38BDF8 100%)',
    accent: '#0284C7',
    accentGrad: 'linear-gradient(135deg, #0284C7, #38BDF8)',
    stars: false,
  },
  blueMature: {
    grad: 'linear-gradient(135deg, #0C4A6E 0%, #1D4ED8 55%, #3B82F6 100%)',
    accent: '#1D4ED8',
    accentGrad: 'linear-gradient(135deg, #1D4ED8, #3B82F6)',
    stars: false,
  },
  blueNight: {
    grad: 'linear-gradient(135deg, #0B1026 0%, #1E1B4B 45%, #1E3A8A 100%)',
    accent: '#6366F1',
    accentGrad: 'linear-gradient(135deg, #4F46E5, #818CF8)',
    stars: true,
  },
  pinkYoung: {
    light: true, // fundo claro → letras escuras (contraste)
    grad: 'linear-gradient(135deg, #EC4899 0%, #F472B6 45%, #F9A8D4 100%)',
    accent: '#DB2777',
    accentGrad: 'linear-gradient(135deg, #EC4899, #F472B6)',
    stars: false,
  },
  pinkAdult: {
    grad: 'linear-gradient(135deg, #BE185D 0%, #DB2777 50%, #F472B6 100%)',
    accent: '#DB2777',
    accentGrad: 'linear-gradient(135deg, #DB2777, #F472B6)',
    stars: false,
  },
  pinkMature: {
    grad: 'linear-gradient(135deg, #831843 0%, #9D174D 50%, #DB2777 100%)',
    accent: '#BE185D',
    accentGrad: 'linear-gradient(135deg, #9D174D, #DB2777)',
    stars: false,
  },
  purpleSenior: {
    grad: 'linear-gradient(135deg, #4C1D95 0%, #6B21A8 50%, #86198F 100%)',
    accent: '#7E22CE',
    accentGrad: 'linear-gradient(135deg, #7E22CE, #A855F7)',
    stars: false,
  },
  // sexo ainda desconhecido (começo do funil) = VERDE dopamine neutro;
  // quando o sexo é descoberto (equipe ou Secretário), a cor muda sozinha.
  // Fonte BRANCA (pedido 19/07): tinta escura fica SÓ nos temas clarinhos
  // de verdade (azul jovem e rosa jovem) — no verde ela sumia na parte
  // escura do degradê.
  greenNeutral: {
    grad: 'linear-gradient(135deg, #047857 0%, #10B981 50%, #34D399 100%)',
    accent: '#059669',
    accentGrad: 'linear-gradient(135deg, #059669, #34D399)',
    stars: false,
  },
};

// contraste automático: tema claro → tinta escura; tema escuro → branca
const isLightTheme = computed(() => !!theme.value.light);

const theme = computed(() => {
  const { gender, age } = identity.value;
  if (gender === 'male') {
    if (age === null || age === undefined) return THEMES.blueAdult;
    if (age < 25) return THEMES.blueYoung;
    if (age < 45) return THEMES.blueAdult;
    if (age < 60) return THEMES.blueMature;
    return THEMES.blueNight;
  }
  if (gender === 'female') {
    if (age === null || age === undefined) return THEMES.pinkAdult;
    if (age < 25) return THEMES.pinkYoung;
    if (age < 45) return THEMES.pinkAdult;
    if (age < 60) return THEMES.pinkMature;
    return THEMES.purpleSenior;
  }
  return THEMES.greenNeutral;
});

// seleção manual de sexo (botões em linha no cabeçalho)
const profileSaving = ref(false);
const setGender = async sexo => {
  if (profileSaving.value) return;
  profileSaving.value = true;
  try {
    await CrmAPI.updatePatientProfile(contactId.value, { sexo });
    await fetchPatient();
  } finally {
    profileSaving.value = false;
  }
};

// ── Formatação ─────────────────────────────────────────────────────
const fmtDate = iso => {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  });
};
const fmtShortDate = iso => {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: 'short',
  });
};
const fmtDateTime = iso => {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('pt-BR', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
};
const fmtMoney = v => {
  if (v === null || v === undefined || v === '') return null;
  return Number(v).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    maximumFractionDigits: 0,
  });
};
const fmtDuration = minutes => {
  if (!minutes && minutes !== 0) return null;
  if (minutes < 60) return `${minutes} min`;
  if (minutes < 60 * 24) return `${Math.round(minutes / 60)} h`;
  return `${Math.round(minutes / 60 / 24)} dia(s)`;
};

// modalidades e unidades do segmento (preset clínica = os de sempre)
const MODALITY_LABELS = Object.fromEntries(MODALITIES.map(m => [m.key, m.label]));
const UNIT_LABELS = SEGMENT_UNIT_LABELS;
const CHANNEL_LABELS = {
  Whatsapp: 'WhatsApp',
  FacebookPage: 'Instagram/Facebook',
  WebWidget: 'Site',
  Api: 'API',
  Email: 'E-mail',
  Sms: 'SMS',
};

// visual de cada tipo de evento (lista detalhada)
const EVENT_STYLE = {
  origem: { icon: 'i-lucide-megaphone', color: '#7C3AED' },
  conversa: { icon: 'i-lucide-message-circle', color: '#0F5FA6' },
  funil: { icon: 'i-lucide-kanban', color: '#64748B' },
  consulta: { icon: 'i-lucide-stethoscope', color: '#0284C7' },
  cirurgia: { icon: 'i-lucide-heart-pulse', color: '#B8860B' },
  fechamento: { icon: 'i-lucide-badge-dollar-sign', color: '#059669' },
  nps: { icon: 'i-lucide-star', color: '#D4A017' },
  formulario: { icon: 'i-lucide-clipboard-list', color: '#0D9488' },
  followup: { icon: 'i-lucide-bot', color: '#9333EA' },
};
const eventStyle = e => EVENT_STYLE[e.type] || EVENT_STYLE.funil;
const eventKey = (e, idx) => `${e.type}-${e.at}-${idx}`;
const detailedTimeline = computed(() => [...timeline.value].reverse());

const toggleForm = key => {
  const set = new Set(expandedForms.value);
  if (set.has(key)) set.delete(key);
  else set.add(key);
  expandedForms.value = set;
};

const openConversation = id => {
  router.push(frontendURL(`accounts/${accountId.value}/conversations/${id}`));
};

// ── JORNADA EMPILHADA: estágios do funil, do primeiro ao atual ─────
// Cada bloco = um estágio; à esquerda a data de entrada e o salto de dias;
// dentro, quanto tempo o paciente ficou; à direita as etiquetas ganhas
// naquele período. Embaixo, o total e a média por estágio.
const DAY_MS = 86400000;
const funnelJourney = computed(() => {
  const raw = timeline.value.filter(e => e.type === 'funil');
  // jornada CORRIDA: entradas repetidas no mesmo estágio (em sequência)
  // viram um bloco só — o que importa é o caminho, não o vai-e-volta
  const stages = raw.filter(
    (s, i) => i === 0 || s.stage !== raw[i - 1].stage
  );
  const labels = labelEvents.value;
  const now = new Date();

  const rows = stages.map((s, i) => {
    const start = new Date(s.at);
    const next = stages[i + 1] ? new Date(stages[i + 1].at) : null;
    const end = s.left_at ? new Date(s.left_at) : next || now;
    const days = Math.max(0, Math.round((end - start) / DAY_MS));
    const stageLabels = labels
      .filter(l => {
        const at = new Date(l.at);
        const afterStart = i === 0 ? true : at >= start; // etiquetas pré-funil entram no 1º
        return afterStart && (next ? at < next : true);
      })
      .map(l => l.label);
    return {
      key: `${s.at}-${i}`,
      stage: s.stage,
      color: s.stage_color || '#64748B',
      start,
      at: s.at,
      days,
      current: !next && !s.left_at,
      labels: [...new Set(stageLabels)],
    };
  });

  const totalDays = rows.length
    ? Math.max(0, Math.round((now - rows[0].start) / DAY_MS))
    : 0;
  const avgDays = rows.length ? (totalDays / rows.length).toFixed(1) : 0;
  return { rows, totalDays, avgDays };
});

// ── Dados dos cards de informação ───────────────────────────────────
const consultEvents = computed(() =>
  timeline.value.filter(e => e.type === 'consulta').reverse()
);
const surgeryEvents = computed(() =>
  timeline.value.filter(e => e.type === 'cirurgia').reverse()
);
const closingEvent = computed(() =>
  timeline.value.find(e => e.type === 'fechamento')
);
const npsEvent = computed(() => timeline.value.find(e => e.type === 'nps'));
const formEvents = computed(() =>
  timeline.value.filter(e => e.type === 'formulario')
);

// procedimento + investimento: orçamento de indicação (anotação do médico)
// × valor de fechamento → taxa de performance (quanto vendemos do máximo)
const latestIndication = computed(() => {
  const indicated = notes.value.find(
    n => String(n.fields?.surgery_indicated) === 'true'
  );
  if (indicated) {
    return {
      procedure: indicated.fields.indicated_procedure,
      value: Number(indicated.fields.indicated_value) || null,
      at: indicated.performed_at,
    };
  }
  const fromTask = consultEvents.value.find(e => e.indicated);
  if (fromTask) {
    return {
      procedure: fromTask.indicated_procedure,
      value: null,
      at: fromTask.at,
    };
  }
  return null;
});
const closingValue = computed(
  () =>
    Number(closingEvent.value?.value) || Number(indicators.value.value) || null
);
const performanceRate = computed(() => {
  const indicated = latestIndication.value?.value;
  const closed = Number(closingEvent.value?.value) || null;
  if (!indicated || !closed) return null;
  return Math.round((closed / indicated) * 100);
});

// ── Espaço do Médico (anotações clínicas) ──────────────────────────
const notesAllowed = ref(false);
const canEditNotes = ref(false);
const notes = ref([]);
const notesLoading = ref(false);

const fetchNotes = async () => {
  notesLoading.value = true;
  try {
    const { data: payload } = await CrmAPI.getClinicalNotes(contactId.value);
    notes.value = payload.notes || [];
    canEditNotes.value = payload.can_edit === true;
    notesAllowed.value = true;
  } catch {
    // 403 = sem acesso às anotações — a seção simplesmente não aparece
    notesAllowed.value = false;
    canEditNotes.value = false;
  } finally {
    notesLoading.value = false;
  }
};

// "à uma vista": resumo da última anotação para o time bater o olho
const latestNote = computed(() => notes.value[0] || null);

// ── PROCEDIMENTOS OFICIAIS (preços = orçamento de indicação) ────────
// O valor escolhido aqui é o orçamento OFICIAL da indicação; no fechamento
// a IA grava o valor final e a diferença vira a taxa de performance.
// Os preços vêm da TABELA DE PREÇOS (Configurações → Tabela de preços) —
// os valores abaixo são só o plano B enquanto as settings carregam.
const PROCEDURE_GROUPS = [
  {
    key: 'refrativa',
    label: 'Refrativa',
    optionLabel: 'Técnica',
    options: [
      { name: 'PRK', price: 4900 },
      { name: 'Lasik', price: 5700 },
    ],
  },
  {
    key: 'catarata',
    label: 'Catarata',
    optionLabel: 'Lente',
    options: [
      { name: 'Nacional', price: 2800 },
      { name: 'Mono Rayner', price: 3200 },
      { name: 'Tórica monofocal', price: 5600 },
      { name: 'Foco estendido', price: 5690 },
      { name: 'Trifocal', price: 8490 },
      { name: 'Galaxy', price: 14990 },
    ],
  },
  {
    key: 'faco_refrativa',
    label: 'Faco Refrativa',
    optionLabel: 'Lente',
    options: [
      { name: 'Trifocal', price: 8490 },
      { name: 'Galaxy', price: 14990 },
    ],
  },
  { key: 'artisan', label: 'Artisan', price: 11900, options: [] },
  {
    key: 'outros',
    label: 'Outros',
    optionLabel: 'Procedimento',
    options: [
      { name: 'Anel de Ferrara' },
      { name: 'Crosslinking' },
      { name: 'Glaucoma' },
      { name: 'Retina' },
      { name: 'Lente Escleral' },
      { name: 'Blefaroplastia' },
    ],
  },
];
// preço vigente por nome (promocional vence) vindo da tabela oficial
const officialPriceByName = computed(() => {
  const items = crmSettings.value?.price_table?.items || [];
  const map = {};
  items.forEach(item => {
    map[item.name.toLowerCase().trim()] =
      Number(item.promo_price || item.price) || undefined;
  });
  return map;
});
const withOfficialPrice = option => {
  const official = officialPriceByName.value[option.name?.toLowerCase().trim()];
  return official ? { ...option, price: official } : option;
};
const PROCEDURES = computed(() =>
  PROCEDURE_GROUPS.map(group => ({
    ...withOfficialPrice(group),
    options: group.options.map(withOfficialPrice),
  }))
);
const selectedProcedure = computed(() =>
  PROCEDURES.value.find(p => p.key === noteForm.value.procedure_type)
);

const EYES = ['OD', 'OE', 'AO'];
// nomes oficiais vêm do segmento (antes: lista duplicada dos 3 médicos)
const DOCTORS = SEGMENT_DOCTORS.map(d => d.name);

// formulário de anotação (campos rápidos — a vida do médico fácil)
const showNoteForm = ref(false);
const editingNote = ref(null);
const noteSaving = ref(false);
const noteForm = ref({});
const notePhotos = ref([]);
const removePhotoIds = ref([]);

const blankForm = () => ({
  doctor: '',
  performed_at: new Date().toISOString().slice(0, 10),
  task_id: null,
  procedure_type: '',
  procedure_option: '',
  eye: '',
  refraction_od: '',
  refraction_oe: '',
  acuity_od: '',
  acuity_oe: '',
  pio_od: '',
  pio_oe: '',
  biomicroscopy: '',
  fundoscopy: '',
  conductText: '',
  examsText: '',
  surgery_indicated: false,
  indicated_procedure: '',
  indicated_value: '',
  observations: '',
});

const pickProcedure = key => {
  const form = noteForm.value;
  if (form.procedure_type === key) {
    form.procedure_type = '';
    form.procedure_option = '';
    return;
  }
  form.procedure_type = key;
  form.procedure_option = '';
  const proc = PROCEDURES.value.find(p => p.key === key);
  if (proc?.price) applyIndication(proc.label, proc.price);
};

const pickOption = option => {
  const form = noteForm.value;
  const proc = selectedProcedure.value;
  form.procedure_option =
    form.procedure_option === option.name ? '' : option.name;
  if (form.procedure_option) {
    applyIndication(`${proc.label} — ${option.name}`, option.price || null);
  }
};

// escolher procedimento/lente GERA o orçamento de indicação (editável)
const applyIndication = (label, price) => {
  const form = noteForm.value;
  form.indicated_procedure = label;
  if (price) form.indicated_value = String(price);
};

// ── CONSULTA AUTOMÁTICA DE ESTOQUE na indicação (item 68) ──────────
// Indicou a lente → o sistema já consulta o estoque: tem? agendar a
// cirurgia para uma data próxima; não tem? encomendar — o PEDIDO nasce
// vinculado ao card do paciente com o motivo.
const stockLookup = ref({ state: 'idle', matches: [] });
const stockOrderCreated = ref(false);
const orderingStock = ref(false);
let stockTimer = null;

const stockQuery = computed(() => {
  if (!noteForm.value.surgery_indicated) return '';
  return (
    noteForm.value.procedure_option || noteForm.value.indicated_procedure || ''
  ).trim();
});

watch(stockQuery, q => {
  stockOrderCreated.value = false;
  clearTimeout(stockTimer);
  if (!q || q.length < 3) {
    stockLookup.value = { state: 'idle', matches: [] };
    return;
  }
  stockLookup.value = { state: 'loading', matches: [] };
  stockTimer = setTimeout(async () => {
    try {
      const { data: payload } = await CrmAPI.lookupStock(q);
      stockLookup.value = { state: 'done', matches: payload.matches || [] };
    } catch {
      // sem acesso/sem estoque cadastrado — a caixinha simplesmente não aparece
      stockLookup.value = { state: 'idle', matches: [] };
    }
  }, 400);
});

const stockAvailable = computed(() =>
  stockLookup.value.matches.filter(m => m.available)
);

const orderStockForPatient = async () => {
  orderingStock.value = true;
  try {
    // auditoria P1: se o lookup achou o item (zerado) no catálogo, o
    // pedido nasce VINCULADO a ele — o "Recebi ✓" repõe o estoque sozinho
    const catalogMatch = stockLookup.value.matches[0];
    await CrmAPI.createStockOrder({
      item_name: catalogMatch?.name || stockQuery.value,
      stock_item_id: catalogMatch?.id || null,
      quantity: 1,
      reason:
        `Indicação: ${noteForm.value.indicated_procedure || stockQuery.value}` +
        (identity.value?.name ? ` — paciente ${identity.value.name}` : ''),
      task_id: noteForm.value.task_id,
      contact_id: contactId.value,
    });
    stockOrderCreated.value = true;
    useAlert('Pedido criado e vinculado ao paciente. 🛒');
  } catch {
    useAlert('Não consegui criar o pedido de estoque.');
  } finally {
    orderingStock.value = false;
  }
};

// auditoria P2: sair para a Agenda no meio da anotação descartava tudo
// que o médico digitou — agora avisa antes
const goToAgendaForSurgery = () => {
  // eslint-disable-next-line no-alert
  const ok = window.confirm(
    'Você está no meio de uma anotação — o que não foi salvo se perde ao ir para a Agenda. Ir mesmo assim?'
  );
  if (!ok) return;
  router.push(frontendURL(`accounts/${accountId.value}/agenda`));
};

const openNewNote = () => {
  editingNote.value = null;
  noteForm.value = blankForm();
  notePhotos.value = [];
  removePhotoIds.value = [];
  showNoteForm.value = true;
};

const openEditNote = note => {
  editingNote.value = note;
  const f = note.fields || {};
  noteForm.value = {
    doctor: note.doctor || '',
    performed_at: (note.performed_at || '').slice(0, 10),
    task_id: note.task_id,
    procedure_type: f.procedure_type || '',
    procedure_option: f.procedure_option || f.technique || f.lens_type || '',
    eye: f.eye || '',
    refraction_od: f.refraction_od || '',
    refraction_oe: f.refraction_oe || '',
    acuity_od: f.acuity_od || '',
    acuity_oe: f.acuity_oe || '',
    pio_od: f.pio_od || '',
    pio_oe: f.pio_oe || '',
    biomicroscopy: f.biomicroscopy || '',
    fundoscopy: f.fundoscopy || '',
    conductText: (f.conduct || []).join('\n'),
    examsText: (f.exams_requested || []).join('\n'),
    surgery_indicated: String(f.surgery_indicated) === 'true',
    indicated_procedure: f.indicated_procedure || '',
    indicated_value: f.indicated_value ? String(f.indicated_value) : '',
    observations: note.observations || '',
  };
  notePhotos.value = [];
  removePhotoIds.value = [];
  showNoteForm.value = true;
};

const onPhotosSelected = event => {
  notePhotos.value = [
    ...notePhotos.value,
    ...Array.from(event.target.files || []),
  ];
  event.target.value = '';
};

const buildNoteFormData = () => {
  const f = noteForm.value;
  const fd = new FormData();
  fd.append('doctor', f.doctor || '');
  fd.append('performed_at', f.performed_at || '');
  if (f.task_id) fd.append('task_id', f.task_id);
  fd.append('observations', f.observations || '');
  const proc = selectedProcedure.value;
  const fields = {
    procedure_type: f.procedure_type,
    procedure_option: f.procedure_option,
    // compat: técnica (refrativa) e lente (catarata/faco) continuam gravadas
    technique: f.procedure_type === 'refrativa' ? f.procedure_option : '',
    lens_type: ['catarata', 'faco_refrativa'].includes(f.procedure_type)
      ? f.procedure_option
      : '',
    eye: f.eye,
    refraction_od: f.refraction_od,
    refraction_oe: f.refraction_oe,
    acuity_od: f.acuity_od,
    acuity_oe: f.acuity_oe,
    pio_od: f.pio_od,
    pio_oe: f.pio_oe,
    biomicroscopy: f.biomicroscopy,
    fundoscopy: f.fundoscopy,
    surgery_indicated: f.surgery_indicated ? 'true' : '',
    indicated_procedure: f.surgery_indicated
      ? f.indicated_procedure ||
        (proc
          ? `${proc.label}${f.procedure_option ? ` — ${f.procedure_option}` : ''}`
          : '')
      : '',
    indicated_value: f.surgery_indicated ? f.indicated_value : '',
  };
  Object.entries(fields).forEach(([key, value]) => {
    if (value) fd.append(`fields[${key}]`, value);
  });
  f.conductText
    .split('\n')
    .map(s => s.trim())
    .filter(Boolean)
    .forEach(item => fd.append('fields[conduct][]', item));
  f.examsText
    .split('\n')
    .map(s => s.trim())
    .filter(Boolean)
    .forEach(item => fd.append('fields[exams_requested][]', item));
  notePhotos.value.forEach(file => fd.append('photos[]', file));
  removePhotoIds.value.forEach(id => fd.append('remove_photo_ids[]', id));
  return fd;
};

const saveNote = async () => {
  noteSaving.value = true;
  try {
    const fd = buildNoteFormData();
    if (editingNote.value) {
      await CrmAPI.updateClinicalNote(
        contactId.value,
        editingNote.value.id,
        fd
      );
    } else {
      await CrmAPI.createClinicalNote(contactId.value, fd);
    }
    showNoteForm.value = false;
    await Promise.all([fetchNotes(), fetchPatient()]);
  } catch {
    // mantém o formulário aberto para não perder o que o médico digitou
  } finally {
    noteSaving.value = false;
  }
};

const deleteNote = async note => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm('Excluir esta anotação clínica? Essa ação não tem volta.')
  )
    return;
  try {
    await CrmAPI.deleteClinicalNote(contactId.value, note.id);
    useAlert('Anotação excluída.');
  } catch (error) {
    useAlert(
      error?.response?.data?.error || 'Não consegui excluir a anotação.'
    );
  }
  fetchNotes();
};

const canTouchNote = note =>
  canEditNotes.value &&
  (isAdmin.value || note.author?.id === currentUser.value?.id);

// consultas da linha do tempo (para ligar a anotação a uma consulta)
const consultOptions = computed(() =>
  timeline.value
    .filter(e => e.type === 'consulta' && e.task_id)
    .map(e => ({
      id: e.task_id,
      label: `${fmtDate(e.at)} — ${MODALITY_LABELS[e.modality] || 'Consulta'}${e.doctor ? ` · ${e.doctor}` : ''}`,
    }))
    .reverse()
);

// pílulas de resumo da anotação
const notePills = note => {
  const f = note.fields || {};
  const pills = [];
  const proc = PROCEDURES.value.find(p => p.key === f.procedure_type);
  if (proc) pills.push(proc.label);
  else if (f.procedure_type) pills.push(f.procedure_type);
  const option = f.procedure_option || f.technique || f.lens_type;
  if (option) pills.push(option);
  if (f.eye) pills.push(`Olho: ${f.eye}`);
  if (f.pio_od || f.pio_oe)
    pills.push(
      `PIO ${[f.pio_od && `OD ${f.pio_od}`, f.pio_oe && `OE ${f.pio_oe}`].filter(Boolean).join(' · ')}`
    );
  return pills;
};

// ── Configuração de acesso (admin) ─────────────────────────────────
const showAccessConfig = ref(false);
const accessSaving = ref(false);
const doctorUserIds = ref([]);
const teamView = ref(false);
const agents = useMapGetter('agents/getAgents');
const crmSettings = useMapGetter('crm/getSettings');

const loadAccessConfig = () => {
  const access = crmSettings.value?.clinical_access || {};
  doctorUserIds.value = [...(access.doctor_user_ids || [])];
  teamView.value = access.team_view === true;
};
watch(crmSettings, loadAccessConfig);

const toggleDoctorUser = id => {
  doctorUserIds.value = doctorUserIds.value.includes(id)
    ? doctorUserIds.value.filter(x => x !== id)
    : [...doctorUserIds.value, id];
};

const saveAccessConfig = async () => {
  accessSaving.value = true;
  try {
    await CrmAPI.updateClinicalAccess({
      doctor_user_ids: doctorUserIds.value,
      team_view: teamView.value,
    });
    await store.dispatch('crm/fetchSettings').catch(() => {});
    showAccessConfig.value = false;
    fetchNotes();
  } finally {
    accessSaving.value = false;
  }
};

onMounted(() => {
  fetchPatient();
  fetchNotes();
  if (!(agents.value || []).length)
    store.dispatch('agents/get').catch(() => {});
  if (!crmSettings.value) store.dispatch('crm/fetchSettings').catch(() => {});
  loadAccessConfig();
});
watch(contactId, () => {
  fetchPatient();
  fetchNotes();
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-6xl mx-auto w-full p-4 sm:p-8">
      <SkeletonScreen v-if="isLoading" variant="dashboard" />

      <div v-else-if="!data" class="text-center py-16">
        <p class="text-sm text-n-slate-10">
          Não consegui carregar este paciente.
        </p>
      </div>

      <template v-else>
        <!-- ══ Cabeçalho dopamine (a cor segue o paciente) ══ -->
        <div
          class="relative rounded-2xl p-5 mb-5 text-white shadow-lg overflow-hidden"
          :class="isLightTheme ? 'cevico-ink-dark' : ''"
          :style="{ background: theme.grad }"
        >
          <div
            v-if="theme.stars"
            class="absolute inset-0 pointer-events-none"
            :style="{ backgroundImage: STAR_FIELD }"
          />
          <div class="relative flex items-start gap-4 flex-wrap">
            <img
              v-if="identity.thumbnail"
              :src="identity.thumbnail"
              class="w-16 h-16 rounded-2xl object-cover border-2 border-white/30"
            />
            <span
              v-else
              class="w-16 h-16 rounded-2xl bg-white/15 flex items-center justify-center"
            >
              <span class="i-lucide-user text-3xl text-white/80" />
            </span>
            <div class="flex-1 min-w-[220px]">
              <div class="flex items-center gap-2 flex-wrap">
                <h1 class="text-xl font-bold leading-tight">
                  {{ identity.name || 'Paciente' }}
                </h1>
                <span
                  v-if="identity.age"
                  class="px-2 py-0.5 rounded-full bg-white/20 text-[11px] font-semibold"
                >
                  {{ identity.age }} anos
                </span>
                <!-- sexo: botões em linha (muda o tema da página na hora) -->
                <span class="flex items-center gap-1">
                  <button
                    class="px-2 py-0.5 rounded-full text-[11px] font-semibold transition-all"
                    :class="identity.gender === 'male' ? 'bg-white text-sky-700 shadow-sm' : 'bg-white/15 text-white/70 hover:bg-white/25'"
                    :disabled="profileSaving"
                    title="Marcar como homem"
                    @click="setGender('masculino')"
                  >
                    ♂ Homem
                  </button>
                  <button
                    class="px-2 py-0.5 rounded-full text-[11px] font-semibold transition-all"
                    :class="identity.gender === 'female' ? 'bg-white text-pink-600 shadow-sm' : 'bg-white/15 text-white/70 hover:bg-white/25'"
                    :disabled="profileSaving"
                    title="Marcar como mulher"
                    @click="setGender('feminino')"
                  >
                    ♀ Mulher
                  </button>
                </span>
              </div>
              <div
                class="flex items-center gap-3 flex-wrap mt-1 text-[13px] text-white/85"
              >
                <span
                  v-if="identity.phone_number"
                  class="flex items-center gap-1"
                >
                  <span class="i-lucide-phone text-xs" />
                  {{ identity.phone_number }}
                </span>
                <span v-if="identity.email" class="flex items-center gap-1">
                  <span class="i-lucide-mail text-xs" /> {{ identity.email }}
                </span>
                <span class="flex items-center gap-1">
                  <span class="i-lucide-clock text-xs" />
                  paciente desde {{ fmtDate(identity.created_at) }}
                </span>
              </div>
              <div
                v-if="(identity.labels || []).length"
                class="flex items-center gap-1.5 flex-wrap mt-2"
              >
                <span
                  v-for="label in identity.labels"
                  :key="label"
                  class="px-2 py-0.5 rounded-full bg-white/15 text-[11px] font-medium"
                >
                  {{ label }}
                </span>
              </div>
              <!-- anúncio de origem: a PLACA DOURADA do primeiro contato -->
              <div
                v-if="identity.origin"
                class="mt-2.5 flex items-center gap-2 rounded-xl px-3 py-2 w-fit max-w-full"
                style="background: rgba(212, 175, 55, 0.18); border: 1.5px solid rgba(212, 175, 55, 0.65); box-shadow: 0 2px 10px rgba(212, 175, 55, 0.25)"
              >
                <span class="i-lucide-megaphone text-sm shrink-0" style="color: #f4de8e" />
                <p class="text-[12px] truncate">
                  <span class="font-bold uppercase tracking-wide text-[10px]" style="color: #f4de8e">Anúncio do 1º contato</span><br />
                  <strong>{{
                    identity.origin.ad_name ||
                    identity.origin.headline ||
                    'Meta Ads'
                  }}</strong>
                  · {{ fmtDate(identity.origin.captured_at) }}
                </p>
              </div>
            </div>

            <!-- trunfo: card do funil + sinais rápidos -->
            <div class="flex flex-col gap-2 min-w-[190px]">
              <div
                v-for="card in identity.cards"
                :key="card.id"
                class="bg-white/12 backdrop-blur rounded-xl px-3.5 py-2.5"
              >
                <p class="text-[10px] uppercase tracking-wide text-white/60">
                  {{ card.pipeline }}
                </p>
                <p class="text-sm font-bold flex items-center gap-1.5">
                  <span
                    class="w-2 h-2 rounded-full inline-block"
                    :style="{ background: card.stage_color || '#fff' }"
                  />
                  {{ card.stage || '—' }}
                </p>
                <p class="text-[11px] text-white/70">
                  {{ fmtMoney(card.value) || 'sem valor'
                  }}<span v-if="card.assignee"> · {{ card.assignee }}</span>
                </p>
              </div>
              <div class="flex items-center gap-1.5 flex-wrap">
                <span
                  class="px-2 py-1 rounded-lg bg-white/15 text-[10px] font-semibold flex items-center gap-1"
                  :title="
                    formEvents.length
                      ? 'Formulários respondidos'
                      : 'Nenhum formulário respondido'
                  "
                >
                  <span class="i-lucide-clipboard-check text-[11px]" />
                  {{
                    formEvents.length
                      ? `${formEvents.length} formulário(s) ✓`
                      : 'sem formulário'
                  }}
                </span>
                <span
                  v-if="npsEvent"
                  class="px-2 py-1 rounded-lg bg-white/15 text-[10px] font-semibold flex items-center gap-1"
                >
                  <span class="i-lucide-star text-[11px]" /> NPS
                  {{ npsEvent.score }}
                </span>
                <span
                  v-if="(automations.followup_bots || []).length"
                  class="px-2 py-1 rounded-lg bg-white/15 text-[10px] font-semibold flex items-center gap-1"
                  :title="
                    automations.followup_bots.map(b => b.name).join(' · ')
                  "
                >
                  <span class="i-lucide-bot text-[11px]" />
                  {{ automations.followup_bots.length }} robô(s)
                </span>
                <span
                  v-if="automations.followup_paused"
                  class="px-2 py-1 rounded-lg bg-white/25 text-[10px] font-semibold flex items-center gap-1"
                >
                  <span class="i-lucide-pause text-[11px]" /> follow-up pausado
                </span>
              </div>
            </div>
          </div>
        </div>

        <!-- ══ Cards de informação ══ -->
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3 mb-6">
          <!-- Consultas -->
          <div class="rounded-xl px-4 py-3 bg-n-solid-1 border border-n-weak">
            <p
              class="text-[11px] font-semibold text-n-slate-10 flex items-center gap-1.5 mb-1.5"
            >
              <span
                class="i-lucide-stethoscope text-xs"
                :style="{ color: theme.accent }"
              />
              Consultas · {{ consultEvents.length }}
            </p>
            <div
              v-if="!consultEvents.length"
              class="text-[11px] text-n-slate-9 py-2"
            >
              Nenhuma consulta ainda.
            </div>
            <div v-else class="space-y-1 max-h-24 overflow-y-auto">
              <p
                v-for="(c, ci) in consultEvents.slice(0, 4)"
                :key="ci"
                class="text-[11px] text-n-slate-11 leading-snug"
              >
                <span class="font-semibold text-n-slate-12">{{
                  fmtShortDate(c.at)
                }}</span>
                · {{ MODALITY_LABELS[c.modality] || 'Consulta' }}
                <template v-if="c.procedure"> · {{ c.procedure }}</template>
                <span v-if="c.attendance === 'attended'" class="text-green-600">
                  ✓</span>
                <span
                  v-else-if="c.attendance === 'missed'"
                  class="text-red-500"
                >
                  ✗</span>
              </p>
            </div>
          </div>

          <!-- Procedimento & investimento -->
          <div class="rounded-xl px-4 py-3 bg-n-solid-1 border border-n-weak">
            <p
              class="text-[11px] font-semibold text-n-slate-10 flex items-center gap-1.5 mb-1.5"
            >
              <span
                class="i-lucide-badge-dollar-sign text-xs"
                :style="{ color: theme.accent }"
              />
              Procedimento & investimento
            </p>
            <template v-if="latestIndication">
              <p class="text-[12px] font-bold text-n-slate-12 leading-snug">
                {{ latestIndication.procedure || 'Cirurgia indicada' }}
              </p>
              <p class="text-[11px] text-n-slate-10 mt-0.5">
                <template v-if="latestIndication.value">
                  Orçamento:
                  <strong class="text-n-slate-12">{{
                    fmtMoney(latestIndication.value)
                  }}</strong>
                </template>
              </p>
              <p v-if="closingValue" class="text-[11px] text-n-slate-10">
                Fechou:
                <strong class="text-n-slate-12">{{
                  fmtMoney(closingValue)
                }}</strong>
                <template v-if="closingEvent?.payment">
                  · {{ closingEvent.payment }}
                </template>
              </p>
              <p v-if="performanceRate" class="text-[11px] mt-0.5">
                <span
                  class="px-1.5 py-0.5 rounded-md text-[10px] font-bold text-white"
                  :style="{ background: theme.accentGrad }"
                >
                  performance {{ performanceRate }}%
                </span>
              </p>
            </template>
            <p v-else class="text-[11px] text-n-slate-9 py-2">
              Sem indicação de cirurgia ainda.
            </p>
          </div>

          <!-- NPS & pesquisas -->
          <div class="rounded-xl px-4 py-3 bg-n-solid-1 border border-n-weak">
            <p
              class="text-[11px] font-semibold text-n-slate-10 flex items-center gap-1.5 mb-1.5"
            >
              <span
                class="i-lucide-star text-xs"
                :style="{ color: theme.accent }"
              />
              NPS & pesquisas
            </p>
            <template v-if="npsEvent">
              <p class="text-xl font-bold text-n-slate-12 leading-tight">
                {{ npsEvent.score }} <span class="text-sm">⭐</span>
              </p>
              <p
                v-if="npsEvent.comment"
                class="text-[11px] text-n-slate-10 italic leading-snug line-clamp-2"
              >
                “{{ npsEvent.comment }}”
              </p>
            </template>
            <p v-else class="text-[11px] text-n-slate-9 py-1">
              Sem nota NPS ainda.
            </p>
            <p
              v-if="formEvents.length"
              class="text-[11px] text-n-slate-11 mt-1"
            >
              📋
              {{
                formEvents
                  .map(f => f.form)
                  .filter(Boolean)
                  .join(' · ')
              }}
            </p>
          </div>

          <!-- Automações no contato -->
          <div class="rounded-xl px-4 py-3 bg-n-solid-1 border border-n-weak">
            <p
              class="text-[11px] font-semibold text-n-slate-10 flex items-center gap-1.5 mb-1.5"
            >
              <span
                class="i-lucide-bot text-xs"
                :style="{ color: theme.accent }"
              />
              Automações neste contato
            </p>
            <div class="space-y-1">
              <p
                v-for="bot in automations.followup_bots || []"
                :key="`bot-${bot.id}`"
                class="text-[11px] text-n-slate-11 flex items-center gap-1"
              >
                <span
                  class="w-1.5 h-1.5 rounded-full bg-green-500 inline-block shrink-0"
                />
                {{ bot.name }}
              </p>
              <p
                v-if="automations.followup_paused"
                class="text-[11px] text-amber-600 flex items-center gap-1"
              >
                <span class="i-lucide-pause text-[10px]" /> follow-up pausado p/
                este paciente
              </p>
              <p
                v-if="(automations.stage_automations || []).length"
                class="text-[11px] text-n-slate-10"
                :title="
                  automations.stage_automations.map(a => a.name).join(' · ')
                "
              >
                ⚙️ {{ automations.stage_automations.length }} automação(ões) na
                coluna atual
              </p>
              <p
                v-if="
                  !(automations.followup_bots || []).length &&
                  !(automations.stage_automations || []).length &&
                  !automations.followup_paused
                "
                class="text-[11px] text-n-slate-9 py-1"
              >
                Nada rodando agora.
              </p>

              <!-- trilha: por quais automações ele JÁ passou, e quando -->
              <details v-if="(automations.trail || []).length" class="pt-1">
                <summary class="text-[11px] font-semibold cursor-pointer" :style="{ color: theme.accent }">
                  🧭 Por onde ele já passou ({{ automations.trail.length }} disparo(s))
                </summary>
                <div class="mt-1.5 space-y-1 max-h-44 overflow-y-auto pr-1">
                  <p
                    v-for="(t, ti) in automations.trail"
                    :key="ti"
                    class="text-[11px] text-n-slate-11 flex items-center gap-1.5"
                  >
                    <span class="text-n-slate-9 shrink-0 tabular-nums">{{ fmtDateTime(t.at) }}</span>
                    <span class="truncate">⚙️ {{ t.name }}</span>
                    <span v-if="t.stage" class="text-n-slate-9 truncate">· {{ t.stage }}</span>
                  </p>
                </div>
              </details>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-5 gap-5">
          <!-- ══ Jornada no funil (pilha de estágios) ══ -->
          <div class="lg:col-span-2 space-y-5">
            <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
              <div class="flex items-center justify-between mb-1">
                <h2
                  class="text-sm font-bold text-n-slate-12 flex items-center gap-2"
                >
                  <span
                    class="i-lucide-layers text-base"
                    :style="{ color: theme.accent }"
                  />
                  Jornada no funil
                </h2>
                <button
                  class="text-[11px] text-n-slate-10 hover:text-n-slate-12"
                  @click="showDetailed = !showDetailed"
                >
                  {{ showDetailed ? 'ver jornada' : 'eventos detalhados' }}
                </button>
              </div>

              <template v-if="!showDetailed">
                <p class="text-[10px] text-n-slate-9 mb-4">
                  do primeiro contato até hoje · etiquetas ganhas em cada etapa
                </p>

                <div
                  v-if="!funnelJourney.rows.length"
                  class="text-xs text-n-slate-10 py-6 text-center"
                >
                  Este paciente ainda não entrou no funil.
                </div>

                <div v-else>
                  <div
                    v-for="(row, ri) in funnelJourney.rows"
                    :key="row.key"
                    class="flex items-stretch gap-2.5"
                  >
                    <!-- trilho da esquerda: data + salto de dias -->
                    <div class="w-14 shrink-0 flex flex-col items-end pt-0.5">
                      <span
                        class="text-[10px] font-semibold text-n-slate-11 leading-tight text-right"
                      >
                        {{ fmtShortDate(row.at) }}
                      </span>
                      <span
                        v-if="ri < funnelJourney.rows.length - 1"
                        class="text-[9px] text-n-slate-9 mt-auto mb-1"
                      >
                        +{{
                          funnelJourney.rows[ri + 1]
                            ? Math.max(
                                0,
                                Math.round(
                                  (new Date(funnelJourney.rows[ri + 1].at) -
                                    new Date(row.at)) /
                                    86400000
                                )
                              )
                            : 0
                        }}d
                      </span>
                    </div>

                    <!-- pilha central -->
                    <div class="flex-1 min-w-0 pb-2.5 relative">
                      <div
                        v-if="ri < funnelJourney.rows.length - 1"
                        class="absolute left-1/2 -translate-x-1/2 bottom-0 w-0.5 h-2.5 bg-n-weak"
                      />
                      <div
                        class="rounded-xl px-3.5 py-2.5 text-white shadow-sm"
                        :style="{
                          background: `linear-gradient(135deg, ${row.color}, ${row.color}CC)`,
                          outline: row.current
                            ? `2px solid ${theme.accent}`
                            : 'none',
                          outlineOffset: '2px',
                        }"
                      >
                        <div class="flex items-center justify-between gap-2">
                          <p class="text-[12px] font-bold truncate">
                            {{ row.stage }}
                          </p>
                          <span
                            class="text-[10px] font-semibold bg-black/20 rounded-md px-1.5 py-0.5 shrink-0"
                          >
                            {{
                              row.current ? `há ${row.days}d` : `${row.days}d`
                            }}
                          </span>
                        </div>
                        <div
                          v-if="row.labels.length"
                          class="flex items-center gap-1 flex-wrap mt-1.5"
                        >
                          <span
                            v-for="label in row.labels"
                            :key="label"
                            class="px-1.5 py-0.5 rounded-full bg-white/20 text-[9px] font-medium"
                          >
                            🏷️ {{ label }}
                          </span>
                        </div>
                      </div>
                    </div>
                  </div>

                  <!-- resumo da jornada -->
                  <div
                    class="mt-3 rounded-xl px-3.5 py-2.5 text-white"
                    :style="{ background: theme.accentGrad }"
                  >
                    <div
                      class="flex items-center justify-between text-[11px] font-semibold"
                    >
                      <span>Jornada completa</span>
                      <span>{{ funnelJourney.totalDays }} dias</span>
                    </div>
                    <p class="text-[10px] text-white/80 mt-0.5">
                      média de {{ funnelJourney.avgDays }} dia(s) por estágio ·
                      {{ funnelJourney.rows.length }} movimento(s)
                    </p>
                  </div>
                </div>
              </template>

              <!-- eventos detalhados (a linha do tempo completa) -->
              <template v-else>
                <p class="text-[10px] text-n-slate-9 mb-4">
                  tudo que aconteceu, mais recente primeiro
                </p>
                <div class="relative pl-6 max-h-[560px] overflow-y-auto">
                  <div
                    class="absolute left-[9px] top-1 bottom-1 w-px bg-n-weak"
                  />
                  <div
                    v-for="(event, idx) in detailedTimeline"
                    :key="eventKey(event, idx)"
                    class="relative pb-4 last:pb-0"
                  >
                    <span
                      class="absolute -left-6 top-0.5 w-5 h-5 rounded-full flex items-center justify-center text-white"
                      :style="{
                        background:
                          event.type === 'funil'
                            ? event.stage_color || '#64748B'
                            : eventStyle(event).color,
                      }"
                    >
                      <span
                        :class="eventStyle(event).icon"
                        class="text-[11px]"
                      />
                    </span>
                    <div class="ml-1">
                      <p class="text-[10px] text-n-slate-9">
                        {{ fmtDateTime(event.at) }}
                      </p>

                      <template v-if="event.type === 'origem'">
                        <p class="text-[13px] text-n-slate-12">
                          📣 Chegou pelo anúncio
                          <strong>{{
                            event.ad_name || event.headline || 'Meta Ads'
                          }}</strong>
                        </p>
                      </template>

                      <template v-else-if="event.type === 'conversa'">
                        <p class="text-[13px] text-n-slate-12">
                          Conversa iniciada
                          <template v-if="event.inbox">
                            em <strong>{{ event.inbox }}</strong>
                          </template>
                          <span v-if="event.channel" class="text-n-slate-10">
                            ({{
                              CHANNEL_LABELS[event.channel] || event.channel
                            }})</span>
                          <button
                            class="ml-1.5 text-[11px] text-n-blue-text hover:underline"
                            @click="openConversation(event.conversation_id)"
                          >
                            abrir #{{ event.conversation_id }}
                          </button>
                        </p>
                        <!-- o anúncio que trouxe ESTA conversa, bem visível -->
                        <p
                          v-if="event.ad_name"
                          class="mt-1 text-[11px] font-semibold inline-flex items-center gap-1 px-2 py-0.5 rounded-full"
                          style="background: rgba(212, 175, 55, 0.14); color: #8a6620; border: 1px solid rgba(212, 175, 55, 0.4)"
                        >
                          📣 Veio do anúncio: {{ event.ad_name }}
                        </p>
                      </template>

                      <template v-else-if="event.type === 'funil'">
                        <p class="text-[13px] text-n-slate-12">
                          Entrou na coluna
                          <strong
                            :style="{ color: event.stage_color || undefined }"
                            >{{ event.stage }}</strong>
                          <span
                            v-if="fmtDuration(event.duration_minutes)"
                            class="text-n-slate-10"
                          >
                            · ficou
                            {{ fmtDuration(event.duration_minutes) }}</span>
                        </p>
                      </template>

                      <template
                        v-else-if="
                          event.type === 'consulta' || event.type === 'cirurgia'
                        "
                      >
                        <p class="text-[13px] text-n-slate-12">
                          <strong>{{
                            event.type === 'cirurgia'
                              ? 'Cirurgia'
                              : MODALITY_LABELS[event.modality] || 'Consulta'
                          }}</strong>
                          <template v-if="event.doctor">
                            com {{ event.doctor }}
                          </template>
                          <template v-if="event.unit">
                            ·
                            {{ UNIT_LABELS[event.unit] || event.unit }}
                          </template>
                          <template v-if="event.procedure">
                            · {{ event.procedure }}
                          </template>
                        </p>
                        <div class="flex items-center gap-1.5 flex-wrap mt-1">
                          <span
                            v-if="event.canceled"
                            class="px-1.5 py-0.5 rounded-md bg-red-100 dark:bg-red-900/40 text-red-700 dark:text-red-300 text-[10px] font-medium"
                            >Cancelada</span>
                          <span
                            v-else-if="event.attendance === 'attended'"
                            class="px-1.5 py-0.5 rounded-md bg-green-100 dark:bg-green-900/40 text-green-700 dark:text-green-300 text-[10px] font-medium"
                            >✓ Compareceu</span>
                          <span
                            v-else-if="event.attendance === 'missed'"
                            class="px-1.5 py-0.5 rounded-md bg-red-100 dark:bg-red-900/40 text-red-700 dark:text-red-300 text-[10px] font-medium"
                            >✗ Faltou</span>
                          <span
                            v-if="event.rescheduled_count"
                            class="px-1.5 py-0.5 rounded-md bg-amber-100 dark:bg-amber-900/40 text-amber-700 dark:text-amber-300 text-[10px] font-medium"
                            >🔁 {{ event.rescheduled_count }}x</span>
                          <span
                            v-if="event.indicated"
                            class="px-1.5 py-0.5 rounded-md text-[10px] font-semibold text-white"
                            :style="{ background: theme.accentGrad }"
                          >
                            ⭐ Indicação{{
                              event.indicated_procedure
                                ? ` — ${event.indicated_procedure}`
                                : ''
                            }}
                          </span>
                        </div>
                      </template>

                      <template v-else-if="event.type === 'fechamento'">
                        <p class="text-[13px] text-n-slate-12">
                          💰 <strong>Fechamento</strong>
                          <template v-if="fmtMoney(event.value)">
                            — {{ fmtMoney(event.value) }}
                          </template>
                          <template v-if="event.payment">
                            · {{ event.payment }}
                          </template>
                        </p>
                      </template>

                      <template v-else-if="event.type === 'nps'">
                        <p class="text-[13px] text-n-slate-12">
                          ⭐ Avaliou com <strong>nota {{ event.score }}</strong>
                        </p>
                        <p
                          v-if="event.comment"
                          class="text-[11px] text-n-slate-10 mt-0.5 italic"
                        >
                          “{{ event.comment }}”
                        </p>
                      </template>

                      <template v-else-if="event.type === 'formulario'">
                        <p class="text-[13px] text-n-slate-12">
                          📋 Respondeu
                          <strong>{{ event.form || 'formulário' }}</strong>
                          <button
                            v-if="(event.answers || []).length"
                            class="ml-1.5 text-[11px] text-n-blue-text hover:underline"
                            @click="toggleForm(eventKey(event, idx))"
                          >
                            {{
                              expandedForms.has(eventKey(event, idx))
                                ? 'esconder'
                                : 'ver respostas'
                            }}
                          </button>
                        </p>
                        <div
                          v-if="expandedForms.has(eventKey(event, idx))"
                          class="mt-1.5 bg-n-alpha-1 rounded-lg p-2.5 space-y-1"
                        >
                          <p
                            v-for="(ans, ai) in event.answers"
                            :key="ai"
                            class="text-[11px] text-n-slate-11"
                          >
                            <span class="font-medium text-n-slate-12">{{ ans.question || ans.label }}:</span>
                            {{
                              Array.isArray(ans.answer)
                                ? ans.answer.join(', ')
                                : (ans.answer ?? ans.value)
                            }}
                          </p>
                        </div>
                      </template>

                      <template v-else-if="event.type === 'followup'">
                        <p class="text-[13px] text-n-slate-12">
                          🤖 Follow-up<template v-if="event.bot">
                            · <strong>{{ event.bot }}</strong>
                          </template>
                        </p>
                        <p
                          v-if="event.content"
                          class="text-[11px] text-n-slate-10 mt-0.5 truncate"
                        >
                          “{{ event.content }}”
                        </p>
                      </template>
                    </div>
                  </div>
                </div>
              </template>
            </div>
          </div>

          <!-- ══ Espaço do Médico (protagonista) + Atualizações ══ -->
          <div class="lg:col-span-3 space-y-5">
            <div
              v-if="notesAllowed"
              class="bg-n-solid-2 border border-n-weak rounded-2xl p-5"
            >
              <div class="flex items-center justify-between mb-1">
                <h2
                  class="text-sm font-bold text-n-slate-12 flex items-center gap-2"
                >
                  <span
                    class="i-lucide-notebook-pen text-base"
                    style="color: #b8860b"
                  />
                  {{ frase('espaco_profissional', 'Espaço do Médico') }}
                </h2>
                <div class="flex items-center gap-1.5">
                  <button
                    v-if="isAdmin"
                    class="w-7 h-7 rounded-lg hover:bg-n-alpha-1 flex items-center justify-center text-n-slate-10"
                    title="Quem pode ver e anotar"
                    @click="showAccessConfig = !showAccessConfig"
                  >
                    <span class="i-lucide-shield text-sm" />
                  </button>
                  <button
                    v-if="canEditNotes"
                    class="px-2.5 h-7 rounded-lg text-[11px] font-semibold text-white flex items-center gap-1 shadow-sm"
                    :style="{ background: theme.accentGrad }"
                    @click="openNewNote"
                  >
                    <span class="i-lucide-plus text-xs" /> Nova anotação
                  </button>
                </div>
              </div>
              <p class="text-[10px] text-n-slate-9 mb-3">
                Anotações internas da {{ termo('empresa') }} · dado sensível (LGPD) · acesso
                restrito
              </p>

              <!-- config de acesso (admin) -->
              <div
                v-if="showAccessConfig"
                class="mb-4 bg-n-alpha-1 rounded-xl p-3"
              >
                <p class="text-[11px] font-semibold text-n-slate-12 mb-2">
                  {{ termoCap('profissionais') }} (podem anotar):
                </p>
                <label
                  v-for="agent in agents"
                  :key="agent.id"
                  class="flex items-center gap-2 text-[12px] text-n-slate-11 py-0.5 cursor-pointer"
                >
                  <input
                    type="checkbox"
                    :checked="doctorUserIds.includes(agent.id)"
                    @change="toggleDoctorUser(agent.id)"
                  />
                  {{ agent.name }}
                </label>
                <label
                  class="flex items-center gap-2 text-[12px] text-n-slate-11 mt-2 pt-2 border-t border-n-weak cursor-pointer"
                >
                  <input v-model="teamView" type="checkbox" />
                  Equipe pode <strong>visualizar</strong> as anotações
                </label>
                <button
                  class="mt-2 px-3 h-7 rounded-lg text-white text-[11px] font-semibold disabled:opacity-60"
                  :style="{ background: theme.accentGrad }"
                  :disabled="accessSaving"
                  @click="saveAccessConfig"
                >
                  {{ accessSaving ? 'Salvando…' : 'Salvar acesso' }}
                </button>
              </div>

              <!-- "à uma vista": o resumo que o time bate o olho e entende -->
              <div
                v-if="latestNote"
                class="mb-4 rounded-xl p-3.5 text-white shadow-sm"
                :style="{ background: theme.accentGrad }"
              >
                <p
                  class="text-[10px] uppercase tracking-wide text-white/70 mb-1"
                >
                  À uma vista — última consulta anotada ({{
                    fmtDate(latestNote.performed_at)
                  }})
                </p>
                <div class="flex items-center gap-1.5 flex-wrap">
                  <span
                    v-for="pill in notePills(latestNote)"
                    :key="pill"
                    class="px-2 py-0.5 rounded-full bg-white/20 text-[11px] font-semibold"
                  >
                    {{ pill }}
                  </span>
                  <span
                    v-if="
                      String(latestNote.fields?.surgery_indicated) === 'true'
                    "
                    class="px-2 py-0.5 rounded-full bg-amber-400 text-amber-950 text-[11px] font-bold"
                  >
                    ⭐
                    {{
                      latestNote.fields?.indicated_procedure ||
                      'Cirurgia indicada'
                    }}
                    <template v-if="latestNote.fields?.indicated_value">
                      · {{ fmtMoney(latestNote.fields.indicated_value) }}
                    </template>
                  </span>
                </div>
                <p
                  v-if="(latestNote.fields?.conduct || []).length"
                  class="text-[11px] text-white/90 mt-1.5"
                >
                  Conduta:
                  {{ latestNote.fields.conduct.slice(0, 3).join(' · ') }}
                </p>
              </div>

              <div v-if="notesLoading" class="flex justify-center py-6">
                <Spinner :size="20" class="text-n-brand" />
              </div>
              <div
                v-else-if="!notes.length"
                class="text-xs text-n-slate-10 py-4 text-center"
              >
                Nenhuma anotação clínica ainda.
                <template v-if="canEditNotes">
                  <br />Clique em “Nova anotação” após a consulta.
                </template>
              </div>

              <div v-else class="space-y-3">
                <div
                  v-for="note in notes"
                  :key="note.id"
                  class="border border-n-weak rounded-xl p-3"
                >
                  <div class="flex items-start justify-between gap-2">
                    <div>
                      <p class="text-[12px] font-semibold text-n-slate-12">
                        {{ fmtDate(note.performed_at)
                        }}<template v-if="note.doctor">
                          · {{ note.doctor }}
                        </template>
                      </p>
                      <p class="text-[10px] text-n-slate-9">
                        anotado por {{ note.author?.name }}
                      </p>
                    </div>
                    <div
                      v-if="canTouchNote(note)"
                      class="flex items-center gap-1 shrink-0"
                    >
                      <button
                        class="w-6 h-6 rounded-md hover:bg-n-alpha-1 flex items-center justify-center text-n-slate-10"
                        @click="openEditNote(note)"
                      >
                        <span class="i-lucide-pencil text-xs" />
                      </button>
                      <button
                        class="w-6 h-6 rounded-md hover:bg-n-alpha-1 flex items-center justify-center text-red-500"
                        @click="deleteNote(note)"
                      >
                        <span class="i-lucide-trash-2 text-xs" />
                      </button>
                    </div>
                  </div>

                  <div
                    v-if="notePills(note).length"
                    class="flex items-center gap-1 flex-wrap mt-1.5"
                  >
                    <span
                      v-for="pill in notePills(note)"
                      :key="pill"
                      class="px-1.5 py-0.5 rounded-md bg-n-alpha-1 text-[10px] font-medium text-n-slate-11"
                    >
                      {{ pill }}
                    </span>
                    <span
                      v-if="String(note.fields?.surgery_indicated) === 'true'"
                      class="px-1.5 py-0.5 rounded-md text-[10px] font-semibold text-white"
                      :style="{ background: theme.accentGrad }"
                    >
                      ⭐ Indicou{{
                        note.fields?.indicated_procedure
                          ? ` — ${note.fields.indicated_procedure}`
                          : ''
                      }}
                      <template v-if="note.fields?.indicated_value">
                        · {{ fmtMoney(note.fields.indicated_value) }}</template>
                    </span>
                  </div>

                  <div
                    v-if="
                      note.fields?.refraction_od || note.fields?.refraction_oe
                    "
                    class="mt-1.5 text-[11px] text-n-slate-11"
                  >
                    <span class="font-medium text-n-slate-12">Refração:</span>
                    <template v-if="note.fields.refraction_od">
                      OD {{ note.fields.refraction_od }}
                    </template>
                    <template v-if="note.fields.refraction_oe">
                      · OE {{ note.fields.refraction_oe }}
                    </template>
                  </div>
                  <div
                    v-if="note.fields?.acuity_od || note.fields?.acuity_oe"
                    class="text-[11px] text-n-slate-11"
                  >
                    <span class="font-medium text-n-slate-12">Acuidade:</span>
                    <template v-if="note.fields.acuity_od">
                      OD {{ note.fields.acuity_od }}
                    </template>
                    <template v-if="note.fields.acuity_oe">
                      · OE {{ note.fields.acuity_oe }}
                    </template>
                  </div>
                  <p
                    v-if="note.fields?.biomicroscopy"
                    class="text-[11px] text-n-slate-11"
                  >
                    <span class="font-medium text-n-slate-12">Biomicroscopia:</span>
                    {{ note.fields.biomicroscopy }}
                  </p>
                  <p
                    v-if="note.fields?.fundoscopy"
                    class="text-[11px] text-n-slate-11"
                  >
                    <span class="font-medium text-n-slate-12">Fundoscopia:</span>
                    {{ note.fields.fundoscopy }}
                  </p>

                  <div
                    v-if="(note.fields?.conduct || []).length"
                    class="mt-1.5"
                  >
                    <p class="text-[11px] font-medium text-n-slate-12">
                      Conduta:
                    </p>
                    <ul class="mt-0.5 space-y-0.5">
                      <li
                        v-for="(item, ci) in note.fields.conduct"
                        :key="ci"
                        class="text-[11px] text-n-slate-11 flex items-start gap-1"
                      >
                        <span
                          class="i-lucide-check text-[10px] mt-0.5 text-green-600 shrink-0"
                        />
                        {{ item }}
                      </li>
                    </ul>
                  </div>
                  <div
                    v-if="(note.fields?.exams_requested || []).length"
                    class="mt-1"
                  >
                    <p class="text-[11px] font-medium text-n-slate-12">
                      Exames pedidos:
                    </p>
                    <div class="flex items-center gap-1 flex-wrap mt-0.5">
                      <span
                        v-for="(exam, ei) in note.fields.exams_requested"
                        :key="ei"
                        class="px-1.5 py-0.5 rounded-md bg-sky-100 dark:bg-sky-900/40 text-sky-700 dark:text-sky-300 text-[10px]"
                      >
                        {{ exam }}
                      </span>
                    </div>
                  </div>

                  <p
                    v-if="note.observations"
                    class="mt-1.5 text-[11px] text-n-slate-11 whitespace-pre-line"
                  >
                    {{ note.observations }}
                  </p>

                  <div
                    v-if="(note.photos || []).length"
                    class="flex items-center gap-2 flex-wrap mt-2"
                  >
                    <a
                      v-for="photo in note.photos"
                      :key="photo.id"
                      :href="photo.url"
                      target="_blank"
                      rel="noopener"
                      class="block"
                    >
                      <img
                        :src="photo.url"
                        :alt="photo.filename"
                        class="w-14 h-14 rounded-lg object-cover border border-n-weak hover:opacity-80"
                      />
                    </a>
                  </div>
                </div>
              </div>
            </div>

            <!-- ══ Atualizações do paciente ══ -->
            <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
              <h2
                class="text-sm font-bold text-n-slate-12 flex items-center gap-2 mb-3"
              >
                <span
                  class="i-lucide-bell-ring text-base"
                  :style="{ color: theme.accent }"
                />
                Atualizações do paciente
              </h2>

              <div v-if="(updates.upcoming || []).length" class="mb-3">
                <p class="text-[11px] font-semibold text-n-slate-10 mb-1.5">
                  Próximos compromissos
                </p>
                <div
                  v-for="t in updates.upcoming"
                  :key="`up-${t.id}`"
                  class="flex items-center gap-2 text-[12px] text-n-slate-11 py-1 border-b border-n-weak/60 last:border-0"
                >
                  <span
                    class="w-6 h-6 rounded-lg flex items-center justify-center text-white shrink-0"
                    :style="{ background: theme.accentGrad }"
                  >
                    <span
                      :class="
                        t.task_type === 'cirurgia'
                          ? 'i-lucide-heart-pulse'
                          : 'i-lucide-calendar-days'
                      "
                      class="text-[11px]"
                    />
                  </span>
                  <span class="font-semibold text-n-slate-12">{{
                    fmtDateTime(t.due_at)
                  }}</span>
                  <span class="truncate">
                    {{
                      t.task_type === 'cirurgia'
                        ? 'Cirurgia'
                        : MODALITY_LABELS[t.modality] || 'Consulta'
                    }}
                    <template v-if="t.doctor"> · {{ t.doctor }}</template>
                    <template v-if="t.unit">
                      · {{ UNIT_LABELS[t.unit] || t.unit }}</template>
                  </span>
                </div>
              </div>

              <div v-if="(updates.open_tasks || []).length" class="mb-3">
                <p class="text-[11px] font-semibold text-n-slate-10 mb-1.5">
                  Pendências abertas
                </p>
                <p
                  v-for="t in updates.open_tasks"
                  :key="`open-${t.id}`"
                  class="text-[12px] text-n-slate-11 py-0.5 flex items-center gap-1.5"
                >
                  <span
                    class="i-lucide-circle-dashed text-[11px] text-amber-500 shrink-0"
                  />
                  <span class="truncate">{{ t.title }}</span>
                </p>
              </div>

              <div v-if="(updates.notes || []).length">
                <p class="text-[11px] font-semibold text-n-slate-10 mb-1.5">
                  Notas da equipe
                </p>
                <div
                  v-for="n in updates.notes"
                  :key="`note-${n.id}`"
                  class="text-[12px] text-n-slate-11 py-1 border-b border-n-weak/60 last:border-0"
                >
                  <p class="whitespace-pre-line line-clamp-3">
                    {{ n.content }}
                  </p>
                  <p class="text-[10px] text-n-slate-9 mt-0.5">
                    {{ n.author || 'equipe' }} · {{ fmtDate(n.at) }}
                  </p>
                </div>
              </div>

              <p
                v-if="
                  !(updates.upcoming || []).length &&
                  !(updates.open_tasks || []).length &&
                  !(updates.notes || []).length
                "
                class="text-[11px] text-n-slate-9 py-2 text-center"
              >
                Nenhuma atualização pendente — jornada em dia. ✨
              </p>
            </div>
          </div>
        </div>
      </template>
    </div>

    <!-- ══ Modal: nova anotação / editar ══ -->
    <div
      v-if="showNoteForm"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      @click.self="showNoteForm = false"
    >
      <div
        class="bg-n-solid-1 rounded-2xl shadow-xl w-full max-w-2xl max-h-[90vh] overflow-y-auto p-5"
      >
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-sm font-bold text-n-slate-12 flex items-center gap-2">
            <PatientSpaceIcon :size="22" />
            {{ editingNote ? 'Editar anotação' : 'Nova anotação de consulta' }}
          </h3>
          <button
            class="w-7 h-7 rounded-lg hover:bg-n-alpha-1 flex items-center justify-center text-n-slate-10"
            @click="showNoteForm = false"
          >
            <span class="i-lucide-x text-sm" />
          </button>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-3">
          <label class="block">
            <span class="text-[11px] font-medium text-n-slate-11">Data da consulta</span>
            <input
              v-model="noteForm.performed_at"
              type="date"
              class="mt-1 w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] text-n-slate-12"
            />
          </label>
          <label class="block">
            <span class="text-[11px] font-medium text-n-slate-11">Médico</span>
            <select
              v-model="noteForm.doctor"
              class="mt-1 w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] text-n-slate-12"
            >
              <option value="">—</option>
              <option v-for="doc in DOCTORS" :key="doc" :value="doc">
                {{ doc }}
              </option>
            </select>
          </label>
          <label class="block">
            <span class="text-[11px] font-medium text-n-slate-11">Ligar à consulta da Agenda</span>
            <select
              v-model="noteForm.task_id"
              class="mt-1 w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] text-n-slate-12"
            >
              <option :value="null">nenhuma</option>
              <option
                v-for="opt in consultOptions"
                :key="opt.id"
                :value="opt.id"
              >
                {{ opt.label }}
              </option>
            </select>
          </label>
        </div>

        <!-- campos rápidos: procedimento com preço oficial → orçamento -->
        <div class="bg-n-alpha-1 rounded-xl p-3 mb-3">
          <div class="flex items-center gap-2 flex-wrap mb-2">
            <span class="text-[11px] font-medium text-n-slate-11">Procedimento:</span>
            <button
              v-for="proc in PROCEDURES"
              :key="proc.key"
              class="px-2.5 h-7 rounded-lg text-[11px] font-medium border transition-all"
              :class="
                noteForm.procedure_type === proc.key
                  ? 'text-white border-transparent shadow-sm'
                  : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'
              "
              :style="
                noteForm.procedure_type === proc.key
                  ? { background: theme.accentGrad }
                  : {}
              "
              @click="pickProcedure(proc.key)"
            >
              {{ proc.label }}
              <span v-if="proc.price"
class="opacity-70"
                >· {{ fmtMoney(proc.price) }}</span>
            </button>
          </div>
          <div
            v-if="selectedProcedure && selectedProcedure.options.length"
            class="flex items-center gap-2 flex-wrap"
          >
            <span class="text-[11px] font-medium text-n-slate-11">{{ selectedProcedure.optionLabel }}:</span>
            <button
              v-for="option in selectedProcedure.options"
              :key="option.name"
              class="px-2.5 h-7 rounded-lg text-[11px] font-medium border transition-all"
              :class="
                noteForm.procedure_option === option.name
                  ? 'text-white border-transparent shadow-sm'
                  : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'
              "
              :style="
                noteForm.procedure_option === option.name
                  ? { background: theme.accentGrad }
                  : {}
              "
              @click="pickOption(option)"
            >
              {{ option.name }}
              <span v-if="option.price"
class="opacity-70"
                >· {{ fmtMoney(option.price) }}</span>
            </button>
          </div>
          <div class="flex items-center gap-2 flex-wrap mt-2">
            <span class="text-[11px] font-medium text-n-slate-11">Olho:</span>
            <button
              v-for="eye in EYES"
              :key="eye"
              class="px-2.5 h-7 rounded-lg text-[11px] font-bold border transition-all"
              :class="
                noteForm.eye === eye
                  ? 'text-white border-transparent shadow-sm'
                  : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'
              "
              :style="
                noteForm.eye === eye ? { background: theme.accentGrad } : {}
              "
              @click="noteForm.eye = noteForm.eye === eye ? '' : eye"
            >
              {{ eye }}
            </button>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-3 mb-3">
          <label class="block">
            <span class="text-[11px] font-medium text-n-slate-11">Refração OD</span>
            <input
              v-model="noteForm.refraction_od"
              type="text"
              placeholder="-2,25 -0,50 x 180"
              class="mt-1 w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] text-n-slate-12"
            />
          </label>
          <label class="block">
            <span class="text-[11px] font-medium text-n-slate-11">Refração OE</span>
            <input
              v-model="noteForm.refraction_oe"
              type="text"
              placeholder="-1,75 -0,25 x 10"
              class="mt-1 w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] text-n-slate-12"
            />
          </label>
          <label class="block">
            <span class="text-[11px] font-medium text-n-slate-11">Acuidade OD</span>
            <input
              v-model="noteForm.acuity_od"
              type="text"
              placeholder="20/20"
              class="mt-1 w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] text-n-slate-12"
            />
          </label>
          <label class="block">
            <span class="text-[11px] font-medium text-n-slate-11">Acuidade OE</span>
            <input
              v-model="noteForm.acuity_oe"
              type="text"
              placeholder="20/25"
              class="mt-1 w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] text-n-slate-12"
            />
          </label>
          <label class="block">
            <span class="text-[11px] font-medium text-n-slate-11">PIO OD (mmHg)</span>
            <input
              v-model="noteForm.pio_od"
              type="text"
              placeholder="14"
              class="mt-1 w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] text-n-slate-12"
            />
          </label>
          <label class="block">
            <span class="text-[11px] font-medium text-n-slate-11">PIO OE (mmHg)</span>
            <input
              v-model="noteForm.pio_oe"
              type="text"
              placeholder="15"
              class="mt-1 w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] text-n-slate-12"
            />
          </label>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-3">
          <label class="block">
            <span class="text-[11px] font-medium text-n-slate-11">Biomicroscopia</span>
            <textarea
              v-model="noteForm.biomicroscopy"
              rows="2"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 px-2 py-1.5 text-[13px] text-n-slate-12"
            />
          </label>
          <label class="block">
            <span class="text-[11px] font-medium text-n-slate-11">Fundoscopia</span>
            <textarea
              v-model="noteForm.fundoscopy"
              rows="2"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 px-2 py-1.5 text-[13px] text-n-slate-12"
            />
          </label>
          <label class="block">
            <span class="text-[11px] font-medium text-n-slate-11">Conduta (uma por linha — vira pílulas)</span>
            <textarea
              v-model="noteForm.conductText"
              rows="3"
              placeholder="Indicada cirurgia refrativa&#10;Colírio lubrificante 4x/dia"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 px-2 py-1.5 text-[13px] text-n-slate-12"
            />
          </label>
          <label class="block">
            <span class="text-[11px] font-medium text-n-slate-11">Exames pedidos (um por linha)</span>
            <textarea
              v-model="noteForm.examsText"
              rows="3"
              placeholder="Topografia&#10;Paquimetria"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 px-2 py-1.5 text-[13px] text-n-slate-12"
            />
          </label>
        </div>

        <!-- indicação + orçamento oficial -->
        <div class="bg-n-alpha-1 rounded-xl p-3 mb-3">
          <label
            class="flex items-center gap-2 text-[12px] text-n-slate-12 font-medium cursor-pointer"
          >
            <input v-model="noteForm.surgery_indicated" type="checkbox" />
            ⭐ Saiu com indicação de cirurgia
          </label>
          <template v-if="noteForm.surgery_indicated">
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2 mt-2">
              <input
                v-model="noteForm.indicated_procedure"
                type="text"
                placeholder="Procedimento indicado"
                class="w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] text-n-slate-12"
              />
              <div class="flex items-center gap-2">
                <span class="text-[11px] font-medium text-n-slate-11 shrink-0">Orçamento R$</span>
                <input
                  v-model="noteForm.indicated_value"
                  type="number"
                  min="0"
                  placeholder="8490"
                  class="w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] font-semibold text-n-slate-12"
                />
              </div>
            </div>
            <p class="text-[10px] text-n-slate-9 mt-1.5">
              Este é o <strong>orçamento oficial da indicação</strong> — entra
              no valor do card do CRM (se vazio) e depois é comparado com o
              fechamento para medir a taxa de performance.
              <template v-if="noteForm.task_id">
                A consulta ligada também é marcada e o card se move no funil.
              </template>
            </p>

            <!-- consulta automática de ESTOQUE (item 68) -->
            <div v-if="stockLookup.state === 'loading'" class="mt-2 flex items-center gap-2 text-[11px] text-n-slate-10">
              <Spinner size="tiny" />
              Consultando o estoque…
            </div>
            <div
              v-else-if="stockLookup.state === 'done' && stockAvailable.length"
              class="mt-2 rounded-lg p-2.5"
              style="background: rgba(5, 150, 105, 0.1); border: 1px solid rgba(5, 150, 105, 0.3)"
            >
              <p class="text-[11px] font-bold" style="color: #059669">
                ✅ Em estoque:
                {{ stockAvailable.map(m => `${m.name}${m.specification ? ` (${m.specification})` : ''} — ${m.quantity} un.`).join(' · ') }}
              </p>
              <div class="flex items-center gap-2 mt-1.5 flex-wrap">
                <p class="text-[10px] text-n-slate-10">Dá para agendar a cirurgia para uma data próxima.</p>
                <button
                  type="button"
                  class="h-7 px-2.5 rounded-lg text-[10px] font-bold text-white"
                  style="background: #059669"
                  @click="goToAgendaForSurgery"
                >
                  📅 Agendar cirurgia
                </button>
              </div>
            </div>
            <div
              v-else-if="stockLookup.state === 'done'"
              class="mt-2 rounded-lg p-2.5"
              style="background: rgba(217, 119, 6, 0.1); border: 1px solid rgba(217, 119, 6, 0.3)"
            >
              <p class="text-[11px] font-bold" style="color: #D97706">
                📦 Sem estoque para esta indicação.
              </p>
              <div class="flex items-center gap-2 mt-1.5 flex-wrap">
                <template v-if="stockOrderCreated">
                  <p class="text-[10px] font-semibold" style="color: #059669">
                    ✓ Pedido criado e vinculado ao card deste paciente — acompanhe em Financeiro → Estoque.
                  </p>
                </template>
                <template v-else>
                  <p class="text-[10px] text-n-slate-10">Encomende agora: o pedido fica vinculado ao card do paciente com o motivo.</p>
                  <button
                    type="button"
                    class="h-7 px-2.5 rounded-lg text-[10px] font-bold text-white disabled:opacity-60"
                    style="background: #D97706"
                    :disabled="orderingStock"
                    @click="orderStockForPatient"
                  >
                    {{ orderingStock ? 'Criando pedido…' : '🛒 Encomendar para este paciente' }}
                  </button>
                </template>
              </div>
            </div>
          </template>
        </div>

        <label class="block mb-3">
          <span class="text-[11px] font-medium text-n-slate-11">Observações livres</span>
          <textarea
            v-model="noteForm.observations"
            rows="3"
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 px-2 py-1.5 text-[13px] text-n-slate-12"
          />
        </label>

        <!-- fotos de exames -->
        <div class="mb-4">
          <span class="text-[11px] font-medium text-n-slate-11">Fotos de exames</span>
          <div class="flex items-center gap-2 flex-wrap mt-1.5">
            <template v-if="editingNote">
              <div
                v-for="photo in editingNote.photos"
                :key="photo.id"
                class="relative"
              >
                <img
                  :src="photo.url"
                  class="w-14 h-14 rounded-lg object-cover border border-n-weak"
                  :class="removePhotoIds.includes(photo.id) ? 'opacity-30' : ''"
                />
                <button
                  class="absolute -top-1.5 -right-1.5 w-5 h-5 rounded-full bg-red-500 text-white flex items-center justify-center"
                  :title="
                    removePhotoIds.includes(photo.id)
                      ? 'Manter foto'
                      : 'Remover foto'
                  "
                  @click="
                    removePhotoIds.includes(photo.id)
                      ? (removePhotoIds = removePhotoIds.filter(
                          id => id !== photo.id
                        ))
                      : removePhotoIds.push(photo.id)
                  "
                >
                  <span
                    :class="
                      removePhotoIds.includes(photo.id)
                        ? 'i-lucide-undo-2'
                        : 'i-lucide-x'
                    "
                    class="text-[10px]"
                  />
                </button>
              </div>
            </template>
            <span
              v-for="(file, fi) in notePhotos"
              :key="fi"
              class="px-2 py-1 rounded-lg bg-n-alpha-1 text-[10px] text-n-slate-11 flex items-center gap-1"
            >
              📎 {{ file.name }}
              <button
                class="text-red-500"
                @click="notePhotos = notePhotos.filter((_, i) => i !== fi)"
              >
                <span class="i-lucide-x text-[10px]" />
              </button>
            </span>
            <label
              class="w-14 h-14 rounded-lg border-2 border-dashed border-n-weak flex items-center justify-center cursor-pointer hover:bg-n-alpha-1 text-n-slate-10"
            >
              <span class="i-lucide-image-plus text-lg" />
              <input
                type="file"
                accept="image/*"
                multiple
                class="hidden"
                @change="onPhotosSelected"
              />
            </label>
          </div>
        </div>

        <div class="flex items-center justify-end gap-2">
          <button
            class="px-3 h-9 rounded-lg text-[12px] font-medium text-n-slate-11 hover:bg-n-alpha-1"
            @click="showNoteForm = false"
          >
            Cancelar
          </button>
          <button
            class="px-4 h-9 rounded-lg text-[12px] font-semibold text-white disabled:opacity-60 shadow-sm"
            :style="{ background: theme.accentGrad }"
            :disabled="noteSaving"
            @click="saveNote"
          >
            {{
              noteSaving
                ? 'Salvando…'
                : editingNote
                  ? 'Salvar alterações'
                  : 'Salvar anotação'
            }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.cevico-ink-dark { color: #0b2239 !important; }
.cevico-ink-dark [class*='text-white'] { color: rgba(11,34,57,.85) !important; }
.cevico-ink-dark [class*='bg-white/'] { background: rgba(11,34,57,.10) !important; }
</style>
