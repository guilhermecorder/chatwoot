import { evaluationLoad, spacedEvaluationSlots } from '../cevicoAgenda';

// 🩺 Agendamento Eficiente 1.0 (27/11): 4 avaliações por hora, uma a cada 15 min
const hm = s => {
  const [h, m] = s.split(':').map(Number);
  return h * 60 + m;
};
const caps = { hourlyCap: 4, quarterCap: 1 };

describe('evaluationLoad', () => {
  it('08:00, 08:15, 08:30, 08:45 = dentro da regra', () => {
    const others = ['08:00', '08:15', '08:30'].map(hm);
    const load = evaluationLoad({ others, at: hm('08:45'), ...caps });
    expect(load).toEqual({
      hour: 4,
      quarter: 1,
      overHour: false,
      overQuarter: false,
    });
  });

  it('duas avaliações no mesmo quarto de hora passam do combinado', () => {
    const load = evaluationLoad({
      others: [hm('08:00')],
      at: hm('08:10'),
      ...caps,
    });
    expect(load.overQuarter).toBe(true);
    expect(load.overHour).toBe(false);
  });

  it('no mesmo minuto, com o teto em 2, ainda cabe a segunda (e não a terceira)', () => {
    const one = evaluationLoad({
      others: [hm('08:00')],
      at: hm('08:00'),
      hourlyCap: 4,
      quarterCap: 2,
    });
    expect(one.overQuarter).toBe(false);
    const two = evaluationLoad({
      others: [hm('08:00'), hm('08:00')],
      at: hm('08:00'),
      hourlyCap: 4,
      quarterCap: 2,
    });
    expect(two.overQuarter).toBe(true);
  });

  it('a quinta avaliação da hora passa do teto', () => {
    const others = ['09:00', '09:15', '09:30', '09:45'].map(hm);
    expect(evaluationLoad({ others, at: hm('09:50'), ...caps }).overHour).toBe(
      true
    );
  });
});

describe('spacedEvaluationSlots', () => {
  it('sugere os horários mais perto que respeitam os 15 minutos', () => {
    const slots = [];
    for (let m = hm('08:00'); m < hm('10:00'); m += 10) slots.push(m);
    const others = [hm('08:00'), hm('08:20')];
    const got = spacedEvaluationSlots({
      slots,
      others,
      at: hm('08:00'),
      ...caps,
    });
    // 08:10 (quarto das 08:00) e 08:20/08:40? 08:20 tem avaliação; 08:30 e 08:40 estão no
    // quarto 08:30–08:44 (vazio) — os 3 mais perto: 08:30, 08:40, 08:50
    expect(got).toEqual(['08:30', '08:40', '08:50'].map(hm));
  });
});
