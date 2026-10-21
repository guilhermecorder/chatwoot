<script setup>
// 🎯 AGENTE DE CAMPANHAS (item 352, 19/10/2026 — "um sistema/dispositivo pra
// verificar resultados de campanha, indicadores primários/secundários/
// terciários, subir e otimizar campanhas"). Decisões dele: a régua é o NOSSO
// histórico (7/30/90/180/360 dias); estrela-guia = custo por agendamento
// (com modo custo por cirurgia para testes); autonomia = analisa → sugere →
// alguém aprova → aplica → aprende; tudo centralizado aqui e no Meu Painel.
// Filosofia: cada número diz de onde veio e com o que está sendo comparado.
import { ref, computed, onMounted, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import HBars from 'dashboard/components-next/cevico/HBars.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import CrmAPI from 'dashboard/api/crm';

const isLoading = ref(true);
const data = ref(null);
const period = ref({ preset: 'last7', from: '', to: '' });
const channel = ref('all');
const tab = ref('leitura');
const campaignView = ref('list');
const expanded = ref(new Set());
const queueFilter = ref('suggested');
const mediaChannel = ref('all');
const busy = ref(false);
const steps = ref(null); // { title, steps, action }

const pal = useCevicoPalette({
  scope: 'report:campaign_agent',
  blocks: [
    { id: 'resumo', label: 'A estrela-guia', icon: 'i-lucide-target' },
    {
      id: 'indicadores',
      label: 'Secundários e terciários',
      icon: 'i-lucide-layers',
    },
    { id: 'campanhas', label: 'Campanhas', icon: 'i-lucide-megaphone' },
    { id: 'fila', label: 'Recomendações', icon: 'i-lucide-lightbulb' },
    { id: 'placar', label: 'Aprendizado', icon: 'i-lucide-graduation-cap' },
    { id: 'media', label: 'Nossa média', icon: 'i-lucide-ruler' },
    {
      id: 'parametros',
      label: 'Parâmetros',
      icon: 'i-lucide-sliders-horizontal',
    },
    { id: 'subir', label: 'Subir campanha', icon: 'i-lucide-rocket' },
  ],
});
const { cvVars, blockVars } = pal;

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
const timeBR = iso =>
  iso
    ? new Date(iso).toLocaleString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '';
const CHANNEL_LABEL = { all: 'Tudo', meta: 'Meta', google: 'Google' };
const CHANNEL_COLORS = { meta: '#bf5af2', google: '#0a84ff' };
const SEVERITY = {
  alerta: { label: 'alerta', tone: 'cv-red' },
  atencao: { label: 'atenção', tone: 'cv-amber' },
  oportunidade: { label: 'oportunidade', tone: 'cv-green' },
  info: { label: 'aviso', tone: 'cv-slate' },
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
const LEVEL_LABEL = {
  channel: 'canal',
  campaign: 'campanha',
  adset: 'conjunto',
  ad: 'anúncio',
};

// ── a leitura ──
const p = computed(() => data.value?.params || {});
const goal = computed(() => p.value.goal || 'booked');
const goalLabel = computed(() => data.value?.goal_label || '');
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
  bom: { label: 'melhor que a nossa média', tone: 'cv-green', state: 'hit' },
  atencao: { label: 'na nossa média', tone: 'cv-amber', state: '' },
  ruim: { label: 'pior que a nossa média', tone: 'cv-red', state: 'low' },
};
const kpiState = (value, base, key) =>
  BAND[band(value, base, key)]?.state || '';
const baseSub = (value, key, fmt = money) => {
  const b = baseline.value;
  if (!b) return 'sem média ainda';
  let base = b[key];
  if (key === 'spend') base = b.daily_spend * (data.value?.period?.days || 1);
  else if (key === 'goal_cost') base = b.goal_cost;
  else if (key.startsWith('rates.')) base = b.rates?.[key.slice(6)];
  return `nossa média ${b.days}d: ${dash(base, fmt)}`;
};
const kpis = computed(() => {
  const t = totals.value;
  const b = baseline.value || {};
  const days = data.value?.period?.days || 1;
  return [
    {
      label: 'Gasto',
      value: moneyShort(t.spend),
      sub: b.daily_spend
        ? `ritmo da nossa média: ${moneyShort(b.daily_spend * days)}`
        : 'sem média ainda',
      state: '',
    },
    {
      label: 'Leads',
      value: fmtNum(t.leads),
      sub: `antes: ${fmtNum(previous.value.leads)}`,
      state: '',
    },
    {
      label: 'CPL',
      value: dash(rate(t, 'cpl'), moneyShort),
      sub: baseSub(rate(t, 'cpl'), 'rates.cpl', moneyShort),
      state: kpiState(rate(t, 'cpl'), rate(b, 'cpl'), 'cpl'),
    },
    {
      label: 'Agendamentos',
      value: fmtNum(t.booked),
      sub: `antes: ${fmtNum(previous.value.booked)}`,
      state: '',
    },
    {
      label: 'Custo por agendamento',
      value: dash(rate(t, 'cost_booked'), moneyShort),
      sub: baseSub(rate(t, 'cost_booked'), 'rates.cost_booked', moneyShort),
      state: kpiState(
        rate(t, 'cost_booked'),
        rate(b, 'cost_booked'),
        'cost_booked'
      ),
      star: goal.value === 'booked',
    },
    {
      label: 'Cirurgias',
      value: fmtNum(t.surgeries),
      sub: `fechadas: ${fmtNum(t.closed)} · antes: ${fmtNum(previous.value.surgeries)}`,
      state: '',
    },
    {
      label: 'Custo por cirurgia (CAC)',
      value: dash(rate(t, 'cost_surgery'), moneyShort),
      sub: baseSub(rate(t, 'cost_surgery'), 'rates.cost_surgery', moneyShort),
      state: kpiState(
        rate(t, 'cost_surgery'),
        rate(b, 'cost_surgery'),
        'cost_surgery'
      ),
      star: goal.value === 'surgery',
    },
    {
      label: 'Retorno (ROAS)',
      value: roasFmt(rate(t, 'roas')),
      sub: `receita ${moneyShort(t.revenue)} · ${baseSub(rate(t, 'roas'), 'rates.roas', roasFmt)}`,
      state: kpiState(rate(t, 'roas'), rate(b, 'roas'), 'roas'),
    },
  ];
});
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
const campaignBars = computed(() =>
  campaigns.value
    .filter(c => c.goal_cost)
    .map(c => ({
      label: c.name,
      sub: CHANNEL_LABEL[c.channel],
      values: [c.goal_cost],
      color: CHANNEL_COLORS[c.channel],
    }))
);
const openActionsOf = row =>
  (data.value?.actions?.open || []).filter(
    a => a.ref_id === String(row.id) && a.channel === row.channel
  );

// ── recomendações ──
const QUEUE_TABS = [
  ['suggested', 'Esperando ok'],
  ['approved', 'Aprovadas'],
  ['applied', 'Aplicadas / aprendendo'],
  ['dismissed', 'Descartadas'],
];
const allActions = computed(() => [
  ...(data.value?.actions?.open || []),
  ...(data.value?.actions?.history || []),
]);
const queueCount = status =>
  allActions.value.filter(a =>
    status === 'dismissed'
      ? ['dismissed', 'expired'].includes(a.status)
      : a.status === status
  ).length;
const queue = computed(() =>
  allActions.value.filter(a =>
    queueFilter.value === 'dismissed'
      ? ['dismissed', 'expired'].includes(a.status)
      : a.status === queueFilter.value
  )
);
const canEdit = computed(() => Boolean(data.value?.can_edit));
const state = computed(() => data.value?.state || {});
const learningLeft = a => {
  if (!a.applied_at) return null;
  const days = p.value.learning_days || 7;
  const end = new Date(a.applied_at);
  end.setDate(end.getDate() + days + 1);
  const left = Math.ceil((end - new Date()) / 86400000);
  return left > 0 ? left : 0;
};
const OUTCOME = {
  better: { label: 'melhorou', tone: 'cv-green' },
  worse: { label: 'piorou', tone: 'cv-red' },
  same: { label: 'ficou igual', tone: 'cv-amber' },
  saved: { label: 'economizou', tone: 'cv-green' },
  early: { label: 'ainda cedo', tone: 'cv-slate' },
};
const beforeAfter = a => {
  const b = a.metrics_before || {};
  const af = a.metrics_after || {};
  if (!a.learned_at) return '';
  return `custo por ${goal.value === 'surgery' ? 'cirurgia' : 'agendamento'} ${dash(b.goal_cost, moneyShort)} → ${dash(af.goal_cost, moneyShort)} · gasto ${moneyShort(b.spend)} → ${moneyShort(af.spend)} · resultados ${fmtNum(b.goal_events)} → ${fmtNum(af.goal_events)}`;
};
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
const channels = computed(() => data.value?.channels || {});
</script>

<template>
  <!-- tela só em português (CEVICO): textos direto no template, sem i18n -->
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <!-- w-full + min-w-0: nunca estica além da tela; h-full + overflow-y-auto: a própria tela rola até o fim -->
  <div
    class="cv-page cv-overlay h-full w-full min-w-0 overflow-y-auto"
    :style="cvVars"
  >
    <CevicoHero
      :pal="pal"
      title="Campanhas"
      subtitle="Meta + Google lidos contra a nossa própria média · o agente sugere, você aprova, ele aprende"
      icon="i-lucide-target"
    />

    <div class="flex items-center gap-2 flex-wrap mb-3">
      <PeriodRuler v-model="period" glass class="max-w-full min-w-0" />
      <div
        class="cv-seg cv-seg-sm inline-flex items-center gap-0.5 flex-shrink-0"
      >
        <button
          v-for="ch in ['all', 'meta', 'google']"
          :key="ch"
          class="cv-seg-item text-xs font-medium whitespace-nowrap"
          :class="channel === ch ? 'cv-seg-on' : ''"
          @click="channel = ch"
        >
          {{ CHANNEL_LABEL[ch] }}
        </button>
      </div>
    </div>

    <div
      class="cv-seg inline-flex items-center gap-0.5 flex-wrap mb-5 max-w-full"
    >
      <button
        v-for="t in [
          ['leitura', 'Leitura', 'i-lucide-bar-chart-3'],
          ['recomendacoes', 'Recomendações', 'i-lucide-lightbulb'],
          ['media', 'Nossa média', 'i-lucide-ruler'],
          ['parametros', 'Parâmetros', 'i-lucide-sliders-horizontal'],
          ['subir', 'Subir campanha', 'i-lucide-rocket'],
        ]"
        :key="t[0]"
        class="cv-seg-item text-xs font-medium whitespace-nowrap"
        :class="tab === t[0] ? 'cv-seg-on' : ''"
        @click="tab = t[0]"
      >
        <span :class="t[2]" class="text-sm mr-1 align-middle" />
        {{ t[1] }}
        <b
          v-if="t[0] === 'recomendacoes' && queueCount('suggested')"
          class="ml-1"
        >
          {{ queueCount('suggested') }}
        </b>
      </button>
    </div>

    <SkeletonScreen v-if="isLoading" variant="dashboard" />

    <template v-else-if="data">
      <!-- ════════════ LEITURA ════════════ -->
      <template v-if="tab === 'leitura'">
        <!-- a estrela-guia -->
        <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('resumo')">
          <div class="flex items-center gap-2 mb-1 flex-wrap">
            <span class="cv-icon"
              ><span class="i-lucide-target text-base"
            /></span>
            <h2 class="text-sm font-bold text-n-slate-12">
              A estrela-guia: {{ goalLabel }}
            </h2>
            <span v-if="goalVerdict" class="cv-chip" :class="goalVerdict.tone">
              {{ goalVerdict.label }} ({{ num(goalVerdict.ratio, 2) }}×)
            </span>
            <span class="text-[11px] text-n-slate-9 ml-auto">
              {{ dateBR(data.period.from) }} a {{ dateBR(data.period.to) }} ·
              {{ data.period.days }} dia(s) · comparado com a nossa média de
              {{ p.baseline_days }} dias
            </span>
          </div>
          <p class="text-[11px] text-n-slate-9 mb-4">
            Gasto, exibições e cliques vêm das plataformas (Meta por anúncio,
            Google por campanha via GA4). Leads, agendamentos, cirurgias e
            receita vêm do CRM × Agenda × Oftalmofácil, ligados ao anúncio pelo
            clique (Meta) ou pelo utm da página (Google). "Antes" = o período
            igual logo anterior.
          </p>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
            <DashKpi
              v-for="k in kpis"
              :key="k.label"
              :label="k.star ? `⭐ ${k.label}` : k.label"
              :value="k.value"
              :sub="k.sub"
              :state="k.state"
              compact
            />
          </div>
          <div
            v-if="!channels.meta?.configured && !channels.google?.configured"
            class="cv-sub p-3 mt-4 text-xs text-n-slate-11"
          >
            Nenhum canal ligado ainda: Meta em Integrações → Meta Ads (token +
            conta de anúncios) e Google em Integrações → Google (conta de
            serviço + propriedade do GA4).
          </div>
        </div>

        <!-- secundários e terciários -->
        <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('indicadores')">
          <div class="flex items-center gap-2 mb-1">
            <span class="cv-icon"
              ><span class="i-lucide-layers text-base"
            /></span>
            <h2 class="text-sm font-bold text-n-slate-12">
              Indicadores secundários e terciários
            </h2>
          </div>
          <p class="text-[11px] text-n-slate-9 mb-4">
            Secundários explicam o custo (antes do lead). Terciários explicam o
            resultado (depois do lead). Cada número com a nossa média de
            {{ p.baseline_days }} dias ao lado.
          </p>
          <div class="overflow-x-auto">
            <table class="w-full text-xs min-w-[520px]">
              <thead>
                <tr class="text-[10px] uppercase text-n-slate-9">
                  <th class="text-left py-1.5 pr-2 font-medium">Indicador</th>
                  <th
                    v-for="ch in channelsShown"
                    :key="ch"
                    class="text-right py-1.5 px-2 font-medium"
                  >
                    {{ CHANNEL_LABEL[ch] }}
                    <span class="block normal-case text-[9px]">
                      período · nossa média
                    </span>
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td
                    colspan="4"
                    class="pt-2 pb-1 text-[10px] font-bold text-n-slate-10 uppercase"
                  >
                    Secundários
                  </td>
                </tr>
                <tr
                  v-for="ind in SECONDARY"
                  :key="ind.key"
                  class="border-t ca-line"
                >
                  <td class="py-1.5 pr-2 text-n-slate-11" :title="ind.hint">
                    {{ ind.label }}
                  </td>
                  <td
                    v-for="ch in channelsShown"
                    :key="ch"
                    class="py-1.5 px-2 text-right whitespace-nowrap"
                  >
                    <b class="text-n-slate-12">{{
                      ind.fmt(indicatorValue(ind, ch))
                    }}</b>
                    <span class="text-n-slate-9">
                      · {{ ind.fmt(indicatorBase(ind, ch)) }}</span
                    >
                  </td>
                </tr>
                <tr>
                  <td
                    colspan="4"
                    class="pt-3 pb-1 text-[10px] font-bold text-n-slate-10 uppercase"
                  >
                    Terciários
                  </td>
                </tr>
                <tr
                  v-for="ind in TERTIARY"
                  :key="ind.key"
                  class="border-t ca-line"
                >
                  <td class="py-1.5 pr-2 text-n-slate-11" :title="ind.hint">
                    {{ ind.label }}
                  </td>
                  <td
                    v-for="ch in channelsShown"
                    :key="ch"
                    class="py-1.5 px-2 text-right whitespace-nowrap"
                  >
                    <b class="text-n-slate-12">{{
                      ind.fmt(indicatorValue(ind, ch))
                    }}</b>
                    <span v-if="!ind.special" class="text-n-slate-9">
                      · {{ ind.fmt(indicatorBase(ind, ch)) }}</span
                    >
                    <span
                      v-else-if="data.time_to_book?.[ch]?.measured"
                      class="text-n-slate-9"
                    >
                      · {{ data.time_to_book[ch].measured }} medidos
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <!-- campanhas em três níveis -->
        <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('campanhas')">
          <div class="flex items-center gap-2 mb-1 flex-wrap">
            <span class="cv-icon"
              ><span class="i-lucide-megaphone text-base"
            /></span>
            <h2 class="text-sm font-bold text-n-slate-12">
              Campanhas → conjuntos → anúncios
            </h2>
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
            Clique na campanha para abrir os conjuntos e os anúncios (Meta). O
            selo compara a estrela-guia de cada linha com a nossa média do
            canal. "Sem rastreio" = leads que chegaram sem utm que case com uma
            campanha.
          </p>

          <div v-if="campaignView === 'list'" class="overflow-x-auto">
            <table
              v-if="visibleRows.length"
              class="w-full text-xs min-w-[860px]"
            >
              <thead>
                <tr class="text-[10px] uppercase text-n-slate-9">
                  <th class="text-left py-1.5 pr-2 font-medium">Nome</th>
                  <th class="text-right py-1.5 px-1.5 font-medium">Gasto</th>
                  <th class="text-right py-1.5 px-1.5 font-medium">Leads</th>
                  <th class="text-right py-1.5 px-1.5 font-medium">CPL</th>
                  <th class="text-right py-1.5 px-1.5 font-medium">Agend.</th>
                  <th class="text-right py-1.5 px-1.5 font-medium">
                    Custo/agend.
                  </th>
                  <th class="text-right py-1.5 px-1.5 font-medium">Cirurg.</th>
                  <th class="text-right py-1.5 px-1.5 font-medium">CAC</th>
                  <th class="text-right py-1.5 px-1.5 font-medium">ROAS</th>
                  <th class="text-right py-1.5 px-1.5 font-medium">CTR</th>
                  <th class="text-right py-1.5 px-1.5 font-medium">CPM</th>
                  <th class="text-right py-1.5 px-1.5 font-medium">Freq.</th>
                  <th class="text-left py-1.5 pl-2 font-medium">vs média</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="row in visibleRows"
                  :key="row.rowKey || row.id"
                  class="border-t ca-line"
                  :class="row.depth === 0 ? 'font-semibold' : ''"
                >
                  <td class="py-1.5 pr-2">
                    <button
                      class="flex items-center gap-1.5 text-left max-w-[320px]"
                      :style="{ paddingLeft: `${row.depth * 16}px` }"
                      :disabled="!row.hasChildren"
                      @click="row.hasChildren && toggle(row.rowKey || row.id)"
                    >
                      <span
                        v-if="row.hasChildren"
                        class="text-n-slate-9"
                        :class="
                          row.open
                            ? 'i-lucide-chevron-down'
                            : 'i-lucide-chevron-right'
                        "
                      />
                      <span
                        v-else
                        class="w-2 h-2 rounded-full flex-shrink-0 ml-1"
                        :style="{ background: CHANNEL_COLORS[row.channel] }"
                      />
                      <span class="truncate text-n-slate-12" :title="row.name">
                        {{ row.name }}
                      </span>
                      <span class="text-[10px] text-n-slate-9 flex-shrink-0">
                        {{
                          row.depth === 0
                            ? CHANNEL_LABEL[row.channel]
                            : LEVEL_LABEL[row.level]
                        }}
                      </span>
                      <span
                        v-if="row.status && row.status !== 'ACTIVE'"
                        class="text-[10px] text-n-slate-9 flex-shrink-0"
                      >
                        · pausado
                      </span>
                    </button>
                    <p v-if="row.note" class="text-[10px] text-n-slate-9 pl-1">
                      {{ row.note }}
                    </p>
                  </td>
                  <td class="text-right px-1.5 whitespace-nowrap">
                    {{ moneyShort(row.spend) }}
                  </td>
                  <td class="text-right px-1.5">{{ fmtNum(row.leads) }}</td>
                  <td class="text-right px-1.5 whitespace-nowrap">
                    {{ dash(row.rates?.cpl, moneyShort) }}
                  </td>
                  <td class="text-right px-1.5">{{ fmtNum(row.booked) }}</td>
                  <td class="text-right px-1.5 whitespace-nowrap">
                    {{ dash(row.rates?.cost_booked, moneyShort) }}
                  </td>
                  <td class="text-right px-1.5">{{ fmtNum(row.surgeries) }}</td>
                  <td class="text-right px-1.5 whitespace-nowrap">
                    {{ dash(row.rates?.cost_surgery, moneyShort) }}
                  </td>
                  <td class="text-right px-1.5">
                    {{ roasFmt(row.rates?.roas) }}
                  </td>
                  <td class="text-right px-1.5">
                    {{ pct(row.rates?.ctr, 2) }}
                  </td>
                  <td class="text-right px-1.5 whitespace-nowrap">
                    {{ dash(row.rates?.cpm, money) }}
                  </td>
                  <td class="text-right px-1.5">{{ num(row.frequency, 2) }}</td>
                  <td class="pl-2 whitespace-nowrap">
                    <span
                      v-if="goalBand(row)"
                      class="cv-chip"
                      :class="goalBand(row).tone"
                    >
                      {{ goalBand(row).label.replace('que a nossa média', '') }}
                    </span>
                    <span
                      v-if="openActionsOf(row).length"
                      class="cv-chip ml-1"
                      :title="
                        openActionsOf(row)
                          .map(a => a.title)
                          .join(' · ')
                      "
                    >
                      <span class="i-lucide-lightbulb text-[10px]" />
                      {{ openActionsOf(row).length }}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
            <p v-else class="text-xs text-n-slate-9 py-6 text-center">
              nenhuma campanha com número no período
            </p>
          </div>

          <div
            v-else
            class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3"
          >
            <div
              v-for="c in campaigns"
              :key="`${c.channel}-${c.id}`"
              class="cv-sub p-4"
            >
              <div class="flex items-center gap-2 mb-2">
                <span
                  class="w-2.5 h-2.5 rounded-full flex-shrink-0"
                  :style="{ background: CHANNEL_COLORS[c.channel] }"
                />
                <p
                  class="text-sm font-bold text-n-slate-12 truncate"
                  :title="c.name"
                >
                  {{ c.name }}
                </p>
                <span
                  v-if="goalBand(c)"
                  class="cv-chip ml-auto flex-shrink-0"
                  :class="goalBand(c).tone"
                >
                  {{ goalBand(c).label.replace('que a nossa média', '') }}
                </span>
              </div>
              <div class="grid grid-cols-3 gap-2 text-xs">
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
                  <p class="text-[10px] text-n-slate-9">CPL</p>
                  <p class="font-semibold text-n-slate-11">
                    {{ dash(c.rates?.cpl, moneyShort) }}
                  </p>
                </div>
                <div>
                  <p class="text-[10px] text-n-slate-9">Agend.</p>
                  <p class="font-bold text-n-slate-12">
                    {{ fmtNum(c.booked) }}
                  </p>
                </div>
                <div>
                  <p class="text-[10px] text-n-slate-9">Custo/agend.</p>
                  <p class="font-bold text-n-slate-12">
                    {{ dash(c.rates?.cost_booked, moneyShort) }}
                  </p>
                </div>
                <div>
                  <p class="text-[10px] text-n-slate-9">CAC</p>
                  <p class="font-bold text-n-slate-12">
                    {{ dash(c.rates?.cost_surgery, moneyShort) }}
                  </p>
                </div>
                <div>
                  <p class="text-[10px] text-n-slate-9">ROAS</p>
                  <p class="font-semibold text-n-slate-11">
                    {{ roasFmt(c.rates?.roas) }}
                  </p>
                </div>
                <div>
                  <p class="text-[10px] text-n-slate-9">CTR</p>
                  <p class="font-semibold text-n-slate-11">
                    {{ pct(c.rates?.ctr, 2) }}
                  </p>
                </div>
                <div>
                  <p class="text-[10px] text-n-slate-9">CPM</p>
                  <p class="font-semibold text-n-slate-11">
                    {{ dash(c.rates?.cpm, money) }}
                  </p>
                </div>
              </div>
              <p
                v-if="c.children?.length"
                class="text-[10px] text-n-slate-9 mt-2"
              >
                {{ c.children.length }} conjunto(s) ·
                {{
                  c.children.reduce((n, s) => n + (s.children?.length || 0), 0)
                }}
                anúncio(s)
              </p>
            </div>
          </div>

          <div v-if="campaignBars.length" class="mt-5">
            <p class="text-[11px] text-n-slate-9 mb-2">
              Barra = {{ goalLabel }} de cada campanha (menor é melhor).
            </p>
            <HBars
              :rows="campaignBars"
              :series="[{ label: goalLabel, format: v => moneyShort(v) }]"
              :format="v => moneyShort(v)"
              :label-width="15"
              :highlight-max="false"
              empty-text="sem campanha com resultado no período"
            />
          </div>
        </div>
      </template>

      <!-- ════════════ RECOMENDAÇÕES ════════════ -->
      <template v-else-if="tab === 'recomendacoes'">
        <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('fila')">
          <div class="flex items-center gap-2 mb-1 flex-wrap">
            <span class="cv-icon"
              ><span class="i-lucide-lightbulb text-base"
            /></span>
            <h2 class="text-sm font-bold text-n-slate-12">
              Recomendações do agente
            </h2>
            <span class="text-[11px] text-n-slate-9">
              última leitura:
              {{
                state.last_run_at ? timeBR(state.last_run_at) : 'ainda não leu'
              }}
              <template v-if="state.new !== undefined">
                · {{ state.new }} nova(s) ·
                {{ state.learned || 0 }} aprendida(s)</template
              >
            </span>
            <button
              v-if="canEdit"
              class="cv-btn cv-btn-sm ml-auto"
              :disabled="isRunning"
              @click="runNow"
            >
              <span
                class="i-lucide-refresh-cw text-xs"
                :class="isRunning ? 'animate-spin' : ''"
              />
              Ler agora
            </button>
          </div>
          <p class="text-[11px] text-n-slate-9 mb-3">
            O agente lê os últimos {{ p.window_days }} dias contra a nossa média
            de {{ p.baseline_days }} dias e só fala com volume mínimo. Nada muda
            sem o seu ok: aprovar → aplicar (pela API da Meta, se ligada, ou à
            mão no Gerenciador) → {{ p.learning_days }} dias depois ele compara
            o antes × depois e aprende.
          </p>
          <p
            v-if="state.brief"
            class="cv-sub p-3 text-sm text-n-slate-11 leading-relaxed mb-3"
          >
            {{ state.brief }}
          </p>

          <div
            class="cv-seg cv-seg-sm inline-flex items-center gap-0.5 flex-wrap mb-4 max-w-full"
          >
            <button
              v-for="t in QUEUE_TABS"
              :key="t[0]"
              class="cv-seg-item text-xs font-medium whitespace-nowrap"
              :class="queueFilter === t[0] ? 'cv-seg-on' : ''"
              @click="queueFilter = t[0]"
            >
              {{ t[1] }}
              <b v-if="queueCount(t[0])" class="ml-1">{{ queueCount(t[0]) }}</b>
            </button>
          </div>

          <div v-if="queue.length" class="space-y-2">
            <div v-for="a in queue" :key="a.id" class="cv-sub p-4">
              <div class="flex items-center gap-2 flex-wrap mb-1">
                <span class="cv-chip" :class="SEVERITY[a.severity]?.tone">{{
                  SEVERITY[a.severity]?.label
                }}</span>
                <span class="cv-chip">
                  <span
                    class="w-1.5 h-1.5 rounded-full"
                    :style="{ background: CHANNEL_COLORS[a.channel] }"
                  />
                  {{ CHANNEL_LABEL[a.channel] }} · {{ LEVEL_LABEL[a.level] }}
                </span>
                <span class="cv-chip">{{ KIND_LABEL[a.kind] }}</span>
                <span class="text-[10px] text-n-slate-9 ml-auto">{{
                  dateBR(a.suggested_on)
                }}</span>
              </div>
              <p class="text-sm font-bold text-n-slate-12">{{ a.title }}</p>
              <p class="text-[11px] text-n-slate-10 mb-1 truncate">
                {{ a.ref_name
                }}<template v-if="a.campaign_name && a.level !== 'campaign'">
                  · {{ a.campaign_name }}
                </template>
              </p>
              <p class="text-xs text-n-slate-11 leading-relaxed">
                {{ a.evidence }}
              </p>
              <p class="text-xs text-n-slate-12 leading-relaxed mt-1">
                <b>O que fazer:</b> {{ a.suggestion }}
              </p>
              <p v-if="a.expected" class="text-[11px] text-n-slate-10 mt-1">
                <span class="i-lucide-trending-up text-[11px] align-middle" />
                esperado: {{ a.expected }}
              </p>
              <p v-if="a.error" class="text-[11px] text-red-600 mt-1">
                {{ a.error }}
              </p>

              <!-- aplicada: aprendizado -->
              <div v-if="a.status === 'applied'" class="mt-2 text-[11px]">
                <span class="text-n-slate-9">
                  aplicada {{ timeBR(a.applied_at) }} ({{
                    a.applied_mode === 'api' ? 'pela API' : 'à mão'
                  }})
                </span>
                <template v-if="a.learned_at">
                  <span
                    class="cv-chip ml-2"
                    :class="OUTCOME[a.outcome]?.tone"
                    >{{ OUTCOME[a.outcome]?.label }}</span
                  >
                  <p class="text-n-slate-11 mt-1">{{ beforeAfter(a) }}</p>
                </template>
                <span v-else class="cv-chip cv-slate ml-2">
                  aprendendo · faltam {{ learningLeft(a) }} dia(s)
                </span>
              </div>

              <div
                v-if="canEdit"
                class="flex items-center gap-2 flex-wrap mt-3"
              >
                <template v-if="a.status === 'suggested'">
                  <button
                    class="cv-btn cv-btn-sm"
                    :disabled="busy"
                    @click="decide(a, 'approve')"
                  >
                    <span class="i-lucide-check text-xs" /> Aprovar
                  </button>
                  <button
                    class="cv-btn cv-btn-sm cv-btn-ghost"
                    :disabled="busy"
                    @click="decide(a, 'dismiss')"
                  >
                    Descartar
                  </button>
                </template>
                <template v-else-if="a.status === 'approved'">
                  <button
                    class="cv-btn cv-btn-sm"
                    :disabled="busy"
                    @click="apply(a)"
                  >
                    <span class="i-lucide-play text-xs" />
                    {{
                      a.platform &&
                      a.channel === 'meta' &&
                      channels.meta?.execute
                        ? 'Aplicar na Meta'
                        : 'Ver passo a passo'
                    }}
                  </button>
                  <button
                    class="cv-btn cv-btn-sm cv-btn-ghost"
                    :disabled="busy"
                    @click="markManual(a)"
                  >
                    Fiz à mão
                  </button>
                  <button
                    class="cv-btn cv-btn-sm cv-btn-ghost"
                    :disabled="busy"
                    @click="decide(a, 'dismiss')"
                  >
                    Descartar
                  </button>
                </template>
                <template
                  v-else-if="['dismissed', 'expired'].includes(a.status)"
                >
                  <button
                    class="cv-btn cv-btn-sm cv-btn-ghost"
                    :disabled="busy"
                    @click="decide(a, 'reopen')"
                  >
                    Voltar para a fila
                  </button>
                </template>
              </div>
            </div>
          </div>
          <p v-else class="text-xs text-n-slate-9 py-6 text-center">
            {{
              queueFilter === 'suggested'
                ? 'nada esperando ok — ou o agente ainda não leu (botão "Ler agora")'
                : 'nada aqui'
            }}
          </p>
        </div>

        <!-- placar do aprendizado -->
        <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('placar')">
          <div class="flex items-center gap-2 mb-1">
            <span class="cv-icon"
              ><span class="i-lucide-graduation-cap text-base"
            /></span>
            <h2 class="text-sm font-bold text-n-slate-12">
              O que o agente aprendeu
            </h2>
          </div>
          <p class="text-[11px] text-n-slate-9 mb-3">
            Placar por regra: cada recomendação aplicada vira um antes × depois.
            Regra que erra mais do que acerta (5 ou mais julgadas) entra em
            observação e só avisa, sem propor mudança.
          </p>
          <div
            v-if="scoreboard.length"
            class="grid grid-cols-1 md:grid-cols-2 gap-2"
          >
            <div
              v-for="r in scoreboard"
              :key="r.rule"
              class="cv-sub p-3 text-xs flex items-center gap-2 flex-wrap"
            >
              <b class="text-n-slate-12">{{ r.label }}</b>
              <span v-if="r.observing" class="cv-chip cv-amber">
                em observação
              </span>
              <span class="ml-auto text-n-slate-11">
                melhorou <b>{{ r.better }}</b> · piorou <b>{{ r.worse }}</b> ·
                igual <b>{{ r.same }}</b> · economizou <b>{{ r.saved }}</b> ·
                cedo <b>{{ r.early }}</b>
              </span>
              <span
                v-if="r.confidence !== null"
                class="cv-chip"
                :class="
                  r.confidence >= 0.6
                    ? 'cv-green'
                    : r.confidence < 0.4
                      ? 'cv-red'
                      : 'cv-amber'
                "
              >
                acerta {{ pct(r.confidence, 0) }}
              </span>
            </div>
          </div>
          <p v-else class="text-xs text-n-slate-9 py-4 text-center">
            ainda sem antes × depois — aparece {{ p.learning_days }} dias depois
            da primeira aplicada
          </p>
        </div>
      </template>

      <!-- ════════════ NOSSA MÉDIA ════════════ -->
      <template v-else-if="tab === 'media'">
        <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('media')">
          <div class="flex items-center gap-2 mb-1 flex-wrap">
            <span class="cv-icon"
              ><span class="i-lucide-ruler text-base"
            /></span>
            <h2 class="text-sm font-bold text-n-slate-12">
              Nossa média: 7 · 30 · 90 · 180 · 360 dias
            </h2>
            <div
              class="cv-seg cv-seg-sm inline-flex items-center gap-0.5 ml-auto"
            >
              <button
                v-for="ch in ['all', 'meta', 'google']"
                :key="ch"
                class="cv-seg-item text-xs font-medium"
                :class="mediaChannel === ch ? 'cv-seg-on' : ''"
                @click="mediaChannel = ch"
              >
                {{ CHANNEL_LABEL[ch] }}
              </button>
            </div>
          </div>
          <p class="text-[11px] text-n-slate-9 mb-4">
            Janelas fechadas em ontem. É contra a de {{ p.baseline_days }} dias
            que o agente julga (troque em Parâmetros). "Jogamos o nosso próprio
            jogo": nenhum número de mercado entra aqui.
          </p>
          <div class="overflow-x-auto">
            <table class="w-full text-xs min-w-[900px]">
              <thead>
                <tr class="text-[10px] uppercase text-n-slate-9">
                  <th class="text-left py-1.5 pr-2 font-medium">Janela</th>
                  <th
                    v-for="c in MEDIA_COLS"
                    :key="c.label"
                    class="text-right py-1.5 px-1.5 font-medium"
                  >
                    {{ c.label }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="r in mediaRows"
                  :key="r.days"
                  class="border-t ca-line"
                  :class="
                    Number(r.days) === Number(p.baseline_days)
                      ? 'font-bold'
                      : ''
                  "
                >
                  <td class="py-2 pr-2 text-n-slate-12 whitespace-nowrap">
                    {{ r.days }} dias
                    <span
                      v-if="Number(r.days) === Number(p.baseline_days)"
                      class="cv-chip ml-1"
                      >régua</span
                    >
                    <span
                      v-if="r.since"
                      class="block text-[10px] text-n-slate-9 font-normal"
                      >{{ dateBR(r.since) }} a {{ dateBR(r.until) }}</span
                    >
                  </td>
                  <td
                    v-for="c in MEDIA_COLS"
                    :key="c.label"
                    class="text-right px-1.5 whitespace-nowrap"
                  >
                    {{ c.get(r) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </template>

      <!-- ════════════ PARÂMETROS ════════════ -->
      <template v-else-if="tab === 'parametros'">
        <div
          v-if="paramsDraft"
          class="cv-block p-5 sm:p-6 mb-4"
          :style="blockVars('parametros')"
        >
          <div class="flex items-center gap-2 mb-1">
            <span class="cv-icon"
              ><span class="i-lucide-sliders-horizontal text-base"
            /></span>
            <h2 class="text-sm font-bold text-n-slate-12">
              Parâmetros do agente
            </h2>
          </div>
          <p class="text-[11px] text-n-slate-9 mb-4">
            O que o agente persegue, com quanta verba, quando fala e quando
            mexe.
            {{
              canEdit
                ? ''
                : 'Você só pode ver; peça a um administrador para mudar.'
            }}
          </p>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div class="cv-sub p-4 space-y-3">
              <p class="text-xs font-bold text-n-slate-12">Estrela-guia</p>
              <div class="cv-seg cv-seg-sm inline-flex items-center gap-0.5">
                <button
                  v-for="g in [
                    ['booked', 'Custo por agendamento'],
                    ['surgery', 'Custo por cirurgia'],
                  ]"
                  :key="g[0]"
                  class="cv-seg-item text-xs font-medium"
                  :class="paramsDraft.goal === g[0] ? 'cv-seg-on' : ''"
                  :disabled="!canEdit"
                  @click="paramsDraft.goal = g[0]"
                >
                  {{ g[1] }}
                </button>
              </div>
              <p class="text-[11px] text-n-slate-9">
                Agendamento chega em dias e já filtra lead ruim; cirurgia é o
                CAC real, mas demora semanas. Troque para testes.
              </p>
              <label class="block text-xs">
                <span class="text-n-slate-10">Verba mensal da Meta (R$)</span>
                <input
                  v-model="paramsDraft.budget.meta"
                  type="number"
                  min="0"
                  class="cv-input w-full mt-1"
                  :disabled="!canEdit"
                />
              </label>
              <label class="block text-xs">
                <span class="text-n-slate-10">Verba mensal do Google (R$)</span>
                <input
                  v-model="paramsDraft.budget.google"
                  type="number"
                  min="0"
                  class="cv-input w-full mt-1"
                  :disabled="!canEdit"
                />
              </label>
              <label class="block text-xs">
                <span class="text-n-slate-10"
                  >Teto por conjunto/campanha por dia (R$, 0 = sem teto)</span
                >
                <input
                  v-model="paramsDraft.daily_cap"
                  type="number"
                  min="0"
                  class="cv-input w-full mt-1"
                  :disabled="!canEdit"
                />
              </label>
            </div>

            <div class="cv-sub p-4 space-y-3">
              <p class="text-xs font-bold text-n-slate-12">Janelas e régua</p>
              <label class="block text-xs">
                <span class="text-n-slate-10"
                  >Janela que o agente julga (dias fechados)</span
                >
                <input
                  v-model="paramsDraft.window_days"
                  type="number"
                  min="3"
                  max="30"
                  class="cv-input w-full mt-1"
                  :disabled="!canEdit"
                />
              </label>
              <label class="block text-xs">
                <span class="text-n-slate-10">Nossa média de referência</span>
                <select
                  v-model="paramsDraft.baseline_days"
                  class="cv-input w-full mt-1"
                  :disabled="!canEdit"
                >
                  <option v-for="d in WINDOWS" :key="d" :value="d">
                    {{ d }} dias
                  </option>
                </select>
              </label>
              <label class="block text-xs">
                <span class="text-n-slate-10"
                  >Pior que a média em (%) = atenção · 2× = pausar</span
                >
                <input
                  v-model="paramsDraft.worse_pct"
                  type="number"
                  min="10"
                  max="200"
                  class="cv-input w-full mt-1"
                  :disabled="!canEdit"
                />
              </label>
              <label class="block text-xs">
                <span class="text-n-slate-10"
                  >Melhor que a média em (%) = campeã (sobe verba)</span
                >
                <input
                  v-model="paramsDraft.better_pct"
                  type="number"
                  min="10"
                  max="90"
                  class="cv-input w-full mt-1"
                  :disabled="!canEdit"
                />
              </label>
              <label class="block text-xs">
                <span class="text-n-slate-10">Passo de verba (%)</span>
                <input
                  v-model="paramsDraft.budget_step_pct"
                  type="number"
                  min="5"
                  max="100"
                  class="cv-input w-full mt-1"
                  :disabled="!canEdit"
                />
              </label>
            </div>

            <div class="cv-sub p-4 space-y-3">
              <p class="text-xs font-bold text-n-slate-12">
                Volume mínimo para falar
              </p>
              <p class="text-[11px] text-n-slate-9">
                Abaixo disso é ruído: o agente não julga.
              </p>
              <div class="grid grid-cols-2 gap-2">
                <label class="block text-xs"
                  ><span class="text-n-slate-10">Gasto (R$)</span
                  ><input
                    v-model="paramsDraft.min.spend"
                    type="number"
                    min="0"
                    class="cv-input w-full mt-1"
                    :disabled="!canEdit"
                /></label>
                <label class="block text-xs"
                  ><span class="text-n-slate-10">Exibições</span
                  ><input
                    v-model="paramsDraft.min.impressions"
                    type="number"
                    min="0"
                    class="cv-input w-full mt-1"
                    :disabled="!canEdit"
                /></label>
                <label class="block text-xs"
                  ><span class="text-n-slate-10">Cliques</span
                  ><input
                    v-model="paramsDraft.min.clicks"
                    type="number"
                    min="0"
                    class="cv-input w-full mt-1"
                    :disabled="!canEdit"
                /></label>
                <label class="block text-xs"
                  ><span class="text-n-slate-10">Leads</span
                  ><input
                    v-model="paramsDraft.min.leads"
                    type="number"
                    min="0"
                    class="cv-input w-full mt-1"
                    :disabled="!canEdit"
                /></label>
                <label class="block text-xs col-span-2"
                  ><span class="text-n-slate-10"
                    >Resultados (agend./cirurgias) para chamar de campeã</span
                  ><input
                    v-model="paramsDraft.min.goal_events"
                    type="number"
                    min="0"
                    class="cv-input w-full mt-1"
                    :disabled="!canEdit"
                /></label>
              </div>
            </div>

            <div class="cv-sub p-4 space-y-3">
              <p class="text-xs font-bold text-n-slate-12">
                Autonomia e aprendizado
              </p>
              <label class="block text-xs">
                <span class="text-n-slate-10"
                  >Dias para medir o antes × depois</span
                >
                <input
                  v-model="paramsDraft.learning_days"
                  type="number"
                  min="3"
                  max="30"
                  class="cv-input w-full mt-1"
                  :disabled="!canEdit"
                />
              </label>
              <label class="block text-xs">
                <span class="text-n-slate-10"
                  >Não mexer de novo no mesmo item antes de (dias)</span
                >
                <input
                  v-model="paramsDraft.respect_days"
                  type="number"
                  min="1"
                  max="30"
                  class="cv-input w-full mt-1"
                  :disabled="!canEdit"
                />
              </label>
              <div
                v-for="sw in [
                  [
                    'enabled',
                    'Agente ligado',
                    'desligado = não lê, não sugere',
                  ],
                  [
                    'execute_api',
                    'Aplicar na Meta pela API',
                    'precisa de token com ads_management; desligado = passo a passo para fazer à mão',
                  ],
                  ['weekend', 'Não sugerir no fim de semana', ''],
                  [
                    'brief_ai',
                    'Resumo diário escrito pela IA',
                    'haiku, barato; os números são do sistema',
                  ],
                ]"
                :key="sw[0]"
                class="flex items-center gap-3"
              >
                <button
                  type="button"
                  class="cv-switch"
                  :class="paramsDraft[sw[0]] ? 'cv-switch-on' : ''"
                  :aria-pressed="paramsDraft[sw[0]]"
                  :disabled="!canEdit"
                  @click="paramsDraft[sw[0]] = !paramsDraft[sw[0]]"
                />
                <div class="text-xs">
                  <p class="text-n-slate-12 font-medium">{{ sw[1] }}</p>
                  <p v-if="sw[2]" class="text-[10px] text-n-slate-9">
                    {{ sw[2] }}
                  </p>
                </div>
              </div>
              <p class="text-[11px] text-n-slate-9">
                Modo atual:
                <b>analisa → sugere → você aprova → aplica → aprende</b>. A
                autonomia total vem depois, com o placar provado.
              </p>
            </div>
          </div>

          <div v-if="canEdit" class="flex items-center gap-2 mt-4">
            <button
              class="cv-btn"
              :disabled="isSavingParams"
              @click="saveParams"
            >
              <span class="i-lucide-save text-xs" /> Guardar parâmetros
            </button>
            <button class="cv-btn cv-btn-ghost" @click="resetParams">
              Desfazer
            </button>
          </div>
        </div>
      </template>

      <!-- ════════════ SUBIR CAMPANHA ════════════ -->
      <template v-else-if="tab === 'subir'">
        <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('subir')">
          <div class="flex items-center gap-2 mb-1">
            <span class="cv-icon"
              ><span class="i-lucide-rocket text-base"
            /></span>
            <h2 class="text-sm font-bold text-n-slate-12">
              Ficha de subir campanha
            </h2>
          </div>
          <p class="text-[11px] text-n-slate-9 mb-4">
            Preencha a ficha e o agente monta o plano: nomes no padrão da casa,
            sufixo de rastreio, estrutura campanha → conjunto → anúncios. Com
            "Aplicar na Meta pela API" ligado, ele cria tudo PAUSADO para você
            conferir no Gerenciador e ligar. Sem a chavinha, a ficha guarda o
            roteiro para subir à mão.
          </p>

          <div v-if="canEdit" class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div class="cv-sub p-4 space-y-3">
              <label class="block text-xs">
                <span class="text-n-slate-10">Nome curto da campanha</span>
                <input
                  v-model="brief.name"
                  class="cv-input w-full mt-1"
                  placeholder="ex.: Cirurgia de miopia · cenas do dia a dia"
                />
              </label>
              <div class="text-xs">
                <span class="text-n-slate-10">Objetivo</span>
                <div
                  class="cv-seg cv-seg-sm inline-flex items-center gap-0.5 mt-1 flex-wrap"
                >
                  <button
                    v-for="o in [
                      ['leads_whatsapp', 'Leads pelo WhatsApp'],
                      ['leads_page', 'Leads pela página'],
                    ]"
                    :key="o[0]"
                    class="cv-seg-item text-xs font-medium"
                    :class="brief.objective === o[0] ? 'cv-seg-on' : ''"
                    @click="brief.objective = o[0]"
                  >
                    {{ o[1] }}
                  </button>
                </div>
              </div>
              <label class="block text-xs">
                <span class="text-n-slate-10">Verba diária (R$)</span>
                <input
                  v-model="brief.daily_budget"
                  type="number"
                  min="1"
                  class="cv-input w-full mt-1"
                />
              </label>
              <label
                v-if="brief.objective === 'leads_whatsapp'"
                class="block text-xs"
              >
                <span class="text-n-slate-10"
                  >WhatsApp de destino (só números, com 55)</span
                >
                <input
                  v-model="brief.whatsapp"
                  class="cv-input w-full mt-1"
                  placeholder="5511998085773"
                />
              </label>
              <label v-else class="block text-xs">
                <span class="text-n-slate-10">Página de destino</span>
                <input
                  v-model="brief.page_url"
                  class="cv-input w-full mt-1"
                  placeholder="https://clinica.cevico.com.br/…-m"
                />
              </label>
              <label class="block text-xs">
                <span class="text-n-slate-10"
                  >ID da página do Facebook (para o destino WhatsApp pela API;
                  opcional)</span
                >
                <input v-model="brief.page_id" class="cv-input w-full mt-1" />
              </label>
            </div>
            <div class="cv-sub p-4 space-y-3">
              <p class="text-xs font-bold text-n-slate-12">Público</p>
              <label class="block text-xs">
                <span class="text-n-slate-10"
                  >Cidades/região (texto livre; o país é o Brasil)</span
                >
                <input
                  v-model="brief.audience.cities"
                  class="cv-input w-full mt-1"
                  placeholder="ex.: São Paulo e região (40 km)"
                />
              </label>
              <div class="grid grid-cols-2 gap-2">
                <label class="block text-xs"
                  ><span class="text-n-slate-10">Idade mínima</span
                  ><input
                    v-model="brief.audience.age_min"
                    type="number"
                    min="18"
                    max="65"
                    class="cv-input w-full mt-1"
                /></label>
                <label class="block text-xs"
                  ><span class="text-n-slate-10">Idade máxima</span
                  ><input
                    v-model="brief.audience.age_max"
                    type="number"
                    min="18"
                    max="65"
                    class="cv-input w-full mt-1"
                /></label>
              </div>
              <p class="text-xs font-bold text-n-slate-12 mt-2">
                Anúncios a reaproveitar (até 10)
              </p>
              <div
                v-if="creatives.length"
                class="flex flex-wrap gap-1.5 max-h-40 overflow-y-auto"
              >
                <button
                  v-for="c in creatives"
                  :key="c.ad_id"
                  class="cv-chip cv-chip-wrap text-left"
                  :class="
                    brief.creative_ad_ids.includes(c.ad_id) ? 'cv-green' : ''
                  "
                  :title="c.campaign_name"
                  @click="toggleCreative(c.ad_id)"
                >
                  <span
                    v-if="brief.creative_ad_ids.includes(c.ad_id)"
                    class="i-lucide-check text-[10px]"
                  />
                  {{ c.name }}
                </button>
              </div>
              <p v-else class="text-[11px] text-n-slate-9">
                Sem anúncios na Central de Criativos ainda — as peças novas do
                núcleo sobem à mão.
              </p>
              <label class="block text-xs">
                <span class="text-n-slate-10">Observações</span>
                <textarea
                  v-model="brief.notes"
                  rows="2"
                  class="cv-input ca-textarea w-full mt-1 py-2"
                />
              </label>
              <button class="cv-btn" :disabled="isPlanning" @click="planBrief">
                <span class="i-lucide-wand-2 text-xs" /> Montar plano e guardar
                ficha
              </button>
            </div>
          </div>

          <div v-if="briefs.length" class="mt-5 space-y-3">
            <p class="text-xs font-bold text-n-slate-12">Fichas</p>
            <div v-for="b in briefs" :key="b.id" class="cv-sub p-4">
              <div class="flex items-center gap-2 flex-wrap mb-1">
                <span
                  class="cv-chip"
                  :class="b.status === 'criada' ? 'cv-green' : ''"
                >
                  {{
                    b.status === 'criada' ? 'criada pausada na Meta' : 'ficha'
                  }}
                </span>
                <p class="text-sm font-bold text-n-slate-12">
                  {{ b.plan?.campaign_name || b.name }}
                </p>
                <span class="text-[10px] text-n-slate-9 ml-auto"
                  >{{ timeBR(b.created_at)
                  }}<template v-if="b.created_by">
                    · {{ b.created_by }}</template
                  ></span
                >
              </div>
              <p class="text-[11px] text-n-slate-10 mb-2">
                Conjunto: {{ b.plan?.adset_name }} · R$
                {{ num(b.daily_budget, 2) }}/dia (≈
                {{ moneyShort(b.plan?.monthly_estimate) }}/mês)
              </p>
              <p
                v-if="b.plan?.budget_note"
                class="text-[11px] text-amber-700 mb-2"
              >
                {{ b.plan.budget_note }}
              </p>
              <ol class="text-xs text-n-slate-11 space-y-1 list-decimal pl-4">
                <li v-for="(s, i) in b.plan?.steps || []" :key="i">{{ s }}</li>
              </ol>
              <div class="flex items-center gap-2 flex-wrap mt-3">
                <button
                  class="cv-btn cv-btn-sm cv-btn-ghost"
                  @click="copy(b.plan?.utm || '')"
                >
                  <span class="i-lucide-copy text-xs" /> Copiar sufixo de
                  rastreio
                </button>
                <button
                  v-if="
                    canEdit && b.status !== 'criada' && b.channel === 'meta'
                  "
                  class="cv-btn cv-btn-sm"
                  :disabled="busy || !channels.meta?.execute"
                  :title="
                    channels.meta?.execute
                      ? ''
                      : 'Ligue a chavinha Aplicar na Meta pela API, em Parâmetros'
                  "
                  @click="launch(b)"
                >
                  <span class="i-lucide-rocket text-xs" /> Criar pausada na Meta
                </button>
                <span
                  v-if="b.meta?.campaign_id"
                  class="text-[11px] text-n-slate-9"
                >
                  campanha {{ b.meta.campaign_id }} · conjunto
                  {{ b.meta.adset_id }} ·
                  {{ (b.meta.ads || []).length }} anúncio(s)
                </span>
                <p v-if="b.error" class="text-[11px] text-red-600">
                  {{ b.error }}
                </p>
                <button
                  v-if="canEdit"
                  class="cv-btn cv-btn-sm cv-btn-ghost cv-btn-danger ml-auto"
                  @click="removeBrief(b)"
                >
                  Apagar
                </button>
              </div>
            </div>
          </div>
        </div>
      </template>
    </template>

    <!-- passo a passo para fazer à mão -->
    <div
      v-if="steps"
      class="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-3 ca-backdrop"
      @click.self="steps = null"
    >
      <div class="cv-pop w-full max-w-lg p-5 max-h-[85vh] overflow-y-auto">
        <p class="text-sm font-bold text-n-slate-12 mb-1">{{ steps.title }}</p>
        <p v-if="steps.error" class="text-[11px] text-red-600 mb-2">
          {{ steps.error }}
        </p>
        <p class="text-[11px] text-n-slate-9 mb-3">
          Faça no Gerenciador e marque aqui; o antes × depois começa a contar.
        </p>
        <ol class="text-xs text-n-slate-11 space-y-1.5 list-decimal pl-4">
          <li v-for="(s, i) in steps.steps" :key="i">{{ s }}</li>
        </ol>
        <div class="flex items-center gap-2 mt-4">
          <button
            class="cv-btn cv-btn-sm"
            :disabled="busy"
            @click="markManual(steps.action)"
          >
            <span class="i-lucide-check text-xs" /> Fiz à mão
          </button>
          <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="steps = null">
            Depois
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* linhas das tabelas na cor do dia; o resto é o kit .cv-* */
.ca-line {
  border-color: rgb(var(--cv-rgb) / 0.12);
}
.ca-textarea {
  height: auto;
}
.ca-backdrop {
  background: rgba(0, 0, 0, 0.35);
}
</style>
