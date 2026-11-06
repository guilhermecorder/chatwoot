import { isRescheduled, rescheduledTitle } from '../cevicoAgenda';

// 🔁 item 368: consulta reagendada tem marca própria (azul-piscina), separada do tipo
describe('consulta reagendada', () => {
  it('marca só quem mudou de horário e não foi cancelada', () => {
    expect(isRescheduled({ rescheduled_count: 1 })).toBe(true);
    expect(isRescheduled({ rescheduled_count: 0 })).toBe(false);
    expect(isRescheduled({})).toBe(false);
    expect(isRescheduled({ rescheduled_count: 2, canceled_at: '2026-10-23T10:00:00Z' })).toBe(false);
  });

  it('o título conta quantas vezes', () => {
    expect(rescheduledTitle({ rescheduled_count: 1 })).toBe('Reagendada');
    expect(rescheduledTitle({ rescheduled_count: 3 })).toBe('Reagendada 3 vezes');
  });
});
