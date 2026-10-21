<script setup>
// 🧲 QUADRO COM ÍMÃ (Painel do empresário, 27/09). Mais solto que o modo
// edição do Meu Painel: não precisa entrar em "editar" — pega pelo título e
// arrasta; o quadro segue o dedo, os vizinhos abrem espaço AO VIVO e, ao
// soltar, ele desliza até a vaga com uma molinha. A borda direita, a de
// baixo e o canto esticam (horizontal, vertical ou os dois). Tudo encaixa na
// grade de 12 colunas (magnetLayout.js). Em tela estreita vira uma coluna só.
//
// 28/09 (item 266): o mesmo ímã vai para o MEU PAINEL. Lá os blocos têm
// altura que o CONTEÚDO decide (lista que cresce, gráfico que carrega…), então
// nasceu o modo `auto-height`: cada quadro é medido (ResizeObserver) e a
// altura em linhas vem da medida — só se arrasta e se estica para os lados;
// quem está embaixo desce/sobe sozinho quando o conteúdo muda. Bloco sem
// conteúdo (altura 0) não ocupa vaga. `stack-below` e `handle` (seletor da
// alça) também viraram props para cada tela usar o seu.
import { ref, computed, onMounted, onBeforeUnmount, nextTick } from 'vue';
import { place, compact, boardHeight, colsOf } from './magnetLayout';

const props = defineProps({
  layout: { type: Array, required: true }, // [{ id, x, y, w, h, hidden }]
  locked: { type: Boolean, default: false },
  // altura pelo conteúdo (Meu Painel): mede cada quadro, sem alça de altura
  autoHeight: { type: Boolean, default: false },
  // abaixo desta largura (px): uma coluna só, sem arrastar
  stackBelow: { type: Number, default: 760 },
  // onde se pega para arrastar (seletor CSS)
  handle: { type: String, default: '[data-drag-handle]' },
  // 28/09: x e largura só em múltiplos de N colunas (cards: 3 → grade de 4)
  snap: { type: [Number, Object], default: 1 },
  // 28/09: quantas colunas tem a grade (blocos = 12; cards = N quadrados por linha)
  cols: { type: Number, default: 12 },
});
const emit = defineEmits(['update:layout', 'moved']);
// opções do motor (snap + colunas), sempre juntas
const layoutOpts = computed(() =>
  props.snap && typeof props.snap === 'object'
    ? { ...props.snap, cols: props.cols }
    : { x: props.snap || 1, cols: props.cols }
);

// altura de 1 linha da grade (px): no modo automático a linha é mais fina
// (passo de 18 px) para a altura medida "bater" com o conteúdo
const ROW = props.autoHeight ? 4 : 16;
const GAP = 14; // respiro entre quadros (px)
const DRAG_START = 5; // px antes de começar a arrastar (clique continua clique)

const root = ref(null);
const width = ref(0);
let observer = null;
onMounted(() => {
  // medida já na montagem (o ResizeObserver só entrega quando a aba desenha
  // um quadro — em aba escondida ele pode demorar)
  if (root.value?.clientWidth) width.value = root.value.clientWidth;
  observer = new ResizeObserver(entries => {
    width.value = entries[0].contentRect.width;
  });
  if (root.value) observer.observe(root.value);
});

const stacked = computed(
  () => width.value > 0 && width.value < props.stackBelow
);
const colW = computed(
  () =>
    (width.value - GAP * (colsOf(layoutOpts.value) - 1)) /
    colsOf(layoutOpts.value)
);
const toPx = it => ({
  left: it.x * (colW.value + GAP),
  top: it.y * (ROW + GAP),
  width: it.w * colW.value + (it.w - 1) * GAP,
  height: it.h * ROW + (it.h - 1) * GAP,
});

// ── modo automático: a altura de cada quadro vem da medida do conteúdo ──
const measured = ref({}); // id → altura em px (0 = sem conteúdo)
let sizer = null;
const sizerIds = new Map(); // elemento → id
const rowsFor = px => Math.max(1, Math.ceil((px + GAP) / (ROW + GAP)));
// uma função de ref por quadro (nova a cada render faria o Vue soltar e
// religar o observador toda hora)
const refFns = {};
const measureEl = id => el => {
  if (!props.autoHeight) return;
  if (!el) {
    [...sizerIds.entries()].forEach(([node, nid]) => {
      if (nid === id) {
        sizer?.unobserve(node);
        sizerIds.delete(node);
      }
    });
    return;
  }
  if (sizerIds.has(el)) return;
  sizerIds.set(el, id);
  // primeira medida logo depois de o DOM assentar (mesmo motivo acima)
  nextTick(() => {
    if (!sizerIds.has(el)) return;
    const px = Math.round(el.getBoundingClientRect().height);
    if (measured.value[id] !== px)
      measured.value = { ...measured.value, [id]: px };
  });
  if (!sizer && typeof ResizeObserver !== 'undefined') {
    sizer = new ResizeObserver(entries => {
      const next = { ...measured.value };
      let changed = false;
      entries.forEach(en => {
        const nid = sizerIds.get(en.target);
        if (!nid) return;
        const px = Math.round(en.contentRect.height);
        if (next[nid] !== px) {
          next[nid] = px;
          changed = true;
        }
      });
      if (changed) measured.value = next;
    });
  }
  sizer?.observe(el);
};
const measureRef = id => {
  if (!refFns[id]) refFns[id] = measureEl(id);
  return refFns[id];
};

const visible = computed(() => {
  const list = props.layout.filter(i => !i.hidden);
  if (!props.autoHeight) return list;
  // quadro medido com 0 px (conteúdo escondido por v-if) não ocupa vaga
  return list
    .filter(i => measured.value[i.id] !== 0)
    .map(i => {
      const px = measured.value[i.id];
      return { ...i, h: px === undefined ? i.h : rowsFor(px) };
    });
});
// no modo automático a arrumação é calculada aqui (as alturas mudam com o
// conteúdo e com a largura da tela); o que se salva é só a ORDEM (x/y/w)
const arranged = computed(() =>
  props.autoHeight ? compact(visible.value, layoutOpts.value) : visible.value
);

// ── arrastar / esticar ─────────────────────────────────────────────────────
const active = ref(null); // { id, mode, dir, sx, sy, orig, origPx, started }
const preview = ref(null); // layout provisório enquanto arrasta
const livePx = ref(null); // posição do quadro que está na mão
const landing = ref(null); // id do quadro deslizando até a vaga
const pulse = ref(0); // muda quando a vaga troca (o ímã "puxa")

const shown = computed(() => preview.value || arranged.value);
const byId = computed(() =>
  Object.fromEntries(shown.value.map(i => [i.id, i]))
);
const slot = computed(() =>
  active.value?.started ? byId.value[active.value.id] : null
);
const height = computed(() => {
  const rows = boardHeight(shown.value);
  return rows ? rows * (ROW + GAP) - GAP : 0;
});

const isFormField = el =>
  el.closest(
    'input, textarea, select, button, a, [contenteditable], [data-no-drag]'
  );

const onMove = e => {
  const a = active.value;
  if (!a) return;
  const dx = e.clientX - a.sx;
  const dy = e.clientY - a.sy;
  if (!a.started) {
    if (Math.hypot(dx, dy) < DRAG_START) return;
    a.started = true;
    document.body.classList.add(
      a.mode === 'drag' ? 'mb-grabbing' : `mb-resizing-${a.dir}`
    );
  }
  e.preventDefault();
  const stepX = colW.value + GAP;
  const stepY = ROW + GAP;
  let target;
  if (a.mode === 'drag') {
    livePx.value = {
      ...a.origPx,
      left: a.origPx.left + dx,
      top: a.origPx.top + dy,
    };
    target = {
      x: Math.round(livePx.value.left / stepX),
      y: Math.round(livePx.value.top / stepY),
    };
  } else {
    const w = a.dir.includes('e') ? a.origPx.width + dx : a.origPx.width;
    const h = a.dir.includes('s') ? a.origPx.height + dy : a.origPx.height;
    livePx.value = {
      ...a.origPx,
      width: Math.max(
        colW.value *
          Math.max(layoutOpts.value.minW ?? 2, layoutOpts.value.x || 1),
        w
      ),
      height: props.autoHeight ? a.origPx.height : Math.max(ROW * 4, h),
    };
    target = { w: Math.round((livePx.value.width + GAP) / stepX) };
    if (!props.autoHeight)
      target.h = Math.round((livePx.value.height + GAP) / stepY);
  }
  const next = place(arranged.value, a.id, target, layoutOpts.value);
  const was = byId.value[a.id];
  const now = next.find(i => i.id === a.id);
  if (
    !was ||
    was.x !== now.x ||
    was.y !== now.y ||
    was.w !== now.w ||
    was.h !== now.h
  ) {
    pulse.value += 1;
  }
  preview.value = next;
};

const stop = () => {
  window.removeEventListener('pointermove', onMove);
  window.removeEventListener('pointerup', onUp);
  window.removeEventListener('pointercancel', onUp);
  document.body.classList.remove(
    'mb-grabbing',
    'mb-resizing-e',
    'mb-resizing-s',
    'mb-resizing-se'
  );
};

// depois de arrastar, o navegador ainda dispara um "click" no quadro — quem
// tem clique próprio (card de indicador abre o popup) não pode receber esse
const swallowClick = e => {
  e.stopPropagation();
  e.preventDefault();
};
function onUp() {
  const a = active.value;
  stop();
  active.value = null;
  if (a?.started) {
    window.addEventListener('click', swallowClick, { capture: true });
    setTimeout(
      () =>
        window.removeEventListener('click', swallowClick, { capture: true }),
      300
    );
  }
  if (a?.started && preview.value) {
    const hidden = props.layout.filter(i => i.hidden);
    emit('update:layout', [...preview.value, ...hidden]);
    emit('moved', a.id);
    landing.value = a.id;
    setTimeout(() => {
      if (landing.value === a.id) landing.value = null;
    }, 420);
  }
  preview.value = null;
  livePx.value = null;
}

const start = (e, item, mode, dir = '') => {
  if (props.locked || stacked.value || e.button > 0) return;
  if (mode === 'drag') {
    if (!e.target.closest(props.handle) || isFormField(e.target)) return;
  }
  active.value = {
    id: item.id,
    mode,
    dir,
    sx: e.clientX,
    sy: e.clientY,
    // parte de onde o quadro ESTÁ (arrumação atual), não do y salvo
    origPx: toPx(byId.value[item.id] || item),
    started: false,
  };
  window.addEventListener('pointermove', onMove, { passive: false });
  window.addEventListener('pointerup', onUp);
  window.addEventListener('pointercancel', onUp);
};
onBeforeUnmount(() => {
  stop();
  observer?.disconnect();
  sizer?.disconnect();
});

const styleFor = item => {
  if (stacked.value) return {};
  const inHand = active.value?.started && active.value.id === item.id;
  const px =
    inHand && livePx.value ? livePx.value : toPx(byId.value[item.id] || item);
  if (props.autoHeight) {
    // left/top em vez de transform: transform viraria "containing block" de
    // qualquer fixed/sticky dentro do bloco (modais, barras grudadas)
    return {
      width: `${px.width}px`,
      left: `${px.left}px`,
      top: `${px.top}px`,
    };
  }
  return {
    width: `${px.width}px`,
    height: `${px.height}px`,
    transform: `translate3d(${px.left}px, ${px.top}px, 0)`,
  };
};
const slotStyle = computed(() => {
  if (!slot.value) return null;
  const px = toPx(slot.value);
  if (props.autoHeight)
    return {
      width: `${px.width}px`,
      height: `${px.height}px`,
      left: `${px.left}px`,
      top: `${px.top}px`,
    };
  return {
    width: `${px.width}px`,
    height: `${px.height}px`,
    transform: `translate3d(${px.left}px, ${px.top}px, 0)`,
  };
});
const stackOrder = computed(() =>
  [...props.layout.filter(i => !i.hidden)].sort(
    (a, b) => a.y - b.y || a.x - b.x
  )
);
// o que se desenha: no modo automático, TODOS os visíveis (os de 0 px ficam
// invisíveis no lugar, prontos para aparecer quando ganharem conteúdo)
const drawn = computed(() => {
  if (stacked.value) return stackOrder.value;
  if (props.autoHeight) return props.layout.filter(i => !i.hidden);
  return visible.value;
});
const isParked = item => props.autoHeight && measured.value[item.id] === 0;
</script>

<template>
  <div
    ref="root"
    class="mb-board"
    :class="{ 'mb-stacked': stacked, 'mb-locked': locked }"
    :style="stacked ? {} : { height: `${height}px` }"
  >
    <!-- a vaga do ímã: brilha onde o quadro vai encaixar -->
    <div
      v-if="slotStyle"
      :key="pulse"
      class="mb-slot"
      :style="slotStyle"
      aria-hidden="true"
    />
    <div
      v-for="item in drawn"
      :key="item.id"
      class="mb-item"
      :class="{
        'mb-inhand': active?.started && active.id === item.id,
        'mb-landing': landing === item.id,
        'mb-parked': isParked(item),
        'mb-auto': autoHeight,
        'mb-resizing':
          active?.started && active.id === item.id && active.mode === 'resize',
      }"
      :style="styleFor(item)"
      @pointerdown="start($event, item, 'drag')"
    >
      <div :ref="measureRef(item.id)" class="mb-measure">
        <slot
          name="card"
          :item="item"
          :dragging="!!(active?.started && active.id === item.id)"
          :stacked="stacked"
        />
      </div>
      <template v-if="!locked && !stacked">
        <span
          class="mb-grip mb-grip-e"
          title="Esticar para os lados"
          @pointerdown.stop="start($event, item, 'resize', 'e')"
        />
        <template v-if="!autoHeight">
          <span
            class="mb-grip mb-grip-s"
            title="Esticar para baixo"
            @pointerdown.stop="start($event, item, 'resize', 's')"
          />
          <span
            class="mb-grip mb-grip-se"
            title="Esticar nas duas direções"
            @pointerdown.stop="start($event, item, 'resize', 'se')"
          />
        </template>
      </template>
    </div>
  </div>
</template>

<style lang="scss">
.mb-board {
  position: relative;
  width: 100%;
  transition: height 0.3s ease;
}
.mb-item {
  position: absolute;
  top: 0;
  left: 0;
  will-change: transform;
  transition:
    transform 0.32s cubic-bezier(0.2, 0.8, 0.2, 1),
    width 0.32s cubic-bezier(0.2, 0.8, 0.2, 1),
    height 0.32s cubic-bezier(0.2, 0.8, 0.2, 1);
}
.mb-stacked > .mb-item {
  position: relative;
  transform: none !important;
  width: auto !important;
  margin-bottom: 14px;
}
.mb-measure {
  min-width: 0;
  display: flow-root; /* a medida inclui as margens de dentro */
}
/* modo automático: anda por left/top, sem will-change (ver styleFor) */
.mb-item.mb-auto {
  will-change: auto;
  transition:
    left 0.32s cubic-bezier(0.2, 0.8, 0.2, 1),
    top 0.32s cubic-bezier(0.2, 0.8, 0.2, 1),
    width 0.32s cubic-bezier(0.2, 0.8, 0.2, 1);
}
.mb-item.mb-auto.mb-inhand {
  transition: none;
}
.mb-item.mb-auto.mb-landing {
  transition:
    left 0.42s cubic-bezier(0.34, 1.56, 0.64, 1),
    top 0.42s cubic-bezier(0.34, 1.56, 0.64, 1),
    width 0.42s cubic-bezier(0.34, 1.56, 0.64, 1);
}
.mb-stacked > .mb-item.mb-auto {
  left: auto !important;
  top: auto !important;
}
.mb-item:not(.mb-auto) > .mb-measure,
.mb-item:not(.mb-auto) > .mb-measure > :first-child {
  height: 100%;
}
/* quadro sem conteúdo no modo automático: fica invisível, sem ocupar vaga */
.mb-item.mb-parked {
  pointer-events: none;
  opacity: 0;
}
.mb-stacked > .mb-item.mb-parked {
  display: none;
}
.mb-item.mb-inhand {
  z-index: 30;
  transition: none;
  filter: drop-shadow(0 28px 40px rgb(15 23 42 / 0.22));
}
.mb-item.mb-inhand:not(.mb-resizing) > .mb-measure {
  transform: scale(1.015) rotate(-0.4deg);
  transition: transform 0.18s ease;
}
/* soltou: desliza até a vaga com uma molinha */
.mb-item.mb-landing {
  z-index: 20;
  transition:
    transform 0.42s cubic-bezier(0.34, 1.56, 0.64, 1),
    width 0.42s cubic-bezier(0.34, 1.56, 0.64, 1),
    height 0.42s cubic-bezier(0.34, 1.56, 0.64, 1);
}
.mb-slot {
  position: absolute;
  top: 0;
  left: 0;
  z-index: 1;
  border-radius: 24px;
  border: 1.5px dashed rgb(212 175 55 / 0.75);
  background: radial-gradient(
      120% 90% at 50% 0%,
      rgb(212 175 55 / 0.16),
      transparent 70%
    ),
    rgb(255 255 255 / 0.35);
  box-shadow:
    0 0 0 6px rgb(212 175 55 / 0.08),
    inset 0 0 30px rgb(212 175 55 / 0.12);
  backdrop-filter: blur(6px);
  transition:
    transform 0.22s cubic-bezier(0.2, 0.8, 0.2, 1),
    width 0.22s ease,
    height 0.22s ease;
  animation: mb-snap 0.34s ease-out;
}
@keyframes mb-snap {
  0% {
    box-shadow:
      0 0 0 0 rgb(212 175 55 / 0.45),
      inset 0 0 30px rgb(212 175 55 / 0.12);
  }
  100% {
    box-shadow:
      0 0 0 10px rgb(212 175 55 / 0),
      inset 0 0 30px rgb(212 175 55 / 0.12);
  }
}
.dark .mb-slot {
  background: rgb(255 255 255 / 0.04);
}

/* alças de esticar: invisíveis até passar o mouse no quadro */
.mb-grip {
  position: absolute;
  z-index: 5;
  touch-action: none;
}
.mb-grip-e {
  top: 18px;
  right: -5px;
  bottom: 18px;
  width: 10px;
  cursor: ew-resize;
}
.mb-grip-s {
  left: 18px;
  right: 18px;
  bottom: -5px;
  height: 10px;
  cursor: ns-resize;
}
.mb-grip-se {
  right: 2px;
  bottom: 2px;
  width: 18px;
  height: 18px;
  cursor: nwse-resize;
  border-radius: 0 0 20px 0;
  opacity: 0;
  transition: opacity 0.2s ease;
  background: linear-gradient(
      135deg,
      transparent 55%,
      rgb(100 116 139 / 0.55) 55%,
      rgb(100 116 139 / 0.55) 62%,
      transparent 62%
    ),
    linear-gradient(
      135deg,
      transparent 72%,
      rgb(100 116 139 / 0.55) 72%,
      rgb(100 116 139 / 0.55) 79%,
      transparent 79%
    );
}
.mb-item:hover .mb-grip-se,
.mb-item.mb-resizing .mb-grip-se {
  opacity: 1;
}
.mb-grip-e::after,
.mb-grip-s::after {
  content: '';
  position: absolute;
  border-radius: 9999px;
  background: rgb(212 175 55 / 0.9);
  opacity: 0;
  transition: opacity 0.15s ease;
}
.mb-grip-e::after {
  top: 40%;
  bottom: 40%;
  left: 3px;
  width: 4px;
}
.mb-grip-s::after {
  left: 40%;
  right: 40%;
  top: 3px;
  height: 4px;
}
.mb-grip-e:hover::after,
.mb-grip-s:hover::after {
  opacity: 1;
}

body.mb-grabbing,
body.mb-grabbing * {
  cursor: grabbing !important;
  user-select: none !important;
}
body.mb-resizing-e * {
  cursor: ew-resize !important;
  user-select: none !important;
}
body.mb-resizing-s * {
  cursor: ns-resize !important;
  user-select: none !important;
}
body.mb-resizing-se * {
  cursor: nwse-resize !important;
  user-select: none !important;
}
.mb-locked [data-drag-handle] {
  cursor: default;
}
</style>
