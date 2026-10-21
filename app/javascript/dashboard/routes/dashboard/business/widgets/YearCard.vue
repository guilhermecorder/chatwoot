<script setup>
// Objetivos do ano / Metas específicas / Atividades estratégicas (até 8 cada),
// com data, "atualizar" e o selo de conquistado / pivotou.
// 27/09: OBJETIVOS DO ANO são SMART — Específico (o texto), Mensurável (o
// número que prova), Alcançável (por que dá), Realista (com o que temos) e
// Tempo (até quando). A linha mostra o resumo; clicar abre os 5 campos, e as
// 5 bolinhas mostram o que ainda falta preencher.
import { ref, computed, inject } from 'vue';
import BizStamp from './BizStamp.vue';
import { fmtDay } from '../useBusinessBoard';

const props = defineProps({
  section: { type: String, required: true }, // objectives | goals | activities
});
const biz = inject('biz');
const META = {
  objectives: {
    card: 'Objetivos do ano',
    placeholder: 'Novo objetivo (específico)',
    color: '#C8962E',
  },
  goals: {
    card: 'Metas específicas',
    placeholder: 'Nova meta',
    color: '#0A84FF',
  },
  activities: {
    card: 'Atividades estratégicas',
    placeholder: 'Nova atividade',
    color: '#30A46C',
  },
};
const SMART = [
  { key: 'text', letter: 'S', label: 'Específico', hint: 'o quê, exatamente' },
  {
    key: 'measure',
    letter: 'M',
    label: 'Mensurável',
    hint: 'o número que prova (ex.: 40 cirurgias/mês)',
  },
  {
    key: 'achievable',
    letter: 'A',
    label: 'Alcançável',
    hint: 'por que dá para chegar lá',
  },
  {
    key: 'realistic',
    letter: 'R',
    label: 'Realista',
    hint: 'com o time, o caixa e a estrutura de hoje',
  },
  { key: 'due', letter: 'T', label: 'Tempo', hint: 'até quando' },
];
const meta = computed(() => META[props.section]);
const smart = computed(() => props.section === 'objectives');
const list = computed(() => biz.board.value[props.section]);
const done = computed(
  () => list.value.filter(i => i.status === 'conquistado').length
);
const draft = ref('');
const open = ref(null);
const editing = ref(null);

const filled = item =>
  SMART.filter(f => String(item[f.key] || '').trim()).length;
const overdue = item =>
  item.due && item.status !== 'conquistado' && new Date(item.due) < new Date();

const add = () => {
  const text = draft.value.trim();
  if (!text || list.value.length >= 8) return;
  const item = biz.stampNew(
    {
      text,
      status: 'aberto',
      measure: '',
      achievable: '',
      realistic: '',
      due: '',
    },
    meta.value.card
  );
  list.value.push(item);
  draft.value = '';
  if (smart.value) open.value = item.id;
};
const remove = item => {
  biz.board.value[props.section] = list.value.filter(i => i.id !== item.id);
};
</script>

<template>
  <div class="biz-fill">
    <div v-if="list.length" class="biz-progress mb-2">
      <div class="biz-track">
        <div
          class="biz-fillbar"
          :style="{
            width: `${(done / list.length) * 100}%`,
            background: meta.color,
          }"
        />
      </div>
      <span>{{ done }}/{{ list.length }} conquistados</span>
    </div>
    <div class="biz-auto" :class="smart ? '' : 'biz-auto-sm'">
      <div
        v-for="(item, i) in list"
        :key="item.id"
        class="biz-line group"
        :class="{
          'biz-won': item.status === 'conquistado',
          'biz-pivot': item.status === 'pivotado',
        }"
      >
        <div class="flex items-start gap-2">
          <span class="biz-num" :style="{ background: meta.color }">{{
            i + 1
          }}</span>
          <div class="min-w-0 flex-1">
            <input
              v-if="editing === item.id"
              v-model="item.text"
              class="biz-inline w-full"
              @blur="editing = null"
              @keydown.enter.prevent="editing = null"
            />
            <p
              v-else
              class="cursor-text"
              data-no-drag
              @click="smart ? (open = open === item.id ? null : item.id) : null"
              @dblclick="editing = item.id"
            >
              {{ item.text }}
            </p>
            <!-- resumo SMART na linha -->
            <div
              v-if="smart && open !== item.id"
              class="flex items-center gap-1.5 flex-wrap mt-1"
              data-no-drag
            >
              <span
                class="biz-smart-dots"
                :title="`${filled(item)} de 5 preenchidos`"
              >
                <span
                  v-for="f in SMART"
                  :key="f.key"
                  class="biz-smart-dot"
                  :class="{ on: String(item[f.key] || '').trim() }"
                  :title="f.label"
                  >{{ f.letter }}</span
                >
              </span>
              <span v-if="item.measure" class="biz-chip"
                ><span class="i-lucide-ruler" /> {{ item.measure }}</span
              >
              <span
                v-if="item.due"
                class="biz-chip"
                :style="overdue(item) ? { color: '#FF453A' } : {}"
                ><span class="i-lucide-calendar" /> até
                {{ fmtDay(item.due) }}</span
              >
              <button class="biz-link" @click="open = item.id">
                {{ filled(item) < 5 ? 'completar SMART' : 'editar' }}
              </button>
            </div>
          </div>
        </div>
        <!-- os 5 campos -->
        <div
          v-if="smart && open === item.id"
          class="biz-core-form"
          data-no-drag
        >
          <label v-for="f in SMART.filter(x => x.key !== 'text')" :key="f.key">
            <span class="biz-smart-letter">{{ f.letter }}</span> {{ f.label }}
            <span class="biz-hint">— {{ f.hint }}</span>
            <input
              v-if="f.key === 'due'"
              v-model="item.due"
              type="date"
              class="biz-add"
            />
            <input
              v-else
              v-model="item[f.key]"
              class="biz-add"
              :placeholder="f.hint"
            />
          </label>
          <label>
            <span class="biz-smart-letter">S</span> Específico
            <span class="biz-hint">— o objetivo em uma frase concreta</span>
            <input v-model="item.text" class="biz-add" />
          </label>
          <button class="biz-link" @click="open = null">
            <span class="i-lucide-check" /> pronto
          </button>
        </div>
        <BizStamp :item="item" :card="meta.card" />
        <button
          class="biz-x"
          data-no-drag
          title="Excluir"
          @click="remove(item)"
        >
          <span class="i-lucide-x" />
        </button>
      </div>
    </div>
    <input
      v-if="list.length < 8"
      v-model="draft"
      class="biz-add mt-2"
      :placeholder="`+ ${meta.placeholder} e Enter`"
      @keydown.enter.prevent="add"
    />
  </div>
</template>
