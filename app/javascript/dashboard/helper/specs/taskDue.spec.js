import { dueCountdown } from '../taskDue';

describe('dueCountdown (⏰ prazo das tarefas)', () => {
  const now = new Date(2026, 10, 8, 15, 0); // dom 08/11 15:00 (hora local)

  it('conta os dias até o prazo', () => {
    expect(
      dueCountdown(new Date(2026, 10, 11, 9, 0).toISOString(), now)
    ).toEqual({ text: 'em 3 dias · 11/11', tone: 'later' });
  });

  it('amanhã e hoje com a hora', () => {
    expect(
      dueCountdown(new Date(2026, 10, 9, 9, 0).toISOString(), now)
    ).toEqual({ text: 'amanhã 09:00', tone: 'soon' });
    expect(
      dueCountdown(new Date(2026, 10, 8, 18, 30).toISOString(), now)
    ).toEqual({ text: 'hoje 18:30', tone: 'soon' });
  });

  it('minutos quando falta menos de 1 hora', () => {
    expect(
      dueCountdown(new Date(2026, 10, 8, 15, 40).toISOString(), now)
    ).toEqual({ text: 'em 40 min', tone: 'soon' });
  });

  it('atrasada', () => {
    expect(
      dueCountdown(new Date(2026, 10, 8, 9, 0).toISOString(), now)
    ).toEqual({ text: 'atrasada desde 09:00', tone: 'late' });
    expect(
      dueCountdown(new Date(2026, 10, 6, 9, 0).toISOString(), now)
    ).toEqual({ text: 'atrasada há 2 dias', tone: 'late' });
  });

  it('sem data', () => {
    expect(dueCountdown(null, now)).toBeNull();
  });
});
