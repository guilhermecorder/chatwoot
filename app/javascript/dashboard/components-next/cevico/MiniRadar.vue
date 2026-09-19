<script setup>
// TEIA (radar) pequena e reutilizável do kit CEVICO — mesmo desenho do radar
// da área de Pessoas (anéis, raios, polígono com pontos), mas cabe dentro de
// um card: 40 px sem rótulos até ~240 px com rótulos curtos. Cada conjunto
// (dataset) é um polígono; o segundo pode ser tracejado (ex.: média da conta).
import { computed } from 'vue';

const props = defineProps({
  axes: { type: Array, required: true }, // [{ key, label, short }]
  datasets: { type: Array, required: true }, // [{ key, label, color, values{key:0..100}, texts{key}, dashed }]
  size: { type: Number, default: 120 },
  labels: { type: Boolean, default: true },
  legend: { type: Boolean, default: false },
});

const pad = computed(() => (props.labels ? 18 : 4));
const c = computed(() => props.size / 2);
const radius = computed(() => props.size / 2 - pad.value);
const count = computed(() => props.axes.length);
const clamp = v => Math.max(0, Math.min(100, Number(v) || 0));
const angle = i => (Math.PI * 2 * i) / count.value - Math.PI / 2;
const point = (i, v) => {
  const r = (clamp(v) / 100) * radius.value;
  return [c.value + r * Math.cos(angle(i)), c.value + r * Math.sin(angle(i))];
};
const polygon = ds =>
  props.axes.map((a, i) => point(i, ds.values[a.key]).join(',')).join(' ');
const grid = s =>
  props.axes.map((_a, i) => point(i, s * 100).join(',')).join(' ');
const labelFor = i => {
  const r = radius.value + 9;
  const cos = Math.cos(angle(i));
  const sin = Math.sin(angle(i));
  let anchor = 'middle';
  if (cos > 0.25) anchor = 'start';
  else if (cos < -0.25) anchor = 'end';
  let baseline = 'middle';
  if (sin > 0.25) baseline = 'hanging';
  else if (sin < -0.25) baseline = 'auto';
  return { x: c.value + r * cos, y: c.value + r * sin, anchor, baseline };
};
const RINGS = [0.25, 0.5, 0.75, 1];
const fontSize = computed(() => (props.size >= 200 ? 10 : 9));
</script>

<template>
  <div class="inline-flex flex-col items-center">
    <svg
      :viewBox="`0 0 ${size} ${size}`"
      :width="size"
      :height="size"
      class="block overflow-visible"
    >
      <template v-if="count >= 3">
        <polygon
          v-for="ring in RINGS"
          :key="ring"
          :points="grid(ring)"
          fill="none"
          stroke="currentColor"
          class="text-n-slate-7"
          stroke-width="0.75"
          :opacity="ring === 1 ? 0.7 : 0.4"
        />
        <line
          v-for="(a, i) in axes"
          :key="`ax-${a.key}`"
          :x1="c"
          :y1="c"
          :x2="point(i, 100)[0]"
          :y2="point(i, 100)[1]"
          stroke="currentColor"
          class="text-n-slate-7"
          stroke-width="0.75"
          opacity="0.4"
        />
        <g v-for="(ds, di) in datasets" :key="ds.key || ds.label || di">
          <polygon
            :points="polygon(ds)"
            :fill="ds.color"
            :fill-opacity="ds.dashed ? 0.08 : di === 0 ? 0.28 : 0.16"
            :stroke="ds.color"
            :stroke-width="ds.dashed ? 1.2 : 1.8"
            :stroke-dasharray="ds.dashed ? '3 3' : null"
            stroke-linejoin="round"
            class="cv-radar-poly"
          />
          <circle
            v-for="(a, i) in axes"
            :key="`pt-${ds.key}-${a.key}`"
            :cx="point(i, ds.values[a.key])[0]"
            :cy="point(i, ds.values[a.key])[1]"
            :r="ds.dashed ? 1.6 : size >= 100 ? 2.6 : 1.8"
            :fill="ds.color"
          >
            <title v-if="ds.texts && ds.texts[a.key]">
              {{ ds.texts[a.key] }}
            </title>
          </circle>
        </g>
        <g v-if="labels">
          <text
            v-for="(a, i) in axes"
            :key="`lb-${a.key}`"
            :x="labelFor(i).x"
            :y="labelFor(i).y"
            :text-anchor="labelFor(i).anchor"
            :dominant-baseline="labelFor(i).baseline"
            :font-size="fontSize"
            font-weight="700"
            fill="currentColor"
            class="text-n-slate-11"
          >
            {{ a.short || a.label }}
          </text>
        </g>
      </template>
      <text
        v-else
        :x="c"
        :y="c"
        text-anchor="middle"
        dominant-baseline="middle"
        font-size="9"
        fill="currentColor"
        class="text-n-slate-9"
      >
        3+ eixos
      </text>
    </svg>
    <div
      v-if="legend && datasets.length > 1"
      class="flex items-center justify-center gap-3 mt-1 flex-wrap"
    >
      <span
        v-for="ds in datasets"
        :key="`lg-${ds.key || ds.label}`"
        class="inline-flex items-center gap-1 text-[10px] text-n-slate-10"
      >
        <span
          class="w-2 h-2 rounded-full"
          :style="{ background: ds.color, opacity: ds.dashed ? 0.6 : 1 }"
        />{{ ds.label }}
      </span>
    </div>
  </div>
</template>

<style scoped>
.cv-radar-poly {
  transition: all 0.6s cubic-bezier(0.22, 1, 0.36, 1);
}
</style>
