<script setup>
// 🧭 LINHA DO TEMPO CONVERGENTE (kit CEVICO, item 299 — 30/09): todas as fontes
// no MESMO eixo de tempo, uma faixa embaixo da outra (investimento → exibições
// → leads → consultas → cirurgias → receita). O cursor atravessa todas as
// faixas: o que aconteceu naquela semana, em cada fonte, lado a lado.
// Filosofia dele: revelar os dados pelas conexões — de onde veio, como se
// ramifica, pra onde vai.
//   timeline = { granularity, buckets: [{label,start,end}], tracks: [{key,label,
//                source,unit,values,total}], lags: [{text,days,people}], marks, notes }
import { computed, ref, onMounted, onBeforeUnmount } from 'vue';
import { smoothPath } from 'dashboard/helper/cevicoBuckets';

const props = defineProps({
  timeline: { type: Object, default: () => ({}) },
  // versão sem dados financeiros: esconde investimento e receita
  hideMoney: { type: Boolean, default: false },
  trackHeight: { type: Number, default: 74 },
});

const COLORS = {
  spend: '#2563eb',
  impressions: '#0ea5e9',
  link_clicks: '#06b6d4',
  conversations: '#14b8a6',
  leads: '#22c55e',
  booked: '#84cc16',
  attended: '#eab308',
  closed: '#f97316',
  surgeries: '#ef4444',
  revenue: '#a855f7',
};
const GRAN = { day: 'dia a dia', week: 'semana a semana', month: 'mês a mês' };
const BUCKET = { day: 'dia', week: 'semana de', month: 'mês' };

const uid = `ct${Math.random().toString(36).slice(2, 8)}`;
const wrap = ref(null);
const W = ref(720);
let observer = null;
const measure = () => {
  const w = wrap.value?.clientWidth;
  if (w) W.value = Math.max(240, Math.round(w));
};
onMounted(() => {
  measure();
  if (typeof ResizeObserver !== 'undefined' && wrap.value) {
    observer = new ResizeObserver(measure);
    observer.observe(wrap.value);
  }
});
onBeforeUnmount(() => observer?.disconnect());

const PAD = 8;
const TOP = 10;
const buckets = computed(() => props.timeline?.buckets || []);
const n = computed(() => buckets.value.length);
const xAt = i =>
  n.value <= 1 ? W.value / 2 : PAD + (i / (n.value - 1)) * (W.value - PAD * 2);

const money = v =>
  `R$ ${Number(v || 0).toLocaleString('pt-BR', { maximumFractionDigits: 0 })}`;
const count = v => Number(v || 0).toLocaleString('pt-BR');
const fmt = (track, v) => (track.unit === 'money' ? money(v) : count(v));

const tracks = computed(() =>
  (props.timeline?.tracks || [])
    .filter(t => !(props.hideMoney && t.unit === 'money'))
    .map(t => {
      const values = (t.values || []).map(v => Number(v) || 0);
      const max = Math.max(...values, 0);
      const h = props.trackHeight;
      const yAt = v => TOP + (h - TOP - 4) * (1 - (max ? v / max : 0));
      const pts =
        n.value === 1
          ? [
              [PAD, yAt(0)],
              [W.value / 2, yAt(values[0] || 0)],
              [W.value - PAD, yAt(0)],
            ]
          : values.map((v, i) => [xAt(i), yAt(v)]);
      const line = smoothPath(pts);
      const peak = max > 0 ? values.indexOf(max) : -1;
      return {
        ...t,
        values,
        max,
        color: COLORS[t.key] || '#64748b',
        yAt,
        line,
        area: pts.length
          ? `${line} L${pts[pts.length - 1][0].toFixed(1)},${h} L${pts[0][0].toFixed(1)},${h} Z`
          : '',
        peak,
        empty: max === 0,
      };
    })
);

const xLabels = computed(() => {
  const every = Math.max(1, Math.ceil(n.value / 9));
  return buckets.value
    .map((b, i) => ({ label: b.label, i, x: xAt(i) }))
    .filter(l => l.i % every === 0 || l.i === n.value - 1)
    .filter((l, k, arr) => k === 0 || l.x - arr[k - 1].x > 40);
});
const marks = computed(() =>
  (props.timeline?.marks || [])
    .filter(m => m.bucket !== null && m.bucket !== undefined)
    .map(m => ({ ...m, x: xAt(m.bucket) }))
);

// ── cursor que atravessa todas as faixas ──
const hover = ref(-1);
const onMove = event => {
  const rect = wrap.value?.getBoundingClientRect();
  if (!rect || !n.value) return;
  const x = (event.touches?.[0]?.clientX ?? event.clientX) - rect.left;
  const ratio = (x - PAD) / Math.max(1, W.value - PAD * 2);
  hover.value = Math.min(
    n.value - 1,
    Math.max(0, Math.round(ratio * (n.value - 1)))
  );
};
const hoverX = computed(() => (hover.value < 0 ? 0 : xAt(hover.value)));
const hoverBucket = computed(() =>
  hover.value < 0 ? null : buckets.value[hover.value]
);
const lagDays = l => {
  if (!l.days) return 'mesmo dia';
  return `${l.days} ${l.days === 1 ? 'dia' : 'dias'}`;
};
const lagRest = l => String(l.text || '').replace(/^.*?(?=entre )/, '');
const dayLabel = iso =>
  iso ? iso.split('-').reverse().slice(0, 2).join('/') : '';
const hoverTitle = computed(() => {
  const b = hoverBucket.value;
  if (!b) return '';
  const g = props.timeline?.granularity;
  if (g === 'day') return `dia ${dayLabel(b.start)}`;
  if (g === 'month') return `mês ${b.label}`;
  return `${BUCKET.week} ${dayLabel(b.start)} a ${dayLabel(b.end)}`;
});
</script>

<template>
  <div class="cv-ct">
    <p v-if="!tracks.length || !n" class="cv-ct-empty">
      sem dados neste período
    </p>
    <template v-else>
      <p class="cv-ct-lead">
        {{ GRAN[timeline.granularity] || '' }} · passe o mouse (ou o dedo) para
        ver o mesmo momento em todas as fontes
      </p>
      <div class="cv-ct-grid">
        <div class="cv-ct-names">
          <div
            v-for="t in tracks"
            :key="`n${t.key}`"
            class="cv-ct-name"
            :style="{ height: `${trackHeight}px` }"
          >
            <p class="cv-ct-label">
              <span class="cv-ct-dot" :style="{ background: t.color }" />
              {{ t.label }}
            </p>
            <p class="cv-ct-total" :style="{ color: t.color }">
              {{ hover >= 0 ? fmt(t, t.values[hover]) : fmt(t, t.total) }}
            </p>
            <p class="cv-ct-source">
              {{ hover >= 0 ? hoverTitle : `total · ${t.source}` }}
            </p>
          </div>
        </div>
        <div
          ref="wrap"
          class="cv-ct-plot"
          @mousemove="onMove"
          @touchstart.passive="onMove"
          @touchmove.passive="onMove"
          @mouseleave="hover = -1"
        >
          <svg
            v-for="(t, ti) in tracks"
            :key="`s${t.key}`"
            class="cv-ct-track"
            :width="W"
            :height="trackHeight"
            :viewBox="`0 0 ${W} ${trackHeight}`"
            aria-hidden="true"
          >
            <defs>
              <linearGradient :id="`${uid}-${ti}`" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" :stop-color="t.color" stop-opacity="0.45" />
                <stop offset="100%" :stop-color="t.color" stop-opacity="0.03" />
              </linearGradient>
            </defs>
            <line
              v-for="m in marks"
              :key="`m${t.key}${m.date}`"
              class="cv-ct-mark"
              :x1="m.x"
              :x2="m.x"
              y1="0"
              :y2="trackHeight"
            />
            <template v-if="!t.empty">
              <path :d="t.area" :fill="`url(#${uid}-${ti})`" />
              <path
                :d="t.line"
                fill="none"
                :stroke="t.color"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
              <circle
                v-if="t.peak >= 0 && n > 1 && hover < 0"
                :cx="xAt(t.peak)"
                :cy="t.yAt(t.max)"
                r="3.5"
                :fill="t.color"
                stroke="#fff"
                stroke-width="1.5"
              />
            </template>
            <text v-else class="cv-ct-none" :x="W / 2" :y="trackHeight / 2 + 4">
              nada registrado neste período
            </text>
            <g v-if="hover >= 0">
              <line
                class="cv-ct-cursor"
                :x1="hoverX"
                :x2="hoverX"
                y1="0"
                :y2="trackHeight"
              />
              <circle
                v-if="!t.empty && n > 1"
                :cx="hoverX"
                :cy="t.yAt(t.values[hover] || 0)"
                r="4"
                :fill="t.color"
                stroke="#fff"
                stroke-width="2"
              />
            </g>
          </svg>
          <svg
            class="cv-ct-axis"
            :width="W"
            height="34"
            :viewBox="`0 0 ${W} 34`"
            aria-hidden="true"
          >
            <text
              v-for="l in xLabels"
              :key="`x${l.i}`"
              :x="l.x"
              y="14"
              text-anchor="middle"
            >
              {{ l.label }}
            </text>
            <text
              v-for="m in marks"
              :key="`ml${m.date}`"
              class="cv-ct-mark-label"
              :x="Math.min(Math.max(m.x, 50), W - 70)"
              y="30"
              text-anchor="middle"
            >
              ▲ {{ m.label }}
            </text>
          </svg>
        </div>
      </div>
      <div v-if="(timeline.lags || []).length" class="cv-ct-lags">
        <p class="cv-ct-lags-title">O tempo entre um passo e o outro</p>
        <div class="cv-ct-lags-list">
          <span
            v-for="l in timeline.lags"
            :key="`${l.from}${l.to}`"
            class="cv-ct-lag"
            :title="`mediana de ${l.people} paciente(s) que deram os dois passos`"
          >
            <b>{{ lagDays(l) }}</b>
            {{ lagRest(l) }}
          </span>
        </div>
      </div>
      <ul v-if="(timeline.notes || []).length" class="cv-ct-notes">
        <li v-for="note in timeline.notes" :key="note">{{ note }}</li>
      </ul>
    </template>
  </div>
</template>

<style scoped>
.cv-ct-lead {
  font-size: 13px;
  opacity: 0.7;
  margin-bottom: 14px;
}
.cv-ct-empty {
  font-size: 14px;
  opacity: 0.6;
  padding: 24px 0;
  text-align: center;
}
.cv-ct-grid {
  display: grid;
  grid-template-columns: 190px minmax(0, 1fr);
  column-gap: 18px;
}
.cv-ct-name {
  display: flex;
  flex-direction: column;
  justify-content: center;
  margin-bottom: 10px;
  min-width: 0;
}
.cv-ct-label {
  display: flex;
  align-items: center;
  gap: 7px;
  font-size: 13px;
  font-weight: 600;
  line-height: 1.2;
}
.cv-ct-dot {
  width: 9px;
  height: 9px;
  border-radius: 9999px;
  flex-shrink: 0;
}
.cv-ct-total {
  font-size: 22px;
  font-weight: 800;
  line-height: 1.15;
  letter-spacing: -0.01em;
  font-variant-numeric: tabular-nums;
}
.cv-ct-source {
  font-size: 11.5px;
  opacity: 0.6;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.cv-ct-plot {
  position: relative;
  min-width: 0;
  touch-action: pan-y;
}
.cv-ct-track {
  display: block;
  margin-bottom: 10px;
  border-radius: 12px;
  background: rgb(100 116 139 / 0.06);
}
.cv-ct-axis {
  display: block;
}
.cv-ct-axis text {
  font-size: 11.5px;
  fill: rgb(100 116 139);
  font-variant-numeric: tabular-nums;
}
.cv-ct-axis .cv-ct-mark-label {
  font-size: 11px;
  font-weight: 600;
  fill: rgb(71 85 105);
}
.cv-ct-mark {
  stroke: rgb(71 85 105 / 0.45);
  stroke-dasharray: 4 4;
}
.cv-ct-cursor {
  stroke: rgb(15 23 42 / 0.55);
  stroke-width: 1;
}
.dark .cv-ct-cursor {
  stroke: rgb(255 255 255 / 0.6);
}
.cv-ct-none {
  font-size: 12px;
  fill: rgb(100 116 139);
  text-anchor: middle;
}
.cv-ct-lags {
  margin-top: 22px;
}
.cv-ct-lags-title {
  font-size: 14px;
  font-weight: 700;
  margin-bottom: 8px;
}
.cv-ct-lags-list {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.cv-ct-lag {
  padding: 8px 14px;
  border-radius: 14px;
  font-size: 13px;
  background: rgb(var(--cv-rgb, 37 99 235) / 0.08);
  border: 1px solid rgb(var(--cv-rgb, 37 99 235) / 0.18);
}
.cv-ct-lag b {
  font-size: 15px;
  margin-right: 4px;
}
.cv-ct-notes {
  margin-top: 16px;
  font-size: 13px;
  line-height: 1.5;
  opacity: 0.72;
  list-style: disc;
  padding-left: 18px;
}
@media (max-width: 640px) {
  .cv-ct-grid {
    grid-template-columns: 112px minmax(0, 1fr);
    column-gap: 10px;
  }
  .cv-ct-total {
    font-size: 17px;
  }
  .cv-ct-label {
    font-size: 12px;
  }
}
</style>
