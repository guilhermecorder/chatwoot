<script setup>
// 📊 TimelineChart (kit CEVICO, 19/10/2026): linha do tempo com BARRAS (uma
// série, eixo da esquerda) e LINHAS finas por cima (eixo da direita quando há
// barras; da esquerda quando são só linhas). Nasceu para os dois gráficos do
// Financeiro & CAC — "Custo por fonte ao longo do tempo" (só linhas, com
// buracos onde não houve quantidade) e "Faturamento × etapas do CRM" (barras
// de R$ + colunas do CRM escolhidas em chips).
//   labels = rótulo de cada balde (dia, semana ou mês)
//   bars   = { key, label, color, values } | null
//   lines  = [{ key, label, color, values: [n | null], dashed? }]
//   tip(i) = { title, rows: [{ color, label, value, sub? }] } — dica própria da
//            tela (filosofia: mostrar de onde veio o número); sem ela, a dica
//            lista as séries do ponto.
import { computed, ref, onMounted, onBeforeUnmount } from 'vue';
import { smoothPath } from 'dashboard/helper/cevicoBuckets';

const props = defineProps({
  labels: { type: Array, default: () => [] },
  bars: { type: Object, default: null },
  lines: { type: Array, default: () => [] },
  height: { type: Number, default: 230 },
  leftFormat: {
    type: Function,
    default: v => Number(v || 0).toLocaleString('pt-BR'),
  },
  rightFormat: {
    type: Function,
    default: v => Number(v || 0).toLocaleString('pt-BR'),
  },
  leftWidth: { type: Number, default: 44 },
  rightWidth: { type: Number, default: 34 },
  tip: { type: Function, default: null },
  // nome curto da unidade das linhas na legenda ("em média", "no período")
  legendNote: { type: String, default: '' },
  emptyText: { type: String, default: 'nada no período' },
  // marcas do que mudou: [{ index, title }] — traço vertical com número em cima
  marks: { type: Array, default: () => [] },
  // 358c: linhas de REFERÊNCIA horizontais (a nossa média), uma por eixo:
  // [{ axis: 'left' | 'right', value, label, color }]
  refs: { type: Array, default: () => [] },
});

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

const TOP = 14;
const BOTTOM = 26;
const hasBars = computed(
  () => !!props.bars && (props.bars.values || []).some(v => Number(v) > 0)
);
const hasRightAxis = computed(() => hasBars.value && props.lines.length > 0);
const LEFT = computed(() => props.leftWidth);
const RIGHT = computed(() => (hasRightAxis.value ? props.rightWidth : 16));
const n = computed(() => props.labels.length);
const plotW = computed(() => W.value - LEFT.value - RIGHT.value);
const plotH = computed(() => props.height - TOP - BOTTOM);
const base = computed(() => TOP + plotH.value);
const slotW = computed(() => plotW.value / Math.max(1, n.value));
const xAt = i => LEFT.value + slotW.value * (i + 0.5);

const num = v => (v === null || v === undefined ? null : Number(v));
const lineList = computed(() =>
  props.lines.map(s => {
    const values = (s.values || []).map(num);
    const present = values.filter(v => v !== null);
    return {
      ...s,
      values,
      total: present.reduce((a, b) => a + b, 0),
      avg: present.length
        ? present.reduce((a, b) => a + b, 0) / present.length
        : null,
      count: present.length,
    };
  })
);
const barValues = computed(() =>
  hasBars.value ? (props.bars.values || []).map(v => Number(v) || 0) : []
);

// teto "redondo" com 4 linhas de grade
const niceCeil = m => {
  if (m <= 0) return 1;
  if (m <= 4) return Math.ceil(m);
  const pow = 10 ** Math.floor(Math.log10(m));
  return (
    [1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]
      .map(f => f * pow)
      .find(v => v >= m) || m
  );
};
const refValues = axis =>
  props.refs
    .filter(r => r && (r.axis || 'left') === axis)
    .map(r => Number(r.value) || 0);
const leftMax = computed(() =>
  Math.max(
    hasBars.value
      ? Math.max(...barValues.value)
      : Math.max(
          0,
          ...lineList.value.flatMap(s => s.values.filter(v => v !== null))
        ),
    ...refValues(hasRightAxis.value ? 'left' : 'right'),
    ...refValues('left')
  )
);
const rightMax = computed(() =>
  Math.max(
    0,
    ...lineList.value.flatMap(s => s.values.filter(v => v !== null)),
    ...refValues('right')
  )
);
const leftCeil = computed(() => niceCeil(leftMax.value));
const rightCeil = computed(() => niceCeil(rightMax.value));
const yLeft = v => TOP + plotH.value * (1 - v / leftCeil.value);
const yRight = v => TOP + plotH.value * (1 - v / rightCeil.value);
const yLine = v => (hasRightAxis.value ? yRight(v) : yLeft(v));
const lineFormat = computed(() =>
  hasRightAxis.value ? props.rightFormat : props.leftFormat
);

const FRACS = [0, 0.25, 0.5, 0.75, 1];
const ticks = computed(() =>
  FRACS.map(f => ({
    f,
    y: TOP + plotH.value * (1 - f),
    left: leftCeil.value * f,
    right: rightCeil.value * f,
  }))
);
const tickText = (v, fmt) =>
  Number.isInteger(v) || v >= 10 ? fmt(Math.round(v * 100) / 100) : '';

// ── barras: topo arredondado (4px), 2px de folga entre vizinhas ──
const R = 4;
const barShapes = computed(() =>
  barValues.value.map((v, i) => {
    const w = Math.max(3, Math.min(slotW.value * 0.62, 48));
    const x = xAt(i) - w / 2;
    const y = yLeft(v);
    const h = base.value - y;
    const r = Math.min(R, h, w / 2);
    const d =
      h <= 0
        ? ''
        : `M${x},${base.value} V${y + r} Q${x},${y} ${x + r},${y} H${x + w - r} Q${x + w},${y} ${x + w},${y + r} V${base.value} Z`;
    return { i, x, y, w, h, d, v };
  })
);

// ── linhas: um traço por trecho contínuo (buraco = sem quantidade) ──
const shapes = computed(() =>
  lineList.value.map(s => {
    const segments = [];
    let current = [];
    s.values.forEach((v, i) => {
      if (v === null) {
        if (current.length) segments.push(current);
        current = [];
      } else {
        current.push([xAt(i), yLine(v)]);
      }
    });
    if (current.length) segments.push(current);
    return {
      ...s,
      paths: segments.filter(seg => seg.length > 1).map(smoothPath),
      dots: segments.filter(seg => seg.length === 1).map(seg => seg[0]),
    };
  })
);

// no máximo ~8 rótulos no eixo de baixo, nunca mais perto que 44 px (celular)
const xLabels = computed(() => {
  const every = Math.max(
    1,
    Math.ceil(n.value / 8),
    Math.ceil(44 / Math.max(1, slotW.value))
  );
  return props.labels
    .map((label, i) => ({ label, i, x: xAt(i) }))
    .filter(l => l.i % every === 0);
});

// linhas de referência: no eixo das barras (left) ou no das linhas (right)
const refList = computed(() =>
  props.refs
    .filter(r => r && Number(r.value) > 0)
    .map((r, k) => {
      const axis = r.axis || 'left';
      const y =
        axis === 'right' ? yLine(Number(r.value)) : yLeft(Number(r.value));
      const fmt = axis === 'right' ? lineFormat.value : props.leftFormat;
      return {
        ...r,
        k,
        y,
        text: `${r.label || 'média'} ${fmt(Number(r.value))}`,
        anchorRight: axis !== 'right',
      };
    })
);

const markList = computed(() =>
  props.marks
    .filter(m => m && m.index >= 0 && m.index < n.value)
    .map((m, k) => ({ ...m, k: k + 1, x: xAt(m.index) }))
);

// ── dica ──
const hover = ref(-1);
const onMove = event => {
  const rect = wrap.value?.getBoundingClientRect();
  if (!rect || !n.value) return;
  const x = (event.touches?.[0]?.clientX ?? event.clientX) - rect.left;
  hover.value = Math.min(
    n.value - 1,
    Math.max(0, Math.floor((x - LEFT.value) / Math.max(1, slotW.value)))
  );
};
const onLeave = () => {
  hover.value = -1;
};
const defaultTip = i => {
  const rows = [];
  if (hasBars.value)
    rows.push({
      color: props.bars.color,
      label: props.bars.label,
      value: props.leftFormat(barValues.value[i] || 0),
      square: true,
    });
  lineList.value.forEach(s => {
    if (s.values[i] !== null)
      rows.push({
        color: s.color,
        label: s.label,
        value: lineFormat.value(s.values[i]),
        dashed: s.dashed,
      });
  });
  return { title: props.labels[i], rows };
};
const tipBox = computed(() => {
  if (hover.value < 0 || hover.value >= n.value) return null;
  const i = hover.value;
  const content = (props.tip || defaultTip)(i);
  if (!content) return null;
  const x = xAt(i);
  return { i, x, left: x > W.value * 0.58, ...content };
});
const fmtLegend = s => {
  if (s.count === 0) return '—';
  return hasBars.value
    ? lineFormat.value(s.total)
    : `${lineFormat.value(s.avg)} ${props.legendNote}`.trim();
};
const barsTotal = computed(() => barValues.value.reduce((a, b) => a + b, 0));
const empty = computed(
  () => !hasBars.value && lineList.value.every(s => s.count === 0)
);
</script>

<template>
  <div class="w-full min-w-0">
    <div
      ref="wrap"
      class="relative w-full select-none touch-pan-y"
      :style="{ height: `${height}px` }"
      @mousemove="onMove"
      @mouseleave="onLeave"
      @touchstart.passive="onMove"
      @touchmove.passive="onMove"
      @touchend="onLeave"
    >
      <svg
        v-if="n && !empty"
        :width="W"
        :height="height"
        :viewBox="`0 0 ${W} ${height}`"
        class="block overflow-visible"
      >
        <!-- grade e eixos: fios finos, quase invisíveis -->
        <g class="text-n-slate-10">
          <line
            v-for="t in ticks"
            :key="`g${t.f}`"
            :x1="LEFT"
            :x2="W - RIGHT"
            :y1="t.y"
            :y2="t.y"
            stroke="currentColor"
            stroke-opacity="0.16"
          />
          <text
            v-for="t in ticks"
            :key="`l${t.f}`"
            :x="LEFT - 6"
            :y="t.y + 3"
            text-anchor="end"
            class="text-[10px] fill-current tabular-nums"
          >
            {{ tickText(t.left, leftFormat) }}
          </text>
          <template v-if="hasRightAxis">
            <text
              v-for="t in ticks"
              :key="`r${t.f}`"
              :x="W - RIGHT + 6"
              :y="t.y + 3"
              text-anchor="start"
              class="text-[10px] fill-current tabular-nums"
            >
              {{ tickText(t.right, rightFormat) }}
            </text>
          </template>
          <text
            v-for="l in xLabels"
            :key="`x${l.i}`"
            :x="l.x"
            :y="height - 7"
            text-anchor="middle"
            class="text-[10px] fill-current"
          >
            {{ l.label }}
          </text>
        </g>

        <!-- barras -->
        <g v-if="hasBars">
          <path
            v-for="b in barShapes"
            :key="`b${b.i}`"
            :d="b.d"
            :fill="props.bars.color"
            :fill-opacity="tipBox && tipBox.i === b.i ? 0.95 : 0.62"
            class="transition-[fill-opacity] duration-150"
          />
        </g>

        <!-- linhas -->
        <g v-for="s in shapes" :key="`s${s.key}`">
          <path
            v-for="(d, k) in s.paths"
            :key="`p${s.key}${k}`"
            :d="d"
            fill="none"
            :stroke="s.color"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            :stroke-dasharray="s.dashed ? '5 5' : null"
          />
          <circle
            v-for="(pt, k) in s.dots"
            :key="`o${s.key}${k}`"
            :cx="pt[0]"
            :cy="pt[1]"
            r="4"
            :fill="s.color"
          />
        </g>

        <!-- linhas de referência (a nossa média) -->
        <g v-for="r in refList" :key="`r${r.k}`">
          <line
            :x1="LEFT"
            :x2="W - RIGHT"
            :y1="r.y"
            :y2="r.y"
            :stroke="r.color || 'currentColor'"
            stroke-width="1.5"
            stroke-dasharray="6 4"
            stroke-opacity="0.9"
          />
          <text
            :x="r.anchorRight ? W - RIGHT - 4 : LEFT + 4"
            :y="r.y - 4"
            :text-anchor="r.anchorRight ? 'end' : 'start'"
            class="text-[10px] font-semibold"
            :fill="r.color || 'currentColor'"
          >
            {{ r.text }}
          </text>
        </g>

        <!-- marcas do que mudou -->
        <g v-for="m in markList" :key="`m${m.k}`" class="text-n-slate-11">
          <line
            :x1="m.x"
            :x2="m.x"
            :y1="TOP"
            :y2="base"
            stroke="currentColor"
            stroke-opacity="0.45"
            stroke-dasharray="3 3"
          />
          <circle :cx="m.x" :cy="TOP - 2" r="7" fill="currentColor" />
          <text
            :x="m.x"
            :y="TOP + 1"
            text-anchor="middle"
            class="text-[9px] font-bold fill-white"
          >
            {{ m.k }}
          </text>
        </g>

        <!-- cursor -->
        <g v-if="tipBox">
          <line
            :x1="tipBox.x"
            :x2="tipBox.x"
            :y1="TOP"
            :y2="base"
            stroke="currentColor"
            stroke-opacity="0.35"
            class="text-n-slate-11"
          />
          <template v-for="s in shapes" :key="`d${s.key}`">
            <circle
              v-if="s.values[tipBox.i] !== null"
              :cx="tipBox.x"
              :cy="yLine(s.values[tipBox.i])"
              r="4.5"
              :fill="s.color"
              stroke="#fff"
              stroke-width="2"
            />
          </template>
        </g>
      </svg>
      <p
        v-else
        class="flex items-center justify-center h-full text-xs text-n-slate-9"
      >
        {{ emptyText }}
      </p>

      <div
        v-if="tipBox"
        class="absolute top-1 z-10 min-w-[170px] max-w-[270px] px-3 py-2 rounded-xl text-[11px] pointer-events-none bg-white/95 text-n-slate-12 border border-n-slate-5 shadow-lg dark:bg-n-solid-1/95 dark:border-n-slate-6"
        :class="
          tipBox.left ? '-translate-x-[calc(100%+10px)]' : 'translate-x-[10px]'
        "
        :style="{ left: `${tipBox.x}px` }"
      >
        <p class="font-semibold mb-1">{{ tipBox.title }}</p>
        <div
          v-for="(r, k) in tipBox.rows"
          :key="k"
          class="flex items-start gap-1.5 leading-[1.45]"
        >
          <span
            class="mt-[5px] w-2 h-2 flex-shrink-0"
            :class="r.square ? 'rounded-[2px]' : 'rounded-full'"
            :style="{ background: r.color }"
          />
          <span class="min-w-0 flex-1">
            <span class="block">{{ r.label }}</span>
            <span v-if="r.sub" class="block text-[10px] text-n-slate-10">
              {{ r.sub }}
            </span>
          </span>
          <b class="tabular-nums whitespace-nowrap">{{ r.value }}</b>
        </div>
      </div>
    </div>

    <!-- legenda: sempre presente com 2+ séries -->
    <div
      v-if="hasBars || lineList.length"
      class="flex flex-wrap gap-x-4 gap-y-1.5 mt-3 text-[11px] text-n-slate-11"
    >
      <span v-if="hasBars" class="inline-flex items-center gap-1.5">
        <span
          class="w-2.5 h-2.5 rounded-[3px]"
          :style="{ background: props.bars.color }"
        />
        <span>{{ props.bars.label }}</span>
        <b class="tabular-nums">{{ leftFormat(barsTotal) }}</b>
      </span>
      <span
        v-for="s in lineList"
        :key="`k${s.key}`"
        class="inline-flex items-center gap-1.5"
        :title="s.hint || s.label"
      >
        <svg width="14" height="8" class="flex-shrink-0">
          <line
            x1="1"
            x2="13"
            y1="4"
            y2="4"
            :stroke="s.color"
            stroke-width="2"
            stroke-linecap="round"
            :stroke-dasharray="s.dashed ? '3 3' : null"
          />
        </svg>
        <span>{{ s.label }}</span>
        <b class="tabular-nums">{{ fmtLegend(s) }}</b>
      </span>
    </div>
  </div>
</template>
