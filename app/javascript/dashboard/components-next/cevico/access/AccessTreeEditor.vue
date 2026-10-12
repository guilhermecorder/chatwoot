<script setup>
// 🔐 rodada 334 — EDITOR DA ÁRVORE DE ACESSOS (reutilizável).
//
// Mostra o catálogo do servidor em árvore e deixa o admin marcar, nó a nó,
// o que a pessoa (ou o papel) pode fazer: Herda | Nada | Ver | Editar.
//   • `modelValue` guarda SÓ as marcações explícitas { 'crm': 'edit' };
//     o nível que vai valer em cada nó (herança do pai, papel, padrão)
//     é calculado aqui mesmo com o helper cevicoAccessTree.
//   • marcar o PAI não grava nos filhos — a herança faz o resto; filho com
//     marcação própria ganha um pontinho e o pai um "limpar os filhos".
//   • nó "só administradores" aparece com cadeado e não se mexe.
//   • `admin` = o alvo é administrador(a): tudo aparece travado no máximo.
//   • `readonly` = só mostra o nível efetivo (Mapa do sistema).
// Precisa estar dentro de um `.cv-page` (os tokens --cv-* vêm de lá).
import { ref, computed, watch, provide } from 'vue';
import AccessTreeNode from './AccessTreeNode.vue';
import './access.scss';
import {
  flattenCatalog,
  effectiveMap,
  effectiveLevel,
  explicitLevel,
  mergedMarks,
  summarize,
  clampLevel,
  descendantsOf,
  adminLocked,
  subtreeHasMarks,
  LEVEL_LABELS,
  INHERIT,
} from 'dashboard/helper/cevicoAccessTree';

const props = defineProps({
  catalog: { type: Array, required: true },
  modelValue: { type: Object, default: () => ({}) },
  roleTree: { type: Object, default: () => ({}) },
  admin: { type: Boolean, default: false },
  readonly: { type: Boolean, default: false },
  // abre todos os pais logo de cara (Mapa do sistema)
  startExpanded: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);

const index = computed(() => flattenCatalog(props.catalog));
const roots = computed(() =>
  (props.catalog || []).map(n => String(n.key)).filter(k => index.value[k])
);
const marks = computed(() => props.modelValue || {});
const effective = computed(() =>
  effectiveMap({
    catalog: index.value,
    explicit: marks.value,
    roleTree: props.roleTree,
    admin: props.admin,
  })
);
const summary = computed(() => summarize(effective.value));
const locked = computed(() => props.readonly || props.admin);

// ── busca: filtra e abre os pais que têm algum filho batendo ──
const search = ref('');
const norm = s =>
  String(s || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase();
const term = computed(() => norm(search.value.trim()));
const matches = key => {
  if (!term.value) return true;
  const n = index.value[key];
  return (
    norm(n?.label).includes(term.value) ||
    norm(n?.hint).includes(term.value) ||
    norm(key).includes(term.value)
  );
};
const visible = key =>
  !term.value ||
  matches(key) ||
  descendantsOf(index.value, key).some(k => matches(k));

// ── pais abertos/fechados: começam fechados, menos os que têm marcação
//    própria em algum filho (ou tudo aberto, no Mapa) ──
const expanded = ref({});
const resetExpanded = () => {
  const next = {};
  Object.keys(index.value).forEach(key => {
    const node = index.value[key];
    if (!node.children.length) return;
    if (props.startExpanded || subtreeHasMarks(index.value, marks.value, key)) {
      next[key] = true;
    }
  });
  expanded.value = next;
};
watch(index, resetExpanded, { immediate: true });
const isExpanded = key =>
  term.value
    ? descendantsOf(index.value, key).some(k => matches(k))
    : expanded.value[key] === true;
const toggle = key => {
  expanded.value = { ...expanded.value, [key]: !expanded.value[key] };
};
const expandAll = open => {
  const next = {};
  if (open) {
    Object.keys(index.value).forEach(key => {
      if (index.value[key].children.length) next[key] = true;
    });
  }
  expanded.value = next;
};

// ── marcações ──
const emitMarks = next => emit('update:modelValue', next);
const setLevel = (key, level) => {
  if (locked.value || adminLocked(index.value, key)) return;
  const next = { ...marks.value };
  if (level === INHERIT) delete next[key];
  else next[key] = clampLevel(index.value[key], level);
  emitMarks(next);
};
const clearChildren = key => {
  if (locked.value) return;
  const next = { ...marks.value };
  descendantsOf(index.value, key).forEach(k => delete next[k]);
  emitMarks(next);
};
// Ver tudo / Editar tudo: marca só as RAÍZES (a herança leva aos filhos)
const setAll = level => {
  if (locked.value) return;
  const next = {};
  roots.value.forEach(key => {
    if (adminLocked(index.value, key)) return;
    next[key] = clampLevel(index.value[key], level);
  });
  emitMarks(next);
};
const clearAll = () => !locked.value && emitMarks({});

// o nível que vale em "Herda" (como se o nó não tivesse marcação própria)
// e de onde ele vem (pai, papel ou padrão)
const inherited = key => {
  const without = { ...marks.value };
  delete without[key];
  const level = effectiveLevel({
    catalog: index.value,
    explicit: without,
    roleTree: props.roleTree,
    key,
    admin: false,
  });
  const all = mergedMarks(index.value, without, props.roleTree);
  const found = explicitLevel(index.value, all, key);
  let from = 'padrão do sistema';
  if (found) {
    const ownMark = found.from in without;
    const label = index.value[found.from]?.label || found.from;
    if (found.from === key) from = 'do papel';
    else from = ownMark ? `de ${label}` : `do papel (${label})`;
  }
  return { level, from };
};

provide('cvAccessTree', {
  index,
  marks,
  effective,
  locked,
  readonly: computed(() => props.readonly),
  admin: computed(() => props.admin),
  isExpanded,
  toggle,
  visible,
  matches,
  setLevel,
  clearChildren,
  inherited,
});

const anyParent = computed(() =>
  Object.values(index.value).some(n => n.children.length)
);
const allOpen = computed(() =>
  Object.values(index.value)
    .filter(n => n.children.length)
    .every(n => expanded.value[n.key])
);
const LEVEL_LIST = ['view', 'edit', 'none'];
defineExpose({ summary, effective, LEVEL_LABELS });
</script>

<template>
  <div class="cv-acc">
    <!-- topo: resumo + busca + atalhos -->
    <div class="cv-acc-top">
      <div class="cv-acc-summary">
        <span
          v-for="lvl in LEVEL_LIST"
          :key="lvl"
          class="cv-acc-pill cv-acc-pill-sm"
          :class="`cv-acc-${lvl}`"
          :title="`${summary[lvl]} ${summary[lvl] === 1 ? 'tela' : 'telas'} em “${LEVEL_LABELS[lvl]}”`"
        >
          {{ LEVEL_LABELS[lvl] }}
          <b>{{ summary[lvl] }}</b>
        </span>
      </div>
      <label class="cv-acc-search">
        <span class="i-lucide-search text-sm opacity-60" />
        <input
          v-model="search"
          type="search"
          class="cv-input"
          placeholder="Buscar tela…"
          aria-label="Buscar tela"
        />
      </label>
      <div class="cv-acc-actions">
        <button
          v-if="anyParent"
          class="cv-btn cv-btn-ghost cv-btn-sm"
          type="button"
          @click="expandAll(!allOpen)"
        >
          <span
            :class="
              allOpen
                ? 'i-lucide-chevrons-down-up'
                : 'i-lucide-chevrons-up-down'
            "
            class="text-xs"
          />
          {{ allOpen ? 'Recolher' : 'Abrir tudo' }}
        </button>
        <template v-if="!locked">
          <button
            class="cv-btn cv-btn-ghost cv-btn-sm cv-acc-btn-view"
            type="button"
            title="Marca Ver em todas as áreas (os filhos herdam)"
            @click="setAll('view')"
          >
            <span class="i-lucide-eye text-xs" /> Ver tudo
          </button>
          <button
            class="cv-btn cv-btn-ghost cv-btn-sm cv-acc-btn-edit"
            type="button"
            title="Marca Editar em todas as áreas (os filhos herdam)"
            @click="setAll('edit')"
          >
            <span class="i-lucide-pencil text-xs" /> Editar tudo
          </button>
          <button
            class="cv-btn cv-btn-ghost cv-btn-sm"
            type="button"
            title="Apaga todas as marcações próprias (volta ao papel ou ao padrão)"
            @click="clearAll"
          >
            <span class="i-lucide-eraser text-xs" /> Limpar tudo
          </button>
        </template>
      </div>
    </div>

    <p v-if="admin" class="cv-acc-note">
      <span class="i-lucide-crown text-xs" />
      administrador(a): tudo liberado, nada para marcar aqui.
    </p>
    <p v-else-if="readonly" class="cv-acc-note">
      <span class="i-lucide-info text-xs" />
      o que um atendente SEM configuração tem em cada tela.
    </p>
    <p v-else class="cv-acc-note">
      <span class="i-lucide-info text-xs" />
      marcar uma área vale para tudo dentro dela; só mexa no filho quando ele
      for diferente do pai. “Herda” mostra, entre parênteses, o que vai valer.
    </p>

    <!-- a árvore -->
    <div class="cv-acc-tree">
      <template v-for="key in roots" :key="key">
        <AccessTreeNode v-if="visible(key)" :node-key="key" :depth="0" />
      </template>
      <p v-if="term && !roots.some(k => visible(k))" class="cv-acc-empty">
        nenhuma tela com “{{ search }}”.
      </p>
    </div>
  </div>
</template>
