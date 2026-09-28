<script setup>
// Principais problemas → solução imediata (cada par com data e atualizar).
// 27/09: a solução pode VIRAR uma Atividade principal da empresa.
import { inject } from 'vue';
import BizStamp from './BizStamp.vue';

const biz = inject('biz');
const CARD = 'Problemas → Solução';
const add = () => {
  biz.board.value.problems.push({
    id: Math.random().toString(16).slice(2, 10),
    problem: '',
    solution: '',
    created_at: new Date().toISOString(),
    fresh: true,
  });
};
// só entra na linha do tempo quando o problema ganha texto (não a cada letra)
const onBlur = row => {
  if (row.fresh && row.problem) {
    biz.log('criado', CARD, row.problem);
    delete row.fresh;
  }
};
const remove = row => {
  biz.board.value.problems = biz.board.value.problems.filter(
    p => p.id !== row.id
  );
};
const toActivity = row => {
  const text = row.solution.trim();
  if (!text) return;
  biz.board.value.core_activities.push(
    biz.stampNew(
      {
        text,
        why: `resolve: ${row.problem.trim()}`,
        owner: '',
        cadence: 'semanal',
        status: 'aberto',
      },
      'Atividades principais'
    )
  );
  biz.updateItem(row, 'acao', 'virou atividade principal', CARD);
  biz.toast?.('Virou uma Atividade principal da empresa');
};
</script>

<template>
  <div class="biz-fill">
    <div class="biz-auto biz-auto-md">
      <div
        v-for="row in biz.board.value.problems"
        :key="row.id"
        class="biz-pair group"
      >
        <textarea
          v-model="row.problem"
          rows="2"
          class="biz-sticky biz-sticky-warn"
          placeholder="Qual é o problema?"
          @blur="onBlur(row)"
        />
        <span class="i-lucide-arrow-right biz-pair-arrow" />
        <textarea
          v-model="row.solution"
          rows="2"
          class="biz-sticky biz-sticky-ok"
          placeholder="Solução imediata"
        />
        <div class="biz-pair-foot">
          <BizStamp :item="row" :card="CARD" />
          <button
            v-if="row.solution"
            class="biz-mini"
            data-no-drag
            title="A solução vira uma atividade principal da empresa"
            @click="toActivity(row)"
          >
            → atividade principal
          </button>
          <button
            class="biz-x"
            data-no-drag
            title="Excluir"
            @click="remove(row)"
          >
            <span class="i-lucide-x" />
          </button>
        </div>
      </div>
    </div>
    <p v-if="!biz.board.value.problems.length" class="biz-empty">
      O que mais dói hoje? Escreva o problema e, na frente, a solução mais
      rápida possível.
    </p>
    <button class="biz-add-btn" data-no-drag @click="add">
      <span class="i-lucide-plus" /> novo par problema → solução
    </button>
  </div>
</template>
