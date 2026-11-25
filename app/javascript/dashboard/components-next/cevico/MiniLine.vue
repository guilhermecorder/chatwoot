<script setup>
// 📈 item 418 (25/11): MINI GRÁFICO DE LINHA (o "micro dashboard" dos cartões
// do Comparativo de caixas; desenho pedido pelo Guilherme a partir do painel de
// criativos: uma linha colorida por cartão, a linha tracejada cinza de
// referência e a mesma escala em todos os cartões do grupo).
//   values  números ou null (buraco = pontilhado por cima, nunca zero falso)
//   top     teto da escala (o grupo inteiro usa o mesmo: helper scaleFor)
//   base    valor da linha tracejada de referência (ou null)
// Curva suave que não inventa pico (smoothPath), pontas redondas.
import { computed, ref, onMounted, onBeforeUnmount } from 'vue';
import { smoothPath } from 'dashboard/helper/cevicoBuckets';
import { lineRuns } from 'dashboard/helper/cevicoInboxCompare';

const props = defineProps({
  values: { type: Array, default: () => [] },
  labels: { type: Array, default: () => [] },
  // texto extra de cada ponto no balão (ex.: "12 chegaram na janela")
  notes: { type: Array, default: () => [] },
  color: { type: String, default: '#2563EB' },
  top: { type: Number, default: 0 },
  ticks: { type: Array, default: () => [] },
  base: { type: Number, default: null },
  baseLabel: { type: String, default: '' },
  format: { type: Function, default: v => String(v) },
  height: { type: Number, default: 104 },
  // compacto: sem eixo nem datas (a linha sozinha, dentro de outro cartão)
  compact: { type: Boolean, default: false },
  emptyText: { type: String, default: 'ainda sem gente suficiente' },
  // 📍 item 419: marcos de teste — [{ pos: índice do ponto, label }] vira uma
  // linha em pé com o alfinete no topo (o "antes" fica à esquerda dela)
  marks: { type: Array, default: () => [] },
});

const wrap = ref(null);
const W = ref(260);
let observer = null;
onMounted(() => {
  if (wrap.value?.clientWidth)
    W.value = Math.max(120, Math.round(wrap.value.clientWidth));
  if (typeof ResizeObserver !== 'undefined' && wrap.value) {
    observer = new ResizeObserver(entries => {
      const w = entries[0]?.contentRect?.width;
      if (w) W.value = Math.max(120, Math.round(w));
    });
    observer.observe(wrap.value);
  }
});
onBeforeUnmount(() => observer?.disconnect());

const LEFT = computed(() => (props.compact ? 4 : 30));
const RIGHT = 8;
const TOP = 8;
const BOTTOM = computed(() => (props.compact ? 6 : 18));
const plotH = computed(() => props.height - TOP - BOTTOM.value);
const shape = computed(() => lineRuns(props.values));
const ceiling = computed(() => {
  const own = Math.max(
    0,
    ...shape.value.runs.flat().map(p => p[1]),
    props.base || 0
  );
  return Math.max(props.top || 0, own, 1);
});
const xAt = i => {
  const n = props.values.length;
  const span = W.value - LEFT.value - RIGHT;
  return n <= 1 ? LEFT.value + span / 2 : LEFT.value + (i / (n - 1)) * span;
};
const yAt = v => TOP + plotH.value - (v / ceiling.value) * plotH.value;
const toXY = p => [xAt(p[0]), yAt(p[1])];
const solid = computed(() =>
  shape.value.runs.filter(r => r.length > 1).map(r => smoothPath(r.map(toXY)))
);
const dots = computed(() =>
  shape.value.runs.filter(r => r.length === 1).map(r => toXY(r[0]))
);
const dashed = computed(() =>
  shape.value.bridges.map(([a, b]) => {
    const [x1, y1] = toXY(a);
    const [x2, y2] = toXY(b);
    return { x1, y1, x2, y2 };
  })
);
const end = computed(() => (shape.value.last ? toXY(shape.value.last) : null));
const area = computed(() => {
  const run = shape.value.runs.at(-1);
  if (!run || run.length < 2 || shape.value.runs.length > 1) return '';
  const pts = run.map(toXY);
  const floor = TOP + plotH.value;
  return `${smoothPath(pts)} L${pts.at(-1)[0].toFixed(1)},${floor} L${pts[0][0].toFixed(1)},${floor} Z`;
});
const baseY = computed(() =>
  props.base === null || props.base === undefined ? null : yAt(props.base)
);
const grid = computed(() =>
  (props.ticks.length ? props.ticks : [0, ceiling.value]).map(v => ({
    v,
    y: yAt(v),
  }))
);
const gradId = `cvMini${Math.random().toString(36).slice(2, 9)}`;
const pins = computed(() =>
  props.marks
    .filter(m => m && m.pos >= 0 && m.pos < props.values.length)
    .map(m => ({ x: xAt(m.pos), label: m.label || 'marco', pos: m.pos }))
);

const active = ref(null);
const onMove = ev => {
  const rect = wrap.value?.getBoundingClientRect();
  const n = props.values.length;
  if (!rect || !n) return;
  const span = W.value - LEFT.value - RIGHT;
  const raw =
    n <= 1 ? 0 : ((ev.clientX - rect.left - LEFT.value) / span) * (n - 1);
  active.value = Math.min(n - 1, Math.max(0, Math.round(raw)));
};
const tip = computed(() => {
  if (active.value === null) return null;
  const i = active.value;
  const v = props.values[i];
  return {
    x: xAt(i),
    y: v === null || v === undefined ? null : yAt(Number(v)),
    left: Math.min(80, Math.max(20, (xAt(i) / W.value) * 100)),
    label: props.labels[i] || '',
    value: v === null || v === undefined ? 'pouca gente' : props.format(v),
    note: props.notes[i] || '',
    marks: pins.value.filter(m => m.pos === i).map(m => m.label),
  };
});
</script>

<template>
  <div
    ref="wrap"
    class="cv-mini relative w-full select-none"
    :style="{ '--ml': color }"
    @pointermove="onMove"
    @pointerdown="onMove"
    @pointerleave="active = null"
  >
    <svg
      :viewBox="`0 0 ${W} ${height}`"
      :width="W"
      :height="height"
      class="block max-w-full"
      role="img"
      :aria-label="`linha de ${labels[0] || ''} a ${labels.at(-1) || ''}`"
    >
      <defs>
        <linearGradient :id="gradId" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" :stop-color="color" stop-opacity="0.2" />
          <stop offset="1" :stop-color="color" stop-opacity="0" />
        </linearGradient>
      </defs>
      <template v-if="!compact">
        <g v-for="g in grid" :key="`g${g.v}`">
          <line
            class="cv-mini-grid"
            :x1="LEFT"
            :x2="W - RIGHT"
            :y1="g.y"
            :y2="g.y"
          />
          <text
            class="cv-mini-eixo"
            :x="LEFT - 5"
            :y="g.y + 3"
            text-anchor="end"
          >
            {{ format(g.v) }}
          </text>
        </g>
      </template>
      <line
        v-else
        class="cv-mini-grid"
        :x1="LEFT"
        :x2="W - RIGHT"
        :y1="TOP + plotH"
        :y2="TOP + plotH"
      />
      <line
        v-if="baseY !== null"
        class="cv-mini-base"
        :x1="LEFT"
        :x2="W - RIGHT"
        :y1="baseY"
        :y2="baseY"
      />
      <path v-if="area" :d="area" :fill="`url(#${gradId})`" />
      <g v-for="(m, k) in pins" :key="`m${k}`" class="cv-mini-marco">
        <title>{{ m.label }}</title>
        <line :x1="m.x" :x2="m.x" :y1="TOP - 2" :y2="TOP + plotH" />
        <circle :cx="m.x" :cy="TOP - 2" r="3" />
      </g>
      <line
        v-for="(b, k) in dashed"
        :key="`b${k}`"
        class="cv-mini-ponte"
        :x1="b.x1"
        :y1="b.y1"
        :x2="b.x2"
        :y2="b.y2"
      />
      <path
        v-for="(d, k) in solid"
        :key="`s${k}`"
        class="cv-mini-linha"
        :d="d"
      />
      <circle
        v-for="(p, k) in dots"
        :key="`d${k}`"
        class="cv-mini-ponto"
        :cx="p[0]"
        :cy="p[1]"
        r="2.4"
      />
      <circle
        v-if="end"
        class="cv-mini-fim"
        :cx="end[0]"
        :cy="end[1]"
        r="3.6"
      />
      <template v-if="tip">
        <line
          class="cv-mini-guia"
          :x1="tip.x"
          :x2="tip.x"
          :y1="TOP"
          :y2="TOP + plotH"
        />
        <circle
          v-if="tip.y !== null"
          class="cv-mini-fim"
          :cx="tip.x"
          :cy="tip.y"
          r="4.2"
        />
      </template>
      <template v-if="!compact && labels.length">
        <text
          class="cv-mini-eixo"
          :x="LEFT"
          :y="height - 3"
          text-anchor="start"
        >
          {{ labels[0] }}
        </text>
        <text
          v-if="labels.length > 1"
          class="cv-mini-eixo"
          :x="W - RIGHT"
          :y="height - 3"
          text-anchor="end"
        >
          {{ labels.at(-1) }}
        </text>
      </template>
      <text
        v-if="!end"
        class="cv-mini-eixo"
        :x="LEFT + (W - LEFT - RIGHT) / 2"
        :y="TOP + plotH / 2 + 3"
        text-anchor="middle"
      >
        {{ emptyText }}
      </text>
    </svg>
    <div v-if="tip" class="cv-mini-balao" :style="{ left: `${tip.left}%` }">
      <b>{{ tip.label }} · {{ tip.value }}</b>
      <span v-if="tip.note">{{ tip.note }}</span>
      <span v-for="m in tip.marks" :key="m" class="cv-mini-balao-marco">
        📍 {{ m }}
      </span>
      <span v-if="base !== null && baseLabel">
        {{ baseLabel }}: {{ format(base) }}
      </span>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.cv-mini {
  touch-action: pan-y;
}
.cv-mini-grid {
  stroke: rgb(var(--slate-6) / 0.55);
  stroke-width: 1;
}
.cv-mini-eixo {
  font-size: 9.5px;
  fill: rgb(var(--slate-10));
  font-variant-numeric: tabular-nums;
}
.cv-mini-base {
  stroke: rgb(var(--slate-9));
  stroke-width: 1.2;
  stroke-dasharray: 4 4;
}
.cv-mini-linha {
  fill: none;
  stroke: var(--ml);
  stroke-width: 2.2;
  stroke-linecap: round;
  stroke-linejoin: round;
}
.cv-mini-ponte {
  stroke: var(--ml);
  stroke-width: 1.6;
  stroke-dasharray: 2 4;
  stroke-linecap: round;
  opacity: 0.7;
}
.cv-mini-ponto {
  fill: var(--ml);
}
.cv-mini-fim {
  fill: var(--ml);
  stroke: rgb(var(--slate-1));
  stroke-width: 1.5;
}
.cv-mini-marco {
  line {
    stroke: rgb(var(--slate-12));
    stroke-width: 1.3;
    stroke-dasharray: 3 3;
    opacity: 0.75;
  }
  circle {
    fill: rgb(var(--slate-12));
    stroke: rgb(var(--slate-1));
    stroke-width: 1.2;
  }
}
.cv-mini-balao-marco {
  color: rgb(var(--slate-12)) !important;
  font-weight: 600;
}
.cv-mini-guia {
  stroke: rgb(var(--slate-8));
  stroke-width: 1;
}
.cv-mini-balao {
  position: absolute;
  top: -0.25rem;
  transform: translate(-50%, -100%);
  z-index: 10;
  pointer-events: none;
  white-space: nowrap;
  padding: 0.3rem 0.6rem;
  border-radius: 0.6rem;
  font-size: 0.6875rem;
  line-height: 1.3;
  color: rgb(var(--slate-12));
  background: rgb(var(--slate-1) / 0.97);
  border: 1px solid rgb(var(--slate-6) / 0.7);
  box-shadow: 0 6px 18px rgb(0 0 0 / 0.14);
  b {
    display: block;
    font-variant-numeric: tabular-nums;
  }
  span {
    display: block;
    color: rgb(var(--slate-10));
  }
}
</style>
