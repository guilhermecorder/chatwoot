<script setup>
// Dashboard CEVICO — paleta oficial: azul #0F5FA6, branco, roxo #7C3AED,
// dourado #D4A017; verde-limão #84CC16 reservado para o que é MUITO bom
// (valor em pipeline, cirurgias). "Conversa" no lugar de "lead".
import { ref, computed, watch, onMounted } from 'vue';
import { useStore } from 'dashboard/composables/store';
import {
  Chart as ChartJS,
  Title, Tooltip, Legend,
  BarElement, CategoryScale, LinearScale,
  ArcElement,
  PointElement, LineElement, Filler,
} from 'chart.js';
import { Bar, Doughnut } from 'vue-chartjs';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import { useCevicoGoals } from 'dashboard/composables/useCevicoGoals';

ChartJS.register(
  Title, Tooltip, Legend,
  BarElement, CategoryScale, LinearScale,
  ArcElement,
  PointElement, LineElement, Filler,
);

const props = defineProps({
  pipeline: { type: Object, required: true },
});

const AZUL = '#0F5FA6';
const ROXO = '#7C3AED';
const OURO = '#D4A017';
const LIME = '#84CC16';
const PALETTE = [AZUL, ROXO, OURO, LIME, '#3B82F6', '#A78BFA', '#F0C420', '#22D3EE', '#EA580C', '#10B981', '#F472B6', '#94A3B8'];

const store   = useStore();
const data    = ref(null);
const loading = ref(false);
const error   = ref(false);

const PERIODS = [
  { key: 'today',     preset: 'today',     label: 'Hoje' },
  { key: 'yesterday', preset: 'yesterday', label: 'Ontem' },
  { key: 'week',      preset: 'week',      label: 'Essa semana' },
  { key: '30',        period: 30,          label: '30 dias' },
  { key: '90',        period: 90,          label: '90 dias' },
  { key: '365',       period: 365,         label: '1 ano' },
  { key: '1095',      period: 1095,        label: '3 anos' },
];
const selectedPeriodKey = ref('30');
const selectedPeriod = computed(() => PERIODS.find(p => p.key === selectedPeriodKey.value));

// ── Load ─────────────────────────────────────────────────────────────

const load = async () => {
  loading.value = true;
  error.value   = false;
  try {
    data.value = await store.dispatch('crm/fetchDashboard', {
      pipelineId: props.pipeline.id,
      period: selectedPeriod.value?.period,
      preset: selectedPeriod.value?.preset,
    });
  } catch {
    error.value = true;
  } finally {
    loading.value = false;
  }
};

// metas oficiais do mês (Painel de Metas) → selos de recorde/meta nos KPIs
const goals = useCevicoGoals();

onMounted(() => {
  load();
  goals.load();
});
watch(selectedPeriodKey, load);
watch(() => props.pipeline?.id, load);

// ── Helpers ───────────────────────────────────────────────────────────

const formatDuration = (mins) => {
  if (!mins || mins <= 0) return '—';
  if (mins < 60)  return `${mins}min`;
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  if (h < 24) return m > 0 ? `${h}h ${m}min` : `${h}h`;
  const d = Math.floor(h / 24);
  const rh = h % 24;
  return rh > 0 ? `${d}d ${rh}h` : `${d}d`;
};

const formatSeconds = (secs) => {
  if (!secs || secs <= 0) return '—';
  if (secs < 60) return `${Math.round(secs)}s`;
  return formatDuration(Math.round(secs / 60));
};

const formatCurrency = (val) =>
  val > 0
    ? 'R$ ' + Number(val).toLocaleString('pt-BR', { maximumFractionDigits: 0 })
    : 'R$ 0';

// ── Charts ────────────────────────────────────────────────────────────

// fatia com gradiente vertical (mesmo aspecto "macio e brilhante" do donut
// de Tarefas): topo mais claro, base na cor cheia
const shinySlices = colors => ctx => {
  const base = colors[ctx.dataIndex % colors.length];
  const { chartArea, ctx: c } = ctx.chart;
  if (!chartArea) return base;
  const g = c.createLinearGradient(chartArea.left, chartArea.top, chartArea.left, chartArea.bottom);
  g.addColorStop(0, base + '99');
  g.addColorStop(1, base);
  return g;
};

const CHART_OPTIONS_BASE = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: { legend: { display: false } },
  animation: { duration: 400 },
};

// Conversas ao longo do tempo — colunas arredondadas, 3 séries sobrepostas
const timelineChart = computed(() => {
  if (!data.value?.created_over_time) return null;
  const t = data.value.created_over_time;
  const labels = t.map(d => {
    const dt = new Date(d.date + 'T12:00:00');
    return dt.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
  });
  const barBase = { borderRadius: 8, borderSkipped: false, maxBarThickness: 26 };
  return {
    data: {
      labels,
      datasets: [
        { label: 'Novas conversas', data: t.map(d => d.count), backgroundColor: AZUL + 'E6', ...barBase },
        { label: 'Chegaram a agendar', data: t.map(d => d.agendamentos), backgroundColor: OURO + 'E6', ...barBase },
        { label: 'Chegaram à cirurgia', data: t.map(d => d.cirurgias), backgroundColor: LIME + 'E6', ...barBase },
      ],
    },
    options: {
      ...CHART_OPTIONS_BASE,
      plugins: {
        legend: { display: true, position: 'bottom', labels: { boxWidth: 12, padding: 14, font: { size: 11 } } },
        tooltip: { callbacks: { label: ctx => ` ${ctx.dataset.label}: ${ctx.raw}` } },
      },
      scales: {
        y: { beginAtZero: true, ticks: { stepSize: 1 }, grid: { color: 'rgba(120,140,180,0.12)' } },
        x: { grid: { display: false }, ticks: { maxTicksLimit: 12 } },
      },
    },
  };
});

// Conversas por caixa de entrada (doughnut)
const inboxChart = computed(() => {
  if (!data.value?.by_inbox?.length) return null;
  const o = data.value.by_inbox;
  return {
    data: {
      labels: o.map(x => x.inbox),
      datasets: [{
        data: o.map(x => x.count),
        backgroundColor: shinySlices(PALETTE),
        borderWidth: 0,
        borderRadius: 14,
        spacing: 3,
        hoverOffset: 6,
      }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { display: true, position: 'bottom', labels: { padding: 12, boxWidth: 12, font: { size: 11 } } },
        tooltip: { callbacks: { label: ctx => ` ${ctx.raw} conversas (${ctx.label})` } },
      },
      cutout: '66%',
      animation: { duration: 500, easing: 'easeOutQuart' },
    },
  };
});

// Etiquetas (doughnut com volume e %)
const labelChart = computed(() => {
  const items = data.value?.by_label?.items || [];
  if (!items.length) return null;
  return {
    data: {
      labels: items.map(x => x.label),
      datasets: [{
        data: items.map(x => x.count),
        backgroundColor: shinySlices(PALETTE),
        borderWidth: 0,
        borderRadius: 14,
        spacing: 3,
        hoverOffset: 6,
      }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { display: false },
        tooltip: {
          callbacks: {
            label: ctx => {
              const item = items[ctx.dataIndex];
              return ` ${item.label}: ${item.count} (${item.pct}%)`;
            },
          },
        },
      },
      cutout: '66%',
      animation: { duration: 500, easing: 'easeOutQuart' },
    },
  };
});

// Conversas por etapa (horizontal)
const funnelChart = computed(() => {
  if (!data.value?.funnel) return null;
  const f = data.value.funnel;
  return {
    data: {
      labels: f.map(s => s.stage_name),
      datasets: [{
        data: f.map(s => s.count),
        backgroundColor: f.map((_, i) => PALETTE[i % PALETTE.length] + 'DD'),
        borderRadius: 8,
        borderSkipped: false,
      }],
    },
    options: {
      ...CHART_OPTIONS_BASE,
      indexAxis: 'y',
      plugins: {
        ...CHART_OPTIONS_BASE.plugins,
        tooltip: { callbacks: { label: ctx => ` ${ctx.raw} conversas` } },
      },
      scales: {
        x: { ticks: { stepSize: 1 }, grid: { color: 'rgba(120,140,180,0.12)' } },
        y: { grid: { display: false } },
      },
    },
  };
});

// Valor em cada etapa do pipeline
const valueChart = computed(() => {
  if (!data.value?.value_by_stage) return null;
  const v = data.value.value_by_stage.filter(s => s.value > 0);
  if (!v.length) return null;
  return {
    data: {
      labels: v.map(s => s.stage_name),
      datasets: [{
        data: v.map(s => s.value),
        backgroundColor: v.map((_, i) => [AZUL, ROXO, OURO, LIME][i % 4] + 'E6'),
        borderRadius: 10,
        borderSkipped: false,
        maxBarThickness: 56,
      }],
    },
    options: {
      ...CHART_OPTIONS_BASE,
      plugins: {
        ...CHART_OPTIONS_BASE.plugins,
        tooltip: { callbacks: { label: ctx => ' R$ ' + Number(ctx.raw).toLocaleString('pt-BR', { maximumFractionDigits: 0 }) } },
      },
      scales: {
        y: { grid: { color: 'rgba(120,140,180,0.12)' } },
        x: { grid: { display: false } },
      },
    },
  };
});

// Tempo médio por etapa
const timeChart = computed(() => {
  if (!data.value?.avg_time_by_stage) return null;
  const t = data.value.avg_time_by_stage.filter(s => s.avg_minutes > 0);
  if (!t.length) return null;
  return {
    data: {
      labels: t.map(s => s.stage_name),
      datasets: [{
        data: t.map(s => s.avg_minutes),
        backgroundColor: t.map((_, i) => PALETTE[i % PALETTE.length] + 'B3'),
        borderRadius: 10,
        borderSkipped: false,
        maxBarThickness: 56,
      }],
    },
    options: {
      ...CHART_OPTIONS_BASE,
      plugins: {
        ...CHART_OPTIONS_BASE.plugins,
        tooltip: { callbacks: { label: ctx => ' ' + formatDuration(ctx.raw) } },
      },
      scales: {
        y: { grid: { color: 'rgba(120,140,180,0.12)' }, ticks: { callback: v => formatDuration(v) } },
        x: { grid: { display: false } },
      },
    },
  };
});

// cores das 5 faixas de NPS (promotores → detratores)
const NPS_BAND_GRADS = [
  ['#059669', '#34D399'],
  ['#65A30D', '#A3E635'],
  ['#B8860B', '#D4A017'],
  ['#EA580C', '#FB923C'],
  ['#DC2626', '#F87171'],
];

// ── Responsividade ────────────────────────────────────────────────────
const resp = computed(() => data.value?.responsiveness ?? null);

// gradientes harmônicos (azul → roxo → dourado → laranja → verde → ciano),
// seguindo a paleta oficial do dashboard
// tema "Flor del Mar": fúcsia vibrante sobre azul-mar (referências)
const RESP_GRADS = [
  ['#9D174D', '#EC4899'],
  ['#1D4ED8', '#60A5FA'],
  ['#BE185D', '#F472B6'],
  ['#0369A1', '#38BDF8'],
  ['#DB2777', '#F9A8D4'],
  ['#0D9488', '#2DD4BF'],
  ['#7C3AED', '#A78BFA'],
  ['#B8860B', '#D4A017'],
];

const respMilestones = computed(() => {
  if (!resp.value?.stages?.length) return [];
  const rows = resp.value.stages.slice(1);
  // largura relativa à MAIOR etapa (não ao total) — barras cheias e
  // legíveis, com o % real do total escrito dentro
  const max = Math.max(...rows.map(s => s.reached), 1);
  return rows.map((s, i) => ({
    name: s.stage_name,
    grad: RESP_GRADS[i % RESP_GRADS.length],
    reached: s.reached,
    pct: s.reached_pct,
    // pelo menos 33% preenchido: barra curta demais fica feia de ler
    width: Math.max((s.reached / max) * 100, 33),
  }));
});

// ── Atendimento por agente ────────────────────────────────────────────
const selectedAgentId = ref('all');

const agentRows = computed(() => data.value?.agents?.rows ?? []);

const agentView = computed(() => {
  if (selectedAgentId.value === 'all') {
    return {
      name: 'Todos os agentes',
      open: agentRows.value.reduce((a, r) => a + r.open, 0) + (data.value?.agents?.unassigned?.open || 0),
      unanswered: agentRows.value.reduce((a, r) => a + r.unanswered, 0) + (data.value?.agents?.unassigned?.unanswered || 0),
      avg_first_response_seconds: (() => {
        const vals = agentRows.value.map(r => r.avg_first_response_seconds).filter(v => v);
        return vals.length ? vals.reduce((a, v) => a + v, 0) / vals.length : null;
      })(),
    };
  }
  return agentRows.value.find(r => r.id === selectedAgentId.value) || null;
});
</script>

<template>
  <div class="bg-n-solid-1 p-8 min-h-full">

    <!-- Header do dashboard -->
    <div class="flex items-center justify-between mb-8 flex-wrap gap-4">
      <div>
        <h2 class="text-lg font-bold text-n-slate-12">Dashboard — {{ pipeline.name }}</h2>
        <p class="text-xs text-n-slate-10 mt-0.5">Métricas automáticas com base nas conversas do funil</p>
      </div>
      <!-- Seletor de período -->
      <div class="flex items-center gap-1.5 bg-n-solid-2 border border-n-weak rounded-xl p-1 flex-wrap">
        <button
          v-for="p in PERIODS"
          :key="p.key"
          class="px-3 py-1.5 text-xs font-medium rounded-lg transition-colors"
          :class="selectedPeriodKey === p.key
            ? 'text-white shadow'
            : 'text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1'"
          :style="selectedPeriodKey === p.key ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' } : {}"
          @click="selectedPeriodKey = p.key"
        >
          {{ p.label }}
        </button>
      </div>
    </div>

    <!-- Loading -->
    <div v-if="loading" class="flex items-center justify-center py-24 text-n-slate-10">
      <span class="i-lucide-loader-2 animate-spin text-2xl mr-2" />
      <span class="text-sm">Carregando métricas...</span>
    </div>

    <!-- Error -->
    <div v-else-if="error" class="flex flex-col items-center justify-center py-24 text-n-slate-10">
      <span class="i-lucide-alert-circle text-3xl mb-2 text-red-400" />
      <p class="text-sm mb-3">Erro ao carregar o dashboard.</p>
      <button class="text-xs text-n-brand hover:underline" @click="load">Tentar novamente</button>
    </div>

    <!-- Content -->
    <div v-else-if="data">

      <!-- KPIs (padrão CEVICO: DashKpi c/ selos de recorde/meta do mês) -->
      <div class="grid grid-cols-2 lg:grid-cols-3 xl:grid-cols-6 gap-5 mb-10">
        <DashKpi
          label="Total no funil"
          :value="data.kpis.total_leads"
          sub="conversas"
          from="#0F5FA6"
          to="#0B4A82"
        />
        <DashKpi
          label="Novas no período"
          :value="data.kpis.new_in_period"
          sub="conversas"
          value-color="#0F5FA6"
          :state="goals.stateFor('new_leads')"
          :goal="goals.goalFor('new_leads')"
        />
        <DashKpi
          label="Valor em pipeline"
          :value="Math.round(data.kpis.total_value || 0)"
          prefix="R$ "
          sub="total"
          from="#65A30D"
          to="#84CC16"
        />
        <DashKpi
          label="Fechamentos"
          :value="data.kpis.closed_count"
          sub="conversas"
          from="#B8860B"
          to="#D4A017"
        />
        <DashKpi
          label="Taxa de fechamento"
          :value="`${data.kpis.close_rate}%`"
          sub="conversão"
          from="#5B21B6"
          to="#7C3AED"
        />
        <DashKpi
          label="Tempo médio"
          :value="formatDuration(data.kpis.avg_conversion_minutes)"
          sub="de conversão"
        />
      </div>

      <!-- Atendimento por agente -->
      <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-10">
        <div class="flex items-center justify-between flex-wrap gap-3 mb-5">
          <h3 class="text-sm font-bold text-n-slate-12 flex items-center gap-2">
            <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)">
              <span class="i-lucide-headset text-white text-sm" />
            </span>
            Atendimento por agente
          </h3>
          <select
            v-model="selectedAgentId"
            class="h-9 text-sm border border-n-weak rounded-xl px-3 bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand"
          >
            <option value="all">Todos os agentes</option>
            <option v-for="a in agentRows" :key="a.id" :value="a.id">{{ a.name }}</option>
          </select>
        </div>

        <div v-if="agentView" class="grid grid-cols-1 sm:grid-cols-3 gap-5">
          <div class="rounded-xl p-4 bg-n-alpha-1" style="border-left: 4px solid #0F5FA6">
            <p class="text-xs text-n-slate-10 mb-1">Conversas em aberto</p>
            <p class="text-2xl font-bold text-n-slate-12">{{ agentView.open }}</p>
          </div>
          <div class="rounded-xl p-4 bg-n-alpha-1" style="border-left: 4px solid #D4A017">
            <p class="text-xs text-n-slate-10 mb-1">Sem resposta (paciente aguardando)</p>
            <p class="text-2xl font-bold" :style="{ color: agentView.unanswered > 0 ? '#B8860B' : undefined }">
              {{ agentView.unanswered }}
            </p>
          </div>
          <div class="rounded-xl p-4 bg-n-alpha-1" style="border-left: 4px solid #7C3AED">
            <p class="text-xs text-n-slate-10 mb-1">Tempo de 1ª resposta (período)</p>
            <p class="text-2xl font-bold text-n-slate-12">{{ formatSeconds(agentView.avg_first_response_seconds) }}</p>
          </div>
        </div>

        <p v-if="selectedAgentId === 'all' && data.agents?.unassigned?.open" class="text-[11px] text-n-slate-9 mt-3">
          Inclui {{ data.agents.unassigned.open }} conversas abertas sem agente atribuído.
        </p>
      </div>

      <!-- Responsividade das conversas -->
      <div v-if="resp && resp.total > 0" class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-10">
        <div class="flex items-center justify-between flex-wrap gap-2 mb-5">
          <h3 class="text-sm font-bold text-n-slate-12 flex items-center gap-2">
            <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)">
              <span class="i-lucide-activity text-white text-sm" />
            </span>
            Responsividade das conversas
          </h3>
          <span class="text-xs text-n-slate-10">% = quanto do total chegou até a etapa · barras proporcionais entre si</span>
        </div>

        <div class="space-y-2.5">
          <div v-for="m in respMilestones" :key="m.name" class="flex items-center gap-3">
            <div class="w-40 text-right flex-shrink-0">
              <p class="text-xs text-n-slate-12 font-medium truncate">{{ m.name }}</p>
            </div>
            <div class="flex-1 h-9 rounded-xl bg-n-alpha-1 relative overflow-hidden">
              <div
                class="absolute inset-y-0 left-0 rounded-xl transition-all shadow-sm"
                :style="{ width: m.width + '%', background: `linear-gradient(90deg, ${m.grad[0]}, ${m.grad[1]})` }"
              />
              <div class="absolute inset-0 flex items-center">
                <span
                  v-if="m.width >= 34"
                  class="text-[11px] font-bold text-white drop-shadow pl-3"
                >
                  {{ m.pct }}% · {{ m.reached.toLocaleString('pt-BR') }} conversas
                </span>
                <span
                  v-else
                  class="text-[11px] font-bold whitespace-nowrap"
                  :style="{ marginLeft: `calc(${m.width}% + 10px)`, color: m.grad[0] }"
                >
                  {{ m.pct }}% · {{ m.reached.toLocaleString('pt-BR') }} conversas
                </span>
              </div>
            </div>
          </div>
        </div>

        <div class="mt-5 flex items-center gap-3 rounded-xl p-4 flex-wrap border-2" style="background: rgba(212,160,23,0.08); border-color: rgba(212,160,23,0.35)">
          <span class="i-lucide-user-x text-xl flex-shrink-0" style="color: #B8860B" />
          <div class="flex-1 min-w-0">
            <p class="text-sm font-bold text-n-slate-12">
              {{ resp.stuck.count }} conversas pouco responsivas ({{ resp.stuck.pct }}%)
            </p>
            <p class="text-xs text-n-slate-10">
              paradas em "{{ resp.stuck.stage_name }}" — não avançaram no funil. Público ideal para uma campanha de reativação.
            </p>
          </div>
          <button
            class="text-xs font-bold px-4 py-2 rounded-xl text-white hover:opacity-90 flex-shrink-0 shadow"
            style="background: linear-gradient(135deg, #B8860B, #D4A017)"
            @click="$router.push({ name: 'crm_campaigns' })"
          >
            Criar campanha →
          </button>
        </div>
      </div>

      <!-- Linha do tempo + Caixas de entrada -->
      <div class="grid grid-cols-1 xl:grid-cols-3 gap-6 mb-10">

        <!-- Conversas ao longo do tempo (colunas arredondadas, 3 séries) -->
        <div class="xl:col-span-2 bg-n-solid-2 border border-n-weak rounded-2xl p-6">
          <h3 class="text-sm font-bold text-n-slate-12 mb-1">Conversas ao longo do tempo</h3>
          <p class="text-[11px] text-n-slate-10 mb-4">
            pela data em que o lead chegou — e, desses leads, quantos avançaram até agendar ou operar
          </p>
          <div class="h-64">
            <Bar
              v-if="timelineChart"
              :data="timelineChart.data"
              :options="timelineChart.options"
            />
            <div v-else class="flex items-center justify-center h-full text-n-slate-10 text-sm">
              Sem dados no período
            </div>
          </div>
        </div>

        <!-- Conversas por caixa de entrada -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6">
          <h3 class="text-sm font-bold text-n-slate-12 mb-5">Conversas por caixa de entrada</h3>
          <div class="h-64">
            <Doughnut
              v-if="inboxChart"
              :data="inboxChart.data"
              :options="inboxChart.options"
            />
            <div v-else class="flex flex-col items-center justify-center h-full text-n-slate-10 text-sm gap-2">
              <span class="i-lucide-pie-chart text-2xl" />
              <span>Sem conversas no período</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Etiquetas + Radar de Oportunidades -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        <!-- Etiquetas (volume e proporção) -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6">
          <div class="flex items-center gap-2 mb-5">
            <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)">
              <span class="i-lucide-tags text-white text-sm" />
            </span>
            <h3 class="text-sm font-bold text-n-slate-12">Etiquetas dos leads</h3>
            <span v-if="data.by_label?.total" class="text-[11px] text-n-slate-9 ml-auto">
              {{ data.by_label.total }} etiquetas aplicadas
            </span>
          </div>
          <div v-if="!labelChart" class="flex flex-col items-center justify-center h-64 text-n-slate-10 text-sm gap-2">
            <span class="i-lucide-tags text-2xl" />
            <span>Nenhuma etiqueta aplicada nos leads deste funil</span>
          </div>
          <div v-else class="flex flex-col sm:flex-row items-center gap-5">
            <div class="h-52 w-52 flex-shrink-0">
              <Doughnut :data="labelChart.data" :options="labelChart.options" />
            </div>
            <div class="flex-1 w-full space-y-2 max-h-52 overflow-y-auto pr-1" style="scrollbar-width: thin;">
              <!-- colunas arredondadas em gradiente (mínimo 33% preenchido) -->
              <div v-for="(item, i) in data.by_label.items" :key="item.label" class="flex items-center gap-2 text-xs">
                <span class="text-n-slate-12 w-24 truncate flex-shrink-0">{{ item.label }}</span>
                <div class="flex-1 h-5 rounded-full bg-n-alpha-1 overflow-hidden">
                  <div
                    class="h-full rounded-full flex items-center justify-end pr-2"
                    :style="{
                      width: Math.max((item.count / (data.by_label.items[0]?.count || 1)) * 100, 33) + '%',
                      background: `linear-gradient(90deg, ${PALETTE[i % PALETTE.length]}, ${PALETTE[i % PALETTE.length]}99)`,
                    }"
                  >
                    <span class="text-[10px] font-bold text-white drop-shadow">{{ item.count }}</span>
                  </div>
                </div>
                <span class="text-n-slate-9 w-10 text-right flex-shrink-0">{{ item.pct }}%</span>
              </div>
            </div>
          </div>
        </div>

        <!-- Radar de Oportunidades × Consultas -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6">
          <div class="flex items-center gap-2 mb-5">
            <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #059669, #4ADE80)">
              <span class="i-lucide-radar text-white text-sm" />
            </span>
            <h3 class="text-sm font-bold text-n-slate-12">Radar de Oportunidades</h3>
            <span class="text-[11px] text-n-slate-9 ml-auto">no período selecionado</span>
          </div>
          <div class="grid grid-cols-2 gap-4">
            <div class="rounded-2xl p-5 text-white shadow-lg" style="background: linear-gradient(135deg, #059669, #4ADE80)">
              <p class="text-xs font-medium text-white/80 mb-1">Oportunidades detectadas</p>
              <p class="text-3xl font-bold">{{ data.radar?.opportunities ?? 0 }}</p>
              <p class="text-[11px] text-white/70 mt-1">pacientes quentes sem atendimento</p>
            </div>
            <div class="rounded-2xl p-5 text-white shadow-lg" style="background: linear-gradient(135deg, #5B21B6, #7C3AED)">
              <p class="text-xs font-medium text-white/80 mb-1">Consultas agendadas</p>
              <p class="text-3xl font-bold">{{ data.radar?.appointments ?? 0 }}</p>
              <p class="text-[11px] text-white/70 mt-1">criadas na Agenda no período</p>
            </div>
          </div>
          <p class="text-[11px] text-n-slate-9 mt-4 flex items-center gap-1.5">
            <span class="i-lucide-info text-xs" />
            O Radar audita as colunas vigiadas (07:30–18h a cada 10 min; madrugada a cada 4h)
            e avisa no Meu Painel — configure em Automações → Agentes de IA.
          </p>
        </div>
      </div>

      <!-- 🌟 Satisfação (NPS) — pós-operatório -->
      <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-10">
        <div class="flex items-center gap-2 mb-5 flex-wrap">
          <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0D9488, #2DD4BF)">
            <span class="i-lucide-smile text-white text-sm" />
          </span>
          <h3 class="text-sm font-bold text-n-slate-12">Satisfação dos pacientes (NPS)</h3>
          <span class="text-[11px] text-n-slate-9 ml-auto">
            {{ data.nps?.stage_name ? `pacientes que chegaram a "${data.nps.stage_name}"` : 'funil inteiro' }} · notas lidas pelo agente de NPS
          </span>
        </div>
        <div v-if="!data.nps?.total" class="flex flex-col items-center justify-center py-8 text-n-slate-10 text-sm gap-2">
          <span class="i-lucide-smile text-2xl" />
          <span>Sem respostas de NPS ainda — ligue o Agente de NPS numa coluna do pós-operatório (Automações → Agentes de IA).</span>
        </div>
        <div v-else class="grid grid-cols-1 sm:grid-cols-3 gap-4 items-center">
          <div class="rounded-2xl p-5 text-white shadow-lg text-center" style="background: linear-gradient(135deg, #0D9488, #2DD4BF)">
            <p class="text-xs font-medium text-white/80 mb-1">% satisfação (notas 9-10)</p>
            <p class="text-4xl font-bold">{{ data.nps.satisfaction }}%</p>
            <p class="text-[11px] text-white/70 mt-1">NPS {{ data.nps.nps_score }} · {{ data.nps.total }} resposta(s)</p>
          </div>
          <div class="sm:col-span-2 space-y-2.5">
            <div
              v-for="(band, bi) in data.nps.bands"
              :key="band.key"
              class="flex items-center gap-3"
            >
              <span class="text-xs text-n-slate-12 w-44 flex-shrink-0 truncate">{{ band.label }}</span>
              <div class="flex-1 h-6 rounded-full bg-n-alpha-1 overflow-hidden">
                <div
                  class="h-full rounded-full flex items-center justify-end pr-2"
                  :style="{
                    width: Math.max((band.count / data.nps.total) * 100, band.count ? 33 : 4) + '%',
                    background: `linear-gradient(90deg, ${NPS_BAND_GRADS[bi][0]}, ${NPS_BAND_GRADS[bi][1]})`,
                  }"
                >
                  <span v-if="band.count" class="text-[10px] font-bold text-white drop-shadow">{{ band.count }}</span>
                </div>
              </div>
              <span class="text-xs text-n-slate-9 w-12 text-right">{{ Math.round((band.count / data.nps.total) * 100) }}%</span>
            </div>
            <p class="text-[10px] text-n-slate-9">Etiquetas nps-9-10 / nps-7-8 / nps-0-6 aplicadas pelo agente — também dá pra filtrar o board por elas.</p>
          </div>
        </div>
      </div>

      <!-- Cirurgias da planilha (Google Sheets) -->
      <div
        v-if="data.sheet_surgeries?.configured"
        class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-6"
      >
        <div class="flex items-center gap-2 mb-5">
          <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0F9D58, #34A853)">
            <span class="i-lucide-sheet text-white text-sm" />
          </span>
          <h3 class="text-sm font-bold text-n-slate-12">Cirurgias — planilha (Google Sheets)</h3>
          <span class="text-[11px] text-n-slate-9 ml-auto">mesmo período selecionado acima</span>
        </div>

        <p v-if="data.sheet_surgeries.error" class="text-sm text-n-slate-10">
          {{ data.sheet_surgeries.error }}
        </p>
        <template v-else>
          <div class="grid grid-cols-2 lg:grid-cols-4 gap-5 mb-6">
            <div class="rounded-2xl p-5 text-white shadow-lg" style="background: linear-gradient(135deg, #0F9D58, #34A853)">
              <p class="text-xs font-medium text-white/80 mb-1">Cirurgias no período</p>
              <p class="text-3xl font-bold">{{ data.sheet_surgeries.count }}</p>
            </div>
            <div class="rounded-2xl p-5 text-white shadow-lg" style="background: linear-gradient(135deg, #65A30D, #84CC16)">
              <p class="text-xs font-medium text-white/80 mb-1">Receita (planilha)</p>
              <p class="text-2xl font-bold leading-tight">{{ formatCurrency(data.sheet_surgeries.revenue) }}</p>
            </div>
            <div class="col-span-2 bg-n-solid-1 border border-n-weak rounded-2xl p-5">
              <p class="text-xs font-medium text-n-slate-10 mb-2">Por unidade</p>
              <div v-if="data.sheet_surgeries.by_unit?.length" class="space-y-1.5">
                <div v-for="u in data.sheet_surgeries.by_unit" :key="u.name" class="flex items-center gap-2 text-sm">
                  <span class="text-n-slate-12 flex-1 truncate">{{ u.name }}</span>
                  <span class="font-semibold text-n-slate-12">{{ u.count }}</span>
                  <span class="text-xs text-n-slate-10 w-24 text-right">{{ formatCurrency(u.value) }}</span>
                </div>
              </div>
              <p v-else class="text-xs text-n-slate-10">Sem coluna "Unidade" na planilha.</p>
            </div>
          </div>

          <div v-if="data.sheet_surgeries.by_procedure?.length">
            <p class="text-xs font-medium text-n-slate-10 mb-2">Por procedimento</p>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-x-8 gap-y-1.5">
              <div v-for="p in data.sheet_surgeries.by_procedure" :key="p.name" class="flex items-center gap-2 text-sm">
                <span class="w-1.5 h-1.5 rounded-full flex-shrink-0" style="background: #0F9D58" />
                <span class="text-n-slate-12 flex-1 truncate">{{ p.name }}</span>
                <span class="font-semibold text-n-slate-12">{{ p.count }}</span>
                <span class="text-xs text-n-slate-10 w-24 text-right">{{ formatCurrency(p.value) }}</span>
              </div>
            </div>
          </div>
          <p v-if="!data.sheet_surgeries.count" class="text-sm text-n-slate-10">
            Nenhuma cirurgia na planilha dentro do período selecionado.
          </p>
        </template>
      </div>

      <!-- Funil + Valor + Tempo -->
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">

        <!-- Conversas por etapa -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6">
          <h3 class="text-sm font-bold text-n-slate-12 mb-5">Conversas por etapa</h3>
          <div class="h-56">
            <Bar
              v-if="funnelChart"
              :data="funnelChart.data"
              :options="funnelChart.options"
            />
            <div v-else class="flex items-center justify-center h-full text-n-slate-10 text-sm">
              Sem dados
            </div>
          </div>
        </div>

        <!-- Valor em cada etapa do pipeline -->
        <div class="rounded-2xl p-6 border-2" style="border-color: rgba(132,204,22,0.35); background: rgba(132,204,22,0.05)">
          <h3 class="text-sm font-bold text-n-slate-12 mb-5 flex items-center gap-2">
            <span class="i-lucide-circle-dollar-sign" style="color: #65A30D" />
            Valor em cada etapa do pipeline
          </h3>
          <div class="h-56">
            <Bar
              v-if="valueChart"
              :data="valueChart.data"
              :options="valueChart.options"
            />
            <div v-else class="flex flex-col items-center justify-center h-full text-n-slate-10 text-sm gap-2">
              <span class="i-lucide-dollar-sign text-2xl" />
              <span>Preencha o valor das conversas</span>
            </div>
          </div>
        </div>

        <!-- Tempo médio por etapa -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6">
          <h3 class="text-sm font-bold text-n-slate-12 mb-5">Tempo médio por etapa</h3>
          <div class="h-56">
            <Bar
              v-if="timeChart"
              :data="timeChart.data"
              :options="timeChart.options"
            />
            <div v-else class="flex flex-col items-center justify-center h-full text-n-slate-10 text-sm gap-2">
              <span class="i-lucide-clock text-2xl" />
              <span>Mova conversas entre etapas para gerar dados</span>
            </div>
          </div>
        </div>

      </div>

    </div>

    <!-- Empty state -->
    <div v-else class="flex flex-col items-center justify-center py-24 text-n-slate-10">
      <span class="i-lucide-layout-dashboard text-4xl mb-3" />
      <p class="text-sm">Nenhum dado disponível ainda.</p>
      <p class="text-xs mt-1">Adicione conversas ao funil para ver as métricas.</p>
    </div>

  </div>
</template>
