<script setup>
// 🎯 Indicador SEM LEGENDA (item 287). Rodada 3: a régua é a MÉDIA DA CONTA e
// o alvo é o RECORDE DA CONTA. Três barras com o nome escrito — "Este
// anúncio", "Média da conta" e "Recorde da conta" (com o anúncio recordista e
// quando foi) —, veredito "acima / na média / abaixo da média" e quanto falta
// para o recorde. No modo Linha: tracejada = média, pontilhada = recorde.
// Dados: `scorecard.indicators` do detalhe (Crm::CreativeScorecard).
import { computed } from 'vue';
import RateLine from './RateLine.vue';

const props = defineProps({
  indicator: { type: Object, required: true },
  view: { type: String, default: 'bars' }, // bars | line
  values: { type: Array, default: () => [] }, // por dia (modo linha)
  labels: { type: Array, default: () => [] },
});

const TONES = {
  good: { color: '#059669', icon: 'i-lucide-trending-up' },
  even: { color: '#b45309', icon: 'i-lucide-minus' },
  bad: { color: '#dc2626', icon: 'i-lucide-trending-down' },
};
const RECORD_COLOR = '#d4a017';
const tone = computed(
  () => TONES[props.indicator.verdict] || { color: '#64748b', icon: '' }
);
const fmt = v => {
  if (v === null || v === undefined) return '—';
  if (props.indicator.money)
    return `R$ ${Number(v).toFixed(2).replace('.', ',')}`;
  return `${(Number(v) * 100).toFixed(props.indicator.digits || 1).replace('.', ',')}%`;
};
const has = v => v !== null && v !== undefined;
const rows = computed(() => {
  const i = props.indicator;
  const top =
    Math.max(Number(i.value) || 0, Number(i.avg) || 0, Number(i.record) || 0) *
      1.08 || 1;
  const width = v => `${Math.max(2, Math.min(100, (Number(v) / top) * 100))}%`;
  const list = [
    {
      key: 'value',
      name: 'Este anúncio',
      text: i.value_text,
      width: width(i.value),
      color: tone.value.color,
      strong: true,
    },
  ];
  if (has(i.avg))
    list.push({
      key: 'avg',
      name: 'Média da conta',
      text: i.avg_text,
      width: width(i.avg),
      color: '#94a3b8',
    });
  if (has(i.record))
    list.push({
      key: 'record',
      name: 'Recorde da conta',
      text: i.record_text,
      width: width(i.record),
      color: RECORD_COLOR,
      record: true,
    });
  return list;
});
const holder = computed(() => {
  const i = props.indicator;
  if (!has(i.record) || i.is_record) return '';
  return [i.record_ad, i.record_when].filter(Boolean).join(' · ');
});
</script>

<template>
  <div
    class="cv-sub rounded-2xl px-5 py-5 min-w-0"
    :class="indicator.is_record ? 'vb-champion' : ''"
    :title="indicator.hint"
  >
    <div class="flex items-center gap-2 flex-wrap mb-3">
      <p class="text-base font-bold text-n-slate-12 leading-tight">
        {{ indicator.label }}
        <span class="font-normal text-n-slate-10">
          · {{ indicator.metric }}
        </span>
      </p>
      <span
        v-if="indicator.verdict_label"
        class="ml-auto inline-flex items-center gap-1 text-sm font-bold"
        :style="{ color: tone.color }"
      >
        <span :class="tone.icon" class="text-sm" />{{ indicator.verdict_label }}
      </span>
    </div>

    <ul v-if="view === 'bars'" class="flex flex-col gap-2.5 list-none p-0 m-0">
      <li
        v-for="r in rows"
        :key="r.key"
        class="grid grid-cols-[9.5rem_minmax(0,1fr)_5rem] items-center gap-2"
      >
        <span
          class="text-[13px] leading-tight inline-flex items-center gap-1"
          :class="r.strong ? 'font-bold text-n-slate-12' : 'text-n-slate-10'"
        >
          <span v-if="r.record" class="i-lucide-trophy text-amber-500" />{{
            r.name
          }}
        </span>
        <span class="h-4 rounded-full bg-n-alpha-2 overflow-hidden">
          <span
            class="vb-bar block h-full rounded-full"
            :style="{ width: r.width, background: r.color }"
          />
        </span>
        <span
          class="text-right tabular-nums"
          :class="
            r.strong
              ? 'text-xl font-extrabold text-n-slate-12'
              : 'text-sm font-semibold text-n-slate-11'
          "
        >
          {{ r.text }}
        </span>
      </li>
    </ul>
    <RateLine
      v-else
      :values="values"
      :labels="labels"
      :avg="indicator.avg"
      :record="indicator.record"
      :color="tone.color"
      :format="fmt"
    />

    <p class="text-sm mt-2 font-semibold" :style="{ color: tone.color }">
      {{ indicator.phrase }}
    </p>
    <p class="text-sm font-semibold vb-record">
      {{ indicator.record_phrase }}
    </p>
    <p v-if="holder" class="text-[13px] text-n-slate-10 leading-snug">
      recorde: {{ holder }}
    </p>
    <p class="text-[13px] text-n-slate-9 leading-snug mt-1">
      {{ indicator.hint }}
    </p>
  </div>
</template>

<style scoped>
.vb-bar {
  transition: width 0.5s cubic-bezier(0.22, 1, 0.36, 1);
}
.vb-record {
  color: #a16207;
}
.vb-champion {
  border-color: rgb(212 160 23 / 0.7);
  box-shadow: 0 0 0 3px rgb(212 160 23 / 0.16);
}
</style>
