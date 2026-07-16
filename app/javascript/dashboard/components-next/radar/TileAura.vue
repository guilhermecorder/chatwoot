<script setup>
// 🏆 Aura de RECORDE dos cards do painel: a nuvem de átomos (a mesma
// linguagem da barra dos formulários) orbita RENTE à borda do card em
// SENTIDO HORÁRIO — cada vez mais forte quando o resultado está na meta
// e acima dela. Canvas leve, respeita prefers-reduced-motion.
import { ref, onMounted, onBeforeUnmount, watch } from 'vue';

const props = defineProps({
  intensity: { type: Number, default: 0.7 }, // 0..1.2 (acima da meta)
  gold: { type: Boolean, default: true },
});

const canvas = ref(null);
let raf = null;
let parts = [];

const rand = (a, b) => a + Math.random() * (b - a);

const spawn = () => ({
  p: Math.random(), // posição no perímetro (0..1, sentido horário)
  off: rand(-4, 7), // distância da borda (rente, com respiro pra fora)
  r: rand(0.6, 2.1),
  tw: rand(0, Math.PI * 2), // fase do brilho
  sp: rand(0.7, 1.3), // velocidade individual
});

// perímetro de um retângulo arredondado → ponto (x, y) no parâmetro t
const pointAt = (t, w, h, rd) => {
  const straightW = w - 2 * rd;
  const straightH = h - 2 * rd;
  const arc = (Math.PI / 2) * rd;
  const total = 2 * straightW + 2 * straightH + 4 * arc;
  let d = ((t % 1) + 1) % 1 * total;

  if (d < straightW) return { x: rd + d, y: 0 };
  d -= straightW;
  if (d < arc) {
    const a = d / rd;
    return { x: w - rd + Math.sin(a) * rd, y: rd - Math.cos(a) * rd };
  }
  d -= arc;
  if (d < straightH) return { x: w, y: rd + d };
  d -= straightH;
  if (d < arc) {
    const a = d / rd;
    return { x: w - rd + Math.cos(a) * rd, y: h - rd + Math.sin(a) * rd };
  }
  d -= arc;
  if (d < straightW) return { x: w - rd - d, y: h };
  d -= straightW;
  if (d < arc) {
    const a = d / rd;
    return { x: rd - Math.sin(a) * rd, y: h - rd + Math.cos(a) * rd };
  }
  d -= arc;
  if (d < straightH) return { x: 0, y: h - rd - d };
  d -= straightH;
  const a = d / rd;
  return { x: rd - Math.cos(a) * rd, y: rd - Math.sin(a) * rd };
};

const tick = () => {
  const cv = canvas.value;
  if (!cv) return;
  const ctx = cv.getContext('2d');
  const dpr = window.devicePixelRatio || 1;
  const rect = cv.getBoundingClientRect();
  if (cv.width !== Math.round(rect.width * dpr)) {
    cv.width = Math.round(rect.width * dpr);
    cv.height = Math.round(rect.height * dpr);
  }
  const W = cv.width;
  const H = cv.height;
  const pad = 8 * dpr; // o card fica 8px pra dentro do canvas
  const k = Math.max(0.15, Math.min(1.2, props.intensity));
  const target = Math.round(12 + 30 * k);
  while (parts.length < target) parts.push(spawn());
  if (parts.length > target) parts.length = target;

  ctx.clearRect(0, 0, W, H);
  const w = W - pad * 2;
  const h = H - pad * 2;
  const rd = 16 * dpr;
  parts.forEach(pt => {
    pt.p += 0.0011 * pt.sp * (0.5 + k); // sentido horário, acelera com a meta
    pt.tw += 0.04;
    const { x, y } = pointAt(pt.p, w, h, rd);
    const alpha = (0.25 + 0.45 * k) * (0.55 + 0.45 * Math.sin(pt.tw));
    ctx.beginPath();
    ctx.arc(pad + x + pt.off * dpr * 0.4, pad + y + pt.off * dpr * 0.4, pt.r * dpr * (0.8 + 0.4 * k), 0, Math.PI * 2);
    ctx.fillStyle = props.gold
      ? `rgba(244, 222, 142, ${alpha})`
      : `rgba(255, 255, 255, ${alpha})`;
    ctx.fill();
  });
  raf = requestAnimationFrame(tick);
};

onMounted(() => {
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  raf = requestAnimationFrame(tick);
});
onBeforeUnmount(() => cancelAnimationFrame(raf));
watch(() => props.intensity, () => {}); // intensidade entra no próximo frame
</script>

<template>
  <canvas
    ref="canvas"
    class="absolute -inset-2 w-[calc(100%+16px)] h-[calc(100%+16px)] pointer-events-none z-[1]"
  />
</template>
