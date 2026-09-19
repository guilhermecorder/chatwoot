<script setup>
// Tabela de peças (ganchos, corpos, CTAs, posicionamentos, idade × sexo):
// texto inteiro, fatia das impressões em barra, CTR, conversas e custo por
// conversa, com o melhor e o pior marcados por ícone + palavra. Item 172 r2.
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
</script>

<template>
  <div class="overflow-x-auto -mx-1 px-1">
    <p v-if="!sorted.length" class="text-xs text-n-slate-9 py-4 text-center">
      {{ emptyText }}
    </p>
    <table v-else class="w-full text-xs">
      <thead>
        <tr class="text-[10px] uppercase tracking-wide text-n-slate-9">
          <th class="text-left font-semibold py-1.5 pr-3">{{ labelHeader }}</th>
          <th class="text-left font-semibold py-1.5 pr-3 w-[26%] min-w-[9rem]">
            Fatia das impressões
          </th>
          <th
            v-if="video"
            class="text-right font-semibold py-1.5 pr-3 whitespace-nowrap hidden xl:table-cell"
          >
            Parada
          </th>
          <th class="text-right font-semibold py-1.5 pr-3">CTR</th>
          <th class="text-right font-semibold py-1.5 pr-3">Conversas</th>
          <th class="text-right font-semibold py-1.5 whitespace-nowrap">
            Custo por conversa
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="r in sorted"
          :key="r.key"
          class="border-t border-n-weak align-top"
        >
          <td class="py-2 pr-3 text-n-slate-12 max-w-[22rem]">
            <span class="whitespace-pre-line">{{ r.label }}</span>
            <span
              v-if="r.key === bestKey"
              class="ml-1 inline-flex items-center gap-0.5 text-[10px] font-semibold text-emerald-700 dark:text-emerald-400 whitespace-nowrap"
              ><span class="i-lucide-trophy" />melhor custo</span
            >
            <span
              v-if="r.key === worstKey"
              class="ml-1 inline-flex items-center gap-0.5 text-[10px] font-semibold text-red-700 dark:text-red-400 whitespace-nowrap"
              ><span class="i-lucide-trending-down" />pior custo</span
            >
            <button
              v-if="copyable"
              class="ml-1 inline-flex items-center gap-0.5 text-[10px] font-semibold text-n-slate-10 hover:text-n-slate-12 whitespace-nowrap align-middle"
              title="Copiar o texto desta peça"
              @click="transcribe(r, part)"
            >
              <span class="i-lucide-copy" />transcrever
            </button>
          </td>
          <td class="py-2 pr-3">
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
              <span class="tabular-nums text-n-slate-11 whitespace-nowrap"
                >{{ fmtPct(r.share, 0) }} ·
                {{ fmtCompact(r.impressions) }}</span
              >
            </div>
          </td>
          <td
            v-if="video"
            class="py-2 pr-3 text-right tabular-nums text-n-slate-11 hidden xl:table-cell"
          >
            {{ fmtPct(r.hook_rate) }}
          </td>
          <td class="py-2 pr-3 text-right tabular-nums text-n-slate-11">
            {{ fmtPct(r.link_ctr, 2) }}
          </td>
          <td
            class="py-2 pr-3 text-right tabular-nums font-semibold text-n-slate-12"
          >
            {{ fmtNum(r.conversations) }}
          </td>
          <td class="py-2 text-right tabular-nums text-n-slate-11">
            {{ r.cost_conversation ? fmtMoney(r.cost_conversation) : '—' }}
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
