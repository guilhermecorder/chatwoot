<script setup>
// 🧲 CONSTRUTOR (item 57): cada pessoa monta o próprio painel com os
// indicadores que já existem no sistema. Drag-and-drop com ÍMÃ (os cards
// deslizam magneticamente para o lugar), tamanhos P/M/G numa grade de 12
// colunas pré-configurada para ficar bonita, e escolha de paleta de cores.
// O layout fica salvo por pessoa (neste navegador).
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { frontendURL } from 'dashboard/helper/URLHelper';
import CrmAPI from 'dashboard/api/crm';

const currentUser = useMapGetter('getCurrentUser');
const route = useRoute();
const router = useRouter();

// ── catálogo COMPLETO (pedido 19/07): TODOS os indicadores que o sistema
// já calcula + os blocos vivos + atalhos para TODOS os dashboards criados,
// organizados em seções para montar o painel do seu jeito ──
const CATALOG = [
  // Indicadores de agora (independem do período)
  { section: 'Indicadores — agora', key: 'open_conversations', label: 'Conversas abertas', icon: 'i-lucide-message-circle', kind: 'kpi' },
  { section: 'Indicadores — agora', key: 'unanswered', label: 'Aguardando resposta', icon: 'i-lucide-clock-alert', kind: 'kpi' },
  { section: 'Indicadores — agora', key: 'appointments_today', label: 'Consultas hoje', icon: 'i-lucide-calendar-check', kind: 'kpi' },
  { section: 'Indicadores — agora', key: 'new_contacts_30d', label: 'Novos leads (30 dias)', icon: 'i-lucide-user-plus', kind: 'kpi' },
  { section: 'Indicadores — agora', key: 'appointments_30d', label: 'Agendamentos (30 dias)', icon: 'i-lucide-calendar-plus', kind: 'kpi' },
  // Indicadores do dia (processo inteiro — mesmos números do Meu Painel)
  { section: 'Indicadores — hoje', key: 'new_leads', label: 'Novos leads (hoje)', icon: 'i-lucide-user-round-plus', kind: 'kpi' },
  { section: 'Indicadores — hoje', key: 'appointments_created', label: 'Consultas agendadas (hoje)', icon: 'i-lucide-calendar-plus-2', kind: 'kpi' },
  { section: 'Indicadores — hoje', key: 'appointments_booked', label: 'Marcadas na Agenda (hoje)', icon: 'i-lucide-notebook-pen', kind: 'kpi' },
  { section: 'Indicadores — hoje', key: 'appointments_same_day', label: 'Chegou e agendou no dia', icon: 'i-lucide-zap', kind: 'kpi' },
  { section: 'Indicadores — hoje', key: 'booking_conversion', label: 'Taxa de agendamento', icon: 'i-lucide-percent', kind: 'kpi', pct: true },
  { section: 'Indicadores — hoje', key: 'show_rate', label: 'Comparecimento', icon: 'i-lucide-door-open', kind: 'kpi', pct: true },
  { section: 'Indicadores — hoje', key: 'surgery_indications', label: 'Indicações de cirurgia', icon: 'i-lucide-stethoscope', kind: 'kpi' },
  { section: 'Indicadores — hoje', key: 'surgeries_booked', label: 'Cirurgias agendadas', icon: 'i-lucide-calendar-heart', kind: 'kpi' },
  { section: 'Indicadores — hoje', key: 'closing_rate', label: 'Fechamento pós-indicação', icon: 'i-lucide-handshake', kind: 'kpi', pct: true },
  { section: 'Indicadores — hoje', key: 'surgeries_done', label: 'Cirurgias realizadas', icon: 'i-lucide-heart-pulse', kind: 'kpi' },
  { section: 'Indicadores — hoje', key: 'nps_satisfaction', label: 'NPS — satisfação', icon: 'i-lucide-star', kind: 'kpi', pct: true },
  // Blocos vivos
  { section: 'Blocos vivos', key: 'goals', label: 'Metas do mês', icon: 'i-lucide-target', kind: 'goals' },
  { section: 'Blocos vivos', key: 'radar', label: 'Radar de Oportunidades', icon: 'i-lucide-radar', kind: 'radar' },
  { section: 'Blocos vivos', key: 'tasks', label: 'Tarefas esperando você', icon: 'i-lucide-list-checks', kind: 'tasks' },
  { section: 'Blocos vivos', key: 'next_appointments', label: 'Próximas consultas', icon: 'i-lucide-calendar-range', kind: 'appointments' },
  { section: 'Blocos vivos', key: 'response_goal', label: 'Minha meta de tempo', icon: 'i-lucide-timer', kind: 'response' },
  // Dashboards criados (atalhos vivos — clique e abra)
  { section: 'Dashboards', key: 'dash_crm', label: 'Dashboard CRM', icon: 'i-lucide-layout-dashboard', kind: 'dash', to: 'reports/crm_dashboard' },
  { section: 'Dashboards', key: 'dash_campanhas', label: 'Painel de Campanhas', icon: 'i-lucide-megaphone', kind: 'dash', to: 'crm/campaigns?tab=panel' },
  { section: 'Dashboards', key: 'dash_funil', label: 'Funil de Tráfego', icon: 'i-lucide-filter', kind: 'dash', to: 'reports/traffic_funnel' },
  { section: 'Dashboards', key: 'dash_medicos', label: 'Dashboard dos Médicos', icon: 'i-lucide-stethoscope', kind: 'dash', to: 'reports/doctors' },
  { section: 'Dashboards', key: 'dash_agentes', label: 'Dashboard dos Agentes', icon: 'i-lucide-users', kind: 'dash', to: 'reports/agents_dashboard' },
  { section: 'Dashboards', key: 'dash_agenda', label: 'Dashboard da Agenda', icon: 'i-lucide-calendar-days', kind: 'dash', to: 'reports/agenda_dashboard' },
  { section: 'Dashboards', key: 'dash_google', label: 'Google (Ads + GA4)', icon: 'i-lucide-trending-up', kind: 'dash', to: 'reports/google_dashboard' },
  { section: 'Dashboards', key: 'dash_ads', label: 'Anúncios (Meta)', icon: 'i-lucide-badge-dollar-sign', kind: 'dash', to: 'reports/ads' },
  { section: 'Dashboards', key: 'dash_whatsapp', label: 'Saúde do WhatsApp', icon: 'i-lucide-message-square-heart', kind: 'dash', to: 'reports/whatsapp_health' },
  { section: 'Dashboards', key: 'dash_financeiro', label: 'Gestão Financeira', icon: 'i-lucide-wallet', kind: 'dash', to: 'finance' },
  { section: 'Dashboards', key: 'dash_metas', label: 'Painel de Metas', icon: 'i-lucide-goal', kind: 'dash', to: 'goals' },
  { section: 'Dashboards', key: 'dash_estrategia', label: 'Painel Estratégico', icon: 'i-lucide-compass', kind: 'dash', to: 'strategy' },
  { section: 'Dashboards', key: 'dash_ia', label: 'Painel dos agentes de IA', icon: 'i-lucide-activity', kind: 'dash', to: 'cevico-automations?tab=painel_ia' },
];
const CATALOG_SECTIONS = [...new Set(CATALOG.map(c => c.section))];

// ── paletas de cor (o mesmo indicador, o clima que a pessoa quiser) ──
const PALETTES = [
  { key: 'cevico', label: 'CEVICO', grads: ['linear-gradient(135deg, #0F5FA6, #7C3AED)', 'linear-gradient(135deg, #B8860B, #D4A017)', 'linear-gradient(135deg, #047857, #34D399)', 'linear-gradient(135deg, #0284C7, #38BDF8)'] },
  { key: 'dourado', label: 'Dourado', grads: ['linear-gradient(135deg, #92600A, #D4AF37)', 'linear-gradient(135deg, #B8860B, #F1C40F)', 'linear-gradient(135deg, #7C5E10, #D4A017)', 'linear-gradient(135deg, #A16207, #FACC15)'] },
  { key: 'oceano', label: 'Oceano', grads: ['linear-gradient(135deg, #075985, #38BDF8)', 'linear-gradient(135deg, #0E7490, #67E8F9)', 'linear-gradient(135deg, #1D4ED8, #93C5FD)', 'linear-gradient(135deg, #0F766E, #5EEAD4)'] },
  { key: 'verde', label: 'Verde vivo', grads: ['linear-gradient(135deg, #047857, #4ADE80)', 'linear-gradient(135deg, #15803D, #86EFAC)', 'linear-gradient(135deg, #0F766E, #2DD4BF)', 'linear-gradient(135deg, #3F6212, #A3E635)'] },
  { key: 'rosa', label: 'Flor del Mar', grads: ['linear-gradient(135deg, #9D174D, #F472B6)', 'linear-gradient(135deg, #BE123C, #FDA4AF)', 'linear-gradient(135deg, #7C3AED, #C4B5FD)', 'linear-gradient(135deg, #C2410C, #FDBA74)'] },
];

// tamanhos na grade de 12 colunas (P/M/G) — o "espaço pré-configurado"
// (classes por extenso: o Tailwind só gera o que enxerga literalmente)
const SIZE_CLASS = { sm: 'sm:col-span-3', md: 'sm:col-span-6', lg: 'sm:col-span-12' };
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

const palette = computed(() => PALETTES.find(p => p.key === paletteKey.value) || PALETTES[0]);
const gradFor = idx => palette.value.grads[idx % palette.value.grads.length];
const metaOf = key => CATALOG.find(c => c.key === key) || {};
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

        <!-- predefinições: salvar o painel montado com nome e reaplicar -->
        <div class="border-t border-n-weak mt-3 pt-3">
          <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1.5">
            Predefinições — salve este painel e troque com um clique
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
