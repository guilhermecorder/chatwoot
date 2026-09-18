<script setup>
// 🗺️ JORNADA DO PACIENTE (item 168): a linha do tempo (Lead → Consulta →
// Orçamento → Cirurgia agendada → Pós-operatório → Retorno) com as
// mensagens penduradas em cada etapa, a "Fila de hoje" (aprovar/pular),
// o assistente "Nova mensagem" (3 passos), locais/horário e o histórico
// de envios de cada mensagem. Substitui o N8N da confirmação cirúrgica.
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import CevicoJourneyAPI from 'dashboard/api/cevicoJourney';
import JourneyWizard from './components/JourneyWizard.vue';

const store = useStore();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabels');
const pipelines = useMapGetter('crm/getPipelines');

const GRADIENT = 'linear-gradient(135deg, #0F766E, #14B8A6)';
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
const byStep = computed(() =>
  Object.keys(steps.value).map(key => ({
    key,
    label: steps.value[key],
    items: filtered.value.filter(m => m.step === key),
  }))
);
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
const openNew = () => {
  editing.value = null;
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

const goTo = (name, query = {}) => router.push({ name, query });

let timer = null;
onMounted(async () => {
  await Promise.all([
    store.dispatch('crm/fetchPipelines').catch(() => {}),
    store.dispatch('labels/get').catch(() => {}),
  ]);
  await Promise.all([load(), loadQueue()]);
  timer = setInterval(loadQueue, 60000);
});
onUnmounted(() => clearInterval(timer));

const inputClass =
  'w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:border-n-brand outline-none';
</script>

<template>
  <div class="flex-1 overflow-auto p-4 sm:p-6 space-y-5">
    <!-- cabeçalho -->
    <div class="flex flex-wrap items-center gap-3">
      <h1 class="text-xl font-bold text-n-slate-12 flex items-center gap-2">
        <span
          class="w-9 h-9 rounded-xl flex items-center justify-center"
          :style="{ background: GRADIENT }"
        >
          <span class="i-lucide-route text-white text-lg" />
        </span>
        Jornada do paciente
      </h1>
      <p class="text-xs text-n-slate-10 hidden md:block">
        a mensagem certa no momento certo · {{ activeCount }} ligada(s) de
        {{ messages.length }}
      </p>
      <div class="ml-auto flex items-center gap-2 flex-wrap">
        <input
          v-model="search"
          :class="inputClass"
          class="!w-48 !mb-0"
          style="margin-bottom: 0"
          placeholder="Buscar mensagem…"
        />
        <button
          class="px-3 py-2 text-xs border border-n-weak rounded-lg text-n-slate-11 hover:bg-n-alpha-1 flex items-center gap-1"
          @click="openSettings"
        >
          <span class="i-lucide-map-pin" /> Locais e horário
        </button>
        <button
          class="px-3 py-2 text-xs text-white rounded-lg font-semibold flex items-center gap-1"
          :style="{ background: GRADIENT }"
          @click="openNew"
        >
          <span class="i-lucide-plus" /> Nova mensagem
        </button>
      </div>
    </div>

    <SkeletonScreen v-if="isLoading" variant="cards" />

    <template v-else>
      <!-- FILA DE HOJE -->
      <section
        class="rounded-2xl border border-n-weak bg-n-solid-1 overflow-hidden"
      >
        <div
          class="flex flex-wrap items-center gap-3 px-4 py-3 border-b border-n-weak"
        >
          <h2 class="text-sm font-bold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-inbox text-teal-700" /> Fila de hoje
            <span class="text-xs font-normal text-n-slate-10">{{
              dmy(queueDate)
            }}</span>
          </h2>
          <div class="flex items-center gap-1.5 text-[11px]">
            <span
              v-for="(meta, key) in SEND_STATUS"
              v-show="queueByStatus(key)"
              :key="key"
              class="px-2 py-0.5 rounded-full font-semibold"
              :class="meta.cls"
            >
              {{ queueByStatus(key) }} {{ meta.label.toLowerCase() }}
            </span>
          </div>
          <div class="ml-auto flex items-center gap-2">
            <button
              class="text-xs text-n-slate-10 hover:text-n-slate-12"
              :disabled="isQueueLoading"
              @click="loadQueue"
            >
              <span
                class="i-lucide-refresh-cw"
                :class="isQueueLoading ? 'animate-spin' : ''"
              />
            </button>
            <button
              v-if="pendingReview.length"
              class="px-3 py-1.5 text-xs text-white rounded-lg font-semibold disabled:opacity-50"
              :style="{ background: GRADIENT }"
              :disabled="busySend === 'all'"
              @click="approveAll"
            >
              Aprovar todos ({{ pendingReview.length }})
            </button>
          </div>
        </div>
        <p v-if="!queue.length" class="px-4 py-4 text-xs text-n-slate-10">
          Nada planejado para hoje ainda. O motor roda a cada 15 minutos; use
          "Planejar agora" numa mensagem para adiantar.
        </p>
        <div v-else class="divide-y divide-n-weak max-h-80 overflow-y-auto">
          <div
            v-for="s in queue"
            :key="s.id"
            class="flex items-center gap-3 px-4 py-2 text-xs"
          >
            <span class="w-11 text-n-slate-10 font-mono">{{
              hhmm(s.scheduled_for)
            }}</span>
            <button
              class="font-semibold text-n-slate-12 hover:text-n-brand truncate min-w-0"
              @click="openConversation(s)"
            >
              {{ s.contact?.name || 'Paciente' }}
            </button>
            <span class="text-n-slate-10 truncate min-w-0 hidden sm:inline"
              >· {{ s.message_name }}</span
            >
            <span
              class="px-2 py-0.5 rounded-full font-semibold whitespace-nowrap"
              :class="SEND_STATUS[s.status]?.cls"
              >{{ SEND_STATUS[s.status]?.label }}</span
            >
            <span
              v-if="s.reply"
              class="px-2 py-0.5 rounded-full font-semibold whitespace-nowrap"
              :class="REPLY_META[s.reply]?.cls"
              >{{ REPLY_META[s.reply]?.label || 'Respondeu' }}</span
            >
            <span
              v-if="s.error"
              class="text-red-600 truncate min-w-0"
              :title="s.error"
              >{{ s.error }}</span
            >
            <div class="ml-auto flex items-center gap-1.5 flex-shrink-0">
              <template v-if="s.status === 'pending_review'">
                <button
                  class="px-2 py-1 rounded-lg text-white font-semibold disabled:opacity-50"
                  :style="{ background: GRADIENT }"
                  :disabled="busySend === s.id"
                  @click="act(s, 'approve')"
                >
                  Aprovar
                </button>
                <button
                  class="px-2 py-1 rounded-lg border border-n-weak text-n-slate-11 disabled:opacity-50"
                  :disabled="busySend === s.id"
                  @click="act(s, 'skip')"
                >
                  Pular
                </button>
              </template>
              <button
                v-else-if="s.status === 'queued'"
                class="px-2 py-1 rounded-lg border border-n-weak text-n-slate-11 disabled:opacity-50"
                :disabled="busySend === s.id"
                @click="act(s, 'skip')"
              >
                Pular
              </button>
              <button
                v-else-if="['failed', 'skipped', 'expired'].includes(s.status)"
                class="px-2 py-1 rounded-lg border border-n-weak text-n-slate-11 disabled:opacity-50"
                :disabled="busySend === s.id"
                @click="act(s, 'retry')"
              >
                Reenviar
              </button>
            </div>
          </div>
        </div>
      </section>

      <!-- LINHA DO TEMPO -->
      <section>
        <div class="flex gap-3 overflow-x-auto pb-2 -mx-1 px-1">
          <div
            v-for="col in byStep"
            :key="col.key"
            class="flex-shrink-0 w-64 sm:w-72"
          >
            <div class="flex items-center gap-2 mb-2">
              <span
                class="w-7 h-7 rounded-lg flex items-center justify-center text-white"
                :style="{ background: STEP_META[col.key]?.color }"
              >
                <span :class="STEP_META[col.key]?.icon" class="text-sm" />
              </span>
              <p class="text-sm font-bold text-n-slate-12">{{ col.label }}</p>
              <span class="text-[11px] text-n-slate-10 ml-auto">{{
                col.items.length
              }}</span>
            </div>
            <div
              class="space-y-2 min-h-[80px] rounded-2xl border border-dashed border-n-weak p-2"
            >
              <div
                v-for="m in col.items"
                :key="m.id"
                class="rounded-xl bg-n-solid-1 border border-n-weak p-3 shadow-sm"
                :class="!m.active ? 'opacity-60' : ''"
              >
                <div class="flex items-start gap-2">
                  <span
                    :class="KIND_ICON[m.trigger?.kind]"
                    class="text-base mt-0.5"
                    :style="{ color: STEP_META[col.key]?.color }"
                  />
                  <div class="min-w-0 flex-1">
                    <p
                      class="text-sm font-semibold text-n-slate-12 leading-tight"
                    >
                      {{ m.name }}
                    </p>
                    <p class="text-[11px] text-n-slate-10 mt-0.5">
                      {{ m.kind_label }} · {{ m.when_label }}
                    </p>
                  </div>
                  <button
                    class="relative w-8 h-4 rounded-full flex-shrink-0 transition-colors"
                    :class="m.active ? 'bg-green-500' : 'bg-n-slate-6'"
                    :title="
                      m.active
                        ? 'Ligada — clique para desligar'
                        : 'Desligada — clique para ligar'
                    "
                    :disabled="busyMessage === m.id"
                    @click="toggleActive(m)"
                  >
                    <span
                      class="absolute top-0.5 w-3 h-3 rounded-full bg-white transition-all"
                      :class="m.active ? 'left-[18px]' : 'left-0.5'"
                    />
                  </button>
                </div>
                <div
                  class="flex items-center gap-1.5 mt-2 text-[10px] flex-wrap"
                >
                  <span
                    v-if="m.approval === 'review'"
                    class="px-1.5 py-0.5 rounded-full bg-amber-500/15 text-amber-700"
                    >aprovação</span
                  >
                  <span
                    v-if="m.expects_reply"
                    class="px-1.5 py-0.5 rounded-full bg-teal-500/15 text-teal-700"
                    >espera resposta</span
                  >
                  <span
                    v-if="m.content?.mode === 'text'"
                    class="px-1.5 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-10"
                    >texto livre</span
                  >
                </div>
                <div class="grid grid-cols-3 gap-1 mt-2 text-center">
                  <div class="rounded-lg bg-n-alpha-1 py-1">
                    <p class="text-sm font-bold text-n-slate-12">
                      {{ m.stats?.sent ?? 0 }}
                    </p>
                    <p
                      class="text-[9px] uppercase tracking-wide text-n-slate-10"
                    >
                      enviadas
                    </p>
                  </div>
                  <div class="rounded-lg bg-green-500/10 py-1">
                    <p class="text-sm font-bold text-green-700">
                      {{ m.stats?.confirmed ?? 0 }}
                    </p>
                    <p
                      class="text-[9px] uppercase tracking-wide text-n-slate-10"
                    >
                      confirmou
                    </p>
                  </div>
                  <div class="rounded-lg bg-red-500/10 py-1">
                    <p class="text-sm font-bold text-red-600">
                      {{ m.stats?.declined ?? 0 }}
                    </p>
                    <p
                      class="text-[9px] uppercase tracking-wide text-n-slate-10"
                    >
                      não vai
                    </p>
                  </div>
                </div>
                <p
                  v-if="m.stats?.pending || m.stats?.failed"
                  class="text-[10px] text-n-slate-10 mt-1"
                >
                  <span v-if="m.stats.pending"
                    >{{ m.stats.pending }} na fila</span
                  >
                  <span v-if="m.stats.pending && m.stats.failed"> · </span>
                  <span v-if="m.stats.failed" class="text-red-600">
                    {{ m.stats.failed }} falharam
                  </span>
                </p>
                <div class="flex items-center gap-1 mt-2 text-n-slate-10">
                  <button
                    class="p-1 rounded hover:bg-n-alpha-1 hover:text-n-slate-12"
                    title="Editar"
                    @click="openEdit(m)"
                  >
                    <span class="i-lucide-pencil text-xs" />
                  </button>
                  <button
                    class="p-1 rounded hover:bg-n-alpha-1 hover:text-n-slate-12"
                    title="Histórico de envios"
                    @click="openHistory(m)"
                  >
                    <span class="i-lucide-history text-xs" />
                  </button>
                  <button
                    class="p-1 rounded hover:bg-n-alpha-1 hover:text-n-slate-12"
                    title="Enviar teste para o meu número"
                    @click="openTest(m)"
                  >
                    <span class="i-lucide-send text-xs" />
                  </button>
                  <button
                    class="p-1 rounded hover:bg-n-alpha-1 hover:text-n-slate-12"
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
                    <button class="text-[10px]" @click="deleteConfirmId = null">
                      não
                    </button>
                  </template>
                  <button
                    v-else
                    class="ml-auto p-1 rounded hover:bg-red-500/10 hover:text-red-600"
                    title="Excluir"
                    @click="deleteConfirmId = m.id"
                  >
                    <span class="i-lucide-trash-2 text-xs" />
                  </button>
                </div>
              </div>
              <p
                v-if="!col.items.length"
                class="text-[11px] text-n-slate-9 text-center py-4"
              >
                Nenhuma mensagem nesta etapa
              </p>
            </div>
          </div>
        </div>
        <!-- outras réguas que já existem -->
        <p
          class="text-[11px] text-n-slate-10 mt-2 flex items-center gap-1.5 flex-wrap"
        >
          <span class="i-lucide-link" /> Outras réguas do sistema:
          <button
            class="underline hover:text-n-slate-12"
            @click="goTo('cevico_automations', { tab: 'robos' })"
          >
            Lembretes da consulta (D-1/D-0)
          </button>
          ·
          <button
            class="underline hover:text-n-slate-12"
            @click="goTo('crm_campaigns')"
          >
            Campanha WhatsApp
          </button>
          ·
          <button
            class="underline hover:text-n-slate-12"
            @click="goTo('crm_campaigns', { tab: 'automations' })"
          >
            Régua de mensagens
          </button>
          ·
          <button
            class="underline hover:text-n-slate-12"
            @click="goTo('cevico_automations', { tab: 'regras' })"
          >
            Automações de coluna
          </button>
          ·
          <button
            class="underline hover:text-n-slate-12"
            @click="goTo('cevico_automations', { tab: 'fluxos' })"
          >
            Fluxograma
          </button>
        </p>
      </section>
    </template>

    <!-- assistente -->
    <JourneyWizard
      v-if="showWizard"
      :message="editing"
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
            Manda a mensagem para o telefone abaixo com os dados de um paciente
            real de exemplo. Sai pela caixa configurada, de verdade.
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
          <p v-if="isHistoryLoading" class="px-5 py-4 text-xs text-n-slate-10">
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
            <b>&#123;&#123;endereco&#125;&#125;</b> nas mensagens: pela unidade
            da consulta (Agenda) ou pela clínica da cirurgia (OftalmoFácil).
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
        <footer class="flex justify-end gap-2 px-5 py-3 border-t border-n-weak">
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
</template>
