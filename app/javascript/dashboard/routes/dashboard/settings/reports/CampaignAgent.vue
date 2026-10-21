<script setup>
// 🎯 AGENTE DE CAMPANHAS (item 352, 19/10/2026 — "um sistema/dispositivo pra
// verificar resultados de campanha, indicadores primários/secundários/
// terciários, subir e otimizar campanhas"). Decisões dele: a régua é o NOSSO
// histórico (7/30/90/180/360 dias); estrela-guia = custo por agendamento
// (com modo custo por cirurgia para testes); autonomia = analisa → sugere →
// alguém aprova → aplica → aprende; tudo centralizado aqui e no Meu Painel.
//
// v2 (item 358, 21/10 — "organizar melhor este ambiente… visualização
// parecida com a página do iPhone… fácil de escolher se é Meta ou Google…
// precisa ser seguro e precisamos entender o tipo de otimização"):
// desenho HÍBRIDO igual ao da Análise de Páginas (item 353) — a história
// estilo Apple em cima (PagesStory: resultado, como o agente trabalha, o que
// ele otimiza, o que espera o seu ok, campeã, vazamento), seletor de canal
// grande com o estado de cada um, e os blocos do kit embaixo (números,
// caminho, campanhas, recomendações, aprendizado, nossa média); Ajustes e
// Subir campanha ficam em sanfona, fechados, para a tela não assustar.
// Filosofia: cada número diz de onde veio e com o que está sendo comparado.
import { ref, computed, onMounted, watch, nextTick } from 'vue';
import { useAlert } from 'dashboard/composables';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import HBars from 'dashboard/components-next/cevico/HBars.vue';
import TimelineChart from 'dashboard/components-next/cevico/TimelineChart.vue';
import DonutChart from 'dashboard/components-next/cevico/DonutChart.vue';
import CvRegua from 'dashboard/components-next/cevico/guia/CvRegua.vue';
import CvCabecalho from 'dashboard/components-next/cevico/guia/CvCabecalho.vue';
import CvBloco from 'dashboard/components-next/cevico/guia/CvBloco.vue';
import CvIndicador from 'dashboard/components-next/cevico/guia/CvIndicador.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import CrmAPI from 'dashboard/api/crm';
import PagesStory from '../../pages/PagesStory.vue';

const isLoading = ref(true);
const data = ref(null);
const period = ref({ preset: 'last7', from: '', to: '' });
const channel = ref('all');
const campaignView = ref('list');
const expanded = ref(new Set());
const queueFilter = ref('suggested');
const mediaChannel = ref('all');
const busy = ref(false);
const steps = ref(null); // { title, steps, action, error }
const confirmApply = ref(null); // recomendação esperando o "sim, aplique na Meta"
const openParams = ref(false); // sanfona dos Ajustes
const openLaunch = ref(false); // sanfona de Subir campanha

const pal = useCevicoPalette({
  scope: 'report:campaign_agent',
  // os ids são os dos CvBloco (id="bloco-<id>"): é por eles que a salada de
  // frutas e a fruta por bloco chegam a cada bloco
  blocks: [
    { id: 'primarios', label: 'Números', icon: 'i-lucide-target' },
    { id: 'graficos', label: 'Gráficos', icon: 'i-lucide-chart-line' },
    { id: 'secundarios', label: 'O caminho', icon: 'i-lucide-layers' },
    { id: 'campanhas', label: 'Campanhas', icon: 'i-lucide-megaphone' },
    {
      id: 'recomendacoes',
      label: 'Recomendações',
      icon: 'i-lucide-lightbulb',
    },
    {
      id: 'aprendizado',
      label: 'Aprendizado',
      icon: 'i-lucide-graduation-cap',
    },
    { id: 'media', label: 'Nossa média', icon: 'i-lucide-ruler' },
    {
      id: 'parametros',
      label: 'Ajustes',
      icon: 'i-lucide-sliders-horizontal',
    },
    { id: 'subir', label: 'Subir campanha', icon: 'i-lucide-rocket' },
  ],
});
const { cvVars } = pal;

const params = () => ({
  preset: period.value.preset,
  ...(period.value.preset === 'custom'
    ? { from: period.value.from, to: period.value.to }
    : {}),
  ...(channel.value !== 'all' ? { channel: channel.value } : {}),
});

// ── parâmetros (rascunho editável; nasce da primeira leitura) ──
const paramsDraft = ref(null);
const resetParams = () => {
  paramsDraft.value = JSON.parse(JSON.stringify(data.value?.params || {}));
};

const load = async (quiet = false) => {
  if (!quiet) isLoading.value = true;
  try {
    const { data: payload } = await CrmAPI.getCampaignAgent(params());
    data.value = payload;
    if (!paramsDraft.value) resetParams();
  } catch {
    useAlert('Não consegui ler as campanhas agora.');
  } finally {
    isLoading.value = false;
  }
};
watch([period, channel], () => load(), { deep: true });
onMounted(load);

// ── formatação ──
const fmtNum = v => Number(v || 0).toLocaleString('pt-BR');
const money = (v, digits = 2) =>
  `R$ ${Number(v || 0).toLocaleString('pt-BR', {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  })}`;
const moneyShort = v => money(v, 0);
const dash = (v, fmt = money) => (v === null || v === undefined ? '—' : fmt(v));
const pct = (v, digits = 1) =>
  v === null || v === undefined
    ? '—'
    : `${(Number(v) * 100).toLocaleString('pt-BR', {
        maximumFractionDigits: digits,
      })}%`;
const num = (v, digits = 1) =>
  v === null || v === undefined
    ? '—'
    : Number(v).toLocaleString('pt-BR', { maximumFractionDigits: digits });
const roasFmt = v => (v === null || v === undefined ? '—' : `${num(v, 2)}×`);
const dateBR = iso =>
  iso
    ? new Date(`${iso.slice(0, 10)}T12:00:00`).toLocaleDateString('pt-BR')
    : '';
const dateShort = iso =>
  iso
    ? new Date(`${iso.slice(0, 10)}T12:00:00`).toLocaleDateString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
      })
    : '';
const timeBR = iso =>
  iso
    ? new Date(iso).toLocaleString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '';
const plural = (n, one, many) => `${fmtNum(n)} ${Number(n) === 1 ? one : many}`;

const CHANNEL_LABEL = { all: 'Meta + Google', meta: 'Meta', google: 'Google' };
const CHANNEL_SHORT = {
  all: 'nos dois canais',
  meta: 'na Meta',
  google: 'no Google',
};
const CHANNEL_COLORS = { meta: '#bf5af2', google: '#0a84ff' };
const SEVERITY = {
  alerta: { label: 'alerta', tone: 'cvg-chip--problema' },
  atencao: { label: 'atenção', tone: 'cvg-chip--atencao' },
  oportunidade: { label: 'oportunidade', tone: 'cvg-chip--bom' },
  info: { label: 'aviso', tone: '' },
};
const KIND_LABEL = {
  pause: 'pausar',
  budget_up: 'subir verba',
  budget_down: 'reduzir verba',
  new_creative: 'criativo novo',
  audience: 'público',
  page: 'página',
  quality: 'qualidade do lead',
  pacing: 'ritmo da verba',
  watch: 'observar',
};
const KIND_ICON = {
  pause: 'i-lucide-pause-circle',
  budget_up: 'i-lucide-trending-up',
  budget_down: 'i-lucide-trending-down',
  new_creative: 'i-lucide-sparkles',
  audience: 'i-lucide-users',
  page: 'i-lucide-file-text',
  quality: 'i-lucide-message-square-heart',
  pacing: 'i-lucide-gauge',
  watch: 'i-lucide-eye',
};
const LEVEL_LABEL = {
  channel: 'canal',
  campaign: 'campanha',
  adset: 'conjunto',
  ad: 'anúncio',
};
// só verba e pausa mexem na plataforma; o resto é tarefa para a equipe
const PLATFORM_KINDS = new Set(['pause', 'budget_up', 'budget_down']);

// ── a leitura ──
const p = computed(() => data.value?.params || {});
const goal = computed(() => p.value.goal || 'booked');
const goalLabel = computed(() => data.value?.goal_label || '');
const goalWord = computed(() =>
  goal.value === 'surgery' ? 'cirurgia' : 'agendamento de consulta'
);
const totals = computed(() => data.value?.totals?.[channel.value] || {});
const previous = computed(() => data.value?.previous?.[channel.value] || {});
const baselineFor = ch => {
  const b = data.value?.baselines?.[ch] || {};
  const days = p.value.baseline_days || 30;
  const row = b[days] || b[String(days)];
  if (row && Number(row.spend) > 0) return row;
  const all = data.value?.baselines?.all || {};
  return all[days] || all[String(days)] || null;
};
const baseline = computed(() => baselineFor(channel.value));
const rate = (row, key) => row?.rates?.[key];
const periodoTxt = computed(() => {
  const per = data.value?.period;
  if (!per) return '';
  return `${dateShort(per.from)} a ${dateShort(per.to)} · ${plural(per.days, 'dia', 'dias')}`;
});
const channels = computed(() => data.value?.channels || {});
const canEdit = computed(() => Boolean(data.value?.can_edit));
const state = computed(() => data.value?.state || {});
const executeApi = computed(() => Boolean(channels.value.meta?.execute));

// bom / atenção / ruim contra a nossa média (custos: menor é melhor)
const LOWER = new Set([
  'cpl',
  'cost_booked',
  'cost_surgery',
  'cpm',
  'cpc',
  'goal_cost',
]);
const band = (value, base, key) => {
  if (value === null || value === undefined || !base) return null;
  const ratio = Number(value) / Number(base);
  const worse = 1 + (p.value.worse_pct || 30) / 100;
  const better = 1 - (p.value.better_pct || 30) / 100;
  if (LOWER.has(key)) {
    if (ratio >= worse) return 'ruim';
    if (ratio <= better) return 'bom';
    return 'atencao';
  }
  if (ratio <= 1 - (p.value.worse_pct || 30) / 100) return 'ruim';
  if (ratio >= 1 + (p.value.better_pct || 30) / 100) return 'bom';
  return 'atencao';
};
const BAND = {
  bom: {
    label: 'melhor que a nossa média',
    chip: 'cvg-chip--bom',
    estado: 'bom',
    tone: 'bom',
  },
  atencao: {
    label: 'na nossa média',
    chip: '',
    estado: 'neutro',
    tone: '',
  },
  ruim: {
    label: 'pior que a nossa média',
    chip: 'cvg-chip--problema',
    estado: 'problema',
    tone: 'problema',
  },
};
const pctDiff = (value, base) => {
  if (!base || value === null || value === undefined) return '';
  const d = (Number(value) / Number(base) - 1) * 100;
  if (Math.abs(d) < 1) return 'igual à nossa média';
  return `${d > 0 ? '+' : '−'}${num(Math.abs(d), 0)}% vs a nossa média`;
};
// comparação de um CUSTO/TAXA com a nossa média → { texto, estado }
const cmpBase = (value, key, fmt = moneyShort) => {
  const b = baseline.value;
  if (!b) return { texto: 'sem média ainda', estado: 'neutro' };
  let base = key.startsWith('rates.') ? b.rates?.[key.slice(6)] : b[key];
  if (key === 'goal_cost') base = b.goal_cost;
  if (
    base === null ||
    base === undefined ||
    value === null ||
    value === undefined
  )
    return {
      texto: `nossa média ${b.days}d: ${dash(base, fmt)}`,
      estado: 'neutro',
    };
  const k = band(value, base, key.replace('rates.', ''));
  return {
    texto: `${pctDiff(value, base)} (${dash(base, fmt)})`,
    estado: BAND[k]?.estado || 'neutro',
  };
};
// comparação de um TOTAL com o período igual anterior → { texto, estado, seta }
const cmpPrev = (value, prev) => {
  const v = Number(value || 0);
  const pv = Number(prev || 0);
  if (!pv) return { texto: 'antes: 0', estado: 'neutro' };
  const d = ((v - pv) / pv) * 100;
  if (Math.abs(d) < 1)
    return { texto: 'igual ao período anterior', estado: 'neutro' };
  return {
    texto: `${num(Math.abs(d), 0)}% vs período anterior (${fmtNum(pv)})`,
    estado: d > 0 ? 'bom' : 'atencao',
    seta: true,
  };
};
const goalVerdict = computed(() => {
  const v = totals.value.goal_cost;
  const b = baseline.value?.goal_cost;
  const k = band(v, b, 'goal_cost');
  if (!k) return null;
  return { ...BAND[k], ratio: Number(v) / Number(b) };
});

// secundários e terciários, por canal, com a nossa média ao lado
const SECONDARY = [
  {
    key: 'ctr',
    label: 'CTR (clique por exibição)',
    fmt: v => pct(v, 2),
    hint: 'de cada 100 exibições, quantas viraram clique no link',
  },
  {
    key: 'cpm',
    label: 'CPM (custo por mil exibições)',
    fmt: money,
    hint: 'quanto custa aparecer mil vezes',
  },
  {
    key: 'cpc',
    label: 'CPC (custo por clique)',
    fmt: money,
    hint: 'quanto custa cada clique',
  },
  {
    key: 'frequency',
    label: 'Frequência',
    fmt: v => num(v, 2),
    raw: true,
    hint: 'quantas vezes a mesma pessoa viu (Meta)',
  },
  {
    key: 'conv_rate',
    label: 'Conversa por clique',
    fmt: pct,
    hint: 'cliques que abriram conversa no WhatsApp (Meta)',
  },
  {
    key: 'lead_rate',
    label: 'Lead por clique',
    fmt: pct,
    hint: 'cliques que viraram lead no atendimento (é a página / a mensagem pronta)',
  },
  {
    key: 'hook_rate',
    label: 'Gancho (parada em 3 s)',
    fmt: pct,
    hint: 'exibições que pararam para ver 3 segundos (vídeo)',
  },
  {
    key: 'hold_rate',
    label: 'Retenção (ThruPlay)',
    fmt: pct,
    hint: 'de quem parou, quantos viram quase todo (vídeo)',
  },
];
const TERTIARY = [
  {
    key: 'booking_rate',
    label: 'Taxa de agendamento',
    fmt: pct,
    hint: 'leads que marcaram consulta',
  },
  {
    key: 'attend_rate',
    label: 'Comparecimento',
    fmt: pct,
    hint: 'de quem marcou, quantos vieram',
  },
  {
    key: 'close_rate',
    label: 'Fechamento',
    fmt: pct,
    hint: 'de quem veio, quantos fecharam cirurgia',
  },
  {
    key: 'surgery_rate',
    label: 'Cirurgia por lead',
    fmt: pct,
    hint: 'leads que já operaram',
  },
  {
    key: 'time_to_book',
    label: 'Tempo até agendar (mediana)',
    fmt: v => (v === null || v === undefined ? '—' : `${num(v)} dia(s)`),
    special: true,
    hint: 'dias entre chegar e marcar a consulta',
  },
];
const channelsShown = computed(() =>
  channel.value === 'all' ? ['all', 'meta', 'google'] : [channel.value]
);
const indicatorValue = (ind, ch) => {
  if (ind.special) return data.value?.time_to_book?.[ch]?.median_days;
  const row = data.value?.totals?.[ch];
  return ind.raw ? row?.[ind.key] : row?.rates?.[ind.key];
};
const indicatorBase = (ind, ch) => {
  if (ind.special) return undefined;
  const b = baselineFor(ch);
  return ind.raw ? b?.[ind.key] : b?.rates?.[ind.key];
};
const indicatorClass = (ind, ch) => {
  if (ind.special || ind.raw) return '';
  const k = band(indicatorValue(ind, ch), indicatorBase(ind, ch), ind.key);
  if (k === 'bom') return 'cvg-bom';
  return k === 'ruim' ? 'cvg-problema' : '';
};

// ── campanhas em três níveis ──
const campaigns = computed(() => data.value?.campaigns || []);
const toggle = id => {
  const s = new Set(expanded.value);
  if (s.has(id)) s.delete(id);
  else s.add(id);
  expanded.value = s;
};
const visibleRows = computed(() => {
  const out = [];
  campaigns.value.forEach(c => {
    out.push({
      ...c,
      depth: 0,
      open: expanded.value.has(c.id),
      hasChildren: (c.children || []).length > 0,
    });
    if (!expanded.value.has(c.id)) return;
    (c.children || []).forEach(s => {
      const sid = `${c.id}/${s.id}`;
      out.push({
        ...s,
        depth: 1,
        open: expanded.value.has(sid),
        hasChildren: (s.children || []).length > 0,
        rowKey: sid,
      });
      if (!expanded.value.has(sid)) return;
      (s.children || []).forEach(a =>
        out.push({
          ...a,
          depth: 2,
          hasChildren: false,
          rowKey: `${sid}/${a.id}`,
        })
      );
    });
  });
  return out;
});
const goalBand = row =>
  BAND[band(row.goal_cost, baselineFor(row.channel)?.goal_cost, 'goal_cost')] ||
  null;
const goalBandShort = row => {
  const gb = goalBand(row);
  if (!gb) return '';
  return gb.label
    .replace(' que a nossa média', '')
    .replace('na nossa média', 'na média');
};
const campaignBars = computed(() =>
  campaigns.value
    .filter(c => c.goal_cost)
    .map(c => ({
      label: c.name,
      sub: CHANNEL_LABEL[c.channel],
      values: [c.goal_cost],
      color:
        { bom: '#059669', problema: '#dc2626' }[goalBand(c)?.estado] ||
        CHANNEL_COLORS[c.channel],
    }))
);
const openActionsOf = row =>
  (data.value?.actions?.open || []).filter(
    a => a.ref_id === String(row.id) && a.channel === row.channel
  );
const adsCount = c =>
  (c.children || []).reduce((n, s) => n + (s.children?.length || 0), 0);

// ── gráficos (358c): dia a dia, fatias e a régua contra a nossa média ──
const series = computed(() => data.value?.series || null);
const seriesCh = computed(() => series.value?.[channel.value] || null);
// a nossa média POR DIA (gasto já vem por dia; leads/agendamentos = total ÷ dias)
const dailyAvg = key => {
  const b = baseline.value;
  if (!b) return 0;
  if (key === 'spend') return Number(b.daily_spend || 0);
  return Number(b[key] || 0) / Number(b.days || 1);
};
const CHART = {
  spend: 'var(--cv, #2563eb)',
  leads: '#0a84ff',
  booked: '#059669',
};
const timelineBars = computed(() =>
  seriesCh.value
    ? {
        key: 'spend',
        label: 'Investido',
        color: CHART.spend,
        values: seriesCh.value.spend,
      }
    : null
);
const timelineLines = computed(() =>
  seriesCh.value
    ? [
        {
          key: 'leads',
          label: 'Leads',
          color: CHART.leads,
          values: seriesCh.value.leads,
        },
        {
          key: 'booked',
          label: 'Agendamentos',
          color: CHART.booked,
          values: seriesCh.value.booked,
        },
      ]
    : []
);
const timelineRefs = computed(() =>
  [
    {
      axis: 'left',
      value: dailyAvg('spend'),
      label: 'média/dia',
      color: 'var(--g-texto, #111827)',
    },
    {
      axis: 'right',
      value: dailyAvg('leads'),
      label: 'média de leads/dia',
      color: CHART.leads,
    },
  ].filter(r => r.value > 0)
);
const timelineTip = i => {
  const s = seriesCh.value;
  if (!s) return null;
  return {
    title: series.value.labels[i],
    rows: [
      {
        color: CHART.spend,
        label: 'Investido',
        value: moneyShort(s.spend[i]),
        square: true,
      },
      { color: CHART.leads, label: 'Leads', value: fmtNum(s.leads[i]) },
      {
        color: CHART.booked,
        label: 'Agendaram (dos que chegaram neste dia)',
        value: fmtNum(s.booked[i]),
      },
    ],
  };
};
// fatias: por canal (os dois) ou por campanha (um canal só)
const SLICE_COLORS = [
  '#2563eb',
  '#7c3aed',
  '#059669',
  '#d97706',
  '#dc2626',
  '#0891b2',
];
const donut = key => {
  if (channel.value === 'all')
    return ['meta', 'google'].map(ch => ({
      key: ch,
      label: CHANNEL_LABEL[ch],
      value: data.value?.totals?.[ch]?.[key] || 0,
      color: CHANNEL_COLORS[ch],
    }));
  return campaigns.value
    .filter(c => !String(c.id).includes('untracked'))
    .map((c, i) => ({
      key: `${c.channel}-${c.id}`,
      label: c.name,
      value: c[key] || 0,
      color: SLICE_COLORS[i % SLICE_COLORS.length],
    }));
};
const donutSpend = computed(() => donut('spend'));
const donutLeads = computed(() => donut('leads'));
const donutBooked = computed(() => donut('booked'));
// a régua: seis indicadores contra a nossa média, nos limiares do agente
const reguaItems = computed(() => {
  const t = totals.value;
  const b = baseline.value;
  const r = (row, k) => row?.rates?.[k];
  return [
    {
      key: 'goal',
      label: `⭐ ${goalLabel.value}`,
      value: t.goal_cost,
      avg: b?.goal_cost,
      lower: true,
      fmt: moneyShort,
      hint: 'investido ÷ resultados · menor é melhor',
    },
    {
      key: 'cpl',
      label: 'Custo por lead (CPL)',
      value: r(t, 'cpl'),
      avg: r(b, 'cpl'),
      lower: true,
      fmt: moneyShort,
      hint: 'investido ÷ leads · menor é melhor',
    },
    {
      key: 'ctr',
      label: 'CTR (clique por exibição)',
      value: r(t, 'ctr'),
      avg: r(b, 'ctr'),
      lower: false,
      fmt: v => pct(v, 2),
      hint: 'de cada 100 exibições, quantas clicaram · maior é melhor',
    },
    {
      key: 'cpm',
      label: 'CPM (custo por mil exibições)',
      value: r(t, 'cpm'),
      avg: r(b, 'cpm'),
      lower: true,
      fmt: money,
      hint: 'quanto custa aparecer mil vezes · menor é melhor',
    },
    {
      key: 'lead_rate',
      label: 'Lead por clique',
      value: r(t, 'lead_rate'),
      avg: r(b, 'lead_rate'),
      lower: false,
      fmt: pct,
      hint: 'cliques que viraram lead · maior é melhor',
    },
    {
      key: 'booking_rate',
      label: 'Taxa de agendamento',
      value: r(t, 'booking_rate'),
      avg: r(b, 'booking_rate'),
      lower: false,
      fmt: pct,
      hint: 'leads que marcaram consulta · maior é melhor',
    },
  ];
});
// barras das campanhas: a média do canal como traço (a cor pelo veredito está em campaignBars)
const campaignRef = computed(() =>
  baseline.value?.goal_cost
    ? {
        value: baseline.value.goal_cost,
        label: `a nossa média (${CHANNEL_LABEL[channel.value]}, ${baseline.value.days} dias)`,
        color: 'var(--g-texto, #111827)',
      }
    : null
);

// ── recomendações ──
const QUEUE_TABS = [
  ['suggested', 'Esperando o seu ok'],
  ['approved', 'Aprovadas, falta fazer'],
  ['applied', 'Feitas · aprendendo'],
  ['dismissed', 'Descartadas'],
];
const allActions = computed(() => [
  ...(data.value?.actions?.open || []),
  ...(data.value?.actions?.history || []),
]);
const inChannel = a => channel.value === 'all' || a.channel === channel.value;
const queueOf = status =>
  allActions.value.filter(
    a =>
      inChannel(a) &&
      (status === 'dismissed'
        ? ['dismissed', 'expired'].includes(a.status)
        : a.status === status)
  );
const queueCount = status => queueOf(status).length;
const queue = computed(() => queueOf(queueFilter.value));
const learningLeft = a => {
  if (!a.applied_at) return null;
  const days = p.value.learning_days || 7;
  const end = new Date(a.applied_at);
  end.setDate(end.getDate() + days + 1);
  const left = Math.ceil((end - new Date()) / 86400000);
  return left > 0 ? left : 0;
};
const OUTCOME = {
  better: { label: 'melhorou', tone: 'cvg-chip--bom' },
  worse: { label: 'piorou', tone: 'cvg-chip--problema' },
  same: { label: 'ficou igual', tone: 'cvg-chip--atencao' },
  saved: { label: 'economizou', tone: 'cvg-chip--bom' },
  early: { label: 'ainda cedo', tone: '' },
};
const beforeAfter = a => {
  const b = a.metrics_before || {};
  const af = a.metrics_after || {};
  if (!a.learned_at) return '';
  return `custo por ${goal.value === 'surgery' ? 'cirurgia' : 'agendamento'} ${dash(b.goal_cost, moneyShort)} → ${dash(af.goal_cost, moneyShort)} · gasto ${moneyShort(b.spend)} → ${moneyShort(af.spend)} · resultados ${fmtNum(b.goal_events)} → ${fmtNum(af.goal_events)}`;
};
// aplica pela API? só verba/pausa, só Meta, só com a chavinha ligada
const viaApi = a =>
  PLATFORM_KINDS.has(a.kind) && a.channel === 'meta' && executeApi.value;
// o que acontece se aprovar: na plataforma (pela API ou à mão) ou tarefa para a equipe
const howApplies = a => {
  if (!PLATFORM_KINDS.has(a.kind))
    return 'tarefa para a equipe · nada muda na plataforma';
  if (viaApi(a)) return 'mexe na Meta pela API, só depois do seu ok';
  return `mexe no ${a.channel === 'meta' ? 'Gerenciador da Meta' : 'Google Ads'} · à mão, com passo a passo`;
};
const applyLabel = a =>
  viaApi(a) ? 'Aplicar na Meta (API)' : 'Ver passo a passo';
const applyActions = payload => {
  data.value = {
    ...data.value,
    actions: payload.actions || data.value.actions,
  };
};
const decide = async (a, decision) => {
  if (busy.value) return;
  busy.value = true;
  try {
    const { data: out } = await CrmAPI.decideCampaignAction(a.id, decision);
    applyActions(out);
    if (decision === 'approve') queueFilter.value = 'approved';
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui decidir agora.');
  } finally {
    busy.value = false;
  }
};
const apply = async a => {
  if (busy.value) return;
  busy.value = true;
  confirmApply.value = null;
  try {
    const { data: out } = await CrmAPI.applyCampaignAction(a.id);
    applyActions(out);
    if (out.mode === 'api')
      useAlert('Aplicado na Meta. O antes × depois começa a contar.');
    else steps.value = { title: a.title, steps: out.steps, action: a };
  } catch (error) {
    const out = error?.response?.data || {};
    if (out.steps)
      steps.value = {
        title: a.title,
        steps: out.steps,
        action: a,
        error: out.error,
      };
    else useAlert(out.error || 'Não consegui aplicar agora.');
    if (out.actions) applyActions(out);
  } finally {
    busy.value = false;
  }
};
// pela API, pede confirmação antes (segurança): mostra o que vai mudar
const askApply = a => {
  if (viaApi(a)) confirmApply.value = a;
  else apply(a);
};
const markManual = async a => {
  if (busy.value) return;
  busy.value = true;
  try {
    const { data: out } = await CrmAPI.manualCampaignAction(a.id);
    applyActions(out);
    steps.value = null;
    useAlert('Marcada como feita. O antes × depois começa a contar.');
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui marcar.');
  } finally {
    busy.value = false;
  }
};
const isRunning = ref(false);
const runNow = async () => {
  if (isRunning.value) return;
  isRunning.value = true;
  try {
    await CrmAPI.runCampaignAgent();
    useAlert('Pedi a leitura. Em 1 minuto as recomendações aparecem aqui.');
    setTimeout(() => load(true), 40000);
  } catch {
    useAlert('Não consegui pedir a leitura agora.');
  } finally {
    isRunning.value = false;
  }
};
const scoreboard = computed(() => data.value?.scoreboard || []);
const confidenceChip = c => {
  if (c >= 0.6) return 'cvg-chip--bom';
  return c < 0.4 ? 'cvg-chip--problema' : 'cvg-chip--atencao';
};

// ── nossa média ──
const WINDOWS = [7, 30, 90, 180, 360];
const mediaRows = computed(() => {
  const b = data.value?.baselines?.[mediaChannel.value] || {};
  return WINDOWS.map(d => b[d] || b[String(d)] || { days: d });
});
const MEDIA_COLS = [
  { label: 'Gasto/dia', get: r => moneyShort(r.daily_spend) },
  { label: 'Leads', get: r => fmtNum(r.leads) },
  { label: 'CPL', get: r => dash(r.rates?.cpl, moneyShort) },
  { label: 'Agend.', get: r => fmtNum(r.booked) },
  { label: 'Custo/agend.', get: r => dash(r.rates?.cost_booked, moneyShort) },
  { label: 'Cirurgias', get: r => fmtNum(r.surgeries) },
  { label: 'CAC', get: r => dash(r.rates?.cost_surgery, moneyShort) },
  { label: 'ROAS', get: r => roasFmt(r.rates?.roas) },
  { label: 'CTR', get: r => pct(r.rates?.ctr, 2) },
  { label: 'CPM', get: r => dash(r.rates?.cpm, money) },
  { label: 'CPC', get: r => dash(r.rates?.cpc, money) },
  { label: 'Tx. agend.', get: r => pct(r.rates?.booking_rate) },
];
const isRegua = r => Number(r.days) === Number(p.value.baseline_days);

const isSavingParams = ref(false);
const saveParams = async () => {
  if (isSavingParams.value) return;
  isSavingParams.value = true;
  try {
    const { data: out } = await CrmAPI.saveCampaignAgentParams(
      paramsDraft.value
    );
    data.value = { ...data.value, params: out.params };
    resetParams();
    useAlert('Parâmetros guardados. Valem na próxima leitura.');
    load(true);
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui guardar.');
  } finally {
    isSavingParams.value = false;
  }
};
const SWITCHES = [
  ['enabled', 'Agente ligado', 'desligado = não lê, não sugere'],
  [
    'execute_api',
    'Aplicar na Meta pela API',
    'precisa de token com ads_management; desligado = passo a passo para fazer à mão; ligado = verba e pausa saem pela API depois do seu ok e de uma confirmação',
  ],
  ['weekend', 'Não sugerir no fim de semana', ''],
  [
    'brief_ai',
    'Resumo diário escrito pela IA',
    'haiku, barato; os números são do sistema',
  ],
];

// ── ficha de subir campanha ──
const brief = ref({
  channel: 'meta',
  name: '',
  objective: 'leads_whatsapp',
  daily_budget: '',
  whatsapp: '',
  page_url: '',
  page_id: '',
  audience: { countries: ['BR'], cities: '', age_min: 25, age_max: 65 },
  creative_ad_ids: [],
  notes: '',
});
const toggleCreative = id => {
  const list = brief.value.creative_ad_ids;
  const i = list.indexOf(id);
  if (i >= 0) list.splice(i, 1);
  else if (list.length < 10) list.push(id);
};
const isPlanning = ref(false);
const planBrief = async () => {
  if (isPlanning.value) return;
  isPlanning.value = true;
  try {
    const { data: out } = await CrmAPI.saveCampaignBrief(brief.value);
    data.value = { ...data.value, briefs: out.briefs };
    useAlert('Plano montado e ficha guardada.');
    brief.value = {
      ...brief.value,
      name: '',
      daily_budget: '',
      creative_ad_ids: [],
      notes: '',
    };
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui montar o plano.');
  } finally {
    isPlanning.value = false;
  }
};
const launch = async b => {
  if (busy.value) return;
  busy.value = true;
  try {
    const { data: out } = await CrmAPI.launchCampaignBrief(b.id);
    data.value = { ...data.value, briefs: out.briefs };
    useAlert('Criada PAUSADA na Meta. Confira no Gerenciador e ligue.');
  } catch (error) {
    const out = error?.response?.data || {};
    if (out.briefs) data.value = { ...data.value, briefs: out.briefs };
    useAlert(out.error || 'Não consegui criar.');
  } finally {
    busy.value = false;
  }
};
const removeBrief = async b => {
  try {
    const { data: out } = await CrmAPI.removeCampaignBrief(b.id);
    data.value = { ...data.value, briefs: out.briefs };
  } catch {
    useAlert('Não consegui apagar.');
  }
};
const copy = async text => {
  try {
    await copyTextToClipboard(text);
    useAlert('Copiado.');
  } catch {
    useAlert('Não consegui copiar.');
  }
};
const briefs = computed(() => data.value?.briefs || []);
const creatives = computed(() => data.value?.creatives || []);

// ── o seletor de canal: o que cada um é e como o agente mexe nele ──
const channelTiles = computed(() => {
  const m = channels.value.meta || {};
  const g = channels.value.google || {};
  // antes da primeira leitura não dá para dizer se o canal está ligado
  const lendo = { text: 'lendo…', estado: 'neutro' };
  let metaStatus = {
    text: 'não ligada · Integrações → Meta Ads',
    estado: 'problema',
  };
  if (m.configured)
    metaStatus = executeApi.value
      ? { text: 'ligada · aplica verba e pausa pela API', estado: 'bom' }
      : { text: 'ligada · ajustes à mão, com passo a passo', estado: 'neutro' };
  const googleStatus = g.configured
    ? { text: 'ligado · só leitura (custo pelo GA4)', estado: 'neutro' }
    : { text: 'não ligado · Integrações → Google', estado: 'problema' };
  return [
    {
      key: 'all',
      label: 'Meta + Google',
      status: { text: 'os dois canais somados', estado: 'neutro' },
      icon: 'i-lucide-layers',
    },
    {
      key: 'meta',
      label: 'Meta',
      status: data.value ? metaStatus : lendo,
      icon: 'i-lucide-facebook',
    },
    {
      key: 'google',
      label: 'Google',
      status: data.value ? googleStatus : lendo,
      icon: 'i-lucide-search',
    },
  ];
});
const estadoClass = estado =>
  estado === 'neutro' ? 'cvg-texto-2' : `cvg-${estado}`;

// ── a história (gramática Apple, PagesStory) ──
const minTxt = computed(() => {
  const m = p.value.min || {};
  return `${moneyShort(m.spend)} gastos, ${fmtNum(m.impressions)} exibições, ${fmtNum(m.clicks)} cliques e ${fmtNum(m.leads)} leads`;
});
const champion = computed(() => {
  const m = p.value.min || {};
  const minEv = Number(m.goal_events || 3);
  return campaigns.value
    .filter(c => c.goal_cost && Number(c.goal_events ?? c.booked) >= minEv)
    .sort((a, b) => Number(a.goal_cost) - Number(b.goal_cost))[0];
});
const leak = computed(() => {
  const t = totals.value;
  const b = baseline.value;
  if (!b) return null;
  const steps3 = [
    {
      key: 'ctr',
      label: 'exibição → clique',
      value: rate(t, 'ctr'),
      avg: rate(b, 'ctr'),
      text: 'Muita gente vê e pouca gente clica: é o anúncio (gancho, imagem, promessa).',
    },
    {
      key: 'lead_rate',
      label: 'clique → lead',
      value: rate(t, 'lead_rate'),
      avg: rate(b, 'lead_rate'),
      text: 'Clica e não vira lead: é a página ou a mensagem pronta do WhatsApp.',
    },
    {
      key: 'booking_rate',
      label: 'lead → consulta marcada',
      value: rate(t, 'booking_rate'),
      avg: rate(b, 'booking_rate'),
      text: 'O lead chega e não marca: público, promessa do anúncio e atendimento não estão falando a mesma língua.',
    },
  ].filter(x => x.value !== null && x.value !== undefined && x.avg);
  const worst = steps3
    .map(x => ({ ...x, gap: (x.avg - x.value) / x.avg }))
    .sort((x, y) => y.gap - x.gap)[0];
  return worst && worst.gap > 0.1 ? worst : null;
});
const capitalize = s => (s ? `${s.charAt(0).toUpperCase()}${s.slice(1)}` : '');
const story = computed(() => {
  if (!data.value) return [];
  const t = totals.value;
  const b = baseline.value;
  const out = [];
  const chips = [];
  if (goalVerdict.value)
    chips.push({
      text: `${goalVerdict.value.label} (${num(goalVerdict.value.ratio, 2)}×)`,
      tone: goalVerdict.value.tone,
    });
  const events = goal.value === 'surgery' ? t.surgeries : t.booked;
  const eventTitle =
    goal.value === 'surgery'
      ? plural(events, 'cirurgia veio', 'cirurgias vieram')
      : plural(events, 'pessoa marcou consulta', 'pessoas marcaram consulta');
  out.push({
    key: 'resultado',
    kicker: `${CHANNEL_LABEL[channel.value]} · ${periodoTxt.value}`,
    title: Number(events)
      ? `${eventTitle} pelos anúncios.`
      : `Nenhum ${goalWord.value} veio dos anúncios neste período.`,
    number: t.goal_cost ? moneyShort(t.goal_cost) : null,
    sub: `por ${goalWord.value} · a estrela-guia`,
    text: `${moneyShort(t.spend)} investidos ${CHANNEL_SHORT[channel.value]} · ${plural(t.leads, 'lead', 'leads')} · ${plural(t.booked, 'agendamento', 'agendamentos')} · ${plural(t.surgeries, 'cirurgia', 'cirurgias')}.${b?.goal_cost ? ` A nossa média de ${b.days} dias é ${moneyShort(b.goal_cost)} por ${goalWord.value}.` : ' Ainda não há média da casa para comparar.'}${t.goal_cost ? '' : ` Sem ${goalWord.value} no período, a estrela-guia ainda não tem valor.`}`,
    tone: 'dia',
    chips,
    cta: { label: 'Ver os números', key: 'primarios' },
  });
  const m = channels.value.meta || {};
  const g = channels.value.google || {};
  let metaChip = { text: 'Meta: não ligada', tone: 'problema' };
  if (m.configured)
    metaChip = executeApi.value
      ? { text: 'Meta: aplica pela API, só depois do seu ok', tone: 'bom' }
      : { text: 'Meta: API desligada · tudo à mão', tone: '' };
  out.push({
    key: 'seguranca',
    kicker: 'Como o agente trabalha',
    title: 'Nada muda sem o seu ok.',
    text: `Toda madrugada ele lê os últimos ${p.value.window_days} dias e compara com a nossa média de ${p.value.baseline_days} dias. Só fala quando há volume: ${minTxt.value}. Abaixo disso é ruído, não sinal.`,
    tone: 'neutro',
    chips: [
      metaChip,
      {
        text: g.configured ? 'Google: só leitura' : 'Google: não ligado',
        tone: g.configured ? '' : 'problema',
      },
      { text: `Aprende ${p.value.learning_days} dias depois`, tone: '' },
    ],
    items: [
      {
        title: 'Lê',
        sub: 'Gasto, exibições e cliques da Meta (por anúncio) e do Google (por campanha). Leads, consultas e cirurgias vêm do nosso CRM, Agenda e Oftalmofácil.',
      },
      {
        title: 'Compara com a nossa média',
        sub: `Nunca com número de mercado: a régua é o que a CEVICO já fez nos últimos ${p.value.baseline_days} dias. "Jogamos o nosso próprio jogo."`,
      },
      {
        title: 'Sugere',
        sub: 'Cada recomendação diz o que viu, o que quer fazer e o que espera ganhar. Vai para a fila "Esperando o seu ok".',
      },
      {
        title: 'Você aprova ou descarta',
        sub: 'Aprovar não muda nada ainda: só autoriza o próximo passo.',
      },
      {
        title: 'Aplica',
        sub: executeApi.value
          ? 'Verba e pausa na Meta saem pela API, com confirmação antes. Criativo, público, página e qualidade são tarefas para a equipe. No Google tudo é à mão.'
          : 'Hoje tudo é à mão: ele mostra o passo a passo para fazer no Gerenciador e você marca "Fiz à mão". A chavinha da API da Meta está desligada.',
      },
      {
        title: 'Aprende',
        sub: `${p.value.learning_days} dias depois mede o antes × depois. Regra que erra mais do que acerta entra em observação e passa a só avisar.`,
      },
    ],
    cta: { label: 'Ver os ajustes', key: 'parametros' },
  });
  out.push({
    key: 'otimizacao',
    kicker: 'O que ele otimiza',
    title: 'Seis tipos de ajuste, todos a serviço da estrela-guia.',
    text: 'Só verba e pausa mexem na plataforma. Os outros quatro viram tarefas para a equipe, porque o problema não está no leilão: está no anúncio, no público, na página ou no atendimento.',
    tone: 'neutro',
    items: [
      {
        title: 'Verba',
        sub: `Campeã (${p.value.better_pct}% melhor que a média, com volume) → sobe ${p.value.budget_step_pct}%. Custo ${p.value.worse_pct}% acima da média → reduz ${p.value.budget_step_pct}%. Duas vezes a média, ou gasto sem nenhum resultado → pausar.`,
      },
      {
        title: 'Criativo',
        sub: 'Anúncio cansado (frequência alta e CTR caindo) ou com poucos cliques para tanta exibição → pedir variações ao núcleo criativo.',
      },
      {
        title: 'Público',
        sub: 'Exibição cara (CPM bem acima da média) → rever público e posicionamentos do conjunto.',
      },
      {
        title: 'Página',
        sub: 'Clica muito e vira pouco lead → o problema é a página ou a mensagem pronta, não o anúncio.',
      },
      {
        title: 'Qualidade do lead',
        sub: 'Lead chega e não agenda → apertar o público e alinhar o texto do anúncio com o Roteiro do atendimento.',
      },
      {
        title: 'Ritmo da verba',
        sub: `Mês gastando abaixo ou acima dos ${moneyShort(p.value.budget?.meta)} (Meta) e ${moneyShort(p.value.budget?.google)} (Google) combinados → redistribuir.`,
      },
    ],
    cta: { label: 'Ver as recomendações', key: 'recomendacoes' },
  });
  const open = queueOf('suggested');
  let agentText = '';
  if (!open.length)
    agentText = state.value.last_run_at
      ? `Última leitura ${timeBR(state.value.last_run_at)}. As próximas saem toda madrugada; "Ler agora" força uma leitura.`
      : 'O agente ainda não leu. Peça com "Ler agora", no topo.';
  out.push({
    key: 'agente',
    kicker: 'O agente recomenda',
    title: open.length
      ? `${open.length === 1 ? '1 recomendação espera' : `${open.length} recomendações esperam`} o seu ok.`
      : 'Nada esperando o seu ok agora.',
    text: agentText,
    items: open.slice(0, 3).map(a => ({
      title: `${KIND_LABEL[a.kind] || a.kind} · ${a.title}`,
      sub: `${a.ref_name ? `${a.ref_name} · ` : ''}${a.suggestion}`,
    })),
    tone: 'neutro',
    cta: {
      label: open.length ? 'Decidir agora' : 'Ver o histórico',
      key: 'recomendacoes',
    },
  });
  if (champion.value) {
    const c = champion.value;
    const cb = baselineFor(c.channel)?.goal_cost;
    out.push({
      key: 'campea',
      kicker: 'A campeã do período',
      title: c.name,
      number: moneyShort(c.goal_cost),
      sub: `por ${goalWord.value} · ${CHANNEL_LABEL[c.channel]} · ${moneyShort(c.spend)} investidos, ${plural(c.leads, 'lead', 'leads')}, ${plural(c.booked, 'agendamento', 'agendamentos')}`,
      text: goalBand(c)
        ? `${capitalize(goalBand(c).label)} do canal${cb ? ` (${moneyShort(cb)})` : ''}.`
        : '',
      tone: 'bom',
      cta: { label: 'Ver todas as campanhas', key: 'campanhas' },
    });
  }
  if (leak.value)
    out.push({
      key: 'vazamento',
      kicker: 'Onde o funil vaza',
      title: `O degrau mais fraco é ${leak.value.label}.`,
      number: pct(leak.value.value, 1),
      sub: `contra ${pct(leak.value.avg, 1)} da nossa média de ${b?.days} dias`,
      text: leak.value.text,
      tone: 'atencao',
      cta: { label: 'Ver o caminho', key: 'secundarios' },
    });
  return out;
});
const STORY_KEYS = [
  'resultado',
  'seguranca',
  'otimizacao',
  'agente',
  'campea',
  'vazamento',
];
const storyIndex = computed(() => {
  const keys = new Set(story.value.map(x => x.key));
  return [
    { key: 'resultado', label: 'Resultado' },
    { key: 'seguranca', label: 'Como trabalha' },
    { key: 'otimizacao', label: 'O que otimiza' },
    { key: 'agente', label: 'Agente' },
    { key: 'campea', label: 'Campeã' },
    { key: 'vazamento', label: 'Vazamento' },
    { key: 'primarios', label: 'Números' },
    { key: 'graficos', label: 'Gráficos' },
    { key: 'secundarios', label: 'Caminho' },
    { key: 'campanhas', label: 'Campanhas' },
    { key: 'recomendacoes', label: 'Recomendações' },
    { key: 'aprendizado', label: 'Aprendizado' },
    { key: 'media', label: 'Nossa média' },
    { key: 'parametros', label: 'Ajustes' },
    { key: 'subir', label: 'Subir campanha' },
  ].filter(i => keys.has(i.key) || !STORY_KEYS.includes(i.key));
});
const goTo = async key => {
  if (key === 'parametros') openParams.value = true;
  if (key === 'subir') openLaunch.value = true;
  await nextTick();
  const el =
    document.getElementById(`cvs-${key}`) ||
    document.getElementById(`bloco-${key}`);
  el?.scrollIntoView({ behavior: 'smooth', block: 'start' });
};
</script>

<template>
  <!-- tela só em português (CEVICO): textos direto no template, sem i18n -->
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <!-- w-full + min-w-0: nunca estica além da tela; h-full + overflow-y-auto: a própria tela rola até o fim -->
  <div
    class="cv-page cv-overlay cvg-page ca-page h-full w-full min-w-0 overflow-y-auto"
    :style="cvVars"
  >
    <CvCabecalho
      :pal="pal"
      title="Campanhas"
      subtitle="Meta e Google lidos contra a nossa própria média. O agente sugere, você aprova, ele aprende — nada muda sem o seu ok."
      icon="i-lucide-target"
    >
      <template #acoes>
        <span v-if="data" class="cvg-legenda ca-cab-legenda">
          última leitura:
          {{ state.last_run_at ? timeBR(state.last_run_at) : 'ainda não leu' }}
        </span>
        <button
          v-if="canEdit"
          type="button"
          class="cvg-btn cvg-btn--principal"
          :disabled="isRunning"
          @click="runNow"
        >
          <span
            class="i-lucide-refresh-cw text-sm"
            :class="isRunning ? 'animate-spin' : ''"
          />
          Ler agora
        </button>
      </template>
    </CvCabecalho>

    <!-- ══ escolher o canal + o período ══ -->
    <section class="ca-canais" aria-label="Canal e período">
      <div class="ca-tiles" role="tablist" aria-label="Canal">
        <button
          v-for="t in channelTiles"
          :key="t.key"
          type="button"
          role="tab"
          class="ca-tile"
          :class="channel === t.key ? 'ca-tile--on' : ''"
          :aria-selected="channel === t.key"
          @click="channel = t.key"
        >
          <span class="ca-tile-topo">
            <span
              class="ca-tile-icone"
              :style="
                t.key !== 'all'
                  ? { background: CHANNEL_COLORS[t.key], color: '#fff' }
                  : {}
              "
            >
              <span :class="t.icon" />
            </span>
            <span class="ca-tile-nome">{{ t.label }}</span>
          </span>
          <span class="ca-tile-estado" :class="estadoClass(t.status.estado)">
            {{ t.status.text }}
          </span>
        </button>
      </div>
      <div class="ca-regua">
        <span class="cvg-rotulo">Período</span>
        <!-- no celular a régua rola de lado dentro do cartão, sem alargar a tela -->
        <div class="ca-regua-rolo">
          <PeriodRuler v-model="period" glass class="max-w-full min-w-0" />
        </div>
      </div>
    </section>

    <SkeletonScreen v-if="isLoading" variant="dashboard" />

    <template v-else-if="data">
      <!-- ══ a história (gramática Apple) ══ -->
      <PagesStory :sections="story" :index="storyIndex" @go="goTo" />

      <!-- ══ 1 · NÚMEROS — o que os anúncios trouxeram ══ -->
      <CvBloco
        id="bloco-primarios"
        titulo="Números · o que os anúncios trouxeram"
        :subtitulo="`${CHANNEL_LABEL[channel]} · ${periodoTxt} · comparado com a nossa média de ${p.baseline_days} dias e com o período igual anterior`"
        tom="dia"
        icon="i-lucide-target"
      >
        <div class="cvg-bloco-pilha">
          <div class="cvg-fila cvg-fila--5">
            <CvIndicador
              :rotulo="`⭐ ${goalLabel}`"
              :valor="dash(totals.goal_cost, moneyShort)"
              :comparacao="cmpBase(totals.goal_cost, 'goal_cost')"
              contexto="A estrela-guia: tudo que o agente faz é para baixar este número sem perder volume."
              heroi
              pe="investido ÷ resultados"
            />
            <CvIndicador
              rotulo="Investido"
              :valor="moneyShort(totals.spend)"
              :comparacao="
                baseline?.daily_spend
                  ? {
                      texto: `ritmo da nossa média: ${moneyShort(baseline.daily_spend * (data.period?.days || 1))}`,
                      estado: 'neutro',
                    }
                  : { texto: 'sem média ainda', estado: 'neutro' }
              "
              contexto="Gasto das plataformas no período."
            />
            <CvIndicador
              rotulo="Leads"
              :valor="fmtNum(totals.leads)"
              :comparacao="cmpPrev(totals.leads, previous.leads)"
              :contexto="`CPL ${dash(rate(totals, 'cpl'), moneyShort)} · ${cmpBase(rate(totals, 'cpl'), 'rates.cpl').texto}.`"
            />
            <CvIndicador
              rotulo="Agendamentos"
              :valor="fmtNum(totals.booked)"
              :comparacao="cmpPrev(totals.booked, previous.booked)"
              :contexto="`${pct(rate(totals, 'booking_rate'))} dos leads marcaram consulta.`"
            />
            <CvIndicador
              rotulo="Cirurgias"
              :valor="fmtNum(totals.surgeries)"
              :comparacao="cmpPrev(totals.surgeries, previous.surgeries)"
              :contexto="`${fmtNum(totals.closed)} fechadas · custo por cirurgia (CAC) ${dash(rate(totals, 'cost_surgery'), moneyShort)}.`"
            />
          </div>
          <div class="cvg-fila ca-fila-apoio">
            <CvIndicador
              rotulo="Receita das cirurgias"
              :valor="moneyShort(totals.revenue)"
              :comparacao="cmpPrev(totals.revenue, previous.revenue)"
              contexto="Valor fechado das cirurgias dos leads do período."
              apoio
            />
            <CvIndicador
              rotulo="Retorno (ROAS)"
              :valor="roasFmt(rate(totals, 'roas'))"
              :comparacao="cmpBase(rate(totals, 'roas'), 'rates.roas', roasFmt)"
              contexto="Receita ÷ investido."
              apoio
            />
            <CvIndicador
              rotulo="Custo por lead (CPL)"
              :valor="dash(rate(totals, 'cpl'), moneyShort)"
              :comparacao="cmpBase(rate(totals, 'cpl'), 'rates.cpl')"
              contexto="Investido ÷ leads."
              apoio
            />
            <CvIndicador
              rotulo="Custo por cirurgia (CAC)"
              :valor="dash(rate(totals, 'cost_surgery'), moneyShort)"
              :comparacao="
                cmpBase(rate(totals, 'cost_surgery'), 'rates.cost_surgery')
              "
              contexto="Investido ÷ cirurgias. Demora semanas para fechar."
              apoio
            />
          </div>
          <p class="cvg-legenda">
            Gasto, exibições e cliques vêm das plataformas (Meta por anúncio;
            Google por campanha, pelo GA4). Leads, agendamentos, cirurgias e
            receita vêm do CRM × Agenda × Oftalmofácil, ligados ao anúncio pelo
            clique (Meta) ou pelo utm da página (Google).
            <template
              v-if="!channels.meta?.configured && !channels.google?.configured"
            >
              Nenhum canal ligado ainda: Meta em Integrações → Meta Ads e Google
              em Integrações → Google.
            </template>
          </p>
        </div>
      </CvBloco>

      <!-- ══ 1b · GRÁFICOS — a leitura em desenho (358c) ══ -->
      <CvBloco
        id="bloco-graficos"
        titulo="Gráficos · a leitura em desenho"
        :subtitulo="`Linha do dia a dia, fatias por ${channel === 'all' ? 'canal' : 'campanha'} e a régua contra a nossa média de ${p.baseline_days} dias. O traço escuro é sempre a média.`"
        icon="i-lucide-chart-line"
      >
        <div class="cvg-bloco-pilha">
          <div class="cvg-grafico">
            <span class="cvg-grafico-titulo">
              <span>Dia a dia · investido, leads e agendamentos</span>
              <span>{{ periodoTxt }}</span>
            </span>
            <div class="cvg-grafico-corpo">
              <TimelineChart
                v-if="seriesCh"
                :labels="series.labels"
                :bars="timelineBars"
                :lines="timelineLines"
                :refs="timelineRefs"
                :left-format="moneyShort"
                :right-format="fmtNum"
                :tip="timelineTip"
                :height="240"
                empty-text="sem dia com número no período"
              />
            </div>
            <p class="cvg-grafico-nota">
              Barras = investido no dia. Linhas = leads que chegaram e, desses,
              quantos marcaram consulta. Tracejado = a nossa média por dia nos
              últimos {{ p.baseline_days }} dias: barra acima do tracejado é dia
              gastando mais que o normal; linha de leads acima é dia melhor.
            </p>
          </div>

          <div class="cvg-graficos">
            <div class="cvg-grafico">
              <span class="cvg-grafico-titulo">
                <span>Quem levou o investimento</span>
              </span>
              <div class="cvg-grafico-corpo">
                <DonutChart
                  :slices="donutSpend"
                  :size="150"
                  :format="moneyShort"
                  unit="investidos"
                  empty-text="sem gasto no período"
                />
              </div>
            </div>
            <div class="cvg-grafico">
              <span class="cvg-grafico-titulo"
                ><span>Quem trouxe os leads</span></span
              >
              <div class="cvg-grafico-corpo">
                <DonutChart
                  :slices="donutLeads"
                  :size="150"
                  unit="leads"
                  empty-text="nenhum lead no período"
                />
              </div>
            </div>
            <div class="cvg-grafico">
              <span class="cvg-grafico-titulo"
                ><span>Quem trouxe os agendamentos</span></span
              >
              <div class="cvg-grafico-corpo">
                <DonutChart
                  :slices="donutBooked"
                  :size="150"
                  unit="agendamentos"
                  empty-text="nenhum agendamento no período"
                />
              </div>
            </div>
          </div>

          <div class="cvg-grafico">
            <span class="cvg-grafico-titulo">
              <span>Contra a nossa média · o que é bom e o que é ruim</span>
              <span>média de {{ p.baseline_days }} dias</span>
            </span>
            <div class="cvg-grafico-corpo">
              <CvRegua
                :items="reguaItems"
                :worse="Number(p.worse_pct) || 30"
                :better="Number(p.better_pct) || 30"
              />
            </div>
            <p class="cvg-grafico-nota">
              O traço escuro é a nossa média. Verde = {{ p.better_pct }}% melhor
              que ela (campeã). Vermelho = {{ p.worse_pct }}% pior (atenção;
              duas vezes a média = pausar). Âmbar = perto da média. São os
              mesmos limiares que o agente usa para recomendar.
            </p>
          </div>
        </div>
      </CvBloco>

      <!-- ══ 2 · O CAMINHO — antes e depois do lead ══ -->
      <CvBloco
        id="bloco-secundarios"
        titulo="O caminho · antes e depois do lead"
        :subtitulo="`Secundários explicam o custo (antes do lead). Terciários explicam o resultado (depois do lead). Cada número com a nossa média de ${p.baseline_days} dias ao lado.`"
        tom="apoio"
        icon="i-lucide-layers"
      >
        <div class="overflow-x-auto">
          <table
            class="ca-tab"
            :class="channelsShown.length > 1 ? 'ca-tab--larga' : ''"
          >
            <thead>
              <tr>
                <th class="text-left">Indicador</th>
                <th v-for="ch in channelsShown" :key="ch" class="text-right">
                  {{ CHANNEL_LABEL[ch] }}
                  <span class="ca-th-sub">período · nossa média</span>
                </th>
              </tr>
            </thead>
            <tbody>
              <tr class="ca-tab-grupo">
                <td :colspan="channelsShown.length + 1">
                  Secundários · antes do lead
                </td>
              </tr>
              <tr v-for="ind in SECONDARY" :key="ind.key">
                <td>
                  <span class="ca-ind-nome">{{ ind.label }}</span>
                  <span class="ca-ind-dica">{{ ind.hint }}</span>
                </td>
                <td v-for="ch in channelsShown" :key="ch" class="text-right">
                  <b :class="indicatorClass(ind, ch)">{{
                    ind.fmt(indicatorValue(ind, ch))
                  }}</b>
                  <span class="ca-media">{{
                    ind.fmt(indicatorBase(ind, ch))
                  }}</span>
                </td>
              </tr>
              <tr class="ca-tab-grupo">
                <td :colspan="channelsShown.length + 1">
                  Terciários · depois do lead
                </td>
              </tr>
              <tr v-for="ind in TERTIARY" :key="ind.key">
                <td>
                  <span class="ca-ind-nome">{{ ind.label }}</span>
                  <span class="ca-ind-dica">{{ ind.hint }}</span>
                </td>
                <td v-for="ch in channelsShown" :key="ch" class="text-right">
                  <b :class="indicatorClass(ind, ch)">{{
                    ind.fmt(indicatorValue(ind, ch))
                  }}</b>
                  <span v-if="!ind.special" class="ca-media">{{
                    ind.fmt(indicatorBase(ind, ch))
                  }}</span>
                  <span
                    v-else-if="data.time_to_book?.[ch]?.measured"
                    class="ca-media"
                  >
                    {{ data.time_to_book[ch].measured }} medidos
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </CvBloco>

      <!-- ══ 3 · CAMPANHAS em três níveis ══ -->
      <CvBloco
        id="bloco-campanhas"
        titulo="Campanhas → conjuntos → anúncios"
        :subtitulo="`Clique na campanha para abrir os conjuntos e os anúncios (Meta). O selo compara ${goalLabel} de cada linha com a nossa média do canal.`"
        icon="i-lucide-megaphone"
      >
        <template #acoes>
          <div class="cvg-chave" role="tablist" aria-label="Visualização">
            <button
              type="button"
              :class="campaignView === 'list' ? 'cvg-on' : ''"
              @click="campaignView = 'list'"
            >
              <span class="i-lucide-list text-sm" /> Lista
            </button>
            <button
              type="button"
              :class="campaignView === 'cards' ? 'cvg-on' : ''"
              @click="campaignView = 'cards'"
            >
              <span class="i-lucide-layout-grid text-sm" /> Cards
            </button>
          </div>
        </template>

        <div v-if="campaignView === 'list'" class="overflow-x-auto">
          <table v-if="visibleRows.length" class="ca-tab ca-tab--campanhas">
            <thead>
              <tr>
                <th class="text-left">Nome</th>
                <th class="text-right">Investido</th>
                <th class="text-right">Leads</th>
                <th class="text-right">CPL</th>
                <th class="text-right">Agend.</th>
                <th class="text-right">Custo/agend.</th>
                <th class="text-right">Cirurg.</th>
                <th class="text-right">CAC</th>
                <th class="text-right">ROAS</th>
                <th class="text-right">CTR</th>
                <th class="text-right">CPM</th>
                <th class="text-right">Freq.</th>
                <th class="text-left">vs média</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in visibleRows"
                :key="row.rowKey || row.id"
                :class="row.depth === 0 ? 'ca-linha--campanha' : ''"
              >
                <td>
                  <button
                    type="button"
                    class="ca-nome"
                    :style="{ paddingLeft: `${row.depth * 18}px` }"
                    :disabled="!row.hasChildren"
                    @click="row.hasChildren && toggle(row.rowKey || row.id)"
                  >
                    <span
                      v-if="row.hasChildren"
                      class="cvg-texto-3"
                      :class="
                        row.open
                          ? 'i-lucide-chevron-down'
                          : 'i-lucide-chevron-right'
                      "
                    />
                    <span
                      v-else
                      class="ca-ponto"
                      :style="{ background: CHANNEL_COLORS[row.channel] }"
                    />
                    <span class="ca-nome-txt" :title="row.name">{{
                      row.name
                    }}</span>
                    <span class="cvg-legenda flex-shrink-0">
                      {{
                        row.depth === 0
                          ? CHANNEL_LABEL[row.channel]
                          : LEVEL_LABEL[row.level]
                      }}
                    </span>
                    <span
                      v-if="row.status && row.status !== 'ACTIVE'"
                      class="cvg-legenda flex-shrink-0"
                    >
                      · pausado
                    </span>
                  </button>
                  <p v-if="row.note" class="cvg-legenda pl-1">
                    {{ row.note }}
                  </p>
                </td>
                <td class="text-right">{{ moneyShort(row.spend) }}</td>
                <td class="text-right">{{ fmtNum(row.leads) }}</td>
                <td class="text-right">
                  {{ dash(row.rates?.cpl, moneyShort) }}
                </td>
                <td class="text-right">{{ fmtNum(row.booked) }}</td>
                <td class="text-right">
                  <b>{{ dash(row.rates?.cost_booked, moneyShort) }}</b>
                </td>
                <td class="text-right">{{ fmtNum(row.surgeries) }}</td>
                <td class="text-right">
                  {{ dash(row.rates?.cost_surgery, moneyShort) }}
                </td>
                <td class="text-right">{{ roasFmt(row.rates?.roas) }}</td>
                <td class="text-right">{{ pct(row.rates?.ctr, 2) }}</td>
                <td class="text-right">{{ dash(row.rates?.cpm, money) }}</td>
                <td class="text-right">{{ num(row.frequency, 2) }}</td>
                <td class="whitespace-nowrap">
                  <span
                    v-if="goalBand(row)"
                    class="cvg-chip"
                    :class="goalBand(row).chip"
                  >
                    {{ goalBandShort(row) }}
                  </span>
                  <span
                    v-if="openActionsOf(row).length"
                    class="cvg-chip ml-1"
                    :title="
                      openActionsOf(row)
                        .map(a => a.title)
                        .join(' · ')
                    "
                  >
                    <span class="i-lucide-lightbulb text-xs" />
                    {{ openActionsOf(row).length }}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
          <p v-else class="cvg-vazio">nenhuma campanha com número no período</p>
        </div>

        <div v-else class="cvg-cards">
          <div
            v-for="c in campaigns"
            :key="`${c.channel}-${c.id}`"
            class="cvg-card"
          >
            <div class="flex items-center gap-2">
              <span
                class="ca-ponto"
                :style="{ background: CHANNEL_COLORS[c.channel] }"
              />
              <p class="cvg-card-titulo min-w-0 ca-quebra" :title="c.name">
                {{ c.name }}
              </p>
            </div>
            <p
              class="cvg-numero"
              :class="
                goalBand(c)?.estado === 'neutro'
                  ? ''
                  : `cvg-${goalBand(c)?.estado}`
              "
            >
              {{ dash(c.rates?.cost_booked, moneyShort) }}
              <span class="cvg-legenda font-normal">por agendamento</span>
            </p>
            <div class="ca-card-nums">
              <div>
                <span>Investido</span><b>{{ moneyShort(c.spend) }}</b>
              </div>
              <div>
                <span>Leads</span><b>{{ fmtNum(c.leads) }}</b>
              </div>
              <div>
                <span>Agend.</span><b>{{ fmtNum(c.booked) }}</b>
              </div>
              <div>
                <span>CPL</span><b>{{ dash(c.rates?.cpl, moneyShort) }}</b>
              </div>
              <div>
                <span>CAC</span
                ><b>{{ dash(c.rates?.cost_surgery, moneyShort) }}</b>
              </div>
              <div>
                <span>ROAS</span><b>{{ roasFmt(c.rates?.roas) }}</b>
              </div>
            </div>
            <div class="cvg-card-pe">
              <span
                v-if="goalBand(c)"
                class="cvg-chip"
                :class="goalBand(c).chip"
              >
                {{ goalBand(c).label }}
              </span>
              <span v-if="c.children?.length" class="cvg-legenda">
                {{ c.children.length }} conjunto(s) · {{ adsCount(c) }}
                anúncio(s)
              </span>
            </div>
          </div>
        </div>

        <div v-if="campaignBars.length" class="cvg-grafico">
          <span class="cvg-grafico-titulo">
            <span>{{ goalLabel }} por campanha</span>
            <span
              >menor é melhor · verde/vermelho = veredito contra a média</span
            >
          </span>
          <div class="cvg-grafico-corpo">
            <HBars
              :rows="campaignBars"
              :series="[{ label: goalLabel, format: v => moneyShort(v) }]"
              :format="v => moneyShort(v)"
              :label-width="15"
              :highlight-max="false"
              :reference="campaignRef"
              empty-text="sem campanha com resultado no período"
            />
          </div>
        </div>
      </CvBloco>

      <!-- ══ 4 · RECOMENDAÇÕES ══ -->
      <CvBloco
        id="bloco-recomendacoes"
        titulo="Recomendações do agente"
        :subtitulo="`Cada cartão diz o que ele viu, o que quer fazer e o que espera ganhar. Aprovar não muda nada: só autoriza o próximo passo. ${p.learning_days} dias depois de feita, ele mede o antes × depois.`"
        tom="apoio"
        icon="i-lucide-lightbulb"
      >
        <template #acoes>
          <span v-if="state.new !== undefined" class="cvg-legenda">
            última leitura: {{ state.new }} nova(s) ·
            {{ state.learned || 0 }} aprendida(s)
          </span>
        </template>

        <!-- a trava de segurança, sempre à vista -->
        <div class="ca-trava" :class="executeApi ? 'ca-trava--api' : ''">
          <span class="ca-trava-icone">
            <span
              :class="executeApi ? 'i-lucide-shield-check' : 'i-lucide-lock'"
            />
          </span>
          <div class="min-w-0">
            <p class="ca-trava-titulo">
              {{
                executeApi
                  ? 'API da Meta ligada: verba e pausa saem pela API, com confirmação antes.'
                  : 'Modo seguro: nada é alterado automaticamente.'
              }}
            </p>
            <p class="cvg-corpo cvg-texto-2">
              <template v-if="executeApi">
                Só recomendações aprovadas, e só de verba ou pausa. Criativo,
                público, página e qualidade continuam como tarefas para a
                equipe. No Google tudo é à mão.
              </template>
              <template v-else>
                Toda aprovação vira um passo a passo para fazer à mão no
                Gerenciador (Meta) ou no Google Ads; depois você marca "Fiz à
                mão". Para o agente aplicar sozinho na Meta, ligue a chavinha em
                Ajustes.
              </template>
            </p>
          </div>
        </div>

        <p v-if="state.brief" class="ca-resumo cvg-corpo">{{ state.brief }}</p>

        <div class="ca-filtros">
          <button
            v-for="t in QUEUE_TABS"
            :key="t[0]"
            type="button"
            class="cvg-chip cvg-chip--marcavel"
            :class="queueFilter === t[0] ? 'cvg-on' : ''"
            @click="queueFilter = t[0]"
          >
            {{ t[1] }}
            <b v-if="queueCount(t[0])">{{ queueCount(t[0]) }}</b>
          </button>
        </div>

        <div v-if="queue.length" class="ca-recs">
          <article
            v-for="a in queue"
            :key="a.id"
            class="ca-rec"
            :class="`ca-rec--${a.severity}`"
          >
            <div class="ca-rec-topo">
              <span class="ca-rec-kind">
                <span :class="KIND_ICON[a.kind] || 'i-lucide-lightbulb'" />
                {{ capitalize(KIND_LABEL[a.kind] || a.kind) }}
              </span>
              <span class="cvg-chip" :class="SEVERITY[a.severity]?.tone">{{
                SEVERITY[a.severity]?.label || a.severity
              }}</span>
              <span class="cvg-chip">
                <span
                  class="ca-ponto"
                  :style="{ background: CHANNEL_COLORS[a.channel] }"
                />
                {{ CHANNEL_LABEL[a.channel] }} · {{ LEVEL_LABEL[a.level] }}
              </span>
              <span class="cvg-legenda ml-auto">{{
                dateBR(a.suggested_on)
              }}</span>
            </div>
            <h3 class="ca-rec-titulo">{{ a.title }}</h3>
            <p class="cvg-legenda ca-quebra">
              {{ a.ref_name
              }}<template v-if="a.campaign_name && a.level !== 'campaign'">
                · {{ a.campaign_name }}
              </template>
            </p>
            <dl class="ca-rec-corpo">
              <div>
                <dt>O que ele viu</dt>
                <dd>{{ a.evidence }}</dd>
              </div>
              <div>
                <dt>O que quer fazer</dt>
                <dd>
                  <b>{{ a.suggestion }}</b>
                </dd>
              </div>
              <div v-if="a.expected">
                <dt>O que espera ganhar</dt>
                <dd>{{ a.expected }}</dd>
              </div>
              <div>
                <dt>Se aprovar</dt>
                <dd class="cvg-texto-2">{{ howApplies(a) }}</dd>
              </div>
            </dl>
            <p v-if="a.error" class="cvg-problema text-sm">{{ a.error }}</p>

            <!-- feita: aprendizado -->
            <div v-if="a.status === 'applied'" class="ca-rec-feita">
              <span class="cvg-legenda">
                feita {{ timeBR(a.applied_at) }} ({{
                  a.applied_mode === 'api' ? 'pela API' : 'à mão'
                }})
              </span>
              <template v-if="a.learned_at">
                <span class="cvg-chip" :class="OUTCOME[a.outcome]?.tone">{{
                  OUTCOME[a.outcome]?.label
                }}</span>
                <p class="cvg-corpo cvg-texto-2 w-full">{{ beforeAfter(a) }}</p>
              </template>
              <span v-else class="cvg-chip">
                aprendendo · faltam {{ learningLeft(a) }} dia(s)
              </span>
            </div>

            <div v-if="canEdit" class="ca-rec-acoes">
              <template v-if="a.status === 'suggested'">
                <button
                  type="button"
                  class="cvg-btn cvg-btn--principal"
                  :disabled="busy"
                  @click="decide(a, 'approve')"
                >
                  <span class="i-lucide-check text-sm" /> Aprovar
                </button>
                <button
                  type="button"
                  class="cvg-btn"
                  :disabled="busy"
                  @click="decide(a, 'dismiss')"
                >
                  Descartar
                </button>
              </template>
              <template v-else-if="a.status === 'approved'">
                <button
                  type="button"
                  class="cvg-btn cvg-btn--principal"
                  :disabled="busy"
                  @click="askApply(a)"
                >
                  <span
                    :class="viaApi(a) ? 'i-lucide-zap' : 'i-lucide-list-checks'"
                    class="text-sm"
                  />
                  {{ applyLabel(a) }}
                </button>
                <button
                  type="button"
                  class="cvg-btn"
                  :disabled="busy"
                  @click="markManual(a)"
                >
                  Fiz à mão
                </button>
                <button
                  type="button"
                  class="cvg-btn cvg-btn--ghost"
                  :disabled="busy"
                  @click="decide(a, 'dismiss')"
                >
                  Descartar
                </button>
              </template>
              <template v-else-if="['dismissed', 'expired'].includes(a.status)">
                <button
                  type="button"
                  class="cvg-btn"
                  :disabled="busy"
                  @click="decide(a, 'reopen')"
                >
                  Voltar para a fila
                </button>
              </template>
            </div>
          </article>
        </div>
        <p v-else class="cvg-vazio">
          {{
            queueFilter === 'suggested'
              ? 'nada esperando o seu ok — ou o agente ainda não leu (botão "Ler agora", no topo)'
              : 'nada aqui'
          }}
        </p>
      </CvBloco>

      <!-- ══ 5 · APRENDIZADO ══ -->
      <CvBloco
        id="bloco-aprendizado"
        titulo="O que o agente aprendeu"
        :subtitulo="`Placar por regra: cada recomendação feita vira um antes × depois em ${p.learning_days} dias. Regra que erra mais do que acerta (5 ou mais julgadas) entra em observação e só avisa.`"
        icon="i-lucide-graduation-cap"
      >
        <div v-if="scoreboard.length" class="cvg-cards">
          <div v-for="r in scoreboard" :key="r.rule" class="cvg-card">
            <div class="flex items-center gap-2 flex-wrap">
              <p class="cvg-card-titulo">{{ r.label }}</p>
              <span v-if="r.observing" class="cvg-chip cvg-chip--atencao">
                em observação
              </span>
              <span
                v-if="r.confidence !== null && r.confidence !== undefined"
                class="cvg-chip ml-auto"
                :class="confidenceChip(r.confidence)"
              >
                acerta {{ pct(r.confidence, 0) }}
              </span>
            </div>
            <div class="ca-card-nums ca-card-nums--5">
              <div>
                <span>melhorou</span><b class="cvg-bom">{{ r.better }}</b>
              </div>
              <div>
                <span>economizou</span><b class="cvg-bom">{{ r.saved }}</b>
              </div>
              <div>
                <span>igual</span><b>{{ r.same }}</b>
              </div>
              <div>
                <span>piorou</span><b class="cvg-problema">{{ r.worse }}</b>
              </div>
              <div>
                <span>cedo</span><b>{{ r.early }}</b>
              </div>
            </div>
          </div>
        </div>
        <p v-else class="cvg-vazio">
          ainda sem antes × depois — aparece {{ p.learning_days }} dias depois
          da primeira recomendação feita
        </p>
      </CvBloco>

      <!-- ══ 6 · NOSSA MÉDIA ══ -->
      <CvBloco
        id="bloco-media"
        titulo="Nossa média · 7, 30, 90, 180 e 360 dias"
        :subtitulo="`Janelas fechadas em ontem. É contra a de ${p.baseline_days} dias que o agente julga (troque em Ajustes). Nenhum número de mercado entra aqui.`"
        icon="i-lucide-ruler"
      >
        <template #acoes>
          <div class="cvg-chave" role="tablist" aria-label="Canal da média">
            <button
              v-for="ch in ['all', 'meta', 'google']"
              :key="ch"
              type="button"
              :class="mediaChannel === ch ? 'cvg-on' : ''"
              @click="mediaChannel = ch"
            >
              {{ CHANNEL_LABEL[ch] }}
            </button>
          </div>
        </template>
        <div class="overflow-x-auto">
          <table class="ca-tab ca-tab--media">
            <thead>
              <tr>
                <th class="text-left">Janela</th>
                <th v-for="c in MEDIA_COLS" :key="c.label" class="text-right">
                  {{ c.label }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="r in mediaRows"
                :key="r.days"
                :class="isRegua(r) ? 'ca-linha--regua' : ''"
              >
                <td class="whitespace-nowrap">
                  <b>{{ r.days }} dias</b>
                  <span v-if="isRegua(r)" class="cvg-chip cvg-chip--dia ml-1">
                    régua
                  </span>
                  <span v-if="r.since" class="ca-ind-dica">
                    {{ dateBR(r.since) }} a {{ dateBR(r.until) }}
                  </span>
                </td>
                <td
                  v-for="c in MEDIA_COLS"
                  :key="c.label"
                  class="text-right whitespace-nowrap"
                >
                  {{ c.get(r) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </CvBloco>

      <!-- ══ 7 · AJUSTES (sanfona) ══ -->
      <CvBloco
        v-if="paramsDraft"
        id="bloco-parametros"
        titulo="Ajustes do agente"
        :subtitulo="
          openParams
            ? 'O que ele persegue, com quanta verba, quando fala e quando mexe.'
            : `Estrela-guia: ${goalLabel} · julga ${p.window_days} dias contra ${p.baseline_days} · API da Meta ${executeApi ? 'ligada' : 'desligada'}`
        "
        icon="i-lucide-sliders-horizontal"
      >
        <template #acoes>
          <button
            type="button"
            class="cvg-btn"
            @click="openParams = !openParams"
          >
            <span
              :class="
                openParams ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
              "
              class="text-sm"
            />
            {{ openParams ? 'Fechar' : 'Abrir os ajustes' }}
          </button>
        </template>
        <template v-if="openParams">
          <p v-if="!canEdit" class="cvg-legenda">
            Você só pode ver; peça a um administrador para mudar.
          </p>
          <div class="cvg-grupo">
            <div class="cvg-card ca-form">
              <p class="cvg-card-titulo">Estrela-guia e verba</p>
              <div class="cvg-chave" role="tablist" aria-label="Estrela-guia">
                <button
                  v-for="g in [
                    ['booked', 'Custo por agendamento'],
                    ['surgery', 'Custo por cirurgia'],
                  ]"
                  :key="g[0]"
                  type="button"
                  :class="paramsDraft.goal === g[0] ? 'cvg-on' : ''"
                  :disabled="!canEdit"
                  @click="paramsDraft.goal = g[0]"
                >
                  {{ g[1] }}
                </button>
              </div>
              <p class="cvg-legenda">
                Agendamento chega em dias e já filtra lead ruim; cirurgia é o
                CAC real, mas demora semanas. Troque para testes.
              </p>
              <label class="cvg-campo-rotulo">
                <span class="cvg-rotulo">Verba mensal da Meta (R$)</span>
                <input
                  v-model="paramsDraft.budget.meta"
                  type="number"
                  min="0"
                  class="cvg-campo"
                  :disabled="!canEdit"
                />
              </label>
              <label class="cvg-campo-rotulo">
                <span class="cvg-rotulo">Verba mensal do Google (R$)</span>
                <input
                  v-model="paramsDraft.budget.google"
                  type="number"
                  min="0"
                  class="cvg-campo"
                  :disabled="!canEdit"
                />
              </label>
              <label class="cvg-campo-rotulo">
                <span class="cvg-rotulo">
                  Teto por conjunto/campanha por dia (R$, 0 = sem teto)
                </span>
                <input
                  v-model="paramsDraft.daily_cap"
                  type="number"
                  min="0"
                  class="cvg-campo"
                  :disabled="!canEdit"
                />
              </label>
            </div>

            <div class="cvg-card ca-form">
              <p class="cvg-card-titulo">Janelas e régua</p>
              <label class="cvg-campo-rotulo">
                <span class="cvg-rotulo">
                  Janela que o agente julga (dias fechados)
                </span>
                <input
                  v-model="paramsDraft.window_days"
                  type="number"
                  min="3"
                  max="30"
                  class="cvg-campo"
                  :disabled="!canEdit"
                />
              </label>
              <label class="cvg-campo-rotulo">
                <span class="cvg-rotulo">Nossa média de referência</span>
                <select
                  v-model="paramsDraft.baseline_days"
                  class="cvg-campo"
                  :disabled="!canEdit"
                >
                  <option v-for="d in WINDOWS" :key="d" :value="d">
                    {{ d }} dias
                  </option>
                </select>
              </label>
              <label class="cvg-campo-rotulo">
                <span class="cvg-rotulo">
                  Pior que a média em (%) = atenção · 2× = pausar
                </span>
                <input
                  v-model="paramsDraft.worse_pct"
                  type="number"
                  min="10"
                  max="200"
                  class="cvg-campo"
                  :disabled="!canEdit"
                />
              </label>
              <label class="cvg-campo-rotulo">
                <span class="cvg-rotulo">
                  Melhor que a média em (%) = campeã (sobe verba)
                </span>
                <input
                  v-model="paramsDraft.better_pct"
                  type="number"
                  min="10"
                  max="90"
                  class="cvg-campo"
                  :disabled="!canEdit"
                />
              </label>
              <label class="cvg-campo-rotulo">
                <span class="cvg-rotulo">Passo de verba (%)</span>
                <input
                  v-model="paramsDraft.budget_step_pct"
                  type="number"
                  min="5"
                  max="100"
                  class="cvg-campo"
                  :disabled="!canEdit"
                />
              </label>
            </div>

            <div class="cvg-card ca-form">
              <p class="cvg-card-titulo">Volume mínimo para falar</p>
              <p class="cvg-legenda">
                Abaixo disso é ruído: o agente não julga.
              </p>
              <div class="ca-form-2col">
                <label class="cvg-campo-rotulo">
                  <span class="cvg-rotulo">Gasto (R$)</span>
                  <input
                    v-model="paramsDraft.min.spend"
                    type="number"
                    min="0"
                    class="cvg-campo"
                    :disabled="!canEdit"
                  />
                </label>
                <label class="cvg-campo-rotulo">
                  <span class="cvg-rotulo">Exibições</span>
                  <input
                    v-model="paramsDraft.min.impressions"
                    type="number"
                    min="0"
                    class="cvg-campo"
                    :disabled="!canEdit"
                  />
                </label>
                <label class="cvg-campo-rotulo">
                  <span class="cvg-rotulo">Cliques</span>
                  <input
                    v-model="paramsDraft.min.clicks"
                    type="number"
                    min="0"
                    class="cvg-campo"
                    :disabled="!canEdit"
                  />
                </label>
                <label class="cvg-campo-rotulo">
                  <span class="cvg-rotulo">Leads</span>
                  <input
                    v-model="paramsDraft.min.leads"
                    type="number"
                    min="0"
                    class="cvg-campo"
                    :disabled="!canEdit"
                  />
                </label>
              </div>
              <label class="cvg-campo-rotulo">
                <span class="cvg-rotulo">
                  Resultados (agend./cirurgias) para chamar de campeã
                </span>
                <input
                  v-model="paramsDraft.min.goal_events"
                  type="number"
                  min="0"
                  class="cvg-campo"
                  :disabled="!canEdit"
                />
              </label>
            </div>

            <div class="cvg-card ca-form">
              <p class="cvg-card-titulo">Autonomia e aprendizado</p>
              <label class="cvg-campo-rotulo">
                <span class="cvg-rotulo">
                  Dias para medir o antes × depois
                </span>
                <input
                  v-model="paramsDraft.learning_days"
                  type="number"
                  min="3"
                  max="30"
                  class="cvg-campo"
                  :disabled="!canEdit"
                />
              </label>
              <label class="cvg-campo-rotulo">
                <span class="cvg-rotulo">
                  Não mexer de novo no mesmo item antes de (dias)
                </span>
                <input
                  v-model="paramsDraft.respect_days"
                  type="number"
                  min="1"
                  max="30"
                  class="cvg-campo"
                  :disabled="!canEdit"
                />
              </label>
              <div v-for="sw in SWITCHES" :key="sw[0]" class="ca-switch">
                <button
                  type="button"
                  class="cv-switch"
                  :class="paramsDraft[sw[0]] ? 'cv-switch-on' : ''"
                  :aria-pressed="paramsDraft[sw[0]]"
                  :disabled="!canEdit"
                  @click="paramsDraft[sw[0]] = !paramsDraft[sw[0]]"
                />
                <div class="min-w-0">
                  <p class="cvg-corpo font-medium">{{ sw[1] }}</p>
                  <p v-if="sw[2]" class="cvg-legenda">{{ sw[2] }}</p>
                </div>
              </div>
              <p class="cvg-legenda">
                Modo atual:
                <b>analisa → sugere → você aprova → aplica → aprende</b>. A
                autonomia total vem depois, com o placar provado.
              </p>
            </div>
          </div>
          <div v-if="canEdit" class="flex items-center gap-2 flex-wrap">
            <button
              type="button"
              class="cvg-btn cvg-btn--principal"
              :disabled="isSavingParams"
              @click="saveParams"
            >
              <span class="i-lucide-save text-sm" /> Guardar ajustes
            </button>
            <button type="button" class="cvg-btn" @click="resetParams">
              Desfazer
            </button>
          </div>
        </template>
      </CvBloco>

      <!-- ══ 8 · SUBIR CAMPANHA (sanfona) ══ -->
      <CvBloco
        id="bloco-subir"
        titulo="Subir campanha"
        :subtitulo="
          openLaunch
            ? 'Preencha a ficha e o agente monta o plano: nomes no padrão da casa, sufixo de rastreio, estrutura campanha → conjunto → anúncios.'
            : `${briefs.length ? plural(briefs.length, 'ficha guardada', 'fichas guardadas') : 'nenhuma ficha ainda'} · com a API da Meta ligada ele cria tudo PAUSADO para você conferir`
        "
        icon="i-lucide-rocket"
      >
        <template #acoes>
          <button
            type="button"
            class="cvg-btn"
            @click="openLaunch = !openLaunch"
          >
            <span
              :class="
                openLaunch ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
              "
              class="text-sm"
            />
            {{ openLaunch ? 'Fechar' : 'Abrir a ficha' }}
          </button>
        </template>
        <template v-if="openLaunch">
          <p class="cvg-legenda">
            Com "Aplicar na Meta pela API" ligado, ele cria tudo PAUSADO para
            você conferir no Gerenciador e ligar. Sem a chavinha, a ficha guarda
            o roteiro para subir à mão.
          </p>
          <div v-if="canEdit" class="cvg-grupo">
            <div class="cvg-card ca-form">
              <p class="cvg-card-titulo">A campanha</p>
              <label class="cvg-campo-rotulo">
                <span class="cvg-rotulo">Nome curto da campanha</span>
                <input
                  v-model="brief.name"
                  class="cvg-campo"
                  placeholder="ex.: Cirurgia de miopia · cenas do dia a dia"
                />
              </label>
              <div class="cvg-campo-rotulo">
                <span class="cvg-rotulo">Objetivo</span>
                <div class="cvg-chave" role="tablist" aria-label="Objetivo">
                  <button
                    v-for="o in [
                      ['leads_whatsapp', 'Leads pelo WhatsApp'],
                      ['leads_page', 'Leads pela página'],
                    ]"
                    :key="o[0]"
                    type="button"
                    :class="brief.objective === o[0] ? 'cvg-on' : ''"
                    @click="brief.objective = o[0]"
                  >
                    {{ o[1] }}
                  </button>
                </div>
              </div>
              <label class="cvg-campo-rotulo">
                <span class="cvg-rotulo">Verba diária (R$)</span>
                <input
                  v-model="brief.daily_budget"
                  type="number"
                  min="1"
                  class="cvg-campo"
                />
              </label>
              <label
                v-if="brief.objective === 'leads_whatsapp'"
                class="cvg-campo-rotulo"
              >
                <span class="cvg-rotulo">
                  WhatsApp de destino (só números, com 55)
                </span>
                <input
                  v-model="brief.whatsapp"
                  class="cvg-campo"
                  placeholder="5511998085773"
                />
              </label>
              <label v-else class="cvg-campo-rotulo">
                <span class="cvg-rotulo">Página de destino</span>
                <input
                  v-model="brief.page_url"
                  class="cvg-campo"
                  placeholder="https://clinica.cevico.com.br/…-m"
                />
              </label>
              <label class="cvg-campo-rotulo">
                <span class="cvg-rotulo">
                  ID da página do Facebook (para o destino WhatsApp pela API;
                  opcional)
                </span>
                <input v-model="brief.page_id" class="cvg-campo" />
              </label>
            </div>
            <div class="cvg-card ca-form">
              <p class="cvg-card-titulo">Público e anúncios</p>
              <label class="cvg-campo-rotulo">
                <span class="cvg-rotulo">
                  Cidades/região (texto livre; o país é o Brasil)
                </span>
                <input
                  v-model="brief.audience.cities"
                  class="cvg-campo"
                  placeholder="ex.: São Paulo e região (40 km)"
                />
              </label>
              <div class="ca-form-2col">
                <label class="cvg-campo-rotulo">
                  <span class="cvg-rotulo">Idade mínima</span>
                  <input
                    v-model="brief.audience.age_min"
                    type="number"
                    min="18"
                    max="65"
                    class="cvg-campo"
                  />
                </label>
                <label class="cvg-campo-rotulo">
                  <span class="cvg-rotulo">Idade máxima</span>
                  <input
                    v-model="brief.audience.age_max"
                    type="number"
                    min="18"
                    max="65"
                    class="cvg-campo"
                  />
                </label>
              </div>
              <p class="cvg-rotulo">Anúncios a reaproveitar (até 10)</p>
              <div
                v-if="creatives.length"
                class="flex flex-wrap gap-1.5 max-h-40 overflow-y-auto"
              >
                <button
                  v-for="c in creatives"
                  :key="c.ad_id"
                  type="button"
                  class="cvg-chip cvg-chip--marcavel text-left"
                  :class="
                    brief.creative_ad_ids.includes(c.ad_id)
                      ? 'cvg-chip--bom'
                      : ''
                  "
                  :title="c.campaign_name"
                  @click="toggleCreative(c.ad_id)"
                >
                  <span
                    v-if="brief.creative_ad_ids.includes(c.ad_id)"
                    class="i-lucide-check text-xs"
                  />
                  {{ c.name }}
                </button>
              </div>
              <p v-else class="cvg-legenda">
                Sem anúncios na Central de Criativos ainda — as peças novas do
                núcleo sobem à mão.
              </p>
              <label class="cvg-campo-rotulo">
                <span class="cvg-rotulo">Observações</span>
                <textarea
                  v-model="brief.notes"
                  rows="2"
                  class="cvg-campo ca-textarea"
                />
              </label>
              <button
                type="button"
                class="cvg-btn cvg-btn--principal"
                :disabled="isPlanning"
                @click="planBrief"
              >
                <span class="i-lucide-wand-2 text-sm" /> Montar plano e guardar
                ficha
              </button>
            </div>
          </div>

          <div v-if="briefs.length" class="ca-recs">
            <p class="cvg-rotulo">Fichas</p>
            <article v-for="b in briefs" :key="b.id" class="ca-rec">
              <div class="ca-rec-topo">
                <span
                  class="cvg-chip"
                  :class="b.status === 'criada' ? 'cvg-chip--bom' : ''"
                >
                  {{
                    b.status === 'criada' ? 'criada pausada na Meta' : 'ficha'
                  }}
                </span>
                <span class="cvg-legenda ml-auto">
                  {{ timeBR(b.created_at)
                  }}<template v-if="b.created_by">
                    · {{ b.created_by }}</template
                  >
                </span>
              </div>
              <h3 class="ca-rec-titulo">
                {{ b.plan?.campaign_name || b.name }}
              </h3>
              <p class="cvg-legenda">
                Conjunto: {{ b.plan?.adset_name }} · R$
                {{ num(b.daily_budget, 2) }}/dia (≈
                {{ moneyShort(b.plan?.monthly_estimate) }}/mês)
              </p>
              <p v-if="b.plan?.budget_note" class="cvg-atencao text-sm">
                {{ b.plan.budget_note }}
              </p>
              <ol class="ca-passos">
                <li v-for="(s, i) in b.plan?.steps || []" :key="i">{{ s }}</li>
              </ol>
              <div class="ca-rec-acoes">
                <button
                  type="button"
                  class="cvg-btn"
                  @click="copy(b.plan?.utm || '')"
                >
                  <span class="i-lucide-copy text-sm" /> Copiar sufixo de
                  rastreio
                </button>
                <button
                  v-if="
                    canEdit && b.status !== 'criada' && b.channel === 'meta'
                  "
                  type="button"
                  class="cvg-btn cvg-btn--principal"
                  :disabled="busy || !executeApi"
                  :title="
                    executeApi
                      ? ''
                      : 'Ligue a chavinha Aplicar na Meta pela API, em Ajustes'
                  "
                  @click="launch(b)"
                >
                  <span class="i-lucide-rocket text-sm" /> Criar pausada na Meta
                </button>
                <span v-if="b.meta?.campaign_id" class="cvg-legenda">
                  campanha {{ b.meta.campaign_id }} · conjunto
                  {{ b.meta.adset_id }} · {{ (b.meta.ads || []).length }}
                  anúncio(s)
                </span>
                <p v-if="b.error" class="cvg-problema text-sm">{{ b.error }}</p>
                <button
                  v-if="canEdit"
                  type="button"
                  class="cvg-btn cvg-btn--ghost cvg-btn--problema ml-auto"
                  @click="removeBrief(b)"
                >
                  Apagar
                </button>
              </div>
            </article>
          </div>
        </template>
      </CvBloco>
    </template>

    <!-- passo a passo para fazer à mão -->
    <div v-if="steps" class="ca-veu" @click.self="steps = null">
      <div
        class="ca-modal"
        role="dialog"
        aria-modal="true"
        aria-label="Passo a passo"
      >
        <p class="cvg-rotulo">Passo a passo · à mão</p>
        <h3 class="ca-rec-titulo mt-1">{{ steps.title }}</h3>
        <p v-if="steps.error" class="cvg-problema text-sm mt-1">
          {{ steps.error }}
        </p>
        <p class="cvg-legenda mt-2">
          Faça no Gerenciador e marque aqui; o antes × depois começa a contar.
        </p>
        <ol class="ca-passos mt-3">
          <li v-for="(s, i) in steps.steps" :key="i">{{ s }}</li>
        </ol>
        <div class="flex items-center gap-2 flex-wrap mt-5">
          <button
            type="button"
            class="cvg-btn cvg-btn--principal"
            :disabled="busy"
            @click="markManual(steps.action)"
          >
            <span class="i-lucide-check text-sm" /> Fiz à mão
          </button>
          <button type="button" class="cvg-btn" @click="steps = null">
            Depois
          </button>
        </div>
      </div>
    </div>

    <!-- confirmação antes de mexer na Meta pela API -->
    <div v-if="confirmApply" class="ca-veu" @click.self="confirmApply = null">
      <div
        class="ca-modal"
        role="dialog"
        aria-modal="true"
        aria-label="Confirmar"
      >
        <p class="cvg-rotulo">Vai mudar na Meta, pela API</p>
        <h3 class="ca-rec-titulo mt-1">{{ confirmApply.title }}</h3>
        <p class="cvg-legenda ca-quebra">
          {{ confirmApply.ref_name
          }}<template
            v-if="
              confirmApply.campaign_name && confirmApply.level !== 'campaign'
            "
          >
            · {{ confirmApply.campaign_name }}
          </template>
        </p>
        <dl class="ca-rec-corpo mt-3">
          <div>
            <dt>O que vai acontecer</dt>
            <dd>
              <b>{{ confirmApply.suggestion }}</b>
            </dd>
          </div>
          <div v-if="confirmApply.payload?.budget_to">
            <dt>Verba diária</dt>
            <dd>
              {{
                confirmApply.payload.budget_from
                  ? `${money(confirmApply.payload.budget_from)} → `
                  : ''
              }}{{ money(confirmApply.payload.budget_to) }}
            </dd>
          </div>
          <div>
            <dt>Para voltar atrás</dt>
            <dd class="cvg-texto-2">
              No Gerenciador da Meta, no próprio
              {{ LEVEL_LABEL[confirmApply.level] }}. O agente não mexe de novo
              neste item por {{ p.respect_days }} dias.
            </dd>
          </div>
        </dl>
        <div class="flex items-center gap-2 flex-wrap mt-5">
          <button
            type="button"
            class="cvg-btn cvg-btn--principal"
            :disabled="busy"
            @click="apply(confirmApply)"
          >
            <span class="i-lucide-zap text-sm" /> Sim, aplicar na Meta
          </button>
          <button type="button" class="cvg-btn" @click="confirmApply = null">
            Cancelar
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* A tela de Campanhas no desenho híbrido (item 358): a história Apple vem do
   PagesStory; os blocos são o guia arejado (.cvg-*). Aqui só o que é desta
   tela: o seletor de canal em azulejos, a trava de segurança, os cartões de
   recomendação com "o que viu / o que quer fazer / se aprovar", as tabelas
   e os dois modais. Cores pelas variáveis do guia (--g-*) e do dia (--cv). */
.ca-cab-legenda {
  color: rgba(255, 255, 255, 0.85);
}

/* ── canal + período ── */
.ca-canais {
  display: grid;
  grid-template-columns: minmax(0, 1.6fr) minmax(280px, 1fr);
  gap: 16px 24px;
  align-items: stretch;
}
@media (max-width: 1100px) {
  .ca-canais {
    grid-template-columns: minmax(0, 1fr);
  }
}
.ca-tiles {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 12px;
}
@media (max-width: 720px) {
  .ca-tiles {
    grid-template-columns: 1fr;
  }
}
.ca-tile {
  text-align: left;
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding: 16px 18px;
  border-radius: var(--g-raio-lg, 20px);
  background: var(--g-superficie, #fff);
  border: 2px solid transparent;
  box-shadow: var(--g-sombra-bloco);
  cursor: pointer;
  transition:
    transform 160ms ease,
    border-color 160ms ease,
    box-shadow 160ms ease;
  min-width: 0;
}
.ca-tile:hover {
  transform: translateY(-1px);
}
.ca-tile:focus-visible {
  outline: 2px solid var(--g-foco);
  outline-offset: 2px;
}
.ca-tile--on {
  border-color: var(--cv, #2563eb);
  box-shadow:
    var(--g-sombra-bloco),
    0 0 0 4px rgb(var(--cv-rgb, 37 99 235) / 0.14);
}
.ca-tile-topo {
  display: flex;
  align-items: center;
  gap: 12px;
  min-width: 0;
}
.ca-tile-icone {
  width: 40px;
  height: 40px;
  border-radius: 12px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 20px;
  flex-shrink: 0;
  background: rgb(var(--cv-rgb, 37 99 235) / 0.12);
  color: var(--g-dia-texto);
}
.ca-tile-nome {
  font-size: 20px;
  line-height: 26px;
  font-weight: 600;
  letter-spacing: -0.01em;
  color: var(--g-texto);
}
.ca-tile--on .ca-tile-nome {
  color: var(--g-dia-texto);
}
.ca-tile-estado {
  font-size: 13px;
  line-height: 18px;
  font-weight: 500;
}
.ca-regua {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 16px 18px;
  border-radius: var(--g-raio-lg, 20px);
  background: var(--g-superficie, #fff);
  box-shadow: var(--g-sombra-bloco);
  min-width: 0;
  justify-content: center;
}
.ca-regua-rolo {
  max-width: 100%;
  min-width: 0;
  overflow-x: auto;
}

/* ── números ── */
.ca-fila-apoio {
  grid-template-columns: repeat(4, minmax(0, 1fr));
}
@media (max-width: 1100px) {
  .ca-fila-apoio {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}
@media (max-width: 720px) {
  .ca-fila-apoio {
    grid-template-columns: 1fr;
  }
}

/* ── tabelas (caminho, campanhas, nossa média) ── */
.ca-tab {
  width: 100%;
  font-size: 14px;
  line-height: 20px;
  border-collapse: collapse;
  color: var(--g-texto);
}
.ca-tab--larga {
  min-width: 640px;
}
.ca-tab--campanhas {
  min-width: 980px;
}
.ca-tab--media {
  min-width: 960px;
}
.ca-tab th {
  font-size: 12px;
  line-height: 16px;
  font-weight: 500;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: var(--g-texto-3);
  padding: 8px 10px;
  vertical-align: bottom;
}
.ca-th-sub {
  display: block;
  text-transform: none;
  letter-spacing: 0;
  font-size: 11px;
  opacity: 0.8;
}
.ca-tab td {
  padding: 10px;
  border-top: 1px solid var(--g-borda);
  vertical-align: top;
}
.ca-tab td b {
  font-weight: 600;
}
.ca-tab-grupo td {
  padding-top: 18px;
  padding-bottom: 6px;
  border-top: 0;
  font-size: 13px;
  font-weight: 600;
  letter-spacing: 0.02em;
  color: var(--ga, var(--g-texto-2));
}
.ca-ind-nome {
  display: block;
  font-weight: 500;
}
.ca-ind-dica {
  display: block;
  font-size: 12px;
  line-height: 16px;
  color: var(--g-texto-3);
}
.ca-media {
  display: block;
  font-size: 12px;
  line-height: 16px;
  color: var(--g-texto-3);
}
.ca-media::before {
  content: 'média ';
}
.ca-linha--campanha td {
  font-weight: 500;
}
.ca-linha--regua td {
  background: rgb(var(--cv-rgb, 37 99 235) / 0.06);
}
.ca-nome {
  display: flex;
  align-items: center;
  gap: 8px;
  text-align: left;
  max-width: 380px;
  min-width: 0;
  color: var(--g-texto);
}
.ca-nome:disabled {
  cursor: default;
}
.ca-nome-txt {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.ca-ponto {
  width: 9px;
  height: 9px;
  border-radius: 50%;
  flex-shrink: 0;
  display: inline-block;
}
.ca-quebra {
  overflow-wrap: anywhere;
}
.ca-card-nums {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 10px 12px;
}
.ca-card-nums--5 {
  grid-template-columns: repeat(5, minmax(0, 1fr));
}
.ca-card-nums div {
  display: flex;
  flex-direction: column;
  min-width: 0;
}
.ca-card-nums span {
  font-size: 12px;
  line-height: 16px;
  color: var(--g-texto-3);
}
.ca-card-nums b {
  font-size: 15px;
  line-height: 20px;
  font-weight: 600;
  white-space: nowrap;
}

/* ── recomendações ── */
.ca-trava {
  display: flex;
  gap: 14px;
  align-items: flex-start;
  padding: 16px 18px;
  border-radius: var(--g-raio-md, 14px);
  background: var(--g-superficie-2);
  border: 1px solid var(--g-borda);
}
.ca-trava--api {
  background: var(--g-bom-fundo);
  border-color: transparent;
}
.ca-trava-icone {
  width: 40px;
  height: 40px;
  border-radius: 12px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 20px;
  flex-shrink: 0;
  background: var(--g-superficie);
  color: var(--g-texto-2);
}
.ca-trava--api .ca-trava-icone {
  color: var(--g-bom);
}
.ca-trava-titulo {
  margin: 0 0 2px;
  font-size: 15px;
  line-height: 22px;
  font-weight: 600;
  color: var(--g-texto);
}
.ca-resumo {
  padding: 14px 16px;
  border-radius: var(--g-raio-md, 14px);
  background: rgb(var(--cv-rgb, 37 99 235) / 0.06);
  color: var(--g-texto);
}
.ca-filtros {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.ca-filtros .cvg-chip.cvg-on {
  background: var(--cv, #2563eb);
  color: #fff;
}
.ca-filtros .cvg-chip b {
  margin-left: 4px;
}
.ca-recs {
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.ca-rec {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 18px 20px;
  border-radius: var(--g-raio-md, 14px);
  background: var(--g-superficie-2);
  border-left: 4px solid var(--g-borda);
  min-width: 0;
}
.ca-rec--alerta {
  border-left-color: var(--g-problema);
}
.ca-rec--atencao {
  border-left-color: var(--g-atencao);
}
.ca-rec--oportunidade {
  border-left-color: var(--g-bom);
}
.ca-rec-topo {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
}
.ca-rec-kind {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  height: 28px;
  padding: 0 12px;
  border-radius: 9999px;
  font-size: 13px;
  font-weight: 600;
  color: #fff;
  background: var(--cv, #2563eb);
}
.ca-rec-titulo {
  margin: 0;
  font-size: 17px;
  line-height: 24px;
  font-weight: 600;
  color: var(--g-texto);
  overflow-wrap: anywhere;
}
.ca-rec-corpo {
  margin: 4px 0 0;
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(220px, 100%), 1fr));
  gap: 10px 20px;
}
.ca-rec-corpo dt {
  font-size: 12px;
  line-height: 16px;
  font-weight: 500;
  letter-spacing: 0.02em;
  color: var(--g-texto-3);
}
.ca-rec-corpo dd {
  margin: 2px 0 0;
  font-size: 14px;
  line-height: 20px;
  color: var(--g-texto);
}
.ca-rec-corpo dd b {
  font-weight: 600;
}
.ca-rec-feita {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
}
.ca-rec-acoes {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  margin-top: 6px;
}
.ca-passos {
  margin: 0;
  padding-left: 22px;
  font-size: 14px;
  line-height: 20px;
  color: var(--g-texto-2);
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.ca-passos li::marker {
  font-weight: 600;
  color: var(--g-dia-texto);
}

/* ── formulários ── */
.ca-form {
  gap: 12px;
}
/* o reset global pinta input[type=number] de cinza; aqui todo campo é branco (ou escuro no tema escuro) */
.ca-form input[type='number'].cvg-campo {
  background: var(--g-superficie);
}
.ca-form-2col {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
}
.ca-textarea {
  height: auto;
  padding-top: 10px;
  padding-bottom: 10px;
  resize: vertical;
}
.ca-switch {
  display: flex;
  align-items: flex-start;
  gap: 12px;
}
.ca-switch .cv-switch {
  flex-shrink: 0;
  margin-top: 2px;
}

/* ── modais ── */
.ca-veu {
  position: fixed;
  inset: 0;
  z-index: 60;
  display: flex;
  align-items: flex-end;
  justify-content: center;
  padding: 12px;
  background: var(--g-veu, rgba(17, 24, 39, 0.3));
}
@media (min-width: 640px) {
  .ca-veu {
    align-items: center;
  }
}
.ca-modal {
  width: 100%;
  max-width: 520px;
  max-height: 85vh;
  overflow-y: auto;
  padding: 24px;
  border-radius: var(--g-raio-lg, 20px);
  background: var(--g-superficie, #fff);
  color: var(--g-texto, #111827);
  box-shadow: var(--g-sombra-painel);
}
</style>
