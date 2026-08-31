<script setup>
// Roleta de números estilo iPhone (rodada 11): rola com o dedo dentro da
// caixinha e o "ímã" (CSS scroll-snap) trava no número. O valor volta como
// string ('' = vazio, decimal com vírgula) — compatível com o toNum do save.
import { ref, computed, watch, onMounted, nextTick } from 'vue';

const props = defineProps({
  modelValue: { type: [String, Number], default: '' },
  step: { type: Number, default: 1 },
  max: { type: Number, default: 30 },
  decimal: { type: Boolean, default: false },
  placeholder: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue']);

const ITEM = 26; // altura de cada número (px) — 3 visíveis por vez

const el = ref(null);
const num = v => {
  const n = Number(String(v ?? '').replace(',', '.'));
  return String(v ?? '').trim() === '' || !Number.isFinite(n) ? null : n;
};
const fmt = n => (n === null ? '' : props.decimal ? String(n).replace('.', ',') : String(n));

// teto dinâmico: cresce se o valor atual pedir ou se a roleta chegar no fim
const maxN = ref(Math.max(props.max, (num(props.modelValue) ?? 0) + 20 * props.step));
const options = computed(() => {
  const out = [null]; // null = vazio ("—", série não feita)
  const steps = Math.round(maxN.value / props.step);
  for (let i = 0; i <= steps; i += 1) out.push(Math.round(i * props.step * 100) / 100);
  return out;
});

const selIdx = ref(0);
const idxOf = v => {
  const n = num(v);
  if (n === null) return 0;
  return Math.min(options.value.length - 1, Math.max(1, Math.round(n / props.step) + 1));
};

const scrollToIdx = (i, smooth) => {
  if (!el.value) return;
  el.value.scrollTo({ top: i * ITEM, behavior: smooth ? 'smooth' : 'auto' });
};

onMounted(() => {
  selIdx.value = idxOf(props.modelValue);
  nextTick(() => scrollToIdx(selIdx.value, false));
});

// valor mudou por fora (chip "última vez") → a roleta acompanha
watch(
  () => props.modelValue,
  v => {
    const n = num(v);
    if (n !== null && n > maxN.value - 4 * props.step) maxN.value = n + 20 * props.step;
    const i = idxOf(v);
    if (i === selIdx.value) return;
    selIdx.value = i;
    nextTick(() => scrollToIdx(i, false));
  }
);

let timer = null;
const onScroll = () => {
  if (!el.value) return;
  const i = Math.min(
    options.value.length - 1,
    Math.max(0, Math.round(el.value.scrollTop / ITEM))
  );
  selIdx.value = i;
  clearTimeout(timer);
  timer = setTimeout(commit, 140);
};
const commit = () => {
  emit('update:modelValue', fmt(options.value[selIdx.value] ?? null));
  // chegou perto do fim → estica a régua (só cresce; nada muda acima)
  if (selIdx.value >= options.value.length - 4) maxN.value += 20 * props.step;
};
const pick = i => scrollToIdx(i, true); // tocar num número rola até ele
</script>

<template>
  <div class="hub-wheel relative rounded-lg border border-n-weak bg-n-solid-2">
    <div ref="el" class="hub-wheel-scroll" @scroll="onScroll">
      <div
        v-for="(opt, i) in options"
        :key="i"
        class="hub-wheel-item"
        :class="i === selIdx && opt !== null ? 'is-sel text-n-slate-12' : 'text-n-slate-10'"
        @click="pick(i)"
      >
        {{ opt === null ? (i === selIdx && placeholder ? placeholder : '—') : fmt(opt) }}
      </div>
    </div>
    <div class="hub-wheel-lines" aria-hidden="true" />
  </div>
</template>

<style scoped>
.hub-wheel-scroll {
  height: 78px; /* 3 × 26px */
  overflow-y: auto;
  scroll-snap-type: y mandatory;
  padding: 26px 0;
  overscroll-behavior: contain;
  scrollbar-width: none;
  -webkit-mask-image: linear-gradient(to bottom, transparent, #000 32%, #000 68%, transparent);
  mask-image: linear-gradient(to bottom, transparent, #000 32%, #000 68%, transparent);
}
.hub-wheel-scroll::-webkit-scrollbar {
  display: none;
}
.hub-wheel-item {
  height: 26px;
  line-height: 26px;
  text-align: center;
  font-size: 12px;
  scroll-snap-align: center;
  cursor: pointer;
  user-select: none;
}
.hub-wheel-item.is-sel {
  font-weight: 700;
  font-size: 13px;
}
.hub-wheel-lines {
  position: absolute;
  left: 5px;
  right: 5px;
  top: 26px;
  height: 26px;
  border-top: 1px solid rgba(128, 128, 128, 0.35);
  border-bottom: 1px solid rgba(128, 128, 128, 0.35);
  pointer-events: none;
}
</style>
