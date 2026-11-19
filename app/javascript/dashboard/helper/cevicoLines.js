// 📈 item 398 (19/11/2026 — "o gráfico do financeiro está ruim, precisa ser de
// linhas certinhas"): contas e traços das linhas do kit, separados da tela para
// ter teste. Regra da casa: linha contínua SEM inventar valor — reta de ponto a
// ponto (nada de curva que cria pico), e onde não existe número (custo ÷ 0) o
// trecho vira um pontilhado fino ligando os vizinhos, sem bolinha.

const n = v => Number(v) || 0;
const cost = (spend, count) => (spend > 0 && count > 0 ? spend / count : null);

// custo de CADA balde: gasto do balde ÷ resultado do balde (null sem resultado)
export const bucketCost = (spend = [], count = []) =>
  spend.map((v, i) => ({
    spend: n(v),
    count: n(count[i]),
    cost: cost(n(v), n(count[i])),
  }));

// custo ACUMULADO: tudo que foi gasto do começo até o balde ÷ tudo que chegou
// até ali. Depois do 1º resultado a linha nunca mais quebra, e o último ponto
// é o custo do período inteiro (gasto total ÷ resultado total).
export const cumulativeCost = (spend = [], count = []) => {
  let s = 0;
  let c = 0;
  return spend.map((v, i) => {
    s += n(v);
    c += n(count[i]);
    return { spend: s, count: c, cost: cost(s, c) };
  });
};

// pontos [[x, y] | null] → trechos de linha cheia (runs), pontes pontilhadas
// sobre os buracos do MEIO (bridges) e pontos sozinhos (singles). Buraco no
// começo ou no fim não ganha ponte: ali ainda não existe número nenhum.
export const lineSegments = (points = []) => {
  const runs = [];
  let current = [];
  points.forEach(p => {
    if (p) current.push(p);
    else if (current.length) {
      runs.push(current);
      current = [];
    }
  });
  if (current.length) runs.push(current);
  const bridges = [];
  for (let i = 0; i < runs.length - 1; i += 1) {
    bridges.push([runs[i][runs[i].length - 1], runs[i + 1][0]]);
  }
  return {
    runs: runs.filter(r => r.length > 1),
    bridges,
    singles: runs.filter(r => r.length === 1).map(r => r[0]),
  };
};

// reta de ponto a ponto
export const straightPath = (pts = []) =>
  pts
    .map((p, i) => `${i ? 'L' : 'M'}${p[0].toFixed(1)},${p[1].toFixed(1)}`)
    .join(' ');
