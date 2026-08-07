<script setup>
// Funil de Tráfego REMODELADO (06/08): além do funil simétrico, o mesmo
// dado ganha visões de BARRAS (gargalos evidentes), TENDÊNCIA (semanas com
// linha de média) e MAPA DE CALOR (etapas × semanas). As etapas do CRM
// agora RESPEITAM o período: contam leads que ENTRARAM na coluna dentro da
// janela (histórico de movimentação), com o retrato atual ao lado.
import { ref, computed, onMounted, watch } from 'vue';
import {
  Chart as ChartJS,
  Title,
  Tooltip,
  Legend,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Filler,
} from 'chart.js';
import { Line } from 'vue-chartjs';
import CrmAPI from 'dashboard/api/crm';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';

ChartJS.register(Title, Tooltip, Legend, CategoryScale, LinearScale, PointElement, LineElement, Filler);

const period = ref({ preset: 'month', from: '', to: '' });
const data = ref(null);
const isLoading = ref(false);
const hasError = ref(false);

const load = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const params = { preset: period.value.preset };
    if (period.value.preset === 'custom') {
      params.from = period.value.from;
      params.to = period.value.to;
    }
    const { data: response } = await CrmAPI.getTrafficReport(params);
    data.value = response;
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

onMounted(load);
watch(period, load, { deep: true });

// ── Modo de visualização (o MESMO dado, vários olhares) ──────────────
const VIEW_MODES = [
  { key: 'funnel', label: 'Funil', icon: 'i-lucide-filter' },
  { key: 'bars', label: 'Barras', icon: 'i-lucide-align-left' },
  { key: 'trend', label: 'Tendência', icon: 'i-lucide-line-chart' },
  { key: 'heat', label: 'Mapa de calor', icon: 'i-lucide-grid-3x3' },
];
const savedView = localStorage.getItem('cevico_funnel_view');
const viewMode = ref(VIEW_MODES.some(v => v.key === savedView) ? savedView : 'funnel');
const setViewMode = key => {
  viewMode.value = key;
  localStorage.setItem('cevico_funnel_view', key);
};

const formatCurrency = v =>
  'R$ ' + Number(v || 0).toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

const formatNumber = v => Number(v || 0).toLocaleString('pt-BR');

const formatDuration = seconds => {
  if (!seconds || seconds <= 0) return '—';
  if (seconds < 60) return `${Math.round(seconds)}s`;
  const mins = Math.round(seconds / 60);
  if (mins < 60) return `${mins}min`;
  const h = Math.floor(mins / 60);
  return `${h}h ${mins % 60}min`;
};

// ── Médias históricas (12 semanas) por etapa ─────────────────────────
const weeklyAverages = computed(() => {
  const weeks = data.value?.funnel_weeks;
  if (!weeks) return {};
  const avg = {};
  (weeks.stages ?? []).forEach(s => {
    const counts = s.counts ?? [];
    if (!counts.length) return;
    avg[`stage-${s.stage_id}`] = counts.reduce((a, b) => a + b, 0) / counts.length;
  });
  const conv = weeks.conversations ?? [];
  if (conv.length) avg.conversations = conv.reduce((a, b) => a + b, 0) / conv.length;
  return avg;
});

// ritmo semanal do período atual (para comparar com a média de 12 semanas)
const weeklyPace = count => {
  const days = Math.max(Number(data.value?.period_days) || 1, 1);
  return (count / days) * 7;
};

const paceVsAvg = row => {
  const avg = weeklyAverages.value[row.key];
  if (!avg || avg <= 0) return null;
  const pace = weeklyPace(row.count);
  const delta = ((pace - avg) / avg) * 100;
  return { avg, pace, delta, above: delta >= 0 };
};

// ── Funil: ads (alcance, cliques) + conversas + etapas do CRM ─────────
const funnelRows = computed(() => {
  if (!data.value) return [];
  const rows = [];
  const ads = data.value.ads ?? {};

  if (ads.configured && !ads.error) {
    rows.push({ key: 'reach', name: 'Alcance', count: ads.reach, color: '#0F5FA6', source: 'Meta Ads' });
    rows.push({ key: 'clicks', name: 'Cliques no link', count: ads.link_clicks, color: '#2781F6', source: 'Meta Ads' });
  }

  rows.push({
    key: 'conversations',
    name: 'Conversas iniciadas',
    count: data.value.conversations_started,
    color: '#12A594',
    source: 'WhatsApp',
  });

  (data.value.funnel_stages ?? []).forEach(stage => {
    rows.push({
      key: `stage-${stage.stage_id}`,
      name: stage.name,
      count: stage.count,
      current: stage.current,
      color: stage.color || '#6B7280',
      source: 'CRM',
    });
  });

  const max = Math.max(...rows.map(r => r.count), 1);
  return rows.map((row, index) => {
    const previous = index > 0 ? rows[index - 1].count : null;
    const rate = previous ? (row.count / previous) * 100 : null;
    return {
      ...row,
      width: Math.max((row.count / max) * 100, 4),
      rate: rate !== null ? rate.toFixed(1) : null,
      rateNum: rate,
      gain: rate !== null && rate >= 100,
      media: paceVsAvg(row),
    };
  });
});

// os 3 maiores gargalos (maiores quedas % entre etapas do CRM)
const bottleneckKeys = computed(() => {
  const crmRows = funnelRows.value.filter(
    r => r.source === 'CRM' && r.rateNum !== null && r.rateNum < 100
  );
  return new Set(
    crmRows
      .slice()
      .sort((a, b) => a.rateNum - b.rateNum)
      .slice(0, 3)
      .map(r => r.key)
  );
});

const cpl = computed(() => {
  const ads = data.value?.ads;
  const conversations = data.value?.conversations_started;
  if (!ads?.configured || ads.error || !conversations) return null;
  return ads.spend / conversations;
});

// ── Tendência (semanas): etapas selecionáveis, máx. 4 séries ─────────
const trendSelection = ref(null); // null = padrão calculado

const trendCandidates = computed(() => {
  const weeks = data.value?.funnel_weeks;
  if (!weeks) return [];
  const rows = [
    { key: 'conversations', name: 'Conversas', color: '#12A594', counts: weeks.conversations ?? [] },
  ];
  (weeks.stages ?? []).forEach(s => {
    rows.push({ key: `stage-${s.stage_id}`, name: s.name, color: s.color || '#6B7280', counts: s.counts ?? [] });
  });
  return rows;
});

const defaultTrendKeys = computed(() => {
  const keys = [];
  const candidates = trendCandidates.value;
  const first = candidates.find(c => c.key.startsWith('stage-'));
  if (first) keys.push(first.key);
  const agendamento = candidates.find(c => /agendamento/i.test(c.name));
  if (agendamento && !keys.includes(agendamento.key)) keys.push(agendamento.key);
  const cirurgia = candidates.find(c => /cirurgia realizada/i.test(c.name));
  if (cirurgia && !keys.includes(cirurgia.key)) keys.push(cirurgia.key);
  return keys.length ? keys : candidates.slice(0, 2).map(c => c.key);
});

const activeTrendKeys = computed(() => trendSelection.value ?? defaultTrendKeys.value);

const toggleTrendKey = key => {
  const current = [...activeTrendKeys.value];
  const idx = current.indexOf(key);
  if (idx >= 0) {
    if (current.length === 1) return; // sempre ao menos 1 série
    current.splice(idx, 1);
  } else {
    if (current.length >= 4) current.shift(); // máx. 4 séries legíveis
    current.push(key);
  }
  trendSelection.value = current;
};

const weekLabels = computed(() =>
  (data.value?.funnel_weeks?.weeks ?? []).map(w => {
    const d = new Date(`${w}T00:00:00`);
    return `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}`;
  })
);

const trendChartData = computed(() => {
  const datasets = trendCandidates.value
    .filter(c => activeTrendKeys.value.includes(c.key))
    .map(c => ({
      label: c.name,
      data: c.counts,
      borderColor: c.color,
      backgroundColor: c.color,
      borderWidth: 2,
      pointRadius: 3,
      pointHoverRadius: 5,
      tension: 0.3,
    }));

  // com UMA série, a média de 12 semanas entra como linha tracejada neutra
  if (datasets.length === 1) {
    const only = trendCandidates.value.find(c => activeTrendKeys.value.includes(c.key));
    const avg = weeklyAverages.value[only.key];
    if (avg) {
      datasets.push({
        label: `Média 12 semanas (${avg.toFixed(1)})`,
        data: weekLabels.value.map(() => avg),
        borderColor: '#94A3B8',
        borderDash: [6, 5],
        borderWidth: 2,
        pointRadius: 0,
        pointHoverRadius: 0,
      });
    }
  }

  return { labels: weekLabels.value, datasets };
});

const trendChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  interaction: { mode: 'index', intersect: false },
  plugins: {
    legend: { position: 'bottom', labels: { boxWidth: 10, boxHeight: 10, usePointStyle: true, font: { size: 11 } } },
  },
  scales: {
    y: { beginAtZero: true, ticks: { precision: 0, font: { size: 10 } }, grid: { color: 'rgba(148,163,184,0.15)' } },
    x: { ticks: { font: { size: 10 } }, grid: { display: false } },
  },
};

// ── Mapa de calor (etapas × semanas, tom único normalizado por linha) ──
const heatRows = computed(() =>
  trendCandidates.value.map(row => {
    const max = Math.max(...row.counts, 1);
    return {
      ...row,
      cells: row.counts.map(count => ({
        count,
        // sequencial de UM tom (azul CEVICO): claro → escuro pela intensidade
        alpha: count === 0 ? 0.04 : 0.12 + (count / max) * 0.88,
        strong: count / max > 0.55,
      })),
    };
  })
);
</script>

<template>
  <div class="flex flex-col h-full overflow-y-auto p-8 bg-n-surface-1">
    <!-- Header -->
    <div class="flex items-center gap-4 mb-8 flex-wrap">
      <span class="w-9 h-9 rounded-xl flex items-center justify-center" style="background: linear-gradient(135deg, #0F5FA6, #22D3EE)">
        <span class="i-lucide-filter text-white text-lg" />
      </span>
      <div>
        <h1 class="text-lg font-bold text-n-slate-12">Funil de Tráfego</h1>
        <p class="text-xs text-n-slate-10 mt-0.5">
          Do anúncio à cirurgia: Meta Ads → WhatsApp → jornada no CRM
        </p>
      </div>
      <div class="flex-1" />
      <PeriodRuler v-model="period" />
    </div>

    <div v-if="isLoading" class="flex justify-center py-16"><Spinner /></div>

    <div v-else-if="hasError" class="text-center py-16 text-sm text-n-slate-10">
      Erro ao carregar o relatório. Tente novamente.
    </div>

    <template v-else-if="data">
      <!-- Aviso de configuração dos anúncios -->
      <div
        v-if="!data.ads?.configured"
        class="mb-5 text-xs text-amber-700 bg-amber-500/10 border border-amber-500/30 rounded-2xl p-5 max-w-3xl"
      >
        <p class="font-semibold mb-1">Meta Ads não conectado ao funil</p>
        <p>
          Para ver investimento, alcance e cliques: abra o <b>CRM → Integrações → Meta Ads</b> e
          preencha o <b>token de acesso</b> e o <b>ID da conta de anúncios</b> (começa com act_).
          As etapas do WhatsApp e do CRM abaixo já funcionam sem isso.
        </p>
      </div>
      <div
        v-else-if="data.ads?.error"
        class="mb-5 text-xs text-red-600 bg-red-500/10 border border-red-500/30 rounded-2xl p-5 max-w-3xl"
      >
        <p class="font-semibold mb-1">Erro ao consultar o Meta Ads</p>
        <p>{{ data.ads.error }}</p>
      </div>

      <!-- KPIs (kit CEVICO) -->
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 max-w-4xl mb-6">
        <DashKpi
          label="Investimento"
          :value="data.ads?.configured && !data.ads?.error ? Number(data.ads.spend || 0) : 0"
          prefix="R$ "
          sub="Meta Ads no período"
          from="#0F5FA6"
          to="#22D3EE"
        />
        <DashKpi
          label="Alcance"
          :value="data.ads?.configured && !data.ads?.error ? Number(data.ads.reach || 0) : 0"
          sub="pessoas alcançadas"
          from="#2781F6"
          to="#7C3AED"
        />
        <DashKpi
          label="Conversas iniciadas"
          :value="Number(data.conversations_started || 0)"
          sub="no período"
          from="#12A594"
          to="#2DD4BF"
        />
        <DashKpi
          label="Custo por conversa"
          :value="cpl ? Number(cpl.toFixed(2)) : 0"
          prefix="R$ "
          sub="investimento ÷ conversas"
          from="#B8860B"
          to="#D4A017"
        />
      </div>

      <!-- Alternador de visualização: o MESMO funil, vários olhares -->
      <div class="flex items-center gap-1.5 bg-n-solid-2 border border-n-weak rounded-xl p-1 mb-4 self-start">
        <button
          v-for="mode in VIEW_MODES"
          :key="mode.key"
          class="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg transition-colors"
          :class="viewMode === mode.key ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="viewMode === mode.key ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' } : {}"
          @click="setViewMode(mode.key)"
        >
          <span :class="mode.icon" class="text-sm" />
          {{ mode.label }}
        </button>
      </div>

      <!-- ═══ VISÃO 1: FUNIL SIMÉTRICO ═══ -->
      <div v-if="viewMode === 'funnel'" class="bg-n-solid-2 border border-n-weak rounded-xl p-5 max-w-4xl mb-6">
        <p class="text-xs font-semibold text-n-slate-11 mb-6">Funil completo — quem entrou em cada etapa no período</p>
        <div class="space-y-1.5">
          <div v-for="row in funnelRows" :key="row.key" class="flex items-center gap-3">
            <div class="w-44 text-right flex-shrink-0">
              <p class="text-xs text-n-slate-12 font-medium truncate">{{ row.name }}</p>
              <p class="text-[10px] text-n-slate-9">
                {{ row.source }}<template v-if="row.source === 'CRM'"> · agora: {{ formatNumber(row.current) }}</template>
              </p>
            </div>
            <div class="flex-1 flex justify-center min-w-0">
              <div
                class="cevico-funnel-bar"
                :style="{
                  width: row.width + '%',
                  background: `linear-gradient(90deg, ${row.color}77 0%, ${row.color}F2 50%, ${row.color}77 100%)`,
                }"
              >
                <span class="text-xs font-bold text-white" style="text-shadow: 0 1px 2px rgba(15, 23, 42, 0.45)">
                  {{ formatNumber(row.count) }}
                </span>
              </div>
            </div>
            <div class="w-32 flex-shrink-0 flex items-center gap-1">
              <span
                v-if="row.rate"
                class="inline-flex items-center gap-0.5 text-[10px] font-semibold rounded-full px-1.5 py-0.5"
                :class="row.gain
                  ? 'bg-emerald-500/12 text-emerald-600'
                  : 'bg-n-alpha-1 text-n-slate-10'"
              >
                <span :class="row.gain ? 'i-lucide-trending-up' : 'i-lucide-trending-down'" class="text-[10px]" />
                {{ row.rate }}%
              </span>
              <span
                v-if="row.media"
                class="inline-flex items-center gap-0.5 text-[10px] font-semibold rounded-full px-1.5 py-0.5"
                :class="row.media.above ? 'bg-emerald-500/12 text-emerald-600' : 'bg-amber-500/12 text-amber-600'"
                :title="`Ritmo do período: ${row.media.pace.toFixed(1)}/semana · média 12 semanas: ${row.media.avg.toFixed(1)}/semana`"
              >
                {{ row.media.above ? '▲' : '▼' }} média
              </span>
            </div>
          </div>
        </div>
        <p class="text-xs text-n-slate-9 mt-4">
          A porcentagem compara com a etapa anterior. As etapas do CRM contam quem
          <b>entrou na coluna dentro do período</b> ("agora" é o retrato atual). O selo
          ▲/▼ compara o ritmo semanal do período com a média das últimas 12 semanas.
        </p>
      </div>

      <!-- ═══ VISÃO 2: BARRAS (gargalos evidentes) ═══ -->
      <div v-else-if="viewMode === 'bars'" class="bg-n-solid-2 border border-n-weak rounded-xl p-5 max-w-4xl mb-6">
        <p class="text-xs font-semibold text-n-slate-11 mb-6">Barras — onde o funil ganha e onde perde</p>
        <div class="space-y-0.5">
          <template v-for="(row, index) in funnelRows" :key="row.key">
            <!-- conector de conversão entre etapas -->
            <div v-if="index > 0" class="flex items-center gap-2 pl-44 py-0.5">
              <span
                class="inline-flex items-center gap-1 text-[10px] font-semibold rounded-full px-2 py-0.5"
                :class="bottleneckKeys.has(row.key)
                  ? 'bg-red-500/12 text-red-600'
                  : row.gain
                    ? 'bg-emerald-500/12 text-emerald-600'
                    : 'bg-n-alpha-1 text-n-slate-10'"
                :title="bottleneckKeys.has(row.key) ? 'Um dos 3 maiores gargalos do funil' : 'Conversão da etapa anterior para esta'"
              >
                <span class="i-lucide-corner-down-right text-[10px]" />
                {{ row.rate }}% da etapa anterior
                <template v-if="bottleneckKeys.has(row.key)"> · GARGALO</template>
              </span>
            </div>
            <div class="flex items-center gap-3">
              <div class="w-40 text-right flex-shrink-0">
                <p class="text-xs text-n-slate-12 font-medium truncate">{{ row.name }}</p>
                <p class="text-[10px] text-n-slate-9">{{ row.source }}</p>
              </div>
              <div class="flex-1 min-w-0 flex items-center gap-2">
                <div
                  class="h-6 rounded-r-md rounded-l-sm transition-all duration-500"
                  :style="{
                    width: row.width + '%',
                    background: `linear-gradient(90deg, ${row.color}AA, ${row.color})`,
                    minWidth: '0.5rem',
                  }"
                  :title="`${row.name}: ${formatNumber(row.count)}`"
                />
                <span class="text-xs font-bold text-n-slate-12 flex-shrink-0">{{ formatNumber(row.count) }}</span>
                <span
                  v-if="row.media"
                  class="text-[10px] font-semibold flex-shrink-0"
                  :class="row.media.above ? 'text-emerald-600' : 'text-amber-600'"
                  :title="`Ritmo: ${row.media.pace.toFixed(1)}/sem · média 12 semanas: ${row.media.avg.toFixed(1)}/sem`"
                >
                  {{ row.media.above ? '▲' : '▼' }}
                </span>
              </div>
            </div>
          </template>
        </div>
        <p class="text-xs text-n-slate-9 mt-4">
          Os selos vermelhos marcam os <b>3 maiores gargalos</b> (maiores quedas percentuais
          entre etapas do CRM). ▲/▼ compara o ritmo do período com a média de 12 semanas.
        </p>
      </div>

      <!-- ═══ VISÃO 3: TENDÊNCIA (semanas) ═══ -->
      <div v-else-if="viewMode === 'trend'" class="bg-n-solid-2 border border-n-weak rounded-xl p-5 max-w-4xl mb-6">
        <p class="text-xs font-semibold text-n-slate-11 mb-3">Tendência — entradas por semana (últimas 12 semanas)</p>
        <div class="flex items-center gap-1 flex-wrap mb-4">
          <button
            v-for="c in trendCandidates"
            :key="c.key"
            class="flex items-center gap-1.5 h-6 px-2 rounded-full text-[11px] font-medium border transition-colors"
            :class="activeTrendKeys.includes(c.key)
              ? 'border-transparent text-white'
              : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
            :style="activeTrendKeys.includes(c.key) ? { background: c.color } : {}"
            :title="activeTrendKeys.includes(c.key) ? 'Clique para tirar do gráfico' : 'Clique para ver no gráfico (máx. 4)'"
            @click="toggleTrendKey(c.key)"
          >
            <span v-if="!activeTrendKeys.includes(c.key)" class="w-2 h-2 rounded-full" :style="{ background: c.color }" />
            {{ c.name }}
          </button>
        </div>
        <div style="height: 300px">
          <Line :data="trendChartData" :options="trendChartOptions" />
        </div>
        <p class="text-xs text-n-slate-9 mt-3">
          Selecione até 4 etapas. Com <b>uma</b> etapa selecionada, a linha tracejada mostra a média
          de 12 semanas — acima dela é resultado acima do normal.
        </p>
      </div>

      <!-- ═══ VISÃO 4: MAPA DE CALOR (etapas × semanas) ═══ -->
      <div v-else-if="viewMode === 'heat'" class="bg-n-solid-2 border border-n-weak rounded-xl p-5 max-w-5xl mb-6">
        <p class="text-xs font-semibold text-n-slate-11 mb-4">Mapa de calor — entradas por etapa × semana</p>
        <div class="overflow-x-auto">
          <div class="min-w-[720px]">
            <!-- cabeçalho de semanas -->
            <div class="flex items-center gap-1 mb-1">
              <div class="w-40 flex-shrink-0" />
              <div
                v-for="(w, i) in weekLabels"
                :key="i"
                class="flex-1 text-center text-[10px] text-n-slate-9"
              >
                {{ w }}
              </div>
            </div>
            <div v-for="row in heatRows" :key="row.key" class="flex items-center gap-1 mb-1">
              <div class="w-40 flex-shrink-0 flex items-center gap-1.5 min-w-0">
                <span class="w-2 h-2 rounded-full flex-shrink-0" :style="{ background: row.color }" />
                <span class="text-[11px] text-n-slate-12 truncate">{{ row.name }}</span>
              </div>
              <div
                v-for="(cell, i) in row.cells"
                :key="i"
                class="flex-1 h-7 rounded-md flex items-center justify-center transition-colors"
                :style="{ background: `rgba(15, 95, 166, ${cell.alpha})` }"
                :title="`${row.name} · semana de ${weekLabels[i]}: ${formatNumber(cell.count)}`"
              >
                <span
                  v-if="cell.count > 0"
                  class="text-[10px] font-semibold"
                  :class="cell.strong ? 'text-white' : 'text-n-slate-11'"
                >
                  {{ cell.count }}
                </span>
              </div>
            </div>
          </div>
        </div>
        <p class="text-xs text-n-slate-9 mt-3">
          Quanto mais escuro, mais leads entraram naquela etapa naquela semana
          (escala própria por linha). Semanas fracas ficam claras — dá para ver
          padrões e buracos de uma olhada.
        </p>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 max-w-4xl">
        <!-- Etiquetas -->
        <div class="bg-n-solid-2 border border-n-weak rounded-xl p-5">
          <p class="text-xs font-semibold text-n-slate-11 mb-3 flex items-center gap-1.5">
            <span class="i-lucide-tags text-n-brand" /> Contatos por etiqueta
          </p>
          <div v-if="!data.labels?.length" class="text-xs text-n-slate-9 py-4">
            Nenhuma etiqueta aplicada ainda.
          </div>
          <div v-else class="space-y-1.5 max-h-80 overflow-y-auto">
            <div
              v-for="l in data.labels"
              :key="l.label"
              class="flex items-center justify-between px-3 py-1.5 rounded-lg bg-n-alpha-1"
            >
              <span class="text-xs text-n-slate-12 flex items-center gap-2 min-w-0">
                <span class="w-2 h-2 rounded-full flex-shrink-0" :style="{ backgroundColor: l.color || '#6B7280' }" />
                <span class="truncate">{{ l.label }}</span>
              </span>
              <span class="text-xs font-bold text-n-slate-12 flex-shrink-0 ml-2">{{ l.count }}</span>
            </div>
          </div>
        </div>

        <!-- Agentes -->
        <div class="bg-n-solid-2 border border-n-weak rounded-xl p-5">
          <p class="text-xs font-semibold text-n-slate-11 mb-3 flex items-center gap-1.5">
            <span class="i-lucide-headset text-n-brand" /> Desempenho por agente
          </p>
          <div v-if="!data.agents?.rows?.length" class="text-xs text-n-slate-9 py-4">
            Sem dados de agentes no período.
          </div>
          <template v-else>
            <div class="grid grid-cols-3 text-[10px] text-n-slate-9 px-3 pb-1.5">
              <span>Agente</span>
              <span class="text-center">1ª resposta (média)</span>
              <span class="text-right">Conversas abertas</span>
            </div>
            <div class="space-y-1.5 max-h-72 overflow-y-auto">
              <div
                v-for="agent in data.agents.rows"
                :key="agent.id"
                class="grid grid-cols-3 items-center px-3 py-2 rounded-lg bg-n-alpha-1"
              >
                <span class="text-xs text-n-slate-12 truncate">{{ agent.name }}</span>
                <span class="text-xs text-center font-medium" :class="agent.avg_first_response_seconds > 3600 ? 'text-red-500' : 'text-n-slate-12'">
                  {{ formatDuration(agent.avg_first_response_seconds) }}
                </span>
                <span class="text-xs text-right font-bold" :class="agent.open_conversations > 0 ? 'text-n-brand' : 'text-n-slate-10'">
                  {{ agent.open_conversations }}
                </span>
              </div>
            </div>
            <p v-if="data.agents.unassigned_open > 0" class="text-xs text-amber-600 mt-3 flex items-center gap-1">
              <span class="i-lucide-alert-triangle" />
              {{ data.agents.unassigned_open }} conversa(s) aberta(s) sem agente atribuído
            </p>
          </template>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped>
/* barra do funil: cheia, arredondada, com relevo e varredura de brilho
   (mesma linguagem da barra de progresso do formulário) */
.cevico-funnel-bar {
  position: relative;
  overflow: hidden;
  height: 30px;
  min-width: 3rem;
  border-radius: 9999px;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: width 0.6s cubic-bezier(0.22, 1, 0.36, 1);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.35),
    inset 0 -2px 5px rgba(15, 23, 42, 0.18);
}
.cevico-funnel-bar::after {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(
    100deg,
    transparent 35%,
    rgba(255, 255, 255, 0.32) 50%,
    transparent 65%
  );
  transform: translateX(-100%);
  animation: cevico-funnel-sheen 2.6s ease-in-out infinite;
}
@keyframes cevico-funnel-sheen {
  to {
    transform: translateX(100%);
  }
}
@media (prefers-reduced-motion: reduce) {
  .cevico-funnel-bar::after {
    animation: none;
  }
}
</style>
