<script setup>
// 🕸️ Teia radar de vidro (0–10 por área). Cresce com o quadro (viewBox), as
// pontas podem ser PUXADAS com o mouse/dedo (de 0,5 em 0,5) e dá para
// mostrar uma teia fantasma tracejada (retrato antigo ou o outro estado).
// 27/09: a ALÇA nunca some no centro — em 0 ela fica um pouco afastada no
// próprio eixo (a teia continua desenhada no valor real), a área de toque é
// maior e clicar no eixo também dá a nota. A média saiu do centro (o quadro
// mostra na legenda).
import { ref } from 'vue';

const props = defineProps({
  axes: { type: Array, required: true }, // [{ key, label }]
  values: { type: Object, required: true }, // { key: 0..10 }
  color: { type: String, default: '#0A84FF' },
  ghost: { type: Object, default: null }, // { key: 0..10 } tracejado
  ghostColor: { type: String, default: '#94A3B8' },
  editable: { type: Boolean, default: true },
  label: { type: String, default: '' },
});
const emit = defineEmits(['set']);

const W = 480;
const H = 350;
const CX = W / 2;
const CY = 180;
const R = 122;
const MAX = 10;
const HANDLE_MIN = 0.9; // a alça nunca cai no centro
const gid = `gr${Math.random().toString(36).slice(2, 8)}`;

const angle = i =>
  -Math.PI / 2 + (i * 2 * Math.PI) / Math.max(props.axes.length, 1);
const pt = (i, v) => {
  const r = (Math.max(0, Math.min(MAX, Number(v) || 0)) / MAX) * R;
  return [CX + r * Math.cos(angle(i)), CY + r * Math.sin(angle(i))];
};
const handlePt = (i, v) => pt(i, Math.max(HANDLE_MIN, Number(v) || 0));
const poly = vals =>
  props.axes
    .map((a, i) =>
      pt(i, vals?.[a.key] ?? 0)
        .map(n => n.toFixed(1))
        .join(',')
    )
    .join(' ');
const rings = [2, 4, 6, 8, 10];
const ringPoly = level =>
  props.axes.map((_, i) => pt(i, level).join(',')).join(' ');
const labelPos = i => {
  const r = R + 18;
  const x = CX + r * Math.cos(angle(i));
  const y =
    CY +
    r * Math.sin(angle(i)) +
    (Math.sin(angle(i)) > 0.5 ? 10 : Math.sin(angle(i)) < -0.5 ? -4 : 0);
  const anchor = Math.abs(x - CX) < 8 ? 'middle' : x > CX ? 'start' : 'end';
  return { x, y, anchor };
};

// ── puxar a ponta / clicar no eixo ──
const svg = ref(null);
const dragging = ref(null);
const valueAt = (i, e) => {
  const p = svg.value.createSVGPoint();
  p.x = e.clientX;
  p.y = e.clientY;
  const loc = p.matrixTransform(svg.value.getScreenCTM().inverse());
  const ux = Math.cos(angle(i));
  const uy = Math.sin(angle(i));
  const t = ((loc.x - CX) * ux + (loc.y - CY) * uy) / R;
  return Math.round(Math.max(0, Math.min(1, t)) * MAX * 2) / 2;
};
const onMove = e => {
  if (dragging.value === null) return;
  e.preventDefault();
  const i = dragging.value;
  emit('set', props.axes[i].key, valueAt(i, e));
};
const onUp = () => {
  dragging.value = null;
  window.removeEventListener('pointermove', onMove);
  window.removeEventListener('pointerup', onUp);
};
const grab = (i, e) => {
  if (!props.editable) return;
  e.stopPropagation();
  e.preventDefault();
  dragging.value = i;
  emit('set', props.axes[i].key, valueAt(i, e));
  window.addEventListener('pointermove', onMove, { passive: false });
  window.addEventListener('pointerup', onUp);
};
</script>

<template>
  <div class="biz-radar" data-no-drag>
    <svg
      ref="svg"
      :viewBox="`0 0 ${W} ${H}`"
      class="biz-radar-svg"
      role="img"
      :aria-label="label"
    >
      <defs>
        <radialGradient :id="`${gid}-bg`" cx="50%" cy="45%" r="60%">
          <stop offset="0%" :stop-color="color" stop-opacity="0.1" />
          <stop offset="70%" :stop-color="color" stop-opacity="0.03" />
          <stop offset="100%" :stop-color="color" stop-opacity="0" />
        </radialGradient>
        <linearGradient :id="`${gid}-fill`" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" :stop-color="color" stop-opacity="0.3" />
          <stop offset="100%" :stop-color="color" stop-opacity="0.08" />
        </linearGradient>
        <filter
          :id="`${gid}-glow`"
          x="-20%"
          y="-20%"
          width="140%"
          height="140%"
        >
          <feGaussianBlur stdDeviation="4" result="b" />
          <feMerge>
            <feMergeNode in="b" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
      </defs>
      <circle
        :cx="CX"
        :cy="CY"
        :r="R + 10"
        :fill="`url(#${gid}-bg)`"
        class="biz-radar-disc"
      />
      <polygon
        v-for="lv in rings"
        :key="lv"
        :points="ringPoly(lv)"
        class="biz-radar-ring"
        :class="{ 'biz-radar-ring-outer': lv === 10 }"
      />
      <g v-for="(a, i) in axes" :key="`ax${a.key}`">
        <line
          :x1="CX"
          :y1="CY"
          :x2="pt(i, 10)[0]"
          :y2="pt(i, 10)[1]"
          class="biz-radar-axis"
        />
        <!-- faixa larga invisível: clicar em qualquer ponto do eixo dá a nota -->
        <line
          v-if="editable"
          :x1="CX"
          :y1="CY"
          :x2="pt(i, 10)[0]"
          :y2="pt(i, 10)[1]"
          class="biz-radar-axis-hit"
          @pointerdown="grab(i, $event)"
        />
      </g>
      <polygon
        v-if="ghost"
        :points="poly(ghost)"
        class="biz-radar-ghost"
        :style="{ stroke: ghostColor }"
      />
      <polygon
        :points="poly(values)"
        :fill="`url(#${gid}-fill)`"
        :stroke="color"
        stroke-width="2.5"
        stroke-linejoin="round"
        :filter="`url(#${gid}-glow)`"
        class="biz-radar-shape"
      />
      <g v-for="(a, i) in axes" :key="`pt${a.key}`">
        <circle
          :cx="pt(i, values[a.key] ?? 0)[0]"
          :cy="pt(i, values[a.key] ?? 0)[1]"
          r="3"
          :fill="color"
        />
        <g
          v-if="editable"
          class="biz-radar-handle"
          :class="{ on: dragging === i }"
          @pointerdown="grab(i, $event)"
        >
          <circle
            :cx="handlePt(i, values[a.key] ?? 0)[0]"
            :cy="handlePt(i, values[a.key] ?? 0)[1]"
            r="16"
            fill="transparent"
          />
          <circle
            :cx="handlePt(i, values[a.key] ?? 0)[0]"
            :cy="handlePt(i, values[a.key] ?? 0)[1]"
            :r="dragging === i ? 8 : 6"
            class="biz-radar-dot"
            :stroke="color"
          />
        </g>
        <text
          :x="labelPos(i).x"
          :y="labelPos(i).y - 6"
          :text-anchor="labelPos(i).anchor"
          class="biz-radar-label"
        >
          {{ a.label }}
        </text>
        <text
          :x="labelPos(i).x"
          :y="labelPos(i).y + 12"
          :text-anchor="labelPos(i).anchor"
          class="biz-radar-value"
          :fill="color"
        >
          {{ Number(values[a.key] ?? 0).toLocaleString('pt-BR') }}
        </text>
      </g>
    </svg>
  </div>
</template>
