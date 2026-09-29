<script setup>
// 🖱️ CevicoContextMenu (item 283, 29/09): o MENU DO BOTÃO DIREITO do CEVICO.
// Montado UMA vez (Dashboard.vue) e desenhado no <body> por Teleport — por
// isso tem estilo próprio (mora fora da .cv-page), igual ao popup da chamada.
// Quem abre é o composable useCevicoContextMenu (openMenu / v-cv-menu).
// Fecha com Esc, clique fora, rolagem, troca de tela ou ao escolher; anda
// pelo teclado (setas, Enter); itens com `children` abrem um segundo nível.
// Item "paleta" (item 290): fileira de bolinhas de cor + botão "Padrão".
import { ref, computed, watch, nextTick, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import {
  useCevicoContextMenu,
  computeMenuPosition,
} from 'dashboard/composables/useCevicoContextMenu';

const HINT_KEY = 'cevico_ctxmenu_hint_seen';
const HINT_MS = 9000;
// toque longo: o "clique" de quando o dedo sai não pode escolher um item
const TOUCH_GUARD_MS = 700;

const route = useRoute();
const currentUser = useMapGetter('getCurrentUser');
const { state, closeMenu } = useCevicoContextMenu();

const menuEl = ref(null);
const parent = ref(null); // item "pai" quando está no segundo nível
const active = ref(-1);
const swatch = ref(0); // bolinha em foco na paleta (a última posição = "Padrão")
const pos = ref({ left: 0, top: 0, maxHeight: 0, ready: false });
let lastFocus = null;

const items = computed(() =>
  parent.value ? parent.value.children : state.items
);
const usable = computed(() =>
  items.value
    .map((item, index) => ({ item, index }))
    .filter(({ item }) => !item.separator && !item.disabled)
    .map(({ index }) => index)
);
const menuStyle = computed(() => ({
  left: `${pos.value.left}px`,
  top: `${pos.value.top}px`,
  maxHeight: pos.value.maxHeight ? `${pos.value.maxHeight}px` : '',
  visibility: pos.value.ready ? 'visible' : 'hidden',
  '--cv-rgb': state.rgb,
}));

const place = async () => {
  await nextTick();
  const el = menuEl.value;
  if (!el) return;
  const next = computeMenuPosition({
    x: state.x,
    y: state.y,
    width: el.offsetWidth,
    height: el.scrollHeight,
    viewportWidth: window.innerWidth,
    viewportHeight: window.innerHeight,
  });
  pos.value = { ...next, ready: true };
  el.focus({ preventScroll: true });
};

// ── paleta de cores ──
const sameColor = (a, b) =>
  String(a || '').toUpperCase() === String(b || '').toUpperCase();
const isPicked = (item, color) =>
  Boolean(item.value) && sameColor(item.value, color);
const pick = (item, value) => {
  if (!item || item.disabled) return;
  if (state.byTouch && Date.now() - state.openedAt < TOUCH_GUARD_MS) return;
  closeMenu();
  try {
    const result = item.onPick ? item.onPick(value) : null;
    if (result && typeof result.catch === 'function') result.catch(() => {});
  } catch (e) {
    // eslint-disable-next-line no-console
    console.error('[CEVICO menu]', e);
  }
};
const moveSwatch = (item, step) => {
  const total = item.palette.length + 1; // + "Padrão"
  swatch.value = (swatch.value + step + total) % total;
};
const pickSwatch = item => {
  const color = item.palette[swatch.value];
  pick(item, color ? color.value : null);
};
// pelo teclado, a linha da paleta começa na cor atual (ou na primeira)
const focusRow = index => {
  active.value = index;
  const item = items.value[index];
  if (!item?.palette) return;
  const at = item.palette.findIndex(c => sameColor(c.value, item.value));
  swatch.value = Math.max(at, 0);
};

const move = step => {
  const list = usable.value;
  if (!list.length) return;
  const at = list.indexOf(active.value);
  let next;
  if (at === -1) next = step > 0 ? 0 : list.length - 1;
  else next = (at + step + list.length) % list.length;
  focusRow(list[next]);
};

const goBack = () => {
  if (!parent.value) return;
  const from = state.items.indexOf(parent.value);
  parent.value = null;
  active.value = from;
  place();
};

const choose = item => {
  if (!item || item.separator || item.disabled) return;
  if (item.palette) {
    pickSwatch(item);
    return;
  }
  if (state.byTouch && Date.now() - state.openedAt < TOUCH_GUARD_MS) return;
  if (item.children) {
    parent.value = item;
    active.value = -1;
    place();
    return;
  }
  closeMenu();
  try {
    const result = item.action ? item.action() : null;
    if (result && typeof result.catch === 'function') result.catch(() => {});
  } catch (e) {
    // a ação é da tela; um erro nela não pode travar o menu
    // eslint-disable-next-line no-console
    console.error('[CEVICO menu]', e);
  }
};

const KEYS = {
  ArrowDown: () => move(1),
  ArrowUp: () => move(-1),
  Home: () => focusRow(usable.value[0] ?? -1),
  End: () => focusRow(usable.value[usable.value.length - 1] ?? -1),
  Enter: () => choose(items.value[active.value]),
  ' ': () => choose(items.value[active.value]),
  ArrowRight: () => {
    const item = items.value[active.value];
    if (item?.palette) moveSwatch(item, 1);
    else if (item?.children) choose(item);
  },
  ArrowLeft: () => {
    const item = items.value[active.value];
    if (item?.palette) moveSwatch(item, -1);
    else goBack();
  },
  Escape: () => closeMenu(),
  Tab: () => closeMenu(),
};

const onKeydown = event => {
  const handler = KEYS[event.key];
  if (!handler) return;
  event.preventDefault();
  event.stopPropagation();
  handler();
};
const isInside = event => {
  const el = menuEl.value;
  // a rolagem da janela chega com alvo = window/document (não é um elemento)
  const target = event.target;
  return Boolean(el && target instanceof Node && el.contains(target));
};
const onPointerDown = event => {
  if (!isInside(event)) closeMenu();
};
const onScroll = event => {
  if (!isInside(event)) closeMenu();
};
const onAway = () => closeMenu();

const listen = on => {
  const fn = on ? 'addEventListener' : 'removeEventListener';
  document[fn]('keydown', onKeydown, true);
  document[fn]('pointerdown', onPointerDown, true);
  window[fn]('scroll', onScroll, true);
  window[fn]('resize', onAway);
  window[fn]('blur', onAway);
};

watch(
  () => state.token,
  () => {
    if (!state.open) return;
    parent.value = null;
    active.value = -1;
    pos.value = { left: 0, top: 0, maxHeight: 0, ready: false };
    place();
  }
);
watch(
  () => state.open,
  open => {
    listen(open);
    if (open) {
      lastFocus = document.activeElement;
      return;
    }
    parent.value = null;
    if (lastFocus && lastFocus.focus && document.contains(lastFocus)) {
      lastFocus.focus({ preventScroll: true });
    }
    lastFocus = null;
  }
);
watch(
  () => route.fullPath,
  () => closeMenu()
);

// ── dica da primeira vez (uma por pessoa, guardada no navegador) ──
const showHint = ref(false);
const isTouch = ref(false);
let hintTimer = null;
const hintKey = () => `${HINT_KEY}_${currentUser.value?.id || 'eu'}`;
const hintSeen = () => {
  try {
    return localStorage.getItem(hintKey()) === '1';
  } catch (e) {
    return true; // sem acesso ao navegador: não insiste
  }
};
const markHintSeen = () => {
  try {
    localStorage.setItem(hintKey(), '1');
  } catch (e) {
    /* sem espaço */
  }
};
const dismissHint = () => {
  showHint.value = false;
  if (hintTimer) clearTimeout(hintTimer);
  hintTimer = null;
};
watch(
  () => state.hintRequested,
  wanted => {
    if (!wanted || showHint.value || hintSeen()) return;
    try {
      isTouch.value = window.matchMedia('(pointer: coarse)').matches;
    } catch (e) {
      isTouch.value = false;
    }
    markHintSeen();
    showHint.value = true;
    hintTimer = setTimeout(dismissHint, HINT_MS);
  },
  { immediate: true }
);
// abriu o menu = já aprendeu
watch(
  () => state.open,
  open => {
    if (!open) return;
    markHintSeen();
    dismissHint();
  }
);

onBeforeUnmount(() => {
  listen(false);
  dismissHint();
  closeMenu();
});
</script>

<template>
  <Teleport to="body">
    <div
      v-if="state.open"
      ref="menuEl"
      class="cevico-ctx"
      :class="{ 'cevico-ctx-in': pos.ready }"
      :style="menuStyle"
      role="menu"
      tabindex="-1"
      :aria-label="state.title || 'Atalhos'"
      @contextmenu.prevent.stop
    >
      <div v-if="parent" class="cevico-ctx-head">
        <button type="button" class="cevico-ctx-back" @click="goBack">
          <span class="i-lucide-chevron-left" />
          <span class="cevico-ctx-title">{{ parent.label }}</span>
        </button>
      </div>
      <div v-else-if="state.title || state.subtitle" class="cevico-ctx-head">
        <p v-if="state.title" class="cevico-ctx-title">{{ state.title }}</p>
        <p v-if="state.subtitle" class="cevico-ctx-sub">{{ state.subtitle }}</p>
      </div>

      <template v-for="(item, index) in items" :key="index">
        <div v-if="item.separator" class="cevico-ctx-sep" role="separator" />
        <div
          v-else-if="item.palette"
          class="cevico-ctx-palette"
          :class="{
            'cevico-ctx-palette-active': active === index,
            'cevico-ctx-off': item.disabled,
          }"
          role="group"
          :aria-label="item.label || 'Cor'"
          @mouseenter="active = item.disabled ? active : index"
        >
          <p v-if="item.label" class="cevico-ctx-palette-label">
            {{ item.label }}
          </p>
          <div class="cevico-ctx-swatches">
            <button
              v-for="(color, ci) in item.palette"
              :key="color.value"
              type="button"
              class="cevico-ctx-swatch"
              :class="{
                'cevico-ctx-swatch-on': isPicked(item, color.value),
                'cevico-ctx-swatch-focus': active === index && swatch === ci,
              }"
              :style="{ background: color.value }"
              role="menuitemradio"
              tabindex="-1"
              :aria-checked="isPicked(item, color.value) ? 'true' : 'false'"
              :aria-label="color.label"
              :title="color.label"
              @mouseenter="swatch = ci"
              @click="pick(item, color.value)"
            >
              <span
                v-if="isPicked(item, color.value)"
                class="i-lucide-check cevico-ctx-swatch-check"
              />
            </button>
          </div>
          <button
            type="button"
            class="cevico-ctx-default"
            :class="{
              'cevico-ctx-default-on': !item.value,
              'cevico-ctx-swatch-focus':
                active === index && swatch === item.palette.length,
            }"
            role="menuitemradio"
            tabindex="-1"
            :aria-checked="item.value ? 'false' : 'true'"
            @mouseenter="swatch = item.palette.length"
            @click="pick(item, null)"
          >
            {{ item.defaultLabel || 'Padrão' }}
          </button>
        </div>
        <button
          v-else
          type="button"
          class="cevico-ctx-item"
          :class="{
            'cevico-ctx-active': active === index,
            'cevico-ctx-danger': item.danger,
            'cevico-ctx-off': item.disabled,
          }"
          role="menuitem"
          tabindex="-1"
          :aria-disabled="item.disabled ? 'true' : null"
          :aria-haspopup="item.children ? 'menu' : null"
          :title="item.title || null"
          @mouseenter="active = item.disabled ? active : index"
          @click="choose(item)"
        >
          <span class="cevico-ctx-icon">
            <span v-if="item.icon" :class="item.icon" />
          </span>
          <span class="cevico-ctx-label">{{ item.label }}</span>
          <span v-if="item.hint" class="cevico-ctx-hint">{{ item.hint }}</span>
          <span
            v-if="item.children"
            class="i-lucide-chevron-right cevico-ctx-more"
          />
        </button>
      </template>
    </div>

    <div v-if="showHint" class="cevico-ctx-tip" role="status">
      <span class="i-lucide-mouse-pointer-click cevico-ctx-tip-icon" />
      <span v-if="isTouch">
        Dica: segure o dedo sobre um item para ver os atalhos
      </span>
      <span v-else>Dica: clique com o botão direito para ver os atalhos</span>
      <button type="button" class="cevico-ctx-tip-ok" @click="dismissHint">
        Entendi
      </button>
    </div>
  </Teleport>
</template>

<style scoped>
/* vidro CEVICO: cantos 16px, sombra suave, claro/escuro. --cv-rgb vem da
   página onde o menu nasceu, sempre no formato "r g b" (com espaços).
   ESCURO: aqui é ".dark .classe" puro — no Vue 3.5 o ":global(.dark) .classe"
   vira só ".dark {…}" e pinta a página inteira. */
.cevico-ctx {
  position: fixed;
  z-index: 10050;
  min-width: 228px;
  max-width: min(320px, calc(100vw - 16px));
  padding: 6px;
  overflow-y: auto;
  overscroll-behavior: contain;
  border-radius: 16px;
  color: #0f172a;
  font-size: 13px;
  line-height: 1.25;
  background: linear-gradient(
      160deg,
      rgba(255, 255, 255, 0.94) 0%,
      rgba(255, 255, 255, 0.86) 100%
    ),
    rgb(var(--cv-rgb) / 0.08);
  border: 1px solid rgb(var(--cv-rgb) / 0.24);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.95),
    0 18px 44px -16px rgba(15, 23, 42, 0.4),
    0 2px 8px rgba(15, 23, 42, 0.08);
  backdrop-filter: blur(18px) saturate(1.5);
  -webkit-backdrop-filter: blur(18px) saturate(1.5);
  outline: none;
  user-select: none;
  -webkit-user-select: none;
}
.dark .cevico-ctx {
  color: #f1f5f9;
  background: rgba(23, 25, 28, 0.92);
  border-color: rgba(255, 255, 255, 0.12);
  box-shadow: 0 18px 44px -16px rgba(0, 0, 0, 0.75);
}
.cevico-ctx-in {
  animation: cevicoCtxIn 0.14s ease-out;
}
@keyframes cevicoCtxIn {
  from {
    transform: scale(0.96);
    opacity: 0;
  }
  to {
    transform: none;
    opacity: 1;
  }
}

.cevico-ctx-head {
  padding: 6px 10px 8px;
  margin-bottom: 4px;
  border-bottom: 1px solid rgb(var(--cv-rgb) / 0.16);
}
.cevico-ctx-title {
  font-size: 12.5px;
  font-weight: 700;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.cevico-ctx-sub {
  margin-top: 1px;
  font-size: 11px;
  opacity: 0.62;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.cevico-ctx-back {
  display: flex;
  align-items: center;
  gap: 4px;
  width: 100%;
  margin-left: -4px;
  color: inherit;
  text-align: left;
}

.cevico-ctx-item {
  display: flex;
  align-items: center;
  gap: 9px;
  width: 100%;
  min-height: 34px;
  padding: 6px 10px;
  border-radius: 10px;
  color: inherit;
  text-align: left;
  cursor: pointer;
  transition: background-color 0.1s ease;
}
.cevico-ctx-active {
  background: rgb(var(--cv-rgb) / 0.13);
}
.cevico-ctx-icon {
  display: inline-flex;
  flex: 0 0 16px;
  justify-content: center;
  font-size: 15px;
  color: rgb(var(--cv-rgb));
}
.cevico-ctx-label {
  flex: 1 1 auto;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-weight: 500;
}
.cevico-ctx-hint {
  flex: 0 0 auto;
  font-size: 11px;
  opacity: 0.55;
}
.cevico-ctx-more {
  flex: 0 0 auto;
  font-size: 13px;
  opacity: 0.55;
}
.cevico-ctx-danger,
.cevico-ctx-danger .cevico-ctx-icon {
  color: #dc2626;
}
.cevico-ctx-danger.cevico-ctx-active {
  background: rgba(220, 38, 38, 0.12);
}
.dark .cevico-ctx-danger,
.dark .cevico-ctx-danger .cevico-ctx-icon {
  color: #f87171;
}
.cevico-ctx-off {
  opacity: 0.42;
  cursor: default;
}
.cevico-ctx-sep {
  height: 1px;
  margin: 4px 8px;
  background: rgb(var(--cv-rgb) / 0.16);
}
.dark .cevico-ctx-sep,
.dark .cevico-ctx-head {
  border-color: rgba(255, 255, 255, 0.1);
}
.dark .cevico-ctx-sep {
  background: rgba(255, 255, 255, 0.1);
}

/* paleta de cores (item 290): bolinhas + "Padrão" */
.cevico-ctx-palette {
  padding: 6px 10px 8px;
  border-radius: 10px;
}
.cevico-ctx-palette-label {
  margin-bottom: 6px;
  font-size: 11px;
  font-weight: 600;
  opacity: 0.62;
}
.cevico-ctx-swatches {
  display: grid;
  grid-template-columns: repeat(6, 24px);
  gap: 8px 10px;
  justify-content: space-between;
}
.cevico-ctx-swatch {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  border-radius: 9999px;
  color: #fff;
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.45),
    0 1px 3px rgba(15, 23, 42, 0.25);
  cursor: pointer;
  transition:
    transform 0.1s ease,
    box-shadow 0.1s ease;
}
.cevico-ctx-swatch:hover,
.cevico-ctx-swatch.cevico-ctx-swatch-focus {
  transform: scale(1.18);
}
.cevico-ctx-swatch-on {
  box-shadow:
    0 0 0 2px #fff,
    0 0 0 4px rgba(15, 23, 42, 0.55);
}
.dark .cevico-ctx-swatch-on {
  box-shadow:
    0 0 0 2px #17191c,
    0 0 0 4px rgba(255, 255, 255, 0.8);
}
.cevico-ctx-swatch-check {
  font-size: 13px;
}
.cevico-ctx-default {
  width: 100%;
  min-height: 28px;
  margin-top: 9px;
  border-radius: 9999px;
  color: inherit;
  font-size: 12px;
  font-weight: 600;
  border: 1px solid rgb(var(--cv-rgb) / 0.3);
  cursor: pointer;
  transition: background-color 0.1s ease;
}
.cevico-ctx-default:hover,
.cevico-ctx-default.cevico-ctx-swatch-focus {
  background: rgb(var(--cv-rgb) / 0.13);
}
.cevico-ctx-default-on {
  border-color: rgb(var(--cv-rgb) / 0.7);
  background: rgb(var(--cv-rgb) / 0.08);
}

/* dica da primeira vez */
.cevico-ctx-tip {
  position: fixed;
  left: 50%;
  bottom: 22px;
  z-index: 10040;
  display: flex;
  align-items: center;
  gap: 8px;
  max-width: calc(100vw - 24px);
  padding: 8px 8px 8px 14px;
  border-radius: 9999px;
  color: #0f172a;
  font-size: 12.5px;
  font-weight: 500;
  background: rgba(255, 255, 255, 0.94);
  border: 1px solid rgba(37, 99, 235, 0.24);
  box-shadow: 0 14px 34px -14px rgba(15, 23, 42, 0.4);
  backdrop-filter: blur(14px);
  -webkit-backdrop-filter: blur(14px);
  transform: translateX(-50%);
  animation: cevicoCtxTip 0.3s ease-out;
}
.dark .cevico-ctx-tip {
  color: #f1f5f9;
  background: rgba(23, 25, 28, 0.94);
  border-color: rgba(255, 255, 255, 0.12);
}
.cevico-ctx-tip-icon {
  flex: 0 0 auto;
  font-size: 15px;
  color: #2563eb;
}
.cevico-ctx-tip-ok {
  flex: 0 0 auto;
  padding: 4px 12px;
  border-radius: 9999px;
  color: #fff;
  font-size: 12px;
  font-weight: 600;
  background: linear-gradient(135deg, #1d4ed8, #3b82f6);
}
@keyframes cevicoCtxTip {
  from {
    transform: translate(-50%, 12px);
    opacity: 0;
  }
  to {
    transform: translate(-50%, 0);
    opacity: 1;
  }
}

/* dedo: linhas mais altas */
@media (pointer: coarse) {
  .cevico-ctx-item {
    min-height: 42px;
    font-size: 14px;
  }
  .cevico-ctx-swatches {
    grid-template-columns: repeat(6, 30px);
  }
  .cevico-ctx-swatch {
    width: 30px;
    height: 30px;
  }
  .cevico-ctx-default {
    min-height: 36px;
  }
}
@media (prefers-reduced-motion: reduce) {
  .cevico-ctx-in,
  .cevico-ctx-tip {
    animation: none;
  }
}
</style>
