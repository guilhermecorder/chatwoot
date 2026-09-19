<script setup>
// Comparação lado a lado de 2 a 4 criativos (item 172, rodada 2): modal
// sólido do kit, o melhor de cada linha marcado com troféu + palavra, o
// veredito de cada peça (bom / atenção / ruim) e as curvas de retenção.
import { computed } from 'vue';
import RetentionCurve from './RetentionCurve.vue';
import MiniRadar from 'dashboard/components-next/cevico/MiniRadar.vue';
import RadarAxesPicker from './RadarAxesPicker.vue';
import { useRadarAxes, datasetFor } from './radarAxes';
import {
  fmtMoney,
  fmtCompact,
  fmtPct,
  fmtNum,
  BAND_META,
} from './creativeFormat';

const props = defineProps({
  rows: { type: Array, default: () => [] },
  cvVars: { type: Object, default: () => ({}) },
  targets: { type: Object, default: () => ({}) },
  averages: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['close']);

const COLORS = ['#0F5FA6', '#D4AF37', '#2E8B57', '#C0392B'];

// teia: um polígono por criativo, na cor da coluna
const { axesFor } = useRadarAxes('comparar');
const radarAxes = computed(() => axesFor('copy', 'creative', true));
const radarDatasets = computed(() =>
  props.rows.map((r, i) =>
    datasetFor(
      r,
      radarAxes.value,
      { targets: props.targets, averages: props.averages, peers: props.rows },
      { key: r.ad_id, label: r.ad_name, color: COLORS[i % COLORS.length] }
    )
  )
);

const METRICS = [
  {
    key: 'hook',
    label: 'Gancho · taxa de parada',
    band: 'hook',
    get: r => r.rates.hook_rate,
    fmt: v => fmtPct(v),
    best: 'max',
  },
  {
    key: 'hold',
    label: 'Corpo · retenção',
    band: 'hold',
    get: r => r.rates.hold_rate,
    fmt: v => fmtPct(v),
    best: 'max',
  },
  {
    key: 'ctr',
    label: 'CTA · CTR de link',
    band: 'cta',
    get: r => r.rates.link_ctr,
    fmt: v => fmtPct(v, 2),
    best: 'max',
  },
  {
    key: 'conv',
    label: 'Conversa por clique',
    band: 'conv',
    get: r => r.rates.conv_rate,
    fmt: v => fmtPct(v),
    best: 'max',
  },
  {
    key: 'cost',
    label: 'Custo por conversa',
    band: 'cost',
    get: r => r.rates.cost_conversation,
    fmt: v => (v ? fmtMoney(v) : '—'),
    best: 'min',
  },
  {
    key: 'cpm',
    label: 'CPM',
    get: r => r.rates.cpm,
    fmt: v => (v ? fmtMoney(v) : '—'),
    best: 'min',
  },
  {
    key: 'spend',
    label: 'Investimento',
    get: r => r.totals.spend,
    fmt: v => fmtMoney(v),
    best: null,
  },
  {
    key: 'impr',
    label: 'Impressões',
    get: r => r.totals.impressions,
    fmt: v => fmtCompact(v),
    best: null,
  },
  {
    key: 'conversations',
    label: 'Conversas iniciadas',
    get: r => r.totals.conversations,
    fmt: v => fmtNum(v),
    best: 'max',
  },
  {
    key: 'leads',
    label: 'Leads no CRM',
    get: r => r.funnel.leads,
    fmt: v => fmtNum(v),
    best: 'max',
  },
  {
    key: 'booked',
    label: 'Consultas marcadas',
    get: r => r.funnel.booked,
    fmt: v => fmtNum(v),
    best: 'max',
  },
  {
    key: 'surgeries',
    label: 'Cirurgias',
    get: r => r.funnel.surgeries,
    fmt: v => fmtNum(v),
    best: 'max',
  },
];

const bestIndex = m => {
  const valid = props.rows
    .map((r, i) => ({ v: m.get(r), i }))
    .filter(x => x.v !== null && x.v !== undefined && !Number.isNaN(x.v));
  if (!m.best || valid.length < 2) return -1;
  const sorted = [...valid].sort((a, b) =>
    m.best === 'max' ? b.v - a.v : a.v - b.v
  );
  return sorted[0].v === sorted[1].v ? -1 : sorted[0].i;
};
const bandOf = (r, m) =>
  m.band && r.diagnosis && r.diagnosis.bands ? r.diagnosis.bands[m.band] : null;
const series = computed(() =>
  props.rows
    .map((r, i) => ({
      label: r.ad_name,
      values: r.rates.retention,
      color: COLORS[i % COLORS.length],
    }))
    .filter(s => Array.isArray(s.values))
);
</script>

<template>
  <Teleport to="body">
    <div
      class="cv-page fixed inset-0 z-[60] flex items-center justify-center bg-black/60 p-3 sm:p-6"
      :style="cvVars"
      @click.self="emit('close')"
    >
      <div class="cv-modal w-full max-w-6xl max-h-[92vh] flex flex-col">
        <div class="cv-modal-head flex items-center gap-3">
          <span class="cv-icon cv-icon-lg"
            ><span class="i-lucide-columns-3 text-lg"
          /></span>
          <div class="min-w-0 flex-1">
            <p class="text-[11px] opacity-80">Lado a lado</p>
            <h2 class="text-base font-bold">Comparar criativos</h2>
          </div>
          <button
            class="cv-iconbtn cv-iconbtn-lg"
            title="Fechar"
            @click="emit('close')"
          >
            <span class="i-lucide-x" />
          </button>
        </div>
        <div class="overflow-y-auto min-h-0 p-5 sm:p-6">
          <div
            class="cv-sub rounded-2xl p-4 mb-5 flex flex-col md:flex-row md:items-center gap-4"
          >
            <MiniRadar
              :axes="radarAxes"
              :datasets="radarDatasets"
              :size="240"
              legend
            />
            <div class="min-w-0 flex-1">
              <p class="text-xs font-bold text-n-slate-12 mb-1">
                Teia: a força de cada parte, lado a lado
              </p>
              <p class="text-[11px] text-n-slate-10 mb-2">
                100 = atingiu o parâmetro bom · 50 = na linha do ruim · sem
                parâmetro, contra o melhor dos comparados.
              </p>
              <RadarAxesPicker env="comparar" :only="['copy']" />
            </div>
          </div>
          <div class="overflow-x-auto -mx-2 px-2">
            <table class="w-full text-xs">
              <thead>
                <tr>
                  <th
                    class="text-left text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold py-2 pr-3"
                  >
                    Métrica
                  </th>
                  <th
                    v-for="(r, i) in rows"
                    :key="r.ad_id"
                    class="text-left py-2 px-3 align-top min-w-[11rem]"
                  >
                    <span
                      class="inline-block w-2.5 h-2.5 rounded-full mr-1 align-middle"
                      :style="{ background: COLORS[i % COLORS.length] }"
                    />
                    <span class="font-bold text-n-slate-12">{{
                      r.ad_name
                    }}</span>
                    <span class="block text-[10px] text-n-slate-9 font-normal"
                      >{{ r.format_label }} · {{ r.cta_label }}</span
                    >
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="m in METRICS"
                  :key="m.key"
                  class="border-t border-n-weak"
                >
                  <td class="py-2 pr-3 text-n-slate-11 whitespace-nowrap">
                    {{ m.label }}
                  </td>
                  <td
                    v-for="(r, i) in rows"
                    :key="r.ad_id"
                    class="py-2 px-3 tabular-nums align-top"
                    :class="
                      bestIndex(m) === i
                        ? 'font-bold text-n-slate-12'
                        : 'text-n-slate-11'
                    "
                  >
                    <span class="text-sm">{{ m.fmt(m.get(r)) }}</span>
                    <span
                      v-if="bestIndex(m) === i"
                      class="ml-1 inline-flex items-center gap-0.5 text-[10px] text-amber-600 font-semibold"
                      ><span class="i-lucide-trophy" />melhor</span
                    >
                    <span
                      v-if="bandOf(r, m)"
                      class="block text-[10px] font-semibold inline-flex items-center gap-0.5"
                      :class="BAND_META[bandOf(r, m)].cls"
                      ><span :class="BAND_META[bandOf(r, m)].icon" />{{
                        BAND_META[bandOf(r, m)].label
                      }}</span
                    >
                  </td>
                </tr>
                <tr class="border-t border-n-weak">
                  <td class="py-2 pr-3 text-n-slate-11">Gancho</td>
                  <td
                    v-for="r in rows"
                    :key="r.ad_id"
                    class="py-2 px-3 text-n-slate-12 font-semibold align-top"
                  >
                    {{ r.hook || '—' }}
                  </td>
                </tr>
                <tr class="border-t border-n-weak">
                  <td class="py-2 pr-3 text-n-slate-11 align-top">Corpo</td>
                  <td
                    v-for="r in rows"
                    :key="r.ad_id"
                    class="py-2 px-3 text-n-slate-11 whitespace-pre-line align-top"
                  >
                    {{ r.body || '—' }}
                  </td>
                </tr>
                <tr class="border-t border-n-weak">
                  <td class="py-2 pr-3 text-n-slate-11 align-top">Leitura</td>
                  <td
                    v-for="r in rows"
                    :key="r.ad_id"
                    class="py-2 px-3 text-n-slate-11 align-top"
                  >
                    {{ r.diagnosis ? r.diagnosis.text : '—' }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div v-if="series.length" class="mt-5">
            <p class="text-xs font-semibold text-n-slate-11 mb-1">
              Curva de retenção · % das impressões que chegou a cada marco
            </p>
            <RetentionCurve :series="series" :height="200" />
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>
