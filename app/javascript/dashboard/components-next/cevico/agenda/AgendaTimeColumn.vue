<script setup>
// 🍎📅 AgendaTimeColumn (item 210): UMA coluna de horas da Agenda — usada pela
// visão Semana (7 colunas) e pela visão Dia (1 coluna larga). Desenha as
// faixas das janelas (médico / sala cirúrgica), os balões dos agendamentos
// com altura proporcional à duração, a linha vermelha de AGORA e responde a
// clique (agendar naquele horário) e a arrastar-e-soltar (reagendar).
import { computed } from 'vue';
import { hexToRgbSpaced } from 'dashboard/helper/cevicoAgenda';

const props = defineProps({
  day: { type: Date, required: true },
  tasks: { type: Array, default: () => [] },
  // [{ key, startMin, endMin, block, color, label, title, unit, doctor }]
  bands: { type: Array, default: () => [] },
  startHour: { type: Number, default: 8 },
  endHour: { type: Number, default: 18 }, // exclusivo
  hourPx: { type: Number, default: 64 },
  dayOff: { type: Boolean, default: false },
  today: { type: Boolean, default: false },
  nowMinutes: { type: Number, default: null },
  dropActive: { type: Boolean, default: false },
  durationOf: { type: Function, required: true },
  accentOf: { type: Function, required: true },
  nameOf: { type: Function, required: true },
  // item 234: etiqueta pequena no balão (ex.: a unidade) — { label, short } ou null
  tagOf: { type: Function, default: null },
  compact: { type: Boolean, default: false },
});
const emit = defineEmits(['create', 'open', 'dragstart', 'drop', 'dragover', 'dragleave']);

const startMin = computed(() => props.startHour * 60);
const totalMin = computed(() => (props.endHour - props.startHour) * 60);
const height = computed(() => (props.endHour - props.startHour) * props.hourPx);
const pxPerMin = computed(() => props.hourPx / 60);
const pad = n => String(n).padStart(2, '0');
const timeOf = task => {
  const d = new Date(task.due_at);
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
};
const minutesOf = task => {
  const d = new Date(task.due_at);
  return d.getHours() * 60 + d.getMinutes();
};

// balões: posição pela hora, altura pela duração; quando dois ou mais se
// sobrepõem (encaixe), o GRUPO divide a largura da coluna em raias iguais —
// o mesmo jeito do Calendário da Apple
const events = computed(() => {
  const sorted = [...props.tasks]
    .filter(t => t.due_at)
    .sort((a, b) => minutesOf(a) - minutesOf(b) || a.id - b.id);
  const items = sorted.map(task => {
    const start = minutesOf(task);
    const dur = Math.max(Number(props.durationOf(task)) || 15, 5);
    return { task, start, end: start + dur, dur, lane: 0, lanes: 1 };
  });
  // grupos de sobreposição + raia de cada um dentro do grupo
  let group = [];
  let groupEnd = -1;
  const closeGroup = () => {
    const lanes = Math.max(1, ...group.map(g => g.lane + 1));
    group.forEach(g => { g.lanes = lanes; });
    group = [];
  };
  items.forEach(it => {
    if (group.length && it.start >= groupEnd) closeGroup();
    const laneEnds = group.map(g => g.end);
    let lane = 0;
    // a primeira raia livre (quem terminou antes deste começar libera a raia)
    const used = new Set(group.filter(g => g.end > it.start).map(g => g.lane));
    while (used.has(lane)) lane += 1;
    it.lane = lane;
    group.push(it);
    groupEnd = Math.max(groupEnd, it.end, ...laneEnds);
  });
  if (group.length) closeGroup();

  return items.map(it => {
    const top = (Math.max(it.start, startMin.value) - startMin.value) * pxPerMin.value;
    const rawH = (Math.min(it.end, startMin.value + totalMin.value) - Math.max(it.start, startMin.value)) * pxPerMin.value;
    const h = Math.max(rawH - 2, 18);
    const accent = props.accentOf(it.task) || '#2563EB';
    const width = 100 / it.lanes;
    return {
      task: it.task,
      time: timeOf(it.task),
      name: props.nameOf(it.task),
      dur: it.dur,
      short: h < 34,
      // item 247: selos (parceiro/unidade) só quando cabem sem espremer o nome
      roomy: h >= 50,
      style: {
        top: `${top}px`,
        height: `${h}px`,
        left: `calc(${it.lane * width}% + 2px)`,
        width: `calc(${width}% - ${it.lanes > 1 ? 3 : 5}px)`,
        zIndex: 5 + it.lane,
        '--ev': accent,
        '--ev-rgb': hexToRgbSpaced(accent),
      },
    };
  });
});

const bandStyles = computed(() =>
  props.bands.map(b => {
    const s = Math.max(b.startMin, startMin.value);
    const e = Math.min(b.endMin, startMin.value + totalMin.value);
    return {
      ...b,
      style: {
        top: `${(s - startMin.value) * pxPerMin.value}px`,
        height: `${Math.max((e - s) * pxPerMin.value, 0)}px`,
        '--w-rgb': hexToRgbSpaced(b.color),
      },
    };
  })
);

const nowTop = computed(() => {
  if (!props.today || props.nowMinutes == null) return null;
  const m = props.nowMinutes;
  if (m < startMin.value || m > startMin.value + totalMin.value) return null;
  return (m - startMin.value) * pxPerMin.value;
});

// minuto do clique/solte: cai numa janela → gruda no bloco dela; fora → 15 em 15
const snap = (evt, el) => {
  const rect = el.getBoundingClientRect();
  const y = Math.min(Math.max(evt.clientY - rect.top, 0), rect.height - 1);
  const raw = startMin.value + y / pxPerMin.value;
  const band = props.bands.find(b => raw >= b.startMin && raw < b.endMin);
  let minutes;
  if (band?.block) {
    minutes = band.startMin + Math.floor((raw - band.startMin) / band.block) * band.block;
  } else {
    minutes = Math.round(raw / 15) * 15;
  }
  minutes = Math.min(Math.max(minutes, startMin.value), startMin.value + totalMin.value - 5);
  return { minutes, band: band || null };
};
const onClick = evt => {
  if (props.dayOff) return;
  emit('create', { day: props.day, ...snap(evt, evt.currentTarget) });
};
const onDrop = evt => {
  if (props.dayOff) return;
  emit('drop', { day: props.day, ...snap(evt, evt.currentTarget) });
};
const badges = task => {
  const out = [];
  if (task.attendance === 'attended') out.push('✓');
  else if (task.attendance === 'missed') out.push('✗');
  else if (task.attendance === 'attended_not_done') out.push('⚠️');
  if (task.surgery_indication === 'indicated') out.push('🎯');
  return out;
};
const evClass = ev => ({
  'cv-ag-ev-short': ev.short,
  'cv-ag-ev-tight': !ev.roomy,
  'cv-ag-ev-done': ev.task.status === 'done' && ev.task.attendance !== 'missed',
  'cv-ag-ev-missed': ev.task.attendance === 'missed',
});
</script>

<template>
  <div
    class="cv-ag-col"
    :class="{
      'cv-ag-col-off': dayOff,
      'cv-ag-col-today': today && !dayOff,
      'cv-ag-col-drop': dropActive && !dayOff,
    }"
    :style="{ height: `${height}px`, '--hour-px': `${hourPx}px` }"
    :title="dayOff ? '' : 'Clique num espaço vazio para agendar naquele horário · arraste um balão para reagendar'"
    @click="onClick"
    @dragover.prevent="!dayOff && emit('dragover', day)"
    @dragleave="emit('dragleave', day)"
    @drop.prevent="onDrop"
  >
    <!-- faixas das janelas (horário em que o médico / a sala atende) -->
    <div
      v-for="b in bandStyles"
      :key="b.key"
      class="cv-ag-band"
      :style="b.style"
      :title="b.title"
    >
      <span v-if="!compact" class="cv-ag-band-label">{{ b.label }}</span>
    </div>

    <!-- balões -->
    <button
      v-for="ev in events"
      :key="ev.task.id"
      type="button"
      class="cv-ag-ev cv-ag-ev-block"
      :class="evClass(ev)"
      :style="ev.style"
      draggable="true"
      :title="`${ev.time} · ${ev.name} (${ev.dur} min)${ev.task.source_detail ? ' · ' + ev.task.source_detail : ''}${tagOf && tagOf(ev.task) ? ' · ' + tagOf(ev.task).label : ''} — clique abre, arraste reagenda`"
      @dragstart="emit('dragstart', ev.task)"
      @click.stop="emit('open', ev.task)"
    >
      <span class="cv-ag-ev-time">{{ ev.time }}</span>
      <span class="cv-ag-ev-name">{{ ev.name }}</span>
      <!-- 🏥 item 228: selo de origem (veio de outro sistema) -->
      <span v-if="ev.task.source" class="cv-ag-ev-src" :title="`Veio do Oftalmofácil${ev.task.source_detail ? ' · ' + ev.task.source_detail : ''}`">{{ compact ? 'OF' : (ev.task.source_detail || 'Oftalmofácil') }}</span>
      <span v-if="tagOf && tagOf(ev.task)" class="cv-ag-ev-tag" :title="tagOf(ev.task).label">{{ compact ? tagOf(ev.task).short : tagOf(ev.task).label }}</span>
      <span v-if="badges(ev.task).length" class="cv-ag-ev-badges">
        <span v-for="(b, bi) in badges(ev.task)" :key="bi">{{ b }}</span>
      </span>
    </button>

    <!-- agora -->
    <div v-if="nowTop !== null" class="cv-ag-now" :style="{ top: `${nowTop}px` }" />
  </div>
</template>
