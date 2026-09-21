<script setup>
// RADAR (teia) do HUB — rodada 30b. Nasceu do RadarChart da área de
// Pessoas, com o que faltava pro HUB: rótulos com folga e ancorados por
// lado (nada cortado), preenchimento em degradê da paleta, piso mínimo
// (a forma não colapsa no centro quando um eixo é zero), pontos com
// borda branca e legenda opcional. Valores 0–100 por eixo.
import { computed } from 'vue';

const props = defineProps({
  axes: { type: Array, required: true }, // [{ key, label, color? }]
  datasets: { type: Array, required: true }, // [{ label, color, values: {key: 0..100} }]
  size: { type: Number, default: 240 },
  floor: { type: Number, default: 6 }, // % mínimo desenhado (só visual)
  legend: { type: Boolean, default: true },
  labelSize: { type: Number, default: 10 },
  // rodada 31: folga lateral e margem em fração do tamanho — o card de tela
  // inteira do PROGRESSO usa folgas menores pra teia crescer
  exRatio: { type: Number, default: 0.22 },
  padRatio: { type: Number, default: 0.2 },
});

const uid = `hr${Math.random().toString(36).slice(2, 8)}`;
// folga horizontal extra no viewBox: rótulos laterais ("Sequências",
// "Movimento") cabem inteiros sem depender de overflow
// rótulo em até 2 linhas (quebra no espaço mais perto do meio) — nada de
// reticências: "todas as palavras encaixem perfeitamente" (pedido dele 19/09)
const linesOf = label => {
  const t = String(label || '').trim();
  if (t.length <= 12 || !t.includes(' ')) return [t];
  const mid = t.length / 2;
  let best = -1;
  for (let i = 0; i < t.length; i += 1) if (t[i] === ' ' && (best < 0 || Math.abs(i - mid) < Math.abs(best - mid))) best = i;
  return [t.slice(0, best), t.slice(best + 1)];
};
const lineH = computed(() => Math.round(props.labelSize * 1.15));
const pad = computed(() => Math.max(36, Math.round(props.size * props.padRatio)));
// folga lateral = o que cada rótulo realmente precisa na SUA posição
// (≈ 0,58 em por caractere): um rótulo largo no topo não pede folga
// lateral, um no lado pede a largura inteira — a teia fica a maior possível
const ex = computed(() => {
  const n = Math.max(3, props.axes.length);
  const radius = props.size / 2 - pad.value;
  let need = 0;
  props.axes.forEach((ax, i) => {
    const c = Math.cos((Math.PI * 2 * i) / n - Math.PI / 2);
    const w = Math.max(...linesOf(ax.label).map(l => l.length)) * props.labelSize * 0.58;
    const side = Math.abs(c) > 0.35;
    const reach = Math.abs(c) * (radius + 12) + (side ? w : w / 2);
    need = Math.max(need, reach - props.size / 2);
  });
  return Math.round(Math.max(props.size * props.exRatio, need + 6));
});
const cx = computed(() => props.size / 2);
const cy = computed(() => props.size / 2);
const radius = computed(() => props.size / 2 - pad.value);
const n = computed(() => Math.max(3, props.axes.length));

const angleOf = i => (Math.PI * 2 * i) / n.value - Math.PI / 2;
const pointAt = (i, pct) => {
  const a = angleOf(i);
  const r = (Math.max(0, Math.min(100, pct)) / 100) * radius.value;
  return [cx.value + r * Math.cos(a), cy.value + r * Math.sin(a)];
};
const valueOf = (ds, axis) => {
  const v = Number(ds.values?.[axis.key]) || 0;
  return v > 0 ? Math.max(props.floor, v) : props.floor;
};
const polygonOf = ds => props.axes.map((ax, i) => pointAt(i, valueOf(ds, ax)).join(',')).join(' ');
const rings = [0.25, 0.5, 0.75, 1];
const ringPoints = k => props.axes.map((_a, i) => pointAt(i, k * 100).join(',')).join(' ');

// rótulo: fora da teia, ancorado conforme o lado (esq/dir/topo/base)
const labelOf = i => {
  const a = angleOf(i);
  const r = radius.value + 12;
  const x = cx.value + r * Math.cos(a);
  const y = cy.value + r * Math.sin(a);
  const c = Math.cos(a);
  const s = Math.sin(a);
  const anchor = c > 0.35 ? 'start' : c < -0.35 ? 'end' : 'middle';
  const lines = linesOf(props.axes[i]?.label);
  // topo: sobe o bloco inteiro (2 linhas ficam acima do vértice); base: desce;
  // lados: centraliza verticalmente as linhas
  let dy = s < -0.8 ? -3 - (lines.length - 1) * lineH.value : s > 0.8 ? 9 : 4;
  if (Math.abs(s) <= 0.8 && lines.length > 1) dy -= Math.round(lineH.value / 2);
  return { x, y, anchor, dy, lines };
};
// cor do rótulo: os 2 tons padrão viram classes (o CSS troca pro claro no
// modo escuro); só uma cor realmente própria entra como estilo inline
const DEFAULT_TONES = ['#27408B', '#B85C00'];
const toneOf = (ax, i) => {
  const c = String(ax.color || '').toUpperCase();
  if (c === DEFAULT_TONES[1]) return 'tone-b';
  if (c === DEFAULT_TONES[0]) return 'tone-a';
  return i % 2 ? 'tone-b' : 'tone-a';
};
const ownColor = ax => (ax.color && !DEFAULT_TONES.includes(String(ax.color).toUpperCase()) ? { fill: ax.color } : null);
</script>

<template>
  <div class="hub-radar">
    <svg :viewBox="`${-ex} 0 ${size + ex * 2} ${size}`" class="hub-radar-svg" :style="{ maxWidth: `${size + ex * 2}px` }">
      <defs>
        <radialGradient v-for="(ds, di) in datasets" :id="`${uid}-g${di}`" :key="`g-${di}`" cx="50%" cy="50%" r="60%">
          <stop offset="0%" :stop-color="ds.color" stop-opacity="0.45" />
          <stop offset="100%" :stop-color="ds.color" stop-opacity="0.12" />
        </radialGradient>
      </defs>
      <!-- teia -->
      <polygon v-for="k in rings" :key="k" :points="ringPoints(k)" fill="none" class="hub-radar-ring" :class="{ 'is-outer': k === 1 }" />
      <line v-for="(ax, i) in axes" :key="`ax-${ax.key}`" :x1="cx" :y1="cy" :x2="pointAt(i, 100)[0]" :y2="pointAt(i, 100)[1]" class="hub-radar-axis" />
      <!-- conjuntos -->
      <g v-for="(ds, di) in datasets" :key="`ds-${di}`" class="hub-radar-set">
        <polygon :points="polygonOf(ds)" :fill="`url(#${uid}-g${di})`" :stroke="ds.color" stroke-width="2" stroke-linejoin="round" />
        <circle
          v-for="(ax, i) in axes"
          :key="`p-${di}-${ax.key}`"
          :cx="pointAt(i, valueOf(ds, ax))[0]"
          :cy="pointAt(i, valueOf(ds, ax))[1]"
          r="3.2"
          :fill="ds.color"
          stroke="#fff"
          stroke-width="1.4"
        />
      </g>
      <!-- rótulos -->
      <text
        v-for="(ax, i) in axes"
        :key="`l-${ax.key}`"
        :x="labelOf(i).x"
        :y="labelOf(i).y + labelOf(i).dy"
        :text-anchor="labelOf(i).anchor"
        :font-size="labelSize"
        font-weight="700"
        class="hub-radar-label"
        :class="toneOf(ax, i)"
        :style="ownColor(ax)"
      >
        <tspan v-for="(ln, li) in labelOf(i).lines" :key="li" :x="labelOf(i).x" :dy="li ? lineH : 0">{{ ln }}</tspan>
      </text>
    </svg>
    <div v-if="legend && datasets.length" class="hub-radar-legend">
      <span v-for="(ds, di) in datasets" :key="`lg-${di}`">
        <i :style="{ background: ds.color }" />{{ ds.label }}
      </span>
    </div>
  </div>
</template>

<style scoped>
.hub-radar { width: 100%; }
.hub-radar-svg { width: 100%; height: auto; display: block; margin: 0 auto; overflow: visible; }
.hub-radar-ring { stroke: rgba(65, 105, 225, 0.22); stroke-width: 0.8; }
.hub-radar-ring.is-outer { stroke: rgba(65, 105, 225, 0.4); stroke-width: 1; }
.hub-radar-axis { stroke: rgba(65, 105, 225, 0.18); stroke-width: 0.8; }
.hub-radar-set { animation: hub-radar-in 0.6s cubic-bezier(0.2, 0.9, 0.3, 1) both; transform-origin: center; }
@keyframes hub-radar-in {
  from { opacity: 0; transform: scale(0.6); }
  to { opacity: 1; transform: none; }
}
/* fonte limpa, sem contorno/sombra; azul e laranja de alto contraste nos 2 modos */
.hub-radar-label { letter-spacing: 0; stroke: none; paint-order: fill; text-shadow: none; font-family: inherit; }
.hub-radar-label.tone-a { fill: #3b5bdb; }
/* laranja = o mesmo LARANJA da paleta (#ff8a00), como nos números do painel */
.hub-radar-label.tone-b { fill: #e07800; }
:global(.dark) .hub-radar-label.tone-a { fill: #9db8ff; }
:global(.dark) .hub-radar-label.tone-b { fill: #ff8a00; }
:global(.dark) .hub-radar-ring { stroke: rgba(195, 208, 255, 0.3); }
:global(.dark) .hub-radar-ring.is-outer { stroke: rgba(195, 208, 255, 0.6); }
:global(.dark) .hub-radar-axis { stroke: rgba(195, 208, 255, 0.26); }
.hub-radar-legend { display: flex; justify-content: center; gap: 12px; flex-wrap: wrap; margin-top: 2px; font-size: 11px; font-weight: 600; color: #334155; }
.hub-radar-legend span { display: inline-flex; align-items: center; gap: 5px; }
.hub-radar-legend i { width: 9px; height: 9px; border-radius: 50%; display: inline-block; }
:global(.dark) .hub-radar-legend { color: #c7d3ff; }
@media (prefers-reduced-motion: reduce) { .hub-radar-set { animation: none; } }
</style>
