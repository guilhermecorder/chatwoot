<script setup>
// 🎨 item 209: a cor de cada uma nas Conversas — FUNDO e BALÕES, escolhas
// independentes que se combinam (cabeçalho da conversa; vale só para a pessoa)
import { ref, computed } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAlert } from 'dashboard/composables';
import {
  BG_THEMES,
  BUBBLE_THEMES,
  BG_THEME_KEY,
  BUBBLE_THEME_KEY,
  DEFAULT_THEME,
  findBgTheme,
  findBubbleTheme,
} from 'dashboard/helper/cevicoBubbleThemes';

const { uiSettings, updateUISettings } = useUISettings();
const open = ref(false);
const bgKey = computed(() => uiSettings.value?.[BG_THEME_KEY] || DEFAULT_THEME);
const bubbleKey = computed(
  () => uiSettings.value?.[BUBBLE_THEME_KEY] || DEFAULT_THEME
);
const title = computed(
  () =>
    `A sua cor nas Conversas · fundo ${findBgTheme(bgKey.value).label} · balões ${findBubbleTheme(bubbleKey.value).label} (só para você)`
);

const save = async (settingKey, value, label) => {
  try {
    await updateUISettings({ [settingKey]: value });
    useAlert(label);
  } catch {
    useAlert('Não deu para salvar a sua cor.');
  }
};
const pickBg = t => {
  if (t.key !== bgKey.value) save(BG_THEME_KEY, t.key, `Fundo: ${t.label}.`);
};
const pickBubble = t => {
  if (t.key !== bubbleKey.value)
    save(BUBBLE_THEME_KEY, t.key, `Balões: ${t.label}.`);
};
</script>

<template>
  <div v-on-clickaway="() => (open = false)" class="relative flex-shrink-0">
    <button
      class="w-8 h-8 rounded-lg flex items-center justify-center text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1 transition-colors"
      :title="title"
      @click="open = !open"
    >
      <span class="i-lucide-palette text-base" />
    </button>
    <div
      v-if="open"
      class="cv-pop absolute z-40 right-0 top-9 w-72 p-3 rounded-2xl shadow-xl bg-n-solid-1 border border-n-weak"
    >
      <p class="text-[11px] font-semibold text-n-slate-12 mb-0.5">
        A sua cor nas Conversas
      </p>
      <p class="text-[10px] text-n-slate-10 mb-2.5 leading-snug">
        Tons leitosos para se orientar sem cansar a vista. Combine fundo e
        balões como preferir. Vale só para você, em qualquer aparelho.
      </p>

      <p
        class="text-[10px] font-semibold uppercase tracking-wide text-n-slate-10 mb-1.5"
      >
        Fundo
      </p>
      <div class="flex flex-wrap gap-1.5 mb-3">
        <button
          v-for="t in BG_THEMES"
          :key="`bg-${t.key}`"
          class="w-7 h-7 rounded-full border-2 transition-transform hover:scale-110 flex items-center justify-center"
          :class="t.key === bgKey ? 'border-n-brand' : 'border-black/10'"
          :style="{ background: t.swatch }"
          :title="t.label"
          @click="pickBg(t)"
        >
          <span
            v-if="t.key === bgKey"
            class="i-lucide-check text-[11px]"
            :class="t.kind === 'dark' ? 'text-white' : 'text-n-slate-12'"
          />
        </button>
      </div>

      <p
        class="text-[10px] font-semibold uppercase tracking-wide text-n-slate-10 mb-1.5"
      >
        Balões
      </p>
      <div class="flex flex-wrap gap-1.5">
        <button
          v-for="t in BUBBLE_THEMES"
          :key="`bb-${t.key}`"
          class="h-7 w-11 rounded-full border-2 transition-transform hover:scale-105 flex items-center justify-center gap-0.5 bg-n-alpha-1"
          :class="t.key === bubbleKey ? 'border-n-brand' : 'border-black/10'"
          :title="t.label"
          @click="pickBubble(t)"
        >
          <span
            class="w-3.5 h-3.5 rounded-full border border-black/10"
            :style="{ background: t.swatch.in }"
          />
          <span
            class="w-3.5 h-3.5 rounded-full border border-black/10"
            :style="{ background: t.swatch.out }"
          />
        </button>
      </div>
      <p class="text-[10px] text-n-slate-10 mt-2.5 leading-snug">
        Agora: fundo <b>{{ findBgTheme(bgKey).label }}</b> · balões
        <b>{{ findBubbleTheme(bubbleKey).label }}</b>
      </p>
    </div>
  </div>
</template>
