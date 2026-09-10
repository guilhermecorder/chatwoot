// PALETA DO HUB PESSOAL (rodada 16): azul royal + laranja brilhante em
// TODO o mundo Saúde (treino, corpo, dieta, dashboard, painel) — ele
// aprovou a paleta do Meu Painel (rodada 14) e pediu pra padronizar.
// Verde só pra "feito/progrediu" e vermelho só pra "regrediu/não foi".
export const ROYAL = '#4169E1'; // azul royal
export const ROYAL_PROFUNDO = '#27408B'; // subtom escuro
export const ROYAL_NOITE = '#111C3F'; // quase-preto azulado (fundos)
export const ROYAL_CLARO = '#8FA9F5'; // subtom claro
export const LARANJA = '#FF8A00'; // laranja brilhante
export const LARANJA_VIVO = '#FF6B1A'; // subtom quente
export const LARANJA_CLARO = '#FFB25E'; // subtom suave
export const LARANJA_ESCURO = '#B85C00'; // base dos gradientes laranja
export const VERMELHO = '#E5484D';
export const VERDE_OK = '#30A46C'; // só "feito no dia" / "progrediu"
export const CINZA = '#94A3B8';

export const GRAD_ROYAL = `linear-gradient(135deg, ${ROYAL_PROFUNDO}, ${ROYAL})`;
export const GRAD_NOITE = `linear-gradient(135deg, ${ROYAL_NOITE}, ${ROYAL_PROFUNDO} 65%, ${ROYAL})`;
export const GRAD_CLARO = `linear-gradient(135deg, ${ROYAL}, ${ROYAL_CLARO})`;
export const GRAD_LARANJA = `linear-gradient(135deg, ${LARANJA_VIVO}, ${LARANJA})`;
export const GRAD_LARANJA_ESCURO = `linear-gradient(135deg, ${LARANJA_ESCURO}, ${LARANJA})`;

// ▲▬▼ do placar (semântica fixa, fora da paleta)
export const VERDICT_COLORS = {
  progress: VERDE_OK,
  tie: CINZA,
  regress: VERMELHO,
};
