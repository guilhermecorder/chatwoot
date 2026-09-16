<script setup>
// 🥧 ShareBar (kit CEVICO, 14/09): a "pizza deitada" — uma barra 100% com
// as fatias lado a lado (até 6; o resto vira "Outros"), separadas por 2px
// de respiro, e a legenda com valor e %. Substitui a rosca do chart.js:
// lê melhor, cabe em qualquer largura e as cores seguem a paleta do bloco.
import { computed } from 'vue';

const props = defineProps({
  // [{ label, value, color }]
  items: { type: Array, default: () => [] },
  format: {
    type: Function,
    default: v => Number(v || 0).toLocaleString('pt-BR'),
  },
  max: { type: Number, default: 6 },
  otherLabel: { type: String, default: 'Outros' },
  // degraus da família do bloco (4 degradês) — cor por posição quando o
  // item não traz a sua
  family: { type: Array, default: () => [] },
  height: { type: Number, default: 14 },
});

const FALLBACK = [
  'var(--cv-grad)',
  'var(--cv-grad-2)',
  'var(--cv-grad-3)',
  'rgb(var(--cv-rgb) / 0.45)',
];
const total = computed(() =>
  props.items.reduce((s, it) => s + Number(it.value || 0), 0)
);
const slices = computed(() => {
  const sorted = [...props.items]
    .filter(it => Number(it.value || 0) > 0)
    .sort((a, b) => Number(b.value) - Number(a.value));
  const head = sorted.slice(0, props.max - 1);
  const tail = sorted.slice(props.max - 1);
  const list =
    tail.length > 1
      ? [
          ...head,
          {
            label: props.otherLabel,
            value: tail.reduce((s, it) => s + Number(it.value), 0),
            other: true,
          },
        ]
      : sorted;
  return list.map((it, i) => ({
    ...it,
    pct: total.value ? (Number(it.value) / total.value) * 100 : 0,
    color: it.other
      ? 'rgb(var(--cv-rgb) / 0.28)'
      : it.color ||
        props.family[i % Math.max(1, props.family.length)] ||
        FALLBACK[i % FALLBACK.length],
  }));
});
const pctLabel = p => `${p < 1 ? p.toFixed(1) : Math.round(p)}%`;
</script>

<template>
  <div class="cv-sharebar">
    <p v-if="!slices.length" class="text-xs text-n-slate-9 py-3">
      sem dados no período
    </p>
    <template v-else>
      <div
        class="flex w-full overflow-hidden rounded-full"
        :style="{ height: `${height}px`, gap: '2px' }"
      >
        <div
          v-for="(s, i) in slices"
          :key="i"
          class="h-full transition-[flex-basis] duration-500"
          :class="i === 0 ? 'rounded-l-full' : ''"
          :style="{
            flex: `0 0 ${s.pct}%`,
            background: s.color,
            minWidth: '3px',
          }"
          :title="`${s.label}: ${format(s.value)} · ${pctLabel(s.pct)}`"
        />
      </div>
      <div class="flex flex-wrap gap-x-4 gap-y-1.5 mt-2.5">
        <span
          v-for="(s, i) in slices"
          :key="'l' + i"
          class="inline-flex items-center gap-1.5 text-[11px] text-n-slate-11 min-w-0"
          :title="s.label"
        >
          <span
            class="w-2.5 h-2.5 rounded-sm flex-shrink-0"
            :style="{ background: s.color }"
          />
          <span class="truncate max-w-[12rem]">{{ s.label }}</span>
          <b class="text-n-slate-12 tabular-nums">{{ format(s.value) }}</b>
          <span class="text-n-slate-9 tabular-nums">{{ pctLabel(s.pct) }}</span>
        </span>
      </div>
    </template>
  </div>
</template>
