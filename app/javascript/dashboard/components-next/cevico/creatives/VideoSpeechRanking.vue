<script setup>
// 🎬 O QUE OS VÍDEOS FALAM (item 181): ganchos, corpos e CTAs vindos da
// TRANSCRIÇÃO dos vídeos, ranqueados pelo que cada parte tem de provar —
// gancho pela taxa de parada, corpo pela retenção, CTA falado pela conversa
// por clique. Cada linha: miniatura, fala literal, anúncio, número, ângulo.
import { computed } from 'vue';
import { fmtPct, fmtCompact, fmtMoney, FORMAT_ICON } from './creativeFormat';
import { useTranscribe } from './useTranscribe';

const props = defineProps({
  rows: { type: Array, default: () => [] },
  title: { type: String, required: true },
  subtitle: { type: String, default: '' },
  icon: { type: String, default: 'i-lucide-film' },
  color: { type: String, default: 'var(--cv)' },
  metricLabel: { type: String, default: '' },
  part: { type: String, default: 'hook' }, // hook | body | cta (Transcrever)
  emptyText: { type: String, default: 'nenhum vídeo transcrito no período' },
});
const { transcribe } = useTranscribe();
const max = computed(() =>
  Math.max(...props.rows.map(r => r.value || 0), 0.0001)
);
const ANGLE = {
  pergunta: 'pergunta',
  dor: 'dor',
  curiosidade: 'curiosidade',
  prova: 'prova',
  oferta: 'oferta',
  autoridade: 'autoridade',
  historia: 'história',
};
const PART_KEY = { hook: 'hook', body: 'hold', cta: 'cta' };
const copyRow = r =>
  transcribe(
    { hook: r.text, body: r.text, cta_label: r.text, ad_name: r.ad_name },
    PART_KEY[props.part] || 'hook'
  );
</script>

<template>
  <section>
    <div class="flex items-center gap-2 mb-1 flex-wrap">
      <span class="cv-icon cv-icon-sm"
        ><span :class="icon" class="text-sm"
      /></span>
      <h3 class="text-base sm:text-lg font-bold text-n-slate-12 tracking-tight">
        {{ title }}
      </h3>
      <span v-if="subtitle" class="text-[11px] text-n-slate-9">{{
        subtitle
      }}</span>
    </div>
    <p v-if="!rows.length" class="text-xs text-n-slate-9 py-3">
      {{ emptyText }}
    </p>
    <ol v-else class="divide-y divide-n-weak">
      <li
        v-for="(r, i) in rows"
        :key="r.ad_id"
        class="py-3 grid gap-x-4 gap-y-2 items-start grid-cols-[2.5rem_minmax(0,1fr)] sm:grid-cols-[2.5rem_3.5rem_minmax(0,1fr)_9rem]"
      >
        <span
          class="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold"
          :class="i === 0 ? 'text-white' : 'text-n-slate-11 bg-n-alpha-2'"
          :style="i === 0 ? { background: color } : {}"
        >
          {{ i + 1 }}
        </span>
        <span
          class="hidden sm:flex w-14 h-[4.5rem] rounded-xl overflow-hidden bg-n-alpha-2 items-center justify-center flex-shrink-0"
        >
          <img
            v-if="r.thumbnail_url"
            :src="r.thumbnail_url"
            :alt="r.ad_name"
            class="w-full h-full object-cover"
            loading="lazy"
          />
          <span v-else :class="FORMAT_ICON.video" class="text-n-slate-9" />
        </span>
        <div class="min-w-0">
          <p class="text-sm font-semibold text-n-slate-12 leading-snug">
            “{{ r.text }}”
          </p>
          <p
            class="text-[11px] text-n-slate-9 mt-1 flex items-center gap-1.5 flex-wrap"
          >
            <span class="min-w-0 break-words">{{ r.ad_name }}</span>
            <span v-if="r.angle && ANGLE[r.angle]" class="cv-chip">{{
              ANGLE[r.angle]
            }}</span>
            <span
              >· {{ fmtCompact(r.impressions) }} impressões ·
              {{ r.conversations }} conversas</span
            >
            <span v-if="r.cost_conversation"
              >· {{ fmtMoney(r.cost_conversation) }} por conversa</span
            >
            <button
              class="inline-flex items-center gap-0.5 font-semibold text-n-slate-10 hover:text-n-slate-12"
              title="Copiar esta fala"
              @click="copyRow(r)"
            >
              <span class="i-lucide-copy" />transcrever
            </button>
          </p>
        </div>
        <div
          class="col-span-2 sm:col-span-1 flex sm:flex-col items-center sm:items-end gap-2 sm:gap-0.5"
        >
          <span
            class="text-xl font-extrabold tabular-nums text-n-slate-12 leading-none"
            >{{ fmtPct(r.value, 1) }}</span
          >
          <span class="text-[10px] text-n-slate-9">{{ metricLabel }}</span>
          <div class="cv-track cv-track-sm w-24">
            <div
              class="cv-fill"
              :style="{
                width: `${Math.max(3, (r.value / max) * 100)}%`,
                background: color,
              }"
            />
          </div>
        </div>
      </li>
    </ol>
  </section>
</template>
