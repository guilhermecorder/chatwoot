// Formatação compartilhada da Central de Criativos (pt-BR, sem lib).
export const fmtMoney = v => {
  const n = Number(v || 0);
  if (n >= 1000000)
    return `R$ ${(n / 1000000).toFixed(2).replace('.', ',')} mi`;
  if (n >= 1000) return `R$ ${(n / 1000).toFixed(1).replace('.', ',')} mil`;
  return `R$ ${n.toFixed(n < 100 ? 2 : 0).replace('.', ',')}`;
};

export const fmtCompact = v => {
  const n = Number(v || 0);
  if (n >= 1000000) return `${(n / 1000000).toFixed(1).replace('.', ',')} mi`;
  if (n >= 1000) return `${(n / 1000).toFixed(1).replace('.', ',')} mil`;
  return n.toLocaleString('pt-BR');
};

export const fmtPct = (v, digits = 1) => {
  if (v === null || v === undefined || Number.isNaN(Number(v))) return '—';
  return `${(Number(v) * 100).toFixed(digits).replace('.', ',')}%`;
};

export const fmtNum = v => Number(v || 0).toLocaleString('pt-BR');

export const STATUS_META = {
  ACTIVE: { label: 'no ar', cls: 'bg-emerald-500' },
  PAUSED: { label: 'pausado', cls: 'bg-amber-500' },
  CAMPAIGN_PAUSED: { label: 'campanha pausada', cls: 'bg-amber-500' },
  ADSET_PAUSED: { label: 'conjunto pausado', cls: 'bg-amber-500' },
  ARCHIVED: { label: 'arquivado', cls: 'bg-n-slate-8' },
  DELETED: { label: 'apagado', cls: 'bg-n-slate-8' },
  UNKNOWN: { label: 'sem detalhe', cls: 'bg-n-slate-8' },
};

export const statusMeta = status =>
  STATUS_META[status] || {
    label: (status || '').toLowerCase().replace(/_/g, ' '),
    cls: 'bg-n-slate-8',
  };

export const FORMAT_ICON = {
  video: 'i-lucide-clapperboard',
  image: 'i-lucide-image',
  carousel: 'i-lucide-gallery-horizontal',
  dynamic: 'i-lucide-shuffle',
  other: 'i-lucide-file-question',
};

export const LEVEL_META = {
  forte: {
    label: 'forte',
    icon: 'i-lucide-trending-up',
    cls: 'text-emerald-600 dark:text-emerald-400',
  },
  ok: { label: 'na média', icon: 'i-lucide-minus', cls: 'text-n-slate-10' },
  fraco: {
    label: 'fraco',
    icon: 'i-lucide-trending-down',
    cls: 'text-red-600 dark:text-red-400',
  },
};

// ── parâmetros bom / atenção / ruim (item 172, rodada 2) ──
export const BAND_META = {
  bom: {
    label: 'Bom',
    icon: 'i-lucide-circle-check',
    cls: 'text-emerald-700 dark:text-emerald-400',
    bg: 'bg-emerald-500/15',
    fill: 'rgb(16 185 129 / 0.22)',
  },
  atencao: {
    label: 'Atenção',
    icon: 'i-lucide-triangle-alert',
    cls: 'text-amber-700 dark:text-amber-400',
    bg: 'bg-amber-500/15',
    fill: 'rgb(245 158 11 / 0.22)',
  },
  ruim: {
    label: 'Ruim',
    icon: 'i-lucide-circle-x',
    cls: 'text-red-700 dark:text-red-400',
    bg: 'bg-red-500/15',
    fill: 'rgb(239 68 68 / 0.22)',
  },
};

export const VS_META = {
  acima: 'acima da média da conta',
  na_media: 'na média da conta',
  abaixo: 'abaixo da média da conta',
};

export const FOCUS_META = {
  gancho: 'Trabalhar o gancho',
  corpo: 'Trabalhar o corpo',
  cta: 'Trabalhar o CTA',
  conversa: 'Trabalhar o atendimento',
  publico: 'Trabalhar público e entrega',
  escalar: 'Escalar com cautela',
  esperar: 'Esperar mais dados',
  hook: 'Melhorar o gancho',
  hold: 'Melhorar o corpo',
  conv: 'Melhorar a conversa',
  cost: 'Baixar o custo',
};

// variação em % entre dois valores (null quando não dá para comparar)
export const delta = (current, previous) => {
  if (previous === null || previous === undefined || !previous) return null;
  if (current === null || current === undefined) return null;
  return (Number(current) - Number(previous)) / Number(previous);
};

export const fmtDelta = d => {
  if (d === null || d === undefined || !Number.isFinite(d)) return '';
  const pct = Math.round(Math.abs(d) * 100);
  if (pct === 0) return 'igual';
  return `${d > 0 ? '▲' : '▼'} ${pct}%`;
};

// cor da variação: `lowerIsBetter` inverte (custo caindo é bom)
export const deltaCls = (d, lowerIsBetter = false) => {
  if (
    d === null ||
    d === undefined ||
    !Number.isFinite(d) ||
    Math.round(Math.abs(d) * 100) === 0
  )
    return 'text-n-slate-9';
  const good = lowerIsBetter ? d < 0 : d > 0;
  return good
    ? 'text-emerald-700 dark:text-emerald-400'
    : 'text-red-700 dark:text-red-400';
};

export const METRIC_DEFS = [
  {
    key: 'hook_rate',
    band: 'hook',
    label: 'Gancho',
    metric: 'taxa de parada',
    hint: 'plays de 3 s ÷ impressões (só vídeo)',
    digits: 1,
    video: true,
  },
  {
    key: 'hold_rate',
    band: 'hold',
    label: 'Corpo',
    metric: 'retenção',
    hint: 'ThruPlay ÷ plays de 3 s',
    digits: 1,
    video: true,
  },
  {
    key: 'link_ctr',
    band: 'cta',
    label: 'CTA',
    metric: 'CTR de link',
    hint: 'cliques no link ÷ impressões',
    digits: 2,
    video: false,
  },
  {
    key: 'conv_rate',
    band: 'conv',
    label: 'Conversa',
    metric: 'por clique',
    hint: 'conversas iniciadas ÷ cliques',
    digits: 1,
    video: false,
  },
  {
    key: 'cost_conversation',
    band: 'cost',
    label: 'Custo por conversa',
    metric: 'investimento ÷ conversas',
    hint: '',
    money: true,
    video: false,
  },
];

// ── campeões (item 172, rodada 3) ──
export const CHAMPION_META = {
  cost: {
    label: 'Campeão · menor custo por conversa',
    icon: 'i-lucide-trophy',
  },
  hook: { label: 'Campeão de gancho', icon: 'i-lucide-anchor' },
  hold: { label: 'Campeão de corpo', icon: 'i-lucide-film' },
  cta: { label: 'Campeão de CTA', icon: 'i-lucide-mouse-pointer-click' },
  conv: { label: 'Campeão de conversa', icon: 'i-lucide-message-circle' },
};

export const PART_META = {
  hook: {
    label: 'Gancho',
    metric: 'taxa de parada',
    icon: 'i-lucide-anchor',
    fmt: v => fmtPct(v),
    key: 'hook_rate',
  },
  hold: {
    label: 'Corpo',
    metric: 'retenção',
    icon: 'i-lucide-film',
    fmt: v => fmtPct(v),
    key: 'hold_rate',
  },
  cta: {
    label: 'CTA',
    metric: 'CTR de link',
    icon: 'i-lucide-mouse-pointer-click',
    fmt: v => fmtPct(v, 2),
    key: 'link_ctr',
  },
  conv: {
    label: 'Conversa',
    metric: 'por clique',
    icon: 'i-lucide-message-circle',
    fmt: v => fmtPct(v),
    key: 'conv_rate',
  },
  cost: {
    label: 'Custo por conversa',
    metric: 'investimento ÷ conversas',
    icon: 'i-lucide-trophy',
    fmt: v => fmtMoney(v),
    key: 'cost_conversation',
  },
};

export const fmtDate = iso => {
  if (!iso) return '';
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
  return m ? `${m[3]}/${m[2]}/${m[1].slice(2)}` : iso;
};
