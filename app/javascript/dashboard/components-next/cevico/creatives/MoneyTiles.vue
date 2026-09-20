<script setup>
// 💰 O QUE VALE DINHEIRO (Central de Criativos v2, item 177): custo por
// consulta agendada, custo por cirurgia realizada (CAC), ROAS e % de
// agendamento de um criativo, cada um contra a média da conta e com a
// jornada por baixo (leads → consultas → compareceram → cirurgias · receita).
// Alto contraste: número grande, rótulo curto, cor só no veredito.
import { computed } from 'vue';
import { MONEY_DEFS, vsAverage, fmtMoney } from './creativeFormat';

const props = defineProps({
  rates: { type: Object, default: () => ({}) },
  funnel: { type: Object, default: () => ({}) },
  averages: { type: Object, default: () => ({}) },
  champions: { type: Array, default: () => [] }, // champion_of do criativo
  compact: { type: Boolean, default: false },
  showFunnel: { type: Boolean, default: true },
});

const CHAMPION_BY_KEY = {
  cost_surgery: 'cac',
  roas: 'roas',
  booking_rate: 'booking',
};
const tiles = computed(() =>
  MONEY_DEFS.map(d => {
    const value = props.rates ? props.rates[d.key] : null;
    const vs = vsAverage(value, props.averages[d.key], d.lower);
    return {
      ...d,
      value,
      text: d.fmt(value),
      vs,
      champion: props.champions.includes(CHAMPION_BY_KEY[d.key]),
      empty: value === null || value === undefined,
    };
  })
);
const f = computed(() => props.funnel || {});
const hasFunnel = computed(() => Number(f.value.leads || 0) > 0);
</script>

<template>
  <div class="flex flex-col gap-3">
    <div
      class="grid grid-cols-2 gap-2.5"
      :class="compact ? '' : 'md:grid-cols-4'"
    >
      <div
        v-for="t in tiles"
        :key="t.key"
        class="cv-sub rounded-2xl px-4 py-3.5 flex flex-col gap-1 min-w-0"
        :class="t.champion ? 'cv-sub-on' : ''"
        :title="t.hint"
      >
        <p
          class="text-[11px] font-semibold text-n-slate-10 flex items-center gap-1.5 leading-tight"
        >
          <span :class="t.icon" class="text-xs flex-shrink-0" />
          <span class="truncate">{{ t.short }}</span>
          <span
            v-if="t.champion"
            class="i-lucide-trophy text-amber-500 text-xs ml-auto flex-shrink-0"
            title="Campeão do recorte"
          />
        </p>
        <p
          class="font-extrabold tabular-nums tracking-tight leading-none"
          :class="[
            compact ? 'text-xl' : 'text-2xl',
            t.empty ? 'text-n-slate-8' : 'text-n-slate-12',
          ]"
        >
          {{ t.text }}
        </p>
        <p
          v-if="t.vs"
          class="text-[10px] font-semibold leading-tight"
          :class="
            t.vs.good === null
              ? 'text-n-slate-9'
              : t.vs.good
                ? 'text-emerald-700 dark:text-emerald-400'
                : 'text-red-700 dark:text-red-400'
          "
        >
          {{ t.vs.good === null ? '' : t.vs.good ? '▲ ' : '▼ ' }}{{ t.vs.text }}
        </p>
        <p v-else-if="t.empty" class="text-[10px] text-n-slate-8 leading-tight">
          sem jornada ainda
        </p>
      </div>
    </div>
    <p
      v-if="showFunnel"
      class="flex items-center gap-x-2 gap-y-1 text-xs text-n-slate-11 flex-wrap"
      title="leads que chegaram por este anúncio (CTWA) → consulta marcada → compareceu → cirurgia realizada"
    >
      <span class="i-lucide-route text-sm text-n-slate-9" />
      <template v-if="hasFunnel">
        <span
          ><b class="text-n-slate-12">{{ f.leads }}</b> leads</span
        >
        <span class="i-lucide-chevron-right text-[10px] text-n-slate-8" />
        <span
          ><b class="text-n-slate-12">{{ f.booked }}</b> consultas</span
        >
        <span class="i-lucide-chevron-right text-[10px] text-n-slate-8" />
        <span
          ><b class="text-n-slate-12">{{ f.attended }}</b> compareceram</span
        >
        <span class="i-lucide-chevron-right text-[10px] text-n-slate-8" />
        <span
          ><b class="text-n-slate-12">{{ f.surgeries }}</b> cirurgias</span
        >
        <span v-if="f.revenue" class="text-n-slate-9"
          >· {{ fmtMoney(f.revenue) }} de receita</span
        >
      </template>
      <span v-else class="text-n-slate-9"
        >nenhum lead do CRM chegou por este anúncio no período</span
      >
    </p>
  </div>
</template>
