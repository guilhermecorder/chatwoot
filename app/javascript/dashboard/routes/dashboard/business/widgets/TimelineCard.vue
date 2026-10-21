<script setup>
// 📍 LINHA DO TEMPO do quadro: tudo que entrou, cada ação feita, conquista,
// pivô, ajuste e retrato do radar — com a data. Dá para registrar um MARCO
// solto (decisão, virada, pivô da empresa) direto aqui.
import { ref, computed, inject } from 'vue';
import { UPDATE_KINDS, fmtDay } from '../useBusinessBoard';

const biz = inject('biz');
const FILTERS = [
  { key: 'all', label: 'Tudo' },
  {
    key: 'big',
    label: 'Marcos',
    kinds: ['conquista', 'pivot', 'marco', 'radar'],
  },
  { key: 'acao', label: 'Ações', kinds: ['acao', 'concluido', 'ajuste'] },
  { key: 'criado', label: 'Anotações', kinds: ['criado'] },
];
const filter = ref('all');
const limit = ref(40);
const events = computed(() => {
  const f = FILTERS.find(x => x.key === filter.value);
  const list = biz.board.value.events;
  return f?.kinds ? list.filter(e => f.kinds.includes(e.kind)) : list;
});
const groups = computed(() => {
  const out = [];
  events.value.slice(0, limit.value).forEach(e => {
    const day = fmtDay(e.at);
    const last = out[out.length - 1];
    if (last && last.day === day) last.items.push(e);
    else out.push({ day, items: [e] });
  });
  return out;
});
const hour = iso =>
  new Date(iso).toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  });

const markKind = ref('marco');
const markText = ref('');
const addMark = () => {
  const t = markText.value.trim();
  if (!t) return;
  biz.log(markKind.value, 'Linha do tempo', t);
  if (markKind.value === 'conquista') biz.celebrate?.();
  markText.value = '';
};
</script>

<template>
  <div class="biz-fill biz-timeline">
    <div class="biz-toolbar" data-no-drag>
      <button
        v-for="f in FILTERS"
        :key="f.key"
        class="biz-chip"
        :class="{ 'biz-chip-on': filter === f.key }"
        @click="filter = f.key"
      >
        {{ f.label }}
      </button>
    </div>
    <div class="biz-mark" data-no-drag>
      <select v-model="markKind" class="biz-select">
        <option value="marco">📍 Marco</option>
        <option value="pivot">↪️ Pivô</option>
        <option value="conquista">🏆 Conquista</option>
        <option value="acao">✅ Ação feita</option>
      </select>
      <input
        v-model="markText"
        class="biz-add"
        placeholder="Registrar agora (Enter)"
        @keydown.enter.prevent="addMark"
      />
    </div>
    <div class="biz-tl">
      <div v-for="g in groups" :key="g.day" class="biz-tl-day">
        <p class="biz-tl-date">{{ g.day }}</p>
        <div
          v-for="e in g.items"
          :key="e.id"
          class="biz-tl-item"
          :style="{ '--k': UPDATE_KINDS[e.kind]?.color }"
        >
          <span class="biz-tl-emoji">{{ UPDATE_KINDS[e.kind]?.emoji }}</span>
          <div class="min-w-0">
            <p class="biz-tl-text">
              {{ e.text || UPDATE_KINDS[e.kind]?.label }}
            </p>
            <p class="biz-hint">
              {{ UPDATE_KINDS[e.kind]?.label }} · {{ e.card }} ·
              {{ hour(e.at) }}
            </p>
          </div>
        </div>
      </div>
      <p v-if="!groups.length" class="biz-empty">
        Tudo que você anotar, atualizar, conquistar ou pivotar aparece aqui com
        a data.
      </p>
      <button
        v-if="events.length > limit"
        class="biz-link"
        data-no-drag
        @click="limit += 40"
      >
        ver mais antigos
      </button>
    </div>
  </div>
</template>
