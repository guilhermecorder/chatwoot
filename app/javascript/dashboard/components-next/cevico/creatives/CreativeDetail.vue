<script setup>
// "Análise científica" (era "Ver a fundo"; item 172, rodada 2): modal SÓLIDO do kit (cv-modal) com
// seções que se leem de cima para baixo — ficha, leitura com as quatro
// réguas, ritmo dia a dia (um eixo por gráfico, linha da média e do
// parâmetro), 1ª × 2ª metade, curva de retenção contra a média da conta,
// onde apareceu, quem viu e as peças do criativo dinâmico.
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import CevicoCreativesAPI from 'dashboard/api/cevicoCreatives';
import MiniBars from 'dashboard/components-next/cevico/MiniBars.vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import { hexFromGrad } from 'dashboard/helper/cevicoPalettes';
import VerdictBars from './VerdictBars.vue';
import BreakdownRanking from './BreakdownRanking.vue';
import RateLine from './RateLine.vue';
import ScoreRadar from './ScoreRadar.vue';
import RetentionCurve from './RetentionCurve.vue';
import MoneyTiles from './MoneyTiles.vue';
import AssetTable from './AssetTable.vue';
import CreativeRadar from './CreativeRadar.vue';
import RadarAxesPicker from './RadarAxesPicker.vue';
import RetentionArea from './RetentionArea.vue';
import ClicksByMark from './ClicksByMark.vue';
import { useAlert } from 'dashboard/composables';
import { useTranscribe, copyPlain } from './useTranscribe';
import {
  fmtMoney,
  fmtCompact,
  fmtPct,
  fmtNum,
  statusMeta,
  FORMAT_ICON,
  FOCUS_META,
  BAND_META,
  CHAMPION_META,
  delta,
  fmtDelta,
  deltaCls,
} from './creativeFormat';

const props = defineProps({
  adId: { type: String, required: true },
  periodParams: { type: Object, default: () => ({}) },
  family: { type: Array, default: () => [] },
  cvVars: { type: Object, default: () => ({}) },
  adAccountId: { type: String, default: '' },
});
const emit = defineEmits(['close']);
const { transcribe } = useTranscribe();
const data = ref(null);
const isLoading = ref(false);
const error = ref('');
const imgFailed = ref(false);

// 🎬 item 181: transcrição do vídeo
const showTranscript = ref(false);
const isTranscribing = ref(false);
const fromVideo = computed(
  () => data.value && data.value.text_source === 'video'
);
const transcriptStatus = computed(
  () =>
    (data.value && data.value.transcript && data.value.transcript.status) || ''
);
const isWaitingTranscript = computed(() =>
  ['queued', 'processing'].includes(transcriptStatus.value)
);
// item 286: o motivo de não ter transcrito fica À VISTA (antes o botão escondia)
const transcriptProblem = computed(() => {
  if (!['failed', 'skipped'].includes(transcriptStatus.value)) return '';
  return data.value.transcript.error || 'a transcrição falhou';
});
const canTranscribe = computed(
  () =>
    data.value &&
    (data.value.transcribable || data.value.format === 'video') &&
    !fromVideo.value &&
    !isWaitingTranscript.value
);
// acompanha a fila: confere a cada 6 s (até 5 min) e a tela se atualiza sozinha
const POLL_MS = 6000;
const POLL_MAX = 50;
let pollTimer = null;
let pollCount = 0;
const stopPolling = () => {
  clearTimeout(pollTimer);
  pollTimer = null;
};
const pollTranscript = () => {
  stopPolling();
  if (!isWaitingTranscript.value || pollCount >= POLL_MAX) return;
  pollTimer = setTimeout(async () => {
    pollCount += 1;
    try {
      const { data: fresh } = await CevicoCreativesAPI.show(
        props.adId,
        props.periodParams
      );
      data.value = fresh;
      if (fresh.text_source === 'video') showTranscript.value = true;
    } catch {
      // rede oscilou: tenta de novo na próxima volta
    }
    pollTranscript();
  }, POLL_MS);
};
onBeforeUnmount(stopPolling);
const transcribeVideo = async () => {
  if (!data.value) return;
  isTranscribing.value = true;
  try {
    const { data: r } = await CevicoCreativesAPI.transcribeVideo(
      data.value.ad_id
    );
    data.value = { ...data.value, transcript: r.transcript };
    pollCount = 0;
    pollTranscript();
  } catch (e) {
    error.value =
      (e.response && e.response.data && e.response.data.error) ||
      'Não consegui pedir a transcrição.';
  } finally {
    isTranscribing.value = false;
  }
};

// 🔗 item 287: link só de leitura (vale 30 dias) + copiar a análise completa
// rodada 2: duas versões — SEM dados financeiros (padrão) ou COM; a escolha vai dentro do link
const shareLink = ref(null);
const isSharing = ref(false);
const showShareOptions = ref(false);
const shareFinance = ref(false);
const SHARE_OPTIONS = [
  {
    value: false,
    label: 'Sem dados financeiros',
    icon: 'i-lucide-eye-off',
    hint: 'Mostra taxas, retenção, cliques, transcrição, textos e as quantidades da jornada. Nenhum valor em reais.',
  },
  {
    value: true,
    label: 'Com dados financeiros',
    icon: 'i-lucide-badge-dollar-sign',
    hint: 'Mostra também investimento, custo por conversa, por consulta e por cirurgia, e o retorno (ROAS).',
  },
];
const copyShareUrl = async () => {
  if (!shareLink.value) return;
  const ok = await copyPlain(shareLink.value.url);
  useAlert(
    ok
      ? `Link copiado. Este link vale até ${shareLink.value.expires_label}.`
      : 'Não consegui copiar sozinho: selecione o link e copie.'
  );
};
const share = async () => {
  if (!data.value || isSharing.value) return;
  isSharing.value = true;
  try {
    const { data: link } = await CevicoCreativesAPI.share(data.value.ad_id, {
      ...props.periodParams,
      finance: shareFinance.value ? 1 : 0,
    });
    shareLink.value = link;
    showShareOptions.value = false;
    await copyShareUrl();
  } catch (e) {
    useAlert(
      (e.response && e.response.data && e.response.data.error) ||
        'Não consegui gerar o link de leitura.'
    );
  } finally {
    isSharing.value = false;
  }
};
const copyAnalysis = async () => {
  if (!data.value || !data.value.analysis_text) return;
  const ok = await copyPlain(data.value.analysis_text);
  useAlert(
    ok
      ? 'Análise completa copiada: é só colar onde quiser.'
      : 'Não consegui copiar. Tente de novo.'
  );
};
const fmtDay = iso =>
  iso ? String(iso).slice(0, 10).split('-').reverse().join('/') : '';

const load = async () => {
  isLoading.value = true;
  shareLink.value = null;
  showShareOptions.value = false;
  error.value = '';
  try {
    const { data: response } = await CevicoCreativesAPI.show(
      props.adId,
      props.periodParams
    );
    data.value = response;
    pollCount = 0;
    pollTranscript();
  } catch (e) {
    error.value =
      (e.response && e.response.data && e.response.data.error) ||
      'Não consegui carregar este anúncio.';
  } finally {
    isLoading.value = false;
  }
};
onMounted(load);
watch(() => [props.adId, props.periodParams], load, { deep: true });

const color = i => hexFromGrad(props.family[i] || '') || '#0F5FA6';
const averages = computed(() => (data.value && data.value.averages) || {});
const targets = computed(() => (data.value && data.value.targets) || {});
const isVideo = computed(
  () =>
    data.value &&
    data.value.rates.hook_rate !== null &&
    data.value.rates.hook_rate !== undefined
);
const status = computed(() => statusMeta(data.value && data.value.status));
const diag = computed(() => (data.value && data.value.diagnosis) || {});
const bands = computed(() => diag.value.bands || {});
const prev = computed(() => (data.value && data.value.prev) || null);
// 🎯 rodada 2: indicadores sem legenda (Barras | Linha), preferência guardada no navegador
const METERS_VIEW_KEY = 'cevico:creatives:meters-view';
const readMetersView = () => {
  try {
    return localStorage.getItem(METERS_VIEW_KEY) === 'line' ? 'line' : 'bars';
  } catch {
    return 'bars';
  }
};
const metersView = ref(readMetersView());
const setMetersView = view => {
  metersView.value = view;
  try {
    localStorage.setItem(METERS_VIEW_KEY, view);
  } catch {
    // navegador sem armazenamento: a escolha vale só nesta tela
  }
};
const scorecard = computed(
  () => (data.value && data.value.scorecard) || { indicators: [], radar: null }
);
const dailyOf = key => {
  if (!data.value) return [];
  return data.value.daily.map(d => {
    if (key === 'conv_rate')
      return d.link_clicks ? d.conversations / d.link_clicks : null;
    const v = d[key];
    return v === null || v === undefined ? null : Number(v);
  });
};
const rateFmt = digits => v =>
  `${(Number(v || 0) * 100).toFixed(digits).replace('.', ',')}%`;
const lineCharts = computed(() =>
  scorecard.value.indicators
    .filter(i => ['hook_rate', 'hold_rate', 'link_ctr'].includes(i.key))
    .map((i, n) => ({
      ...i,
      values: dailyOf(i.key),
      format: rateFmt(i.digits || 1),
      color: color(n),
    }))
);
const labels = computed(() =>
  data.value ? data.value.daily.map(d => d.label) : []
);
const series = key =>
  computed(() => (data.value ? data.value.daily.map(d => d[key]) : []));
const ctrSeries = computed(() =>
  data.value
    ? data.value.daily.map(d => Number(((d.link_ctr || 0) * 100).toFixed(2)))
    : []
);
const hookSeries = computed(() =>
  data.value
    ? data.value.daily.map(d => Number(((d.hook_rate || 0) * 100).toFixed(1)))
    : []
);
const spendSeries = series('spend');
const convSeries = series('conversations');
const avgCtrPct = computed(() =>
  averages.value.link_ctr
    ? Number((averages.value.link_ctr * 100).toFixed(2))
    : null
);
const hookGoalPct = computed(() =>
  targets.value.hook_rate
    ? Number((targets.value.hook_rate.good * 100).toFixed(0))
    : null
);

// leitura de cada série: média, melhor e pior dia
const readSeries = (values, fmt, lowerIsBetter = false) => {
  if (!data.value || !values.length) return '';
  const pairs = values
    .map((v, i) => ({ v, l: data.value.daily[i].label }))
    .filter(p => Number.isFinite(p.v));
  if (!pairs.length) return '';
  const avg = pairs.reduce((a, p) => a + p.v, 0) / pairs.length;
  const sorted = [...pairs].sort((a, b) => b.v - a.v);
  const best = lowerIsBetter ? sorted[sorted.length - 1] : sorted[0];
  const worst = lowerIsBetter ? sorted[0] : sorted[sorted.length - 1];
  return `média ${fmt(avg)} · melhor dia ${best.l} (${fmt(best.v)}) · pior dia ${worst.l} (${fmt(worst.v)})`;
};
const pctFmt = v => `${Number(v).toFixed(2).replace('.', ',')}%`;

const halfRows = computed(() => {
  if (!data.value || !data.value.halves) return [];
  const { first, last } = data.value.halves;
  const rows = [
    {
      label: 'CTR de link',
      a: fmtPct(first.link_ctr, 2),
      b: fmtPct(last.link_ctr, 2),
      d: delta(last.link_ctr, first.link_ctr),
      lower: false,
    },
    {
      label: 'Conversas',
      a: fmtNum(first.conversations),
      b: fmtNum(last.conversations),
      d: delta(last.conversations, first.conversations),
      lower: false,
    },
    {
      label: 'Investimento',
      a: fmtMoney(first.spend),
      b: fmtMoney(last.spend),
      d: delta(last.spend, first.spend),
      neutral: true,
    },
    {
      label: 'Impressões',
      a: fmtCompact(first.impressions),
      b: fmtCompact(last.impressions),
      d: delta(last.impressions, first.impressions),
      neutral: true,
    },
  ];
  if (isVideo.value)
    rows.splice(1, 0, {
      label: 'Taxa de parada',
      a: fmtPct(first.hook_rate),
      b: fmtPct(last.hook_rate),
      d: delta(last.hook_rate, first.hook_rate),
      lower: false,
    });
  return rows;
});

const retentionSeries = computed(() => {
  if (!data.value || !data.value.rates.retention) return [];
  const s = [
    {
      label: 'Este criativo',
      values: data.value.rates.retention,
      color: color(0),
    },
  ];
  if (averages.value.retention)
    s.push({
      label: 'Média da conta',
      values: averages.value.retention,
      color: '#94a3b8',
    });
  return s;
});
const retentionReading = computed(() => {
  if (!data.value || !data.value.rates.retention) return '';
  const r = data.value.rates.retention;
  const drops = [
    { from: 'impressão', to: '3 s', d: 1 - r[0] },
    { from: '3 s', to: '25%', d: r[0] - r[1] },
    { from: '25%', to: '50%', d: r[1] - r[2] },
    { from: '50%', to: '75%', d: r[2] - r[3] },
    { from: '75%', to: '100%', d: r[3] - r[4] },
  ];
  const worst = [...drops].sort((a, b) => b.d - a.d)[0];
  return `${fmtPct(r[2], 0)} das impressões chegam à metade do vídeo e ${fmtPct(r[4], 0)} ao fim. A maior queda é entre ${worst.from} e ${worst.to}.`;
});

const managerUrl = computed(() =>
  props.adAccountId && data.value
    ? `https://business.facebook.com/adsmanager/manage/ads?act=${props.adAccountId}&selected_ad_ids=${data.value.ad_id}`
    : ''
);
const bkRows = bk => (bk && bk.rows) || [];
// 🧭 faixa do topo (pedido 20/09): os indicadores mais relevantes juntos, com nome
const topTiles = computed(() => {
  if (!data.value) return [];
  const d = data.value;
  const r = d.rates || {};
  const s = d.summary || {};
  const tiles = [
    { label: 'Investido', value: fmtMoney(d.totals.spend) },
    { label: 'Impressões', value: fmtCompact(d.totals.impressions) },
    { label: 'Alcance', value: fmtCompact(s.reach || d.totals.reach) },
    { label: 'Conversas', value: fmtNum(d.totals.conversations), strong: true },
    {
      label: 'Custo por conversa',
      value: r.cost_conversation ? fmtMoney(r.cost_conversation) : '—',
      band: bands.value.cost,
    },
    {
      label: 'CTR de link',
      value: fmtPct(r.link_ctr, 2),
      band: bands.value.cta,
    },
    {
      label: 'Conversa por clique',
      value: fmtPct(r.conv_rate),
      band: bands.value.conv,
    },
  ];
  if (isVideo.value) {
    tiles.push(
      {
        label: 'Taxa de parada',
        value: fmtPct(r.hook_rate),
        band: bands.value.hook,
      },
      { label: 'Retenção', value: fmtPct(r.hold_rate), band: bands.value.hold }
    );
  }
  tiles.push(
    {
      label: 'Custo por consulta',
      value: r.cost_booked ? fmtMoney(r.cost_booked) : '—',
      money: true,
    },
    {
      label: 'Custo por cirurgia',
      value: r.cost_surgery ? fmtMoney(r.cost_surgery) : '—',
      money: true,
    },
    {
      label: 'ROAS',
      value: r.roas ? `${String(r.roas).replace('.', ',')}×` : '—',
      money: true,
    },
    { label: '% agendamento', value: fmtPct(r.booking_rate, 0), money: true }
  );
  return tiles;
});
const champions = computed(() =>
  ((data.value && data.value.champion_of) || []).filter(k => CHAMPION_META[k])
);
// tiles de contexto (Meta) em uma linha só — cada um com a variação
const metaTiles = computed(() => {
  if (!data.value) return [];
  const d = data.value;
  const p = prev.value;
  const s = d.summary || {};
  return [
    {
      label: 'Investido',
      value: fmtMoney(d.totals.spend),
      d: p && delta(d.totals.spend, p.spend),
      neutral: true,
    },
    {
      label: 'Impressões',
      value: fmtCompact(d.totals.impressions),
      d: p && delta(d.totals.impressions, p.impressions),
      neutral: true,
    },
    {
      label: 'Alcance real',
      value: fmtCompact(s.reach || d.totals.reach),
      sub: 'pessoas no período',
    },
    {
      label: 'Frequência',
      value: s.frequency ? String(s.frequency).replace('.', ',') : '—',
      sub: 'vezes por pessoa',
    },
    {
      label: 'Conversas',
      value: fmtNum(d.totals.conversations),
      d: p && delta(d.totals.conversations, p.conversations),
    },
    {
      label: 'Custo por conversa',
      value: d.rates.cost_conversation
        ? fmtMoney(d.rates.cost_conversation)
        : '—',
      d: p && delta(d.rates.cost_conversation, p.cost_conversation),
      lower: true,
      band: bands.value.cost,
    },
  ];
});
</script>

<template>
  <Teleport to="body">
    <div
      class="cv-page fixed inset-0 z-[60] flex items-start sm:items-center justify-center bg-black/60 p-0 sm:p-6"
      :style="cvVars"
      @click.self="emit('close')"
    >
      <div
        class="cv-modal w-full max-w-6xl h-full sm:h-auto sm:max-h-[95vh] flex flex-col rounded-none sm:rounded-3xl"
      >
        <!-- cabeçalho: nome grande, contexto, ações -->
        <div class="cv-modal-head flex items-center gap-3 sm:gap-4">
          <span class="cv-icon cv-icon-lg flex-shrink-0"
            ><span
              :class="FORMAT_ICON[(data && data.format) || 'other']"
              class="text-lg"
          /></span>
          <div class="min-w-0 flex-1">
            <p class="cd-head-sub text-[11px]">Análise científica</p>
            <h2
              class="cd-head-title text-lg sm:text-2xl font-bold leading-tight tracking-tight break-words"
            >
              {{ data ? data.ad_name : 'Carregando…' }}
            </h2>
          </div>
          <button
            class="cv-iconbtn cv-iconbtn-lg flex-shrink-0"
            title="Fechar"
            @click="emit('close')"
          >
            <span class="i-lucide-x" />
          </button>
        </div>

        <div class="overflow-y-auto min-h-0 p-4 sm:p-8 space-y-8">
          <SkeletonScreen v-if="isLoading && !data" variant="dashboard" />
          <div
            v-else-if="error"
            class="cv-strip cv-red px-4 py-3 text-sm text-n-slate-11 flex items-center gap-2"
          >
            <span class="i-lucide-alert-triangle" />{{ error }}
          </div>
          <template v-else-if="data">
            <!-- 0. indicadores nomeados, juntos, logo no topo -->
            <section
              class="grid grid-cols-[repeat(auto-fit,minmax(10rem,1fr))] gap-2.5"
            >
              <div
                v-for="t in topTiles"
                :key="t.label"
                class="cv-sub rounded-2xl px-4 py-3 min-w-0"
                :class="t.money ? 'cv-sub-on' : ''"
              >
                <p
                  class="text-[11px] font-semibold text-n-slate-10 leading-tight flex items-center gap-1 flex-wrap"
                >
                  <span class="min-w-0">{{ t.label }}</span>
                  <span
                    v-if="t.band"
                    class="ml-auto"
                    :class="[BAND_META[t.band].icon, BAND_META[t.band].cls]"
                    :title="BAND_META[t.band].label"
                  />
                </p>
                <p
                  class="text-lg sm:text-xl font-extrabold tabular-nums tracking-tight leading-none mt-1 whitespace-nowrap"
                  :class="
                    t.value === '—' ? 'text-n-slate-8' : 'text-n-slate-12'
                  "
                >
                  {{ t.value }}
                </p>
              </div>
            </section>

            <!-- 1. ficha: mídia + copy + chips -->
            <section
              class="grid grid-cols-1 gap-6 md:grid-cols-[180px_minmax(0,1fr)]"
            >
              <div class="flex flex-col gap-4 min-w-0">
                <div
                  class="w-44 h-56 md:w-full md:h-[230px] rounded-3xl overflow-hidden bg-n-alpha-2 flex items-center justify-center"
                >
                  <img
                    v-if="data.thumbnail_url && !imgFailed"
                    :src="data.thumbnail_url"
                    :alt="data.ad_name"
                    class="w-full h-full object-cover"
                    @error="imgFailed = true"
                  />
                  <span
                    v-else
                    :class="FORMAT_ICON[data.format] || FORMAT_ICON.other"
                    class="text-4xl text-n-slate-9"
                  />
                </div>
              </div>
              <div class="min-w-0 flex flex-col gap-4">
                <div class="flex items-center gap-1.5 flex-wrap">
                  <span class="cv-chip"
                    ><span
                      :class="FORMAT_ICON[data.format]"
                      class="text-xs"
                    />{{ data.format_label }}</span
                  >
                  <span
                    class="inline-flex items-center gap-1 text-[11px] text-n-slate-10"
                    ><span
                      class="w-1.5 h-1.5 rounded-full"
                      :class="status.cls"
                    />{{ status.label }}</span
                  >
                  <span
v-if="diag.fatigue" class="cv-chip cv-amber"
                    ><span class="i-lucide-battery-low text-xs" />sinal de
                    fadiga</span
                  >
                  <span
v-if="data.simulated" class="cv-chip cv-slate"
                    >simulação</span
                  >
                  <span class="text-[11px] text-n-slate-9"
                    >{{ data.campaign_name }} · {{ data.adset_name }}</span
                  >
                </div>
                <div v-if="champions.length" class="flex flex-wrap gap-1.5">
                  <span
                    v-for="k in champions"
                    :key="k"
                    class="cv-champion-badge"
                  >
                    <span :class="CHAMPION_META[k].icon" />{{
                      CHAMPION_META[k].label
                    }}
                  </span>
                </div>
                <div class="rounded-3xl bg-n-alpha-1 p-6 space-y-3">
                  <p
                    class="text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold flex items-center gap-2 flex-wrap"
                  >
                    Gancho
                    <span
                      v-if="fromVideo"
                      class="cv-chip cv-green normal-case tracking-normal"
                      title="Transcrição do vídeo"
                      ><span class="i-lucide-clapperboard text-xs" />fala do
                      vídeo</span
                    >
                    <span
                      v-else-if="data.format === 'video'"
                      class="cv-chip cv-amber normal-case tracking-normal"
                      ><span class="i-lucide-file-text text-xs" />texto do
                      anúncio</span
                    >
                    <button
                      v-if="canTranscribe"
                      class="cv-btn cv-btn-sm cv-btn-ghost normal-case tracking-normal"
                      :disabled="isTranscribing"
                      @click="transcribeVideo"
                    >
                      <span class="i-lucide-sparkles text-xs" />
                      {{
                        transcriptProblem
                          ? 'Tentar de novo'
                          : 'Transcrever vídeo'
                      }}
                    </button>
                    <span
                      v-else-if="isWaitingTranscript"
                      class="normal-case tracking-normal text-n-slate-9 inline-flex items-center gap-1"
                    >
                      <span class="i-lucide-loader-circle animate-spin" />
                      transcrevendo… a tela atualiza sozinha
                    </span>
                    <span
                      v-if="transcriptProblem && !isWaitingTranscript"
                      class="normal-case tracking-normal text-red-600 basis-full"
                    >
                      não transcreveu: {{ transcriptProblem }}
                    </span>
                  </p>
                  <p
                    class="text-xl font-bold text-n-slate-12 leading-snug tracking-tight"
                  >
                    {{ data.hook || '—' }}
                  </p>
                  <p
                    class="text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold pt-2"
                  >
                    Corpo
                  </p>
                  <p
                    class="text-sm text-n-slate-11 whitespace-pre-line leading-relaxed"
                  >
                    {{ data.body || '—' }}
                  </p>
                  <div class="flex items-center gap-2 pt-2 flex-wrap">
                    <span
                      class="text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold"
                      >CTA</span
                    ><span class="cv-chip">{{ data.cta_label }}</span>
                    <span
v-if="data.video_cta" class="text-xs text-n-slate-11"
                      >· no vídeo: “{{ data.video_cta }}”</span
                    >
                  </div>
                  <div v-if="fromVideo" class="pt-2">
                    <button
                      class="cv-btn cv-btn-sm cv-btn-ghost"
                      @click="showTranscript = !showTranscript"
                    >
                      <span class="i-lucide-scroll-text text-xs" />{{
                        showTranscript
                          ? 'Esconder a transcrição'
                          : 'Ver a transcrição inteira'
                      }}
                    </button>
                    <p
                      v-if="showTranscript"
                      class="mt-3 text-sm text-n-slate-11 whitespace-pre-line leading-relaxed"
                    >
                      {{ data.transcript.text }}
                    </p>
                    <p
                      v-if="data.ad_hook || data.ad_body"
                      class="mt-3 text-[11px] text-n-slate-9"
                    >
                      Texto do anúncio na Meta: “{{ data.ad_hook || '—' }}” ·
                      {{ data.ad_body || '—' }}
                    </p>
                  </div>
                </div>
                <div class="flex gap-2 flex-wrap">
                  <button
                    class="cv-btn cv-btn-sm"
                    title="Copiar gancho, corpo e CTA"
                    @click="transcribe(data)"
                  >
                    <span class="i-lucide-copy text-sm" />Transcrever
                  </button>
                  <button
                    class="cv-btn cv-btn-sm"
                    title="Copia a análise inteira em texto limpo: leitura, números, curva, transcrição e textos do anúncio"
                    @click="copyAnalysis"
                  >
                    <span class="i-lucide-clipboard-list text-sm" />Copiar
                    análise completa
                  </button>
                  <button
                    class="cv-btn cv-btn-sm"
                    title="Gera um link só de leitura desta análise para mandar a outras pessoas"
                    :disabled="isSharing"
                    @click="showShareOptions = !showShareOptions"
                  >
                    <span
                      :class="
                        isSharing
                          ? 'i-lucide-loader-circle animate-spin'
                          : 'i-lucide-share-2'
                      "
                      class="text-sm"
                    />Compartilhar
                  </button>
                  <a
                    v-if="managerUrl"
                    :href="managerUrl"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="cv-btn cv-btn-sm cv-btn-ghost"
                    ><span
                      class="i-lucide-external-link text-sm"
                    />Gerenciador</a
                  >
                  <a
                    v-if="data.permalink"
                    :href="data.permalink"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="cv-btn cv-btn-sm cv-btn-ghost"
                    ><span class="i-lucide-instagram text-sm" />Instagram</a
                  >
                </div>
                <div
                  v-if="showShareOptions"
                  class="cv-sub rounded-2xl px-4 py-3.5 flex flex-col gap-3"
                >
                  <p class="text-sm font-bold text-n-slate-12">
                    Qual versão você quer compartilhar?
                  </p>
                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
                    <button
                      v-for="o in SHARE_OPTIONS"
                      :key="o.label"
                      type="button"
                      class="cd-share-option text-left"
                      :class="shareFinance === o.value ? 'cd-share-on' : ''"
                      :aria-pressed="shareFinance === o.value"
                      @click="shareFinance = o.value"
                    >
                      <span
                        class="flex items-center gap-2 text-sm font-bold text-n-slate-12"
                      >
                        <span :class="o.icon" class="text-base" />{{ o.label }}
                        <span
                          v-if="shareFinance === o.value"
                          class="i-lucide-circle-check ml-auto text-base"
                        />
                      </span>
                      <span
                        class="block text-xs text-n-slate-10 mt-1 leading-snug"
                        >{{ o.hint }}</span
                      >
                    </button>
                  </div>
                  <div class="flex items-center gap-2 flex-wrap">
                    <button
                      class="cv-btn cv-btn-sm"
                      :disabled="isSharing"
                      @click="share"
                    >
                      <span class="i-lucide-link text-sm" />Gerar link e copiar
                    </button>
                    <span class="text-[11px] text-n-slate-9">
                      A escolha fica gravada dentro do link: não dá para trocar
                      a versão mexendo no endereço.
                    </span>
                  </div>
                </div>
                <div
                  v-if="shareLink"
                  class="cd-share-ready px-4 py-3 flex flex-col gap-2"
                >
                  <p class="text-sm text-n-slate-12 leading-snug">
                    <span class="font-bold">Link só de leitura pronto.</span>
                    <span
                      class="cv-chip mx-1"
                      :class="shareLink.finance ? 'cv-amber' : 'cv-green'"
                      >{{ shareLink.finance_label }}</span
                    >
                    Este link vale até {{ shareLink.expires_label }} e mostra a
                    análise de {{ fmtDay(shareLink.since) }} a
                    {{ fmtDay(shareLink.until) }}. Quem abrir vê só os dados do
                    anúncio, sem nenhum dado de paciente.
                  </p>
                  <div class="flex gap-2 flex-wrap items-center">
                    <input
                      :value="shareLink.url"
                      readonly
                      class="cv-input flex-1 min-w-[12rem] text-xs"
                      @focus="$event.target.select()"
                    />
                    <button class="cv-btn cv-btn-sm" @click="copyShareUrl">
                      <span class="i-lucide-copy text-sm" />Copiar link
                    </button>
                    <a
                      :href="shareLink.url"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="cv-btn cv-btn-sm cv-btn-ghost"
                      ><span class="i-lucide-external-link text-sm" />Abrir</a
                    >
                  </div>
                </div>
              </div>
            </section>

            <!-- 2. o que vale dinheiro -->
            <section
              class="cv-block p-6 sm:p-8"
              :style="{ '--cv-grad': family[0] }"
            >
              <div class="flex items-center gap-2.5 mb-1 flex-wrap">
                <span class="cv-icon"
                  ><span class="i-lucide-badge-dollar-sign text-base"
                /></span>
                <h3
                  class="text-lg sm:text-xl font-bold text-n-slate-12 tracking-tight"
                >
                  O que vale dinheiro
                </h3>
              </div>
              <p class="text-xs text-n-slate-10 mb-5">
                jornada do CRM deste anúncio × investido, contra a média da
                conta no mesmo período
              </p>
              <MoneyTiles
                :rates="data.rates"
                :funnel="data.funnel"
                :averages="averages"
                :champions="data.champion_of || []"
              />
            </section>

            <!-- 2b. curva de retenção detalhada + cliques por marco (item 287) -->
            <section
              v-if="data.retention_detail"
              class="cv-block p-6 sm:p-8"
              :style="{ '--cv-grad': family[0] }"
            >
              <div class="flex items-center gap-2.5 mb-1">
                <span class="cv-icon"
                  ><span class="i-lucide-film text-base"
                /></span>
                <h3
                  class="text-lg sm:text-xl font-bold text-n-slate-12 tracking-tight"
                >
                  Curva de retenção
                </h3>
              </div>
              <RetentionArea
                :detail="data.retention_detail"
                :color="color(0)"
              />
            </section>
            <section
              v-if="data.retention_detail && data.retention_detail.clicks"
              class="cv-block p-6 sm:p-8"
              :style="{ '--cv-grad': family[2] }"
            >
              <div class="flex items-center gap-2.5 mb-1">
                <span class="cv-icon"
                  ><span class="i-lucide-mouse-pointer-click text-base"
                /></span>
                <h3
                  class="text-lg sm:text-xl font-bold text-n-slate-12 tracking-tight"
                >
                  Cliques por quem chegou até aqui
                </h3>
              </div>
              <ClicksByMark :clicks="data.retention_detail.clicks" />
            </section>

            <!-- 3. leitura + réguas + retenção -->
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <section
                class="cv-block p-6 sm:p-8"
                :style="{ '--cv-grad': family[1] }"
              >
                <div class="flex items-center gap-2.5 mb-1 flex-wrap">
                  <span class="cv-icon"
                    ><span class="i-lucide-sparkles text-base"
                  /></span>
                  <h3
                    class="text-lg sm:text-xl font-bold text-n-slate-12 tracking-tight"
                  >
                    Leitura
                  </h3>
                  <span v-if="FOCUS_META[diag.focus]" class="cv-chip ml-auto">{{
                    FOCUS_META[diag.focus]
                  }}</span>
                </div>
                <p class="text-base text-n-slate-12 leading-relaxed mb-6">
                  {{ diag.text }}
                </p>
                <div class="flex flex-col items-center gap-3 mb-6">
                  <CreativeRadar
                    :row="data"
                    env="detalhe"
                    :relative-ok="false"
                    :targets="targets"
                    :averages="averages"
                    :size="200"
                    show-average
                    legend
                  />
                  <RadarAxesPicker env="detalhe" :relative-ok="false" />
                </div>
              </section>

              <div class="flex flex-col gap-6">
                <section
                  v-if="!data.retention_detail && retentionSeries.length"
                  class="cv-block p-6 sm:p-8"
                  :style="{ '--cv-grad': family[0] }"
                >
                  <div class="flex items-center gap-2.5 mb-1">
                    <span class="cv-icon"
                      ><span class="i-lucide-film text-base"
                    /></span>
                    <h3
                      class="text-lg sm:text-xl font-bold text-n-slate-12 tracking-tight"
                    >
                      Curva de retenção
                    </h3>
                  </div>
                  <p class="text-xs text-n-slate-10 mb-1">
                    % das impressões que chegou a cada marco · tempo médio
                    assistido
                    {{ String(data.rates.avg_watch || 0).replace('.', ',') }} s
                  </p>
                  <p class="text-sm text-n-slate-12 mb-3">
                    {{ retentionReading }}
                  </p>
                  <RetentionCurve :series="retentionSeries" :height="200" />
                </section>

                <section
                  class="cv-block p-6 sm:p-8"
                  :style="{ '--cv-grad': family[2] }"
                >
                  <div class="flex items-center gap-2.5 mb-1">
                    <span class="cv-icon"
                      ><span class="i-lucide-scale text-base"
                    /></span>
                    <h3
                      class="text-lg sm:text-xl font-bold text-n-slate-12 tracking-tight"
                    >
                      1ª metade × 2ª metade
                    </h3>
                  </div>
                  <p class="text-xs text-n-slate-10 mb-4">
                    O período dividido ao meio. Queda de CTR com entrega mantida
                    é o sinal clássico de fadiga.
                  </p>
                  <ul class="divide-y divide-n-weak">
                    <li
                      v-for="r in halfRows"
                      :key="r.label"
                      class="py-2 flex items-center gap-3 text-sm"
                    >
                      <span class="text-n-slate-11 flex-1 min-w-0">{{
                        r.label
                      }}</span>
                      <span
                        class="tabular-nums text-n-slate-10 w-20 text-right"
                        >{{ r.a }}</span
                      >
                      <span
                        class="i-lucide-arrow-right text-[10px] text-n-slate-8"
                      />
                      <span
                        class="tabular-nums text-n-slate-12 font-semibold w-20 text-right"
                        >{{ r.b }}</span
                      >
                      <span
                        class="tabular-nums font-semibold w-16 text-right text-xs"
                        :class="
                          r.neutral ? 'text-n-slate-9' : deltaCls(r.d, r.lower)
                        "
                        >{{ fmtDelta(r.d) }}</span
                      >
                    </li>
                  </ul>
                </section>
              </div>
            </div>

            <!-- 3b. indicadores sem legenda (rodada 2): Barras | Linha -->
            <section
              v-if="scorecard.indicators.length"
              class="cv-block p-6 sm:p-8"
              :style="{ '--cv-grad': family[3] }"
            >
              <div class="flex items-center gap-2 flex-wrap mb-3">
                <span class="cv-icon"
                  ><span class="i-lucide-gauge text-base"
                /></span>
                <div class="min-w-0">
                  <h3
                    class="text-lg sm:text-xl font-bold text-n-slate-12 tracking-tight"
                  >
                    Indicadores
                  </h3>
                  <p class="text-xs text-n-slate-10">
                    este anúncio contra a média da conta (para superar) e o
                    recorde da conta (para ir buscar)
                  </p>
                </div>
                <div class="cd-seg ml-auto" role="group">
                  <button
                    type="button"
                    :class="metersView === 'bars' ? 'cd-seg-on' : ''"
                    @click="setMetersView('bars')"
                  >
                    <span class="i-lucide-align-left text-xs" />Barras
                  </button>
                  <button
                    type="button"
                    :class="metersView === 'line' ? 'cd-seg-on' : ''"
                    @click="setMetersView('line')"
                  >
                    <span class="i-lucide-chart-line text-xs" />Linha
                  </button>
                </div>
              </div>
              <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
                <VerdictBars
                  v-for="i in scorecard.indicators"
                  :key="i.key"
                  :indicator="i"
                  :view="metersView"
                  :values="dailyOf(i.key)"
                  :labels="labels"
                />
              </div>
            </section>

            <!-- 4. números da Meta -->
            <section
              class="cv-block p-6 sm:p-8"
              :style="{ '--cv-grad': family[3] }"
            >
              <div class="flex items-center gap-2.5 mb-5">
                <span class="cv-icon"
                  ><span class="i-lucide-gauge text-base"
                /></span>
                <h3
                  class="text-lg sm:text-xl font-bold text-n-slate-12 tracking-tight"
                >
                  Números da Meta
                </h3>
              </div>
              <div
                class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-2.5"
              >
                <div
                  v-for="t in metaTiles"
                  :key="t.label"
                  class="cv-sub rounded-2xl px-4 py-3.5"
                >
                  <p class="text-[10px] text-n-slate-9 flex items-center gap-1">
                    {{ t.label }}
                    <span
                      v-if="t.band"
                      class="inline-flex items-center gap-0.5 ml-auto font-semibold"
                      :class="BAND_META[t.band].cls"
                      ><span :class="BAND_META[t.band].icon" />{{
                        BAND_META[t.band].label
                      }}</span
                    >
                  </p>
                  <p
                    class="text-xl font-extrabold text-n-slate-12 tabular-nums tracking-tight"
                  >
                    {{ t.value }}
                  </p>
                  <p
                    v-if="t.d !== null && t.d !== undefined"
                    class="text-[10px] font-semibold"
                    :class="
                      t.neutral ? 'text-n-slate-9' : deltaCls(t.d, t.lower)
                    "
                  >
                    {{ fmtDelta(t.d) }} vs anterior
                  </p>
                  <p v-else-if="t.sub" class="text-[10px] text-n-slate-9">
                    {{ t.sub }}
                  </p>
                </div>
              </div>
            </section>

            <!-- 4b. mais análises: teia (este anúncio × média × recorde) e linhas das taxas -->
            <section
              v-if="scorecard.radar && scorecard.radar.axes.length >= 3"
              class="cv-block p-6 sm:p-8"
              :style="{ '--cv-grad': family[0] }"
            >
              <div class="flex items-center gap-2.5 mb-1">
                <span class="cv-icon"
                  ><span class="i-lucide-radar text-base"
                /></span>
                <h3
                  class="text-lg sm:text-xl font-bold text-n-slate-12 tracking-tight"
                >
                  Este criativo × média × recorde da conta
                </h3>
              </div>
              <p class="text-xs text-n-slate-10 mb-4">
                Do gancho ao agendamento em uma figura só. A borda de fora é o
                recorde da conta: a ponta mais curta é onde há mais para buscar.
              </p>
              <ScoreRadar :radar="scorecard.radar" :color="color(0)" />
            </section>

            <section
              v-if="lineCharts.length"
              class="cv-block p-6 sm:p-8"
              :style="{ '--cv-grad': family[1] }"
            >
              <div class="flex items-center gap-2.5 mb-1">
                <span class="cv-icon"
                  ><span class="i-lucide-chart-line text-base"
                /></span>
                <h3
                  class="text-lg sm:text-xl font-bold text-n-slate-12 tracking-tight"
                >
                  Taxas principais, dia a dia
                </h3>
              </div>
              <p class="text-xs text-n-slate-10 mb-4">
                Linha cheia = este anúncio · tracejada = média da conta ·
                pontilhada dourada = recorde da conta.
              </p>
              <div class="grid grid-cols-1 md:grid-cols-3 gap-5">
                <div v-for="c in lineCharts" :key="c.key" class="min-w-0">
                  <p class="text-sm font-semibold text-n-slate-12">
                    {{ c.label }}
                    <span class="font-normal text-n-slate-10"
                      >· {{ c.metric }}</span
                    >
                  </p>
                  <p class="text-[11px] text-n-slate-9 mb-1">
                    no período: {{ c.value_text }} · {{ c.phrase }}
                  </p>
                  <RateLine
                    :values="c.values"
                    :labels="labels"
                    :avg="c.avg"
                    :record="c.record"
                    :color="c.color"
                    :format="c.format"
                  />
                </div>
              </div>
            </section>

            <!-- 5. ritmo dia a dia -->
            <section
              class="cv-block p-6 sm:p-8"
              :style="{ '--cv-grad': family[1] }"
            >
              <div class="flex items-center gap-2.5 mb-1">
                <span class="cv-icon"
                  ><span class="i-lucide-activity text-base"
                /></span>
                <h3
                  class="text-lg sm:text-xl font-bold text-n-slate-12 tracking-tight"
                >
                  Ritmo dia a dia
                </h3>
              </div>
              <p class="text-xs text-n-slate-10 mb-5">
                Linha tracejada = média da conta · linha pontilhada = parâmetro
                bom
              </p>
              <div class="grid grid-cols-1 md:grid-cols-2 gap-x-8 gap-y-6">
                <div>
                  <p class="text-sm font-semibold text-n-slate-12">
                    CTR de link (%)
                  </p>
                  <p class="text-[11px] text-n-slate-9 mb-1">
                    {{ readSeries(ctrSeries, pctFmt) }}
                  </p>
                  <MiniBars
                    :values="ctrSeries"
                    :labels="labels"
                    :color="color(1)"
                    :height="100"
                    :reference="avgCtrPct"
                    :format="v => `${String(v).replace('.', ',')}%`"
                  />
                </div>
                <div v-if="isVideo">
                  <p class="text-sm font-semibold text-n-slate-12">
                    Taxa de parada (%)
                  </p>
                  <p class="text-[11px] text-n-slate-9 mb-1">
                    {{
                      readSeries(
                        hookSeries,
                        v => `${Number(v).toFixed(1).replace('.', ',')}%`
                      )
                    }}
                  </p>
                  <MiniBars
                    :values="hookSeries"
                    :labels="labels"
                    :color="color(0)"
                    :height="100"
                    :goal="hookGoalPct"
                    :format="v => `${String(v).replace('.', ',')}%`"
                  />
                </div>
                <div>
                  <p class="text-sm font-semibold text-n-slate-12">
                    Conversas iniciadas
                  </p>
                  <p class="text-[11px] text-n-slate-9 mb-1">
                    {{ readSeries(convSeries, v => `${Math.round(v)}`) }}
                  </p>
                  <MiniBars
                    :values="convSeries"
                    :labels="labels"
                    :color="color(3)"
                    :height="100"
                    :format="v => `${v} conv.`"
                  />
                </div>
                <div>
                  <p class="text-sm font-semibold text-n-slate-12">
                    Investimento (R$)
                  </p>
                  <p class="text-[11px] text-n-slate-9 mb-1">
                    {{ readSeries(spendSeries, v => fmtMoney(v)) }}
                  </p>
                  <MiniBars
                    :values="spendSeries"
                    :labels="labels"
                    :color="color(2)"
                    :height="100"
                    :format="v => fmtMoney(v)"
                  />
                </div>
              </div>
            </section>

            <!-- 6. onde apareceu / quem viu -->
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <section
                class="cv-block p-6 sm:p-8"
                :style="{ '--cv-grad': family[3] }"
              >
                <div class="flex items-center gap-2.5 mb-1">
                  <span class="cv-icon"
                    ><span class="i-lucide-layout-grid text-base"
                  /></span>
                  <h3
                    class="text-lg sm:text-xl font-bold text-n-slate-12 tracking-tight"
                  >
                    Onde apareceu: os mais e os menos
                  </h3>
                </div>
                <p class="text-xs text-n-slate-10 mb-3">
                  De onde vem: a Meta separa o resultado por lugar onde o
                  anúncio foi mostrado. Do melhor para o pior.
                </p>
                <p
                  v-if="data.placements && data.placements.error"
                  class="text-[11px] text-red-600"
                >
                  {{ data.placements.error }}
                </p>
                <BreakdownRanking
                  :ranking="data.placement_ranking"
                  empty-text="sem quebra por posicionamento no período"
                />
              </section>
              <section
                class="cv-block p-6 sm:p-8"
                :style="{ '--cv-grad': family[1] }"
              >
                <div class="flex items-center gap-2.5 mb-1">
                  <span class="cv-icon"
                    ><span class="i-lucide-users text-base"
                  /></span>
                  <h3
                    class="text-lg sm:text-xl font-bold text-n-slate-12 tracking-tight"
                  >
                    Quem viu: os mais e os menos
                  </h3>
                </div>
                <p class="text-xs text-n-slate-10 mb-3">
                  De onde vem: a Meta separa o resultado por idade e sexo de
                  quem recebeu o anúncio. Do melhor para o pior.
                </p>
                <p
                  v-if="data.age_gender && data.age_gender.error"
                  class="text-[11px] text-red-600"
                >
                  {{ data.age_gender.error }}
                </p>
                <BreakdownRanking
                  :ranking="data.audience_ranking"
                  empty-text="sem quebra por idade e sexo no período"
                />
              </section>
            </div>

            <!-- 7. peças do criativo dinâmico -->
            <section
              v-if="data.assets"
              class="cv-block p-6 sm:p-8"
              :style="{ '--cv-grad': family[2] }"
            >
              <div class="flex items-center gap-2.5 mb-1">
                <span class="cv-icon"
                  ><span class="i-lucide-shuffle text-base"
                /></span>
                <h3
                  class="text-lg sm:text-xl font-bold text-n-slate-12 tracking-tight"
                >
                  Gancho, corpo e CTA como peças separadas
                </h3>
              </div>
              <p class="text-xs text-n-slate-10 mb-4">
                A Meta testa as combinações sozinha; aqui cada peça aparece com
                o próprio resultado.
              </p>
              <div class="grid grid-cols-1 xl:grid-cols-3 gap-6">
                <div>
                  <p class="text-sm font-semibold text-n-slate-12 mb-1">
                    Ganchos
                  </p>
                  <AssetTable
                    :rows="bkRows(data.assets.titles)"
                    :color="color(0)"
                    label-header="Gancho"
                  />
                </div>
                <div>
                  <p class="text-sm font-semibold text-n-slate-12 mb-1">
                    Corpos
                  </p>
                  <AssetTable
                    :rows="bkRows(data.assets.bodies)"
                    :color="color(1)"
                    label-header="Corpo"
                  />
                </div>
                <div>
                  <p class="text-sm font-semibold text-n-slate-12 mb-1">CTAs</p>
                  <AssetTable
                    :rows="bkRows(data.assets.ctas)"
                    :color="color(2)"
                    label-header="CTA"
                  />
                </div>
              </div>
            </section>
          </template>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
/* título BRANCO no cabeçalho colorido do modal (pedido 29/09): a regra geral
   do sistema para h1–h6 (_base.scss) pinta de escuro e vence as classes de
   cor; aqui a cor é fixada só neste modal */
.cv-modal-head .cd-head-title {
  color: #fff;
}
.cv-modal-head .cd-head-sub {
  color: rgb(255 255 255 / 0.82);
}
.cd-share-option {
  border-radius: 16px;
  padding: 12px 14px;
  border: 1.5px solid rgb(var(--cv-rgb) / 0.22);
  background: rgb(var(--cv-rgb) / 0.04);
  cursor: pointer;
  transition:
    border-color 0.15s ease,
    background 0.15s ease;
}
.cd-share-option:hover {
  border-color: rgb(var(--cv-rgb) / 0.5);
}
.cd-share-on {
  border-color: rgb(var(--cv-rgb) / 0.85);
  background: rgb(var(--cv-rgb) / 0.12);
  box-shadow: 0 0 0 3px rgb(var(--cv-rgb) / 0.12);
}
.cd-share-ready {
  border-radius: 16px;
  border: 1px solid rgb(5 150 105 / 0.3);
  border-left: 4px solid #059669;
  background: rgb(5 150 105 / 0.09);
}
.cd-seg {
  display: inline-flex;
  padding: 2px;
  border-radius: 9999px;
  border: 1px solid rgb(var(--cv-rgb) / 0.25);
  background: rgb(var(--cv-rgb) / 0.06);
}
.cd-seg button {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  height: 24px;
  padding: 0 10px;
  border-radius: 9999px;
  font-size: 11px;
  font-weight: 600;
  cursor: pointer;
  color: inherit;
}
.cd-seg .cd-seg-on {
  color: #fff;
  background: var(--cv);
}
</style>
