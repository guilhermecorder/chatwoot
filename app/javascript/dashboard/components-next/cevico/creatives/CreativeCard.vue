<script setup>
// FICHA COMPLETA de um criativo (item 172 · v2 item 177): o que vale
// dinheiro em cima (custo por consulta, custo por cirurgia, ROAS, %
// agendamento), a curva de retenção em todo vídeo, depois copy, leitura,
// réguas e números da Meta. Layout "de celular" sempre — 2 fichas lado a
// lado no desktop; o que muda de tamanho responde à largura da FICHA
// (container queries `.cv-cq-*` no kit), não à da janela.
import { computed, ref } from 'vue';
import MiniBars from 'dashboard/components-next/cevico/MiniBars.vue';
import BulletMeter from './BulletMeter.vue';
import CreativeRadar from './CreativeRadar.vue';
import MoneyTiles from './MoneyTiles.vue';
import RetentionCurve from './RetentionCurve.vue';
import { useTranscribe } from './useTranscribe';
import {
  fmtMoney,
  fmtCompact,
  fmtNum,
  statusMeta,
  FORMAT_ICON,
  METRIC_DEFS,
  FOCUS_META,
  BAND_META,
  CHAMPION_META,
  delta,
  fmtDelta,
  deltaCls,
} from './creativeFormat';

const props = defineProps({
  row: { type: Object, required: true },
  averages: { type: Object, default: () => ({}) },
  targets: { type: Object, default: () => ({}) },
  family: { type: Array, default: () => [] },
  accent: { type: String, default: '#0F5FA6' },
  compareMode: { type: Boolean, default: false },
  selected: { type: Boolean, default: false },
  peers: { type: Array, default: () => [] }, // os outros criativos do recorte (teia)
});
const emit = defineEmits(['open', 'toggle', 'transcribe-video']);
const { transcribe } = useTranscribe();
// 🎬 item 181: gancho/corpo vêm da fala do vídeo quando há transcrição
const fromVideo = computed(() => props.row.text_source === 'video');
const transcriptStatus = computed(
  () => (props.row.transcript && props.row.transcript.status) || ''
);
const canTranscribe = computed(
  () =>
    props.row.format === 'video' &&
    !fromVideo.value &&
    !['queued', 'processing'].includes(transcriptStatus.value)
);

const imgFailed = ref(false);
const champions = computed(() =>
  (props.row.champion_of || []).filter(k => CHAMPION_META[k])
);
const isChampion = computed(() => champions.value.length > 0);
const isVideo = computed(
  () =>
    props.row.rates.hook_rate !== null &&
    props.row.rates.hook_rate !== undefined
);
const status = computed(() => statusMeta(props.row.status));
const diag = computed(() => props.row.diagnosis || {});
const bands = computed(() => diag.value.bands || {});
const vsAvg = computed(() => diag.value.vs_avg || {});
const prev = computed(() => props.row.prev || null);
const grad = i => props.family[i] || 'var(--cv-grad-2)';
const meters = computed(() =>
  METRIC_DEFS.filter(
    m => (isVideo.value || !m.video) && m.key !== 'cost_conversation'
  )
);
const focusLabel = computed(() => FOCUS_META[diag.value.focus] || '');
const worstBand = computed(() => {
  const order = ['ruim', 'atencao', 'bom'];
  const vals = Object.values(bands.value).filter(Boolean);
  return vals.sort((a, b) => order.indexOf(a) - order.indexOf(b))[0] || null;
});
const kpis = computed(() => [
  {
    label: 'Investido',
    value: fmtMoney(props.row.totals.spend),
    d: delta(props.row.totals.spend, prev.value && prev.value.spend),
    neutral: true,
  },
  {
    label: 'Impressões',
    value: fmtCompact(props.row.totals.impressions),
    d: delta(
      props.row.totals.impressions,
      prev.value && prev.value.impressions
    ),
    neutral: true,
  },
  {
    label: 'Conversas',
    value: fmtNum(props.row.totals.conversations),
    d: delta(
      props.row.totals.conversations,
      prev.value && prev.value.conversations
    ),
  },
  {
    label: 'Custo por conversa',
    value: props.row.rates.cost_conversation
      ? fmtMoney(props.row.rates.cost_conversation)
      : '—',
    d: delta(
      props.row.rates.cost_conversation,
      prev.value && prev.value.cost_conversation
    ),
    lower: true,
    band: bands.value.cost,
  },
]);
const hasSpark = computed(
  () => props.row.spark && props.row.spark.ctr && props.row.spark.ctr.length > 1
);
const avgCtrPct = computed(() =>
  props.averages.link_ctr
    ? Number((props.averages.link_ctr * 100).toFixed(2))
    : null
);
// curva de retenção do vídeo × média da conta (em todo card de vídeo)
const retentionSeries = computed(() => {
  if (!isVideo.value || !props.row.rates.retention) return [];
  const s = [
    {
      label: 'Este criativo',
      values: props.row.rates.retention,
      color: props.accent,
    },
  ];
  if (props.averages.retention)
    s.push({
      label: 'Média da conta',
      values: props.averages.retention,
      color: '#94a3b8',
    });
  return s;
});
const retentionNote = computed(() => {
  const r = props.row.rates.retention;
  if (!r) return '';
  const pct = v => `${Math.round((v || 0) * 100)}%`;
  return `${pct(r[0])} param nos 3 s · ${pct(r[2])} chegam à metade · ${pct(r[4])} veem até o fim`;
});
</script>

<template>
  <div class="cv-frame cv-cq" :class="{ 'cv-champion': isChampion }">
    <article
      class="cv-block p-6 sm:p-8"
      :class="{ 'ring-2 ring-[var(--cv)]': selected }"
    >
      <div class="flex flex-col gap-8">
        <!-- cabeçalho: mídia · nome · chips · ações · teias -->
        <div class="flex flex-wrap gap-5 items-start">
          <button
            class="cv-cq-thumb rounded-2xl overflow-hidden bg-n-alpha-2 flex-shrink-0 flex items-center justify-center"
            title="Ver a fundo"
            @click="emit('open', row)"
          >
            <img
              v-if="row.thumbnail_url && !imgFailed"
              :src="row.thumbnail_url"
              :alt="row.ad_name"
              class="w-full h-full object-cover"
              loading="lazy"
              @error="imgFailed = true"
            />
            <span
              v-else
              :class="FORMAT_ICON[row.format] || FORMAT_ICON.other"
              class="text-4xl text-n-slate-9"
            />
          </button>
          <div class="flex flex-col gap-2.5 min-w-0 flex-auto">
            <div>
              <h3
                class="text-xl sm:text-2xl font-bold text-n-slate-12 leading-tight tracking-tight"
              >
                {{ row.ad_name || `Anúncio ${row.ad_id}` }}
              </h3>
              <p class="text-xs text-n-slate-9 mt-1">
                {{ row.campaign_name || 'sem campanha'
                }}<span v-if="row.adset_name"> · {{ row.adset_name }}</span> ·
                {{ row.days }} dia(s) com dados
              </p>
            </div>
            <div class="flex items-center gap-1.5 flex-wrap">
              <span class="cv-chip"
                ><span
                  :class="FORMAT_ICON[row.format] || FORMAT_ICON.other"
                  class="text-xs"
                />{{ row.format_label }}</span
              >
              <span
                class="inline-flex items-center gap-1 text-[11px] text-n-slate-10"
                ><span class="w-1.5 h-1.5 rounded-full" :class="status.cls" />{{
                  status.label
                }}</span
              >
              <span v-if="diag.fatigue" class="cv-chip cv-amber"
                ><span class="i-lucide-battery-low text-xs" />sinal de
                fadiga</span
              >
              <span
                v-if="worstBand"
                class="inline-flex items-center gap-1 text-xs font-semibold"
                :class="BAND_META[worstBand].cls"
              >
                <span :class="BAND_META[worstBand].icon" class="text-sm" />
                {{
                  worstBand === 'bom'
                    ? 'Tudo no verde'
                    : worstBand === 'ruim'
                      ? 'Tem parâmetro no vermelho'
                      : 'Zona de atenção'
                }}
              </span>
            </div>
            <div v-if="champions.length" class="flex flex-wrap gap-1.5">
              <span v-for="k in champions" :key="k" class="cv-champion-badge">
                <span :class="CHAMPION_META[k].icon" />{{
                  CHAMPION_META[k].label
                }}
              </span>
            </div>
            <div class="flex flex-wrap gap-2 pt-1">
              <button class="cv-btn cv-btn-sm" @click="emit('open', row)">
                <span class="i-lucide-search text-sm" />Ver a fundo
              </button>
              <button
                class="cv-btn cv-btn-sm cv-btn-ghost"
                title="Copiar gancho, corpo e CTA"
                @click="transcribe(row)"
              >
                <span class="i-lucide-copy text-sm" />Transcrever
              </button>
              <a
                v-if="row.permalink"
                :href="row.permalink"
                target="_blank"
                rel="noopener noreferrer"
                class="cv-btn cv-btn-sm cv-btn-ghost"
                ><span class="i-lucide-instagram text-sm" />Instagram</a
              >
              <label
                v-if="compareMode"
                class="flex items-center gap-1.5 text-xs text-n-slate-11 cursor-pointer"
              >
                <input
                  type="checkbox"
                  :checked="selected"
                  class="accent-[var(--cv)]"
                  @change="emit('toggle', row)"
                />
                incluir na comparação
              </label>
            </div>
          </div>
          <!-- TEIAS: uma por pergunta (copy × parâmetros; retenção do vídeo) -->
          <div
            class="cv-cq-radar flex flex-wrap justify-center gap-x-4 gap-y-2"
          >
            <figure class="flex flex-col items-center gap-1 m-0">
              <CreativeRadar
                :row="row"
                env="criativos"
                group="copy"
                :targets="targets"
                :averages="averages"
                :peers="peers"
                :size="isVideo ? 132 : 150"
                :color="accent"
                show-average
              />
              <figcaption
                class="text-[10px] text-n-slate-10 text-center leading-tight"
              >
                <b class="text-n-slate-12">Copy</b> · qual bloco está fraco
              </figcaption>
            </figure>
            <figure v-if="isVideo" class="flex flex-col items-center gap-1 m-0">
              <CreativeRadar
                :row="row"
                env="criativos"
                group="video"
                :targets="targets"
                :averages="averages"
                :peers="peers"
                :size="132"
                :color="accent"
                show-average
              />
              <figcaption
                class="text-[10px] text-n-slate-10 text-center leading-tight"
              >
                <b class="text-n-slate-12">Retenção</b> · onde o vídeo solta
              </figcaption>
            </figure>
          </div>
        </div>

        <!-- 💰 o que vale dinheiro -->
        <section>
          <p
            class="text-[11px] uppercase tracking-wide text-n-slate-9 font-semibold mb-3 flex items-center gap-1.5"
          >
            <span
              class="i-lucide-badge-dollar-sign text-sm"
              :style="{ color: accent }"
            />
            O que vale dinheiro
            <span
              class="normal-case tracking-normal font-normal text-n-slate-8 ml-1"
            >
              jornada do CRM × investido · contra a média da conta
            </span>
          </p>
          <MoneyTiles
            :rates="row.rates"
            :funnel="row.funnel"
            :averages="averages"
            :champions="row.champion_of || []"
          />
        </section>

        <!-- 🎬 retenção (todo vídeo) -->
        <section v-if="retentionSeries.length">
          <p
            class="text-[11px] uppercase tracking-wide text-n-slate-9 font-semibold mb-1 flex items-center gap-1.5"
          >
            <span class="i-lucide-film text-sm" :style="{ color: accent }" />
            Retenção do vídeo
            <span
              class="normal-case tracking-normal font-normal text-n-slate-8 ml-1"
            >
              linha cinza = média da conta
            </span>
          </p>
          <p class="text-xs text-n-slate-11 mb-2">{{ retentionNote }}</p>
          <RetentionCurve :series="retentionSeries" :height="150" />
        </section>

        <!-- texto -->
        <div class="min-w-0 flex flex-col gap-5">
          <div class="rounded-2xl bg-n-alpha-1 p-6 space-y-3">
            <p
              class="text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold flex items-center gap-2 flex-wrap"
            >
              Gancho
              <span
                v-if="fromVideo"
                class="cv-chip cv-green normal-case tracking-normal"
                title="Transcrição do vídeo: o que é falado nos primeiros segundos"
                ><span class="i-lucide-clapperboard text-xs" />fala do
                vídeo</span
              >
              <span
                v-else-if="row.format === 'video'"
                class="cv-chip cv-amber normal-case tracking-normal"
                title="Ainda sem transcrição: mostrando o texto do anúncio"
                ><span class="i-lucide-file-text text-xs" />texto do
                anúncio</span
              >
              <button
                v-if="canTranscribe"
                class="cv-btn cv-btn-sm cv-btn-ghost normal-case tracking-normal"
                @click="emit('transcribe-video', row)"
              >
                <span class="i-lucide-sparkles text-xs" />Transcrever vídeo
              </button>
              <span
                v-else-if="['queued', 'processing'].includes(transcriptStatus)"
                class="normal-case tracking-normal text-n-slate-9"
                >transcrevendo…</span
              >
              <span
                v-else-if="
                  transcriptStatus === 'failed' && row.transcript.error
                "
                class="normal-case tracking-normal text-red-600"
                :title="row.transcript.error"
                >falhou</span
              >
            </p>
            <p class="text-lg font-bold text-n-slate-12 leading-snug">
              {{ row.hook || '—' }}
              <span
                v-if="row.titles && row.titles.length > 1"
                class="text-xs text-n-slate-9 font-normal"
                >e mais {{ row.titles.length - 1 }} no criativo dinâmico</span
              >
            </p>
            <p
              class="text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold pt-1"
            >
              Corpo
            </p>
            <p
              class="text-sm text-n-slate-11 whitespace-pre-line leading-relaxed"
            >
              {{ row.body || '—' }}
            </p>
            <div class="flex items-center gap-2 pt-1 flex-wrap">
              <span
                class="text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold"
                >CTA</span
              >
              <span class="cv-chip">{{ row.cta_label }}</span>
              <span v-if="row.video_cta" class="text-xs text-n-slate-11"
                >· no vídeo: “{{ row.video_cta }}”</span
              >
            </div>
          </div>
          <div v-if="row.diagnosis" class="cv-sub rounded-2xl p-5">
            <p
              class="text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold flex flex-wrap items-center gap-1 mb-1"
            >
              <span
                class="i-lucide-sparkles text-sm"
                :style="{ color: accent }"
              />Leitura
              <span
                v-if="focusLabel"
                class="ml-auto normal-case tracking-normal cv-chip"
                >{{ focusLabel }}</span
              >
            </p>
            <p class="text-sm text-n-slate-12 leading-relaxed">
              {{ row.diagnosis.text }}
            </p>
          </div>
        </div>

        <!-- números da Meta -->
        <div class="min-w-0 flex flex-col gap-6">
          <div class="cv-cq-meters grid gap-x-8 gap-y-5">
            <BulletMeter
              v-for="(m, i) in meters"
              :key="m.key"
              :label="m.label"
              :metric="m.metric"
              :hint="m.hint"
              :value="row.rates[m.key]"
              :avg="averages[m.key]"
              :prev="prev ? prev[m.key] : null"
              :band="bands[m.band]"
              :vs-avg="vsAvg[m.band]"
              :target="targets[m.key]"
              :digits="m.digits"
              :color="grad(i)"
            />
          </div>
          <div class="cv-cq-kpis grid gap-3">
            <div
              v-for="k in kpis"
              :key="k.label"
              class="cv-sub rounded-xl px-4 py-3"
            >
              <p
                class="text-[10px] text-n-slate-9 flex flex-wrap items-center gap-1"
              >
                {{ k.label }}
                <span
                  v-if="k.band"
                  class="inline-flex items-center gap-0.5 ml-auto font-semibold"
                  :class="BAND_META[k.band].cls"
                  ><span :class="BAND_META[k.band].icon" />{{
                    BAND_META[k.band].label
                  }}</span
                >
              </p>
              <p class="text-base font-bold text-n-slate-12 tabular-nums">
                {{ k.value }}
              </p>
              <p
                v-if="k.d !== null"
                class="text-[10px] font-semibold"
                :class="k.neutral ? 'text-n-slate-9' : deltaCls(k.d, k.lower)"
              >
                {{ fmtDelta(k.d) }} vs período anterior
              </p>
              <p v-else class="text-[10px] text-n-slate-8">
                sem período anterior
              </p>
            </div>
          </div>
          <div v-if="hasSpark">
            <p class="text-[11px] text-n-slate-10 mb-0.5">
              CTR de link por dia (%) · linha tracejada = média da conta
            </p>
            <MiniBars
              :values="row.spark.ctr"
              :labels="row.spark.labels"
              :color="accent"
              :height="80"
              :reference="avgCtrPct"
              :show-values="false"
              :format="v => `${String(v).replace('.', ',')}%`"
            />
          </div>
        </div>
      </div>
    </article>
  </div>
</template>
