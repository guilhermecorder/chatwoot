<script setup>
// 🧪 item 383: RESULTADOS DE UM SEGMENTO, mensagem por mensagem — tabela
// (enviadas, entregues, lidas, respondeu, consulta, cirurgia, taxas) com a
// vencedora marcada, e o gráfico de linha por dia (enviadas / respostas /
// consultas, uma linha por mensagem, acumulado).
import { ref, computed, onMounted, watch } from 'vue';
import { Chart as ChartJS, Tooltip, Legend, CategoryScale, LinearScale, PointElement, LineElement, Filler } from 'chart.js';
import { Line } from 'vue-chartjs';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import { variantColor, fmtInt, fmtPct, fmtDay } from './segmentacaoHelpers';

ChartJS.register(Tooltip, Legend, CategoryScale, LinearScale, PointElement, LineElement, Filler);

const props = defineProps({
  segmentId: { type: Number, required: true },
  refreshKey: { type: Number, default: 0 },
});
const emit = defineEmits(['loaded']);

const results = ref(null);
const loading = ref(false);
const metric = ref('replied'); // 'sent' | 'replied' | 'booked'
const METRICS = [
  { key: 'sent', label: 'Enviadas' },
  { key: 'replied', label: 'Respostas' },
  { key: 'booked', label: 'Consultas marcadas' },
];

const load = async () => {
  loading.value = true;
  try {
    const { data } = await CrmAPI.getSegmentResults(props.segmentId);
    results.value = data;
    emit('loaded', data);
  } catch (err) {
    useAlert(err?.response?.data?.error || 'Não deu para carregar os resultados.');
  } finally {
    loading.value = false;
  }
};
onMounted(load);
watch(() => props.refreshKey, load);

const variants = computed(() => results.value?.variants || []);
const totals = computed(() => results.value?.totals || {});
const winner = computed(() => results.value?.winner || null);
const minSample = computed(() => Number(results.value?.min_sample || 20));

const cumulative = arr => {
  let acc = 0;
  return (arr || []).map(v => {
    acc += Number(v || 0);
    return acc;
  });
};
const chart = computed(() => {
  const t = results.value?.timeline;
  if (!t?.days?.length) return null;
  return {
    data: {
      labels: t.days.map(fmtDay),
      datasets: t.series.map(s => ({
        label: s.label,
        data: cumulative(s[metric.value]),
        borderColor: variantColor(s.key),
        backgroundColor: `${variantColor(s.key)}22`,
        borderWidth: 2,
        pointRadius: 3,
        tension: 0.35,
        fill: false,
      })),
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: 'index', intersect: false },
      plugins: {
        legend: { display: true, position: 'bottom', labels: { boxWidth: 12, padding: 14, font: { size: 11 } } },
        tooltip: { callbacks: { label: ctx => ` ${ctx.dataset.label}: ${fmtInt(ctx.raw)}` } },
      },
      scales: {
        y: { beginAtZero: true, ticks: { precision: 0, maxTicksLimit: 6 }, grid: { color: 'rgba(148, 163, 184, 0.18)' } },
        x: { ticks: { maxTicksLimit: 12 }, grid: { display: false } },
      },
      animation: { duration: 400 },
    },
  };
});
</script>

<template>
  <div>
    <p v-if="loading && !results" class="text-xs text-n-slate-10">Lendo os resultados…</p>
    <template v-if="results">
      <div class="overflow-x-auto -mx-1 px-1">
        <table class="w-full text-xs res-tabela">
          <thead>
            <tr class="text-left">
              <th class="py-2 pr-3 cv-label">Mensagem</th>
              <th class="py-2 pr-3 cv-label text-right">Enviadas</th>
              <th class="py-2 pr-3 cv-label text-right">Entregues</th>
              <th class="py-2 pr-3 cv-label text-right">Lidas</th>
              <th class="py-2 pr-3 cv-label text-right">Respondeu</th>
              <th class="py-2 pr-3 cv-label text-right">Consulta</th>
              <th class="py-2 cv-label text-right">Cirurgia</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="v in variants" :key="v.key" class="border-t text-n-slate-12" :class="{ 'res-winner': winner === v.key }">
              <td class="py-2 pr-3">
                <div class="flex items-center gap-2">
                  <span class="res-key" :style="{ background: variantColor(v.key) }">{{ v.key }}</span>
                  <span class="font-medium whitespace-nowrap">{{ v.label }}</span>
                  <span v-if="winner === v.key" class="cv-chip cv-gold" title="Maior taxa de consulta (desempate: respostas)">🏆 vencedora</span>
                  <span v-else-if="v.sent < minSample" class="text-[10px] text-n-slate-9 whitespace-nowrap">amostra pequena</span>
                </div>
                <div class="text-[10px] text-n-slate-9 font-mono mt-0.5">{{ v.template }}</div>
              </td>
              <td class="py-2 pr-3 text-right tabular-nums"><b>{{ fmtInt(v.sent) }}</b><span v-if="v.reserved" class="text-n-slate-9"> · {{ fmtInt(v.reserved) }} na fila</span></td>
              <td class="py-2 pr-3 text-right tabular-nums">{{ fmtInt(v.delivered) }}<span v-if="v.refused" class="text-red-600"> · {{ fmtInt(v.refused) }} recusadas</span></td>
              <td class="py-2 pr-3 text-right tabular-nums">{{ fmtInt(v.read) }} <span class="text-n-slate-9">({{ fmtPct(v.read_rate) }})</span></td>
              <td class="py-2 pr-3 text-right tabular-nums"><b>{{ fmtInt(v.replied) }}</b> <span class="text-n-slate-9">({{ fmtPct(v.replied_rate) }})</span></td>
              <td class="py-2 pr-3 text-right tabular-nums"><b>{{ fmtInt(v.booked) }}</b> <span class="text-n-slate-9">({{ fmtPct(v.booked_rate) }})</span></td>
              <td class="py-2 text-right tabular-nums">{{ fmtInt(v.surgery) }} <span class="text-n-slate-9">({{ fmtPct(v.surgery_rate) }})</span></td>
            </tr>
            <tr v-if="variants.length > 1" class="border-t font-bold text-n-slate-12">
              <td class="py-2 pr-3">Total</td>
              <td class="py-2 pr-3 text-right tabular-nums">{{ fmtInt(totals.sent) }}</td>
              <td class="py-2 pr-3 text-right tabular-nums">{{ fmtInt(totals.delivered) }}</td>
              <td class="py-2 pr-3 text-right tabular-nums">{{ fmtInt(totals.read) }}</td>
              <td class="py-2 pr-3 text-right tabular-nums">{{ fmtInt(totals.replied) }} <span class="font-normal text-n-slate-9">({{ fmtPct(totals.replied_rate) }})</span></td>
              <td class="py-2 pr-3 text-right tabular-nums">{{ fmtInt(totals.booked) }} <span class="font-normal text-n-slate-9">({{ fmtPct(totals.booked_rate) }})</span></td>
              <td class="py-2 text-right tabular-nums">{{ fmtInt(totals.surgery) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <p class="text-[11px] text-n-slate-10 mt-2">
        Respondeu = mandou qualquer mensagem depois de receber · Consulta = consulta marcada na Agenda depois do envio · Cirurgia = entrou numa coluna de cirurgia depois do envio.
        As taxas são sobre as entregáveis (enviadas menos as recusadas pela Meta). A vencedora só é marcada com pelo menos {{ minSample }} enviadas por mensagem.
      </p>

      <div v-if="chart" class="mt-5">
        <div class="flex flex-wrap items-center gap-2 mb-3">
          <span class="cv-label">Linha do tempo (acumulado por dia)</span>
          <div class="cv-seg cv-seg-sm">
            <button v-for="m in METRICS" :key="m.key" class="cv-seg-item" :class="{ 'cv-seg-on': metric === m.key }" @click="metric = m.key">{{ m.label }}</button>
          </div>
        </div>
        <div class="h-56"><Line :data="chart.data" :options="chart.options" /></div>
      </div>
      <p v-else class="text-xs text-n-slate-10 mt-3">O gráfico aparece quando a primeira leva sair.</p>
    </template>
  </div>
</template>

<style scoped>
.res-tabela tbody tr {
  border-color: rgb(var(--cv-rgb) / 0.18);
}
.res-winner {
  background: rgba(212, 175, 55, 0.1);
}
.res-key {
  width: 22px;
  height: 22px;
  border-radius: 8px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 11px;
  font-weight: 800;
  color: #fff;
  flex-shrink: 0;
}
</style>
