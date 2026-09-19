<script setup>
// FICHA COMPLETA de um criativo (item 172): layout "de celular" sempre —
// mídia + chips + teia em cima, texto (gancho, corpo, CTA, leitura, jornada),
// números embaixo — 2 fichas lado a lado no desktop. O que muda de tamanho
// (miniatura, réguas em 2 colunas, KPIs em 4) responde à largura da FICHA
// (container queries `.cv-cq-*` no kit), não à da janela.
import { computed, ref } from 'vue';
import MiniBars from 'dashboard/components-next/cevico/MiniBars.vue';
import BulletMeter from './BulletMeter.vue';
import CreativeRadar from './CreativeRadar.vue';
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
const emit = defineEmits(['open', 'toggle']);
const { transcribe } = useTranscribe();

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
</script>

<template>
  <div class="cv-frame cv-cq" :class="{ 'cv-champion': isChampion }">
    <article
      class="cv-block p-6 sm:p-8"
      :class="{ 'ring-2 ring-[var(--cv)]': selected }"
    >
      <div class="flex flex-col gap-7">
        <!-- topo: mídia · chips e botões · teia (embrulha na ficha estreita) -->
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
          <div class="flex flex-col gap-2 min-w-0 flex-auto">
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
            </div>
            <span
              v-for="k in champions"
              :key="k"
              class="cv-champion-badge self-start"
            >
              <span :class="CHAMPION_META[k].icon" />{{
                CHAMPION_META[k].label
              }}
            </span>
            <span
v-if="diag.fatigue" class="cv-chip cv-amber self-start"
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
            </div>
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
            <span class="text-[11px] text-n-slate-9"
              >{{ row.days }} dia(s) com dados</span
            >
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
            <p
              class="w-full text-[10px] text-n-slate-9 text-center leading-tight"
            >
              <span
                class="inline-block w-2 h-2 rounded-full align-middle"
                :style="{ background: accent }"
              />
              este criativo ·
              <span
                class="inline-block w-2 h-2 rounded-full align-middle border border-dashed border-n-slate-10"
              />
              média da conta · 100 = bateu o parâmetro
            </p>
          </div>
        </div>

        <!-- texto -->
        <div class="min-w-0 flex flex-col gap-5">
          <div>
            <h3
              class="text-xl font-bold text-n-slate-12 leading-snug tracking-tight"
            >
              {{ row.ad_name || `Anúncio ${row.ad_id}` }}
            </h3>
            <p class="text-xs text-n-slate-9">
              {{ row.campaign_name || 'sem campanha'
              }}<span v-if="row.adset_name"> · {{ row.adset_name }}</span>
            </p>
          </div>
          <div class="rounded-2xl bg-n-alpha-1 p-6 space-y-3">
            <p
              class="text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold"
            >
              Gancho
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
            </div>
          </div>
          <div v-if="row.diagnosis" class="cv-sub rounded-2xl p-5">
            <p
              class="text-[10px] uppercase tracking-wide text-n-slate-9 font-semibold flex items-center gap-1 mb-1"
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
          <div
            class="flex items-center gap-x-3 gap-y-1 text-xs text-n-slate-11 flex-wrap"
            title="leads que chegaram por este anúncio (CTWA) → consulta marcada → compareceu → cirurgia"
          >
            <span class="i-lucide-route text-sm text-n-slate-9" />
            <span
              ><b class="text-n-slate-12">{{ row.funnel.leads }}</b> leads no
              CRM</span
            >
            <span class="i-lucide-chevron-right text-xs text-n-slate-8" />
            <span
              ><b class="text-n-slate-12">{{ row.funnel.booked }}</b> marcaram
              consulta</span
            >
            <span class="i-lucide-chevron-right text-xs text-n-slate-8" />
            <span
              ><b class="text-n-slate-12">{{ row.funnel.attended }}</b>
              compareceram</span
            >
            <span class="i-lucide-chevron-right text-xs text-n-slate-8" />
            <span
              ><b class="text-n-slate-12">{{ row.funnel.surgeries }}</b>
              cirurgias</span
            >
            <span
v-if="row.funnel.revenue" class="text-n-slate-9"
              >· {{ fmtMoney(row.funnel.revenue) }}</span
            >
          </div>
        </div>

        <!-- números -->
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
              <p class="text-[10px] text-n-slate-9 flex items-center gap-1">
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
