// 🔢 Rodada 5 (#401): Tabela de preços não salva R$ 0, promoção estranha
// nem linha sem unidade.
import {
  rowProblem,
  tableProblems,
  rowsToSave,
  isPerEyeLocked,
  groupUnitConflict,
} from '../priceRows';

describe('Tabela de preços — regras antes de salvar', () => {
  it('linha só com o nome (cenário do achado) não pode ser salva', () => {
    const rows = [{ group: 'Exames', name: 'Topografia', price: null }];
    expect(tableProblems(rows)).toEqual([
      { name: 'Topografia', problem: 'falta o preço' },
    ]);
  });

  it('preço R$ 0 também é recusado', () => {
    expect(rowProblem({ name: 'X', price: 0, unit: 'unico' })).toBe(
      'falta o preço'
    );
  });

  it('promoção só vale se 0 < promoção < preço', () => {
    const base = { name: 'Trifocal', price: 8490, unit: 'por_olho' };
    expect(rowProblem({ ...base, promo_price: 0 })).toMatch('promoção');
    expect(rowProblem({ ...base, promo_price: 9000 })).toMatch('promoção');
    expect(rowProblem({ ...base, promo_price: 7990 })).toBeNull();
    expect(rowProblem({ ...base, promo_price: '' })).toBeNull();
  });

  it('exige a unidade, menos na lente fácica (sempre por olho)', () => {
    expect(rowProblem({ name: 'Trifocal', price: 8490, unit: '' })).toBe(
      'escolha a unidade'
    );
    expect(isPerEyeLocked({ group: 'Lentes', name: 'Artisan' })).toBe(true);
    expect(rowProblem({ name: 'Artisan', price: 11900, unit: '' })).toBeNull();
  });

  it('avisa quando o grupo diz uma unidade e a linha escolheu outra', () => {
    const row = {
      group: 'Catarata (por olho)',
      name: 'Trifocal',
      price: 8490,
      unit: 'dois_olhos',
    };
    expect(groupUnitConflict(row)).toBe('por_olho');
    expect(rowProblem(row)).toMatch('o grupo diz "por olho"');
    expect(rowProblem({ ...row, unit: 'por_olho' })).toBeNull();
    expect(rowProblem({ ...row, group: 'Catarata' })).toBeNull();
    // fácica é sempre por olho: grupo "(2 olhos)" precisa ser corrigido
    expect(
      rowProblem({ group: 'Fácica (2 olhos)', name: 'Artisan', price: 11900 })
    ).toMatch('o grupo diz "dois olhos"');
  });

  it('linha sem nome é ignorada e fácica sai como por olho', () => {
    const out = rowsToSave([
      { name: ' ', price: null },
      { name: 'Artisan', price: '11900', promo_price: '', unit: 'dois_olhos' },
    ]);
    expect(out).toEqual([
      { name: 'Artisan', price: 11900, promo_price: null, unit: 'por_olho' },
    ]);
  });

  // Rodada 6: o campo virou texto; "8.490" é R$ 8.490 (no campo numérico do
  // navegador virava 8,49), igual ao Cevico::PriceList.sanitize_row
  it('lê o preço digitado com a regra brasileira de dinheiro', () => {
    const row = {
      name: 'Trifocal',
      price: '8.490',
      promo_price: '7.990,00',
      unit: 'por_olho',
    };
    expect(rowProblem(row)).toBeNull();
    expect(rowsToSave([row])[0]).toMatchObject({
      price: 8490,
      promo_price: 7990,
    });
    expect(rowProblem({ ...row, price: 'à combinar' })).toBe('falta o preço');
  });
});
