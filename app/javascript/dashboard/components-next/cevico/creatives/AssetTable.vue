<script setup>
// Quebras e peças (ganchos, corpos, CTAs, posicionamentos, idade × sexo)
// SEM rolagem lateral (v2, item 177): cada linha é um cartão-linha —
// rótulo inteiro, barra da fatia e os números em pares "rótulo · valor"
// que embrulham no celular. Melhor e pior custo por conversa marcados.
import { computed } from 'vue';
import { fmtCompact, fmtPct, fmtNum, fmtMoney } from './creativeFormat';
import { useTranscribe } from './useTranscribe';

const props = defineProps({
  rows: { type: Array, default: () => [] },
  color: { type: String, default: 'var(--cv)' },
  emptyText: { type: String, default: 'sem dados no período' },
  labelHeader: { type: String, default: 'Peça' },
  video: { type: Boolean, default: false },
  max: { type: Number, default: 12 },
  // botão Transcrever por linha (só faz sentido em peças de texto)
  copyable: { type: Boolean, default: false },
  part: { type: String, default: 'title' },
});
const { transcribe } = useTranscribe();

const sorted = computed(() =>
  [...props.rows]
    .sort(
      (a, b) =>
        (b.conversations || 0) - (a.conversations || 0) ||
        (b.impressions || 0) - (a.impressions || 0)
    )
    .slice(0, props.max)
);
const maxShare = computed(() =>
  Math.max(...sorted.value.map(r => r.share || 0), 0.0001)
);
const bestKey = computed(() => {
  const withCost = sorted.value.filter(r => r.cost_conversation);
  if (withCost.length < 2) return null;
  return [...withCost].sort(
    (a, b) => a.cost_conversation - b.cost_conversation
  )[0].key;
});
const worstKey = computed(() => {
  const withCost = sorted.value.filter(
    r => r.cost_conversation && (r.impressions || 0) > 300
  );
  if (withCost.length < 2) return null;
  const w = [...withCost].sort(
    (a, b) => b.cost_conversation - a.cost_conversation
  )[0];
  return w.key === bestKey.value ? null : w.key;
});
const stats = r => {
  const list = [];
  if (props.video) list.push({ k: 'parada', v: fmtPct(r.hook_rate) });
  list.push({ k: 'CTR', v: fmtPct(r.link_ctr, 2) });
  list.push({ k: 'conversas', v: fmtNum(r.conversations), strong: true });
  list.push({
    k: 'por conversa',
    v: r.cost_conversation ? fmtMoney(r.cost_conversation) : '—',
  });
  return list;
};
</script>

<template>
  <div class="w-full min-w-0">
    <p v-if="!sorted.length" class="text-xs text-n-slate-9 py-4 text-center">
      {{ emptyText }}
    </p>
    <ul v-else class="divide-y divide-n-weak" :aria-label="labelHeader">
      <li
        v-for="r in sorted"
        :key="r.key"
        class="py-3 grid gap-x-5 gap-y-2 items-center md:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]"
      >
        <div class="min-w-0">
          <p class="text-sm text-n-slate-12 leading-snug whitespace-pre-line">
            {{ r.label }}
          </p>
          <p class="flex items-center gap-2 flex-wrap mt-1">
            <span
              v-if="r.key === bestKey"
              class="inline-flex items-center gap-0.5 text-[10px] font-semibold text-emerald-700 dark:text-emerald-400"
              ><span class="i-lucide-trophy" />melhor custo</span
            >
            <span
              v-if="r.key === worstKey"
              class="inline-flex items-center gap-0.5 text-[10px] font-semibold text-red-700 dark:text-red-400"
              ><span class="i-lucide-trending-down" />pior custo</span
            >
            <button
              v-if="copyable"
              class="inline-flex items-center gap-0.5 text-[10px] font-semibold text-n-slate-10 hover:text-n-slate-12"
              title="Copiar o texto desta peça"
              @click="transcribe(r, part)"
            >
              <span class="i-lucide-copy" />transcrever
            </button>
          </p>
        </div>
        <div class="min-w-0 flex flex-col gap-1.5">
          <div class="flex items-center gap-2">
            <div class="cv-track cv-track-sm flex-1">
              <div
                class="cv-fill"
                :style="{
                  width: `${Math.max(2, ((r.share || 0) / maxShare) * 100)}%`,
                  background: color,
                }"
              />
            </div>
            <span
              class="text-[11px] tabular-nums text-n-slate-10 whitespace-nowrap"
              >{{ fmtPct(r.share, 0) }} · {{ fmtCompact(r.impressions) }}</span
            >
          </div>
          <div class="flex flex-wrap gap-x-4 gap-y-0.5">
            <span
              v-for="s in stats(r)"
              :key="s.k"
              class="text-[11px] text-n-slate-10 whitespace-nowrap"
            >
              {{ s.k }}
              <b
                class="tabular-nums"
                :class="s.strong ? 'text-n-slate-12' : 'text-n-slate-11'"
                >{{ s.v }}</b
              >
            </span>
          </div>
        </div>
      </li>
    </ul>
  </div>
</template>
