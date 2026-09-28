<script setup>
// Corpo do Painel do empresário: nasce já com o quadro carregado (o autosave
// do useBusinessBoard depende disso). Barra de edição sempre à mão — mais
// solta que o modo edição do Meu Painel: sem "entrar em editar", o quadro
// já se move; a barra só guarda os extras (arrumar sozinho, quadros
// escondidos, travar, voltar ao padrão).
import { ref, computed, provide } from 'vue';
import { useAlert } from 'dashboard/composables';
import EmojiFx from 'dashboard/components-next/cevico/EmojiFx.vue';
import MagnetBoard from './MagnetBoard.vue';
import { mergeLayout, compact, place } from './magnetLayout';
import { useBusinessBoard, fmtDay } from './useBusinessBoard';
import { CARD_BY_ID, DEFAULT_LAYOUT } from './cards';

const props = defineProps({
  initial: { type: Object, default: () => ({}) },
  metrics: { type: Object, default: null },
});

const { board, saveState, savedAt, log, stampNew, updateItem } =
  useBusinessBoard(props.initial);
const fx = ref(null);
const celebrate = event => {
  const x = event?.clientX ?? window.innerWidth / 2;
  const y = event?.clientY ?? window.innerHeight / 3;
  fx.value?.burstAt(x, y, ['🏆', '🎉', '✨'], 5);
};
provide('biz', {
  board,
  log,
  stampNew,
  updateItem,
  celebrate,
  toast: msg => useAlert(msg),
  metrics: computed(() => props.metrics),
});

// ── layout (o ímã) ──
board.value.layout = mergeLayout(board.value.layout, DEFAULT_LAYOUT);
const layout = computed({
  get: () => board.value.layout,
  set: v => {
    board.value.layout = v;
  },
});
const hiddenCards = computed(() =>
  layout.value
    .filter(i => i.hidden)
    .map(i => CARD_BY_ID[i.id])
    .filter(Boolean)
);

const setHidden = (id, hidden) => {
  const list = layout.value.map(i =>
    i.id === id ? { ...i, hidden, y: hidden ? i.y : 9999 } : i
  );
  const visible = compact(list.filter(i => !i.hidden));
  layout.value = [...visible, ...list.filter(i => i.hidden)];
};
const tidy = () => {
  layout.value = [
    ...compact(layout.value.filter(i => !i.hidden)),
    ...layout.value.filter(i => i.hidden),
  ];
  useAlert('Quadro arrumado ✓');
};
const resetLayout = () => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      'Voltar os quadros para as posições e tamanhos de fábrica? (as anotações ficam)'
    )
  )
    return;
  layout.value = DEFAULT_LAYOUT.map(i => ({ ...i }));
};
const toggleLock = () => {
  board.value.locked = !board.value.locked;
};

// largura rápida pelo menu do quadro
const WIDTHS = [
  { w: 4, label: '⅓' },
  { w: 6, label: '½' },
  { w: 8, label: '⅔' },
  { w: 12, label: 'inteira' },
];
const menuFor = ref(null);
const setWidth = (id, w) => {
  const visible = layout.value.filter(i => !i.hidden);
  layout.value = [
    ...place(visible, id, { w }),
    ...layout.value.filter(i => i.hidden),
  ];
  menuFor.value = null;
};
// altura na medida do conteúdo (o que está dentro decide)
const bodies = {};
const fitHeight = id => {
  const el = bodies[id];
  if (!el) return;
  // conteúdo + cabeçalho (≈58 px) + respiros do corpo (2 × 16 px); grade = 16 px + 14 de vão
  const content =
    el.firstElementChild?.getBoundingClientRect().height || el.scrollHeight;
  const need = content + 58 + 32;
  const h = Math.max(6, Math.ceil((need + 14) / 30));
  const visible = layout.value.filter(i => !i.hidden);
  layout.value = [
    ...place(visible, id, { h }),
    ...layout.value.filter(i => i.hidden),
  ];
  menuFor.value = null;
};

const saveLabel = computed(() => {
  if (saveState.value === 'saving') return 'Salvando…';
  if (saveState.value === 'saved') return `Salvo às ${savedAt.value}`;
  if (saveState.value === 'error')
    return 'Não salvou — tento de novo na próxima mudança';
  return 'Salva sozinho';
});
const wins = computed(() =>
  ['objectives', 'goals', 'activities'].reduce(
    (n, k) => n + board.value[k].filter(i => i.status === 'conquistado').length,
    0
  )
);
const lastEvent = computed(() => board.value.events[0] || null);
</script>

<template>
  <div class="biz-body" @click="menuFor = null">
    <!-- barra de edição: sempre à mão, sem "modo" -->
    <div class="biz-editbar">
      <span class="biz-save" :class="`biz-save-${saveState}`">
        <span
          :class="
            saveState === 'saving'
              ? 'i-lucide-loader-2 animate-spin'
              : saveState === 'error'
                ? 'i-lucide-alert-triangle'
                : 'i-lucide-cloud-check'
          "
        />
        {{ saveLabel }}
      </span>
      <span class="biz-hint hidden xl:inline">
        Pegue pelo título para mover · puxe a borda ou o canto para esticar
      </span>
      <span class="flex-1" />
      <span v-if="wins" class="biz-chip"
        >🏆 {{ wins }} conquista{{ wins > 1 ? 's' : '' }}</span
      >
      <span
        v-if="lastEvent"
        class="biz-chip hidden lg:inline-flex"
        :title="lastEvent.text"
      >
        último registro {{ fmtDay(lastEvent.at) }}
      </span>
      <div class="relative" @click.stop>
        <button
          class="biz-btn"
          :disabled="!hiddenCards.length"
          @click="menuFor = menuFor === '__add' ? null : '__add'"
        >
          <span class="i-lucide-layout-grid" /> Quadros
          <span v-if="hiddenCards.length" class="biz-badge">{{
            hiddenCards.length
          }}</span>
        </button>
        <div v-if="menuFor === '__add'" class="biz-menu biz-menu-right">
          <p class="biz-label">Quadros escondidos</p>
          <button
            v-for="c in hiddenCards"
            :key="c.id"
            class="biz-menu-item"
            @click="
              setHidden(c.id, false);
              menuFor = null;
            "
          >
            <span :class="c.icon" :style="{ color: c.color }" /> {{ c.title }}
          </button>
        </div>
      </div>
      <button
        class="biz-btn"
        title="Encosta tudo e tira os buracos"
        @click="tidy"
      >
        <span class="i-lucide-magnet" /> Arrumar sozinho
      </button>
      <button
        class="biz-btn"
        :class="{ 'biz-btn-on': board.locked }"
        :title="
          board.locked
            ? 'Destravar: voltar a mover'
            : 'Travar: nada se move sem querer'
        "
        @click="toggleLock"
      >
        <span :class="board.locked ? 'i-lucide-lock' : 'i-lucide-lock-open'" />
        {{ board.locked ? 'Travado' : 'Travar' }}
      </button>
      <button
        class="biz-btn biz-btn-ghost"
        title="Posições e tamanhos de fábrica"
        @click="resetLayout"
      >
        <span class="i-lucide-rotate-ccw" />
      </button>
    </div>

    <MagnetBoard v-model:layout="layout" :locked="board.locked">
      <template #card="{ item, dragging }">
        <article
          class="biz-card"
          :class="{ 'biz-card-dragging': dragging }"
          :style="{ '--accent': CARD_BY_ID[item.id]?.color }"
        >
          <header class="biz-card-head" data-drag-handle>
            <span class="biz-card-icon">
              <span :class="CARD_BY_ID[item.id]?.icon" />
            </span>
            <div class="min-w-0 flex-1">
              <h3 class="biz-card-title">{{ CARD_BY_ID[item.id]?.title }}</h3>
              <p class="biz-card-sub">{{ CARD_BY_ID[item.id]?.sub }}</p>
            </div>
            <div class="relative" @click.stop>
              <button
                class="biz-iconbtn"
                title="Tamanho e opções"
                @click="menuFor = menuFor === item.id ? null : item.id"
              >
                <span class="i-lucide-ellipsis" />
              </button>
              <div v-if="menuFor === item.id" class="biz-menu biz-menu-right">
                <p class="biz-label">Largura</p>
                <div class="flex gap-1 mb-2">
                  <button
                    v-for="o in WIDTHS"
                    :key="o.w"
                    class="biz-chip"
                    :class="{ 'biz-chip-on': item.w === o.w }"
                    @click="setWidth(item.id, o.w)"
                  >
                    {{ o.label }}
                  </button>
                </div>
                <button class="biz-menu-item" @click="fitHeight(item.id)">
                  <span class="i-lucide-move-vertical" /> Altura do tamanho do
                  conteúdo
                </button>
                <button
                  class="biz-menu-item"
                  @click="
                    setHidden(item.id, true);
                    menuFor = null;
                  "
                >
                  <span class="i-lucide-eye-off" /> Esconder este quadro
                </button>
              </div>
            </div>
          </header>
          <div :ref="el => (bodies[item.id] = el)" class="biz-card-body">
            <component
              :is="CARD_BY_ID[item.id]?.comp"
              v-bind="CARD_BY_ID[item.id]?.props || {}"
            />
          </div>
        </article>
      </template>
    </MagnetBoard>
    <EmojiFx ref="fx" />
  </div>
</template>
