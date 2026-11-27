<script setup>
// 🎈 27/11 (ele: "a visualização personalizada também tem um balãozinho parecido
// com aquele da agenda que você corrigiu… em todos os lugares, todas as réguas"):
// o balão do "Personalizado" ficava PRESO no bloco da régua — atrás do bloco de
// baixo ("Comparar com", que tem vidro/backdrop-filter e cria camada própria),
// meio transparente e, no celular, cortado pela rolagem lateral da régua.
// Agora ele é desenhado no <body> (Teleport), com fundo cheio, sempre na frente
// e dentro da tela; clicar fora fecha. Leva junto a cor do dia (--cv*) do botão.
import { ref, watch, onBeforeUnmount, nextTick } from 'vue';

const props = defineProps({
  open: { type: Boolean, default: false },
  // elemento ao lado do qual o balão abre (o botão "Personalizado")
  anchor: { type: Object, default: null },
});
const emit = defineEmits(['close']);

const pop = ref(null);
const popStyle = ref({});
const CV_VARS = ['--cv', '--cv-deep', '--cv-rgb', '--cv-deep-rgb', '--cv-grad'];

const place = () => {
  const el = props.anchor;
  if (!el || !pop.value) return;
  const rect = el.getBoundingClientRect();
  const vw = window.innerWidth;
  const width = Math.min(pop.value.offsetWidth || 320, vw - 16);
  // alinhado à direita do botão (como era); se não couber, encosta na margem
  let left = rect.right - width;
  left = Math.max(8, Math.min(left, vw - width - 8));
  const vars = {};
  const cs = getComputedStyle(el);
  CV_VARS.forEach(v => {
    const val = cs.getPropertyValue(v);
    if (val) vars[v] = val.trim();
  });
  popStyle.value = {
    ...vars,
    top: `${Math.round(rect.bottom + 6)}px`,
    left: `${Math.round(left)}px`,
    maxWidth: `${vw - 16}px`,
  };
};

const onMove = () => place();
const listen = on => {
  const fn = on ? window.addEventListener : window.removeEventListener;
  fn('resize', onMove);
  fn('scroll', onMove, true);
};

watch(
  () => props.open,
  async v => {
    listen(false);
    if (!v) return;
    await nextTick();
    place();
    // 2ª passada: a largura real só existe depois de desenhado
    requestAnimationFrame(place);
    listen(true);
  },
  { immediate: true }
);
onBeforeUnmount(() => listen(false));
</script>

<template>
  <Teleport to="body">
    <template v-if="open">
      <!-- véu invisível: clicar fora fecha (sem prender a rolagem) -->
      <div class="fixed inset-0 z-[9998]" @click="emit('close')" />
      <div class="cv-page cv-overlay">
        <div
          ref="pop"
          class="cv-float-pop fixed z-[9999] p-3 flex flex-wrap items-center gap-1.5 sm:gap-2 rounded-2xl border border-n-weak bg-n-solid-1 shadow-2xl"
          :style="popStyle"
          @click.stop
        >
          <slot />
        </div>
      </div>
    </template>
  </Teleport>
</template>

<style scoped>
/* os campos de data herdam uma margem embaixo do estilo geral — no balão, não */
:slotted(input) {
  margin-bottom: 0 !important;
}
</style>
