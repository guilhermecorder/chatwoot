<script setup>
// 📏 Guia arejado — RÉGUA "contra a nossa média" (item 358c, 21/10/2026 —
// pedido dele: "as médias em evidência, para entender o que é bom e o que é
// ruim"). Uma linha por indicador: o número grande na cor do veredito, a barra
// preenchida até o valor e um TRAÇO escuro onde fica a nossa média, com o
// rótulo "média X" embaixo. Verde = melhor que a média, âmbar = perto dela,
// vermelho = pior. Para custos (`lower: true`) menor é melhor; para taxas,
// maior é melhor.
//   items = [{ key, label, value, avg, lower, fmt, hint }]
//   worse / better = os mesmos % dos parâmetros do agente (atenção / campeã)
import { computed } from 'vue';

const props = defineProps({
  items: { type: Array, default: () => [] },
  worse: { type: Number, default: 30 },
  better: { type: Number, default: 30 },
  emptyText: { type: String, default: 'sem média da casa ainda' },
});

const num = v => (v === null || v === undefined ? null : Number(v));
const bandOf = it => {
  const v = num(it.value);
  const a = num(it.avg);
  if (v === null || !a) return null;
  const ratio = v / a;
  const worse = 1 + props.worse / 100;
  const better = 1 - props.better / 100;
  if (it.lower) {
    if (ratio >= worse) return 'problema';
    if (ratio <= better) return 'bom';
    return 'atencao';
  }
  if (ratio <= better) return 'problema';
  if (ratio >= worse) return 'bom';
  return 'atencao';
};
const LABEL = {
  bom: 'melhor que a média',
  atencao: 'na média',
  problema: 'pior que a média',
};
const diffTextOf = diff => {
  if (diff === null) return '';
  if (Math.abs(diff) < 1) return 'igual à média';
  const n = Math.abs(diff).toLocaleString('pt-BR', {
    maximumFractionDigits: 0,
  });
  return `${diff > 0 ? '+' : '−'}${n}%`;
};
const rows = computed(() =>
  props.items.map(it => {
    const v = num(it.value);
    const a = num(it.avg);
    const top = Math.max(v || 0, a || 0) * 1.25 || 1;
    const band = bandOf(it);
    const diff = v !== null && a ? (v / a - 1) * 100 : null;
    return {
      ...it,
      band,
      verdict: band ? LABEL[band] : 'sem média',
      fillPct: v !== null ? Math.max(1.5, (v / top) * 100) : 0,
      avgPct: a ? (a / top) * 100 : null,
      diffText: diffTextOf(diff),
      valueText: v === null ? '—' : it.fmt(v),
      avgText: a ? it.fmt(a) : '—',
    };
  })
);
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <div class="cvr">
    <p v-if="!rows.length" class="cvg-vazio">{{ emptyText }}</p>
    <div
      v-for="r in rows"
      :key="r.key"
      class="cvr-row"
      :class="r.band ? `cvr-row--${r.band}` : ''"
      :title="r.hint || ''"
    >
      <div class="cvr-cab">
        <span class="cvr-label">{{ r.label }}</span>
        <span class="cvr-valor">{{ r.valueText }}</span>
        <span class="cvr-veredito">
          {{ r.verdict
          }}<template v-if="r.diffText"> · {{ r.diffText }}</template>
        </span>
      </div>
      <div class="cvr-track">
        <div class="cvr-fill" :style="{ width: `${r.fillPct}%` }" />
        <div
          v-if="r.avgPct !== null"
          class="cvr-avg"
          :style="{ left: `${r.avgPct}%` }"
        >
          <span class="cvr-avg-txt">média {{ r.avgText }}</span>
        </div>
      </div>
      <p v-if="r.hint" class="cvr-dica">{{ r.hint }}</p>
    </div>
  </div>
</template>

<style scoped>
.cvr {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(300px, 100%), 1fr));
  gap: 14px 24px;
}
.cvr-row {
  --cvr: var(--g-texto-3, #6b7280);
  --cvr-fundo: rgb(var(--cv-rgb, 37 99 235) / 0.1);
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 14px 16px 18px;
  border-radius: var(--g-raio-md, 14px);
  background: var(--g-superficie-2, #eef1f7);
  min-width: 0;
}
.cvr-row--bom {
  --cvr: var(--g-bom, #15803d);
  --cvr-fundo: var(--g-bom-fundo, #dcfce7);
}
.cvr-row--atencao {
  --cvr: var(--g-atencao, #b45309);
  --cvr-fundo: var(--g-atencao-fundo, #fef3c7);
}
.cvr-row--problema {
  --cvr: var(--g-problema, #b91c1c);
  --cvr-fundo: var(--g-problema-fundo, #fee2e2);
}
.cvr-cab {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: 4px 10px;
}
.cvr-label {
  font-size: 13px;
  line-height: 18px;
  font-weight: 500;
  color: var(--g-texto-2, #4b5563);
  flex: 1 1 140px;
  min-width: 0;
}
.cvr-valor {
  font-size: 26px;
  line-height: 30px;
  font-weight: 600;
  letter-spacing: -0.01em;
  color: var(--cvr);
  white-space: nowrap;
}
.cvr-veredito {
  width: 100%;
  font-size: 12px;
  line-height: 16px;
  font-weight: 600;
  color: var(--cvr);
}
.cvr-track {
  position: relative;
  height: 12px;
  border-radius: 9999px;
  background: var(--cvr-fundo);
  margin-top: 4px;
}
.cvr-fill {
  height: 100%;
  border-radius: 9999px;
  background: var(--cvr);
  opacity: 0.85;
  transition: width 500ms ease;
}
.cvr-avg {
  position: absolute;
  top: -5px;
  bottom: -5px;
  width: 3px;
  margin-left: -1.5px;
  border-radius: 2px;
  background: var(--g-texto, #111827);
}
.cvr-avg-txt {
  position: absolute;
  top: calc(100% + 3px);
  left: 50%;
  transform: translateX(-50%);
  white-space: nowrap;
  font-size: 11px;
  line-height: 14px;
  font-weight: 600;
  color: var(--g-texto, #111827);
}
.cvr-dica {
  margin: 22px 0 0; /* abaixo do rótulo "média X" que fica pendurado na barra */
  font-size: 12px;
  line-height: 16px;
  color: var(--g-texto-3, #6b7280);
}
</style>
