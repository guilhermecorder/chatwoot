<script setup>
// 📉 Curva de retenção DETALHADA (item 287): gráfico de ÁREA suave com degradê.
// Rodada 4: tudo fala em TEMPO e em ZONA — o eixo mostra o marco e o segundo
// ("25% · 8 s"), o fundo tem as faixas Gancho · Corpo · CTA e cada queda diz
// em que zona e em que segundo aconteceu. Linha tracejada = média da conta;
// faixas numeradas = as maiores quedas. Ao passar o mouse: o segundo, a zona,
// a % que ainda assiste, quantas chegaram ali e a fala daquele trecho.
// Dados: `retention_detail` do detalhe do anúncio (Crm::AdRetentionCurve).
import { computed, ref, onMounted, onBeforeUnmount } from 'vue';
import { smoothPath } from 'dashboard/helper/cevicoBuckets';
import { fmtPct, fmtNum } from './creativeFormat';

const props = defineProps({
  detail: { type: Object, required: true },
  color: { type: String, default: '#2563eb' },
});

// no celular o desenho é mais estreito, para as letras não encolherem
const wrapRef = ref(null);
const narrow = ref(false);
let observer = null;
const measure = () => {
  const width = wrapRef.value ? wrapRef.value.clientWidth : 0;
  if (width) narrow.value = width < 560;
};
onMounted(() => {
  measure();
  if (typeof ResizeObserver !== 'undefined' && wrapRef.value) {
    observer = new ResizeObserver(measure);
    observer.observe(wrapRef.value);
  }
});
onBeforeUnmount(() => observer && observer.disconnect());
const W = computed(() => (narrow.value ? 400 : 760));
const H = computed(() => (narrow.value ? 350 : 360));
const PAD = computed(() => ({
  l: narrow.value ? 42 : 50,
  r: narrow.value ? 14 : 20,
  t: 52,
  b: 46,
}));
const GRID = [0, 0.25, 0.5, 0.75, 1];
const ZONE_TINT = { hook: '#7c3aed', body: '#0891b2', cta: '#d97706' };
const DROP_TONE = ['#dc2626', '#d97706'];
const uid = `cv-ret-${Math.random().toString(36).slice(2, 8)}`;

const svgRef = ref(null);
const hover = ref(null);

const has = v => v !== null && v !== undefined;
const points = computed(() => props.detail.points || []);
const isSeconds = computed(() => props.detail.axis === 'seconds');
const isCurve = computed(() => props.detail.source === 'meta_curve');
const xMax = computed(() => {
  const list = points.value;
  if (!list.length) return 1;
  return (isSeconds.value ? list[list.length - 1].t : list.length - 1) || 1;
});
const px = v =>
  PAD.value.l + (W.value - PAD.value.l - PAD.value.r) * (v / xMax.value);
const py = v =>
  PAD.value.t +
  (H.value - PAD.value.t - PAD.value.b) *
    (1 - Math.max(0, Math.min(1, v || 0)));
const coords = list =>
  list.map((p, i) => [px(isSeconds.value ? p.t : i), py(p.pct)]);

const line = computed(() => coords(points.value));
const linePath = computed(() => smoothPath(line.value));
const areaPath = computed(() => {
  const l = line.value;
  if (l.length < 2) return '';
  return `${linePath.value} L${l[l.length - 1][0].toFixed(1)},${py(0)} L${l[0][0].toFixed(1)},${py(0)} Z`;
});
const averagePath = computed(() => {
  const avg = props.detail.average || [];
  return avg.length > 1 ? smoothPath(coords(avg)) : '';
});

// eixo X: com a curva da Meta, segundos redondos; só com os marcos, o marco e
// o segundo juntos ("25% · 8 s")
const xTicks = computed(() => {
  if (!isSeconds.value || !isCurve.value)
    return points.value.map((p, i) => ({
      x: px(isSeconds.value ? p.t : i),
      label:
        narrow.value && isSeconds.value ? `${p.t} s` : p.axis_label || p.label,
      strong: true,
    }));
  let step = 10;
  if (xMax.value <= 20) step = 2;
  else if (xMax.value <= 45) step = 5;
  if (narrow.value) step *= 2;
  const ticks = [];
  for (let s = 0; s <= xMax.value; s += step)
    ticks.push({ x: px(s), label: `${s} s` });
  return ticks;
});
const marks = computed(() =>
  isSeconds.value && isCurve.value
    ? (props.detail.marks || [])
        .filter(m => has(m.t) && m.t <= xMax.value)
        .map(m => ({
          ...m,
          x: px(m.t),
          end: m.t >= xMax.value,
          text: narrow.value ? m.label : m.axis_label || m.label,
        }))
    : []
);
const zones = computed(() =>
  isSeconds.value
    ? (props.detail.zones || [])
        .filter(z => z.from < xMax.value)
        .map(z => {
          const from = px(z.from);
          const to = px(Math.min(z.to, xMax.value));
          return {
            ...z,
            x: from,
            width: Math.max(to - from, 2),
            mid: (from + to) / 2,
            tint: ZONE_TINT[z.key] || '#64748b',
          };
        })
    : []
);
const zoneAt = t => {
  const list = props.detail.zones || [];
  if (!has(t) || !list.length) return null;
  return list.find(z => t >= z.from && t < z.to) || list[list.length - 1];
};

const indexOfLabel = label => points.value.findIndex(p => p.label === label);
const dropList = computed(() => {
  const list = props.detail.top_drops || [];
  if (list.length) return list;
  return props.detail.biggest_drop
    ? [{ ...props.detail.biggest_drop, rank: 1 }]
    : [];
});
const dropBands = computed(() =>
  dropList.value.map(d => {
    const from = px(isSeconds.value ? d.from_t : indexOfLabel(d.from_label));
    const to = px(isSeconds.value ? d.to_t : indexOfLabel(d.to_label));
    return {
      rank: d.rank,
      x: from,
      width: Math.max(to - from, 3),
      mid: (from + to) / 2,
      tone: DROP_TONE[d.rank === 1 ? 0 : 1],
    };
  })
);

const segmentAt = t => {
  if (!isSeconds.value || !has(t)) return null;
  return (
    (props.detail.segments || []).find(s => t >= s.start && t <= s.end) || null
  );
};
const averageAt = t => {
  const found = (props.detail.average || []).find(a => a.t === t);
  return found ? found.pct : null;
};
const baseWord = computed(() =>
  props.detail.base === 'plays' ? 'reproduções' : 'exibições'
);

const onMove = evt => {
  const svg = svgRef.value;
  if (!svg || !line.value.length) return;
  const rect = svg.getBoundingClientRect();
  const point = evt.touches ? evt.touches[0] : evt;
  const x = ((point.clientX - rect.left) / rect.width) * W.value;
  let best = 0;
  line.value.forEach((c, i) => {
    if (Math.abs(c[0] - x) < Math.abs(line.value[best][0] - x)) best = i;
  });
  const p = points.value[best];
  const [cx, cy] = line.value[best];
  const seg = segmentAt(p.t);
  const zone = isSeconds.value ? zoneAt(p.t) : null;
  hover.value = {
    cx,
    cy,
    point: p,
    title: p.axis_label || p.label,
    zone: zone ? zone.label : '',
    average: isSeconds.value ? averageAt(p.t) : null,
    speech: seg ? seg.text : '',
    style: {
      position: 'absolute',
      left: `${Math.min((cx / W.value) * 100 + 2, 62)}%`,
      top: `${Math.max((cy / H.value) * 100 - 36, 0)}%`,
    },
  };
};
const onLeave = () => {
  hover.value = null;
};

const num = v => String(Math.round(Number(v) * 10) / 10).replace('.', ',');
const secs = v => `${num(v)} s`;
const points100 = v =>
  `${(Number(v || 0) * 100).toFixed(1).replace('.', ',')} pontos`;
const drops = computed(() =>
  dropList.value.map(d => ({
    ...d,
    tone: DROP_TONE[d.rank === 1 ? 0 : 1],
    where:
      has(d.from_t) && has(d.to_t)
        ? `do segundo ${num(d.from_t)} ao ${num(d.to_t)}`
        : `de ${d.from_label} a ${d.to_label}`,
  }))
);
// a leitura em uma frase, na mesma base do gráfico
const reading = computed(() => {
  const d = props.detail;
  const mark = key => (d.marks || []).find(m => m.key === key);
  const half = mark('p50');
  const end = mark('p100');
  if (!half || !end || half.pct === null || end.pct === null) return '';
  return `${fmtPct(half.pct, 0)} ${d.base_label} chegam à metade do vídeo e ${fmtPct(end.pct, 0)} vão até o fim.`;
});
const sourceText = computed(() => {
  const d = props.detail;
  if (isCurve.value)
    return `De onde vem: a Meta informa, segundo a segundo, quantos por cento das reproduções ainda estavam assistindo. Base: ${fmtNum(d.base_total)} reproduções (${d.curve_days} de ${d.period_days} dias do período têm a curva detalhada).`;
  return `De onde vem: a Meta informa quantas pessoas chegaram a cada marco do vídeo. Base: ${fmtNum(d.base_total)} exibições. A curva segundo a segundo aparece depois da próxima carga de dados da Meta.`;
});
</script>

<template>
  <div class="w-full">
    <p v-if="reading" class="text-base text-n-slate-12 mb-2 leading-relaxed">
      {{ reading }}
    </p>
    <p class="text-sm text-n-slate-10 mb-2 leading-relaxed">
      {{ sourceText }}
      <template v-if="detail.duration">
        Duração do vídeo: {{ secs(detail.duration)
        }}{{ detail.duration_estimated ? ' (estimada pela curva)' : '' }}.
      </template>
      <template v-if="detail.avg_watch">
        Tempo médio assistido: {{ secs(detail.avg_watch) }}.
      </template>
    </p>
    <p v-if="detail.duration_note" class="ra-note px-5 py-4 mb-3 text-sm">
      {{ detail.duration_note }}
    </p>
    <p v-if="detail.zones_note" class="text-[13px] text-n-slate-10 mb-4">
      {{ detail.zones_note }}
    </p>

    <div ref="wrapRef" class="relative">
      <svg
        ref="svgRef"
        :viewBox="`0 0 ${W} ${H}`"
        class="w-full h-auto select-none"
        role="img"
        aria-label="Curva de retenção do vídeo, com as zonas e as maiores quedas"
        @mousemove="onMove"
        @mouseleave="onLeave"
        @touchstart.passive="onMove"
        @touchmove.passive="onMove"
      >
        <defs>
          <linearGradient :id="uid" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" :stop-color="color" stop-opacity="0.5" />
            <stop offset="100%" :stop-color="color" stop-opacity="0.03" />
          </linearGradient>
        </defs>
        <g v-for="z in zones" :key="`zone-${z.key}`">
          <rect
            :x="z.x"
            :y="PAD.t"
            :width="z.width"
            :height="H - PAD.t - PAD.b"
            :fill="z.tint"
            opacity="0.07"
          />
          <rect
            :x="z.x + 1"
            :y="PAD.t - 42"
            :width="Math.max(z.width - 2, 1)"
            height="20"
            rx="6"
            :fill="z.tint"
            opacity="0.16"
          />
          <text
            :x="z.mid"
            :y="PAD.t - 28"
            text-anchor="middle"
            :fill="z.tint"
            font-size="12"
            font-weight="800"
          >
            {{ z.label }}
          </text>
        </g>
        <g v-for="g in GRID" :key="g">
          <line
            :x1="PAD.l"
            :x2="W - PAD.r"
            :y1="py(g)"
            :y2="py(g)"
            class="stroke-n-slate-6"
            stroke-width="0.7"
          />
          <text
            :x="PAD.l - 8"
            :y="py(g) + 4"
            text-anchor="end"
            class="fill-n-slate-10"
            font-size="12"
          >
            {{ Math.round(g * 100) }}%
          </text>
        </g>
        <rect
          v-for="b in dropBands"
          :key="`band${b.rank}`"
          :x="b.x"
          :y="PAD.t"
          :width="b.width"
          :height="H - PAD.t - PAD.b"
          :fill="b.tone"
          :opacity="b.rank === 1 ? 0.16 : 0.12"
          rx="4"
        />
        <text
          v-for="t in xTicks"
          :key="`x${t.x}`"
          :x="t.x"
          :y="H - 14"
          text-anchor="middle"
          :class="t.strong ? 'fill-n-slate-12' : 'fill-n-slate-10'"
          :font-size="t.strong ? 12.5 : 12"
          :font-weight="t.strong ? 700 : 400"
        >
          {{ t.label }}
        </text>
        <g v-for="m in marks" :key="m.key">
          <line
            :x1="m.x"
            :x2="m.x"
            :y1="PAD.t"
            :y2="H - PAD.b"
            class="stroke-n-slate-8"
            stroke-width="0.8"
            stroke-dasharray="3 4"
          />
          <text
            :x="m.x"
            :y="PAD.t - 6"
            :text-anchor="m.end ? 'end' : 'middle'"
            class="fill-n-slate-11"
            font-size="11.5"
            font-weight="700"
          >
            {{ m.text }}
          </text>
        </g>
        <path :d="areaPath" :fill="`url(#${uid})`" />
        <path
          v-if="averagePath"
          :d="averagePath"
          fill="none"
          stroke="#94a3b8"
          stroke-width="2"
          stroke-dasharray="6 5"
          stroke-linecap="round"
        />
        <path
          :d="linePath"
          fill="none"
          :stroke="color"
          stroke-width="2.8"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
        <g v-if="!isCurve">
          <circle
            v-for="(c, i) in line"
            :key="`dot${i}`"
            :cx="c[0]"
            :cy="c[1]"
            r="4"
            :fill="color"
            class="stroke-n-surface-1"
            stroke-width="1.5"
          />
        </g>
        <g v-for="b in dropBands" :key="`rank${b.rank}`">
          <circle :cx="b.mid" :cy="H - PAD.b - 14" r="10" :fill="b.tone" />
          <text
            :x="b.mid"
            :y="H - PAD.b - 10"
            text-anchor="middle"
            fill="#fff"
            font-size="11.5"
            font-weight="800"
          >
            {{ b.rank }}
          </text>
        </g>
        <g v-if="hover">
          <line
            :x1="hover.cx"
            :x2="hover.cx"
            :y1="PAD.t"
            :y2="H - PAD.b"
            :stroke="color"
            stroke-width="1"
            opacity="0.5"
          />
          <circle
            :cx="hover.cx"
            :cy="hover.cy"
            r="6"
            :fill="color"
            class="stroke-n-surface-1"
            stroke-width="2"
          />
        </g>
      </svg>
      <div
        v-if="hover"
        class="cv-sub pointer-events-none px-4 py-3 text-[13px] text-n-slate-11 leading-snug max-w-[19rem] z-10 bg-n-surface-1"
        :style="hover.style"
      >
        <p class="text-n-slate-12">
          {{ hover.title }}
          <template v-if="hover.zone"> · {{ hover.zone }}</template>
        </p>
        <p class="text-n-slate-12">
          <span class="text-lg font-extrabold tabular-nums">{{
            fmtPct(hover.point.pct)
          }}</span>
          ainda assistindo
        </p>
        <p>{{ fmtNum(hover.point.people) }} {{ baseWord }} chegaram até aqui</p>
        <p v-if="hover.average !== null">
          média da conta: {{ fmtPct(hover.average) }}
        </p>
        <p v-if="hover.speech" class="italic mt-1">
          fala: “{{ hover.speech }}”
        </p>
      </div>
    </div>

    <div
      class="flex flex-wrap gap-x-6 gap-y-1.5 mt-2 text-[13px] text-n-slate-11"
    >
      <span class="inline-flex items-center gap-2">
        <span class="w-5 h-[3px] rounded" :style="{ background: color }" />
        Este criativo
      </span>
      <span v-if="averagePath" class="inline-flex items-center gap-2">
        <span class="w-5 h-[3px] rounded bg-slate-400" />
        Média da conta
      </span>
      <span v-if="dropBands.length" class="inline-flex items-center gap-2">
        <span class="w-5 h-[3px] rounded bg-red-500/50" />
        Maiores quedas (numeradas)
      </span>
      <span
        v-for="z in zones"
        :key="`lg-${z.key}`"
        class="inline-flex items-center gap-2"
      >
        <span
          class="w-3 h-3 rounded"
          :style="{ background: z.tint, opacity: 0.45 }"
        />
        {{ z.label }}: {{ secs(z.from) }} a {{ secs(z.to) }}
      </span>
    </div>

    <template v-if="drops.length">
      <h4 class="text-lg font-bold text-n-slate-12 mt-8 mb-2 tracking-tight">
        As {{ drops.length }} maiores quedas do vídeo
      </h4>
      <p
        v-if="detail.drops_summary"
        class="ra-summary px-5 py-4 mb-4 text-base text-n-slate-12 leading-relaxed"
      >
        {{ detail.drops_summary }}
      </p>
      <ol class="flex flex-col gap-3 list-none p-0 m-0">
        <li
          v-for="d in drops"
          :key="d.rank"
          class="ra-drop"
          :style="{ '--ra-tone': d.tone }"
        >
          <span class="ra-rank">{{ d.rank }}</span>
          <div class="min-w-0">
            <p class="text-base text-n-slate-12 leading-snug">
              <span v-if="d.zone_label" class="font-extrabold">
                {{ d.zone_label }} ·
              </span>
              <span class="font-bold">{{ d.where }}</span>
            </p>
            <p class="text-sm text-n-slate-12 mt-1 leading-snug">
              caiu
              <span class="text-lg font-extrabold tabular-nums">{{
                points100(d.drop)
              }}</span>
              (de {{ fmtPct(d.from_pct) }} para {{ fmtPct(d.to_pct) }})
            </p>
            <p class="text-sm text-n-slate-10 mt-0.5">
              {{ fmtNum(d.people_lost) }} {{ baseWord }} se perderam neste
              trecho
            </p>
            <p v-if="d.speech" class="text-sm text-n-slate-11 italic mt-1">
              fala: “{{ d.speech }}”
            </p>
          </div>
        </li>
      </ol>
    </template>

    <h4 class="text-lg font-bold text-n-slate-12 mt-8 mb-3 tracking-tight">
      Os marcos do vídeo
    </h4>
    <div class="grid grid-cols-[repeat(auto-fit,minmax(10rem,1fr))] gap-3">
      <div
        v-for="m in detail.marks"
        :key="m.key"
        class="cv-sub rounded-2xl px-5 py-4"
      >
        <p class="text-[13px] font-semibold text-n-slate-10">
          {{ m.axis_label || m.label }}
        </p>
        <p
          class="text-2xl font-extrabold text-n-slate-12 tabular-nums tracking-tight my-1"
        >
          {{ fmtPct(m.pct) }}
        </p>
        <p class="text-[13px] text-n-slate-10">
          {{ fmtNum(m.people) }} chegaram aqui
        </p>
      </div>
    </div>

    <template v-if="detail.segments && detail.segments.length">
      <h4 class="text-lg font-bold text-n-slate-12 mt-8 mb-3 tracking-tight">
        O que está sendo falado em cada trecho
      </h4>
      <ul class="flex flex-col gap-3 list-none p-0 m-0">
        <li
          v-for="s in detail.segments"
          :key="s.start"
          class="cv-row px-5 py-4 text-base text-n-slate-12 leading-snug"
        >
          <span class="text-[13px] font-bold tabular-nums text-n-slate-10">
            {{ secs(s.start) }} a {{ secs(s.end) }}
          </span>
          <span class="block mt-0.5">“{{ s.text }}”</span>
          <span class="block text-sm text-n-slate-10 mt-1">
            de {{ fmtPct(s.pct_start) }} para {{ fmtPct(s.pct_end) }} assistindo
            · {{ fmtNum(s.people_lost) }} saíram neste trecho
          </span>
        </li>
      </ul>
    </template>
  </div>
</template>

<style scoped>
.ra-note {
  border-radius: 16px;
  border: 1px solid rgb(100 116 139 / 0.3);
  border-left: 4px solid #64748b;
  background: rgb(100 116 139 / 0.08);
}
.ra-summary {
  border-radius: 16px;
  border: 1px solid rgb(220 38 38 / 0.25);
  border-left: 4px solid #dc2626;
  background: rgb(220 38 38 / 0.06);
}
.ra-drop {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr);
  gap: 16px;
  align-items: start;
  padding: 16px 20px;
  border-radius: 16px;
  border: 1px solid color-mix(in srgb, var(--ra-tone) 30%, transparent);
  border-left: 4px solid var(--ra-tone);
  background: color-mix(in srgb, var(--ra-tone) 9%, transparent);
}
.ra-rank {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 30px;
  height: 30px;
  border-radius: 9999px;
  color: #fff;
  font-size: 14px;
  font-weight: 800;
  background: var(--ra-tone);
}
</style>
