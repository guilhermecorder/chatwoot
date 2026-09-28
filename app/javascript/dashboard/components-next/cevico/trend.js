// 📈 LINHA DE TENDÊNCIA (item 266, 28/09 — pedido: "os indicadores devem ter a
// opção da linha de tendência… assim poderemos analisar nossos indicadores
// melhor ainda"). Regressão linear simples (mínimos quadrados) sobre os
// baldes COM valor — os dias que ainda não chegaram (zero) não puxam a reta
// para baixo, mesma regra da linha de média. Precisa de 3 baldes com valor.
// Retorna a reta nos índices do primeiro e do último balde, a inclinação por
// balde e o ritmo em % da média (o que se lê: "subindo ~3% por dia").
export const trendOf = values => {
  const nums = (values || []).map(v => Number(v) || 0);
  const pts = nums.map((v, i) => [i, v]).filter(p => p[1] > 0);
  if (pts.length < 3) return null;
  const n = pts.length;
  const sx = pts.reduce((s, p) => s + p[0], 0);
  const sy = pts.reduce((s, p) => s + p[1], 0);
  const sxx = pts.reduce((s, p) => s + p[0] * p[0], 0);
  const sxy = pts.reduce((s, p) => s + p[0] * p[1], 0);
  const den = n * sxx - sx * sx;
  if (!den) return null;
  const slope = (n * sxy - sx * sy) / den;
  const intercept = (sy - slope * sx) / n;
  const mean = sy / n;
  const first = pts[0][0];
  const last = pts[pts.length - 1][0];
  const at = i => Math.max(0, intercept + slope * i);
  return {
    slope,
    intercept,
    mean,
    first,
    last,
    y0: at(first),
    y1: at(last),
    at,
    // ritmo por balde em % da média (estável quando |ritmo| < 1%)
    pct: mean > 0 ? (slope / mean) * 100 : 0,
  };
};

const UNIT = { day: 'por dia', week: 'por semana', month: 'por mês' };

// a tendência lida em palavras: "subindo ~3% por dia" · "estável" · "caindo ~5% por semana"
export const trendText = (values, granularity = 'day') => {
  const t = trendOf(values);
  if (!t) return null;
  const unit = UNIT[granularity] || 'por período';
  const pct = Math.abs(t.pct);
  if (pct < 1) return { dir: 0, text: `estável ${unit}`, pct: t.pct };
  const shown = pct >= 10 ? Math.round(pct) : Math.round(pct * 10) / 10;
  const dir = t.pct > 0 ? 1 : -1;
  return {
    dir,
    pct: t.pct,
    text: `${dir > 0 ? 'subindo' : 'caindo'} ~${String(shown).replace('.', ',')}% ${unit}`,
  };
};
