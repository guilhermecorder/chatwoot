<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import OverviewReportFilters from './components/OverviewReportFilters.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import ReportsAPI from 'dashboard/api/reports';

const { t } = useI18n();
const store = useStore();

// 🍎 formato novo (rodada 163): kit "iMac G3 + vidro" com a paleta desta
// página (o admin escolhe pelo chip do banner; cada bloco pode ter a sua)
const pal = useCevicoPalette({
  scope: 'report:etiquetas',
  blocks: [
    { id: 'top', label: 'Principais etiquetas', icon: 'i-lucide-trophy' },
    { id: 'grafico', label: 'Conversas por etiqueta', icon: 'i-lucide-bar-chart-3' },
    { id: 'matriz', label: 'Caixa × etiqueta', icon: 'i-lucide-grid-3x3' },
  ],
});
const { cvVars, blockVars } = pal;

const from = ref(0);
const to = ref(0);
const isLoadingMatrix = ref(false);
const matrixData = ref(null);

const labels = useMapGetter('labels/getLabels');
const labelSummaryReports = useMapGetter('summaryReports/getLabelSummaryReports');
const uiFlags = useMapGetter('summaryReports/getUIFlags');
const isLoadingSummary = computed(() => uiFlags.value.isFetchingLabelSummaryReports);

// a cor de cada etiqueta (cadastro) tem significado: bolinhas e barras
const labelColor = id => labels.value?.find(l => l.id === id)?.color || null;

const topLabels = computed(() => {
  if (!labelSummaryReports.value?.length) return [];
  return [...labelSummaryReports.value]
    .sort((a, b) => (b.conversationsCount ?? 0) - (a.conversationsCount ?? 0))
    .slice(0, 5);
});

const barChartData = computed(() => {
  if (!labelSummaryReports.value?.length || !labels.value?.length) {
    return { labels: [], datasets: [] };
  }
  const labelMap = Object.fromEntries(labels.value.map(l => [l.id, l.title]));
  const sorted = [...labelSummaryReports.value]
    .sort((a, b) => (b.conversationsCount ?? 0) - (a.conversationsCount ?? 0))
    .slice(0, 10);
  return {
    labels: sorted.map(r => labelMap[r.id] ?? r.id),
    datasets: [
      {
        label: t('LABEL_DASHBOARD.CHART_LABEL'),
        backgroundColor: sorted.map((r, i) => labelColor(r.id) || `hsl(${(i * 37) % 360}, 65%, 55%)`),
        data: sorted.map(r => r.conversationsCount ?? 0),
      },
    ],
  };
});

const matrixInboxes = computed(() => matrixData.value?.inboxes ?? []);
const matrixLabels = computed(() => matrixData.value?.labels ?? []);
const matrixRows = computed(() => matrixData.value?.matrix ?? []);

const maxMatrixValue = computed(() => {
  if (!matrixRows.value.length) return 1;
  return Math.max(1, ...matrixRows.value.flat());
});

// intensidade da célula: 4 degraus no tom do bloco (classes locais abaixo)
const cellIntensity = count => {
  if (!count) return 'cv-heat-0';
  const ratio = count / maxMatrixValue.value;
  if (ratio > 0.75) return 'cv-heat-4';
  if (ratio > 0.5) return 'cv-heat-3';
  if (ratio > 0.25) return 'cv-heat-2';
  return 'cv-heat-1';
};

const fetchSummary = async () => {
  const params = { since: from.value, until: to.value, businessHours: false };
  await store.dispatch('summaryReports/fetchLabelSummaryReports', params);
};

const fetchMatrix = async () => {
  if (!from.value) return;
  isLoadingMatrix.value = true;
  try {
    const res = await ReportsAPI.getInboxLabelMatrix({ from: from.value, to: to.value });
    matrixData.value = res.data;
  } finally {
    isLoadingMatrix.value = false;
  }
};

const fetchAll = () => {
  store.dispatch('labels/get');
  fetchSummary();
  fetchMatrix();
};

onMounted(() => fetchAll());

const onFilterChange = updated => {
  from.value = updated.from;
  to.value = updated.to;
  fetchAll();
};
</script>

<template>
  <div class="cv-page pt-6" :style="cvVars">
    <!-- banner de vidro na paleta da página (rodada 163) -->
    <CevicoHero
      :pal="pal"
      :title="$t('LABEL_DASHBOARD.HEADER')"
      :subtitle="$t('LABEL_DASHBOARD.DESCRIPTION')"
      icon="i-lucide-tags"
    />

    <!-- filtros do core (o calendário abre em posição absoluta: fica fora
         de qualquer bloco de vidro pra não ser cortado) -->
    <OverviewReportFilters class="mb-6" @filter-change="onFilterChange" />

    <!-- 🏆 Principais etiquetas -->
    <div class="cv-block p-5 sm:p-6 mb-6" :style="blockVars('top')">
      <div class="flex items-center gap-2 mb-5 flex-wrap">
        <span class="cv-icon"><span class="i-lucide-trophy text-base" /></span>
        <h2 class="text-sm font-bold text-n-slate-12">{{ $t('LABEL_DASHBOARD.TOP_LABELS') }}</h2>
      </div>
      <div v-if="isLoadingSummary" class="flex justify-center py-8">
        <Spinner :size="28" class="text-n-brand" />
      </div>
      <div v-else-if="topLabels.length" class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
        <div
          v-for="item in topLabels"
          :key="item.id"
          class="cv-sub p-4 flex flex-col gap-1"
        >
          <span class="text-xs text-n-slate-11 truncate inline-flex items-center gap-1.5">
            <span
              class="w-2.5 h-2.5 rounded-full flex-shrink-0"
              :style="{ background: labelColor(item.id) || 'var(--cv)' }"
            />
            {{ labels.find(l => l.id === item.id)?.title ?? item.id }}
          </span>
          <span class="text-2xl font-bold text-n-slate-12">
            {{ (item.conversationsCount ?? 0).toLocaleString() }}
          </span>
          <span class="text-xs text-n-slate-10">{{ $t('LABEL_DASHBOARD.CONVERSATIONS') }}</span>
          <div class="cv-track cv-track-sm mt-1">
            <div
              class="cv-fill"
              :style="{
                width: Math.max(4, Math.round(((item.conversationsCount ?? 0) / Math.max(1, topLabels[0]?.conversationsCount ?? 0)) * 100)) + '%',
                background: labelColor(item.id) || undefined,
              }"
            />
          </div>
        </div>
      </div>
      <p v-else class="text-sm text-n-slate-10 py-4">
        {{ $t('LABEL_DASHBOARD.NO_DATA') }}
      </p>
    </div>

    <!-- 📊 Conversas por etiqueta (gráfico de barras) -->
    <div class="cv-block p-5 sm:p-6 mb-6" :style="blockVars('grafico')">
      <div class="flex items-center gap-2 mb-5 flex-wrap">
        <span class="cv-icon"><span class="i-lucide-bar-chart-3 text-base" /></span>
        <h2 class="text-sm font-bold text-n-slate-12">{{ $t('LABEL_DASHBOARD.CHART_TITLE') }}</h2>
      </div>
      <div v-if="isLoadingSummary" class="flex justify-center py-8">
        <Spinner :size="28" class="text-n-brand" />
      </div>
      <div v-else-if="barChartData.labels.length" class="h-64">
        <BarChart :collection="barChartData" />
      </div>
      <p v-else class="text-sm text-n-slate-10 py-4">
        {{ $t('LABEL_DASHBOARD.NO_DATA') }}
      </p>
    </div>

    <!-- 🔲 Matriz Caixa de Entrada × Etiqueta -->
    <div class="cv-block p-5 sm:p-6 mb-6" :style="blockVars('matriz')">
      <div class="flex items-center gap-2 mb-5 flex-wrap">
        <span class="cv-icon"><span class="i-lucide-grid-3x3 text-base" /></span>
        <h2 class="text-sm font-bold text-n-slate-12">{{ $t('LABEL_DASHBOARD.MATRIX_TITLE') }}</h2>
      </div>
      <div v-if="isLoadingMatrix" class="flex justify-center py-8">
        <Spinner :size="28" class="text-n-brand" />
      </div>
      <div v-else-if="matrixRows.length" class="overflow-x-auto">
        <table class="w-full text-xs border-collapse">
          <thead>
            <tr>
              <th class="py-2 pr-4 text-left text-n-slate-11 font-medium min-w-32">
                {{ $t('LABEL_DASHBOARD.MATRIX_INBOX') }}
              </th>
              <th
                v-for="lbl in matrixLabels"
                :key="lbl.id"
                class="py-2 px-2 text-center text-n-slate-11 font-medium whitespace-nowrap"
              >
                <span class="inline-flex items-center gap-1.5">
                  <span
                    class="w-2 h-2 rounded-full flex-shrink-0"
                    :style="{ background: labelColor(lbl.id) || 'var(--cv)' }"
                  />
                  {{ lbl.title }}
                </span>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(row, i) in matrixRows"
              :key="i"
              class="border-t"
              style="border-color: rgb(var(--cv-rgb) / 0.16)"
            >
              <td class="py-2 pr-4 text-n-slate-12 font-medium whitespace-nowrap">
                {{ matrixInboxes[i]?.name ?? '—' }}
              </td>
              <td
                v-for="(count, j) in row"
                :key="j"
                class="py-1 px-1 text-center"
              >
                <span
                  class="inline-block min-w-8 rounded-lg px-1.5 py-0.5 font-medium"
                  :class="cellIntensity(count)"
                >
                  {{ count || '—' }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p v-else class="text-sm text-n-slate-10 py-4">
        {{ $t('LABEL_DASHBOARD.NO_DATA') }}
      </p>
    </div>
  </div>
</template>

<style scoped>
/* mapa de calor da matriz: 4 degraus no tom do bloco (lê as --cv* do kit) */
.cv-heat-0 { background: rgb(var(--cv-rgb) / 0.05); color: var(--cv-deep); opacity: 0.6; }
.cv-heat-1 { background: rgb(var(--cv-rgb) / 0.14); color: var(--cv-deep); }
.cv-heat-2 { background: rgb(var(--cv-rgb) / 0.3); color: var(--cv-deep); }
.cv-heat-3 { background: rgb(var(--cv-rgb) / 0.6); color: #fff; }
.cv-heat-4 { background: var(--cv-grad); color: #fff; box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.35); }
.dark .cv-heat-0, .dark .cv-heat-1, .dark .cv-heat-2 { color: #fff; }
</style>
