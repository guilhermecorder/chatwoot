<script setup>
// Gráfico de barras ENXUTO em SVG (kit CEVICO, itens 141/144) — sem lib:
// série do período nos popups dos cards de KPI e nos cards do "+".
// Item 144: série do período ANTERIOR sobreposta (linha tracejada balde a
// balde), linha de META (pontilhada ouro), marcadores 📌 das ações da
// empresa e TOOLTIP próprio (funciona no toque, não só no hover).
import { computed, ref } from 'vue';

const props = defineProps({
  values: { type: Array, default: () => [] },
  labels: { type: Array, default: () => [] },
  color: { type: String, default: '#0F5FA6' },
  height: { type: Number, default: 96 },
  // valor de referência (ex.: média do período anterior) → linha tracejada
  // reta; ignorado quando prevValues (a série inteira) está presente
  reference: { type: Number, default: null },
  // série do período anterior, balde a balde (item 144)
  prevValues: { type: Array, default: null },
  // meta do balde (fatia da meta mensal) → linha pontilhada ouro
  goal: { type: Number, default: null },
  // ações da empresa no período: [{ index, title }] → 📌 no topo do balde
  markers: { type: Array, default: () => [] },
  format: { type: Function, default: v => String(v) },
});

const W = 320;
const PAD = 4;
const prevSlice = computed(() =>
  props.prevValues ? props.prevValues.slice(0, Math.max(1, props.values.length)) : null
);
const max = computed(() =>
  Math.max(
    1,
    ...props.values.map(v => Number(v) || 0),
    ...(prevSlice.value || []).map(v => Number(v) || 0),
    props.reference || 0,
    props.goal || 0
  )
);
const chartTop = 10; // folga pros marcadores 📌
const plotH = computed(() => props.height - 14 - chartTop);
const yFor = v => props.height - 14 - ((Number(v) || 0) / max.value) * plotH.value;
const barW = computed(() => Math.max(2, (W - PAD * 2) / Math.max(1, props.values.length) - 2));
const centerX = i => PAD + i * (barW.value + 2) + barW.value / 2;
const bars = computed(() =>
  props.values.map((v, i) => {
    const val = Number(v) || 0;
    const h = (val / max.value) * plotH.value;
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
// período anterior como LINHA tracejada ligando os baldes (fantasma)
const prevLine = computed(() => {
  if (!prevSlice.value || !prevSlice.value.length) return null;
  return prevSlice.value.map((v, i) => `${centerX(i)},${yFor(v)}`).join(' ');
});
const refY = computed(() =>
  props.reference === null || prevLine.value ? null : yFor(props.reference)
);
const goalY = computed(() => (props.goal === null ? null : yFor(props.goal)));
const markerAt = i => props.markers.find(m => m.index === i) || null;
const tickIdx = computed(() => {
  const n = props.values.length;
  if (n <= 1) return [0];
  if (n <= 8) return props.values.map((_, i) => i);
  return [0, Math.floor(n / 2), n - 1];
});

// ── tooltip próprio (item 144): hover no desktop, toque no celular ──
// no mouse o pointerenter já marcou o balde — o pointerdown só age no
// TOQUE (senão o clique desmarcava o que o hover tinha acabado de marcar)
const active = ref(null);
const setActive = (i, ev) => {
  if (ev?.pointerType === 'mouse') {
    active.value = i;
    return;
  }
  active.value = active.value === i ? null : i;
};
const tooltip = computed(() => {
  if (active.value === null || !bars.value[active.value]) return null;
  const b = bars.value[active.value];
  const prev = prevSlice.value ? Number(prevSlice.value[b.i]) || 0 : null;
  let delta = null;
  if (prev !== null && prev > 0) {
    const pct = Math.round(((b.val - prev) / prev) * 100);
    delta = `${pct >= 0 ? '▲' : '▼'} ${Math.abs(pct)}% vs anterior`;
  }
  const marker = markerAt(b.i);
  return {
    label: b.label,
    value: props.format(b.val),
    prev: prev === null ? null : props.format(prev),
    delta,
    marker: marker ? marker.title : null,
    leftPct: Math.min(86, Math.max(14, (centerX(b.i) / W) * 100)),
  };
});
</script>

<template>
  <div class="relative" @pointerleave="active = null">
    <svg
      :viewBox="`0 0 ${W} ${height}`"
      class="w-full"
      :style="{ height: height + 'px' }"
      preserveAspectRatio="none"
    >
      <!-- linha de META (pontilhada ouro) -->
      <line
        v-if="goalY !== null"
        :x1="PAD" :x2="W - PAD" :y1="goalY" :y2="goalY"
        stroke="#D4A017" stroke-dasharray="2 3" stroke-width="1.4" opacity="0.9"
      />
      <!-- média do anterior (só quando não temos a série inteira) -->
      <line
        v-if="refY !== null"
        :x1="PAD" :x2="W - PAD" :y1="refY" :y2="refY"
        stroke="currentColor" stroke-dasharray="4 3" stroke-width="1" class="text-n-slate-9" opacity="0.7"
      />
      <g v-for="b in bars" :key="b.i">
        <rect
          :x="b.x" :y="b.y" :width="barW" :height="b.h" rx="2"
          :fill="color" :opacity="active === b.i ? 1 : b.isMax ? 0.95 : 0.55"
        />
        <!-- 📌 ação da empresa no balde -->
        <g v-if="markerAt(b.i)">
          <line :x1="centerX(b.i)" :x2="centerX(b.i)" :y1="chartTop - 2" :y2="height - 14" stroke="#D4A017" stroke-width="0.8" opacity="0.5" />
          <circle :cx="centerX(b.i)" :cy="chartTop - 4" r="3.2" fill="#D4A017" />
        </g>
        <!-- área de toque do balde inteiro (tooltip fácil no dedo) -->
        <rect
          :x="b.x - 1" :y="0" :width="barW + 2" :height="height" fill="transparent"
          style="cursor: pointer"
          @pointerenter="active = b.i"
          @pointerdown.prevent="setActive(b.i, $event)"
        />
      </g>
      <!-- série do período ANTERIOR (fantasma, balde a balde) -->
      <polyline
        v-if="prevLine"
        :points="prevLine"
        fill="none" stroke="currentColor" stroke-width="1.4" stroke-dasharray="4 3"
        class="text-n-slate-9" opacity="0.85" style="pointer-events: none"
      />
      <text
        v-for="i in tickIdx"
        :key="'t' + i"
        :x="centerX(i)"
        :y="height - 3"
        text-anchor="middle"
        font-size="9"
        fill="currentColor"
        class="text-n-slate-10"
      >
        {{ labels[i] }}
      </text>
    </svg>
    <!-- tooltip próprio -->
    <div
      v-if="tooltip"
      class="absolute top-0 -translate-x-1/2 -translate-y-1 z-10 rounded-lg border border-n-weak bg-n-solid-1 shadow-lg px-2.5 py-1.5 text-[10px] leading-tight whitespace-nowrap pointer-events-none"
      :style="{ left: tooltip.leftPct + '%' }"
    >
      <p class="font-semibold text-n-slate-12">{{ tooltip.label }} · {{ tooltip.value }}</p>
      <p v-if="tooltip.prev !== null" class="text-n-slate-10">anterior: {{ tooltip.prev }}<template v-if="tooltip.delta"> · {{ tooltip.delta }}</template></p>
      <p v-if="tooltip.marker" class="text-amber-600">📌 {{ tooltip.marker }}</p>
    </div>
  </div>
</template>
