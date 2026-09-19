// TEIA dos criativos (item 175): eixos disponíveis, "força" 0–100 de cada um
// e a escolha de eixos por ambiente (chavinhas), guardada no navegador.
//
// Força: com parâmetro (gancho, corpo, CTA, conversa, custo) → 0 no zero,
// 50 na linha do RUIM, 100 no BOM (custo invertido). Sem parâmetro (leads,
// fim do vídeo, conversas, fatia) → contra o MELHOR do recorte (100 = o
// melhor). Frequência tem escala fixa (1 = 100, 3 = 0).
import { reactive } from 'vue';
import { fmtPct, fmtMoney, fmtNum } from './creativeFormat';

const clamp = v => Math.max(0, Math.min(100, Number.isFinite(v) ? v : 0));
const rateOf = (row, key) => {
  if (!row) return null;
  if (row.rates && row.rates[key] !== undefined) return row.rates[key];
  return row[key];
};
// curva de retenção: [parou 3 s, 25 %, 50 %, 75 %, fim] ÷ impressões.
// Para ler "onde o vídeo solta", cada ponto é dividido por quem PAROU
// (3 s): 100 = todos que pararam chegaram até ali.
const retentionShare = (row, i) => {
  const c = row && row.rates && row.rates.retention;
  if (!Array.isArray(c) || !(c[0] > 0)) return null;
  return c[i] / c[0];
};
const shareAxis = (key, i, label, metric, short = label) => ({
  key,
  label,
  short,
  metric,
  get: r => retentionShare(r, i),
  fixed: v => clamp(v * 100),
  fmt: v => fmtPct(v, 0),
  scopes: ['creative'],
  video: true,
});

export const RADAR_AXES = [
  {
    key: 'hook',
    label: 'Gancho',
    short: 'Gancho',
    metric: 'taxa de parada',
    get: r => rateOf(r, 'hook_rate'),
    target: 'hook_rate',
    fmt: v => fmtPct(v),
    scopes: ['creative', 'asset'],
    video: true,
  },
  {
    key: 'hold',
    label: 'Corpo',
    short: 'Corpo',
    metric: 'retenção',
    get: r => rateOf(r, 'hold_rate'),
    target: 'hold_rate',
    fmt: v => fmtPct(v),
    scopes: ['creative'],
    video: true,
  },
  {
    key: 'cta',
    label: 'CTA',
    short: 'CTA',
    metric: 'CTR de link',
    get: r => rateOf(r, 'link_ctr'),
    target: 'link_ctr',
    fmt: v => fmtPct(v, 2),
    scopes: ['creative', 'asset'],
  },
  {
    key: 'conv',
    label: 'Conversa',
    short: 'Conv.',
    metric: 'conversa por clique',
    get: r => rateOf(r, 'conv_rate'),
    target: 'conv_rate',
    fmt: v => fmtPct(v),
    scopes: ['creative'],
  },
  {
    key: 'cost',
    label: 'Custo',
    short: 'Custo',
    metric: 'custo por conversa (menor = melhor)',
    get: r => rateOf(r, 'cost_conversation'),
    target: 'cost_conversation',
    lower: true,
    fmt: v => fmtMoney(v),
    scopes: ['creative', 'asset'],
  },
  shareAxis('p25', 1, '25 %', 'chegou a 25 % do vídeo ÷ parou 3 s'),
  shareAxis('p50', 2, '50 %', 'chegou à metade ÷ parou 3 s'),
  shareAxis('p75', 3, '75 %', 'chegou a 75 % ÷ parou 3 s'),
  shareAxis(
    'finish',
    4,
    'Fim do vídeo',
    'assistiu até o fim ÷ parou 3 s',
    'Fim'
  ),
  {
    key: 'conversations',
    label: 'Conversas',
    short: 'Conv.',
    metric: 'conversas iniciadas (contra a melhor peça)',
    get: r => (r ? r.conversations : null),
    relative: true,
    fmt: v => fmtNum(v),
    scopes: ['asset'],
  },
  {
    key: 'share',
    label: 'Fatia',
    short: 'Fatia',
    metric: 'fatia das impressões (contra a maior)',
    get: r => (r ? r.share : null),
    relative: true,
    fmt: v => fmtPct(v, 0),
    scopes: ['asset'],
  },
];

// ── TEIAS: cada uma responde UMA pergunta e mistura só eixos da MESMA
//    régua, para a forma do polígono ter lógica ("ponta curta = bloco a
//    trocar"). Chavinhas parametrizam cada teia (mínimo 3 eixos). ──
export const RADAR_GROUPS = [
  {
    key: 'copy',
    label: 'Copy × parâmetros',
    short: 'Copy',
    question: 'qual bloco está fraco?',
    icon: 'i-lucide-target',
    hint: 'Cada ponta é um bloco da copy medido contra o SEU parâmetro: 100 = bateu o bom, 50 = na linha do ruim, 0 = zero (custo invertido). A ponta mais curta é o bloco a trocar na próxima versão.',
    axes: ['hook', 'hold', 'cta', 'conv', 'cost'],
    scopes: ['creative'],
  },
  {
    key: 'video',
    label: 'Retenção do vídeo',
    short: 'Retenção',
    question: 'onde o vídeo solta?',
    icon: 'i-lucide-film',
    hint: 'Parada nos 3 s contra o parâmetro e, de quem parou, quanto chegou a 25 %, 50 %, 75 % e ao fim (100 = todos). Teia cheia = ninguém solta; a ponta curta mostra em que trecho o vídeo perde.',
    axes: ['hook', 'p25', 'p50', 'p75', 'finish'],
    scopes: ['creative'],
    video: true,
  },
  {
    key: 'asset',
    label: 'Peça × recorte',
    short: 'Peça',
    question: 'qual peça rende mais?',
    icon: 'i-lucide-puzzle',
    hint: 'CTA e custo contra o parâmetro; conversas e fatia contra a melhor peça do recorte.',
    axes: ['cta', 'conversations', 'cost', 'share'],
    scopes: ['asset'],
  },
];
export const groupOf = key => RADAR_GROUPS.find(g => g.key === key);
// compatibilidade: eixos padrão por escopo = a 1ª teia do escopo
export const DEFAULT_AXES = {
  creative: RADAR_GROUPS[0].axes,
  asset: RADAR_GROUPS[2].axes,
};

const valid = v => v !== null && v !== undefined && Number.isFinite(Number(v));

// força contra o parâmetro: 0 → 50 (ruim) → 100 (bom)
const targetScore = (v, t) => {
  const bad = Number(t.bad);
  const good = Number(t.good);
  if (!valid(bad) || !valid(good) || bad === good) return null;
  if (t.lower_is_better) {
    if (v <= good) return 100;
    if (v <= bad) return 100 - (50 * (v - good)) / (bad - good);
    return clamp((50 * bad) / v);
  }
  if (v >= good) return 100;
  if (v >= bad) return 50 + (50 * (v - bad)) / (good - bad);
  return clamp((50 * v) / bad);
};

// força contra o melhor do recorte
const relativeScore = (axis, v, peers) => {
  const vals = (peers || []).map(axis.get).filter(valid).map(Number);
  if (!vals.length) return null;
  if (axis.lower) {
    const best = Math.min(...vals);
    return v > 0 ? clamp((100 * best) / v) : 100;
  }
  const best = Math.max(...vals);
  return best > 0 ? clamp((100 * v) / best) : 0;
};

const scoreRaw = (axis, v, ctx = {}) => {
  let score = null;
  if (axis.fixed) score = axis.fixed(v);
  else if (axis.target && ctx.targets && ctx.targets[axis.target])
    score = targetScore(v, ctx.targets[axis.target]);
  if (score === null) score = relativeScore(axis, v, ctx.peers);
  return score === null ? null : Math.round(clamp(score));
};

export const scoreFor = (axis, row, ctx = {}) => {
  const raw = axis.get(row);
  if (!valid(raw)) return { score: null, raw: null };
  const v = Number(raw);
  return { score: scoreRaw(axis, v, ctx), raw: v };
};

// polígono de UMA linha (criativo, peça, campeão)
export const datasetFor = (
  row,
  axes,
  ctx,
  { key, label, color, dashed } = {}
) => {
  const values = {};
  const texts = {};
  axes.forEach(axis => {
    const { score, raw } = scoreFor(axis, row, ctx);
    values[axis.key] = score === null ? 0 : score;
    texts[axis.key] =
      score === null
        ? `${axis.label}: não se aplica`
        : `${axis.label} (${axis.metric}): ${axis.fmt(raw)} → força ${score}`;
  });
  return {
    key: key || 'row',
    label: label || '',
    color: color || 'var(--cv)',
    values,
    texts,
    dashed: !!dashed,
  };
};

// polígono tracejado da MÉDIA da conta: taxa média da conta quando o
// backend manda (averages), senão a média dos pares do recorte
export const averageDataset = (axes, ctx) => {
  const values = {};
  const texts = {};
  const peers = ctx.peers || [];
  axes.forEach(axis => {
    let mean = null;
    if (axis.target && ctx.averages && valid(ctx.averages[axis.target])) {
      mean = Number(ctx.averages[axis.target]);
    } else {
      const vals = peers.map(axis.get).filter(valid).map(Number);
      if (vals.length) mean = vals.reduce((a, b) => a + b, 0) / vals.length;
    }
    const score = mean === null ? null : scoreRaw(axis, mean, ctx);
    values[axis.key] = score === null ? 0 : score;
    texts[axis.key] =
      score === null
        ? `${axis.label}: média não se aplica`
        : `Média da conta — ${axis.label}: ${axis.fmt(mean)} → força ${score}`;
  });
  return {
    key: 'avg',
    label: 'média da conta',
    color: '#64748b',
    values,
    texts,
    dashed: true,
  };
};

// eixos que existem no ambiente (escopo + se eixos relativos valem)
export const availableAxes = (scope = 'creative', relativeOk = true) =>
  RADAR_AXES.filter(
    a => a.scopes.includes(scope) && (relativeOk || !a.relative)
  );

// teias que fazem sentido no ambiente (escopo, vídeo, ≥ 3 eixos)
export const groupsFor = (
  scope = 'creative',
  relativeOk = true,
  video = true
) => {
  const avail = availableAxes(scope, relativeOk).map(a => a.key);
  return RADAR_GROUPS.filter(
    g =>
      g.scopes.includes(scope) &&
      (video || !g.video) &&
      g.axes.filter(k => avail.includes(k)).length >= 3
  );
};

// ── escolha por ambiente: quais eixos de cada teia ficam ligados
//    (chavinhas), compartilhada entre os cards da tela e guardada no
//    navegador como { copy: [...], video: [...], asset: [...] } ──
const stores = {};
const storageKey = env => `cevico_radar_axes:${env}`;

export const useRadarAxes = env => {
  if (!stores[env]) {
    let saved = null;
    try {
      saved = JSON.parse(localStorage.getItem(storageKey(env)) || 'null');
    } catch {
      saved = null;
    }
    const selected = {};
    RADAR_GROUPS.forEach(g => {
      const sel =
        saved && saved.selected && Array.isArray(saved.selected[g.key])
          ? saved.selected[g.key].filter(k => g.axes.includes(k))
          : null;
      selected[g.key] = sel && sel.length >= 3 ? sel : [...g.axes];
    });
    stores[env] = reactive({ selected });
  }
  const store = stores[env];
  const persist = () => {
    try {
      localStorage.setItem(
        storageKey(env),
        JSON.stringify({ selected: store.selected })
      );
    } catch {
      /* navegador sem armazenamento: só não lembra */
    }
  };
  const isOn = (group, key) => (store.selected[group] || []).includes(key);
  // mínimo de 3 eixos: sem isso não há teia
  const toggle = (group, key) => {
    const list = store.selected[group];
    if (!list) return false;
    const i = list.indexOf(key);
    if (i >= 0) {
      if (list.length <= 3) return false;
      list.splice(i, 1);
    } else {
      list.push(key);
    }
    persist();
    return true;
  };
  // opções (chavinhas) de uma teia no ambiente, na ordem da teia
  const optionsFor = (group, scope = 'creative', relativeOk = true) => {
    const g = groupOf(group);
    if (!g) return [];
    const avail = availableAxes(scope, relativeOk);
    return g.axes.map(k => avail.find(a => a.key === k)).filter(Boolean);
  };
  const axesFor = (group, scope = 'creative', relativeOk = true) =>
    optionsFor(group, scope, relativeOk).filter(a => isOn(group, a.key));
  return { store, isOn, toggle, optionsFor, axesFor };
};
