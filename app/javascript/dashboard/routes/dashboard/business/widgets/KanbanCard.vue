<script setup>
// ⭐ COISAS MUITO IMPORTANTES (27/09; antes "Semana do empresário" em 3
// colunas): UMA lista, e à direita, bem alinhadas, as chavinhas
// A fazer · Fazendo · Feito. Os dados continuam em kanban.todo/doing/done.
import { ref, computed, inject } from 'vue';
import BizStamp from './BizStamp.vue';

const biz = inject('biz');
const CARD = 'Coisas muito importantes';
const STATES = [
  { key: 'todo', label: 'A fazer', color: '#64748B' },
  { key: 'doing', label: 'Fazendo', color: '#0A84FF' },
  { key: 'done', label: 'Feito', color: '#30A46C' },
];
const draft = ref('');
const showDone = ref(false);

// fazendo primeiro, depois a fazer; feitos ficam embaixo (recolhidos)
const rows = computed(() => {
  const k = biz.board.value.kanban;
  return [
    ...k.doing.map(i => ({ item: i, state: 'doing' })),
    ...k.todo.map(i => ({ item: i, state: 'todo' })),
  ];
});
const doneRows = computed(() => biz.board.value.kanban.done);

const add = () => {
  const text = draft.value.trim();
  if (!text) return;
  biz.board.value.kanban.todo.push(biz.stampNew({ text }, CARD));
  draft.value = '';
};
const setState = (item, from, to, event) => {
  if (from === to) return;
  const k = biz.board.value.kanban;
  k[from] = k[from].filter(i => i.id !== item.id);
  item.updated_at = new Date().toISOString();
  k[to].push(item);
  if (to === 'done') {
    biz.log('concluido', CARD, item.text);
    biz.celebrate?.(event);
  }
};
const remove = (item, from) => {
  const k = biz.board.value.kanban;
  k[from] = k[from].filter(i => i.id !== item.id);
};
const clearDone = () => {
  biz.board.value.kanban.done = [];
};
</script>

<template>
  <div class="biz-fill">
    <div class="biz-list">
      <div v-for="r in rows" :key="r.item.id" class="biz-imp group">
        <span
          class="biz-dot"
          :style="{ background: STATES.find(s => s.key === r.state).color }"
        />
        <div class="min-w-0 flex-1">
          <p class="biz-imp-text">{{ r.item.text }}</p>
          <BizStamp :item="r.item" :card="CARD" />
        </div>
        <div class="biz-seg" data-no-drag>
          <button
            v-for="s in STATES"
            :key="s.key"
            class="biz-seg-item"
            :class="{ on: r.state === s.key }"
            :style="r.state === s.key ? { '--seg': s.color } : {}"
            @click="setState(r.item, r.state, s.key, $event)"
          >
            {{ s.label }}
          </button>
        </div>
        <button
          class="biz-x biz-x-inline"
          data-no-drag
          title="Excluir"
          @click="remove(r.item, r.state)"
        >
          <span class="i-lucide-x" />
        </button>
      </div>
    </div>
    <p v-if="!rows.length" class="biz-empty">
      O que é MUITO importante esta semana? Anote abaixo.
    </p>
    <input
      v-model="draft"
      class="biz-add mt-2"
      placeholder="+ anotar algo muito importante e Enter"
      @keydown.enter.prevent="add"
    />

    <div v-if="doneRows.length" class="mt-3" data-no-drag>
      <div class="flex items-center gap-2">
        <button class="biz-link" @click="showDone = !showDone">
          <span
            :class="
              showDone ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right'
            "
          />
          {{ doneRows.length }} feito{{ doneRows.length > 1 ? 's' : '' }}
        </button>
        <button v-if="showDone" class="biz-link ml-auto" @click="clearDone">
          <span class="i-lucide-eraser" /> limpar feitos
        </button>
      </div>
      <div v-if="showDone" class="biz-list mt-1">
        <div v-for="item in doneRows" :key="item.id" class="biz-imp group">
          <span class="biz-dot" style="background: #30a46c" />
          <div class="min-w-0 flex-1">
            <p class="biz-imp-text biz-done">{{ item.text }}</p>
            <BizStamp :item="item" :card="CARD" />
          </div>
          <div class="biz-seg" data-no-drag>
            <button
              v-for="s in STATES"
              :key="s.key"
              class="biz-seg-item"
              :class="{ on: s.key === 'done' }"
              :style="s.key === 'done' ? { '--seg': s.color } : {}"
              @click="setState(item, 'done', s.key, $event)"
            >
              {{ s.label }}
            </button>
          </div>
          <button
            class="biz-x biz-x-inline"
            data-no-drag
            title="Excluir"
            @click="remove(item, 'done')"
          >
            <span class="i-lucide-x" />
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
