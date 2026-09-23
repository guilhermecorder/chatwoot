// 🎨 CEVICO item 212 (23/09): a COR DE CADA PESSOA DA EQUIPE — a mesma na
// lista de conversas (crachá na foto + pílula do responsável), nos botões
// "Pessoa responsável" do painel e onde mais a pessoa aparecer.
// Regra igual à das caixas de entrada: a cor segue a ORDEM DE ENTRADA na
// equipe (id) — quem chega depois pega a próxima cor e ninguém muda de cor.
// A paleta começa por tons diferentes dos das caixas (violeta/ciano/rosa…)
// para não confundir "caixa" com "pessoa" à primeira vista; além disso a
// caixa aparece como NOME colorido e a pessoa como PÍLULA com foto.
export const PERSON_PALETTE = [
  { solid: '#7C3AED', grad: 'linear-gradient(135deg, #6D28D9, #A78BFA)' }, // violeta
  { solid: '#0891B2', grad: 'linear-gradient(135deg, #0E7490, #22D3EE)' }, // ciano
  { solid: '#DB2777', grad: 'linear-gradient(135deg, #BE185D, #F472B6)' }, // rosa
  { solid: '#D97706', grad: 'linear-gradient(135deg, #B45309, #FBBF24)' }, // âmbar
  { solid: '#059669', grad: 'linear-gradient(135deg, #047857, #34D399)' }, // esmeralda
  { solid: '#2563EB', grad: 'linear-gradient(135deg, #1D4ED8, #60A5FA)' }, // azul royal
  { solid: '#E11D48', grad: 'linear-gradient(135deg, #BE123C, #FB7185)' }, // coral
  { solid: '#0D9488', grad: 'linear-gradient(135deg, #0F766E, #2DD4BF)' }, // teal
  { solid: '#EA580C', grad: 'linear-gradient(135deg, #C2410C, #FB923C)' }, // laranja
  { solid: '#4F46E5', grad: 'linear-gradient(135deg, #4338CA, #818CF8)' }, // índigo
];

// Atendente IA / robôs (AgentBot): lilás "sistema" — a mesma cor do balão
// automático na conversa
export const BOT_COLOR = {
  solid: '#8B5CF6',
  grad: 'linear-gradient(135deg, #7C3AED, #C4B5FD)',
};

// sem responsável: cinza neutro — a cor só existe quando há alguém cuidando
export const UNASSIGNED_COLOR = {
  solid: '#8e8e93',
  grad: 'linear-gradient(135deg, #6e6e73, #aeaeb2)',
};

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

// cor escolhida pelo admin (#hex) → {solid, grad} no mesmo formato da paleta
const shade = (hex, f) => {
  const m = String(hex).replace('#', '');
  const c = [0, 2, 4].map(i =>
    Math.round(parseInt(m.slice(i, i + 2), 16) * (1 - f))
  );
  return `#${c.map(v => v.toString(16).padStart(2, '0')).join('')}`;
};
const lighten = (hex, f) => {
  const m = String(hex).replace('#', '');
  const c = [0, 2, 4].map(i => {
    const v = parseInt(m.slice(i, i + 2), 16);
    return Math.round(v + (255 - v) * f);
  });
  return `#${c.map(v => v.toString(16).padStart(2, '0')).join('')}`;
};
export const colorFromHex = hex => {
  const found = PERSON_PALETTE.find(
    c => c.solid.toLowerCase() === String(hex).toLowerCase()
  );
  if (found) return found;
  return {
    solid: hex,
    grad: `linear-gradient(135deg, ${shade(hex, 0.18)}, ${lighten(hex, 0.3)})`,
  };
};

// `agents` = lista do store (agents/getAgents); `overrides` = cores escolhidas
// pelo admin ({user_id: '#hex'}, Configurações → Painéis). Devolve
// {solid, grad}: a escolhida, senão a automática pelo id (ordem de entrada)
// ou, se a pessoa não estiver mais na equipe, por hash do nome.
export const personColorFor = (agents, idOrName, overrides = {}) => {
  const chosen = overrides && overrides[String(idOrName)];
  if (chosen && /^#[0-9a-f]{6}$/i.test(chosen)) return colorFromHex(chosen);
  const list = [...(agents || [])].sort((a, b) => a.id - b.id);
  const idx = list.findIndex(a => a.id === idOrName || a.name === idOrName);
  if (idx >= 0) return PERSON_PALETTE[idx % PERSON_PALETTE.length];
  return PERSON_PALETTE[hashName(idOrName) % PERSON_PALETTE.length];
};

export const personSolidFor = (agents, idOrName, overrides) =>
  personColorFor(agents, idOrName, overrides).solid;

// primeiro nome limpo ("Guilherme, da CEVICO" → "Guilherme")
export const firstNameOf = name =>
  String(name || '')
    .split(/[\s,]+/)
    .filter(Boolean)[0] || '';

export const initialOf = name => firstNameOf(name).slice(0, 1).toUpperCase();
