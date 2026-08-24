<script setup>
// 🔍 Popup de detalhes de um KPI (kit CEVICO, item 145) — o motor do popup
// do Meu Painel (item 144) empacotado pra qualquer tela: gráfico do cesto
// de indicadores com mini-régua própria, período anterior sobreposto,
// linha de meta, 📌 ações da empresa e a decomposição ("de onde vem").
// tile: { label, icon, grad, value, sub, chip, chartKey|chartMatch,
//         components: [chaves do cesto], details: [{label, value}], about,
//         format: 'number'|'percent'|'currency', goalTarget: meta MENSAL }
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import CrmAPI from 'dashboard/api/crm';
import MiniBars from 'dashboard/components-next/cevico/MiniBars.vue';
import { formatKpi } from 'dashboard/helper/cevicoFormula';

const props = defineProps({
  tile: { type: Object, required: true },
  // período da tela que abriu o popup ({ preset, from, to })
  period: { type: Object, default: () => ({ preset: 'month' }) },
  accent: { type: String, default: '#0F5FA6' },
});
const emit = defineEmits(['close']);

const store = useStore();
const crmSettings = useMapGetter('crm/getSettings');

// ── cesto de indicadores do popup (recorte próprio) ──
const bag = ref(null);
const isLoadingBag = ref(false);
const preset = ref(null); // null = período da tela
const granularity = ref(null);
const MODAL_PRESETS = [
  [null, 'Régua da tela'],
  ['last7', '7 dias'],
  ['month', 'Este mês'],
  ['year', 'Este ano'],
];
const MODAL_GRAINS = [
  [null, 'Auto'],
  ['day', 'Dia'],
  ['week', 'Semana'],
  ['month', 'Mês'],
];
const fetchBag = async () => {
  isLoadingBag.value = true;
  try {
    const params = preset.value
      ? { preset: preset.value }
      : {
          preset: props.period.preset,
          ...(props.period.preset === 'custom'
            ? { from: props.period.from, to: props.period.to }
            : {}),
        };
    if (granularity.value) params.granularity = granularity.value;
    const { data } = await CrmAPI.getKpiBag(params);
    bag.value = data;
  } catch {
    bag.value = bag.value || null;
  } finally {
    isLoadingBag.value = false;
  }
};
const setPreset = p => {
  preset.value = p;
  fetchBag();
};
const setGranularity = g => {
  granularity.value = g;
  fetchBag();
};
onMounted(() => {
  fetchBag();
  if (!Object.keys(crmSettings.value || {}).length) {
    store.dispatch('crm/fetchSettings').catch(() => {});
  }
});

const fmt = v => formatKpi(v, props.tile.format || 'number');
const grainLabel = computed(() => {
  const g = bag.value?.granularity;
  if (g === 'month') return 'por mês';
  if (g === 'week') return 'por semana';
  return 'por dia';
});

// métrica do gráfico: chave direta ou casada pelo rótulo (colunas do funil)
const metric = computed(() => {
  const b = bag.value;
  if (!b?.metrics) return null;
  if (props.tile.chartKey) return b.metrics[props.tile.chartKey] || null;
  if (props.tile.chartMatch) {
    const re = new RegExp(props.tile.chartMatch, 'i');
    const key = Object.keys(b.metrics).find(k => re.test(b.metrics[k].label || ''));
    return key ? b.metrics[key] : null;
  }
  return null;
});
const labels = computed(() => (bag.value?.points || []).map(p => p.label));

// meta do balde: fatia da meta MENSAL pela granularidade do cesto
const goalPerBucket = computed(() => {
  const target = Number(props.tile.goalTarget) || 0;
  if (!target) return null;
  const now = new Date();
  const daysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
  const daily = target / daysInMonth;
  const g = bag.value?.granularity;
  if (g === 'week') return Math.round(daily * 7 * 10) / 10;
  if (g === 'month') return target;
  return Math.round(daily * 10) / 10;
});
// 📌 ações da empresa nos baldes do gráfico
const markers = computed(() => {
  const b = bag.value;
  const actions = crmSettings.value?.company_actions || [];
  if (!b?.points?.length || !actions.length) return [];
  const keys = b.points.map(p => p.key);
  const idxFor = date => {
    if (b.granularity === 'month') return keys.findIndex(k => k.slice(0, 7) === date.slice(0, 7));
    if (b.granularity === 'week') {
      for (let i = keys.length - 1; i >= 0; i -= 1) if (keys[i] <= date) return i;
      return -1;
    }
    return keys.indexOf(date);
  };
  return actions.map(a => ({ index: idxFor(a.date), title: a.title })).filter(m => m.index >= 0);
});
const deltaText = computed(() => {
  const m = metric.value;
  if (!m || m.prev === null || m.prev === undefined) return '';
  if (!m.prev) return `anterior: ${fmt(m.prev)}`;
  const pct = ((m.value - m.prev) / Math.abs(m.prev)) * 100;
  return `${pct >= 0 ? '▲' : '▼'} ${Math.abs(pct).toFixed(0)}% vs ${bag.value?.previous_label || 'período anterior'} (${fmt(m.prev)})`;
});
// decomposição: as séries que formam a conta
const components = computed(() => {
  const b = bag.value;
  if (!b?.metrics) return [];
  return (props.tile.components || [])
    .slice(0, 3)
    .filter(k => b.metrics[k])
    .map(k => ({ key: k, ...b.metrics[k] }));
});
const compFmt = comp => v => formatKpi(v, comp.unit === 'brl' ? 'currency' : 'number');
</script>

<template>
  <Teleport to="body">
    <div
      class="fixed inset-0 z-[70] flex items-center justify-center bg-black/50 p-4"
      @click.self="emit('close')"
    >
      <div class="w-full max-w-lg rounded-2xl overflow-hidden shadow-2xl bg-n-solid-1 max-h-[92vh] flex flex-col">
        <div class="p-5 text-white flex-shrink-0" :style="{ background: tile.grad || accent }">
          <div class="flex items-center gap-2 text-white/85">
            <span v-if="tile.icon" :class="tile.icon" class="text-base" />
            <p class="text-sm font-medium flex-1">{{ tile.label }}</p>
            <button class="w-7 h-7 rounded-lg bg-white/15 hover:bg-white/30 flex items-center justify-center" @click="emit('close')">
              <span class="i-lucide-x text-sm" />
            </button>
          </div>
          <p class="text-4xl font-bold mt-2">{{ tile.value }}</p>
          <span v-if="tile.chip" class="inline-block mt-1 text-[11px] px-2 py-0.5 rounded-full font-semibold bg-white/20">{{ tile.chip }}</span>
          <p v-if="tile.sub" class="text-xs text-white/80 mt-1">{{ tile.sub }}</p>
        </div>
        <div class="p-5 space-y-3 overflow-y-auto">
          <div v-if="metric" class="rounded-xl bg-n-alpha-1 px-3 py-2">
            <div class="flex items-center justify-between gap-2 text-[10px] text-n-slate-10 mb-1">
              <span class="truncate">{{ metric.label }} · {{ grainLabel }}</span>
              <span v-if="isLoadingBag" class="i-lucide-loader-circle animate-spin text-xs flex-shrink-0" />
              <span v-else-if="metric.prev_series?.length" class="flex-shrink-0">tracejado = período anterior</span>
            </div>
            <MiniBars
              :values="metric.series || []"
              :labels="labels"
              :color="accent"
              :height="110"
              :prev-values="metric.prev_series?.length ? metric.prev_series : null"
              :goal="goalPerBucket"
              :markers="markers"
              :format="fmt"
            />
            <div class="flex items-center justify-between gap-2 flex-wrap mt-1">
              <p
                v-if="deltaText"
                class="text-[11px]"
                :class="(metric.value ?? 0) >= (metric.prev ?? 0) ? 'text-emerald-600' : 'text-red-500'"
              >
                {{ deltaText }}
              </p>
              <p v-if="goalPerBucket" class="text-[10px]" style="color: #B8860B">
                ⭑ meta ≈ {{ fmt(goalPerBucket) }} por {{ bag?.granularity === 'month' ? 'mês' : bag?.granularity === 'week' ? 'semana' : 'dia' }}
              </p>
            </div>
            <div class="flex items-center gap-1 flex-wrap mt-2 pt-2 border-t border-n-weak/60">
              <button
                v-for="p in MODAL_PRESETS"
                :key="String(p[0])"
                class="h-6 px-2 rounded-md text-[10px] font-medium border transition-colors"
                :class="preset === p[0] ? 'text-white border-transparent' : 'border-n-weak text-n-slate-10 hover:bg-n-alpha-1'"
                :style="preset === p[0] ? { background: accent } : {}"
                @click="setPreset(p[0])"
              >
                {{ p[1] }}
              </button>
              <span class="text-n-weak text-[10px]">·</span>
              <button
                v-for="g in MODAL_GRAINS"
                :key="String(g[0])"
                class="h-6 px-2 rounded-md text-[10px] font-medium border transition-colors"
                :class="granularity === g[0] ? 'text-white border-transparent' : 'border-n-weak text-n-slate-10 hover:bg-n-alpha-1'"
                :style="granularity === g[0] ? { background: accent } : {}"
                @click="setGranularity(g[0])"
              >
                {{ g[1] }}
              </button>
            </div>
          </div>
          <div v-if="components.length" class="rounded-xl bg-n-alpha-1 px-3 py-2 space-y-2">
            <p class="text-[10px] text-n-slate-10">🧩 de onde vem: as séries da conta</p>
            <div v-for="comp in components" :key="comp.key">
              <div class="flex items-center justify-between text-[10px] mb-0.5">
                <span class="text-n-slate-11">{{ comp.label }}</span>
                <b class="text-n-slate-12">{{ compFmt(comp)(comp.value) }}</b>
              </div>
              <MiniBars
                :values="comp.series || []"
                :labels="labels"
                color="#64748B"
                :height="46"
                :prev-values="comp.prev_series?.length ? comp.prev_series : null"
                :format="compFmt(comp)"
              />
            </div>
          </div>
          <div v-if="tile.details?.length" class="space-y-1.5">
            <div
              v-for="(row, ri) in tile.details"
              :key="ri"
              class="flex items-start justify-between gap-3 text-xs rounded-xl bg-n-alpha-1 px-3 py-2"
            >
              <span class="text-n-slate-11">{{ row.label }}</span>
              <b class="text-n-slate-12 text-right whitespace-nowrap">{{ row.value }}</b>
            </div>
          </div>
          <p v-if="tile.about" class="text-[11px] text-n-slate-10 leading-relaxed">
            <span class="i-lucide-info text-xs align-middle mr-1" />{{ tile.about }}
          </p>
        </div>
      </div>
    </div>
  </Teleport>
</template>
