// 🍎🍊 PALETAS do Meu Painel (rodada 162): as 7 cores dos iMac G3 (uma por
// dia da semana, item 160) + as 10 frutas da Apple + a "salada de frutas".
// O admin escolhe, por painel, o painel inteiro e cada bloco (InicioPage).
//
// Cada paleta:
//   key/label/emoji/group  · dot = tom principal (hex) · swatch = o que a
//   bolinha mostra (só a salada tem um diferente do dot)
//   hero   = degradê translúcido do banner (3 paradas, escuro → tom → claro)
//   family = 4 degradês OPACOS escuro→médio (cards, ícones, botões) —
//            número branco sempre legível (pedido "mais opaco", item 160)
//   alt    = cor COMPLEMENTAR da paleta (pedido 19/09: "roxo e laranja/ouro,
//            azul e amarelo, verde e rosa…") — os cards de uma fileira
//            alternam família × altFamily para dar contraste agradável
const shade = (hex, f) => {
  const m = String(hex).replace('#', '');
  const c = [0, 2, 4].map(i =>
    Math.round(parseInt(m.slice(i, i + 2), 16) * (1 - f))
  );
  return `#${c.map(v => v.toString(16).padStart(2, '0')).join('')}`;
};
const familyOf = fam => [
  `linear-gradient(135deg, ${fam[0]}, ${fam[1]})`,
  `linear-gradient(135deg, ${fam[1]}, ${fam[2]})`,
  `linear-gradient(135deg, ${fam[2]}, ${fam[3]})`,
  `linear-gradient(135deg, ${fam[3]}, ${fam[4]})`,
];
// mistura linear de dois hex (t = 0 → a, 1 → b)
const mix = (a, b, t) => {
  const A = String(a).replace('#', '');
  const B = String(b).replace('#', '');
  const c = [0, 2, 4].map(i =>
    Math.round(
      parseInt(A.slice(i, i + 2), 16) * (1 - t) +
        parseInt(B.slice(i, i + 2), 16) * t
    )
  );
  return `#${c.map(v => v.toString(16).padStart(2, '0')).join('')}`;
};
// luminância relativa (0 = preto, 1 = branco) — decide a tinta do texto
const luminance = hex => {
  const m = String(hex).replace('#', '');
  const [r, g, b] = [0, 2, 4].map(k => {
    const c = parseInt(m.slice(k, k + 2), 16) / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
// cor CLARA (amarelo, ouro) → texto escuro; cor forte (azul, rosa, verde,
// roxo) → texto branco
const altInkOf = tone => (luminance(tone) > 0.45 ? 'dark' : 'light');
// família da complementar: VIVA como na natureza (miolo de flor: âmbar →
// amarelo puro), sem escurecer para o marrom. Com texto branco a família
// não sobe até o tom claro (branco sobre azul-claro não lê); com texto
// escuro ela vai do tom ao claro.
const altFamilyOf = ([tone, light]) =>
  altInkOf(tone) === 'dark'
    ? familyOf([
        shade(tone, 0.12),
        tone,
        mix(tone, light, 0.35),
        mix(tone, light, 0.7),
        light,
      ])
    : familyOf([
        shade(tone, 0.35),
        shade(tone, 0.18),
        tone,
        mix(tone, light, 0.25),
        mix(tone, light, 0.45),
      ]);
const P = (key, group, label, emoji, dot, hero, fam, alt) => ({
  key,
  group,
  label,
  emoji,
  dot,
  alt: alt[0],
  altLight: alt[1],
  altInk: altInkOf(alt[0]),
  hero: `linear-gradient(135deg, ${hero[0]} 0%, ${hero[1]} 48%, ${hero[2]} 100%)`,
  family: familyOf(fam),
  altFamily: altFamilyOf(alt),
});

export const PALETTES = [
  // ── iMac G3 (1998–99): segunda abre com o original, depois a ordem da
  //    foto dele; domingo = Graphite, a edição especial ──
  P(
    'bondi',
    'imac',
    'Bondi Blue',
    '',
    '#1099BC',
    ['#0B4F63', '#1099BC', '#4FD3EA'],
    ['#0B4F63', '#0F7A93', '#0E8FAC', '#1099BC', '#17AACB'],
    ['#FF9F1C', '#FFE600']
  ),
  P(
    'blueberry',
    'imac',
    'Blueberry',
    '',
    '#3060E0',
    ['#1B2F8A', '#3060E0', '#7CB0FF'],
    ['#1B2F8A', '#2447C4', '#2C55D6', '#3060E0', '#3F72EA'],
    ['#FFB000', '#FFF200']
  ),
  P(
    'strawberry',
    'imac',
    'Strawberry',
    '',
    '#D42040',
    ['#7A0B23', '#D42040', '#FF7A93'],
    ['#7A0B23', '#B01432', '#C21A3A', '#D42040', '#E22F50'],
    ['#00C2A8', '#7CF5DC']
  ),
  P(
    'lime',
    'imac',
    'Lime',
    '',
    '#4CAF2A',
    ['#1F5A15', '#3E9E1F', '#9FE84D'],
    ['#1F5A15', '#2F7D1E', '#388F1F', '#3E9E1F', '#4CAF2A'],
    ['#F0148C', '#FF7AC8']
  ),
  P(
    'tangerine',
    'imac',
    'Tangerine',
    '',
    '#F26A1B',
    ['#7F3208', '#E0600F', '#FFB35C'],
    ['#7F3208', '#B84A0E', '#CC540F', '#E0600F', '#EE6E14'],
    ['#2F5BFF', '#7DB8FF']
  ),
  P(
    'grape',
    'imac',
    'Grape',
    '',
    '#6B3AC9',
    ['#2A1055', '#5E2FB5', '#B48CFF'],
    ['#2A1055', '#4A2390', '#54299F', '#5E2FB5', '#6B3AC9'],
    ['#FFBA00', '#FFF200']
  ),
  P(
    'graphite',
    'imac',
    'Graphite',
    '',
    '#6B7280',
    ['#111827', '#4B5563', '#B0B7C3'],
    ['#111827', '#374151', '#4B5563', '#5B6472', '#6B7280'],
    ['#FFC300', '#FFF176']
  ),
  // ── frutas da Apple (ideia dele, 13/09): cada fruta é um tema e uma cor ──
  P(
    'laranja',
    'fruta',
    'Laranja',
    '🍊',
    '#F97316',
    ['#7C2D12', '#F97316', '#FDBA74'],
    ['#7C2D12', '#B44A10', '#D45A11', '#EA6A14', '#F97316'],
    ['#3D5AFE', '#8AB4FF']
  ),
  P(
    'limao',
    'fruta',
    'Limão',
    '🍋',
    '#D4A70A',
    ['#5C3D07', '#D4A70A', '#FDE68A'],
    ['#5C3D07', '#8A5E0A', '#A6750B', '#BF8A0A', '#D4A70A'],
    ['#8B3DF0', '#C4B5FD']
  ),
  P(
    'melancia',
    'fruta',
    'Melancia',
    '🍉',
    '#E5395B',
    ['#7A1230', '#E5395B', '#FDA4AF'],
    ['#7A1230', '#A31A44', '#BE2450', '#D22E56', '#E5395B'],
    ['#00B894', '#6EF3C9']
  ),
  P(
    'uva',
    'fruta',
    'Uva',
    '🍇',
    '#7C3AED',
    ['#3B0764', '#7C3AED', '#C4B5FD'],
    ['#3B0764', '#581C87', '#6B21A8', '#7E22CE', '#8B3DF0'],
    ['#FFB300', '#FFEE33']
  ),
  P(
    'kiwi',
    'fruta',
    'Kiwi',
    '🥝',
    '#7CB518',
    ['#365314', '#7CB518', '#D9F99D'],
    ['#365314', '#4D7C0F', '#5C8F0F', '#6BA312', '#7CB518'],
    ['#F5127A', '#FF8AC4']
  ),
  P(
    'coco',
    'fruta',
    'Coco',
    '🥥',
    '#8B5E3C',
    ['#3F2A1D', '#8B5E3C', '#F3E6D3'],
    ['#3F2A1D', '#5C3D2E', '#704A36', '#7D5439', '#8B5E3C'],
    ['#00A3C4', '#67E8F9']
  ),
  P(
    'pessego',
    'fruta',
    'Pêssego',
    '🍑',
    '#F4845F',
    ['#8A3A1B', '#F4845F', '#FED7AA'],
    ['#8A3A1B', '#B24B25', '#CC5A30', '#E26F45', '#F4845F'],
    ['#2F6BFF', '#8EC5FF']
  ),
  P(
    'cereja',
    'fruta',
    'Cereja',
    '🍒',
    '#C41E3A',
    ['#4A0A14', '#C41E3A', '#FCA5A5'],
    ['#4A0A14', '#7A1223', '#96182D', '#AD1B33', '#C41E3A'],
    ['#00C48C', '#7BF1C6']
  ),
  P(
    'abacate',
    'fruta',
    'Abacate',
    '🥑',
    '#3E8E41',
    ['#1B3D1E', '#3E8E41', '#C6E9B0'],
    ['#1B3D1E', '#2A5A2D', '#326B35', '#387B3B', '#3E8E41'],
    ['#F0148C', '#FF9AD5']
  ),
  P(
    'mirtilo',
    'fruta',
    'Mirtilo',
    '🫐',
    '#4F46E5',
    ['#1E1B4B', '#4F46E5', '#A5B4FC'],
    ['#1E1B4B', '#312E81', '#3730A3', '#4338CA', '#4F46E5'],
    ['#FFC400', '#FFF59D']
  ),
];

export const PALETTE_BY_KEY = Object.fromEntries(PALETTES.map(p => [p.key, p]));
export const IMAC_PALETTES = PALETTES.filter(p => p.group === 'imac');
export const FRUIT_PALETTES = PALETTES.filter(p => p.group === 'fruta');
export const paletteFor = key => PALETTE_BY_KEY[key] || null;

// dia da semana (getDay) → cor do dia
export const DAY_KEYS = {
  0: 'graphite',
  1: 'bondi',
  2: 'blueberry',
  3: 'strawberry',
  4: 'lime',
  5: 'tangerine',
  6: 'grape',
};

// 🥗 SALADA DE FRUTAS: cada bloco da tela leva uma fruta (nesta ordem, pela
// posição padrão do bloco — reordenar não troca a fruta) e os cards da
// fileira alternam as frutas. O banner mistura as quatro primeiras.
export const SALAD_ORDER = [
  'laranja',
  'uva',
  'kiwi',
  'cereja',
  'mirtilo',
  'pessego',
  'limao',
  'melancia',
  'abacate',
  'coco',
];
export const SALAD = {
  key: 'salada',
  group: 'salada',
  label: 'Salada de frutas',
  emoji: '🥗',
  dot: '#F97316',
  swatch:
    'conic-gradient(from 90deg, #F97316, #E5395B, #7C3AED, #7CB518, #F4845F, #F97316)',
  // item 284 (29/09): base AZUL → VERDE com brilho AMARELO ("o azul deixa mais
  // suave e agradável"); rosa e roxo só como toque de contraste nos cantos
  hero: [
    'radial-gradient(circle at 96% 0%, rgba(250, 204, 21, 0.9) 0%, rgba(250, 204, 21, 0) 34%)',
    'radial-gradient(circle at 72% 125%, rgba(236, 72, 153, 0.55) 0%, rgba(236, 72, 153, 0) 36%)',
    'radial-gradient(circle at 0% 115%, rgba(124, 58, 237, 0.55) 0%, rgba(124, 58, 237, 0) 40%)',
    'linear-gradient(120deg, #1E3A8A 0%, #2563EB 36%, #0EA5A4 66%, #22C55E 100%)',
  ].join(', '),
  family: PALETTE_BY_KEY.laranja.family,
  alt: PALETTE_BY_KEY.uva.dot,
  altLight: '#C4B5FD',
  altInk: 'light',
  altFamily: PALETTE_BY_KEY.uva.family,
};

// ── utilidades de cor do kit .cv-* (InicioPage) ──
export const hexFromGrad = grad =>
  (String(grad || '').match(/#[0-9a-f]{6}/gi) || [])[0] || null;
// "r g b" SEPARADO POR ESPAÇO: o kit usa `rgb(var(--cv-rgb) / 0.2)` (sintaxe
// moderna), e o navegador REJEITA a mistura "r, g, b / a" — com vírgulas,
// toda borda/fundo/sombra do kit que usa a variável era ignorada em silêncio.
export const hexToRgb = hex => {
  const m = String(hex || '').replace('#', '');
  if (m.length !== 6) return '21 44 97';
  return [0, 2, 4].map(i => parseInt(m.slice(i, i + 2), 16)).join(' ');
};
// ── 🧭 GUIA AREJADO (item 336): 3 cores por ambiente em 60-30-10 pela
//    COMPLEMENTAR DIVIDIDA. 60% = a cor da paleta (--cv); 30% = apoio
//    (uma vizinha da complementar, usada CLARA no fundo e escura no texto);
//    10% = destaque (a outra vizinha, cheia: botão principal e número que
//    manda). As 7 cores do dia têm os tons escolhidos à mão no guia
//    (claude.ai/artifact/M7af1huY3VB8XEbt5gr7Jt); as frutas são calculadas.
// (cada uma com os tons do modo CLARO e, em `escuro`, os do modo escuro)
const HARMONY = {
  bondi: {
    apoio: '#c2410c',
    apoioFundo: '#ffefe6',
    destaque: '#c9a200',
    destaqueInk: '#111827',
    escuro: {
      apoio: '#fb923c',
      apoioFundo: '#3a1d10',
      destaque: '#ffd60a',
      destaqueInk: '#111827',
    },
  },
  blueberry: {
    apoio: '#8a5e0a',
    apoioFundo: '#fff4d6',
    destaque: '#f26a1b',
    destaqueInk: '#111827',
    escuro: {
      apoio: '#fbbf24',
      apoioFundo: '#3b2a08',
      destaque: '#ff8a4c',
      destaqueInk: '#111827',
    },
  },
  strawberry: {
    apoio: '#0b6b80',
    apoioFundo: '#e3f6fa',
    destaque: '#16a34a',
    destaqueInk: '#ffffff',
    escuro: {
      apoio: '#5ad4ec',
      apoioFundo: '#0e2f38',
      destaque: '#4ade80',
      destaqueInk: '#111827',
    },
  },
  lime: {
    apoio: '#4338ca',
    apoioFundo: '#ecebff',
    destaque: '#e0218a',
    destaqueInk: '#ffffff',
    escuro: {
      apoio: '#a5b4fc',
      apoioFundo: '#1f1b4a',
      destaque: '#ff6fbd',
      destaqueInk: '#111827',
    },
  },
  tangerine: {
    apoio: '#0f766e',
    apoioFundo: '#dff7f3',
    destaque: '#2f5bff',
    destaqueInk: '#ffffff',
    escuro: {
      apoio: '#5eead4',
      apoioFundo: '#0d3330',
      destaque: '#7a9bff',
      destaqueInk: '#111827',
    },
  },
  grape: {
    apoio: '#3f6212',
    apoioFundo: '#eef9d6',
    destaque: '#e0a800',
    destaqueInk: '#111827',
    escuro: {
      apoio: '#bef264',
      apoioFundo: '#233308',
      destaque: '#ffcc33',
      destaqueInk: '#111827',
    },
  },
  // domingo: a única tela em que o navy e o ouro da marca entram
  graphite: {
    apoio: '#152c61',
    apoioFundo: '#e8edf8',
    destaque: '#d4af37',
    destaqueInk: '#111827',
    escuro: {
      apoio: '#9db4ff',
      apoioFundo: '#15213f',
      destaque: '#e6c65a',
      destaqueInk: '#111827',
    },
  },
};
const hexToHsl = hex => {
  const m = String(hex).replace('#', '');
  const [r, g, b] = [0, 2, 4].map(i => parseInt(m.slice(i, i + 2), 16) / 255);
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  if (max === min) return [0, 0, l];
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  let h;
  if (max === r) h = (g - b) / d + (g < b ? 6 : 0);
  else if (max === g) h = (b - r) / d + 2;
  else h = (r - g) / d + 4;
  return [h * 60, s, l];
};
const hslToHex = (h, s, l) => {
  const k = n => (n + h / 30) % 12;
  const a = s * Math.min(l, 1 - l);
  const f = n =>
    l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
  return `#${[f(0), f(8), f(4)]
    .map(v =>
      Math.round(v * 255)
        .toString(16)
        .padStart(2, '0')
    )
    .join('')}`;
};
// complementar dividida calculada: apoio a +150°, destaque a +210°
const harmonyOf = pal => {
  if (HARMONY[pal.key]) return HARMONY[pal.key];
  const [h, s] = hexToHsl(pal.dot);
  const sat = Math.max(0.55, Math.min(s, 0.9));
  const destaque = hslToHex((h + 210) % 360, sat, 0.5);
  const destaqueEscuro = hslToHex((h + 210) % 360, sat, 0.62);
  return {
    apoio: hslToHex((h + 150) % 360, sat, 0.3),
    apoioFundo: hslToHex((h + 150) % 360, 0.7, 0.93),
    destaque,
    destaqueInk: luminance(destaque) > 0.45 ? '#111827' : '#ffffff',
    escuro: {
      apoio: hslToHex((h + 150) % 360, sat, 0.75),
      apoioFundo: hslToHex((h + 150) % 360, 0.5, 0.16),
      destaque: destaqueEscuro,
      destaqueInk: luminance(destaqueEscuro) > 0.45 ? '#111827' : '#ffffff',
    },
  };
};
export const paletteHarmony = harmonyOf;

// as variáveis --cv* que o kit lê (na página inteira ou num bloco só)
export const paletteVars = pal => {
  const accent = pal.dot;
  const deep = hexFromGrad(pal.family[0]) || accent;
  const harmony = harmonyOf(pal);
  return {
    // 🧭 guia arejado: os 30% e os 10% do ambiente
    '--cv-apoio': harmony.apoio,
    '--cv-apoio-rgb': hexToRgb(harmony.apoio),
    '--cv-apoio-fundo': harmony.apoioFundo,
    '--cv-destaque': harmony.destaque,
    '--cv-destaque-rgb': hexToRgb(harmony.destaque),
    '--cv-destaque-ink': harmony.destaqueInk,
    // tons do modo escuro (o .scss troca para eles em `.dark .cv-page`)
    '--cv-apoio-escuro': harmony.escuro.apoio,
    '--cv-apoio-fundo-escuro': harmony.escuro.apoioFundo,
    '--cv-destaque-escuro': harmony.escuro.destaque,
    '--cv-destaque-ink-escuro': harmony.escuro.destaqueInk,
    '--cv': accent,
    '--cv-rgb': hexToRgb(accent),
    '--cv-deep': deep,
    '--cv-deep-rgb': hexToRgb(deep),
    '--cv-grad': pal.family[1],
    '--cv-grad-2': pal.family[2],
    '--cv-grad-3': pal.family[3],
    '--cv-hero': pal.hero,
    // complementar (kit: `.cv-alt` troca --cv pela complementar do bloco)
    '--cv-alt': pal.alt || accent,
    '--cv-alt-rgb': hexToRgb(pal.alt || accent),
    '--cv-alt-grad': (pal.altFamily || pal.family)[1],
    '--cv-alt-ink': pal.altInk === 'dark' ? deep : '#ffffff',
  };
};
