<script setup>
// 🗺️ JORNADA DO PACIENTE (item 168 + 173): a linha do tempo (Lead →
// Consulta → Orçamento → Cirurgia → Pós-operatório → Retorno) numa tela só,
// SEM rolagem lateral: cada etapa mostra as mensagens da jornada E tudo o
// que já age nela (lembretes D-1/D-0, follow-up, réguas, automações da
// coluna, campanhas, agentes) vindo do mapa do servidor. "Personalizar"
// deixa mostrar/esconder categorias, renomear e ordenar etapas, mover itens
// de etapa, mapear colunas do CRM → etapa e escolher densidade e posição da
// fila — tudo salvo em agenda_config.journey.map. Kit CEVICO (cv-*).
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import CevicoJourneyAPI from 'dashboard/api/cevicoJourney';
import JourneyWizard from './components/JourneyWizard.vue';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { hexFromGrad } from 'dashboard/helper/cevicoPalettes';

const store = useStore();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabels');
const pipelines = useMapGetter('crm/getPipelines');

const GRADIENT = 'linear-gradient(135deg, #0F766E, #14B8A6)';
const STEP_BLOCKS = [
  { id: 'lead', label: 'Lead', icon: 'i-lucide-sparkles' },
  { id: 'consulta', label: 'Consulta', icon: 'i-lucide-calendar-check' },
  { id: 'orcamento', label: 'Orçamento', icon: 'i-lucide-receipt' },
  { id: 'cirurgia', label: 'Cirurgia', icon: 'i-lucide-stethoscope' },
  { id: 'pos_op', label: 'Pós-operatório', icon: 'i-lucide-heart-pulse' },
  { id: 'retorno', label: 'Retorno', icon: 'i-lucide-rotate-ccw' },
  { id: 'fila', label: 'Fila de hoje', icon: 'i-lucide-inbox' },
  { id: 'geral', label: 'Vigias gerais', icon: 'i-lucide-radar' },
];
const pal = useCevicoPalette({ scope: 'crm:jornada', blocks: STEP_BLOCKS });
const { cvVars, blockVars, blockFamily } = pal;
const stepColor = key => hexFromGrad(blockFamily(key)[1] || '') || '#0F766E';
const STEP_META = {
  lead: { icon: 'i-lucide-sparkles', color: '#2563EB' },
  consulta: { icon: 'i-lucide-calendar-check', color: '#7C3AED' },
  orcamento: { icon: 'i-lucide-receipt', color: '#D97706' },
  cirurgia: { icon: 'i-lucide-stethoscope', color: '#0F766E' },
  pos_op: { icon: 'i-lucide-heart-pulse', color: '#DB2777' },
  retorno: { icon: 'i-lucide-rotate-ccw', color: '#475569' },
};
const KIND_ICON = {
  surgery: 'i-lucide-stethoscope',
  appointment: 'i-lucide-calendar-check',
  stage: 'i-lucide-kanban',
  label: 'i-lucide-tag',
  call_missed: 'i-lucide-phone-missed',
};
const SEND_STATUS = {
  queued: { label: 'Na fila', cls: 'bg-n-alpha-2 text-n-slate-11' },
  pending_review: {
    label: 'Aguardando aprovação',
    cls: 'bg-amber-500/15 text-amber-700',
  },
  sent: { label: 'Enviada', cls: 'bg-green-500/15 text-green-700' },
  skipped: { label: 'Pulada', cls: 'bg-n-alpha-2 text-n-slate-10' },
  failed: { label: 'Falhou', cls: 'bg-red-500/15 text-red-600' },
  expired: { label: 'Expirou', cls: 'bg-n-alpha-2 text-n-slate-10' },
};
const REPLY_META = {
  confirmed: { label: 'Confirmou', cls: 'bg-green-500/15 text-green-700' },
  declined: { label: 'Não vai / remarcar', cls: 'bg-red-500/15 text-red-600' },
};

// ── dados ──
const isLoading = ref(true);
const messages = ref([]);
const steps = ref({});
const kinds = ref({});
const tokens = ref([]);
const settings = ref({
  places: {},
  hours: { start: '08:00', end: '20:00' },
  daily_cap: 300,
  quiet_labels: [],
});
const todayCounts = ref({});
const search = ref('');

const load = async (silent = false) => {
  if (!silent) isLoading.value = true;
  try {
    const { data } = await CevicoJourneyAPI.list();
    messages.value = data.journey_messages || [];
    steps.value = data.steps || {};
    kinds.value = data.kinds || {};
    tokens.value = data.tokens || [];
    settings.value = { ...settings.value, ...(data.settings || {}) };
    todayCounts.value = data.today || {};
  } catch {
    useAlert('Não consegui carregar a jornada.');
  } finally {
    isLoading.value = false;
  }
};

const whatsappInboxes = computed(() =>
  (inboxes.value || []).filter(i => i.channel_type === 'Channel::Whatsapp')
);
const labelOptions = computed(() =>
  (labels.value || []).map(l => ({ id: l.id, label: l.title, color: l.color }))
);
const labelTitleOptions = computed(() =>
  (labels.value || []).map(l => ({
    id: l.title,
    label: l.title,
    color: l.color,
  }))
);
const stageOptions = computed(() =>
  (pipelines.value || []).flatMap(p =>
    (p.stages ?? []).map(s => ({
      id: s.id,
      label: `${p.name} › ${s.name}`,
      color: s.color,
    }))
  )
);

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return messages.value;
  return messages.value.filter(m =>
    [m.name, m.kind_label, m.when_label, m.step_label]
      .join(' ')
      .toLowerCase()
      .includes(q)
  );
});
const activeCount = computed(() => messages.value.filter(m => m.active).length);

// ── Fila de hoje ──
const queue = ref([]);
const queueDate = ref('');
const isQueueLoading = ref(false);
const busySend = ref(null);
const loadQueue = async () => {
  isQueueLoading.value = true;
  try {
    const { data } = await CevicoJourneyAPI.queue();
    queue.value = data.sends || [];
    queueDate.value = data.date || '';
    todayCounts.value = data.counts || {};
  } catch {
    queue.value = [];
  } finally {
    isQueueLoading.value = false;
  }
};
const pendingReview = computed(() =>
  queue.value.filter(s => s.status === 'pending_review')
);
const queueByStatus = key => queue.value.filter(s => s.status === key).length;
const act = async (send, action) => {
  busySend.value = send.id;
  try {
    const fn = { approve: 'approve', skip: 'skip', retry: 'retry' }[action];
    const { data } = await CevicoJourneyAPI[fn](send.id);
    const idx = queue.value.findIndex(s => s.id === send.id);
    if (idx >= 0 && data.send) queue.value.splice(idx, 1, data.send);
    if (action === 'approve') {
      useAlert(
        data.outcome === 'sent'
          ? 'Enviada!'
          : `Não saiu: ${data.send?.error || data.outcome}`
      );
    }
    load(true);
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui fazer isso agora.');
  } finally {
    busySend.value = null;
  }
};
const approveAll = async () => {
  if (!pendingReview.value.length) return;
  busySend.value = 'all';
  try {
    const { data } = await CevicoJourneyAPI.approveAll();
    const r = data.results || {};
    useAlert(
      `Aprovadas: ${r.sent || 0} enviadas · ${r.failed || 0} falharam · ${r.skipped || 0} puladas`
    );
    await loadQueue();
    load(true);
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui aprovar todos.');
  } finally {
    busySend.value = null;
  }
};
const openConversation = send => {
  if (!send.conversation_id) return;
  router.push(
    `/app/accounts/${accountId.value}/conversations/${send.conversation_id}`
  );
};
const hhmm = iso => {
  if (!iso) return '';
  return new Date(iso).toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  });
};
const dmy = iso => {
  if (!iso) return '';
  // data pura (AAAA-MM-DD) não pode virar UTC — senão mostra o dia anterior
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (m) return `${m[3]}/${m[2]}`;
  return new Date(iso).toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
  });
};
const dmyhm = iso => (iso ? `${dmy(iso)} ${hhmm(iso)}` : '');

// ── ações da mensagem ──
const showWizard = ref(false);
const editing = ref(null);
const presetStep = ref(''); // etapa pré-escolhida no mapa (item 173)
const openNew = () => {
  editing.value = null;
  presetStep.value = '';
  showWizard.value = true;
};
const openEdit = m => {
  editing.value = m;
  showWizard.value = true;
};
const onSaved = async () => {
  showWizard.value = false;
  editing.value = null;
  await load(true);
};
const busyMessage = ref(null);
const toggleActive = async m => {
  busyMessage.value = m.id;
  try {
    const { data } = await CevicoJourneyAPI.update(m.id, { active: !m.active });
    Object.assign(m, data);
  } catch {
    useAlert('Não consegui ligar/desligar.');
  } finally {
    busyMessage.value = null;
  }
};
const deleteConfirmId = ref(null);
const destroy = async m => {
  busyMessage.value = m.id;
  try {
    await CevicoJourneyAPI.destroy(m.id);
    messages.value = messages.value.filter(x => x.id !== m.id);
    deleteConfirmId.value = null;
    useAlert('Mensagem excluída.');
  } catch {
    useAlert('Não consegui excluir.');
  } finally {
    busyMessage.value = null;
  }
};
const planNow = async m => {
  busyMessage.value = m.id;
  try {
    const { data } = await CevicoJourneyAPI.planNow(m.id);
    useAlert(
      data.created
        ? `${data.created} envio(s) entraram na fila de hoje.`
        : 'Nenhum evento novo para hoje (ou já estava tudo na fila).'
    );
    await loadQueue();
    load(true);
  } catch {
    useAlert('Não consegui planejar agora.');
  } finally {
    busyMessage.value = null;
  }
};

// teste para o meu número
const testTarget = ref(null);
const testPhone = ref(localStorage.getItem('cevico_journey_test_phone') || '');
const isTesting = ref(false);
const testResult = ref(null);
const openTest = m => {
  testTarget.value = m;
  testResult.value = null;
};
const runTest = async () => {
  if (!testTarget.value) return;
  isTesting.value = true;
  testResult.value = null;
  try {
    localStorage.setItem('cevico_journey_test_phone', testPhone.value);
    const { data } = await CevicoJourneyAPI.testSend(
      testTarget.value.id,
      testPhone.value
    );
    testResult.value = data;
  } catch (error) {
    testResult.value = {
      ok: false,
      send: { error: error?.response?.data?.error || 'Falhou.' },
    };
  } finally {
    isTesting.value = false;
  }
};

// histórico por mensagem
const historyTarget = ref(null);
const history = ref([]);
const historyMeta = ref({ total: 0, page: 1 });
const isHistoryLoading = ref(false);
const openHistory = async (m, page = 1) => {
  historyTarget.value = m;
  isHistoryLoading.value = true;
  try {
    const { data } = await CevicoJourneyAPI.sends({ message_id: m.id, page });
    history.value = data.sends || [];
    historyMeta.value = data.meta || { total: 0, page };
  } catch {
    history.value = [];
  } finally {
    isHistoryLoading.value = false;
  }
};

// locais e horário
const showSettings = ref(false);
const settingsForm = ref({
  places: {},
  hours: {},
  daily_cap: 300,
  quiet_labels: '',
});
const openSettings = () => {
  const p = settings.value.places || {};
  settingsForm.value = {
    places: {
      default: { unidade: '', endereco: '', ...(p.default || {}) },
      tatuape: { unidade: 'Tatuapé', endereco: '', ...(p.tatuape || {}) },
      paulista: {
        unidade: 'Av. Paulista',
        endereco: '',
        ...(p.paulista || {}),
      },
      clinics: Object.entries(p.clinics || {}).map(([name, v]) => ({
        name,
        ...v,
      })),
    },
    hours: { ...(settings.value.hours || {}) },
    daily_cap: settings.value.daily_cap || 300,
    quiet_labels: (settings.value.quiet_labels || []).join(', '),
  };
  showSettings.value = true;
};
const addClinic = () =>
  settingsForm.value.places.clinics.push({
    name: '',
    unidade: '',
    endereco: '',
  });
const isSavingSettings = ref(false);
const saveSettings = async () => {
  isSavingSettings.value = true;
  try {
    const f = settingsForm.value;
    const clinics = {};
    f.places.clinics
      .filter(c => c.name.trim())
      .forEach(c => {
        clinics[c.name.trim()] = { unidade: c.unidade, endereco: c.endereco };
      });
    const { data } = await CevicoJourneyAPI.updateSettings({
      places: {
        default: f.places.default,
        tatuape: f.places.tatuape,
        paulista: f.places.paulista,
        clinics,
      },
      hours: f.hours,
      daily_cap: f.daily_cap,
      quiet_labels: f.quiet_labels
        .split(',')
        .map(s => s.trim())
        .filter(Boolean),
    });
    settings.value = { ...settings.value, ...(data.settings || {}) };
    showSettings.value = false;
    useAlert('Locais e horário salvos.');
  } catch {
    useAlert('Não consegui salvar.');
  } finally {
    isSavingSettings.value = false;
  }
};

// ── mapa: tudo o que age em cada etapa (item 173) ──
const KIND_ORDER = [
  'reminder',
  'followup',
  'message_automation',
  'column_automation',
  'campaign',
  'agent',
];
const DEFAULT_MAP = () => ({
  stage_steps: {},
  overrides: {},
  hidden: [],
  show: {},
  step_order: [],
  step_labels: {},
  density: 'comfortable',
  queue: 'side',
});
const map = ref({
  steps: [],
  kinds: {},
  stages: [],
  stage_steps: {},
  items: [],
  hidden_items: [],
  map: {},
});
const mapConfig = ref(DEFAULT_MAP());
const loadMap = async () => {
  try {
    const { data } = await CevicoJourneyAPI.map();
    map.value = data;
    mapConfig.value = { ...DEFAULT_MAP(), ...(data.map || {}) };
  } catch {
    // o mapa é complemento: a jornada funciona sem ele
  }
};
const stepList = computed(() =>
  map.value.steps.length
    ? map.value.steps
    : Object.entries(steps.value).map(([key, label]) => ({ key, label }))
);
const matchesSearch = text => {
  const q = search.value.trim().toLowerCase();
  return (
    !q ||
    String(text || '')
      .toLowerCase()
      .includes(q)
  );
};
const columns = computed(() =>
  stepList.value.map(col => {
    const items = map.value.items.filter(
      i => i.step === col.key && matchesSearch(`${i.name} ${i.detail}`)
    );
    const groups = KIND_ORDER.map(k => ({
      key: k,
      label: map.value.kinds[k]?.label || k,
      icon: map.value.kinds[k]?.icon || 'i-lucide-bot',
      items: items.filter(i => i.kind === k),
    })).filter(g => g.items.length);
    return {
      ...col,
      messages: filtered.value.filter(m => m.step === col.key),
      groups,
      total: items.length,
    };
  })
);
const generalItems = computed(() =>
  map.value.items.filter(i => !i.step && matchesSearch(i.name))
);
const mapCount = computed(() => map.value.items.length);
const openItem = item => {
  if (!item.route?.name) return;
  router.push({ name: item.route.name, query: item.route.query || {} });
};

// ── personalizar (salva sozinho em agenda_config.journey.map) ──
const customize = ref(false);
const showStages = ref(false);
const isSavingMap = ref(false);
let saveTimer = null;
const saveMap = () => {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(async () => {
    isSavingMap.value = true;
    try {
      await CevicoJourneyAPI.updateSettings({ map: mapConfig.value });
      await loadMap();
    } catch {
      useAlert('Não consegui salvar a personalização.');
    } finally {
      isSavingMap.value = false;
    }
  }, 500);
};
const isShown = kind => mapConfig.value.show?.[kind] !== false;
const toggleKind = kind => {
  mapConfig.value.show = {
    ...(mapConfig.value.show || {}),
    [kind]: !isShown(kind),
  };
  saveMap();
};
const moveStep = (key, dir) => {
  const order = stepList.value.map(s => s.key);
  const i = order.indexOf(key);
  const j = i + dir;
  if (i < 0 || j < 0 || j >= order.length) return;
  order.splice(j, 0, order.splice(i, 1)[0]);
  mapConfig.value.step_order = order;
  saveMap();
};
const renameStep = (key, label) => {
  mapConfig.value.step_labels = {
    ...(mapConfig.value.step_labels || {}),
    [key]: label,
  };
  saveMap();
};
const moveItem = (item, step) => {
  mapConfig.value.overrides = {
    ...(mapConfig.value.overrides || {}),
    [item.id]: step,
  };
  saveMap();
};
const hideItem = item => {
  mapConfig.value.hidden = [
    ...new Set([...(mapConfig.value.hidden || []), item.id]),
  ];
  saveMap();
};
const unhideItem = id => {
  mapConfig.value.hidden = (mapConfig.value.hidden || []).filter(x => x !== id);
  saveMap();
};
const setStageStep = (stageId, step) => {
  mapConfig.value.stage_steps = {
    ...(mapConfig.value.stage_steps || {}),
    [stageId]: step,
  };
  saveMap();
};
const setDensity = d => {
  mapConfig.value.density = d;
  saveMap();
};
const setQueuePos = q => {
  mapConfig.value.queue = q;
  saveMap();
};
const resetMap = () => {
  mapConfig.value = DEFAULT_MAP();
  saveMap();
};
const compact = computed(() => mapConfig.value.density === 'compact');
const queuePos = computed(() => mapConfig.value.queue || 'side');
const stepGridClass = computed(() =>
  queuePos.value === 'side'
    ? 'grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-6'
    : 'grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-6'
);
const openNewAt = step => {
  editing.value = null;
  presetStep.value = step;
  showWizard.value = true;
};
const stagesByStep = computed(() =>
  stepList.value.map(s => ({
    ...s,
    stages: map.value.stages.filter(st => st.step === s.key),
  }))
);

let timer = null;
onMounted(async () => {
  await Promise.all([
    store.dispatch('crm/fetchPipelines').catch(() => {}),
    store.dispatch('labels/get').catch(() => {}),
  ]);
  await Promise.all([load(), loadQueue(), loadMap()]);
  timer = setInterval(loadQueue, 60000);
});
onUnmounted(() => clearInterval(timer));

const inputClass =
  'w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:border-n-brand outline-none';
</script>

<template>
  <div
    class="cv-page flex flex-col h-full overflow-y-auto bg-n-surface-1"
    :style="cvVars"
  >
    <div class="max-w-[1600px] mx-auto w-full p-4 sm:p-6">
      <CevicoHero
        :pal="pal"
        title="Jornada do paciente"
        subtitle="Cada etapa com as mensagens da jornada e tudo o que já age nela: lembretes, follow-up, réguas, automações, campanhas e agentes. Uma tela só, sem rolar para o lado."
        icon="i-lucide-route"
      >
        <template #chips>
          <span class="cevico-hero-chip"
            >{{ activeCount }} de {{ messages.length }} mensagem(ns)
            ligada(s)</span
          >
          <span class="cevico-hero-chip"
            >{{ mapCount }} automação(ões) no mapa</span
          >
          <span v-if="pendingReview.length" class="cevico-hero-chip"
            >{{ pendingReview.length }} aguardando aprovação</span
          >
        </template>
        <template #actions>
          <button
            class="cevico-hero-btn"
            :class="{ 'cevico-hero-btn-on': customize }"
            @click="customize = !customize"
          >
            <span
              :class="
                customize ? 'i-lucide-check' : 'i-lucide-sliders-horizontal'
              "
              class="text-sm"
            />
            {{ customize ? 'Concluir' : 'Personalizar' }}
          </button>
          <button class="cevico-hero-btn" @click="openSettings">
            <span class="i-lucide-map-pin text-sm" />Locais e horário
          </button>
          <button class="cevico-hero-btn" @click="openNew">
            <span class="i-lucide-plus text-sm" />Nova mensagem
          </button>
        </template>
      </CevicoHero>

      <!-- barra de personalização (salva sozinha) -->
      <div
        v-if="customize"
        class="cv-editbar sticky top-0 z-30 mb-4 px-4 py-3 flex items-center gap-x-4 gap-y-2 flex-wrap text-xs"
      >
        <span class="font-bold text-n-slate-12 flex items-center gap-1.5"
          ><span class="i-lucide-sliders-horizontal" />Personalizar</span
        >
        <span class="flex items-center gap-1 flex-wrap">
          <span class="text-n-slate-10">Mostrar:</span>
          <button
            v-for="(k, key) in map.kinds"
            :key="key"
            class="cv-chip"
            :class="{ 'opacity-40 line-through': !isShown(key) }"
            @click="toggleKind(key)"
          >
            <span :class="k.icon" class="text-xs" />{{ k.label }}
          </button>
        </span>
        <span class="cv-seg cv-seg-sm">
          <button
            class="cv-seg-item"
            :class="{ 'cv-seg-on': !compact }"
            @click="setDensity('comfortable')"
          >
            Confortável
          </button>
          <button
            class="cv-seg-item"
            :class="{ 'cv-seg-on': compact }"
            @click="setDensity('compact')"
          >
            Compacto
          </button>
        </span>
        <span class="cv-seg cv-seg-sm">
          <span class="px-2 text-n-slate-10">Fila:</span>
          <button
            class="cv-seg-item"
            :class="{ 'cv-seg-on': queuePos === 'side' }"
            @click="setQueuePos('side')"
          >
            ao lado
          </button>
          <button
            class="cv-seg-item"
            :class="{ 'cv-seg-on': queuePos === 'top' }"
            @click="setQueuePos('top')"
          >
            em cima
          </button>
          <button
            class="cv-seg-item"
            :class="{ 'cv-seg-on': queuePos === 'hidden' }"
            @click="setQueuePos('hidden')"
          >
            oculta
          </button>
        </span>
        <button class="cv-btn cv-btn-sm" @click="showStages = true">
          <span class="i-lucide-kanban text-sm" />Colunas do CRM → etapas
        </button>
        <button
          v-if="map.hidden_items.length"
          class="cv-btn cv-btn-sm cv-btn-ghost"
          :title="map.hidden_items.map(h => h.name).join(', ')"
          @click="map.hidden_items.forEach(h => unhideItem(h.id))"
        >
          <span class="i-lucide-eye text-sm" />Mostrar
          {{ map.hidden_items.length }} escondido(s)
        </button>
        <span class="ml-auto flex items-center gap-2">
          <span class="text-n-slate-9">{{
            isSavingMap ? 'salvando…' : 'salva sozinho'
          }}</span>
          <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="resetMap">
            Restaurar padrão
          </button>
        </span>
      </div>

      <SkeletonScreen v-if="isLoading" variant="dashboard" />

      <div
        v-else
        :class="
          queuePos === 'side'
            ? 'grid grid-cols-1 xl:grid-cols-[minmax(0,1fr)_330px] gap-4 items-start'
            : 'space-y-4'
        "
      >
        <!-- fila em cima -->
        <section
          v-if="queuePos === 'top'"
          class="cv-block p-4"
          :style="blockVars('fila')"
        >
          <div class="flex items-center gap-2 mb-2 flex-wrap">
            <span class="cv-icon"
              ><span class="i-lucide-inbox text-base"
            /></span>
            <h2 class="text-sm font-bold text-n-slate-12">
              Fila de hoje
              <span class="text-n-slate-9 font-normal">{{
                dmy(queueDate)
              }}</span>
            </h2>
            <span
              v-for="(meta, key) in SEND_STATUS"
              :key="key"
              class="cv-chip"
              :class="{ 'opacity-50': !queueByStatus(key) }"
              >{{ meta.label }} {{ queueByStatus(key) }}</span
            >
            <button
              class="cv-iconbtn ml-auto"
              title="Atualizar"
              @click="loadQueue"
            >
              <span
                class="i-lucide-refresh-cw text-sm"
                :class="{ 'animate-spin': isQueueLoading }"
              />
            </button>
            <button
              v-if="pendingReview.length"
              class="cv-btn cv-btn-sm"
              :disabled="busySend === 'all'"
              @click="approveAll"
            >
              <span class="i-lucide-check-check text-sm" />Aprovar todos ({{
                pendingReview.length
              }})
            </button>
          </div>
          <div class="max-h-64 overflow-y-auto divide-y divide-n-weak">
            <div
              v-for="s in queue"
              :key="s.id"
              class="py-2 flex items-center gap-2 text-xs flex-wrap"
            >
              <span class="text-n-slate-9 tabular-nums w-11">{{
                hhmm(s.send_at)
              }}</span>
              <button
                class="font-semibold text-n-slate-12 hover:underline truncate max-w-[14rem]"
                @click="openConversation(s)"
              >
                {{ s.contact_name || s.phone || 'paciente' }}
              </button>
              <span class="text-n-slate-10 truncate">{{ s.message_name }}</span>
              <span
                class="px-1.5 py-0.5 rounded-full text-[10px]"
                :class="SEND_STATUS[s.status]?.cls"
                >{{ SEND_STATUS[s.status]?.label }}</span
              >
              <span
                v-if="s.reply"
                class="px-1.5 py-0.5 rounded-full text-[10px]"
                :class="REPLY_META[s.reply]?.cls"
                >{{ REPLY_META[s.reply]?.label }}</span
              >
              <span
                v-if="s.error"
                class="text-[10px] text-red-600 truncate max-w-[16rem]"
                :title="s.error"
                >{{ s.error }}</span
              >
              <span class="ml-auto flex items-center gap-1">
                <button
                  v-if="s.status === 'pending_review'"
                  class="cv-btn cv-btn-sm"
                  :disabled="busySend === s.id"
                  @click="act(s, 'approve')"
                >
                  Aprovar
                </button>
                <button
                  v-if="['pending_review', 'queued'].includes(s.status)"
                  class="cv-btn cv-btn-sm cv-btn-ghost"
                  :disabled="busySend === s.id"
                  @click="act(s, 'skip')"
                >
                  Pular
                </button>
                <button
                  v-if="['failed', 'expired', 'skipped'].includes(s.status)"
                  class="cv-btn cv-btn-sm cv-btn-ghost"
                  :disabled="busySend === s.id"
                  @click="act(s, 'retry')"
                >
                  Reenviar
                </button>
              </span>
            </div>
            <p
              v-if="!queue.length"
              class="text-xs text-n-slate-9 py-4 text-center"
            >
              Nada na fila de hoje.
            </p>
          </div>
        </section>

        <div class="min-w-0">
          <!-- busca + legenda -->
          <div class="flex items-center gap-2 mb-3 flex-wrap">
            <input
              v-model="search"
              type="search"
              placeholder="Buscar mensagem, régua ou automação…"
              class="cv-input text-xs !w-auto min-w-[14rem]"
            />
            <span
              class="text-[11px] text-n-slate-9 flex items-center gap-2 flex-wrap ml-auto"
            >
              <span class="inline-flex items-center gap-1"
                ><span
                  class="w-2 h-2 rounded-full bg-emerald-500"
                />ligado</span
              >
              <span class="inline-flex items-center gap-1"
                ><span
                  class="w-2 h-2 rounded-full bg-n-slate-7"
                />desligado</span
              >
              <span class="inline-flex items-center gap-1"
                ><span class="i-lucide-external-link text-xs" />abre onde se
                edita</span
              >
            </span>
          </div>

          <!-- 🗺️ o mapa: uma coluna por etapa, embrulha em linhas — nunca rola de lado -->
          <div class="grid gap-3" :class="stepGridClass">
            <section
              v-for="(col, ci) in columns"
              :key="col.key"
              class="cv-block p-3 min-w-0 flex flex-col"
              :style="blockVars(col.key)"
            >
              <header class="flex items-center gap-2 mb-2">
                <span class="cv-icon cv-icon-sm"
                  ><span
                    :class="STEP_META[col.key]?.icon || 'i-lucide-flag'"
                    class="text-sm"
                /></span>
                <input
                  v-if="customize"
                  :value="col.label"
                  class="cv-input text-sm font-bold !py-1 min-w-0 flex-1"
                  maxlength="40"
                  @change="renameStep(col.key, $event.target.value)"
                />
                <h3 v-else class="text-sm font-bold text-n-slate-12 truncate">
                  {{ col.label }}
                </h3>
                <span
                  class="text-[10px] text-n-slate-9 ml-auto whitespace-nowrap"
                  >{{ col.messages.length + col.total }}</span
                >
                <template v-if="customize">
                  <button
                    class="cv-iconbtn"
                    title="Mover para a esquerda"
                    :disabled="ci === 0"
                    @click="moveStep(col.key, -1)"
                  >
                    <span class="i-lucide-chevron-left text-xs" />
                  </button>
                  <button
                    class="cv-iconbtn"
                    title="Mover para a direita"
                    :disabled="ci === columns.length - 1"
                    @click="moveStep(col.key, 1)"
                  >
                    <span class="i-lucide-chevron-right text-xs" />
                  </button>
                </template>
              </header>

              <!-- mensagens da jornada -->
              <div class="space-y-1.5">
                <div
                  v-for="m in col.messages"
                  :key="m.id"
                  class="cv-sub rounded-xl p-2"
                  :class="{ 'opacity-60': !m.active }"
                >
                  <div class="flex items-start gap-1.5">
                    <span
                      :class="
                        KIND_ICON[m.trigger?.kind] || 'i-lucide-message-square'
                      "
                      class="text-sm mt-0.5"
                      :style="{ color: stepColor(col.key) }"
                    />
                    <div class="min-w-0 flex-1">
                      <p
                        class="text-xs font-semibold text-n-slate-12 leading-tight truncate"
                        :title="m.name"
                      >
                        {{ m.name }}
                      </p>
                      <p class="text-[10px] text-n-slate-10 truncate">
                        {{ m.when_label
                        }}<span v-if="!compact"> · {{ m.kind_label }}</span>
                      </p>
                    </div>
                    <button
                      class="relative w-7 h-3.5 rounded-full flex-shrink-0 transition-colors"
                      :class="m.active ? 'bg-emerald-500' : 'bg-n-slate-6'"
                      :title="
                        m.active
                          ? 'Ligada — clique para desligar'
                          : 'Desligada — clique para ligar'
                      "
                      :disabled="busyMessage === m.id"
                      @click="toggleActive(m)"
                    >
                      <span
                        class="absolute top-0.5 w-2.5 h-2.5 rounded-full bg-white transition-all"
                        :class="m.active ? 'left-[15px]' : 'left-0.5'"
                      />
                    </button>
                  </div>
                  <div
                    v-if="!compact"
                    class="flex items-center gap-1 mt-1.5 text-[10px] text-n-slate-10 flex-wrap"
                  >
                    <span
                      v-if="m.approval === 'review'"
                      class="px-1.5 rounded-full bg-amber-500/15 text-amber-700"
                      >aprovação</span
                    >
                    <span
                      v-if="m.expects_reply"
                      class="px-1.5 rounded-full bg-teal-500/15 text-teal-700"
                      >espera resposta</span
                    >
                    <span
                      v-if="m.content?.mode === 'text'"
                      class="px-1.5 rounded-full bg-n-alpha-2"
                      >texto livre</span
                    >
                    <span
                      class="ml-auto tabular-nums"
                      :title="`${m.stats?.sent || 0} enviadas · ${m.stats?.confirmed || 0} confirmaram · ${m.stats?.declined || 0} não vão · ${m.stats?.failed || 0} falharam`"
                    >
                      {{ m.stats?.sent || 0 }} env ·
                      {{ m.stats?.confirmed || 0 }} ✓ ·
                      {{ m.stats?.declined || 0 }} ✗
                    </span>
                  </div>
                  <div class="flex items-center gap-0.5 mt-1 text-n-slate-10">
                    <button
                      class="cv-iconbtn"
                      title="Editar"
                      @click="openEdit(m)"
                    >
                      <span class="i-lucide-pencil text-xs" />
                    </button>
                    <button
                      class="cv-iconbtn"
                      title="Histórico de envios"
                      @click="openHistory(m)"
                    >
                      <span class="i-lucide-history text-xs" />
                    </button>
                    <button
                      class="cv-iconbtn"
                      title="Enviar teste para o meu número"
                      @click="openTest(m)"
                    >
                      <span class="i-lucide-send text-xs" />
                    </button>
                    <button
                      class="cv-iconbtn"
                      title="Planejar agora (adianta a rodada de 15 min)"
                      :disabled="busyMessage === m.id"
                      @click="planNow(m)"
                    >
                      <span class="i-lucide-play text-xs" />
                    </button>
                    <template v-if="deleteConfirmId === m.id">
                      <button
                        class="ml-auto text-[10px] text-red-600 font-bold"
                        @click="destroy(m)"
                      >
                        Excluir mesmo?
                      </button>
                      <button
                        class="text-[10px]"
                        @click="deleteConfirmId = null"
                      >
                        não
                      </button>
                    </template>
                    <button
                      v-else
                      class="cv-iconbtn ml-auto hover:text-red-600"
                      title="Excluir"
                      @click="deleteConfirmId = m.id"
                    >
                      <span class="i-lucide-trash-2 text-xs" />
                    </button>
                  </div>
                </div>
              </div>

              <!-- o que já age nesta etapa -->
              <div v-for="g in col.groups" :key="g.key" class="mt-2">
                <p
                  class="text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold flex items-center gap-1 mb-1"
                >
                  <span :class="g.icon" class="text-xs" />{{ g.label }}
                </p>
                <div class="space-y-1">
                  <div
                    v-for="it in g.items"
                    :key="it.id"
                    class="cv-sub cv-sub-hover rounded-lg px-2 py-1.5 flex items-start gap-1.5 group"
                    :title="it.detail"
                  >
                    <span
                      class="w-2 h-2 rounded-full mt-1.5 flex-shrink-0"
                      :class="
                        it.enabled
                          ? 'bg-emerald-500'
                          : it.enabled === false
                            ? 'bg-n-slate-7'
                            : 'bg-amber-400'
                      "
                      :title="
                        it.enabled
                          ? 'ligado'
                          : it.enabled === false
                            ? 'desligado'
                            : 'estado desconhecido'
                      "
                    />
                    <div class="min-w-0 flex-1">
                      <p class="text-xs text-n-slate-12 leading-tight truncate">
                        {{ it.name }}
                      </p>
                      <p class="text-[10px] text-n-slate-10 truncate">
                        {{ it.when_label
                        }}<span v-if="!compact && it.detail">
                          · {{ it.detail }}</span
                        >
                      </p>
                      <p
                        v-if="
                          !compact &&
                          it.live?.counters &&
                          Object.keys(it.live.counters).length
                        "
                        class="text-[10px] text-n-slate-9 truncate"
                      >
                        {{
                          Object.entries(it.live.counters)
                            .map(([k, v]) => `${k}: ${v}`)
                            .join(' · ')
                        }}
                      </p>
                    </div>
                    <template v-if="customize">
                      <select
                        class="cv-input !py-0 !px-1 text-[10px] !w-auto"
                        :value="it.step"
                        @change="moveItem(it, $event.target.value)"
                      >
                        <option
                          v-for="s in stepList"
                          :key="s.key"
                          :value="s.key"
                        >
                          {{ s.label }}
                        </option>
                        <option value="geral">Geral</option>
                      </select>
                      <button
                        class="cv-iconbtn"
                        title="Esconder do mapa"
                        @click="hideItem(it)"
                      >
                        <span class="i-lucide-eye-off text-xs" />
                      </button>
                    </template>
                    <button
                      v-else
                      class="cv-iconbtn opacity-0 group-hover:opacity-100 focus:opacity-100"
                      title="Abrir onde se edita"
                      @click="openItem(it)"
                    >
                      <span class="i-lucide-external-link text-xs" />
                    </button>
                  </div>
                </div>
              </div>

              <p
                v-if="!col.messages.length && !col.groups.length"
                class="text-[11px] text-n-slate-9 text-center py-3"
              >
                Nada nesta etapa ainda
              </p>
              <button
                class="cv-btn cv-btn-sm cv-btn-ghost mt-auto self-start"
                @click="openNewAt(col.key)"
              >
                <span class="i-lucide-plus text-xs" />mensagem aqui
              </button>
            </section>
          </div>

          <!-- vigias gerais (transversais) -->
          <section
            v-if="generalItems.length"
            class="cv-block p-3 mt-3"
            :style="blockVars('geral')"
          >
            <div class="flex items-center gap-2 mb-2 flex-wrap">
              <span class="cv-icon cv-icon-sm"
                ><span class="i-lucide-radar text-sm"
              /></span>
              <h3 class="text-sm font-bold text-n-slate-12">Vigias gerais</h3>
              <span class="text-[11px] text-n-slate-9"
                >agem em todas as etapas</span
              >
            </div>
            <div class="flex flex-wrap gap-2">
              <div
                v-for="it in generalItems"
                :key="it.id"
                class="cv-sub cv-sub-hover rounded-lg px-2.5 py-1.5 flex items-center gap-2 group max-w-full"
                :title="it.detail"
              >
                <span
                  class="w-2 h-2 rounded-full flex-shrink-0"
                  :class="
                    it.enabled
                      ? 'bg-emerald-500'
                      : it.enabled === false
                        ? 'bg-n-slate-7'
                        : 'bg-amber-400'
                  "
                />
                <span :class="it.icon" class="text-xs text-n-slate-10" />
                <span class="text-xs text-n-slate-12 truncate">{{
                  it.name
                }}</span>
                <span
                  v-if="!compact"
                  class="text-[10px] text-n-slate-10 truncate hidden sm:inline"
                  >· {{ it.when_label }}</span
                >
                <template v-if="customize">
                  <select
                    class="cv-input !py-0 !px-1 text-[10px] !w-auto"
                    value="geral"
                    @change="moveItem(it, $event.target.value)"
                  >
                    <option value="geral">Geral</option>
                    <option v-for="s in stepList" :key="s.key" :value="s.key">
                      {{ s.label }}
                    </option>
                  </select>
                  <button
                    class="cv-iconbtn"
                    title="Esconder do mapa"
                    @click="hideItem(it)"
                  >
                    <span class="i-lucide-eye-off text-xs" />
                  </button>
                </template>
                <button
                  v-else
                  class="cv-iconbtn opacity-0 group-hover:opacity-100 focus:opacity-100"
                  title="Abrir onde se edita"
                  @click="openItem(it)"
                >
                  <span class="i-lucide-external-link text-xs" />
                </button>
              </div>
            </div>
          </section>
        </div>

        <!-- fila ao lado (rola por dentro; nunca empurra a página) -->
        <aside
          v-if="queuePos === 'side'"
          class="cv-block p-3 xl:sticky xl:top-4 flex flex-col min-h-0 xl:max-h-[calc(100vh-3rem)]"
          :style="blockVars('fila')"
        >
          <div class="flex items-center gap-2 mb-2 flex-wrap">
            <span class="cv-icon cv-icon-sm"
              ><span class="i-lucide-inbox text-sm"
            /></span>
            <h2 class="text-sm font-bold text-n-slate-12">Fila de hoje</h2>
            <span class="text-[11px] text-n-slate-9">{{ dmy(queueDate) }}</span>
            <button
              class="cv-iconbtn ml-auto"
              title="Atualizar"
              @click="loadQueue"
            >
              <span
                class="i-lucide-refresh-cw text-xs"
                :class="{ 'animate-spin': isQueueLoading }"
              />
            </button>
          </div>
          <div class="flex flex-wrap gap-1 mb-2">
            <span
              v-for="(meta, key) in SEND_STATUS"
              :key="key"
              class="px-1.5 py-0.5 rounded-full text-[10px]"
              :class="[meta.cls, { 'opacity-40': !queueByStatus(key) }]"
              >{{ meta.label }} {{ queueByStatus(key) }}</span
            >
          </div>
          <button
            v-if="pendingReview.length"
            class="cv-btn cv-btn-sm mb-2 self-start"
            :disabled="busySend === 'all'"
            @click="approveAll"
          >
            <span class="i-lucide-check-check text-sm" />Aprovar todos ({{
              pendingReview.length
            }})
          </button>
          <div
            class="overflow-y-auto min-h-0 divide-y divide-n-weak -mx-1 px-1"
          >
            <div v-for="s in queue" :key="s.id" class="py-2 text-xs">
              <div class="flex items-center gap-1.5">
                <span class="text-n-slate-9 tabular-nums">{{
                  hhmm(s.send_at)
                }}</span>
                <button
                  class="font-semibold text-n-slate-12 hover:underline truncate"
                  @click="openConversation(s)"
                >
                  {{ s.contact_name || s.phone || 'paciente' }}
                </button>
                <span
                  class="ml-auto px-1.5 py-0.5 rounded-full text-[10px] whitespace-nowrap"
                  :class="SEND_STATUS[s.status]?.cls"
                  >{{ SEND_STATUS[s.status]?.label }}</span
                >
              </div>
              <p class="text-[10px] text-n-slate-10 truncate">
                {{ s.message_name }}
              </p>
              <p v-if="s.reply" class="text-[10px]">
                <span
                  class="px-1.5 rounded-full"
                  :class="REPLY_META[s.reply]?.cls"
                  >{{ REPLY_META[s.reply]?.label }}</span
                >
              </p>
              <p
                v-if="s.error"
                class="text-[10px] text-red-600 truncate"
                :title="s.error"
              >
                {{ s.error }}
              </p>
              <div
                v-if="
                  [
                    'pending_review',
                    'queued',
                    'failed',
                    'expired',
                    'skipped',
                  ].includes(s.status)
                "
                class="flex items-center gap-1 mt-1"
              >
                <button
                  v-if="s.status === 'pending_review'"
                  class="cv-btn cv-btn-sm"
                  :disabled="busySend === s.id"
                  @click="act(s, 'approve')"
                >
                  Aprovar
                </button>
                <button
                  v-if="['pending_review', 'queued'].includes(s.status)"
                  class="cv-btn cv-btn-sm cv-btn-ghost"
                  :disabled="busySend === s.id"
                  @click="act(s, 'skip')"
                >
                  Pular
                </button>
                <button
                  v-if="['failed', 'expired', 'skipped'].includes(s.status)"
                  class="cv-btn cv-btn-sm cv-btn-ghost"
                  :disabled="busySend === s.id"
                  @click="act(s, 'retry')"
                >
                  Reenviar
                </button>
              </div>
            </div>
            <p
              v-if="!queue.length"
              class="text-xs text-n-slate-9 py-6 text-center"
            >
              Nada na fila de hoje.
            </p>
          </div>
        </aside>
      </div>

      <!-- colunas do CRM → etapas (personalizar) -->
      <div
        v-if="showStages"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
        @click.self="showStages = false"
      >
        <div
          class="cv-block bg-n-surface-1 w-full max-w-3xl max-h-[90vh] overflow-y-auto p-5"
        >
          <div class="flex items-center gap-2 mb-1">
            <span class="cv-icon"
              ><span class="i-lucide-kanban text-base"
            /></span>
            <h2 class="text-sm font-bold text-n-slate-12">
              Colunas do CRM → etapas da jornada
            </h2>
            <button class="cv-iconbtn ml-auto" @click="showStages = false">
              <span class="i-lucide-x" />
            </button>
          </div>
          <p class="text-xs text-n-slate-10 mb-4">
            Follow-ups, réguas e automações presas a uma coluna do CRM aparecem
            na etapa que a coluna representa. O sistema adivinha pelo nome;
            ajuste o que estiver fora do lugar.
          </p>
          <div class="grid sm:grid-cols-2 gap-2">
            <div
              v-for="st in map.stages"
              :key="st.id"
              class="cv-sub rounded-xl px-3 py-2 flex items-center gap-2"
            >
              <span
                class="w-2.5 h-2.5 rounded-full flex-shrink-0"
                :style="{ background: st.color || '#94a3b8' }"
              />
              <div class="min-w-0 flex-1">
                <p class="text-xs font-semibold text-n-slate-12 truncate">
                  {{ st.name }}
                </p>
                <p class="text-[10px] text-n-slate-9 truncate">
                  {{ st.pipeline }}
                </p>
              </div>
              <select
                class="cv-input !py-1 text-xs !w-auto"
                :value="st.step"
                @change="setStageStep(st.id, $event.target.value)"
              >
                <option v-for="s in stepList" :key="s.key" :value="s.key">
                  {{ s.label }}
                </option>
              </select>
            </div>
          </div>
          <div
            class="mt-4 text-[11px] text-n-slate-9 flex flex-wrap gap-x-4 gap-y-1"
          >
            <span v-for="s in stagesByStep" :key="s.key"
              ><b class="text-n-slate-11">{{ s.label }}:</b>
              {{ s.stages.map(x => x.name).join(', ') || '—' }}</span
            >
          </div>
        </div>
      </div>
      <JourneyWizard
        v-if="showWizard"
        :message="editing"
        :preset-step="presetStep"
        :steps="steps"
        :kinds="kinds"
        :tokens="tokens"
        :inboxes="whatsappInboxes"
        :label-options="labelOptions"
        :label-title-options="labelTitleOptions"
        :stage-options="stageOptions"
        @close="showWizard = false"
        @saved="onSaved"
      />

      <!-- teste para o meu número -->
      <div
        v-if="testTarget"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
        @click.self="testTarget = null"
      >
        <div
          class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-md overflow-hidden"
        >
          <div class="h-1.5 w-full" :style="{ background: GRADIENT }" />
          <div class="p-5 space-y-3">
            <h2 class="text-base font-semibold text-n-slate-12">
              Enviar teste · {{ testTarget.name }}
            </h2>
            <p class="text-xs text-n-slate-10">
              Manda a mensagem para o telefone abaixo com os dados de um
              paciente real de exemplo. Sai pela caixa configurada, de verdade.
            </p>
            <input
              v-model="testPhone"
              :class="inputClass"
              placeholder="55 11 99999-9999"
            />
            <div
              v-if="testResult"
              class="text-xs rounded-lg px-3 py-2"
              :class="
                testResult.ok
                  ? 'bg-green-500/10 text-green-700'
                  : 'bg-red-500/10 text-red-600'
              "
            >
              <template v-if="testResult.ok"
                >Enviada! Prévia: {{ testResult.send?.preview }}</template
              >
              <template v-else>{{
                testResult.send?.error || 'Não saiu.'
              }}</template>
            </div>
            <div class="flex justify-end gap-2">
              <button
                class="px-3 py-1.5 text-sm border border-n-weak rounded-lg text-n-slate-11"
                @click="testTarget = null"
              >
                Fechar
              </button>
              <button
                class="px-4 py-1.5 text-sm text-white rounded-lg font-semibold disabled:opacity-50"
                :style="{ background: GRADIENT }"
                :disabled="isTesting"
                @click="runTest"
              >
                {{ isTesting ? 'Enviando…' : 'Enviar agora' }}
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- histórico -->
      <div
        v-if="historyTarget"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
        @click.self="historyTarget = null"
      >
        <div
          class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-2xl max-h-[85vh] flex flex-col overflow-hidden"
        >
          <div class="h-1.5 w-full" :style="{ background: GRADIENT }" />
          <div
            class="flex items-center justify-between px-5 py-3 border-b border-n-weak"
          >
            <h2 class="text-base font-semibold text-n-slate-12 truncate">
              Histórico · {{ historyTarget.name }}
              <span class="text-xs font-normal text-n-slate-10"
                >({{ historyMeta.total }})</span
              >
            </h2>
            <button
              class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl"
              @click="historyTarget = null"
            />
          </div>
          <div class="overflow-y-auto flex-1 divide-y divide-n-weak">
            <p
              v-if="isHistoryLoading"
              class="px-5 py-4 text-xs text-n-slate-10"
            >
              Carregando…
            </p>
            <p
              v-else-if="!history.length"
              class="px-5 py-4 text-xs text-n-slate-10"
            >
              Nenhum envio ainda.
            </p>
            <div v-for="s in history" :key="s.id" class="px-5 py-2 text-xs">
              <div class="flex items-center gap-2 flex-wrap">
                <span class="text-n-slate-10 font-mono">{{
                  dmyhm(s.sent_at || s.scheduled_for)
                }}</span>
                <button
                  class="font-semibold text-n-slate-12 hover:text-n-brand"
                  @click="openConversation(s)"
                >
                  {{ s.contact?.name || 'Paciente' }}
                </button>
                <span
                  class="px-2 py-0.5 rounded-full font-semibold"
                  :class="SEND_STATUS[s.status]?.cls"
                  >{{ SEND_STATUS[s.status]?.label }}</span
                >
                <span
                  v-if="s.reply"
                  class="px-2 py-0.5 rounded-full font-semibold"
                  :class="REPLY_META[s.reply]?.cls"
                  >{{ REPLY_META[s.reply]?.label || 'Respondeu' }}</span
                >
                <span v-if="s.error" class="text-red-600">{{ s.error }}</span>
              </div>
              <p
                v-if="s.preview"
                class="text-n-slate-10 mt-0.5 truncate"
                :title="s.preview"
              >
                {{ s.preview }}
              </p>
              <p v-if="s.reply_text" class="text-n-slate-11 mt-0.5 italic">
                “{{ s.reply_text }}”
              </p>
            </div>
          </div>
          <div
            v-if="historyMeta.total > 50"
            class="flex items-center justify-between px-5 py-2 border-t border-n-weak text-xs"
          >
            <button
              class="text-n-slate-11 disabled:opacity-40"
              :disabled="historyMeta.page <= 1"
              @click="openHistory(historyTarget, historyMeta.page - 1)"
            >
              ← Anteriores
            </button>
            <span class="text-n-slate-10">página {{ historyMeta.page }}</span>
            <button
              class="text-n-slate-11 disabled:opacity-40"
              :disabled="historyMeta.page * 50 >= historyMeta.total"
              @click="openHistory(historyTarget, historyMeta.page + 1)"
            >
              Próximos →
            </button>
          </div>
        </div>
      </div>

      <!-- locais e horário -->
      <div
        v-if="showSettings"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
        @click.self="showSettings = false"
      >
        <div
          class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-2xl max-h-[88vh] flex flex-col overflow-hidden"
        >
          <div class="h-1.5 w-full" :style="{ background: GRADIENT }" />
          <div
            class="flex items-center justify-between px-5 py-3 border-b border-n-weak"
          >
            <h2
              class="text-base font-semibold text-n-slate-12 flex items-center gap-2"
            >
              <span class="i-lucide-map-pin text-teal-700" /> Locais, horário e
              limites
            </h2>
            <button
              class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl"
              @click="showSettings = false"
            />
          </div>
          <div class="p-5 overflow-y-auto flex-1 space-y-4 text-sm">
            <p class="text-xs text-n-slate-10">
              Os campos aqui viram <b>&#123;&#123;unidade&#125;&#125;</b> e
              <b>&#123;&#123;endereco&#125;&#125;</b> nas mensagens: pela
              unidade da consulta (Agenda) ou pela clínica da cirurgia
              (OftalmoFácil).
            </p>
            <div
              v-for="key in ['default', 'tatuape', 'paulista']"
              :key="key"
              class="grid grid-cols-1 sm:grid-cols-3 gap-2 items-center"
            >
              <p class="text-xs font-semibold text-n-slate-11">
                {{
                  {
                    default: 'Padrão (quando não sabemos)',
                    tatuape: 'Unidade Tatuapé',
                    paulista: 'Unidade Av. Paulista',
                  }[key]
                }}
              </p>
              <input
                v-model="settingsForm.places[key].unidade"
                :class="inputClass"
                placeholder="Nome da unidade"
              />
              <input
                v-model="settingsForm.places[key].endereco"
                :class="inputClass"
                placeholder="Endereço completo"
              />
            </div>
            <div>
              <div class="flex items-center justify-between mb-1">
                <p class="text-xs font-semibold text-n-slate-11">
                  Clínicas do OftalmoFácil (nome como aparece lá)
                </p>
                <button
                  class="text-xs text-teal-700 font-semibold"
                  @click="addClinic"
                >
                  + clínica
                </button>
              </div>
              <div
                v-for="(c, i) in settingsForm.places.clinics"
                :key="i"
                class="grid grid-cols-1 sm:grid-cols-3 gap-2 mb-1"
              >
                <input
                  v-model="c.name"
                  :class="inputClass"
                  placeholder="Ex.: IOP"
                />
                <input
                  v-model="c.unidade"
                  :class="inputClass"
                  placeholder="Como chamar na mensagem"
                />
                <input
                  v-model="c.endereco"
                  :class="inputClass"
                  placeholder="Endereço"
                />
              </div>
            </div>
            <div
              class="grid grid-cols-1 sm:grid-cols-3 gap-3 pt-2 border-t border-n-weak"
            >
              <div>
                <label class="text-xs font-medium text-n-slate-11 block mb-1"
                  >Envia das</label
                >
                <input
                  v-model="settingsForm.hours.start"
                  type="time"
                  :class="inputClass"
                />
              </div>
              <div>
                <label class="text-xs font-medium text-n-slate-11 block mb-1"
                  >até as</label
                >
                <input
                  v-model="settingsForm.hours.end"
                  type="time"
                  :class="inputClass"
                />
              </div>
              <div>
                <label class="text-xs font-medium text-n-slate-11 block mb-1"
                  >Teto por dia</label
                >
                <input
                  v-model.number="settingsForm.daily_cap"
                  type="number"
                  min="1"
                  :class="inputClass"
                />
              </div>
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1"
                >Etiquetas de silêncio extras (além de nao_perturbe e
                perda_*)</label
              >
              <input
                v-model="settingsForm.quiet_labels"
                :class="inputClass"
                placeholder="att_encerrado, obito"
              />
            </div>
          </div>
          <footer
            class="flex justify-end gap-2 px-5 py-3 border-t border-n-weak"
          >
            <button
              class="px-3 py-1.5 text-sm border border-n-weak rounded-lg text-n-slate-11"
              @click="showSettings = false"
            >
              Cancelar
            </button>
            <button
              class="px-4 py-1.5 text-sm text-white rounded-lg font-semibold disabled:opacity-50"
              :style="{ background: GRADIENT }"
              :disabled="isSavingSettings"
              @click="saveSettings"
            >
              {{ isSavingSettings ? 'Salvando…' : 'Salvar' }}
            </button>
          </footer>
        </div>
      </div>
    </div>
  </div>
</template>
