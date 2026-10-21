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
    <div class="mt-grid grid gap-3" :class="compact ? 'mt-grid-compact' : ''">
      <div
        v-for="t in tiles"
        :key="t.key"
        class="mt-tile cv-sub rounded-2xl px-4 py-3.5 flex flex-col gap-1 min-w-0"
        :class="t.champion ? 'cv-sub-on' : ''"
        :title="t.hint"
      >
        <p
          class="text-xs font-semibold text-n-slate-10 flex items-start gap-1.5 leading-tight"
        >
          <span :class="t.icon" class="text-xs flex-shrink-0 mt-px" />
          <span class="min-w-0">{{ t.short }}</span>
          <span
            v-if="t.champion"
            class="i-lucide-trophy text-amber-500 text-xs ml-auto flex-shrink-0"
            title="Campeão do recorte"
          />
        </p>
        <p
          class="mt-value font-extrabold tabular-nums tracking-tight leading-none whitespace-nowrap"
          :class="t.empty ? 'text-n-slate-8' : 'text-n-slate-12'"
        >
          {{ t.text }}
        </p>
        <p
          v-if="t.vs"
          class="text-[11px] font-semibold leading-tight"
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
        <span
v-if="f.revenue" class="text-n-slate-9"
          >· {{ fmtMoney(f.revenue) }} de receita</span
        >
      </template>
      <span
v-else class="text-n-slate-9"
        >nenhum lead do CRM chegou por este anúncio no período</span
      >
    </p>
  </div>
</template>

<style scoped>
/* O texto aparece INTEIRO sempre (pedido 20/09): a grade decide quantos
   cartões cabem pela largura do CONTÊINER (não da janela) e o número encolhe
   junto com o cartão — nunca corta o rótulo, nunca quebra o "R$" da cifra. */
.mt-grid {
  grid-template-columns: repeat(auto-fit, minmax(9.25rem, 1fr));
}
.mt-grid-compact {
  grid-template-columns: repeat(auto-fit, minmax(8.5rem, 1fr));
}
.mt-tile {
  container-type: inline-size;
}
.mt-value {
  font-size: clamp(1.05rem, 13cqi, 1.6rem);
}
</style>
