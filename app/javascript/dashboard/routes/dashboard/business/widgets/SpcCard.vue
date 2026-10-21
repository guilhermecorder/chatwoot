<script setup>
// Continuar · Parar · Começar — cada anotação com data e "atualizar".
import { ref, inject } from 'vue';
import BizStamp from './BizStamp.vue';

const biz = inject('biz');
const CARD = 'Continuar · Parar · Começar';
const ROWS = [
  {
    key: 'continuar',
    label: 'Continuar',
    hint: 'o que funciona — manter',
    color: '#30A46C',
  },
  {
    key: 'parar',
    label: 'Parar',
    hint: 'o que drena e não traz retorno',
    color: '#FF453A',
  },
  {
    key: 'comecar',
    label: 'Começar',
    hint: 'o que ainda não fazemos e deveríamos',
    color: '#0A84FF',
  },
];
const drafts = ref({ continuar: '', parar: '', comecar: '' });
const add = key => {
  const text = drafts.value[key].trim();
  if (!text) return;
  biz.board.value.spc[key].push(
    biz.stampNew({ text }, CARD, `${key}: ${text}`)
  );
  drafts.value[key] = '';
};
const remove = (key, item) => {
  biz.board.value.spc[key] = biz.board.value.spc[key].filter(
    i => i.id !== item.id
  );
};
</script>

<template>
  <div class="biz-auto biz-auto-md">
    <div
      v-for="row in ROWS"
      :key="row.key"
      class="biz-tint"
      :style="{ '--tint': row.color }"
    >
      <p class="biz-tint-title">
        <span class="biz-dot" :style="{ background: row.color }" />
        {{ row.label }}
        <span class="biz-hint">— {{ row.hint }}</span>
      </p>
      <div class="biz-stack">
        <div
          v-for="item in biz.board.value.spc[row.key]"
          :key="item.id"
          class="biz-line group"
        >
          <p>{{ item.text }}</p>
          <BizStamp :item="item" :card="CARD" />
          <button
            class="biz-x"
            data-no-drag
            title="Excluir"
            @click="remove(row.key, item)"
          >
            <span class="i-lucide-x" />
          </button>
        </div>
        <input
          v-model="drafts[row.key]"
          class="biz-add"
          placeholder="+ adicionar e Enter"
          @keydown.enter.prevent="add(row.key)"
        />
      </div>
    </div>
  </div>
</template>
