import { dueCountdown, stageDeadline } from '../taskDue';

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

describe('stageDeadline (⏳ prazo da coluna no cartão)', () => {
  const now = new Date(2026, 10, 12, 15, 0);

  it('verde com folga, amarelo em menos de 24 h, vermelho quando venceu', () => {
    expect(stageDeadline(new Date(2026, 10, 16, 9, 0).toISOString(), now)).toEqual({
      text: 'vence em 4 dias · 16/11',
      tone: 'later',
    });
    expect(stageDeadline(new Date(2026, 10, 13, 9, 0).toISOString(), now)).toEqual({
      text: 'vence amanhã 09:00',
      tone: 'soon',
    });
    expect(stageDeadline(new Date(2026, 10, 12, 9, 0).toISOString(), now)).toEqual({
      text: 'venceu às 09:00',
      tone: 'late',
    });
    expect(stageDeadline(new Date(2026, 10, 10, 9, 0).toISOString(), now)).toEqual({
      text: 'venceu há 2 dias',
      tone: 'late',
    });
  });

  it('coluna sem prazo não mostra nada', () => {
    expect(stageDeadline(null, now)).toBeNull();
  });
});
