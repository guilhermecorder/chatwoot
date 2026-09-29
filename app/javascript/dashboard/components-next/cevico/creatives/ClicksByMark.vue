<script setup>
// 🖱️ "Cliques por quem chegou até aqui" (item 287). A Meta NÃO informa em que
// segundo cada clique aconteceu — isto é uma leitura aproximada: os cliques
// no link do período ÷ quem chegou a cada ponto do vídeo. A única conta certa
// é o "pelo menos N vieram antes": quando há mais cliques do que gente que
// chegou ao ponto, a diferença clicou antes dele.
import { computed } from 'vue';
import { fmtNum } from './creativeFormat';

const props = defineProps({
  clicks: { type: Object, required: true },
});

const rows = computed(() => {
  const marks = props.clicks.marks || [];
  const top = marks.length ? Number(marks[0].reached || 0) : 0;
  return marks.map(m => ({
    ...m,
    width: top ? `${Math.min((m.reached / top) * 100, 100).toFixed(1)}%` : '0%',
    per100:
      m.rate === null || m.rate === undefined
        ? null
        : (m.rate * 100).toFixed(1).replace('.', ','),
  }));
});
</script>

<template>
  <div class="w-full">
    <p class="text-xs text-n-slate-10 mb-3 leading-relaxed">
      Cliques no link no período:
      <span class="font-bold text-n-slate-12">{{
        fmtNum(clicks.link_clicks)
      }}</span
      >. Fonte: {{ clicks.source }}.
    </p>
    <p class="cbm-note px-4 py-3 mb-4 text-xs text-n-slate-12 leading-relaxed">
      {{ clicks.note }}
    </p>
    <ul class="flex flex-col gap-2 list-none p-0 m-0">
      <li
        v-for="r in rows"
        :key="r.key"
        class="cv-row relative overflow-hidden px-4 py-3 grid grid-cols-1 sm:grid-cols-[minmax(0,1.1fr)_minmax(0,1fr)_minmax(0,1.5fr)] gap-x-3 gap-y-0.5 items-center text-sm"
      >
        <span class="cbm-fill" :style="{ width: r.width }" />
        <span class="relative font-bold text-n-slate-12">{{ r.label }}</span>
        <span class="relative tabular-nums text-n-slate-11">
          {{ fmtNum(r.reached) }} chegaram
        </span>
        <span class="relative text-n-slate-11">
          <template v-if="r.per100 !== null">
            <span class="font-extrabold tabular-nums text-n-slate-12">{{
              r.per100
            }}</span>
            cliques para cada 100
          </template>
          <template v-else>sem dado</template>
          <span v-if="r.before_min > 0" class="block text-xs text-n-slate-10">
            pelo menos {{ fmtNum(r.before_min) }} cliques vieram antes deste
            ponto
          </span>
        </span>
      </li>
    </ul>
  </div>
</template>

<style scoped>
.cbm-note {
  border-radius: 14px;
  border: 1px solid rgb(217 119 6 / 0.3);
  border-left: 4px solid #d97706;
  background: rgb(217 119 6 / 0.1);
}
.cbm-fill {
  position: absolute;
  inset: 0 auto 0 0;
  background: linear-gradient(
    90deg,
    rgb(var(--cv-rgb) / 0.2),
    rgb(var(--cv-rgb) / 0.05)
  );
  pointer-events: none;
}
</style>
