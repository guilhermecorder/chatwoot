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

const ITEM = 32; // altura de cada número (px) — 3 visíveis por vez

const el = ref(null);
const num = v => {
  const n = Number(String(v ?? '').replace(',', '.'));
  return String(v ?? '').trim() === '' || !Number.isFinite(n) ? null : n;
};
const fmt = n => (n === null ? '' : props.decimal ? String(n).replace('.', ',') : String(n));

// teto FIXO (pedido 30/08: "os números não precisam ir até o infinito") —
// a roleta termina no max e o iPhone mostra o amortecedor nas pontas;
// só cresce se um valor externo (registro antigo) passar do teto
const maxN = ref(Math.max(props.max, num(props.modelValue) ?? 0));
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

// VIRTUALIZAÇÃO (peso): só ~60 números em volta da janela ficam no DOM;
// espaçadores mantêm a altura total. A janela NÃO acompanha o scroll ao
// vivo (mexer no DOM no meio da rolagem faz o snap "reancorar" e a roleta
// derrapa) — ela recentra só quando a rolagem ASSENTA, e aí o scrollTop é
// recolocado no ponto exato.
// 60 itens de folga pra cada lado ≈ 1.900px — uma rolagem forte inteira
// cabe na janela; além disso o ímã segura na borda e o próximo gesto segue
const WINDOW = 60;
const windowCenter = ref(0);
const winStart = computed(() => Math.max(0, windowCenter.value - WINDOW));
const winEnd = computed(() =>
  Math.min(options.value.length - 1, windowCenter.value + WINDOW)
);
const visible = computed(() =>
  options.value.slice(winStart.value, winEnd.value + 1)
);
const topPad = computed(() => winStart.value * ITEM);
const bottomPad = computed(
  () => (options.value.length - 1 - winEnd.value) * ITEM
);

const centerOn = i => {
  windowCenter.value = i;
  selIdx.value = i;
  nextTick(() => scrollToIdx(i, false));
};

onMounted(() => centerOn(idxOf(props.modelValue)));

// valor mudou por fora (chip "última vez") → a roleta acompanha
watch(
  () => props.modelValue,
  v => {
    const n = num(v);
    if (n !== null && n > maxN.value) maxN.value = n;
    const i = idxOf(v);
    if (i === selIdx.value) return;
    centerOn(i);
  }
);

let timer = null;
const onScroll = () => {
  if (!el.value) return;
  const i = Math.min(
    options.value.length - 1,
    Math.max(0, Math.round(el.value.scrollTop / ITEM))
  );
  selIdx.value = i; // destaque segue ao vivo (dentro da janela renderizada)
  clearTimeout(timer);
  timer = setTimeout(commit, 140);
};
const commit = () => {
  const i = selIdx.value;
  emit('update:modelValue', fmt(options.value[i] ?? null));
  // rolagem assentou: recentra a janela e recoloca o scroll no ponto exato
  if (i !== windowCenter.value) {
    windowCenter.value = i;
    nextTick(() => scrollToIdx(i, false));
  }
};
const pick = i => scrollToIdx(i, true); // tocar num número rola até ele
</script>

<template>
  <div class="hub-wheel relative rounded-lg border border-n-weak bg-n-solid-2">
    <div ref="el" class="hub-wheel-scroll" @scroll="onScroll">
      <div :style="{ height: `${topPad}px` }" />
      <div
        v-for="(opt, i) in visible"
        :key="winStart + i"
        class="hub-wheel-item"
        :class="winStart + i === selIdx && opt !== null ? 'is-sel text-n-slate-12' : 'text-n-slate-10'"
        @click="pick(winStart + i)"
      >
        {{ opt === null ? (winStart + i === selIdx && placeholder ? placeholder : '—') : fmt(opt) }}
      </div>
      <div :style="{ height: `${bottomPad}px` }" />
    </div>
    <div class="hub-wheel-lines" aria-hidden="true" />
  </div>
</template>

<style scoped>
.hub-wheel {
  border-radius: 0.75rem;
}
.hub-wheel-scroll {
  height: 96px; /* 3 × 32px */
  overflow-y: auto;
  scroll-snap-type: y mandatory;
  padding: 32px 0;
  overscroll-behavior: contain; /* segura o encadeamento mas mantém o amortecedor do iOS nas pontas */
  overflow-anchor: none; /* a janela virtual muda os espaçadores — sem isso o navegador "reancora" o scroll */
  scrollbar-width: none;
  -webkit-mask-image: linear-gradient(to bottom, transparent, #000 34%, #000 66%, transparent);
  mask-image: linear-gradient(to bottom, transparent, #000 34%, #000 66%, transparent);
}
.hub-wheel-scroll::-webkit-scrollbar {
  display: none;
}
.hub-wheel-item {
  height: 32px;
  line-height: 32px;
  text-align: center;
  font-size: 14px;
  letter-spacing: 0.01em;
  scroll-snap-align: center;
  cursor: pointer;
  user-select: none;
}
.hub-wheel-item.is-sel {
  font-weight: 700;
  font-size: 17px;
}
.hub-wheel-lines {
  position: absolute;
  left: 7px;
  right: 7px;
  top: 32px;
  height: 32px;
  border-top: 1px solid rgba(128, 128, 128, 0.3);
  border-bottom: 1px solid rgba(128, 128, 128, 0.3);
  pointer-events: none;
}
</style>
