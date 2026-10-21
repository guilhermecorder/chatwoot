<script setup>
// 🕸️ ANÁLISE DE STATUS ATUAL — teia radar GÊMEA: "Hoje" (azul) ao lado de
// "Onde queremos chegar" (dourado). Nota de 0 a 10 por área. Edita-se
// DIRETO no gráfico (27/09: as réguas saíram — puxe a ponta ou clique no
// eixo). "Onde focar" (a distância entre as duas teias) abre numa aba.
// "Salvar retrato" guarda a foto com data para comparar depois (tracejado).
import { ref, computed, inject } from 'vue';
import GlassRadar from './GlassRadar.vue';
import { fmtDay, uid, nowIso } from '../useBusinessBoard';

const biz = inject('biz');
const CARD = 'Teia radar';
const NOW = '#0A84FF';
const WANT = '#C8962E';
const radar = computed(() => biz.board.value.radar);
const areas = computed(() => radar.value.areas);

const cur = computed(() =>
  Object.fromEntries(
    areas.value.map(a => [a.key, radar.value.current[a.key] ?? 5])
  )
);
const want = computed(() =>
  Object.fromEntries(
    areas.value.map(a => [a.key, radar.value.desired[a.key] ?? 8])
  )
);
const avg = vals => {
  const list = areas.value.map(a => Number(vals[a.key]) || 0);
  return list.length
    ? (list.reduce((s, v) => s + v, 0) / list.length).toFixed(1)
    : '0';
};
const touch = () => {
  radar.value.updated_at = nowIso();
};
const setCur = (key, v) => {
  radar.value.current[key] = v;
  touch();
};
const setWant = (key, v) => {
  radar.value.desired[key] = v;
  touch();
};

// ── onde focar (aba) ──
const showFocus = ref(false);
const gaps = computed(() =>
  areas.value
    .map(a => ({
      ...a,
      gap: +(want.value[a.key] - cur.value[a.key]).toFixed(1),
    }))
    .sort((x, y) => y.gap - x.gap)
);
const gapColor = g =>
  g >= 4 ? '#FF453A' : g >= 2 ? '#FF9F0A' : g > 0 ? '#0A84FF' : '#30A46C';
const addAction = area => {
  const text = `[${area.label}] levar de ${cur.value[area.key]} para ${want.value[area.key]}`;
  biz.board.value.kanban.todo.push(
    biz.stampNew({ text, area: area.key }, 'Coisas muito importantes', text)
  );
  biz.toast?.(`Anotado em Coisas muito importantes: ${area.label}`);
};

// ── retratos com data ──
const compareId = ref('');
const compare = computed(
  () => radar.value.snapshots.find(s => s.id === compareId.value) || null
);
const snapNote = ref('');
const showSnap = ref(false);
const saveSnapshot = () => {
  radar.value.snapshots.unshift({
    id: uid(),
    at: nowIso(),
    note: snapNote.value.trim(),
    areas: areas.value.map(a => ({ ...a })),
    current: { ...cur.value },
    desired: { ...want.value },
  });
  if (radar.value.snapshots.length > 60) radar.value.snapshots.length = 60;
  biz.log(
    'radar',
    CARD,
    `retrato: média ${avg(cur.value)}${snapNote.value.trim() ? ` — ${snapNote.value.trim()}` : ''}`
  );
  snapNote.value = '';
  showSnap.value = false;
};
const evolution = computed(() => {
  if (!compare.value) return [];
  return areas.value.map(a => ({
    ...a,
    delta: +(
      (cur.value[a.key] ?? 0) - (compare.value.current?.[a.key] ?? 0)
    ).toFixed(1),
  }));
});

// ── áreas: renomear, pôr, tirar ──
const editAreas = ref(false);
const newArea = ref('');
const slug = t =>
  t
    .normalize('NFD')
    .replace(/\p{Mn}/gu, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_|_$/g, '')
    .slice(0, 24) || uid();
const addArea = () => {
  const label = newArea.value.trim();
  if (!label || areas.value.length >= 10) return;
  let key = slug(label);
  if (areas.value.some(a => a.key === key)) key = `${key}_${uid().slice(0, 3)}`;
  areas.value.push({ key, label });
  newArea.value = '';
  touch();
};
const removeArea = area => {
  if (areas.value.length <= 3) return;
  radar.value.areas = areas.value.filter(a => a.key !== area.key);
  delete radar.value.current[area.key];
  delete radar.value.desired[area.key];
  touch();
};
</script>

<template>
  <div class="biz-fill">
    <div class="biz-twins">
      <figure class="biz-twin" :style="{ '--twin': NOW }">
        <figcaption>
          <span class="biz-dot" :style="{ background: NOW }" /> Hoje
          <span class="biz-chip" :style="{ color: NOW }"
            >média {{ avg(cur) }}</span
          >
          <span v-if="compare" class="biz-hint"
            >· tracejado = {{ fmtDay(compare.at) }}</span
          >
        </figcaption>
        <GlassRadar
          :axes="areas"
          :values="cur"
          :color="NOW"
          :ghost="compare ? compare.current : null"
          label="Estado atual por área"
          @set="setCur"
        />
      </figure>
      <figure class="biz-twin" :style="{ '--twin': WANT }">
        <figcaption>
          <span class="biz-dot" :style="{ background: WANT }" /> Onde queremos
          chegar
          <span class="biz-chip" :style="{ color: WANT }"
            >média {{ avg(want) }}</span
          >
          <span class="biz-hint">· tracejado = hoje</span>
        </figcaption>
        <GlassRadar
          :axes="areas"
          :values="want"
          :color="WANT"
          :ghost="cur"
          :ghost-color="NOW"
          label="Estado desejado por área"
          @set="setWant"
        />
      </figure>
    </div>
    <p class="biz-hint text-center mt-1">
      puxe a ponta ou clique no eixo para dar a nota (0 a 10)
    </p>

    <!-- abas: onde focar · retratos · áreas -->
    <div class="biz-toolbar mt-3" data-no-drag>
      <button
        class="biz-chip"
        :class="{ 'biz-chip-on': showFocus }"
        @click="showFocus = !showFocus"
      >
        <span class="i-lucide-crosshair" /> Onde focar
        <span class="opacity-70">{{ gaps.filter(g => g.gap > 0).length }}</span>
      </button>
      <button
        class="biz-chip"
        :class="{ 'biz-chip-on': showSnap }"
        @click="showSnap = !showSnap"
      >
        <span class="i-lucide-camera" /> Retratos
        <span class="opacity-70">{{ radar.snapshots.length }}</span>
      </button>
      <button
        class="biz-chip"
        :class="{ 'biz-chip-on': editAreas }"
        @click="editAreas = !editAreas"
      >
        <span class="i-lucide-pencil" /> Áreas
      </button>
      <span v-if="radar.updated_at" class="biz-hint ml-auto"
        >mexido em {{ fmtDay(radar.updated_at) }}</span
      >
    </div>

    <div v-if="showFocus" class="biz-focus mt-2" data-no-drag>
      <p class="biz-label">
        Onde focar (maior distância entre hoje e onde queremos chegar)
      </p>
      <div v-for="g in gaps" :key="g.key" class="biz-focus-row">
        <span class="biz-focus-name">{{ g.label }}</span>
        <div class="biz-track">
          <div
            class="biz-fillbar"
            :style="{
              width: `${Math.max(0, g.gap) * 10}%`,
              background: gapColor(g.gap),
            }"
          />
        </div>
        <span class="biz-focus-gap" :style="{ color: gapColor(g.gap) }">{{
          g.gap > 0 ? `+${g.gap}` : '✓'
        }}</span>
        <button
          v-if="g.gap > 0"
          class="biz-mini"
          title="Anotar em Coisas muito importantes"
          @click="addAction(g)"
        >
          + anotar
        </button>
        <span v-else class="biz-mini opacity-0">—</span>
      </div>
      <template v-if="compare">
        <p class="biz-label mt-3">Evolução desde {{ fmtDay(compare.at) }}</p>
        <div class="flex flex-wrap gap-1.5">
          <span
            v-for="e in evolution"
            :key="e.key"
            class="biz-chip"
            :style="{
              color:
                e.delta > 0 ? '#30A46C' : e.delta < 0 ? '#FF453A' : '#64748B',
            }"
          >
            {{ e.label }} {{ e.delta > 0 ? `+${e.delta}` : e.delta }}
          </span>
        </div>
      </template>
    </div>

    <div v-if="showSnap" class="biz-focus mt-2 space-y-2" data-no-drag>
      <div class="biz-snap">
        <input
          v-model="snapNote"
          class="biz-add"
          placeholder="O que está acontecendo agora? (ex.: depois da nova campanha)"
          @keydown.enter.prevent="saveSnapshot"
        />
        <button class="biz-btn biz-btn-gold" @click="saveSnapshot">
          guardar com a data de hoje
        </button>
      </div>
      <select
        v-model="compareId"
        class="biz-select"
        :disabled="!radar.snapshots.length"
      >
        <option value="">
          {{
            radar.snapshots.length
              ? 'Comparar a teia de hoje com um retrato…'
              : 'Nenhum retrato guardado ainda'
          }}
        </option>
        <option v-for="s in radar.snapshots" :key="s.id" :value="s.id">
          {{ fmtDay(s.at) }}{{ s.note ? ` — ${s.note.slice(0, 40)}` : '' }}
        </option>
      </select>
    </div>

    <div v-if="editAreas" class="biz-focus mt-2" data-no-drag>
      <p class="biz-label">Áreas da empresa (3 a 10)</p>
      <div class="biz-stack">
        <div
          v-for="a in areas"
          :key="a.key"
          class="biz-line group flex items-center gap-2"
        >
          <input v-model="a.label" class="biz-inline" @change="touch" />
          <button
            class="biz-x biz-x-on"
            title="Tirar área"
            @click="removeArea(a)"
          >
            <span class="i-lucide-x" />
          </button>
        </div>
        <input
          v-model="newArea"
          class="biz-add"
          placeholder="+ nova área e Enter"
          @keydown.enter.prevent="addArea"
        />
      </div>
    </div>
  </div>
</template>
