<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore } from 'dashboard/composables/store';
import {
  Chart as ChartJS,
  Title, Tooltip, Legend,
  BarElement, CategoryScale, LinearScale,
  ArcElement,
  PointElement, LineElement, Filler,
} from 'chart.js';
import { Bar, Doughnut, Line } from 'vue-chartjs';

ChartJS.register(
  Title, Tooltip, Legend,
  BarElement, CategoryScale, LinearScale,
  ArcElement,
  PointElement, LineElement, Filler,
);

const props = defineProps({
  pipeline: { type: Object, required: true },
});

const store   = useStore();
const period  = ref(365);
const data    = ref(null);
const loading = ref(false);
const error   = ref(false);

const PERIODS = [
  { value: 30,   label: '30 dias' },
  { value: 90,   label: '90 dias' },
  { value: 180,  label: '6 meses' },
  { value: 365,  label: '1 ano' },
  { value: 1095, label: '3 anos' },
];

// ── Load ─────────────────────────────────────────────────────────────

const load = async () => {
  loading.value = true;
  error.value   = false;
  try {
    data.value = await store.dispatch('crm/fetchDashboard', {
      pipelineId: props.pipeline.id,
      period: period.value,
    });
  } catch {
    error.value = true;
  } finally {
    loading.value = false;
  }
};

onMounted(load);
watch(period, load);
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

const formatCurrency = (val) =>
  val > 0
    ? 'R$ ' + Number(val).toLocaleString('pt-BR', { maximumFractionDigits: 0 })
    : 'R$ 0';

// ── Computed charts ───────────────────────────────────────────────────

const CHART_OPTIONS_BASE = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: { legend: { display: false } },
  animation: { duration: 400 },
};

// Funil: leads por etapa (horizontal bar)
const funnelChart = computed(() => {
  if (!data.value?.funnel) return null;
  const f = data.value.funnel;
  return {
    data: {
      labels: f.map(s => s.stage_name),
      datasets: [{
        data: f.map(s => s.count),
        backgroundColor: f.map(s => s.stage_color || '#6B7280'),
        borderRadius: 6,
        borderSkipped: false,
      }],
    },
    options: {
      ...CHART_OPTIONS_BASE,
      indexAxis: 'y',
      plugins: {
        ...CHART_OPTIONS_BASE.plugins,
        tooltip: { callbacks: { label: ctx => ` ${ctx.raw} leads` } },
      },
      scales: {
        x: { ticks: { stepSize: 1 }, grid: { color: 'rgba(0,0,0,0.05)' } },
        y: { grid: { display: false } },
      },
    },
  };
});

// Valor por etapa (bar vertical)
const valueChart = computed(() => {
  if (!data.value?.value_by_stage) return null;
  const v = data.value.value_by_stage.filter(s => s.value > 0);
  if (!v.length) return null;
  return {
    data: {
      labels: v.map(s => s.stage_name),
      datasets: [{
        data: v.map(s => s.value),
        backgroundColor: v.map(s => (s.stage_color || '#6B7280') + 'CC'),
        borderColor: v.map(s => s.stage_color || '#6B7280'),
        borderWidth: 1,
        borderRadius: 6,
      }],
    },
    options: {
      ...CHART_OPTIONS_BASE,
      plugins: {
        ...CHART_OPTIONS_BASE.plugins,
        tooltip: { callbacks: { label: ctx => ' R$ ' + Number(ctx.raw).toLocaleString('pt-BR', { maximumFractionDigits: 0 }) } },
      },
      scales: {
        y: { grid: { color: 'rgba(0,0,0,0.05)' } },
        x: { grid: { display: false } },
      },
    },
  };
});

// Tempo médio por etapa (bar vertical)
const timeChart = computed(() => {
  if (!data.value?.avg_time_by_stage) return null;
  const t = data.value.avg_time_by_stage.filter(s => s.avg_minutes > 0);
  if (!t.length) return null;
  return {
    data: {
      labels: t.map(s => s.stage_name),
      datasets: [{
        data: t.map(s => s.avg_minutes),
        backgroundColor: t.map(s => (s.stage_color || '#6B7280') + '99'),
        borderColor: t.map(s => s.stage_color || '#6B7280'),
        borderWidth: 1,
        borderRadius: 6,
      }],
    },
    options: {
      ...CHART_OPTIONS_BASE,
      plugins: {
        ...CHART_OPTIONS_BASE.plugins,
        tooltip: { callbacks: { label: ctx => ' ' + formatDuration(ctx.raw) } },
      },
      scales: {
        y: {
          grid: { color: 'rgba(0,0,0,0.05)' },
          ticks: { callback: v => formatDuration(v) },
        },
        x: { grid: { display: false } },
      },
    },
  };
});

// Origem (doughnut)
const originChart = computed(() => {
  if (!data.value?.by_origin?.length) return null;
  const o = data.value.by_origin;
  const COLORS = ['#6366F1','#F59E0B','#10B981','#EF4444','#3B82F6','#8B5CF6','#EC4899','#14B8A6'];
  return {
    data: {
      labels: o.map(x => x.origin),
      datasets: [{
        data: o.map(x => x.count),
        backgroundColor: COLORS.slice(0, o.length),
        borderWidth: 0,
      }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { display: true, position: 'bottom', labels: { padding: 12, boxWidth: 12, font: { size: 11 } } },
        tooltip: { callbacks: { label: ctx => ` ${ctx.raw} leads (${ctx.label})` } },
      },
      cutout: '65%',
      animation: { duration: 400 },
    },
  };
});

// Linha do tempo (line chart)
const timelineChart = computed(() => {
  if (!data.value?.created_over_time) return null;
  const t = data.value.created_over_time;
  return {
    data: {
      labels: t.map(d => {
        const dt = new Date(d.date + 'T12:00:00');
        return dt.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
      }),
      datasets: [{
        data: t.map(d => d.count),
        fill: true,
        backgroundColor: 'rgba(99,102,241,0.12)',
        borderColor: '#6366F1',
        borderWidth: 2,
        pointRadius: 3,
        pointBackgroundColor: '#6366F1',
        tension: 0.4,
      }],
    },
    options: {
      ...CHART_OPTIONS_BASE,
      plugins: {
        ...CHART_OPTIONS_BASE.plugins,
        tooltip: { callbacks: { label: ctx => ` ${ctx.raw} leads` } },
      },
      scales: {
        y: { beginAtZero: true, ticks: { stepSize: 1 }, grid: { color: 'rgba(0,0,0,0.05)' } },
        x: { grid: { display: false }, ticks: { maxTicksLimit: 10 } },
      },
    },
  };
});

// ── Responsividade: quem avançou vs. quem ficou parado no início ──────
const resp = computed(() => data.value?.responsiveness ?? null);

const respMilestones = computed(() => {
  if (!resp.value?.stages?.length) return [];
  // pula a 1ª etapa (todos "chegam" nela = 100%); mostra o avanço real
  return resp.value.stages.slice(1).map(s => ({
    name: s.stage_name,
    color: s.stage_color || '#6B7280',
    reached: s.reached,
    pct: s.reached_pct,
  }));
});
</script>

<template>
  <div class="bg-n-solid-1 p-6 min-h-full">

    <!-- Header do dashboard -->
    <div class="flex items-center justify-between mb-6 flex-wrap gap-3">
      <div>
        <h2 class="text-base font-semibold text-n-slate-12">Dashboard — {{ pipeline.name }}</h2>
        <p class="text-xs text-n-slate-10 mt-0.5">Métricas automáticas com base nos leads do funil</p>
      </div>
      <!-- Seletor de período -->
      <div class="flex items-center gap-1.5 bg-n-solid-2 border border-n-weak rounded-xl p-1">
        <button
          v-for="p in PERIODS"
          :key="p.value"
          class="px-3 py-1.5 text-xs font-medium rounded-lg transition-colors"
          :class="period === p.value
            ? 'bg-n-brand text-white'
            : 'text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1'"
          @click="period = p.value"
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

      <!-- KPIs -->
      <div class="grid grid-cols-2 lg:grid-cols-3 xl:grid-cols-6 gap-3 mb-6">
        <!-- Total de leads -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-4">
          <p class="text-xs text-n-slate-10 mb-1">Total no funil</p>
          <p class="text-2xl font-bold text-n-slate-12">{{ data.kpis.total_leads }}</p>
          <p class="text-xs text-n-slate-9 mt-1">leads</p>
        </div>

        <!-- Novos no período -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-4">
          <p class="text-xs text-n-slate-10 mb-1">Novos ({{ period }}d)</p>
          <p class="text-2xl font-bold text-n-brand">{{ data.kpis.new_in_period }}</p>
          <p class="text-xs text-n-slate-9 mt-1">leads</p>
        </div>

        <!-- Valor em pipeline -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-4">
          <p class="text-xs text-n-slate-10 mb-1">Valor em pipeline</p>
          <p class="text-xl font-bold text-green-600 leading-tight mt-0.5">{{ formatCurrency(data.kpis.total_value) }}</p>
          <p class="text-xs text-n-slate-9 mt-1">total</p>
        </div>

        <!-- Fechamentos -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-4">
          <p class="text-xs text-n-slate-10 mb-1">Fechamentos</p>
          <p class="text-2xl font-bold text-n-slate-12">{{ data.kpis.closed_count }}</p>
          <p class="text-xs text-n-slate-9 mt-1">leads</p>
        </div>

        <!-- Taxa de fechamento -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-4">
          <p class="text-xs text-n-slate-10 mb-1">Taxa de fechamento</p>
          <p class="text-2xl font-bold" :class="data.kpis.close_rate > 20 ? 'text-green-600' : 'text-n-slate-12'">
            {{ data.kpis.close_rate }}%
          </p>
          <p class="text-xs text-n-slate-9 mt-1">conversão</p>
        </div>

        <!-- Tempo médio de conversão -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-4">
          <p class="text-xs text-n-slate-10 mb-1">Tempo médio</p>
          <p class="text-xl font-bold text-n-slate-12 leading-tight mt-0.5">
            {{ formatDuration(data.kpis.avg_conversion_minutes) }}
          </p>
          <p class="text-xs text-n-slate-9 mt-1">de conversão</p>
        </div>
      </div>

      <!-- Responsividade dos leads -->
      <div v-if="resp && resp.total > 0" class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-4">
        <div class="flex items-center justify-between flex-wrap gap-2 mb-4">
          <h3 class="text-sm font-semibold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-activity text-n-brand" />
            Responsividade dos leads
          </h3>
          <span class="text-xs text-n-slate-10">quanto do total avançou em cada etapa</span>
        </div>

        <!-- barras de "chegaram até" -->
        <div class="space-y-2.5">
          <div v-for="m in respMilestones" :key="m.name" class="flex items-center gap-3">
            <div class="w-40 text-right flex-shrink-0">
              <p class="text-xs text-n-slate-12 font-medium truncate">{{ m.name }}</p>
            </div>
            <div class="flex-1 flex items-center gap-2">
              <div class="flex-1 h-6 rounded-lg bg-n-alpha-1 overflow-hidden">
                <div
                  class="h-full rounded-lg transition-all flex items-center justify-end px-2"
                  :style="{ width: Math.max(m.pct, 4) + '%', backgroundColor: (m.color || '#6B7280') + 'CC' }"
                >
                  <span class="text-[11px] font-bold text-white drop-shadow">{{ m.pct }}%</span>
                </div>
              </div>
              <span class="text-xs text-n-slate-10 w-24 flex-shrink-0">{{ m.reached }} leads</span>
            </div>
          </div>
        </div>

        <!-- destaque: pouco responsivos (parados no início) -->
        <div class="mt-4 flex items-center gap-3 bg-amber-500/10 border border-amber-500/25 rounded-xl p-3.5 flex-wrap">
          <span class="i-lucide-user-x text-amber-600 text-xl flex-shrink-0" />
          <div class="flex-1 min-w-0">
            <p class="text-sm font-semibold text-n-slate-12">
              {{ resp.stuck.count }} leads pouco responsivos ({{ resp.stuck.pct }}%)
            </p>
            <p class="text-xs text-n-slate-10">
              parados em "{{ resp.stuck.stage_name }}" — não avançaram no funil. Público ideal para uma campanha de reativação.
            </p>
          </div>
          <button
            class="text-xs font-medium px-3 py-1.5 rounded-lg bg-n-brand text-white hover:opacity-90 flex-shrink-0"
            @click="$router.push({ name: 'crm_campaigns' })"
          >
            Criar campanha →
          </button>
        </div>
      </div>

      <!-- Linha do tempo + Origem -->
      <div class="grid grid-cols-1 xl:grid-cols-3 gap-4 mb-4">

        <!-- Leads por dia (line) -->
        <div class="xl:col-span-2 bg-n-solid-2 border border-n-weak rounded-2xl p-5">
          <h3 class="text-sm font-semibold text-n-slate-12 mb-4">Leads ao longo do tempo</h3>
          <div class="h-52">
            <Line
              v-if="timelineChart"
              :data="timelineChart.data"
              :options="timelineChart.options"
            />
            <div v-else class="flex items-center justify-center h-full text-n-slate-10 text-sm">
              Sem dados no período
            </div>
          </div>
        </div>

        <!-- Por origem (doughnut) -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
          <h3 class="text-sm font-semibold text-n-slate-12 mb-4">Origem dos leads</h3>
          <div class="h-52">
            <Doughnut
              v-if="originChart"
              :data="originChart.data"
              :options="originChart.options"
            />
            <div v-else class="flex flex-col items-center justify-center h-full text-n-slate-10 text-sm gap-2">
              <span class="i-lucide-pie-chart text-2xl" />
              <span>Nenhuma origem cadastrada</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Funil + Valor + Tempo -->
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">

        <!-- Funil de leads (horizontal bar) -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
          <h3 class="text-sm font-semibold text-n-slate-12 mb-4">Leads por etapa</h3>
          <div class="h-52">
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

        <!-- Valor por etapa -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
          <h3 class="text-sm font-semibold text-n-slate-12 mb-4">Valor por etapa</h3>
          <div class="h-52">
            <Bar
              v-if="valueChart"
              :data="valueChart.data"
              :options="valueChart.options"
            />
            <div v-else class="flex flex-col items-center justify-center h-full text-n-slate-10 text-sm gap-2">
              <span class="i-lucide-dollar-sign text-2xl" />
              <span>Preencha o valor dos leads</span>
            </div>
          </div>
        </div>

        <!-- Tempo médio por etapa -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
          <h3 class="text-sm font-semibold text-n-slate-12 mb-4">Tempo médio por etapa</h3>
          <div class="h-52">
            <Bar
              v-if="timeChart"
              :data="timeChart.data"
              :options="timeChart.options"
            />
            <div v-else class="flex flex-col items-center justify-center h-full text-n-slate-10 text-sm gap-2">
              <span class="i-lucide-clock text-2xl" />
              <span>Mova leads entre etapas para gerar dados</span>
            </div>
          </div>
        </div>

      </div>

    </div>

    <!-- Empty state (pipeline sem leads) -->
    <div v-else class="flex flex-col items-center justify-center py-24 text-n-slate-10">
      <span class="i-lucide-layout-dashboard text-4xl mb-3" />
      <p class="text-sm">Nenhum dado disponível ainda.</p>
      <p class="text-xs mt-1">Adicione leads ao funil para ver as métricas.</p>
    </div>

  </div>
</template>
