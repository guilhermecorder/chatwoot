<script setup>
// ✅ TAREFAS (kit CEVICO, 20/09): o quadro da equipe no formato "iMac G3 +
// vidro" — hero, colunas em .cv-block que embrulham (sem rolar de lado),
// cartões .cv-sub, chips e modal do kit. A mecânica (arrastar entre colunas,
// filtros, anexos, comentários, celebração) é a mesma de antes.
import { ref, computed, reactive, onMounted, watch } from 'vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import draggable from 'vuedraggable';
import { Chart as ChartJS, Title, Tooltip, Legend, ArcElement } from 'chart.js';
import { Doughnut } from 'vue-chartjs';
import TasksAPI from 'dashboard/api/tasks';
import CrmAPI from 'dashboard/api/crm';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import PatientNoteForm from 'dashboard/components-next/cevico/PatientNoteForm.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { useRouter } from 'vue-router';

ChartJS.register(Title, Tooltip, Legend, ArcElement);

const store = useStore();
const router = useRouter();
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const { isAdmin } = useAdmin();

const agents = useMapGetter('agents/getAgents');
const currentUser = useMapGetter('getCurrentUser');

const tasks = ref([]);
const isLoading = ref(true);
const filterAssignee = ref('me'); // 'me' | '' (todas) | id

// listas por coluna (reconstruídas a partir de tasks)
const lists = reactive({ todo: [], doing: [], done: [] });

const STATUSES = ['todo', 'doing', 'done'];

// prioridade → cor do chip do kit (média fica na cor da coluna)
const PRIORITY_STYLES = {
  low: 'cv-slate',
  medium: '',
  high: 'cv-amber',
  urgent: 'cv-red',
};

// 🍎 paleta do kit: um bloco por coluna + o resumo (admin escolhe a cor de
// cada um no chip da paleta do hero; escopo 'crm:tarefas')
const BLOCKS = [
  { id: 'todo', label: 'A fazer', icon: 'i-lucide-circle' },
  { id: 'doing', label: 'Fazendo', icon: 'i-lucide-loader' },
  { id: 'done', label: 'Feito', icon: 'i-lucide-check-circle-2' },
  { id: 'resumo', label: 'Resumo', icon: 'i-lucide-pie-chart' },
  { id: 'notas', label: 'Notas dos pacientes', icon: 'i-lucide-sticky-note' },
];
const BLOCK_ICON = Object.fromEntries(BLOCKS.map(b => [b.id, b.icon]));
const pal = useCevicoPalette({ scope: 'crm:tarefas', blocks: BLOCKS });
const { cvVars, blockVars } = pal;

const plural = (n, one, many) => (n === 1 ? one : many);

// ── 📝 NOTAS DOS PACIENTES (item 211): recados rápidos sobre um paciente,
// da clínica inteira (a mesma nota do contato — aparece na ficha, no Espaço
// do Paciente e no Meu Painel). Seguem o filtro de pessoa do topo. ──
const patientNotes = ref([]);
const isLoadingNotes = ref(false);
const showNoteModal = ref(false);
const fetchNotes = async () => {
  isLoadingNotes.value = true;
  try {
    const { data } = await CrmAPI.patientNotes({ limit: 60 });
    patientNotes.value = data;
  } catch {
    patientNotes.value = [];
  } finally {
    isLoadingNotes.value = false;
  }
};
const visibleNotes = computed(() => {
  if (filterAssignee.value === 'me')
    return patientNotes.value.filter(n => n.mine);
  if (filterAssignee.value)
    return patientNotes.value.filter(
      n => n.author?.id === Number(filterAssignee.value)
    );
  return patientNotes.value;
});
const onNoteSaved = note => {
  patientNotes.value.unshift(note);
  showNoteModal.value = false;
};
const deleteNote = async note => {
  try {
    await CrmAPI.deletePatientNote(note.id);
    patientNotes.value = patientNotes.value.filter(n => n.id !== note.id);
    useAlert('Nota apagada.');
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui apagar a nota.');
  }
};
const openPatient = note => {
  if (!note.contact?.id) return;
  router.push({
    name: 'patient_space',
    params: { accountId: accountId.value, contactId: note.contact.id },
  });
};
const fmtNoteAt = iso =>
  new Date(iso).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });

// ── Celebração: EXPLOSÃO DE EMOJIS (sempre diferente) perto do painel ──
// Nada de troféu: emojis aleatórios do set oficial voam do centro pra fora.
const CELEBRATION_EMOJIS = [
  '❤️',
  '😧',
  '🥳',
  '👏',
  '⭐️',
  '🔥',
  '🥇',
  '🚀',
  '❤️‍🔥',
  '💖',
  '✅',
  '🔝',
  '💎',
];
const showCelebration = ref(false);
const burstPieces = ref([]);
const burstOrigin = ref('float'); // 'ring' = do centro do anel · 'float' = perto do painel
// 1 TIPO de emoji por explosão (sorteado do set) — cada festa é diferente;
// o sorteado também fica no CENTRO do donut durante a fase dourada
const centerEmoji = ref('');
const makeBurst = count => {
  const emoji =
    CELEBRATION_EMOJIS[Math.floor(Math.random() * CELEBRATION_EMOJIS.length)];
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
  requestAnimationFrame(() => {
    showCelebration.value = true;
  });
  clearTimeout(celebrationTimer);
  celebrationTimer = setTimeout(() => {
    showCelebration.value = false;
  }, 2800);
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
  new Date(iso).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });

const visibleTasks = computed(() => {
  if (filterAssignee.value === 'me') {
    return tasks.value.filter(x => x.assignee?.id === currentUser.value.id);
  }
  if (filterAssignee.value) {
    return tasks.value.filter(
      x => x.assignee?.id === Number(filterAssignee.value)
    );
  }
  return tasks.value;
});

// admin: seletor "por pessoa" — limpar volta para "Minhas tarefas"
const agentFilter = computed({
  get: () =>
    filterAssignee.value === 'me' || filterAssignee.value === ''
      ? ''
      : String(filterAssignee.value),
  set: v => {
    filterAssignee.value = v || 'me';
  },
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

// faixa de aviso acima do quadro ("2 atrasadas e 1 perto do prazo")
const deadlineNote = computed(() => {
  const parts = [];
  const { overdue, dueSoon } = stats.value;
  if (overdue)
    parts.push(`${overdue} ${plural(overdue, 'atrasada', 'atrasadas')}`);
  if (dueSoon) parts.push(`${dueSoon} perto do prazo`);
  return parts.join(' e ');
});

// board zerado (tudo FEITO): o anel TREME (tremor que antecede a explosão),
// os emojis explodem do centro e o anel fica pulsando VERDE.
// (declarado DEPOIS de stats: o watch avalia o computed já na montagem)
const allDone = computed(
  () =>
    stats.value.todo === 0 && stats.value.doing === 0 && stats.value.done > 0
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
const pickPraise = () =>
  PRAISE_BANK[Math.floor(Math.random() * PRAISE_BANK.length)];
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
  renewTicker = setInterval(() => {
    renewCountdown.value = Math.max(0, renewCountdown.value - 1);
  }, 1000);
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
        centerEmoji.value =
          CELEBRATION_EMOJIS[
            Math.floor(Math.random() * CELEBRATION_EMOJIS.length)
          ];
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
  const openTodo = visibleTasks.value.filter(
    x => x.status === 'todo' && !isOverdue(x)
  ).length;
  const openDoing = visibleTasks.value.filter(
    x => x.status === 'doing' && !isOverdue(x)
  ).length;
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
      datasets: [
        {
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
            const g = c.createLinearGradient(
              chartArea.left,
              chartArea.top,
              chartArea.left,
              chartArea.bottom
            );
            g.addColorStop(0, pair[1]);
            g.addColorStop(1, pair[0]);
            return g;
          },
          borderWidth: 0,
          borderRadius: 14, // pontas arredondadas até na parte "reta" das fatias
          spacing: 3,
          hoverOffset: 6,
        },
      ],
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
  store.dispatch('crm/fetchSettings').catch(() => {}); // paletas do kit
  fetchTasks();
  fetchNotes();
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
    const { data } = await TasksAPI.deleteAttachment(
      editingTask.value.id,
      att.id
    );
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
      due_at: form.value.due_at
        ? new Date(form.value.due_at).toISOString()
        : null,
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
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};
</script>

<template>
  <div
    class="cv-page flex flex-col h-full overflow-y-auto bg-n-surface-1"
    :style="cvVars"
  >
    <div class="max-w-[1600px] mx-auto w-full p-4 sm:p-6">
      <!-- hero do kit: título, efeito prático, contagens e o botão de criar -->
      <CevicoHero
        :pal="pal"
        :title="$t('TASKS.TITLE')"
        subtitle="O que a equipe precisa fazer, em três colunas: arraste cada cartão conforme avança e nada fica esquecido."
        icon="i-lucide-list-checks"
      >
        <template #chips>
          <span class="cevico-hero-chip">
            {{ stats.todo + stats.doing }}
            {{ plural(stats.todo + stats.doing, 'aberta', 'abertas') }}
          </span>
          <span class="cevico-hero-chip">
            <span class="i-lucide-check text-xs" />
            {{ stats.done }} {{ plural(stats.done, 'feita', 'feitas') }}
          </span>
          <span v-if="stats.overdue > 0" class="cevico-hero-chip">
            <span class="i-lucide-alert-triangle text-xs" />
            {{ stats.overdue }}
            {{ plural(stats.overdue, 'atrasada', 'atrasadas') }}
          </span>
          <span v-if="stats.dueSoon > 0" class="cevico-hero-chip">
            <span class="i-lucide-clock text-xs" />
            {{ stats.dueSoon }} perto do prazo
          </span>
        </template>
        <template #actions>
          <button
            class="cevico-hero-btn"
            title="Escrever um recado sobre um paciente"
            @click="showNoteModal = true"
          >
            <span class="i-lucide-sticky-note text-sm" />Nova nota
          </button>
          <button class="cevico-hero-btn cevico-hero-btn-on" @click="openCreate">
            <span class="i-lucide-plus text-sm" />{{ $t('TASKS.NEW') }}
          </button>
        </template>
      </CevicoHero>

      <!-- filtros: de quem são as tarefas — item 211: barra, seletor "Por
           pessoa" e contagem com a MESMA altura (36 px) e os mesmos cantos -->
      <div class="flex items-center gap-2 flex-wrap mb-4">
        <span class="cv-seg !rounded-xl">
          <button
            class="cv-seg-item !rounded-[9px]"
            :class="{ 'cv-seg-on': filterAssignee === 'me' }"
            @click="filterAssignee = 'me'"
          >
            <span class="i-lucide-user text-xs" />{{ $t('TASKS.FILTER.MINE') }}
          </button>
          <button
            class="cv-seg-item !rounded-[9px]"
            :class="{ 'cv-seg-on': filterAssignee === '' }"
            @click="filterAssignee = ''"
          >
            <span class="i-lucide-users text-xs" />{{ $t('TASKS.FILTER.ALL') }}
          </button>
        </span>
        <select
          v-if="isAdmin"
          v-model="agentFilter"
          class="cv-input !h-9 !w-auto text-xs font-medium text-n-slate-12 max-w-full min-w-[160px]"
        >
          <option value="">Por pessoa…</option>
          <option
            v-for="agent in agents"
            :key="agent.id"
            :value="String(agent.id)"
          >
            {{ agent.name }}
          </option>
        </select>
        <span class="cv-chip cv-chip-lg !h-9 !rounded-xl ml-auto">
          {{ visibleTasks.length }}
          {{ plural(visibleTasks.length, 'tarefa', 'tarefas') }}
        </span>
      </div>

      <!-- aviso de prazo: faixa colorida do kit (vermelha se há atrasadas) -->
      <div
        v-if="!isLoading && deadlineNote"
        class="cv-block cv-strip px-4 py-3 mb-4 flex items-center gap-3 flex-wrap"
        :class="stats.overdue > 0 ? 'cv-red' : 'cv-amber'"
      >
        <span class="cv-icon cv-icon-sm">
          <span
            :class="
              stats.overdue > 0 ? 'i-lucide-alert-triangle' : 'i-lucide-clock'
            "
            class="text-sm"
          />
        </span>
        <p class="text-sm text-n-slate-11 min-w-0 flex-1 break-words">
          <strong class="text-n-slate-12">{{ deadlineNote }}</strong> — abra o
          cartão para ajustar o prazo ou arraste para Feito.
        </p>
      </div>

      <!-- Loading -->
      <SkeletonScreen v-if="isLoading" variant="board" />

      <!-- quadro: colunas que EMBRULHAM em linhas (nunca rola de lado) + resumo -->
      <div
        v-else
        class="grid gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
      >
        <!-- board 100% feito: as colunas vestem o DOURADO (cv-gold) no lugar da paleta -->
        <section
          v-for="statusKey in STATUSES"
          :key="statusKey"
          class="cv-block p-4 min-w-0 flex flex-col"
          :class="allDone ? 'cv-gold' : ''"
          :style="allDone ? undefined : blockVars(statusKey)"
        >
          <!-- item 211: ícone, título e número na MESMA linha de base -->
          <header class="flex items-center gap-2.5 mb-3 min-h-[30px]">
            <span class="cv-icon cv-icon-sm">
              <span :class="BLOCK_ICON[statusKey]" class="text-sm" />
            </span>
            <h2
              class="text-base sm:text-lg font-bold tracking-tight text-n-slate-12 leading-none min-w-0 break-words"
            >
              {{ $t(`TASKS.COLUMNS.${statusKey.toUpperCase()}`) }}
            </h2>
            <span class="cv-chip cv-chip-lg !h-[26px] ml-auto tabular-nums">{{
              lists[statusKey].length
            }}</span>
          </header>

          <p
            v-if="!lists[statusKey].length"
            class="text-xs text-n-slate-9 text-center py-3 px-2 break-words"
          >
            Nenhuma tarefa aqui — arraste um cartão ou crie uma nova.
          </p>

          <!-- o draggable continua sendo o pai direto dos cartões -->
          <draggable
            v-model="lists[statusKey]"
            group="tasks"
            item-key="id"
            :animation="150"
            ghost-class="opacity-40"
            class="flex flex-col gap-2.5 flex-1 min-h-16"
            @change="onColumnChange(statusKey, $event)"
          >
            <template #item="{ element: task }">
              <div
                class="cv-sub cv-sub-hover rounded-2xl p-4 flex flex-col gap-2 min-w-0 cursor-pointer select-none"
                @click="openEdit(task)"
              >
                <!-- título inteiro, sempre visível -->
                <p
                  class="text-sm font-semibold text-n-slate-12 leading-snug break-words min-w-0"
                  :class="
                    task.status === 'done' ? 'line-through opacity-60' : ''
                  "
                >
                  {{ task.title }}
                </p>

                <!-- linha de contexto: responsável · prazo · quem criou -->
                <div
                  v-if="task.assignee || task.due_at || task.creator"
                  class="flex items-center gap-x-3 gap-y-1 flex-wrap text-xs text-n-slate-10 min-w-0"
                >
                  <span
                    v-if="task.assignee"
                    class="inline-flex items-center gap-1 min-w-0 break-words"
                  >
                    <span class="i-lucide-user text-[11px] flex-shrink-0" />
                    {{ task.assignee.name }}
                  </span>
                  <span
                    v-if="task.due_at"
                    class="inline-flex items-center gap-1"
                    :class="
                      isOverdue(task)
                        ? 'text-red-600 dark:text-red-400 font-semibold'
                        : isDueSoon(task)
                          ? 'text-amber-700 dark:text-amber-400 font-semibold'
                          : ''
                    "
                  >
                    <span
                      class="i-lucide-calendar-clock text-[11px] flex-shrink-0"
                    />
                    {{ formatDue(task.due_at) }}
                  </span>
                  <span
                    v-if="task.creator && task.creator.id !== task.assignee?.id"
                    class="text-n-slate-9"
                    :title="$t('TASKS.CREATED_BY', { name: task.creator.name })"
                  >
                    {{ $t('TASKS.BY') }} {{ task.creator.name.split(' ')[0] }}
                  </span>
                </div>

                <!-- chips: prioridade, situação do prazo, tipo, anexos -->
                <div class="flex items-center gap-1.5 flex-wrap">
                  <span class="cv-chip" :class="PRIORITY_STYLES[task.priority]">
                    {{ $t(`TASKS.PRIORITY.${task.priority.toUpperCase()}`) }}
                  </span>
                  <span v-if="task.status === 'done'" class="cv-chip cv-green">
                    <span class="i-lucide-check text-[11px]" />Concluída
                  </span>
                  <span v-else-if="isOverdue(task)" class="cv-chip cv-red">
                    <span class="i-lucide-alert-triangle text-[11px]" />Atrasada
                  </span>
                  <span v-else-if="isDueSoon(task)" class="cv-chip cv-amber">
                    <span class="i-lucide-clock text-[11px]" />{{
                      $t('TASKS.STATS.DUE_SOON')
                    }}
                  </span>
                  <span v-if="task.task_type" class="cv-chip cv-slate">
                    {{ task.task_type }}
                  </span>
                  <span
                    v-if="task.attachments?.length"
                    class="cv-chip cv-slate"
                    :title="$t('TASKS.ATTACH.TITLE')"
                  >
                    <span class="i-lucide-paperclip text-[11px]" />{{
                      task.attachments.length
                    }}
                  </span>
                </div>
              </div>
            </template>
          </draggable>
        </section>

        <!-- Painel de resumo (donut) — só desktop, como antes -->
        <section
          class="cv-block p-4 min-w-0 hidden lg:flex flex-col"
          :class="allDone ? 'cv-gold cevico-all-done-ring' : ''"
          :style="allDone ? undefined : blockVars('resumo')"
        >
          <header class="flex items-center gap-2.5 mb-1 min-h-[30px]">
            <span class="cv-icon cv-icon-sm">
              <span class="i-lucide-pie-chart text-sm" />
            </span>
            <h2
              class="text-base sm:text-lg font-bold tracking-tight text-n-slate-12 leading-none"
            >
              {{ $t('TASKS.DASHBOARD.TITLE') }}
            </h2>
          </header>
          <p class="text-xs text-n-slate-10 mb-4">
            {{ $t('TASKS.DASHBOARD.SUBTITLE') }}
          </p>

          <!-- O DONUT é o anel: fecha verde → TREME → explosão do centro →
               fica DOURADO pulsando (como os ícones da sidebar) -->
          <div
            v-if="donutChart"
            class="h-48 relative"
            :class="{
              'cevico-ring-tremor': ringPhase === 'tremor',
              'cevico-donut-gold': ringPhase === 'gold',
            }"
          >
            <!-- névoa de partículas douradas circulando com o donut -->
            <span
              v-for="p in ringPhase === 'gold' ? mistParticles : []"
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
            <div
              class="h-full"
              :class="ringPhase === 'gold' ? 'cevico-donut-spin' : ''"
            >
              <Doughnut :data="donutChart.data" :options="donutChart.options" />
            </div>
            <!-- o emoji da explosão mora no CENTRO do donut -->
            <span
              v-if="ringPhase === 'gold' && centerEmoji"
              class="absolute inset-0 flex items-center justify-center text-4xl pointer-events-none"
            >
              {{ centerEmoji }}
            </span>
            <!-- explosão a partir do CENTRO do anel -->
            <span
              v-for="c in showCelebration && burstOrigin === 'ring'
                ? burstPieces
                : []"
              :key="'ring' + c.id"
              class="cevico-burst-emoji"
              :style="{
                '--dx': c.dx + 'px',
                '--dy': c.dy + 'px',
                '--rot': c.rot + 'deg',
                fontSize: c.size + 'px',
                animationDelay: c.delay + 's',
              }"
            >
              {{ c.emoji }}
            </span>
          </div>
          <!-- legenda própria: 2 de cada lado, dourada junto com a explosão -->
          <div
            v-if="donutChart"
            class="grid grid-cols-2 gap-x-5 gap-y-1.5 w-fit mx-auto mt-3"
          >
            <span
              v-for="item in donutLegend"
              :key="item.label"
              class="flex items-center gap-1.5 text-[11px] transition-colors"
              :class="ringPhase === 'gold' ? '' : 'text-n-slate-10'"
              :style="ringPhase === 'gold' ? { color: '#D4A017' } : {}"
            >
              <span
                class="w-2.5 h-2.5 rounded-full transition-colors"
                :style="{ backgroundColor: item.color }"
              />
              {{ item.label }}
            </span>
          </div>
          <div
            v-if="!donutChart"
            class="h-56 flex flex-col items-center justify-center text-n-slate-10 gap-2"
          >
            <span class="i-lucide-pie-chart text-3xl" />
            <span class="text-xs">{{ $t('TASKS.DASHBOARD.EMPTY') }}</span>
          </div>
          <div v-if="allDone" class="text-center mt-3 space-y-1 flex-shrink-0">
            <p class="text-xs font-semibold leading-snug cevico-gold-text">
              Parabéns, 100% das tarefas concluídas.
            </p>
            <!-- elogio ALEATÓRIO do banco de elogios, com destaque -->
            <p
              class="text-lg font-black tracking-wide leading-snug flex items-center justify-center gap-1.5 flex-wrap cevico-gold-deep"
            >
              <span class="i-lucide-sparkles text-base flex-shrink-0" />{{
                praise
              }}
            </p>
            <!-- item 95: renovação automática do ambiente -->
            <div
              v-if="renewCountdown > 0"
              class="flex items-center justify-center gap-1.5 pt-1 flex-wrap"
            >
              <span class="cv-chip cv-gold">
                <span class="i-lucide-timer text-[11px]" />tela nova em
                {{ renewLabel }}
              </span>
              <button
                class="cv-btn cv-btn-sm cv-gold"
                title="Mover as concluídas pra coluna oculta agora"
                @click="renewNow"
              >
                Renovar agora
              </button>
            </div>
          </div>

          <!-- Números-chave em vidro (cor só no fio): FEITO verde (dourado
               pulsando no 100%), ATRASADAS vermelho quando há alguma -->
          <div class="grid grid-cols-2 gap-2.5 mt-4 flex-shrink-0">
            <div
              class="cv-sub rounded-2xl p-3 text-center"
              :class="allDone ? 'cv-gold cevico-tile-gold-pulse' : 'cv-green'"
            >
              <p class="text-xl font-bold text-n-slate-12 leading-tight">
                {{ stats.done }}
              </p>
              <p class="text-[11px] text-n-slate-10 mt-0.5">
                {{ $t('TASKS.COLUMNS.DONE') }}
              </p>
            </div>
            <div class="cv-sub rounded-2xl p-3 text-center">
              <p class="text-xl font-bold text-n-slate-12 leading-tight">
                {{ stats.doing }}
              </p>
              <p class="text-[11px] text-n-slate-10 mt-0.5">
                {{ $t('TASKS.COLUMNS.DOING') }}
              </p>
            </div>
            <div class="cv-sub rounded-2xl p-3 text-center">
              <p class="text-xl font-bold text-n-slate-12 leading-tight">
                {{ stats.todo }}
              </p>
              <p class="text-[11px] text-n-slate-10 mt-0.5">
                {{ $t('TASKS.COLUMNS.TODO') }}
              </p>
            </div>
            <div
              class="cv-sub rounded-2xl p-3 text-center"
              :class="stats.overdue > 0 ? 'cv-red' : 'cv-slate'"
            >
              <p class="text-xl font-bold text-n-slate-12 leading-tight">
                {{ stats.overdue }}
              </p>
              <p class="text-[11px] text-n-slate-10 mt-0.5">
                {{ $t('TASKS.STATS.OVERDUE') }}
              </p>
            </div>
          </div>
        </section>
      </div>
    </div>

    <!-- 📝 NOTAS DOS PACIENTES (item 211): recados rápidos, da clínica inteira -->
    <div class="max-w-[1600px] mx-auto w-full px-4 sm:px-6 pb-6">
      <section class="cv-block p-4 sm:p-5" :style="blockVars('notas')">
        <header class="flex items-center gap-2.5 mb-1 min-h-[30px] flex-wrap">
          <span class="cv-icon cv-icon-sm">
            <span class="i-lucide-sticky-note text-sm" />
          </span>
          <h2
            class="text-base sm:text-lg font-bold tracking-tight text-n-slate-12 leading-none"
          >
            Notas dos pacientes
          </h2>
          <span class="cv-chip cv-chip-lg !h-[26px] tabular-nums">{{
            visibleNotes.length
          }}</span>
          <button class="cv-btn cv-btn-sm ml-auto" @click="showNoteModal = true">
            <span class="i-lucide-plus text-xs" />Nova nota
          </button>
        </header>
        <p class="text-xs text-n-slate-10 mb-3">
          recados rápidos sobre um paciente — a nota vai para a ficha, para o
          Espaço do Paciente e para o Meu Painel de quem cuida
        </p>
        <p
          v-if="!isLoadingNotes && !visibleNotes.length"
          class="text-xs text-n-slate-9 text-center py-4"
        >
          Nenhuma nota ainda{{
            filterAssignee ? ' desta pessoa' : ''
          }}. Escreva a primeira em "Nova nota".
        </p>
        <div
          v-else
          class="grid gap-2.5 grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 max-h-[26rem] overflow-y-auto pr-1"
        >
          <div
            v-for="note in visibleNotes"
            :key="note.id"
            class="cv-sub cv-sub-hover rounded-2xl p-3.5 flex flex-col gap-1.5 min-w-0"
          >
            <div class="flex items-center gap-2 min-w-0">
              <button
                class="text-sm font-semibold text-n-slate-12 truncate hover:underline text-left"
                title="Abrir o Espaço do Paciente"
                @click="openPatient(note)"
              >
                {{ note.contact?.name || 'Paciente' }}
              </button>
              <span class="text-[10px] text-n-slate-9 ml-auto whitespace-nowrap tabular-nums">{{
                fmtNoteAt(note.created_at)
              }}</span>
              <button
                v-if="note.mine || isAdmin"
                class="text-n-slate-9 hover:text-red-500"
                title="Apagar a nota"
                @click="deleteNote(note)"
              >
                <span class="i-lucide-trash-2 text-xs" />
              </button>
            </div>
            <p class="text-xs text-n-slate-11 leading-snug whitespace-pre-line break-words">
              {{ note.content }}
            </p>
            <p class="text-[10px] text-n-slate-9">
              por {{ note.author?.name?.split(' ')[0] || 'equipe' }}<template v-if="note.contact?.phone"> · {{ note.contact.phone }}</template>
            </p>
          </div>
        </div>
      </section>
    </div>

    <!-- modal: nova nota de paciente -->
    <div
      v-if="showNoteModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      @click.self="showNoteModal = false"
    >
      <div class="cv-modal w-full max-w-md flex flex-col" :style="blockVars('notas')">
        <div class="cv-modal-head flex items-center gap-3">
          <span class="cv-glass w-10 h-10 flex items-center justify-center flex-shrink-0">
            <span class="i-lucide-sticky-note text-base" />
          </span>
          <div class="flex-1 min-w-0">
            <p class="text-[11px] opacity-85">Notas dos pacientes</p>
            <h2 class="text-base font-bold leading-tight">Nova nota</h2>
          </div>
          <button class="cv-glass-btn cv-iconbtn flex-shrink-0" aria-label="Fechar" @click="showNoteModal = false">
            <span class="i-lucide-x text-base" />
          </button>
        </div>
        <div class="p-5">
          <PatientNoteForm @saved="onNoteSaved" @cancel="showNoteModal = false" />
        </div>
      </div>
    </div>

    <!-- anexo de imagem em tela cheia -->
    <div
      v-if="previewImage"
      class="fixed inset-0 z-[70] flex items-center justify-center p-6 cursor-zoom-out bg-black/80"
      @click="previewImage = null"
    >
      <img
        :src="previewImage"
        alt=""
        class="max-w-full max-h-full rounded-2xl shadow-2xl"
      />
      <button
        class="cv-glass-btn cv-iconbtn absolute top-4 right-4"
        aria-label="Fechar"
        @click="previewImage = null"
      >
        <span class="i-lucide-x text-base" />
      </button>
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
      >
        {{ c.emoji }}
      </span>
    </div>

    <!-- Modal criar/editar: concha sólida do kit (cv-modal) -->
    <div
      v-if="showModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      @click.self="showModal = false"
    >
      <div class="cv-modal w-full max-w-md max-h-[90vh] flex flex-col">
        <div class="cv-modal-head flex items-center gap-3">
          <span
            class="cv-glass w-10 h-10 flex items-center justify-center flex-shrink-0"
          >
            <span
              :class="editingTask ? 'i-lucide-pencil' : 'i-lucide-list-checks'"
              class="text-base"
            />
          </span>
          <div class="flex-1 min-w-0">
            <p class="text-[11px] opacity-85">{{ $t('TASKS.TITLE') }}</p>
            <h2 class="text-base font-bold leading-tight break-words">
              {{ editingTask ? $t('TASKS.EDIT') : $t('TASKS.NEW') }}
            </h2>
          </div>
          <button
            class="cv-glass-btn cv-iconbtn flex-shrink-0"
            aria-label="Fechar"
            @click="showModal = false"
          >
            <span class="i-lucide-x text-base" />
          </button>
        </div>

        <div class="flex-1 overflow-y-auto p-5 space-y-4">
          <div>
            <label class="cv-label block mb-1">
              {{ $t('TASKS.FORM.TITLE') }} *
            </label>
            <input
              v-model="form.title"
              class="cv-input w-full text-n-slate-12"
              :placeholder="$t('TASKS.FORM.TITLE_PLACEHOLDER')"
            />
          </div>

          <div>
            <label class="cv-label block mb-1">{{
              $t('TASKS.FORM.DESCRIPTION')
            }}</label>
            <textarea
              v-model="form.description"
              rows="3"
              class="cv-input w-full text-n-slate-12 resize-none"
            />
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <label class="cv-label block mb-1">{{
                $t('TASKS.FORM.TYPE')
              }}</label>
              <select
                v-model="form.task_type"
                class="cv-input w-full text-n-slate-12"
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
              <label class="cv-label block mb-1">{{
                $t('TASKS.FORM.PRIORITY')
              }}</label>
              <select
                v-model="form.priority"
                class="cv-input w-full text-n-slate-12"
              >
                <option value="low">{{ $t('TASKS.PRIORITY.LOW') }}</option>
                <option value="medium">
                  {{ $t('TASKS.PRIORITY.MEDIUM') }}
                </option>
                <option value="high">{{ $t('TASKS.PRIORITY.HIGH') }}</option>
                <option value="urgent">
                  {{ $t('TASKS.PRIORITY.URGENT') }}
                </option>
              </select>
            </div>

            <div>
              <label class="cv-label block mb-1">{{
                $t('TASKS.FORM.ASSIGNEE')
              }}</label>
              <select
                v-model="form.assignee_id"
                class="cv-input w-full text-n-slate-12"
              >
                <option
                  v-for="agent in agents"
                  :key="agent.id"
                  :value="agent.id"
                >
                  {{ agent.name }}
                </option>
              </select>
            </div>

            <div>
              <label class="cv-label block mb-1">{{
                $t('TASKS.FORM.DUE_AT')
              }}</label>
              <input
                v-model="form.due_at"
                type="datetime-local"
                class="cv-input w-full text-n-slate-12"
              />
            </div>
          </div>

          <div v-if="editingTask">
            <label class="cv-label block mb-1">{{
              $t('TASKS.FORM.STATUS')
            }}</label>
            <select
              v-model="form.status"
              class="cv-input w-full text-n-slate-12"
            >
              <option value="todo">{{ $t('TASKS.COLUMNS.TODO') }}</option>
              <option value="doing">{{ $t('TASKS.COLUMNS.DOING') }}</option>
              <option value="done">{{ $t('TASKS.COLUMNS.DONE') }}</option>
            </select>
          </div>

          <!-- Anexos: imagem/PDF/documento (criador ↔ responsável) -->
          <div class="border-t border-n-weak pt-4">
            <div class="flex items-center gap-2 mb-2 flex-wrap">
              <span class="cv-icon cv-icon-sm">
                <span class="i-lucide-paperclip text-xs" />
              </span>
              <p class="text-sm font-bold text-n-slate-12">
                {{ $t('TASKS.ATTACH.TITLE') }}
              </p>
              <span class="text-[11px] text-n-slate-9 break-words">{{
                $t('TASKS.ATTACH.HINT')
              }}</span>
            </div>
            <div
              v-if="
                (editingTask?.attachments?.length || 0) + pendingFiles.length
              "
              class="flex flex-wrap gap-2 mb-2"
            >
              <!-- já salvos na tarefa -->
              <div
                v-for="att in editingTask?.attachments || []"
                :key="`att-${att.id}`"
                class="relative group max-w-full"
              >
                <img
                  v-if="att.is_image"
                  :src="att.url"
                  :title="att.filename"
                  alt=""
                  class="w-16 h-16 rounded-xl object-cover border border-n-weak cursor-zoom-in"
                  @click="previewImage = att.url"
                />
                <a
                  v-else
                  :href="att.url"
                  target="_blank"
                  rel="noopener noreferrer"
                  :title="att.filename"
                  class="cv-sub rounded-xl px-3 py-2 flex items-center gap-1.5 text-xs text-n-slate-11 min-w-0"
                >
                  <span
                    class="i-lucide-file-text text-base text-n-slate-10 flex-shrink-0"
                  />
                  <span class="break-all min-w-0">{{ att.filename }}</span>
                </a>
                <button
                  class="absolute -top-1.5 -right-1.5 w-5 h-5 rounded-full bg-red-600 text-white shadow hidden group-hover:flex items-center justify-center"
                  :title="$t('TASKS.ATTACH.REMOVE')"
                  @click.stop="removeAttachment(att)"
                >
                  <span class="i-lucide-x text-[10px]" />
                </button>
              </div>
              <!-- escolhidos agora (sobem ao salvar) -->
              <div
                v-for="(p, i) in pendingFiles"
                :key="`pend-${i}`"
                class="relative group max-w-full"
              >
                <img
                  v-if="p.url"
                  :src="p.url"
                  :title="p.file.name"
                  alt=""
                  class="w-16 h-16 rounded-xl object-cover border border-dashed border-n-strong"
                />
                <div
                  v-else
                  :title="p.file.name"
                  class="cv-sub rounded-xl px-3 py-2 flex items-center gap-1.5 text-xs text-n-slate-11 min-w-0 !border-dashed"
                >
                  <span
                    class="i-lucide-file-text text-base text-n-slate-10 flex-shrink-0"
                  />
                  <span class="break-all min-w-0">{{ p.file.name }}</span>
                </div>
                <button
                  class="absolute -top-1.5 -right-1.5 w-5 h-5 rounded-full bg-red-600 text-white shadow hidden group-hover:flex items-center justify-center"
                  :title="$t('TASKS.ATTACH.REMOVE')"
                  @click.stop="removePending(i)"
                >
                  <span class="i-lucide-x text-[10px]" />
                </button>
              </div>
            </div>
            <button
              class="cv-btn cv-btn-sm cv-btn-ghost"
              :disabled="isUploadingFiles"
              @click="pickFiles"
            >
              <span class="i-lucide-plus text-xs" />
              {{
                isUploadingFiles
                  ? $t('TASKS.ATTACH.SENDING')
                  : $t('TASKS.ATTACH.ADD')
              }}
            </button>
            <input
              ref="fileInputEl"
              type="file"
              class="hidden"
              multiple
              :accept="ACCEPT_FILES"
              @change="onFilesPicked"
            />
            <p
              v-if="pendingFiles.length"
              class="text-[11px] text-n-slate-9 mt-1.5"
            >
              {{ $t('TASKS.ATTACH.ON_SAVE') }}
            </p>
          </div>

          <!-- Solicitações / ajuda: conversa entre quem criou e quem executa -->
          <div v-if="editingTask" class="border-t border-n-weak pt-4">
            <div class="flex items-center gap-2 mb-2 flex-wrap">
              <span class="cv-icon cv-icon-sm">
                <span class="i-lucide-messages-square text-xs" />
              </span>
              <p class="text-sm font-bold text-n-slate-12">
                Solicitações e ajuda
              </p>
              <span class="text-[11px] text-n-slate-9 break-words">
                entre {{ editingTask.creator?.name?.split(' ')[0] }} e
                {{
                  editingTask.assignee?.name?.split(' ')[0] || 'o responsável'
                }}
              </span>
            </div>
            <div
              v-if="editingTask.comments?.length"
              class="space-y-1.5 max-h-40 overflow-y-auto mb-2 pr-1"
            >
              <div
                v-for="(c, i) in editingTask.comments"
                :key="i"
                class="cv-sub rounded-xl px-3 py-2 text-xs"
                :class="c.user_id === currentUser.id ? 'cv-sub-on' : ''"
              >
                <p class="flex items-center gap-2 mb-0.5">
                  <span class="font-semibold text-n-slate-12">{{
                    c.name?.split(' ')[0]
                  }}</span>
                  <span class="text-[10px] text-n-slate-9 ml-auto">{{
                    fmtCommentAt(c.at)
                  }}</span>
                </p>
                <p class="text-n-slate-11 leading-snug break-words">
                  {{ c.text }}
                </p>
              </div>
            </div>
            <p v-else class="text-xs text-n-slate-9 mb-2">
              Precisa de esclarecimento ou quer avisar algo? Escreva aqui — fica
              registrado na tarefa.
            </p>
            <div class="flex gap-2">
              <input
                v-model="commentText"
                class="cv-input flex-1 min-w-0 text-n-slate-12"
                placeholder="Ex: consigo os telefones atualizados?"
                @keyup.enter="sendComment"
              />
              <button
                class="cv-btn !h-9 !px-3 flex-shrink-0"
                aria-label="Enviar"
                :disabled="!commentText.trim() || isSendingComment"
                @click="sendComment"
              >
                <span
                  :class="
                    isSendingComment
                      ? 'i-lucide-loader-2 animate-spin'
                      : 'i-lucide-send'
                  "
                  class="text-sm"
                />
              </button>
            </div>
          </div>
        </div>

        <div class="cv-modal-foot flex flex-col gap-2">
          <div class="flex gap-2">
            <button
              class="cv-btn cv-btn-lg flex-1"
              :disabled="!form.title.trim() || isSaving"
              @click="save"
            >
              {{ isSaving ? $t('TASKS.SAVING') : $t('TASKS.SAVE') }}
            </button>
            <button
              class="cv-btn cv-btn-ghost cv-btn-lg"
              @click="showModal = false"
            >
              {{ $t('TASKS.CANCEL') }}
            </button>
          </div>

          <!-- Delete (só na edição) -->
          <div v-if="editingTask">
            <button
              v-if="!showDeleteConfirm"
              class="cv-btn cv-btn-sm cv-btn-ghost cv-btn-danger w-full"
              @click="showDeleteConfirm = true"
            >
              <span class="i-lucide-trash-2 text-xs" />{{ $t('TASKS.DELETE') }}
            </button>
            <div v-else class="flex items-center gap-2 flex-wrap">
              <span class="text-xs text-n-slate-11 flex-1 min-w-0">{{
                $t('TASKS.DELETE_CONFIRM')
              }}</span>
              <button
                class="cv-btn cv-btn-sm cv-btn-danger-on"
                @click="removeTask"
              >
                {{ $t('TASKS.DELETE') }}
              </button>
              <button
                class="cv-btn cv-btn-sm cv-btn-ghost"
                @click="showDeleteConfirm = false"
              >
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
  0% {
    transform: translate(0, 0) rotate(0deg) scale(0.4);
    opacity: 1;
  }
  70% {
    opacity: 1;
  }
  100% {
    transform: translate(var(--dx), var(--dy)) rotate(var(--rot)) scale(1.1);
    opacity: 0;
  }
}

/* textos da festa do 100%: dourado do anel (claro) e o tom fundo */
.cevico-gold-text {
  color: #d4a017;
}
.cevico-gold-deep {
  color: #b8860b;
}

/* caixinha FEITO pulsando dourada no modo 100% */
.cevico-tile-gold-pulse {
  animation: cevico-tile-gold 2.2s ease-in-out infinite;
}
@keyframes cevico-tile-gold {
  0%,
  100% {
    box-shadow: 0 0 6px rgba(212, 160, 23, 0.35);
  }
  50% {
    box-shadow: 0 0 18px rgba(255, 200, 40, 0.7);
  }
}

/* board 100% feito: a CAIXA do resumo pulsa DOURADA (cor do anel) */
.cevico-all-done-ring {
  border-color: #d4a017 !important;
  animation: cevico-ring-pulse 2.2s ease-in-out infinite;
}
@keyframes cevico-ring-pulse {
  0%,
  100% {
    box-shadow: 0 0 8px rgba(212, 160, 23, 0.35);
  }
  50% {
    box-shadow: 0 0 22px rgba(255, 200, 40, 0.75);
  }
}

/* TREMOR que antecede a explosão (o donut sacode rapidinho) */
.cevico-ring-tremor {
  animation: cevico-ring-tremor 0.12s linear infinite;
}
@keyframes cevico-ring-tremor {
  0%,
  100% {
    transform: translate(0, 0) rotate(0deg);
  }
  25% {
    transform: translate(-2px, 1px) rotate(-1.5deg);
  }
  50% {
    transform: translate(2px, -1px) rotate(1.5deg);
  }
  75% {
    transform: translate(-1px, -2px) rotate(-1deg);
  }
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
  0% {
    transform: rotate(0deg);
  }
  100% {
    transform: rotate(720deg);
  }
}
@keyframes cevico-donut-spin {
  0% {
    transform: rotate(0deg);
  }
  100% {
    transform: rotate(360deg);
  }
}
/* sem glow no donut (pedido 18/07) — só a respiração sutil de opacidade;
   quem brilha é a névoa de partículas ao redor */
@keyframes cevico-donut-gold-pulse {
  0%,
  100% {
    opacity: 1;
  }
  50% {
    opacity: 0.9;
  }
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
