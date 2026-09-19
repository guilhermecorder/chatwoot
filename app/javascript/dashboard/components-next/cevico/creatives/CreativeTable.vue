<script setup>
// Visão TABELA (item 172, rodada 2): um criativo por linha para varrer a
// conta inteira; colunas ordenáveis, veredito de cada peça por ícone +
// palavra, nada truncado (o nome quebra linha). Cabe SEMPRE na largura, sem
// barra: tabela fixa; no celular só Criativo, Conversas e Custo; o resto a
// partir de md (leads/cirurgias em xl).
// Clique = Ver a fundo.
import { computed, ref } from 'vue';
import {
  fmtMoney,
  fmtNum,
  fmtPct,
  statusMeta,
  FORMAT_ICON,
  BAND_META,
  CHAMPION_META,
} from './creativeFormat';
import CreativeRadar from './CreativeRadar.vue';

const props = defineProps({
  targets: { type: Object, default: () => ({}) },
  averages: { type: Object, default: () => ({}) },
  peers: { type: Array, default: () => [] },
  color: { type: String, default: 'var(--cv)' },
  rows: { type: Array, default: () => [] },
  compareMode: { type: Boolean, default: false },
  selectedIds: { type: Array, default: () => [] },
});
const emit = defineEmits(['open', 'toggle']);

const COLS = [
  {
    key: 'hook_rate',
    md: true,
    label: 'Gancho',
    band: 'hook',
    fmt: v => fmtPct(v),
    get: r => r.rates.hook_rate,
  },
  {
    key: 'hold_rate',
    md: true,
    label: 'Corpo',
    band: 'hold',
    fmt: v => fmtPct(v),
    get: r => r.rates.hold_rate,
  },
  {
    key: 'link_ctr',
    md: true,
    label: 'CTA',
    band: 'cta',
    fmt: v => fmtPct(v, 2),
    get: r => r.rates.link_ctr,
  },
  {
    key: 'conv_rate',
    md: true,
    label: 'Conversa',
    band: 'conv',
    fmt: v => fmtPct(v),
    get: r => r.rates.conv_rate,
  },
  {
    key: 'conversations',
    label: 'Conversas',
    fmt: v => fmtNum(v),
    get: r => r.totals.conversations,
  },
  {
    key: 'cost_conversation',
    label: 'Custo por conversa',
    band: 'cost',
    fmt: v => (v ? fmtMoney(v) : '—'),
    get: r => r.rates.cost_conversation,
    lower: true,
  },
  {
    key: 'spend',
    md: true,
    label: 'Investido',
    fmt: v => fmtMoney(v),
    get: r => r.totals.spend,
  },
  {
    key: 'leads',
    label: 'Leads',
    fmt: v => fmtNum(v),
    get: r => r.funnel.leads,
    xl: true,
  },
  {
    key: 'surgeries',
    label: 'Cirurgias',
    fmt: v => fmtNum(v),
    get: r => r.funnel.surgeries,
    xl: true,
  },
];
const sortKey = ref('spend');
const sortDir = ref(-1);
const sortBy = key => {
  if (sortKey.value === key) sortDir.value *= -1;
  else {
    sortKey.value = key;
    sortDir.value = -1;
  }
};
const sorted = computed(() => {
  const col = COLS.find(c => c.key === sortKey.value);
  if (!col) return props.rows;
  return [...props.rows].sort((a, b) => {
    const va = col.get(a);
    const vb = col.get(b);
    if (va === null || va === undefined) return 1;
    if (vb === null || vb === undefined) return -1;
    return (va - vb) * sortDir.value;
  });
});
const bandOf = (r, col) =>
  col.band && r.diagnosis && r.diagnosis.bands
    ? r.diagnosis.bands[col.band]
    : null;
</script>

<template>
  <div>
    <table class="w-full table-fixed text-xs">
      <thead>
        <tr class="text-[10px] uppercase tracking-wide text-n-slate-9">
          <th v-if="compareMode" class="py-2 pr-1 w-6" />
          <th class="text-left font-semibold py-2 pr-2 w-1/2 md:w-[30%]">
            Criativo
          </th>
          <th
            v-for="c in COLS"
            :key="c.key"
            class="text-right font-semibold py-2 pr-1.5 leading-tight cursor-pointer select-none"
            :class="{
              'hidden xl:table-cell': c.xl,
              'hidden md:table-cell': c.md,
            }"
            @click="sortBy(c.key)"
          >
            {{ c.label }}
            <span
              v-if="sortKey === c.key"
              :class="sortDir < 0 ? 'i-lucide-arrow-down' : 'i-lucide-arrow-up'"
              class="text-[10px]"
            />
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="r in sorted"
          :key="r.ad_id"
          class="border-t border-n-weak hover:bg-n-alpha-1 cursor-pointer align-top"
          @click="emit('open', r)"
        >
          <td v-if="compareMode" class="py-2 pr-1" @click.stop>
            <input
              type="checkbox"
              :checked="selectedIds.includes(r.ad_id)"
              class="accent-[var(--cv)]"
              @change="emit('toggle', r)"
            />
          </td>
          <td class="py-2 pr-2">
            <div class="flex items-start gap-2">
              <CreativeRadar
                :row="r"
                env="criativos"
                :targets="targets"
                :averages="averages"
                :peers="peers"
                :size="46"
                :labels="false"
                :color="color"
                class="flex-shrink-0 mt-0.5 hidden md:inline-flex"
              />
              <span
                class="w-10 h-12 rounded-lg overflow-hidden bg-n-alpha-2 flex-shrink-0 hidden md:flex items-center justify-center"
              >
                <img
                  v-if="r.thumbnail_url"
                  :src="r.thumbnail_url"
                  :alt="r.ad_name"
                  class="w-full h-full object-cover"
                  loading="lazy"
                />
                <span
                  v-else
                  :class="FORMAT_ICON[r.format]"
                  class="text-n-slate-9"
                />
              </span>
              <div class="min-w-0">
                <p class="font-semibold text-n-slate-12 leading-snug">
                  {{ r.ad_name }}
                  <span
                    v-for="k in r.champion_of || []"
                    :key="k"
                    class="inline-flex items-center text-amber-500 ml-1 align-middle"
                    :title="CHAMPION_META[k] && CHAMPION_META[k].label"
                  >
                    <span
                      :class="
                        CHAMPION_META[k]
                          ? CHAMPION_META[k].icon
                          : 'i-lucide-trophy'
                      "
                      class="text-xs"
                    />
                  </span>
                </p>
                <p class="text-[10px] text-n-slate-9">
                  {{ r.format_label }} ·
                  <span
                    class="inline-block w-1.5 h-1.5 rounded-full align-middle"
                    :class="statusMeta(r.status).cls"
                  />
                  {{ statusMeta(r.status).label }}
                  <span
                    v-if="r.diagnosis && r.diagnosis.fatigue"
                    class="text-amber-700 dark:text-amber-400 font-semibold"
                  >
                    · fadiga</span
                  >
                </p>
                <p class="text-[11px] text-n-slate-11 italic">
                  “{{ r.hook || '—' }}”
                </p>
              </div>
            </div>
          </td>
          <td
            v-for="c in COLS"
            :key="c.key"
            class="py-2 pr-1.5 text-right tabular-nums"
            :class="{
              'hidden xl:table-cell': c.xl,
              'hidden md:table-cell': c.md,
            }"
          >
            <span class="text-n-slate-12 font-semibold">{{
              c.fmt(c.get(r))
            }}</span>
            <span
              v-if="bandOf(r, c)"
              class="flex text-[10px] font-semibold items-center gap-0.5 justify-end"
              :class="BAND_META[bandOf(r, c)].cls"
            >
              <span :class="BAND_META[bandOf(r, c)].icon" />{{
                BAND_META[bandOf(r, c)].label
              }}
            </span>
          </td>
        </tr>
      </tbody>
    </table>
    <p v-if="!rows.length" class="text-xs text-n-slate-9 py-4 text-center">
      Nenhum criativo neste recorte.
    </p>
  </div>
</template>
