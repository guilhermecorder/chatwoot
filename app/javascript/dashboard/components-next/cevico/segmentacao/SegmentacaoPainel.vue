<script setup>
// 🧪 item 383: PAINEL DA SEGMENTAÇÃO — os números de todos os segmentos e a
// linha do tempo dos últimos 30 dias (enviadas, respostas, consultas por dia).
import { ref, computed, onMounted, watch } from 'vue';
import { Chart as ChartJS, Tooltip, Legend, CategoryScale, LinearScale, PointElement, LineElement, Filler } from 'chart.js';
import { Line } from 'vue-chartjs';
import CrmAPI from 'dashboard/api/crm';
import { fmtInt, fmtPct, fmtDay } from './segmentacaoHelpers';

ChartJS.register(Tooltip, Legend, CategoryScale, LinearScale, PointElement, LineElement, Filler);

const props = defineProps({ refreshKey: { type: Number, default: 0 } });

const data = ref(null);
const loading = ref(false);
const load = async () => {
  loading.value = true;
  try {
    const { data: res } = await CrmAPI.getSegmentsDashboard();
    data.value = res;
  } catch {
    data.value = null;
  } finally {
    loading.value = false;
  }
};
onMounted(load);
watch(() => props.refreshKey, load);

const t = computed(() => data.value?.totals || {});
const tiles = computed(() => [
  { label: 'segmentos', value: fmtInt(t.value.segments), sub: `${fmtInt(t.value.testes)} testes · ${fmtInt(t.value.escalas)} escalas`, icon: 'i-lucide-layers' },
  { label: 'enviando agora', value: fmtInt(t.value.sending), sub: 'segmentos com o robô ligado', icon: 'i-lucide-play' },
  { label: 'na fila', value: fmtInt(t.value.reserved), sub: 'reservadas, ainda não receberam', icon: 'i-lucide-lock' },
  { label: 'enviadas', value: fmtInt(t.value.sent), sub: 'desde o começo', icon: 'i-lucide-send' },
  { label: 'respostas · 30 dias', value: fmtPct(t.value.replied_rate_30d), sub: `${fmtInt(t.value.replied_30d)} de ${fmtInt(t.value.sent_30d)} enviadas`, icon: 'i-lucide-message-circle-reply' },
  { label: 'consultas · 30 dias', value: fmtPct(t.value.booked_rate_30d), sub: `${fmtInt(t.value.booked_30d)} marcadas depois da mensagem`, icon: 'i-lucide-calendar-check' },
]);

const chart = computed(() => {
  const tl = data.value?.timeline;
  if (!tl?.days?.length) return null;
  const line = (label, values, color) => ({
    label, data: values, borderColor: color, backgroundColor: `${color}22`, borderWidth: 2, pointRadius: 2.5, tension: 0.35, fill: false,
  });
  return {
    data: {
      labels: tl.days.map(fmtDay),
      datasets: [line('Enviadas', tl.sent, '#2563EB'), line('Respostas', tl.replied, '#059669'), line('Consultas marcadas', tl.booked, '#D97706')],
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
        x: { ticks: { maxTicksLimit: 10 }, grid: { display: false } },
      },
      animation: { duration: 400 },
    },
  };
});
const hasSends = computed(() => Number(t.value.sent || 0) > 0);
</script>

<template>
  <div>
    <div class="flex items-start gap-4 mb-6 flex-wrap">
      <span class="cv-icon cv-icon-lg"><span class="i-lucide-line-chart text-xl" /></span>
      <div class="min-w-0 flex-1">
        <h2 class="text-xl sm:text-2xl tracking-tight font-bold text-n-slate-12 leading-tight">4. Painel</h2>
        <p class="text-sm text-n-slate-11 mt-1">Tudo que saiu pelos segmentos: quanto foi, quem respondeu e quantas consultas vieram, dia a dia.</p>
      </div>
    </div>
    <p v-if="loading && !data" class="text-sm text-n-slate-10">Somando…</p>
    <template v-else-if="data">
      <div class="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-3 mb-6">
        <div v-for="k in tiles" :key="k.label" class="painel-tile">
          <span class="cv-icon cv-icon-sm"><span :class="k.icon" class="text-xs" /></span>
          <b>{{ k.value }}</b>
          <span class="painel-label">{{ k.label }}</span>
          <span class="painel-sub">{{ k.sub }}</span>
        </div>
      </div>
      <div v-if="chart && hasSends" class="h-64"><Line :data="chart.data" :options="chart.options" /></div>
      <p v-else class="text-sm text-n-slate-10">O gráfico dos últimos 30 dias aparece quando o primeiro segmento começar a enviar.</p>
    </template>
  </div>
</template>

<style scoped>
.painel-tile {
  display: flex;
  flex-direction: column;
  gap: 4px;
  padding: 12px 14px;
  border-radius: 14px;
  background: rgb(var(--cv-rgb) / 0.08);
  border: 1px solid rgb(var(--cv-rgb) / 0.16);
  min-width: 0;
}
.painel-tile b {
  font-size: 22px;
  font-weight: 800;
  font-variant-numeric: tabular-nums;
  line-height: 1.1;
  white-space: nowrap;
}
.painel-label {
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  opacity: 0.8;
}
.painel-sub {
  font-size: 10px;
  opacity: 0.7;
}
</style>
