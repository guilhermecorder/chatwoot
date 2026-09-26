<script setup>
// 📈 item 248 (26/09): gráfico de LINHA do card grande do Meu Painel, desenhado
// direto sobre a cor do card (como as sparklines dos cards pequenos, só que
// maior): linha branca + área suave, período anterior tracejado, ponto no pico
// e no último balde, rótulos das pontas e tooltip no toque/hover.
import { computed, ref, onMounted, onBeforeUnmount } from 'vue';

const props = defineProps({
  values: { type: Array, default: () => [] },
  prevValues: { type: Array, default: null },
  labels: { type: Array, default: () => [] },
  format: { type: Function, default: v => String(v) },
  height: { type: Number, default: 118 },
});

const wrap = ref(null);
const W = ref(320);
let observer = null;
onMounted(() => {
  if (wrap.value?.clientWidth) W.value = Math.max(140, Math.round(wrap.value.clientWidth));
  if (typeof ResizeObserver !== 'undefined' && wrap.value) {
    observer = new ResizeObserver(entries => {
      const w = entries[0]?.contentRect?.width;
      if (w) W.value = Math.max(140, Math.round(w));
    });
    observer.observe(wrap.value);
  }
});
onBeforeUnmount(() => observer?.disconnect());

const TOP = 16;
const BOTTOM = 16;
const PAD = 6;
const nums = computed(() => props.values.map(v => Number(v) || 0));
const prev = computed(() =>
  props.prevValues && props.prevValues.length === props.values.length
    ? props.prevValues.map(v => Number(v) || 0)
    : null
);
const max = computed(() => Math.max(1, ...nums.value, ...(prev.value || [])));
const plotH = computed(() => props.height - TOP - BOTTOM);
const xAt = i => {
  const n = nums.value.length;
  return n <= 1 ? W.value / 2 : PAD + (i / (n - 1)) * (W.value - PAD * 2);
};
const yAt = v => TOP + plotH.value - (v / max.value) * plotH.value;
const pts = computed(() => nums.value.map((v, i) => [xAt(i), yAt(v)]));
const line = computed(() => pts.value.map(p => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(' '));
const area = computed(() => {
  if (!pts.value.length) return '';
  const base = TOP + plotH.value;
  return `${pts.value[0][0].toFixed(1)},${base} ${line.value} ${pts.value[pts.value.length - 1][0].toFixed(1)},${base}`;
});
const prevLine = computed(() =>
  prev.value ? prev.value.map((v, i) => `${xAt(i).toFixed(1)},${yAt(v).toFixed(1)}`).join(' ') : ''
);
const peakIdx = computed(() => {
  const m = Math.max(...nums.value);
  return m > 0 ? nums.value.indexOf(m) : -1;
});
const lastIdx = computed(() => nums.value.length - 1);
// rótulos de baixo: primeiro, meio e último (não embola)
const ticks = computed(() => {
  const n = nums.value.length;
  if (!n) return [];
  const idx = n <= 3 ? [...Array(n).keys()] : [0, Math.floor((n - 1) / 2), n - 1];
  return [...new Set(idx)].map(i => ({ i, x: xAt(i), label: props.labels[i] || '' }));
});
const active = ref(null);
const onMove = ev => {
  const rect = wrap.value?.getBoundingClientRect();
  if (!rect || !nums.value.length) return;
  const x = ev.clientX - rect.left;
  let best = 0;
  pts.value.forEach((p, i) => { if (Math.abs(p[0] - x) < Math.abs(pts.value[best][0] - x)) best = i; });
  active.value = best;
};
const tip = computed(() => {
  if (active.value === null) return null;
  const i = active.value;
  return {
    left: Math.min(84, Math.max(16, (xAt(i) / W.value) * 100)),
    label: props.labels[i] || '',
    value: props.format(nums.value[i]),
    prev: prev.value ? props.format(prev.value[i]) : null,
  };
});
</script>

<template>
  <div ref="wrap" class="relative w-full select-none" @pointermove="onMove" @pointerleave="active = null">
    <svg :viewBox="`0 0 ${W} ${height}`" :width="W" :height="height" class="block max-w-full" :style="{ height: height + 'px' }">
      <defs>
        <linearGradient id="cvTileLineArea" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#fff" stop-opacity="0.34" />
          <stop offset="1" stop-color="#fff" stop-opacity="0" />
        </linearGradient>
      </defs>
      <line :x1="PAD" :x2="W - PAD" :y1="TOP + plotH" :y2="TOP + plotH" stroke="rgba(255,255,255,0.35)" stroke-width="1" />
      <line :x1="PAD" :x2="W - PAD" :y1="TOP + plotH / 2" :y2="TOP + plotH / 2" stroke="rgba(255,255,255,0.18)" stroke-dasharray="2 4" stroke-width="1" />
      <polyline v-if="prevLine" :points="prevLine" fill="none" stroke="rgba(255,255,255,0.55)" stroke-width="1.4" stroke-dasharray="4 4" />
      <polygon :points="area" fill="url(#cvTileLineArea)" />
      <polyline :points="line" fill="none" stroke="#fff" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round" />
      <template v-if="peakIdx >= 0">
        <circle :cx="pts[peakIdx][0]" :cy="pts[peakIdx][1]" r="4" fill="#fff" />
        <text :x="pts[peakIdx][0]" :y="pts[peakIdx][1] - 7" text-anchor="middle" font-size="10" font-weight="800" fill="#fff">{{ format(nums[peakIdx]) }}</text>
      </template>
      <circle v-if="lastIdx >= 0 && lastIdx !== peakIdx" :cx="pts[lastIdx][0]" :cy="pts[lastIdx][1]" r="3.2" fill="#fff" stroke="rgba(0,0,0,0.15)" />
      <template v-if="active !== null && pts[active]">
        <line :x1="pts[active][0]" :x2="pts[active][0]" :y1="TOP" :y2="TOP + plotH" stroke="rgba(255,255,255,0.55)" stroke-width="1" />
        <circle :cx="pts[active][0]" :cy="pts[active][1]" r="4.5" fill="#fff" stroke="rgba(0,0,0,0.2)" />
      </template>
      <text v-for="t in ticks" :key="'t' + t.i" :x="t.x" :y="height - 3" :text-anchor="t.i === 0 ? 'start' : t.i === nums.length - 1 ? 'end' : 'middle'" font-size="9.5" fill="rgba(255,255,255,0.8)">{{ t.label }}</text>
    </svg>
    <div v-if="tip" class="absolute top-0 -translate-x-1/2 z-10 rounded-lg bg-white/95 text-slate-900 shadow-lg px-2.5 py-1 text-[11px] leading-tight whitespace-nowrap pointer-events-none" :style="{ left: tip.left + '%' }">
      <b>{{ tip.label }} · {{ tip.value }}</b>
      <span v-if="tip.prev !== null" class="block text-slate-500">anterior: {{ tip.prev }}</span>
    </div>
  </div>
</template>
