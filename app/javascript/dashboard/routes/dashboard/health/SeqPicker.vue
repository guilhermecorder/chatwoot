<script setup>
// SELETOR DE SEQUÊNCIAS (rodada 27) — pedido dele 19/09: o construtor por
// rounds virou "salada de frutas" com as 30 sequências repetidas em cada
// round. Aqui só as ESCOLHIDAS ficam visíveis; "+ sequência" abre um
// painel único com abas por etiqueta, busca e linhas (nome · passos ·
// quando usar). Reusado no construtor do professor, no plano de luta e
// no editor de blocos.
import { ref, computed } from 'vue';
import { SEQ_CATEGORIES } from './warrior';

const props = defineProps({
  modelValue: { type: Array, default: () => [] },
  seqs: { type: Array, default: () => [] },
  dark: { type: Boolean, default: false }, // dentro de um bloco escuro
});
const emit = defineEmits(['update:modelValue']);

const open = ref(false);
const cat = ref('');
const q = ref('');

const byId = id => props.seqs.find(s => s.id === id);
const selected = computed(() => props.modelValue.map(byId).filter(Boolean));
const norm = s =>
  String(s || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase();
const list = computed(() =>
  props.seqs.filter(s => {
    if (cat.value && s.category !== cat.value) return false;
    if (!q.value.trim()) return true;
    const n = norm(q.value);
    return norm(s.name).includes(n) || norm(s.steps).includes(n) || norm(s.when).includes(n);
  })
);
const count = key => props.seqs.filter(s => s.category === key).length;
const has = id => props.modelValue.includes(id);
const toggle = id => {
  const next = has(id) ? props.modelValue.filter(x => x !== id) : [...props.modelValue, id];
  emit('update:modelValue', next);
};
const catOf = key => SEQ_CATEGORIES.find(c => c.key === key) || null;
</script>

<template>
  <div class="hub-sp" :class="{ 'is-dark': dark }">
    <div class="hub-sp-sel">
      <button v-for="s in selected" :key="s.id" class="hub-sp-chip" :title="s.when || s.desc" @click="toggle(s.id)">
        <span v-if="catOf(s.category)" :class="catOf(s.category).ico" class="hub-sp-ci" />
        <b>{{ s.name }}</b>
        <small>{{ s.steps }}</small>
        <i class="i-lucide-x hub-sp-x" />
      </button>
      <button class="hub-sp-add" :class="{ 'is-on': open }" @click="open = !open">
        <span :class="open ? 'i-lucide-chevron-up' : 'i-lucide-plus'" />
        {{ open ? 'fechar' : selected.length ? 'sequência' : 'adicionar sequência' }}
      </button>
    </div>

    <div v-if="open" class="hub-sp-panel">
      <div class="hub-sp-tabs">
        <button class="hub-sp-tab" :class="{ 'is-on': !cat }" @click="cat = ''">todas <small>{{ seqs.length }}</small></button>
        <button
          v-for="c in SEQ_CATEGORIES"
          :key="c.key"
          class="hub-sp-tab"
          :class="{ 'is-on': cat === c.key }"
          :title="c.hint"
          @click="cat = cat === c.key ? '' : c.key"
        >
          <span :class="c.ico" />
          {{ c.label }} <small>{{ count(c.key) }}</small>
        </button>
      </div>
      <div class="hub-sp-search">
        <span class="i-lucide-search" />
        <input v-model="q" type="text" placeholder="buscar por nome, passos ou situação" />
      </div>
      <div class="hub-sp-list">
        <button v-for="s in list" :key="s.id" class="hub-sp-row" :class="{ 'is-on': has(s.id) }" @click="toggle(s.id)">
          <span class="hub-sp-check" :class="has(s.id) ? 'i-lucide-check-circle-2' : 'i-lucide-circle'" />
          <span class="hub-sp-body">
            <span class="hub-sp-name">
              {{ s.name }}
              <span v-if="catOf(s.category)" class="hub-sp-cat"><span :class="catOf(s.category).ico" />{{ catOf(s.category).label }}</span>
            </span>
            <span class="hub-sp-steps">{{ s.steps }}</span>
            <span v-if="s.when" class="hub-sp-when">{{ s.when }}</span>
          </span>
        </button>
        <p v-if="!list.length" class="hub-sp-empty">Nada com esse filtro.</p>
      </div>
    </div>
  </div>
</template>

<style scoped>
.hub-sp { --c: #27408b; --rgb: 65, 105, 225; --txt: #1e293b; --mut: #64748b; }
.hub-sp.is-dark { --c: #ffb25e; --rgb: 255, 255, 255; --txt: #fff; --mut: rgba(255, 255, 255, 0.72); }
.hub-sp-sel { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; }
.hub-sp-chip {
  display: inline-flex; align-items: center; gap: 6px; height: 30px; padding: 0 8px 0 9px;
  border-radius: 9px; font-size: 11px; color: var(--txt);
  background: rgb(var(--rgb) / 0.12); border: 1px solid rgb(var(--rgb) / 0.3);
}
.hub-sp-chip small { opacity: 0.75; }
.hub-sp-ci, .hub-sp-x { width: 12px; height: 12px; }
.hub-sp-x { opacity: 0.6; }
.hub-sp-chip:hover .hub-sp-x { opacity: 1; }
.hub-sp-add {
  display: inline-flex; align-items: center; gap: 5px; height: 30px; padding: 0 10px; border-radius: 9px;
  font-size: 11px; font-weight: 700; color: var(--c); border: 1px dashed rgb(var(--rgb) / 0.45); background: transparent;
}
.hub-sp-add > span { width: 13px; height: 13px; }
.hub-sp-add.is-on { border-style: solid; background: rgb(var(--rgb) / 0.12); }
.hub-sp-panel {
  margin-top: 8px; border-radius: 12px; border: 1px solid rgb(var(--rgb) / 0.28);
  background: rgba(255, 255, 255, 0.92); color: #1e293b; overflow: hidden;
}
.hub-sp.is-dark .hub-sp-panel { background: rgba(17, 28, 63, 0.96); color: #fff; }
.hub-sp-tabs { display: flex; gap: 4px; padding: 8px 8px 0; overflow-x: auto; scrollbar-width: none; }
.hub-sp-tabs::-webkit-scrollbar { display: none; }
.hub-sp-tab {
  display: inline-flex; align-items: center; gap: 5px; height: 28px; padding: 0 9px; border-radius: 8px;
  font-size: 11px; font-weight: 700; white-space: nowrap; color: inherit; opacity: 0.75; border: 1px solid transparent;
}
.hub-sp-tab > span[class^='i-'] { width: 12px; height: 12px; }
.hub-sp-tab small { font-weight: 500; opacity: 0.7; }
.hub-sp-tab.is-on { opacity: 1; background: rgb(65 105 225 / 0.14); border-color: rgb(65 105 225 / 0.3); }
.hub-sp.is-dark .hub-sp-tab.is-on { background: rgba(255, 255, 255, 0.14); border-color: rgba(255, 255, 255, 0.3); }
.hub-sp-search { display: flex; align-items: center; gap: 6px; margin: 8px; height: 32px; padding: 0 9px; border-radius: 9px; border: 1px solid rgb(65 105 225 / 0.22); background: rgba(255, 255, 255, 0.7); }
.hub-sp.is-dark .hub-sp-search { background: rgba(255, 255, 255, 0.08); border-color: rgba(255, 255, 255, 0.2); }
.hub-sp-search > span { width: 14px; height: 14px; opacity: 0.6; flex-shrink: 0; }
.hub-sp-search input { flex: 1; height: 100%; border: 0; background: transparent; font-size: 12px; color: inherit; margin: 0; padding: 0; outline: none; }
.hub-sp-list { max-height: 260px; overflow-y: auto; }
.hub-sp-row {
  display: flex; align-items: flex-start; gap: 9px; width: 100%; text-align: left; padding: 8px 10px;
  border-top: 1px solid rgb(65 105 225 / 0.1); color: inherit;
}
.hub-sp.is-dark .hub-sp-row { border-top-color: rgba(255, 255, 255, 0.1); }
.hub-sp-row.is-on { background: rgb(65 105 225 / 0.08); }
.hub-sp.is-dark .hub-sp-row.is-on { background: rgba(255, 255, 255, 0.1); }
.hub-sp-check { width: 16px; height: 16px; margin-top: 2px; flex-shrink: 0; opacity: 0.55; }
.hub-sp-row.is-on .hub-sp-check { opacity: 1; color: #4169e1; }
.hub-sp.is-dark .hub-sp-row.is-on .hub-sp-check { color: #ffb25e; }
.hub-sp-body { display: flex; flex-direction: column; gap: 1px; min-width: 0; }
.hub-sp-name { font-size: 12px; font-weight: 700; display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }
.hub-sp-cat { display: inline-flex; align-items: center; gap: 3px; font-size: 9.5px; font-weight: 700; padding: 1px 6px; border-radius: 6px; background: rgb(65 105 225 / 0.12); color: #27408b; }
.hub-sp.is-dark .hub-sp-cat { background: rgba(255, 255, 255, 0.16); color: #fff; }
.hub-sp-cat > span { width: 10px; height: 10px; }
.hub-sp-steps { font-size: 14px; font-weight: 900; letter-spacing: 0.02em; color: #4169e1; }
.hub-sp.is-dark .hub-sp-steps { color: #ffb25e; }
.hub-sp-when { font-size: 10.5px; opacity: 0.75; }
.hub-sp-empty { font-size: 11px; opacity: 0.7; padding: 10px; margin: 0; }
</style>
