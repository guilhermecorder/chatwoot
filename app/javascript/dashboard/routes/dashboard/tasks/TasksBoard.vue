<script setup>
import { ref, computed, reactive, onMounted, watch } from 'vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import draggable from 'vuedraggable';
import {
  Chart as ChartJS,
  Title, Tooltip, Legend, ArcElement,
} from 'chart.js';
import { Doughnut } from 'vue-chartjs';
import TasksAPI from 'dashboard/api/tasks';
import CrmAPI from 'dashboard/api/crm';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { resolveTheme } from 'dashboard/helper/cevicoThemes';

ChartJS.register(Title, Tooltip, Legend, ArcElement);

const store = useStore();
const { t } = useI18n();
const { isAdmin } = useAdmin();

const agents = useMapGetter('agents/getAgents');
const currentUser = useMapGetter('getCurrentUser');

const tasks = ref([]);
const isLoading = ref(true);
const filterAssignee = ref('me'); // 'me' | '' (todas) | id

// listas por coluna (reconstruídas a partir de tasks)
const lists = reactive({ todo: [], doing: [], done: [] });

const STATUSES = ['todo', 'doing', 'done'];

const PRIORITY_STYLES = {
  low:    'bg-n-alpha-2 text-n-slate-10',
  medium: 'bg-blue-500/15 text-blue-600 dark:text-blue-400',
  high:   'bg-amber-500/15 text-amber-700 dark:text-amber-400',
  urgent: 'bg-red-500/15 text-red-600 dark:text-red-400',
};

const COLUMN_STYLES = {
  todo:  { icon: 'i-lucide-circle',        color: 'text-n-slate-10' },
  doing: { icon: 'i-lucide-loader',        color: 'text-blue-500' },
  done:  { icon: 'i-lucide-check-circle-2', color: 'text-green-500' },
};

// topo das colunas em GRADIENTE — segue o TEMA escolhido pelo admin
// (Santorini, Flor del Mar... — Agenda → botão 🎨). No tema padrão fica
// o visual original azul→roxo / dourado / verde.
const crmSettings = useMapGetter('crm/getSettings');
const theme = computed(() => resolveTheme(crmSettings.value));
// board 100% FEITO = a tela inteira assume o DOURADO do anel
const GOLD_GRAD = 'linear-gradient(135deg, #B8860B, #D4A017)';
const COLUMN_GRADIENTS = computed(() =>
  allDone.value
    ? { todo: GOLD_GRAD, doing: GOLD_GRAD, done: GOLD_GRAD }
    : { todo: theme.value.primary, doing: theme.value.accent, done: theme.value.action }
);
const uiGrad = computed(() => ({
  primary: allDone.value ? GOLD_GRAD : theme.value.primary,
  action: allDone.value ? GOLD_GRAD : theme.value.action,
  accent: allDone.value ? GOLD_GRAD : theme.value.accent,
}));

// ── Celebração: EXPLOSÃO DE EMOJIS (sempre diferente) perto do painel ──
// Nada de troféu: emojis aleatórios do set oficial voam do centro pra fora.
const CELEBRATION_EMOJIS = ['❤️', '😧', '🥳', '👏', '⭐️', '🔥', '🥇', '🚀', '❤️‍🔥', '💖', '✅', '🔝', '💎'];
const showCelebration = ref(false);
const burstPieces = ref([]);
const burstOrigin = ref('float'); // 'ring' = do centro do anel · 'float' = perto do painel
// 1 TIPO de emoji por explosão (sorteado do set) — cada festa é diferente;
// o sorteado também fica no CENTRO do donut durante a fase dourada
const centerEmoji = ref('');
const makeBurst = count => {
  const emoji = CELEBRATION_EMOJIS[Math.floor(Math.random() * CELEBRATION_EMOJIS.length)];
  centerEmoji.value = emoji;
  return Array.from({ length: count }, (_, i) => {
    const angle = Math.random() * Math.PI * 2;
    const dist = 70 + Math.random() * 260;
    return {
      id: i,
      emoji,
      dx: Math.cos(angle) * dist,
      dy: Math.sin(angle) * dist - 50, // tende pra cima, como explosão
      rot: Math.random() * 540 - 270,
      delay: Math.random() * 0.25,
      size: 14 + Math.random() * 16,
    };
  });
};
let celebrationTimer = null;
const explodeEmojis = (count, origin = 'float') => {
  burstOrigin.value = origin;
  burstPieces.value = makeBurst(count);
  showCelebration.value = false; // reinicia a animação se já estava rodando
  requestAnimationFrame(() => { showCelebration.value = true; });
  clearTimeout(celebrationTimer);
  celebrationTimer = setTimeout(() => { showCelebration.value = false; }, 2800);
};
const celebrateIfEarly = task => {
  if (!task.due_at || new Date() >= new Date(task.due_at)) return;
  explodeEmojis(3); // sutil no dia a dia; a festa de verdade é no board zerado
};

// ── Solicitações/ajuda dentro da tarefa (executor ↔ criador) ──
const commentText = ref('');
const isSendingComment = ref(false);

const sendComment = async () => {
  const text = commentText.value.trim();
  if (!text || !editingTask.value || isSendingComment.value) return;
  isSendingComment.value = true;
  try {
    const { data } = await TasksAPI.comment(editingTask.value.id, text);
    const idx = tasks.value.findIndex(x => x.id === data.id);
    if (idx !== -1) tasks.value.splice(idx, 1, data);
    editingTask.value = data;
    store.commit('tasks/upsertTask', data);
    commentText.value = '';
  } catch {
    useAlert(t('TASKS.ERROR'));
  } finally {
    isSendingComment.value = false;
  }
};

const fmtCommentAt = iso =>
  new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });

const visibleTasks = computed(() => {
  if (filterAssignee.value === 'me') {
    return tasks.value.filter(x => x.assignee?.id === currentUser.value.id);
  }
  if (filterAssignee.value) {
    return tasks.value.filter(x => x.assignee?.id === Number(filterAssignee.value));
  }
  return tasks.value;
});

const rebuildLists = () => {
  STATUSES.forEach(s => {
    lists[s] = visibleTasks.value.filter(x => x.status === s);
  });
};

watch([visibleTasks], rebuildLists);

const isOverdue = task =>
  task.status !== 'done' && task.due_at && new Date(task.due_at) < new Date();

// prazo próximo: vence nas próximas 24h e ainda não está atrasada nem feita
const isDueSoon = task => {
  if (task.status === 'done' || !task.due_at) return false;
  const due = new Date(task.due_at).getTime();
  const now = Date.now();
  return due >= now && due - now <= 24 * 60 * 60 * 1000;
};

// ── Mini dashboard ─────────────────────────────────────────
const stats = computed(() => ({
  todo: visibleTasks.value.filter(x => x.status === 'todo').length,
  doing: visibleTasks.value.filter(x => x.status === 'doing').length,
  done: visibleTasks.value.filter(x => x.status === 'done').length,
  overdue: visibleTasks.value.filter(isOverdue).length,
  dueSoon: visibleTasks.value.filter(isDueSoon).length,
}));

// board zerado (tudo FEITO): o anel TREME (tremor que antecede a explosão),
// os emojis explodem do centro e o anel fica pulsando VERDE.
// (declarado DEPOIS de stats: o watch avalia o computed já na montagem)
const allDone = computed(
  () => stats.value.todo === 0 && stats.value.doing === 0 && stats.value.done > 0
);

// 🏆 BANCO DE ELOGIOS: um elogio aleatório a cada 100% (bem-humorado,
// alegre e incentivador — pedido 17/07)
const PRAISE_BANK = [
  'Você desenrola mesmo!',
  'Espantoso!',
  'Como você consegue jogar tão solta?',
  'Impressionante!',
  'Você mandou muito bem!',
  'Mandou bem demais!',
  'Assim que é bom, é ou não é?',
  'Zerado!',
  'Pessoa desenrolada é outro nível!',
  'Como você faz pra ser tão incrível?',
  'Fez parecer fácil. De novo.',
  'A fila viu você chegando e desistiu.',
  'Isso foi uma aula.',
  'Tarefa nenhuma sobrevive a você!',
  'O dia acabou cedo pra essa lista.',
  'Talento é pouco: isso é hábito de campeão.',
];
const pickPraise = () => PRAISE_BANK[Math.floor(Math.random() * PRAISE_BANK.length)];
const praise = ref(pickPraise());
watch(allDone, now => {
  if (now) praise.value = pickPraise();
});

// ── item 95: RENOVAR O AMBIENTE — 5 min depois do 100%, as concluídas
// vão pra coluna oculta e a tela nasce limpa pro próximo ciclo ──
const RENEW_AFTER_MS = 5 * 60 * 1000;
let renewTimer = null;
const renewCountdown = ref(0); // segundos restantes (mostra o chip)
let renewTicker = null;
const clearRenewTimers = () => {
  clearTimeout(renewTimer);
  clearInterval(renewTicker);
  renewTimer = null;
  renewTicker = null;
  renewCountdown.value = 0;
};
const renewNow = async () => {
  clearRenewTimers();
  try {
    await CrmAPI.archiveDoneTasks();
    await fetchTasks();
    useAlert('Ambiente renovado — tela limpa pro próximo ciclo! ✨');
  } catch {
    useAlert('Não consegui renovar o ambiente.');
  }
};
watch(allDone, now => {
  if (!now) {
    clearRenewTimers(); // entrou tarefa nova no meio → cancela a renovação
    return;
  }
  renewCountdown.value = RENEW_AFTER_MS / 1000;
  renewTicker = setInterval(() => { renewCountdown.value = Math.max(0, renewCountdown.value - 1); }, 1000);
  renewTimer = setTimeout(renewNow, RENEW_AFTER_MS);
});
const renewLabel = computed(() => {
  const m = Math.floor(renewCountdown.value / 60);
  const s = String(renewCountdown.value % 60).padStart(2, '0');
  return `${m}:${s}`;
});

// névoa de partículas douradas ORBITANDO o donut (substitui o glow) —
// aura ESPALHADA e VOLUMOSA (pedidos 18/07): muitas partículas em órbitas
// amplas, mais densas perto do anel; as distantes menores e mais tênues
const mistParticles = Array.from({ length: 70 }, (_, i) => {
  const r = 60 + Math.random() * 78;
  const far = (r - 60) / 78; // 0 = coladinha no anel · 1 = bem longe
  return {
    id: i,
    r,
    dur: 4.5 + Math.random() * 6.5,
    delay: -Math.random() * 10,
    size: 2.5 + Math.random() * (5 - far * 2.5),
    op: (0.5 + Math.random() * 0.45) * (1 - far * 0.4),
  };
});

const ringPhase = ref(''); // '' | 'tremor' | 'gold'
let ringTimer = null;
watch(
  allDone,
  (now, before) => {
    clearTimeout(ringTimer);
    if (now && before === false) {
      ringPhase.value = 'tremor'; // treme quando o verde fecha...
      ringTimer = setTimeout(() => {
        explodeEmojis(150, 'ring'); // ...explode do centro...
        ringPhase.value = 'gold'; // ...e fica DOURADO pulsante
      }, 750);
    } else if (now) {
      ringPhase.value = 'gold'; // já abriu completo: sem explosão de novo
      if (!centerEmoji.value)
        centerEmoji.value = CELEBRATION_EMOJIS[Math.floor(Math.random() * CELEBRATION_EMOJIS.length)];
    } else {
      ringPhase.value = '';
    }
  },
  { immediate: true }
);

// legenda própria do donut (alinhada, e DOURADA junto com a explosão)
const donutLegend = computed(() => {
  const gold = ringPhase.value === 'gold';
  const item = (label, color) => ({ label, color: gold ? '#D4A017' : color });
  return [
    item(t('TASKS.COLUMNS.TODO'), '#94A3B8'),
    item(t('TASKS.COLUMNS.DOING'), '#3B82F6'),
    item(t('TASKS.STATS.OVERDUE'), '#EF4444'),
    item(t('TASKS.COLUMNS.DONE'), '#10B981'),
  ];
});

// tarefas em aberto (não feitas) por status, para o donut
const donutChart = computed(() => {
  const phase = ringPhase.value; // repinta o donut quando vira DOURADO
  const openTodo = visibleTasks.value.filter(x => x.status === 'todo' && !isOverdue(x)).length;
  const openDoing = visibleTasks.value.filter(x => x.status === 'doing' && !isOverdue(x)).length;
  const overdue = stats.value.overdue;
  const done = stats.value.done;
  const total = openTodo + openDoing + overdue + done;
  if (total === 0) return null;
  return {
    total,
    data: {
      labels: [
        t('TASKS.COLUMNS.TODO'),
        t('TASKS.COLUMNS.DOING'),
        t('TASKS.STATS.OVERDUE'),
        t('TASKS.COLUMNS.DONE'),
      ],
      datasets: [{
        data: [openTodo, openDoing, overdue, done],
        // gradiente por fatia = aspecto brilhante/vítreo; quando o board
        // completa, a fatia "Feito" (o anel inteiro) vira DOURADA
        backgroundColor: ctx => {
          const gold = phase === 'gold';
          const pairs = [
            ['#94A3B8', '#D8E0EA'],
            ['#3B82F6', '#93E3FD'],
            ['#EF4444', '#FCA5A5'],
            gold ? ['#B8860B', '#FFD700'] : ['#10B981', '#86EFC9'],
          ];
          const { chartArea, ctx: c } = ctx.chart;
          const pair = pairs[ctx.dataIndex % pairs.length];
          if (!chartArea) return pair[0];
          const g = c.createLinearGradient(chartArea.left, chartArea.top, chartArea.left, chartArea.bottom);
          g.addColorStop(0, pair[1]);
          g.addColorStop(1, pair[0]);
          return g;
        },
        borderWidth: 0,
        borderRadius: 14, // pontas arredondadas até na parte "reta" das fatias
        spacing: 3,
        hoverOffset: 6,
      }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { display: false }, // legenda própria em HTML, alinhada abaixo
        tooltip: { callbacks: { label: ctx => ` ${ctx.raw} (${ctx.label})` } },
      },
      cutout: '66%',
      animation: { duration: 500, easing: 'easeOutQuart' },
    },
  };
});

// ── Fetch ──────────────────────────────────────────────────
const fetchTasks = async () => {
  isLoading.value = true;
  try {
    const { data } = await TasksAPI.get();
    tasks.value = data;
    store.commit('tasks/setTasks', data); // mantém o badge da sidebar em dia
  } catch {
    useAlert(t('TASKS.ERROR'));
  } finally {
    isLoading.value = false;
  }
};

onMounted(() => {
  if (!agents.value.length) store.dispatch('agents/get');
  store.dispatch('crm/fetchSettings').catch(() => {}); // tema do ambiente
  fetchTasks();
});

// ── Drag entre colunas ─────────────────────────────────────
const onColumnChange = async (statusKey, evt) => {
  const moved = evt.added?.element;
  if (!moved || moved.status === statusKey) return;
  const previous = moved.status;
  moved.status = statusKey;
  try {
    const { data } = await TasksAPI.update(moved.id, { status: statusKey });
    const idx = tasks.value.findIndex(x => x.id === moved.id);
    if (idx !== -1) tasks.value.splice(idx, 1, data);
    store.commit('tasks/upsertTask', data);
    if (statusKey === 'done' && previous !== 'done') celebrateIfEarly(data);
  } catch {
    moved.status = previous;
    rebuildLists();
    useAlert(t('TASKS.ERROR'));
  }
};

// ── Modal criar/editar ─────────────────────────────────────
const showModal = ref(false);
const editingTask = ref(null);
const isSaving = ref(false);
const showDeleteConfirm = ref(false);

const emptyForm = () => ({
  title: '',
  description: '',
  task_type: '',
  priority: 'medium',
  status: 'todo',
  due_at: '',
  assignee_id: currentUser.value.id,
});

const form = ref(emptyForm());

const toLocalInput = iso => {
  if (!iso) return '';
  const d = new Date(iso);
  const pad = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

const openCreate = () => {
  editingTask.value = null;
  form.value = emptyForm();
  showDeleteConfirm.value = false;
  resetPendingFiles();
  showModal.value = true;
};

const openEdit = task => {
  editingTask.value = task;
  resetPendingFiles();
  form.value = {
    title: task.title,
    description: task.description ?? '',
    task_type: task.task_type ?? '',
    priority: task.priority,
    status: task.status,
    due_at: toLocalInput(task.due_at),
    assignee_id: task.assignee?.id ?? null,
  };
  showDeleteConfirm.value = false;
  showModal.value = true;
};

// ── 📎 Anexos da tarefa (imagem/PDF/documento) ─────────────
const ACCEPT_FILES = 'image/*,.pdf,.doc,.docx,.xls,.xlsx';
const pendingFiles = ref([]); // escolhidos e ainda não enviados ({ file, url })
const isUploadingFiles = ref(false);
const previewImage = ref(null); // imagem aberta em tela cheia
const fileInputEl = ref(null);

const resetPendingFiles = () => {
  pendingFiles.value.forEach(p => p.url && URL.revokeObjectURL(p.url));
  pendingFiles.value = [];
  previewImage.value = null;
};

const pickFiles = () => fileInputEl.value?.click();

const onFilesPicked = event => {
  const files = Array.from(event.target.files || []);
  event.target.value = '';
  files.forEach(file => {
    const already =
      (editingTask.value?.attachments?.length || 0) + pendingFiles.value.length;
    if (already >= 10) return;
    pendingFiles.value.push({
      file,
      url: file.type?.startsWith('image/') ? URL.createObjectURL(file) : null,
    });
  });
};

const removePending = index => {
  const item = pendingFiles.value[index];
  if (item?.url) URL.revokeObjectURL(item.url);
  pendingFiles.value.splice(index, 1);
};

// envia os pendentes depois que a tarefa existe; devolve a tarefa atualizada
const uploadPending = async taskId => {
  if (!pendingFiles.value.length) return null;
  isUploadingFiles.value = true;
  try {
    const { data } = await TasksAPI.addAttachments(
      taskId,
      pendingFiles.value.map(p => p.file)
    );
    resetPendingFiles();
    return data;
  } catch (error) {
    useAlert(error?.response?.data?.error || t('TASKS.ATTACH.ERROR'));
    return null;
  } finally {
    isUploadingFiles.value = false;
  }
};

const removeAttachment = async att => {
  if (!editingTask.value) return;
  try {
    const { data } = await TasksAPI.deleteAttachment(editingTask.value.id, att.id);
    syncTask(data);
    editingTask.value = data;
  } catch {
    useAlert(t('TASKS.ATTACH.ERROR'));
  }
};

const syncTask = data => {
  const idx = tasks.value.findIndex(x => x.id === data.id);
  if (idx !== -1) tasks.value.splice(idx, 1, data);
  else tasks.value.push(data);
  store.commit('tasks/upsertTask', data);
};

const save = async () => {
  if (!form.value.title.trim() || isSaving.value) return;
  isSaving.value = true;
  try {
    const payload = {
      ...form.value,
      title: form.value.title.trim(),
      due_at: form.value.due_at ? new Date(form.value.due_at).toISOString() : null,
    };
    if (editingTask.value) {
      const wasDone = editingTask.value.status === 'done';
      let { data } = await TasksAPI.update(editingTask.value.id, payload);
      data = (await uploadPending(data.id)) || data;
      syncTask(data);
      if (data.status === 'done' && !wasDone) celebrateIfEarly(data);
      useAlert(t('TASKS.SAVED'));
    } else {
      let { data } = await TasksAPI.create(payload);
      data = (await uploadPending(data.id)) || data;
      syncTask(data);
      useAlert(t('TASKS.CREATED'));
    }
    showModal.value = false;
  } catch {
    useAlert(t('TASKS.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const removeTask = async () => {
  if (!editingTask.value) return;
  try {
    await TasksAPI.delete(editingTask.value.id);
    store.commit('tasks/removeTask', editingTask.value.id);
    tasks.value = tasks.value.filter(x => x.id !== editingTask.value.id);
    showModal.value = false;
    useAlert(t('TASKS.DELETED'));
  } catch {
    useAlert(t('TASKS.ERROR'));
  }
};

const formatDue = iso => {
  if (!iso) return null;
  return new Date(iso).toLocaleString('pt-BR', {
    day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit',
  });
};
</script>

<template>
  <div class="bg-n-surface-1 flex flex-col h-full w-full">
    <!-- Top bar -->
    <div class="flex items-center gap-3 px-8 py-5 border-b border-n-weak flex-shrink-0 flex-wrap">
      <div class="flex flex-col gap-2">
        <h1 class="text-lg font-bold text-n-slate-12 flex items-center gap-2">
          <span class="w-8 h-8 rounded-lg flex items-center justify-center transition-all" :style="{ background: uiGrad.primary }">
            <span class="i-lucide-list-checks text-white text-base" />
          </span>
          {{ $t('TASKS.TITLE') }}
        </h1>
        <button
          class="flex items-center justify-center gap-1.5 text-sm font-semibold px-3.5 py-2 rounded-lg text-white hover:opacity-90 transition-opacity shadow w-fit"
          :style="{ background: uiGrad.action }"
          @click="openCreate"
        >
          <span class="i-lucide-plus text-sm" />
          {{ $t('TASKS.NEW') }}
        </button>
      </div>

      <!-- Mini dashboard -->
      <div class="flex items-center gap-2 ml-2 flex-wrap">
        <span class="text-xs bg-n-alpha-2 text-n-slate-11 rounded-full px-2.5 py-1">
          {{ $t('TASKS.COLUMNS.TODO') }}: <strong>{{ stats.todo }}</strong>
        </span>
        <span class="text-xs bg-blue-500/10 text-blue-600 dark:text-blue-400 rounded-full px-2.5 py-1">
          {{ $t('TASKS.COLUMNS.DOING') }}: <strong>{{ stats.doing }}</strong>
        </span>
        <span class="text-xs bg-green-500/10 text-green-600 rounded-full px-2.5 py-1">
          {{ $t('TASKS.COLUMNS.DONE') }}: <strong>{{ stats.done }}</strong>
        </span>
        <span
          v-if="stats.overdue > 0"
          class="text-xs bg-red-500/10 text-red-600 rounded-full px-2.5 py-1 font-medium"
        >
          ⚠ {{ $t('TASKS.STATS.OVERDUE') }}: <strong>{{ stats.overdue }}</strong>
        </span>
        <span
          v-if="stats.dueSoon > 0"
          class="text-xs bg-amber-500/10 text-amber-700 dark:text-amber-400 rounded-full px-2.5 py-1 font-medium"
        >
          ⏰ {{ $t('TASKS.STATS.DUE_SOON') }}: <strong>{{ stats.dueSoon }}</strong>
        </span>
      </div>

      <div class="flex items-center gap-2 ml-auto">
        <!-- Filtro por pessoa -->
        <select
          v-model="filterAssignee"
          class="h-9 text-sm border border-n-weak rounded-lg px-2 bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
        >
          <option value="me">{{ $t('TASKS.FILTER.MINE') }}</option>
          <option value="">{{ $t('TASKS.FILTER.ALL') }}</option>
          <template v-if="isAdmin">
            <option v-for="agent in agents" :key="agent.id" :value="agent.id">{{ agent.name }}</option>
          </template>
        </select>
      </div>
    </div>

    <!-- Loading -->
    <SkeletonScreen v-if="isLoading" variant="board" />

    <!-- Kanban + dashboard -->
    <div v-else class="flex-1 min-h-0 overflow-x-auto p-8">
      <div class="flex gap-4 h-full min-w-max">
        <!-- Colunas de largura fixa (padrão, igual CRM) -->
        <div
          v-for="statusKey in STATUSES"
          :key="statusKey"
          class="flex flex-col bg-n-alpha-1 rounded-2xl w-[86vw] min-w-[86vw] snap-center md:w-72 md:min-w-72 flex-shrink-0 h-full min-h-0 overflow-hidden border border-n-weak"
        >
          <!-- Topo da coluna em gradiente -->
          <div
            class="flex items-center gap-2 px-3.5 py-2.5 flex-shrink-0 text-white"
            :style="{ background: COLUMN_GRADIENTS[statusKey] }"
            :class="theme.glass ? 'cevico-glass' : ''"
          >
            <span :class="COLUMN_STYLES[statusKey].icon" class="text-sm" />
            <span class="text-sm font-bold">{{ $t(`TASKS.COLUMNS.${statusKey.toUpperCase()}`) }}</span>
            <span class="text-xs bg-white/25 rounded-full px-2 py-0.5 font-semibold ml-auto">{{ lists[statusKey].length }}</span>
          </div>

          <!-- Cards -->
          <div class="flex-1 overflow-y-auto p-2 min-h-0" style="scrollbar-width:thin;">
            <draggable
              v-model="lists[statusKey]"
              group="tasks"
              item-key="id"
              :animation="150"
              ghost-class="opacity-40"
              class="min-h-16 h-full"
              @change="onColumnChange(statusKey, $event)"
            >
              <template #item="{ element: task }">
                <div
                  class="bg-n-solid-2 border rounded-xl p-4 mb-2 cursor-pointer hover:border-n-brand hover:shadow-sm transition-all select-none"
                  :class="isOverdue(task) ? 'border-red-400/60' : (isDueSoon(task) ? 'border-amber-400/60' : 'border-n-weak')"
                  @click="openEdit(task)"
                >
                  <p
                    class="text-sm font-medium text-n-slate-12 leading-snug"
                    :class="task.status === 'done' ? 'line-through opacity-60' : ''"
                  >
                    {{ task.title }}
                  </p>

                  <div class="flex items-center gap-1.5 mt-2 flex-wrap">
                    <span
                      class="text-[10px] font-medium rounded-full px-2 py-0.5"
                      :class="PRIORITY_STYLES[task.priority]"
                    >
                      {{ $t(`TASKS.PRIORITY.${task.priority.toUpperCase()}`) }}
                    </span>
                    <span
                      v-if="task.task_type"
                      class="text-[10px] bg-n-alpha-2 text-n-slate-10 rounded-full px-2 py-0.5"
                    >
                      {{ task.task_type }}
                    </span>
                    <span
                      v-if="task.attachments?.length"
                      class="text-[10px] bg-n-alpha-2 text-n-slate-10 rounded-full px-2 py-0.5 inline-flex items-center gap-0.5"
                      :title="$t('TASKS.ATTACH.TITLE')"
                    >
                      <span class="i-lucide-paperclip text-[9px]" />
                      {{ task.attachments.length }}
                    </span>
                  </div>

                  <div v-if="task.due_at" class="mt-2">
                    <span
                      class="inline-flex items-center gap-1 text-[11px]"
                      :class="isOverdue(task) ? 'text-red-500 font-medium' : (isDueSoon(task) ? 'text-amber-600 dark:text-amber-400 font-medium' : 'text-n-slate-9')"
                    >
                      <span class="i-lucide-calendar-clock text-[11px]" />
                      {{ formatDue(task.due_at) }}
                      <span v-if="isDueSoon(task)" class="ml-0.5">· {{ $t('TASKS.STATS.DUE_SOON') }}</span>
                    </span>
                  </div>

                  <div class="flex items-center justify-between mt-2 gap-1">
                    <span v-if="task.assignee" class="flex items-center gap-1 text-[11px] text-n-slate-10 min-w-0">
                      <span class="i-lucide-user text-[10px] flex-shrink-0" />
                      <span class="truncate">{{ task.assignee.name }}</span>
                    </span>
                    <span
                      v-if="task.creator && task.creator.id !== task.assignee?.id"
                      class="text-[10px] text-n-slate-9 ml-auto flex-shrink-0"
                      :title="$t('TASKS.CREATED_BY', { name: task.creator.name })"
                    >
                      {{ $t('TASKS.BY') }} {{ task.creator.name.split(' ')[0] }}
                    </span>
                  </div>
                </div>
              </template>
            </draggable>
          </div>
        </div>

        <!-- Painel de resumo (donut) — só desktop -->
        <div
          class="hidden lg:flex flex-col w-72 min-w-72 flex-shrink-0 rounded-2xl p-4 h-full min-h-0 overflow-y-auto cevico-no-scrollbar border-2 transition-all"
          :class="allDone ? 'cevico-all-done-ring bg-amber-500/5' : 'bg-n-alpha-1 border-n-weak'"
        >
          <p class="text-sm font-bold text-n-slate-12 mb-1 flex items-center gap-1.5">
            <span class="w-6 h-6 rounded-lg flex items-center justify-center transition-all" :style="{ background: uiGrad.primary }">
              <span class="i-lucide-pie-chart text-white text-xs" />
            </span>
            {{ $t('TASKS.DASHBOARD.TITLE') }}
          </p>
          <p class="text-xs text-n-slate-10 mb-4">{{ $t('TASKS.DASHBOARD.SUBTITLE') }}</p>

          <!-- O DONUT é o anel: fecha verde → TREME → explosão do centro →
               fica DOURADO pulsando (como os ícones da sidebar) -->
          <div
            v-if="donutChart"
            class="h-48 relative"
            :class="{ 'cevico-ring-tremor': ringPhase === 'tremor', 'cevico-donut-gold': ringPhase === 'gold' }"
          >
            <!-- névoa de partículas douradas circulando com o donut -->
            <span
              v-for="p in (ringPhase === 'gold' ? mistParticles : [])"
              :key="'mist' + p.id"
              class="cevico-donut-mist"
              :style="{
                '--r': p.r + 'px',
                '--dur': p.dur + 's',
                '--delay': p.delay + 's',
                width: p.size + 'px',
                height: p.size + 'px',
                opacity: p.op,
              }"
            />
            <!-- só o anel gira (sentido horário); os emojis ficam parados -->
            <div class="h-full" :class="ringPhase === 'gold' ? 'cevico-donut-spin' : ''">
              <Doughnut :data="donutChart.data" :options="donutChart.options" />
            </div>
            <!-- o emoji da explosão mora no CENTRO do donut -->
            <span
              v-if="ringPhase === 'gold' && centerEmoji"
              class="absolute inset-0 flex items-center justify-center text-4xl pointer-events-none"
            >{{ centerEmoji }}</span>
            <!-- explosão a partir do CENTRO do anel -->
            <span
              v-for="c in (showCelebration && burstOrigin === 'ring' ? burstPieces : [])"
              :key="'ring' + c.id"
              class="cevico-burst-emoji"
              :style="{
                '--dx': c.dx + 'px',
                '--dy': c.dy + 'px',
                '--rot': c.rot + 'deg',
                fontSize: c.size + 'px',
                animationDelay: c.delay + 's',
              }"
            >{{ c.emoji }}</span>
          </div>
          <!-- legenda própria: 2 de cada lado, dourada junto com a explosão -->
          <div v-if="donutChart" class="grid grid-cols-2 gap-x-5 gap-y-1.5 w-fit mx-auto mt-3">
            <span
              v-for="item in donutLegend"
              :key="item.label"
              class="flex items-center gap-1.5 text-[11px] transition-colors"
              :style="{ color: ringPhase === 'gold' ? '#D4A017' : 'var(--n-slate-11, #94A3B8)' }"
            >
              <span class="w-2.5 h-2.5 rounded-full transition-colors" :style="{ backgroundColor: item.color }" />
              {{ item.label }}
            </span>
          </div>
          <div v-if="!donutChart" class="h-56 flex flex-col items-center justify-center text-n-slate-10 gap-2">
            <span class="i-lucide-pie-chart text-3xl" />
            <span class="text-xs">{{ $t('TASKS.DASHBOARD.EMPTY') }}</span>
          </div>
          <div v-if="allDone" class="text-center mt-3 space-y-0.5 flex-shrink-0">
            <p class="text-xs font-semibold leading-snug" style="color: #D4A017">
              Parabéns, 100% das tarefas concluídas.
            </p>
            <!-- elogio ALEATÓRIO do banco de elogios, com destaque -->
            <p class="text-lg font-black tracking-wide leading-snug" style="color: #B8860B">
              {{ praise }} ✨
            </p>
            <!-- item 95: renovação automática do ambiente -->
            <div v-if="renewCountdown > 0" class="flex items-center justify-center gap-1.5 pt-1">
              <span class="text-[10px] px-2 py-0.5 rounded-full font-bold" style="background: rgba(184, 134, 11, 0.14); color: #92600A">
                🧹 tela nova em {{ renewLabel }}
              </span>
              <button
                class="text-[10px] font-bold px-2 py-0.5 rounded-full text-white hover:opacity-90"
                style="background: linear-gradient(135deg, #B8860B, #D4A017)"
                title="Mover as concluídas pra coluna oculta agora"
                @click="renewNow"
              >
                Renovar agora
              </button>
            </div>
          </div>

          <!-- Números-chave: no modo 100%, só o FEITO fica dourado (pulsando);
               as caixinhas zeradas ficam escuras -->
          <div class="grid grid-cols-2 gap-2.5 mt-4 flex-shrink-0">
            <div
              class="rounded-xl p-2.5 text-center text-white shadow transition-all"
              :class="allDone ? 'cevico-tile-gold-pulse' : ''"
              :style="{ background: uiGrad.action }"
            >
              <p class="text-lg font-bold leading-tight">{{ stats.done }}</p>
              <p class="text-[11px] text-white/85">{{ $t('TASKS.COLUMNS.DONE') }}</p>
            </div>
            <div
              class="rounded-xl p-2.5 text-center shadow transition-all"
              :class="allDone && stats.doing === 0 ? 'bg-n-solid-2' : 'text-white'"
              :style="allDone && stats.doing === 0 ? {} : { background: uiGrad.accent }"
            >
              <p class="text-lg font-bold leading-tight" :class="allDone && stats.doing === 0 ? 'text-n-slate-12' : ''">{{ stats.doing }}</p>
              <p class="text-[11px]" :class="allDone && stats.doing === 0 ? 'text-n-slate-10' : 'text-white/85'">{{ $t('TASKS.COLUMNS.DOING') }}</p>
            </div>
            <div
              class="rounded-xl p-2.5 text-center shadow transition-all"
              :class="allDone && stats.todo === 0 ? 'bg-n-solid-2' : 'text-white'"
              :style="allDone && stats.todo === 0 ? {} : { background: uiGrad.primary }"
            >
              <p class="text-lg font-bold leading-tight" :class="allDone && stats.todo === 0 ? 'text-n-slate-12' : ''">{{ stats.todo }}</p>
              <p class="text-[11px]" :class="allDone && stats.todo === 0 ? 'text-n-slate-10' : 'text-white/85'">{{ $t('TASKS.COLUMNS.TODO') }}</p>
            </div>
            <div
              class="rounded-xl p-2.5 text-center shadow"
              :class="stats.overdue > 0 ? 'text-white' : 'bg-n-solid-2'"
              :style="stats.overdue > 0 ? { background: 'linear-gradient(135deg, #DC2626, #F59E0B)' } : {}"
            >
              <p class="text-lg font-bold leading-tight" :class="stats.overdue > 0 ? '' : 'text-n-slate-12'">{{ stats.overdue }}</p>
              <p class="text-[11px]" :class="stats.overdue > 0 ? 'text-white/85' : 'text-n-slate-10'">{{ $t('TASKS.STATS.OVERDUE') }}</p>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 🔍 anexo de imagem em tela cheia -->
    <div
      v-if="previewImage"
      class="fixed inset-0 z-[70] flex items-center justify-center p-6 cursor-zoom-out"
      style="background: rgba(0, 0, 0, 0.82)"
      @click="previewImage = null"
    >
      <img :src="previewImage" class="max-w-full max-h-full rounded-xl shadow-2xl" />
      <button class="absolute top-4 right-4 text-white text-2xl i-lucide-x" @click="previewImage = null" />
    </div>

    <!-- 🎉 Celebração: EXPLOSÃO DE EMOJIS localizada perto do painel -->
    <div
      v-if="showCelebration && burstOrigin === 'float'"
      class="fixed z-[60] pointer-events-none top-1/3 left-1/2 -translate-x-1/2 lg:left-auto lg:translate-x-0 lg:right-44"
    >
      <span
        v-for="c in burstPieces"
        :key="c.id"
        class="cevico-burst-emoji"
        :style="{
          '--dx': c.dx + 'px',
          '--dy': c.dy + 'px',
          '--rot': c.rot + 'deg',
          fontSize: c.size + 'px',
          animationDelay: c.delay + 's',
        }"
      >{{ c.emoji }}</span>
    </div>

    <!-- Modal criar/editar -->
    <div
      v-if="showModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      @click.self="showModal = false"
    >
      <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-md max-h-[90vh] flex flex-col">
        <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak flex-shrink-0">
          <h2 class="text-base font-semibold text-n-slate-12">
            {{ editingTask ? $t('TASKS.EDIT') : $t('TASKS.NEW') }}
          </h2>
          <button class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl" @click="showModal = false" />
        </div>

        <div class="flex-1 overflow-y-auto p-5 space-y-3.5">
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1">{{ $t('TASKS.FORM.TITLE') }} *</label>
            <input
              v-model="form.title"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
              :placeholder="$t('TASKS.FORM.TITLE_PLACEHOLDER')"
            />
          </div>

          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1">{{ $t('TASKS.FORM.DESCRIPTION') }}</label>
            <textarea
              v-model="form.description"
              rows="3"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 resize-none focus:outline-none focus:border-n-brand"
            />
          </div>

          <div class="grid grid-cols-2 gap-5">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">{{ $t('TASKS.FORM.TYPE') }}</label>
              <select
                v-model="form.task_type"
                class="w-full border border-n-weak rounded-lg px-2 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              >
                <option value="">—</option>
                <option value="Atendimento">Atendimento</option>
                <option value="Follow-up">Follow-up</option>
                <option value="Administrativo">Administrativo</option>
                <option value="Marketing">Marketing</option>
                <option value="Outro">Outro</option>
              </select>
            </div>

            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">{{ $t('TASKS.FORM.PRIORITY') }}</label>
              <select
                v-model="form.priority"
                class="w-full border border-n-weak rounded-lg px-2 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              >
                <option value="low">{{ $t('TASKS.PRIORITY.LOW') }}</option>
                <option value="medium">{{ $t('TASKS.PRIORITY.MEDIUM') }}</option>
                <option value="high">{{ $t('TASKS.PRIORITY.HIGH') }}</option>
                <option value="urgent">{{ $t('TASKS.PRIORITY.URGENT') }}</option>
              </select>
            </div>

            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">{{ $t('TASKS.FORM.ASSIGNEE') }}</label>
              <select
                v-model="form.assignee_id"
                class="w-full border border-n-weak rounded-lg px-2 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              >
                <option v-for="agent in agents" :key="agent.id" :value="agent.id">{{ agent.name }}</option>
              </select>
            </div>

            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">{{ $t('TASKS.FORM.DUE_AT') }}</label>
              <input
                v-model="form.due_at"
                type="datetime-local"
                class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-sm bg-n-solid-2 text-n-slate-12"
              />
            </div>
          </div>

          <div v-if="editingTask">
            <label class="text-xs font-medium text-n-slate-11 block mb-1">{{ $t('TASKS.FORM.STATUS') }}</label>
            <select
              v-model="form.status"
              class="w-full border border-n-weak rounded-lg px-2 py-2 text-sm bg-n-solid-2 text-n-slate-12"
            >
              <option value="todo">{{ $t('TASKS.COLUMNS.TODO') }}</option>
              <option value="doing">{{ $t('TASKS.COLUMNS.DOING') }}</option>
              <option value="done">{{ $t('TASKS.COLUMNS.DONE') }}</option>
            </select>
          </div>

          <!-- 📎 Anexos: imagem/PDF/documento (criador ↔ responsável) -->
          <div class="border-t border-n-weak pt-3">
            <p class="text-xs font-semibold text-n-slate-11 mb-2 flex items-center gap-1.5">
              <span class="i-lucide-paperclip text-sm" style="color: #B8860B" />
              {{ $t('TASKS.ATTACH.TITLE') }}
              <span class="text-n-slate-9 font-normal">{{ $t('TASKS.ATTACH.HINT') }}</span>
            </p>
            <div v-if="(editingTask?.attachments?.length || 0) + pendingFiles.length" class="flex flex-wrap gap-2 mb-2">
              <!-- já salvos na tarefa -->
              <div v-for="att in editingTask?.attachments || []" :key="`att-${att.id}`" class="relative group">
                <img
                  v-if="att.is_image"
                  :src="att.url"
                  :title="att.filename"
                  class="w-16 h-16 rounded-lg object-cover border border-n-weak cursor-zoom-in"
                  @click="previewImage = att.url"
                />
                <a
                  v-else
                  :href="att.url"
                  target="_blank"
                  :title="att.filename"
                  class="w-16 h-16 rounded-lg border border-n-weak bg-n-alpha-1 flex flex-col items-center justify-center gap-0.5 px-1"
                >
                  <span class="i-lucide-file-text text-lg text-n-slate-10" />
                  <span class="text-[8px] text-n-slate-10 truncate w-full text-center">{{ att.filename }}</span>
                </a>
                <button
                  class="absolute -top-1.5 -right-1.5 w-4 h-4 rounded-full bg-n-slate-12 text-white text-[9px] leading-none hidden group-hover:flex items-center justify-center"
                  :title="$t('TASKS.ATTACH.REMOVE')"
                  @click.stop="removeAttachment(att)"
                >
                  ✕
                </button>
              </div>
              <!-- escolhidos agora (sobem ao salvar) -->
              <div v-for="(p, i) in pendingFiles" :key="`pend-${i}`" class="relative group">
                <img v-if="p.url" :src="p.url" :title="p.file.name" class="w-16 h-16 rounded-lg object-cover border border-dashed border-n-strong" />
                <div v-else :title="p.file.name" class="w-16 h-16 rounded-lg border border-dashed border-n-strong bg-n-alpha-1 flex flex-col items-center justify-center gap-0.5 px-1">
                  <span class="i-lucide-file-text text-lg text-n-slate-10" />
                  <span class="text-[8px] text-n-slate-10 truncate w-full text-center">{{ p.file.name }}</span>
                </div>
                <button
                  class="absolute -top-1.5 -right-1.5 w-4 h-4 rounded-full bg-n-slate-12 text-white text-[9px] leading-none hidden group-hover:flex items-center justify-center"
                  :title="$t('TASKS.ATTACH.REMOVE')"
                  @click.stop="removePending(i)"
                >
                  ✕
                </button>
              </div>
            </div>
            <button
              class="text-xs font-medium px-3 py-1.5 rounded-lg border border-n-weak hover:border-n-brand text-n-slate-11 flex items-center gap-1.5 disabled:opacity-50"
              :disabled="isUploadingFiles"
              @click="pickFiles"
            >
              <span class="i-lucide-plus text-xs" />
              {{ isUploadingFiles ? $t('TASKS.ATTACH.SENDING') : $t('TASKS.ATTACH.ADD') }}
            </button>
            <input ref="fileInputEl" type="file" class="hidden" multiple :accept="ACCEPT_FILES" @change="onFilesPicked" />
            <p v-if="pendingFiles.length" class="text-[10px] text-n-slate-9 mt-1">{{ $t('TASKS.ATTACH.ON_SAVE') }}</p>
          </div>

          <!-- Solicitações / ajuda: conversa entre quem criou e quem executa -->
          <div v-if="editingTask" class="border-t border-n-weak pt-3">
            <p class="text-xs font-semibold text-n-slate-11 mb-1.5 flex items-center gap-1.5">
              <span class="i-lucide-messages-square text-sm" style="color: #B8860B" />
              Solicitações e ajuda
              <span class="text-n-slate-9 font-normal">(entre {{ editingTask.creator?.name?.split(' ')[0] }} e {{ editingTask.assignee?.name?.split(' ')[0] || 'o responsável' }})</span>
            </p>
            <div v-if="editingTask.comments?.length" class="space-y-1.5 max-h-40 overflow-y-auto mb-2 pr-1">
              <div
                v-for="(c, i) in editingTask.comments"
                :key="i"
                class="rounded-lg px-2.5 py-1.5 text-xs border"
                :class="c.user_id === currentUser.id
                  ? 'bg-n-brand/5 border-n-brand/20'
                  : 'bg-n-solid-2 border-n-weak'"
              >
                <p class="flex items-center gap-2 mb-0.5">
                  <span class="font-semibold text-n-slate-12">{{ c.name?.split(' ')[0] }}</span>
                  <span class="text-[10px] text-n-slate-9 ml-auto">{{ fmtCommentAt(c.at) }}</span>
                </p>
                <p class="text-n-slate-11 leading-snug">{{ c.text }}</p>
              </div>
            </div>
            <p v-else class="text-[11px] text-n-slate-9 mb-2">
              Precisa de esclarecimento ou quer avisar algo? Escreva aqui — fica registrado na tarefa.
            </p>
            <div class="flex gap-1.5">
              <input
                v-model="commentText"
                class="flex-1 border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
                placeholder="Ex: consigo os telefones atualizados?"
                @keyup.enter="sendComment"
              />
              <button
                class="px-3 rounded-lg text-white text-sm font-medium disabled:opacity-50"
                style="background: linear-gradient(135deg, #B8860B, #D4A017)"
                :disabled="!commentText.trim() || isSendingComment"
                @click="sendComment"
              >
                <span :class="isSendingComment ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-send'" class="text-sm" />
              </button>
            </div>
          </div>
        </div>

        <div class="px-5 py-4 border-t border-n-weak flex-shrink-0 space-y-2">
          <div class="flex gap-2">
            <button
              class="flex-1 text-white rounded-lg py-2 text-sm font-medium disabled:opacity-50"
              :style="{ background: theme.primary }"
              :disabled="!form.title.trim() || isSaving"
              @click="save"
            >
              {{ isSaving ? $t('TASKS.SAVING') : $t('TASKS.SAVE') }}
            </button>
            <button
              class="px-4 border border-n-weak rounded-lg py-2 text-sm text-n-slate-11"
              @click="showModal = false"
            >
              {{ $t('TASKS.CANCEL') }}
            </button>
          </div>

          <!-- Delete (só na edição) -->
          <div v-if="editingTask">
            <button
              v-if="!showDeleteConfirm"
              class="w-full py-1.5 text-xs text-red-500 hover:text-red-600"
              @click="showDeleteConfirm = true"
            >
              {{ $t('TASKS.DELETE') }}
            </button>
            <div v-else class="flex items-center gap-2">
              <span class="text-xs text-n-slate-11 flex-1">{{ $t('TASKS.DELETE_CONFIRM') }}</span>
              <button class="bg-red-500 text-white px-3 py-1 rounded-lg text-xs" @click="removeTask">
                {{ $t('TASKS.DELETE') }}
              </button>
              <button class="border border-n-weak px-3 py-1 rounded-lg text-xs text-n-slate-11" @click="showDeleteConfirm = false">
                {{ $t('TASKS.CANCEL') }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* EXPLOSÃO DE EMOJIS: cada emoji voa do centro pra fora, gira e some
   (GPU: só transform/opacity — leve mesmo com 150 peças, roda 1 vez) */
.cevico-burst-emoji {
  position: absolute;
  top: 50%;
  left: 50%;
  opacity: 0;
  line-height: 1;
  animation: cevico-burst-fly 1.4s cubic-bezier(0.16, 0.84, 0.44, 1) forwards;
}
@keyframes cevico-burst-fly {
  0% { transform: translate(0, 0) rotate(0deg) scale(0.4); opacity: 1; }
  70% { opacity: 1; }
  100% { transform: translate(var(--dx), var(--dy)) rotate(var(--rot)) scale(1.1); opacity: 0; }
}

/* painel de resumo rola por dentro SEM mostrar a barra */
.cevico-no-scrollbar {
  scrollbar-width: none;
  -ms-overflow-style: none;
}
.cevico-no-scrollbar::-webkit-scrollbar {
  display: none;
}

/* caixinha FEITO pulsando dourada no modo 100% */
.cevico-tile-gold-pulse {
  animation: cevico-tile-gold 2.2s ease-in-out infinite;
}
@keyframes cevico-tile-gold {
  0%, 100% { box-shadow: 0 0 6px rgba(212, 160, 23, 0.35); }
  50% { box-shadow: 0 0 18px rgba(255, 200, 40, 0.7); }
}

/* board 100% feito: a CAIXA pulsa DOURADA (cor do anel) */
.cevico-all-done-ring {
  border-color: #d4a017 !important;
  animation: cevico-ring-pulse 2.2s ease-in-out infinite;
}
@keyframes cevico-ring-pulse {
  0%, 100% { box-shadow: 0 0 8px rgba(212, 160, 23, 0.35); }
  50% { box-shadow: 0 0 22px rgba(255, 200, 40, 0.75); }
}

/* TREMOR que antecede a explosão (o donut sacode rapidinho) */
.cevico-ring-tremor {
  animation: cevico-ring-tremor 0.12s linear infinite;
}
@keyframes cevico-ring-tremor {
  0%, 100% { transform: translate(0, 0) rotate(0deg); }
  25% { transform: translate(-2px, 1px) rotate(-1.5deg); }
  50% { transform: translate(2px, -1px) rotate(1.5deg); }
  75% { transform: translate(-1px, -2px) rotate(-1deg); }
}

/* depois da explosão: o donut dourado GIRA em sentido horário e pulsa
   suave, no ritmo dos ícones da sidebar (2.2s) */
.cevico-donut-gold {
  animation: cevico-donut-gold-pulse 2.2s ease-in-out infinite;
}
.cevico-donut-spin {
  /* 3 tempos FLUIDOS: volta 1 rápida, volta 2 mais lenta, e da volta 3 em
     diante estabiliza. A curva do arranque termina exatamente na velocidade
     do giro contínuo (45°/s) — o movimento emenda sem freio brusco. */
  animation:
    cevico-donut-spin-burst 3.2s cubic-bezier(0.15, 0.6, 0.5, 0.9) 1,
    cevico-donut-spin 8s linear 3.2s infinite;
}
@keyframes cevico-donut-spin-burst {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(720deg); }
}
@keyframes cevico-donut-spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}
/* sem glow no donut (pedido 18/07) — só a respiração sutil de opacidade;
   quem brilha é a névoa de partículas ao redor */
@keyframes cevico-donut-gold-pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.9; }
}

/* efeito "vidro" leve dos temas (Santorini etc.) */
.cevico-glass {
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.4),
    inset 0 -1px 0 rgba(15, 23, 42, 0.15);
}

/* névoa de partículas douradas orbitando o donut (no lugar do glow) */
.cevico-donut-mist {
  position: absolute;
  left: 50%;
  top: 50%;
  border-radius: 9999px;
  background: radial-gradient(circle, #f5e9b8 0%, #d4a017 70%);
  box-shadow: 0 0 6px rgba(212, 160, 23, 0.85);
  pointer-events: none;
  animation: cevico-donut-orbit var(--dur) linear infinite;
  animation-delay: var(--delay);
}
@keyframes cevico-donut-orbit {
  from {
    transform: translate(-50%, -50%) rotate(0deg) translateX(var(--r));
  }
  to {
    transform: translate(-50%, -50%) rotate(360deg) translateX(var(--r));
  }
}
@media (prefers-reduced-motion: reduce) {
  .cevico-donut-mist {
    animation: none;
    display: none;
  }
}
</style>
