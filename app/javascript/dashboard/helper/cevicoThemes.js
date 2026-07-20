// Temas CEVICO — "lugares maravilhosos que encantam a humanidade".
// Cada tema é uma pré-configuração de cores/gradientes aplicada aos
// ambientes (Agenda de Consultas/Cirurgias, Tarefas...). O admin escolhe
// o tema (salvo em agenda_config.theme) e as telas leem daqui.
//
// Papel de cada cor:
// - primary:  gradiente principal (título, botão Hoje, pílula ativa)
// - action:   gradiente do botão de ação (Nova consulta / Agendar cirurgia)
// - accent:   gradiente de apoio (KPIs, contadores)
// - pill:     gradiente das pílulas de visão/período ATIVAS
// - soft:     cor clara p/ fundos suaves (10-15% de opacidade por cima)
// - ring:     cor do anel/bordas de destaque
// - glass:    true = aplicar brilho vítreo (.cevico-glass)
// - surgeryGrad/surgeryText: paleta do TRILHO DE CIRURGIAS — a mesma cor
//   do tema "puxando para o branco" (pedido do Guilherme: diferença bem
//   evidente entre Consultas × Cirurgias), com texto na cor escura

export const CEVICO_THEMES = [
  {
    key: 'santorini',
    label: 'Santorini',
    emoji: '🇬🇷',
    desc: 'mar Egeu — azul cristalino, branco e cinza, clean e fluido',
    primary: 'linear-gradient(135deg, #0C4A6E 0%, #0284C7 55%, #7DD3FC 100%)',
    action: 'linear-gradient(135deg, #0284C7, #38BDF8)',
    accent: 'linear-gradient(135deg, #334155, #64748B)',
    pill: 'linear-gradient(135deg, #0369A1, #38BDF8)',
    soft: '#38BDF8',
    ring: '#38BDF8',
    glass: true,
    surgeryGrad: 'linear-gradient(135deg, #7DD3FC 0%, #E0F2FE 55%, #FFFFFF 100%)',
    surgeryText: '#075985',
    surgerySoft: 'linear-gradient(135deg, #38BDF8 0%, #BAE6FD 100%)',
    surgerySoftText: '#075985',
  },
  {
    key: 'flor_del_mar',
    label: 'Flor del Mar',
    emoji: '🌺',
    desc: 'buganvílias sobre o mar — fúcsia vibrante com azul profundo',
    primary: 'linear-gradient(135deg, #9D174D 0%, #EC4899 60%, #F9A8D4 100%)',
    action: 'linear-gradient(135deg, #DB2777, #F472B6)',
    accent: 'linear-gradient(135deg, #1D4ED8, #60A5FA)',
    pill: 'linear-gradient(135deg, #BE185D, #F472B6)',
    soft: '#F472B6',
    ring: '#F472B6',
    glass: true,
    surgeryGrad: 'linear-gradient(135deg, #F9A8D4 0%, #FCE7F3 55%, #FFFFFF 100%)',
    surgeryText: '#9D174D',
    surgerySoft: 'linear-gradient(135deg, #F472B6 0%, #FBCFE8 100%)',
    surgerySoftText: '#9D174D',
  },
  {
    key: 'flamingo',
    label: 'Flamingo',
    emoji: '🦩',
    desc: 'rosa-coral quente com areia dourada',
    primary: 'linear-gradient(135deg, #BE123C 0%, #FB7185 60%, #FECDD3 100%)',
    action: 'linear-gradient(135deg, #E11D48, #FB7185)',
    accent: 'linear-gradient(135deg, #D97706, #FBBF24)',
    pill: 'linear-gradient(135deg, #E11D48, #FDA4AF)',
    soft: '#FB7185',
    ring: '#FB7185',
    glass: false,
    surgeryGrad: 'linear-gradient(135deg, #FECDD3 0%, #FFF1F2 55%, #FFFFFF 100%)',
    surgeryText: '#BE123C',
    surgerySoft: 'linear-gradient(135deg, #FDA4AF 0%, #FECDD3 100%)',
    surgerySoftText: '#BE123C',
  },
  {
    key: 'caribe',
    label: 'Praia do Caribe',
    emoji: '🏝️',
    desc: 'água turquesa transparente e areia clara',
    primary: 'linear-gradient(135deg, #0F766E 0%, #14B8A6 55%, #99F6E4 100%)',
    action: 'linear-gradient(135deg, #0D9488, #2DD4BF)',
    accent: 'linear-gradient(135deg, #B45309, #F59E0B)',
    pill: 'linear-gradient(135deg, #0F766E, #2DD4BF)',
    soft: '#2DD4BF',
    ring: '#2DD4BF',
    glass: true,
    surgeryGrad: 'linear-gradient(135deg, #99F6E4 0%, #F0FDFA 55%, #FFFFFF 100%)',
    surgeryText: '#0F766E',
    surgerySoft: 'linear-gradient(135deg, #5EEAD4 0%, #CCFBF1 100%)',
    surgerySoftText: '#0F766E',
  },
  {
    key: 'aloe_vera',
    label: 'Aloe Vera',
    emoji: '🌿',
    desc: 'verde fresco e suculento, leve e natural',
    primary: 'linear-gradient(135deg, #166534 0%, #16A34A 55%, #86EFAC 100%)',
    action: 'linear-gradient(135deg, #15803D, #4ADE80)',
    accent: 'linear-gradient(135deg, #65A30D, #A3E635)',
    pill: 'linear-gradient(135deg, #15803D, #4ADE80)',
    soft: '#4ADE80',
    ring: '#4ADE80',
    glass: true,
    surgeryGrad: 'linear-gradient(135deg, #BBF7D0 0%, #F0FDF4 55%, #FFFFFF 100%)',
    surgeryText: '#166534',
    surgerySoft: 'linear-gradient(135deg, #86EFAC 0%, #DCFCE7 100%)',
    surgerySoftText: '#166534',
  },
];

// tema padrão = o visual atual do sistema (azul CEVICO → roxo)
export const DEFAULT_THEME = {
  key: 'cevico',
  label: 'CEVICO (padrão)',
  emoji: '👁️',
  desc: 'azul CEVICO com roxo — o visual original',
  primary: 'linear-gradient(135deg, #0F5FA6 0%, #7C3AED 100%)',
  // verde DOPAMINE oficial (o mesmo do Radar: #059669 → #4ADE80)
  action: 'linear-gradient(135deg, #059669, #4ADE80)',
  accent: 'linear-gradient(135deg, #B8860B, #D4A017)',
  pill: 'linear-gradient(135deg, #0F5FA6, #7C3AED)',
  soft: '#7C3AED',
  ring: '#7C3AED',
  glass: false,
  // padrão do trilho de cirurgias (pedido 18/07): DOPAMINE → esbranquiçado
  surgeryGrad: 'linear-gradient(135deg, #059669 0%, #A7F3D0 55%, #FFFFFF 100%)',
  surgeryText: '#065F46',
  // "Nesta semana" do trilho: mais claro que o tema, menos que o "hoje"
  surgerySoft: 'linear-gradient(135deg, #4ADE80 0%, #D1FAE5 100%)',
  surgerySoftText: '#065F46',
};

export const ALL_THEMES = [DEFAULT_THEME, ...CEVICO_THEMES];

// resolve o tema salvo nas settings (crm/getSettings → agenda_theme)
export const resolveTheme = settings => {
  const key = settings?.agenda_theme;
  return ALL_THEMES.find(t => t.key === key) || DEFAULT_THEME;
};
