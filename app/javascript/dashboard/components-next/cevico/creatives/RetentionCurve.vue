<script setup>
// Curva de retenção do vídeo em SVG (kit CEVICO, sem lib): % das impressões
// que chegou a cada marco — 3 s (gancho) → 25 → 50 → 75 → 100 % (corpo).
// Aceita várias séries para comparar criativos (legenda + rótulo direto).
import { computed, ref } from 'vue';
import { fmtPct } from './creativeFormat';

const props = defineProps({
  // [{ label, values: [3s, p25, p50, p75, p100] em fração, color }]
  series: { type: Array, default: () => [] },
  height: { type: Number, default: 170 },
});

const MARKS = ['Impressões', '3 s', '25%', '50%', '75%', '100%'];
const W = 360;
const PAD = { l: 34, r: 14, t: 18, b: 26 };
const hovered = ref(null);

const plotW = W - PAD.l - PAD.r;
const plotH = computed(() => props.height - PAD.t - PAD.b);
const xAt = i => PAD.l + (plotW / (MARKS.length - 1)) * i;
const yAt = v => PAD.t + plotH.value * (1 - Math.max(0, Math.min(1, v || 0)));

const lines = computed(() =>
  props.series.map(s => {
    const values = [1, ...(s.values || []).slice(0, 5)];
    const pts = values.map((v, i) => [xAt(i), yAt(v)]);
    return {
      label: s.label,
      color: s.color || 'var(--cv)',
      values,
      path: pts
        .map((p, i) => `${i ? 'L' : 'M'}${p[0].toFixed(1)},${p[1].toFixed(1)}`)
        .join(' '),
      area: `${pts.map((p, i) => `${i ? 'L' : 'M'}${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(' ')} L${pts[pts.length - 1][0].toFixed(1)},${yAt(0)} L${pts[0][0].toFixed(1)},${yAt(0)} Z`,
      pts,
    };
  })
);
const gridY = [0, 0.25, 0.5, 0.75, 1];
</script>

<template>
  <div class="w-full">
    <svg
      :viewBox="`0 0 ${W} ${height}`"
      class="w-full h-auto select-none"
      role="img"
      aria-label="Curva de retenção do vídeo"
    >
      <g v-for="g in gridY" :key="g">
        <line
          :x1="PAD.l"
          :x2="W - PAD.r"
          :y1="yAt(g)"
          :y2="yAt(g)"
          class="stroke-n-slate-6"
          stroke-width="0.6"
        />
        <text
          :x="PAD.l - 6"
          :y="yAt(g) + 3"
          text-anchor="end"
          class="fill-n-slate-9"
          font-size="9"
        >
          {{ Math.round(g * 100) }}%
        </text>
      </g>
      <g v-for="(m, i) in MARKS" :key="m">
        <line
          :x1="xAt(i)"
          :x2="xAt(i)"
          :y1="PAD.t"
          :y2="height - PAD.b"
          class="stroke-n-slate-5"
          stroke-width="0.5"
          stroke-dasharray="2 3"
        />
        <text
          :x="xAt(i)"
          :y="height - 8"
          text-anchor="middle"
          class="fill-n-slate-10"
          font-size="9"
          font-weight="600"
        >
          {{ m }}
        </text>
      </g>
      <g v-for="(ln, si) in lines" :key="ln.label">
        <path v-if="si === 0" :d="ln.area" :fill="ln.color" opacity="0.10" />
        <path
          :d="ln.path"
          fill="none"
          :stroke="ln.color"
          stroke-width="2"
          stroke-linejoin="round"
          stroke-linecap="round"
        />
        <g
          v-for="(p, i) in ln.pts"
          :key="i"
          @mouseenter="hovered = { si, i }"
          @mouseleave="hovered = null"
        >
          <circle :cx="p[0]" :cy="p[1]" r="9" fill="transparent" />
          <circle
            :cx="p[0]"
            :cy="p[1]"
            :r="hovered && hovered.si === si && hovered.i === i ? 5 : 3.5"
            :fill="ln.color"
            class="stroke-n-surface-1"
            stroke-width="1.5"
          />
          <title>
            {{ ln.label }} · {{ MARKS[i] }}: {{ fmtPct(ln.values[i]) }}
          </title>
          <text
            v-if="
              i > 0 &&
              (lines.length === 1 ||
                (hovered && hovered.si === si && hovered.i === i))
            "
            :x="p[0]"
            :y="p[1] - 9"
            text-anchor="middle"
            class="fill-n-slate-12"
            font-size="9.5"
            font-weight="700"
          >
            {{ fmtPct(ln.values[i], 0) }}
          </text>
        </g>
      </g>
    </svg>
    <div v-if="lines.length > 1" class="flex flex-wrap gap-x-4 gap-y-1 mt-1">
      <span
        v-for="ln in lines"
        :key="ln.label"
        class="inline-flex items-center gap-1.5 text-[11px] text-n-slate-11"
      >
        <span class="w-3 h-0.5 rounded" :style="{ background: ln.color }" />{{
          ln.label
        }}
      </span>
    </div>
  </div>
</template>
