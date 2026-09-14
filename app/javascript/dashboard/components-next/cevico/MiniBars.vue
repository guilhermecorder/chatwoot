<script setup>
// Gráfico de barras ENXUTO em SVG (kit CEVICO, itens 141/144) — sem lib:
// série do período nos popups dos cards de KPI e nos cards do "+".
// Item 144: série do período ANTERIOR sobreposta (linha tracejada balde a
// balde), linha de META (pontilhada ouro), marcadores 📌 das ações da
// empresa e TOOLTIP próprio (funciona no toque, não só no hover).
// v3 (varredura de design 12/09): o SVG mede a própria largura (texto sem
// esticar), barras com degradê e topo arredondado, eixo com linhas-guia e
// valores de referência, valor em cima de cada barra quando cabe, série
// anterior com pontinhos e rótulo na linha de meta. API compatível com a
// v2 — as props novas são opcionais.
import { computed, ref, onMounted, onBeforeUnmount } from 'vue';

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
  // eixo com linhas-guia e valores (automático: só em gráficos altos)
  axis: { type: Boolean, default: null },
  // valor escrito em cima de cada barra (automático: quando cabe)
  showValues: { type: Boolean, default: null },
});

// ── medidas: o SVG tem a largura REAL do contêiner (1 unidade = 1px), então
// texto e barras não esticam quando o popup é mais largo que o desenho ──
const uid = `mb${Math.random().toString(36).slice(2, 8)}`;
const wrap = ref(null);
const W = ref(320);
let observer = null;
onMounted(() => {
  if (wrap.value?.clientWidth) W.value = Math.max(120, Math.round(wrap.value.clientWidth));
  if (typeof ResizeObserver !== 'undefined' && wrap.value) {
    observer = new ResizeObserver(entries => {
      const w = entries[0]?.contentRect?.width;
      if (w) W.value = Math.max(120, Math.round(w));
    });
    observer.observe(wrap.value);
  }
});
onBeforeUnmount(() => observer?.disconnect());

const PAD = 4;
const chartTop = 12; // folga p/ valores e marcadores 📌
const bottom = 14; // rótulos de baixo
const hasAxis = computed(() => (props.axis === null ? props.height >= 70 : props.axis));
const L = computed(() => (hasAxis.value ? 30 : 0)); // calha do eixo
const plotH = computed(() => props.height - bottom - chartTop);
const baseY = computed(() => props.height - bottom);
const count = computed(() => Math.max(1, props.values.length));
const gap = computed(() => (count.value > 30 ? 1 : 2));
const plotW = computed(() => Math.max(10, W.value - L.value - PAD * 2));
const barW = computed(() => Math.max(2, plotW.value / count.value - gap.value));
const xFor = i => L.value + PAD + i * (barW.value + gap.value);
const centerX = i => xFor(i) + barW.value / 2;

const nums = computed(() => props.values.map(v => Number(v) || 0));
const prevSlice = computed(() =>
  props.prevValues ? props.prevValues.slice(0, Math.max(1, props.values.length)) : null
);
const dataMax = computed(() => Math.max(0, ...nums.value));
const rawMax = computed(() =>
  Math.max(
    1,
    dataMax.value,
    ...(prevSlice.value || []).map(v => Number(v) || 0),
    props.reference || 0,
    props.goal || 0
  )
);
// teto "redondo" do eixo: 7 → 8, 23 → 25, 130 → 150 — valores-guia legíveis
const NICE = [1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10];
const max = computed(() => {
  const m = rawMax.value;
  if (!hasAxis.value || m <= 5) return m;
  const pow = 10 ** Math.floor(Math.log10(m));
  const nice = NICE.find(k => k * pow >= m) || 10;
  return nice * pow;
});
const yFor = v => baseY.value - ((Number(v) || 0) / max.value) * plotH.value;
const bars = computed(() =>
  nums.value.map((val, i) => {
    const h = (val / max.value) * plotH.value;
    return {
      i,
      x: xFor(i),
      y: baseY.value - h,
      h: Math.max(val > 0 ? 2 : 0, h),
      val,
      label: props.labels[i] || '',
      isMax: val > 0 && val === dataMax.value,
    };
  })
);
// período anterior como LINHA tracejada com pontinhos (fantasma)
const prevPts = computed(() => (prevSlice.value || []).map((v, i) => ({ x: centerX(i), y: yFor(v) })));
const prevLine = computed(() =>
  prevPts.value.length ? prevPts.value.map(p => `${p.x},${p.y}`).join(' ') : null
);
const refY = computed(() =>
  props.reference === null || prevLine.value ? null : yFor(props.reference)
);
const goalY = computed(() => (props.goal === null ? null : yFor(props.goal)));
const markerAt = i => props.markers.find(m => m.index === i) || null;
// valores-guia do eixo: o teto e a metade
const gridTicks = computed(() => {
  if (!hasAxis.value) return [];
  const top = max.value;
  return [
    { v: top, y: yFor(top) },
    { v: top / 2, y: yFor(top / 2) },
  ];
});
// rótulos de baixo: todos quando cabem; senão um a cada N baldes (e o último)
const tickIdx = computed(() => {
  const n = props.values.length;
  if (n <= 1) return [0];
  const step = Math.max(1, Math.ceil(34 / (barW.value + gap.value)));
  const idx = [];
  for (let i = 0; i < n; i += step) idx.push(i);
  const last = n - 1;
  const gapToLast = last - idx[idx.length - 1];
  if (gapToLast > 0 && gapToLast >= Math.max(1, Math.floor(step / 2))) idx.push(last);
  return idx;
});
const showVals = computed(() =>
  props.showValues === null
    ? props.values.length <= 16 && props.height >= 70 && barW.value >= 14
    : props.showValues
);
// texto curto p/ eixo e topo das barras: 1234 → 1,2k · 16,3 → 16,3
const compact = v => {
  const num = Number(v) || 0;
  if (Math.abs(num) >= 1000) return `${(num / 1000).toFixed(num % 1000 === 0 ? 0 : 1).replace('.', ',')}k`;
  return Number.isInteger(num) ? String(num) : num.toFixed(1).replace('.', ',');
};
const barLabel = v => {
  const s = props.format(v);
  return s.length > 6 ? compact(v) : s;
};

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
    leftPct: Math.min(86, Math.max(14, (centerX(b.i) / W.value) * 100)),
  };
});
</script>

<template>
  <div ref="wrap" class="relative w-full" @pointerleave="active = null">
    <svg
      :viewBox="`0 0 ${W} ${height}`"
      :width="W"
      :height="height"
      class="block max-w-full"
      :style="{ height: height + 'px' }"
    >
      <defs>
        <linearGradient :id="uid" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" :stop-color="color" stop-opacity="1" />
          <stop offset="1" :stop-color="color" stop-opacity="0.45" />
        </linearGradient>
      </defs>
      <!-- linhas-guia + valores do eixo (teto e metade) -->
      <g v-for="(t, ti) in gridTicks" :key="'g' + ti">
        <line
          :x1="L" :x2="W - PAD" :y1="t.y" :y2="t.y"
          stroke="currentColor" stroke-dasharray="2 4" stroke-width="1" class="text-n-slate-9" opacity="0.35"
        />
        <text :x="L - 5" :y="t.y + 3" text-anchor="end" font-size="8.5" fill="currentColor" class="text-n-slate-9">
          {{ compact(t.v) }}
        </text>
      </g>
      <!-- linha de base -->
      <line
        :x1="L" :x2="W - PAD" :y1="baseY" :y2="baseY"
        stroke="currentColor" stroke-width="1" class="text-n-slate-9" opacity="0.45"
      />
      <!-- linha de META (pontilhada ouro) com rótulo -->
      <g v-if="goalY !== null">
        <line
          :x1="L" :x2="W - PAD" :y1="goalY" :y2="goalY"
          stroke="#D4A017" stroke-dasharray="2 3" stroke-width="1.4" opacity="0.9"
        />
        <text :x="W - PAD" :y="goalY - 2.5" text-anchor="end" font-size="8" font-weight="700" fill="#B8860B">
          meta {{ compact(goal) }}
        </text>
      </g>
      <!-- média do anterior (só quando não temos a série inteira) -->
      <line
        v-if="refY !== null"
        :x1="L" :x2="W - PAD" :y1="refY" :y2="refY"
        stroke="currentColor" stroke-dasharray="4 3" stroke-width="1" class="text-n-slate-9" opacity="0.7"
      />
      <g v-for="b in bars" :key="b.i">
        <rect
          :x="b.x" :y="b.y" :width="barW" :height="b.h" :rx="Math.min(3, barW / 2)"
          :fill="`url(#${uid})`" :opacity="active === b.i || b.isMax ? 1 : 0.82"
        />
        <!-- valor em cima da barra (quando cabe) -->
        <text
          v-if="showVals && b.val > 0"
          :x="centerX(b.i)" :y="b.y - 3"
          text-anchor="middle" font-size="8.5" font-weight="600" fill="currentColor" class="text-n-slate-11"
        >
          {{ barLabel(b.val) }}
        </text>
        <!-- 📌 ação da empresa no balde -->
        <g v-if="markerAt(b.i)">
          <line :x1="centerX(b.i)" :x2="centerX(b.i)" :y1="chartTop - 2" :y2="baseY" stroke="#D4A017" stroke-width="0.8" opacity="0.5" />
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
      <!-- série do período ANTERIOR (fantasma, balde a balde, com pontinhos) -->
      <g v-if="prevLine" style="pointer-events: none">
        <polyline
          :points="prevLine"
          fill="none" stroke="currentColor" stroke-width="1.4" stroke-dasharray="3 3"
          class="text-n-slate-9" opacity="0.85"
        />
        <circle
          v-for="(p, pi) in prevPts"
          :key="'p' + pi"
          :cx="p.x" :cy="p.y" r="1.7" fill="currentColor" class="text-n-slate-9" opacity="0.85"
        />
      </g>
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
      class="absolute top-0 -translate-x-1/2 -translate-y-1 z-10 rounded-lg border border-n-weak bg-n-solid-1 shadow-lg px-2.5 py-1.5 text-[11px] leading-tight whitespace-nowrap pointer-events-none"
      :style="{ left: tooltip.leftPct + '%' }"
    >
      <p class="font-semibold text-n-slate-12">{{ tooltip.label }} · {{ tooltip.value }}</p>
      <p v-if="tooltip.prev !== null" class="text-n-slate-10">anterior: {{ tooltip.prev }}<template v-if="tooltip.delta"> · {{ tooltip.delta }}</template></p>
      <p v-if="tooltip.marker" class="text-amber-600">📌 {{ tooltip.marker }}</p>
    </div>
  </div>
</template>
