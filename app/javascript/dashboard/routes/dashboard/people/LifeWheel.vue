<script setup>
// RODA DA VIDA: 8 áreas coloridas em fatias que crescem até a nota (0-10),
// média no centro e, quando existe avaliação anterior, o polígono de
// comparação por cima (evolução visível) — moderna, leve e animada.
import { ref, computed, watch, onMounted } from 'vue';
import { WHEEL_AREAS } from './discQuiz';

const props = defineProps({
  scores: { type: Object, required: true }, // { carreira: 7, ... } 0-10
  previous: { type: Object, default: null }, // avaliação anterior (opcional)
  size: { type: Number, default: 340 },
});

const cx = computed(() => props.size / 2);
const cy = computed(() => props.size / 2);
const R = computed(() => props.size / 2 - 42); // raio máximo (nota 10)
const R0 = 26; // miolo (círculo central)

// animação: as fatias CRESCEM até a nota (mola suave)
const progress = ref(0);
const animate = () => {
  progress.value = 0;
  const start = performance.now();
  const dur = 900;
  const tick = now => {
    const t = Math.min(1, (now - start) / dur);
    progress.value = 1 - (1 - t) ** 3; // ease-out cúbico
    if (t < 1) requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
};
onMounted(animate);
watch(() => props.scores, animate, { deep: true });

const slice = 360 / WHEEL_AREAS.length;
const GAP = 2.5; // graus de respiro entre fatias

const polar = (angleDeg, r) => {
  const a = ((angleDeg - 90) * Math.PI) / 180;
  return [cx.value + r * Math.cos(a), cy.value + r * Math.sin(a)];
};

// fatia em anel: do miolo até o raio da nota
const wedgePath = (i, score) => {
  const r = R0 + (Math.max(0, Math.min(10, score)) / 10) * (R.value - R0) * progress.value;
  const a0 = i * slice + GAP / 2;
  const a1 = (i + 1) * slice - GAP / 2;
  const [x0, y0] = polar(a0, R0);
  const [x1, y1] = polar(a0, r);
  const [x2, y2] = polar(a1, r);
  const [x3, y3] = polar(a1, R0);
  const large = a1 - a0 > 180 ? 1 : 0;
  return `M ${x0} ${y0} L ${x1} ${y1} A ${r} ${r} 0 ${large} 1 ${x2} ${y2} L ${x3} ${y3} A ${R0} ${R0} 0 ${large} 0 ${x0} ${y0} Z`;
};

// pontos do polígono de comparação (centro da fatia, raio da nota anterior)
const prevPoints = computed(() => {
  if (!props.previous) return '';
  return WHEEL_AREAS.map((area, i) => {
    const score = Number(props.previous[area.key]) || 0;
    const r = R0 + (score / 10) * (R.value - R0);
    return polar(i * slice + slice / 2, r).join(',');
  }).join(' ');
});
const prevDots = computed(() => {
  if (!props.previous) return [];
  return WHEEL_AREAS.map((area, i) => {
    const score = Number(props.previous[area.key]) || 0;
    const r = R0 + (score / 10) * (R.value - R0);
    const [x, y] = polar(i * slice + slice / 2, r);
    return { x, y, key: area.key };
  });
});

const labelPos = i => {
  const [x, y] = polar(i * slice + slice / 2, R.value + 24);
  return { x, y };
};

const average = computed(() => {
  const vals = WHEEL_AREAS.map(a => Number(props.scores[a.key]) || 0);
  const sum = vals.reduce((s, v) => s + v, 0);
  return Math.round((sum / WHEEL_AREAS.length) * 10) / 10;
});

const rings = [0.2, 0.4, 0.6, 0.8, 1];
</script>

<template>
  <svg :viewBox="`0 0 ${size} ${size}`" class="w-full max-w-[420px] mx-auto select-none">
    <!-- trilhas circulares -->
    <circle
      v-for="ring in rings"
      :key="ring"
      :cx="cx"
      :cy="cy"
      :r="R0 + ring * (R - R0)"
      fill="none"
      stroke="currentColor"
      class="text-n-slate-6"
      stroke-width="0.75"
      opacity="0.45"
    />
    <!-- fatias coloridas -->
    <path
      v-for="(area, i) in WHEEL_AREAS"
      :key="area.key"
      :d="wedgePath(i, Number(scores[area.key]) || 0)"
      :fill="area.color"
      fill-opacity="0.88"
      stroke="rgba(255,255,255,0.35)"
      stroke-width="1"
    >
      <title>{{ area.label }}: {{ Number(scores[area.key]) || 0 }}/10</title>
    </path>
    <!-- comparação com a avaliação anterior -->
    <template v-if="previous">
      <polygon :points="prevPoints" fill="none" stroke="#0f172a" stroke-opacity="0.75" stroke-width="1.75" stroke-linejoin="round" class="dark:opacity-90" />
      <circle v-for="d in prevDots" :key="d.key" :cx="d.x" :cy="d.y" r="3.5" fill="#0f172a" stroke="#fff" stroke-width="1.25" />
    </template>
    <!-- centro: média -->
    <circle :cx="cx" :cy="cy" :r="R0 - 2" fill="#0f172a" />
    <text :x="cx" :y="cy + 1" text-anchor="middle" dominant-baseline="middle" fill="#fff" class="text-base font-black">
      {{ average }}
    </text>
    <!-- rótulos -->
    <text
      v-for="(area, i) in WHEEL_AREAS"
      :key="`t-${area.key}`"
      :x="labelPos(i).x"
      :y="labelPos(i).y"
      text-anchor="middle"
      dominant-baseline="middle"
      class="text-[10px] font-bold"
      :fill="area.color"
    >
      {{ area.label }}
    </text>
  </svg>
</template>
