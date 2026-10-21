import { parseMoneyBR } from '../cevicoMoney';

// Rodada 6: mesma tabela de valores do spec do servidor
// (spec/services/cevico/money_spec.rb) — tela e servidor leem igual
describe('parseMoneyBR', () => {
  it.each([
    ['5.000', 5000],
    ['12.500', 12500],
    ['1.234.567', 1234567],
    ['5.000,00', 5000],
    ['3900,5', 3900.5],
    ['1.234,56', 1234.56],
    ['24187.8', 24187.8],
    ['3900', 3900],
    ['R$ 5.000', 5000],
    ['R$ 8.490,00', 8490],
    ['-1.500', -1500],
    [3900, 3900],
    [3900.555, 3900.56],
  ])('lê %p como %p', (raw, expected) => {
    expect(parseMoneyBR(raw)).toBe(expected);
  });

  it.each([['à combinar'], ['5,000'], ['1,2,3'], [''], [null], [undefined]])(
    'não inventa valor para %p',
    raw => {
      expect(parseMoneyBR(raw)).toBeNull();
    }
  );
});
