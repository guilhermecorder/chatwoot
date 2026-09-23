<script setup>
// 🎨 item 209: a cor de cada uma nas Conversas — FUNDO e BALÕES, escolhas
// independentes que se combinam (cabeçalho da conversa; vale só para a pessoa)
// 23/09 (item 210): o popup abre TELEPORTADO para o body, em posição fixa —
// o cabeçalho da conversa tem desfoque (backdrop-filter), que cria um
// contexto de empilhamento próprio, e a paleta ficava POR TRÁS dos balões,
// sem dar para clicar. Fora do cabeçalho ela fica por cima de tudo.
import { ref, computed, nextTick } from 'vue';
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
const anchor = ref(null);
const popStyle = ref({});
const bgKey = computed(() => uiSettings.value?.[BG_THEME_KEY] || DEFAULT_THEME);
const bubbleKey = computed(
  () => uiSettings.value?.[BUBBLE_THEME_KEY] || DEFAULT_THEME
);
const title = computed(
  () =>
    `A sua cor nas Conversas · fundo ${findBgTheme(bgKey.value).label} · balões ${findBubbleTheme(bubbleKey.value).label} (só para você)`
);

// posição fixa a partir do botão: encostada na direita dele, logo abaixo;
// no celular a caixa não passa da borda da tela
const place = () => {
  const rect = anchor.value?.getBoundingClientRect();
  if (!rect) return;
  const width = 288;
  const right = Math.max(8, window.innerWidth - rect.right);
  const fitsRight = right + width <= window.innerWidth - 8;
  popStyle.value = {
    top: `${Math.round(rect.bottom + 6)}px`,
    right: fitsRight ? `${Math.round(right)}px` : '8px',
    width: `${width}px`,
  };
};
const toggle = async () => {
  open.value = !open.value;
  if (open.value) {
    await nextTick();
    place();
  }
};
const close = () => {
  open.value = false;
};

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
  <div class="relative flex-shrink-0">
    <button
      ref="anchor"
      class="w-8 h-8 rounded-lg flex items-center justify-center text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1 transition-colors"
      :class="open ? 'bg-n-alpha-2 text-n-slate-12' : ''"
      :title="title"
      @click="toggle"
    >
      <span class="i-lucide-palette text-base" />
    </button>
    <Teleport to="body">
      <template v-if="open">
        <!-- véu invisível: clicar fora fecha (sem prender a rolagem) -->
        <div class="fixed inset-0 z-[9998]" @click="close" />
        <div
          class="cv-bubble-pop fixed z-[9999] p-3 rounded-2xl shadow-2xl bg-n-solid-1 border border-n-weak"
          :style="popStyle"
          role="dialog"
          aria-label="A sua cor nas Conversas"
        >
          <p class="text-[11px] font-semibold text-n-slate-12 mb-0.5">
            A sua cor nas Conversas
          </p>
          <p class="text-[10px] text-n-slate-10 mb-2.5 leading-snug">
            Tons suaves para se orientar sem cansar a vista. Combine fundo e
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
              :class="
                t.key === bubbleKey ? 'border-n-brand' : 'border-black/10'
              "
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
      </template>
    </Teleport>
  </div>
</template>

<style scoped>
.cv-bubble-pop {
  animation: cv-bubble-pop 0.18s cubic-bezier(0.34, 1.4, 0.64, 1);
  transform-origin: top right;
}
@keyframes cv-bubble-pop {
  from {
    opacity: 0;
    transform: scale(0.94) translateY(-4px);
  }
  to {
    opacity: 1;
    transform: none;
  }
}
</style>
