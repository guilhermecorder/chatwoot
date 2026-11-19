import {
  bucketCost,
  cumulativeCost,
  lineSegments,
  straightPath,
} from '../cevicoLines';

describe('cevicoLines', () => {
  const spend = [100, 50, 50, 0, 100];
  const count = [0, 2, 0, 0, 3];

  it('custo de cada balde: sem resultado não tem custo', () => {
    expect(bucketCost(spend, count).map(p => p.cost)).toEqual([
      null,
      25,
      null,
      null,
      100 / 3,
    ]);
  });

  it('custo acumulado: não quebra depois do 1º resultado e fecha no custo do período', () => {
    const acc = cumulativeCost(spend, count);
    expect(acc.map(p => p.cost)).toEqual([null, 75, 100, 100, 60]);
    expect(acc[4]).toEqual({ spend: 300, count: 5, cost: 60 });
  });

  it('acumulado sem gasto ou sem resultado fica sem número', () => {
    expect(cumulativeCost([0, 0], [1, 2]).map(p => p.cost)).toEqual([
      null,
      null,
    ]);
    expect(cumulativeCost([10, 10], [0, 0]).map(p => p.cost)).toEqual([
      null,
      null,
    ]);
  });

  it('trechos: ponte só sobre buraco do meio, ponto sozinho à parte', () => {
    const a = [0, 0];
    const b = [1, 1];
    const c = [3, 3];
    const d = [5, 5];
    const out = lineSegments([null, a, b, null, c, null, d, null]);
    expect(out.runs).toEqual([[a, b]]);
    expect(out.bridges).toEqual([
      [b, c],
      [c, d],
    ]);
    expect(out.singles).toEqual([c, d]);
  });

  it('linha inteira sem buraco não tem ponte', () => {
    const pts = [
      [0, 0],
      [1, 2],
      [2, 1],
    ];
    expect(lineSegments(pts)).toEqual({
      runs: [pts],
      bridges: [],
      singles: [],
    });
    expect(straightPath(pts)).toBe('M0.0,0.0 L1.0,2.0 L2.0,1.0');
  });
});
