import { bucketize, granularityOf, smoothPath } from '../cevicoBuckets';

describe('cevicoBuckets', () => {
  it('escolhe hora, dia ou semana pelo tamanho do período', () => {
    expect(granularityOf('2026-09-29T00:00:00', '2026-09-29T23:59:59')).toBe(
      'hour'
    );
    expect(granularityOf('2026-09-01T00:00:00', '2026-09-29T23:59:59')).toBe(
      'day'
    );
    expect(granularityOf('2026-01-01T00:00:00', '2026-09-29T23:59:59')).toBe(
      'week'
    );
  });

  it('conta cada item no balde e na série certos', () => {
    const items = [
      { at: '2026-09-02T10:00:00', k: 'google' },
      { at: '2026-09-02T18:00:00', k: 'google' },
      { at: '2026-09-04T09:00:00', k: 'instagram' },
      { at: '2026-08-20T09:00:00', k: 'fora' },
    ];
    const out = bucketize(
      items,
      '2026-09-01T00:00:00',
      '2026-09-05T23:59:59',
      i => i.at,
      i => i.k
    );
    expect(out.granularity).toBe('day');
    expect(out.labels).toEqual(['01/09', '02/09', '03/09', '04/09', '05/09']);
    expect(out.series.google).toEqual([0, 2, 0, 0, 0]);
    expect(out.series.instagram).toEqual([0, 0, 0, 1, 0]);
    expect(out.series.fora).toBeUndefined();
    expect(out.total).toEqual([0, 2, 0, 1, 0]);
  });

  it('a curva suave nunca desce abaixo da base entre dois zeros', () => {
    const d = smoothPath([
      [0, 100],
      [50, 100],
      [100, 20],
      [150, 100],
    ]);
    const ys = [...d.matchAll(/,(-?\d+\.\d)/g)].map(m => Number(m[1]));
    expect(Math.max(...ys)).toBeLessThanOrEqual(100);
  });
});
