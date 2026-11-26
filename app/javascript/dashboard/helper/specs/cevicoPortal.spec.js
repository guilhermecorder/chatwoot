import {
  spParts,
  dueAtFor,
  dowOf,
  addDays,
  addMonths,
  monthEnd,
  monthGrid,
  slotsOfWindow,
  windowsOn,
  closedReason,
  dayPlan,
  appointmentStatus,
  maskPhone,
  windowsText,
} from '../cevicoPortal';
import { portalRedirect } from '../cevicoAccess';

// 🚪 item 420: as contas do portal de terceiros (sempre no fuso de São Paulo)
describe('cevicoPortal', () => {
  const windows = [
    { dow: 2, start: '13:00', end: '14:00', unit: 'paulista', block: 15 },
  ];
  const terca = '2026-12-01';

  it('datas e horários em São Paulo, seja qual for o fuso do computador', () => {
    expect(spParts('2026-12-01T16:15:00Z')).toEqual({
      date: terca,
      time: '13:15',
    });
    expect(spParts('2026-12-02T01:30:00Z')).toEqual({
      date: terca,
      time: '22:30',
    });
    expect(dueAtFor(terca, '13:15')).toBe('2026-12-01T13:15:00-03:00');
    expect(dowOf(terca)).toBe(2);
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01');
    expect(addMonths('2026-12-15', 1)).toBe('2027-01-01');
    expect(monthEnd('2026-02-10')).toBe('2026-02-28');
  });

  it('grade do mês: semanas de 7 casas, domingo primeiro', () => {
    const weeks = monthGrid(terca);
    expect(weeks.every(w => w.length === 7)).toBe(true);
    expect(weeks[0][2]).toBe('2026-12-01'); // 01/12/2026 é terça
    expect(weeks.flat().filter(Boolean)).toHaveLength(31);
  });

  it('horários da faixa e faixas do dia', () => {
    expect(slotsOfWindow(windows[0])).toEqual([
      '13:00',
      '13:15',
      '13:30',
      '13:45',
    ]);
    expect(windowsOn(windows, terca)).toHaveLength(1);
    expect(windowsOn(windows, '2026-12-02')).toHaveLength(0);
  });

  it('o que cada horário é para quem está no portal', () => {
    const plan = dayPlan({
      date: terca,
      windows,
      appointments: [
        { id: 1, name: 'João', due_at: '2026-12-01T16:15:00Z' },
        {
          id: 2,
          name: 'Cancelada',
          due_at: '2026-12-01T16:30:00Z',
          canceled_at: '2026-11-30T10:00:00Z',
        },
        { id: 3, name: 'Fora da faixa', due_at: '2026-12-01T18:00:00Z' },
      ],
      clinic: [
        { due_at: '2026-12-01T16:00:00Z', particular: false, name: null },
        { due_at: '2026-12-01T16:45:00Z', particular: true, name: 'Ana' },
      ],
      closed: [],
      now: { date: '2026-11-30', time: '12:00' },
    });
    expect(plan.groups[0].slots.map(s => s.state)).toEqual([
      'busy',
      'mine',
      'free',
      'private',
    ]);
    expect(plan.free).toBe(1);
    expect(plan.mine).toBe(2); // a da grade + a que ficou fora da faixa
    expect(plan.extras.map(a => a.id)).toEqual([3]);
    expect(plan.hasWindow).toBe(true);
  });

  it('dia fechado, cadeado de horário e horário que já passou', () => {
    const base = { date: terca, windows, appointments: [], clinic: [] };
    const fechado = dayPlan({
      ...base,
      closed: [{ date: terca, unit: null }],
      now: { date: '2026-11-30', time: '12:00' },
    });
    expect(fechado.closed).toBe(true);
    expect(fechado.free).toBe(0);
    expect(
      closedReason([{ date: terca, unit: 'tatuape' }], terca, 'paulista')
    ).toBe(null);
    expect(closedReason([{ all: true, reason: 'x' }], terca, 'paulista')).toBe(
      'x'
    );

    const cadeado = dayPlan({
      ...base,
      closed: [{ date: terca, time: '13:30', unit: 'paulista' }],
      now: { date: terca, time: '13:05' },
    });
    expect(cadeado.groups[0].slots.map(s => s.state)).toEqual([
      'past',
      'free',
      'locked',
      'free',
    ]);
  });

  it('situação da consulta em uma palavra', () => {
    const now = { date: terca, time: '12:00' };
    const at = '2026-12-01T16:15:00Z';
    expect(appointmentStatus({ due_at: at }, now).key).toBe('pending');
    expect(appointmentStatus({ due_at: at, confirmed_at: 'x' }, now).key).toBe(
      'confirmed'
    );
    expect(
      appointmentStatus({ due_at: at, attendance: 'missed' }, now).key
    ).toBe('missed');
    expect(appointmentStatus({ due_at: at, canceled_at: 'x' }, now).key).toBe(
      'canceled'
    );
    expect(
      appointmentStatus({ due_at: at }, { date: terca, time: '15:00' }).key
    ).toBe('unmarked');
  });

  it('telefone e resumo das faixas', () => {
    expect(maskPhone('11988887777')).toBe('(11) 98888-7777');
    expect(maskPhone('5511988887777')).toBe('(11) 98888-7777');
    expect(maskPhone('1133334444')).toBe('(11) 3333-4444');
    expect(windowsText(windows, () => 'Av. Paulista')).toEqual([
      'terça, 13:00 às 14:00 · Av. Paulista',
    ]);
  });
});

describe('portalRedirect', () => {
  const third = { id: 3, cevico_third_party: { kind: 'agenda_medico' } };
  const comum = { id: 3 };

  it('terceiro: tudo cai no portal', () => {
    expect(portalRedirect({ name: 'inicio_home' }, third)).toBe(
      'accounts/3/portal'
    );
    expect(portalRedirect({ name: 'agenda_board' }, third)).toBe(
      'accounts/3/portal'
    );
    expect(portalRedirect({ name: 'cevico_portal' }, third)).toBe('stay');
  });

  it('administrador marcado por engano não é desviado', () => {
    expect(portalRedirect({ name: 'inicio_home' }, third, true)).toBe(null);
  });

  it('quem não é terceiro só abre o portal para conferir (admin + as)', () => {
    expect(portalRedirect({ name: 'inicio_home' }, comum)).toBe(null);
    expect(
      portalRedirect({ name: 'cevico_portal', query: {} }, comum, true)
    ).toBe('accounts/3/dashboard');
    expect(
      portalRedirect({ name: 'cevico_portal', query: { as: '9' } }, comum, true)
    ).toBe('stay');
    expect(
      portalRedirect(
        { name: 'cevico_portal', query: { as: '9' } },
        comum,
        false
      )
    ).toBe('accounts/3/dashboard');
  });
});
