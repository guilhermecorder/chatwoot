import {
  normalizeCompare,
  compareParams,
  compareMonthOptions,
  variation,
  variationText,
} from '../cevicoComparison';

describe('cevicoComparison — base de comparação (item 394)', () => {
  it('normaliza o que veio salvo: modo inválido ou "outro mês" sem mês vira o padrão', () => {
    expect(normalizeCompare(null)).toEqual({ mode: 'previous', month: '' });
    expect(normalizeCompare({ mode: 'xyz' })).toEqual({
      mode: 'previous',
      month: '',
    });
    expect(normalizeCompare({ mode: 'pick', month: '' })).toEqual({
      mode: 'previous',
      month: '',
    });
    expect(normalizeCompare({ mode: 'month', month: '2026-08' })).toEqual({
      mode: 'month',
      month: '',
    });
    expect(normalizeCompare({ mode: 'pick', month: '2026-08' })).toEqual({
      mode: 'pick',
      month: '2026-08',
    });
  });

  it('sempre manda o modo para a API; o mês só no "outro mês"', () => {
    expect(compareParams({ mode: 'previous' })).toEqual({
      compare: 'previous',
      compare_month: undefined,
    });
    expect(compareParams({ mode: 'pick', month: '2026-08' })).toEqual({
      compare: 'pick',
      compare_month: '2026-08',
    });
  });

  it('lista os meses fechados do mais recente ao mais antigo, virando o ano', () => {
    const meses = compareMonthOptions(3, new Date(2026, 1, 15));
    expect(meses).toEqual([
      { value: '2026-01', label: 'janeiro/26' },
      { value: '2025-12', label: 'dezembro/25' },
      { value: '2025-11', label: 'novembro/25' },
    ]);
  });

  it('variação: subiu, caiu, igual, novo e sem base', () => {
    expect(variation(56, 50)).toMatchObject({
      estado: 'bom',
      seta: '▲',
      curto: '+12%',
    });
    expect(variation(45, 50)).toMatchObject({
      estado: 'atencao',
      seta: '▼',
      curto: '-10%',
    });
    expect(variation(50, 50).curto).toBe('igual');
    expect(variation(0, 0).curto).toBe('igual');
    expect(variation(4, 0)).toMatchObject({ estado: 'bom', curto: 'novo' });
    expect(variation(4, null).curto).toBe('—');
  });

  it('variação: quando cair é bom (faltas) e taxas em pontos', () => {
    expect(variation(3, 6, { bomQuandoSobe: false })).toMatchObject({
      estado: 'bom',
      seta: '▼',
      curto: '-50%',
    });
    expect(variation(42.5, 40, { pontos: true })).toMatchObject({
      estado: 'bom',
      curto: '+2,5 pts',
    });
  });

  it('frase da comparação leva o nome da base', () => {
    expect(variationText(56, 50, 'setembro')).toEqual({
      texto: '+12% vs setembro (50)',
      estado: 'bom',
      seta: '▲',
    });
    expect(variationText(3, 6, 'ontem', { bomQuandoSobe: false })).toEqual({
      texto: '-50% vs ontem (6)',
      estado: 'bom',
      seta: '▼',
    });
    expect(variationText(50, 50, 'ontem')).toEqual({
      texto: 'igual: ontem também teve 50',
      estado: 'neutro',
    });
    expect(variationText(0, 0, 'ontem')).toEqual({
      texto: 'sem movimento · ontem: 0',
      estado: 'neutro',
    });
    expect(variationText(4, 0, 'ontem')).toEqual({
      texto: 'ontem: 0',
      estado: 'neutro',
    });
    expect(variationText(4, undefined, 'ontem')).toBeNull();
  });
});
