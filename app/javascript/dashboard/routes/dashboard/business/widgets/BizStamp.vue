<script setup>
// Data de cada anotação ("desde 27/09 · atualizado 30/09") + o botão
// ATUALIZAR: ação feita, conquistado, pivotou ou ajuste, com uma nota. O
// histórico fica no próprio item e vai para a Linha do tempo.
import { ref, computed, inject, nextTick } from 'vue';
import { UPDATE_KINDS, fmtDay } from '../useBusinessBoard';

const props = defineProps({
  item: { type: Object, required: true },
  card: { type: String, required: true }, // nome do quadro (linha do tempo)
  kinds: {
    type: Array,
    default: () => ['acao', 'conquista', 'pivot', 'ajuste'],
  },
});

const biz = inject('biz');
const open = ref(false);
const kind = ref('acao');
const note = ref('');
const noteEl = ref(null);

const since = computed(() => fmtDay(props.item.created_at));
const updated = computed(() => fmtDay(props.item.updated_at));
const last = computed(() => (props.item.history || []).slice(-1)[0] || null);
const status = computed(() => {
  if (props.item.status === 'conquistado') return UPDATE_KINDS.conquista;
  if (props.item.status === 'pivotado') return UPDATE_KINDS.pivot;
  return null;
});
const title = computed(() =>
  (props.item.history || [])
    .map(
      h =>
        `${fmtDay(h.at)} ${UPDATE_KINDS[h.kind]?.emoji || ''} ${UPDATE_KINDS[h.kind]?.label || h.kind}${h.note ? ` — ${h.note}` : ''}`
    )
    .join('\n')
);

const toggle = async () => {
  open.value = !open.value;
  if (open.value) {
    kind.value = props.kinds[0];
    note.value = '';
    await nextTick();
    noteEl.value?.focus();
  }
};
const confirm = () => {
  biz.updateItem(props.item, kind.value, note.value.trim(), props.card);
  if (kind.value === 'conquista') biz.celebrate?.();
  open.value = false;
};
</script>

<template>
  <div class="biz-stamp" data-no-drag>
    <span
      v-if="status"
      class="biz-stamp-status"
      :style="{ color: status.color }"
    >
      {{ status.emoji }} {{ status.label.toLowerCase() }}
    </span>
    <span v-if="since" :title="title || undefined">desde {{ since }}</span>
    <span v-if="updated" :title="title || undefined">
      · {{ last ? UPDATE_KINDS[last.kind]?.emoji : '' }} {{ updated }}
    </span>
    <button
      class="biz-stamp-btn"
      title="Atualizar: ação feita, conquista, pivô ou ajuste"
      @click.stop="toggle"
    >
      <span class="i-lucide-refresh-cw" /> atualizar
    </button>
    <div v-if="open" class="biz-pop" @click.stop>
      <div class="biz-pop-kinds">
        <button
          v-for="k in kinds"
          :key="k"
          class="biz-pop-kind"
          :class="{ on: kind === k }"
          :style="kind === k ? { '--k': UPDATE_KINDS[k].color } : {}"
          @click="kind = k"
        >
          {{ UPDATE_KINDS[k].emoji }} {{ UPDATE_KINDS[k].label }}
        </button>
      </div>
      <input
        ref="noteEl"
        v-model="note"
        class="biz-pop-input"
        placeholder="O que mudou? (opcional)"
        @keydown.enter.prevent="confirm"
        @keydown.esc="open = false"
      />
      <div class="biz-pop-foot">
        <button class="biz-pop-cancel" @click="open = false">cancelar</button>
        <button class="biz-pop-ok" @click="confirm">registrar hoje</button>
      </div>
    </div>
  </div>
</template>
