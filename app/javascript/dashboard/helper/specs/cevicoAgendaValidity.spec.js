import {
  isSoloWindow,
  windowAt,
  windowInForce,
  windowOnDay,
} from '../cevicoAgenda';

// 🗓️ item 415 (24/11): terça da Dra. Roberta — grade antiga até 21/12,
// grade nova (14h, sem encaixe) a partir de 22/12
const roberta = 'Dra. Roberta Negri';
const OLD = {
  dow: 2,
  unit: 'paulista',
  doctor: roberta,
  start: '13:00',
  end: '16:30',
  block: 15,
  until: '2026-12-21',
};
const NEW = {
  dow: 2,
  unit: 'paulista',
  doctor: roberta,
  start: '14:00',
  end: '16:30',
  block: 15,
  from: '2026-12-22',
  solo: true,
};
const day = key => new Date(`${key}T12:00:00`);

describe('vigência da faixa (item 415)', () => {
  it('a faixa antiga vale até a véspera e a nova a partir da data', () => {
    expect(windowOnDay(OLD, day('2026-12-15'))).toBe(true);
    expect(windowOnDay(NEW, day('2026-12-15'))).toBe(false);
    expect(windowOnDay(OLD, day('2026-12-22'))).toBe(false);
    expect(windowOnDay(NEW, day('2026-12-22'))).toBe(true);
    expect(windowOnDay(NEW, day('2027-01-05'))).toBe(true);
  });

  it('sem from/until a faixa vale sempre', () => {
    const always = { ...OLD, until: undefined };
    expect(windowInForce(always, '2030-01-01')).toBe(true);
    expect(windowOnDay(always, day('2027-03-02'))).toBe(true);
  });

  it('windowAt com data respeita a vigência; sem data, só o dia da semana', () => {
    const wins = [OLD, NEW];
    const spot = { dow: 2, unit: 'paulista', minutes: 13 * 60 };
    expect(windowAt(wins, { ...spot, date: '2026-12-15' })).toBe(OLD);
    expect(windowAt(wins, { ...spot, date: '2026-12-22' })).toBeUndefined();
    expect(
      windowAt(wins, { ...spot, minutes: 14 * 60, date: '2026-12-22' })
    ).toBe(NEW);
    expect(windowAt(wins, spot)).toBe(OLD);
  });

  it('sem encaixe só quando marcado', () => {
    expect(isSoloWindow(NEW)).toBe(true);
    expect(isSoloWindow(OLD)).toBe(false);
    expect(isSoloWindow(undefined)).toBe(false);
  });
});
