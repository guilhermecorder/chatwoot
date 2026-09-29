<script setup>
// 🖱️ "Cliques por quem chegou até aqui" (item 287). Rodada 4: cada linha é
// uma % DE CONVERSÃO escrita ("0,7% de quem viu o anúncio clicou") com barra.
// A Meta NÃO informa em que segundo cada clique aconteceu — é leitura
// aproximada: cliques no link do período ÷ quem chegou a cada ponto do vídeo.
// A única conta certa é o "pelo menos N vieram antes": quando há mais cliques
// do que gente que chegou ao ponto, a diferença clicou antes dele.
import { computed } from 'vue';
import { fmtNum } from './creativeFormat';

const props = defineProps({
  clicks: { type: Object, required: true },
});

const rows = computed(() => {
  const marks = props.clicks.marks || [];
  const top = Math.max(0.0001, ...marks.map(m => Math.min(m.rate || 0, 1)));
  return marks.map(m => ({
    ...m,
    width: `${Math.max(2, (Math.min(m.rate || 0, 1) / top) * 100).toFixed(1)}%`,
    tail: (m.conversion_text || '').replace(m.rate_text || '', '').trim(),
  }));
});
</script>

<template>
  <div class="w-full">
    <p class="text-sm text-n-slate-11 mb-4 leading-relaxed">
      Cliques no link no período:
      <span class="font-extrabold text-n-slate-12 text-base">{{
        fmtNum(clicks.link_clicks)
      }}</span
      >. Fonte: {{ clicks.source }}.
    </p>
    <p class="cbm-note px-5 py-4 mb-5 text-sm text-n-slate-12 leading-relaxed">
      {{ clicks.note }}
    </p>
    <ul class="flex flex-col gap-3 list-none p-0 m-0">
      <li v-for="r in rows" :key="r.key" class="cbm-row">
        <div class="flex items-baseline gap-3 flex-wrap">
          <span class="text-sm font-bold text-n-slate-12">{{ r.label }}</span>
          <span class="ml-auto text-[13px] text-n-slate-10 tabular-nums">
            {{ fmtNum(r.reached) }} chegaram até aqui
          </span>
        </div>
        <p class="text-sm text-n-slate-12 mt-1 leading-snug">
          <template v-if="r.rate_text">
            <span class="text-2xl font-extrabold tabular-nums">{{
              r.rate_text
            }}</span>
            {{ r.tail }}
          </template>
          <template v-else>sem dado</template>
        </p>
        <div class="h-3 rounded-full bg-n-alpha-2 overflow-hidden mt-2">
          <span class="cbm-fill" :style="{ width: r.width }" />
        </div>
        <p v-if="r.before_min > 0" class="text-[13px] text-n-slate-10 mt-1.5">
          pelo menos {{ fmtNum(r.before_min) }} cliques vieram antes deste ponto
        </p>
      </li>
    </ul>
  </div>
</template>

<style scoped>
.cbm-note {
  border-radius: 16px;
  border: 1px solid rgb(217 119 6 / 0.3);
  border-left: 4px solid #d97706;
  background: rgb(217 119 6 / 0.1);
}
.cbm-row {
  padding: 16px 20px;
  border-radius: 16px;
  border: 1px solid rgb(var(--cv-rgb) / 0.18);
  background: rgb(var(--cv-rgb) / 0.04);
}
.cbm-fill {
  display: block;
  height: 100%;
  border-radius: 9999px;
  background: linear-gradient(
    90deg,
    rgb(var(--cv-rgb) / 0.9),
    rgb(var(--cv-rgb) / 0.55)
  );
}
</style>
