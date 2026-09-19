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
  {
    key: 'leads',
    label: 'Leads',
    short: 'Leads',
    metric: 'leads no CRM (contra o melhor do recorte)',
    get: r => (r && r.funnel ? r.funnel.leads : null),
    relative: true,
    fmt: v => fmtNum(v),
    scopes: ['creative'],
  },
  {
    key: 'finish',
    label: 'Fim do vídeo',
    short: 'Fim',
    metric: 'assistiu até o fim ÷ impressões (contra o melhor)',
    get: r =>
      r && r.rates && Array.isArray(r.rates.retention)
        ? r.rates.retention[4]
        : null,
    relative: true,
    video: true,
    fmt: v => fmtPct(v),
    scopes: ['creative'],
  },
  {
    key: 'freq',
    label: 'Frequência',
    short: 'Freq.',
    metric: 'vezes que a mesma pessoa viu (1 = ótimo, 3 = saturou)',
    get: r => rateOf(r, 'frequency'),
    fixed: v => clamp((100 * (3 - v)) / 2),
    fmt: v => `${Number(v).toFixed(1).replace('.', ',')}×`,
    scopes: ['creative'],
  },
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

export const DEFAULT_AXES = {
  creative: ['hook', 'hold', 'cta', 'conv', 'cost', 'leads'],
  asset: ['cta', 'conversations', 'cost', 'share'],
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

export const scoreFor = (axis, row, ctx = {}) => {
  const raw = axis.get(row);
  if (!valid(raw)) return { score: null, raw: null };
  const v = Number(raw);
  let score = null;
  if (axis.fixed) score = axis.fixed(v);
  else if (axis.target && ctx.targets && ctx.targets[axis.target])
    score = targetScore(v, ctx.targets[axis.target]);
  if (score === null) score = relativeScore(axis, v, ctx.peers);
  return { score: score === null ? null : Math.round(clamp(score)), raw: v };
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

// polígono tracejado da MÉDIA da conta (taxas médias + média dos pares)
export const averageDataset = (axes, ctx) => {
  const avgRow = { rates: { ...(ctx.averages || {}) } };
  const peers = ctx.peers || [];
  axes.forEach(axis => {
    if (axis.target && ctx.averages && valid(ctx.averages[axis.target])) return;
    const vals = peers.map(axis.get).filter(valid).map(Number);
    if (!vals.length) return;
    const mean = vals.reduce((a, b) => a + b, 0) / vals.length;
    if (axis.key === 'leads') avgRow.funnel = { leads: mean };
    else if (axis.key === 'finish') avgRow.rates.retention = [0, 0, 0, 0, mean];
    else if (axis.key === 'conversations') avgRow.conversations = mean;
    else if (axis.key === 'share') avgRow.share = mean;
    else avgRow.rates[axis.target || axis.key] = mean;
  });
  return datasetFor(avgRow, axes, ctx, {
    key: 'avg',
    label: 'média da conta',
    color: '#64748b',
    dashed: true,
  });
};

// eixos que fazem sentido no ambiente
export const availableAxes = (scope = 'creative', relativeOk = true) =>
  RADAR_AXES.filter(
    a => a.scopes.includes(scope) && (relativeOk || !a.relative)
  );

// ── escolha por ambiente (chavinhas), compartilhada entre os cards da tela ──
const stores = {};
const storageKey = env => `cevico_radar_axes:${env}`;

export const useRadarAxes = (env, defaults = DEFAULT_AXES.creative) => {
  if (!stores[env]) {
    let saved = null;
    try {
      saved = JSON.parse(localStorage.getItem(storageKey(env)) || 'null');
    } catch {
      saved = null;
    }
    stores[env] = reactive({
      selected:
        Array.isArray(saved) && saved.length >= 3 ? saved : [...defaults],
    });
  }
  const store = stores[env];
  const isOn = key => store.selected.includes(key);
  // mínimo de 3 eixos: sem isso não há teia
  const toggle = key => {
    const i = store.selected.indexOf(key);
    if (i >= 0) {
      if (store.selected.length <= 3) return false;
      store.selected.splice(i, 1);
    } else {
      store.selected.push(key);
    }
    try {
      localStorage.setItem(storageKey(env), JSON.stringify(store.selected));
    } catch {
      /* navegador sem armazenamento: só não lembra */
    }
    return true;
  };
  const axesFor = (scope = 'creative', relativeOk = true) =>
    availableAxes(scope, relativeOk).filter(a => isOn(a.key));
  return { store, isOn, toggle, axesFor };
};
