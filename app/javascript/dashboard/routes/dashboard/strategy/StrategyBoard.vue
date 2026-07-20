<script setup>
// Painel Estratégico CEVICO (só admin): a empresa estruturada por pilares —
// Aquisição de Pacientes, Operação Clínica, Financeiro/Tributário (e os que
// vierem). Cada pilar: responsáveis, semáforo de saúde, "como está" e as
// estratégias/ações corretivas com dono, prazo e andamento.
import { ref, computed, onMounted } from 'vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';
import BusinessPanel from './BusinessPanel.vue';

const store = useStore();
const teamAgents = useMapGetter('agents/getAgents');
const { isAdmin } = useAdmin();

const isLoading = ref(true);
const pillars = ref([]);
// abas do Estratégico: Pilares | 🏭 Desenho do Processo (item 59) |
// 🧭 Painel do Empresário (quadro de gestão do dono — só admin)
const activeTab = ref('pilares');
const business = ref(null);

// identidade CEVICO: gradientes oficiais por cor do pilar
const PILLAR_COLORS = {
  navy: { grad: 'linear-gradient(135deg, #152C61, #3B82F6)', solid: '#152C61' },
  gold: { grad: 'linear-gradient(135deg, #B8860B, #D4AF37)', solid: '#B8860B' },
  emerald: { grad: 'linear-gradient(135deg, #059669, #4ADE80)', solid: '#059669' },
  purple: { grad: 'linear-gradient(135deg, #5B21B6, #7C3AED)', solid: '#7C3AED' },
  rose: { grad: 'linear-gradient(135deg, #9D174D, #F472B6)', solid: '#BE185D' },
  slate: { grad: 'linear-gradient(135deg, #111827, #64748B)', solid: '#334155' },
};
const colorOf = p => PILLAR_COLORS[p.color] || PILLAR_COLORS.navy;

// semáforo de saúde do pilar (clique direto = decisão rápida) —
// bolinha colorida no lugar de emoji (pedido 17/07: maneirar nos emojis)
const PILLAR_STATUS = [
  { key: 'otimo', label: 'Saudável', dot: '#10B981', color: '#047857', bg: 'rgba(16,185,129,0.12)' },
  { key: 'atencao', label: 'Atenção', dot: '#F59E0B', color: '#B45309', bg: 'rgba(245,158,11,0.14)' },
  { key: 'critico', label: 'Crítico', dot: '#EF4444', color: '#B91C1C', bg: 'rgba(239,68,68,0.12)' },
];
const statusOf = p => PILLAR_STATUS.find(s => s.key === p.status) || PILLAR_STATUS[1];

// andamento das estratégias
const ITEM_STATUS = [
  { key: 'ideia', label: 'Ideia', color: '#6D28D9', bg: 'rgba(124,58,237,0.1)' },
  { key: 'andamento', label: 'Em andamento', color: '#1D4ED8', bg: 'rgba(59,130,246,0.1)' },
  { key: 'concluida', label: 'Concluída', color: '#047857', bg: 'rgba(16,185,129,0.12)' },
  { key: 'pausada', label: 'Pausada', color: '#64748B', bg: 'rgba(100,116,139,0.14)' },
];
const itemStatusOf = item => ITEM_STATUS.find(s => s.key === item.status) || ITEM_STATUS[1];
const ITEM_KINDS = [
  { key: 'estrategia', label: 'Estratégia', icon: 'i-lucide-target', color: '#3B82F6', hint: 'caminho escolhido para o pilar crescer' },
  { key: 'correcao', label: 'Correção', icon: 'i-lucide-wrench', color: '#D97706', hint: 'o que vamos fazer para corrigir o rumo' },
];
const kindOf = item => ITEM_KINDS.find(k => k.key === item.kind) || ITEM_KINDS[0];

const agentName = id => {
  const a = teamAgents.value.find(u => u.id === Number(id));
  return a ? (a.available_name || a.name) : null;
};
const ownersOf = p => (p.owner_ids || []).map(agentName).filter(Boolean);

// dopamine: barra de progresso do pilar (% de estratégias concluídas)
const progressOf = p => {
  const total = (p.items || []).length;
  if (!total) return null;
  const done = p.items.filter(i => i.status === 'concluida').length;
  return { done, total, pct: Math.round((done / total) * 100) };
};

const load = async () => {
  try {
    const { data } = await CrmAPI.getStrategyBoard();
    pillars.value = data.pillars || [];
    processes.value = data.processes || [];
    business.value = data.business || {};
    if (!selectedProcessId.value && processes.value.length) {
      selectedProcessId.value = processes.value[0].id;
    }
  } catch {
    useAlert('Não consegui carregar o Painel Estratégico.');
  } finally {
    isLoading.value = false;
  }
};

// ── 🏭 DESENHO DO PROCESSO (item 59): a máquina da clínica ──
// etapas conectadas com PASSE DE BASTÃO; clique = zoom na etapa
const processes = ref([]);
const selectedProcessId = ref('');
const selectedProcess = computed(
  () => processes.value.find(p => p.id === selectedProcessId.value) || null
);
const zoomStep = ref(null); // etapa aberta em zoom (leitura ou edição)
const editingProcess = ref(false); // modo de desenho (admin)
const savingProcess = ref(false);

const ownerName = id => agentName(id) || 'Sem dono definido';

const persistProcesses = async () => {
  savingProcess.value = true;
  try {
    const { data } = await CrmAPI.saveStrategyProcesses(processes.value);
    processes.value = data.processes || [];
    useAlert('Processo salvo — o time já vê o desenho novo. 🏭');
  } catch {
    useAlert('Não consegui salvar o processo.');
  } finally {
    savingProcess.value = false;
  }
};

const addProcess = () => {
  const proc = {
    id: `novo-${Date.now()}`,
    name: 'Novo processo',
    emoji: '🏭',
    steps: [{ id: `s-${Date.now()}`, title: 'Primeira etapa', desc: '', owner_id: null, handoff: '' }],
  };
  processes.value.push(proc);
  selectedProcessId.value = proc.id;
  editingProcess.value = true;
};
const removeProcess = () => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`Excluir o processo "${selectedProcess.value?.name}"?`)) return;
  processes.value = processes.value.filter(p => p.id !== selectedProcessId.value);
  selectedProcessId.value = processes.value[0]?.id || '';
  persistProcesses();
};
const addStep = () => {
  selectedProcess.value.steps.push({
    id: `s-${Date.now()}`, title: 'Nova etapa', desc: '', owner_id: null, handoff: '',
  });
};
const removeStep = idx => selectedProcess.value.steps.splice(idx, 1);
const moveStep = (idx, dir) => {
  const steps = selectedProcess.value.steps;
  const j = idx + dir;
  if (j < 0 || j >= steps.length) return;
  [steps[idx], steps[j]] = [steps[j], steps[idx]];
};

// ── editor do pilar (modal) ─────────────────────────────────
const editingPillar = ref(null); // cópia editável; null = fechado
const isNewPillar = ref(false);
const savingPillar = ref(false);

const openNewPillar = () => {
  isNewPillar.value = true;
  editingPillar.value = {
    name: '', subtitle: '', emoji: '🏛️', color: 'purple',
    status: 'atencao', health_note: '', owner_ids: [],
  };
};
const openEditPillar = p => {
  isNewPillar.value = false;
  editingPillar.value = JSON.parse(JSON.stringify(p));
};
const toggleOwner = id => {
  const list = editingPillar.value.owner_ids;
  const idx = list.indexOf(id);
  if (idx === -1) list.push(id);
  else list.splice(idx, 1);
};
const savePillar = async () => {
  const p = editingPillar.value;
  if (!p.name.trim()) return useAlert('Dê um nome ao pilar.');
  savingPillar.value = true;
  try {
    const payload = {
      name: p.name.trim(), subtitle: p.subtitle, emoji: p.emoji, color: p.color,
      status: p.status, health_note: p.health_note, owner_ids: p.owner_ids,
    };
    if (isNewPillar.value) {
      const { data } = await CrmAPI.createStrategyPillar(payload);
      pillars.value.push(data);
    } else {
      const { data } = await CrmAPI.updateStrategyPillar(p.id, payload);
      const idx = pillars.value.findIndex(x => x.id === p.id);
      if (idx !== -1) pillars.value[idx] = { ...pillars.value[idx], ...data };
    }
    editingPillar.value = null;
  } catch {
    useAlert('Não consegui salvar o pilar.');
  } finally {
    savingPillar.value = false;
  }
  return null;
};
const deletePillar = async () => {
  const p = editingPillar.value;
  if (!window.confirm(`Excluir o pilar "${p.name}" e todas as estratégias dele?`)) return;
  try {
    await CrmAPI.deleteStrategyPillar(p.id);
    pillars.value = pillars.value.filter(x => x.id !== p.id);
    editingPillar.value = null;
  } catch {
    useAlert('Não consegui excluir o pilar.');
  }
};

// semáforo direto no card (sem abrir o modal)
const setPillarStatus = async (p, status) => {
  const before = p.status;
  p.status = status;
  try {
    await CrmAPI.updateStrategyPillar(p.id, { status });
  } catch {
    p.status = before;
    useAlert('Não consegui mudar o status.');
  }
};

// ── estratégias/ações ───────────────────────────────────────
const newItem = ref({}); // por pilar: { [pillarId]: { title, kind } }
const draftFor = pillarId => {
  if (!newItem.value[pillarId]) newItem.value[pillarId] = { title: '', kind: 'estrategia' };
  return newItem.value[pillarId];
};
const addItem = async pillar => {
  const draft = draftFor(pillar.id);
  if (!draft.title.trim()) return;
  try {
    const { data } = await CrmAPI.createStrategyItem(pillar.id, {
      title: draft.title.trim(), kind: draft.kind, status: draft.kind === 'correcao' ? 'andamento' : 'ideia',
    });
    pillar.items.push(data);
    draft.title = '';
  } catch {
    useAlert('Não consegui adicionar.');
  }
};

const expandedItem = ref(null); // id do item aberto para detalhes
const toggleExpand = item => {
  expandedItem.value = expandedItem.value === item.id ? null : item.id;
};
const saveItem = async item => {
  try {
    await CrmAPI.updateStrategyItem(item.id, {
      title: item.title, description: item.description, status: item.status,
      kind: item.kind, owner_id: item.owner_id || null, due_on: item.due_on || null,
    });
  } catch {
    useAlert('Não consegui salvar a estratégia.');
  }
};
const cycleItemStatus = async item => {
  const order = ITEM_STATUS.map(s => s.key);
  const next = order[(order.indexOf(item.status) + 1) % order.length];
  item.status = next;
  await saveItem(item);
};
const deleteItem = async (pillar, item) => {
  if (!window.confirm(`Excluir "${item.title}"?`)) return;
  try {
    await CrmAPI.deleteStrategyItem(item.id);
    pillar.items = pillar.items.filter(i => i.id !== item.id);
  } catch {
    useAlert('Não consegui excluir.');
  }
};

const overdue = item =>
  item.due_on && item.status !== 'concluida' && new Date(`${item.due_on}T23:59:59`) < new Date();
const fmtDue = d => new Date(`${d}T12:00:00`).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });

onMounted(() => {
  if (!teamAgents.value.length) store.dispatch('agents/get');
  load();
});
</script>

<template>
  <div class="flex-1 overflow-auto bg-n-background">
    <div class="max-w-[1400px] mx-auto p-4 sm:p-6">
      <!-- cabeçalho: identidade navy+ouro -->
      <div class="flex items-center gap-3 mb-1 flex-wrap">
        <span
          class="w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0 shadow-md"
          style="background: linear-gradient(135deg, #152C61, #3B82F6)"
        >
          <span class="i-lucide-compass text-white text-xl" />
        </span>
        <div class="flex-1 min-w-[220px]">
          <h1 class="text-lg font-bold text-n-slate-12">Painel Estratégico</h1>
          <p class="text-xs text-n-slate-10">
            A CEVICO estruturada pelos pilares do negócio — responsáveis, saúde e o que vamos fazer em cada um.
          </p>
        </div>
        <button
          v-if="activeTab === 'pilares'"
          class="flex items-center gap-1.5 text-xs font-semibold text-white px-3.5 h-9 rounded-xl hover:opacity-90 shadow-sm"
          style="background: linear-gradient(135deg, #152C61, #3B82F6)"
          @click="openNewPillar"
        >
          <span class="i-lucide-plus text-sm" />
          Novo pilar
        </button>
      </div>

      <!-- abas: Pilares | Desenho do Processo (item 59) -->
      <div class="flex items-center gap-1 bg-n-solid-2 border border-n-weak rounded-xl p-1 w-fit mt-3">
        <button
          class="px-3 h-8 rounded-lg text-xs font-medium transition-colors flex items-center gap-1.5"
          :class="activeTab === 'pilares' ? 'text-white font-bold' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="activeTab === 'pilares' ? 'background: linear-gradient(135deg, #152C61, #3B82F6)' : ''"
          @click="activeTab = 'pilares'"
        >
          <span class="i-lucide-columns-3 text-sm" /> Pilares
        </button>
        <button
          class="px-3 h-8 rounded-lg text-xs font-medium transition-colors flex items-center gap-1.5"
          :class="activeTab === 'processo' ? 'text-white font-bold' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="activeTab === 'processo' ? 'background: linear-gradient(135deg, #B8860B, #D4AF37)' : ''"
          @click="activeTab = 'processo'"
        >
          <span class="i-lucide-factory text-sm" /> Desenho do Processo
        </button>
        <button
          v-if="isAdmin"
          class="px-3 h-8 rounded-lg text-xs font-medium transition-colors flex items-center gap-1.5"
          :class="activeTab === 'empresario' ? 'text-white font-bold' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="activeTab === 'empresario' ? 'background: linear-gradient(135deg, #C2410C, #F97316)' : ''"
          @click="activeTab = 'empresario'"
        >
          <span class="i-lucide-briefcase text-sm" /> Painel do Empresário
        </button>
      </div>

      <SkeletonScreen v-if="isLoading" variant="board" />

      <!-- ══ 🧭 PAINEL DO EMPRESÁRIO ══ o quadro de gestão do dono (só admin) -->
      <div v-else-if="activeTab === 'empresario' && isAdmin" class="mt-4">
        <BusinessPanel :initial="business" />
      </div>

      <!-- ══ 🏭 DESENHO DO PROCESSO ══ a máquina da clínica, etapa a etapa -->
      <div v-else-if="activeTab === 'processo'" class="mt-4">
        <div class="flex items-center gap-2 flex-wrap mb-4">
          <button
            v-for="p in processes"
            :key="p.id"
            class="px-3 h-8 rounded-full text-xs font-medium border transition-colors flex items-center gap-1.5"
            :class="selectedProcessId === p.id ? 'text-white border-transparent font-bold' : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
            :style="selectedProcessId === p.id ? 'background: linear-gradient(135deg, #B8860B, #D4AF37)' : ''"
            @click="selectedProcessId = p.id"
          >
            {{ p.emoji }} {{ p.name }}
          </button>
          <button
            v-if="isAdmin"
            class="px-3 h-8 rounded-full text-xs font-medium border border-dashed border-n-weak text-n-slate-10 hover:bg-n-alpha-1 flex items-center gap-1"
            @click="addProcess"
          >
            <span class="i-lucide-plus text-xs" /> Criar processo
          </button>
          <div class="flex-1" />
          <template v-if="isAdmin && selectedProcess">
            <button
              class="px-3 h-8 rounded-xl text-xs font-bold transition-colors"
              :class="editingProcess ? 'text-white' : 'border border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
              :style="editingProcess ? 'background: linear-gradient(135deg, #B8860B, #D4AF37)' : ''"
              @click="editingProcess = !editingProcess"
            >
              {{ editingProcess ? '✓ Visualizar' : '✏️ Desenhar' }}
            </button>
            <button
              v-if="editingProcess"
              class="px-3 h-8 rounded-xl text-xs font-bold text-white disabled:opacity-60"
              style="background: linear-gradient(135deg, #047857, #34D399)"
              :disabled="savingProcess"
              @click="persistProcesses"
            >
              {{ savingProcess ? 'Salvando…' : 'Salvar processo' }}
            </button>
            <button
              v-if="editingProcess && processes.length > 1"
              class="w-8 h-8 rounded-xl border border-n-weak text-n-slate-10 hover:text-red-500 flex items-center justify-center"
              title="Excluir este processo"
              @click="removeProcess"
            >
              <span class="i-lucide-trash-2 text-sm" />
            </button>
          </template>
        </div>

        <div v-if="selectedProcess" class="bg-n-card outline outline-1 outline-n-container rounded-2xl p-5 overflow-x-auto">
          <input
            v-if="editingProcess"
            v-model="selectedProcess.name"
            class="text-sm font-bold text-n-slate-12 bg-n-solid-2 border border-n-weak rounded-lg px-2 h-8 mb-4"
            style="width: 20rem; margin-bottom: 1rem"
          />
          <!-- a MÁQUINA: etapas conectadas pelo passe de bastão -->
          <div class="flex items-stretch gap-0 min-w-max pb-2">
            <template v-for="(s, si) in selectedProcess.steps" :key="s.id">
              <button
                class="w-60 flex-shrink-0 rounded-2xl border-2 text-left p-3.5 transition-all hover:shadow-md hover:-translate-y-0.5"
                style="border-color: rgba(184, 134, 11, 0.35); background: rgba(184, 134, 11, 0.05)"
                title="Clique para dar zoom nesta etapa"
                @click="zoomStep = s"
              >
                <div class="flex items-center gap-1.5 mb-1">
                  <span
                    class="w-6 h-6 rounded-full flex items-center justify-center text-[10px] font-black text-white flex-shrink-0"
                    style="background: linear-gradient(135deg, #B8860B, #D4AF37)"
                  >{{ si + 1 }}</span>
                  <p class="text-xs font-bold text-n-slate-12 leading-tight">{{ s.title }}</p>
                </div>
                <p class="text-[11px] text-n-slate-10 leading-snug line-clamp-3">{{ s.desc || '—' }}</p>
                <p class="text-[10px] font-semibold mt-1.5" style="color: #92600A">
                  <span class="i-lucide-user-round text-[10px]" /> {{ ownerName(s.owner_id) }}
                </p>
              </button>
              <!-- passe de bastão -->
              <div v-if="si < selectedProcess.steps.length - 1" class="flex flex-col items-center justify-center px-2 flex-shrink-0 w-28">
                <span class="i-lucide-arrow-right text-xl" style="color: #B8860B" />
                <span class="text-[9px] text-center leading-tight mt-0.5 text-n-slate-9">{{ s.handoff || 'passe de bastão' }}</span>
              </div>
            </template>
            <button
              v-if="editingProcess"
              class="w-14 flex-shrink-0 rounded-2xl border-2 border-dashed border-n-weak text-n-slate-9 hover:text-n-slate-11 hover:bg-n-alpha-1 flex items-center justify-center ml-2"
              title="Adicionar etapa"
              @click="addStep"
            >
              <span class="i-lucide-plus text-lg" />
            </button>
          </div>
          <p class="text-[10px] text-n-slate-9 mt-2">
            clique numa etapa para dar ZOOM — descrição completa, responsável e o passe de bastão para a próxima.
          </p>
        </div>

        <!-- ZOOM da etapa -->
        <div
          v-if="zoomStep"
          class="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4"
          @click.self="zoomStep = null"
        >
          <div class="w-full max-w-lg bg-n-solid-1 border border-n-weak rounded-3xl shadow-2xl overflow-hidden">
            <div class="h-1.5 w-full" style="background: linear-gradient(90deg, #B8860B, #D4AF37)" />
            <div class="p-5">
              <div class="flex items-center gap-2 mb-3">
                <span class="w-8 h-8 rounded-xl flex items-center justify-center text-white text-sm font-black" style="background: linear-gradient(135deg, #B8860B, #D4AF37)">
                  {{ selectedProcess.steps.indexOf(zoomStep) + 1 }}
                </span>
                <input
                  v-if="editingProcess"
                  v-model="zoomStep.title"
                  class="flex-1 text-sm font-bold text-n-slate-12 bg-n-solid-2 border border-n-weak rounded-lg px-2 h-9"
                  style="margin-bottom: 0"
                />
                <h2 v-else class="text-sm font-bold text-n-slate-12 flex-1">{{ zoomStep.title }}</h2>
                <button class="i-lucide-x text-n-slate-10 hover:text-n-slate-12" @click="zoomStep = null" />
              </div>

              <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1">O que acontece nesta etapa</p>
              <textarea
                v-if="editingProcess"
                v-model="zoomStep.desc"
                rows="3"
                class="w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2 text-xs text-n-slate-12 resize-y mb-3"
              />
              <p v-else class="text-xs text-n-slate-11 leading-relaxed mb-3 whitespace-pre-line">{{ zoomStep.desc || '—' }}</p>

              <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1">Responsável (quem segura o bastão)</p>
              <select
                v-if="editingProcess"
                v-model="zoomStep.owner_id"
                class="h-9 rounded-xl border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 mb-3"
                style="width: 14rem; margin-bottom: 0.75rem"
              >
                <option :value="null">— sem dono definido —</option>
                <option v-for="a in teamAgents" :key="a.id" :value="a.id">{{ a.available_name || a.name }}</option>
              </select>
              <p v-else class="text-xs font-semibold mb-3" style="color: #92600A">{{ ownerName(zoomStep.owner_id) }}</p>

              <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1">Passe de bastão (o que dispara a próxima etapa)</p>
              <textarea
                v-if="editingProcess"
                v-model="zoomStep.handoff"
                rows="2"
                class="w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2 text-xs text-n-slate-12 resize-y"
              />
              <p v-else class="text-xs text-n-slate-11 leading-relaxed whitespace-pre-line">{{ zoomStep.handoff || '—' }}</p>

              <div v-if="editingProcess" class="flex items-center gap-1.5 mt-4 pt-3 border-t border-n-weak">
                <button class="px-2.5 h-8 rounded-lg border border-n-weak text-xs text-n-slate-11 hover:bg-n-alpha-1" @click="moveStep(selectedProcess.steps.indexOf(zoomStep), -1)">← mover</button>
                <button class="px-2.5 h-8 rounded-lg border border-n-weak text-xs text-n-slate-11 hover:bg-n-alpha-1" @click="moveStep(selectedProcess.steps.indexOf(zoomStep), 1)">mover →</button>
                <button
                  class="ml-auto px-2.5 h-8 rounded-lg border border-red-500/40 text-xs text-red-500 hover:bg-red-500/10"
                  @click="removeStep(selectedProcess.steps.indexOf(zoomStep)); zoomStep = null"
                >
                  Excluir etapa
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- pilares: 1 coluna no celular, 2 no notebook, 3 no desktop largo -->
      <div v-else class="grid grid-cols-1 lg:grid-cols-2 2xl:grid-cols-3 gap-4 mt-4 items-start">
        <div
          v-for="pillar in pillars"
          :key="pillar.id"
          class="bg-n-card outline outline-1 outline-n-container rounded-2xl overflow-hidden shadow-sm"
        >
          <div class="h-1.5 w-full" :style="{ background: colorOf(pillar).grad }" />
          <div class="p-4 sm:p-5">
            <!-- identidade do pilar -->
            <div class="flex items-start gap-2.5">
              <span
                class="w-10 h-10 rounded-xl flex items-center justify-center text-xl flex-shrink-0"
                :style="{ background: colorOf(pillar).grad }"
              >
                {{ pillar.emoji }}
              </span>
              <div class="flex-1 min-w-0">
                <h2 class="text-sm font-bold text-n-slate-12 leading-tight">{{ pillar.name }}</h2>
                <p v-if="pillar.subtitle" class="text-[11px] text-n-slate-10 mt-0.5">{{ pillar.subtitle }}</p>
              </div>
              <button
                class="w-8 h-8 rounded-lg text-n-slate-10 hover:bg-n-alpha-1 flex items-center justify-center flex-shrink-0"
                title="Editar pilar (nome, responsáveis, como está)"
                @click="openEditPillar(pillar)"
              >
                <span class="i-lucide-pencil text-sm" />
              </button>
            </div>

            <!-- semáforo de saúde: clique direto -->
            <div class="flex items-center gap-1.5 mt-3 flex-wrap">
              <button
                v-for="s in PILLAR_STATUS"
                :key="s.key"
                class="inline-flex items-center gap-1.5 text-[11px] font-semibold px-2.5 py-1 rounded-full transition-all"
                :style="pillar.status === s.key
                  ? { background: s.bg, color: s.color, boxShadow: `inset 0 0 0 1.5px ${s.color}` }
                  : { background: 'transparent', color: '#94A3B8' }"
                :title="`Marcar este pilar como ${s.label}`"
                @click="setPillarStatus(pillar, s.key)"
              >
                <span
                  class="w-2 h-2 rounded-full flex-shrink-0"
                  :style="{ background: pillar.status === s.key ? s.dot : '#CBD5E1' }"
                />
                {{ s.label }}
              </button>
            </div>

            <!-- responsáveis -->
            <div class="flex items-center gap-1.5 mt-3 flex-wrap">
              <span class="i-lucide-users text-sm text-n-slate-9" />
              <template v-if="ownersOf(pillar).length">
                <span
                  v-for="name in ownersOf(pillar)"
                  :key="name"
                  class="text-[11px] font-medium px-2 py-0.5 rounded-full"
                  style="background: rgba(212, 175, 55, 0.14); color: #92600A"
                >
                  {{ name }}
                </span>
              </template>
              <button
                v-else
                class="text-[11px] text-n-slate-9 underline decoration-dotted"
                @click="openEditPillar(pillar)"
              >
                definir responsáveis…
              </button>
            </div>

            <!-- como está (nota de desempenho do gestor) -->
            <div
              v-if="pillar.health_note"
              class="mt-3 rounded-r-lg px-2.5 py-2 bg-n-alpha-1"
              :style="{ borderLeft: `3px solid ${statusOf(pillar).color}` }"
            >
              <p class="text-xs text-n-slate-11 leading-snug whitespace-pre-line">{{ pillar.health_note }}</p>
            </div>

            <!-- progresso das estratégias -->
            <div v-if="progressOf(pillar)" class="mt-3">
              <div class="h-2 bg-n-alpha-1 rounded-full overflow-hidden">
                <div
                  class="h-full rounded-full transition-all duration-700"
                  :style="{ width: Math.max(progressOf(pillar).pct, 3) + '%', background: colorOf(pillar).grad }"
                />
              </div>
              <p class="text-[10px] text-n-slate-9 mt-1">
                {{ progressOf(pillar).done }} de {{ progressOf(pillar).total }} concluídas · {{ progressOf(pillar).pct }}%
              </p>
            </div>

            <!-- estratégias e correções -->
            <div class="mt-3 space-y-1.5">
              <div
                v-for="item in pillar.items"
                :key="item.id"
                class="rounded-xl border border-n-weak bg-n-solid-2 overflow-hidden"
              >
                <div
                  class="flex items-center gap-2 px-3 py-2 cursor-pointer hover:bg-n-alpha-1"
                  @click="toggleExpand(item)"
                >
                  <span
                    :class="kindOf(item).icon"
                    class="text-sm flex-shrink-0"
                    :style="{ color: kindOf(item).color }"
                    :title="kindOf(item).label"
                  />
                  <span
                    class="text-xs font-medium text-n-slate-12 flex-1 min-w-0 truncate"
                    :class="item.status === 'concluida' ? 'line-through opacity-60' : ''"
                  >
                    {{ item.title }}
                  </span>
                  <span v-if="item.owner_id && agentName(item.owner_id)" class="text-[10px] text-n-slate-9 hidden sm:inline">
                    {{ agentName(item.owner_id).split(' ')[0] }}
                  </span>
                  <span
                    v-if="item.due_on"
                    class="inline-flex items-center gap-1 text-[10px] font-semibold"
                    :style="{ color: overdue(item) ? '#DC2626' : '#94A3B8' }"
                  >
                    <span class="i-lucide-clock text-[10px]" />
                    {{ fmtDue(item.due_on) }}
                  </span>
                  <!-- clique gira o andamento: ideia → andamento → concluída → pausada -->
                  <button
                    class="text-[10px] font-bold px-2 py-0.5 rounded-full flex-shrink-0"
                    :style="{ background: itemStatusOf(item).bg, color: itemStatusOf(item).color }"
                    title="Clique para mudar o andamento"
                    @click.stop="cycleItemStatus(item)"
                  >
                    {{ itemStatusOf(item).label }}
                  </button>
                </div>
                <!-- detalhes (expande): descrição, dono, prazo, excluir -->
                <div v-if="expandedItem === item.id" class="px-3 pb-3 pt-1 border-t border-n-weak space-y-2">
                  <textarea
                    v-model="item.description"
                    rows="2"
                    placeholder="Detalhe a estratégia: o que vamos fazer, como medir…"
                    class="w-full border border-n-weak rounded-lg px-2.5 py-1.5 text-xs bg-n-solid-1 text-n-slate-12 resize-y"
                    @change="saveItem(item)"
                  />
                  <div class="flex items-center gap-2 flex-wrap">
                    <select
                      v-model="item.owner_id"
                      class="border border-n-weak rounded-lg px-2 py-1 text-xs bg-n-solid-1 text-n-slate-12"
                      style="width: 9.5rem"
                      @change="saveItem(item)"
                    >
                      <option :value="null">Sem dono</option>
                      <option v-for="a in teamAgents" :key="a.id" :value="a.id">{{ a.available_name || a.name }}</option>
                    </select>
                    <input
                      v-model="item.due_on"
                      type="date"
                      class="border border-n-weak rounded-lg px-2 py-1 text-xs bg-n-solid-1 text-n-slate-12"
                      style="width: 9rem"
                      @change="saveItem(item)"
                    />
                    <select
                      v-model="item.kind"
                      class="border border-n-weak rounded-lg px-2 py-1 text-xs bg-n-solid-1 text-n-slate-12"
                      style="width: 8.5rem"
                      @change="saveItem(item)"
                    >
                      <option v-for="k in ITEM_KINDS" :key="k.key" :value="k.key">{{ k.label }}</option>
                    </select>
                    <button
                      class="ml-auto text-n-slate-9 hover:text-red-500 i-lucide-trash-2 text-sm"
                      title="Excluir"
                      @click="deleteItem(pillar, item)"
                    />
                  </div>
                </div>
              </div>

              <!-- adicionar estratégia/correção -->
              <div class="flex items-center gap-1.5">
                <!-- largura fixa: o reset global deixa select com 100% -->
                <select
                  v-model="draftFor(pillar.id).kind"
                  class="border border-n-weak rounded-lg px-1.5 py-1.5 text-xs bg-n-solid-1 text-n-slate-12 flex-shrink-0"
                  style="width: 8.5rem"
                >
                  <option v-for="k in ITEM_KINDS" :key="k.key" :value="k.key" :title="k.hint">{{ k.label }}</option>
                </select>
                <input
                  v-model="draftFor(pillar.id).title"
                  type="text"
                  placeholder="Nova estratégia deste pilar…"
                  class="flex-1 min-w-0 border border-n-weak rounded-lg px-2.5 py-1.5 text-xs bg-n-solid-1 text-n-slate-12"
                  @keyup.enter="addItem(pillar)"
                />
                <button
                  class="w-8 h-8 rounded-lg text-white flex items-center justify-center flex-shrink-0 hover:opacity-90 disabled:opacity-40"
                  :style="{ background: colorOf(pillar).grad }"
                  :disabled="!draftFor(pillar.id).title.trim()"
                  title="Adicionar"
                  @click="addItem(pillar)"
                >
                  <span class="i-lucide-plus text-sm" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- modal do pilar -->
    <div
      v-if="editingPillar"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      @click.self="editingPillar = null"
    >
      <div class="bg-n-card rounded-2xl shadow-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto">
        <div class="h-1.5 w-full" :style="{ background: (PILLAR_COLORS[editingPillar.color] || PILLAR_COLORS.navy).grad }" />
        <div class="p-5 space-y-4">
          <h3 class="text-sm font-bold text-n-slate-12">
            {{ isNewPillar ? 'Novo pilar do negócio' : `Editar pilar: ${editingPillar.name}` }}
          </h3>

          <div class="flex gap-2">
            <div class="w-16">
              <label class="text-[10px] font-medium text-n-slate-9 block mb-1">Emoji</label>
              <input
                v-model="editingPillar.emoji"
                type="text"
                class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-base text-center bg-n-solid-1 text-n-slate-12"
              />
            </div>
            <div class="flex-1">
              <label class="text-[10px] font-medium text-n-slate-9 block mb-1">Nome do pilar</label>
              <input
                v-model="editingPillar.name"
                type="text"
                placeholder="ex.: Aquisição de Pacientes"
                class="w-full border border-n-weak rounded-lg px-2.5 py-1.5 text-sm bg-n-solid-1 text-n-slate-12"
              />
            </div>
          </div>

          <div>
            <label class="text-[10px] font-medium text-n-slate-9 block mb-1">O que este pilar cobre</label>
            <input
              v-model="editingPillar.subtitle"
              type="text"
              placeholder="ex.: marketing e vendas — do anúncio ao agendamento"
              class="w-full border border-n-weak rounded-lg px-2.5 py-1.5 text-xs bg-n-solid-1 text-n-slate-12"
            />
          </div>

          <div>
            <label class="text-[10px] font-medium text-n-slate-9 block mb-1">Cor</label>
            <div class="flex items-center gap-1.5 flex-wrap">
              <button
                v-for="(c, key) in PILLAR_COLORS"
                :key="key"
                class="w-8 h-8 rounded-lg transition-transform"
                :class="editingPillar.color === key ? 'scale-110 ring-2 ring-offset-1 ring-n-brand' : 'opacity-70 hover:opacity-100'"
                :style="{ background: c.grad }"
                @click="editingPillar.color = key"
              />
            </div>
          </div>

          <div>
            <label class="text-[10px] font-medium text-n-slate-9 block mb-1">Responsáveis pelo pilar</label>
            <div class="flex items-center gap-1.5 flex-wrap">
              <button
                v-for="a in teamAgents"
                :key="a.id"
                class="text-[11px] font-medium px-2.5 py-1 rounded-full border transition-colors"
                :style="editingPillar.owner_ids.includes(a.id)
                  ? { background: 'rgba(212, 175, 55, 0.16)', color: '#92600A', borderColor: '#D4AF37' }
                  : { borderColor: '#CBD5E1', color: '#64748B' }"
                @click="toggleOwner(a.id)"
              >
                {{ a.available_name || a.name }}
              </button>
            </div>
          </div>

          <div>
            <label class="text-[10px] font-medium text-n-slate-9 block mb-1">
              Como está este pilar hoje (desempenho, contexto, números)
            </label>
            <textarea
              v-model="editingPillar.health_note"
              rows="3"
              placeholder="ex.: 120 leads/mês vindos do Instagram, custo por lead subiu 30% — testar novas criativos e páginas."
              class="w-full border border-n-weak rounded-lg px-2.5 py-1.5 text-xs bg-n-solid-1 text-n-slate-12 resize-y"
            />
          </div>

          <div class="flex items-center gap-2 pt-1">
            <button
              v-if="!isNewPillar"
              class="text-xs font-medium text-red-500 hover:text-red-600 px-2 py-2"
              @click="deletePillar"
            >
              Excluir pilar
            </button>
            <span class="flex-1" />
            <button
              class="text-xs font-medium text-n-slate-10 px-3 py-2 rounded-lg hover:bg-n-alpha-1"
              @click="editingPillar = null"
            >
              Cancelar
            </button>
            <button
              class="text-xs font-bold text-white px-4 py-2 rounded-lg hover:opacity-90 disabled:opacity-50"
              style="background: linear-gradient(135deg, #152C61, #3B82F6)"
              :disabled="savingPillar"
              @click="savePillar"
            >
              {{ savingPillar ? 'Salvando…' : (isNewPillar ? 'Criar pilar' : 'Salvar') }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
