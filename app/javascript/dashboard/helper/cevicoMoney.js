// 💰 Rodada 6 (revisão do #260): a MESMA regra de dinheiro do servidor
// (Cevico::Money.parse, app/services/cevico/money.rb) para as telas que
// convertem o texto digitado em número antes de enviar.
// Antes, "5.000" virava 5 (parseFloat) e o lançamento saía como R$ 5,00.
//   - vírgula = centavos ("3900,5" → 3900.5; "5.000,00" → 5000);
//   - sem vírgula, ponto só é MILHAR em grupos de 3 dígitos
//     ("5.000" → 5000; "1.234.567" → 1234567);
//   - fora disso o ponto é decimal ("24187.8" → 24187.8);
//   - aceita "R$" e espaços; número de verdade passa direto;
//   - texto que não é dinheiro ("à combinar", "5,000") → null.
const MILHAR = /^[1-9]\d{0,2}(\.\d{3})+$/;
const INTEIRO = /^(\d+|[1-9]\d{0,2}(\.\d{3})+)$/;

const withComma = text => {
  const [inteiro, centavos, sobra] = text.split(',');
  if (sobra !== undefined || !/^\d{1,2}$/.test(centavos || '')) return null;
  if (!INTEIRO.test(inteiro)) return null;
  return parseFloat(`${inteiro.replace(/\./g, '')}.${centavos}`);
};

const toNumber = text => {
  if (text.includes(',')) return withComma(text);
  if (MILHAR.test(text)) return parseFloat(text.replace(/\./g, ''));
  if (/^\d+(\.\d+)?$/.test(text)) return parseFloat(text);
  return null;
};

const round2 = n => Math.round(n * 100) / 100;

export const parseMoneyBR = raw => {
  if (raw === null || raw === undefined) return null;
  if (typeof raw === 'number') return Number.isFinite(raw) ? round2(raw) : null;

  let text = String(raw)
    .replace(/\s/g, '')
    .replace(/^(-?)r?\$/i, '$1')
    .replace(/r?\$$/i, '');
  const negative = text.startsWith('-');
  if (negative) text = text.slice(1);
  if (!/^\d[\d.,]*$/.test(text)) return null;

  const n = toNumber(text);
  if (n === null || !Number.isFinite(n)) return null;
  return round2(negative ? -n : n);
};

export default parseMoneyBR;
