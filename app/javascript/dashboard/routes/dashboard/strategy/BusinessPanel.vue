<script setup>
// 🧭 PAINEL DO EMPRESÁRIO — o quadro da parede do Guilherme, vivo dentro
// do sistema (aba do Estratégico, só admin). Reproduz o desenho original:
// kanban pessoal, Continuar/Parar/Começar, Matriz de Prioridades
// (importância × urgência), Pessoas Estratégicas, Matriz de Oportunidades
// (resultados × esforço), Objetivos/Metas/Atividades do ano, Métricas da
// Empresa (integradas ao Financeiro real) e Problemas → Solução Imediata.
// Tudo salva sozinho (autosave com debounce) em agenda_config.business_board.
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import CrmAPI from 'dashboard/api/crm';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import EmojiFx from 'dashboard/components-next/cevico/EmojiFx.vue';

const props = defineProps({
  initial: { type: Object, default: null },
});

const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const fx = ref(null);
// foca o campo assim que o quadrante abre para escrever
const vFocus = { mounted: el => el.focus() };

// ── Estado do quadro (estrutura completa, mesmo vindo vazio) ──
const emptyBoard = () => ({
  kanban: { todo: [], doing: [], done: [] },
  spc: { continuar: [], parar: [], comecar: [] },
  priorities: { do: [], schedule: [], delegate: [], drop: [] },
  opportunities: { first: [], plan: [], fit: [], avoid: [] },
  people: [],
  objectives: ['', '', '', '', ''],
  goals: ['', '', '', '', ''],
  activities: ['', '', '', '', ''],
  problems: [],
});

const board = ref(emptyBoard());
const hydrate = source => {
  const base = emptyBoard();
  if (!source || typeof source !== 'object') return base;
  Object.keys(base.kanban).forEach(k => { base.kanban[k] = [...(source.kanban?.[k] || [])]; });
  Object.keys(base.spc).forEach(k => { base.spc[k] = [...(source.spc?.[k] || [])]; });
  Object.keys(base.priorities).forEach(k => { base.priorities[k] = [...(source.priorities?.[k] || [])]; });
  Object.keys(base.opportunities).forEach(k => { base.opportunities[k] = [...(source.opportunities?.[k] || [])]; });
  base.people = [...(source.people || [])];
  ['objectives', 'goals', 'activities'].forEach(k => {
    base[k] = Array.from({ length: 5 }, (_, i) => source[k]?.[i] || '');
  });
  base.problems = [...(source.problems || [])];
  return base;
};
board.value = hydrate(props.initial);

const uid = () => Math.random().toString(16).slice(2, 10);

// ── Autosave com respiro (o quadro salva sozinho, sem botão) ──
const saveState = ref('idle'); // idle | saving | saved | error
const savedAt = ref('');
let saveTimer = null;
let hydrated = false;
const persist = async () => {
  saveState.value = 'saving';
  try {
    await CrmAPI.saveBusinessBoard(board.value);
    saveState.value = 'saved';
    savedAt.value = new Date().toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
  } catch {
    saveState.value = 'error';
  }
};
watch(board, () => {
  if (!hydrated) return;
  clearTimeout(saveTimer);
  saveTimer = setTimeout(persist, 900);
}, { deep: true });
onMounted(() => { setTimeout(() => { hydrated = true; }, 300); });
onBeforeUnmount(() => clearTimeout(saveTimer));

// ── Kanban do empresário (A fazer → Fazendo → Feito) ──
const KANBAN_COLS = [
  { key: 'todo', label: 'A fazer', grad: 'linear-gradient(135deg, #111827, #64748B)', accent: '#64748B' },
  { key: 'doing', label: 'Fazendo', grad: 'linear-gradient(135deg, #1D4ED8, #3B82F6)', accent: '#2563EB' },
  { key: 'done', label: 'Feito', grad: 'linear-gradient(135deg, #059669, #4ADE80)', accent: '#059669' },
];
const kanbanDrafts = ref({ todo: '', doing: '', done: '' });
const addKanban = col => {
  const text = kanbanDrafts.value[col].trim();
  if (!text) return;
  board.value.kanban[col].push({ id: uid(), text });
  kanbanDrafts.value[col] = '';
};
const moveKanban = (col, item, dir, event) => {
  const order = ['todo', 'doing', 'done'];
  const next = order[order.indexOf(col) + dir];
  if (!next) return;
  board.value.kanban[col] = board.value.kanban[col].filter(i => i.id !== item.id);
  board.value.kanban[next].push(item);
  if (next === 'done' && fx.value && event) {
    fx.value.burstAt(event.clientX, event.clientY, ['✅', '🎉', '💪'], 4);
  }
};
const removeKanban = (col, item) => {
  board.value.kanban[col] = board.value.kanban[col].filter(i => i.id !== item.id);
};
const clearDone = () => { board.value.kanban.done = []; };

// ── Continuar · Parar · Começar ──
const SPC_ROWS = [
  { key: 'continuar', label: 'Continuar', hint: 'o que está funcionando — manter', dot: '#10B981', bg: 'rgba(16,185,129,0.08)', border: 'rgba(16,185,129,0.35)', ink: '#047857' },
  { key: 'parar', label: 'Parar', hint: 'o que drena e não traz retorno', dot: '#EF4444', bg: 'rgba(239,68,68,0.07)', border: 'rgba(239,68,68,0.3)', ink: '#B91C1C' },
  { key: 'comecar', label: 'Começar', hint: 'o que ainda não fazemos e deveríamos', dot: '#3B82F6', bg: 'rgba(59,130,246,0.08)', border: 'rgba(59,130,246,0.35)', ink: '#1D4ED8' },
];
const spcDrafts = ref({ continuar: '', parar: '', comecar: '' });
const addSpc = key => {
  const text = spcDrafts.value[key].trim();
  if (!text) return;
  board.value.spc[key].push({ id: uid(), text });
  spcDrafts.value[key] = '';
};
const removeSpc = (key, item) => {
  board.value.spc[key] = board.value.spc[key].filter(i => i.id !== item.id);
};

// ── Matrizes (2×2 com eixos, como no quadro da parede) ──
// prioridades: importância (↑) × urgência (→)
const PRIORITY_QUADS = [
  { key: 'schedule', label: 'Agendar', icon: 'i-lucide-clock', hint: 'importante, sem pressa: marcar hora na agenda', ink: '#1D4ED8', bg: 'rgba(59,130,246,0.08)', border: 'rgba(59,130,246,0.35)' },
  { key: 'do', label: 'Fazer agora', icon: 'i-lucide-zap', hint: 'importante E urgente: prioridade máxima', ink: '#047857', bg: 'rgba(16,185,129,0.1)', border: 'rgba(16,185,129,0.4)' },
  { key: 'drop', label: 'Eliminar', icon: 'i-lucide-x', hint: 'nem importante nem urgente: cortar sem dó', ink: '#B91C1C', bg: 'rgba(239,68,68,0.06)', border: 'rgba(239,68,68,0.28)' },
  { key: 'delegate', label: 'Delegar', icon: 'i-lucide-user-round', hint: 'urgente mas não precisa ser você: passar o bastão', ink: '#B45309', bg: 'rgba(245,158,11,0.09)', border: 'rgba(245,158,11,0.38)' },
];
// oportunidades: resultados (↑) × esforço (→)
const OPPORTUNITY_QUADS = [
  { key: 'first', label: 'Fazer primeiro', icon: 'i-lucide-rocket', hint: 'muito resultado com pouco esforço: ouro', ink: '#047857', bg: 'rgba(16,185,129,0.1)', border: 'rgba(16,185,129,0.4)' },
  { key: 'plan', label: 'Planejar', icon: 'i-lucide-clock', hint: 'muito resultado, muito esforço: projeto com data', ink: '#1D4ED8', bg: 'rgba(59,130,246,0.08)', border: 'rgba(59,130,246,0.35)' },
  { key: 'fit', label: 'Encaixar', icon: 'i-lucide-check', hint: 'pouco esforço: fazer nos espaços da semana', ink: '#B45309', bg: 'rgba(245,158,11,0.09)', border: 'rgba(245,158,11,0.38)' },
  { key: 'avoid', label: 'Evitar', icon: 'i-lucide-ban', hint: 'muito esforço, pouco resultado: não entrar', ink: '#B91C1C', bg: 'rgba(239,68,68,0.06)', border: 'rgba(239,68,68,0.28)' },
];
const quadDraft = ref(null); // { section, key } com input aberto
const quadText = ref('');
const openQuadInput = (section, key) => {
  quadDraft.value = { section, key };
  quadText.value = '';
};
const addQuadItem = () => {
  const text = quadText.value.trim();
  if (!text || !quadDraft.value) return;
  const { section, key } = quadDraft.value;
  board.value[section][key].push({ id: uid(), text });
  quadText.value = '';
};
const removeQuadItem = (section, key, item) => {
  board.value[section][key] = board.value[section][key].filter(i => i.id !== item.id);
};

// ── Pessoas estratégicas ──
const personDraft = ref({ name: '', why: '' });
const addPerson = () => {
  const name = personDraft.value.name.trim();
  if (!name) return;
  board.value.people.push({ id: uid(), name, why: personDraft.value.why.trim() });
  personDraft.value = { name: '', why: '' };
};
const removePerson = person => {
  board.value.people = board.value.people.filter(p => p.id !== person.id);
};
const initialsOf = name =>
  (name || '?').split(' ').map(w => w[0]).slice(0, 2).join('').toUpperCase();
const PERSON_GRADS = [
  'linear-gradient(135deg, #152C61, #3B82F6)',
  'linear-gradient(135deg, #B8860B, #D4AF37)',
  'linear-gradient(135deg, #059669, #4ADE80)',
  'linear-gradient(135deg, #5B21B6, #7C3AED)',
  'linear-gradient(135deg, #9D174D, #F472B6)',
];

// ── Objetivos do ano · Metas específicas · Atividades estratégicas ──
const YEAR_CARDS = [
  { key: 'objectives', label: 'Objetivos do Ano', icon: 'i-lucide-flag', grad: 'linear-gradient(135deg, #B8860B, #D4AF37)', placeholder: 'Objetivo' },
  { key: 'goals', label: 'Metas Específicas', icon: 'i-lucide-target', grad: 'linear-gradient(135deg, #1D4ED8, #3B82F6)', placeholder: 'Meta' },
  { key: 'activities', label: 'Atividades Estratégicas', icon: 'i-lucide-list-checks', grad: 'linear-gradient(135deg, #059669, #4ADE80)', placeholder: 'Atividade' },
];

// ── Problemas → Solução imediata ──
const addProblem = () => {
  board.value.problems.push({ id: uid(), problem: '', solution: '' });
};
const removeProblem = row => {
  board.value.problems = board.value.problems.filter(p => p.id !== row.id);
};

// ── Métricas da Empresa: números REAIS do Financeiro (este mês) ──
const finance = ref(null);
const financeLoading = ref(true);
const loadFinance = async () => {
  try {
    const { data } = await CrmAPI.getFinance({ preset: 'month' });
    finance.value = data;
  } catch {
    finance.value = null;
  } finally {
    financeLoading.value = false;
  }
};
onMounted(loadFinance);

const money = v => `R$ ${Number(v || 0).toLocaleString('pt-BR', { maximumFractionDigits: 0 })}`;
const metrics = computed(() => {
  const s = finance.value?.summary;
  if (!s) return null;
  const faturamento = s.receita || 0;
  const custoMensal = (s.custo || 0) + (s.tributo || 0);
  const vendas = (finance.value.entries || []).filter(e => e.kind === 'receita').length;
  return {
    faturamento,
    custoMensal,
    lucro: s.lucro || 0,
    margem: s.margem,
    vendas,
    ticket: vendas ? faturamento / vendas : 0,
    equilibrio: custoMensal,
  };
});
// frase por extenso (padrão do kit): a saúde do mês contada em uma linha
const financePhrase = computed(() => {
  const m = metrics.value;
  if (!m) return null;
  if (!m.faturamento && !m.custoMensal) {
    return 'O Financeiro ainda não tem lançamentos neste mês — registre receitas e custos para o painel contar a história completa.';
  }
  const gap = m.faturamento - m.equilibrio;
  if (gap >= 0) {
    return `Este mês entraram ${money(m.faturamento)} com custo total de ${money(m.custoMensal)}: a clínica já passou o ponto de equilíbrio em ${money(gap)} — daqui pra frente, cada real que entra é lucro.`;
  }
  return `Este mês entraram ${money(m.faturamento)} com custo total de ${money(m.custoMensal)}: faltam ${money(-gap)} de faturamento para a clínica empatar o mês e começar a lucrar.`;
});
const equilibrioPct = computed(() => {
  const m = metrics.value;
  if (!m || !m.equilibrio) return 0;
  return Math.min(100, Math.round((m.faturamento / m.equilibrio) * 100));
});
const openFinance = () =>
  router.push({ name: 'cevico_finance', params: { accountId: accountId.value } });
</script>

<template>
  <div class="space-y-5">
    <!-- faixa de status: o quadro salva sozinho -->
    <div class="flex items-center gap-2 flex-wrap">
      <p class="text-xs text-n-slate-10">
        O quadro da parede, vivo: tudo que você anota aqui fica guardado e salva sozinho.
      </p>
      <span
        class="ml-auto text-[11px] font-medium px-2.5 py-1 rounded-full flex items-center gap-1.5"
        :class="saveState === 'error' ? 'text-red-600 bg-red-500/10' : 'text-n-slate-10 bg-n-alpha-1'"
      >
        <span v-if="saveState === 'saving'" class="i-lucide-loader-2 animate-spin text-xs" />
        <span v-else-if="saveState === 'saved'" class="i-lucide-check text-xs" style="color: #059669" />
        <span v-else-if="saveState === 'error'" class="i-lucide-alert-triangle text-xs" />
        {{ saveState === 'saving' ? 'Salvando…'
          : saveState === 'saved' ? `Salvo às ${savedAt}`
            : saveState === 'error' ? 'Não consegui salvar — tento de novo na próxima mudança'
              : 'Alterações salvam sozinhas' }}
      </span>
    </div>

    <!-- ══ Linha 1: Kanban + Continuar/Parar/Começar + Ano ══ -->
    <div class="grid grid-cols-1 xl:grid-cols-12 gap-5">
      <!-- Kanban pessoal -->
      <div class="xl:col-span-5 bg-n-solid-2 border border-n-weak rounded-2xl p-4">
        <div class="flex items-center gap-2 mb-3">
          <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #C2410C, #F97316)">
            <span class="i-lucide-kanban text-white text-sm" />
          </span>
          <h3 class="text-sm font-bold text-n-slate-12">Semana do empresário</h3>
          <button
            v-if="board.kanban.done.length"
            class="ml-auto text-[11px] text-n-slate-10 hover:text-n-slate-12 flex items-center gap-1"
            title="Limpar os concluídos"
            @click="clearDone"
          >
            <span class="i-lucide-eraser text-xs" /> limpar feitos
          </button>
        </div>
        <div class="grid grid-cols-3 gap-2">
          <div v-for="col in KANBAN_COLS" :key="col.key" class="rounded-xl bg-n-alpha-1 p-2 flex flex-col gap-1.5 min-h-[180px]">
            <div class="flex items-center justify-between px-1">
              <span class="text-[11px] font-bold text-white px-2 py-0.5 rounded-full" :style="{ background: col.grad }">
                {{ col.label }}
              </span>
              <span class="text-[10px] text-n-slate-9">{{ board.kanban[col.key].length }}</span>
            </div>
            <TransitionGroup name="cevico-card" tag="div" class="flex flex-col gap-1.5 flex-1">
              <div
                v-for="item in board.kanban[col.key]"
                :key="item.id"
                class="group rounded-lg bg-n-solid-1 border border-n-weak px-2 py-1.5 text-xs text-n-slate-12 leading-snug shadow-sm"
                :style="{ borderLeft: `3px solid ${col.accent}` }"
              >
                <p :class="col.key === 'done' ? 'line-through opacity-70' : ''">{{ item.text }}</p>
                <div class="flex items-center gap-1 mt-1 opacity-0 group-hover:opacity-100 transition-opacity">
                  <button
                    v-if="col.key !== 'todo'"
                    class="w-5 h-5 rounded flex items-center justify-center text-n-slate-10 hover:bg-n-alpha-2"
                    title="Voltar"
                    @click="moveKanban(col.key, item, -1, $event)"
                  >
                    <span class="i-lucide-arrow-left text-[11px]" />
                  </button>
                  <button
                    v-if="col.key !== 'done'"
                    class="w-5 h-5 rounded flex items-center justify-center hover:bg-n-alpha-2"
                    :style="{ color: col.key === 'doing' ? '#059669' : '#2563EB' }"
                    :title="col.key === 'doing' ? 'Feito!' : 'Começar'"
                    @click="moveKanban(col.key, item, 1, $event)"
                  >
                    <span class="i-lucide-arrow-right text-[11px]" />
                  </button>
                  <button
                    class="w-5 h-5 rounded flex items-center justify-center text-n-slate-9 hover:text-red-500 ml-auto"
                    title="Excluir"
                    @click="removeKanban(col.key, item)"
                  >
                    <span class="i-lucide-trash-2 text-[11px]" />
                  </button>
                </div>
              </div>
            </TransitionGroup>
            <input
              v-model="kanbanDrafts[col.key]"
              class="w-full rounded-lg border border-dashed border-n-weak bg-transparent px-2 py-1.5 text-xs text-n-slate-12 focus:outline-none focus:border-n-brand"
              placeholder="+ anotar"
              @keydown.enter.prevent="addKanban(col.key)"
            />
          </div>
        </div>
      </div>

      <!-- Continuar · Parar · Começar -->
      <div class="xl:col-span-4 bg-n-solid-2 border border-n-weak rounded-2xl p-4">
        <div class="flex items-center gap-2 mb-3">
          <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0F766E, #2DD4BF)">
            <span class="i-lucide-refresh-ccw text-white text-sm" />
          </span>
          <h3 class="text-sm font-bold text-n-slate-12">Continuar · Parar · Começar</h3>
        </div>
        <div class="space-y-2.5">
          <div
            v-for="row in SPC_ROWS"
            :key="row.key"
            class="rounded-xl p-2.5"
            :style="{ background: row.bg, border: `1px solid ${row.border}` }"
          >
            <div class="flex items-center gap-1.5 mb-1.5">
              <span class="w-2 h-2 rounded-full flex-shrink-0" :style="{ background: row.dot }" />
              <span class="text-xs font-bold" :style="{ color: row.ink }">{{ row.label }}</span>
              <span class="text-[10px] text-n-slate-9 truncate">— {{ row.hint }}</span>
            </div>
            <div class="flex flex-wrap gap-1.5">
              <span
                v-for="item in board.spc[row.key]"
                :key="item.id"
                class="group inline-flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-full bg-n-solid-1 border border-n-weak text-n-slate-12"
              >
                {{ item.text }}
                <button class="opacity-0 group-hover:opacity-100 text-n-slate-9 hover:text-red-500" @click="removeSpc(row.key, item)">
                  <span class="i-lucide-x text-[10px]" />
                </button>
              </span>
              <input
                v-model="spcDrafts[row.key]"
                class="text-[11px] bg-transparent border-b border-dashed border-n-weak focus:outline-none focus:border-n-brand min-w-[80px] flex-1 py-0.5 text-n-slate-12"
                placeholder="+ adicionar"
                @keydown.enter.prevent="addSpc(row.key)"
              />
            </div>
          </div>
        </div>
      </div>

      <!-- Ano: objetivos, metas, atividades (1 a 5) -->
      <div class="xl:col-span-3 space-y-3">
        <div
          v-for="card in YEAR_CARDS"
          :key="card.key"
          class="bg-n-solid-2 border border-n-weak rounded-2xl p-3.5"
        >
          <div class="flex items-center gap-2 mb-2">
            <span class="w-6 h-6 rounded-lg flex items-center justify-center flex-shrink-0" :style="{ background: card.grad }">
              <span :class="card.icon" class="text-white text-xs" />
            </span>
            <h3 class="text-xs font-bold text-n-slate-12">{{ card.label }}</h3>
          </div>
          <div class="space-y-1">
            <div v-for="i in 5" :key="i" class="flex items-center gap-2">
              <span
                class="w-[18px] h-[18px] rounded-full flex items-center justify-center text-[10px] font-bold flex-shrink-0"
                :class="board[card.key][i - 1] ? 'text-white' : 'text-n-slate-9 border border-dashed border-n-weak'"
                :style="board[card.key][i - 1] ? { background: card.grad } : {}"
              >
                {{ i }}
              </span>
              <input
                v-model="board[card.key][i - 1]"
                class="flex-1 text-xs bg-transparent border-b border-transparent hover:border-n-weak focus:border-n-brand focus:outline-none py-0.5 text-n-slate-12"
                :placeholder="`${card.placeholder} ${i}…`"
              />
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- ══ Linha 2: Matriz de Prioridades · Pessoas · Matriz de Oportunidades ══ -->
    <div class="grid grid-cols-1 xl:grid-cols-12 gap-5">
      <!-- Matriz de Prioridades -->
      <div
        v-for="matrix in [
          { section: 'priorities', title: 'Matriz de Prioridades', quads: PRIORITY_QUADS, yAxis: 'Importância', xAxis: 'Urgência', grad: 'linear-gradient(135deg, #5B21B6, #7C3AED)', icon: 'i-lucide-grid-2x2' },
          { section: 'opportunities', title: 'Matriz de Oportunidades', quads: OPPORTUNITY_QUADS, yAxis: 'Resultados', xAxis: 'Esforço', grad: 'linear-gradient(135deg, #C2410C, #F97316)', icon: 'i-lucide-gem' },
        ]"
        :key="matrix.section"
        class="xl:col-span-4 bg-n-solid-2 border border-n-weak rounded-2xl p-4"
        :class="matrix.section === 'opportunities' ? 'xl:order-3' : ''"
      >
        <div class="flex items-center gap-2 mb-3">
          <span class="w-7 h-7 rounded-lg flex items-center justify-center" :style="{ background: matrix.grad }">
            <span :class="matrix.icon" class="text-white text-sm" />
          </span>
          <h3 class="text-sm font-bold text-n-slate-12">{{ matrix.title }}</h3>
        </div>
        <div class="flex gap-1.5">
          <!-- eixo Y -->
          <div class="flex items-center flex-shrink-0">
            <span class="text-[10px] font-bold uppercase tracking-wide text-n-slate-9 -rotate-90 whitespace-nowrap flex items-center gap-1">
              {{ matrix.yAxis }} <span class="i-lucide-arrow-right text-[10px]" />
            </span>
          </div>
          <div class="flex-1 min-w-0">
            <div class="grid grid-cols-2 gap-1.5">
              <div
                v-for="quad in matrix.quads"
                :key="quad.key"
                class="rounded-xl p-2 min-h-[92px] flex flex-col gap-1"
                :style="{ background: quad.bg, border: `1px solid ${quad.border}` }"
              >
                <div class="flex items-center gap-1" :title="quad.hint">
                  <span :class="quad.icon" class="text-[11px]" :style="{ color: quad.ink }" />
                  <span class="text-[10px] font-bold" :style="{ color: quad.ink }">{{ quad.label }}</span>
                  <button
                    class="ml-auto w-4 h-4 rounded flex items-center justify-center hover:bg-n-alpha-2"
                    :style="{ color: quad.ink }"
                    :title="`Adicionar em ${quad.label}`"
                    @click="openQuadInput(matrix.section, quad.key)"
                  >
                    <span class="i-lucide-plus text-[10px]" />
                  </button>
                </div>
                <span
                  v-for="item in board[matrix.section][quad.key]"
                  :key="item.id"
                  class="group inline-flex items-start gap-1 text-[10px] leading-tight px-1.5 py-1 rounded-md bg-n-solid-1 border border-n-weak text-n-slate-12"
                >
                  <span class="flex-1">{{ item.text }}</span>
                  <button class="opacity-0 group-hover:opacity-100 text-n-slate-9 hover:text-red-500 flex-shrink-0" @click="removeQuadItem(matrix.section, quad.key, item)">
                    <span class="i-lucide-x text-[9px]" />
                  </button>
                </span>
                <input
                  v-if="quadDraft && quadDraft.section === matrix.section && quadDraft.key === quad.key"
                  v-model="quadText"
                  v-focus
                  class="text-[10px] bg-n-solid-1 border border-n-weak rounded-md px-1.5 py-1 focus:outline-none focus:border-n-brand text-n-slate-12"
                  placeholder="escrever e Enter"
                  @keydown.enter.prevent="addQuadItem"
                  @blur="quadDraft = null"
                />
              </div>
            </div>
            <p class="text-[10px] font-bold uppercase tracking-wide text-n-slate-9 text-center mt-1 flex items-center justify-center gap-1">
              {{ matrix.xAxis }} <span class="i-lucide-arrow-right text-[10px]" />
            </p>
          </div>
        </div>
      </div>

      <!-- Pessoas estratégicas -->
      <div class="xl:col-span-4 xl:order-2 bg-n-solid-2 border border-n-weak rounded-2xl p-4">
        <div class="flex items-center gap-2 mb-3">
          <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #152C61, #3B82F6)">
            <span class="i-lucide-users-round text-white text-sm" />
          </span>
          <h3 class="text-sm font-bold text-n-slate-12">Pessoas Estratégicas</h3>
          <span class="text-[10px] text-n-slate-9 ml-auto">quem move o negócio com você</span>
        </div>
        <div class="space-y-2 mb-3">
          <div
            v-for="(person, i) in board.people"
            :key="person.id"
            class="group flex items-center gap-2.5 rounded-xl bg-n-alpha-1 px-2.5 py-2"
          >
            <span
              class="w-8 h-8 rounded-full flex items-center justify-center text-white text-[11px] font-bold flex-shrink-0 shadow-sm"
              :style="{ background: PERSON_GRADS[i % PERSON_GRADS.length] }"
            >
              {{ initialsOf(person.name) }}
            </span>
            <div class="flex-1 min-w-0">
              <p class="text-xs font-semibold text-n-slate-12 truncate">{{ person.name }}</p>
              <p v-if="person.why" class="text-[11px] text-n-slate-10 truncate">{{ person.why }}</p>
            </div>
            <button class="opacity-0 group-hover:opacity-100 text-n-slate-9 hover:text-red-500 flex-shrink-0" @click="removePerson(person)">
              <span class="i-lucide-trash-2 text-xs" />
            </button>
          </div>
          <p v-if="!board.people.length" class="text-[11px] text-n-slate-9 text-center py-3">
            Liste as pessoas-chave: sócios, mentores, fornecedores, parceiros.
          </p>
        </div>
        <div class="space-y-1.5">
          <input
            v-model="personDraft.name"
            class="w-full text-xs bg-transparent border border-dashed border-n-weak rounded-lg px-2.5 py-1.5 focus:outline-none focus:border-n-brand text-n-slate-12"
            placeholder="Nome da pessoa"
            @keydown.enter.prevent="addPerson"
          />
          <div class="flex gap-1.5">
            <input
              v-model="personDraft.why"
              class="flex-1 text-xs bg-transparent border border-dashed border-n-weak rounded-lg px-2.5 py-1.5 focus:outline-none focus:border-n-brand text-n-slate-12"
              placeholder="Por que é estratégica? (opcional)"
              @keydown.enter.prevent="addPerson"
            />
            <button
              class="text-xs font-semibold text-white px-3 rounded-lg disabled:opacity-40"
              style="background: linear-gradient(135deg, #152C61, #3B82F6)"
              :disabled="!personDraft.name.trim()"
              @click="addPerson"
            >
              <span class="i-lucide-plus text-sm" />
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- ══ Linha 3: Métricas da Empresa (Financeiro real) + Problemas → Solução ══ -->
    <div class="grid grid-cols-1 xl:grid-cols-12 gap-5">
      <div class="xl:col-span-7 bg-n-solid-2 border border-n-weak rounded-2xl p-4">
        <div class="flex items-center gap-2 mb-3 flex-wrap">
          <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #B8860B, #D4AF37)">
            <span class="i-lucide-bar-chart-3 text-white text-sm" />
          </span>
          <h3 class="text-sm font-bold text-n-slate-12">Métricas da Empresa</h3>
          <span class="text-[10px] text-n-slate-9">este mês, direto do Financeiro</span>
          <button
            class="ml-auto text-[11px] font-medium text-n-slate-10 hover:text-n-brand flex items-center gap-1"
            @click="openFinance"
          >
            abrir Financeiro <span class="i-lucide-arrow-right text-[11px]" />
          </button>
        </div>

        <div v-if="financeLoading" class="grid grid-cols-2 sm:grid-cols-3 gap-2.5">
          <div v-for="i in 6" :key="i" class="h-20 rounded-xl bg-n-alpha-1 animate-pulse" />
        </div>
        <template v-else-if="metrics">
          <!-- frase por extenso: a saúde do mês em uma linha -->
          <div
            class="rounded-xl px-3.5 py-2.5 mb-3 text-xs leading-relaxed"
            :style="metrics.faturamento >= metrics.equilibrio
              ? 'background: rgba(16,185,129,0.09); border: 1px solid rgba(16,185,129,0.35); color: #047857'
              : 'background: rgba(245,158,11,0.1); border: 1px solid rgba(245,158,11,0.4); color: #92600a'"
          >
            {{ financePhrase }}
          </div>
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-2.5">
            <DashKpi label="Faturamento" :value="Math.round(metrics.faturamento)" prefix="R$ " from="#B8860B" to="#D4AF37" compact sub="receitas lançadas no mês" />
            <DashKpi label="Volume de vendas" :value="metrics.vendas" from="#1D4ED8" to="#3B82F6" compact sub="lançamentos de receita" />
            <DashKpi label="Ticket médio" :value="Math.round(metrics.ticket)" prefix="R$ " from="#5B21B6" to="#7C3AED" compact sub="faturamento ÷ vendas" />
            <DashKpi label="Custo mensal" :value="Math.round(metrics.custoMensal)" prefix="R$ " from="#9D174D" to="#F472B6" compact sub="custos + tributos" />
            <DashKpi label="Lucro" :value="Math.round(metrics.lucro)" prefix="R$ " from="#059669" to="#4ADE80" compact :sub="metrics.margem !== null && metrics.margem !== undefined ? `margem de ${metrics.margem}%` : 'sem margem ainda'" />
            <!-- ponto de equilíbrio com barra de progresso do mês -->
            <div class="rounded-xl bg-n-solid-1 border border-n-weak p-3 flex flex-col justify-between">
              <div>
                <p class="text-[10px] font-medium text-n-slate-10 uppercase tracking-wide">Ponto de equilíbrio</p>
                <p class="text-lg font-bold text-n-slate-12">{{ money(metrics.equilibrio) }}</p>
              </div>
              <div>
                <div class="h-2 rounded-full bg-n-alpha-2 overflow-hidden">
                  <div
                    class="h-full rounded-full transition-all duration-700"
                    :style="{
                      width: `${equilibrioPct}%`,
                      background: equilibrioPct >= 100
                        ? 'linear-gradient(90deg, #059669, #4ADE80)'
                        : 'linear-gradient(90deg, #B8860B, #D4AF37)',
                    }"
                  />
                </div>
                <p class="text-[10px] mt-1" :style="{ color: equilibrioPct >= 100 ? '#047857' : '#92600a' }">
                  {{ equilibrioPct >= 100 ? 'mês pago — lucrando' : `${equilibrioPct}% do caminho` }}
                </p>
              </div>
            </div>
          </div>
        </template>
        <p v-else class="text-xs text-n-slate-10 py-6 text-center">
          Não consegui ler o Financeiro agora — as métricas aparecem aqui assim que ele responder.
        </p>
      </div>

      <!-- Problemas → Solução imediata -->
      <div class="xl:col-span-5 bg-n-solid-2 border border-n-weak rounded-2xl p-4">
        <div class="flex items-center gap-2 mb-3">
          <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #9D174D, #F472B6)">
            <span class="i-lucide-flame text-white text-sm" />
          </span>
          <h3 class="text-sm font-bold text-n-slate-12">Principais Problemas → Solução Imediata</h3>
        </div>
        <div class="space-y-2.5 mb-3">
          <div v-for="(row, i) in board.problems" :key="row.id" class="group flex items-stretch gap-2">
            <textarea
              v-model="row.problem"
              rows="2"
              class="flex-1 text-[11px] leading-snug rounded-lg px-2.5 py-2 resize-none focus:outline-none"
              :class="i % 2 ? '-rotate-[0.6deg]' : 'rotate-[0.6deg]'"
              style="background: rgba(245, 158, 11, 0.12); border: 1px solid rgba(245, 158, 11, 0.45); color: #713f12"
              placeholder="Qual é o problema?"
            />
            <span class="i-lucide-arrow-right self-center flex-shrink-0" style="color: #EA580C" />
            <textarea
              v-model="row.solution"
              rows="2"
              class="flex-1 text-[11px] leading-snug rounded-lg px-2.5 py-2 resize-none focus:outline-none"
              :class="i % 2 ? 'rotate-[0.6deg]' : '-rotate-[0.6deg]'"
              style="background: rgba(16, 185, 129, 0.12); border: 1px solid rgba(16, 185, 129, 0.45); color: #065f46"
              placeholder="Solução imediata"
            />
            <button
              class="self-center opacity-0 group-hover:opacity-100 text-n-slate-9 hover:text-red-500 flex-shrink-0"
              @click="removeProblem(row)"
            >
              <span class="i-lucide-trash-2 text-xs" />
            </button>
          </div>
          <p v-if="!board.problems.length" class="text-[11px] text-n-slate-9 text-center py-3">
            O que mais dói hoje? Escreva o problema e, na frente, a solução mais rápida possível.
          </p>
        </div>
        <button
          class="w-full text-xs font-semibold py-2 rounded-xl border border-dashed border-n-weak text-n-slate-10 hover:text-n-brand hover:border-n-brand transition-colors flex items-center justify-center gap-1"
          @click="addProblem"
        >
          <span class="i-lucide-plus text-sm" /> novo par problema → solução
        </button>
      </div>
    </div>

    <EmojiFx ref="fx" />
  </div>
</template>

<style scoped>
/* cards do kanban entram/saem com vida (dopamine, sem exagero) */
.cevico-card-enter-active,
.cevico-card-leave-active {
  transition: all 0.25s ease;
}
.cevico-card-enter-from {
  opacity: 0;
  transform: translateY(6px) scale(0.97);
}
.cevico-card-leave-to {
  opacity: 0;
  transform: scale(0.94);
}
</style>
