<script setup>
// Radar (teia) de 4 eixos — compara até 2 conjuntos (ex.: DISC ×
// Temperamentos, ou teste atual × anterior), como o gráfico de atributos
// de jogador que inspirou o pedido.
import { computed } from 'vue';

const props = defineProps({
  axes: { type: Array, required: true }, // [{ key, label, color }]
  datasets: { type: Array, required: true }, // [{ label, color, values: {key: 0..100} }]
  size: { type: Number, default: 240 },
});

const cx = computed(() => props.size / 2);
const cy = computed(() => props.size / 2);
const radius = computed(() => props.size / 2 - 36);

const pointFor = (axisIndex, value) => {
  const angle = (Math.PI * 2 * axisIndex) / props.axes.length - Math.PI / 2;
  const r = (Math.max(0, Math.min(100, value)) / 100) * radius.value;
  return [cx.value + r * Math.cos(angle), cy.value + r * Math.sin(angle)];
};

const polygonFor = dataset =>
  props.axes
    .map((axis, i) => pointFor(i, dataset.values[axis.key] || 0).join(','))
    .join(' ');

const labelPos = i => {
  const angle = (Math.PI * 2 * i) / props.axes.length - Math.PI / 2;
  const r = radius.value + 20;
  return { x: cx.value + r * Math.cos(angle), y: cy.value + r * Math.sin(angle) };
};

const rings = [0.25, 0.5, 0.75, 1];
const gridPolygon = scale =>
  props.axes.map((_a, i) => pointFor(i, scale * 100).join(',')).join(' ');
</script>

<template>
  <div>
    <svg :viewBox="`0 0 ${size} ${size}`" class="w-full max-w-[300px] mx-auto">
      <!-- teia -->
      <polygon
        v-for="ring in rings"
        :key="ring"
        :points="gridPolygon(ring)"
        fill="none"
        stroke="currentColor"
        class="text-n-slate-6"
        stroke-width="0.75"
        opacity="0.5"
      />
      <line
        v-for="(axis, i) in axes"
        :key="axis.key"
        :x1="cx"
        :y1="cy"
        :x2="pointFor(i, 100)[0]"
        :y2="pointFor(i, 100)[1]"
        stroke="currentColor"
        class="text-n-slate-6"
        stroke-width="0.75"
        opacity="0.5"
      />
      <!-- conjuntos -->
      <g v-for="(ds, di) in datasets" :key="ds.label">
        <polygon
          :points="polygonFor(ds)"
          :fill="ds.color"
          :fill-opacity="di === 0 ? 0.28 : 0.18"
          :stroke="ds.color"
          stroke-width="2"
          stroke-linejoin="round"
          class="cevico-radar-poly"
        />
        <circle
          v-for="(axis, i) in axes"
          :key="axis.key"
          :cx="pointFor(i, ds.values[axis.key] || 0)[0]"
          :cy="pointFor(i, ds.values[axis.key] || 0)[1]"
          r="3"
          :fill="ds.color"
        />
      </g>
      <!-- rótulos -->
      <text
        v-for="(axis, i) in axes"
        :key="`l-${axis.key}`"
        :x="labelPos(i).x"
        :y="labelPos(i).y"
        text-anchor="middle"
        dominant-baseline="middle"
        class="text-[10px] font-bold"
        :fill="axis.color"
      >
        {{ axis.label }}
      </text>
    </svg>
    <!-- legenda -->
    <div class="flex items-center justify-center gap-4 mt-1 flex-wrap">
      <span v-for="ds in datasets" :key="`leg-${ds.label}`" class="flex items-center gap-1.5 text-[11px] text-n-slate-11">
        <span class="w-2.5 h-2.5 rounded-full" :style="{ background: ds.color }" />
        {{ ds.label }}
      </span>
    </div>
  </div>
</template>

<style scoped>
.cevico-radar-poly {
  transition: all 0.7s cubic-bezier(0.22, 1, 0.36, 1);
}
</style>
