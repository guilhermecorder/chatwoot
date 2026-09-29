<script setup>
// 🔻 FUNIL do anúncio com a % DE CONVERSÃO de cada etapa (item 287, rodada 4):
// Exibições → Cliques → Conversas → Leads → Consultas marcadas → Compareceram
// → Cirurgias fechadas → Cirurgias realizadas. Entre as etapas, quantos por
// cento da etapa anterior chegaram ali; menor, quantos por cento do total de
// leads; a seta compara com a média da conta. Na tela interna aparece também
// "de onde vem" cada número. Dados: `funnel_view` (Crm::CreativeFunnelView).
import { computed } from 'vue';
import { fmtNum } from './creativeFormat';

const props = defineProps({
  view: { type: Object, default: () => ({ steps: [] }) },
  sources: { type: Boolean, default: true },
});

const VERSUS = {
  above: {
    color: '#059669',
    icon: 'i-lucide-arrow-up',
    text: 'acima da média da conta',
  },
  below: {
    color: '#dc2626',
    icon: 'i-lucide-arrow-down',
    text: 'abaixo da média da conta',
  },
  even: {
    color: '#b45309',
    icon: 'i-lucide-minus',
    text: 'na média da conta',
  },
};
const steps = computed(() =>
  (props.view.steps || []).map(s => ({
    ...s,
    versusMeta: VERSUS[s.versus] || null,
    barWidth: `${Math.max(Number(s.width) || 0, 4)}%`,
  }))
);
</script>

<template>
  <div class="w-full">
    <ol class="flex flex-col list-none p-0 m-0">
      <li v-for="s in steps" :key="s.key" class="fs-step">
        <div v-if="s.conversion_text" class="fs-link">
          <span class="i-lucide-arrow-down text-base text-n-slate-9" />
          <p class="text-sm text-n-slate-12 leading-snug">
            <span class="text-lg font-extrabold tabular-nums">{{
              s.rate_text
            }}</span>
            {{ s.conversion_text.replace(s.rate_text, '').trim() }}
            <span
              v-if="s.versusMeta"
              class="fs-versus"
              :style="{ color: s.versusMeta.color }"
            >
              <span :class="s.versusMeta.icon" />
              {{ s.versusMeta.text }} ({{ s.average_text }})
            </span>
          </p>
          <p v-if="s.of_leads_text" class="text-[13px] text-n-slate-10">
            {{ s.of_leads_text }}
          </p>
        </div>
        <div class="fs-row">
          <div class="fs-bar" :style="{ width: s.barWidth }" />
          <div class="fs-text">
            <p class="text-2xl font-extrabold tabular-nums text-n-slate-12">
              {{ fmtNum(s.count) }}
            </p>
            <p class="text-sm font-bold text-n-slate-12 leading-tight">
              {{ s.label }}
            </p>
            <p class="text-[13px] text-n-slate-10 leading-snug">{{ s.hint }}</p>
            <p
              v-if="sources && s.source_text"
              class="text-[13px] text-n-slate-9 leading-snug"
            >
              {{ s.source_text }}
            </p>
          </div>
        </div>
      </li>
    </ol>
    <p v-if="view.note" class="text-[13px] text-n-slate-9 mt-4 leading-snug">
      {{ view.note }}
    </p>
  </div>
</template>

<style scoped>
.fs-link {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr);
  column-gap: 10px;
  align-items: center;
  padding: 10px 0 10px 18px;
}
.fs-link > p:last-child:not(:first-of-type) {
  grid-column: 2;
}
.fs-versus {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  margin-left: 6px;
  font-size: 13px;
  font-weight: 700;
}
.fs-row {
  position: relative;
  min-height: 92px;
  border-radius: 18px;
  border: 1px solid rgb(var(--cv-rgb) / 0.2);
  background: rgb(var(--cv-rgb) / 0.04);
  overflow: hidden;
}
.fs-bar {
  position: absolute;
  inset: 0 auto 0 0;
  border-radius: 18px;
  background: linear-gradient(
    90deg,
    rgb(var(--cv-rgb) / 0.42),
    rgb(var(--cv-rgb) / 0.16)
  );
}
.fs-text {
  position: relative;
  padding: 14px 20px;
}
</style>
