<script setup>
import { ref, computed, reactive, onMounted, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import draggable from 'vuedraggable';
import TasksAPI from 'dashboard/api/tasks';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const store = useStore();
const { t } = useI18n();

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

// ── Mini dashboard ─────────────────────────────────────────
const stats = computed(() => ({
  todo: visibleTasks.value.filter(x => x.status === 'todo').length,
  doing: visibleTasks.value.filter(x => x.status === 'doing').length,
  done: visibleTasks.value.filter(x => x.status === 'done').length,
  overdue: visibleTasks.value.filter(isOverdue).length,
}));

// ── Fetch ──────────────────────────────────────────────────
const fetchTasks = async () => {
  isLoading.value = true;
  try {
    const { data } = await TasksAPI.get();
    tasks.value = data;
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
  showModal.value = true;
};

const openEdit = task => {
  editingTask.value = task;
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
      const { data } = await TasksAPI.update(editingTask.value.id, payload);
      const idx = tasks.value.findIndex(x => x.id === data.id);
      if (idx !== -1) tasks.value.splice(idx, 1, data);
      useAlert(t('TASKS.SAVED'));
    } else {
      const { data } = await TasksAPI.create(payload);
      tasks.value.push(data);
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
    <div class="flex items-center gap-3 px-6 py-4 border-b border-n-weak flex-shrink-0 flex-wrap">
      <h1 class="text-lg font-semibold text-n-slate-12">{{ $t('TASKS.TITLE') }}</h1>

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
      </div>

      <div class="flex items-center gap-2 ml-auto">
        <!-- Filtro por pessoa -->
        <select
          v-model="filterAssignee"
          class="h-9 text-sm border border-n-weak rounded-lg px-2 bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
        >
          <option value="me">{{ $t('TASKS.FILTER.MINE') }}</option>
          <option value="">{{ $t('TASKS.FILTER.ALL') }}</option>
          <option v-for="agent in agents" :key="agent.id" :value="agent.id">{{ agent.name }}</option>
        </select>

        <button
          class="flex items-center gap-1.5 text-sm px-3 py-2 rounded-lg bg-n-brand text-white hover:bg-n-brand/90 transition-colors"
          @click="openCreate"
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

    <!-- Kanban -->
    <div v-else class="flex-1 min-h-0 overflow-x-auto p-6">
      <div class="flex gap-4 h-full min-w-max md:min-w-0 md:grid md:grid-cols-3">
        <div
          v-for="statusKey in STATUSES"
          :key="statusKey"
          class="flex flex-col bg-n-alpha-1 rounded-xl w-[80vw] md:w-auto flex-shrink-0 h-full min-h-0"
        >
          <!-- Column header -->
          <div class="flex items-center gap-2 px-3 py-2.5 border-b border-n-weak flex-shrink-0">
            <span :class="[COLUMN_STYLES[statusKey].icon, COLUMN_STYLES[statusKey].color]" class="text-sm" />
            <span class="text-sm font-semibold text-n-slate-12">{{ $t(`TASKS.COLUMNS.${statusKey.toUpperCase()}`) }}</span>
            <span class="text-xs text-n-slate-10 bg-n-alpha-2 rounded px-1.5 py-0.5">{{ lists[statusKey].length }}</span>
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
                  class="bg-n-solid-2 border rounded-xl p-3 mb-2 cursor-pointer hover:border-n-brand hover:shadow-sm transition-all select-none"
                  :class="isOverdue(task) ? 'border-red-400/60' : 'border-n-weak'"
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
                  </div>

                  <div v-if="task.due_at" class="mt-2">
                    <span
                      class="inline-flex items-center gap-1 text-[11px]"
                      :class="isOverdue(task) ? 'text-red-500 font-medium' : 'text-n-slate-9'"
                    >
                      <span class="i-lucide-calendar-clock text-[11px]" />
                      {{ formatDue(task.due_at) }}
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
              rows="3"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 resize-none focus:outline-none focus:border-n-brand"
            />
          </div>

          <div class="grid grid-cols-2 gap-3">
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
