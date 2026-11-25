// 🆚 item 413 (24/11) — as contas do COMPARATIVO DE CAIXAS, separadas da tela
// para poderem ser testadas sozinhas (specs/cevicoInboxCompare.spec.js).
// A conta é de TURMA (quem chegou por aquela caixa no período): tudo aqui é
// parte ÷ inteiro da mesma turma.

// parte ÷ inteiro em %, com 1 casa; null quando não há inteiro (nunca 0% falso)
export const rate = (part, whole) => {
  const w = Number(whole) || 0;
  if (!w) return null;
  return Math.round(((Number(part) || 0) / w) * 1000) / 10;
};

// as taxas que a tela mostra, a partir do funil de uma caixa
export const funnelRates = (f = {}) => ({
  responderam: rate(f.responderam, f.chegaram),
  orcamento: rate(f.orcamento, f.chegaram),
  agendaram: rate(f.agendaram, f.chegaram),
  // do orçamento para a consulta: os que agendaram ENTRE os que receberam orçamento
  // (quem agendou sem passar pelo orçamento não entra nesta conta; teto de 100%)
  orcamento_consulta: f.orcamento
    ? Math.min(100, rate(Math.min(f.agendaram, f.orcamento), f.orcamento))
    : null,
  compareceram: rate(f.compareceram, f.agendaram),
  indicacoes: rate(f.indicacoes, f.compareceram),
  cirurgias: rate(f.cirurgias, f.chegaram),
});

const erf = x => {
  // aproximação de Abramowitz-Stegun (erro < 1,5e-7): basta para a confiança
  const sign = x < 0 ? -1 : 1;
  const ax = Math.abs(x);
  const t = 1 / (1 + 0.3275911 * ax);
  const y =
    1 -
    ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) *
      t +
      0.254829592) *
      t *
      Math.exp(-ax * ax);
  return sign * y;
};

// A diferença é de verdade ou pode ser acaso? Teste de duas proporções (o mesmo
// do Laboratório). Devolve a chance (0–100) de a caixa B ser MELHOR que a A:
//   50 = cara ou coroa · ≥ 95 = dá para decidir pela B · ≤ 5 = pela A
export const confidence = (hitsA, totalA, hitsB, totalB) => {
  const [ha, ta, hb, tb] = [hitsA, totalA, hitsB, totalB].map(
    v => Number(v) || 0
  );
  if (!ta || !tb) return null;
  const pooled = (ha + hb) / (ta + tb);
  const spread = Math.sqrt(pooled * (1 - pooled) * (1 / ta + 1 / tb));
  if (!spread) return { chance: 50, z: 0 };
  const z = (hb / tb - ha / ta) / spread;
  const chance = 0.5 * (1 + erf(z / Math.sqrt(2))) * 100;
  return { chance: Math.round(chance * 10) / 10, z: Math.round(z * 100) / 100 };
};

// a frase da confiança, sem jargão
export const confidenceText = (conf, nameA, nameB) => {
  if (!conf)
    return 'Ainda não há gente suficiente nas duas caixas para comparar.';
  const { chance } = conf;
  if (chance >= 95)
    return `Dá para confiar: ${nameB} agenda mais que ${nameA} (${Math.round(chance)}% de certeza).`;
  if (chance <= 5)
    return `Dá para confiar: ${nameA} agenda mais que ${nameB} (${Math.round(100 - chance)}% de certeza).`;
  const lider = chance >= 50 ? nameB : nameA;
  const pct = Math.round(chance >= 50 ? chance : 100 - chance);
  if (pct <= 60)
    return `Empate técnico: com o volume de hoje não dá para dizer quem agenda mais.`;
  return `${lider} está na frente, mas ainda pode ser acaso (${pct}% de certeza; decide com 95%).`;
};

// índice da melhor caixa numa métrica (null/undefined não concorrem);
// lowerIsBetter = custo e tempo. Empate ou uma caixa só = ninguém marcado.
export const bestIndex = (values, { lowerIsBetter = false } = {}) => {
  const valid = values
    .map((v, i) => ({ v, i }))
    .filter(({ v }) => v !== null && v !== undefined && !Number.isNaN(v));
  if (valid.length < 2) return -1;
  const sorted = [...valid].sort((a, b) =>
    lowerIsBetter ? a.v - b.v : b.v - a.v
  );
  if (sorted[0].v === sorted[1].v) return -1;
  return sorted[0].i;
};

// "2 h 10 min", "45 min", "3 dias" — tempo em minutos, por extenso e curto
export const humanMinutes = minutes => {
  if (minutes === null || minutes === undefined) return '—';
  const m = Number(minutes);
  if (m < 1) return 'menos de 1 min';
  if (m < 60) return `${Math.round(m)} min`;
  if (m < 60 * 48) {
    const h = Math.floor(m / 60);
    const rest = Math.round(m - h * 60);
    return rest ? `${h} h ${rest} min` : `${h} h`;
  }
  const days = Math.round((m / 1440) * 10) / 10;
  return `${String(days).replace('.', ',')} dias`;
};

// ── 📈 item 418 (25/11): as contas dos MINI GRÁFICOS DE LINHA ──────────────
// As mesmas 10 cores do servidor (Crm::InboxComparison::PALETTE): campanhas e
// criativos ganham uma cor cada, na ordem em que aparecem.
export const LINE_PALETTE = [
  '#2563EB',
  '#EA580C',
  '#059669',
  '#7C3AED',
  '#DB2777',
  '#0D9488',
  '#B8860B',
  '#DC2626',
  '#475569',
  '#0891B2',
];

// teto e marcas do eixo, redondos, para um grupo de mini gráficos usar a MESMA
// escala (aí dá para comparar um cartão com o outro só de olhar).
//   percent: 10 · 20 · 30 · 40 · 60 · 80 · 100
//   número:  2 · 4 · 6 · 10 · 20 · 40 · 60 · 100 · 200 …
const PERCENT_SCALES = [
  [10, 5],
  [20, 10],
  [30, 10],
  [40, 20],
  [60, 20],
  [80, 40],
  [100, 50],
];
export const scaleFor = (values, { percent = false } = {}) => {
  const max = Math.max(
    0,
    ...(values || []).filter(v => v !== null && v !== undefined).map(Number)
  );
  if (percent) {
    const [top, step] =
      PERCENT_SCALES.find(([limit]) => max <= limit) || PERCENT_SCALES.at(-1);
    const ticks = [];
    for (let v = 0; v <= top; v += step) ticks.push(v);
    return { top, ticks };
  }
  let top = 2;
  for (let pow = 1; pow <= 1e9; pow *= 10) {
    const hit = [2, 4, 6, 10].map(b => b * pow).find(c => c >= max);
    if (hit) {
      top = hit;
      break;
    }
  }
  return { top, ticks: [0, top / 2, top] };
};

// uma série com buracos (null) vira: trechos CHEIOS (pontos vizinhos com dado)
// e PONTES (ligam um trecho ao seguinte por cima do buraco; a tela desenha
// pontilhado — nunca zero falso). Cada ponto = [índice, valor].
export const lineRuns = values => {
  const runs = [];
  let current = [];
  (values || []).forEach((v, i) => {
    if (v === null || v === undefined || Number.isNaN(Number(v))) {
      if (current.length) runs.push(current);
      current = [];
    } else current.push([i, Number(v)]);
  });
  if (current.length) runs.push(current);
  const bridges = [];
  for (let k = 0; k < runs.length - 1; k += 1)
    bridges.push([runs[k].at(-1), runs[k + 1][0]]);
  return { runs, bridges, last: runs.length ? runs.at(-1).at(-1) : null };
};
