<script setup>
// CARD COMPACTO de um criativo (pedido 20/09): "cards menores que representem
// o criativo, com a teia principal, a imagem, o título, alguns selos, o ROAS
// e as cirurgias fechadas através dele — mais quadradinhos, bem enquadrados,
// e expandir para uma análise completa". Tudo que era da ficha completa
// (réguas, retenção, copy, números da Meta, transcrição) vive na ANÁLISE
// CIENTÍFICA (CreativeDetail). Clicar em qualquer ponto do card abre ela.
import { computed, ref } from 'vue';
import CreativeRadar from './CreativeRadar.vue';
import { useTranscribe } from './useTranscribe';
import {
  fmtRoas,
  fmtNum,
  vsAverage,
  statusMeta,
  FORMAT_ICON,
  BAND_META,
  CHAMPION_META,
} from './creativeFormat';

const props = defineProps({
  row: { type: Object, required: true },
  averages: { type: Object, default: () => ({}) },
  targets: { type: Object, default: () => ({}) },
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
const status = computed(() => statusMeta(props.row.status));
const diag = computed(() => props.row.diagnosis || {});
const bands = computed(() => diag.value.bands || {});
const worstBand = computed(() => {
  const order = ['ruim', 'atencao', 'bom'];
  const vals = Object.values(bands.value).filter(Boolean);
  return vals.sort((a, b) => order.indexOf(a) - order.indexOf(b))[0] || null;
});
// rótulo curto do pior parâmetro (o card é pequeno; o detalhe está na Análise)
const BAND_SHORT = { bom: 'no verde', atencao: 'atenção', ruim: 'no vermelho' };

// 💰 os dois números que valem dinheiro: ROAS e cirurgias fechadas por ele
const funnel = computed(() => props.row.funnel || {});
const roas = computed(() => (props.row.rates ? props.row.rates.roas : null));
const roasVs = computed(() =>
  vsAverage(roas.value, props.averages.roas, false)
);
const surgeries = computed(() => Number(funnel.value.surgeries || 0));
const booked = computed(() => Number(funnel.value.booked || 0));
const leads = computed(() => Number(funnel.value.leads || 0));
const hasJourney = computed(() => leads.value > 0);

const open = () => emit('open', props.row);
</script>

<template>
  <div class="cv-frame cv-cq h-full" :class="{ 'cv-champion': isChampion }">
    <article
      class="cv-block p-5 flex flex-col gap-4 h-full cursor-pointer"
      :class="{ 'ring-2 ring-[var(--cv)]': selected }"
      role="button"
      tabindex="0"
      :title="`Abrir a Análise científica de ${row.ad_name || 'anúncio'}`"
      @click="open"
      @keydown.enter.prevent="open"
    >
      <!-- topo: mídia + nome inteiro + origem -->
      <div class="flex gap-4 items-start min-w-0">
        <div
          class="w-16 h-20 rounded-xl overflow-hidden bg-n-alpha-2 flex-shrink-0 flex items-center justify-center"
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
            class="text-2xl text-n-slate-9"
          />
        </div>
        <div class="min-w-0 flex-1">
          <h3
            class="text-base font-bold text-n-slate-12 leading-snug tracking-tight break-words"
          >
            {{ row.ad_name || `Anúncio ${row.ad_id}` }}
          </h3>
          <p class="text-[11px] text-n-slate-9 mt-1 leading-snug break-words">
            {{ row.campaign_name || 'sem campanha' }} · {{ row.days }} dia(s)
          </p>
        </div>
      </div>

      <!-- selos: formato · situação · pior parâmetro · fadiga · fala do vídeo -->
      <div class="flex items-center gap-1.5 flex-wrap">
        <span class="cv-chip"
          ><span
            :class="FORMAT_ICON[row.format] || FORMAT_ICON.other"
            class="text-xs"
          />{{ row.format_label }}</span
        >
        <span class="inline-flex items-center gap-1 text-[11px] text-n-slate-10"
          ><span class="w-1.5 h-1.5 rounded-full" :class="status.cls" />{{
            status.label
          }}</span
        >
        <span
          v-if="worstBand"
          class="inline-flex items-center gap-1 text-[11px] font-semibold"
          :class="BAND_META[worstBand].cls"
          title="Pior parâmetro do criativo neste período"
        >
          <span :class="BAND_META[worstBand].icon" class="text-sm" />{{
            BAND_SHORT[worstBand]
          }}
        </span>
        <span
          v-if="diag.fatigue"
          class="cv-chip cv-amber"
          title="Sinal de fadiga"
          ><span class="i-lucide-battery-low text-xs" />fadiga</span
        >
        <span
          v-if="fromVideo"
          class="cv-chip cv-green"
          title="Gancho, corpo e CTA vêm da fala do vídeo"
          ><span class="i-lucide-clapperboard text-xs" />fala do vídeo</span
        >
      </div>
      <div v-if="champions.length" class="flex flex-wrap gap-1.5">
        <span v-for="k in champions" :key="k" class="cv-champion-badge">
          <span :class="CHAMPION_META[k].icon" />{{ CHAMPION_META[k].label }}
        </span>
      </div>

      <!-- a teia principal: força de gancho, corpo, CTA, custo e conversa -->
      <figure class="flex flex-col items-center gap-1 m-0">
        <CreativeRadar
          :row="row"
          env="criativos"
          group="copy"
          :targets="targets"
          :averages="averages"
          :peers="peers"
          :size="150"
          :color="accent"
          show-average
        />
        <figcaption
          class="text-[10px] text-n-slate-10 text-center leading-tight"
        >
          <b class="text-n-slate-12">Copy</b> · 100 = no parâmetro bom ·
          tracejado = média da conta
        </figcaption>
      </figure>

      <!-- o que vale dinheiro, em 2 números (o resto está na Análise) -->
      <div class="grid grid-cols-2 gap-3 mt-auto">
        <div class="cc-tile cv-sub rounded-2xl px-4 py-3 min-w-0">
          <p class="text-[11px] font-semibold text-n-slate-10 leading-tight">
            ROAS
          </p>
          <p
            class="cc-value font-extrabold tabular-nums tracking-tight leading-none whitespace-nowrap mt-1"
            :class="
              roas === null || roas === undefined
                ? 'text-n-slate-8'
                : 'text-n-slate-12'
            "
          >
            {{ fmtRoas(roas) }}
          </p>
          <p
            v-if="roasVs"
            class="text-[11px] font-semibold leading-tight mt-1"
            :class="
              roasVs.good === null
                ? 'text-n-slate-9'
                : roasVs.good
                  ? 'text-emerald-700 dark:text-emerald-400'
                  : 'text-red-700 dark:text-red-400'
            "
          >
            {{ roasVs.good === null ? '' : roasVs.good ? '▲ ' : '▼ '
            }}{{ roasVs.text }}
          </p>
          <p v-else class="text-[11px] text-n-slate-8 leading-tight mt-1">
            sem jornada ainda
          </p>
        </div>
        <div class="cc-tile cv-sub rounded-2xl px-4 py-3 min-w-0">
          <p class="text-[11px] font-semibold text-n-slate-10 leading-tight">
            Cirurgias fechadas
          </p>
          <p
            class="cc-value font-extrabold tabular-nums tracking-tight leading-none whitespace-nowrap mt-1"
            :class="hasJourney ? 'text-n-slate-12' : 'text-n-slate-8'"
          >
            {{ fmtNum(surgeries) }}
          </p>
          <p
            v-if="hasJourney"
            class="text-[11px] text-n-slate-9 leading-tight mt-1"
          >
            {{ fmtNum(leads) }} leads · {{ fmtNum(booked) }} consultas
          </p>
          <p v-else class="text-[11px] text-n-slate-8 leading-tight mt-1">
            nenhum lead por este anúncio
          </p>
        </div>
      </div>

      <!-- ações (não abrem o card por engano) -->
      <div class="flex items-center gap-2 flex-wrap pt-1" @click.stop>
        <button class="cv-btn cv-btn-sm" @click="open">
          <span class="i-lucide-microscope text-sm" />Análise científica
        </button>
        <button
          class="cv-iconbtn"
          title="Copiar gancho, corpo e CTA"
          @click="transcribe(row)"
        >
          <span class="i-lucide-copy text-sm" />
        </button>
        <button
          v-if="canTranscribe"
          class="cv-iconbtn"
          title="Transcrever a fala do vídeo com IA"
          @click="emit('transcribe-video', row)"
        >
          <span class="i-lucide-sparkles text-sm" />
        </button>
        <span
          v-else-if="['queued', 'processing'].includes(transcriptStatus)"
          class="text-[11px] text-n-slate-9"
          >transcrevendo…</span
        >
        <a
          v-if="row.permalink"
          :href="row.permalink"
          target="_blank"
          rel="noopener noreferrer"
          class="cv-iconbtn"
          title="Abrir no Instagram"
          ><span class="i-lucide-instagram text-sm"
        /></a>
        <label
          v-if="compareMode"
          class="ml-auto flex items-center gap-1.5 text-xs text-n-slate-11 cursor-pointer"
        >
          <input
            type="checkbox"
            :checked="selected"
            class="accent-[var(--cv)]"
            @change="emit('toggle', row)"
          />
          comparar
        </label>
      </div>
    </article>
  </div>
</template>

<style scoped>
/* número encolhe com o cartão (container query) — nunca corta, nunca quebra */
.cc-tile {
  container-type: inline-size;
}
.cc-value {
  font-size: clamp(1.2rem, 15cqi, 1.75rem);
}
</style>
