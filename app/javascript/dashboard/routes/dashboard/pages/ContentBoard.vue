<script setup>
// PLANEJAMENTO DE CONTEÚDOS (workflow de marketing): cada peça de conteúdo
// (reels, carrossel, post, anúncio, página, e-mail) anda pelo fluxo
// ideia → copy → produção → revisão → publicado. Time inteiro usa.
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';

const store = useStore();
const teamAgents = useMapGetter('agents/getAgents');
const { isAdmin } = useAdmin();

const isLoading = ref(true);
const items = ref([]);

const STAGES = [
  { key: 'ideia', label: 'Ideias', icon: 'i-lucide-lightbulb', grad: 'linear-gradient(135deg, #5B21B6, #7C3AED)' },
  { key: 'copy', label: 'Copy', icon: 'i-lucide-pen-line', grad: 'linear-gradient(135deg, #0F5FA6, #1E7FBF)' },
  { key: 'producao', label: 'Em produção', icon: 'i-lucide-clapperboard', grad: 'linear-gradient(135deg, #B8860B, #D4A017)' },
  { key: 'revisao', label: 'Revisão', icon: 'i-lucide-eye', grad: 'linear-gradient(135deg, #9D174D, #F472B6)' },
  { key: 'publicado', label: 'Publicado', icon: 'i-lucide-check-check', grad: 'linear-gradient(135deg, #047857, #10B981)' },
];
const FORMATS = [
  { key: 'reels', label: 'Reels', color: '#DB2777' },
  { key: 'carrossel', label: 'Carrossel', color: '#7C3AED' },
  { key: 'post', label: 'Post', color: '#0F5FA6' },
  { key: 'anuncio', label: 'Anúncio', color: '#EA580C' },
  { key: 'pagina', label: 'Página', color: '#0D9488' },
  { key: 'email', label: 'E-mail', color: '#64748B' },
];
const formatOf = key => FORMATS.find(f => f.key === key) || FORMATS[2];

const byStage = computed(() => {
  const map = {};
  STAGES.forEach(s => {
    map[s.key] = items.value.filter(i => i.stage === s.key);
  });
  return map;
});

const load = async () => {
  try {
    const { data } = await CrmAPI.getContentItems();
    items.value = data.items || [];
  } catch {
    useAlert('Não consegui carregar o planejamento.');
  } finally {
    isLoading.value = false;
  }
};

// ── criar rápido (input no topo de cada coluna) ──
const drafts = ref({});
const draftFor = stage => {
  if (!drafts.value[stage]) drafts.value[stage] = { title: '', format: 'post' };
  return drafts.value[stage];
};
const addItem = async stage => {
  const draft = draftFor(stage);
  if (!draft.title.trim()) return;
  try {
    const { data } = await CrmAPI.createContentItem({ title: draft.title.trim(), format: draft.format, stage });
    items.value.push(data);
    draft.title = '';
  } catch {
    useAlert('Não consegui criar.');
  }
};

// ── mover pelo fluxo (setas ← →) ──
const stageIndex = key => STAGES.findIndex(s => s.key === key);
const moveItem = async (item, dir) => {
  const idx = stageIndex(item.stage) + dir;
  if (idx < 0 || idx >= STAGES.length) return;
  const before = item.stage;
  item.stage = STAGES[idx].key;
  try {
    await CrmAPI.updateContentItem(item.id, { stage: item.stage });
  } catch {
    item.stage = before;
    useAlert('Não consegui mover.');
  }
};

// ── detalhes (expande no clique) ──
const expanded = ref(null);
const saveItem = async item => {
  try {
    await CrmAPI.updateContentItem(item.id, {
      title: item.title, format: item.format, owner_id: item.owner_id || null,
      due_on: item.due_on || null, notes: item.notes,
    });
  } catch {
    useAlert('Não consegui salvar.');
  }
};
const deleteItem = async item => {
  if (!window.confirm(`Excluir "${item.title}"?`)) return;
  try {
    await CrmAPI.deleteContentItem(item.id);
    items.value = items.value.filter(i => i.id !== item.id);
  } catch {
    useAlert('Só administradores excluem conteúdos.');
  }
};

const agentName = id => {
  const a = teamAgents.value.find(u => u.id === Number(id));
  return a ? (a.available_name || a.name).split(' ')[0] : null;
};
const overdue = item => item.due_on && item.stage !== 'publicado' && new Date(`${item.due_on}T23:59:59`) < new Date();
const fmtDue = d => new Date(`${d}T12:00:00`).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });

onMounted(() => {
  if (!teamAgents.value.length) store.dispatch('agents/get');
  load();
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-hidden bg-n-surface-1">
    <div class="p-4 sm:px-8 sm:pt-6 pb-2">
      <div class="flex items-center gap-3 flex-wrap">
        <span class="w-9 h-9 rounded-xl flex items-center justify-center" style="background: linear-gradient(135deg, #7C3AED, #DB2777)">
          <span class="i-lucide-kanban text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-lg font-bold text-n-slate-12">Planejamento de conteúdos</h1>
          <p class="text-xs text-n-slate-10">o fluxo das peças de marketing: ideia → copy → produção → revisão → publicado</p>
        </div>
      </div>
    </div>

    <div v-if="isLoading" class="flex justify-center py-16">
      <Spinner :size="32" class="text-n-brand" />
    </div>

    <!-- board: colunas deslizáveis (desktop e mobile) -->
    <div v-else class="flex-1 overflow-x-auto overflow-y-hidden px-4 sm:px-8 pb-4">
      <div class="flex gap-3 h-full min-w-max">
        <div
          v-for="stage in STAGES"
          :key="stage.key"
          class="w-64 flex-shrink-0 flex flex-col rounded-2xl bg-n-solid-2 border border-n-weak overflow-hidden"
        >
          <div class="px-3 py-2 flex items-center gap-2 text-white" :style="{ background: stage.grad }">
            <span :class="stage.icon" class="text-sm" />
            <span class="text-xs font-bold flex-1">{{ stage.label }}</span>
            <span class="text-[10px] font-bold bg-white/20 rounded-full px-1.5 py-0.5">{{ byStage[stage.key].length }}</span>
          </div>

          <div class="p-2 flex-1 overflow-y-auto">
            <!-- criar rápido -->
            <div class="flex items-center gap-1 mb-2">
              <input
                v-model="draftFor(stage.key).title"
                type="text"
                placeholder="Nova peça…"
                class="flex-1 min-w-0 h-7 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-[11px] text-n-slate-12"
                @keyup.enter="addItem(stage.key)"
              />
              <button
                class="w-7 h-7 rounded-lg text-white flex items-center justify-center flex-shrink-0 disabled:opacity-40"
                :style="{ background: stage.grad }"
                :disabled="!draftFor(stage.key).title.trim()"
                @click="addItem(stage.key)"
              >
                <span class="i-lucide-plus text-xs" />
              </button>
            </div>

            <!-- cards -->
            <div
              v-for="item in byStage[stage.key]"
              :key="item.id"
              class="rounded-xl border border-n-weak bg-n-solid-1 mb-1.5 overflow-hidden"
            >
              <div class="px-2.5 py-2 cursor-pointer hover:bg-n-alpha-1" @click="expanded = expanded === item.id ? null : item.id">
                <p class="text-xs font-semibold text-n-slate-12 leading-snug">{{ item.title }}</p>
                <div class="flex items-center gap-1.5 flex-wrap mt-1.5">
                  <span
                    class="text-[9px] font-bold px-1.5 py-0.5 rounded-full text-white"
                    :style="{ background: formatOf(item.format).color }"
                  >
                    {{ formatOf(item.format).label }}
                  </span>
                  <span v-if="item.owner_id && agentName(item.owner_id)" class="text-[10px] text-n-slate-10">{{ agentName(item.owner_id) }}</span>
                  <span
                    v-if="item.due_on"
                    class="inline-flex items-center gap-0.5 text-[10px] font-semibold ml-auto"
                    :style="{ color: overdue(item) ? '#DC2626' : '#94A3B8' }"
                  >
                    <span class="i-lucide-clock text-[10px]" /> {{ fmtDue(item.due_on) }}
                  </span>
                </div>
              </div>

              <!-- detalhes -->
              <div v-if="expanded === item.id" class="px-2.5 pb-2.5 pt-1 border-t border-n-weak space-y-1.5">
                <input v-model="item.title" type="text" class="w-full h-7 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[11px] text-n-slate-12" @change="saveItem(item)" />
                <div class="flex items-center gap-1 flex-wrap">
                  <button
                    v-for="f in FORMATS"
                    :key="f.key"
                    class="text-[9px] font-bold px-1.5 py-0.5 rounded-full border transition-all"
                    :style="item.format === f.key
                      ? { background: f.color, color: '#fff', borderColor: f.color }
                      : { borderColor: '#CBD5E1', color: '#64748B' }"
                    @click="item.format = f.key; saveItem(item)"
                  >
                    {{ f.label }}
                  </button>
                </div>
                <div class="flex items-center gap-1.5">
                  <select v-model="item.owner_id" class="h-7 rounded-lg border border-n-weak bg-n-solid-2 px-1 text-[10px] text-n-slate-12" style="width: 7.5rem" @change="saveItem(item)">
                    <option :value="null">Sem dono</option>
                    <option v-for="a in teamAgents" :key="a.id" :value="a.id">{{ a.available_name || a.name }}</option>
                  </select>
                  <input v-model="item.due_on" type="date" class="h-7 rounded-lg border border-n-weak bg-n-solid-2 px-1 text-[10px] text-n-slate-12" style="width: 7rem" @change="saveItem(item)" />
                </div>
                <textarea
                  v-model="item.notes"
                  rows="2"
                  placeholder="Roteiro, referências, link do drive…"
                  class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-2 py-1 text-[11px] text-n-slate-12 resize-y"
                  @change="saveItem(item)"
                />
                <div class="flex items-center gap-1">
                  <button
                    class="h-6 px-2 rounded-md border border-n-weak text-[10px] text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-30"
                    :disabled="stageIndex(item.stage) === 0"
                    @click="moveItem(item, -1)"
                  >
                    ← voltar
                  </button>
                  <button
                    class="h-6 px-2 rounded-md border border-n-weak text-[10px] font-semibold text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-30"
                    :disabled="stageIndex(item.stage) === STAGES.length - 1"
                    @click="moveItem(item, 1)"
                  >
                    avançar →
                  </button>
                  <button
                    v-if="isAdmin"
                    class="ml-auto w-6 h-6 rounded-md flex items-center justify-center text-red-500 hover:bg-red-500/10"
                    @click="deleteItem(item)"
                  >
                    <span class="i-lucide-trash-2 text-xs" />
                  </button>
                </div>
              </div>
            </div>

            <p v-if="!byStage[stage.key].length" class="text-[10px] text-n-slate-9 text-center py-3">
              nada aqui ainda
            </p>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
