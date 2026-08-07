<script setup>
// 🧲 CONSTRUTOR (item 57): cada pessoa monta o próprio painel com os
// indicadores que já existem no sistema. Drag-and-drop com ÍMÃ (os cards
// deslizam magneticamente para o lugar), tamanhos P/M/G numa grade de 12
// colunas pré-configurada para ficar bonita, e escolha de paleta de cores.
// O layout fica salvo por pessoa (neste navegador).
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import { frontendURL } from 'dashboard/helper/URLHelper';
import CrmAPI from 'dashboard/api/crm';
// catálogo ÚNICO (06/08): widgets, paletas e tamanhos agora moram no helper
// compartilhado — o Meu Painel usa as MESMAS definições para exibir os
// painéis da conta salvos aqui
import {
  CATALOG,
  CATALOG_SECTIONS,
  PALETTES,
  SIZE_CLASS,
  paletteByKey,
  catalogMetaOf,
} from 'dashboard/helper/cevicoBuilderCatalog';

const store = useStore();
const currentUser = useMapGetter('getCurrentUser');
const crmSettings = useMapGetter('crm/getSettings');
const teamAgents = useMapGetter('agents/getAgents');
const { isAdmin } = useAdmin();
const route = useRoute();
const router = useRouter();

const nextSize = s => (s === 'sm' ? 'md' : s === 'md' ? 'lg' : 'sm');

// ── layout salvo por pessoa ──
const storageKey = computed(() => `cevico_builder_${currentUser.value?.id || 0}`);
const paletteKey = ref('cevico');
const widgets = ref([]); // [{ key, size }]
const editing = ref(false);

const DEFAULT_LAYOUT = [
  { key: 'appointments_today', size: 'sm' },
  { key: 'open_conversations', size: 'sm' },
  { key: 'unanswered', size: 'sm' },
  { key: 'new_contacts_30d', size: 'sm' },
  { key: 'goals', size: 'md' },
  { key: 'radar', size: 'md' },
];

const loadLayout = () => {
  try {
    const saved = JSON.parse(localStorage.getItem(storageKey.value) || 'null');
    if (saved?.widgets?.length) {
      widgets.value = saved.widgets.filter(w => CATALOG.some(c => c.key === w.key));
      paletteKey.value = PALETTES.some(p => p.key === saved.palette) ? saved.palette : 'cevico';
      return;
    }
  } catch {
    // layout corrompido → volta pro padrão
  }
  widgets.value = DEFAULT_LAYOUT.map(w => ({ ...w }));
};
const saveLayout = () => {
  localStorage.setItem(storageKey.value, JSON.stringify({ palette: paletteKey.value, widgets: widgets.value }));
};

const palette = computed(() => paletteByKey(paletteKey.value));
const gradFor = idx => palette.value.grads[idx % palette.value.grads.length];
const metaOf = catalogMetaOf;
const availableToAdd = computed(() => CATALOG.filter(c => !widgets.value.some(w => w.key === c.key)));
const availableBySection = computed(() =>
  CATALOG_SECTIONS.map(section => ({
    section,
    items: availableToAdd.value.filter(c => c.section === section),
  })).filter(s => s.items.length)
);

const addWidget = key => {
  const kind = metaOf(key).kind;
  widgets.value.push({ key, size: kind === 'kpi' || kind === 'dash' ? 'sm' : 'md' });
  saveLayout();
};

// ── PREDEFINIÇÕES (pedido 19/07): salvar o painel montado com nome,
// aplicar depois com um clique — várias predefinições por pessoa ──
const presetsKey = computed(() => `cevico_builder_presets_${currentUser.value?.id || 0}`);
const presets = ref([]);
const presetName = ref('');

const loadPresets = () => {
  try {
    presets.value = JSON.parse(localStorage.getItem(presetsKey.value) || '[]');
  } catch {
    presets.value = [];
  }
};
const persistPresets = () => {
  localStorage.setItem(presetsKey.value, JSON.stringify(presets.value.slice(0, 20)));
};
const savePreset = () => {
  const name = presetName.value.trim();
  if (!name || !widgets.value.length) return;
  presets.value = [
    ...presets.value.filter(p => p.name !== name),
    { name, palette: paletteKey.value, widgets: widgets.value.map(w => ({ ...w })) },
  ];
  persistPresets();
  presetName.value = '';
};
const applyPreset = preset => {
  widgets.value = preset.widgets
    .filter(w => CATALOG.some(c => c.key === w.key))
    .map(w => ({ ...w }));
  paletteKey.value = PALETTES.some(p => p.key === preset.palette) ? preset.palette : 'cevico';
  saveLayout();
};
const removePreset = preset => {
  presets.value = presets.value.filter(p => p.name !== preset.name);
  persistPresets();
};

// ── PAINÉIS DA CONTA (06/08): o admin salva o painel montado para a conta
// inteira — vira pílula no Meu Painel de todo mundo; dá para eleger o
// principal (★) e travar cada atendente num painel (👥) ──
const accountPanels = computed(() => crmSettings.value?.custom_panels || []);
const mainPanelKey = computed(() => crmSettings.value?.main_panel || '');
const accountPanelName = ref('');
const isSavingAccountPanel = ref(false);

// id legível: nome slugificado + 4 caracteres aleatórios (fica estável
// quando o painel é substituído pelo mesmo nome)
const slugify = name =>
  name
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '') // tira acentos (Condução → conducao)
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');

const saveAccountPanel = async () => {
  const name = accountPanelName.value.trim();
  if (!name || !widgets.value.length || isSavingAccountPanel.value) return;
  const existing = accountPanels.value.find(p => p.name === name);
  if (!existing && accountPanels.value.length >= 24) {
    useAlert('Limite de 24 painéis da conta — exclua algum antes.');
    return;
  }
  isSavingAccountPanel.value = true;
  try {
    // mesmo nome = substitui mantendo o id (as atribuições continuam valendo)
    const id = existing
      ? existing.id
      : `${slugify(name) || 'painel'}-${Math.random().toString(36).slice(2, 6)}`;
    const panel = {
      id,
      name,
      palette: paletteKey.value,
      widgets: widgets.value.map(w => ({ ...w })),
    };
    const list = existing
      ? accountPanels.value.map(p => (p.id === existing.id ? panel : p))
      : [...accountPanels.value, panel];
    await CrmAPI.updateCustomPanels(list);
    await store.dispatch('crm/fetchSettings');
    accountPanelName.value = '';
    useAlert('Painel salvo — já aparece no Meu Painel.');
  } catch {
    useAlert('Não deu para salvar o painel da conta. Tente de novo.');
  } finally {
    isSavingAccountPanel.value = false;
  }
};

// clicar no nome = aplicar no construtor local (widgets + paleta)
const applyAccountPanel = panel => {
  widgets.value = (panel.widgets || [])
    .filter(w => CATALOG.some(c => c.key === w.key))
    .map(w => ({ ...w }));
  paletteKey.value = PALETTES.some(p => p.key === panel.palette) ? panel.palette : 'cevico';
  saveLayout();
};

const isMainPanel = panel => mainPanelKey.value === `custom:${panel.id}`;
const isTogglingMain = ref(false);
const toggleMainPanel = async panel => {
  if (isTogglingMain.value) return;
  isTogglingMain.value = true;
  try {
    // ★ no principal atual = volta o Meu Painel ao padrão de fábrica
    const makingMain = !isMainPanel(panel);
    await CrmAPI.updateMainPanel(makingMain ? `custom:${panel.id}` : '');
    await store.dispatch('crm/fetchSettings');
    useAlert(
      makingMain
        ? '★ Painel definido como principal da conta.'
        : 'O Meu Painel voltou ao padrão de fábrica.'
    );
  } catch {
    useAlert('Não deu para mudar o painel principal. Tente de novo.');
  } finally {
    isTogglingMain.value = false;
  }
};

const removeAccountPanel = async panel => {
  if (isSavingAccountPanel.value) return;
  isSavingAccountPanel.value = true;
  try {
    await CrmAPI.updateCustomPanels(accountPanels.value.filter(p => p.id !== panel.id));
    // se era o principal, o Meu Painel volta ao padrão de fábrica
    if (isMainPanel(panel)) await CrmAPI.updateMainPanel('');
    await store.dispatch('crm/fetchSettings');
    useAlert('Painel da conta excluído.');
  } catch {
    useAlert('Não deu para excluir o painel. Tente de novo.');
  } finally {
    isSavingAccountPanel.value = false;
  }
};

// ── Atribuir ao time (mesmo modal do Meu Painel): mapa completo
// { user_id: chave } — painéis fixos ou 'custom:<id>' ──
const FIXED_PANELS = [
  { key: 'agendamento', label: 'Agendamento' },
  { key: 'conducao', label: 'Condução' },
  { key: 'cirurgia', label: 'Cirurgias' },
  { key: 'medico', label: 'Médicos' },
  { key: 'gestor', label: 'Gestor' },
];
const showAssignModal = ref(false);
const assignDraft = ref({});
const isSavingAssign = ref(false);
const openAssignModal = () => {
  assignDraft.value = { ...(crmSettings.value?.panel_assignments || {}) };
  if (!teamAgents.value.length) store.dispatch('agents/get');
  showAssignModal.value = true;
};
const saveAssignments = async () => {
  if (isSavingAssign.value) return;
  isSavingAssign.value = true;
  try {
    // só fica no mapa quem tem painel travado ('' = livre, sai do mapa)
    const clean = Object.fromEntries(
      Object.entries(assignDraft.value).filter(([, v]) => v)
    );
    await CrmAPI.updatePanelAssignments(clean);
    await store.dispatch('crm/fetchSettings');
    showAssignModal.value = false;
    useAlert('Atribuições salvas.');
  } catch {
    useAlert('Não deu para salvar as atribuições. Tente de novo.');
  } finally {
    isSavingAssign.value = false;
  }
};

// atalho de dashboard: clique abre o ambiente (fora do modo edição)
const openDash = w => {
  const to = metaOf(w.key).to;
  if (!to || editing.value) return;
  router.push(frontendURL(`accounts/${route.params.accountId}/${to}`));
};
const removeWidget = i => {
  widgets.value.splice(i, 1);
  saveLayout();
};
const cycleSize = w => {
  w.size = nextSize(w.size);
  saveLayout();
};
const setPalette = key => {
  paletteKey.value = key;
  saveLayout();
};

// ── drag-and-drop com ÍMÃ: ao passar por cima, os cards se REORGANIZAM
// na hora (transition-group faz o deslize magnético) ──
const dragIndex = ref(-1);
const onDragStart = i => { dragIndex.value = i; };
const onDragEnter = i => {
  if (dragIndex.value === -1 || i === dragIndex.value) return;
  const list = widgets.value;
  const [moved] = list.splice(dragIndex.value, 1);
  list.splice(i, 0, moved);
  dragIndex.value = i;
};
const onDragEnd = () => {
  dragIndex.value = -1;
  saveLayout();
};

// ── dados vivos (mesmas fontes do Meu Painel e do Painel de Metas) ──
const home = ref(null);
const goalsData = ref(null);
const isLoading = ref(true);
const load = async () => {
  isLoading.value = true;
  try {
    // painel 'gestor' = superset de indicadores do processo inteiro
    const [homeRes, goalsRes] = await Promise.allSettled([
      CrmAPI.getHome({ preset: 'today', panel: 'gestor' }),
      CrmAPI.getGoalPlans(),
    ]);
    if (homeRes.status === 'fulfilled') home.value = homeRes.value.data;
    if (goalsRes.status === 'fulfilled') goalsData.value = goalsRes.value.data;
  } finally {
    isLoading.value = false;
  }
};

// indicador: busca no topo do payload, depois no panel_data (gestor);
// taxas ganham % e NPS lê a satisfação de dentro do bloco nps
const kpiValue = key => {
  const meta = metaOf(key);
  let v = home.value?.[key];
  if (v === undefined || v === null) v = home.value?.panel_data?.[key];
  if (key === 'nps_satisfaction') v = home.value?.panel_data?.nps?.satisfaction;
  if (v === undefined || v === null) return meta.pct ? '—' : '0';
  return meta.pct ? `${Number(v).toLocaleString('pt-BR')}%` : Number(v).toLocaleString('pt-BR');
};
const radarAlerts = computed(() => home.value?.opportunity_alerts?.alerts || []);
const myTasks = computed(() => home.value?.my_tasks?.items || []);
const nextAppointments = computed(() => home.value?.next_appointments || []);
const myResponse = computed(() => home.value?.response_goal?.mine || null);
const goalRows = computed(() => {
  const targets = goalsData.value?.plan?.targets || {};
  const current = (goalsData.value?.history || []).find(h => h.month === goalsData.value?.month)?.values || {};
  return Object.entries(targets)
    .filter(([, v]) => Number(v) > 0)
    .slice(0, 4)
    .map(([key, target]) => ({
      key,
      label: goalsData.value?.indicators?.[key] || key,
      current: current[key] || 0,
      target: Number(target),
      pct: Math.min(100, Math.round(((current[key] || 0) / Number(target)) * 100)),
    }));
});
const fmtDue = iso =>
  iso ? new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : '';

onMounted(() => {
  loadLayout();
  loadPresets();
  // painéis da conta chegam nos settings do CRM — busca se ainda não vieram
  if (crmSettings.value?.custom_panels === undefined) {
    store.dispatch('crm/fetchSettings');
  }
  load();
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-6xl mx-auto w-full p-4 sm:p-8">
      <!-- header -->
      <div class="flex items-center gap-3 flex-wrap mb-5">
        <span class="w-9 h-9 rounded-xl flex items-center justify-center" :style="{ background: palette.grads[0] }">
          <span class="i-lucide-magnet text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-lg font-bold text-n-slate-12">Construtor</h1>
          <p class="text-xs text-n-slate-10">seu painel, do seu jeito — arraste os cards (eles se encaixam como ímã), mude tamanhos e cores</p>
        </div>
        <!-- paleta -->
        <div class="flex items-center gap-1">
          <button
            v-for="p in PALETTES"
            :key="p.key"
            class="w-7 h-7 rounded-full border-2 transition-transform hover:scale-110"
            :class="paletteKey === p.key ? 'border-n-slate-12 scale-110' : 'border-transparent'"
            :style="{ background: p.grads[0] }"
            :title="p.label"
            @click="setPalette(p.key)"
          />
        </div>
        <button
          class="px-3 h-8 rounded-xl text-xs font-bold transition-colors"
          :class="editing ? 'text-white' : 'border border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
          :style="editing ? { background: palette.grads[0] } : {}"
          @click="editing = !editing"
        >
          {{ editing ? '✓ Pronto' : '🧲 Personalizar' }}
        </button>
      </div>

      <!-- catálogo (modo edição): TODOS os indicadores + dashboards, por seção -->
      <div v-if="editing" class="rounded-2xl border-2 border-dashed border-n-weak bg-n-solid-2 p-4 mb-5">
        <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-2">
          Adicionar elementos — clique para incluir no painel
        </p>
        <div v-for="group in availableBySection" :key="group.section" class="mb-2.5 last:mb-0">
          <p class="text-[10px] font-bold text-n-slate-10 mb-1.5">{{ group.section }}</p>
          <div class="flex items-center gap-1.5 flex-wrap">
            <button
              v-for="c in group.items"
              :key="c.key"
              class="flex items-center gap-1.5 px-2.5 h-8 rounded-xl border border-n-weak text-xs text-n-slate-11 hover:bg-n-alpha-1 transition-colors"
              @click="addWidget(c.key)"
            >
              <span :class="c.icon" class="text-sm" />
              {{ c.label }}
              <span class="i-lucide-plus text-xs" />
            </button>
          </div>
        </div>
        <p v-if="!availableToAdd.length" class="text-xs text-n-slate-9">todos os elementos já estão no painel.</p>

        <!-- 🏢 painéis da CONTA: o admin salva o painel montado e ele vira
        pílula no Meu Painel de todo mundo; ★ elege o principal, 👥 trava
        cada atendente num painel, ✕ exclui -->
        <div class="border-t border-n-weak mt-3 pt-3">
          <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1">
            🏢 Painéis da conta
          </p>
          <p class="text-[11px] text-n-slate-10 mb-1.5">
            Painéis da conta aparecem como pílulas no Meu Painel de todo mundo.
            Atribuir um painel trava o atendente naquele painel.
          </p>
          <div class="flex items-center gap-1.5 flex-wrap">
            <template v-if="isAdmin">
              <input
                v-model="accountPanelName"
                type="text"
                placeholder="nome do painel da conta (ex: Recepção)"
                class="h-8 rounded-xl border border-n-weak bg-n-solid-1 px-2.5 text-xs text-n-slate-12"
                style="width: 16rem; margin-bottom: 0"
                @keyup.enter="saveAccountPanel"
              />
              <button
                class="px-3 h-8 rounded-xl text-xs font-bold text-white disabled:opacity-50"
                :style="{ background: palette.grads[0] }"
                :disabled="!accountPanelName.trim() || !widgets.length || isSavingAccountPanel"
                @click="saveAccountPanel"
              >
                {{ isSavingAccountPanel ? 'Salvando…' : 'Salvar painel da conta' }}
              </button>
            </template>
            <span
              v-for="p in accountPanels"
              :key="p.id"
              class="flex items-center gap-1 pl-2.5 pr-1 h-8 rounded-xl border border-n-weak text-xs text-n-slate-11 bg-n-solid-1"
            >
              <button class="font-semibold hover:text-n-slate-12" title="Aplicar este painel no construtor" @click="applyAccountPanel(p)">
                {{ p.name }}
              </button>
              <template v-if="isAdmin">
                <button
                  class="w-5 h-5 rounded-md flex items-center justify-center text-sm leading-none"
                  :class="isMainPanel(p) ? '' : 'text-n-slate-9 hover:text-n-slate-12'"
                  :style="isMainPanel(p) ? { color: '#D4A017' } : {}"
                  :title="isMainPanel(p) ? 'Painel principal da conta — clique para voltar ao padrão' : 'Definir como painel principal da conta'"
                  @click="toggleMainPanel(p)"
                >
                  {{ isMainPanel(p) ? '★' : '☆' }}
                </button>
                <button
                  class="w-5 h-5 rounded-md flex items-center justify-center text-n-slate-9 hover:text-n-slate-12"
                  title="Atribuir ao time (trava o atendente neste painel)"
                  @click="openAssignModal"
                >
                  <span class="i-lucide-users text-[11px]" />
                </button>
                <button
                  class="w-5 h-5 rounded-md flex items-center justify-center text-n-slate-9 hover:text-red-500"
                  title="Excluir painel da conta"
                  @click="removeAccountPanel(p)"
                >
                  <span class="i-lucide-x text-[10px]" />
                </button>
              </template>
            </span>
            <span v-if="!accountPanels.length && !isAdmin" class="text-xs text-n-slate-9">
              nenhum painel da conta ainda — o admin salva por aqui.
            </span>
          </div>
        </div>

        <!-- predefinições LOCAIS: salvar o painel montado com nome e reaplicar -->
        <div class="border-t border-n-weak mt-3 pt-3">
          <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1.5">
            Minhas predefinições (só neste navegador)
          </p>
          <div class="flex items-center gap-1.5 flex-wrap">
            <input
              v-model="presetName"
              type="text"
              placeholder="nome da predefinição (ex: Manhã de segunda)"
              class="h-8 rounded-xl border border-n-weak bg-n-solid-1 px-2.5 text-xs text-n-slate-12"
              style="width: 16rem; margin-bottom: 0"
              @keyup.enter="savePreset"
            />
            <button
              class="px-3 h-8 rounded-xl text-xs font-bold text-white disabled:opacity-50"
              :style="{ background: palette.grads[0] }"
              :disabled="!presetName.trim() || !widgets.length"
              @click="savePreset"
            >
              Salvar predefinição
            </button>
            <span
              v-for="p in presets"
              :key="p.name"
              class="flex items-center gap-1 pl-2.5 pr-1 h-8 rounded-xl border border-n-weak text-xs text-n-slate-11 bg-n-solid-1"
            >
              <button class="font-semibold hover:text-n-slate-12" title="Aplicar esta predefinição" @click="applyPreset(p)">
                {{ p.name }}
              </button>
              <button class="w-5 h-5 rounded-md flex items-center justify-center text-n-slate-9 hover:text-red-500" title="Excluir" @click="removePreset(p)">
                <span class="i-lucide-x text-[10px]" />
              </button>
            </span>
          </div>
        </div>
      </div>

      <!-- grade magnética de 12 colunas -->
      <TransitionGroup
        tag="div"
        name="magnet"
        class="grid grid-cols-1 sm:grid-cols-12 gap-4"
      >
        <div
          v-for="(w, wi) in widgets"
          :key="w.key"
          class="magnet-card relative rounded-2xl overflow-hidden"
          :class="[SIZE_CLASS[w.size], editing ? 'cursor-grab active:cursor-grabbing outline-dashed outline-2 outline-offset-2' : '']"
          :style="editing ? { outlineColor: 'rgba(148, 163, 184, 0.5)' } : {}"
          :draggable="editing"
          @dragstart="onDragStart(wi)"
          @dragenter.prevent="onDragEnter(wi)"
          @dragover.prevent
          @dragend="onDragEnd"
        >
          <!-- controles do card (modo edição) -->
          <div v-if="editing" class="absolute top-1.5 right-1.5 z-10 flex items-center gap-1">
            <button
              class="w-6 h-6 rounded-lg bg-black/25 text-white text-[9px] font-black flex items-center justify-center hover:bg-black/40"
              title="Mudar o tamanho (P → M → G)"
              @click.stop="cycleSize(w)"
            >
              {{ w.size === 'sm' ? 'P' : w.size === 'md' ? 'M' : 'G' }}
            </button>
            <button
              class="w-6 h-6 rounded-lg bg-black/25 text-white flex items-center justify-center hover:bg-red-500"
              title="Remover do painel"
              @click.stop="removeWidget(wi)"
            >
              <span class="i-lucide-x text-xs" />
            </button>
          </div>

          <!-- KPI -->
          <div v-if="metaOf(w.key).kind === 'kpi'" class="h-full p-4 text-white" :style="{ background: gradFor(wi) }">
            <span :class="metaOf(w.key).icon" class="text-lg opacity-90" />
            <p class="text-3xl font-black leading-tight mt-1.5">{{ kpiValue(w.key) }}</p>
            <p class="text-[11px] opacity-90">{{ metaOf(w.key).label }}</p>
          </div>

          <!-- Atalho de DASHBOARD (clique abre o ambiente) -->
          <button
            v-else-if="metaOf(w.key).kind === 'dash'"
            class="h-full w-full p-4 text-white text-left relative overflow-hidden"
            :style="{ background: gradFor(wi) }"
            @click="openDash(w)"
          >
            <span :class="metaOf(w.key).icon" class="absolute -right-2 -bottom-3 text-[56px] text-white/15 pointer-events-none" />
            <span :class="metaOf(w.key).icon" class="text-lg opacity-90" />
            <p class="text-sm font-bold leading-tight mt-1.5">{{ metaOf(w.key).label }}</p>
            <p class="text-[11px] opacity-90 mt-0.5 flex items-center gap-1">
              abrir dashboard <span class="i-lucide-arrow-right text-[10px]" />
            </p>
          </button>

          <!-- Metas do mês -->
          <div v-else-if="metaOf(w.key).kind === 'goals'" class="h-full bg-n-solid-2 border border-n-weak rounded-2xl p-4">
            <p class="text-xs font-bold text-n-slate-12 mb-2 flex items-center gap-1.5">
              <span class="i-lucide-target text-sm" :style="{ color: '#B8860B' }" /> Metas do mês
            </p>
            <div v-if="goalRows.length" class="space-y-2">
              <div v-for="g in goalRows" :key="g.key">
                <div class="flex items-center justify-between text-[11px] mb-0.5">
                  <span class="text-n-slate-11 truncate">{{ g.label }}</span>
                  <b class="text-n-slate-12">{{ g.current.toLocaleString('pt-BR') }}/{{ g.target.toLocaleString('pt-BR') }}</b>
                </div>
                <div class="h-2 bg-n-alpha-1 rounded-full overflow-hidden">
                  <div class="h-full rounded-full transition-all duration-700" :style="{ width: `${g.pct}%`, background: gradFor(wi) }" />
                </div>
              </div>
            </div>
            <p v-else class="text-[11px] text-n-slate-9">defina as metas no Painel de Metas.</p>
          </div>

          <!-- Radar -->
          <div v-else-if="metaOf(w.key).kind === 'radar'" class="h-full bg-n-solid-2 border border-n-weak rounded-2xl p-4">
            <p class="text-xs font-bold text-n-slate-12 mb-2 flex items-center gap-1.5">
              <span class="i-lucide-radar text-sm" style="color: #059669" /> Radar de Oportunidades
            </p>
            <p v-if="!radarAlerts.length" class="text-[11px] text-n-slate-9">nenhum paciente quente esperando. 🎉</p>
            <div v-else class="space-y-1.5">
              <p class="text-2xl font-black" style="color: #059669">{{ radarAlerts.length }}</p>
              <p class="text-[11px] text-n-slate-10 -mt-1 mb-1">paciente(s) quente(s) sem atendimento</p>
              <div v-for="a in radarAlerts.slice(0, 3)" :key="a.conversation_id" class="text-[11px] text-n-slate-11 truncate">
                • {{ a.contact_name }}
              </div>
            </div>
          </div>

          <!-- Tarefas -->
          <div v-else-if="metaOf(w.key).kind === 'tasks'" class="h-full bg-n-solid-2 border border-n-weak rounded-2xl p-4">
            <p class="text-xs font-bold text-n-slate-12 mb-2 flex items-center gap-1.5">
              <span class="i-lucide-list-checks text-sm" style="color: #B8860B" /> Tarefas esperando você
            </p>
            <p v-if="!myTasks.length" class="text-[11px] text-n-slate-9">nada pendente. ✨</p>
            <div v-else class="space-y-1">
              <p v-for="t in myTasks.slice(0, 4)" :key="t.id" class="text-[11px] text-n-slate-11 truncate">• {{ t.title }}</p>
            </div>
          </div>

          <!-- Próximas consultas -->
          <div v-else-if="metaOf(w.key).kind === 'appointments'" class="h-full bg-n-solid-2 border border-n-weak rounded-2xl p-4">
            <p class="text-xs font-bold text-n-slate-12 mb-2 flex items-center gap-1.5">
              <span class="i-lucide-calendar-range text-sm" style="color: #0369A1" /> Próximas consultas
            </p>
            <p v-if="!nextAppointments.length" class="text-[11px] text-n-slate-9">nenhuma consulta futura marcada.</p>
            <div v-else class="space-y-1">
              <p v-for="a in nextAppointments.slice(0, 4)" :key="a.id" class="text-[11px] text-n-slate-11 truncate">
                <b :style="{ color: '#0369A1' }">{{ fmtDue(a.due_at) }}</b> · {{ (a.title || '').replace(/^Consulta:\s*/i, '') }}
              </p>
            </div>
          </div>

          <!-- Meta de tempo -->
          <div v-else-if="metaOf(w.key).kind === 'response'" class="h-full p-4 text-white" :style="{ background: gradFor(wi) }">
            <span class="i-lucide-timer text-lg opacity-90" />
            <template v-if="myResponse && myResponse.replies">
              <p class="text-3xl font-black leading-tight mt-1.5">{{ String(myResponse.avg_minutes).replace('.', ',') }} min</p>
              <p class="text-[11px] opacity-90">meu tempo médio · {{ myResponse.within_rate }}% dentro da meta</p>
            </template>
            <template v-else>
              <p class="text-sm font-bold mt-1.5">Sem respostas no período</p>
              <p class="text-[11px] opacity-90">minha meta de tempo</p>
            </template>
          </div>
        </div>
      </TransitionGroup>

      <p v-if="!widgets.length" class="text-center text-sm text-n-slate-9 py-16">
        painel vazio — clique em <b>🧲 Personalizar</b> e adicione seus elementos.
      </p>
    </div>

    <!-- Admin: atribuir painéis ao time (mesmo padrão do modal do Meu Painel) -->
    <div
      v-if="showAssignModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      @click.self="showAssignModal = false"
    >
      <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-md max-h-[85vh] flex flex-col overflow-hidden">
        <div class="h-1.5 w-full flex-shrink-0" :style="{ background: palette.grads[0] }" />
        <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak flex-shrink-0">
          <h2 class="text-base font-semibold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-users text-n-brand" />
            Atribuir painéis ao time
          </h2>
          <button class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl" @click="showAssignModal = false" />
        </div>
        <div class="flex-1 overflow-y-auto p-5 space-y-2">
          <p class="text-xs text-n-slate-10 mb-2">
            A pessoa abre o Meu Painel já no painel dela (e só vê esse).
            "— livre —" = pode alternar entre todos.
          </p>
          <div v-for="agent in teamAgents" :key="agent.id" class="flex items-center gap-2">
            <span class="text-sm text-n-slate-12 flex-1 truncate">{{ agent.name }}</span>
            <select
              v-model="assignDraft[String(agent.id)]"
              class="h-8 text-xs border border-n-weak rounded-lg px-2 bg-n-solid-2 text-n-slate-12"
            >
              <option value="">— livre —</option>
              <option v-for="p in FIXED_PANELS" :key="p.key" :value="p.key">{{ p.label }}</option>
              <option v-for="p in accountPanels" :key="`custom:${p.id}`" :value="`custom:${p.id}`">{{ p.name }}</option>
            </select>
          </div>
        </div>
        <div class="px-5 py-4 border-t border-n-weak flex gap-2 flex-shrink-0">
          <button
            class="flex-1 text-white rounded-lg py-2 text-sm font-medium disabled:opacity-50"
            :style="{ background: palette.grads[0] }"
            :disabled="isSavingAssign"
            @click="saveAssignments"
          >
            {{ isSavingAssign ? 'Salvando…' : 'Salvar' }}
          </button>
          <button class="px-4 border border-n-weak rounded-lg py-2 text-sm text-n-slate-11" @click="showAssignModal = false">
            Cancelar
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* o ÍMÃ: quando a ordem muda, os cards DESLIZAM para o novo lugar */
.magnet-move {
  transition: transform 0.35s cubic-bezier(0.22, 1, 0.36, 1);
}
.magnet-card {
  min-height: 96px;
}
</style>
