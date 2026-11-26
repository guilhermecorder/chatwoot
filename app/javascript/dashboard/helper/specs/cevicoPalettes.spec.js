// ♿ item 423 (26/11): cores para daltônicos — as 6 cores do círculo + 3
// misturas, contraste alto, e nenhum par que o daltônico confunda.
import {
  PALETTES,
  MIXES,
  paletteFor,
  mixFor,
  mixPaletteAt,
  paletteVars,
  paletteHarmony,
  DEFAULT_PALETTE,
} from 'dashboard/helper/cevicoPalettes';
import { TYPES, DOCTORS } from 'dashboard/helper/cevicoAgenda';

// simulação de daltonismo (Machado, Oliveira e Fernandes, 2009) + distância
// de cor no espaço Lab — a mesma conta da prévia aprovada
const MATS = {
  protan: [
    [0.152286, 1.052583, -0.204868],
    [0.114503, 0.786281, 0.099216],
    [-0.003882, -0.048116, 1.051998],
  ],
  deutan: [
    [0.367322, 0.860646, -0.227968],
    [0.280085, 0.672501, 0.047413],
    [-0.01182, 0.04294, 0.968881],
  ],
  tritan: [
    [1.255528, -0.076749, -0.178779],
    [-0.078411, 0.930809, 0.147602],
    [0.004733, 0.691367, 0.3039],
  ],
};
const lin = c => {
  const v = c / 255;
  return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
};
const unlin = c => {
  const v = Math.max(0, Math.min(1, c));
  return 255 * (v <= 0.0031308 ? 12.92 * v : 1.055 * v ** (1 / 2.4) - 0.055);
};
const rgb = hex =>
  [0, 2, 4].map(i => parseInt(hex.replace('#', '').slice(i, i + 2), 16));
const simulate = (hex, type) => {
  const r = rgb(hex).map(lin);
  return MATS[type].map(row =>
    unlin(row[0] * r[0] + row[1] * r[1] + row[2] * r[2])
  );
};
const lab = c => {
  const [r, g, b] = c.map(lin);
  const f = t => (t > 0.008856 ? Math.cbrt(t) : 7.787 * t + 16 / 116);
  const X = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
  const Y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  const Z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
  return [116 * f(Y) - 16, 500 * (f(X) - f(Y)), 200 * (f(Y) - f(Z))];
};
const distance = (a, b) => {
  const [x, y] = [lab(a), lab(b)];
  return Math.hypot(x[0] - y[0], x[1] - y[1], x[2] - y[2]);
};
const closestPair = (hexes, type) => {
  let min = Infinity;
  hexes.forEach((a, i) =>
    hexes.slice(i + 1).forEach(b => {
      min = Math.min(min, distance(simulate(a, type), simulate(b, type)));
    })
  );
  return min;
};
const luminance = hex => {
  const [r, g, b] = rgb(hex).map(lin);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const contrastWithWhite = hex => 1.05 / (luminance(hex) + 0.05);
const hexesOf = grad => String(grad).match(/#[0-9a-f]{6}/gi) || [];

describe('paletas para daltônicos (item 423)', () => {
  it('são 6 cores: 3 primárias e 3 secundárias, e 3 misturas', () => {
    expect(PALETTES.map(p => p.key)).toEqual([
      'amarelo',
      'azul',
      'vermelho',
      'verde',
      'laranja',
      'roxo',
    ]);
    expect(MIXES.map(m => m.key)).toEqual([
      'mix:primarias',
      'mix:secundarias',
      'mix:todas',
    ]);
    expect(MIXES[2].order).toHaveLength(6);
    expect(DEFAULT_PALETTE.key).toBe('azul');
  });

  it('número branco legível em todo degradê (contraste 4,5 ou mais)', () => {
    PALETTES.forEach(p => {
      expect(contrastWithWhite(p.accent)).toBeGreaterThanOrEqual(4.5);
      p.family.flatMap(hexesOf).forEach(hex => {
        expect(contrastWithWhite(hex)).toBeGreaterThanOrEqual(4.5);
      });
    });
  });

  it('apoio e destaque (letra sobre fundo claro) também com contraste alto', () => {
    PALETTES.forEach(p => {
      const h = paletteHarmony(p);
      expect(contrastWithWhite(h.apoio)).toBeGreaterThanOrEqual(4.5);
      expect(contrastWithWhite(h.destaque)).toBeGreaterThanOrEqual(4.5);
    });
  });

  it('nenhum par das 6 cores se confunde em nenhum tipo de daltonismo', () => {
    const dots = PALETTES.map(p => p.dot);
    ['protan', 'deutan', 'tritan'].forEach(type => {
      expect(closestPair(dots, type)).toBeGreaterThan(20);
    });
  });

  it('escolha antiga salva cai na cor nova mais parecida', () => {
    expect(paletteFor('bondi').key).toBe('azul');
    expect(paletteFor('blueberry').key).toBe('azul');
    expect(paletteFor('strawberry').key).toBe('vermelho');
    expect(paletteFor('lime').key).toBe('verde');
    expect(paletteFor('tangerine').key).toBe('laranja');
    expect(paletteFor('grape').key).toBe('roxo');
    expect(paletteFor('limao').key).toBe('amarelo');
    expect(paletteFor('nada-disso')).toBeNull();
    expect(mixFor({ mode: 'salad' }).key).toBe('mix:todas');
    expect(mixFor({ mode: 'mix', key: 'primarias' }).key).toBe('mix:primarias');
    expect(mixFor({ mode: 'fixed', key: 'azul' })).toBeNull();
  });

  it('a mistura dá uma cor por posição, em roda', () => {
    const prim = MIXES[0];
    expect([0, 1, 2, 3].map(i => mixPaletteAt(prim, i).key)).toEqual([
      'azul',
      'amarelo',
      'vermelho',
      'azul',
    ]);
    expect(paletteVars(prim)['--cv']).toBe(paletteFor('azul').accent);
  });
});

describe('cores da Agenda para daltônicos (item 423)', () => {
  it('os 6 tipos não se confundem (antes avaliação × teleconsulta ficavam iguais)', () => {
    const colors = TYPES.map(t => t.color);
    ['protan', 'deutan', 'tritan'].forEach(type => {
      expect(closestPair(colors, type)).toBeGreaterThan(20);
    });
  });

  it('botão e letra do tipo aceitam letra branca', () => {
    TYPES.forEach(t => {
      expect(contrastWithWhite(t.strong || t.color)).toBeGreaterThanOrEqual(
        4.5
      );
      expect(contrastWithWhite(t.deep)).toBeGreaterThanOrEqual(4.5);
    });
  });

  it('os médicos se distinguem e aceitam letra branca', () => {
    const colors = DOCTORS.map(d => d.color);
    ['protan', 'deutan'].forEach(type => {
      expect(closestPair(colors, type)).toBeGreaterThan(20);
    });
    colors.forEach(c =>
      expect(contrastWithWhite(c)).toBeGreaterThanOrEqual(4.5)
    );
  });
});
