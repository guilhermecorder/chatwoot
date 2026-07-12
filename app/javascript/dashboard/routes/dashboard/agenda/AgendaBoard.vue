<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import {
  startOfMonth, endOfMonth, startOfWeek, endOfWeek,
  addDays, addMonths, isSameDay, isSameMonth, format,
} from 'date-fns';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const store = useStore();
const { t } = useI18n();
const { isAdmin } = useAdmin();

const agents = useMapGetter('agents/getAgents');
const currentUser = useMapGetter('getCurrentUser');
const allTasks = useMapGetter('tasks/getTasks');

const isLoading = ref(true);
const cursor = ref(startOfMonth(new Date())); // mês exibido
// view: 'me' | '<agentId>' (admin) | 'unit:tatuape' | 'unit:paulista'
const view = ref('me');

const WEEKDAYS = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

// Unidades da clínica (agendas paralelas compartilhadas)
const UNITS = {
  tatuape:  { label: 'Tatuapé',     color: '#2563EB' }, // azul royal
  paulista: { label: 'Av. Paulista', color: '#EA580C' }, // laranja fogo
};

const PRIORITY_DOT = {
  low: '#94A3B8',
  medium: '#3B82F6',
  high: '#F59E0B',
  urgent: '#EF4444',
};

const activeUnit = computed(() =>
  view.value.startsWith('unit:') ? view.value.slice(5) : null
);

const dotColor = task =>
  task.unit && UNITS[task.unit] ? UNITS[task.unit].color : PRIORITY_DOT[task.priority];

const visibleTasks = computed(() => {
  const list = allTasks.value.filter(x => x.due_at);
  if (activeUnit.value) {
    return list.filter(x => x.unit === activeUnit.value);
  }
  if (view.value === 'me') {
    return list.filter(x => !x.unit && x.assignee?.id === currentUser.value.id);
  }
  // admin vê a agenda de uma pessoa específica (tarefas pessoais dela)
  return list.filter(x => !x.unit && x.assignee?.id === Number(view.value));
});

const tasksByDay = computed(() => {
  const map = {};
  visibleTasks.value.forEach(task => {
    const key = format(new Date(task.due_at), 'yyyy-MM-dd');
    (map[key] ||= []).push(task);
  });
  // ordena por hora dentro do dia
  Object.values(map).forEach(arr =>
    arr.sort((a, b) => new Date(a.due_at) - new Date(b.due_at))
  );
  return map;
});

// grade de 6 semanas (começa no domingo, como o Google Agenda em pt-BR)
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

const monthLabel = computed(() => {
  const label = cursor.value.toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' });
  return label.charAt(0).toUpperCase() + label.slice(1);
});

const dayTasks = day => tasksByDay.value[format(day, 'yyyy-MM-dd')] || [];
const isToday = day => isSameDay(day, new Date());
const inMonth = day => isSameMonth(day, cursor.value);
const isOverdue = task =>
  task.status !== 'done' && new Date(task.due_at) < new Date();

const prevMonth = () => { cursor.value = addMonths(cursor.value, -1); };
const nextMonth = () => { cursor.value = addMonths(cursor.value, 1); };
const goToday = () => { cursor.value = startOfMonth(new Date()); };

// ── Fetch ──────────────────────────────────────────────────
const fetchTasks = async () => {
  isLoading.value = true;
  try {
    await store.dispatch('tasks/fetch');
  } catch {
    useAlert(t('TASKS.ERROR'));
  } finally {
    isLoading.value = false;
  }
};

onMounted(() => {
  if (!agents.value.length) store.dispatch('agents/get');
  fetchTasks();
});

// ── Modal criar/editar ─────────────────────────────────────
const showModal = ref(false);
const editingTask = ref(null);
const isSaving = ref(false);
const showDeleteConfirm = ref(false);

const emptyForm = dueDate => ({
  title: '',
  description: '',
  priority: 'medium',
  status: 'todo',
  due_at: dueDate ? `${format(dueDate, 'yyyy-MM-dd')}T09:00` : '',
  assignee_id: currentUser.value.id,
  unit: activeUnit.value || '', // se estou numa unidade, já entra nela
});

const form = ref(emptyForm());

const toLocalInput = iso => {
  if (!iso) return '';
  const d = new Date(iso);
  const pad = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

const openCreateOnDay = day => {
  editingTask.value = null;
  form.value = emptyForm(day);
  showDeleteConfirm.value = false;
  showModal.value = true;
};

const openEdit = task => {
  editingTask.value = task;
  form.value = {
    title: task.title,
    description: task.description ?? '',
    priority: task.priority,
    status: task.status,
    due_at: toLocalInput(task.due_at),
    assignee_id: task.assignee?.id ?? currentUser.value.id,
    unit: task.unit ?? '',
  };
  showDeleteConfirm.value = false;
  showModal.value = true;
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
      await store.dispatch('tasks/update', { id: editingTask.value.id, ...payload });
      useAlert(t('TASKS.SAVED'));
    } else {
      await store.dispatch('tasks/create', payload);
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
    await store.dispatch('tasks/remove', editingTask.value.id);
    showModal.value = false;
    useAlert(t('TASKS.DELETED'));
  } catch {
    useAlert(t('TASKS.ERROR'));
  }
};

const chipTime = task =>
  new Date(task.due_at).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
</script>

<template>
  <div class="bg-n-surface-1 flex flex-col h-full w-full">
    <!-- Top bar -->
    <div class="flex items-center gap-3 px-6 py-4 border-b border-n-weak flex-shrink-0 flex-wrap">
      <h1 class="text-lg font-semibold text-n-slate-12">{{ $t('AGENDA.TITLE') }}</h1>

      <!-- Navegação de mês -->
      <div class="flex items-center gap-1 ml-2">
        <button
          class="w-8 h-8 flex items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-alpha-1 i-lucide-chevron-left"
          @click="prevMonth"
        />
        <span class="text-sm font-medium text-n-slate-12 min-w-[150px] text-center">{{ monthLabel }}</span>
        <button
          class="w-8 h-8 flex items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-alpha-1 i-lucide-chevron-right"
          @click="nextMonth"
        />
        <button
          class="ml-1 text-xs px-2.5 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
          @click="goToday"
        >
          {{ $t('AGENDA.TODAY') }}
        </button>
      </div>

      <div class="flex items-center gap-2 ml-auto flex-wrap">
        <!-- Legenda das unidades -->
        <div class="flex items-center gap-2 mr-1">
          <span
            v-for="(u, key) in UNITS"
            :key="key"
            class="flex items-center gap-1 text-[11px] text-n-slate-10"
          >
            <span class="w-2.5 h-2.5 rounded-full" :style="{ backgroundColor: u.color }" />
            {{ u.label }}
          </span>
        </div>

        <select
          v-model="view"
          class="h-9 text-sm border border-n-weak rounded-lg px-2 bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
        >
          <option value="me">{{ $t('TASKS.FILTER.MINE') }}</option>
          <optgroup :label="$t('AGENDA.UNITS')">
            <option v-for="(u, key) in UNITS" :key="key" :value="`unit:${key}`">{{ u.label }}</option>
          </optgroup>
          <optgroup v-if="isAdmin" :label="$t('AGENDA.PEOPLE')">
            <option v-for="agent in agents" :key="agent.id" :value="String(agent.id)">{{ agent.name }}</option>
          </optgroup>
        </select>
        <button
          class="flex items-center gap-1.5 text-sm px-3 py-2 rounded-lg bg-n-brand text-white hover:bg-n-brand/90 transition-colors"
          @click="openCreateOnDay(new Date())"
        >
          <span class="i-lucide-plus text-sm" />
          {{ $t('TASKS.NEW') }}
        </button>
      </div>
    </div>

    <!-- Loading -->
    <div v-if="isLoading" class="flex justify-center items-center flex-1">
      <Spinner :size="32" class="text-n-brand" />
    </div>

    <!-- Calendário mensal -->
    <div v-else class="flex-1 min-h-0 flex flex-col p-4">
      <!-- Cabeçalho dos dias da semana -->
      <div class="grid grid-cols-7 gap-px mb-px">
        <div
          v-for="wd in WEEKDAYS"
          :key="wd"
          class="text-center text-xs font-medium text-n-slate-10 py-1.5"
        >
          {{ wd }}
        </div>
      </div>

      <!-- Semanas -->
      <div class="flex-1 grid grid-rows-6 gap-px min-h-0">
        <div v-for="(week, wi) in weeks" :key="wi" class="grid grid-cols-7 gap-px min-h-0">
          <div
            v-for="day in week"
            :key="day.toISOString()"
            class="border border-n-weak rounded-lg p-1.5 flex flex-col min-h-0 overflow-hidden cursor-pointer transition-colors hover:border-n-brand/50"
            :class="inMonth(day) ? 'bg-n-solid-1' : 'bg-n-alpha-1 opacity-60'"
            @click="openCreateOnDay(day)"
          >
            <!-- Número do dia -->
            <div class="flex items-center justify-between flex-shrink-0 mb-1">
              <span
                class="text-xs w-5 h-5 flex items-center justify-center rounded-full"
                :class="isToday(day)
                  ? 'bg-n-brand text-white font-semibold'
                  : (inMonth(day) ? 'text-n-slate-11' : 'text-n-slate-9')"
              >
                {{ day.getDate() }}
              </span>
            </div>

            <!-- Chips de tarefas -->
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
                <span
                  class="w-1.5 h-1.5 rounded-full flex-shrink-0"
                  :style="{ backgroundColor: dotColor(task) }"
                />
                <span class="text-[10px] text-n-slate-9 flex-shrink-0">{{ chipTime(task) }}</span>
                <span class="truncate">{{ task.title }}</span>
              </button>
            </div>
          </div>
        </div>
      </div>
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
              rows="2"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 resize-none focus:outline-none focus:border-n-brand"
            />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">{{ $t('TASKS.FORM.DUE_AT') }}</label>
              <input
                v-model="form.due_at"
                type="datetime-local"
                class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-sm bg-n-solid-2 text-n-slate-12"
              />
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
                :disabled="!isAdmin"
                class="w-full border border-n-weak rounded-lg px-2 py-2 text-sm bg-n-solid-2 text-n-slate-12 disabled:opacity-60"
              >
                <option v-for="agent in agents" :key="agent.id" :value="agent.id">{{ agent.name }}</option>
              </select>
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">{{ $t('AGENDA.UNIT') }}</label>
              <select
                v-model="form.unit"
                class="w-full border border-n-weak rounded-lg px-2 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              >
                <option value="">{{ $t('AGENDA.PERSONAL') }}</option>
                <option v-for="(u, key) in UNITS" :key="key" :value="key">{{ u.label }}</option>
              </select>
            </div>
            <div>
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
          </div>
        </div>

        <div class="px-5 py-4 border-t border-n-weak flex-shrink-0 space-y-2">
          <div class="flex gap-2">
            <button
              class="flex-1 bg-n-brand text-white rounded-lg py-2 text-sm font-medium disabled:opacity-50"
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
