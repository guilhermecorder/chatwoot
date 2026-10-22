<script setup>
// 📄 A FICHA de UMA página (19/10/2026 — "os dashboards e indicadores precisam
// ser fáceis de acessar por página… indicadores, gráfico, histórico, números
// reais… mais visual e expansível"). Abre em cima da lista quando a pessoa
// toca numa página, na gramática Apple da história: uma ideia por seção, um
// número herói com a frase que diz o que ele significa, e abaixo os blocos
// densos (caminho, histórico, placar, origens, Google, o que melhorar).
// Tudo reaproveita o que já existe: linha do TrafficReport (números reais do
// período e do período anterior), placar do Agente de Páginas, linha do tempo
// por dia (page_agent/timeline) e os diagnósticos (PageInsights).
import { ref, computed, watch, onMounted } from 'vue';
import CrmAPI from 'dashboard/api/crm';
import TimelineChart from 'dashboard/components-next/cevico/TimelineChart.vue';
import FunnelSteps from 'dashboard/components-next/cevico/FunnelSteps.vue';
import ScoreRadar from 'dashboard/components-next/cevico/creatives/ScoreRadar.vue';
import DonutChart from 'dashboard/components-next/cevico/DonutChart.vue';

const props = defineProps({
  page: { type: Object, required: true },
  previous: { type: Object, default: null },
  scorecard: { type: Object, default: null },
  insights: { type: Array, default: () => [] },
  periodoTxt: { type: String, default: '' },
  sourceLabels: { type: Object, default: () => ({}) },
  gscReady: { type: Boolean, default: false },
  categoryLabel: { type: String, default: '' },
  color: { type: String, default: '#2563eb' },
});
const emit = defineEmits(['close', 'otimizar']);

// ── formatação ──
const n = v => Number(v || 0).toLocaleString('pt-BR');
const brl = v =>
  `R$ ${Number(v || 0).toLocaleString('pt-BR', { maximumFractionDigits: 0 })}`;
const pct = (a, b) => (Number(b) > 0 ? Number(a) / Number(b) : null);
const pctTxt = v =>
  v === null || v === undefined
    ? '—'
    : `${(v * 100).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`;
const fmtPos = v =>
  v ? Number(v).toLocaleString('pt-BR', { maximumFractionDigits: 1 }) : '—';
const abrirUrl = url => url && window.open(url, '_blank', 'noopener');

const isHub = computed(() => props.page.id === 'hub');
const p = computed(() => props.page);
const prev = computed(() => props.previous || null);

// ── 1 · os números reais, com o período anterior ao lado ──
const delta = (now, before) => {
  if (!prev.value || before === undefined || before === null) return null;
  if (!before) return now ? { txt: 'novo', up: true } : null;
  const d = (now - before) / before;
  return {
    txt: `${d > 0 ? '+' : ''}${(d * 100).toLocaleString('pt-BR', { maximumFractionDigits: 0 })}%`,
    up: d >= 0,
  };
};
const tiles = computed(() => {
  const r = p.value;
  const b = prev.value || {};
  return [
    {
      key: 'views',
      label: 'visitas',
      value: n(r.views),
      delta: delta(r.views, b.views),
      rate: 'cada abertura da página com o rastreio',
    },
    {
      key: 'cta',
      label: 'tocaram no WhatsApp',
      value: n(r.cta),
      delta: delta(r.cta, b.cta),
      rate: `${pctTxt(pct(r.cta, r.views))} das visitas`,
    },
    {
      key: 'leads',
      label: 'leads na caixa',
      value: n(r.leads),
      delta: delta(r.leads, b.leads),
      rate: `${pctTxt(pct(r.leads, r.cta))} dos cliques chegaram com o Protocolo`,
    },
    {
      key: 'booked',
      label: 'marcaram consulta',
      value: n(r.booked),
      delta: delta(r.booked, b.booked),
      rate: `${pctTxt(pct(r.booked, r.leads))} dos leads`,
    },
    {
      key: 'conversions',
      label: 'fecharam cirurgia',
      value: n(r.conversions),
      delta: delta(r.conversions, b.conversions),
      rate: `${pctTxt(pct(r.conversions, r.leads))} dos leads`,
    },
    {
      key: 'revenue',
      label: 'receita',
      value: brl(r.revenue),
      delta: delta(r.revenue, b.revenue),
      rate: 'valor do card no CRM de quem fechou',
    },
  ];
});
const heroTxt = computed(() => {
  const r = p.value;
  if (!r.views && !r.leads) return 'Sem visita nem lead neste período.';
  return `De ${n(r.views)} visitas, ${n(r.cta)} tocaram no WhatsApp, ${n(r.leads)} chegaram na caixa com o Protocolo, ${n(r.booked)} marcaram consulta e ${n(r.conversions)} fecharam cirurgia.`;
});

// ── 2 · o caminho ──
const steps = computed(() => [
  { key: 'views', label: 'Visitas', value: p.value.views, color: props.color },
  { key: 'cta', label: 'WhatsApp', value: p.value.cta, color: '#0a84ff' },
  { key: 'leads', label: 'Leads', value: p.value.leads, color: '#db2777' },
  {
    key: 'booked',
    label: 'Consultas',
    value: p.value.booked,
    color: '#7c3aed',
  },
  {
    key: 'conversions',
    label: 'Cirurgias',
    value: p.value.conversions,
    color: '#059669',
  },
]);

// ── 3 · histórico (page_agent/timeline: por dia; acima de 60 dias, por semana) ──
const DAYS = [30, 90, 180, 365];
const days = ref(90);
const timeline = ref(null);
const loading = ref(false);
const load = async () => {
  if (isHub.value) return;
  loading.value = true;
  try {
    const { data } = await CrmAPI.getPageTimeline(p.value.id, days.value);
    timeline.value = data;
  } catch {
    timeline.value = null;
  } finally {
    loading.value = false;
  }
};
onMounted(load);
watch([days, () => p.value.id], load);

const weekly = computed(() => days.value > 60);
const dayLabel = iso => `${iso.slice(8, 10)}/${iso.slice(5, 7)}`;
// agrupa por semana (segunda a domingo) quando o olhar é longo
const history = computed(() => {
  const t = timeline.value;
  if (!t) return null;
  if (!weekly.value) {
    return {
      labels: t.dates.map(dayLabel),
      views: t.views,
      cta: t.cta,
      leads: t.leads,
      marks: (t.marks || []).map(m => ({ ...m })),
      ids: t.dates,
    };
  }
  const keys = [];
  const index = {};
  t.dates.forEach(iso => {
    const d = new Date(`${iso}T12:00:00`);
    d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
    const key = d.toISOString().slice(0, 10);
    if (index[key] === undefined) {
      index[key] = keys.length;
      keys.push(key);
    }
  });
  const sum = arr => {
    const out = new Array(keys.length).fill(0);
    t.dates.forEach((iso, i) => {
      const d = new Date(`${iso}T12:00:00`);
      d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
      out[index[d.toISOString().slice(0, 10)]] += Number(arr[i] || 0);
    });
    return out;
  };
  const bucketOf = i => {
    const d = new Date(`${t.dates[i]}T12:00:00`);
    d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
    return index[d.toISOString().slice(0, 10)];
  };
  return {
    labels: keys.map(dayLabel),
    views: sum(t.views),
    cta: sum(t.cta),
    leads: sum(t.leads),
    marks: (t.marks || []).map(m => ({ ...m, index: bucketOf(m.index) })),
    ids: keys,
  };
});
const historyBars = computed(() => ({
  key: 'views',
  label: 'Visitas',
  color: props.color,
  values: history.value?.views || [],
}));
const historyLines = computed(() => [
  {
    key: 'cta',
    label: 'Tocaram no WhatsApp',
    color: '#0a84ff',
    values: history.value?.cta || [],
  },
  {
    key: 'leads',
    label: 'Leads',
    color: '#db2777',
    values: history.value?.leads || [],
  },
]);
const historyTotal = computed(() => {
  const h = history.value;
  if (!h) return null;
  const s = arr => arr.reduce((a, b) => a + Number(b || 0), 0);
  return { views: s(h.views), cta: s(h.cta), leads: s(h.leads) };
});
const historyTip = i => {
  const h = history.value;
  return {
    title: `${weekly.value ? 'semana de ' : ''}${h.labels[i]}`,
    rows: [
      {
        color: props.color,
        square: true,
        label: 'Visitas',
        value: n(h.views[i]),
      },
      {
        color: '#0a84ff',
        label: 'Tocaram no WhatsApp',
        value: n(h.cta[i]),
        sub: `${pctTxt(pct(h.cta[i], h.views[i]))} das visitas`,
      },
      {
        color: '#db2777',
        label: 'Leads',
        value: n(h.leads[i]),
        sub: `${pctTxt(pct(h.leads[i], h.views[i]))} das visitas`,
      },
    ],
  };
};

// ── 4 · placar: esta página × média da casa × recorde ──
const indicators = computed(() =>
  (props.scorecard?.indicators || []).filter(i => i.value !== null)
);
const barWidth = (v, i) => {
  const top = Math.max(i.value || 0, i.avg || 0, i.record || 0) * 1.08 || 1;
  return `${Math.max(2, Math.min(100, ((Number(v) || 0) / top) * 100))}%`;
};
const TONES = { good: '#059669', even: '#b45309', bad: '#dc2626' };
const toneColor = i => TONES[i.verdict] || '#64748b';

const RADAR_LABELS = {
  mine: 'esta página',
  avg: 'média da casa',
  record: 'recorde da casa (borda)',
  isRecord: '🏆 esta página é o recorde da casa',
  recordOf: 'recorde da casa',
  none: 'a casa ainda não tem recorde aqui',
};

// ── 5 · de onde vieram ──
const sources = computed(() =>
  Object.entries(p.value.row?.sources || {})
    .map(([src, b]) => ({
      key: src,
      label: props.sourceLabels[src] || src,
      views: b.views || 0,
      cta: b.cta || 0,
      leads: b.leads || 0,
      booked: b.booked || 0,
    }))
    .sort((a, b) => b.leads - a.leads || b.views - a.views)
);
// cor fixa por origem (a mesma em toda ficha — a cor segue a origem, não o tamanho)
const SOURCE_COLORS = {
  google_ads: '#0a84ff',
  google_organico: '#30d158',
  meta_ads: '#db2777',
  social: '#f59e0b',
  outros_ads: '#7c3aed',
  funil: '#0ea5e9',
  busca: '#64748b',
  direto: '#94a3b8',
};
const sourceColor = key => SOURCE_COLORS[key] || '#94a3b8';
const donut = field =>
  sources.value.map(s => ({
    key: s.key,
    label: s.label,
    value: s[field],
    color: sourceColor(s.key),
  }));
const donutViews = computed(() => donut('views'));
const donutLeads = computed(() => donut('leads'));

// ── 6 · no Google ──
const gsc = computed(() => p.value.gsc || null);
const terms = computed(() => (gsc.value?.terms || []).slice(0, 8));

// ── 7 · o que melhorar ──
const LEVEL = { alerta: '🔴', atencao: '🟠', oportunidade: '🟢', seo: '🔎' };
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <section
    class="cv-ficha rounded-3xl border bg-white/95 dark:bg-n-solid-1/90 border-n-slate-5 dark:border-n-slate-6 shadow-[0_24px_48px_-28px_rgb(15_23_42/0.35)] p-5 sm:p-8 mb-6 min-w-0"
  >
    <!-- topo -->
    <div class="flex items-start gap-3 flex-wrap">
      <span class="text-3xl leading-none">{{ p.emoji || '📄' }}</span>
      <div class="min-w-0 flex-1">
        <p
          class="text-[11px] uppercase tracking-[0.08em] text-n-slate-10 font-semibold"
        >
          {{ categoryLabel }}
          <template v-if="p.ab_running"> · teste A/B no ar</template>
          <template v-if="p.status && p.status !== 'published'">
            · rascunho
          </template>
        </p>
        <h3
          class="text-xl sm:text-2xl font-semibold tracking-tight text-n-slate-12 leading-tight"
        >
          {{ p.title }}
        </h3>
        <p v-if="p.slug" class="text-[12px] text-n-slate-10">/{{ p.slug }}</p>
      </div>
      <div class="flex items-center gap-1.5 flex-wrap">
        <button
          v-if="p.public_url"
          type="button"
          class="cvg-btn cvg-btn--sm"
          @click="abrirUrl(p.public_url)"
        >
          <span class="i-lucide-external-link text-sm" /> Ver a página
        </button>
        <button
          v-if="p.builder_url"
          type="button"
          class="cvg-btn cvg-btn--ghost cvg-btn--sm"
          @click="abrirUrl(p.builder_url)"
        >
          <span class="i-lucide-wand-sparkles text-sm" /> Montagem
        </button>
        <button
          type="button"
          class="cvg-btn cvg-btn--ghost cvg-btn--sm"
          aria-label="Fechar a ficha"
          @click="emit('close')"
        >
          <span class="i-lucide-x text-sm" /> Fechar
        </button>
      </div>
    </div>

    <!-- 1 · resultado: o número herói e a frase -->
    <div class="mt-7">
      <p
        class="text-[11px] uppercase tracking-[0.08em] text-n-slate-10 font-semibold"
      >
        Resultado · {{ periodoTxt }}
      </p>
      <p class="cvg-numero-heroi mt-1" :style="{ color }">
        {{ n(p.leads) }}
        <span class="text-base font-medium text-n-slate-11 tracking-normal"
          >lead(s)</span
        >
      </p>
      <p class="text-[15px] leading-relaxed text-n-slate-11 max-w-3xl mt-1">
        {{ heroTxt }}
      </p>
      <div class="grid grid-cols-2 sm:grid-cols-3 xl:grid-cols-6 gap-3 mt-5">
        <div
          v-for="t in tiles"
          :key="t.key"
          class="rounded-2xl border border-n-slate-4 dark:border-n-slate-6 bg-n-slate-1/60 dark:bg-n-solid-2/60 px-4 py-3 min-w-0"
        >
          <p
            class="text-[22px] font-semibold tracking-tight text-n-slate-12 tabular-nums leading-tight"
          >
            {{ t.value }}
            <span
              v-if="t.delta"
              class="text-[11px] font-semibold ms-1 align-middle"
              :class="t.delta.up ? 'text-[#059669]' : 'text-[#dc2626]'"
              title="contra o período anterior"
            >
              {{ t.delta.txt }}
            </span>
          </p>
          <p class="text-[12px] font-medium text-n-slate-11">{{ t.label }}</p>
          <p class="text-[10.5px] text-n-slate-9 leading-snug mt-0.5">
            {{ t.rate }}
          </p>
        </div>
      </div>
      <p v-if="prev" class="text-[11px] text-n-slate-9 mt-2">
        a porcentagem ao lado de cada número compara com o período anterior de
        mesmo tamanho
      </p>
    </div>

    <!-- 2 · o caminho -->
    <div v-if="p.views || p.leads" class="mt-8">
      <p
        class="text-[11px] uppercase tracking-[0.08em] text-n-slate-10 font-semibold"
      >
        O caminho
      </p>
      <h4 class="text-lg font-semibold tracking-tight text-n-slate-12">
        Onde o funil desta página perde gente
      </h4>
      <div class="mt-3">
        <FunnelSteps :steps="steps" :height="150" start-text="das visitas" />
      </div>
    </div>

    <!-- 3 · histórico -->
    <div v-if="!isHub" class="mt-8">
      <div class="flex items-end gap-3 flex-wrap">
        <div class="min-w-0 flex-1">
          <p
            class="text-[11px] uppercase tracking-[0.08em] text-n-slate-10 font-semibold"
          >
            Histórico
          </p>
          <h4 class="text-lg font-semibold tracking-tight text-n-slate-12">
            Como a página se comportou dia a dia
          </h4>
          <p v-if="historyTotal" class="text-[12px] text-n-slate-10">
            {{ n(historyTotal.views) }} visitas ·
            {{ n(historyTotal.cta) }} toques no WhatsApp ·
            {{ n(historyTotal.leads) }} leads nos últimos {{ days }} dias
            <template v-if="weekly"> (somados por semana)</template>
          </p>
        </div>
        <div class="cvg-chave" role="group" aria-label="Janela do histórico">
          <button
            v-for="d in DAYS"
            :key="d"
            type="button"
            :class="days === d ? 'cvg-on' : ''"
            @click="days = d"
          >
            {{ d }} dias
          </button>
        </div>
      </div>
      <div class="mt-3">
        <TimelineChart
          v-if="history"
          :labels="history.labels"
          :bars="historyBars"
          :lines="historyLines"
          :marks="history.marks"
          :height="230"
          :left-width="44"
          :right-width="34"
          :tip="historyTip"
          empty-text="sem visita nesta janela"
        />
        <p v-else-if="loading" class="cvg-vazio">carregando o histórico…</p>
        <p v-else class="cvg-vazio">não consegui ler o histórico agora.</p>
        <ol
          v-if="history?.marks?.length"
          class="list-none ps-0 flex flex-wrap gap-x-4 gap-y-1 mt-2 text-[11px] text-n-slate-10"
        >
          <li
            v-for="(m, k) in history.marks"
            :key="k"
            class="inline-flex items-center gap-1.5"
          >
            <span
              class="w-4 h-4 rounded-full bg-n-slate-11 text-white text-[9px] font-bold inline-flex items-center justify-center"
            >
              {{ k + 1 }}
            </span>
            {{ m.title }} · {{ dayLabel(String(m.date)) }}
          </li>
        </ol>
      </div>
    </div>

    <!-- 4 · placar -->
    <div v-if="indicators.length" class="mt-8">
      <p
        class="text-[11px] uppercase tracking-[0.08em] text-n-slate-10 font-semibold"
      >
        Placar
      </p>
      <h4 class="text-lg font-semibold tracking-tight text-n-slate-12">
        Esta página contra a média e o recorde da casa
      </h4>
      <p
        v-if="scorecard?.reading"
        class="text-[13px] leading-relaxed text-n-slate-11 max-w-3xl mt-1"
      >
        {{ scorecard.reading }}
      </p>
      <div class="grid grid-cols-1 grid-cols-1 gap-6 mt-4 items-start">
        <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div
            v-for="i in indicators"
            :key="i.key"
            class="rounded-2xl border border-n-slate-4 dark:border-n-slate-6 px-4 py-3 min-w-0"
          >
            <div class="flex items-baseline gap-2 flex-wrap">
              <p class="text-[13px] font-semibold text-n-slate-12">
                {{ i.label }}
              </p>
              <p class="text-[11px] text-n-slate-9">{{ i.metric }}</p>
            </div>
            <div class="mt-2 space-y-1.5">
              <div class="flex items-center gap-2 text-[11px]">
                <span class="w-24 shrink-0 text-n-slate-11 font-medium"
                  >Esta página</span
                >
                <span
                  class="flex-1 h-2 rounded-full bg-n-slate-3 dark:bg-n-slate-6 overflow-hidden"
                >
                  <span
                    class="block h-full rounded-full"
                    :style="{
                      width: barWidth(i.value, i),
                      background: toneColor(i),
                    }"
                  />
                </span>
                <b class="w-12 text-end tabular-nums text-n-slate-12">{{
                  i.value_text
                }}</b>
              </div>
              <div
                v-if="i.avg !== null && i.avg !== undefined"
                class="flex items-center gap-2 text-[11px]"
              >
                <span class="w-24 shrink-0 text-n-slate-10">Média da casa</span>
                <span
                  class="flex-1 h-2 rounded-full bg-n-slate-3 dark:bg-n-slate-6 overflow-hidden"
                >
                  <span
                    class="block h-full rounded-full bg-[#94a3b8]"
                    :style="{ width: barWidth(i.avg, i) }"
                  />
                </span>
                <b class="w-12 text-end tabular-nums text-n-slate-11">{{
                  i.avg_text
                }}</b>
              </div>
              <div
                v-if="i.record !== null && i.record !== undefined"
                class="flex items-center gap-2 text-[11px]"
              >
                <span class="w-24 shrink-0 text-n-slate-10">Recorde</span>
                <span
                  class="flex-1 h-2 rounded-full bg-n-slate-3 dark:bg-n-slate-6 overflow-hidden"
                >
                  <span
                    class="block h-full rounded-full bg-[#d4a017]"
                    :style="{ width: barWidth(i.record, i) }"
                  />
                </span>
                <b class="w-12 text-end tabular-nums text-n-slate-11">{{
                  i.record_text
                }}</b>
              </div>
            </div>
            <p class="text-[11px] mt-2" :style="{ color: toneColor(i) }">
              {{ i.phrase
              }}<template v-if="i.record_phrase">
                · {{ i.record_phrase }}
              </template>
            </p>
          </div>
        </div>
        <div
          v-if="scorecard?.radar?.axes?.length"
          class="flex flex-col items-center"
        >
          <ScoreRadar
            :radar="scorecard.radar"
            :color="color"
            :size="220"
            :labels="RADAR_LABELS"
          />
        </div>
      </div>
    </div>

    <!-- 5 · de onde vieram -->
    <div v-if="sources.length" class="mt-8">
      <p
        class="text-[11px] uppercase tracking-[0.08em] text-n-slate-10 font-semibold"
      >
        Origens
      </p>
      <h4 class="text-lg font-semibold tracking-tight text-n-slate-12">
        De onde vieram as visitas e os leads
      </h4>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-4">
        <div>
          <p class="text-[12px] font-semibold text-n-slate-11 mb-2">
            Visitas por origem
          </p>
          <DonutChart :slices="donutViews" :size="150" unit="visitas" />
        </div>
        <div>
          <p class="text-[12px] font-semibold text-n-slate-11 mb-2">
            Leads por origem
          </p>
          <DonutChart
            :slices="donutLeads"
            :size="150"
            unit="leads"
            empty-text="nenhum lead no período"
          />
        </div>
      </div>
      <p class="text-[11px] text-n-slate-9 mt-2">
        origem = de onde veio a visita (utm, gclid/fbclid ou quem indicou a
        página); o lead herda a origem da visita que gerou o Protocolo
      </p>
    </div>

    <!-- 6 · no Google -->
    <div v-if="!isHub" class="mt-8">
      <p
        class="text-[11px] uppercase tracking-[0.08em] text-n-slate-10 font-semibold"
      >
        No Google · últimos 28 dias
      </p>
      <template v-if="gsc">
        <h4 class="text-lg font-semibold tracking-tight text-n-slate-12">
          Apareceu {{ n(gsc.impressions) }} vezes e recebeu
          {{ n(gsc.clicks) }} clique(s)
        </h4>
        <div class="grid grid-cols-3 gap-3 mt-3 max-w-md">
          <div>
            <p class="text-xl font-semibold tabular-nums text-n-slate-12">
              {{ n(gsc.impressions) }}
            </p>
            <p class="text-[11px] text-n-slate-10">aparições</p>
          </div>
          <div>
            <p class="text-xl font-semibold tabular-nums text-n-slate-12">
              {{ n(gsc.clicks) }}
            </p>
            <p class="text-[11px] text-n-slate-10">
              cliques · {{ pctTxt(pct(gsc.clicks, gsc.impressions)) }}
            </p>
          </div>
          <div>
            <p class="text-xl font-semibold tabular-nums text-n-slate-12">
              {{ fmtPos(gsc.position) }}
            </p>
            <p class="text-[11px] text-n-slate-10">posição média</p>
          </div>
        </div>
        <div
          v-if="terms.length"
          class="mt-3 grid grid-cols-1 md:grid-cols-2 gap-x-6 gap-y-1"
        >
          <div
            v-for="t in terms"
            :key="t.query"
            class="flex items-baseline gap-2 text-[12px] border-b border-n-slate-3 dark:border-n-slate-6 py-1"
          >
            <span class="min-w-0 truncate text-n-slate-12">{{ t.query }}</span>
            <span class="ms-auto whitespace-nowrap text-n-slate-9 tabular-nums">
              {{ n(t.clicks) }} clique(s) · {{ n(t.impressions) }} · pos.
              {{ fmtPos(t.position) }}
            </span>
          </div>
        </div>
      </template>
      <p v-else class="text-[13px] text-n-slate-10 mt-1">
        {{
          gscReady
            ? 'A página ainda não apareceu no Google nos últimos 28 dias.'
            : 'Search Console ainda não ligado (Integrações → Google).'
        }}
      </p>
    </div>

    <!-- 7 · o que melhorar -->
    <div v-if="!isHub" class="mt-8">
      <p
        class="text-[11px] uppercase tracking-[0.08em] text-n-slate-10 font-semibold"
      >
        O que melhorar
      </p>
      <h4 class="text-lg font-semibold tracking-tight text-n-slate-12">
        {{
          insights.length
            ? `${insights.length} ponto(s) que o sistema achou`
            : 'Nenhum ponto a melhorar com o volume de agora'
        }}
      </h4>
      <ol v-if="insights.length" class="mt-3 space-y-2 list-none ps-0">
        <li
          v-for="i in insights"
          :key="i.key"
          class="rounded-2xl border border-n-slate-4 dark:border-n-slate-6 px-4 py-3"
        >
          <p class="text-[13px] font-semibold text-n-slate-12">
            {{ LEVEL[i.level] || '💡' }} {{ i.title }}
          </p>
          <p
            v-if="i.evidence"
            class="text-[12px] text-n-slate-11 leading-relaxed mt-0.5"
          >
            {{ i.evidence }}
          </p>
          <p v-if="i.suggestion" class="text-[12px] text-n-slate-10 mt-0.5">
            → {{ i.suggestion }}
          </p>
        </li>
      </ol>
      <button
        type="button"
        class="cvg-btn cvg-btn--sm mt-3"
        @click="emit('otimizar')"
      >
        Ver o que fazer no Otimizar ›
      </button>
    </div>
  </section>
</template>
