<script setup>
// 📊 HBars (kit CEVICO, 14/09): lista de BARRAS HORIZONTAIS — o gráfico
// certo para "qual anúncio / termo / agente traz mais". Sem lib: HTML puro.
//   • 1 ou 2 séries por linha (ex.: investimento × receita), mesma escala;
//   • barra fina com ponta arredondada só no fim (base reta), calha leve;
//   • valor escrito ao lado (texto na cor de texto, nunca na cor da série);
//   • legenda sempre que há 2 séries; tooltip nativo por linha;
//   • cor da série: hex/degradê da paleta do bloco (var(--cv-grad-2)) ou
//     cor própria por linha (identidade — ex.: cada agente com a sua cor).
import { computed, ref, onMounted, onBeforeUnmount } from 'vue';

const props = defineProps({
  // [{ label, sub, values: [n, n], color, hint, href }]
  rows: { type: Array, default: () => [] },
  // [{ label, color, format }] — 1 ou 2 séries
  series: { type: Array, default: () => [{ label: '', color: '' }] },
  format: {
    type: Function,
    default: v => Number(v || 0).toLocaleString('pt-BR'),
  },
  // largura da coluna do rótulo (rem)
  labelWidth: { type: Number, default: 11 },
  // destaca a maior barra de cada série
  highlightMax: { type: Boolean, default: true },
  emptyText: { type: String, default: 'sem dados no período' },
});

// contêiner estreito (< 380px) → rótulo em cima, barra embaixo (cabe em
// qualquer coluna sem esmagar a barra)
const wrap = ref(null);
const width = ref(600);
let observer = null;
onMounted(() => {
  if (wrap.value?.clientWidth) width.value = wrap.value.clientWidth;
  if (typeof ResizeObserver !== 'undefined' && wrap.value) {
    observer = new ResizeObserver(entries => {
      const w = entries[0]?.contentRect?.width;
      if (w) width.value = w;
    });
    observer.observe(wrap.value);
  }
});
onBeforeUnmount(() => observer?.disconnect());
const stacked = computed(() => width.value < 380);

const nums = (r, i) => Number((r.values || [])[i] || 0);
const max = computed(() =>
  Math.max(
    1,
    ...props.rows.flatMap(r => props.series.map((_, i) => nums(r, i)))
  )
);
const maxBySeries = computed(() =>
  props.series.map((_, i) => Math.max(0, ...props.rows.map(r => nums(r, i))))
);
const pct = (r, i) =>
  Math.max(nums(r, i) > 0 ? 1.5 : 0, (nums(r, i) / max.value) * 100);
const isMax = (r, i) =>
  props.highlightMax && nums(r, i) > 0 && nums(r, i) === maxBySeries.value[i];
const fmt = (s, v) => (s.format || props.format)(v);
const fillOf = (r, s) => r.color || s.color || 'var(--cv-grad-2)';
const rowTitle = r =>
  [
    r.label,
    ...props.series.map(
      (s, i) => `${s.label || 'valor'}: ${fmt(s, nums(r, i))}`
    ),
    r.hint,
  ]
    .filter(Boolean)
    .join(' · ');
</script>

<template>
  <div ref="wrap" class="cv-hbars">
    <!-- legenda: sempre que há 2 séries -->
    <div
      v-if="series.length > 1"
      class="flex items-center gap-3 flex-wrap mb-2.5"
    >
      <span
        v-for="s in series"
        :key="s.label"
        class="inline-flex items-center gap-1.5 text-[11px] text-n-slate-11"
      >
        <span
          class="w-2.5 h-2.5 rounded-sm flex-shrink-0"
          :style="{ background: s.color || 'var(--cv-grad-2)' }"
        />
        {{ s.label }}
      </span>
    </div>

    <p v-if="!rows.length" class="text-xs text-n-slate-9 py-3">
      {{ emptyText }}
    </p>

    <div v-else class="flex flex-col gap-1.5">
      <div
        v-for="(r, ri) in rows"
        :key="r.key || ri"
        class="cv-hbars-row grid items-center gap-x-3 gap-y-1 px-2 py-1.5 rounded-xl transition-colors hover:bg-[rgb(var(--cv-rgb)/0.07)]"
        :style="{
          gridTemplateColumns: stacked
            ? 'minmax(0, 1fr)'
            : `minmax(0, ${labelWidth}rem) minmax(0, 1fr)`,
        }"
        :title="rowTitle(r)"
      >
        <div class="min-w-0">
          <component
            :is="r.href ? 'a' : 'p'"
            :href="r.href"
            :target="r.href ? '_blank' : undefined"
            rel="noopener noreferrer"
            class="text-xs font-medium text-n-slate-12 truncate block"
            :class="r.href ? 'hover:underline' : ''"
          >
            <span v-if="r.badge" class="mr-1">{{ r.badge }}</span>{{ r.label }}
          </component>
          <p v-if="r.sub" class="text-[10px] text-n-slate-9 truncate">
            {{ r.sub }}
          </p>
        </div>
        <div class="flex flex-col gap-[3px] min-w-0">
          <div
            v-for="(s, si) in series"
            :key="si"
            class="grid items-center gap-2"
            style="grid-template-columns: minmax(0, 1fr) max-content"
          >
            <div
              class="h-[9px] rounded-full overflow-hidden"
              style="background: rgb(var(--cv-rgb) / 0.09)"
            >
              <div
                class="h-full rounded-r-full transition-[width] duration-500"
                :style="{
                  width: `${pct(r, si)}%`,
                  background: fillOf(r, s),
                  opacity: isMax(r, si) ? 1 : 0.82,
                }"
              />
            </div>
            <span
              class="text-[11px] text-right tabular-nums whitespace-nowrap"
              :class="
                isMax(r, si) ? 'font-bold text-n-slate-12' : 'text-n-slate-11'
              "
            >
              {{ nums(r, si) ? fmt(s, nums(r, si)) : '—' }}
            </span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
