<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import ReportHeader from './components/ReportHeader.vue';
import OverviewReportFilters from './components/OverviewReportFilters.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ReportsAPI from 'dashboard/api/reports';

const { t } = useI18n();
const store = useStore();

const from = ref(0);
const to = ref(0);
const isLoadingMatrix = ref(false);
const matrixData = ref(null);

const labels = useMapGetter('labels/getLabels');
const labelSummaryReports = useMapGetter('summaryReports/getLabelSummaryReports');
const uiFlags = useMapGetter('summaryReports/getUIFlags');
const isLoadingSummary = computed(() => uiFlags.value.isFetchingLabelSummaryReports);

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
        backgroundColor: sorted.map((_, i) => `hsl(${(i * 37) % 360}, 65%, 55%)`),
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

const cellIntensity = count => {
  if (!count) return 'bg-n-alpha-1';
  const ratio = count / maxMatrixValue.value;
  if (ratio > 0.75) return 'bg-w-500 text-white';
  if (ratio > 0.5) return 'bg-w-400 text-white';
  if (ratio > 0.25) return 'bg-w-300';
  return 'bg-w-100';
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
  <ReportHeader
    :header-title="$t('LABEL_DASHBOARD.HEADER')"
    :header-description="$t('LABEL_DASHBOARD.DESCRIPTION')"
  />

  <OverviewReportFilters @filter-change="onFilterChange" />

  <!-- Top labels cards -->
  <div class="mt-6">
    <h3 class="text-sm font-semibold text-n-slate-11 mb-3">
      {{ $t('LABEL_DASHBOARD.TOP_LABELS') }}
    </h3>
    <div v-if="isLoadingSummary" class="flex justify-center py-8">
      <Spinner :size="28" class="text-n-brand" />
    </div>
    <div v-else-if="topLabels.length" class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
      <div
        v-for="item in topLabels"
        :key="item.id"
        class="rounded-xl border border-n-weak bg-n-solid-2 p-4 flex flex-col gap-1"
      >
        <span class="text-xs text-n-slate-11 truncate">
          {{ labels.find(l => l.id === item.id)?.title ?? item.id }}
        </span>
        <span class="text-2xl font-bold text-n-slate-12">
          {{ (item.conversationsCount ?? 0).toLocaleString() }}
        </span>
        <span class="text-xs text-n-slate-10">{{ $t('LABEL_DASHBOARD.CONVERSATIONS') }}</span>
      </div>
    </div>
    <p v-else class="text-sm text-n-slate-10 py-4">
      {{ $t('LABEL_DASHBOARD.NO_DATA') }}
    </p>
  </div>

  <!-- Bar chart -->
  <div class="mt-6 rounded-xl border border-n-weak bg-n-solid-2 p-5">
    <h3 class="text-sm font-semibold text-n-slate-11 mb-4">
      {{ $t('LABEL_DASHBOARD.CHART_TITLE') }}
    </h3>
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

  <!-- Inbox × Label matrix -->
  <div class="mt-6 rounded-xl border border-n-weak bg-n-solid-2 p-5">
    <h3 class="text-sm font-semibold text-n-slate-11 mb-4">
      {{ $t('LABEL_DASHBOARD.MATRIX_TITLE') }}
    </h3>
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
              {{ lbl.title }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(row, i) in matrixRows" :key="i" class="border-t border-n-weak">
            <td class="py-2 pr-4 text-n-slate-12 font-medium whitespace-nowrap">
              {{ matrixInboxes[i]?.name ?? '—' }}
            </td>
            <td
              v-for="(count, j) in row"
              :key="j"
              class="py-1 px-1 text-center"
            >
              <span
                :class="['inline-block min-w-8 rounded px-1.5 py-0.5 font-medium', cellIntensity(count)]"
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
</template>
