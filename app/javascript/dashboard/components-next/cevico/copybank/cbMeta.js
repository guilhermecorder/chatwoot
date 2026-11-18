// 🪝 item 397: o que o Banco de Ganchos sabe sobre cada modelo (rótulos,
// ícones, explicação curta) + os filtros compartilhados entre o Banco e o
// ambiente de criação.

// tipos de gancho (as 7 categorias do PDF "1,000 Viral Hooks" + as da casa)
export const TIPOS = [
  {
    key: 'educativo',
    label: 'Educativo',
    icon: 'i-lucide-graduation-cap',
    color: '#2563eb',
    desc: 'Ensina algo rápido e útil',
  },
  {
    key: 'storytelling',
    label: 'Storytelling',
    icon: 'i-lucide-book-open-text',
    color: '#7c3aed',
    desc: 'Conta uma história pessoal',
  },
  {
    key: 'quebra_de_mito',
    label: 'Quebra de mito',
    icon: 'i-lucide-zap',
    color: '#d97706',
    desc: 'Derruba uma crença comum',
  },
  {
    key: 'autoridade',
    label: 'Autoridade',
    icon: 'i-lucide-badge-check',
    color: '#059669',
    desc: 'Mostra experiência e processo',
  },
  {
    key: 'comparacao',
    label: 'Comparação',
    icon: 'i-lucide-git-compare',
    color: '#0891b2',
    desc: 'Isto × aquilo, lado a lado',
  },
  {
    key: 'dia_na_vida',
    label: 'Dia na vida',
    icon: 'i-lucide-sun',
    color: '#ea580c',
    desc: 'Bastidores da rotina',
  },
  {
    key: 'aleatorio',
    label: 'Aleatório',
    icon: 'i-lucide-shuffle',
    color: '#db2777',
    desc: 'Curiosidades e surpresas',
  },
  {
    key: 'cevico',
    label: 'Da casa',
    icon: 'i-lucide-star',
    color: '#152c61',
    desc: 'Criados pela equipe CEVICO',
  },
];
export const TIPO = Object.fromEntries(TIPOS.map(t => [t.key, t]));

export const PECAS = [
  {
    key: 'gancho',
    label: 'Ganchos',
    icon: 'i-lucide-anchor',
    desc: 'A primeira frase: faz a pessoa parar de rolar',
  },
  {
    key: 'historia',
    label: 'Histórias',
    icon: 'i-lucide-book-open',
    desc: 'Estruturas para o corpo da copy',
  },
  {
    key: 'oferta',
    label: 'Ofertas (CTA)',
    icon: 'i-lucide-mouse-pointer-click',
    desc: 'O convite final',
  },
  {
    key: 'regancho',
    label: 'Reganchos',
    icon: 'i-lucide-repeat',
    desc: 'Frases que seguram a pessoa no meio da copy',
  },
];

export const SAUDE = {
  pronto: {
    label: 'Pronto p/ saúde',
    short: 'Pronto',
    cls: 'bg-[#05966922] text-[#059669]',
  },
  adaptar: {
    label: 'Adaptar (CFM)',
    short: 'Adaptar',
    cls: 'bg-[#D9770622] text-[#D97706]',
  },
  evitar: {
    label: 'Não combina',
    short: 'Não combina',
    cls: 'bg-[#DC262622] text-[#DC2626]',
  },
};

// filtro de saúde: "úteis" = pronto + adaptar (o padrão)
export const SAUDE_FILTROS = [
  { key: 'uteis', label: 'Úteis p/ saúde' },
  { key: 'pronto', label: 'Prontos' },
  { key: 'adaptar', label: 'Adaptar' },
  { key: 'evitar', label: 'Não combinam' },
  { key: 'todos', label: 'Todos' },
];
export const FONTES = [
  { key: 'todas', label: 'Toda origem' },
  { key: 'pbl-1000', label: 'Do PDF' },
  { key: 'casa', label: 'Da casa' },
];

export const filtrosPadrao = () => ({
  busca: '',
  saude: 'uteis',
  favoritos: false,
  comVideo: false,
  usados: false,
  fonte: 'todas',
});

export const norm = s =>
  String(s || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '');

export const passaFiltro = (b, f) => {
  if (f.saude === 'uteis' && b.saude === 'evitar') return false;
  if (!['uteis', 'todos'].includes(f.saude) && b.saude !== f.saude)
    return false;
  if (f.favoritos && !b.favorito) return false;
  if (f.comVideo && !b.referencia) return false;
  if (f.usados && !b.usos) return false;
  if (f.fonte === 'pbl-1000' && b.fonte !== 'pbl-1000') return false;
  if (f.fonte === 'casa' && b.fonte === 'pbl-1000') return false;
  const q = norm(f.busca).trim();
  return (
    !q ||
    norm(`${b.texto} ${b.original} ${b.exemplo} ${b.categoria}`).includes(q)
  );
};

export const filtroAtivo = (f, p = filtrosPadrao()) => {
  return Object.keys(p).some(k => f[k] !== p[k]);
};

// texto com as [lacunas] destacadas (sem v-html)
export const pieces = text =>
  String(text || '')
    .split(/(\[[^[\]]{1,60}\])/)
    .filter(Boolean)
    .map(t => ({ t, gap: /^\[.*\]$/.test(t) }));
