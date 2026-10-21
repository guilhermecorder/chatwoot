<script setup>
// Pessoas estratégicas: quem move o negócio com você (com data e atualizar).
import { ref, inject } from 'vue';
import BizStamp from './BizStamp.vue';

const biz = inject('biz');
const CARD = 'Pessoas estratégicas';
const GRADS = [
  'linear-gradient(135deg, #152C61, #0A84FF)',
  'linear-gradient(135deg, #B8860B, #D4AF37)',
  'linear-gradient(135deg, #0F766E, #30D158)',
  'linear-gradient(135deg, #5B21B6, #BF5AF2)',
  'linear-gradient(135deg, #9D174D, #FF375F)',
];
const draft = ref({ name: '', why: '' });
const initials = name =>
  (name || '?')
    .split(' ')
    .map(w => w[0])
    .slice(0, 2)
    .join('')
    .toUpperCase();
const add = () => {
  const name = draft.value.name.trim();
  if (!name) return;
  biz.board.value.people.push(
    biz.stampNew({ name, why: draft.value.why.trim() }, CARD, name)
  );
  draft.value = { name: '', why: '' };
};
const remove = p => {
  biz.board.value.people = biz.board.value.people.filter(x => x.id !== p.id);
};
</script>

<template>
  <div class="biz-fill">
    <div class="biz-auto biz-auto-sm">
      <div
        v-for="(p, i) in biz.board.value.people"
        :key="p.id"
        class="biz-person group"
      >
        <span
          class="biz-avatar"
          :style="{ background: GRADS[i % GRADS.length] }"
          >{{ initials(p.name) }}</span
        >
        <div class="min-w-0 flex-1">
          <p class="biz-person-name">{{ p.name }}</p>
          <p v-if="p.why" class="biz-hint">{{ p.why }}</p>
          <BizStamp :item="p" :card="CARD" />
        </div>
        <button class="biz-x" data-no-drag title="Excluir" @click="remove(p)">
          <span class="i-lucide-x" />
        </button>
      </div>
    </div>
    <p v-if="!biz.board.value.people.length" class="biz-empty">
      Sócios, mentores, fornecedores, parceiros: quem move o negócio com você.
    </p>
    <div class="biz-auto biz-auto-sm mt-2">
      <input
        v-model="draft.name"
        class="biz-add"
        placeholder="+ Nome da pessoa"
        @keydown.enter.prevent="add"
      />
      <input
        v-model="draft.why"
        class="biz-add"
        placeholder="Por que é estratégica? (Enter)"
        @keydown.enter.prevent="add"
      />
    </div>
  </div>
</template>
