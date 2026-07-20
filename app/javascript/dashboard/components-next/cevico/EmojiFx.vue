<script setup>
// EFEITOS DE EMOJI reutilizáveis (dopamine CEVICO):
//  · burstAt(x, y, emojis, count) — emojis "pipocam" do ponto do toque
//    (usado nas comemorações do Planejamento e no botão do Radar)
//  · rain(emojis, count) — chuva caindo do topo da tela (ex.: 🚀 no Publicado)
// Overlay fixo, sem capturar cliques; limpa sozinho ao fim da animação.
import { ref } from 'vue';

const pieces = ref([]);
let seq = 0;
let clearTimer = null;

const scheduleClear = ms => {
  clearTimeout(clearTimer);
  clearTimer = setTimeout(() => {
    pieces.value = [];
  }, ms);
};

const burstAt = (x, y, emojis = ['✅'], count = 3) => {
  const batch = Array.from({ length: count }, (_, i) => {
    const angle = -Math.PI / 2 + (Math.random() - 0.5) * Math.PI * 1.2;
    const dist = 50 + Math.random() * 110;
    return {
      id: `b${seq += 1}-${i}`,
      kind: 'burst',
      emoji: emojis[i % emojis.length],
      x,
      y,
      dx: Math.cos(angle) * dist,
      dy: Math.sin(angle) * dist,
      rot: Math.random() * 240 - 120,
      delay: Math.random() * 0.12,
      size: 16 + Math.random() * 10,
    };
  });
  pieces.value = pieces.value.concat(batch);
  scheduleClear(1600);
};

const rain = (emojis = ['🚀'], count = 22) => {
  const batch = Array.from({ length: count }, (_, i) => ({
    id: `r${seq += 1}-${i}`,
    kind: 'rain',
    emoji: emojis[i % emojis.length],
    left: Math.random() * 100,
    sway: Math.random() * 60 - 30,
    rot: Math.random() * 60 - 30,
    delay: Math.random() * 0.9,
    dur: 1.6 + Math.random() * 1.2,
    size: 18 + Math.random() * 14,
  }));
  pieces.value = pieces.value.concat(batch);
  scheduleClear(3900);
};

defineExpose({ burstAt, rain });
</script>

<template>
  <Teleport to="body">
    <div v-if="pieces.length" class="fixed inset-0 pointer-events-none z-[9999] overflow-hidden">
      <span
        v-for="p in pieces"
        :key="p.id"
        class="absolute select-none"
        :class="p.kind === 'burst' ? 'emoji-fx-burst' : 'emoji-fx-rain'"
        :style="p.kind === 'burst'
          ? {
              left: `${p.x}px`, top: `${p.y}px`, fontSize: `${p.size}px`,
              '--dx': `${p.dx}px`, '--dy': `${p.dy}px`, '--rot': `${p.rot}deg`,
              animationDelay: `${p.delay}s`,
            }
          : {
              left: `${p.left}vw`, top: '-8vh', fontSize: `${p.size}px`,
              '--sway': `${p.sway}px`, '--rot': `${p.rot}deg`,
              animationDuration: `${p.dur}s`, animationDelay: `${p.delay}s`,
            }"
      >
        {{ p.emoji }}
      </span>
    </div>
  </Teleport>
</template>

<style scoped>
.emoji-fx-burst {
  opacity: 0;
  animation: emoji-fx-pop 1.25s cubic-bezier(0.16, 1, 0.3, 1) forwards;
}
@keyframes emoji-fx-pop {
  0% { opacity: 0; transform: translate(-50%, -50%) scale(0.3); }
  12% { opacity: 1; transform: translate(-50%, -50%) scale(1.25); }
  100% {
    opacity: 0;
    transform: translate(calc(-50% + var(--dx)), calc(-50% + var(--dy))) scale(0.9) rotate(var(--rot));
  }
}
.emoji-fx-rain {
  opacity: 0;
  animation-name: emoji-fx-fall;
  animation-timing-function: cubic-bezier(0.3, 0, 0.8, 1);
  animation-fill-mode: forwards;
}
@keyframes emoji-fx-fall {
  0% { opacity: 0; transform: translateY(0) translateX(0) rotate(var(--rot)); }
  8% { opacity: 1; }
  85% { opacity: 1; }
  100% {
    opacity: 0;
    transform: translateY(112vh) translateX(var(--sway)) rotate(calc(var(--rot) * -1));
  }
}
</style>
