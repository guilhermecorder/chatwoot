<script setup>
// 📈 RESULTADOS DE TRÁFEGO das Páginas — painel novo (item 329, 05/10/2026:
// "coloque as taxas de conversão ao longo das etapas do funil; remodele com a
// nossa visão apple glass; gráficos em linha; precisamos poder otimizar a
// página; um ambiente com coleta de insights").
//
// Duas abas:
//   RESULTADOS  o funil com a taxa de cada etapa (visita → clique → lead →
//               agendou → cirurgia), a evolução em gráfico de área, as
//               origens e cada página com as suas taxas;
//   OTIMIZAR    os diagnósticos automáticos (onde o funil vaza e o que
//               fazer), as sugestões da IA por página e a COLEÇÃO de insights
//               que a equipe decidiu guardar — com antes × depois.
// A conta mora no servidor (Cevico::TrafficReport / PageInsights / InsightLog).
import { ref, computed, onMounted, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import AreaChart from 'dashboard/components-next/cevico/AreaChart.vue';
import FunnelSteps from 'dashboard/components-next/cevico/FunnelSteps.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import CrmAPI from 'dashboard/api/crm';

const isLoading = ref(true);
const data = ref(null);
const period = ref({ preset: 'month', from: '', to: '' });
const tab = ref('resultados');
const sourceFilter = ref(''); // '' = todas as origens
const chartMode = ref('volume');
const sourcesView = ref('cards');
const pagesView = ref('list');
const expandedId = ref(null);

const pal = useCevicoPalette({
  scope: 'report:traffic',
  blocks: [
    { id: 'funil', label: 'O funil', icon: 'i-lucide-filter' },
    { id: 'evolucao', label: 'Evolução', icon: 'i-lucide-activity' },
    { id: 'origens', label: 'Origens', icon: 'i-lucide-git-fork' },
    { id: 'paginas', label: 'Páginas', icon: 'i-lucide-layout-template' },
    { id: 'diagnosticos', label: 'Diagnósticos', icon: 'i-lucide-lightbulb' },
    { id: 'ia', label: 'Sugestões da IA', icon: 'i-lucide-sparkles' },
    { id: 'colecao', label: 'Coleção de insights', icon: 'i-lucide-bookmark' },
  ],
});
const { cvVars, blockVars, blockFamily } = pal;

const SOURCE_META = {
  google_ads: { icon: 'i-lucide-target', color: '#1A73E8' },
  google_organico: { icon: 'i-lucide-search', color: '#16A34A' },
  meta_ads: { icon: 'i-lucide-megaphone', color: '#7C3AED' },
  social: { icon: 'i-lucide-smartphone', color: '#DB2777' },
  outros_ads: { icon: 'i-lucide-badge-dollar-sign', color: '#D97706' },
  funil: { icon: 'i-lucide-filter', color: '#0F5FA6' },
  busca: { icon: 'i-lucide-compass', color: '#0891B2' },
  direto: { icon: 'i-lucide-door-open', color: '#64748B' },
};
const STEP_COLORS = {
  views: '#2563EB',
  cta: '#16A34A',
  leads: '#D97706',
  booked: '#0891B2',
  conversions: '#7C3AED',
};

const params = () => ({
  preset: period.value.preset,
  ...(period.value.preset === 'custom'
    ? { from: period.value.from, to: period.value.to }
    : {}),
});
const load = async () => {
  isLoading.value = true;
  try {
    const { data: payload } = await CrmAPI.getPagesReport(params());
    data.value = payload;
  } catch {
    useAlert('Não consegui carregar os resultados.');
  } finally {
    isLoading.value = false;
  }
};
watch(period, load, { deep: true });
onMounted(load);

// ── formatos ────────────────────────────────────────────────────────────
const fmtNum = v => Number(v || 0).toLocaleString('pt-BR');
const fmtMoney = v =>
  Number(v || 0).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    maximumFractionDigits: 0,
  });
const rate = (part, total) =>
  total ? Math.round((part / total) * 1000) / 10 : null;
const fmtRate = r => (r === null ? '—' : `${String(r).replace('.', ',')}%`);
const pct = (part, total) => fmtRate(rate(part, total));
const dateBR = iso => {
  if (!iso) return '';
  const [y, m, d] = String(iso).slice(0, 10).split('-');
  return `${d}/${m}/${y}`;
};

// ── recorte: todas as origens ou uma só ────────────────────────────────
const sources = computed(() => data.value?.sources || {});
const rows = computed(() => data.value?.rows || []);
const sourceLabel = src => sources.value[src] || src;
const bucketOf = page =>
  sourceFilter.value ? page.sources?.[sourceFilter.value] || null : page;
const visibleRows = computed(() =>
  rows.value
    .map(page => ({ page, data: bucketOf(page) }))
    .filter(r => r.data && (r.data.views || r.data.leads || r.data.cta))
);
const blank = () => ({
  views: 0,
  cta: 0,
  leads: 0,
  booked: 0,
  conversions: 0,
  revenue: 0,
});
const totals = computed(() => {
  const sum = blank();
  visibleRows.value.forEach(({ data: d }) => {
    Object.keys(sum).forEach(k => {
      sum[k] += d[k] || 0;
    });
  });
  return sum;
});
// o período anterior só existe para "todas as origens"
const previous = computed(() =>
  sourceFilter.value ? null : data.value?.previous?.totals || null
);
const delta = (cur, prev) => {
  if (prev === null || prev === undefined || !previous.value) return '';
  if (!prev) return cur ? ' · antes: 0' : '';
  const diff = Math.round(((cur - prev) / prev) * 100);
  let arrow = '=';
  if (diff > 0) arrow = '▲';
  if (diff < 0) arrow = '▼';
  return ` · ${arrow} ${Math.abs(diff)}% vs período anterior (${fmtNum(prev)})`;
};
const rateDelta = (curPart, curTotal, prevPart, prevTotal) => {
  if (!previous.value) return '';
  const before = rate(prevPart, prevTotal);
  return before === null ? '' : ` · antes: ${fmtRate(before)}`;
};

// ── o funil ─────────────────────────────────────────────────────────────
const STEPS = [
  { key: 'views', label: 'Visitas', hint: 'abriram a página' },
  { key: 'cta', label: 'Cliques no WhatsApp', hint: 'tocaram no botão' },
  { key: 'leads', label: 'Leads na caixa', hint: 'mandaram a mensagem' },
  { key: 'booked', label: 'Agendaram', hint: 'têm consulta na Agenda' },
  { key: 'conversions', label: 'Cirurgias', hint: 'chegaram à cirurgia' },
];
const funnelSteps = computed(() =>
  STEPS.map(st => ({
    key: st.key,
    label: st.label,
    value: totals.value[st.key],
    color: STEP_COLORS[st.key],
    sub: st.hint,
  }))
);
// de cada 100 visitas…
const per100 = key => {
  const r = rate(totals.value[key], totals.value.views);
  return r === null ? '—' : String(r).replace('.', ',');
};
// a passagem mais apertada do funil (só entre etapas com gente na de cima).
// A cirurgia fica fora: leva semanas para acontecer e daria sempre "0% passam"
const biggestLeak = computed(() => {
  let worst = null;
  STEPS.slice(1, 4).forEach((st, i) => {
    const from = STEPS[i];
    const base = totals.value[from.key];
    if (base < 10) return;
    const r = rate(totals.value[st.key], base);
    if (worst === null || r < worst.rate)
      worst = { from: from.label, to: st.label, rate: r, base };
  });
  return worst;
});

// ── evolução (gráficos de área) ─────────────────────────────────────────
const series = computed(() => data.value?.series || null);
const seriesOf = key => {
  const s = series.value;
  if (!s) return [];
  if (sourceFilter.value) return s.by_source?.[sourceFilter.value]?.[key] || [];
  return s[key] || [];
};
const GRAIN_LABEL = { day: 'por dia', week: 'por semana', month: 'por mês' };
const chartSeries = computed(() => {
  const s = series.value;
  if (!s) return [];
  if (chartMode.value === 'origens') {
    return Object.entries(s.by_source || {})
      .map(([src, vals]) => ({
        key: src,
        label: sourceLabel(src),
        color: SOURCE_META[src]?.color || '#64748B',
        values: vals.views || [],
      }))
      .filter(x => x.values.some(v => v > 0))
      .sort(
        (a, b) =>
          b.values.reduce((p, v) => p + v, 0) -
          a.values.reduce((p, v) => p + v, 0)
      );
  }
  const views = seriesOf('views');
  if (chartMode.value === 'taxas') {
    const ratio = key =>
      seriesOf(key).map((v, i) =>
        views[i] ? Math.round((v / views[i]) * 1000) / 10 : 0
      );
    return [
      {
        key: 'click_rate',
        label: 'Clicam no WhatsApp (% das visitas)',
        color: STEP_COLORS.cta,
        values: ratio('cta'),
      },
      {
        key: 'lead_rate',
        label: 'Viram lead (% das visitas)',
        color: STEP_COLORS.leads,
        values: ratio('leads'),
      },
    ];
  }
  return [
    {
      key: 'views',
      label: 'Visitas',
      color: STEP_COLORS.views,
      values: views,
    },
    {
      key: 'cta',
      label: 'Cliques no WhatsApp',
      color: STEP_COLORS.cta,
      values: seriesOf('cta'),
    },
    {
      key: 'leads',
      label: 'Leads na caixa',
      color: STEP_COLORS.leads,
      values: seriesOf('leads'),
    },
  ];
});
const chartFormat = v =>
  chartMode.value === 'taxas'
    ? `${String(Math.round(v * 10) / 10).replace('.', ',')}%`
    : fmtNum(v);
const CHART_MODES = [
  ['volume', 'Volume'],
  ['taxas', 'Taxas de conversão'],
  ['origens', 'Visitas por origem'],
];
const visibleChartModes = computed(() =>
  CHART_MODES.filter(([key]) => key !== 'origens' || !sourceFilter.value)
);
watch(sourceFilter, v => {
  if (v && chartMode.value === 'origens') chartMode.value = 'volume';
});

// ── origens ─────────────────────────────────────────────────────────────
const sourceRows = computed(() => {
  const acc = {};
  rows.value.forEach(page => {
    Object.entries(page.sources || {}).forEach(([src, d]) => {
      acc[src] = acc[src] || blank();
      Object.keys(acc[src]).forEach(k => {
        acc[src][k] += d[k] || 0;
      });
    });
  });
  const allViews = Object.values(acc).reduce((p, d) => p + d.views, 0);
  return Object.entries(acc)
    .map(([src, d]) => ({
      src,
      label: sourceLabel(src),
      meta: SOURCE_META[src] || SOURCE_META.direto,
      share: rate(d.views, allViews),
      ...d,
    }))
    .sort((a, b) => b.views - a.views);
});

// ── páginas ─────────────────────────────────────────────────────────────
const rowKey = page => page.page_id ?? 'hub';
const sourcesOf = page =>
  Object.entries(page.sources || {}).sort((a, b) => b[1].views - a[1].views);
const campaignsOf = page =>
  Object.entries(page.campaigns || {}).sort(
    (a, b) => b[1].leads - a[1].leads || b[1].views - a[1].views
  );
// linha fininha das visitas da página ao longo do período
const sparkPath = page => {
  const values = (page.spark || []).map(p => p[0]);
  if (values.length < 2 || !values.some(v => v > 0)) return '';
  const max = Math.max(...values, 1);
  const step = 100 / (values.length - 1);
  return values
    .map(
      (v, i) =>
        `${i ? 'L' : 'M'}${(i * step).toFixed(1)},${(26 - (v / max) * 24).toFixed(1)}`
    )
    .join(' ');
};
const readingOf = (page, d) => {
  const sc = page.scroll || {};
  if (!sc['25'] && !sc['50'] && !sc['100']) return '';
  return `metade da página: ${pct(sc['50'] || 0, d.views)} · até o fim: ${pct(sc['100'] || 0, d.views)}`;
};

// ── diagnósticos ────────────────────────────────────────────────────────
const LEVELS = {
  alerta: { label: 'Vazamento', chip: 'cv-red', icon: 'i-lucide-droplets' },
  atencao: { label: 'Atenção', chip: 'cv-amber', icon: 'i-lucide-eye' },
  oportunidade: {
    label: 'Oportunidade',
    chip: 'cv-green',
    icon: 'i-lucide-rocket',
  },
  seo: { label: 'Google', chip: 'cv-blue', icon: 'i-lucide-search' },
};
const insights = computed(() => data.value?.insights || []);
const pages = computed(() => data.value?.pages || []);
const pageById = id => pages.value.find(p => p.id === id) || null;
const insightFilter = ref('todos');
const insightPage = ref('');
const INSIGHT_FILTERS = [
  ['todos', 'Todos', () => true],
  ['funil', 'Funil', i => ['alerta', 'atencao'].includes(i.level)],
  ['oportunidade', 'Oportunidades', i => i.level === 'oportunidade'],
  ['seo', 'Google (SEO)', i => i.level === 'seo'],
];
const countFor = key => {
  const test = INSIGHT_FILTERS.find(f => f[0] === key)[2];
  return insights.value.filter(
    i => test(i) && (!insightPage.value || i.page_id === insightPage.value)
  ).length;
};
const visibleInsights = computed(() => {
  const test = INSIGHT_FILTERS.find(f => f[0] === insightFilter.value)[2];
  return insights.value.filter(
    i => test(i) && (!insightPage.value || i.page_id === insightPage.value)
  );
});
const insightsOfPage = pageId =>
  insights.value.filter(i => i.page_id === pageId);
const pagesWithInsights = computed(() => {
  const ids = [...new Set(insights.value.map(i => i.page_id))];
  return ids.map(pageById).filter(Boolean);
});
const openOptimize = pageId => {
  insightPage.value = pageId || '';
  insightFilter.value = 'todos';
  tab.value = 'otimizar';
};

// ── coleção de insights ─────────────────────────────────────────────────
const collection = computed(() => data.value?.collection || []);
const savedKeys = computed(
  () =>
    new Set(
      collection.value
        .filter(c => c.key && c.status !== 'dismissed')
        .map(c => c.key)
    )
);
const isSaving = ref(false);
const saveInsight = async payload => {
  if (isSaving.value) return;
  isSaving.value = true;
  try {
    const { data: out } = await CrmAPI.savePageInsight(payload);
    data.value = { ...data.value, collection: out.collection };
    if (!payload.id) useAlert('Guardado na coleção de insights.');
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui guardar.');
  } finally {
    isSaving.value = false;
  }
};
const keepInsight = insight =>
  saveInsight({
    key: insight.key,
    page_id: insight.page_id,
    title: insight.title,
    text: `${insight.evidence}\n\nO que fazer: ${insight.suggestion}`,
    origin: 'auto',
  });
const setStatus = (item, status) => saveInsight({ id: item.id, status });
const removeInsight = async item => {
  try {
    const { data: out } = await CrmAPI.removePageInsight(item.id);
    data.value = { ...data.value, collection: out.collection };
  } catch {
    useAlert('Não consegui apagar.');
  }
};
const COLLECTION_TABS = [
  ['todo', 'A fazer'],
  ['done', 'Aplicados'],
  ['dismissed', 'Descartados'],
];
const collectionTab = ref('todo');
const collectionCount = status =>
  collection.value.filter(c => c.status === status).length;
const visibleCollection = computed(() =>
  collection.value.filter(c => c.status === collectionTab.value)
);
const ORIGIN_LABEL = {
  auto: 'diagnóstico automático',
  ia: 'sugestão da IA',
  manual: 'escrito pela equipe',
};
const resultLine = item => {
  const r = item.result;
  if (!r) return '';
  return `clique no WhatsApp ${fmtRate(r.before.click_rate)} → ${fmtRate(r.after.click_rate)} · leads ${r.before.leads} → ${r.after.leads} · visitas ${fmtNum(r.before.views)} → ${fmtNum(r.after.views)}`;
};
// insight escrito à mão
const draft = ref({ title: '', text: '', page_id: '' });
const saveDraft = async () => {
  if (!draft.value.title.trim()) {
    useAlert('Dê um título curto ao insight.');
    return;
  }
  await saveInsight({ ...draft.value, origin: 'manual' });
  draft.value = { title: '', text: '', page_id: '' };
  collectionTab.value = 'todo';
};

// ── levar o insight para a página (ambiente de montagem) ────────────────
const openBuilder = async (pageId, text) => {
  const page = pageById(pageId);
  if (!page) return;
  try {
    await copyTextToClipboard(text);
    useAlert('Pedido copiado. Cole no chat do ambiente de montagem.');
  } catch {
    useAlert('Abri a montagem; copie o texto do insight à mão.');
  }
  window.open(page.builder_url, '_blank', 'noopener');
};
const openPublic = pageId => {
  const page = pageById(pageId);
  if (page) window.open(page.public_url, '_blank', 'noopener');
};

// ── sugestões da IA (só quando alguém pede) ─────────────────────────────
const aiPageId = ref('');
const aiLoading = ref(false);
const aiResults = ref({}); // página → { diagnostico, sugestoes }
const aiResult = computed(() => aiResults.value[aiPageId.value] || null);
watch(insightPage, v => {
  if (v) aiPageId.value = v;
});
const askAi = async () => {
  if (!aiPageId.value || aiLoading.value) return;
  aiLoading.value = true;
  try {
    const { data: out } = await CrmAPI.getPageAiSuggestions({
      ...params(),
      page_id: aiPageId.value,
    });
    aiResults.value = { ...aiResults.value, [aiPageId.value]: out };
  } catch (error) {
    useAlert(
      error?.response?.data?.error || 'Não consegui pedir as sugestões agora.'
    );
  } finally {
    aiLoading.value = false;
  }
};
const keepAi = sug =>
  saveInsight({
    page_id: aiPageId.value,
    title: sug.titulo,
    text: `${sug.por_que}\n\nPedido para a montagem: ${sug.pedido}`,
    origin: 'ia',
  });
</script>

<template>
  <!-- w-full + min-w-0: a página nunca estica além da tela (no celular quem rola para o lado é a régua, não a página) -->
  <div class="cv-page cv-overlay w-full min-w-0" :style="cvVars">
    <CevicoHero
      :pal="pal"
      title="Resultados de tráfego"
      subtitle="de onde veio cada visita, o que ela virou e onde o funil vaza · páginas e SEO"
      icon="i-lucide-trending-up"
    />

    <div class="flex items-center gap-2 flex-wrap mb-3">
      <PeriodRuler v-model="period" glass class="max-w-full min-w-0" />
      <div class="cv-seg inline-flex items-center gap-0.5 flex-shrink-0">
        <button
          class="cv-seg-item text-xs font-medium whitespace-nowrap flex-shrink-0"
          :class="tab === 'resultados' ? 'cv-seg-on' : ''"
          @click="tab = 'resultados'"
        >
          <span class="i-lucide-bar-chart-3 text-sm mr-1 align-middle" />
          Resultados
        </button>
        <button
          class="cv-seg-item text-xs font-medium whitespace-nowrap flex-shrink-0"
          :class="tab === 'otimizar' ? 'cv-seg-on' : ''"
          @click="tab = 'otimizar'"
        >
          <span class="i-lucide-lightbulb text-sm mr-1 align-middle" />
          Otimizar
          <b v-if="insights.length" class="ml-1">{{ insights.length }}</b>
        </button>
      </div>
    </div>

    <SkeletonScreen v-if="isLoading" variant="dashboard" />

    <template v-else-if="data">
      <!-- ════════════════ ABA RESULTADOS ════════════════ -->
      <template v-if="tab === 'resultados'">
        <!-- origem: todas ou uma só (vale para o funil, o gráfico e as páginas) -->
        <div class="flex items-center gap-1.5 flex-wrap mb-6">
          <span class="text-[11px] text-n-slate-10 mr-1">Origem</span>
          <button
            class="cv-chip"
            :class="sourceFilter === '' ? 'cv-chip-on' : ''"
            @click="sourceFilter = ''"
          >
            Todas
          </button>
          <button
            v-for="s in sourceRows"
            :key="s.src"
            class="cv-chip"
            :class="sourceFilter === s.src ? 'cv-chip-on' : ''"
            @click="sourceFilter = sourceFilter === s.src ? '' : s.src"
          >
            <span :class="s.meta.icon" class="text-xs" />
            {{ s.label }}
            <b>{{ fmtNum(s.views) }}</b>
          </button>
        </div>

        <!-- ══ 1 · O FUNIL ══ -->
        <div class="cv-block p-6 sm:p-8 mb-8" :style="blockVars('funil')">
          <div class="flex items-center gap-3 mb-1 flex-wrap">
            <span class="cv-icon"
              ><span class="i-lucide-filter text-base"
            /></span>
            <h2
              class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
            >
              O funil
            </h2>
            <span v-if="sourceFilter" class="cv-chip cv-chip-on ml-auto">
              só {{ sourceLabel(sourceFilter) }}
            </span>
          </div>
          <p class="text-xs text-n-slate-10 mb-6">
            {{ dateBR(data.since) }} a {{ dateBR(data.until) }} · entre uma
            etapa e outra, quanto passou; embaixo, quanto das visitas chegou até
            ali
          </p>
          <!-- no computador: degraus lado a lado; no celular: o mesmo funil em pé -->
          <div class="hidden md:block">
            <FunnelSteps
              :steps="funnelSteps"
              :height="150"
              start-text="das visitas"
            />
          </div>
          <div class="md:hidden">
            <template v-for="(st, si) in funnelSteps" :key="st.key">
              <p
                v-if="si > 0"
                class="pl-4 py-1.5 text-xs text-n-slate-10 border-l-2 ml-3"
                :style="{ borderColor: st.color }"
              >
                <b class="text-n-slate-12">{{
                  pct(st.value, funnelSteps[si - 1].value)
                }}</b>
                passam da etapa anterior
              </p>
              <div class="cv-sub px-4 py-3 flex items-center gap-3">
                <span
                  class="w-2.5 h-10 rounded-full flex-shrink-0"
                  :style="{ background: st.color }"
                />
                <div class="min-w-0 flex-1">
                  <p class="text-sm font-bold text-n-slate-12 leading-tight">
                    {{ st.label }}
                  </p>
                  <p class="text-[11px] text-n-slate-10">
                    {{ st.sub }}
                    <template v-if="si > 0">
                      · {{ pct(st.value, totals.views) }} das visitas
                    </template>
                  </p>
                </div>
                <p
                  class="text-2xl font-extrabold tabular-nums whitespace-nowrap"
                  :style="{ color: st.color }"
                >
                  {{ fmtNum(st.value) }}
                </p>
              </div>
            </template>
          </div>

          <p
            v-if="totals.views"
            class="cv-sub px-4 py-3 mt-6 text-sm text-n-slate-11 leading-relaxed"
          >
            De cada <b class="text-n-slate-12">100 visitas</b>,
            <b class="text-n-slate-12">{{ per100('cta') }}</b> clicam no
            WhatsApp, <b class="text-n-slate-12">{{ per100('leads') }}</b>
            viram lead na caixa e
            <b class="text-n-slate-12">{{ per100('booked') }}</b> agendam
            consulta.
            <template v-if="biggestLeak">
              O ponto mais apertado está entre
              <b class="text-n-slate-12">{{ biggestLeak.from }}</b> e
              <b class="text-n-slate-12">{{ biggestLeak.to }}</b
              >: só {{ fmtRate(biggestLeak.rate) }} passam.
            </template>
          </p>

          <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mt-6">
            <DashKpi
              compact
              glass
              label="Clicam no WhatsApp"
              :value="pct(totals.cta, totals.views)"
              :sub="`${fmtNum(totals.cta)} cliques ÷ ${fmtNum(totals.views)} visitas${rateDelta(totals.cta, totals.views, previous?.cta, previous?.views)}`"
              :grad="blockFamily('funil')[0]"
            />
            <DashKpi
              compact
              glass
              label="Chegam na caixa"
              :value="pct(totals.leads, totals.cta)"
              :sub="`${fmtNum(totals.leads)} leads ÷ ${fmtNum(totals.cta)} cliques${rateDelta(totals.leads, totals.cta, previous?.leads, previous?.cta)}`"
              :grad="blockFamily('funil')[1]"
            />
            <DashKpi
              compact
              glass
              label="Agendam consulta"
              :value="pct(totals.booked, totals.leads)"
              :sub="`${fmtNum(totals.booked)} agendaram ÷ ${fmtNum(totals.leads)} leads${rateDelta(totals.booked, totals.leads, previous?.booked, previous?.leads)}`"
              :grad="blockFamily('funil')[2]"
            />
            <DashKpi
              compact
              glass
              label="Chegam à cirurgia"
              :value="pct(totals.conversions, totals.leads)"
              :sub="`${fmtNum(totals.conversions)} cirurgias ÷ ${fmtNum(totals.leads)} leads · receita ${fmtMoney(totals.revenue)}`"
              :grad="blockFamily('funil')[3] || blockFamily('funil')[0]"
            />
          </div>
          <p class="text-[11px] text-n-slate-9 mt-4 leading-relaxed">
            Visitas no período: <b>{{ fmtNum(totals.views) }}</b
            >{{ delta(totals.views, previous?.views) }}. Lead = paciente que
            chegou na caixa com o Protocolo da página ({{
              data.protocol.matched
            }}
            de {{ data.protocol.minted }} Protocolos gerados no clique chegaram;
            quem apaga o código do texto não entra na conta). Agendaram e
            cirurgias são dos leads do período e sobem com o tempo.
          </p>
        </div>

        <!-- ══ 2 · EVOLUÇÃO ══ -->
        <div class="cv-block p-6 sm:p-8 mb-8" :style="blockVars('evolucao')">
          <div class="flex items-center gap-3 mb-1 flex-wrap">
            <span class="cv-icon"
              ><span class="i-lucide-activity text-base"
            /></span>
            <h2
              class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
            >
              Evolução
            </h2>
            <div
              class="cv-seg cv-seg-sm inline-flex items-center gap-0.5 sm:ml-auto max-w-full min-w-0 flex-nowrap overflow-x-auto"
            >
              <button
                v-for="[key, label] in visibleChartModes"
                :key="key"
                class="cv-seg-item text-xs font-medium whitespace-nowrap flex-shrink-0"
                :class="chartMode === key ? 'cv-seg-on' : ''"
                @click="chartMode = key"
              >
                {{ label }}
              </button>
            </div>
          </div>
          <p class="text-xs text-n-slate-10 mb-5">
            {{ GRAIN_LABEL[series?.granularity] || 'por dia' }} ·
            {{
              chartMode === 'taxas'
                ? 'de cada 100 visitas do dia, quantas clicaram e quantas viraram lead'
                : chartMode === 'origens'
                  ? 'de onde vieram as visitas ao longo do período'
                  : 'como as visitas, os cliques e os leads se formaram'
            }}
          </p>
          <AreaChart
            v-if="chartSeries.length && totals.views"
            :series="chartSeries"
            :labels="series.labels"
            :height="220"
            :format="chartFormat"
            :axis-width="chartMode === 'taxas' ? 44 : 34"
            :legend="chartMode !== 'taxas'"
          />
          <!-- nas taxas a legenda do gráfico somaria percentuais: aqui vai a taxa do período -->
          <div
            v-if="chartMode === 'taxas' && totals.views"
            class="flex items-center gap-5 flex-wrap mt-3 text-xs text-n-slate-11"
          >
            <span class="inline-flex items-center gap-1.5">
              <span
                class="w-2.5 h-2.5 rounded-full"
                :style="{ background: STEP_COLORS.cta }"
              />
              Clicam no WhatsApp ·
              <b class="text-n-slate-12">{{ pct(totals.cta, totals.views) }}</b>
              no período
            </span>
            <span class="inline-flex items-center gap-1.5">
              <span
                class="w-2.5 h-2.5 rounded-full"
                :style="{ background: STEP_COLORS.leads }"
              />
              Viram lead ·
              <b class="text-n-slate-12">{{
                pct(totals.leads, totals.views)
              }}</b>
              no período
            </span>
          </div>
          <p v-else class="text-sm text-n-slate-10 py-8 text-center">
            Sem visitas neste recorte ainda.
          </p>
        </div>

        <!-- ══ 3 · ORIGENS ══ -->
        <div class="cv-block p-6 sm:p-8 mb-8" :style="blockVars('origens')">
          <div class="flex items-center gap-3 mb-1 flex-wrap">
            <span class="cv-icon"
              ><span class="i-lucide-git-fork text-base"
            /></span>
            <h2
              class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
            >
              Origens
            </h2>
            <div class="flex items-center gap-1 ml-auto">
              <button
                class="cv-btn cv-btn-sm"
                :class="sourcesView === 'cards' ? '' : 'cv-btn-ghost'"
                @click="sourcesView = 'cards'"
              >
                <span class="i-lucide-layout-grid text-xs" /> Cards
              </button>
              <button
                class="cv-btn cv-btn-sm"
                :class="sourcesView === 'list' ? '' : 'cv-btn-ghost'"
                @click="sourcesView = 'list'"
              >
                <span class="i-lucide-list text-xs" /> Lista
              </button>
            </div>
          </div>
          <p class="text-xs text-n-slate-10 mb-5">
            qual porta traz gente que clica, conversa e agenda · toque numa
            origem para ver o funil só dela
          </p>

          <p
            v-if="!sourceRows.length"
            class="text-sm text-n-slate-10 py-6 text-center"
          >
            Nenhuma visita no período.
          </p>
          <div
            v-else-if="sourcesView === 'cards'"
            class="grid gap-4 grid-cols-[repeat(auto-fit,minmax(230px,1fr))]"
          >
            <button
              v-for="s in sourceRows"
              :key="s.src"
              class="cv-sub cv-sub-hover p-5 text-left"
              :class="sourceFilter === s.src ? 'cv-sub-on' : ''"
              @click="sourceFilter = sourceFilter === s.src ? '' : s.src"
            >
              <div class="flex items-center gap-2 mb-3">
                <span
                  class="w-8 h-8 rounded-xl inline-flex items-center justify-center text-white flex-shrink-0"
                  :style="{ background: s.meta.color }"
                >
                  <span :class="s.meta.icon" class="text-sm" />
                </span>
                <p class="text-sm font-bold text-n-slate-12 leading-tight">
                  {{ s.label }}
                </p>
              </div>
              <p
                class="text-3xl font-extrabold tracking-tight text-n-slate-12 whitespace-nowrap"
              >
                {{ fmtNum(s.views) }}
                <span class="text-xs font-medium text-n-slate-10">
                  visitas · {{ fmtRate(s.share) }} do total
                </span>
              </p>
              <div class="grid grid-cols-3 gap-2 mt-4 text-center">
                <div>
                  <p
                    class="text-base font-bold"
                    :style="{ color: STEP_COLORS.cta }"
                  >
                    {{ pct(s.cta, s.views) }}
                  </p>
                  <p class="text-[10px] text-n-slate-10 leading-tight">
                    clicam
                  </p>
                </div>
                <div>
                  <p
                    class="text-base font-bold"
                    :style="{ color: STEP_COLORS.leads }"
                  >
                    {{ pct(s.leads, s.views) }}
                  </p>
                  <p class="text-[10px] text-n-slate-10 leading-tight">
                    viram lead
                  </p>
                </div>
                <div>
                  <p
                    class="text-base font-bold"
                    :style="{ color: STEP_COLORS.booked }"
                  >
                    {{ pct(s.booked, s.leads) }}
                  </p>
                  <p class="text-[10px] text-n-slate-10 leading-tight">
                    dos leads agendam
                  </p>
                </div>
              </div>
              <p class="text-[11px] text-n-slate-10 mt-3">
                {{ fmtNum(s.cta) }} cliques · {{ fmtNum(s.leads) }} leads ·
                {{ fmtNum(s.booked) }} agendaram ·
                {{ fmtNum(s.conversions) }} cirurgias
              </p>
            </button>
          </div>
          <div v-else class="overflow-x-auto">
            <table class="w-full text-xs">
              <thead>
                <tr
                  class="text-left text-[10px] uppercase tracking-wide text-n-slate-10"
                >
                  <th class="py-2 pr-3">Origem</th>
                  <th class="py-2 px-2 text-right">Visitas</th>
                  <th class="py-2 px-2 text-right">Clicam</th>
                  <th class="py-2 px-2 text-right">Viram lead</th>
                  <th class="py-2 px-2 text-right">Leads</th>
                  <th class="py-2 px-2 text-right">Agendaram</th>
                  <th class="py-2 px-2 text-right">Cirurgias</th>
                  <th class="py-2 pl-2 text-right">Receita</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="s in sourceRows"
                  :key="s.src"
                  class="border-t border-n-weak cursor-pointer hover:bg-n-alpha-1"
                  @click="sourceFilter = sourceFilter === s.src ? '' : s.src"
                >
                  <td class="py-2.5 pr-3 font-semibold text-n-slate-12">
                    <span
                      class="inline-block w-2.5 h-2.5 rounded-full mr-1.5 align-middle"
                      :style="{ background: s.meta.color }"
                    />{{ s.label }}
                  </td>
                  <td class="py-2.5 px-2 text-right tabular-nums">
                    {{ fmtNum(s.views) }}
                  </td>
                  <td class="py-2.5 px-2 text-right tabular-nums">
                    {{ pct(s.cta, s.views) }}
                  </td>
                  <td class="py-2.5 px-2 text-right tabular-nums">
                    {{ pct(s.leads, s.views) }}
                  </td>
                  <td class="py-2.5 px-2 text-right tabular-nums">
                    {{ fmtNum(s.leads) }}
                  </td>
                  <td class="py-2.5 px-2 text-right tabular-nums">
                    {{ fmtNum(s.booked) }}
                  </td>
                  <td class="py-2.5 px-2 text-right tabular-nums">
                    {{ fmtNum(s.conversions) }}
                  </td>
                  <td
                    class="py-2.5 pl-2 text-right tabular-nums whitespace-nowrap"
                  >
                    {{ fmtMoney(s.revenue) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <!-- ══ 4 · PÁGINAS ══ -->
        <div class="cv-block p-6 sm:p-8 mb-8" :style="blockVars('paginas')">
          <div class="flex items-center gap-3 mb-1 flex-wrap">
            <span class="cv-icon">
              <span class="i-lucide-layout-template text-base" />
            </span>
            <h2
              class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
            >
              Páginas
            </h2>
            <div class="flex items-center gap-1 ml-auto">
              <button
                class="cv-btn cv-btn-sm"
                :class="pagesView === 'list' ? '' : 'cv-btn-ghost'"
                @click="pagesView = 'list'"
              >
                <span class="i-lucide-list text-xs" /> Lista
              </button>
              <button
                class="cv-btn cv-btn-sm"
                :class="pagesView === 'cards' ? '' : 'cv-btn-ghost'"
                @click="pagesView = 'cards'"
              >
                <span class="i-lucide-layout-grid text-xs" /> Cards
              </button>
            </div>
          </div>
          <p class="text-xs text-n-slate-10 mb-5">
            cada página com as taxas dela · a lâmpada mostra quantos pontos a
            melhorar o sistema achou
          </p>

          <p
            v-if="!visibleRows.length"
            class="text-sm text-n-slate-10 py-6 text-center"
          >
            Nenhum movimento neste recorte ainda. Assim que as páginas receberem
            visitas (anúncio, Google ou funil), os números aparecem aqui.
          </p>

          <!-- LISTA -->
          <div v-else-if="pagesView === 'list'" class="space-y-3">
            <div
              v-for="{ page, data: d } in visibleRows"
              :key="rowKey(page)"
              class="cv-sub overflow-hidden"
            >
              <div class="flex items-center gap-3 p-4 flex-wrap">
                <button
                  class="flex items-center gap-3 min-w-0 flex-1 text-left"
                  @click="
                    expandedId =
                      expandedId === rowKey(page) ? null : rowKey(page)
                  "
                >
                  <span class="text-2xl flex-shrink-0">{{
                    page.emoji || '📄'
                  }}</span>
                  <span class="min-w-0">
                    <span
                      class="block text-sm font-bold text-n-slate-12 leading-snug"
                    >
                      {{ page.title }}
                    </span>
                    <span class="block text-[11px] text-n-slate-10">
                      {{ page.page_id ? `/${page.slug}` : 'raiz do domínio' }}
                      <template v-if="page.status !== 'published'">
                        · rascunho</template
                      >
                      <template v-if="page.ab_running">
                        · teste A/B rodando</template
                      >
                    </span>
                  </span>
                </button>
                <svg
                  v-if="sparkPath(page)"
                  viewBox="0 0 100 28"
                  preserveAspectRatio="none"
                  class="w-24 h-7 flex-shrink-0 hidden md:block"
                >
                  <path
                    :d="sparkPath(page)"
                    fill="none"
                    :stroke="STEP_COLORS.views"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    vector-effect="non-scaling-stroke"
                  />
                </svg>
                <div class="flex items-center gap-5 flex-shrink-0 text-right">
                  <div>
                    <p class="text-base font-bold text-n-slate-12 tabular-nums">
                      {{ fmtNum(d.views) }}
                    </p>
                    <p class="text-[10px] text-n-slate-10">visitas</p>
                  </div>
                  <div>
                    <p
                      class="text-base font-bold tabular-nums"
                      :style="{ color: STEP_COLORS.cta }"
                    >
                      {{ pct(d.cta, d.views) }}
                    </p>
                    <p class="text-[10px] text-n-slate-10">clicam</p>
                  </div>
                  <div>
                    <p
                      class="text-base font-bold tabular-nums"
                      :style="{ color: STEP_COLORS.leads }"
                    >
                      {{ fmtNum(d.leads) }}
                    </p>
                    <p class="text-[10px] text-n-slate-10">
                      leads · {{ pct(d.leads, d.views) }}
                    </p>
                  </div>
                  <div class="hidden sm:block">
                    <p
                      class="text-base font-bold tabular-nums"
                      :style="{ color: STEP_COLORS.booked }"
                    >
                      {{ fmtNum(d.booked) }}
                    </p>
                    <p class="text-[10px] text-n-slate-10">agendaram</p>
                  </div>
                  <div class="hidden md:block">
                    <p
                      class="text-base font-bold tabular-nums"
                      :style="{ color: STEP_COLORS.conversions }"
                    >
                      {{ fmtNum(d.conversions) }}
                    </p>
                    <p class="text-[10px] text-n-slate-10">cirurgias</p>
                  </div>
                </div>
                <button
                  v-if="page.page_id && insightsOfPage(page.page_id).length"
                  class="cv-chip cv-amber flex-shrink-0"
                  title="Ver o que melhorar nesta página"
                  @click="openOptimize(page.page_id)"
                >
                  <span class="i-lucide-lightbulb text-xs" />
                  {{ insightsOfPage(page.page_id).length }}
                </button>
              </div>

              <!-- detalhe: leitura, origens e campanhas da página -->
              <div
                v-if="expandedId === rowKey(page)"
                class="border-t border-n-weak px-4 py-4 space-y-4"
              >
                <p v-if="readingOf(page, d)" class="text-xs text-n-slate-11">
                  <span class="i-lucide-book-open text-xs align-middle mr-1" />
                  Até onde leram — {{ readingOf(page, d) }}
                </p>
                <div>
                  <p class="text-[11px] font-semibold text-n-slate-12 mb-2">
                    Por origem
                  </p>
                  <div class="flex gap-2 flex-wrap">
                    <span
                      v-for="[src, b] in sourcesOf(page)"
                      :key="src"
                      class="cv-chip"
                    >
                      <span
                        class="w-2 h-2 rounded-full"
                        :style="{
                          background: SOURCE_META[src]?.color || '#64748B',
                        }"
                      />
                      {{ sourceLabel(src) }}: {{ fmtNum(b.views) }} visitas ·
                      {{ pct(b.cta, b.views) }} clicam ·
                      {{ fmtNum(b.leads) }} leads
                    </span>
                  </div>
                </div>
                <div>
                  <p class="text-[11px] font-semibold text-n-slate-12 mb-2">
                    Por campanha
                  </p>
                  <div
                    v-if="campaignsOf(page).length"
                    class="flex gap-2 flex-wrap"
                  >
                    <span
                      v-for="[name, b] in campaignsOf(page)"
                      :key="name"
                      class="cv-chip"
                    >
                      {{ name }}: {{ fmtNum(b.views) }} visitas ·
                      {{ fmtNum(b.leads) }} leads
                      <template v-if="b.revenue">
                        · {{ fmtMoney(b.revenue) }}
                      </template>
                    </span>
                  </div>
                  <p v-else class="text-[11px] text-n-slate-9">
                    Sem campanhas nomeadas ainda — use utm_campaign nos anúncios
                    para ver a quebra aqui.
                  </p>
                </div>
                <div v-if="page.page_id" class="flex gap-2 flex-wrap">
                  <button
                    class="cv-btn cv-btn-sm"
                    @click="openOptimize(page.page_id)"
                  >
                    <span class="i-lucide-lightbulb text-xs" /> Otimizar esta
                    página
                  </button>
                  <button
                    class="cv-btn cv-btn-sm cv-btn-ghost"
                    @click="openPublic(page.page_id)"
                  >
                    <span class="i-lucide-external-link text-xs" /> Ver a página
                  </button>
                </div>
              </div>
            </div>
          </div>

          <!-- CARDS -->
          <div
            v-else
            class="grid gap-4 grid-cols-[repeat(auto-fit,minmax(260px,1fr))]"
          >
            <div
              v-for="{ page, data: d } in visibleRows"
              :key="rowKey(page)"
              class="cv-sub p-5 flex flex-col"
            >
              <div class="flex items-start gap-3 mb-4">
                <span class="text-2xl flex-shrink-0">{{
                  page.emoji || '📄'
                }}</span>
                <div class="min-w-0 flex-1">
                  <p class="text-sm font-bold text-n-slate-12 leading-snug">
                    {{ page.title }}
                  </p>
                  <p class="text-[11px] text-n-slate-10">
                    {{ page.page_id ? `/${page.slug}` : 'raiz do domínio' }}
                  </p>
                </div>
              </div>
              <p
                class="text-3xl font-extrabold tracking-tight text-n-slate-12 whitespace-nowrap"
              >
                {{ fmtNum(d.views) }}
                <span class="text-xs font-medium text-n-slate-10">visitas</span>
              </p>
              <svg
                v-if="sparkPath(page)"
                viewBox="0 0 100 28"
                preserveAspectRatio="none"
                class="w-full h-8 mt-2"
              >
                <path
                  :d="sparkPath(page)"
                  fill="none"
                  :stroke="STEP_COLORS.views"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  vector-effect="non-scaling-stroke"
                />
              </svg>
              <div class="grid grid-cols-3 gap-2 mt-4 text-center">
                <div>
                  <p
                    class="text-base font-bold"
                    :style="{ color: STEP_COLORS.cta }"
                  >
                    {{ pct(d.cta, d.views) }}
                  </p>
                  <p class="text-[10px] text-n-slate-10 leading-tight">
                    clicam
                  </p>
                </div>
                <div>
                  <p
                    class="text-base font-bold"
                    :style="{ color: STEP_COLORS.leads }"
                  >
                    {{ pct(d.leads, d.views) }}
                  </p>
                  <p class="text-[10px] text-n-slate-10 leading-tight">
                    viram lead
                  </p>
                </div>
                <div>
                  <p
                    class="text-base font-bold"
                    :style="{ color: STEP_COLORS.booked }"
                  >
                    {{ pct(d.booked, d.leads) }}
                  </p>
                  <p class="text-[10px] text-n-slate-10 leading-tight">
                    dos leads agendam
                  </p>
                </div>
              </div>
              <p class="text-[11px] text-n-slate-10 mt-3 flex-1">
                {{ fmtNum(d.cta) }} cliques · {{ fmtNum(d.leads) }} leads ·
                {{ fmtNum(d.booked) }} agendaram ·
                {{ fmtNum(d.conversions) }} cirurgias
                <template v-if="d.revenue">
                  · {{ fmtMoney(d.revenue) }}</template
                >
                <template v-if="readingOf(page, d)">
                  <br />{{ readingOf(page, d) }}
                </template>
              </p>
              <button
                v-if="page.page_id"
                class="cv-btn cv-btn-sm mt-4 self-start"
                @click="openOptimize(page.page_id)"
              >
                <span class="i-lucide-lightbulb text-xs" />
                {{
                  insightsOfPage(page.page_id).length
                    ? `${insightsOfPage(page.page_id).length} ponto(s) a melhorar`
                    : 'Otimizar'
                }}
              </button>
            </div>
          </div>
        </div>
      </template>

      <!-- ════════════════ ABA OTIMIZAR ════════════════ -->
      <template v-else>
        <!-- ══ 1 · DIAGNÓSTICOS ══ -->
        <div
          class="cv-block p-6 sm:p-8 mb-8"
          :style="blockVars('diagnosticos')"
        >
          <div class="flex items-center gap-3 mb-1 flex-wrap">
            <span class="cv-icon"
              ><span class="i-lucide-lightbulb text-base"
            /></span>
            <h2
              class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
            >
              Diagnósticos
            </h2>
          </div>
          <p class="text-xs text-n-slate-10 mb-5 leading-relaxed">
            o sistema lê os números de {{ dateBR(data.since) }} a
            {{ dateBR(data.until) }} e aponta onde cada página perde gente e o
            que fazer · a comparação é com a média das suas próprias páginas, e
            só aparece quando há visita suficiente para não ser acaso
          </p>

          <div class="flex items-center gap-1.5 flex-wrap mb-3">
            <button
              v-for="[key, label] in INSIGHT_FILTERS"
              :key="key"
              class="cv-chip"
              :class="insightFilter === key ? 'cv-chip-on' : ''"
              @click="insightFilter = key"
            >
              {{ label }} <b>{{ countFor(key) }}</b>
            </button>
          </div>
          <div class="flex items-center gap-1.5 flex-wrap mb-6">
            <span class="text-[11px] text-n-slate-10 mr-1">Página</span>
            <button
              class="cv-chip"
              :class="insightPage === '' ? 'cv-chip-on' : ''"
              @click="insightPage = ''"
            >
              Todas
            </button>
            <button
              v-for="p in pagesWithInsights"
              :key="p.id"
              class="cv-chip"
              :class="insightPage === p.id ? 'cv-chip-on' : ''"
              @click="insightPage = insightPage === p.id ? '' : p.id"
            >
              {{ p.emoji || '📄' }} {{ p.title }}
            </button>
          </div>

          <p
            v-if="!visibleInsights.length"
            class="text-sm text-n-slate-10 py-8 text-center"
          >
            Nada a apontar neste recorte. Com mais visitas no período, os
            diagnósticos do funil aparecem aqui.
          </p>
          <div
            v-else
            class="grid gap-4 grid-cols-[repeat(auto-fit,minmax(300px,1fr))]"
          >
            <div
              v-for="i in visibleInsights"
              :key="i.key"
              class="cv-sub p-5 flex flex-col"
            >
              <div class="flex items-center gap-2 flex-wrap mb-3">
                <span class="cv-chip" :class="LEVELS[i.level].chip">
                  <span :class="LEVELS[i.level].icon" class="text-xs" />
                  {{ LEVELS[i.level].label }}
                </span>
                <span class="text-[11px] text-n-slate-10">
                  {{ i.emoji || '📄' }} {{ i.page_title }}
                </span>
              </div>
              <p class="text-base font-bold text-n-slate-12 leading-snug mb-2">
                {{ i.title }}
              </p>
              <p class="text-xs text-n-slate-11 leading-relaxed mb-3">
                {{ i.evidence }}
              </p>
              <p class="text-xs text-n-slate-12 leading-relaxed flex-1">
                <b>O que fazer:</b> {{ i.suggestion }}
              </p>
              <p v-if="i.gain" class="cv-chip cv-green mt-3 self-start">
                <span class="i-lucide-trending-up text-xs" /> {{ i.gain }}
              </p>
              <div class="flex gap-2 flex-wrap mt-4">
                <button
                  v-if="savedKeys.has(i.key)"
                  class="cv-btn cv-btn-sm cv-btn-ghost"
                  disabled
                >
                  <span class="i-lucide-check text-xs" /> Na coleção
                </button>
                <button
                  v-else
                  class="cv-btn cv-btn-sm"
                  :disabled="isSaving"
                  @click="keepInsight(i)"
                >
                  <span class="i-lucide-bookmark-plus text-xs" /> Guardar
                </button>
                <button
                  class="cv-btn cv-btn-sm cv-btn-ghost"
                  title="Copia o que fazer e abre o ambiente de montagem da página"
                  @click="openBuilder(i.page_id, i.suggestion)"
                >
                  <span class="i-lucide-wand-sparkles text-xs" /> Aplicar na
                  montagem
                </button>
                <button
                  class="cv-btn cv-btn-sm cv-btn-ghost"
                  @click="openPublic(i.page_id)"
                >
                  <span class="i-lucide-external-link text-xs" /> Ver
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- ══ 2 · SUGESTÕES DA IA ══ -->
        <div class="cv-block p-6 sm:p-8 mb-8" :style="blockVars('ia')">
          <div class="flex items-center gap-3 mb-1 flex-wrap">
            <span class="cv-icon"
              ><span class="i-lucide-sparkles text-base"
            /></span>
            <h2
              class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
            >
              Sugestões da IA
            </h2>
          </div>
          <p class="text-xs text-n-slate-10 mb-5 leading-relaxed">
            a IA lê os textos da página como estão no ar, junto com os números
            do período, e devolve mudanças concretas com o pedido pronto para a
            montagem · só roda quando você pede (usa o Construtor de Páginas) e
            nada muda na página sozinho
          </p>
          <div class="flex items-center gap-2 flex-wrap">
            <select
              v-model="aiPageId"
              class="cv-input !h-9 text-xs max-w-full sm:!w-80"
            >
              <option value="">Escolha a página…</option>
              <option v-for="p in pages" :key="p.id" :value="p.id">
                {{ p.emoji || '📄' }} {{ p.title }}
              </option>
            </select>
            <button
              class="cv-btn"
              :disabled="!aiPageId || aiLoading"
              @click="askAi"
            >
              <span
                :class="
                  aiLoading
                    ? 'i-lucide-loader-circle animate-spin'
                    : 'i-lucide-sparkles'
                "
                class="text-sm"
              />
              {{ aiLoading ? 'Lendo a página…' : 'Pedir sugestões' }}
            </button>
          </div>

          <div v-if="aiResult" class="mt-6">
            <p
              class="cv-sub px-4 py-3 text-sm text-n-slate-12 leading-relaxed mb-4"
            >
              {{ aiResult.diagnostico }}
            </p>
            <div
              class="grid gap-4 grid-cols-[repeat(auto-fit,minmax(300px,1fr))]"
            >
              <div
                v-for="(sug, si) in aiResult.sugestoes"
                :key="si"
                class="cv-sub p-5 flex flex-col"
              >
                <p
                  class="text-base font-bold text-n-slate-12 leading-snug mb-2"
                >
                  {{ si + 1 }}. {{ sug.titulo }}
                </p>
                <p class="text-xs text-n-slate-11 leading-relaxed mb-3">
                  {{ sug.por_que }}
                </p>
                <p class="text-xs text-n-slate-12 leading-relaxed flex-1">
                  <b>Pedido para a montagem:</b> {{ sug.pedido }}
                </p>
                <div class="flex gap-2 flex-wrap mt-4">
                  <button
                    class="cv-btn cv-btn-sm"
                    :disabled="isSaving"
                    @click="keepAi(sug)"
                  >
                    <span class="i-lucide-bookmark-plus text-xs" /> Guardar
                  </button>
                  <button
                    class="cv-btn cv-btn-sm cv-btn-ghost"
                    @click="openBuilder(aiPageId, sug.pedido)"
                  >
                    <span class="i-lucide-wand-sparkles text-xs" /> Aplicar na
                    montagem
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- ══ 3 · COLEÇÃO DE INSIGHTS ══ -->
        <div class="cv-block p-6 sm:p-8 mb-8" :style="blockVars('colecao')">
          <div class="flex items-center gap-3 mb-1 flex-wrap">
            <span class="cv-icon"
              ><span class="i-lucide-bookmark text-base"
            /></span>
            <h2
              class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
            >
              Coleção de insights
            </h2>
            <div
              class="cv-seg cv-seg-sm inline-flex items-center gap-0.5 sm:ml-auto max-w-full min-w-0 flex-nowrap overflow-x-auto"
            >
              <button
                v-for="[key, label] in COLLECTION_TABS"
                :key="key"
                class="cv-seg-item text-xs font-medium whitespace-nowrap flex-shrink-0"
                :class="collectionTab === key ? 'cv-seg-on' : ''"
                @click="collectionTab = key"
              >
                {{ label }} <b class="ml-1">{{ collectionCount(key) }}</b>
              </button>
            </div>
          </div>
          <p class="text-xs text-n-slate-10 mb-5 leading-relaxed">
            o que a equipe decidiu fazer para melhorar as páginas · ao marcar
            como aplicado, o sistema guarda a data e passa a comparar a página
            antes × depois da mudança
          </p>

          <!-- escrever um insight à mão -->
          <div class="cv-sub p-5 mb-5">
            <p class="text-xs font-semibold text-n-slate-12 mb-3">
              Anotar um insight da equipe
            </p>
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-2 mb-2">
              <input
                v-model="draft.title"
                class="cv-input !h-9 text-xs sm:col-span-2"
                placeholder="ex.: Pacientes perguntam do preço logo na primeira mensagem"
                maxlength="160"
              />
              <select v-model="draft.page_id" class="cv-input !h-9 text-xs">
                <option value="">Vale para todas as páginas</option>
                <option v-for="p in pages" :key="p.id" :value="p.id">
                  {{ p.emoji || '📄' }} {{ p.title }}
                </option>
              </select>
            </div>
            <textarea
              v-model="draft.text"
              class="cv-input text-xs !h-auto py-2"
              rows="2"
              placeholder="o que você viu e o que quer testar (opcional)"
              maxlength="2000"
            />
            <button
              class="cv-btn cv-btn-sm mt-3"
              :disabled="isSaving"
              @click="saveDraft"
            >
              <span class="i-lucide-plus text-xs" /> Guardar na coleção
            </button>
          </div>

          <p
            v-if="!visibleCollection.length"
            class="text-sm text-n-slate-10 py-6 text-center"
          >
            {{
              collectionTab === 'todo'
                ? 'Nada a fazer guardado ainda. Guarde um diagnóstico, uma sugestão da IA ou anote o seu.'
                : 'Nada aqui ainda.'
            }}
          </p>
          <div v-else class="space-y-3">
            <div
              v-for="item in visibleCollection"
              :key="item.id"
              class="cv-sub p-5"
            >
              <div class="flex items-center gap-2 flex-wrap mb-2">
                <span class="cv-chip">{{
                  ORIGIN_LABEL[item.origin] || item.origin
                }}</span>
                <span
                  v-if="item.page_id && pageById(item.page_id)"
                  class="text-[11px] text-n-slate-10"
                >
                  {{ pageById(item.page_id).emoji || '📄' }}
                  {{ pageById(item.page_id).title }}
                </span>
                <span class="text-[11px] text-n-slate-9 ml-auto">
                  {{ item.created_by }} · {{ dateBR(item.created_at) }}
                  <template v-if="item.applied_at">
                    · aplicado em {{ dateBR(item.applied_at) }}
                  </template>
                </span>
              </div>
              <p class="text-sm font-bold text-n-slate-12 leading-snug">
                {{ item.title }}
              </p>
              <p
                v-if="item.text"
                class="text-xs text-n-slate-11 leading-relaxed mt-1 whitespace-pre-line"
              >
                {{ item.text }}
              </p>
              <!-- antes × depois -->
              <div
                v-if="item.result"
                class="cv-strip mt-3 text-xs text-n-slate-12"
              >
                <b
                  >Antes × depois ({{ item.result.days }} dia(s) de cada
                  lado):</b
                >
                {{ resultLine(item) }}
                <span v-if="item.result.early" class="cv-chip cv-amber ml-1">
                  ainda cedo: pouca visita para concluir
                </span>
              </div>
              <div class="flex gap-2 flex-wrap mt-4">
                <button
                  v-if="item.status !== 'done'"
                  class="cv-btn cv-btn-sm"
                  :disabled="isSaving"
                  @click="setStatus(item, 'done')"
                >
                  <span class="i-lucide-check text-xs" /> Marcar como aplicado
                </button>
                <button
                  v-if="item.status !== 'todo'"
                  class="cv-btn cv-btn-sm cv-btn-ghost"
                  :disabled="isSaving"
                  @click="setStatus(item, 'todo')"
                >
                  Voltar para a fazer
                </button>
                <button
                  v-if="item.status === 'todo' && item.page_id"
                  class="cv-btn cv-btn-sm cv-btn-ghost"
                  @click="openBuilder(item.page_id, item.text || item.title)"
                >
                  <span class="i-lucide-wand-sparkles text-xs" /> Aplicar na
                  montagem
                </button>
                <button
                  v-if="item.status === 'todo'"
                  class="cv-btn cv-btn-sm cv-btn-ghost"
                  :disabled="isSaving"
                  @click="setStatus(item, 'dismissed')"
                >
                  Descartar
                </button>
                <button
                  v-if="item.status === 'dismissed'"
                  class="cv-btn cv-btn-sm cv-btn-ghost"
                  @click="removeInsight(item)"
                >
                  <span class="i-lucide-trash-2 text-xs" /> Apagar
                </button>
              </div>
            </div>
          </div>
        </div>
      </template>
    </template>
  </div>
</template>
