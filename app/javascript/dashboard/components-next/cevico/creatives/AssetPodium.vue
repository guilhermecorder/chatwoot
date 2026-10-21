<script setup>
// PÓDIO de uma categoria de peça (gancho / corpo / CTA) — item 172, rodada 3:
// os 3 primeiros em cartões grandes com medalha, texto inteiro e os
// indicadores que decidem (conversas, custo por conversa, CTR, fatia); o
// 1º com a moldura dourada de campeão; botão Transcrever em cada um (copia
// o texto da peça); o ranking completo abaixo.
import { computed, ref } from 'vue';
import AssetTable from './AssetTable.vue';
import { fmtCompact, fmtPct, fmtNum, fmtMoney } from './creativeFormat';
import { useTranscribe } from './useTranscribe';
import CreativeRadar from './CreativeRadar.vue';

const props = defineProps({
  rows: { type: Array, default: () => [] },
  title: { type: String, required: true },
  subtitle: { type: String, default: '' },
  icon: { type: String, default: 'i-lucide-anchor' },
  color: { type: String, default: 'var(--cv)' },
  labelHeader: { type: String, default: 'Peça' },
  emptyText: { type: String, default: 'sem peças separadas neste período' },
  part: { type: String, default: 'title' },
  targets: { type: Object, default: () => ({}) },
});
const { transcribe } = useTranscribe();

const showAll = ref(false);
const sorted = computed(() =>
  [...props.rows].sort(
    (a, b) =>
      (b.conversations || 0) - (a.conversations || 0) ||
      (a.cost_conversation || 1e9) - (b.cost_conversation || 1e9)
  )
);
const podium = computed(() => sorted.value.slice(0, 3));
const maxConv = computed(() =>
  Math.max(...podium.value.map(r => r.conversations || 0), 1)
);
const total = computed(() =>
  sorted.value.reduce((a, r) => a + (r.conversations || 0), 0)
);
const share = r => (total.value ? (r.conversations || 0) / total.value : 0);
</script>

<template>
  <section class="min-w-0">
    <div class="flex items-center gap-2 mb-1 flex-wrap">
      <span class="cv-icon"><span :class="icon" class="text-base" /></span>
      <h3 class="text-sm font-bold text-n-slate-12">{{ title }}</h3>
      <span v-if="subtitle" class="text-[11px] text-n-slate-9">{{
        subtitle
      }}</span>
      <span
v-if="sorted.length" class="text-[11px] text-n-slate-9 ml-auto"
        >{{ sorted.length }} peça(s) · {{ fmtNum(total) }} conversas</span
      >
    </div>
    <p v-if="!sorted.length" class="text-xs text-n-slate-9 py-6 text-center">
      {{ emptyText }}
    </p>
    <template v-else>
      <div class="grid gap-3 md:grid-cols-3 mt-3">
        <div
          v-for="(r, i) in podium"
          :key="r.key"
          class="cv-frame"
          :class="[`cv-podium-${i + 1}`, { 'cv-champion': i === 0 }]"
        >
          <div class="cv-block p-4 h-full flex flex-col gap-3 md:min-h-[15rem]">
            <div class="flex items-start gap-3">
              <span class="cv-medal flex-shrink-0">{{ i + 1 }}º</span>
              <p
                class="font-bold text-n-slate-12 leading-snug whitespace-pre-line"
                :class="i === 0 ? 'text-base' : 'text-sm'"
              >
                {{ r.label }}
              </p>
            </div>
            <div class="flex flex-wrap items-center gap-2">
              <span
v-if="i === 0" class="cv-champion-badge"
                ><span class="i-lucide-trophy" />Campeã do período</span
              >
              <button
                class="cv-btn cv-btn-sm cv-btn-ghost"
                title="Copiar o texto desta peça"
                @click="transcribe(r, part)"
              >
                <span class="i-lucide-copy text-sm" />Transcrever
              </button>
            </div>
            <CreativeRadar
              :row="r"
              env="pecas"
              group="asset"
              scope="asset"
              :targets="targets"
              :peers="podium"
              :size="96"
              :color="color"
              class="self-center"
            />
            <div class="mt-auto">
              <div class="flex items-baseline gap-2">
                <span
                  class="text-2xl font-extrabold text-n-slate-12 tabular-nums"
                  >{{ fmtNum(r.conversations) }}</span
                >
                <span class="text-xs text-n-slate-10"
                  >conversas · {{ fmtPct(share(r), 0) }} da categoria</span
                >
              </div>
              <div class="cv-track cv-track-sm mt-1.5">
                <div
                  class="cv-fill"
                  :style="{
                    width: `${Math.max(3, ((r.conversations || 0) / maxConv) * 100)}%`,
                    background: color,
                  }"
                />
              </div>
              <div class="grid grid-cols-3 gap-2 mt-3 text-center">
                <div>
                  <p class="text-[10px] text-n-slate-9">Custo por conversa</p>
                  <p class="text-sm font-bold text-n-slate-12">
                    {{
                      r.cost_conversation ? fmtMoney(r.cost_conversation) : '—'
                    }}
                  </p>
                </div>
                <div>
                  <p class="text-[10px] text-n-slate-9">CTR</p>
                  <p class="text-sm font-bold text-n-slate-12">
                    {{ fmtPct(r.link_ctr, 2) }}
                  </p>
                </div>
                <div>
                  <p class="text-[10px] text-n-slate-9">Impressões</p>
                  <p class="text-sm font-bold text-n-slate-12">
                    {{ fmtCompact(r.impressions) }}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
      <div v-if="sorted.length > 3" class="mt-3">
        <button
          class="cv-btn cv-btn-sm cv-btn-ghost"
          @click="showAll = !showAll"
        >
          <span
            :class="showAll ? 'i-lucide-chevron-up' : 'i-lucide-list-ordered'"
            class="text-sm"
          />{{
            showAll
              ? 'Esconder ranking completo'
              : `Ranking completo (${sorted.length})`
          }}
        </button>
        <AssetTable
          v-if="showAll"
          :rows="sorted"
          :color="color"
          :label-header="labelHeader"
          :part="part"
          copyable
          class="mt-2"
        />
      </div>
    </template>
  </section>
</template>
