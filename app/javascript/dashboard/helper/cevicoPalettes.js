// 🎨 PALETAS do Meu Painel e das telas do kit .cv-*.
// ♿ item 423 (26/11, pedido dele — o Dr. Henrique é daltônico, vermelho ×
// verde): as 17 paletas (iMac G3 + frutas da Apple) e os modos cor do dia /
// salada de frutas / aleatória viraram SÓ as 6 cores do círculo cromático —
// primárias amarelo, azul e vermelho; secundárias verde, laranja e roxo — e 3
// misturas (primárias, secundárias e todas as 6). Os tons foram escolhidos no
// simulador de daltonismo (normal, deuteranopia, protanopia e tritanopia: o par
// mais parecido ainda se distingue) e todo degradê aceita número BRANCO com
// contraste 4,5 ou mais. Escolha antiga salva cai na cor mais parecida
// (LEGACY_KEYS) — nada some.
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
// escurece até a letra branca ter contraste 4,5 (♿ item 423)
const contrastWhite = hex => 1.05 / (luminance(hex) + 0.05);
const whiteSafe = hex => {
  let h = hex;
  for (let i = 0; i < 20 && contrastWhite(h) < 4.5; i += 1) h = shade(h, 0.06);
  return h;
};
const altFamilyOf = ([tone, light]) =>
  altInkOf(tone) === 'dark'
    ? familyOf([
        shade(tone, 0.12),
        tone,
        mix(tone, light, 0.35),
        mix(tone, light, 0.7),
        light,
      ])
    : familyOf(
        [
          shade(tone, 0.35),
          shade(tone, 0.18),
          tone,
          mix(tone, light, 0.25),
          mix(tone, light, 0.45),
        ].map(whiteSafe)
      );
// key/group/label · dot = a cor pura (bolinha, barras, preenchimento) ·
// accent = o tom para LETRA e ícone sobre fundo claro (contraste 4,5+; no
// amarelo e no laranja é bem mais escuro que a bolinha) · hero = banner ·
// fam = 5 paradas escuras (cards com número branco) · alt = complementar que
// o daltônico também separa (nunca vermelho × verde)
const P = (key, group, label, dot, accent, hero, fam, alt) => ({
  key,
  group,
  label,
  emoji: '',
  dot,
  accent,
  alt: alt[0],
  altLight: alt[1],
  altInk: altInkOf(alt[0]),
  hero: `linear-gradient(135deg, ${hero[0]} 0%, ${hero[1]} 48%, ${hero[2]} 100%)`,
  family: familyOf(fam),
  altFamily: altFamilyOf(alt),
});

export const PALETTES = [
  // ── primárias ──
  P(
    'amarelo',
    'primaria',
    'Amarelo',
    '#F5D000',
    '#8A6A00',
    ['#3F3100', '#8A6A00', '#F5D000'],
    ['#3F3100', '#5C4700', '#6F5600', '#7D6100', '#8A6A00'],
    ['#7E22CE', '#C4B5FD']
  ),
  P(
    'azul',
    'primaria',
    'Azul',
    '#1E4FA0',
    '#1E4FA0',
    ['#0E2A5C', '#1E4FA0', '#6F9BE3'],
    ['#0E2A5C', '#163C7E', '#1A4590', '#1E4FA0', '#2A5DB4'],
    ['#B4530F', '#FDBA74']
  ),
  P(
    'vermelho',
    'primaria',
    'Vermelho',
    '#A3161A',
    '#A3161A',
    ['#4D0A0C', '#A3161A', '#E2575B'],
    ['#4D0A0C', '#6E0F12', '#851216', '#941418', '#A3161A'],
    ['#1E4FA0', '#93B4F0']
  ),
  // ── secundárias ──
  P(
    'verde',
    'secundaria',
    'Verde',
    '#0E9466',
    '#0B7A55',
    ['#053D2A', '#0B7A55', '#3CC48F'],
    ['#053D2A', '#075A3E', '#096A49', '#0A7350', '#0B7A55'],
    ['#7E22CE', '#D8B4FE']
  ),
  P(
    'laranja',
    'secundaria',
    'Laranja',
    '#E0701A',
    '#A84F0A',
    ['#4A2204', '#A84F0A', '#F29A52'],
    ['#4A2204', '#6B3206', '#843D08', '#964509', '#A84F0A'],
    ['#1E4FA0', '#93B4F0']
  ),
  P(
    'roxo',
    'secundaria',
    'Roxo',
    '#9131E6',
    '#7E22CE',
    ['#3A0A66', '#7E22CE', '#B57BF2'],
    ['#3A0A66', '#561395', '#681AAF', '#7320BF', '#7E22CE'],
    ['#F5D000', '#FFF2A6']
  ),
];

// a cor de quem não escolheu nada (antes: a cor do dia do iMac G3)
export const DEFAULT_PALETTE_KEY = 'azul';
// ♿ item 423: escolha antiga salva (crm settings / ui_settings) → a cor nova
// mais parecida
export const LEGACY_KEYS = {
  bondi: 'azul',
  blueberry: 'azul',
  mirtilo: 'azul',
  graphite: 'azul',
  coco: 'laranja',
  strawberry: 'vermelho',
  melancia: 'vermelho',
  cereja: 'vermelho',
  lime: 'verde',
  kiwi: 'verde',
  abacate: 'verde',
  tangerine: 'laranja',
  laranja: 'laranja',
  pessego: 'laranja',
  limao: 'amarelo',
  grape: 'roxo',
  uva: 'roxo',
};
export const PALETTE_BY_KEY = Object.fromEntries(PALETTES.map(p => [p.key, p]));
Object.entries(LEGACY_KEYS).forEach(([old, now]) => {
  if (!PALETTE_BY_KEY[old]) PALETTE_BY_KEY[old] = PALETTE_BY_KEY[now];
});
export const PRIMARY_PALETTES = PALETTES.filter(p => p.group === 'primaria');
export const SECONDARY_PALETTES = PALETTES.filter(
  p => p.group === 'secundaria'
);
export const paletteFor = key => PALETTE_BY_KEY[key] || null;
export const DEFAULT_PALETTE = PALETTE_BY_KEY[DEFAULT_PALETTE_KEY];

// 🎨 as 3 MISTURAS (no lugar da salada de frutas): cada bloco da tela leva
// uma cor (nesta ordem, pela posição padrão do bloco) e os cards da fileira
// alternam. A ordem de "Todas as 6" põe lado a lado só cores que o daltônico
// separa bem (azul · vermelho · amarelo · verde · roxo · laranja).
const mkMix = (key, label, order) => {
  const pals = order.map(k => PALETTE_BY_KEY[k]);
  const dots = pals.map(p => p.dot);
  return {
    key: `mix:${key}`,
    mixKey: key,
    group: 'mistura',
    label,
    emoji: '',
    order,
    dot: pals[0].dot,
    accent: pals[0].accent,
    harmonyKey: pals[0].key,
    swatch: `conic-gradient(from 90deg, ${[...dots, dots[0]].join(', ')})`,
    // banner com os tons ESCUROS (letra branca legível em qualquer ponto)
    hero: `linear-gradient(120deg, ${pals
      .map(
        (p, i) =>
          `${p.accent} ${Math.round((i / Math.max(1, pals.length - 1)) * 100)}%`
      )
      .join(', ')})`,
    family: pals[0].family,
    alt: pals[1].dot,
    altLight: pals[1].altLight,
    altInk: 'light',
    altFamily: pals[1].family,
  };
};
export const MIXES = [
  mkMix('primarias', 'Primárias', ['azul', 'amarelo', 'vermelho']),
  mkMix('secundarias', 'Secundárias', ['verde', 'laranja', 'roxo']),
  mkMix('todas', 'Todas as 6', [
    'azul',
    'vermelho',
    'amarelo',
    'verde',
    'roxo',
    'laranja',
  ]),
];
export const MIX_BY_KEY = Object.fromEntries(MIXES.map(m => [m.mixKey, m]));
// a mistura de uma escolha salva ({ mode: 'mix', key } ou a antiga 'salad')
export const mixFor = entry => {
  if (!entry) return null;
  if (entry.mode === 'salad') return MIX_BY_KEY.todas;
  if (entry.mode === 'mix') return MIX_BY_KEY[entry.key] || MIX_BY_KEY.todas;
  return null;
};
// a cor da posição i numa mistura
export const mixPaletteAt = (mixPal, i) =>
  PALETTE_BY_KEY[mixPal.order[i % mixPal.order.length]];

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
// ── 🧭 GUIA AREJADO (item 336): 3 cores por ambiente em 60-30-10. 60% = a
//    cor da paleta (--cv); 30% = apoio (texto escuro sobre fundo claro); 10% =
//    destaque (botão principal e número que manda — vira LETRA grande sobre
//    fundo claro, por isso sempre escuro no modo claro). ♿ item 423: para cada uma
//    das 6 cores, apoio e destaque escolhidos à mão para o daltônico separar
//    (azul ↔ laranja/amarelo, roxo ↔ amarelo/laranja; nunca vermelho × verde).
// (cada uma com os tons do modo CLARO e, em `escuro`, os do modo escuro)
const HARMONY = {
  azul: {
    apoio: '#8a6a00',
    apoioFundo: '#fff8d6',
    destaque: '#b4530f',
    destaqueInk: '#ffffff',
    escuro: {
      apoio: '#fdba74',
      apoioFundo: '#3a1d10',
      destaque: '#ffd60a',
      destaqueInk: '#111827',
    },
  },
  amarelo: {
    apoio: '#5b21b6',
    apoioFundo: '#f1ebff',
    destaque: '#1e4fa0',
    destaqueInk: '#ffffff',
    escuro: {
      apoio: '#c4b5fd',
      apoioFundo: '#231a45',
      destaque: '#7aa2ff',
      destaqueInk: '#111827',
    },
  },
  vermelho: {
    apoio: '#5b21b6',
    apoioFundo: '#f1ebff',
    destaque: '#1e4fa0',
    destaqueInk: '#ffffff',
    escuro: {
      apoio: '#93b4f0',
      apoioFundo: '#14254a',
      destaque: '#ffd60a',
      destaqueInk: '#111827',
    },
  },
  verde: {
    apoio: '#6b21a8',
    apoioFundo: '#f4ebff',
    destaque: '#1e4fa0',
    destaqueInk: '#ffffff',
    escuro: {
      apoio: '#d8b4fe',
      apoioFundo: '#2a1645',
      destaque: '#ffd60a',
      destaqueInk: '#111827',
    },
  },
  laranja: {
    apoio: '#1e4fa0',
    apoioFundo: '#e8f0fc',
    destaque: '#7e22ce',
    destaqueInk: '#ffffff',
    escuro: {
      apoio: '#93b4f0',
      apoioFundo: '#14254a',
      destaque: '#c4a1ff',
      destaqueInk: '#111827',
    },
  },
  roxo: {
    apoio: '#8a6a00',
    apoioFundo: '#fff8d6',
    destaque: '#b4530f',
    destaqueInk: '#ffffff',
    escuro: {
      apoio: '#fde68a',
      apoioFundo: '#3b2f06',
      destaque: '#ff9a4d',
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
  if (HARMONY[pal.harmonyKey]) return HARMONY[pal.harmonyKey];
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
  // ♿ item 423: --cv vira letra e ícone sobre fundo claro → o tom de contraste
  const accent = pal.accent || pal.dot;
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
