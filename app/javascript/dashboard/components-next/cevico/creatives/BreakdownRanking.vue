<script setup>
// 🥇 Os MAIS e os MENOS de uma quebra (item 287, rodada 3): onde apareceu e
// quem viu, do melhor para o pior, com selo escrito — "mais conversas",
// "menos conversas", "melhor aproveitamento", "pior aproveitamento" — e as
// duas taxas de cada linha (cliques a cada 100 exibições, conversas a cada
// 100 cliques). Quando os números empatam, não escolhe vencedor.
// Dados: `placement_ranking` / `audience_ranking` (Crm::BreakdownHighlights).
import { computed } from 'vue';
import { fmtNum, fmtMoney } from './creativeFormat';

const props = defineProps({
  ranking: { type: Object, default: () => ({ rows: [] }) },
  finance: { type: Boolean, default: true },
  emptyText: { type: String, default: 'sem dados no período' },
});

const TONE = { good: '#059669', bad: '#dc2626' };
const rate = v =>
  v === null || v === undefined
    ? '—'
    : String(Math.round(Number(v) * 10) / 10).replace('.', ',');
const rows = computed(() => {
  const list = props.ranking.rows || [];
  const top = Math.max(1, ...list.map(r => r.conversations || 0));
  return list.map(r => {
    const badges = r.badges || [];
    const lead = badges[0];
    return {
      ...r,
      badges,
      edge: lead ? TONE[lead.tone] : 'transparent',
      width: `${Math.max(1.5, ((r.conversations || 0) / top) * 100)}%`,
      fill: lead ? TONE[lead.tone] : 'rgb(var(--cv-rgb))',
    };
  });
});
</script>

<template>
  <div class="w-full">
    <p
      v-if="ranking.summary"
      class="br-summary px-4 py-3 mb-3 text-sm text-n-slate-12 leading-relaxed"
      :class="ranking.no_difference ? 'br-even' : ''"
    >
      {{ ranking.summary }}
    </p>
    <p v-if="!rows.length" class="text-xs text-n-slate-9">{{ emptyText }}</p>
    <ol class="flex flex-col gap-2 list-none p-0 m-0">
      <li
        v-for="(r, i) in rows"
        :key="r.key || r.label"
        class="br-row"
        :style="{ '--br-edge': r.edge }"
      >
        <div class="flex items-center gap-2 flex-wrap">
          <span class="text-[11px] font-bold text-n-slate-9 tabular-nums">
            {{ i + 1 }}º
          </span>
          <span class="text-sm font-bold text-n-slate-12">{{ r.label }}</span>
          <span
            v-for="b in r.badges"
            :key="b.key"
            class="br-badge"
            :style="{ '--br-tone': TONE[b.tone] }"
          >
            {{ b.label }}
          </span>
          <span
            class="ml-auto text-base font-extrabold text-n-slate-12 tabular-nums"
          >
            {{ fmtNum(r.conversations) }}
            <span class="text-[11px] font-normal text-n-slate-10">
              conversas
            </span>
          </span>
        </div>
        <div class="h-2.5 rounded-full bg-n-alpha-2 overflow-hidden my-1.5">
          <span
            class="block h-full rounded-full"
            :style="{ width: r.width, background: r.fill, opacity: 0.85 }"
          />
        </div>
        <p
          class="text-xs text-n-slate-11 flex flex-wrap gap-x-4 gap-y-0.5 leading-snug"
        >
          <span>
            <span class="font-bold tabular-nums text-n-slate-12">{{
              rate(r.clicks_per_100)
            }}</span>
            cliques a cada 100 exibições
          </span>
          <span>
            <span class="font-bold tabular-nums text-n-slate-12">{{
              rate(r.conversations_per_100)
            }}</span>
            conversas a cada 100 cliques
          </span>
          <span class="text-n-slate-10">
            {{ fmtNum(r.impressions) }} exibições ·
            {{ fmtNum(r.link_clicks) }} cliques
          </span>
          <span v-if="finance && r.spend" class="text-n-slate-10">
            {{ fmtMoney(r.spend) }}
            <template v-if="r.cost_conversation">
              · {{ fmtMoney(r.cost_conversation) }} por conversa
            </template>
          </span>
        </p>
      </li>
    </ol>
    <p v-if="rows.length" class="text-[11px] text-n-slate-9 mt-2 leading-snug">
      Aproveitamento = conversas a cada 1.000 exibições (o caminho inteiro: viu
      → clicou → conversou). Linha com menos de
      {{ ranking.min_impressions || 100 }} exibições não disputa, e diferença
      pequena demais para o volume não vira selo.
    </p>
  </div>
</template>

<style scoped>
.br-summary {
  border-radius: 14px;
  border: 1px solid rgb(var(--cv-rgb) / 0.25);
  border-left: 4px solid rgb(var(--cv-rgb));
  background: rgb(var(--cv-rgb) / 0.08);
}
.br-even {
  border-color: rgb(100 116 139 / 0.3);
  border-left-color: #64748b;
  background: rgb(100 116 139 / 0.08);
}
.br-row {
  padding: 10px 14px;
  border-radius: 14px;
  border: 1px solid rgb(var(--cv-rgb) / 0.16);
  border-left: 4px solid var(--br-edge);
  background: rgb(var(--cv-rgb) / 0.04);
}
.br-badge {
  padding: 1px 9px;
  border-radius: 9999px;
  font-size: 11px;
  font-weight: 700;
  color: var(--br-tone);
  border: 1px solid color-mix(in srgb, var(--br-tone) 45%, transparent);
  background: color-mix(in srgb, var(--br-tone) 10%, transparent);
}
</style>
