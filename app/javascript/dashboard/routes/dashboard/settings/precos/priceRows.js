// 🔢 Rodada 5 (#401): regras da Tabela de preços antes de salvar.
// - procedimento sem preço (vazio ou R$ 0) não sai da tela — virava "R$ 0"
//   no Atendente IA e no Espaço do Paciente;
// - promoção só vale se for maior que zero e menor que o preço normal;
// - toda linha diz a unidade do valor (por olho, dois olhos, por sessão ou
//   único). Lente fácica (Artisan) é SEMPRE por olho.
// O servidor repete as mesmas regras (Cevico::PriceList.sanitize_row).
// - Rodada 6: o preço é digitado como TEXTO e lido com a regra única de
//   dinheiro (cevicoMoney): "8.490" é R$ 8.490 — no campo numérico do
//   navegador virava 8,49.
import { parseMoneyBR } from 'dashboard/helper/cevicoMoney';

export const PRICE_UNITS = [
  { value: 'por_olho', label: 'por olho' },
  { value: 'dois_olhos', label: 'dois olhos' },
  { value: 'por_sessao', label: 'por sessão' },
  { value: 'unico', label: 'único' },
];

const UNIT_VALUES = PRICE_UNITS.map(u => u.value);
const PER_EYE_LOCK = /f[áa]cica|artisan/i;

export const isPerEyeLocked = row =>
  PER_EYE_LOCK.test(`${row?.group || ''} ${row?.name || ''}`);

// o texto do grupo já fala de uma unidade? (mesmas regras do servidor,
// Cevico::PriceList::UNIT_IN_GROUP)
const UNIT_IN_GROUP = {
  por_olho: /por olho/i,
  dois_olhos: /(2|dois|ambos os) olhos/i,
  por_sessao: /por sess[ãa]o/i,
  unico: /valor [úu]nico/i,
};

const unitLabel = value => PRICE_UNITS.find(u => u.value === value)?.label;

// grupo diz uma unidade e a linha escolheu OUTRA? devolve a do grupo (ou null)
export const groupUnitConflict = row => {
  const unit = isPerEyeLocked(row) ? 'por_olho' : row?.unit;
  const said = Object.keys(UNIT_IN_GROUP).filter(key =>
    UNIT_IN_GROUP[key].test(row?.group || '')
  );
  if (!said.length || said.includes(unit)) return null;
  return said[0];
};

const hasPromo = row =>
  row.promo_price !== null &&
  row.promo_price !== undefined &&
  row.promo_price !== '';

// o que falta numa linha (texto curto para a equipe) ou null se está ok
export const rowProblem = row => {
  if (!row?.name?.trim()) return null;
  const price = parseMoneyBR(row.price);
  if (!(price > 0)) return 'falta o preço';
  if (hasPromo(row)) {
    const promo = parseMoneyBR(row.promo_price);
    if (!(promo > 0 && promo < price)) {
      return 'promoção precisa ser maior que zero e menor que o preço';
    }
  }
  if (!isPerEyeLocked(row) && !UNIT_VALUES.includes(row.unit)) {
    return 'escolha a unidade';
  }
  // "Catarata (por olho)" + unidade "dois olhos" = IA lendo as duas coisas
  const other = groupUnitConflict(row);
  if (other) {
    const chosen = unitLabel(isPerEyeLocked(row) ? 'por_olho' : row.unit);
    return `o grupo diz "${unitLabel(other)}" e a unidade é "${chosen}" — deixe os dois iguais`;
  }
  return null;
};

// lista "Nome: problema" de todas as linhas com nome que não podem ser salvas
export const tableProblems = rows =>
  (rows || [])
    .map(row => ({ name: row.name?.trim(), problem: rowProblem(row) }))
    .filter(item => item.problem);

// linhas que vão para o servidor (sem as vazias; fácica sempre por olho)
export const rowsToSave = rows =>
  (rows || [])
    .filter(row => row.name?.trim())
    .map(row => ({
      ...row,
      price: parseMoneyBR(row.price),
      promo_price: hasPromo(row) ? parseMoneyBR(row.promo_price) : null,
      unit: isPerEyeLocked(row) ? 'por_olho' : row.unit,
    }));
