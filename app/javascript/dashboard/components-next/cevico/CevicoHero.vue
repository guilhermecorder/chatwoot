<script setup>
// 🍎 CevicoHero (rodada 163): o BANNER de vidro do formato novo para os
// Relatórios/Dashboards — luzes, olho CEVICO, chip do dia e o chip da paleta
// (admin abre o popup; quem não é admin passeia pelas cores do dia só na
// tela). Slots: chips (ao lado da paleta), actions (canto direito), default
// (linha abaixo do título — filtros) e pulse (vidros de números).
import { computed } from 'vue';
import { useAdmin } from 'dashboard/composables/useAdmin';
import CevicoPalettePicker from 'dashboard/components-next/cevico/CevicoPalettePicker.vue';

const props = defineProps({
  pal: { type: Object, required: true }, // retorno do useCevicoPalette
  title: { type: String, required: true },
  subtitle: { type: String, default: '' },
  icon: { type: String, default: '' }, // classe lucide (i-lucide-…)
  compact: { type: Boolean, default: true },
  eye: { type: Boolean, default: true },
});

const { isAdmin } = useAdmin();
const { pagePalette, dayFlavor, flavorPreview, cycleFlavor, openPalettePicker, paletteLabel } = props.pal;
// :src dinâmico de propósito: src fixo em /brand-assets vira import no Vite
const HERO_EYE = '/brand-assets/cevico-eye.svg';
const todayLabel = computed(() => {
  const label = new Date().toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' });
  return label.charAt(0).toUpperCase() + label.slice(1);
});
const onPaletteChip = () => {
  if (isAdmin.value) openPalettePicker('panel');
  else cycleFlavor();
};
</script>

<template>
  <div
    class="cevico-hero rounded-3xl text-white shadow-lg mb-5 relative transition-all"
    :class="compact ? 'p-5 sm:p-6' : 'p-6 sm:p-8'"
    :style="{ background: pagePalette.hero }"
  >
    <span class="cevico-hero-glow cevico-hero-glow-a" aria-hidden="true" />
    <span class="cevico-hero-glow cevico-hero-glow-b" aria-hidden="true" />
    <img v-if="eye" :src="HERO_EYE" alt="" aria-hidden="true" class="cevico-hero-eye" />
    <div class="relative z-10 flex flex-col gap-3" style="color: #fff">
      <div class="flex items-start justify-between gap-3 flex-wrap">
        <div class="flex items-center gap-1.5 flex-wrap">
          <span class="cevico-hero-chip"><span class="i-lucide-calendar-days text-xs" />{{ todayLabel }}</span>
          <button
            class="cevico-hero-chip cevico-hero-chip-btn"
            :title="isAdmin ? 'Paleta desta página: cor do dia, iMac G3, frutas da Apple ou salada de frutas — e a cor de cada bloco' : 'Cada dia da semana tem a sua cor, inspirada nos iMac G3 (1998–99). Clique para experimentar as outras — só nesta tela.'"
            @click="onPaletteChip"
          >
            <span class="w-2 h-2 rounded-full flex-shrink-0" :style="{ background: pagePalette.swatch || pagePalette.dot, boxShadow: '0 0 0 2px rgba(255,255,255,0.6)' }" />
            {{ paletteLabel(pagePalette) }}<span v-if="flavorPreview !== null && pagePalette === dayFlavor" class="opacity-75 font-normal"> · prévia</span>
            <span v-if="isAdmin" class="i-lucide-palette text-[10px] opacity-80" />
          </button>
          <slot name="chips" />
        </div>
        <div v-if="$slots.actions" class="flex items-center gap-1.5 flex-shrink-0">
          <slot name="actions" />
        </div>
      </div>
      <div class="flex items-center gap-3 flex-wrap">
        <span v-if="icon" class="cv-glass w-11 h-11 flex items-center justify-center flex-shrink-0">
          <span :class="icon" class="text-xl" />
        </span>
        <div class="min-w-0 flex-1">
          <h1 class="text-2xl sm:text-[28px] font-bold leading-none tracking-tight" style="color: #fff">{{ title }}</h1>
          <p v-if="subtitle" class="text-sm mt-1.5 max-w-2xl leading-relaxed" style="color: rgba(255,255,255,0.86)">{{ subtitle }}</p>
        </div>
      </div>
      <div v-if="$slots.default" class="flex items-center gap-2 flex-wrap">
        <slot />
      </div>
      <div v-if="$slots.pulse" class="flex items-stretch gap-2 flex-wrap">
        <slot name="pulse" />
      </div>
    </div>
    <CevicoPalettePicker :pal="pal" :title="`Paleta de cores · ${title}`" />
  </div>
</template>
