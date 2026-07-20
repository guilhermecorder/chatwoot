<script setup>
// SKELETON "armadura do Homem de Ferro" (item 89 — 19/07): enquanto os
// dados chegam, o ambiente vai se MONTANDO por partes — cada peça "encaixa"
// com um pequeno salto (delay progressivo pela ordem) e um brilho dourado
// varre a superfície. Nada de tela branca nem spinner solitário.
defineProps({
  // block = retângulo genérico · tile = KPI · line = linha de texto ·
  // title = título curto · circle = avatar/ícone · pill = botão/pílula
  variant: { type: String, default: 'block' },
  order: { type: Number, default: 0 }, // posição na montagem (70ms por peça)
});
</script>

<template>
  <div
    class="cevico-skel"
    :class="{
      'rounded-2xl': variant === 'block',
      'rounded-2xl h-24': variant === 'tile',
      'rounded-md h-3.5': variant === 'line',
      'rounded-lg h-5 w-36': variant === 'title',
      'rounded-full': variant === 'circle',
      'rounded-full h-8 w-24': variant === 'pill',
    }"
    :style="{ animationDelay: `${order * 70}ms` }"
  />
</template>

<style scoped>
.cevico-skel {
  position: relative;
  overflow: hidden;
  background: rgba(100, 116, 139, 0.13);
  opacity: 0;
  animation: cevico-skel-in 0.45s cubic-bezier(0.2, 0.9, 0.3, 1.18) forwards;
}
.cevico-skel::after {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(
    100deg,
    transparent 32%,
    rgba(212, 175, 55, 0.16) 50%,
    transparent 68%
  );
  transform: translateX(-100%);
  animation: cevico-skel-sheen 1.6s ease-in-out infinite;
}
@keyframes cevico-skel-in {
  from {
    opacity: 0;
    transform: translateY(12px) scale(0.97);
  }
  to {
    opacity: 1;
    transform: none;
  }
}
@keyframes cevico-skel-sheen {
  to {
    transform: translateX(100%);
  }
}
@media (prefers-reduced-motion: reduce) {
  .cevico-skel {
    animation-duration: 0.01s;
  }
  .cevico-skel::after {
    animation: none;
  }
}
</style>
