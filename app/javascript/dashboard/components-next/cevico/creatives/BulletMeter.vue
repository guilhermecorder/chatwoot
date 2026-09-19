<script setup>
// Régua "bullet graph" (Stephen Few) de UMA taxa: faixas ruim / atenção / bom
// ao fundo, barra do valor, traço do parâmetro "bom" e marca da média da
// conta. Veredito sempre com ícone + palavra inteira. Item 172, rodada 2.
import { computed } from 'vue';
import {
  fmtPct,
  fmtMoney,
  BAND_META,
  VS_META,
  delta,
  fmtDelta,
  deltaCls,
} from './creativeFormat';

const props = defineProps({
  label: { type: String, required: true },
  metric: { type: String, default: '' },
  hint: { type: String, default: '' },
  value: { type: Number, default: null },
  avg: { type: Number, default: null },
  prev: { type: Number, default: null },
  band: { type: String, default: null },
  vsAvg: { type: String, default: null },
  target: { type: Object, default: null }, // { bad, good, lower_is_better }
  digits: { type: Number, default: 1 },
  money: { type: Boolean, default: false },
  color: { type: String, default: 'var(--cv)' },
  compact: { type: Boolean, default: false },
});

const lower = computed(() => !!(props.target && props.target.lower_is_better));
const fmt = v =>
  props.money
    ? v === null || v === undefined
      ? '—'
      : fmtMoney(v)
    : fmtPct(v, props.digits);
const good = computed(() => (props.target ? Number(props.target.good) : null));
const bad = computed(() => (props.target ? Number(props.target.bad) : null));
const scale = computed(() => {
  const candidates = [props.value || 0, props.avg || 0];
  if (good.value !== null)
    candidates.push(lower.value ? bad.value * 1.4 : good.value * 1.6);
  const top = Math.max(...candidates);
  return top > 0 ? top * 1.08 : 1;
});
const pctOf = v =>
  v === null || v === undefined
    ? 0
    : Math.min(100, Math.max(0, (v / scale.value) * 100));
// faixas de fundo: [ruim, atenção, bom] ou, quando menor é melhor, [bom, atenção, ruim]
const bands = computed(() => {
  if (good.value === null || bad.value === null) return [];
  const p1 = lower.value ? pctOf(good.value) : pctOf(bad.value);
  const p2 = lower.value ? pctOf(bad.value) : pctOf(good.value);
  const order = lower.value
    ? ['bom', 'atencao', 'ruim']
    : ['ruim', 'atencao', 'bom'];
  return [
    { key: order[0], w: p1 },
    { key: order[1], w: Math.max(0, p2 - p1) },
    { key: order[2], w: Math.max(0, 100 - p2) },
  ];
});
const valuePct = computed(() => pctOf(props.value));
const goodPct = computed(() =>
  good.value === null ? null : pctOf(good.value)
);
const avgPct = computed(() => (props.avg ? pctOf(props.avg) : null));
const bandMeta = computed(() => (props.band ? BAND_META[props.band] : null));
const d = computed(() => delta(props.value, props.prev));
const targetText = computed(() => {
  if (good.value === null) return '';
  return lower.value
    ? `bom ≤ ${fmt(good.value)} · ruim > ${fmt(bad.value)}`
    : `bom ≥ ${fmt(good.value)} · ruim < ${fmt(bad.value)}`;
});
// tudo que é detalhe (parâmetros, posição contra a média) vai para o
// tooltip; na tela fica só o que decide: valor, régua, situação, média, tendência
const tooltip = computed(() =>
  [props.hint, targetText.value, props.vsAvg ? VS_META[props.vsAvg] : '']
    .filter(Boolean)
    .join(' · ')
);
</script>

<template>
  <div class="min-w-0" :title="tooltip">
    <div class="flex items-baseline gap-2 min-w-0">
      <span class="text-xs font-semibold text-n-slate-12 min-w-0 truncate">
        {{ label }}
        <span
v-if="metric" class="text-n-slate-9 font-normal"
          >· {{ metric }}</span
        >
      </span>
      <span
        class="ml-auto font-bold text-n-slate-12 tabular-nums flex-shrink-0"
        :class="compact ? 'text-sm' : 'text-lg'"
      >
        {{ fmt(value) }}
      </span>
    </div>
    <div
      class="relative mt-1 rounded-full overflow-visible"
      :class="compact ? 'h-2' : 'h-2.5'"
    >
      <div
        class="absolute inset-0 rounded-full overflow-hidden flex bg-n-alpha-2"
      >
        <div
          v-for="b in bands"
          :key="b.key"
          class="h-full"
          :style="{ width: `${b.w}%`, background: BAND_META[b.key].fill }"
        />
      </div>
      <div
        v-if="value !== null"
        class="absolute left-0 top-1/2 -translate-y-1/2 rounded-full"
        :class="compact ? 'h-1' : 'h-1.5'"
        :style="{ width: `${valuePct}%`, background: color }"
      />
      <span
        v-if="goodPct !== null"
        class="absolute -top-0.5 -bottom-0.5 w-0.5 bg-n-slate-12/80"
        :style="{ left: `${goodPct}%` }"
        :title="`parâmetro bom: ${fmt(good)}`"
      />
      <span
        v-if="avgPct !== null"
        class="absolute -bottom-1.5 w-0 h-0 -translate-x-1/2 border-l-[4px] border-r-[4px] border-b-[5px] border-l-transparent border-r-transparent border-b-n-slate-11"
        :style="{ left: `${avgPct}%` }"
        :title="`média da conta: ${fmt(avg)}`"
      />
    </div>
    <div
      class="flex items-center gap-x-2.5 gap-y-0.5 mt-1.5 text-[11px] flex-wrap"
    >
      <span
        v-if="bandMeta"
        class="inline-flex items-center gap-1 font-semibold"
        :class="bandMeta.cls"
      >
        <span :class="bandMeta.icon" class="text-sm" />{{ bandMeta.label }}
      </span>
      <span v-else class="text-n-slate-9">sem parâmetro</span>
      <span v-if="avg" class="text-n-slate-10">média {{ fmt(avg) }}</span>
      <span
        v-if="d !== null"
        class="font-semibold ml-auto"
        :class="deltaCls(d, lower)"
        >{{ fmtDelta(d) }} vs anterior</span
      >
    </div>
  </div>
</template>
