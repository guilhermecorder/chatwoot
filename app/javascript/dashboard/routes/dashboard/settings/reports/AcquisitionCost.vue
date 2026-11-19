<script setup>
// 💰 FINANCEIRO & CAC (item 318, 03/10/2026 — "preciso descobrir o CAC
// afinal"). Decisões dele: cliente = 1ª CIRURGIA REALIZADA no período; dois
// CACs — o de ANÚNCIOS (Google + Meta, aberto por canal e campanha) e o
// TOTAL "tecnologia e anúncios" (+ WhatsApp + IA); dólar da IA pela cotação
// do dia com opção MANUAL para projeção; Oftalmofácil (parceiros) à parte.
// Filosofia: cada número diz de onde veio (fórmula escrita embaixo).
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import HBars from 'dashboard/components-next/cevico/HBars.vue';
import ShareBar from 'dashboard/components-next/cevico/ShareBar.vue';
import TimelineChart from 'dashboard/components-next/cevico/TimelineChart.vue';
import DonutChart from 'dashboard/components-next/cevico/DonutChart.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { useUISettings } from 'dashboard/composables/useUISettings';
import CrmAPI from 'dashboard/api/crm';
import { bucketCost, cumulativeCost } from 'dashboard/helper/cevicoLines';

const route = useRoute();
const isLoading = ref(true);
const data = ref(null);
const period = ref({ preset: 'month', from: '', to: '' });
const usdInput = ref('');
const usdManual = ref(null);
const campaignView = ref('list');
const peopleView = ref('list');
const peopleFilter = ref('all');

const pal = useCevicoPalette({
  scope: 'report:acquisition_cost',
  blocks: [
    { id: 'cac', label: 'Os dois CACs', icon: 'i-lucide-piggy-bank' },
    {
      id: 'custo_fonte',
      label: 'Custo por fonte',
      icon: 'i-lucide-trending-down',
    },
    {
      id: 'faturamento',
      label: 'Faturamento × funil',
      icon: 'i-lucide-bar-chart-3',
    },
    { id: 'gasto', label: 'De onde vem o gasto', icon: 'i-lucide-wallet' },
    { id: 'canais', label: 'Por canal', icon: 'i-lucide-git-fork' },
    { id: 'campanhas', label: 'Por campanha', icon: 'i-lucide-megaphone' },
    { id: 'meses', label: 'Mês a mês', icon: 'i-lucide-activity' },
    { id: 'pacientes', label: 'Quem são', icon: 'i-lucide-users' },
    { id: 'parceiros', label: 'Oftalmofácil', icon: 'i-lucide-handshake' },
  ],
});
const { cvVars, blockVars, blockFamily } = pal;

const params = () => ({
  preset: period.value.preset,
  ...(period.value.preset === 'custom'
    ? { from: period.value.from, to: period.value.to }
    : {}),
  ...(usdManual.value ? { usd: usdManual.value } : {}),
});

const load = async () => {
  isLoading.value = true;
  try {
    const { data: payload } = await CrmAPI.getAcquisitionCost(params());
    data.value = payload;
  } catch {
    useAlert('Não consegui calcular o CAC agora.');
  } finally {
    isLoading.value = false;
  }
};
// 📈 os dois gráficos da linha do tempo (19/10) chegam numa chamada à parte,
// leve, para a tela não esperar por eles
const timeline = ref(null);
const timelineLoading = ref(false);
const loadTimeline = async () => {
  timelineLoading.value = true;
  try {
    const { data: payload } = await CrmAPI.getAcquisitionTimeline({
      preset: period.value.preset,
      ...(period.value.preset === 'custom'
        ? { from: period.value.from, to: period.value.to }
        : {}),
    });
    timeline.value = payload;
  } catch {
    timeline.value = null;
  } finally {
    timelineLoading.value = false;
  }
};
const loadAll = () => Promise.all([load(), loadTimeline()]);
watch(period, loadAll, { deep: true });
onMounted(loadAll);

const applyUsd = () => {
  const n = Number(String(usdInput.value).replace(',', '.'));
  usdManual.value = n > 0 ? n : null;
  load();
};
const clearUsd = () => {
  usdInput.value = '';
  usdManual.value = null;
  load();
};

// ── formatação ──
const fmtNum = v => Number(v || 0).toLocaleString('pt-BR');
const money = (v, digits = 2) =>
  `R$ ${Number(v || 0).toLocaleString('pt-BR', {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  })}`;
const moneyShort = v => money(v, 0);
// eixo dos gráficos: "15 mil" cabe; "R$ 15.000" corta
const axisShort = v =>
  v >= 1000
    ? `${(v / 1000).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} mil`
    : String(v);
// eixo em R$ curto: "R$ 15 mil"
const moneyAxis = v => `R$ ${axisShort(v)}`;
const orDash = (v, fmt = money) =>
  v === null || v === undefined ? '—' : fmt(v);
const roasFmt = v =>
  v === null || v === undefined ? '—' : `${v.toLocaleString('pt-BR')}×`;
const dateBR = iso =>
  iso ? new Date(`${iso}T12:00:00`).toLocaleDateString('pt-BR') : '';
const MONTHS = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];
const monthLabel = ym => {
  const [y, m] = ym.split('-');
  return `${MONTHS[Number(m) - 1]}/${y.slice(2)}`;
};

const s = computed(() => data.value?.summary || {});
const sp = computed(() => data.value?.spend || {});
const usd = computed(() => data.value?.usd || {});

const CHANNEL_COLORS = {
  google: '#0a84ff',
  meta: '#bf5af2',
  organico: '#30d158',
};
const CHANNEL_ICONS = {
  google: 'i-lucide-search',
  meta: 'i-lucide-instagram',
  organico: 'i-lucide-sprout',
};
const SOURCE_LABELS = {
  crm: 'CRM (coluna Cirurgia Realizada)',
  agenda: 'Agenda (presença na cirurgia)',
  oftalmofacil: 'Oftalmofácil (data já passou)',
};

// ── avisos de cada fonte de gasto ──
const spendNote = key => {
  const g = sp.value[key] || {};
  if (key === 'google') {
    if (!g.configured) return 'Google não ligado (Integrações → Google Ads)';
    if (g.error) return `Google não respondeu: ${g.error}`;
    return 'gasto lido do GA4 (conta do Google Ads vinculada)';
  }
  if (key === 'meta') {
    if (!g.configured) return 'Meta não ligada (Integrações → Meta Ads)';
    if (g.source === 'espelho')
      return 'a Meta não respondeu agora — usei o espelho diário dos anúncios';
    if (g.error) return `Meta não respondeu: ${g.error}`;
    return 'gasto da conta de anúncios (Marketing API)';
  }
  if (key === 'whatsapp') {
    if (!g.synced)
      return 'sem fatura — use "Atualizar da Meta" em Gasto do WhatsApp';
    return `fatura da Meta (${g.currency})`;
  }
  return `${fmtNum(g.calls)} chamadas · US$ ${Number(g.usd || 0).toLocaleString('pt-BR', { minimumFractionDigits: 2 })}`;
};
const spendSlices = computed(() => [
  {
    label: 'Google Ads',
    value: sp.value.google?.cost || 0,
    color: CHANNEL_COLORS.google,
  },
  {
    label: 'Meta Ads',
    value: sp.value.meta?.spend || 0,
    color: CHANNEL_COLORS.meta,
  },
  { label: 'WhatsApp', value: sp.value.whatsapp?.brl || 0, color: '#25d366' },
  { label: 'IA', value: sp.value.ai?.brl || 0, color: '#ff9f0a' },
]);

const usdLabel = computed(() => {
  const u = usd.value;
  if (u.mode === 'manual')
    return `dólar manual (projeção): R$ ${Number(u.manual).toLocaleString('pt-BR')}`;
  if (u.mode === 'ptax')
    return `dólar do dia (Banco Central) · média do período R$ ${Number(u.avg).toLocaleString('pt-BR')}`;
  return 'sem cotação do Banco Central agora — informe o dólar manual';
});

// ── canais ──
const channels = computed(() => data.value?.channels || []);
const channelBars = computed(() =>
  channels.value
    .filter(c => c.key !== 'organico')
    .map(c => ({
      key: c.key,
      label: c.label,
      sub: `${fmtNum(c.patients)} paciente(s) · ${money(c.spend, 0)} em anúncio`,
      values: [c.cac || 0],
      color: CHANNEL_COLORS[c.key],
    }))
);

// ── campanhas ──
const campaigns = computed(() => data.value?.campaigns || []);
const campaignBars = computed(() =>
  campaigns.value.map((c, i) => ({
    key: `${c.channel}-${c.name}`,
    label: c.name,
    sub: `${c.channel === 'google' ? 'Google' : 'Meta'} · ${money(c.spend, 0)} · ${fmtNum(c.patients)} paciente(s) · retorno ${roasFmt(c.roas)}`,
    values: [c.cac || 0],
    color: CHANNEL_COLORS[c.channel] || blockFamily('campanhas')[i % 4],
  }))
);

// ── mês a mês ──
const monthly = computed(() => data.value?.monthly || []);
const monthLabels = computed(() => monthly.value.map(m => monthLabel(m.month)));
// 398 (19/11): linhas retas, um ponto por mês. Cores de linha validadas no
// daltonismo (azul × rosa × verde × âmbar), as mesmas do custo por fonte.
const MONTH_SPEND = [
  { key: 'google', label: 'Google', color: '#0a84ff' },
  { key: 'meta', label: 'Meta', color: '#db2777' },
  { key: 'whatsapp', label: 'WhatsApp', color: '#25d366' },
  { key: 'ai', label: 'IA', color: '#ff9f0a' },
];
const spendMonthLines = computed(() =>
  MONTH_SPEND.map(line => {
    const values = monthly.value.map(m => Number(m[line.key]) || 0);
    const total = values.reduce((a, b) => a + b, 0);
    return { ...line, values, total, dots: true, legendValue: money(total, 0) };
  }).filter(line => line.total > 0)
);
const spendMonthTip = i => {
  const m = monthly.value[i];
  return {
    title: `${monthLabels.value[i]} · ${money(m.total, 0)} no total`,
    rows: spendMonthLines.value.map(line => ({
      color: line.color,
      label: line.label,
      value: money(line.values[i], 0),
    })),
  };
};
// mês sem paciente operado NÃO tem CAC (não é zero): fica sem bolinha e um
// pontilhado liga os meses vizinhos
const MONTH_CAC = [
  {
    key: 'cac_ads',
    label: 'CAC de anúncios',
    color: '#bf5af2',
    spend: 'ads',
    count: 'paid_patients',
    who: 'paciente(s) dos anúncios',
  },
  {
    key: 'cac_total',
    label: 'CAC total',
    color: '#ff9f0a',
    spend: 'total',
    count: 'patients',
    who: 'paciente(s) novos',
  },
];
const cacMonthLines = computed(() =>
  MONTH_CAC.map(line => ({
    ...line,
    values: monthly.value.map(m => m[line.key] ?? null),
    dots: true,
    legendValue: `${orDash(s.value[line.key], moneyShort)} no período`,
  }))
);
const cacMonthTip = i => {
  const m = monthly.value[i];
  return {
    title: monthLabels.value[i],
    rows: MONTH_CAC.map(line => ({
      color: line.color,
      label: line.label,
      value: orDash(m[line.key], moneyShort),
      sub: `${money(m[line.spend], 0)} ÷ ${fmtNum(m[line.count])} ${line.who}${
        m[line.key] === null || m[line.key] === undefined
          ? ' — sem paciente, sem CAC'
          : ''
      }`,
    })),
  };
};

// ══ 📈 LINHA DO TEMPO (19/10/2026): custo por fonte × tempo e faturamento × etapas ══
const { uiSettings, updateUISettings } = useUISettings();
// escolha salva POR PESSOA: indicador do custo, funil e colunas marcadas
const tlPrefs = computed(() => uiSettings.value?.cevico_cac_timeline || {});
const savePrefs = patch =>
  updateUISettings({ cevico_cac_timeline: { ...tlPrefs.value, ...patch } });

const COST_METRICS = [
  { key: 'leads', label: 'Custo por lead novo', unit: 'lead(s) novo(s)' },
  {
    key: 'booked',
    label: 'Custo por agendamento de consulta',
    unit: 'agendamento(s)',
  },
  {
    key: 'closed',
    label: 'Custo por cirurgia fechada (CAC)',
    unit: 'cirurgia(s) fechada(s)',
  },
];
const costMetric = computed(() => tlPrefs.value.metric || 'leads');
const costUnit = computed(
  () => COST_METRICS.find(m => m.key === costMetric.value)?.unit || ''
);
// cores validadas (skill dataviz): azul × rosa passam no daltonismo; o Geral é
// uma referência neutra tracejada, não uma fonte
const SOURCE_LINES = [
  { key: 'google', label: 'Google Ads', color: '#0a84ff' },
  { key: 'meta', label: 'Meta Ads', color: '#db2777' },
  {
    key: 'all',
    label: 'Geral (anúncios ÷ todas as fontes)',
    color: '#64748b',
    dashed: true,
  },
];
const unitName = computed(() => timeline.value?.period?.unit || 'day');
const bucketDate = iso => new Date(`${iso}T12:00:00`);
const dayMonth = iso =>
  bucketDate(iso).toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
  });
const bucketLabel = iso =>
  unitName.value === 'month' ? monthLabel(iso.slice(0, 7)) : dayMonth(iso);
const bucketTitle = iso => {
  if (unitName.value === 'week') return `semana de ${dayMonth(iso)}`;
  if (unitName.value === 'month') return monthLabel(iso.slice(0, 7));
  return bucketDate(iso).toLocaleDateString('pt-BR', {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
  });
};
const tlLabels = computed(() =>
  (timeline.value?.buckets || []).map(bucketLabel)
);
const unitWord = computed(
  () =>
    ({ day: 'por dia', week: 'por semana', month: 'por mês' })[unitName.value]
);
const sourceData = key => timeline.value?.sources?.[key] || {};
// 398 (19/11, "linhas certinhas"): o custo de UM dia quebra a linha (dia sem
// resultado = conta ÷ 0). Duas leituras, escolha salva por pessoa:
//   acumulado = tudo que a fonte gastou do começo do período até o ponto ÷ tudo
//               que ela trouxe até ali (linha inteira; fecha no custo do período)
//   balde     = gasto ÷ resultado de cada dia/semana/mês (pontilhado sobre o
//               balde sem resultado)
// Sem escolha salva: por dia abre no acumulado; por semana ou mês, em cada balde.
const UNIT_NOUN = { day: 'dia', week: 'semana', month: 'mês' };
const unitNoun = computed(() => UNIT_NOUN[unitName.value]);
// "o dia" / "a semana" / "o mês" e "do dia" / "da semana" / "do mês"
const unitThe = computed(() =>
  unitName.value === 'week' ? 'a semana' : `o ${unitNoun.value}`
);
const unitOf = computed(() => `d${unitThe.value}`);
const costView = computed(() => {
  const saved = tlPrefs.value.view;
  if (saved === 'acumulado' || saved === 'balde') return saved;
  return unitName.value === 'day' ? 'acumulado' : 'balde';
});
const COST_VIEWS = computed(() => [
  { key: 'acumulado', label: 'Acumulado no período' },
  {
    key: 'balde',
    label: `Cada ${unitNoun.value}`,
  },
]);
// balde que ainda não chegou (período até o fim do mês) não entra na linha
const todayIso = new Date().toLocaleDateString('en-CA', {
  timeZone: 'America/Sao_Paulo',
});
const isFuture = i => (timeline.value?.buckets?.[i] || '') > todayIso;
const costSeries = computed(() =>
  SOURCE_LINES.map(line => {
    const src = sourceData(line.key);
    const spend = src.spend || [];
    const count = src[costMetric.value] || [];
    const each = bucketCost(spend, count);
    const sum = cumulativeCost(spend, count);
    return { ...line, each, sum, period: sum[sum.length - 1] || null };
  })
);
const costLines = computed(() =>
  costSeries.value.map(line => {
    const points = costView.value === 'acumulado' ? line.sum : line.each;
    return {
      key: line.key,
      label: line.label,
      color: line.color,
      dashed: line.dashed,
      values: points.map((p, i) => (isFuture(i) ? null : p.cost)),
      // bolinha = balde que teve resultado de verdade
      dots: line.each.map(p =>
        costView.value === 'acumulado' ? p.count > 0 : p.cost !== null
      ),
      legendValue:
        line.period?.cost === null || !line.period
          ? '—'
          : `${money(line.period.cost, 0)} no período`,
    };
  })
);
const costLegendHint = computed(() =>
  costSeries.value
    .filter(line => line.period)
    .map(
      line =>
        `${line.label}: ${money(line.period.spend, 0)} ÷ ${fmtNum(line.period.count)} ${costUnit.value}`
    )
    .join(' · ')
);
// dica: gasto ÷ quantidade = custo, fonte a fonte (revelar de onde veio)
const costTip = i => ({
  title: bucketTitle(timeline.value.buckets[i]),
  rows: [
    ...costSeries.value.map(line => {
      const each = line.each[i];
      const sum = line.sum[i];
      const eachTxt = `${money(each.spend, 0)} ÷ ${fmtNum(each.count)} ${costUnit.value}`;
      const base = {
        color: line.color,
        dashed: line.dashed,
        label: line.label,
      };
      if (costView.value === 'acumulado')
        return {
          ...base,
          value: sum.cost === null ? '—' : money(sum.cost, 0),
          sub: `até aqui: ${money(sum.spend, 0)} ÷ ${fmtNum(sum.count)} ${costUnit.value} · só neste ${unitNoun.value}: ${eachTxt}`,
        };
      return {
        ...base,
        value: each.cost === null ? '—' : money(each.cost, 0),
        sub:
          each.cost === null && each.spend > 0
            ? `${eachTxt} — gastou e não trouxe`
            : eachTxt,
      };
    }),
    {
      color: CHANNEL_COLORS.organico,
      label: 'Orgânico / indicação',
      value: `${fmtNum(sourceData('organico')[costMetric.value]?.[i] || 0)}`,
      sub: 'sem gasto de anúncio — só a quantidade',
    },
  ],
});

// 🍩 as porcentagens do período: quem levou o gasto e quem trouxe o resultado
const sumOf = arr => (arr || []).reduce((a, b) => a + Number(b || 0), 0);
const donutSpend = computed(() =>
  SOURCE_LINES.filter(l => l.key !== 'all').map(l => ({
    key: l.key,
    label: l.label,
    color: l.color,
    value: sumOf(sourceData(l.key).spend),
  }))
);
const donutCount = computed(() => [
  ...SOURCE_LINES.filter(l => l.key !== 'all').map(l => ({
    key: l.key,
    label: l.label,
    color: l.color,
    value: sumOf(sourceData(l.key)[costMetric.value]),
  })),
  {
    key: 'organico',
    label: 'Orgânico / indicação',
    color: CHANNEL_COLORS.organico,
    value: sumOf(sourceData('organico')[costMetric.value]),
  },
]);
const METRIC_SHORT = {
  leads: 'leads novos',
  booked: 'agendamentos',
  closed: 'cirurgias fechadas',
};
const costMetricShort = computed(() => METRIC_SHORT[costMetric.value]);
const METRIC_ARTICLE = { leads: 'os', booked: 'os', closed: 'as' };
const costMetricArticle = computed(() => METRIC_ARTICLE[costMetric.value]);

// ── faturamento × etapas ──
const pipelines = computed(() => timeline.value?.pipelines || []);
const pipelineId = computed(() => {
  const saved = Number(tlPrefs.value.pipeline_id);
  return pipelines.value.some(p => p.id === saved)
    ? saved
    : pipelines.value[0]?.id;
});
const pipeline = computed(() =>
  pipelines.value.find(p => p.id === pipelineId.value)
);
const CONV_KEY = 'conv';
const CONV_COLOR = '#0a84ff';
const stageKey = st => `stage:${st.id}`;
const defaultLines = computed(() => {
  const stages = pipeline.value?.stages || [];
  const pick = re => stages.find(st => re.test(st.name));
  return [
    CONV_KEY,
    pick(/agendamento|consulta agendada/i),
    pick(/cirurgia agendada/i),
  ]
    .filter(Boolean)
    .map(x => (typeof x === 'string' ? x : stageKey(x)));
});
const selectedLines = computed(() =>
  Array.isArray(tlPrefs.value.lines) ? tlPrefs.value.lines : defaultLines.value
);
const lineOn = key => selectedLines.value.includes(key);
const toggleLine = key =>
  savePrefs({
    lines: lineOn(key)
      ? selectedLines.value.filter(k => k !== key)
      : [...selectedLines.value, key],
  });
const pickPipeline = id => savePrefs({ pipeline_id: id, lines: null });
const revenueBars = computed(() => ({
  key: 'revenue',
  label: 'Faturamento',
  color: '#059669',
  values: timeline.value?.revenue || [],
}));
const stageLines = computed(() => {
  const stages = pipeline.value?.stages || [];
  return selectedLines.value
    .map(key => {
      if (key === CONV_KEY)
        return {
          key,
          label: 'Novas conversas',
          color: CONV_COLOR,
          values: timeline.value?.conversations || [],
        };
      const st = stages.find(x => stageKey(x) === key);
      return st
        ? { key, label: st.name, color: st.color, values: st.values }
        : null;
    })
    .filter(Boolean);
});
const revenueTip = i => ({
  title: bucketTitle(timeline.value.buckets[i]),
  rows: [
    {
      color: revenueBars.value.color,
      square: true,
      label: 'Faturamento',
      value: money(revenueBars.value.values[i] || 0, 0),
      sub: 'cirurgias realizadas (pago no Oftalmofácil, senão valor do card)',
    },
    ...stageLines.value.map(line => ({
      color: line.color,
      label: line.label,
      value: fmtNum(line.values[i] || 0),
      sub: line.key === CONV_KEY ? 'conversas criadas' : 'entradas na coluna',
    })),
  ],
});
const revenueTotal = computed(() =>
  (timeline.value?.revenue || []).reduce((a, b) => a + Number(b || 0), 0)
);

// ── pacientes ──
const people = computed(() => data.value?.people || []);
const shownPeople = computed(() =>
  peopleFilter.value === 'all'
    ? people.value
    : people.value.filter(p => p.channel === peopleFilter.value)
);
const contactHref = id =>
  id ? `/app/accounts/${route.params.accountId}/contacts/${id}` : null;
const sources = computed(() =>
  Object.entries(data.value?.sources || {}).map(([k, v]) => ({
    label: SOURCE_LABELS[k] || k,
    value: v,
    color: { crm: '#0a84ff', agenda: '#30d158', oftalmofacil: '#ff9f0a' }[k],
  }))
);

const partner = computed(() => data.value?.partner || {});
</script>

<template>
  <div class="cv-page cv-overlay" :style="cvVars">
    <CevicoHero
      :pal="pal"
      title="Financeiro & CAC"
      subtitle="quanto custa cada paciente que operou · por canal e campanha · retorno do investimento"
      icon="i-lucide-piggy-bank"
    />

    <div class="flex items-center gap-3 flex-wrap mb-6">
      <PeriodRuler
        v-model="period"
        glass
        class="w-full md:w-auto md:flex-1 min-w-0"
      />
      <div class="flex items-center gap-1.5 flex-shrink-0">
        <span class="text-[11px] text-n-slate-10">Dólar manual</span>
        <input
          v-model="usdInput"
          class="cv-input !w-24 !h-8 text-xs"
          placeholder="ex.: 5,50"
          inputmode="decimal"
          @keyup.enter="applyUsd"
        />
        <button class="cv-btn cv-btn-sm" @click="applyUsd">Simular</button>
        <button
          v-if="usdManual"
          class="cv-btn cv-btn-sm cv-btn-ghost"
          @click="clearUsd"
        >
          Voltar ao do dia
        </button>
      </div>
    </div>

    <SkeletonScreen v-if="isLoading" variant="dashboard" />

    <template v-else-if="data">
      <!-- ══ OS DOIS CACs ══ -->
      <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('cac')">
        <div class="flex items-center gap-2 mb-1 flex-wrap">
          <span class="cv-icon"><span class="i-lucide-piggy-bank text-base"/></span>
          <h2 class="text-sm font-bold text-n-slate-12">Os dois CACs</h2>
          <span v-if="usd.mode === 'manual'" class="cv-chip cv-amber ml-auto">
            🧪 simulação com dólar a R$
            {{ Number(usd.manual).toLocaleString('pt-BR') }}
          </span>
        </div>
        <p class="text-[11px] text-n-slate-9 mb-4">
          {{ dateBR(data.period.from) }} a {{ dateBR(data.period.to) }} ·
          cliente = paciente cuja <b>primeira cirurgia realizada</b> caiu no
          período (o 2º olho depois não conta de novo)
        </p>

        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-3">
          <DashKpi
            glass
            label="CAC de anúncios"
            :value="orDash(s.cac_ads)"
            :sub="`${money(sp.ads, 0)} em Google + Meta ÷ ${fmtNum(s.paid_patients)} paciente(s) que vieram dos anúncios`"
            :grad="blockFamily('cac')[0]"
          />
          <DashKpi
            glass
            label="CAC total (tecnologia e anúncios)"
            :value="orDash(s.cac_total)"
            :sub="`${money(sp.total, 0)} (anúncios + WhatsApp + IA) ÷ ${fmtNum(s.patients)} paciente(s) novos`"
            :grad="blockFamily('cac')[1]"
          />
          <DashKpi
            glass
            label="Pacientes operados (novos)"
            :value="s.patients || 0"
            :sub="`${fmtNum(s.paid_patients)} dos anúncios · ${fmtNum(s.patients - s.paid_patients)} orgânicos/indicação`"
            :grad="blockFamily('cac')[2]"
          />
        </div>
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
          <DashKpi
            compact
            glass
            label="Receita das cirurgias"
            :value="moneyShort(s.revenue)"
            :sub="`realizadas no período · ${moneyShort(s.paid_revenue)} vieram dos anúncios`"
          />
          <DashKpi
            compact
            glass
            label="Retorno dos anúncios"
            :value="roasFmt(s.roas_ads)"
            sub="receita dos pacientes dos anúncios ÷ gasto em anúncio"
          />
          <DashKpi
            compact
            glass
            label="Retorno total"
            :value="roasFmt(s.roas_total)"
            sub="receita total ÷ (anúncios + WhatsApp + IA)"
          />
          <DashKpi
            compact
            glass
            label="Custo por lead (anúncios)"
            :value="orDash(s.cpl_ads)"
            :sub="`gasto em anúncio ÷ ${fmtNum(s.paid_leads)} lead(s) dos anúncios (de ${fmtNum(s.leads)} no total)`"
          />
        </div>
        <p class="text-[11px] text-n-slate-9 mt-3">
          CAC de anúncios "misturado" (gasto em anúncio ÷ todos os pacientes
          novos, inclusive orgânicos):
          <b class="text-n-slate-11">{{ orDash(s.cac_ads_blended) }}</b>
          <template v-if="data.bulk_skipped">
            · {{ fmtNum(data.bulk_skipped) }} cartão(ões) entraram em "Cirurgia
            Realizada" por carga em massa no período e ficaram fora (sem data
            confiável)
          </template>
        </p>
      </div>

      <!-- ══ 📈 CUSTO POR FONTE AO LONGO DO TEMPO (19/10) ══ -->
      <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('custo_fonte')">
        <div class="flex items-center gap-2 mb-1 flex-wrap">
          <span class="cv-icon">
            <span class="i-lucide-trending-down text-base" />
          </span>
          <h2 class="text-sm font-bold text-n-slate-12">
            Custo por fonte ao longo do tempo
          </h2>
          <span v-if="timeline" class="text-[11px] text-n-slate-9 ml-auto">
            {{ unitWord }}
          </span>
        </div>
        <p class="text-[11px] text-n-slate-9 mb-3">
          quanto cada fonte cobrou por resultado — escolha o resultado e o jeito
          de ler a linha
        </p>
        <div class="flex flex-wrap gap-1.5 mb-2">
          <button
            v-for="m in COST_METRICS"
            :key="m.key"
            type="button"
            class="cv-chip cv-chip-lg"
            :class="costMetric === m.key ? 'cv-chip-on' : ''"
            @click="savePrefs({ metric: m.key })"
          >
            {{ m.label }}
          </button>
        </div>
        <div v-if="timeline" class="flex flex-wrap gap-1.5 mb-3">
          <button
            v-for="v in COST_VIEWS"
            :key="v.key"
            type="button"
            class="cv-chip"
            :class="costView === v.key ? 'cv-chip-on' : ''"
            @click="savePrefs({ view: v.key })"
          >
            {{ v.label }}
          </button>
        </div>
        <p
          v-if="timeline"
          class="text-[11px] text-n-slate-10 mb-4 leading-relaxed"
        >
          <template v-if="costView === 'acumulado'">
            <b class="text-n-slate-11">Cada ponto da linha</b>
            = tudo que a fonte gastou do começo do período até aquele
            {{ unitNoun }} ÷ o total de {{ costMetricShort }} que ela trouxe até
            ali. A bolinha marca {{ unitThe }} que teve resultado; o último
            ponto é o custo do período inteiro.
          </template>
          <template v-else>
            <b class="text-n-slate-11">Cada ponto da linha</b>
            = gasto {{ unitOf }} ÷ {{ costMetricShort }} {{ unitOf }}. Onde não
            houve resultado não existe custo: fica sem bolinha e um pontilhado
            liga os pontos vizinhos.
          </template>
        </p>
        <TimelineChart
          v-if="timeline"
          :labels="tlLabels"
          :lines="costLines"
          :height="240"
          :left-format="moneyShort"
          :left-width="60"
          :tip="costTip"
          straight
          bridge-gaps
          empty-text="sem gasto ou sem resultado no período"
        />
        <p
          v-if="timeline && costLegendHint"
          class="text-[10px] text-n-slate-9 mt-1.5 leading-relaxed"
        >
          no período: {{ costLegendHint }}
        </p>
        <p v-else-if="timelineLoading" class="text-[11px] text-n-slate-9">
          calculando…
        </p>
        <p v-else class="text-[11px] text-n-slate-9">
          não consegui montar a linha do tempo agora.
        </p>
        <div v-if="timeline" class="grid grid-cols-1 md:grid-cols-2 gap-6 mt-5">
          <div>
            <p class="text-[12px] font-semibold text-n-slate-11 mb-2">
              Quem levou o gasto
            </p>
            <DonutChart
              :slices="donutSpend"
              :size="140"
              :format="moneyShort"
              unit="em anúncios"
              empty-text="sem gasto no período"
            />
          </div>
          <div>
            <p class="text-[12px] font-semibold text-n-slate-11 mb-2">
              Quem trouxe {{ costMetricArticle }} {{ costMetricShort }}
            </p>
            <DonutChart
              :slices="donutCount"
              :size="140"
              :unit="costMetricShort"
              empty-text="nenhum no período"
            />
          </div>
        </div>
        <p class="text-[11px] text-n-slate-9 mt-3 leading-relaxed">
          <b class="text-n-slate-11">De onde vem:</b> gasto da Meta = foto
          diária dos anúncios (mesma base do Agente de Campanhas); gasto do
          Google = GA4 por campanha e dia; lead novo = contato novo das caixas
          de captação, fonte pelo primeiro carimbo (anúncio → WhatsApp ou
          página); agendamento = primeira entrada na coluna de agendamento ou
          consulta na Agenda; cirurgia fechada = primeira entrada em "Cirurgia
          Agendada", cirurgia na Agenda ou no Oftalmofácil. Pacientes de
          parceiro ficam fora.
        </p>
      </div>

      <!-- ══ 📊 FATURAMENTO × ETAPAS DO CRM (19/10) ══ -->
      <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('faturamento')">
        <div class="flex items-center gap-2 mb-1 flex-wrap">
          <span class="cv-icon">
            <span class="i-lucide-bar-chart-3 text-base" />
          </span>
          <h2 class="text-sm font-bold text-n-slate-12">
            Faturamento × etapas do CRM
          </h2>
          <span v-if="timeline" class="text-[11px] text-n-slate-9 ml-auto">
            {{ moneyShort(revenueTotal) }} no período
          </span>
        </div>
        <p class="text-[11px] text-n-slate-9 mb-3">
          barras = faturamento (R$, eixo da esquerda); linhas = quantas vezes
          entraram em cada coluna escolhida (eixo da direita)
        </p>
        <TimelineChart
          v-if="timeline"
          :labels="tlLabels"
          :bars="revenueBars"
          :lines="stageLines"
          :height="260"
          :left-format="moneyAxis"
          :right-format="fmtNum"
          :left-width="66"
          :right-width="36"
          :tip="revenueTip"
          straight
          empty-text="sem faturamento no período"
        />
        <p v-else-if="timelineLoading" class="text-[11px] text-n-slate-9">
          calculando…
        </p>
        <p v-else class="text-[11px] text-n-slate-9">
          não consegui montar a linha do tempo agora.
        </p>
        <div v-if="timeline" class="mt-4">
          <div class="flex items-center gap-2 flex-wrap mb-2">
            <p class="text-[11px] font-semibold text-n-slate-11">
              Adicionar coluna do CRM
            </p>
            <span class="text-[11px] text-n-slate-9">
              — fica salvo para você
            </span>
            <div v-if="pipelines.length > 1" class="ml-auto flex gap-1">
              <button
                v-for="p in pipelines"
                :key="p.id"
                type="button"
                class="cv-chip"
                :class="p.id === pipelineId ? 'cv-chip-on' : ''"
                @click="pickPipeline(p.id)"
              >
                {{ p.name }}
              </button>
            </div>
          </div>
          <div class="flex flex-wrap gap-1.5">
            <button
              type="button"
              class="cv-chip cv-chip-lg inline-flex items-center gap-1.5"
              :class="lineOn(CONV_KEY) ? 'cv-chip-on' : ''"
              @click="toggleLine(CONV_KEY)"
            >
              <span
                class="w-2 h-2 rounded-full"
                :style="{ background: CONV_COLOR }"
              />
              Novas conversas
            </button>
            <button
              v-for="st in pipeline?.stages || []"
              :key="st.id"
              type="button"
              class="cv-chip cv-chip-lg inline-flex items-center gap-1.5"
              :class="lineOn(stageKey(st)) ? 'cv-chip-on' : ''"
              @click="toggleLine(stageKey(st))"
            >
              <span
                class="w-2 h-2 rounded-full"
                :style="{ background: st.color }"
              />
              {{ st.name }}
            </button>
          </div>
        </div>
      </div>

      <!-- ══ DE ONDE VEM O GASTO ══ -->
      <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('gasto')">
        <div class="flex items-center gap-2 mb-1">
          <span class="cv-icon"><span class="i-lucide-wallet text-base"/></span>
          <h2 class="text-sm font-bold text-n-slate-12">De onde vem o gasto</h2>
          <span class="text-[11px] text-n-slate-9 ml-auto">{{ usdLabel }}</span>
        </div>
        <p class="text-[11px] text-n-slate-9 mb-4">
          anúncios = {{ money(sp.ads) }} · tecnologia (WhatsApp + IA) =
          {{ money(sp.tech) }} · total =
          <b class="text-n-slate-11">{{ money(sp.total) }}</b>
        </p>
        <ShareBar
          :items="spendSlices"
          :format="v => money(v, 0)"
          :height="16"
          class="mb-4"
        />
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
          <div
            v-for="k in ['google', 'meta', 'whatsapp', 'ai']"
            :key="k"
            class="cv-sub p-4"
          >
            <p class="text-[11px] text-n-slate-10 mb-0.5">
              {{
                {
                  google: 'Google Ads',
                  meta: 'Meta Ads',
                  whatsapp: 'WhatsApp',
                  ai: 'IA (em reais)',
                }[k]
              }}
            </p>
            <p class="text-lg font-bold text-n-slate-12">
              {{
                money(
                  k === 'google'
                    ? sp.google?.cost
                    : k === 'meta'
                      ? sp.meta?.spend
                      : sp[k]?.brl
                )
              }}
            </p>
            <p class="text-[10px] text-n-slate-9 leading-snug">
              {{ spendNote(k) }}
            </p>
          </div>
        </div>
      </div>

      <!-- ══ POR CANAL ══ -->
      <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('canais')">
        <div class="flex items-center gap-2 mb-1">
          <span class="cv-icon"><span class="i-lucide-git-fork text-base"/></span>
          <h2 class="text-sm font-bold text-n-slate-12">Por canal</h2>
        </div>
        <p class="text-[11px] text-n-slate-9 mb-4">
          o canal é o primeiro carimbo do paciente: clique no anúncio que abre o
          WhatsApp, ou a landing page (utm/gclid). Sem carimbo = orgânico /
          indicação. O CAC por canal é só com anúncio.
        </p>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-3 mb-4">
          <div v-for="c in channels" :key="c.key" class="cv-sub p-4">
            <div class="flex items-center gap-2.5 mb-3">
              <span
                class="cv-icon flex-shrink-0"
                :style="{ background: CHANNEL_COLORS[c.key] }"
              >
                <span :class="CHANNEL_ICONS[c.key]" class="text-base" />
              </span>
              <p class="text-sm font-bold text-n-slate-12">{{ c.label }}</p>
            </div>
            <div class="grid grid-cols-2 gap-x-3 gap-y-2 text-xs">
              <div>
                <p class="text-[10px] text-n-slate-9">CAC</p>
                <p class="font-bold text-n-slate-12">
                  {{ c.key === 'organico' ? 'sem anúncio' : orDash(c.cac) }}
                </p>
              </div>
              <div>
                <p class="text-[10px] text-n-slate-9">Retorno</p>
                <p class="font-bold text-n-slate-12">{{ roasFmt(c.roas) }}</p>
              </div>
              <div>
                <p class="text-[10px] text-n-slate-9">Gasto</p>
                <p class="font-semibold text-n-slate-11">
                  {{ money(c.spend, 0) }}
                </p>
              </div>
              <div>
                <p class="text-[10px] text-n-slate-9">Receita</p>
                <p class="font-semibold text-n-slate-11">
                  {{ moneyShort(c.revenue) }}
                </p>
              </div>
              <div>
                <p class="text-[10px] text-n-slate-9">Leads</p>
                <p class="font-semibold text-n-slate-11">
                  {{ fmtNum(c.leads) }}
                </p>
              </div>
              <div>
                <p class="text-[10px] text-n-slate-9">Operados</p>
                <p class="font-semibold text-n-slate-11">
                  {{ fmtNum(c.patients) }}
                </p>
              </div>
            </div>
            <div
              v-if="c.details?.length"
              class="mt-3 pt-2"
              style="border-top: 1px solid rgb(var(--cv-rgb) / 0.16)"
            >
              <p
                v-for="d in c.details.slice(0, 4)"
                :key="d.label"
                class="text-[10px] text-n-slate-10 flex justify-between gap-2"
              >
                <span class="truncate">{{ d.label }}</span>
                <b class="text-n-slate-11">{{ fmtNum(d.patients) }}</b>
              </p>
            </div>
          </div>
        </div>
        <HBars
          :rows="channelBars"
          :series="[{ label: 'CAC', format: v => money(v, 0) }]"
          :format="v => money(v, 0)"
          :label-width="9"
          :highlight-max="false"
          empty-text="sem gasto em anúncio no período"
        />
      </div>

      <!-- ══ POR CAMPANHA ══ -->
      <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('campanhas')">
        <div class="flex items-center gap-2 mb-1">
          <span class="cv-icon"><span class="i-lucide-megaphone text-base"/></span>
          <h2 class="text-sm font-bold text-n-slate-12">Por campanha</h2>
          <div class="ml-auto flex items-center gap-1">
            <button
              class="cv-btn cv-btn-sm"
              :class="campaignView === 'list' ? '' : 'cv-btn-ghost'"
              @click="campaignView = 'list'"
            >
              <span class="i-lucide-list text-xs" /> Lista
            </button>
            <button
              class="cv-btn cv-btn-sm"
              :class="campaignView === 'cards' ? '' : 'cv-btn-ghost'"
              @click="campaignView = 'cards'"
            >
              <span class="i-lucide-layout-grid text-xs" /> Cards
            </button>
          </div>
        </div>
        <p class="text-[11px] text-n-slate-9 mb-4">
          Meta: gasto do espelho diário de cada anúncio, somado pela campanha ·
          Google: gasto por nome de campanha no GA4, cruzado com o utm_campaign
          da landing page. Barra = CAC da campanha.
        </p>
        <HBars
          v-if="campaignView === 'list'"
          :rows="campaignBars"
          :series="[{ label: 'CAC', format: v => money(v, 0) }]"
          :format="v => (v ? money(v, 0) : '—')"
          :label-width="15"
          :highlight-max="false"
          empty-text="nenhuma campanha com gasto ou paciente no período"
        />
        <div
          v-else
          class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3"
        >
          <div
            v-for="c in campaigns"
            :key="`${c.channel}-${c.name}`"
            class="cv-sub p-4"
          >
            <div class="flex items-center gap-2 mb-2">
              <span
                class="w-2.5 h-2.5 rounded-full flex-shrink-0"
                :style="{ background: CHANNEL_COLORS[c.channel] }"
              />
              <p class="text-sm font-bold text-n-slate-12 truncate">
                {{ c.name }}
              </p>
            </div>
            <div class="grid grid-cols-3 gap-2 text-xs">
              <div>
                <p class="text-[10px] text-n-slate-9">CAC</p>
                <p class="font-bold text-n-slate-12">
                  {{ orDash(c.cac, moneyShort) }}
                </p>
              </div>
              <div>
                <p class="text-[10px] text-n-slate-9">Retorno</p>
                <p class="font-bold text-n-slate-12">{{ roasFmt(c.roas) }}</p>
              </div>
              <div>
                <p class="text-[10px] text-n-slate-9">Gasto</p>
                <p class="font-semibold text-n-slate-11">
                  {{ moneyShort(c.spend) }}
                </p>
              </div>
              <div>
                <p class="text-[10px] text-n-slate-9">Leads</p>
                <p class="font-semibold text-n-slate-11">
                  {{ fmtNum(c.leads) }}
                </p>
              </div>
              <div>
                <p class="text-[10px] text-n-slate-9">Operados</p>
                <p class="font-semibold text-n-slate-11">
                  {{ fmtNum(c.patients) }}
                </p>
              </div>
              <div>
                <p class="text-[10px] text-n-slate-9">Receita</p>
                <p class="font-semibold text-n-slate-11">
                  {{ moneyShort(c.revenue) }}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- ══ MÊS A MÊS ══ -->
      <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('meses')">
        <div class="flex items-center gap-2 mb-1">
          <span class="cv-icon"><span class="i-lucide-activity text-base"/></span>
          <h2 class="text-sm font-bold text-n-slate-12">Mês a mês</h2>
        </div>
        <template v-if="monthly.length">
          <p class="text-[11px] text-n-slate-9 mb-3">como o gasto se formou</p>
          <TimelineChart
            :labels="monthLabels"
            :lines="spendMonthLines"
            :height="190"
            :left-format="moneyAxis"
            :left-width="66"
            :tip="spendMonthTip"
            straight
            empty-text="sem gasto no período"
            class="mb-6"
          />
          <p class="text-[11px] text-n-slate-9 mb-3">
            e quanto custou cada paciente operado — mês sem paciente operado não
            tem CAC: fica sem bolinha e um pontilhado liga os meses vizinhos
          </p>
          <TimelineChart
            :labels="monthLabels"
            :lines="cacMonthLines"
            :height="170"
            :left-format="moneyAxis"
            :left-width="66"
            :tip="cacMonthTip"
            straight
            bridge-gaps
            empty-text="nenhum paciente operado no período"
          />
          <p class="text-[10px] text-n-slate-9 mt-1.5 leading-relaxed">
            CAC de anúncios = anúncios ÷ pacientes dos anúncios · CAC total =
            tudo (anúncios + WhatsApp + IA) ÷ todos os pacientes novos
          </p>
        </template>
        <p v-else class="text-[11px] text-n-slate-9">
          escolha <b>90 dias</b>, <b>Este ano</b> ou um período maior que um mês
          para ver a evolução.
        </p>
      </div>

      <!-- ══ QUEM SÃO ══ -->
      <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('pacientes')">
        <div class="flex items-center gap-2 mb-1 flex-wrap">
          <span class="cv-icon"><span class="i-lucide-users text-base" /></span>
          <h2 class="text-sm font-bold text-n-slate-12">
            Quem são os pacientes do CAC
          </h2>
          <div class="ml-auto flex items-center gap-1 flex-wrap">
            <button
              v-for="f in [
                { k: 'all', l: 'Todos' },
                { k: 'google', l: 'Google' },
                { k: 'meta', l: 'Meta' },
                { k: 'organico', l: 'Orgânico' },
              ]"
              :key="f.k"
              class="cv-chip"
              :class="peopleFilter === f.k ? 'cv-chip-on' : ''"
              @click="peopleFilter = f.k"
            >
              {{ f.l }}
            </button>
            <button
              class="cv-btn cv-btn-sm"
              :class="peopleView === 'list' ? '' : 'cv-btn-ghost'"
              @click="peopleView = 'list'"
            >
              <span class="i-lucide-list text-xs" /> Lista
            </button>
            <button
              class="cv-btn cv-btn-sm"
              :class="peopleView === 'cards' ? '' : 'cv-btn-ghost'"
              @click="peopleView = 'cards'"
            >
              <span class="i-lucide-layout-grid text-xs" /> Cards
            </button>
          </div>
        </div>
        <p class="text-[11px] text-n-slate-9 mb-3">
          de onde veio a data da 1ª cirurgia:
        </p>
        <ShareBar
          :items="sources"
          :family="blockFamily('pacientes')"
          :height="12"
          class="mb-4"
        />

        <div v-if="peopleView === 'list'" class="overflow-x-auto">
          <table class="w-full text-xs">
            <thead>
              <tr class="text-left text-[10px] text-n-slate-9">
                <th class="py-1.5 pr-3 font-semibold">Paciente</th>
                <th class="py-1.5 pr-3 font-semibold">1ª cirurgia</th>
                <th class="py-1.5 pr-3 font-semibold">Canal</th>
                <th class="py-1.5 pr-3 font-semibold">Campanha / origem</th>
                <th class="py-1.5 font-semibold text-right">
                  Receita no período
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="p in shownPeople"
                :key="p.key"
                style="border-top: 1px solid rgb(var(--cv-rgb) / 0.12)"
              >
                <td class="py-1.5 pr-3 text-n-slate-12 font-medium">
                  <a
                    v-if="contactHref(p.contact_id)"
                    :href="contactHref(p.contact_id)"
                    class="hover:underline"
                    >{{ p.name }}</a>
                  <span v-else>{{ p.name }}</span>
                </td>
                <td class="py-1.5 pr-3 text-n-slate-11 whitespace-nowrap">
                  {{ dateBR(p.date) }}
                </td>
                <td class="py-1.5 pr-3 whitespace-nowrap">
                  <span
                    class="inline-flex items-center gap-1.5 text-n-slate-11"
                  >
                    <span
                      class="w-2 h-2 rounded-full"
                      :style="{ background: CHANNEL_COLORS[p.channel] }"
                    />
                    {{
                      { google: 'Google', meta: 'Meta', organico: 'Orgânico' }[
                        p.channel
                      ]
                    }}
                  </span>
                </td>
                <td class="py-1.5 pr-3 text-n-slate-10 max-w-[18rem] truncate">
                  {{ p.campaign || p.detail }}
                </td>
                <td class="py-1.5 text-right text-n-slate-11">
                  {{ p.revenue ? moneyShort(p.revenue) : '—' }}
                </td>
              </tr>
            </tbody>
          </table>
          <p v-if="!shownPeople.length" class="text-[11px] text-n-slate-9 py-3">
            nenhum paciente operado nesse recorte
          </p>
        </div>
        <div
          v-else
          class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3"
        >
          <div v-for="p in shownPeople" :key="p.key" class="cv-sub p-3.5">
            <div class="flex items-center gap-2 mb-1">
              <span
                class="w-2.5 h-2.5 rounded-full flex-shrink-0"
                :style="{ background: CHANNEL_COLORS[p.channel] }"
              />
              <a
                v-if="contactHref(p.contact_id)"
                :href="contactHref(p.contact_id)"
                class="text-sm font-bold text-n-slate-12 truncate hover:underline"
                >{{ p.name }}</a>
              <span v-else class="text-sm font-bold text-n-slate-12 truncate">{{
                p.name
              }}</span>
            </div>
            <p class="text-[11px] text-n-slate-10 truncate">
              {{ p.campaign || p.detail }}
            </p>
            <p class="text-[11px] text-n-slate-9">
              1ª cirurgia {{ dateBR(p.date)
              }}<template v-if="p.revenue">
                · {{ moneyShort(p.revenue) }}
              </template>
            </p>
          </div>
        </div>
      </div>

      <!-- ══ OFTALMOFÁCIL (parceiros) — fora do CAC ══ -->
      <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('parceiros')">
        <div class="flex items-center gap-2 mb-1">
          <span class="cv-icon"><span class="i-lucide-handshake text-base"/></span>
          <h2 class="text-sm font-bold text-n-slate-12">
            Oftalmofácil (parceiros) — fora do CAC
          </h2>
        </div>
        <p class="text-[11px] text-n-slate-9 mb-4">
          pacientes dos parceiros do hub não vêm dos nossos anúncios: ficam
          aqui, à parte, para não baixar o CAC artificialmente.
        </p>
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <DashKpi
            compact
            glass
            label="Pacientes operados"
            :value="partner.patients || 0"
            sub="1ª cirurgia no período"
          />
          <DashKpi
            compact
            glass
            label="Valor das cirurgias"
            :value="moneyShort(partner.revenue)"
            sub="pago (ou cobrado) no Oftalmofácil"
          />
          <DashKpi
            compact
            glass
            label="O que fica para a CEVICO"
            :value="moneyShort(partner.result)"
            sub="cobrado − prestador − taxa da plataforma"
          />
        </div>
      </div>
    </template>
  </div>
</template>
