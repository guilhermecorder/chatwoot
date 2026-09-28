// 🧲 O ÍMÃ do Painel do empresário (27/09): grade de 12 colunas onde cada
// quadro é { id, x, y, w, h } (x/w em colunas, y/h em linhas). Toda mudança
// passa por aqui: o quadro vai para onde foi solto, quem estava no caminho
// abre espaço para baixo e tudo "sobe" até encostar (sem buracos) — o quadro
// fica sempre arrumado sozinho. Funções puras (testadas em specs/).

export const COLS = 12;
export const MIN_W = 2;
export const MIN_H = 4;

const overlapX = (a, b) => a.x < b.x + b.w && a.x + a.w > b.x;
const overlapY = (y, h, b) => y < b.y + b.h && y + h > b.y;

export const clampItem = item => {
  const w = Math.max(MIN_W, Math.min(COLS, Math.round(item.w)));
  const h = Math.max(MIN_H, Math.round(item.h));
  const x = Math.max(0, Math.min(COLS - w, Math.round(item.x)));
  const y = Math.max(0, Math.round(item.y));
  return { ...item, x, y, w, h };
};

// a linha mais alta em que o quadro cabe sem encostar em nenhum já colocado
export const firstFreeY = (placed, item) => {
  const sameCols = placed.filter(p => overlapX(p, item));
  const candidates = [0, ...sameCols.map(p => p.y + p.h)].sort((a, b) => a - b);
  return candidates.find(y => !sameCols.some(p => overlapY(y, item.h, p))) ?? 0;
};

const byYX = (a, b) => a.y - b.y || a.x - b.x;

// arruma tudo de cima para baixo (a ordem é a da lista recebida). Quem está
// em `flex` (os vizinhos atropelados pelo quadro que chegou) pode escorregar
// para o LADO antes de descer: fica o mais alto possível e, empatado, o mais
// perto de onde estava — é o vizinho "abrindo espaço" em vez de despencar.
const settle = (ordered, flex = new Set()) => {
  const placed = [];
  ordered.forEach(it => {
    if (!flex.has(it.id)) {
      placed.push({ ...it, y: firstFreeY(placed, it) });
      return;
    }
    let best = null;
    for (let x = 0; x <= COLS - it.w; x += 1) {
      const y = firstFreeY(placed, { ...it, x });
      const dist = Math.abs(x - it.x);
      if (!best || y < best.y || (y === best.y && dist < best.dist)) {
        best = { x, y, dist };
      }
    }
    placed.push({ ...it, x: best.x, y: best.y });
  });
  return placed;
};

const overlaps = (a, b) => overlapX(a, b) && overlapY(a.y, a.h, b);

// arrumação geral (abrir a tela, "Arrumar sozinho", quadro que volta)
export const compact = items => settle(items.map(clampItem).sort(byYX));

// o quadro `id` vai para `target` ({x,y} ao arrastar, {w,h} ao esticar).
// Ele entra na fila ANTES do primeiro quadro das mesmas colunas cujo MEIO
// ainda está abaixo do ponto de soltura — passar da metade de um vizinho já
// troca de lugar com ele (é o que dá a sensação de ímã).
export const place = (items, id, target) => {
  const current = items.find(i => i.id === id);
  if (!current) return compact(items);
  const act = clampItem({ ...current, ...target });
  const others = items
    .filter(i => i.id !== id)
    .map(clampItem)
    .sort(byYX);
  const idx = others.findIndex(o => overlapX(o, act) && act.y < o.y + o.h / 2);
  const ordered =
    idx === -1
      ? [...others, act]
      : [...others.slice(0, idx), act, ...others.slice(idx)];
  const hit = new Set(others.filter(o => overlaps(o, act)).map(o => o.id));
  return settle(ordered, hit);
};

export const boardHeight = items =>
  items.reduce((max, i) => Math.max(max, i.y + i.h), 0);

// junta o layout salvo com os quadros que existem hoje (quadro novo entra no
// fim; quadro que sumiu do sistema sai) e arruma
export const mergeLayout = (saved, defaults) => {
  const savedById = Object.fromEntries((saved || []).map(s => [s.id, s]));
  const bottom = boardHeight((saved || []).filter(s => !s.hidden));
  const merged = defaults.map(d => {
    const s = savedById[d.id];
    return s ? { ...d, ...s } : { ...d, y: d.y + bottom };
  });
  const visible = compact(merged.filter(i => !i.hidden));
  return [...visible, ...merged.filter(i => i.hidden)];
};
