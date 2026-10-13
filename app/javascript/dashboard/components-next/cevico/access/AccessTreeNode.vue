<script setup>
// 🔐 rodada 334 — UMA linha da árvore de acessos (recursiva: desenha os
// filhos quando o pai está aberto). Tudo vem do AccessTreeEditor por inject.
import { computed, inject } from 'vue';
import {
  adminLocked,
  maxLevel,
  subtreeHasMarks,
  LEVEL_LABELS,
  INHERIT,
} from 'dashboard/helper/cevicoAccessTree';

const props = defineProps({
  nodeKey: { type: String, required: true },
  depth: { type: Number, default: 0 },
});

const tree = inject('cvAccessTree');

const node = computed(() => tree.index.value[props.nodeKey] || {});
const children = computed(() => node.value.children || []);
const hasChildren = computed(() => children.value.length > 0);
const open = computed(() => tree.isExpanded(props.nodeKey));
const lockedNode = computed(() => adminLocked(tree.index.value, props.nodeKey));
const ownMark = computed(() => tree.marks.value[props.nodeKey]);
const hasOwnMark = computed(() => ownMark.value !== undefined);
const level = computed(() => tree.effective.value[props.nodeKey] || 'none');
const canEdit = computed(() => node.value.levels?.includes('edit'));
const top = computed(() => maxLevel(node.value));
const kidsMarked = computed(
  () =>
    hasChildren.value &&
    subtreeHasMarks(tree.index.value, tree.marks.value, props.nodeKey)
);
const editable = computed(() => !tree.locked.value && !lockedNode.value);
const inherited = computed(() =>
  editable.value ? tree.inherited(props.nodeKey) : null
);
const current = computed(() => (hasOwnMark.value ? ownMark.value : INHERIT));

const OPTIONS = computed(() => {
  const list = [
    {
      value: INHERIT,
      label: `Herda (${LEVEL_LABELS[inherited.value?.level || 'none']})`,
      title: `sem marcação própria: vale ${LEVEL_LABELS[inherited.value?.level || 'none']} — ${inherited.value?.from || ''}`,
    },
    { value: 'none', label: LEVEL_LABELS.none, title: 'não vê esta tela' },
    { value: 'view', label: LEVEL_LABELS.view, title: 'abre e lê' },
  ];
  if (canEdit.value) {
    list.push({
      value: 'edit',
      label: LEVEL_LABELS.edit,
      title: 'cria, altera, apaga (inclui ver)',
    });
  }
  return list;
});

const pick = value => tree.setLevel(props.nodeKey, value);
const visibleKids = computed(() => children.value.filter(k => tree.visible(k)));
</script>

<template>
  <div
    class="cv-acc-node"
    :class="{ 'cv-acc-node-hit': tree.matches(nodeKey) }"
  >
    <div
      class="cv-acc-row"
      :class="[
        `cv-acc-row-${level}`,
        { 'cv-acc-row-parent': hasChildren, 'cv-acc-row-locked': lockedNode },
      ]"
      :style="{ '--acc-depth': depth }"
    >
      <!-- seta de abrir/fechar -->
      <button
        v-if="hasChildren"
        type="button"
        class="cv-acc-caret"
        :aria-expanded="open"
        :title="open ? 'Recolher' : `Abrir (${children.length})`"
        @click="tree.toggle(nodeKey)"
      >
        <span
          class="text-sm"
          :class="open ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right'"
        />
      </button>
      <span v-else class="cv-acc-caret cv-acc-caret-leaf" aria-hidden="true">
        <span class="cv-acc-leafdot" :class="`cv-acc-leafdot-${level}`" />
      </span>

      <!-- nome + dica -->
      <div class="cv-acc-main">
        <div class="cv-acc-name">
          <span class="cv-acc-label">{{ node.label || nodeKey }}</span>
          <span
            v-if="hasOwnMark && !tree.locked.value"
            class="cv-acc-own"
            title="marcação própria neste nó"
          />
          <span
            v-if="hasChildren && !open"
            class="cv-acc-count"
            :title="`${children.length} dentro`"
          >
            {{ children.length }}
          </span>
          <span v-if="lockedNode" class="cv-tag cv-acc-lock">
            🔒 só administradores
          </span>
          <!-- nó "sem herança" (auditoria 12/10): a marcação do pai não desce -->
          <span
            v-else-if="node.explicit"
            class="cv-tag cv-acc-lock"
            title="não herda do pai: só vale com marcação própria aqui"
          >
            ✋ não herda
          </span>
        </div>
        <p v-if="node.hint" class="cv-acc-hint">{{ node.hint }}</p>
      </div>

      <!-- o controle -->
      <div class="cv-acc-ctrl">
        <template v-if="lockedNode">
          <span class="cv-acc-pill cv-acc-none" title="só administradores">
            <span class="i-lucide-lock text-[10px]" /> Nada
          </span>
        </template>
        <template v-else-if="tree.admin.value">
          <span
            class="cv-acc-pill"
            :class="`cv-acc-${top}`"
            title="administrador(a): tudo liberado"
          >
            <span class="i-lucide-crown text-[10px]" /> {{ LEVEL_LABELS[top] }}
          </span>
        </template>
        <template v-else-if="tree.readonly.value">
          <span class="cv-acc-pill" :class="`cv-acc-${level}`">
            {{ LEVEL_LABELS[level] }}
          </span>
        </template>
        <div v-else class="cv-seg cv-seg-sm cv-acc-seg" role="radiogroup">
          <button
            v-for="opt in OPTIONS"
            :key="opt.value"
            type="button"
            class="cv-seg-item"
            :class="[
              `cv-acc-seg-${opt.value}`,
              { 'cv-seg-on': current === opt.value },
            ]"
            role="radio"
            :aria-checked="current === opt.value"
            :title="opt.title"
            @click="pick(opt.value)"
          >
            {{ opt.label }}
          </button>
        </div>
        <button
          v-if="kidsMarked && editable"
          type="button"
          class="cv-acc-clearkids"
          title="apaga as marcações próprias dos filhos: todos passam a herdar deste nó"
          @click="tree.clearChildren(nodeKey)"
        >
          <span class="i-lucide-eraser text-[10px]" /> limpar os filhos
        </button>
        <span
          v-else-if="kidsMarked && tree.readonly.value === false"
          class="cv-acc-kidsdot"
          title="há marcação própria em algum filho"
        />
      </div>
    </div>

    <!-- os filhos -->
    <div v-if="hasChildren && open" class="cv-acc-kids">
      <AccessTreeNode
        v-for="kid in visibleKids"
        :key="kid"
        :node-key="kid"
        :depth="depth + 1"
      />
    </div>
  </div>
</template>
