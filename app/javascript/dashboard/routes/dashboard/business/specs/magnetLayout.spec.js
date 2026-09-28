import {
  compact,
  place,
  firstFreeY,
  mergeLayout,
  boardHeight,
} from '../magnetLayout';

const A = { id: 'a', x: 0, y: 0, w: 6, h: 6 };
const B = { id: 'b', x: 6, y: 0, w: 6, h: 6 };
const C = { id: 'c', x: 0, y: 6, w: 12, h: 4 };
const byId = list => Object.fromEntries(list.map(i => [i.id, i]));

describe('magnetLayout', () => {
  it('sobe tudo até encostar (sem buracos)', () => {
    const out = byId(
      compact([
        { ...A, y: 5 },
        { ...C, y: 30 },
      ])
    );
    expect(out.a.y).toBe(0);
    expect(out.c.y).toBe(6);
  });

  it('acha a primeira linha livre nas mesmas colunas', () => {
    expect(firstFreeY([A], { x: 0, w: 4, h: 3 })).toBe(6);
    expect(firstFreeY([A], { x: 6, w: 4, h: 3 })).toBe(0);
  });

  it('arrastar para cima da metade de um vizinho troca de lugar com ele', () => {
    const out = byId(place([A, B, C], 'c', { x: 0, y: 1 }));
    expect(out.c.y).toBe(0);
    expect(out.a.y).toBe(4);
    expect(out.b.y).toBe(4);
  });

  it('antes da metade não troca', () => {
    const out = byId(place([A, B, C], 'c', { x: 0, y: 4 }));
    expect(out.c.y).toBe(6);
  });

  it('esticar empurra quem está embaixo e respeita os limites', () => {
    const out = byId(place([A, B, C], 'a', { w: 12, h: 8 }));
    expect(out.a).toMatchObject({ x: 0, w: 12, h: 8 });
    expect(out.b.y).toBe(8);
    expect(out.c.y).toBe(14);
    const tiny = byId(place([A], 'a', { w: 0, h: 1, x: 20 }));
    expect(tiny.a).toMatchObject({ w: 2, h: 4, x: 10 });
  });

  it('junta o salvo com os quadros novos e guarda os ocultos', () => {
    const saved = [{ ...A, hidden: true }, B];
    const out = mergeLayout(saved, [A, B, C]);
    expect(out.find(i => i.id === 'a').hidden).toBe(true);
    expect(out.find(i => i.id === 'b').y).toBe(0);
    expect(out.find(i => i.id === 'c').y).toBe(6); // largura toda: encosta embaixo do B
    expect(boardHeight(out.filter(i => !i.hidden))).toBe(10);
  });

  it('o vizinho atropelado escorrega de lado em vez de despencar', () => {
    const radar = { id: 'radar', x: 0, y: 0, w: 8, h: 10 };
    const tl = { id: 'tl', x: 8, y: 0, w: 4, h: 10 };
    const out = byId(place([radar, tl], 'tl', { x: 0, y: 0 }));
    expect(out.tl).toMatchObject({ x: 0, y: 0 });
    expect(out.radar).toMatchObject({ x: 4, y: 0 });
  });
});
