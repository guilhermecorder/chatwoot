// 📄 Gerador de proposta (LIFE, 11/11/2026): as contas da tela que não dependem do
// servidor — dinheiro digitado, conta de luz → consumo, e a lista de cotações que
// entra no preço médio do kit. O preço e o DRE são sempre calculados no servidor.

// "1.234,56" → 1234.56 · "300" → 300 · 12.5 → 12.5 · vazio → 0
export const parseMoney = value => {
  if (typeof value === 'number') return Number.isFinite(value) ? value : 0;
  const text = String(value ?? '').replace(/[^\d.,-]/g, '');
  if (!text) return 0;
  const normalized = text.includes(',')
    ? text.replace(/\./g, '').replace(',', '.')
    : text;
  const number = Number(normalized);
  return Number.isFinite(number) ? number : 0;
};

export const formatMoney = value =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(
    value || 0
  );

// conta de hoje + o que vai ser acrescentado (ex.: 2 ares-condicionados)
export const billTotal = (today, additions = []) =>
  parseMoney(today) +
  additions.reduce((sum, item) => sum + parseMoney(item.valor), 0);

// R$ por mês → kWh por mês, pela tarifa (R$ por kWh)
export const kwhFromBill = (total, tariff) =>
  tariff > 0 ? Math.round(total / tariff) : 0;

// a opção completa (kit + estrutura + frete) mais barata de um tipo; sem completa, a mais barata
export const bestOption = (options, type) => {
  const ofType = (options || []).filter(o => o.tipo === type);
  const complete = ofType.filter(o => o.completa);
  const pool = complete.length ? complete : ofType;
  return pool.reduce(
    (best, o) => (!best || o.total < best.total ? o : best),
    null
  );
};

// "kit R$ 7.020,71 + frete R$ 158,09, com estrutura"
export const optionDetail = option => {
  let text = `kit ${formatMoney(option.preco)}`;
  if (option.frete !== null && option.frete !== undefined) {
    text += ` + frete ${formatMoney(option.frete)}`;
  }
  return option.completa
    ? `${text}, com estrutura`
    : `${text}, sem ${option.falta}`;
};

// As cotações do tipo escolhido: a opção escolhida vale pelo fornecedor dela; dos outros
// fornecedores entra a cotação que o servidor separou (a completa mais barata); e as
// cotações digitadas na mão (Belenergy, Cordeiro…) entram como completas.
// Devolve [{ fornecedor, valor, detalhe, entra_na_media, manual }]
export const quotesFor = (averages, option, manual = []) => {
  if (!option) return [];
  const chosen = {
    fornecedor: option.fornecedor,
    valor: option.total,
    detalhe: optionDetail(option),
    entra_na_media: !!option.completa,
  };
  const others = (averages?.[option.tipo]?.cotacoes || [])
    .filter(q => q.fornecedor !== option.fornecedor)
    .map(q => ({
      fornecedor: q.fornecedor,
      valor: q.valor,
      detalhe: q.detalhe,
      entra_na_media: !!q.entra_na_media,
    }));
  const typed = manual
    .filter(m => String(m.fornecedor || '').trim() && parseMoney(m.valor) > 0)
    .map(m => ({
      fornecedor: String(m.fornecedor).trim(),
      valor: parseMoney(m.valor),
      detalhe: 'cotação informada na mão (kit + estrutura + frete)',
      entra_na_media: true,
      manual: true,
    }));
  return [chosen, ...others, ...typed];
};

// média das cotações que entram (nil quando nenhuma entra)
export const quotesAverage = quotes => {
  const inside = quotes.filter(q => q.entra_na_media);
  if (!inside.length) return null;
  return inside.reduce((sum, q) => sum + q.valor, 0) / inside.length;
};

// "telhado metálico" / "telha de barro" / "eternit" → a chave do telhado na tela
const ROOF_WORDS = [
  ['laje', /laje/i],
  ['metalica', /met[aá]l|zinco|galvan|sandu[ií]che/i],
  ['fibrocimento_madeira', /fibro|eternit|brasilit|amianto/i],
  ['ceramica', /cer[aâ]m|barro|colonial|romana|americana|portuguesa/i],
];
export const roofFromText = text => {
  const found = ROOF_WORDS.find(([, pattern]) => pattern.test(String(text)));
  return found ? found[0] : '';
};

// Do resumo escrito do cliente ("Conta de luz: R$ 300 por mês") para os campos da tela.
// Só preenche o que dá para ler com segurança; o resto fica para quem está gerando.
export const prefillFromSummary = (summary = []) => {
  const find = pattern =>
    summary.find(line => pattern.test(String(line.label || '')))?.value || '';
  const bill = find(/conta de luz/i).match(/R\$\s*([\d.]+(?:,\d{1,2})?)/);
  const city = find(/^cidade$/i)
    .split(/[/,-]/)[0]
    .trim();
  return {
    hoje: bill ? parseMoney(bill[1]) : 0,
    acrescimo: find(/aumentar/i).trim(),
    cidade: city,
    telhado: roofFromText(find(/telhado/i)),
  };
};
