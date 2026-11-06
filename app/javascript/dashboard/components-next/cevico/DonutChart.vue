<script setup>
// 🍩 DonutChart (kit CEVICO, 19/10/2026 — pedido dele: "um gráfico circular,
// que mostra melhor as %"). Parte-para-o-todo em até 6 fatias, com o total no
// meio, 2 px de folga entre as fatias e a legenda com a porcentagem de cada
// uma. Passar o mouse destaca a fatia e mostra o valor no centro.
//   slices = [{ key, label, value, color }]
import { computed, ref } from 'vue';

const props = defineProps({
  slices: { type: Array, default: () => [] },
  size: { type: Number, default: 160 },
  thickness: { type: Number, default: 22 },
  format: {
    type: Function,
    default: v => Number(v || 0).toLocaleString('pt-BR'),
  },
  // palavra do todo, no centro ("leads", "R$")
  unit: { type: String, default: '' },
  legend: { type: Boolean, default: true },
  emptyText: { type: String, default: 'nada no período' },
});

const MAX = 6;
const list = computed(() => {
  const all = props.slices
    .map(s => ({ ...s, value: Number(s.value) || 0 }))
    .filter(s => s.value > 0)
    .sort((a, b) => b.value - a.value);
  if (all.length <= MAX) return all;
  const head = all.slice(0, MAX - 1);
  const rest = all.slice(MAX - 1);
  return [
    ...head,
    {
      key: 'outros',
      label: `Outros (${rest.length})`,
      color: '#94a3b8',
      value: rest.reduce((a, s) => a + s.value, 0),
    },
  ];
});
const total = computed(() => list.value.reduce((a, s) => a + s.value, 0));
const pct = v => (total.value ? v / total.value : 0);
const pctTxt = v =>
  `${(pct(v) * 100).toLocaleString('pt-BR', { maximumFractionDigits: pct(v) < 0.1 ? 1 : 0 })}%`;

const r = computed(() => props.size / 2 - props.thickness / 2);
const c = computed(() => 2 * Math.PI * r.value);
const GAP = 2;
const arcs = computed(() => {
  let offset = 0;
  const single = list.value.length === 1;
  return list.value.map(s => {
    const len = c.value * pct(s.value);
    const dash = single ? len : Math.max(0, len - GAP);
    const arc = { ...s, dash, gap: c.value - dash, offset: -offset };
    offset += len;
    return arc;
  });
});
const hover = ref(null);
const center = computed(() => {
  const s = hover.value && list.value.find(x => x.key === hover.value);
  if (s) return { big: pctTxt(s.value), small: s.label };
  return { big: props.format(total.value), small: props.unit };
});
</script>

<template>
  <div class="flex flex-wrap items-center gap-4 min-w-0">
    <div
      class="relative flex-shrink-0"
      :style="{ width: `${size}px`, height: `${size}px` }"
    >
      <svg
        v-if="total > 0"
        :width="size"
        :height="size"
        :viewBox="`0 0 ${size} ${size}`"
        class="block -rotate-90"
      >
        <circle
          :cx="size / 2"
          :cy="size / 2"
          :r="r"
          fill="none"
          stroke="currentColor"
          class="text-n-slate-3 dark:text-n-slate-6"
          :stroke-width="thickness"
        />
        <circle
          v-for="a in arcs"
          :key="a.key"
          :cx="size / 2"
          :cy="size / 2"
          :r="r"
          fill="none"
          :stroke="a.color"
          :stroke-width="hover === a.key ? thickness + 4 : thickness"
          :stroke-dasharray="`${a.dash} ${a.gap}`"
          :stroke-dashoffset="a.offset"
          :stroke-opacity="hover && hover !== a.key ? 0.35 : 1"
          class="transition-all duration-150 cursor-default"
          @mouseenter="hover = a.key"
          @mouseleave="hover = null"
        >
          <title>
            {{ a.label }}: {{ format(a.value) }} ({{ pctTxt(a.value) }})
          </title>
        </circle>
      </svg>
      <div
        v-else
        class="w-full h-full rounded-full border border-dashed border-n-slate-5 flex items-center justify-center text-[11px] text-n-slate-9 text-center px-3"
      >
        {{ emptyText }}
      </div>
      <div
        v-if="total > 0"
        class="absolute inset-0 flex flex-col items-center justify-center pointer-events-none text-center px-6"
      >
        <span
          class="font-semibold tracking-tight tabular-nums text-n-slate-12 leading-tight"
          :class="String(center.big).length > 8 ? 'text-sm' : 'text-xl'"
        >
          {{ center.big }}
        </span>
        <span class="text-[10.5px] text-n-slate-10 leading-snug line-clamp-2">
          {{ center.small }}
        </span>
      </div>
    </div>
    <ul
      v-if="legend && list.length"
      class="list-none ps-0 m-0 min-w-[150px] flex-1 space-y-1"
    >
      <li
        v-for="s in list"
        :key="s.key"
        class="flex items-center gap-2 text-[12px] cursor-default"
        :class="hover && hover !== s.key ? 'opacity-50' : ''"
        @mouseenter="hover = s.key"
        @mouseleave="hover = null"
      >
        <span
          class="w-2.5 h-2.5 rounded-full flex-shrink-0"
          :style="{ background: s.color }"
        />
        <span class="min-w-0 break-words leading-snug text-n-slate-12">{{
          s.label
        }}</span>
        <span class="ms-auto whitespace-nowrap tabular-nums text-n-slate-10">{{
          format(s.value)
        }}</span>
        <b class="w-11 text-end tabular-nums text-n-slate-12">{{
          pctTxt(s.value)
        }}</b>
      </li>
    </ul>
  </div>
</template>
