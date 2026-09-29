// 🖱️ MENU DO BOTÃO DIREITO do CEVICO (item 283, 29/09) — uma peça só para o
// sistema inteiro. Qualquer tela liga o menu de dois jeitos:
//
//   1) diretiva:   <div v-cv-menu="() => ({ title, subtitle, items })">
//   2) na mão:     @contextmenu="e => openMenu(e, { title, subtitle, items })"
//
// Cada item = { label, icon, action, danger?, disabled?, hint?, children? }
// e { separator: true } desenha a linha divisória. `children` vira um
// segundo nível ("Mover para a coluna ›").
// PALETA (item 290): { palette: [{ value, label }], value, onPick, label?,
// defaultLabel? } desenha uma fileira de bolinhas de cor + o botão "Padrão";
// onPick recebe a cor escolhida, ou null no "Padrão".
//
// REGRAS (pedido dele + convivência com o Chatwoot):
//   • campo de texto, área editável, link e texto selecionado continuam com
//     o menu do NAVEGADOR (copiar/colar/corretor);
//   • Shift + botão direito sempre abre o menu do navegador;
//   • sem itens = não abre nada nosso (o navegador segue o padrão);
//   • no celular/tablet, segurar o dedo ~0,5 s abre o mesmo menu.
//
// O desenho fica no CevicoContextMenu.vue (montado UMA vez no Dashboard.vue).
import { reactive, readonly } from 'vue';

export const MENU_MARGIN = 8;
export const LONG_PRESS_MS = 500;
export const LONG_PRESS_MOVE_PX = 10;
export const DEFAULT_RGB = '37 99 235'; // azul royal do kit, sempre "r g b"

// onde o menu do navegador continua mandando
export const NATIVE_MENU_SELECTOR = [
  'input',
  'textarea',
  'select',
  '[contenteditable=""]',
  '[contenteditable="true"]',
  '[contenteditable="plaintext-only"]',
  '.ProseMirror',
  'a[href]',
  '[data-cv-native-menu]',
].join(', ');

const state = reactive({
  open: false,
  token: 0, // muda a cada abertura (o componente reposiciona por ele)
  x: 0,
  y: 0,
  title: '',
  subtitle: '',
  items: [],
  rgb: DEFAULT_RGB,
  byTouch: false, // abriu por toque longo (o dedo ainda está na tela)
  openedAt: 0,
  hintRequested: false, // alguma tela com o menu apareceu → mostrar a dica 1x
});

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

// Posição do menu: abre no ponto do mouse; se não couber à direita vira para
// a esquerda, se não couber embaixo vira para cima; nunca sai da tela.
export const computeMenuPosition = ({
  x,
  y,
  width,
  height,
  viewportWidth,
  viewportHeight,
  margin = MENU_MARGIN,
}) => {
  const maxHeight = Math.max(viewportHeight - margin * 2, 0);
  const h = Math.min(height, maxHeight);
  const flipX = x + width > viewportWidth - margin;
  const flipY = y + h > viewportHeight - margin;
  const left = clamp(
    flipX ? x - width : x,
    margin,
    Math.max(viewportWidth - width - margin, margin)
  );
  const top = clamp(
    flipY ? y - h : y,
    margin,
    Math.max(viewportHeight - h - margin, margin)
  );
  return { left, top, flipX, flipY, maxHeight };
};

const elementOf = node => {
  if (!node) return null;
  return node.nodeType === 1 ? node : node.parentElement || null;
};

const hasSelectedText = (target, getSelection) => {
  let selection = null;
  try {
    selection = getSelection ? getSelection() : null;
  } catch (e) {
    return false;
  }
  if (!selection || selection.isCollapsed) return false;
  if (!String(selection).trim()) return false;
  // só vale quando o clique foi em cima (ou em volta) do texto selecionado
  try {
    if (selection.containsNode && selection.containsNode(target, true)) {
      return true;
    }
    const anchor = elementOf(selection.anchorNode);
    const focus = elementOf(selection.focusNode);
    return Boolean(
      (anchor && target.contains(anchor)) || (focus && target.contains(focus))
    );
  } catch (e) {
    return true; // na dúvida, o navegador fica com o menu
  }
};

// true = deixar o menu do NAVEGADOR (não abrir o nosso)
export const shouldUseNativeMenu = (event, options = {}) => {
  if (!event) return true;
  if (event.shiftKey) return true;
  const target = elementOf(event.target);
  if (!target || typeof target.closest !== 'function') return false;
  if (target.closest(NATIVE_MENU_SELECTOR)) return true;
  const getSelection =
    options.getSelection ||
    (typeof window !== 'undefined' && window.getSelection
      ? () => window.getSelection()
      : null);
  return hasSelectedText(target, getSelection);
};

// Limpa a lista: tira vazios/ocultos, separador repetido, no começo ou no fim
export const normalizeItems = items => {
  const out = [];
  (Array.isArray(items) ? items : []).forEach(raw => {
    if (!raw || raw.hidden) return;
    if (raw.separator) {
      if (out.length && !out[out.length - 1].separator) {
        out.push({ separator: true });
      }
      return;
    }
    if (Array.isArray(raw.palette)) {
      const palette = raw.palette
        .map(c => (typeof c === 'string' ? { value: c, label: c } : c))
        .filter(c => c && c.value);
      if (palette.length) out.push({ ...raw, palette });
      return;
    }
    if (!raw.label) return;
    const item = { ...raw };
    if (Array.isArray(raw.children)) {
      item.children = normalizeItems(raw.children);
      if (!item.children.length) return;
    } else {
      delete item.children;
    }
    out.push(item);
  });
  while (out.length && out[out.length - 1].separator) out.pop();
  return out;
};

const RGB_SPACED = /^\d{1,3} \d{1,3} \d{1,3}$/;
// o menu veste a cor da página onde nasceu (lê o --cv-rgb do elemento)
export const accentOf = el => {
  try {
    const raw = window
      .getComputedStyle(el)
      .getPropertyValue('--cv-rgb')
      .trim()
      .replace(/\s+/g, ' ');
    return RGB_SPACED.test(raw) ? raw : DEFAULT_RGB;
  } catch (e) {
    return DEFAULT_RGB;
  }
};

// ponto de abertura: o mouse; pelo teclado (tecla de menu) = o próprio item
const pointOf = event => {
  const x = Number(event.clientX) || 0;
  const y = Number(event.clientY) || 0;
  if (x || y) return { x, y };
  const el = elementOf(event.currentTarget) || elementOf(event.target);
  if (!el || !el.getBoundingClientRect) return { x, y };
  const rect = el.getBoundingClientRect();
  return {
    x: rect.left + Math.min(rect.width / 2, 24),
    y: rect.top + Math.min(rect.height / 2, 24),
  };
};

export const closeMenu = () => {
  if (state.open) state.open = false;
};

// Abre o menu. Devolve true quando abriu; false quando o navegador ficou
// com o clique (campo de texto, Shift, seleção, lista vazia).
export const openMenu = (event, config = {}) => {
  if (!event || shouldUseNativeMenu(event)) return false;
  const items = normalizeItems(config.items);
  if (!items.length) return false;
  if (event.preventDefault) event.preventDefault();
  if (event.stopPropagation) event.stopPropagation();
  const point = pointOf(event);
  state.x = point.x;
  state.y = point.y;
  state.title = config.title || '';
  state.subtitle = config.subtitle || '';
  state.items = items;
  state.rgb =
    config.rgb && RGB_SPACED.test(config.rgb)
      ? config.rgb
      : accentOf(elementOf(event.target) || document.body);
  state.byTouch = Boolean(event.isLongPress);
  state.openedAt = Date.now();
  state.token += 1;
  state.open = true;
  return true;
};

export const requestHint = () => {
  state.hintRequested = true;
};

// ── diretiva v-cv-menu ────────────────────────────────────────────────────
// valor = função (event, el) => { title, subtitle, items } | [itens] | null
//         ou o próprio objeto/lista. null/lista vazia = não abre.
const KEY = '__cevicoMenu';

const resolveConfig = (el, event) => {
  const value = el[KEY]?.value;
  const result = typeof value === 'function' ? value(event, el) : value;
  if (!result) return null;
  return Array.isArray(result) ? { items: result } : result;
};

const openFrom = (el, event) => {
  if (shouldUseNativeMenu(event)) return false;
  const config = resolveConfig(el, event);
  if (!config) return false;
  return openMenu(event, config);
};

const clearPress = ctx => {
  if (ctx.timer) clearTimeout(ctx.timer);
  ctx.timer = null;
};

export const vCvMenu = {
  mounted(el, binding) {
    const ctx = { value: binding.value, timer: null, swallowClick: false };
    el[KEY] = ctx;

    ctx.onContext = event => {
      // Android avisa o toque longo também como "botão direito": o menu já
      // abriu pelo dedo, só segura o menu do navegador
      if (ctx.swallowClick && state.open) {
        event.preventDefault();
        event.stopPropagation();
        return;
      }
      openFrom(el, event);
    };

    // toque longo (celular/tablet): o item de dentro ganha do de fora
    ctx.onTouchStart = event => {
      clearPress(ctx);
      if (event.cvMenuClaimed || event.touches?.length !== 1) return;
      event.cvMenuClaimed = true;
      const touch = event.touches[0];
      const start = { x: touch.clientX, y: touch.clientY };
      ctx.start = start;
      const target = event.target;
      ctx.timer = setTimeout(() => {
        ctx.timer = null;
        const opened = openFrom(el, {
          clientX: start.x,
          clientY: start.y,
          target,
          currentTarget: el,
          shiftKey: false,
          isLongPress: true,
        });
        if (opened) {
          // o "clique" que vem quando o dedo sai não pode abrir o item
          ctx.swallowClick = true;
          setTimeout(() => {
            ctx.swallowClick = false;
          }, 1500);
        }
      }, LONG_PRESS_MS);
    };
    ctx.onTouchMove = event => {
      if (!ctx.timer || !ctx.start) return;
      const touch = event.touches?.[0];
      if (!touch) return;
      const moved = Math.hypot(
        touch.clientX - ctx.start.x,
        touch.clientY - ctx.start.y
      );
      if (moved > LONG_PRESS_MOVE_PX) clearPress(ctx);
    };
    ctx.onTouchEnd = () => clearPress(ctx);
    ctx.onClickCapture = event => {
      if (!ctx.swallowClick) return;
      ctx.swallowClick = false;
      event.preventDefault();
      event.stopPropagation();
    };

    el.addEventListener('contextmenu', ctx.onContext);
    el.addEventListener('touchstart', ctx.onTouchStart, { passive: true });
    el.addEventListener('touchmove', ctx.onTouchMove, { passive: true });
    el.addEventListener('touchend', ctx.onTouchEnd);
    el.addEventListener('touchcancel', ctx.onTouchEnd);
    el.addEventListener('click', ctx.onClickCapture, true);
    // iPhone/iPad: sem o balão de "copiar/compartilhar" por cima do nosso menu
    el.style.webkitTouchCallout = 'none';
    requestHint();
  },
  updated(el, binding) {
    if (el[KEY]) el[KEY].value = binding.value;
  },
  beforeUnmount(el) {
    const ctx = el[KEY];
    if (!ctx) return;
    clearPress(ctx);
    el.removeEventListener('contextmenu', ctx.onContext);
    el.removeEventListener('touchstart', ctx.onTouchStart);
    el.removeEventListener('touchmove', ctx.onTouchMove);
    el.removeEventListener('touchend', ctx.onTouchEnd);
    el.removeEventListener('touchcancel', ctx.onTouchEnd);
    el.removeEventListener('click', ctx.onClickCapture, true);
    delete el[KEY];
  },
};

export const useCevicoContextMenu = () => ({
  state: readonly(state),
  openMenu,
  closeMenu,
  requestHint,
  vCvMenu,
});

export default useCevicoContextMenu;
