<script setup>
// 🎯 CENTRAL DE CRIATIVOS (item 172, rodadas 2 e 3): cada anúncio da Meta
// lido como gancho, corpo e CTA — fichas completas de largura inteira ou
// tabela; réguas com faixas ruim/atenção/bom (parâmetros manuais ou
// automáticos pelo NOSSO histórico, com passo de superação); campanhas
// escolhidas de forma intencional (cartões com contorno); campeões com
// moldura dourada parada + selo, e botão Transcrever em cada um; pódio de
// ganchos, corpos e CTAs; recordes por dia/semana/mês e campeões mês a mês.
// Kit CEVICO (cv-*, paleta por bloco), gráficos sem lib.
import { ref, computed, onMounted, onBeforeUnmount, watch } from 'vue';
import { useRouter } from 'vue-router';
import CevicoCreativesAPI from 'dashboard/api/cevicoCreatives';
import CrmAPI from 'dashboard/api/crm';
import { useMapGetter } from 'dashboard/composables/store';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import ShareBar from 'dashboard/components-next/cevico/ShareBar.vue';
import MiniBars from 'dashboard/components-next/cevico/MiniBars.vue';
import CreativeCard from 'dashboard/components-next/cevico/creatives/CreativeCard.vue';
import CreativeTable from 'dashboard/components-next/cevico/creatives/CreativeTable.vue';
import CreativeDetail from 'dashboard/components-next/cevico/creatives/CreativeDetail.vue';
import CreativeCompare from 'dashboard/components-next/cevico/creatives/CreativeCompare.vue';
import AssetPodium from 'dashboard/components-next/cevico/creatives/AssetPodium.vue';
import VideoSpeechRanking from 'dashboard/components-next/cevico/creatives/VideoSpeechRanking.vue';
import BulletMeter from 'dashboard/components-next/cevico/creatives/BulletMeter.vue';
import RadarAxesPicker from 'dashboard/components-next/cevico/creatives/RadarAxesPicker.vue';
import CreativeRadar from 'dashboard/components-next/cevico/creatives/CreativeRadar.vue';
import { useTranscribe } from 'dashboard/components-next/cevico/creatives/useTranscribe';
import {
  fmtMoney,
  fmtCompact,
  fmtPct,
  fmtNum,
  fmtDate,
  METRIC_DEFS,
  PART_META,
  FORMAT_ICON,
  delta,
  fmtDelta,
  deltaCls,
} from 'dashboard/components-next/cevico/creatives/creativeFormat';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { hexFromGrad } from 'dashboard/helper/cevicoPalettes';
import { useAlert } from 'dashboard/composables';

const router = useRouter();
const currentRole = useMapGetter('getCurrentRole');
const isAdmin = computed(() => currentRole.value === 'administrator');
const { transcribe } = useTranscribe();

const period = ref({ preset: 'month', from: '', to: '' });
const filters = ref({
  campaign_id: '',
  fmt: '',
  status: '',
  q: '',
  sort: 'spend',
});
const data = ref(null);
const isLoading = ref(false);
const hasError = ref(false);
const tab = ref('criativos');
const VIEW_KEY = 'cevico_creatives_view';
const view = ref(
  localStorage.getItem(VIEW_KEY) === 'tabela' ? 'tabela' : 'fichas'
);
const setView = v => {
  view.value = v;
  localStorage.setItem(VIEW_KEY, v);
};
const assets = ref(null);
// 🎬 item 181: transcrição dos vídeos (gancho/corpo/CTA passam a ser o que o vídeo FALA)
const isTranscribing = ref(false);
const transcribeVideos = async () => {
  isTranscribing.value = true;
  try {
    const { data: res } = await CevicoCreativesAPI.transcribeVideos();
    useAlert(
      res.enqueued
        ? `${res.enqueued} vídeo(s) na fila de transcrição — volte em alguns minutos.`
        : 'Todos os vídeos já estão transcritos.'
    );
  } catch (e) {
    useAlert(
      (e.response && e.response.data && e.response.data.error) ||
        'Não consegui enfileirar as transcrições.'
    );
  } finally {
    isTranscribing.value = false;
  }
};
const videoAssets = computed(
  () => (assets.value && assets.value.video) || null
);
const transcribeOne = async row => {
  try {
    const { data: res } = await CevicoCreativesAPI.transcribeVideo(row.ad_id);
    row.transcript = res.transcript;
    useAlert('Vídeo na fila de transcrição — volte em alguns minutos.');
  } catch (e) {
    useAlert(
      (e.response && e.response.data && e.response.data.error) ||
        'Não consegui pedir a transcrição.'
    );
  }
};
const isAssetsLoading = ref(false);
const history = ref(null);
const isHistoryLoading = ref(false);
const compareMode = ref(false);
const selectedIds = ref([]);
const showCompare = ref(false);
const detailAdId = ref(null);
const isSyncing = ref(false);
const needsPolling = ref(false);
const targetForm = ref({});
const targetMode = ref('manual');
const targetStep = ref('3');
const isSavingTargets = ref(false);
let pollTimer = null;
let searchTimer = null;
const liveSync = ref(null); // estado da carga enquanto roda (progresso por janela)
const liveStorage = ref(null);
const showAllMonths = ref(false);

const pal = useCevicoPalette({
  scope: 'report:criativos',
  blocks: [
    { id: 'kpis', label: 'Números do período', icon: 'i-lucide-gauge' },
    { id: 'campanhas', label: 'Campanhas', icon: 'i-lucide-megaphone' },
    {
      id: 'criativos',
      label: 'Criativo por criativo',
      icon: 'i-lucide-clapperboard',
    },
    { id: 'ativos', label: 'Ganchos, corpos e CTAs', icon: 'i-lucide-shuffle' },
    { id: 'historico', label: 'Recordes e histórico', icon: 'i-lucide-trophy' },
    { id: 'ritmo', label: 'Ritmo da conta', icon: 'i-lucide-activity' },
    {
      id: 'fatia',
      label: 'Onde está o investimento',
      icon: 'i-lucide-chart-pie',
    },
    {
      id: 'formulas',
      label: 'Parâmetros e dados',
      icon: 'i-lucide-sliders-horizontal',
    },
    { id: 'dados', label: 'Nossos dados', icon: 'i-lucide-database' },
  ],
});
const { cvVars, blockVars, blockFamily, blockAltFamily, blockAltInk } = pal;
const hex = (block, i) => hexFromGrad(blockFamily(block)[i] || '') || '#0F5FA6';

const periodParams = computed(() => ({
  preset: period.value.preset,
  ...(period.value.preset === 'custom'
    ? { from: period.value.from, to: period.value.to }
    : {}),
}));

const load = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const params = { ...periodParams.value };
    Object.entries(filters.value).forEach(([k, v]) => {
      if (v) params[k] = v;
    });
    const { data: response } = await CevicoCreativesAPI.list(params);
    data.value = response;
    needsPolling.value = !!(response.sync && response.sync.running);
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

// ── atualizar dados (fila + trava no servidor; aqui só acompanha) ─────────
const stopPolling = () => {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = null;
  isSyncing.value = false;
};
const startPolling = () => {
  if (pollTimer) return;
  isSyncing.value = true;
  pollTimer = setInterval(async () => {
    try {
      const { data: status } = await CevicoCreativesAPI.syncStatus();
      liveSync.value = status.sync || null;
      if (status.storage) liveStorage.value = status.storage;
      if (!status.sync || !status.sync.running) {
        stopPolling();
        liveSync.value = null;
        await load();
        assets.value = null;
        history.value = null;
        const sync = status.sync || {};
        let msg = 'Dados dos criativos atualizados.';
        if (sync.last_error)
          msg = `A Meta respondeu com erro: ${sync.last_error}`;
        else if (sync.last_warning)
          msg = `Dados atualizados, mas ${sync.last_warning}`;
        useAlert(msg);
      }
    } catch {
      stopPolling();
    }
  }, 4000);
};
watch(needsPolling, v => {
  if (v) {
    needsPolling.value = false;
    startPolling();
  }
});
// carga COMPLETA: até 37 meses em janelas de 90 dias, em segundo plano
const runHistory = async () => {
  const max =
    (data.value && data.value.storage && data.value.storage.max_days) || 1125;
  // eslint-disable-next-line no-alert
  const ok = window.confirm(
    `Carregar o histórico completo da Meta (até ${Math.round(max / 30)} meses)? Roda em segundo plano, em janelas de 90 dias, e pode levar alguns minutos. O que já está guardado aqui não se perde.`
  );
  if (!ok) return;
  try {
    await CevicoCreativesAPI.loadHistory();
    useAlert('Carga completa iniciada. Acompanhe o progresso aqui em cima.');
    startPolling();
  } catch (e) {
    useAlert(
      (e.response && e.response.data && e.response.data.error) ||
        'Não consegui iniciar a carga completa.'
    );
  }
};

// CSV do que é NOSSO (período escolhido ou tudo)
const isExporting = ref(false);
const downloadCsv = async all => {
  isExporting.value = true;
  try {
    const params = { ...periodParams.value, ...(all ? { all: 1 } : {}) };
    const { data: blob } = await CevicoCreativesAPI.exportCsv(params);
    const url = URL.createObjectURL(new Blob([blob], { type: 'text/csv' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = `cevico-criativos-${all ? 'tudo' : 'periodo'}-${new Date().toISOString().slice(0, 10)}.csv`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  } catch {
    useAlert('Não consegui gerar o CSV agora.');
  } finally {
    isExporting.value = false;
  }
};

const runSync = async () => {
  try {
    const firstTime = !(
      data.value &&
      data.value.sync &&
      data.value.sync.synced_at
    );
    await CevicoCreativesAPI.sync({ days: firstTime ? 90 : 30 });
    useAlert(
      firstTime
        ? 'Primeira carga: puxando 90 dias da Meta (pode levar 1 a 2 min).'
        : 'Atualizando os últimos 30 dias na Meta…'
    );
    startPolling();
  } catch (e) {
    useAlert(
      (e.response && e.response.data && e.response.data.error) ||
        'Não consegui pedir a atualização.'
    );
  }
};

const loadAssets = async () => {
  isAssetsLoading.value = true;
  try {
    const { data: response } = await CevicoCreativesAPI.assets(
      periodParams.value
    );
    assets.value = response;
  } catch {
    assets.value = { error: true };
  } finally {
    isAssetsLoading.value = false;
  }
};
const loadHistory = async () => {
  isHistoryLoading.value = true;
  try {
    const { data: response } = await CevicoCreativesAPI.history({ months: 12 });
    history.value = response;
  } catch {
    history.value = { error: true };
  } finally {
    isHistoryLoading.value = false;
  }
};

onMounted(load);
onBeforeUnmount(() => {
  stopPolling();
  if (searchTimer) clearTimeout(searchTimer);
});
watch(
  period,
  () => {
    assets.value = null;
    load();
  },
  { deep: true }
);
watch(
  () => [
    filters.value.campaign_id,
    filters.value.fmt,
    filters.value.status,
    filters.value.sort,
  ],
  load
);
watch(
  () => filters.value.q,
  () => {
    if (searchTimer) clearTimeout(searchTimer);
    searchTimer = setTimeout(load, 350);
  }
);
watch(tab, t => {
  if (t === 'ativos' && !assets.value) loadAssets();
  if (t === 'historico' && !history.value) loadHistory();
});

// ── derivados ─────────────────────────────────────────────────────────────
const rows = computed(() => (data.value && data.value.rows) || []);
const totals = computed(() => (data.value && data.value.totals) || {});
const averages = computed(() => (data.value && data.value.averages) || {});
const targets = computed(() => (data.value && data.value.targets) || {});
const prevTotals = computed(
  () => (data.value && data.value.prev_totals) || null
);
const campaignStats = computed(
  () => (data.value && data.value.campaign_stats) || []
);
const selectedCampaign = computed(
  () =>
    campaignStats.value.find(c => c.id === filters.value.campaign_id) || null
);
const selectCampaign = id => {
  filters.value.campaign_id = id === filters.value.campaign_id ? '' : id;
};
const configured = computed(() => data.value && data.value.configured);
const syncState = computed(
  () => liveSync.value || (data.value && data.value.sync) || {}
);
const storage = computed(
  () => liveStorage.value || (data.value && data.value.storage) || null
);
const syncProgress = computed(() => syncState.value.progress || null);
const syncingText = computed(() => {
  const p = syncProgress.value;
  if (!p || !p.total) return 'atualizando…';
  return `carregando histórico: janela ${Math.min(p.done + 1, p.total)} de ${p.total}`;
});
const syncPct = computed(() => {
  const p = syncProgress.value;
  return p && p.total ? Math.round((p.done / p.total) * 100) : 0;
});
const hasData = computed(() => rows.value.length > 0);
const neverSynced = computed(
  () =>
    configured.value && !syncState.value.synced_at && !syncState.value.running
);

const syncedText = computed(() => {
  const at = syncState.value.synced_at;
  if (!at) return 'sem carga ainda';
  const diff = (Date.now() - new Date(at).getTime()) / 60000;
  if (diff < 60) return `atualizado há ${Math.max(1, Math.round(diff))} min`;
  if (diff < 48 * 60) return `atualizado há ${Math.round(diff / 60)} h`;
  return `atualizado em ${new Date(at).toLocaleDateString('pt-BR')}`;
});
const dataSinceText = computed(() =>
  data.value && data.value.data_since
    ? `dados desde ${new Date(`${data.value.data_since}T12:00:00`).toLocaleDateString('pt-BR')}`
    : ''
);
const periodText = computed(() =>
  data.value && data.value.period_days
    ? `${data.value.period_days} dia(s) · comparado com os ${data.value.period_days} anteriores`
    : ''
);

// setas contra o período anterior nos KPIs
const prevOf = key => (prevTotals.value ? prevTotals.value[key] : null);
const deltaSub = (current, key, base) => {
  const d = delta(current, prevOf(key));
  return d === null ? base : `${fmtDelta(d)} vs período anterior · ${base}`;
};

const FORMAT_OPTIONS = [
  { key: '', label: 'Todos' },
  { key: 'video', label: 'Vídeo' },
  { key: 'image', label: 'Imagem' },
  { key: 'dynamic', label: 'Dinâmico' },
  { key: 'carousel', label: 'Carrossel' },
];
const SORT_OPTIONS = [
  { key: 'spend', label: 'Investimento' },
  { key: 'hook', label: 'Taxa de parada' },
  { key: 'hold', label: 'Retenção' },
  { key: 'ctr', label: 'CTR de link' },
  { key: 'conversations', label: 'Conversas' },
  { key: 'cost', label: 'Menor custo por conversa' },
  { key: 'leads', label: 'Leads no CRM' },
  { key: 'surgeries', label: 'Cirurgias' },
];
const formatCount = key => {
  const counts = (data.value && data.value.formats) || {};
  return key
    ? counts[key] || 0
    : Object.values(counts).reduce((a, b) => a + b, 0);
};

// ritmo da conta: série do período + o mesmo dia no período anterior
const dailyLabels = computed(() =>
  ((data.value && data.value.daily) || []).map(d => d.label)
);
const dailySpend = computed(() =>
  ((data.value && data.value.daily) || []).map(d => d.spend)
);
const dailyConv = computed(() =>
  ((data.value && data.value.daily) || []).map(d => d.conversations)
);
const dailyCtr = computed(() =>
  ((data.value && data.value.daily) || []).map(d =>
    Number(((d.link_ctr || 0) * 100).toFixed(2))
  )
);
const prevSeries = key =>
  ((data.value && data.value.prev_daily) || []).map(d => d[key]);
const prevCtr = computed(() =>
  prevSeries('link_ctr').map(v => Number(((v || 0) * 100).toFixed(2)))
);
const avgCtrPct = computed(() =>
  averages.value.link_ctr
    ? Number((averages.value.link_ctr * 100).toFixed(2))
    : null
);
const readSeries = (values, fmt) => {
  const pairs = values
    .map((v, i) => ({ v, l: dailyLabels.value[i] }))
    .filter(p => Number.isFinite(p.v));
  if (!pairs.length) return '';
  const avg = pairs.reduce((a, p) => a + p.v, 0) / pairs.length;
  const sorted = [...pairs].sort((a, b) => b.v - a.v);
  const best = sorted[0];
  const worst = sorted[sorted.length - 1];
  return `média ${fmt(avg)} · melhor dia ${best.l} (${fmt(best.v)}) · pior dia ${worst.l} (${fmt(worst.v)})`;
};
const pctFmt = v => `${Number(v).toFixed(2).replace('.', ',')}%`;

const sliceBy = keyFn => {
  const acc = {};
  rows.value.forEach(r => {
    const k = keyFn(r) || 'sem nome';
    acc[k] = (acc[k] || 0) + Number(r.totals.spend || 0);
  });
  return Object.entries(acc)
    .map(([label, value]) => ({ label, value }))
    .sort((a, b) => b.value - a.value);
};
const spendByFormat = computed(() => sliceBy(r => r.format_label));
const spendByCampaign = computed(() => sliceBy(r => r.campaign_name));

const champion = computed(
  () => rows.value.find(r => (r.champion_of || []).includes('cost')) || null
);
const bandCounts = computed(() => {
  const c = { bom: 0, atencao: 0, ruim: 0 };
  rows.value.forEach(r => {
    const bands = Object.values(
      (r.diagnosis && r.diagnosis.bands) || {}
    ).filter(Boolean);
    if (!bands.length) return;
    if (bands.includes('ruim')) c.ruim += 1;
    else if (bands.includes('atencao')) c.atencao += 1;
    else c.bom += 1;
  });
  return c;
});

// ── comparar ──────────────────────────────────────────────────────────────
const toggleCompare = row => {
  const i = selectedIds.value.indexOf(row.ad_id);
  if (i >= 0) selectedIds.value.splice(i, 1);
  else if (selectedIds.value.length < 4) selectedIds.value.push(row.ad_id);
  else useAlert('Compare até 4 criativos de cada vez.');
};
const compareRows = computed(() =>
  rows.value.filter(r => selectedIds.value.includes(r.ad_id))
);
const leaveCompare = () => {
  compareMode.value = false;
  selectedIds.value = [];
  showCompare.value = false;
};

// ── parâmetros: manual × automático pelo nosso histórico ─────────────────
const toDisplay = (def, v) => {
  if (v === null || v === undefined) return '';
  return def.money
    ? Number(v).toFixed(2)
    : (Number(v) * 100).toFixed(def.digits || 1);
};
const fromDisplay = (def, v) => {
  if (v === '' || v === null || v === undefined) return null;
  const n = Number(String(v).replace(',', '.'));
  return def.money ? n : n / 100;
};
const fillTargetForm = () => {
  targetMode.value = targets.value.mode === 'auto' ? 'auto' : 'manual';
  targetStep.value = String(((targets.value.step || 0.03) * 100).toFixed(0));
  const f = {};
  METRIC_DEFS.forEach(def => {
    const t = targets.value[def.key] || {};
    f[def.key] = { bad: toDisplay(def, t.bad), good: toDisplay(def, t.good) };
  });
  targetForm.value = f;
};
watch(targets, fillTargetForm, { immediate: true });
const isAuto = computed(() => targetMode.value === 'auto');
const saveTargets = async () => {
  isSavingTargets.value = true;
  try {
    const payload = {
      mode: targetMode.value,
      step: Number(String(targetStep.value).replace(',', '.')) / 100,
    };
    if (!isAuto.value) {
      METRIC_DEFS.forEach(def => {
        payload[def.key] = {
          bad: fromDisplay(def, targetForm.value[def.key].bad),
          good: fromDisplay(def, targetForm.value[def.key].good),
        };
      });
    }
    await CrmAPI.updateMetaAds({ creative_targets: payload });
    useAlert('Parâmetros salvos. As leituras foram recalculadas.');
    await load();
  } catch (e) {
    useAlert(
      (e.response && e.response.data && e.response.data.error) ||
        'Não consegui salvar os parâmetros.'
    );
  } finally {
    isSavingTargets.value = false;
  }
};
const fmtTarget = (def, v) => {
  if (v === null || v === undefined) return '—';
  return def.money ? fmtMoney(v) : fmtPct(v, def.digits);
};
const targetText = def => {
  const t = targets.value[def.key];
  if (!t) return '';
  return t.lower_is_better
    ? `bom até ${fmtTarget(def, t.good)} · atenção até ${fmtTarget(def, t.bad)} · ruim acima disso`
    : `bom a partir de ${fmtTarget(def, t.good)} · atenção a partir de ${fmtTarget(def, t.bad)} · ruim abaixo disso`;
};

// ── recordes e histórico ──────────────────────────────────────────────────
const recordFor = key =>
  (history.value && history.value.records && history.value.records[key]) ||
  null;
const superChip = (cur, prev, lower) => {
  const d = delta(cur, prev);
  if (d === null) return { text: 'sem base', cls: 'text-n-slate-9' };
  return { text: fmtDelta(d), cls: deltaCls(d, lower) };
};
const recordBand = (def, rec) => {
  if (
    !rec ||
    !rec.best_week ||
    rec.current.week === null ||
    rec.current.week === undefined
  )
    return null;
  const v = rec.current.week;
  if (def.money) {
    if (v <= rec.best_week.value) return 'bom';
    return rec.median_week && v <= rec.median_week ? 'atencao' : 'ruim';
  }
  if (v >= rec.best_week.value) return 'bom';
  return rec.median_week && v >= rec.median_week ? 'atencao' : 'ruim';
};
// v2 (item 177): campeões de dinheiro (ROAS, custo por cirurgia, % agendamento) primeiro
const PART_KEYS = [
  'roas',
  'cac',
  'booking',
  'cost',
  'hook',
  'hold',
  'cta',
  'conv',
];
const MONTH_PARTS = ['roas', 'cac', 'hook', 'hold', 'cta', 'cost'];
const ASSET_KINDS = ['title', 'body', 'call_to_action'];
const ASSET_META = {
  title: { label: 'Gancho campeão', icon: 'i-lucide-anchor' },
  body: { label: 'Corpo campeão', icon: 'i-lucide-film' },
  call_to_action: {
    label: 'CTA campeão',
    icon: 'i-lucide-mouse-pointer-click',
  },
};
const monthRows = computed(() =>
  ((history.value && history.value.months) || []).slice().reverse()
);
// com 3 anos de histórico a lista fica longa: 12 meses à vista, o resto dobrado
const visibleMonthRows = computed(() =>
  showAllMonths.value ? monthRows.value : monthRows.value.slice(0, 12)
);
const assetMonths = computed(() =>
  ((history.value && history.value.assets_months) || []).filter(
    m => m.title || m.body || m.call_to_action
  )
);
const allTime = part =>
  (history.value && history.value.all_time && history.value.all_time[part]) ||
  null;
const allTimeRows = computed(() => PART_KEYS.map(allTime).filter(Boolean));

const FORMULAS = [
  {
    label: 'Taxa de parada (gancho)',
    text: 'plays de 3 segundos ÷ impressões. Só vídeo. Diz se o começo segura o dedo.',
  },
  {
    label: 'Retenção (corpo)',
    text: 'ThruPlay (15 s ou o vídeo inteiro) ÷ plays de 3 s. A curva mostra quem chegou a 25, 50, 75 e 100 %.',
  },
  { label: 'CTR de link (CTA)', text: 'cliques no link ÷ impressões.' },
  {
    label: 'Conversa por clique',
    text: 'conversas iniciadas no WhatsApp (dado da Meta, janela de 7 dias) ÷ cliques no link.',
  },
  { label: 'Custo por conversa', text: 'investimento ÷ conversas iniciadas.' },
  {
    label: 'Bom / atenção / ruim',
    text: 'comparação com os parâmetros da tabela acima. O triângulo na régua marca a média da conta no período, ponderada por impressões.',
  },
  {
    label: 'Automático pelo histórico',
    text: 'bom = nossa melhor semana (calendário, com pelo menos 4 dias e 1.500 impressões) mais o passo de superação; ruim = abaixo da nossa mediana semanal. Recalculado a cada carga.',
  },
  {
    label: 'Campeões',
    text: 'no recorte: menor custo por conversa (mínimo 5 conversas), melhor parada, retenção, CTR e conversa por clique (mínimo 500 impressões). No histórico: o mesmo, mês a mês e desde o início.',
  },
  {
    label: 'Variação vs período anterior',
    text: 'o mesmo criativo no período imediatamente anterior, de igual tamanho. Verde melhorou, vermelho piorou.',
  },
  {
    label: 'Teia (radar)',
    text: 'força de cada parte de 0 a 100. Com parâmetro (gancho, corpo, CTA, conversa, custo): 50 = na linha do ruim, 100 = atingiu o bom. Sem parâmetro (leads, fim do vídeo, conversas, fatia): contra o melhor do recorte. Frequência: 1 = 100, 3 = 0. As chavinhas escolhem os eixos de cada ambiente (mínimo 3) e ficam guardadas no seu navegador.',
  },
  {
    label: 'Fadiga',
    text: 'o anúncio segue entregando, mas o CTR da 2ª metade do período caiu para 75 % ou menos do CTR da 1ª metade (período de 14 dias ou mais).',
  },
  {
    label: 'Leads → consultas → cirurgias',
    text: 'contatos que chegaram clicando NESTE anúncio (dado da Meta na 1ª mensagem), consulta marcada/realizada na Agenda e cartão que chegou na etapa de cirurgia.',
  },
  {
    label: 'Atualização',
    text: 'toda madrugada o sistema refaz os últimos 3 dias (a Meta reprocessa). "Atualizar dados" refaz 30 dias; a primeira carga traz 90; "Carregar histórico completo" (aba Parâmetros e dados) traz até 37 meses, em janelas de 90 dias. Tudo fica guardado no nosso banco.',
  },
];

const goToIntegrations = () => router.push({ name: 'crm_integrations' });
</script>

<template>
  <div
    class="cv-page cv-page-sheer flex flex-col h-full overflow-y-auto bg-n-surface-1"
    :style="cvVars"
  >
    <div class="max-w-7xl mx-auto w-full p-4 sm:p-6 pb-24">
      <CevicoHero
        :pal="pal"
        title="Central de Criativos"
        subtitle="Gancho, corpo e CTA de cada anúncio, com os números da própria Meta, parâmetros claros de bom e ruim e o que virou consulta e cirurgia no CRM."
        icon="i-lucide-clapperboard"
      >
        <template #chips>
          <span v-if="dataSinceText" class="cevico-hero-chip">{{
            dataSinceText
          }}</span>
          <span class="cevico-hero-chip">{{
            isSyncing ? syncingText : syncedText
          }}</span>
          <span v-if="data && data.simulated" class="cevico-hero-chip"
            >simulação</span
          >
          <span v-if="selectedCampaign" class="cevico-hero-chip"
            ><span class="i-lucide-megaphone text-xs" />Analisando:
            {{ selectedCampaign.name }}</span
          >
          <span v-if="targets.mode === 'auto'" class="cevico-hero-chip"
            ><span class="i-lucide-trending-up text-xs" />régua automática pelo
            nosso histórico</span
          >
        </template>
        <template #actions>
          <button
            class="cevico-hero-btn"
            :disabled="isSyncing || !configured"
            @click="runSync"
          >
            <span
              :class="
                isSyncing
                  ? 'i-lucide-loader-circle animate-spin'
                  : 'i-lucide-refresh-cw'
              "
              class="text-sm"
            />
            {{
              isSyncing
                ? syncProgress
                  ? `Carregando ${syncPct}%`
                  : 'Atualizando'
                : 'Atualizar dados'
            }}
          </button>
        </template>
      </CevicoHero>

      <SkeletonScreen v-if="isLoading && !data" variant="dashboard" />

      <div
        v-else-if="hasError"
        class="cv-block cv-strip cv-red flex items-center gap-3 px-4 py-3.5 text-sm text-n-slate-11"
      >
        <span class="i-lucide-alert-triangle" />Não consegui carregar a Central
        de Criativos.
        <button class="cv-btn cv-btn-sm ml-auto" @click="load">
          Tentar de novo
        </button>
      </div>

      <template v-else-if="data">
        <div
          v-if="!configured"
          class="cv-block cv-strip cv-amber flex items-start gap-3 px-4 py-3.5 mb-6 text-sm text-n-slate-11"
        >
          <span class="i-lucide-plug text-base mt-0.5" />
          <div>
            <p class="font-semibold text-n-slate-12">
              Meta Ads ainda não conectado
            </p>
            <p>
              Informe o token e a conta de anúncios em Integrações → Meta Ads. A
              Central usa a mesma conexão do relatório de anúncios.
            </p>
          </div>
          <button class="cv-btn cv-btn-sm ml-auto" @click="goToIntegrations">
            Abrir Integrações
          </button>
        </div>

        <div
          v-else-if="neverSynced && !hasData"
          class="cv-block p-10 mb-10 text-center"
        >
          <span class="cv-icon cv-icon-xl mx-auto mb-3"
            ><span class="i-lucide-download text-2xl"
          /></span>
          <p class="text-sm font-bold text-n-slate-12">
            Primeira carga dos criativos
          </p>
          <p class="text-xs text-n-slate-10 max-w-md mx-auto mt-1 mb-4">
            Vou buscar na Meta os anúncios da conta com o criativo de cada um e
            as métricas dos últimos 90 dias, dia a dia. Depois disso o sistema
            atualiza sozinho toda madrugada.
          </p>
          <button class="cv-btn" :disabled="isSyncing" @click="runSync">
            <span class="i-lucide-refresh-cw text-sm" />Buscar agora
          </button>
        </div>

        <template v-else>
          <!-- 📊 números do período -->
          <div class="cv-block p-6 sm:p-9 mb-10" :style="blockVars('kpis')">
            <div class="flex items-center gap-2 mb-4 flex-wrap">
              <span class="cv-icon"
                ><span class="i-lucide-gauge text-base"
              /></span>
              <h2
                class="text-xl sm:text-2xl font-bold text-n-slate-12 tracking-tight leading-tight"
              >
                Números do período<span
                  v-if="selectedCampaign"
                  class="font-normal text-n-slate-10"
                >
                  · {{ selectedCampaign.name }}</span
                >
              </h2>
              <span class="text-[11px] text-n-slate-9 ml-auto"
                >{{ totals.ads || 0 }} criativo(s) ·
                {{ fmtCompact(totals.impressions) }} impressões<span
                  v-if="periodText"
                >
                  · {{ periodText }}</span
                ></span
              >
            </div>
            <div class="grid grid-cols-2 lg:grid-cols-4 gap-5">
              <DashKpi
                compact
                glass
                label="Investimento"
                :value="fmtMoney(totals.spend)"
                :sub="deltaSub(totals.spend, 'spend', 'o que saiu (Meta)')"
                :grad="blockFamily('kpis')[0]"
              />
              <DashKpi
                compact
                glass
                label="Taxa de parada"
                :value="fmtPct(averages.hook_rate)"
                :sub="
                  deltaSub(
                    averages.hook_rate,
                    'hook_rate',
                    'gancho · média dos vídeos'
                  )
                "
                :grad="blockAltFamily('kpis')[1]"
                :ink="blockAltInk('kpis')"
              />
              <DashKpi
                compact
                glass
                label="Retenção"
                :value="fmtPct(averages.hold_rate)"
                :sub="
                  deltaSub(
                    averages.hold_rate,
                    'hold_rate',
                    'corpo · ThruPlay ÷ 3 s'
                  )
                "
                :grad="blockAltFamily('kpis')[2]"
                :ink="blockAltInk('kpis')"
              />
              <DashKpi
                compact
                glass
                label="CTR de link"
                :value="fmtPct(averages.link_ctr, 2)"
                :sub="
                  deltaSub(
                    averages.link_ctr,
                    'link_ctr',
                    'CTA · cliques ÷ impressões'
                  )
                "
                :grad="blockFamily('kpis')[3]"
              />
              <DashKpi
                compact
                glass
                label="Conversas iniciadas"
                :value="fmtNum(totals.conversations)"
                :sub="
                  deltaSub(
                    totals.conversations,
                    'conversations',
                    'WhatsApp (dado da Meta)'
                  )
                "
                :grad="blockFamily('kpis')[1]"
              />
              <DashKpi
                compact
                glass
                label="Custo por conversa"
                :value="
                  averages.cost_conversation
                    ? fmtMoney(averages.cost_conversation)
                    : '—'
                "
                :sub="
                  deltaSub(
                    averages.cost_conversation,
                    'cost_conversation',
                    'investimento ÷ conversas'
                  )
                "
                :grad="blockAltFamily('kpis')[2]"
                :ink="blockAltInk('kpis')"
              />
              <DashKpi
                compact
                glass
                label="Leads no CRM"
                :value="fmtNum(totals.leads)"
                :sub="`${fmtNum(totals.booked)} marcaram consulta`"
                :grad="blockAltFamily('kpis')[0]"
                :ink="blockAltInk('kpis')"
              />
              <DashKpi
                compact
                glass
                label="Cirurgias"
                :value="fmtNum(totals.surgeries)"
                :sub="
                  totals.revenue
                    ? fmtMoney(totals.revenue)
                    : 'de leads destes anúncios'
                "
                :grad="blockFamily('kpis')[3]"
              />
            </div>
            <div
              class="flex items-center gap-x-4 gap-y-1 mt-3 text-xs text-n-slate-11 flex-wrap"
            >
              <span
                class="inline-flex items-center gap-1 font-semibold text-emerald-700 dark:text-emerald-400"
                ><span class="i-lucide-circle-check" />{{ bandCounts.bom }} no
                verde</span
              >
              <span
                class="inline-flex items-center gap-1 font-semibold text-amber-700 dark:text-amber-400"
                ><span class="i-lucide-triangle-alert" />{{
                  bandCounts.atencao
                }}
                em atenção</span
              >
              <span
                class="inline-flex items-center gap-1 font-semibold text-red-700 dark:text-red-400"
                ><span class="i-lucide-circle-x" />{{ bandCounts.ruim }} com
                parâmetro no vermelho</span
              >
              <span
                v-if="champion"
                class="inline-flex items-center gap-1.5 flex-wrap"
              >
                <span class="cv-champion-badge"
                  ><span class="i-lucide-trophy" />Campeão</span
                >
                <b class="text-n-slate-12">{{ champion.ad_name }}</b> ·
                {{ fmtMoney(champion.rates.cost_conversation) }} por conversa
                <button
                  class="cv-btn cv-btn-sm cv-btn-ghost"
                  @click="detailAdId = champion.ad_id"
                >
                  ver
                </button>
              </span>
            </div>
          </div>

          <!-- 📣 campanhas: escolha o que analisar -->
          <div
            class="cv-block p-6 sm:p-9 mb-10"
            :style="blockVars('campanhas')"
          >
            <div class="flex items-center gap-2 mb-3 flex-wrap">
              <span class="cv-icon"
                ><span class="i-lucide-megaphone text-base"
              /></span>
              <h2
                class="text-xl sm:text-2xl font-bold text-n-slate-12 tracking-tight leading-tight"
              >
                Campanhas
              </h2>
              <span class="text-[11px] text-n-slate-9"
                >clique em uma para analisar só ela; tudo abaixo passa a olhar
                só para ela</span
              >
              <button
                v-if="selectedCampaign"
                class="cv-btn cv-btn-sm cv-btn-ghost ml-auto"
                @click="selectCampaign('')"
              >
                <span class="i-lucide-x text-sm" />Ver todas
              </button>
            </div>
            <div
              class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4 gap-3"
            >
              <button
                class="cv-choice p-3.5 pr-10 min-w-0"
                :class="{ 'cv-choice-on': !filters.campaign_id }"
                @click="selectCampaign('')"
              >
                <span class="cv-choice-mark"
                  ><span
                    :class="
                      !filters.campaign_id
                        ? 'i-lucide-check'
                        : 'i-lucide-chevron-right'
                    "
                /></span>
                <p class="text-sm font-bold text-n-slate-12">
                  Todas as campanhas
                </p>
                <p class="text-[11px] text-n-slate-9 mt-0.5">
                  {{ campaignStats.reduce((a, c) => a + c.ads, 0) }} criativo(s)
                  com investimento no período
                </p>
                <p class="text-[11px] text-n-slate-10 mt-1.5">
                  {{
                    fmtMoney(
                      campaignStats.reduce(
                        (a, c) => a + Number(c.spend || 0),
                        0
                      )
                    )
                  }}
                  ·
                  {{
                    fmtNum(
                      campaignStats.reduce((a, c) => a + c.conversations, 0)
                    )
                  }}
                  conversas
                </p>
              </button>
              <button
                v-for="c in campaignStats"
                :key="c.id || 'sem'"
                class="cv-choice p-3.5 pr-10 min-w-0"
                :class="{ 'cv-choice-on': filters.campaign_id === c.id }"
                @click="selectCampaign(c.id)"
              >
                <span class="cv-choice-mark"
                  ><span
                    :class="
                      filters.campaign_id === c.id
                        ? 'i-lucide-check'
                        : 'i-lucide-chevron-right'
                    "
                /></span>
                <p class="text-sm font-bold text-n-slate-12 leading-snug">
                  {{ c.name }}
                </p>
                <p class="text-[11px] text-n-slate-9 mt-0.5">
                  {{ c.ads }} criativo(s) · {{ fmtMoney(c.spend) }} investidos
                </p>
                <div
                  class="flex items-baseline gap-x-4 gap-y-0 mt-1.5 flex-wrap"
                >
                  <span
                    ><span
                      class="text-base font-bold text-n-slate-12 tabular-nums"
                      >{{ fmtNum(c.conversations) }}</span
                    >
                    <span class="text-[10px] text-n-slate-9"
                      >conversas</span
                    ></span
                  >
                  <span
                    ><span
                      class="text-base font-bold text-n-slate-12 tabular-nums"
                      >{{
                        c.cost_conversation
                          ? fmtMoney(c.cost_conversation)
                          : '—'
                      }}</span
                    >
                    <span class="text-[10px] text-n-slate-9"
                      >por conversa</span
                    ></span
                  >
                </div>
                <div
                  class="flex items-center gap-2 mt-1.5 text-[10px] font-semibold flex-wrap"
                >
                  <span
                    class="inline-flex items-center gap-0.5 text-emerald-700 dark:text-emerald-400"
                    ><span class="i-lucide-circle-check" />{{ c.bands.bom }} no
                    verde</span
                  >
                  <span
                    class="inline-flex items-center gap-0.5 text-amber-700 dark:text-amber-400"
                    ><span class="i-lucide-triangle-alert" />{{
                      c.bands.atencao
                    }}
                    atenção</span
                  >
                  <span
                    class="inline-flex items-center gap-0.5 text-red-700 dark:text-red-400"
                    ><span class="i-lucide-circle-x" />{{
                      c.bands.ruim
                    }}
                    vermelho</span
                  >
                  <span
                    v-if="c.leads"
                    class="ml-auto text-n-slate-9 font-normal"
                    >{{ c.leads }} leads · {{ c.surgeries }} cirurgias</span
                  >
                </div>
              </button>
            </div>
          </div>

          <!-- abas + período: o que analisar e em que recorte -->
          <div class="cv-seg mb-3 flex-wrap">
            <button
              class="cv-seg-item"
              :class="{ 'cv-seg-on': tab === 'criativos' }"
              @click="tab = 'criativos'"
            >
              <span class="i-lucide-clapperboard cv-seg-icon" />Criativos
            </button>
            <button
              class="cv-seg-item"
              :class="{ 'cv-seg-on': tab === 'ativos' }"
              @click="tab = 'ativos'"
            >
              <span class="i-lucide-shuffle cv-seg-icon" />Ganchos, corpos e
              CTAs
            </button>
            <button
              class="cv-seg-item"
              :class="{ 'cv-seg-on': tab === 'historico' }"
              @click="tab = 'historico'"
            >
              <span class="i-lucide-trophy cv-seg-icon" />Recordes e histórico
            </button>
            <button
              class="cv-seg-item"
              :class="{ 'cv-seg-on': tab === 'conta' }"
              @click="tab = 'conta'"
            >
              <span class="i-lucide-activity cv-seg-icon" />Ritmo da conta
            </button>
            <button
              class="cv-seg-item"
              :class="{ 'cv-seg-on': tab === 'formulas' }"
              @click="tab = 'formulas'"
            >
              <span class="i-lucide-sliders-horizontal cv-seg-icon" />Parâmetros
              e dados
            </button>
          </div>
          <PeriodRuler v-model="period" glass class="mb-4" />

          <!-- 🎬 criativo por criativo -->
          <div
            v-if="tab === 'criativos'"
            class="cv-block cv-block-sheer p-6 sm:p-9 mb-10"
            :style="blockVars('criativos')"
          >
            <div class="flex items-center gap-2 mb-2 flex-wrap">
              <span class="cv-icon"
                ><span class="i-lucide-clapperboard text-base"
              /></span>
              <h2
                class="text-xl sm:text-2xl font-bold text-n-slate-12 tracking-tight leading-tight"
              >
                Criativo por criativo
              </h2>
              <span class="cv-seg cv-seg-sm ml-auto">
                <button
                  class="cv-seg-item"
                  :class="{ 'cv-seg-on': view === 'fichas' }"
                  @click="setView('fichas')"
                >
                  <span class="i-lucide-id-card cv-seg-icon" />Fichas completas
                </button>
                <button
                  class="cv-seg-item"
                  :class="{ 'cv-seg-on': view === 'tabela' }"
                  @click="setView('tabela')"
                >
                  <span class="i-lucide-table cv-seg-icon" />Tabela
                </button>
              </span>
            </div>
            <!-- filtros do recorte: formato, status, ordem, busca, comparar -->
            <div class="flex items-center gap-2 flex-wrap mb-3">
              <div class="cv-seg cv-seg-sm">
                <button
                  v-for="f in FORMAT_OPTIONS"
                  :key="f.key"
                  class="cv-seg-item"
                  :class="{ 'cv-seg-on': filters.fmt === f.key }"
                  @click="filters.fmt = f.key"
                >
                  {{ f.label }}
                  <span class="text-[10px] opacity-70">{{
                    formatCount(f.key)
                  }}</span>
                </button>
              </div>
              <select v-model="filters.status" class="cv-input text-xs !w-auto">
                <option value="">Com investimento no período</option>
                <option value="active">Só no ar</option>
                <option value="all">Todos os anúncios</option>
              </select>
              <select v-model="filters.sort" class="cv-input text-xs !w-auto">
                <option v-for="s in SORT_OPTIONS" :key="s.key" :value="s.key">
                  Ordenar: {{ s.label }}
                </option>
              </select>
              <input
                v-model="filters.q"
                type="search"
                placeholder="Buscar gancho, texto ou nome…"
                class="cv-input text-xs !w-auto min-w-[12rem] flex-1"
              />
              <button
                class="cv-btn cv-btn-sm ml-auto"
                :class="{ 'cv-btn-ghost': !compareMode }"
                @click="compareMode ? leaveCompare() : (compareMode = true)"
              >
                <span class="i-lucide-columns-3 text-sm" />{{
                  compareMode ? 'Sair da comparação' : 'Comparar'
                }}
              </button>
            </div>
            <p class="text-[11px] text-n-slate-9 mb-4">
              Nas réguas: faixa vermelha = ruim, âmbar = atenção, verde = bom ·
              traço preto = parâmetro bom · triângulo = média da conta no
              período. Moldura dourada = campeão do recorte; Transcrever copia
              gancho, corpo e CTA. Teia = força de cada parte: 100 = atingiu o
              parâmetro bom, 50 = na linha do ruim.
            </p>
            <RadarAxesPicker env="criativos" class="mb-4" />
            <p v-if="!hasData" class="text-sm text-n-slate-10 py-6 text-center">
              Nenhum criativo com dados neste recorte. Mude o período, a
              campanha ou os filtros.
            </p>
            <CreativeTable
              v-else-if="view === 'tabela'"
              :rows="rows"
              :compare-mode="compareMode"
              :selected-ids="selectedIds"
              :targets="targets"
              :averages="averages"
              :peers="rows"
              :color="hex('criativos', 1)"
              @open="r => (detailAdId = r.ad_id)"
              @toggle="toggleCompare"
            />
            <div
              v-else
              class="grid grid-cols-1 lg:grid-cols-2 gap-5 items-start"
            >
              <CreativeCard
                v-for="r in rows"
                :key="r.ad_id"
                :row="r"
                :averages="averages"
                :targets="targets"
                :family="blockFamily('criativos')"
                :accent="hex('criativos', 1)"
                :compare-mode="compareMode"
                :selected="selectedIds.includes(r.ad_id)"
                :peers="rows"
                @open="detailAdId = r.ad_id"
                @toggle="toggleCompare"
                @transcribe-video="transcribeOne"
              />
            </div>
          </div>

          <!-- 🔀 ganchos, corpos e CTAs -->
          <div
            v-if="tab === 'ativos'"
            class="cv-block cv-block-sheer p-6 sm:p-9 mb-10"
            :style="blockVars('ativos')"
          >
            <div class="flex items-center gap-2 mb-1 flex-wrap">
              <span class="cv-icon"
                ><span class="i-lucide-shuffle text-base"
              /></span>
              <h2
                class="text-xl sm:text-2xl font-bold text-n-slate-12 tracking-tight leading-tight"
              >
                Ganchos, corpos e CTAs: quem ganha, peça por peça
              </h2>
            </div>
            <p class="text-xs text-n-slate-10 mb-3">
              No anúncio <b>dinâmico</b> a Meta combina títulos, textos e botões
              sozinha e entrega o resultado de cada peça. Aqui a conta inteira
              junta esses resultados no período escolhido. A peça campeã é a que
              mais gerou conversas; o custo por conversa desempata.
            </p>
            <div class="grid sm:grid-cols-3 gap-2 mb-5 text-[11px]">
              <div class="cv-sub rounded-xl px-3 py-2">
                <b class="text-n-slate-12"
                  ><span class="i-lucide-anchor text-xs" /> Gancho</b
                >
                <span class="text-n-slate-10"
                  >= o título. No criativo inteiro, a taxa de parada (3 s ÷
                  impressões) mede o gancho.</span
                >
              </div>
              <div class="cv-sub rounded-xl px-3 py-2">
                <b class="text-n-slate-12"
                  ><span class="i-lucide-film text-xs" /> Corpo</b
                >
                <span class="text-n-slate-10"
                  >= o texto principal. No criativo inteiro, a retenção
                  (ThruPlay ÷ 3 s) mede o corpo.</span
                >
              </div>
              <div class="cv-sub rounded-xl px-3 py-2">
                <b class="text-n-slate-12"
                  ><span class="i-lucide-mouse-pointer-click text-xs" /> CTA</b
                >
                <span class="text-n-slate-10"
                  >= o botão. No criativo inteiro, o CTR de link e a conversa
                  por clique medem o CTA.</span
                >
              </div>
            </div>
            <RadarAxesPicker env="pecas" scope="asset" class="mb-4" />
            <SkeletonScreen v-if="isAssetsLoading" variant="list" />
            <p
              v-else-if="assets && assets.error"
              class="text-sm text-n-slate-10"
            >
              Não consegui buscar as quebras por peça agora.
            </p>
            <template v-else-if="assets">
              <!-- 🎬 o que os vídeos falam (item 181) -->
              <div class="cv-sub rounded-3xl p-5 sm:p-7 mb-8">
                <div class="flex items-center gap-2 mb-1 flex-wrap">
                  <span class="cv-icon"
                    ><span class="i-lucide-clapperboard text-base"
                  /></span>
                  <h3
                    class="text-lg sm:text-xl font-bold text-n-slate-12 tracking-tight"
                  >
                    O que os vídeos falam
                  </h3>
                  <span v-if="videoAssets" class="cv-chip">
                    {{ videoAssets.transcribed }} de
                    {{ videoAssets.videos }} vídeo(s) transcrito(s)
                  </span>
                  <button
                    class="cv-btn cv-btn-sm ml-auto"
                    :disabled="isTranscribing"
                    title="Transcrever os vídeos que ainda não têm transcrição"
                    @click="transcribeVideos"
                  >
                    <span class="i-lucide-sparkles text-sm" />Transcrever vídeos
                  </button>
                </div>
                <p class="text-xs text-n-slate-10 mb-5">
                  Gancho, corpo e CTA aqui são a FALA do vídeo (transcrição por
                  IA), não o texto do anúncio — ranqueados pelo que cada parte
                  tem de provar.
                </p>
                <div v-if="videoAssets" class="space-y-7">
                  <VideoSpeechRanking
                    :rows="videoAssets.hooks"
                    title="Ganchos falados"
                    subtitle="os primeiros 3 segundos · ranqueados pela taxa de parada"
                    icon="i-lucide-anchor"
                    :color="hex('ativos', 0)"
                    metric-label="taxa de parada"
                    part="hook"
                  />
                  <VideoSpeechRanking
                    :rows="videoAssets.bodies"
                    title="Corpos falados"
                    subtitle="o desenvolvimento · ranqueados pela retenção"
                    icon="i-lucide-film"
                    :color="hex('ativos', 1)"
                    metric-label="retenção"
                    part="body"
                  />
                  <VideoSpeechRanking
                    :rows="videoAssets.ctas"
                    title="CTAs falados"
                    subtitle="o pedido final · ranqueados pela conversa por clique"
                    icon="i-lucide-mouse-pointer-click"
                    :color="hex('ativos', 2)"
                    metric-label="conversa por clique"
                    part="cta"
                  />
                </div>
              </div>
              <div
                v-if="!assets.dynamic_ads"
                class="cv-strip cv-amber px-4 py-3 text-xs text-n-slate-11 mb-4 flex gap-2 items-start"
              >
                <span class="i-lucide-lightbulb text-base flex-shrink-0" />
                <span
                  >Nenhum anúncio da conta usa criativo dinâmico. Para ver
                  ganchos, corpos e CTAs separados, crie o próximo anúncio no
                  Gerenciador com "Criativo dinâmico" ligado e 2 a 5 opções de
                  título, texto e botão. Enquanto isso, a aba Criativos compara
                  anúncio contra anúncio e a aba Recordes guarda os campeões de
                  cada parte.</span
                >
              </div>
              <div class="space-y-8">
                <AssetPodium
                  :rows="(assets.titles && assets.titles.rows) || []"
                  title="Ganchos (títulos)"
                  subtitle="a primeira frase que aparece"
                  icon="i-lucide-anchor"
                  :color="hex('ativos', 0)"
                  :targets="targets"
                  label-header="Gancho"
                  empty-text="sem ganchos separados no período"
                />
                <AssetPodium
                  :rows="(assets.bodies && assets.bodies.rows) || []"
                  title="Corpos (textos)"
                  subtitle="o texto principal do anúncio"
                  icon="i-lucide-film"
                  :color="hex('ativos', 1)"
                  :targets="targets"
                  label-header="Corpo"
                  empty-text="sem corpos separados no período"
                />
                <AssetPodium
                  :rows="(assets.ctas && assets.ctas.rows) || []"
                  title="CTAs (botões)"
                  subtitle="o botão que leva ao WhatsApp"
                  icon="i-lucide-mouse-pointer-click"
                  :color="hex('ativos', 2)"
                  :targets="targets"
                  label-header="CTA"
                  empty-text="sem CTAs separados no período"
                />
              </div>
            </template>
          </div>

          <!-- 🏆 recordes e histórico -->
          <div
            v-if="tab === 'historico'"
            class="cv-block cv-block-sheer p-6 sm:p-9 mb-10"
            :style="blockVars('historico')"
          >
            <div class="flex items-center gap-2 mb-1 flex-wrap">
              <span class="cv-icon"
                ><span class="i-lucide-trophy text-base"
              /></span>
              <h2
                class="text-xl sm:text-2xl font-bold text-n-slate-12 tracking-tight leading-tight"
              >
                Recordes e histórico: nos superar um pouco a cada dia
              </h2>
              <span
                v-if="history && history.since"
                class="text-[11px] text-n-slate-9 ml-auto"
                >histórico desde {{ fmtDate(history.since) }}</span
              >
            </div>
            <p class="text-xs text-n-slate-10 mb-4">
              Os nossos melhores números, não os do mercado. Cada recorde batido
              vira a nova régua quando os parâmetros estão no modo automático.
            </p>
            <SkeletonScreen v-if="isHistoryLoading" variant="dashboard" />
            <p
              v-else-if="history && history.error"
              class="text-sm text-n-slate-10"
            >
              Não consegui carregar o histórico agora.
            </p>
            <template v-else-if="history">
              <div class="grid md:grid-cols-2 xl:grid-cols-3 gap-4 mb-10">
                <div
                  v-for="def in METRIC_DEFS"
                  :key="def.key"
                  class="cv-sub rounded-3xl p-5"
                >
                  <template v-if="recordFor(def.key)">
                    <p
                      class="text-xs font-bold text-n-slate-12 flex items-center gap-1.5"
                    >
                      <span
                        :class="PART_META[def.band].icon"
                        class="text-sm"
                      />{{ def.label }}
                      <span class="text-n-slate-9 font-normal"
                        >· {{ def.metric }}</span
                      >
                    </p>
                    <div class="grid grid-cols-3 gap-2 mt-3 text-center">
                      <div>
                        <p class="text-[10px] text-n-slate-9">Melhor dia</p>
                        <p
                          class="text-sm font-bold text-n-slate-12 tabular-nums"
                        >
                          {{
                            recordFor(def.key).best_day
                              ? fmtTarget(
                                  def,
                                  recordFor(def.key).best_day.value
                                )
                              : '—'
                          }}
                        </p>
                        <p class="text-[10px] text-n-slate-9">
                          {{
                            recordFor(def.key).best_day
                              ? fmtDate(recordFor(def.key).best_day.at)
                              : ''
                          }}
                        </p>
                      </div>
                      <div class="rounded-2xl bg-n-alpha-1 py-2">
                        <p class="text-[10px] text-n-slate-9">Melhor semana</p>
                        <p
                          class="text-xl font-extrabold text-n-slate-12 tabular-nums tracking-tight"
                        >
                          {{
                            recordFor(def.key).best_week
                              ? fmtTarget(
                                  def,
                                  recordFor(def.key).best_week.value
                                )
                              : '—'
                          }}
                        </p>
                        <p class="text-[10px] text-n-slate-9">
                          {{
                            recordFor(def.key).best_week
                              ? `de ${fmtDate(recordFor(def.key).best_week.at)}`
                              : ''
                          }}
                        </p>
                      </div>
                      <div>
                        <p class="text-[10px] text-n-slate-9">Melhor mês</p>
                        <p
                          class="text-sm font-bold text-n-slate-12 tabular-nums"
                        >
                          {{
                            recordFor(def.key).best_month
                              ? fmtTarget(
                                  def,
                                  recordFor(def.key).best_month.value
                                )
                              : '—'
                          }}
                        </p>
                        <p class="text-[10px] text-n-slate-9">
                          {{
                            recordFor(def.key).best_month
                              ? fmtDate(recordFor(def.key).best_month.at).slice(
                                  3
                                )
                              : ''
                          }}
                        </p>
                      </div>
                    </div>
                    <div class="mt-3">
                      <BulletMeter
                        label="Esta semana"
                        :band="recordBand(def, recordFor(def.key))"
                        metric="contra o recorde semanal"
                        :value="recordFor(def.key).current.week"
                        :prev="recordFor(def.key).previous.week"
                        :target="
                          recordFor(def.key).best_week
                            ? {
                                good: recordFor(def.key).best_week.value,
                                bad: recordFor(def.key).median_week,
                                lower_is_better: !!def.money,
                              }
                            : null
                        "
                        :digits="def.digits"
                        :money="!!def.money"
                        :color="hex('historico', 1)"
                        compact
                      />
                    </div>
                    <div
                      class="flex flex-wrap gap-x-3 gap-y-1 mt-2 text-[11px]"
                    >
                      <span
                        ><span class="text-n-slate-9">hoje × ontem</span>
                        <b
                          :class="
                            superChip(
                              recordFor(def.key).current.day,
                              recordFor(def.key).previous.day,
                              !!def.money
                            ).cls
                          "
                          >{{
                            superChip(
                              recordFor(def.key).current.day,
                              recordFor(def.key).previous.day,
                              !!def.money
                            ).text
                          }}</b
                        ></span
                      >
                      <span
                        ><span class="text-n-slate-9">semana × anterior</span>
                        <b
                          :class="
                            superChip(
                              recordFor(def.key).current.week,
                              recordFor(def.key).previous.week,
                              !!def.money
                            ).cls
                          "
                          >{{
                            superChip(
                              recordFor(def.key).current.week,
                              recordFor(def.key).previous.week,
                              !!def.money
                            ).text
                          }}</b
                        ></span
                      >
                      <span
                        ><span class="text-n-slate-9">mês × anterior</span>
                        <b
                          :class="
                            superChip(
                              recordFor(def.key).current.month,
                              recordFor(def.key).previous.month,
                              !!def.money
                            ).cls
                          "
                          >{{
                            superChip(
                              recordFor(def.key).current.month,
                              recordFor(def.key).previous.month,
                              !!def.money
                            ).text
                          }}</b
                        ></span
                      >
                    </div>
                  </template>
                  <p v-else class="text-xs text-n-slate-9">
                    {{ def.label }}: ainda sem histórico suficiente.
                  </p>
                </div>
              </div>

              <!-- 👑 campeões de todos os tempos -->
              <div class="flex items-center gap-2 mb-3 flex-wrap">
                <span class="cv-icon cv-icon-sm"
                  ><span class="i-lucide-crown text-sm"
                /></span>
                <h3
                  class="text-lg sm:text-xl font-bold text-n-slate-12 tracking-tight leading-tight"
                >
                  Campeões de todos os tempos
                </h3>
                <span class="text-[11px] text-n-slate-9"
                  >o criativo que fez o melhor número de cada parte desde o
                  início do histórico · Transcrever copia o texto para montar a
                  copy</span
                >
              </div>
              <RadarAxesPicker
                env="recordes"
                :relative-ok="false"
                class="mb-3"
              />
              <div
                class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-10"
              >
                <div
                  v-for="part in PART_KEYS"
                  :key="part"
                  class="cv-frame"
                  :class="{ 'cv-champion': !!allTime(part) }"
                >
                  <div class="cv-block p-5 sm:p-6 h-full flex flex-col gap-4">
                    <p
                      class="text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold flex items-center gap-1.5"
                    >
                      <span :class="PART_META[part].icon" class="text-xs" />{{
                        PART_META[part].label
                      }}
                    </p>
                    <template v-if="allTime(part)">
                      <div class="flex items-start justify-between gap-3">
                        <div class="min-w-0">
                          <p
                            class="text-[28px] font-extrabold text-n-slate-12 tabular-nums tracking-tight leading-none"
                          >
                            {{ PART_META[part].fmt(allTime(part).value) }}
                          </p>
                          <p class="text-[11px] text-n-slate-9 mt-1.5">
                            {{ PART_META[part].metric }}
                          </p>
                        </div>
                        <span
                          class="w-14 h-[4.5rem] rounded-xl overflow-hidden bg-n-alpha-2 flex-shrink-0 flex items-center justify-center ring-1 ring-black/5"
                        >
                          <img
                            v-if="allTime(part).thumbnail_url"
                            :src="allTime(part).thumbnail_url"
                            :alt="allTime(part).ad_name"
                            class="w-full h-full object-cover"
                            loading="lazy"
                          />
                          <span
                            v-else
                            :class="
                              FORMAT_ICON[allTime(part).format] ||
                              FORMAT_ICON.other
                            "
                            class="text-n-slate-9"
                          />
                        </span>
                      </div>
                      <CreativeRadar
                        :row="allTime(part)"
                        env="recordes"
                        :relative-ok="false"
                        :targets="(history && history.targets) || targets"
                        :peers="allTimeRows"
                        :size="104"
                        :color="hex('historico', 1)"
                        class="self-center"
                      />
                      <div class="border-t border-n-weak pt-3 space-y-1.5">
                        <p
                          class="text-xs font-semibold text-n-slate-12 leading-snug"
                        >
                          {{ allTime(part).ad_name }}
                        </p>
                        <p
                          v-if="allTime(part).text"
                          class="text-[11px] text-n-slate-11 italic whitespace-pre-line leading-snug"
                        >
                          “{{ allTime(part).text }}”
                        </p>
                      </div>
                      <div
                        class="mt-auto flex flex-wrap items-center gap-2 pt-1"
                      >
                        <span class="cv-champion-badge"
                          ><span class="i-lucide-trophy" />Recorde
                          histórico</span
                        >
                        <button
                          class="cv-btn cv-btn-sm cv-btn-ghost"
                          title="Copiar o texto desta parte"
                          @click="transcribe(allTime(part), part)"
                        >
                          <span class="i-lucide-copy text-sm" />Transcrever
                        </button>
                      </div>
                    </template>
                    <p v-else class="text-xs text-n-slate-9">
                      ainda sem campeão
                    </p>
                  </div>
                </div>
              </div>

              <!-- 📅 campeões mês a mês (lista agrupada, sem tabela) -->
              <div class="flex items-center gap-2 mb-3 flex-wrap">
                <span class="cv-icon cv-icon-sm"
                  ><span class="i-lucide-calendar-range text-sm"
                /></span>
                <h3
                  class="text-lg sm:text-xl font-bold text-n-slate-12 tracking-tight leading-tight"
                >
                  Campeões mês a mês
                </h3>
                <span class="text-[11px] text-n-slate-9"
                  >gancho, corpo, CTA e custo: quem venceu em cada mês</span
                >
              </div>
              <div class="space-y-3 mb-10">
                <div
                  v-for="m in visibleMonthRows"
                  :key="m.month"
                  class="cv-sub rounded-3xl p-4 sm:p-5"
                >
                  <div class="grid gap-4 lg:grid-cols-[7rem_minmax(0,1fr)]">
                    <div class="lg:border-r lg:border-n-weak lg:pr-4">
                      <p
                        class="text-base font-extrabold text-n-slate-12 tracking-tight"
                      >
                        {{ m.label }}
                      </p>
                      <p class="text-[11px] text-n-slate-9">
                        {{ m.days }} dia(s) com dados
                      </p>
                    </div>
                    <div
                      class="grid gap-x-5 gap-y-4 sm:grid-cols-2 xl:grid-cols-4"
                    >
                      <div
                        v-for="part in MONTH_PARTS"
                        :key="part"
                        class="min-w-0 flex flex-col gap-1.5"
                      >
                        <p
                          class="text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold flex items-center gap-1"
                        >
                          <span
                            :class="PART_META[part].icon"
                            class="text-xs"
                          />{{ PART_META[part].label }}
                        </p>
                        <template v-if="m[part]">
                          <div class="flex items-center gap-2.5">
                            <span
                              class="w-9 h-11 rounded-lg overflow-hidden bg-n-alpha-2 flex-shrink-0 flex items-center justify-center ring-1 ring-black/5"
                            >
                              <img
                                v-if="m[part].thumbnail_url"
                                :src="m[part].thumbnail_url"
                                :alt="m[part].ad_name"
                                class="w-full h-full object-cover"
                                loading="lazy"
                              />
                              <span
                                v-else
                                :class="
                                  FORMAT_ICON[m[part].format] ||
                                  FORMAT_ICON.other
                                "
                                class="text-n-slate-9 text-sm"
                              />
                            </span>
                            <div class="min-w-0">
                              <p
                                class="text-xl font-extrabold text-n-slate-12 tabular-nums tracking-tight leading-none"
                              >
                                {{ PART_META[part].fmt(m[part].value) }}
                              </p>
                              <p
                                class="text-[11px] text-n-slate-11 leading-snug mt-1"
                              >
                                {{ m[part].ad_name }}
                              </p>
                            </div>
                          </div>
                          <p
                            v-if="m[part].text && part !== 'cost'"
                            class="text-[11px] text-n-slate-10 italic whitespace-pre-line leading-snug"
                          >
                            “{{ m[part].text }}”
                          </p>
                          <button
                            class="cv-btn cv-btn-sm cv-btn-ghost self-start mt-auto"
                            title="Copiar o texto desta parte"
                            @click="transcribe(m[part], part)"
                          >
                            <span class="i-lucide-copy text-sm" />Transcrever
                          </button>
                        </template>
                        <span v-else class="text-xs text-n-slate-8">—</span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <div
                v-if="monthRows.length > 12"
                class="-mt-7 mb-10 flex justify-center"
              >
                <button
                  class="cv-btn cv-btn-sm cv-btn-ghost"
                  @click="showAllMonths = !showAllMonths"
                >
                  <span
                    :class="
                      showAllMonths
                        ? 'i-lucide-chevron-up'
                        : 'i-lucide-chevron-down'
                    "
                    class="text-sm"
                  />{{
                    showAllMonths
                      ? 'Mostrar só os últimos 12 meses'
                      : `Ver todos os ${monthRows.length} meses`
                  }}
                </button>
              </div>

              <!-- 🔀 peças campeãs por mês (criativo dinâmico) -->
              <template v-if="assetMonths.length">
                <div class="flex items-center gap-2 mb-3 flex-wrap">
                  <span class="cv-icon cv-icon-sm"
                    ><span class="i-lucide-shuffle text-sm"
                  /></span>
                  <h3
                    class="text-lg sm:text-xl font-bold text-n-slate-12 tracking-tight leading-tight"
                  >
                    Peças campeãs por mês
                  </h3>
                  <span class="text-[11px] text-n-slate-9"
                    >título, texto e botão com mais conversas em cada mês
                    (criativo dinâmico)</span
                  >
                </div>
                <div class="space-y-3">
                  <div
                    v-for="m in assetMonths"
                    :key="m.month"
                    class="cv-sub rounded-3xl p-4 sm:p-5"
                  >
                    <div class="grid gap-4 lg:grid-cols-[7rem_minmax(0,1fr)]">
                      <div class="lg:border-r lg:border-n-weak lg:pr-4">
                        <p
                          class="text-base font-extrabold text-n-slate-12 tracking-tight"
                        >
                          {{ m.label }}
                        </p>
                      </div>
                      <div class="grid gap-x-5 gap-y-4 md:grid-cols-3">
                        <div
                          v-for="k in ASSET_KINDS"
                          :key="k"
                          class="min-w-0 flex flex-col gap-1.5"
                        >
                          <p
                            class="text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold flex items-center gap-1"
                          >
                            <span
                              :class="ASSET_META[k].icon"
                              class="text-xs"
                            />{{ ASSET_META[k].label }}
                          </p>
                          <template v-if="m[k]">
                            <p
                              class="text-sm font-semibold text-n-slate-12 whitespace-pre-line leading-snug"
                            >
                              {{ m[k].label }}
                            </p>
                            <p class="text-[11px] text-n-slate-9">
                              <b class="text-n-slate-12 tabular-nums">{{
                                fmtNum(m[k].conversations)
                              }}</b>
                              conversas ·
                              {{
                                m[k].cost_conversation
                                  ? fmtMoney(m[k].cost_conversation)
                                  : '—'
                              }}
                              por conversa
                            </p>
                            <button
                              class="cv-btn cv-btn-sm cv-btn-ghost self-start mt-auto"
                              title="Copiar o texto desta peça"
                              @click="transcribe(m[k], k)"
                            >
                              <span class="i-lucide-copy text-sm" />Transcrever
                            </button>
                          </template>
                          <span v-else class="text-xs text-n-slate-8">—</span>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </template>
            </template>
          </div>

          <!-- 📈 ritmo da conta + fatia -->
          <template v-if="tab === 'conta'">
            <div class="cv-block p-6 sm:p-9 mb-10" :style="blockVars('ritmo')">
              <div class="flex items-center gap-2 mb-1 flex-wrap">
                <span class="cv-icon"
                  ><span class="i-lucide-activity text-base"
                /></span>
                <h2
                  class="text-xl sm:text-2xl font-bold text-n-slate-12 tracking-tight leading-tight"
                >
                  Ritmo da conta, dia a dia
                </h2>
                <span class="text-[11px] text-n-slate-9 ml-auto"
                  >soma de todos os criativos do recorte</span
                >
              </div>
              <p class="text-[11px] text-n-slate-9 mb-4">
                Pontinhos = o mesmo dia no período anterior · linha tracejada =
                média do período.
              </p>
              <div class="grid lg:grid-cols-3 gap-6">
                <div>
                  <p class="text-xs font-semibold text-n-slate-11">
                    Investimento (R$)
                  </p>
                  <p class="text-[11px] text-n-slate-9 mb-1">
                    {{ readSeries(dailySpend, v => fmtMoney(v)) }}
                  </p>
                  <MiniBars
                    :values="dailySpend"
                    :labels="dailyLabels"
                    :prev-values="prevSeries('spend')"
                    :color="hex('ritmo', 0)"
                    :height="140"
                    :format="v => fmtMoney(v)"
                  />
                </div>
                <div>
                  <p class="text-xs font-semibold text-n-slate-11">
                    Conversas iniciadas
                  </p>
                  <p class="text-[11px] text-n-slate-9 mb-1">
                    {{ readSeries(dailyConv, v => `${Math.round(v)}`) }}
                  </p>
                  <MiniBars
                    :values="dailyConv"
                    :labels="dailyLabels"
                    :prev-values="prevSeries('conversations')"
                    :color="hex('ritmo', 1)"
                    :height="140"
                    :format="v => `${v} conv.`"
                  />
                </div>
                <div>
                  <p class="text-xs font-semibold text-n-slate-11">
                    CTR de link (%)
                  </p>
                  <p class="text-[11px] text-n-slate-9 mb-1">
                    {{ readSeries(dailyCtr, pctFmt) }}
                  </p>
                  <MiniBars
                    :values="dailyCtr"
                    :labels="dailyLabels"
                    :prev-values="prevCtr"
                    :reference="avgCtrPct"
                    :color="hex('ritmo', 2)"
                    :height="140"
                    :format="v => `${String(v).replace('.', ',')}%`"
                  />
                </div>
              </div>
            </div>
            <div class="cv-block p-6 sm:p-9 mb-10" :style="blockVars('fatia')">
              <div class="flex items-center gap-2 mb-3 flex-wrap">
                <span class="cv-icon"
                  ><span class="i-lucide-chart-pie text-base"
                /></span>
                <h2
                  class="text-xl sm:text-2xl font-bold text-n-slate-12 tracking-tight leading-tight"
                >
                  Onde está o investimento
                </h2>
              </div>
              <div class="grid md:grid-cols-2 gap-6">
                <div>
                  <p class="text-xs font-semibold text-n-slate-11 mb-2">
                    Por formato
                  </p>
                  <ShareBar
                    :items="spendByFormat"
                    :family="blockFamily('fatia')"
                    :format="fmtMoney"
                    :height="18"
                  />
                </div>
                <div>
                  <p class="text-xs font-semibold text-n-slate-11 mb-2">
                    Por campanha
                  </p>
                  <ShareBar
                    :items="spendByCampaign"
                    :family="blockFamily('fatia')"
                    :format="fmtMoney"
                    :height="18"
                    :max="5"
                  />
                </div>
              </div>
            </div>
          </template>

          <!-- ⚙️ parâmetros e fórmulas -->
          <div
            v-if="tab === 'formulas'"
            class="cv-block p-6 sm:p-9 mb-10"
            :style="blockVars('formulas')"
          >
            <div class="flex items-center gap-2 mb-1">
              <span class="cv-icon"
                ><span class="i-lucide-sliders-horizontal text-base"
              /></span>
              <h2
                class="text-xl sm:text-2xl font-bold text-n-slate-12 tracking-tight leading-tight"
              >
                Parâmetros: o que é bom e o que é ruim
              </h2>
            </div>
            <p class="text-xs text-n-slate-10 mb-3">
              Dois jeitos de definir a régua. <b>Manual</b>: números fixos,
              começando pelos benchmarks publicados para vídeo na Meta.
              <b>Automático</b>: o nosso próprio histórico manda. O bom é a
              nossa melhor semana mais um passo de superação, e o ruim é ficar
              abaixo da nossa mediana semanal. Cada recorde batido sobe a régua
              sozinho.
            </p>
            <div class="flex items-center gap-3 flex-wrap mb-4">
              <span class="cv-seg cv-seg-sm">
                <button
                  class="cv-seg-item"
                  :class="{ 'cv-seg-on': !isAuto }"
                  :disabled="!isAdmin"
                  @click="targetMode = 'manual'"
                >
                  <span class="i-lucide-pencil cv-seg-icon" />Manual
                </button>
                <button
                  class="cv-seg-item"
                  :class="{ 'cv-seg-on': isAuto }"
                  :disabled="!isAdmin"
                  @click="targetMode = 'auto'"
                >
                  <span class="i-lucide-trending-up cv-seg-icon" />Automático
                  pelo nosso histórico
                </button>
              </span>
              <label
                v-if="isAuto"
                class="inline-flex items-center gap-1.5 text-xs text-n-slate-11"
              >
                passo de superação
                <input
                  v-model="targetStep"
                  type="text"
                  inputmode="decimal"
                  class="cv-input !w-16 !py-1 text-xs"
                  :disabled="!isAdmin"
                />
                % além do nosso recorde
              </label>
              <span
                v-if="
                  isAdmin &&
                  ((isAuto && targets.mode !== 'auto') ||
                    (!isAuto && targets.mode === 'auto'))
                "
                class="text-[11px] text-amber-700 dark:text-amber-400"
                >salve para valer</span
              >
            </div>
            <div class="overflow-x-auto -mx-2 px-2 mb-6">
              <table class="w-full text-xs">
                <thead>
                  <tr
                    class="text-[10px] uppercase tracking-wide text-n-slate-9"
                  >
                    <th class="text-left font-semibold py-2 pr-3">Peça</th>
                    <th class="text-left font-semibold py-2 pr-3">
                      Como se mede
                    </th>
                    <th class="text-left font-semibold py-2 pr-3">Ruim</th>
                    <th class="text-left font-semibold py-2 pr-3">Bom</th>
                    <th
                      class="text-left font-semibold py-2 hidden xl:table-cell"
                    >
                      Leitura das faixas
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="def in METRIC_DEFS"
                    :key="def.key"
                    class="border-t border-n-weak align-middle"
                  >
                    <td
                      class="py-2 pr-3 font-semibold text-n-slate-12 whitespace-nowrap"
                    >
                      {{ def.label }}
                      <span
                        class="block text-[10px] text-n-slate-9 font-normal"
                        >{{ def.metric }}</span
                      >
                      <span
                        class="block text-[10px] text-n-slate-9 font-normal xl:hidden whitespace-normal max-w-[14rem]"
                        >{{ targetText(def) }}</span
                      >
                    </td>
                    <td class="py-2 pr-3 text-n-slate-11">
                      {{ def.hint || 'investimento ÷ conversas iniciadas' }}
                    </td>
                    <td class="py-2 pr-3 whitespace-nowrap">
                      <span
                        v-if="isAdmin && targetForm[def.key] && !isAuto"
                        class="inline-flex items-center gap-1"
                      >
                        <span class="text-n-slate-9">{{
                          targets[def.key] && targets[def.key].lower_is_better
                            ? 'acima de'
                            : 'abaixo de'
                        }}</span>
                        <input
                          v-model="targetForm[def.key].bad"
                          type="text"
                          inputmode="decimal"
                          class="cv-input !w-20 !py-1 text-xs"
                        />
                        <span class="text-n-slate-9">{{
                          def.money ? 'R$' : '%'
                        }}</span>
                      </span>
                      <span
                        v-else-if="targets[def.key]"
                        class="text-red-700 dark:text-red-400 font-semibold"
                        >{{
                          targets[def.key].lower_is_better
                            ? 'acima de'
                            : 'abaixo de'
                        }}
                        {{ fmtTarget(def, targets[def.key].bad) }}</span
                      >
                    </td>
                    <td class="py-2 pr-3 whitespace-nowrap">
                      <span
                        v-if="isAdmin && targetForm[def.key] && !isAuto"
                        class="inline-flex items-center gap-1"
                      >
                        <span class="text-n-slate-9">{{
                          targets[def.key] && targets[def.key].lower_is_better
                            ? 'até'
                            : 'a partir de'
                        }}</span>
                        <input
                          v-model="targetForm[def.key].good"
                          type="text"
                          inputmode="decimal"
                          class="cv-input !w-20 !py-1 text-xs"
                        />
                        <span class="text-n-slate-9">{{
                          def.money ? 'R$' : '%'
                        }}</span>
                      </span>
                      <span
                        v-else-if="targets[def.key]"
                        class="text-emerald-700 dark:text-emerald-400 font-semibold"
                        >{{
                          targets[def.key].lower_is_better
                            ? 'até'
                            : 'a partir de'
                        }}
                        {{ fmtTarget(def, targets[def.key].good) }}</span
                      >
                    </td>
                    <td class="py-2 text-n-slate-10 hidden xl:table-cell">
                      {{ targetText(def) }}
                      <span
                        v-if="
                          targets[def.key] && targets[def.key].source === 'auto'
                        "
                        class="block text-[10px] text-n-slate-9"
                        >recorde
                        {{ fmtTarget(def, targets[def.key].record) }} na semana
                        de {{ fmtDate(targets[def.key].record_at) }} · mediana
                        {{ fmtTarget(def, targets[def.key].median) }}</span
                      >
                      <span
                        v-else-if="
                          targets[def.key] && targets[def.key].fallback
                        "
                        class="block text-[10px] text-amber-700 dark:text-amber-400"
                        >sem histórico suficiente: usando o manual</span
                      >
                    </td>
                  </tr>
                </tbody>
              </table>
              <div
                v-if="isAdmin"
                class="flex items-center gap-3 mt-3 flex-wrap"
              >
                <button
                  class="cv-btn cv-btn-sm"
                  :disabled="isSavingTargets"
                  @click="saveTargets"
                >
                  <span class="i-lucide-save text-sm" />{{
                    isSavingTargets ? 'Salvando…' : 'Salvar parâmetros'
                  }}
                </button>
                <span class="text-[11px] text-n-slate-9"
                  >Entre o ruim e o bom fica a zona de atenção. Vale para toda a
                  conta.{{
                    isAuto
                      ? ' No automático os números da tabela são calculados; edite só o passo.'
                      : ''
                  }}</span
                >
              </div>
            </div>
            <div class="flex items-center gap-2 mb-3">
              <span class="cv-icon"
                ><span class="i-lucide-info text-base"
              /></span>
              <h2
                class="text-xl sm:text-2xl font-bold text-n-slate-12 tracking-tight leading-tight"
              >
                Como se calcula
              </h2>
            </div>
            <ul class="grid md:grid-cols-2 gap-x-6 gap-y-2">
              <li
                v-for="f in FORMULAS"
                :key="f.label"
                class="text-xs text-n-slate-10"
              >
                <b class="text-n-slate-12">{{ f.label }}:</b> {{ f.text }}
              </li>
            </ul>
          </div>

          <!-- 🗄️ nossos dados: guardados aqui, independentes da Meta (item 174) -->
          <div
            v-if="tab === 'formulas'"
            class="cv-block p-6 sm:p-9 mb-10"
            :style="blockVars('dados')"
          >
            <div class="flex items-center gap-2 mb-1 flex-wrap">
              <span class="cv-icon"
                ><span class="i-lucide-database text-base"
              /></span>
              <h2
                class="text-xl sm:text-2xl font-bold text-n-slate-12 tracking-tight leading-tight"
              >
                Nossos dados: guardados aqui, independentes da Meta
              </h2>
              <span
                v-if="storage && storage.since"
                class="text-[11px] text-n-slate-9 ml-auto"
                >histórico guardado desde {{ fmtDate(storage.since) }}</span
              >
            </div>
            <p class="text-xs text-n-slate-10 mb-4">
              Tudo que a Meta entrega fica gravado no nosso banco, anúncio por
              anúncio, dia a dia, junto com o texto do criativo e uma cópia da
              miniatura. Continua aqui mesmo se o anúncio for apagado lá ou a
              imagem expirar. A Meta guarda 37 meses de números; dá para trazer
              tudo de uma vez.
            </p>
            <div
              v-if="storage"
              class="grid grid-cols-2 lg:grid-cols-4 gap-5 mb-4"
            >
              <div class="cv-sub rounded-2xl p-3">
                <p
                  class="text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold"
                >
                  Anúncios guardados
                </p>
                <p
                  class="text-2xl font-extrabold tracking-tight text-n-slate-12 tabular-nums"
                >
                  {{ fmtNum(storage.ads) }}
                </p>
                <p class="text-[11px] text-n-slate-9">
                  {{ storage.gone_on_meta }} já apagado(s) ou arquivado(s) na
                  Meta
                </p>
              </div>
              <div class="cv-sub rounded-2xl p-3">
                <p
                  class="text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold"
                >
                  Dias com dados
                </p>
                <p
                  class="text-2xl font-extrabold tracking-tight text-n-slate-12 tabular-nums"
                >
                  {{ fmtNum(storage.days) }}
                </p>
                <p class="text-[11px] text-n-slate-9">
                  {{
                    storage.since
                      ? `de ${fmtDate(storage.since)} a ${fmtDate(storage.until)}`
                      : 'nada guardado ainda'
                  }}
                </p>
              </div>
              <div class="cv-sub rounded-2xl p-3">
                <p
                  class="text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold"
                >
                  Linhas anúncio × dia
                </p>
                <p
                  class="text-2xl font-extrabold tracking-tight text-n-slate-12 tabular-nums"
                >
                  {{ fmtNum(storage.rows) }}
                </p>
                <p class="text-[11px] text-n-slate-9">
                  cada uma com investimento, vídeo, cliques e conversas
                </p>
              </div>
              <div class="cv-sub rounded-2xl p-3">
                <p
                  class="text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold"
                >
                  Miniaturas guardadas
                </p>
                <p
                  class="text-2xl font-extrabold tracking-tight text-n-slate-12 tabular-nums"
                >
                  {{ fmtNum(storage.thumbnails) }}
                  <span class="text-sm font-semibold text-n-slate-9"
                    >de {{ fmtNum(storage.ads) }}</span
                  >
                </p>
                <p class="text-[11px] text-n-slate-9">
                  cópia nossa; a URL da Meta expira em horas
                </p>
              </div>
            </div>
            <div v-if="isSyncing && syncProgress" class="mb-3">
              <p class="text-[11px] text-n-slate-10 mb-1">
                {{ syncingText }} · {{ fmtDate(syncProgress.since) }} a
                {{ fmtDate(syncProgress.until) }}
              </p>
              <div class="cv-track cv-track-sm">
                <div
                  class="cv-fill"
                  :style="{ width: `${Math.max(3, syncPct)}%` }"
                />
              </div>
            </div>
            <div class="flex flex-wrap items-center gap-2">
              <button
                v-if="isAdmin"
                class="cv-btn cv-btn-sm"
                :disabled="isSyncing || !configured"
                @click="runHistory"
              >
                <span
                  :class="
                    isSyncing
                      ? 'i-lucide-loader-circle animate-spin'
                      : 'i-lucide-history'
                  "
                  class="text-sm"
                />
                {{
                  isSyncing
                    ? 'Carregando…'
                    : 'Carregar histórico completo (até 37 meses)'
                }}
              </button>
              <button
                class="cv-btn cv-btn-sm cv-btn-ghost"
                :disabled="isExporting"
                @click="downloadCsv(false)"
              >
                <span class="i-lucide-download text-sm" />Exportar CSV do
                período
              </button>
              <button
                class="cv-btn cv-btn-sm cv-btn-ghost"
                :disabled="isExporting"
                @click="downloadCsv(true)"
              >
                <span class="i-lucide-archive text-sm" />Exportar tudo (CSV)
              </button>
              <span class="text-[11px] text-n-slate-9">
                A carga completa roda em segundo plano, em janelas de 90 dias;
                pode levar alguns minutos e você pode sair da tela. O CSV abre
                direto no Excel.
              </span>
            </div>
          </div>
        </template>
      </template>
    </div>

    <!-- barra da comparação -->
    <div
      v-if="compareMode"
      class="fixed bottom-4 left-1/2 -translate-x-1/2 z-40 cv-block cv-glass px-4 py-2.5 flex items-center gap-3 shadow-lg"
    >
      <span class="text-xs text-n-slate-11"
        >{{ selectedIds.length }} de 4 selecionado(s)</span
      >
      <button
        class="cv-btn cv-btn-sm"
        :disabled="selectedIds.length < 2"
        @click="showCompare = true"
      >
        <span class="i-lucide-columns-3 text-sm" />Comparar
      </button>
      <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="leaveCompare">
        Cancelar
      </button>
    </div>

    <CreativeDetail
      v-if="detailAdId"
      :ad-id="detailAdId"
      :period-params="periodParams"
      :family="blockFamily('criativos')"
      :cv-vars="cvVars"
      :ad-account-id="(data && data.ad_account_id) || ''"
      @close="detailAdId = null"
    />
    <CreativeCompare
      v-if="showCompare"
      :targets="targets"
      :averages="averages"
      :rows="compareRows"
      :cv-vars="cvVars"
      @close="showCompare = false"
    />
  </div>
</template>
