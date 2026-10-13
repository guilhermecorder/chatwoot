<script setup>
// 🧭 Guia arejado — CABEÇALHO DO AMBIENTE (os 60% da cor do dia).
// Substitui o CevicoHero nas telas migradas: fundo chapado na cor do dia,
// chip do dia + chip da paleta (mesmo popup de sempre), título em 28px e
// uma linha de subtítulo. Slot `acoes` = o botão principal (destaque) e o
// que mais a tela precisar no canto direito; slot default = filtros.
import { computed } from 'vue';
import { useAdmin } from 'dashboard/composables/useAdmin';
import CevicoPalettePicker from 'dashboard/components-next/cevico/CevicoPalettePicker.vue';

const props = defineProps({
  pal: { type: Object, required: true }, // retorno do useCevicoPalette
  title: { type: String, required: true },
  subtitle: { type: String, default: '' },
  icon: { type: String, default: '' },
  palette: { type: Boolean, default: true },
  day: { type: Boolean, default: true },
});

const { isAdmin } = useAdmin();
const {
  pagePalette,
  dayFlavor,
  flavorPreview,
  openPalettePicker,
  paletteLabel,
} = props.pal;

const todayLabel = computed(() => {
  const label = new Date().toLocaleDateString('pt-BR', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  });
  return label.charAt(0).toUpperCase() + label.slice(1);
});
const onPaletteChip = () => openPalettePicker('panel');
</script>

<template>
  <header class="cvg-cab">
    <div class="min-w-0 flex-1">
      <div v-if="day || palette" class="cvg-cab-meta">
        <span v-if="day" class="cvg-cab-chip">
          <span class="i-lucide-calendar-days text-xs" />{{ todayLabel }}
        </span>
        <button
          v-if="palette"
          type="button"
          class="cvg-cab-chip"
          :title="
            isAdmin
              ? 'Cores desta tela: só para você ou para a empresa'
              : 'Escolha as cores do seu painel — só você vê'
          "
          @click="onPaletteChip"
        >
          <span
            class="w-2 h-2 rounded-full flex-shrink-0"
            :style="{
              background: pagePalette.swatch || pagePalette.dot,
              boxShadow: '0 0 0 2px rgba(255,255,255,0.6)',
            }"
          />
          {{ paletteLabel(pagePalette)
          }}<span
            v-if="flavorPreview !== null && pagePalette === dayFlavor"
            class="opacity-75 font-normal"
          >
            · prévia</span
          >
        </button>
        <slot name="chips" />
      </div>
      <div class="flex items-center gap-3 min-w-0">
        <span v-if="icon" class="cvg-cab-icone">
          <span :class="icon" class="text-xl" />
        </span>
        <div class="min-w-0">
          <h1 class="cvg-titulo-ambiente cvg-cab-h1">{{ title }}</h1>
          <p v-if="subtitle" class="cvg-subtitulo">{{ subtitle }}</p>
        </div>
      </div>
      <div v-if="$slots.default" class="flex items-center gap-2 flex-wrap mt-4">
        <slot />
      </div>
    </div>
    <div v-if="$slots.acoes" class="cvg-cab-acoes">
      <slot name="acoes" />
    </div>
    <CevicoPalettePicker :pal="pal" :title="`Paleta de cores · ${title}`" />
  </header>
</template>
