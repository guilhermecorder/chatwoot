<script setup>
// Gráfico de barras ENXUTO em SVG (kit CEVICO, item 141) — sem biblioteca:
// série do período nos popups dos cards de KPI e nos cards do "+".
// Destaca a maior barra, mostra rótulos nas pontas e no meio, e cada barra
// tem tooltip nativo (<title>) com rótulo + valor.
import { computed } from 'vue';

const props = defineProps({
  values: { type: Array, default: () => [] },
  labels: { type: Array, default: () => [] },
  color: { type: String, default: '#0F5FA6' },
  height: { type: Number, default: 96 },
  // valor de referência (ex.: média do período anterior) → linha tracejada
  reference: { type: Number, default: null },
  format: { type: Function, default: v => String(v) },
});

const W = 320;
const PAD = 4;
const max = computed(() => Math.max(1, ...props.values.map(v => Number(v) || 0), props.reference || 0));
const barW = computed(() => Math.max(2, (W - PAD * 2) / Math.max(1, props.values.length) - 2));
const bars = computed(() =>
  props.values.map((v, i) => {
    const val = Number(v) || 0;
    const h = (val / max.value) * (props.height - 18);
    return {
      i,
      x: PAD + i * (barW.value + 2),
      y: props.height - 14 - h,
      h: Math.max(val > 0 ? 2 : 0, h),
      val,
      label: props.labels[i] || '',
      isMax: val > 0 && val === Math.max(...props.values.map(n => Number(n) || 0)),
    };
  })
);
const refY = computed(() =>
  props.reference === null ? null : props.height - 14 - (props.reference / max.value) * (props.height - 18)
);
const tickIdx = computed(() => {
  const n = props.values.length;
  if (n <= 1) return [0];
  if (n <= 8) return props.values.map((_, i) => i);
  return [0, Math.floor(n / 2), n - 1];
});
</script>

<template>
  <svg :viewBox="`0 0 ${W} ${height}`" class="w-full" :style="{ height: height + 'px' }" preserveAspectRatio="none">
    <line
      v-if="refY !== null"
      :x1="PAD" :x2="W - PAD" :y1="refY" :y2="refY"
      stroke="currentColor" stroke-dasharray="4 3" stroke-width="1" class="text-n-slate-9" opacity="0.7"
    />
    <g v-for="b in bars" :key="b.i">
      <rect
        :x="b.x" :y="b.y" :width="barW" :height="b.h" rx="2"
        :fill="color" :opacity="b.isMax ? 1 : 0.55"
      />
      <title>{{ b.label }}: {{ format(b.val) }}</title>
    </g>
    <text
      v-for="i in tickIdx"
      :key="'t' + i"
      :x="PAD + i * (barW + 2) + barW / 2"
      :y="height - 3"
      text-anchor="middle"
      font-size="9"
      fill="currentColor"
      class="text-n-slate-10"
    >
      {{ labels[i] }}
    </text>
  </svg>
</template>
