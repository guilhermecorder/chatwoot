<script setup>
// "Ver a fundo" (item 172, rodada 2): modal SÓLIDO do kit (cv-modal) com
// seções que se leem de cima para baixo — ficha, leitura com as quatro
// réguas, ritmo dia a dia (um eixo por gráfico, linha da média e do
// parâmetro), 1ª × 2ª metade, curva de retenção contra a média da conta,
// onde apareceu, quem viu e as peças do criativo dinâmico.
import { ref, computed, watch, onMounted } from 'vue';
import CevicoCreativesAPI from 'dashboard/api/cevicoCreatives';
import MiniBars from 'dashboard/components-next/cevico/MiniBars.vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import { hexFromGrad } from 'dashboard/helper/cevicoPalettes';
import BulletMeter from './BulletMeter.vue';
import RetentionCurve from './RetentionCurve.vue';
import AssetTable from './AssetTable.vue';
import CreativeRadar from './CreativeRadar.vue';
import RadarAxesPicker from './RadarAxesPicker.vue';
import { useTranscribe } from './useTranscribe';
import {
  fmtMoney,
  fmtCompact,
  fmtPct,
  fmtNum,
  statusMeta,
  FORMAT_ICON,
  METRIC_DEFS,
  FOCUS_META,
  BAND_META,
  delta,
  fmtDelta,
  deltaCls,
} from './creativeFormat';

const { transcribe } = useTranscribe();
const props = defineProps({
  adId: { type: String, required: true },
  periodParams: { type: Object, default: () => ({}) },
  family: { type: Array, default: () => [] },
  cvVars: { type: Object, default: () => ({}) },
  adAccountId: { type: String, default: '' },
});
const emit = defineEmits(['close']);

const data = ref(null);
const isLoading = ref(false);
const error = ref('');
const imgFailed = ref(false);

const load = async () => {
  isLoading.value = true;
  error.value = '';
  try {
    const { data: response } = await CevicoCreativesAPI.show(
      props.adId,
      props.periodParams
    );
    data.value = response;
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
const vsAvg = computed(() => diag.value.vs_avg || {});
const prev = computed(() => (data.value && data.value.prev) || null);
const meters = computed(() =>
  METRIC_DEFS.filter(m => isVideo.value || !m.video)
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
</script>

<template>
  <Teleport to="body">
    <div
      class="cv-page fixed inset-0 z-[60] flex items-start sm:items-center justify-center bg-black/60 p-2 sm:p-6"
      :style="cvVars"
      @click.self="emit('close')"
    >
      <div class="cv-modal w-full max-w-6xl max-h-[95vh] flex flex-col">
        <!-- cabeçalho do kit -->
        <div class="cv-modal-head flex items-center gap-3">
          <span class="cv-icon cv-icon-lg"
            ><span
              :class="FORMAT_ICON[(data && data.format) || 'other']"
              class="text-lg"
          /></span>
          <div class="min-w-0 flex-1">
            <p class="text-[11px] opacity-80">Ver a fundo</p>
            <h2 class="text-base font-bold leading-snug">
              {{ data ? data.ad_name : 'Carregando…' }}
            </h2>
          </div>
          <button
            class="cv-iconbtn cv-iconbtn-lg"
            title="Fechar"
            @click="emit('close')"
          >
            <span class="i-lucide-x" />
          </button>
        </div>

        <div class="overflow-y-auto min-h-0 p-4 sm:p-6 space-y-5">
          <SkeletonScreen v-if="isLoading && !data" variant="dashboard" />
          <div
            v-else-if="error"
            class="cv-strip cv-red px-4 py-3 text-sm text-n-slate-11 flex items-center gap-2"
          >
            <span class="i-lucide-alert-triangle" />{{ error }}
          </div>
          <template v-else-if="data">
            <!-- 1. ficha -->
            <section class="grid gap-5 md:grid-cols-[200px_minmax(0,1fr)]">
              <div class="flex flex-col gap-3 min-w-0">
                <div
                  class="w-40 h-52 md:w-full md:h-[250px] rounded-2xl overflow-hidden bg-n-alpha-2 flex items-center justify-center"
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
                <!-- teia deste criativo × média da conta -->
                <CreativeRadar
                  :row="data"
                  env="detalhe"
                  :relative-ok="false"
                  :targets="targets"
                  :averages="averages"
                  :size="184"
                  show-average
                  legend
                  class="self-center"
                />
                <RadarAxesPicker env="detalhe" :relative-ok="false" />
              </div>
              <div class="min-w-0">
                <div class="flex items-center gap-1.5 flex-wrap mb-2">
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
                  <span v-if="diag.fatigue" class="cv-chip cv-amber"
                    ><span class="i-lucide-battery-low text-xs" />sinal de
                    fadiga</span
                  >
                  <span v-if="data.simulated" class="cv-chip cv-slate"
                    >simulação</span
                  >
                  <span class="text-[11px] text-n-slate-9"
                    >{{ data.campaign_name }} · {{ data.adset_name }}</span
                  >
                  <span class="ml-auto flex gap-2 flex-wrap">
                    <button
                      class="cv-btn cv-btn-sm cv-btn-ghost"
                      title="Copiar gancho, corpo e CTA"
                      @click="transcribe(data)"
                    >
                      <span class="i-lucide-copy text-sm" />Transcrever
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
                  </span>
                </div>
                <div class="rounded-2xl bg-n-alpha-1 p-4 space-y-2">
                  <p
                    class="text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold"
                  >
                    Gancho
                  </p>
                  <p class="text-lg font-bold text-n-slate-12 leading-snug">
                    {{ data.hook || '—' }}
                  </p>
                  <p
                    class="text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold pt-1"
                  >
                    Corpo
                  </p>
                  <p
                    class="text-sm text-n-slate-11 whitespace-pre-line leading-relaxed"
                  >
                    {{ data.body || '—' }}
                  </p>
                  <div class="flex items-center gap-2 pt-1">
                    <span
                      class="text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold"
                      >CTA</span
                    ><span class="cv-chip">{{ data.cta_label }}</span>
                  </div>
                </div>
              </div>
            </section>

            <!-- 2. leitura -->
            <section class="cv-block p-5" :style="{ '--cv-grad': family[0] }">
              <div class="flex items-center gap-2 mb-3 flex-wrap">
                <span class="cv-icon"
                  ><span class="i-lucide-sparkles text-base"
                /></span>
                <h3 class="text-sm font-bold text-n-slate-12">Leitura</h3>
                <span v-if="FOCUS_META[diag.focus]" class="cv-chip">{{
                  FOCUS_META[diag.focus]
                }}</span>
              </div>
              <p class="text-base text-n-slate-12 leading-relaxed mb-5">
                {{ diag.text }}
              </p>
              <div class="grid gap-x-8 gap-y-5 md:grid-cols-2">
                <BulletMeter
                  v-for="(m, i) in meters"
                  :key="m.key"
                  :label="m.label"
                  :metric="m.metric"
                  :hint="m.hint"
                  :value="data.rates[m.key]"
                  :avg="averages[m.key]"
                  :prev="prev ? prev[m.key] : null"
                  :band="bands[m.band]"
                  :vs-avg="vsAvg[m.band]"
                  :target="targets[m.key]"
                  :digits="m.digits"
                  :money="!!m.money"
                  :color="color(i % 4)"
                />
              </div>
              <div
                class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-2 mt-5"
              >
                <div class="cv-sub rounded-xl px-3 py-2">
                  <p class="text-[10px] text-n-slate-9">Investido</p>
                  <p class="text-base font-bold text-n-slate-12">
                    {{ fmtMoney(data.totals.spend) }}
                  </p>
                  <p v-if="prev" class="text-[10px] text-n-slate-9">
                    {{ fmtDelta(delta(data.totals.spend, prev.spend)) }} vs
                    anterior
                  </p>
                </div>
                <div class="cv-sub rounded-xl px-3 py-2">
                  <p class="text-[10px] text-n-slate-9">Impressões</p>
                  <p class="text-base font-bold text-n-slate-12">
                    {{ fmtCompact(data.totals.impressions) }}
                  </p>
                  <p v-if="prev" class="text-[10px] text-n-slate-9">
                    {{
                      fmtDelta(delta(data.totals.impressions, prev.impressions))
                    }}
                    vs anterior
                  </p>
                </div>
                <div class="cv-sub rounded-xl px-3 py-2">
                  <p class="text-[10px] text-n-slate-9">Alcance real</p>
                  <p class="text-base font-bold text-n-slate-12">
                    {{
                      fmtCompact(
                        data.summary ? data.summary.reach : data.totals.reach
                      )
                    }}
                  </p>
                  <p class="text-[10px] text-n-slate-9">pessoas no período</p>
                </div>
                <div class="cv-sub rounded-xl px-3 py-2">
                  <p class="text-[10px] text-n-slate-9">Frequência</p>
                  <p class="text-base font-bold text-n-slate-12">
                    {{
                      data.summary && data.summary.frequency
                        ? String(data.summary.frequency).replace('.', ',')
                        : '—'
                    }}
                  </p>
                  <p class="text-[10px] text-n-slate-9">vezes por pessoa</p>
                </div>
                <div class="cv-sub rounded-xl px-3 py-2">
                  <p class="text-[10px] text-n-slate-9">Conversas</p>
                  <p class="text-base font-bold text-n-slate-12">
                    {{ fmtNum(data.totals.conversations) }}
                  </p>
                  <p
                    v-if="prev"
                    class="text-[10px] font-semibold"
                    :class="
                      deltaCls(
                        delta(data.totals.conversations, prev.conversations)
                      )
                    "
                  >
                    {{
                      fmtDelta(
                        delta(data.totals.conversations, prev.conversations)
                      )
                    }}
                    vs anterior
                  </p>
                </div>
                <div class="cv-sub rounded-xl px-3 py-2">
                  <p class="text-[10px] text-n-slate-9">Jornada no CRM</p>
                  <p class="text-xs font-semibold text-n-slate-12 leading-snug">
                    {{ data.funnel.leads }} leads ·
                    {{ data.funnel.booked }} consultas ·
                    {{ data.funnel.surgeries }} cirurgias
                  </p>
                  <p
                    v-if="data.funnel.revenue"
                    class="text-[10px] text-n-slate-9"
                  >
                    {{ fmtMoney(data.funnel.revenue) }}
                  </p>
                </div>
              </div>
            </section>

            <div class="grid lg:grid-cols-2 gap-5">
              <!-- 3. ritmo -->
              <section class="cv-block p-5" :style="{ '--cv-grad': family[1] }">
                <div class="flex items-center gap-2 mb-1">
                  <span class="cv-icon"
                    ><span class="i-lucide-activity text-base"
                  /></span>
                  <h3 class="text-sm font-bold text-n-slate-12">
                    Ritmo dia a dia
                  </h3>
                </div>
                <p class="text-[11px] text-n-slate-9 mb-3">
                  Linha tracejada = média da conta · linha pontilhada =
                  parâmetro bom
                </p>
                <p class="text-xs font-semibold text-n-slate-11">
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
                <template v-if="isVideo">
                  <p class="text-xs font-semibold text-n-slate-11 mt-4">
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
                    :height="90"
                    :goal="hookGoalPct"
                    :format="v => `${String(v).replace('.', ',')}%`"
                  />
                </template>
                <p class="text-xs font-semibold text-n-slate-11 mt-4">
                  Conversas iniciadas
                </p>
                <p class="text-[11px] text-n-slate-9 mb-1">
                  {{ readSeries(convSeries, v => `${Math.round(v)}`) }}
                </p>
                <MiniBars
                  :values="convSeries"
                  :labels="labels"
                  :color="color(3)"
                  :height="90"
                  :format="v => `${v} conv.`"
                />
                <p class="text-xs font-semibold text-n-slate-11 mt-4">
                  Investimento (R$)
                </p>
                <p class="text-[11px] text-n-slate-9 mb-1">
                  {{ readSeries(spendSeries, v => fmtMoney(v)) }}
                </p>
                <MiniBars
                  :values="spendSeries"
                  :labels="labels"
                  :color="color(2)"
                  :height="90"
                  :format="v => fmtMoney(v)"
                />
              </section>

              <div class="space-y-5">
                <!-- 4. metades -->
                <section
                  class="cv-block p-5"
                  :style="{ '--cv-grad': family[2] }"
                >
                  <div class="flex items-center gap-2 mb-1">
                    <span class="cv-icon"
                      ><span class="i-lucide-scale text-base"
                    /></span>
                    <h3 class="text-sm font-bold text-n-slate-12">
                      Primeira metade × segunda metade
                    </h3>
                  </div>
                  <p class="text-[11px] text-n-slate-9 mb-3">
                    O período dividido ao meio. Queda de CTR com entrega mantida
                    é o sinal clássico de fadiga.
                  </p>
                  <table class="w-full text-xs">
                    <thead>
                      <tr
                        class="text-[10px] uppercase tracking-wide text-n-slate-9"
                      >
                        <th class="text-left font-semibold py-1">Métrica</th>
                        <th class="text-right font-semibold">1ª metade</th>
                        <th class="text-right font-semibold">2ª metade</th>
                        <th class="text-right font-semibold">Variação</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr
                        v-for="r in halfRows"
                        :key="r.label"
                        class="border-t border-n-weak"
                      >
                        <td class="py-1.5 text-n-slate-11">{{ r.label }}</td>
                        <td
                          class="py-1.5 text-right tabular-nums text-n-slate-11"
                        >
                          {{ r.a }}
                        </td>
                        <td
                          class="py-1.5 text-right tabular-nums text-n-slate-12 font-semibold"
                        >
                          {{ r.b }}
                        </td>
                        <td
                          class="py-1.5 text-right tabular-nums font-semibold"
                          :class="
                            r.neutral
                              ? 'text-n-slate-9'
                              : deltaCls(r.d, r.lower)
                          "
                        >
                          {{ fmtDelta(r.d) }}
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </section>

                <!-- 5. retenção -->
                <section
                  v-if="retentionSeries.length"
                  class="cv-block p-5"
                  :style="{ '--cv-grad': family[0] }"
                >
                  <div class="flex items-center gap-2 mb-1">
                    <span class="cv-icon"
                      ><span class="i-lucide-film text-base"
                    /></span>
                    <h3 class="text-sm font-bold text-n-slate-12">
                      Curva de retenção
                    </h3>
                  </div>
                  <p class="text-[11px] text-n-slate-9 mb-1">
                    % das impressões que chegou a cada marco · tempo médio
                    assistido
                    {{ String(data.rates.avg_watch || 0).replace('.', ',') }} s
                  </p>
                  <p class="text-xs text-n-slate-12 mb-2">
                    {{ retentionReading }}
                  </p>
                  <RetentionCurve :series="retentionSeries" :height="190" />
                </section>
              </div>
            </div>

            <!-- 6. onde apareceu / quem viu -->
            <div class="grid lg:grid-cols-2 gap-5">
              <section class="cv-block p-5" :style="{ '--cv-grad': family[3] }">
                <div class="flex items-center gap-2 mb-1">
                  <span class="cv-icon"
                    ><span class="i-lucide-layout-grid text-base"
                  /></span>
                  <h3 class="text-sm font-bold text-n-slate-12">
                    Onde apareceu
                  </h3>
                </div>
                <p class="text-[11px] text-n-slate-9 mb-2">
                  Posicionamento na Meta. O melhor e o pior custo por conversa
                  ficam marcados.
                </p>
                <p
                  v-if="data.placements && data.placements.error"
                  class="text-[11px] text-red-600"
                >
                  {{ data.placements.error }}
                </p>
                <AssetTable
                  :rows="bkRows(data.placements)"
                  :color="color(3)"
                  label-header="Posicionamento"
                  :video="isVideo"
                  empty-text="sem quebra por posicionamento no período"
                />
              </section>
              <section class="cv-block p-5" :style="{ '--cv-grad': family[1] }">
                <div class="flex items-center gap-2 mb-1">
                  <span class="cv-icon"
                    ><span class="i-lucide-users text-base"
                  /></span>
                  <h3 class="text-sm font-bold text-n-slate-12">Quem viu</h3>
                </div>
                <p class="text-[11px] text-n-slate-9 mb-2">
                  Idade e sexo de quem recebeu o anúncio.
                </p>
                <p
                  v-if="data.age_gender && data.age_gender.error"
                  class="text-[11px] text-red-600"
                >
                  {{ data.age_gender.error }}
                </p>
                <AssetTable
                  :rows="bkRows(data.age_gender)"
                  :color="color(1)"
                  label-header="Faixa"
                  :video="isVideo"
                  empty-text="sem quebra por idade e sexo no período"
                />
              </section>
            </div>

            <!-- 7. peças do criativo dinâmico -->
            <section
              v-if="data.assets"
              class="cv-block p-5"
              :style="{ '--cv-grad': family[2] }"
            >
              <div class="flex items-center gap-2 mb-1">
                <span class="cv-icon"
                  ><span class="i-lucide-shuffle text-base"
                /></span>
                <h3 class="text-sm font-bold text-n-slate-12">
                  Gancho, corpo e CTA como peças separadas
                </h3>
              </div>
              <p class="text-[11px] text-n-slate-9 mb-3">
                A Meta testa as combinações sozinha; aqui cada peça aparece com
                o próprio resultado.
              </p>
              <div class="grid xl:grid-cols-3 gap-5">
                <div>
                  <p class="text-xs font-semibold text-n-slate-11 mb-1">
                    Ganchos
                  </p>
                  <AssetTable
                    :rows="bkRows(data.assets.titles)"
                    :color="color(0)"
                    label-header="Gancho"
                  />
                </div>
                <div>
                  <p class="text-xs font-semibold text-n-slate-11 mb-1">
                    Corpos
                  </p>
                  <AssetTable
                    :rows="bkRows(data.assets.bodies)"
                    :color="color(1)"
                    label-header="Corpo"
                  />
                </div>
                <div>
                  <p class="text-xs font-semibold text-n-slate-11 mb-1">CTAs</p>
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
