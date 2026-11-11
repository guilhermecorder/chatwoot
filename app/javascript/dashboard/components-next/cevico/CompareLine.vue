<script setup>
// 📈 CompareLine (kit CEVICO, item 394 — 11/11): gráfico de LINHA com a BASE
// DE COMPARAÇÃO desenhada junto. A linha de AGORA vem forte, com a área em
// degradê; a de ANTES vem mais clara e tracejada, no mesmo eixo, balde a
// balde (1º dia com 1º dia). Pedido dele: "gosto daquelas linhas… sempre
// poder ter uma base de comparação".
//   values      = [n por balde] do período
//   prevValues  = [n | null por balde] da base (null = balde que não existe lá)
//   labels / prevLabels = rótulo de cada balde ("05/11") nos dois períodos
// Passar o dedo/mouse mostra os dois números do balde e a diferença.
import { computed, ref, onMounted, onBeforeUnmount } from 'vue';
import { smoothPath } from 'dashboard/helper/cevicoBuckets';
import { variation } from 'dashboard/helper/cevicoComparison';

const props = defineProps({
  values: { type: Array, default: () => [] },
  prevValues: { type: Array, default: null },
  labels: { type: Array, default: () => [] },
  prevLabels: { type: Array, default: () => [] },
  // nomes das duas linhas na legenda e no balão
  currentLabel: { type: String, default: 'agora' },
  previousLabel: { type: String, default: 'antes' },
  color: { type: String, default: '' }, // vazio = cor do dia (--cv)
  height: { type: Number, default: 200 },
  format: {
    type: Function,
    default: v => Number(v || 0).toLocaleString('pt-BR'),
  },
  unit: { type: String, default: '' },
  // false = cair é bom (faltas, cancelamentos): só muda a cor da diferença
  goodWhenUp: { type: Boolean, default: true },
  legend: { type: Boolean, default: true },
  // sem eixo nem rótulos: a linha ocupa a caixa toda (cartões pequenos)
  bare: { type: Boolean, default: false },
});

const uid = `cl${Math.random().toString(36).slice(2, 8)}`;
const wrap = ref(null);
const W = ref(560);
let observer = null;
const measure = () => {
  const w = wrap.value?.clientWidth;
  if (w) W.value = Math.max(120, Math.round(w));
};
onMounted(() => {
  measure();
  if (typeof ResizeObserver !== 'undefined' && wrap.value) {
    observer = new ResizeObserver(measure);
    observer.observe(wrap.value);
  }
});
onBeforeUnmount(() => observer?.disconnect());

const LEFT = computed(() => (props.bare ? 4 : 34));
const RIGHT = computed(() => (props.bare ? 4 : 14));
const TOP = computed(() => (props.bare ? 6 : 12));
const BOTTOM = computed(() => (props.bare ? 6 : 24));

const cur = computed(() => props.values.map(v => Number(v) || 0));
// a base só entra se tiver algum número; null continua null (buraco na linha)
const prev = computed(() => {
  const list = props.prevValues;
  if (!Array.isArray(list) || !list.some(v => v !== null && v !== undefined))
    return null;
  return cur.value.map((_, i) =>
    list[i] === null || list[i] === undefined ? null : Number(list[i]) || 0
  );
});
const n = computed(() => cur.value.length);
const plotW = computed(() => W.value - LEFT.value - RIGHT.value);
const plotH = computed(() => props.height - TOP.value - BOTTOM.value);
const max = computed(() =>
  Math.max(1, ...cur.value, ...(prev.value || []).map(v => v || 0))
);
// teto "redondo" e linhas de grade
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
    y: TOP.value + plotH.value * (1 - f),
  }))
);
const xAt = i =>
  n.value <= 1
    ? LEFT.value + plotW.value / 2
    : LEFT.value + (i / (n.value - 1)) * plotW.value;
const yAt = v => TOP.value + plotH.value * (1 - v / ceil.value);
const base = computed(() => TOP.value + plotH.value);

// um balde só (Hoje/Ontem): vira um "morro" para a linha existir
const pointsOf = values =>
  n.value === 1
    ? [0, values[0] || 0, 0].map((v, i) => [
        LEFT.value + (i / 2) * plotW.value,
        yAt(v),
      ])
    : values.map((v, i) => [xAt(i), yAt(v)]);

const curShape = computed(() => {
  if (!n.value) return null;
  const pts = pointsOf(cur.value);
  const line = smoothPath(pts);
  const first = pts[0][0].toFixed(1);
  const last = pts[pts.length - 1][0].toFixed(1);
  return {
    line,
    area: `${line} L${last},${base.value} L${first},${base.value} Z`,
    end: n.value === 1 ? pts[1] : pts[pts.length - 1],
  };
});
// a linha de antes para onde a base acaba (mês de 30 × mês de 31 dias)
const prevShape = computed(() => {
  if (!prev.value || !n.value) return null;
  const upto = prev.value.findIndex(v => v === null);
  const values = upto === -1 ? prev.value : prev.value.slice(0, upto);
  if (!values.length) return null;
  if (n.value === 1) return { line: smoothPath(pointsOf(values)) };
  return { line: smoothPath(values.map((v, i) => [xAt(i), yAt(v)])) };
});

// no máximo ~8 rótulos no eixo de baixo
const xLabels = computed(() => {
  const every = Math.max(1, Math.ceil(n.value / 8));
  return props.labels
    .map((label, i) => ({ label, i, x: xAt(i) }))
    .filter(l => l.i % every === 0 || l.i === n.value - 1)
    .filter((l, k, arr) => k === 0 || l.x - arr[k - 1].x > 34);
});

const total = computed(() => cur.value.reduce((a, b) => a + b, 0));
const prevTotal = computed(() =>
  prev.value ? prev.value.reduce((a, b) => a + (b || 0), 0) : null
);

// ── balão ──
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
  const antes = prev.value ? prev.value[i] : null;
  return {
    i,
    x: xAt(i),
    label: props.labels[i],
    prevLabel: props.prevLabels[i] || '',
    agora: cur.value[i],
    antes,
    dif:
      antes === null || antes === undefined
        ? null
        : variation(cur.value[i], antes, { bomQuandoSobe: props.goodWhenUp }),
    left: xAt(i) > W.value * 0.6,
  };
});
const stroke = computed(() => props.color || 'var(--cv, #2563eb)');
</script>

<template>
  <div class="cv-cline" :style="{ '--cl': stroke }">
    <div
      ref="wrap"
      class="cv-cline-plot"
      :style="{ height: `${height}px` }"
      @mousemove="onMove"
      @touchstart.passive="onMove"
      @touchmove.passive="onMove"
      @mouseleave="hover = -1"
    >
      <svg
        v-if="curShape"
        :width="W"
        :height="height"
        :viewBox="`0 0 ${W} ${height}`"
        role="img"
        :aria-label="`${currentLabel}: ${format(total)}${
          prevTotal === null ? '' : `; ${previousLabel}: ${format(prevTotal)}`
        }`"
      >
        <defs>
          <linearGradient :id="uid" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stop-color="var(--cl)" stop-opacity="0.34" />
            <stop offset="100%" stop-color="var(--cl)" stop-opacity="0.02" />
          </linearGradient>
        </defs>
        <g v-if="!bare" class="cv-cline-grid">
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
            {{ Number.isInteger(t.value) ? format(t.value) : '' }}
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
        <path :d="curShape.area" :fill="`url(#${uid})`" />
        <path v-if="prevShape" class="cv-cline-prev" :d="prevShape.line" />
        <path class="cv-cline-cur" :d="curShape.line" />
        <circle
          v-if="!tip"
          class="cv-cline-end"
          :cx="curShape.end[0]"
          :cy="curShape.end[1]"
          r="4"
        />
        <g v-if="tip">
          <line
            class="cv-cline-cursor"
            :x1="tip.x"
            :x2="tip.x"
            :y1="TOP"
            :y2="base"
          />
          <circle
            v-if="tip.antes !== null && tip.antes !== undefined && n > 1"
            class="cv-cline-dot-prev"
            :cx="tip.x"
            :cy="yAt(tip.antes)"
            r="3.5"
          />
          <circle
            v-if="n > 1"
            class="cv-cline-end"
            :cx="tip.x"
            :cy="yAt(tip.agora)"
            r="4.5"
          />
        </g>
      </svg>
      <div
        v-if="tip"
        class="cv-cline-tip"
        :class="{ 'cv-cline-tip-left': tip.left }"
        :style="{ left: `${tip.x}px` }"
      >
        <p class="cv-cline-tip-row">
          <span class="cv-cline-key cv-cline-key-cur" />
          <span>{{ tip.label }}</span>
          <b>{{ format(tip.agora) }}</b>
        </p>
        <p
          v-if="tip.antes !== null && tip.antes !== undefined"
          class="cv-cline-tip-row"
        >
          <span class="cv-cline-key cv-cline-key-prev" />
          <span>{{ tip.prevLabel || previousLabel }}</span>
          <b>{{ format(tip.antes) }}</b>
        </p>
        <p
          v-if="tip.dif"
          class="cv-cline-tip-dif"
          :class="`cv-cline-${tip.dif.estado}`"
        >
          {{ tip.dif.seta }} {{ tip.dif.curto }}
          <template v-if="unit"> · {{ unit }}</template>
        </p>
      </div>
    </div>
    <div v-if="legend" class="cv-cline-legend">
      <span>
        <i class="cv-cline-key cv-cline-key-cur" />
        {{ currentLabel }} <b>{{ format(total) }}</b>
      </span>
      <span v-if="prevTotal !== null">
        <i class="cv-cline-key cv-cline-key-prev" />
        {{ previousLabel }} <b>{{ format(prevTotal) }}</b>
      </span>
      <span v-else class="cv-cline-nobase">sem base de comparação</span>
    </div>
  </div>
</template>

<style scoped>
.cv-cline {
  width: 100%;
  min-width: 0;
}
.cv-cline-plot {
  position: relative;
  width: 100%;
  touch-action: pan-y;
}
.cv-cline-grid line {
  stroke: rgb(100 116 139 / 0.18);
  stroke-dasharray: 3 4;
}
.cv-cline-grid text {
  font-size: 10px;
  fill: rgb(100 116 139);
  font-variant-numeric: tabular-nums;
}
.cv-cline-cur {
  fill: none;
  stroke: var(--cl);
  stroke-width: 2.5;
  stroke-linecap: round;
  stroke-linejoin: round;
}
/* a base de comparação: a mesma cor, bem mais clara e tracejada */
.cv-cline-prev {
  fill: none;
  stroke: var(--cl);
  stroke-opacity: 0.38;
  stroke-width: 2;
  stroke-dasharray: 5 5;
  stroke-linecap: round;
  stroke-linejoin: round;
}
.cv-cline-end {
  fill: var(--cl);
  stroke: #fff;
  stroke-width: 2;
}
.cv-cline-dot-prev {
  fill: #fff;
  stroke: var(--cl);
  stroke-opacity: 0.6;
  stroke-width: 2;
}
.cv-cline-cursor {
  stroke: rgb(100 116 139 / 0.55);
  stroke-width: 1;
}
.cv-cline-tip {
  position: absolute;
  top: 4px;
  transform: translateX(10px);
  min-width: 150px;
  max-width: 240px;
  padding: 8px 10px;
  border-radius: 12px;
  font-size: 12px;
  line-height: 18px;
  pointer-events: none;
  z-index: 5;
  color: rgb(15 23 42);
  background: rgb(255 255 255 / 0.97);
  border: 1px solid rgb(15 23 42 / 0.08);
  box-shadow: 0 12px 30px -12px rgb(15 23 42 / 0.4);
}
.cv-cline-tip-left {
  transform: translateX(calc(-100% - 10px));
}
.dark .cv-cline-tip {
  color: rgb(241 245 249);
  background: rgb(23 25 28 / 0.97);
  border-color: rgb(255 255 255 / 0.12);
}
.cv-cline-tip-row {
  display: flex;
  align-items: center;
  gap: 6px;
  margin: 0;
}
.cv-cline-tip-row b {
  margin-left: auto;
  padding-left: 10px;
  font-variant-numeric: tabular-nums;
}
.cv-cline-tip-dif {
  margin: 4px 0 0;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}
.cv-cline-bom {
  color: #15803d;
}
.cv-cline-atencao {
  color: #b45309;
}
.dark .cv-cline-bom {
  color: #4ade80;
}
.dark .cv-cline-atencao {
  color: #fbbf24;
}
.cv-cline-neutro {
  opacity: 0.7;
}
.cv-cline-key {
  display: inline-block;
  width: 16px;
  height: 0;
  border-top: 3px solid var(--cl);
  border-radius: 2px;
  flex-shrink: 0;
  vertical-align: middle;
}
.cv-cline-key-prev {
  border-top: 2px dashed var(--cl);
  opacity: 0.5;
}
.cv-cline-legend {
  display: flex;
  flex-wrap: wrap;
  gap: 4px 16px;
  margin-top: 8px;
  font-size: 12px;
  line-height: 18px;
  color: rgb(71 85 105);
}
.dark .cv-cline-legend {
  color: rgb(182 188 201);
}
.cv-cline-legend b {
  font-weight: 600;
  font-variant-numeric: tabular-nums;
  color: rgb(15 23 42);
}
.dark .cv-cline-legend b {
  color: rgb(243 244 246);
}
.cv-cline-nobase {
  opacity: 0.7;
}
</style>
