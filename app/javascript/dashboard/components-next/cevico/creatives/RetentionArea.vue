<script setup>
// 📉 Curva de retenção DETALHADA (item 287): gráfico de ÁREA suave com degradê.
// Eixo X em segundos quando a Meta manda a curva segundo a segundo; linha
// tracejada = média da conta; riscos verticais = marcos (3 s, 25%, 50%, 75%,
// fim); faixa vermelha = a MAIOR QUEDA. Ao passar o mouse: o segundo, a % que
// ainda assiste, quantas reproduções e o que está sendo falado naquele trecho.
// Dados: `retention_detail` do detalhe do anúncio (Crm::AdRetentionCurve).
import { computed, ref } from 'vue';
import { fmtPct, fmtNum } from './creativeFormat';

const props = defineProps({
  detail: { type: Object, required: true },
  color: { type: String, default: '#2563eb' },
});

const W = 760;
const H = 320;
const PAD = { l: 46, r: 18, t: 30, b: 40 };
const GRID = [0, 0.25, 0.5, 0.75, 1];
const uid = `cv-ret-${Math.random().toString(36).slice(2, 8)}`;

const svgRef = ref(null);
const hover = ref(null);

const points = computed(() => props.detail.points || []);
const isSeconds = computed(() => props.detail.axis === 'seconds');
const xMax = computed(() => {
  const list = points.value;
  if (!list.length) return 1;
  return (isSeconds.value ? list[list.length - 1].t : list.length - 1) || 1;
});
const px = v => PAD.l + (W - PAD.l - PAD.r) * (v / xMax.value);
const py = v =>
  PAD.t + (H - PAD.t - PAD.b) * (1 - Math.max(0, Math.min(1, v || 0)));
const coords = list =>
  list.map((p, i) => [px(isSeconds.value ? p.t : i), py(p.pct)]);

// curva suave que nunca passa do ponto (interpolação monotônica)
const smooth = p => {
  const n = p.length;
  if (n < 2) return '';
  const d = [];
  const m = [];
  for (let i = 0; i < n - 1; i += 1)
    d.push((p[i + 1][1] - p[i][1]) / (p[i + 1][0] - p[i][0] || 1));
  m[0] = d[0];
  m[n - 1] = d[n - 2];
  for (let i = 1; i < n - 1; i += 1)
    m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
  for (let i = 0; i < n - 1; i += 1) {
    if (d[i] === 0) {
      m[i] = 0;
      m[i + 1] = 0;
    } else {
      const a = m[i] / d[i];
      const b = m[i + 1] / d[i];
      const s = a * a + b * b;
      if (s > 9) {
        const t = 3 / Math.sqrt(s);
        m[i] = t * a * d[i];
        m[i + 1] = t * b * d[i];
      }
    }
  }
  let out = `M${p[0][0].toFixed(1)},${p[0][1].toFixed(1)}`;
  for (let i = 0; i < n - 1; i += 1) {
    const h = (p[i + 1][0] - p[i][0]) / 3;
    out += ` C${(p[i][0] + h).toFixed(1)},${(p[i][1] + m[i] * h).toFixed(1)} ${(
      p[i + 1][0] - h
    ).toFixed(
      1
    )},${(p[i + 1][1] - m[i + 1] * h).toFixed(1)} ${p[i + 1][0].toFixed(1)},${p[
      i + 1
    ][1].toFixed(1)}`;
  }
  return out;
};

const line = computed(() => coords(points.value));
const linePath = computed(() => smooth(line.value));
const areaPath = computed(() => {
  const l = line.value;
  if (l.length < 2) return '';
  return `${linePath.value} L${l[l.length - 1][0].toFixed(1)},${py(0)} L${l[0][0].toFixed(1)},${py(0)} Z`;
});
const averagePath = computed(() => {
  const avg = props.detail.average || [];
  return avg.length > 1 ? smooth(coords(avg)) : '';
});

const xTicks = computed(() => {
  if (!isSeconds.value)
    return points.value.map((p, i) => ({ x: px(i), label: p.label }));
  let step = 10;
  if (xMax.value <= 20) step = 2;
  else if (xMax.value <= 45) step = 5;
  const ticks = [];
  for (let s = 0; s <= xMax.value; s += step)
    ticks.push({ x: px(s), label: `${s} s` });
  return ticks;
});
const marks = computed(() =>
  isSeconds.value
    ? (props.detail.marks || [])
        .filter(m => m.t !== null && m.t !== undefined && m.t <= xMax.value)
        .map(m => ({ ...m, x: px(m.t), end: m.t >= xMax.value }))
    : []
);
const indexOfLabel = label => points.value.findIndex(p => p.label === label);
// as 3 a 5 maiores quedas, numeradas: a 1ª em vermelho, as outras em âmbar
const DROP_TONE = ['#dc2626', '#d97706'];
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
  if (!isSeconds.value || t === null || t === undefined) return null;
  return (
    (props.detail.segments || []).find(s => t >= s.start && t <= s.end) || null
  );
};
const averageAt = t => {
  const found = (props.detail.average || []).find(a => a.t === t);
  return found ? found.pct : null;
};
const baseWord = computed(() =>
  props.detail.base === 'plays' ? 'reproduções' : 'impressões'
);

const onMove = evt => {
  const svg = svgRef.value;
  if (!svg || !line.value.length) return;
  const rect = svg.getBoundingClientRect();
  const point = evt.touches ? evt.touches[0] : evt;
  const x = ((point.clientX - rect.left) / rect.width) * W;
  let best = 0;
  line.value.forEach((c, i) => {
    if (Math.abs(c[0] - x) < Math.abs(line.value[best][0] - x)) best = i;
  });
  const p = points.value[best];
  const [cx, cy] = line.value[best];
  const seg = segmentAt(p.t);
  hover.value = {
    cx,
    cy,
    point: p,
    average: isSeconds.value ? averageAt(p.t) : null,
    speech: seg ? seg.text : '',
    style: {
      position: 'absolute',
      left: `${Math.min((cx / W) * 100 + 2, 66)}%`,
      top: `${Math.max((cy / H) * 100 - 36, 0)}%`,
    },
  };
};
const onLeave = () => {
  hover.value = null;
};

const secs = v =>
  `${String(Math.round(Number(v) * 10) / 10).replace('.', ',')} s`;
const points100 = v =>
  `${(Number(v || 0) * 100).toFixed(1).replace('.', ',')} pontos`;
const drops = computed(() =>
  dropList.value.map(d => ({
    ...d,
    tone: DROP_TONE[d.rank === 1 ? 0 : 1],
    where:
      d.from_t !== null && d.from_t !== undefined
        ? `do segundo ${String(d.from_t).replace('.', ',')} ao ${String(d.to_t).replace('.', ',')}`
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
  if (d.source === 'meta_curve')
    return `De onde vem: a Meta informa, segundo a segundo, quantos por cento das reproduções ainda estavam assistindo. Base: ${fmtNum(d.base_total)} reproduções (${d.curve_days} de ${d.period_days} dias do período têm a curva detalhada).`;
  return `De onde vem: a Meta informa quantas pessoas chegaram a cada marco do vídeo. Base: ${fmtNum(d.base_total)} impressões. A curva segundo a segundo aparece depois da próxima carga de dados da Meta.`;
});
</script>

<template>
  <div class="w-full">
    <p v-if="reading" class="text-sm text-n-slate-12 mb-1">{{ reading }}</p>
    <p class="text-xs text-n-slate-10 mb-3 leading-relaxed">
      {{ sourceText }}
      <template v-if="detail.duration">
        Duração do vídeo: {{ secs(detail.duration)
        }}{{ detail.duration_estimated ? ' (estimada pela curva)' : '' }}.
      </template>
      <template v-if="detail.avg_watch">
        Tempo médio assistido: {{ secs(detail.avg_watch) }}.
      </template>
    </p>

    <div class="relative">
      <svg
        ref="svgRef"
        :viewBox="`0 0 ${W} ${H}`"
        class="w-full h-auto select-none"
        role="img"
        aria-label="Curva de retenção do vídeo, segundo a segundo"
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
            class="fill-n-slate-9"
            font-size="11"
          >
            {{ Math.round(g * 100) }}%
          </text>
        </g>
        <g v-for="b in dropBands" :key="`drop${b.rank}`">
          <rect
            :x="b.x"
            :y="PAD.t"
            :width="b.width"
            :height="H - PAD.t - PAD.b"
            :fill="b.tone"
            :opacity="b.rank === 1 ? 0.16 : 0.12"
            rx="4"
          />
          <circle :cx="b.mid" :cy="H - PAD.b - 12" r="9" :fill="b.tone" />
          <text
            :x="b.mid"
            :y="H - PAD.b - 8.5"
            text-anchor="middle"
            fill="#fff"
            font-size="10.5"
            font-weight="800"
          >
            {{ b.rank }}
          </text>
        </g>
        <text
          v-for="t in xTicks"
          :key="`x${t.x}`"
          :x="t.x"
          :y="H - 10"
          text-anchor="middle"
          class="fill-n-slate-9"
          font-size="11"
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
            :y="PAD.t - 2"
            :text-anchor="m.end ? 'end' : 'middle'"
            class="fill-n-slate-11"
            font-size="10.5"
            font-weight="700"
          >
            {{ m.label }}
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
          stroke-width="2.6"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
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
            r="5.5"
            :fill="color"
            class="stroke-n-surface-1"
            stroke-width="2"
          />
        </g>
      </svg>
      <div
        v-if="hover"
        class="cv-sub absolute pointer-events-none px-3 py-2.5 text-xs text-n-slate-11 leading-snug max-w-[17rem] z-10 bg-n-surface-1"
        :style="hover.style"
      >
        <p class="text-n-slate-12">
          {{ hover.point.label }} ·
          <span class="text-base font-extrabold tabular-nums">{{
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
      class="flex flex-wrap gap-x-5 gap-y-1 mt-1 text-[11px] text-n-slate-11"
    >
      <span class="inline-flex items-center gap-1.5">
        <span class="w-4 h-[3px] rounded" :style="{ background: color }" />
        Este criativo
      </span>
      <span v-if="averagePath" class="inline-flex items-center gap-1.5">
        <span class="w-4 h-[3px] rounded bg-slate-400" />
        Média da conta
      </span>
      <span v-if="dropBands.length" class="inline-flex items-center gap-1.5">
        <span class="w-4 h-[3px] rounded bg-red-500/50" />
        Maiores quedas (numeradas)
      </span>
    </div>

    <template v-if="drops.length">
      <p class="text-sm font-semibold text-n-slate-12 mt-5 mb-2">
        As {{ drops.length }} maiores quedas do vídeo
      </p>
      <ol class="flex flex-col gap-2 list-none p-0 m-0">
        <li
          v-for="d in drops"
          :key="d.rank"
          class="ra-drop"
          :style="{ '--ra-tone': d.tone }"
        >
          <span class="ra-rank">{{ d.rank }}</span>
          <div class="min-w-0">
            <p class="text-sm text-n-slate-12 leading-snug">
              <span class="font-bold capitalize-first">{{ d.where }}</span>
              · caiu
              <span class="font-extrabold tabular-nums">{{
                points100(d.drop)
              }}</span>
              percentuais (de {{ fmtPct(d.from_pct) }} para
              {{ fmtPct(d.to_pct) }})
              <span v-if="d.after_hook" class="ra-chip">depois do gancho</span>
            </p>
            <p class="text-xs text-n-slate-10 mt-0.5">
              {{ fmtNum(d.people_lost) }} {{ baseWord }} se perderam neste
              trecho
            </p>
            <p v-if="d.speech" class="text-xs text-n-slate-11 italic mt-0.5">
              fala: “{{ d.speech }}”
            </p>
          </div>
        </li>
      </ol>
    </template>

    <div
      class="grid grid-cols-[repeat(auto-fit,minmax(8.5rem,1fr))] gap-2.5 mt-4"
    >
      <div
        v-for="m in detail.marks"
        :key="m.key"
        class="cv-sub rounded-2xl px-4 py-3"
      >
        <p class="text-[11px] font-semibold text-n-slate-10">
          {{ m.label }}
          <span v-if="m.t !== null && m.t !== undefined" class="font-normal">
            · {{ secs(m.t) }}
          </span>
        </p>
        <p
          class="text-xl font-extrabold text-n-slate-12 tabular-nums tracking-tight"
        >
          {{ fmtPct(m.pct) }}
        </p>
        <p class="text-[11px] text-n-slate-9">
          {{ fmtNum(m.people) }} chegaram aqui
        </p>
      </div>
    </div>

    <template v-if="detail.segments && detail.segments.length">
      <p class="text-sm font-semibold text-n-slate-12 mt-5 mb-2">
        O que está sendo falado em cada trecho
      </p>
      <ul class="flex flex-col gap-2 list-none p-0 m-0">
        <li
          v-for="s in detail.segments"
          :key="s.start"
          class="cv-row px-4 py-2.5 text-sm text-n-slate-12 leading-snug"
        >
          <span class="text-[11px] font-bold tabular-nums text-n-slate-10">
            {{ secs(s.start) }} a {{ secs(s.end) }}
          </span>
          · “{{ s.text }}”
          <span class="block text-xs text-n-slate-10 mt-0.5">
            de {{ fmtPct(s.pct_start) }} para {{ fmtPct(s.pct_end) }} assistindo
            · {{ fmtNum(s.people_lost) }} saíram neste trecho
          </span>
        </li>
      </ul>
    </template>
  </div>
</template>

<style scoped>
.ra-drop {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr);
  gap: 12px;
  align-items: start;
  padding: 10px 14px;
  border-radius: 14px;
  border: 1px solid color-mix(in srgb, var(--ra-tone) 30%, transparent);
  border-left: 4px solid var(--ra-tone);
  background: color-mix(in srgb, var(--ra-tone) 9%, transparent);
}
.ra-rank {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  border-radius: 9999px;
  color: #fff;
  font-size: 12px;
  font-weight: 800;
  background: var(--ra-tone);
}
.ra-chip {
  display: inline-block;
  margin-left: 4px;
  padding: 1px 8px;
  border-radius: 9999px;
  font-size: 10.5px;
  font-weight: 600;
  color: var(--ra-tone);
  border: 1px solid color-mix(in srgb, var(--ra-tone) 40%, transparent);
}
.capitalize-first {
  display: inline-block;
}
.capitalize-first::first-letter {
  text-transform: uppercase;
}
</style>
