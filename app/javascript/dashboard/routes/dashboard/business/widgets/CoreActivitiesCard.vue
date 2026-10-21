<script setup>
// 🎯 ATIVIDADES PRINCIPAIS DA EMPRESA (27/09): "ultra específico, mas ultra
// importante; pode haver mais de uma". Cada atividade tem o que é (bem
// específico), por que importa, quem cuida e com que frequência. Nasce daqui
// ou de um par Problema → Solução (botão "virar atividade principal").
import { ref, inject } from 'vue';
import BizStamp from './BizStamp.vue';

const biz = inject('biz');
const CARD = 'Atividades principais';
const CADENCES = ['diária', 'semanal', 'quinzenal', 'mensal', 'contínua'];
const open = ref(null);
const draft = ref('');

const add = () => {
  const text = draft.value.trim();
  if (!text) return;
  const item = biz.stampNew(
    { text, why: '', owner: '', cadence: 'semanal', status: 'aberto' },
    CARD
  );
  biz.board.value.core_activities.push(item);
  draft.value = '';
  open.value = item.id;
};
const remove = item => {
  biz.board.value.core_activities = biz.board.value.core_activities.filter(
    i => i.id !== item.id
  );
};
</script>

<template>
  <div class="biz-fill">
    <div class="biz-list">
      <div
        v-for="(item, i) in biz.board.value.core_activities"
        :key="item.id"
        class="biz-core group"
        :class="{
          'biz-won': item.status === 'conquistado',
          'biz-pivot': item.status === 'pivotado',
        }"
      >
        <div class="flex items-start gap-2">
          <span class="biz-num" style="background: #c8962e">{{ i + 1 }}</span>
          <div class="min-w-0 flex-1">
            <p
              class="biz-core-text"
              data-no-drag
              @click="open = open === item.id ? null : item.id"
            >
              {{ item.text }}
            </p>
            <p v-if="open !== item.id" class="biz-hint">
              <span v-if="item.owner">{{ item.owner }} · </span>{{ item.cadence
              }}<span v-if="item.why"> · {{ item.why }}</span>
            </p>
            <BizStamp :item="item" :card="CARD" />
          </div>
          <button
            class="biz-x"
            data-no-drag
            title="Excluir"
            @click="remove(item)"
          >
            <span class="i-lucide-x" />
          </button>
        </div>
        <div v-if="open === item.id" class="biz-core-form" data-no-drag>
          <label
            >O que exatamente
            <span class="biz-hint"
              >(ultra específico: quem faz o quê, com o quê)</span
            >
            <textarea v-model="item.text" rows="2" class="biz-note-input" />
          </label>
          <label
            >Por que é importante
            <input
              v-model="item.why"
              class="biz-add"
              placeholder="o resultado que ela garante"
            />
          </label>
          <div class="grid grid-cols-2 gap-2">
            <label
              >Quem cuida
              <input v-model="item.owner" class="biz-add" placeholder="nome" />
            </label>
            <label
              >Frequência
              <select v-model="item.cadence" class="biz-select w-full">
                <option v-for="c in CADENCES" :key="c" :value="c">
                  {{ c }}
                </option>
              </select>
            </label>
          </div>
          <button class="biz-link" @click="open = null">
            <span class="i-lucide-check" /> pronto
          </button>
        </div>
      </div>
    </div>
    <p v-if="!biz.board.value.core_activities.length" class="biz-empty">
      Quais são as poucas atividades que, bem feitas, sustentam a empresa? Uma
      por linha, o mais específica possível.
    </p>
    <input
      v-model="draft"
      class="biz-add mt-2"
      placeholder="+ nova atividade principal e Enter"
      @keydown.enter.prevent="add"
    />
  </div>
</template>
