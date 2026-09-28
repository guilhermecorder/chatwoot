<script setup>
// 🪜 FUNIL EM DEGRAUS (item 267, 28/09 — pedido: "% de agendamento com as 3
// colunas: novos contatos, envio de orçamento e agendamento de consulta;
// gráfico melhor de ver, mais visual, mais legal"). Cada etapa é uma coluna
// com o número grande; a altura é proporcional à 1ª etapa; entre as colunas,
// a % que passou de uma para a outra; embaixo, a % acumulada desde o início.
import { computed } from 'vue';

const props = defineProps({
  // [{ label, value, color?, hint? }]
  steps: { type: Array, default: () => [] },
  height: { type: Number, default: 150 },
});
const nums = computed(() => props.steps.map(s => Number(s.value) || 0));
const max = computed(() => Math.max(1, ...nums.value));
const pct = (a, b) => (b > 0 ? Math.round((a / b) * 1000) / 10 : null);
const fmtPct = v => (v === null ? '—' : `${String(v).replace('.', ',')}%`);
const cols = computed(() =>
  props.steps.map((s, i) => ({
    ...s,
    n: nums.value[i],
    h: Math.max(6, Math.round((nums.value[i] / max.value) * 100)),
    fromPrev: i > 0 ? pct(nums.value[i], nums.value[i - 1]) : null,
    fromStart: i > 0 ? pct(nums.value[i], nums.value[0]) : null,
    color: s.color || ['#2563eb', '#7c3aed', '#059669', '#d97706'][i % 4],
  }))
);
const fmtN = n => n.toLocaleString('pt-BR');
</script>

<template>
  <div class="cv-funnel" :style="{ '--fh': height + 'px' }">
    <template v-for="(c, i) in cols" :key="c.label">
      <!-- seta com a % que passou da etapa anterior -->
      <div v-if="i > 0" class="cv-funnel-arrow">
        <span class="cv-funnel-arrow-pct">{{ fmtPct(c.fromPrev) }}</span>
        <span class="i-lucide-arrow-right text-sm" />
        <span class="cv-funnel-arrow-sub">da etapa anterior</span>
      </div>
      <div class="cv-funnel-col" :style="{ '--c': c.color }">
        <p class="cv-funnel-n">{{ fmtN(c.n) }}</p>
        <div class="cv-funnel-track">
          <div class="cv-funnel-bar" :style="{ height: c.h + '%' }" />
        </div>
        <p class="cv-funnel-label">{{ c.label }}</p>
        <p v-if="c.fromStart !== null" class="cv-funnel-start">
          {{ fmtPct(c.fromStart) }} dos {{ cols[0].label.toLowerCase() }}
        </p>
        <p v-else-if="c.hint" class="cv-funnel-start">{{ c.hint }}</p>
      </div>
    </template>
  </div>
</template>

<style lang="scss">
.cv-funnel {
  display: flex;
  align-items: stretch;
  gap: 6px;
  width: 100%;
}
.cv-funnel-col {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
}
.cv-funnel-n {
  font-size: 22px;
  font-weight: 800;
  letter-spacing: -0.02em;
  line-height: 1;
  color: var(--c);
  margin-bottom: 6px;
  font-variant-numeric: tabular-nums;
}
.cv-funnel-track {
  width: 100%;
  height: var(--fh);
  display: flex;
  align-items: flex-end;
  border-radius: 14px;
  background: color-mix(in srgb, var(--c) 8%, transparent);
  overflow: hidden;
}
.cv-funnel-bar {
  width: 100%;
  border-radius: 14px 14px 10px 10px;
  background: linear-gradient(
    180deg,
    var(--c),
    color-mix(in srgb, var(--c) 55%, #fff)
  );
  box-shadow: inset 0 1px 0 rgb(255 255 255 / 0.45);
  transition: height 0.6s cubic-bezier(0.2, 0.8, 0.2, 1);
}
.dark .cv-funnel-bar {
  background: linear-gradient(
    180deg,
    var(--c),
    color-mix(in srgb, var(--c) 45%, #000)
  );
}
.cv-funnel-label {
  margin-top: 8px;
  font-size: 11.5px;
  font-weight: 700;
  line-height: 1.2;
  color: var(--c);
}
.cv-funnel-start {
  margin-top: 2px;
  font-size: 10px;
  color: #64748b;
}
.cv-funnel-arrow {
  align-self: center;
  display: flex;
  flex-direction: column;
  align-items: center;
  width: 58px;
  flex-shrink: 0;
  color: #64748b;
}
.cv-funnel-arrow-pct {
  font-size: 13px;
  font-weight: 800;
  color: #0f172a;
  font-variant-numeric: tabular-nums;
}
.dark .cv-funnel-arrow-pct {
  color: #fff;
}
.cv-funnel-arrow-sub {
  font-size: 8.5px;
  line-height: 1.1;
  text-align: center;
}
</style>
