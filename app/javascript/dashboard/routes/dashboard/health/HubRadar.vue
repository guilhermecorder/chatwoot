<script setup>
// RADAR (teia) do HUB — rodada 30b. Nasceu do RadarChart da área de
// Pessoas, com o que faltava pro HUB: rótulos com folga e ancorados por
// lado (nada cortado), preenchimento em degradê da paleta, piso mínimo
// (a forma não colapsa no centro quando um eixo é zero), pontos com
// borda branca e legenda opcional. Valores 0–100 por eixo.
import { computed } from 'vue';

const props = defineProps({
  axes: { type: Array, required: true }, // [{ key, label, color? }]
  datasets: { type: Array, required: true }, // [{ label, color, values: {key: 0..100} }]
  size: { type: Number, default: 240 },
  floor: { type: Number, default: 6 }, // % mínimo desenhado (só visual)
  legend: { type: Boolean, default: true },
  labelSize: { type: Number, default: 10 },
});

const uid = `hr${Math.random().toString(36).slice(2, 8)}`;
// folga horizontal extra no viewBox: rótulos laterais ("Sequências",
// "Movimento") cabem inteiros sem depender de overflow
const ex = computed(() => Math.round(props.size * 0.22));
const pad = computed(() => Math.max(40, Math.round(props.size * 0.2)));
const cx = computed(() => props.size / 2);
const cy = computed(() => props.size / 2);
const radius = computed(() => props.size / 2 - pad.value);
const n = computed(() => Math.max(3, props.axes.length));

const angleOf = i => (Math.PI * 2 * i) / n.value - Math.PI / 2;
const pointAt = (i, pct) => {
  const a = angleOf(i);
  const r = (Math.max(0, Math.min(100, pct)) / 100) * radius.value;
  return [cx.value + r * Math.cos(a), cy.value + r * Math.sin(a)];
};
const valueOf = (ds, axis) => {
  const v = Number(ds.values?.[axis.key]) || 0;
  return v > 0 ? Math.max(props.floor, v) : props.floor;
};
const polygonOf = ds => props.axes.map((ax, i) => pointAt(i, valueOf(ds, ax)).join(',')).join(' ');
const rings = [0.25, 0.5, 0.75, 1];
const ringPoints = k => props.axes.map((_a, i) => pointAt(i, k * 100).join(',')).join(' ');

// rótulo: fora da teia, ancorado conforme o lado (esq/dir/topo/base)
const labelOf = i => {
  const a = angleOf(i);
  const r = radius.value + 12;
  const x = cx.value + r * Math.cos(a);
  const y = cy.value + r * Math.sin(a);
  const c = Math.cos(a);
  const s = Math.sin(a);
  const anchor = c > 0.35 ? 'start' : c < -0.35 ? 'end' : 'middle';
  const dy = s < -0.8 ? -3 : s > 0.8 ? 9 : 4;
  return { x, y, anchor, dy };
};
const colorOf = (ax, i) => ax.color || (i % 2 ? '#B85C00' : '#27408B');
</script>

<template>
  <div class="hub-radar">
    <svg :viewBox="`${-ex} 0 ${size + ex * 2} ${size}`" class="hub-radar-svg" :style="{ maxWidth: `${size + ex * 2}px` }">
      <defs>
        <radialGradient v-for="(ds, di) in datasets" :id="`${uid}-g${di}`" :key="`g-${di}`" cx="50%" cy="50%" r="60%">
          <stop offset="0%" :stop-color="ds.color" stop-opacity="0.45" />
          <stop offset="100%" :stop-color="ds.color" stop-opacity="0.12" />
        </radialGradient>
      </defs>
      <!-- teia -->
      <polygon v-for="k in rings" :key="k" :points="ringPoints(k)" fill="none" class="hub-radar-ring" :class="{ 'is-outer': k === 1 }" />
      <line v-for="(ax, i) in axes" :key="`ax-${ax.key}`" :x1="cx" :y1="cy" :x2="pointAt(i, 100)[0]" :y2="pointAt(i, 100)[1]" class="hub-radar-axis" />
      <!-- conjuntos -->
      <g v-for="(ds, di) in datasets" :key="`ds-${di}`" class="hub-radar-set">
        <polygon :points="polygonOf(ds)" :fill="`url(#${uid}-g${di})`" :stroke="ds.color" stroke-width="2" stroke-linejoin="round" />
        <circle
          v-for="(ax, i) in axes"
          :key="`p-${di}-${ax.key}`"
          :cx="pointAt(i, valueOf(ds, ax))[0]"
          :cy="pointAt(i, valueOf(ds, ax))[1]"
          r="3.2"
          :fill="ds.color"
          stroke="#fff"
          stroke-width="1.4"
        />
      </g>
      <!-- rótulos -->
      <text
        v-for="(ax, i) in axes"
        :key="`l-${ax.key}`"
        :x="labelOf(i).x"
        :y="labelOf(i).y + labelOf(i).dy"
        :text-anchor="labelOf(i).anchor"
        :font-size="labelSize"
        font-weight="700"
        :fill="colorOf(ax, i)"
        class="hub-radar-label"
      >
        {{ ax.label }}
      </text>
    </svg>
    <div v-if="legend && datasets.length" class="hub-radar-legend">
      <span v-for="(ds, di) in datasets" :key="`lg-${di}`">
        <i :style="{ background: ds.color }" />{{ ds.label }}
      </span>
    </div>
  </div>
</template>

<style scoped>
.hub-radar { width: 100%; }
.hub-radar-svg { width: 100%; height: auto; display: block; margin: 0 auto; overflow: visible; }
.hub-radar-ring { stroke: rgba(65, 105, 225, 0.22); stroke-width: 0.8; }
.hub-radar-ring.is-outer { stroke: rgba(65, 105, 225, 0.4); stroke-width: 1; }
.hub-radar-axis { stroke: rgba(65, 105, 225, 0.18); stroke-width: 0.8; }
.hub-radar-set { animation: hub-radar-in 0.6s cubic-bezier(0.2, 0.9, 0.3, 1) both; transform-origin: center; }
@keyframes hub-radar-in {
  from { opacity: 0; transform: scale(0.6); }
  to { opacity: 1; transform: none; }
}
.hub-radar-label { letter-spacing: 0.01em; }
.hub-radar-legend { display: flex; justify-content: center; gap: 12px; flex-wrap: wrap; margin-top: 2px; font-size: 11px; color: #64748b; }
.hub-radar-legend span { display: inline-flex; align-items: center; gap: 5px; }
.hub-radar-legend i { width: 9px; height: 9px; border-radius: 50%; display: inline-block; }
:global(.dark) .hub-radar-legend { color: rgba(255, 255, 255, 0.7); }
@media (prefers-reduced-motion: reduce) { .hub-radar-set { animation: none; } }
</style>
