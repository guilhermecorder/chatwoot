// CEVICO (item 199, 22/09): "cara" para quem não tem foto — cada pessoa ganha
// um degradê alegre FIXO (sorteado pelo nome), o mesmo na lista, no cabeçalho
// da conversa e na ficha do painel. Só aparece quando não há foto; a foto
// real (Instagram, upload) sempre fica por cima. Pares "dopamina", sem navy
// e sem dourado (o azul royal é do botão principal, o verde é do WhatsApp).
export const PERSON_GRADIENTS = [
  ['#2563eb', '#22d3ee'], // azul → ciano
  ['#7c3aed', '#f472b6'], // violeta → rosa
  ['#db2777', '#fb923c'], // rosa → laranja
  ['#f97316', '#facc15'], // laranja → amarelo
  ['#059669', '#6ee7b7'], // verde → menta
  ['#4338ca', '#60a5fa'], // índigo → azul
  ['#e11d48', '#fb7185'], // coral → rosa
  ['#0f766e', '#34d399'], // teal → verde
];

// hash estável do nome inteiro (não só do tamanho): "Carlos" ≠ "Marcos"
const hashName = name => {
  const s = String(name || '')
    .trim()
    .toLowerCase();
  let h = 5381;
  for (let i = 0; i < s.length; i += 1) {
    h = (h * 33 + s.charCodeAt(i)) % 4294967296;
  }
  return h;
};

export const personGradientPair = name =>
  PERSON_GRADIENTS[hashName(name) % PERSON_GRADIENTS.length];

export const personGradient = name => {
  const [from, to] = personGradientPair(name);
  return `linear-gradient(135deg, ${from}, ${to})`;
};
