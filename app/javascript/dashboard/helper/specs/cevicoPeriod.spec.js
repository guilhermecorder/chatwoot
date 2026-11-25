import {
  PERIOD_PRESETS,
  periodPresetsWith,
  periodRangeFor,
  periodParams,
} from '../cevicoPeriod';

// item 321: a lista única de períodos do sistema
describe('cevicoPeriod', () => {
  const sat = new Date(2026, 9, 3, 15, 0); // sábado, 03/10/2026

  it('tem os 8 períodos na ordem combinada (Personalizado é o campo De/Até)', () => {
    expect(PERIOD_PRESETS.map(p => p.key)).toEqual([
      'today',
      'yesterday',
      'last7',
      'last_week',
      'month',
      'last_month',
      'last90',
      'year',
    ]);
  });

  it('calcula De/Até de cada período', () => {
    const r = key => periodRangeFor(key, sat);
    expect(r('today')).toEqual({ from: '2026-10-03', to: '2026-10-03' });
    expect(r('yesterday')).toEqual({ from: '2026-10-02', to: '2026-10-02' });
    expect(r('last7')).toEqual({ from: '2026-09-27', to: '2026-10-03' });
    expect(r('last_week')).toEqual({ from: '2026-09-21', to: '2026-09-27' });
    expect(r('month')).toEqual({ from: '2026-10-01', to: '2026-10-03' });
    expect(r('last_month')).toEqual({ from: '2026-09-01', to: '2026-09-30' });
    expect(r('last90')).toEqual({ from: '2026-07-06', to: '2026-10-03' });
    expect(r('year')).toEqual({ from: '2026-01-01', to: '2026-10-03' });
  });

  it('item 418: "Hoje + ontem" só entra na régua da tela que pede, logo depois de Ontem', () => {
    expect(periodPresetsWith().map(p => p.key)).toEqual(
      PERIOD_PRESETS.map(p => p.key)
    );
    const keys = periodPresetsWith(['last2']).map(p => p.key);
    expect(keys.slice(0, 4)).toEqual(['today', 'yesterday', 'last2', 'last7']);
    expect(keys).toHaveLength(9);
    expect(periodRangeFor('last2', sat)).toEqual({
      from: '2026-10-02',
      to: '2026-10-03',
    });
  });

  it('manda só o preset; De/Até apenas no Personalizado', () => {
    expect(periodParams({ preset: 'last90', from: 'a', to: 'b' })).toEqual({
      preset: 'last90',
    });
    expect(
      periodParams({ preset: 'custom', from: '2026-08-01', to: '2026-08-31' })
    ).toEqual({ preset: 'custom', from: '2026-08-01', to: '2026-08-31' });
  });
});
