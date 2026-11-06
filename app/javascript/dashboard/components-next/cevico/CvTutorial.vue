<script setup>
// 🎓 CvTutorial — tutorial guiado reutilizável do kit CEVICO.
// Recebe uma lista de passos; cada passo pode apontar para um elemento da tela
// (seletor CSS em `target`). O elemento fica iluminado por um "holofote" e o
// resto da página escurece; o cartão com título/texto aparece logo abaixo do
// alvo (ou acima, se não couber; no celular fica preso no rodapé).
// Uso: <CvTutorial v-model="aberto" name="Tutorial · Segmentação" :steps="passos" @finish="..." />
import { ref, computed, watch, nextTick, onBeforeUnmount } from 'vue';

const props = defineProps({
  steps: { type: Array, required: true }, // [{ title, text, target?, icon? }]
  modelValue: { type: Boolean, default: false },
  name: { type: String, default: 'Tutorial' },
});
const emit = defineEmits(['update:modelValue', 'finish', 'close']);

const PAD = 8; // folga do holofote em volta do alvo
const GAP = 14; // distância entre o alvo e o cartão
const MARGIN = 16; // margem mínima até a borda da janela

const index = ref(0);
const rect = ref(null); // { top, left, width, height } do alvo, ou null
const cardEl = ref(null);
const nextBtn = ref(null);
const cardSize = ref({ width: 440, height: 220 });
const viewport = ref({ width: 1024, height: 768 });

let rafId = null;
let measureTimer = null;
let listening = false;

const total = computed(() => props.steps?.length || 0);
const step = computed(() => props.steps?.[index.value] || {});
const isFirst = computed(() => index.value === 0);
const isLast = computed(() => index.value >= total.value - 1);
const isMobile = computed(() => viewport.value.width < 640);

const findTarget = () => {
  const sel = step.value?.target;
  if (!sel || typeof document === 'undefined') return null;
  try {
    return document.querySelector(sel);
  } catch {
    return null;
  }
};

const readViewport = () => {
  if (typeof window === 'undefined') return;
  viewport.value = { width: window.innerWidth, height: window.innerHeight };
};

const measure = () => {
  readViewport();
  const el = findTarget();
  if (!el) {
    rect.value = null;
  } else {
    const r = el.getBoundingClientRect();
    rect.value = { top: r.top, left: r.left, width: r.width, height: r.height };
  }
  if (cardEl.value) {
    cardSize.value = {
      width: cardEl.value.offsetWidth || cardSize.value.width,
      height: cardEl.value.offsetHeight || cardSize.value.height,
    };
  }
};

const scheduleMeasure = () => {
  if (typeof window === 'undefined') return;
  if (rafId) return;
  rafId = window.requestAnimationFrame(() => {
    rafId = null;
    measure();
  });
};

const focusNext = () => {
  nextTick(() => {
    try {
      nextBtn.value?.focus({ preventScroll: true });
    } catch {
      // alguns navegadores antigos não aceitam opções no focus
    }
  });
};

const showStep = () => {
  if (measureTimer) clearTimeout(measureTimer);
  const el = findTarget();
  if (el) {
    try {
      el.scrollIntoView({ block: 'center', behavior: 'smooth' });
    } catch {
      el.scrollIntoView();
    }
    // mede uma vez já (para não ficar vazio) e de novo quando a rolagem assentar
    measure();
    measureTimer = setTimeout(() => {
      measure();
      focusNext();
    }, 380);
  } else {
    rect.value = null;
    nextTick(measure);
    focusNext();
  }
};

const close = () => {
  emit('update:modelValue', false);
  emit('close');
};

const goTo = i => {
  if (!total.value) return;
  const n = Math.max(0, Math.min(total.value - 1, Number(i) || 0));
  index.value = n;
  nextTick(showStep);
};

const next = () => {
  if (isLast.value) {
    emit('finish');
    emit('update:modelValue', false);
    return;
  }
  goTo(index.value + 1);
};

const prev = () => {
  if (isFirst.value) return;
  goTo(index.value - 1);
};

const onKey = e => {
  if (e.key === 'Escape') {
    e.preventDefault();
    close();
  } else if (e.key === 'ArrowRight') {
    e.preventDefault();
    next();
  } else if (e.key === 'ArrowLeft') {
    e.preventDefault();
    prev();
  }
};

const startListening = () => {
  if (listening || typeof window === 'undefined') return;
  listening = true;
  window.addEventListener('scroll', scheduleMeasure, {
    capture: true,
    passive: true,
  });
  window.addEventListener('resize', scheduleMeasure);
  window.addEventListener('keydown', onKey);
};

const stopListening = () => {
  if (!listening || typeof window === 'undefined') return;
  listening = false;
  window.removeEventListener('scroll', scheduleMeasure, { capture: true });
  window.removeEventListener('resize', scheduleMeasure);
  window.removeEventListener('keydown', onKey);
  if (rafId) {
    window.cancelAnimationFrame(rafId);
    rafId = null;
  }
  if (measureTimer) {
    clearTimeout(measureTimer);
    measureTimer = null;
  }
};

watch(
  () => props.modelValue,
  open => {
    if (open) {
      index.value = 0;
      readViewport();
      startListening();
      nextTick(showStep);
    } else {
      stopListening();
      rect.value = null;
    }
  },
  { immediate: true }
);

onBeforeUnmount(stopListening);

// ── posições ─────────────────────────────────────────────────────────────
const spotStyle = computed(() => {
  const r = rect.value;
  if (!r) return null;
  return {
    top: `${r.top - PAD}px`,
    left: `${r.left - PAD}px`,
    width: `${r.width + PAD * 2}px`,
    height: `${r.height + PAD * 2}px`,
  };
});

const cardStyle = computed(() => {
  const r = rect.value;
  const vw = viewport.value.width;
  const vh = viewport.value.height;
  const cardW = Math.min(440, vw - MARGIN * 2);
  if (isMobile.value) {
    return {
      left: `${MARGIN}px`,
      right: `${MARGIN}px`,
      bottom: `${MARGIN}px`,
      width: 'auto',
    };
  }
  if (!r) {
    return {
      left: '50%',
      top: '50%',
      transform: 'translate(-50%, -50%)',
      width: `${cardW}px`,
    };
  }
  const h = cardSize.value.height || 220;
  let top = r.top + r.height + PAD + GAP;
  if (top + h > vh - MARGIN) {
    top = r.top - PAD - GAP - h;
    if (top < MARGIN) top = Math.max(MARGIN, vh - MARGIN - h);
  }
  let left = r.left - PAD;
  left = Math.max(MARGIN, Math.min(left, vw - MARGIN - cardW));
  return { top: `${top}px`, left: `${left}px`, width: `${cardW}px` };
});

const dialogLabel = computed(
  () => `${props.name} — passo ${index.value + 1} de ${total.value}`
);

defineExpose({ goTo });
</script>

<template>
  <Teleport to="body">
    <Transition name="cv-tut">
      <div
        v-if="modelValue && total"
        class="cv-page cv-overlay cv-tut-root"
        role="dialog"
        aria-modal="true"
        :aria-label="dialogLabel"
      >
        <!-- fundo escuro inteiro: pega os cliques e não faz nada -->
        <div v-if="!spotStyle" class="cv-tut-dim" @click.stop />
        <!-- holofote: ilumina o alvo e escurece o resto -->
        <div v-else class="cv-tut-spot" :style="spotStyle" />
        <!-- camada invisível que segura os cliques quando há holofote -->
        <div v-if="spotStyle" class="cv-tut-catch" @click.stop />

        <div
          ref="cardEl"
          class="cv-blue cv-tut-card bg-white dark:bg-slate-900 rounded-2xl"
          :style="cardStyle"
        >
          <button
            type="button"
            class="cv-tut-x"
            aria-label="Fechar tutorial"
            @click="close"
          >
            <span class="i-lucide-x text-base" />
          </button>

          <div
            class="text-[11px] uppercase tracking-wide text-n-slate-10 font-semibold pr-8"
          >
            {{ name }} · Passo {{ index + 1 }} de {{ total }}
          </div>

          <div class="flex items-start gap-3 mt-3">
            <span v-if="step.icon" class="cv-tut-icon">
              <span :class="step.icon" class="text-white text-lg" />
            </span>
            <div class="min-w-0 flex-1">
              <h3 class="text-base font-bold text-n-slate-12 leading-snug m-0">
                {{ step.title }}
              </h3>
              <p
                class="text-sm text-n-slate-11 leading-relaxed mt-1.5 mb-0 whitespace-pre-line"
              >
                {{ step.text }}
              </p>
            </div>
          </div>

          <div class="flex items-center justify-between gap-3 mt-4">
            <div class="flex items-center gap-1.5" aria-hidden="true">
              <span
                v-for="(s, i) in steps"
                :key="i"
                class="cv-tut-dot"
                :class="{ 'cv-tut-dot-on': i === index }"
              />
            </div>
            <div class="flex items-center gap-2">
              <button
                v-if="!isFirst"
                type="button"
                class="cv-btn cv-btn-ghost cv-btn-sm"
                @click="prev"
              >
                <span class="i-lucide-arrow-left text-sm" />
                Anterior
              </button>
              <button
                ref="nextBtn"
                type="button"
                class="cv-btn cv-btn-sm"
                @click="next"
              >
                {{ isLast ? 'Concluir' : 'Próximo' }}
                <span
                  :class="isLast ? 'i-lucide-check' : 'i-lucide-arrow-right'"
                  class="text-sm"
                />
              </button>
            </div>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.cv-tut-root {
  position: fixed;
  inset: 0;
  z-index: 9999;
}
.cv-tut-dim {
  position: absolute;
  inset: 0;
  background: rgba(15, 23, 42, 0.62);
}
.cv-tut-catch {
  position: absolute;
  inset: 0;
  background: transparent;
}
.cv-tut-spot {
  position: fixed;
  border-radius: 18px;
  box-shadow:
    0 0 0 9999px rgba(15, 23, 42, 0.62),
    0 0 0 3px rgba(37, 99, 235, 0.9);
  pointer-events: none;
  transition:
    top 0.35s ease,
    left 0.35s ease,
    width 0.35s ease,
    height 0.35s ease;
  z-index: 1;
}
.cv-tut-card {
  position: fixed;
  z-index: 2;
  width: min(440px, calc(100vw - 32px));
  padding: 20px;
  box-shadow:
    0 24px 60px -12px rgba(15, 23, 42, 0.55),
    0 0 0 1px rgba(15, 23, 42, 0.08);
  transition:
    top 0.35s ease,
    left 0.35s ease;
}
.cv-tut-x {
  position: absolute;
  top: 12px;
  right: 12px;
  width: 28px;
  height: 28px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 9999px;
  color: #64748b;
  background: transparent;
  border: 0;
  cursor: pointer;
  transition: background 0.15s ease;
}
.cv-tut-x:hover {
  background: rgba(15, 23, 42, 0.08);
}
.dark .cv-tut-x:hover {
  background: rgba(255, 255, 255, 0.1);
}
.cv-tut-icon {
  flex-shrink: 0;
  width: 36px;
  height: 36px;
  border-radius: 11px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #1d4ed8, #3b82f6);
  box-shadow: 0 6px 14px -6px rgba(30, 64, 175, 0.7);
}
.cv-tut-dot {
  width: 7px;
  height: 7px;
  border-radius: 9999px;
  background: rgba(100, 116, 139, 0.35);
  transition:
    background 0.2s ease,
    transform 0.2s ease;
}
.cv-tut-dot-on {
  background: #2563eb;
  transform: scale(1.25);
}

/* fade do overlay */
.cv-tut-enter-active,
.cv-tut-leave-active {
  transition: opacity 0.2s ease;
}
.cv-tut-enter-from,
.cv-tut-leave-to {
  opacity: 0;
}
</style>
