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
// (item 326: a cor é CHEIA o dia inteiro — o vidro que enchia até as 19h saiu)

// 🎨 item 326 (05/10 — pedido dele: "tire aquelas cores transparentes do meu
// painel; deixe os temas dos indicadores mais organizados; combinações legais
// com dopamine colors, contraste"): cada família tem 5 tons VIVOS e o card
// tem cor cheia o dia inteiro (acabou o vidro que enchia até as 19h).
//   deep → c1  resultado principal: o tom mais intenso, número branco
//   c1 → c2    volume: o tom vivo da família, número branco
//   light→pale apoio: o tom claro e alegre da família, número ESCURO (deep)
// Todos os pares foram escolhidos para o número ler de longe: branco só
// sobre tom escuro o bastante, escuro só sobre tom claro.
export const KPI_FAMILIES = {
  financeiro: {
    label: 'Financeiro',
    deep: '#713f12',
    c1: '#a16207',
    c2: '#ca8a04',
    light: '#fde047',
    pale: '#fef08a',
  },
  cirurgia: {
    label: 'Cirurgia',
    deep: '#4c1d95',
    c1: '#6d28d9',
    c2: '#8b5cf6',
    light: '#c4b5fd',
    pale: '#ddd6fe',
  },
  satisfacao: {
    label: 'Satisfação',
    deep: '#9d174d',
    c1: '#be185d',
    c2: '#ec4899',
    light: '#f9a8d4',
    pale: '#fbcfe8',
  },
  presenca: {
    label: 'Presença',
    deep: '#9a3412',
    c1: '#c2410c',
    c2: '#f97316',
    light: '#fdba74',
    pale: '#fed7aa',
  },
  agendamento: {
    label: 'Agendamento',
    deep: '#065f46',
    c1: '#047857',
    c2: '#10b981',
    light: '#6ee7b7',
    pale: '#a7f3d0',
  },
  captacao: {
    label: 'Captação',
    deep: '#1e3a8a',
    c1: '#1d4ed8',
    c2: '#3b82f6',
    light: '#93c5fd',
    pale: '#bfdbfe',
  },
  outros: {
    label: 'Outros',
    deep: '#0f172a',
    c1: '#334155',
    c2: '#64748b',
    light: '#cbd5e1',
    pale: '#e2e8f0',
  },
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

// degradê do card por família e nível — sempre cor CHEIA (item 326)
export const kpiGrad = (family, tier, dark = false) => {
  const f = KPI_FAMILIES[family] || KPI_FAMILIES.outros;
  if (tier === 'primary') return `linear-gradient(135deg, ${f.deep}, ${f.c1})`;
  if (tier === 'secondary') return `linear-gradient(135deg, ${f.c1}, ${f.c2})`;
  // apoio: tom claro e alegre com número escuro; no tema escuro, o tom
  // intenso apagado (número claro) para não ofuscar
  return dark
    ? `linear-gradient(135deg, ${mix(f.deep, '#0b0d12', 30)}, ${mix(f.c1, '#0b0d12', 45)})`
    : `linear-gradient(135deg, ${f.light}, ${f.pale})`;
};

// tinta do número: escura (o tom mais intenso da família) só no card de
// apoio do tema claro; nos outros, branco
export const kpiInkDark = (tier, dark = false) => !dark && tier === 'tertiary';
export const kpiInk = family =>
  (KPI_FAMILIES[family] || KPI_FAMILIES.outros).deep;

export const KPI_LEGEND = [
  ['captacao', 'captação'],
  ['agendamento', 'agendamento'],
  ['presenca', 'presença'],
  ['cirurgia', 'cirurgia'],
  ['financeiro', 'financeiro'],
  ['satisfacao', 'satisfação'],
].map(([key, label]) => ({ key, label, ...KPI_FAMILIES[key] }));
