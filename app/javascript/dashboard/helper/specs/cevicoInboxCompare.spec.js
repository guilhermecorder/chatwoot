import {
  rate,
  funnelRates,
  confidence,
  confidenceText,
  bestIndex,
  humanMinutes,
} from '../cevicoInboxCompare';

describe('cevicoInboxCompare', () => {
  it('divide a parte pelo inteiro e nunca inventa 0% sem inteiro', () => {
    expect(rate(13, 52)).toBe(25);
    expect(rate(20, 329)).toBe(6.1);
    expect(rate(3, 0)).toBeNull();
  });

  it('calcula as taxas da turma, com o orçamento → consulta limitado a 100%', () => {
    const r = funnelRates({
      chegaram: 100,
      responderam: 60,
      orcamento: 40,
      agendaram: 10,
      compareceram: 5,
      indicacoes: 2,
      cirurgias: 1,
    });
    expect(r).toEqual({
      responderam: 60,
      orcamento: 40,
      agendaram: 10,
      orcamento_consulta: 25,
      compareceram: 50,
      indicacoes: 40,
      cirurgias: 1,
    });
    expect(
      funnelRates({ chegaram: 10, orcamento: 2, agendaram: 5 })
        .orcamento_consulta
    ).toBe(100);
    expect(funnelRates({ chegaram: 10 }).orcamento_consulta).toBeNull();
  });

  it('mede a confiança de uma caixa agendar mais que a outra', () => {
    expect(confidence(10, 0, 5, 100)).toBeNull();
    expect(confidence(10, 100, 10, 100)).toEqual({ chance: 50, z: 0 });
    const forte = confidence(20, 400, 60, 400);
    expect(forte.chance).toBeGreaterThan(99);
    const fraca = confidence(20, 329, 19, 276);
    expect(fraca.chance).toBeGreaterThan(50);
    expect(fraca.chance).toBeLessThan(95);
  });

  it('escreve a confiança sem jargão', () => {
    expect(confidenceText(null, 'A', 'B')).toContain('gente suficiente');
    expect(confidenceText({ chance: 99 }, 'A', 'B')).toContain(
      'B agenda mais que A'
    );
    expect(confidenceText({ chance: 2 }, 'A', 'B')).toContain(
      'A agenda mais que B'
    );
    expect(confidenceText({ chance: 55 }, 'A', 'B')).toContain(
      'Empate técnico'
    );
    expect(confidenceText({ chance: 80 }, 'A', 'B')).toContain(
      'B está na frente'
    );
  });

  it('marca a melhor caixa só quando há disputa de verdade', () => {
    expect(bestIndex([6.1, 6.9, null])).toBe(1);
    expect(bestIndex([15.43, 18.39], { lowerIsBetter: true })).toBe(0);
    expect(bestIndex([5, 5])).toBe(-1);
    expect(bestIndex([5, null])).toBe(-1);
  });

  it('escreve o tempo por extenso', () => {
    expect(humanMinutes(null)).toBe('—');
    expect(humanMinutes(0.4)).toBe('menos de 1 min');
    expect(humanMinutes(45)).toBe('45 min');
    expect(humanMinutes(130)).toBe('2 h 10 min');
    expect(humanMinutes(60 * 72)).toBe('3 dias');
  });
});
