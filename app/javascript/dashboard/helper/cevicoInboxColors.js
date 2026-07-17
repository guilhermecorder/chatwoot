// CEVICO — cor oficial por caixa de entrada (pedido 16/07).
// Cada caixa ganha uma cor própria e ESTÁVEL: a posição na paleta segue a
// ordem de criação (id) — caixas novas entram no fim e NÃO mudam a cor das
// antigas. Usado nas pílulas de Conversas e no filtro do CRM. O dourado fica
// reservado para "Todas" (identidade CEVICO).
const INBOX_PALETTE = [
  { grad: 'linear-gradient(135deg, #1D4ED8, #3B82F6)', solid: '#1D4ED8' }, // azul royal
  { grad: 'linear-gradient(135deg, #059669, #34D399)', solid: '#059669' }, // esmeralda
  { grad: 'linear-gradient(135deg, #7C3AED, #A78BFA)', solid: '#7C3AED' }, // violeta
  { grad: 'linear-gradient(135deg, #DB2777, #F472B6)', solid: '#DB2777' }, // rosa
  { grad: 'linear-gradient(135deg, #0891B2, #22D3EE)', solid: '#0891B2' }, // ciano
  { grad: 'linear-gradient(135deg, #D97706, #FBBF24)', solid: '#D97706' }, // âmbar
  { grad: 'linear-gradient(135deg, #4338CA, #818CF8)', solid: '#4338CA' }, // índigo
  { grad: 'linear-gradient(135deg, #DC2626, #F87171)', solid: '#DC2626' }, // coral
];

// fallback p/ nomes que não estão mais no cadastro (histórico do CRM)
const hashName = name => {
  const s = String(name || '');
  let h = 0;
  for (let i = 0; i < s.length; i += 1) {
    h = (h * 31 + s.charCodeAt(i)) % 997;
  }
  return h;
};

// `inboxes` = lista do store (objetos com id e name). Devolve a cor da caixa
// pelo id (ordem de criação) ou, se o nome não existir mais, por hash do nome.
export const inboxColorFor = (inboxes, idOrName) => {
  const list = [...(inboxes || [])].sort((a, b) => a.id - b.id);
  const idx = list.findIndex(
    i => i.id === idOrName || i.name === idOrName
  );
  if (idx >= 0) return INBOX_PALETTE[idx % INBOX_PALETTE.length];
  return INBOX_PALETTE[hashName(idOrName) % INBOX_PALETTE.length];
};

export const inboxGradientFor = (inboxes, idOrName) =>
  inboxColorFor(inboxes, idOrName).grad;

export const inboxSolidFor = (inboxes, idOrName) =>
  inboxColorFor(inboxes, idOrName).solid;

// Gradiente dourado do "Todas" (mesmo das pílulas atuais)
export const ALL_INBOXES_GRADIENT = 'linear-gradient(135deg, #B8860B, #D4A017)';
