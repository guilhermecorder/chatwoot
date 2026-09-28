import { trendOf, trendText } from '../trend';

describe('trend (linha de tendência, item 266)', () => {
  it('reta sobe quando a série sobe', () => {
    const t = trendOf([1, 2, 3, 4, 5]);
    expect(t.slope).toBeCloseTo(1);
    expect(t.y0).toBeCloseTo(1);
    expect(t.y1).toBeCloseTo(5);
    expect(t.pct).toBeCloseTo(33.33, 1);
  });

  it('ignora os baldes zerados (dias que ainda não chegaram)', () => {
    const t = trendOf([2, 4, 6, 0, 0]);
    expect(t.first).toBe(0);
    expect(t.last).toBe(2);
    expect(t.slope).toBeCloseTo(2);
  });

  it('precisa de 3 baldes com valor', () => {
    expect(trendOf([5, 0, 5])).toBeNull();
    expect(trendOf([])).toBeNull();
  });

  it('lê em palavras: subindo / caindo / estável', () => {
    expect(trendText([1, 2, 3, 4], 'day').text).toBe('subindo ~40% por dia');
    expect(trendText([4, 3, 2, 1], 'week').text).toBe('caindo ~40% por semana');
    expect(trendText([5, 5, 5, 5], 'month').text).toBe('estável por mês');
  });
});
