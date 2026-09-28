// 🎨 PALETA DOS INDICADORES (item 269, 28/09 — pedido: "não fica legal eu
// escolhendo entre infinitas cores… cores relacionadas para indicadores
// relacionados, contraste entre primários, secundários e terciários").
//
// FAMÍLIA = o que o indicador mede (mesma cor para indicadores irmãos):
//   captação (azul) · agendamento (verde) · presença (âmbar) · cirurgia (roxo)
//   · financeiro (ouro) · satisfação (rosa) · outros (grafite)
// NÍVEL = a importância: primário = resultado que decide (taxas, fechamento,
// faturamento, consultas marcadas) em cor cheia; secundário = volume que
// explica (novos contatos, entrou em…, indicações) em cor média; terciário =
// apoio (confirmadas, lançadas, faltas, "pela data") em cor clara.
// O card nasce TRANSPARENTE e a cor vai ficando DENSA ao longo do dia
// (07h vidro → 19h cor cheia) — ver dayFill().

export const KPI_FAMILIES = {
  financeiro: {
    label: 'Financeiro',
    c1: '#a16207',
    c2: '#d4af37',
    deep: '#713f12',
  },
  cirurgia: {
    label: 'Cirurgia',
    c1: '#6d28d9',
    c2: '#a78bfa',
    deep: '#4c1d95',
  },
  satisfacao: {
    label: 'Satisfação',
    c1: '#be123c',
    c2: '#fb7185',
    deep: '#881337',
  },
  presenca: {
    label: 'Presença',
    c1: '#c2410c',
    c2: '#fb923c',
    deep: '#7c2d12',
  },
  agendamento: {
    label: 'Agendamento',
    c1: '#047857',
    c2: '#34d399',
    deep: '#064e3b',
  },
  captacao: {
    label: 'Captação',
    c1: '#1d4ed8',
    c2: '#60a5fa',
    deep: '#1e3a8a',
  },
  outros: { label: 'Outros', c1: '#334155', c2: '#64748b', deep: '#0f172a' },
};

// ordem importa: a 1ª regra que casar vence
const FAMILY_RULES = [
  ['financeiro', /faturamento|ticket|receita|r\$|custo|cac|investimento/i],
  ['cirurgia', /cirurg|indica[cç]|fechamento|p[oó]s[- ]?op|lead ?→ ?cirurgia/i],
  ['satisfacao', /nps|satisfa|promotor|detrator/i],
  [
    'presenca',
    /comparec|presen|falta|confirmad|n[aã]o confirm|lan[cç]ad|pela data|consultas do per[ií]odo|consultas no per[ií]odo/i,
  ],
  ['agendamento', /agendamento|agendad|marcad|or[cç]amento|consulta/i],
  ['captacao', /novos contatos|lead|conversa|instagram|google|caixa|contato/i],
];

const TIER_RULES = [
  [
    'primary',
    /taxa|%|fechamento|faturamento|comparecimento|consultas marcadas|cirurgias realizadas|conversão|conversao|lead ?→/i,
  ],
  [
    'tertiary',
    /confirmad|n[aã]o confirm|lan[cç]ad|falta|cancelad|pela data|sem cadastro|espaço|hoje$/i,
  ],
];

const textOf = tile =>
  [tile?.label, tile?.gk, tile?.id, tile?.chartKey, tile?.def?.expr]
    .filter(Boolean)
    .join(' ');

export const classifyKpi = tile => {
  const text = textOf(tile);
  const family = (FAMILY_RULES.find(([, re]) => re.test(text)) || [
    'outros',
  ])[0];
  let tier = (TIER_RULES.find(([, re]) => re.test(text)) || ['secondary'])[0];
  if (tile?.pct && tier !== 'tertiary') tier = 'primary';
  return { family, tier };
};

const mix = (hex, other, pct) =>
  `color-mix(in srgb, ${hex} ${100 - pct}%, ${other})`;

// degradê do card por família e nível
export const kpiGrad = (family, tier, dark = false) => {
  const f = KPI_FAMILIES[family] || KPI_FAMILIES.outros;
  if (tier === 'primary') return `linear-gradient(135deg, ${f.c1}, ${f.c2})`;
  if (tier === 'secondary')
    return `linear-gradient(135deg, ${mix(f.c1, dark ? '#0b0d12' : '#fff', 22)}, ${mix(f.c2, dark ? '#0b0d12' : '#fff', 22)})`;
  // terciário: cor clara, texto escuro (no escuro: cor apagada, texto claro)
  return dark
    ? `linear-gradient(135deg, ${mix(f.c1, '#0b0d12', 55)}, ${mix(f.c2, '#0b0d12', 55)})`
    : `linear-gradient(135deg, ${mix(f.c1, '#fff', 62)}, ${mix(f.c2, '#fff', 62)})`;
};

// o card NASCE 100% transparente (vidro) e a cor da família vai ficando
// mais DENSA ao longo do dia — o vidro é o mesmo para todas as famílias
export const kpiGlass = (dark = false) =>
  dark ? 'rgba(255, 255, 255, 0.06)' : 'rgba(255, 255, 255, 0.34)';

// borda fina na cor da família, para o card ainda ter identidade de manhã
export const kpiEdge = (family, dark = false) => {
  const f = KPI_FAMILIES[family] || KPI_FAMILIES.outros;
  return mix(dark ? f.c2 : f.c1, 'transparent', dark ? 55 : 60);
};

// texto escuro enquanto a cor ainda está rala (tema claro); no escuro, sempre
// claro. Terciário é cor clara mesmo cheio → texto escuro o dia todo.
export const kpiInkDark = (tier, fill, dark = false) => {
  if (dark) return false;
  if (tier === 'tertiary') return true;
  return fill < 0.5;
};

// 0 → 1 ao longo do dia útil: 07h 100% transparente, 19h cor cheia (fora
// disso, cheio à noite e transparente de madrugada até as 07h)
export const dayFill = (now = new Date(), start = 7, end = 19) => {
  // hora de SÃO PAULO, seja qual for o fuso do computador
  const sp = new Date(
    now.toLocaleString('en-US', { timeZone: 'America/Sao_Paulo' })
  );
  const h = sp.getHours() + sp.getMinutes() / 60;
  if (h < start) return 0;
  if (h >= end) return 1;
  return Math.max(0, Math.min(1, (h - start) / (end - start)));
};

export const KPI_LEGEND = [
  ['captacao', 'captação'],
  ['agendamento', 'agendamento'],
  ['presenca', 'presença'],
  ['cirurgia', 'cirurgia'],
  ['financeiro', 'financeiro'],
  ['satisfacao', 'satisfação'],
].map(([key, label]) => ({ key, label, ...KPI_FAMILIES[key] }));
