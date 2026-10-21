<script setup>
// 📈 AreaChart (kit CEVICO, item 285 — 29/09): gráfico de ÁREA suave com
// degradê, uma área por série, sobrepostas e translúcidas (referência dele:
// "Sessions × Page Views"). Substitui a barra empilhada fina (ShareBar) onde
// o que importa é ver COMO o número se formou ao longo do período.
//   series = [{ key, label, color, values: [n por balde], hint? }]
//   labels = rótulo de cada balde (hora ou dia)
// Legenda em botões (total e %) — clicar emite `pick` (a tela abre os nomes).
import { computed, ref, onMounted, onBeforeUnmount } from 'vue';
import { smoothPath } from 'dashboard/helper/cevicoBuckets';

const props = defineProps({
  series: { type: Array, default: () => [] },
  labels: { type: Array, default: () => [] },
  height: { type: Number, default: 190 },
  format: {
    type: Function,
    default: v => Number(v || 0).toLocaleString('pt-BR'),
  },
  // palavra do que está sendo contado, no tooltip ("marcadas", "pacientes")
  unit: { type: String, default: '' },
  active: { type: String, default: '' },
  legend: { type: Boolean, default: true },
  // rótulo CURTO do eixo (item 318: "R$ 15.000" não cabe nos 30 px)
  axisFormat: { type: Function, default: null },
  // largura da coluna do eixo (px) — números maiores pedem mais espaço
  axisWidth: { type: Number, default: 30 },
});
const emit = defineEmits(['pick']);

const uid = `ac${Math.random().toString(36).slice(2, 8)}`;
const wrap = ref(null);
const W = ref(640);
let observer = null;
const measure = () => {
  const w = wrap.value?.clientWidth;
  if (w) W.value = Math.max(220, Math.round(w));
};
onMounted(() => {
  measure();
  if (typeof ResizeObserver !== 'undefined' && wrap.value) {
    observer = new ResizeObserver(measure);
    observer.observe(wrap.value);
  }
});
onBeforeUnmount(() => observer?.disconnect());

const LEFT = computed(() => props.axisWidth);
const RIGHT = 22;
const TOP = 12;
const BOTTOM = 24;
const n = computed(() => props.labels.length);
const plotW = computed(() => W.value - LEFT.value - RIGHT);
const plotH = computed(() => props.height - TOP - BOTTOM);
const list = computed(() =>
  props.series
    .map(s => ({
      ...s,
      values: (s.values || []).map(v => Number(v) || 0),
      total: (s.values || []).reduce((a, b) => a + (Number(b) || 0), 0),
    }))
    .filter(s => s.total > 0)
    .sort((a, b) => b.total - a.total)
);
const grand = computed(() => list.value.reduce((a, s) => a + s.total, 0));
const max = computed(() => Math.max(1, ...list.value.flatMap(s => s.values)));
// teto "redondo" e 4 linhas de grade
const ceil = computed(() => {
  const m = max.value;
  if (m <= 2) return 2;
  if (m <= 4) return 4;
  const pow = 10 ** Math.floor(Math.log10(m));
  return [1, 2, 4, 5, 10].map(f => f * pow).find(v => v >= m) || m;
});
const ticks = computed(() =>
  (ceil.value === 2 ? [0, 0.5, 1] : [0, 0.25, 0.5, 0.75, 1]).map(f => ({
    value: ceil.value * f,
    y: TOP + plotH.value * (1 - f),
  }))
);
const xAt = i =>
  n.value <= 1
    ? LEFT.value + plotW.value / 2
    : LEFT.value + (i / (n.value - 1)) * plotW.value;
const yAt = v => TOP + plotH.value * (1 - v / ceil.value);
const base = computed(() => TOP + plotH.value);

const shapes = computed(() =>
  list.value.map((s, idx) => {
    // um balde só: desenha um "morro" para a área existir
    const values = n.value === 1 ? [0, s.values[0], 0] : s.values;
    const pts = values.map((v, i) => [
      n.value === 1 ? LEFT.value + (i / 2) * plotW.value : xAt(i),
      yAt(v),
    ]);
    const line = smoothPath(pts);
    const first = pts[0][0].toFixed(1);
    const last = pts[pts.length - 1][0].toFixed(1);
    return {
      ...s,
      idx,
      line,
      area: `${line} L${last},${base.value} L${first},${base.value} Z`,
      dimmed: props.active && props.active !== s.key,
    };
  })
);
// no máximo ~8 rótulos no eixo de baixo
const xLabels = computed(() => {
  const every = Math.max(1, Math.ceil(n.value / 8));
  return props.labels
    .map((label, i) => ({ label, i, x: xAt(i) }))
    .filter(l => l.i % every === 0 || l.i === n.value - 1)
    .filter((l, k, arr) => k === 0 || l.x - arr[k - 1].x > 34);
});

// ── tooltip ──
const hover = ref(-1);
const onMove = event => {
  const rect = wrap.value?.getBoundingClientRect();
  if (!rect || !n.value) return;
  const x = (event.touches?.[0]?.clientX ?? event.clientX) - rect.left;
  const ratio = (x - LEFT.value) / Math.max(1, plotW.value);
  hover.value = Math.min(
    n.value - 1,
    Math.max(0, Math.round(ratio * (n.value - 1)))
  );
};
const tip = computed(() => {
  if (hover.value < 0) return null;
  const i = hover.value;
  const rows = list.value
    .map(s => ({ label: s.label, color: s.color, value: s.values[i] || 0 }))
    .filter(r => r.value > 0);
  const x = xAt(i);
  return {
    i,
    x,
    label: props.labels[i],
    rows,
    total: rows.reduce((a, r) => a + r.value, 0),
    left: x > W.value * 0.62,
  };
});
const pct = v => {
  if (!grand.value) return '0%';
  const p = (v / grand.value) * 100;
  return `${p > 0 && p < 1 ? p.toFixed(1) : Math.round(p)}%`;
};
</script>

<template>
  <div class="cv-area">
    <div
      ref="wrap"
      class="cv-area-plot"
      :style="{ height: `${height}px` }"
      @mousemove="onMove"
      @touchstart.passive="onMove"
      @touchmove.passive="onMove"
      @mouseleave="hover = -1"
    >
      <svg
        v-if="list.length"
        :width="W"
        :height="height"
        :viewBox="`0 0 ${W} ${height}`"
        role="img"
        aria-hidden="true"
      >
        <defs>
          <linearGradient
            v-for="s in shapes"
            :id="`${uid}-${s.idx}`"
            :key="`g${s.key}`"
            x1="0"
            y1="0"
            x2="0"
            y2="1"
          >
            <stop offset="0%" :stop-color="s.color" stop-opacity="0.5" />
            <stop offset="100%" :stop-color="s.color" stop-opacity="0.04" />
          </linearGradient>
        </defs>
        <g class="cv-area-grid">
          <line
            v-for="t in ticks"
            :key="`t${t.value}`"
            :x1="LEFT"
            :x2="W - RIGHT"
            :y1="t.y"
            :y2="t.y"
          />
          <text
            v-for="t in ticks"
            :key="`tl${t.value}`"
            :x="LEFT - 6"
            :y="t.y + 3"
            text-anchor="end"
          >
            {{ Number.isInteger(t.value) ? (axisFormat || format)(t.value) : '' }}
          </text>
          <text
            v-for="l in xLabels"
            :key="`x${l.i}`"
            :x="l.x"
            :y="height - 6"
            text-anchor="middle"
          >
            {{ l.label }}
          </text>
        </g>
        <g
          v-for="s in shapes"
          :key="`s${s.key}`"
          class="cv-area-serie"
          :class="{ 'cv-area-dim': s.dimmed }"
        >
          <path :d="s.area" :fill="`url(#${uid}-${s.idx})`" />
          <path
            :d="s.line"
            fill="none"
            :stroke="s.color"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </g>
        <g v-if="tip">
          <line
            class="cv-area-cursor"
            :x1="tip.x"
            :x2="tip.x"
            :y1="TOP"
            :y2="base"
          />
          <template v-if="n > 1">
            <circle
              v-for="s in shapes"
              v-show="s.values[tip.i] > 0"
              :key="`d${s.key}`"
              :cx="tip.x"
              :cy="yAt(s.values[tip.i] || 0)"
              r="4"
              :fill="s.color"
              stroke="#fff"
              stroke-width="2"
            />
          </template>
        </g>
      </svg>
      <p v-else class="cv-area-empty">nada no período</p>
      <div
        v-if="tip"
        class="cv-area-tip"
        :class="{ 'cv-area-tip-left': tip.left }"
        :style="{ left: `${tip.x}px` }"
      >
        <p class="cv-area-tip-title">
          {{ tip.label }}
          <b>{{ format(tip.total) }}</b>
          {{ unit }}
        </p>
        <p v-for="r in tip.rows" :key="r.label" class="cv-area-tip-row">
          <span class="cv-area-dot" :style="{ background: r.color }" />
          <span class="truncate">{{ r.label }}</span>
          <b>{{ format(r.value) }}</b>
        </p>
        <p v-if="!tip.rows.length" class="cv-area-tip-row">nada aqui</p>
      </div>
    </div>
    <div v-if="legend && list.length" class="cv-area-legend">
      <button
        v-for="s in list"
        :key="`l${s.key}`"
        type="button"
        class="cv-area-key"
        :class="{ 'cv-area-key-on': active === s.key }"
        :title="s.hint || `${s.label}: ${format(s.total)} (${pct(s.total)})`"
        @click="emit('pick', s)"
      >
        <span class="cv-area-dot" :style="{ background: s.color }" />
        <span class="truncate">{{ s.label }}</span>
        <b>{{ format(s.total) }}</b>
        <span class="cv-area-pct">{{ pct(s.total) }}</span>
      </button>
    </div>
  </div>
</template>

<style scoped>
.cv-area-plot {
  position: relative;
  width: 100%;
  touch-action: pan-y;
}
.cv-area-grid line {
  stroke: rgb(100 116 139 / 0.18);
  stroke-dasharray: 3 4;
}
.cv-area-grid text {
  font-size: 10px;
  fill: rgb(100 116 139);
  font-variant-numeric: tabular-nums;
}
.cv-area-serie {
  transition: opacity 0.2s ease;
}
.cv-area-dim {
  opacity: 0.18;
}
.cv-area-cursor {
  stroke: rgb(100 116 139 / 0.55);
  stroke-width: 1;
}
.cv-area-empty {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100%;
  font-size: 12px;
  color: rgb(100 116 139);
}
.cv-area-tip {
  position: absolute;
  top: 4px;
  transform: translateX(10px);
  min-width: 150px;
  max-width: 240px;
  padding: 8px 10px;
  border-radius: 12px;
  font-size: 11px;
  pointer-events: none;
  z-index: 5;
  color: rgb(15 23 42);
  background: rgb(255 255 255 / 0.96);
  border: 1px solid rgb(15 23 42 / 0.08);
  box-shadow: 0 12px 30px -12px rgb(15 23 42 / 0.4);
}
.cv-area-tip-left {
  transform: translateX(calc(-100% - 10px));
}
.dark .cv-area-tip {
  color: rgb(241 245 249);
  background: rgb(23 25 28 / 0.96);
  border-color: rgb(255 255 255 / 0.12);
}
.cv-area-tip-title {
  font-weight: 600;
  margin-bottom: 4px;
}
.cv-area-tip-title b {
  margin-left: 4px;
}
.cv-area-tip-row {
  display: flex;
  align-items: center;
  gap: 6px;
  line-height: 1.5;
}
.cv-area-tip-row b {
  margin-left: auto;
  font-variant-numeric: tabular-nums;
}
.cv-area-dot {
  width: 8px;
  height: 8px;
  border-radius: 9999px;
  flex-shrink: 0;
}
.cv-area-legend {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin-top: 10px;
}
.cv-area-key {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  max-width: 100%;
  height: 26px;
  padding: 0 10px;
  border-radius: 9999px;
  font-size: 11px;
  font-weight: 600;
  cursor: pointer;
  color: inherit;
  background: rgb(var(--cv-rgb, 37 99 235) / 0.08);
  border: 1px solid rgb(var(--cv-rgb, 37 99 235) / 0.18);
  transition: background 0.15s ease;
}
.cv-area-key:hover,
.cv-area-key-on {
  background: rgb(var(--cv-rgb, 37 99 235) / 0.2);
}
.cv-area-key b {
  font-variant-numeric: tabular-nums;
}
.cv-area-pct {
  font-weight: 400;
  opacity: 0.6;
  font-variant-numeric: tabular-nums;
}
</style>
