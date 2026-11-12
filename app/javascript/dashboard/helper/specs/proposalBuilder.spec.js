import {
  parseMoney,
  billTotal,
  kwhFromBill,
  bestOption,
  optionDetail,
  quotesFor,
  quotesAverage,
  prefillFromSummary,
  roofFromText,
} from '../proposalBuilder';

const option = (extra = {}) => ({
  fornecedor: 'Bluesun',
  tipo: 'micro',
  preco: 7020.71,
  frete: 158.09,
  total: 7178.8,
  completa: true,
  falta: '',
  ...extra,
});

describe('proposalBuilder', () => {
  it('lê dinheiro digitado no formato brasileiro', () => {
    expect(parseMoney('1.234,56')).toBe(1234.56);
    expect(parseMoney('R$ 300')).toBe(300);
    expect(parseMoney('12880')).toBe(12880);
    expect(parseMoney(12.5)).toBe(12.5);
    expect(parseMoney('')).toBe(0);
    expect(parseMoney(null)).toBe(0);
  });

  it('soma a conta de hoje com o que vai ser acrescentado e passa para kWh', () => {
    const total = billTotal('300', [{ valor: '200' }, { valor: '' }]);
    expect(total).toBe(500);
    expect(kwhFromBill(total, 1.035)).toBe(483);
    expect(kwhFromBill(total, 0)).toBe(0);
  });

  it('escolhe a opção completa mais barata do tipo', () => {
    const options = [
      option({ total: 7500 }),
      option({ fornecedor: 'AVT', total: 7000, completa: false }),
      option({ total: 7178.8 }),
      option({ tipo: 'string', total: 6000 }),
    ];
    expect(bestOption(options, 'micro').total).toBe(7178.8);
    expect(bestOption(options, 'string').total).toBe(6000);
    expect(bestOption([options[1]], 'micro').fornecedor).toBe('AVT');
    expect(bestOption([], 'micro')).toBeNull();
  });

  it('descreve a cotação com o que ela tem e o que falta', () => {
    expect(optionDetail(option())).toMatch(
      /^kit R\$\s7\.020,71 \+ frete R\$\s158,09, com estrutura$/
    );
    expect(
      optionDetail(
        option({
          frete: null,
          completa: false,
          falta: 'estrutura do telhado e frete',
        })
      )
    ).toMatch(/^kit R\$\s7\.020,71, sem estrutura do telhado e frete$/);
  });

  it('monta as cotações: a escolhida, a dos outros fornecedores e as digitadas', () => {
    const averages = {
      micro: {
        cotacoes: [
          { fornecedor: 'Bluesun', valor: 7100, entra_na_media: true },
          {
            fornecedor: 'AVT',
            valor: 7011.82,
            detalhe: 'kit R$ 7.011,82, sem estrutura do telhado e frete',
            entra_na_media: false,
          },
        ],
      },
    };
    const quotes = quotesFor(averages, option(), [
      { fornecedor: ' Belenergy ', valor: '7.000,00' },
      { fornecedor: '', valor: '500' },
    ]);

    expect(quotes.map(q => [q.fornecedor, q.valor, q.entra_na_media])).toEqual([
      ['Bluesun', 7178.8, true],
      ['AVT', 7011.82, false],
      ['Belenergy', 7000, true],
    ]);
    expect(quotesAverage(quotes)).toBeCloseTo(7089.4, 2);
    expect(quotesFor(averages, null)).toEqual([]);
  });

  it('sem cotação completa, não há média', () => {
    const quotes = quotesFor({}, option({ completa: false, falta: 'frete' }));
    expect(quotesAverage(quotes)).toBeNull();
  });

  it('aproveita o resumo escrito do cliente para preencher a tela', () => {
    const summary = [
      { label: 'Conta de luz', value: 'R$ 300 por mês' },
      { label: 'Vai aumentar o consumo', value: 'vai pôr 2 ar-condicionados' },
      { label: 'Cidade', value: 'Piracicaba/SP' },
      { label: 'Telhado', value: 'metálico' },
    ];
    expect(prefillFromSummary(summary)).toEqual({
      hoje: 300,
      acrescimo: 'vai pôr 2 ar-condicionados',
      cidade: 'Piracicaba',
      telhado: 'metalica',
    });
    expect(prefillFromSummary([])).toEqual({
      hoje: 0,
      acrescimo: '',
      cidade: '',
      telhado: '',
    });
  });

  it('reconhece o tipo de telhado pelo jeito que o cliente falou', () => {
    expect(roofFromText('telha de barro')).toBe('ceramica');
    expect(roofFromText('Eternit')).toBe('fibrocimento_madeira');
    expect(roofFromText('telhado de zinco')).toBe('metalica');
    expect(roofFromText('laje')).toBe('laje');
    expect(roofFromText('não sei')).toBe('');
  });
});
