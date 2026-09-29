<script setup>
// 📈 Linha por dia de UM indicador (item 287, rodada 2): a linha cheia é o
// anúncio, a tracejada cinza é a média da conta e a pontilhada dourada é o
// recorde da conta. Ao passar o mouse: o dia e o valor.
import { computed, ref } from 'vue';
import { smoothPath } from 'dashboard/helper/cevicoBuckets';

const props = defineProps({
  values: { type: Array, default: () => [] }, // um número (ou null) por dia
  labels: { type: Array, default: () => [] },
  avg: { type: Number, default: null },
  record: { type: Number, default: null },
  color: { type: String, default: '#2563eb' },
  height: { type: Number, default: 150 },
  format: { type: Function, default: v => String(v) },
});

const W = 380;
const PAD = { l: 44, r: 12, t: 12, b: 22 };
const svgRef = ref(null);
const hover = ref(null);

const clean = computed(() =>
  props.values.map(v =>
    v === null || v === undefined || !Number.isFinite(Number(v))
      ? null
      : Number(v)
  )
);
const top = computed(() => {
  const all = clean.value.filter(v => v !== null);
  if (props.avg) all.push(props.avg);
  if (props.record) all.push(props.record);
  const max = Math.max(0, ...all);
  return max > 0 ? max * 1.12 : 1;
});
const xAt = i =>
  clean.value.length <= 1
    ? PAD.l + (W - PAD.l - PAD.r) / 2
    : PAD.l + ((W - PAD.l - PAD.r) * i) / (clean.value.length - 1);
const yAt = v => PAD.t + (props.height - PAD.t - PAD.b) * (1 - v / top.value);
const points = computed(() =>
  clean.value
    .map((v, i) => (v === null ? null : [xAt(i), yAt(v), i]))
    .filter(Boolean)
);
const path = computed(() => smoothPath(points.value));
const ticks = computed(() =>
  [0, 0.5, 1].map(f => ({ y: yAt(top.value * f), label: top.value * f }))
);
const xLabels = computed(() => {
  const n = props.labels.length;
  if (!n) return [];
  const picks = n <= 3 ? [...Array(n).keys()] : [0, Math.floor(n / 2), n - 1];
  return picks.map(i => ({ x: xAt(i), label: props.labels[i] }));
});
const onMove = evt => {
  const svg = svgRef.value;
  if (!svg || !points.value.length) return;
  const rect = svg.getBoundingClientRect();
  const x = ((evt.clientX - rect.left) / rect.width) * W;
  const best = points.value.reduce((a, p) =>
    Math.abs(p[0] - x) < Math.abs(a[0] - x) ? p : a
  );
  hover.value = {
    x: best[0],
    y: best[1],
    label: props.labels[best[2]],
    text: props.format(clean.value[best[2]]),
    style: {
      position: 'absolute',
      left: `${Math.min((best[0] / W) * 100, 62)}%`,
      top: '0',
    },
  };
};
</script>

<template>
  <div class="w-full">
    <div class="relative">
      <svg
        ref="svgRef"
        :viewBox="`0 0 ${W} ${height}`"
        class="w-full h-auto select-none"
        role="img"
        aria-label="Evolução por dia"
        @mousemove="onMove"
        @mouseleave="hover = null"
      >
        <g v-for="t in ticks" :key="t.y">
          <line
            :x1="PAD.l"
            :x2="W - PAD.r"
            :y1="t.y"
            :y2="t.y"
            class="stroke-n-slate-6"
            stroke-width="0.6"
          />
          <text
            :x="PAD.l - 6"
            :y="t.y + 3"
            text-anchor="end"
            class="fill-n-slate-9"
            font-size="11"
          >
            {{ format(t.label) }}
          </text>
        </g>
        <text
          v-for="l in xLabels"
          :key="l.x"
          :x="l.x"
          :y="height - 6"
          text-anchor="middle"
          class="fill-n-slate-9"
          font-size="11"
        >
          {{ l.label }}
        </text>
        <line
          v-if="record"
          :x1="PAD.l"
          :x2="W - PAD.r"
          :y1="yAt(record)"
          :y2="yAt(record)"
          stroke="#d4a017"
          stroke-width="1.4"
          stroke-dasharray="1.5 4"
          stroke-linecap="round"
        />
        <line
          v-if="avg"
          :x1="PAD.l"
          :x2="W - PAD.r"
          :y1="yAt(avg)"
          :y2="yAt(avg)"
          stroke="#94a3b8"
          stroke-width="1.4"
          stroke-dasharray="6 5"
        />
        <path
          :d="path"
          fill="none"
          :stroke="color"
          stroke-width="2.2"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
        <g v-if="hover">
          <line
            :x1="hover.x"
            :x2="hover.x"
            :y1="PAD.t"
            :y2="height - PAD.b"
            :stroke="color"
            stroke-width="0.8"
            opacity="0.5"
          />
          <circle
            :cx="hover.x"
            :cy="hover.y"
            r="4"
            :fill="color"
            class="stroke-n-surface-1"
            stroke-width="1.5"
          />
        </g>
      </svg>
      <div
        v-if="hover"
        class="cv-sub pointer-events-none px-2.5 py-1.5 text-[13px] text-n-slate-11 z-10 bg-n-surface-1 whitespace-nowrap"
        :style="hover.style"
      >
        {{ hover.label }} ·
        <span class="font-extrabold text-n-slate-12">{{ hover.text }}</span>
      </div>
    </div>
    <div class="flex flex-wrap gap-x-4 gap-y-0.5 text-[13px] text-n-slate-10">
      <span class="inline-flex items-center gap-1">
        <span class="w-3.5 h-[3px] rounded" :style="{ background: color }" />
        este anúncio, dia a dia
      </span>
      <span v-if="avg" class="inline-flex items-center gap-1">
        <span class="w-3.5 h-[3px] rounded bg-slate-400" />
        média da conta {{ format(avg) }}
      </span>
      <span v-if="record" class="inline-flex items-center gap-1">
        <span class="w-3.5 h-[3px] rounded bg-amber-500" />
        recorde da conta {{ format(record) }}
      </span>
    </div>
  </div>
</template>
