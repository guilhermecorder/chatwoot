<script setup>
// 📐 MATRIZES como GRÁFICO (27/09, pedido dele: "é importante passar a ideia
// de gráfico — os quadrantes estão posicionados em áreas que nos fazem
// entender o porquê"). Dois eixos com seta, "baixa → alta" nas pontas, o
// plano dividido em 4 e cada quadrante explica sua posição
// ("alta importância · alta urgência"). As anotações vivem dentro do plano.
//   Prioridades: importância (↑) × urgência (→)
//   Oportunidades: resultados (↑) × esforço (→)
import { ref, computed, inject, nextTick } from 'vue';
import BizStamp from './BizStamp.vue';

const props = defineProps({
  section: { type: String, required: true }, // priorities | opportunities
});
const biz = inject('biz');
const MATRICES = {
  priorities: {
    card: 'Matriz de Prioridades',
    yAxis: 'Importância',
    xAxis: 'Urgência',
    // ordem = posição no plano: [cima-esq, cima-dir, baixo-esq, baixo-dir]
    quads: [
      {
        key: 'schedule',
        label: 'Agendar',
        icon: 'i-lucide-clock',
        where: 'alta importância · baixa urgência',
        hint: 'marcar hora na agenda e fazer com calma',
        color: '#0A84FF',
      },
      {
        key: 'do',
        label: 'Fazer agora',
        icon: 'i-lucide-zap',
        where: 'alta importância · alta urgência',
        hint: 'prioridade máxima',
        color: '#30A46C',
      },
      {
        key: 'drop',
        label: 'Eliminar',
        icon: 'i-lucide-x',
        where: 'baixa importância · baixa urgência',
        hint: 'cortar sem dó',
        color: '#FF453A',
      },
      {
        key: 'delegate',
        label: 'Delegar',
        icon: 'i-lucide-user-round',
        where: 'baixa importância · alta urgência',
        hint: 'passar o bastão',
        color: '#FF9F0A',
      },
    ],
  },
  opportunities: {
    card: 'Matriz de Oportunidades',
    yAxis: 'Resultados',
    xAxis: 'Esforço',
    quads: [
      {
        key: 'first',
        label: 'Fazer primeiro',
        icon: 'i-lucide-rocket',
        where: 'muito resultado · pouco esforço',
        hint: 'ouro puro',
        color: '#30A46C',
      },
      {
        key: 'plan',
        label: 'Planejar',
        icon: 'i-lucide-calendar-range',
        where: 'muito resultado · muito esforço',
        hint: 'projeto com data',
        color: '#0A84FF',
      },
      {
        key: 'fit',
        label: 'Encaixar',
        icon: 'i-lucide-check',
        where: 'pouco resultado · pouco esforço',
        hint: 'nos espaços da semana',
        color: '#FF9F0A',
      },
      {
        key: 'avoid',
        label: 'Evitar',
        icon: 'i-lucide-ban',
        where: 'pouco resultado · muito esforço',
        hint: 'não entrar',
        color: '#FF453A',
      },
    ],
  },
};
const m = computed(() => MATRICES[props.section]);
// 28/09 (item 266, pedido: "precisamos poder adicionar coisas nessas
// matrizes"): cada quadrante tem a sua caixa de anotar SEMPRE à vista
// (escreve e Enter), como nos outros quadros; o "+" do título só leva o
// cursor até ela
const drafts = ref({});
const inputs = {};
const count = key => biz.board.value[props.section][key].length;

const focusInput = async key => {
  await nextTick();
  inputs[key]?.focus();
};
const add = key => {
  const t = (drafts.value[key] || '').trim();
  if (!t) return;
  biz.board.value[props.section][key].push(
    biz.stampNew({ text: t }, m.value.card)
  );
  drafts.value[key] = '';
  biz.toast?.(`Anotado em ${m.value.quads.find(q => q.key === key).label} ✓`);
};
const remove = (key, item) => {
  const s = biz.board.value[props.section];
  s[key] = s[key].filter(i => i.id !== item.id);
};
// mover uma anotação para outro quadrante (o item ganha um ajuste no histórico)
const moveTo = (item, from, to) => {
  if (from === to) return;
  const s = biz.board.value[props.section];
  s[from] = s[from].filter(i => i.id !== item.id);
  s[to].push(item);
  biz.updateItem(
    item,
    'ajuste',
    `movido para ${m.value.quads.find(q => q.key === to).label}`,
    m.value.card
  );
};
</script>

<template>
  <div class="biz-plane" data-no-drag>
    <!-- eixo Y -->
    <div class="biz-plane-y">
      <span class="biz-plane-end">alta</span>
      <span class="biz-plane-axis-name"
        >{{ m.yAxis }} <span class="i-lucide-arrow-up"
      /></span>
      <span class="biz-plane-end">baixa</span>
    </div>
    <div class="biz-plane-body">
      <div class="biz-plane-grid">
        <div
          v-for="q in m.quads"
          :key="q.key"
          class="biz-quad"
          :style="{ '--q': q.color }"
        >
          <div class="biz-quad-head">
            <span :class="q.icon" class="biz-quad-icon" />
            <div class="min-w-0">
              <p class="biz-quad-title">
                {{ q.label }} <span class="biz-quad-n">{{ count(q.key) }}</span>
              </p>
              <p class="biz-quad-where">{{ q.where }}</p>
            </div>
            <button
              class="biz-plus"
              :title="`Anotar em ${q.label}`"
              @click="focusInput(q.key)"
            >
              <span class="i-lucide-plus" />
            </button>
          </div>
          <div class="biz-stack">
            <div
              v-for="item in biz.board.value[section][q.key]"
              :key="item.id"
              class="biz-line biz-line-sm group"
            >
              <p>{{ item.text }}</p>
              <BizStamp :item="item" :card="m.card" />
              <div class="biz-quad-move">
                <button
                  v-for="o in m.quads.filter(x => x.key !== q.key)"
                  :key="o.key"
                  class="biz-quad-move-btn"
                  :style="{ '--q': o.color }"
                  :title="`Mover para ${o.label}`"
                  @click="moveTo(item, q.key, o.key)"
                >
                  <span :class="o.icon" />
                </button>
              </div>
              <button
                class="biz-x"
                title="Excluir"
                @click="remove(q.key, item)"
              >
                <span class="i-lucide-x" />
              </button>
            </div>
            <p v-if="!count(q.key)" class="biz-quad-empty">
              {{ q.hint }}
            </p>
          </div>
          <input
            :ref="el => (inputs[q.key] = el)"
            v-model="drafts[q.key]"
            class="biz-add biz-quad-add"
            :placeholder="`+ anotar em ${q.label} e Enter`"
            @keydown.enter.prevent="add(q.key)"
          />
        </div>
      </div>
      <!-- eixo X -->
      <div class="biz-plane-x">
        <span class="biz-plane-end">baixa</span>
        <span class="biz-plane-axis-name"
          >{{ m.xAxis }} <span class="i-lucide-arrow-right"
        /></span>
        <span class="biz-plane-end">alta</span>
      </div>
    </div>
  </div>
</template>
